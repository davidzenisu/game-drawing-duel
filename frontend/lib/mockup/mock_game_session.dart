import 'dart:math';

import 'package:flutter/foundation.dart' show visibleForTesting;

import '../game/game_session.dart';
import '../game/rules/content.dart';
import '../game/rules/daily_loop.dart';
import '../game/rules/gacha.dart';
import '../game/rules/models.dart';
import '../game/rules/setup_plan.dart';
import '../game/rules/themes.dart';
import '../game/rules/upgrades.dart';
import 'bot_artist.dart';

/// The mockup of the gameplay loop: everything happens in memory within a
/// single session and all other players are simulated locally.
class MockGameSession extends GameSession {
  /// [launchDate] fixes the calendar day of day 1, which sets the themes;
  /// by default it's the day the game launches.
  MockGameSession({int? seed, this.launchDate})
    : _random = Random(seed),
      _bots = BotArtist(seed ?? DateTime.now().microsecondsSinceEpoch),
      _gacha = GachaMachine(random: Random(seed));

  final DateTime? launchDate;
  DateTime _launchedOn = DateTime.now().toUtc();

  /// A few of the prompt hints the API keeps in its database, per theme:
  /// each a description and the premade title that comes with it.
  static const _hints = {
    DailyTheme.forest: [
      ('a challenger lost on the way to work', 'Druid of the Delayed 7:42'),
      ('a challenger who walks the dog at dawn', 'Ranger of the Dog Park'),
    ],
    DailyTheme.beach: [
      ('a challenger doing laps at the public pool', 'Lifeguard of the Kiddie Pool'),
      ('a challenger planning a holiday in spreadsheets', 'Towel Warlord of Sunbed Row'),
    ],
    DailyTheme.volcano: [
      ('a challenger who can take the heat in the sauna', 'Lord of the Top Sauna Bench'),
      ('a challenger who burns dinner every night', 'Smoke Alarm Summoner'),
    ],
    DailyTheme.snow: [
      ("a challenger who can't decide on an ice cream flavour", 'Brain-Freeze Champion'),
      ('a challenger scraping ice off the windshield', 'Windshield Scraper Knight'),
    ],
    DailyTheme.jungle: [
      ('a challenger who gets lost in the club', 'Explorer of the Sticky Floor'),
      ('a challenger ruling the dance floor', 'Dancer in the Dry-Ice Mist'),
    ],
    DailyTheme.space: [
      ('a challenger lost in a furniture store maze', 'Navigator of the Showroom Maze'),
      ('a challenger fixing their washing machine', 'Astronaut of the Endless Spin'),
    ],
    DailyTheme.castle: [
      ('a challenger who rules from the couch', 'The Nap Emperor'),
      ('a challenger hosting Sunday brunch', 'Baron of the Brunch Table'),
    ],
  };

  /// A few of the starter prompts the API keeps in its database, per setup
  /// prompt type.
  static const _setupHints = {
    SetupPrompt.basic: ['Them by day', 'Them on their way to work', 'Them at their favourite spot'],
    SetupPrompt.alter: ['Them by night', 'Them on holiday', 'Them as a kid'],
    SetupPrompt.knight: ["What they'd defend at all costs", 'Their loyal companion', 'Their sworn rival'],
    SetupPrompt.mage: ['Their hidden talent', 'The spell they wish they could cast', 'Their lucky charm'],
    SetupPrompt.rogue: ['Their guilty pleasure', "What they'd steal if no one was looking", 'Their worst habit'],
    SetupPrompt.hero: ['Their proudest moment', 'Their biggest win', 'The time they were brave'],
    SetupPrompt.legend: ["How they'll be remembered", 'Their statue in the town square', 'Them as the final boss'],
  };

  static const suggestedNames = ['Alex', 'Sam', 'Robin', 'Kim', 'Charlie', 'Jo', 'Mika', 'Toni', 'Lou', 'Nico'];

  final Random _random;
  final BotArtist _bots;
  GachaMachine _gacha;

  @override
  List<String> get suggestedPlayerNames => suggestedNames;

  @override
  GachaStatus get gachaStatus => _gacha.status;

  @override
  Set<String> get rateUp {
    final hero = _weeklyHero?.card;
    if (hero == null) return const {};
    return {
      hero.id,
      for (final card in _pool)
        if (card.rarity == Rarity.legend && card.subject == hero.subject) card.id,
    };
  }

  @override
  bool get isMockup => true;

  @override
  String? get signInProblem => null;

  /// The mockup's signup screen offers a pretend social login instead.
  @override
  String get suggestedFirstName => '';

  /// The mockup starts at the signup, there is nothing to sign in to.
  @override
  Future<void> signIn() async {}

  @override
  Future<void> signOut() => Future.error(UnsupportedError('The mockup has no account to sign out of.'));

  /// The mockup shows every intro once per session.
  final Set<String> _tutorialsSeen = {};

  @override
  Set<String> get tutorialsSeen => _tutorialsSeen;

  @override
  Future<void> markTutorialSeen(String key) async {
    if (_tutorialsSeen.add(key)) notifyListeners();
  }

  GamePhase _phase = GamePhase.signup;
  @override
  GamePhase get phase => _phase;

  Player? _you;
  @override
  Player get you => _you!;

  ServerSession? _server;
  @override
  ServerSession get server => _server!;

  List<DrawingAssignment> _assignments = const [];
  @override
  List<DrawingAssignment> get assignments => _assignments;
  final Map<String, CharacterCard> _setupDrawings = {};

  final List<CharacterCard> _pool = [];
  @override
  List<CharacterCard> get pool => List.unmodifiable(_pool);

  final Map<String, OwnedCard> _owned = {};

  int _tickets = 0;

  @override
  int get victoryStars => _victoryStars;
  int _victoryStars = 0;
  @override
  int get tickets => _tickets;

  int _day = 0;
  @override
  int get day => _day;
  DailyTheme _theme = DailyTheme.forest;
  @override
  DailyTheme get theme => _theme;

  // Signup ------------------------------------------------------------------

  @override
  Future<void> signUp(String firstName) async {
    _you = Player(id: 'you', name: firstName.trim(), isYou: true);
    _setPhase(GamePhase.server);
  }

  // Server creation / join ----------------------------------------------------

  /// Creates a server with a prepopulated roster; the creator is the admin.
  @override
  Future<void> createServer(List<String> otherNames, {bool isTest = false}) async {
    final players = [you, for (final (i, name) in otherNames.indexed) Player(id: 'p$i', name: name.trim())];
    _server = ServerSession(code: _newCode(), players: players, isAdmin: true, joined: {you.id}, isTest: isTest);
    _setPhase(GamePhase.lobby);
  }

  /// Looks up a (simulated) server by its 6-digit code and returns its roster
  /// so the joining player can claim a seat.
  @override
  Future<ServerSession> previewServer(String code) async {
    final rng = Random(int.parse(code));
    final names = [...suggestedNames]..shuffle(rng);
    final count = SetupPlan.minPlayers + rng.nextInt(SetupPlan.maxPlayers - SetupPlan.minPlayers + 1);
    final roster = [for (var i = 0; i < count; i++) Player(id: 'p$i', name: names[i])];
    // The admin usually knows your name already.
    final seat = 1 + rng.nextInt(count - 1);
    roster[seat] = Player(id: 'p$seat', name: you.name);
    // Everyone listed before your seat is assumed to have joined already.
    final joined = {for (final p in roster.take(seat)) p.id};
    return ServerSession(code: code, players: roster, isAdmin: false, joined: joined);
  }

  @override
  Future<void> joinServer(ServerSession server, Player seat) async {
    if (server.joined.contains(seat.id)) throw StateError('This seat is taken');
    _you = seat.copyWith(isYou: true);
    final players = [for (final p in server.players) p.id == seat.id ? you : p];
    _server = ServerSession(code: server.code, players: players, isAdmin: false, joined: {...server.joined, you.id});
    _setPhase(GamePhase.lobby);
  }

  @override
  Duration get refreshInterval => const Duration(milliseconds: 900);

  /// The simulated friends join one at a time; when you joined someone
  /// else's server, its simulated admin starts once everyone is there.
  /// During the setup, they finish their drawings one at a time.
  @override
  Future<void> refreshServer() async {
    if (_phase == GamePhase.setup) return _finishNextBot();
    if (_phase != GamePhase.lobby) return;
    final next = server.players.where((p) => !server.joined.contains(p.id)).firstOrNull;
    if (next != null) {
      server.joined.add(next.id);
      notifyListeners();
    }
    if (!server.isAdmin && server.everyoneJoined) await startSetup();
  }

  /// Nobody else cancels in the mockup.
  @override
  String? get serverNotice => null;

  /// Throws away the whole game, as on the API.
  @override
  Future<void> cancelServer() async {
    _server = null;
    _assignments = const [];
    _setupDrawings.clear();
    _pool.clear();
    _owned.clear();
    _tickets = 0;
    _victoryStars = 0;
    _day = 0;
    _theme = DailyTheme.forest;
    _gacha = GachaMachine(random: _random);
    _prompts.clear();
    _challengers.clear();
    _fights.clear();
    _boostStars.clear();
    _yourBoosts.clear();
    _fightOffsets.clear();
    _boostOffsets.clear();
    _finaleVotes.clear();
    _yourFinaleVotes.clear();
    _weeklyHero = null;
    _usedHints.clear();
    _botRosters.clear();
    _promptTheme = DailyTheme.forest;
    _promptHint = null;
    _promptToDraw = null;
    _fightChallenger = null;
    _incomingHurries = const [];
    _hurrySentTo = null;
    _setPhase(GamePhase.server);
  }

  String _newCode() => List.generate(6, (_) => _random.nextInt(10)).join();

  // Initial drawing setup -----------------------------------------------------

  @override
  Future<void> startSetup() async {
    _assignments = _assignmentsOf(you);
    _setPhase(GamePhase.setup);
  }

  /// The setup assignments of [artist], one of the [ServerSession.artists].
  List<DrawingAssignment> _assignmentsOf(Player artist) {
    final players = server.players;
    final index = players.indexWhere((p) => p.id == artist.id);
    final planned = server.isTest
        ? SetupPlan.testAssignmentsFor(players, index, _random)
        : SetupPlan.assignmentsFor(players, index);
    return [
      for (final a in planned)
        switch ([
          for (final h in _setupContent)
            if (h.prompt == a.prompt) h,
        ]) {
          final hints when hints.isNotEmpty => a.withHint(hints[_random.nextInt(hints.length)].text),
          _ => a,
        },
    ];
  }

  @override
  CharacterCard? setupDrawing(DrawingAssignment assignment) => _setupDrawings[assignment.id];

  @override
  Future<void> submitSetupDrawing(DrawingAssignment assignment, Sketch sketch, String title) async {
    _setupDrawings[assignment.id] = CharacterCard(
      id: assignment.id,
      subject: assignment.subject.name,
      title: title,
      rarity: assignment.prompt.rarity,
      prompt: assignment.prompt.label,
      artist: you.name,
      sketch: sketch,
    );
    notifyListeners();
  }

  void _finishNextBot() {
    final next = server.artists.where((p) => !p.isYou && !server.setupDone.contains(p.id)).firstOrNull;
    if (next == null) return;
    server.setupDone.add(next.id);
    notifyListeners();
  }

  /// Fills the pool with your drawings and everybody else's and starts day 1;
  /// the simulated friends finish their drawings right away.
  /// Every artist's setup drawings also land in their own roster.
  @override
  Future<void> launch() async {
    _launchedOn = (launchDate ?? DateTime.now()).toUtc();
    server.setupDone.addAll(server.artists.map((p) => p.id));
    for (final artist in server.artists) {
      if (artist.isYou) continue;
      final roster = _botRosters[artist.id] = [];
      for (final assignment in _assignmentsOf(artist)) {
        final card = CharacterCard(
          id: assignment.id,
          subject: assignment.subject.name,
          title: _bots.title(),
          rarity: assignment.prompt.rarity,
          prompt: assignment.prompt.label,
          artist: artist.name,
          sketch: _bots.doodle(assignment.prompt.label),
        );
        roster.add(card);
        _pool.add(card);
      }
    }
    _pool.addAll(_setupDrawings.values);
    for (final card in _setupDrawings.values) {
      _owned[card.id] = OwnedCard(card);
    }
    _tickets += GachaMachine.launchBonus;
    _startDay();
    _setPhase(GamePhase.daily);
  }

  // Daily routine ---------------------------------------------------------------

  /// Prompts per day, in roster order.
  final Map<int, List<ChallengerPrompt>> _prompts = {};

  /// Challengers drawn per day.
  final Map<int, List<CharacterCard>> _challengers = {};

  /// Fights set up per day.
  final Map<int, List<FightSetup>> _fights = {};

  /// Everyone's fights on [day].
  @visibleForTesting
  List<FightSetup> fightsOn(int day) => List.unmodifiable(_fights[day] ?? const <FightSetup>[]);

  /// The boost stars every challenger got, by its id.
  final Map<String, int> _boostStars = {};

  /// The boost stars you gave each day, by challenger id.
  final Map<int, Map<String, int>> _yourBoosts = {};

  /// Like online, everyone fights the challenger of the player a number of
  /// seats on, picked per day, so every challenger has one fight when all
  /// drew; and boosts the challengers of the players other offsets on.
  final Map<int, int> _fightOffsets = {};
  final Map<int, List<int>> _boostOffsets = {};

  /// Characters in the simulated players' rosters.
  final Map<String, List<CharacterCard>> _botRosters = {};

  /// The character you write today's prompt for.
  @override
  DailyTheme get promptTheme => _promptTheme;
  DailyTheme _promptTheme = DailyTheme.forest;

  @override
  String? get promptHint => _promptHint;
  String? _promptHint;

  @override
  ChallengerPrompt? get yourPrompt => _prompts[_day]?.where((p) => p.author.isYou).firstOrNull;

  /// The prompt you draw today, written by someone else yesterday.
  @override
  ChallengerPrompt? get promptToDraw => _promptToDraw;
  ChallengerPrompt? _promptToDraw;

  @override
  CharacterCard? get yourChallenger =>
      _challengers[_day]?.where((c) => c.artist == you.name && c.day == _day).firstOrNull;

  /// One randomly selected challenger from yesterday to pick fighters against.
  @override
  CharacterCard? get fightChallenger => _fightChallenger;
  CharacterCard? _fightChallenger;

  @override
  FightSetup? get yourFight => _fights[_day]?.where((f) => f.owner.isYou).firstOrNull;

  /// Like online: your characters that fought earlier this week, which
  /// starts on Monday.
  @override
  Set<String> get restingCharacterIds {
    final weekStart = _day - (_launchedOn.add(Duration(days: _day - 1)).weekday - DateTime.monday);
    return {
      for (var day = weekStart; day < _day; day++)
        for (final fight in _fights[day] ?? const <FightSetup>[])
          if (fight.owner.isYou)
            for (final fighter in fight.fighters)
              if (fighter.card.rarity != Rarity.basic) fighter.card.id,
    };
  }

  // Game content -----------------------------------------------------------------

  /// Like online, kept for the whole session: used from the day after it was
  /// added on, and retired ones until the end of the day they were retired.
  final List<_MockContent> _content = [
    for (final MapEntry(:key, :value) in _hints.entries)
      for (final (text, premadeTitle) in value)
        _MockContent(theme: key, text: text, premadeTitle: premadeTitle, addedOn: 0),
  ];
  int _nextContent = 1;

  /// The starter prompts in use, like online kept for the whole session:
  /// given out from the next setup on.
  final List<SetupHintEntry> _setupContent = [
    for (final MapEntry(:key, :value) in _setupHints.entries)
      for (final text in value)
        SetupHintEntry(id: 'setup-${key.name}-$text', prompt: key, text: text, createdAt: DateTime.now()),
  ];

  /// The ids of the hints the server gave out: every one is used once only.
  final Set<String> _usedHints = {};

  /// The hints of [theme] used on [day].
  List<_MockContent> _hintsOn(DailyTheme theme, int day) => [
    for (final c in _content)
      if (c.theme == theme && c.addedOn < day && (c.retiredOn == null || c.retiredOn! >= day)) c,
  ];

  /// The mockup has no accounts, so you can try the content screen.
  @override
  bool get canEditContent => true;

  @override
  Future<List<ContentEntry>> contentEntries(DailyTheme theme) async => [
    for (final c in _content)
      if (c.theme == theme && c.retiredOn == null) c.entry,
  ];

  @override
  Future<ContentAddResult> addContent(DailyTheme theme, List<HintDraft> hints) async {
    final drafts = [for (final h in hints) (h.text.trim(), h.premadeTitle.trim())];
    if (drafts.any((d) => d.$1.isEmpty || d.$2.isEmpty)) {
      throw ArgumentError("A description and its premade title can't be empty.");
    }
    if (drafts.any((d) => d.$2.length > CharacterCard.maxTitleLength)) {
      throw ArgumentError('A premade title has at most ${CharacterCard.maxTitleLength} characters.');
    }
    final known = {
      for (final c in _content)
        if (c.theme == theme && c.retiredOn == null) c.text.toLowerCase(),
    };
    final added = <ContentEntry>[];
    final skipped = <String>[];
    for (final (text, premadeTitle) in drafts) {
      if (!known.add(text.toLowerCase())) {
        skipped.add(text);
        continue;
      }
      final content = _MockContent(
        theme: theme,
        text: text,
        premadeTitle: premadeTitle,
        addedOn: _day,
        id: 'content-${_nextContent++}',
      );
      _content.add(content);
      added.add(content.entry);
    }
    return ContentAddResult(added: added, skipped: skipped);
  }

  @override
  Future<void> retireContent(ContentEntry entry) async {
    final content = _content.where((c) => c.entry.id == entry.id && c.retiredOn == null).firstOrNull;
    if (content == null) throw StateError('No such hint.');
    content.retiredOn = _day;
  }

  @override
  Future<List<SetupHintEntry>> setupHints(SetupPrompt prompt) async => [
    for (final h in _setupContent)
      if (h.prompt == prompt) h,
  ];

  @override
  Future<SetupHintAddResult> addSetupHints(SetupPrompt prompt, List<String> texts) async {
    final trimmed = [for (final t in texts) t.trim()];
    if (trimmed.any((t) => t.isEmpty)) throw ArgumentError("A starter prompt can't be empty.");
    final known = {
      for (final h in _setupContent)
        if (h.prompt == prompt) h.text.toLowerCase(),
    };
    final added = <SetupHintEntry>[];
    final skipped = <String>[];
    for (final text in trimmed) {
      if (!known.add(text.toLowerCase())) {
        skipped.add(text);
        continue;
      }
      final entry = SetupHintEntry(
        id: 'setup-${_nextContent++}',
        prompt: prompt,
        text: text,
        createdAt: DateTime.now(),
      );
      _setupContent.add(entry);
      added.add(entry);
    }
    return SetupHintAddResult(added: added, skipped: skipped);
  }

  @override
  Future<void> retireSetupHint(SetupHintEntry entry) async {
    if (!_setupContent.any((h) => h.id == entry.id)) throw StateError('No such starter prompt.');
    _setupContent.removeWhere((h) => h.id == entry.id);
  }

  int _fightOffset(int day) => _fightOffsets.putIfAbsent(day, () => 1 + _random.nextInt(server.players.length - 1));

  /// The challenger [player] fights on [day]: the one drawn two days before
  /// by the player [_fightOffset] seats on, or the next one on who drew.
  CharacterCard? _fightChallengerOf(Player player, int day) {
    final players = server.players;
    final drawn = _challengers[day - 2] ?? const <CharacterCard>[];
    if (players.length < 2 || drawn.isEmpty) return null;
    final position = players.indexOf(player);
    for (var step = 0; step < players.length; step++) {
      final other = players[(position + _fightOffset(day) + step) % players.length];
      if (other.id == player.id) continue;
      final challenger = drawn.where((c) => c.artist == other.name).firstOrNull;
      if (challenger != null) return challenger;
    }
    return null;
  }

  /// The challengers [player] may boost on [day], like online: up to
  /// [Boost.challengers] of the day before's, of the players the same
  /// offsets on for everyone, never their own or the one they fight
  /// tomorrow.
  List<CharacterCard> _boostTargetsOf(Player player, int day) {
    final players = server.players;
    final drawn = _challengers[day - 1] ?? const <CharacterCard>[];
    if (players.length < 2 || drawn.isEmpty) return const [];
    final offsets = _boostOffsets.putIfAbsent(day, () {
      final fightOffset = _fightOffset(day + 1);
      return [
        for (var offset = 1; offset < players.length; offset++)
          if (offset != fightOffset) offset,
      ]..shuffle(_random);
    });
    final fought = _fightChallengerOf(player, day + 1);
    final position = players.indexOf(player);
    final targets = <CharacterCard>[];
    for (final offset in offsets) {
      final artist = players[(position + offset) % players.length];
      final challenger = drawn.where((c) => c.artist == artist.name).firstOrNull;
      if (challenger == null || challenger.artist == player.name || challenger.id == fought?.id) continue;
      targets.add(challenger);
      if (targets.length == Boost.challengers) break;
    }
    return targets;
  }

  @override
  List<BoostTarget> get boostTargets => [
    for (final challenger in _boostTargetsOf(you, _day))
      BoostTarget(challenger: challenger, stars: _yourBoosts[_day]?[challenger.id] ?? 0),
  ];

  /// Step 3: gives today's challengers to boost these stars, replacing the
  /// ones you gave today.
  @override
  Future<void> setBoosts(Map<String, int> stars) async {
    final targets = {for (final challenger in _boostTargetsOf(you, _day)) challenger.id};
    if (targets.isEmpty) throw StateError('No challengers to boost today.');
    if (!targets.containsAll(stars.keys)) throw ArgumentError("You can't boost that challenger today.");
    if (stars.values.any((n) => n < 0 || n > Boost.maxPerChallenger)) {
      throw ArgumentError('A challenger takes up to ${Boost.maxPerChallenger} of your stars.');
    }
    if (stars.values.fold(0, (a, b) => a + b) > Boost.stars) {
      throw ArgumentError('You have ${Boost.stars} stars to give.');
    }
    _yourBoosts[_day] = {
      for (final MapEntry(key: id, value: n) in stars.entries)
        if (n > 0) id: n,
    };
    notifyListeners();
  }

  /// Adds [given] and [left] more stars spread at random to [targets]'
  /// boost stars, at most [Boost.maxPerChallenger] on one in all.
  void _spreadBoosts(List<CharacterCard> targets, Map<String, int> given) {
    final spread = {...given};
    var left = Boost.stars - given.values.fold(0, (a, b) => a + b);
    while (left > 0) {
      final open = targets.where((c) => (spread[c.id] ?? 0) < Boost.maxPerChallenger).toList();
      if (open.isEmpty) break;
      final pick = open[_random.nextInt(open.length)];
      spread[pick.id] = (spread[pick.id] ?? 0) + 1;
      left--;
    }
    for (final MapEntry(key: id, value: n) in spread.entries) {
      _boostStars[id] = (_boostStars[id] ?? 0) + n;
    }
  }

  // Step 5: the finale --------------------------------------------------------

  /// The votes of each finale, by its day: the votes each challenger got.
  final Map<int, Map<String, int>> _finaleVotes = {};

  /// The pairs you voted on in each finale, by its day, see [_pairKey].
  final Map<int, Set<String>> _yourFinaleVotes = {};

  WeeklyHero? _weeklyHero;

  @override
  WeeklyHero? get weeklyHero => _weeklyHero;

  bool _isFinaleDay(int day) => Finale.isFinaleDate(_launchedOn.add(Duration(days: day - 1)));

  /// Like online: the challengers that won a fight in the week that ends on
  /// [day], before that day, oldest first.
  List<_Contender> _contenders(int day) {
    final lastFightDay = day - Finale.fightsUntil;
    final byChallenger = <String, List<FightSetup>>{};
    for (var fightDay = lastFightDay - 6; fightDay <= lastFightDay; fightDay++) {
      for (final fight in _fights[fightDay] ?? const <FightSetup>[]) {
        byChallenger.putIfAbsent(fight.challenger.id, () => []).add(fight);
      }
    }
    return [
      for (final fights in byChallenger.values)
        if (fights.where((f) => !f.fightersWin).length case final wins when wins > 0)
          _Contender(fights.first.challenger, wins: wins, boostStars: fights.first.boostStars),
    ];
  }

  static String _pairKey(CharacterCard a, CharacterCard b) =>
      a.id.compareTo(b.id) < 0 ? '${a.id}|${b.id}' : '${b.id}|${a.id}';

  /// The pairs [artist] votes on in the finale on [day]: every pair of the
  /// contenders without one they drew, in an order and left/right of their own.
  List<(CharacterCard, CharacterCard)> _finalePairs(int day, String artist) {
    final theirs = [
      for (final contender in _contenders(day))
        if (contender.card.artist != artist) contender.card,
    ];
    final random = Random(Object.hash(day, artist));
    return [
      for (final (i, a) in theirs.indexed)
        for (final b in theirs.skip(i + 1)) random.nextBool() ? (a, b) : (b, a),
    ]..shuffle(random);
  }

  @override
  FinaleBallot? get finale {
    if (!_isFinaleDay(_day)) return null;
    final pairs = _finalePairs(_day, you.name);
    final voted = _yourFinaleVotes[_day] ?? const {};
    return FinaleBallot(
      pair: pairs.where((p) => !voted.contains(_pairKey(p.$1, p.$2))).firstOrNull,
      votes: voted.length,
      pairs: pairs.length,
      contenders: _contenders(_day).length,
    );
  }

  @override
  Future<void> voteFinale(CharacterCard chosen, CharacterCard other) async {
    if (!_isFinaleDay(_day)) throw StateError('The finale is on the last day of a week.');
    final key = _pairKey(chosen, other);
    if (!_finalePairs(_day, you.name).any((p) => _pairKey(p.$1, p.$2) == key)) {
      throw ArgumentError("You can't vote on that pair.");
    }
    if (!(_yourFinaleVotes[_day] ??= {}).add(key)) throw StateError('You voted on that pair already.');
    _vote(_day, chosen);
    notifyListeners();
  }

  void _vote(int day, CharacterCard chosen) {
    final votes = _finaleVotes[day] ??= {};
    votes[chosen.id] = (votes[chosen.id] ?? 0) + 1;
  }

  /// Once the finale on [day] is over: the simulated players vote at random,
  /// and the challenger with the most stars (then the most fights won, then
  /// the one drawn first) joins the pool as a hero.
  void _decideFinale(int day) {
    for (final voter in otherPlayers) {
      for (final (a, b) in _finalePairs(day, voter.name)) {
        _vote(day, _random.nextBool() ? a : b);
      }
    }
    final votes = _finaleVotes[day] ?? const {};
    int stars(_Contender c) => Stars.ofChallenger(c.boostStars) + (votes[c.card.id] ?? 0);
    final ranked = _contenders(day).indexed.toList()
      ..sort((x, y) {
        final byStars = stars(y.$2).compareTo(stars(x.$2));
        if (byStars != 0) return byStars;
        final byWins = y.$2.wins.compareTo(x.$2.wins);
        return byWins != 0 ? byWins : x.$1.compareTo(y.$1);
      });
    if (ranked.isEmpty) {
      _weeklyHero = null;
      return;
    }
    final winner = ranked.first.$2;
    if (!_pool.any((c) => c.id == winner.card.id)) _pool.add(winner.card);
    _weeklyHero = WeeklyHero(card: winner.card, day: day, stars: stars(winner), votes: votes[winner.card.id] ?? 0);
  }

  /// Yesterday's fights you picked the fighters for.
  @override
  List<FightSetup> get yourFightResults => [
    for (final fight in _fights[_day - 1] ?? const <FightSetup>[])
      if (fight.owner.isYou) fight,
  ];

  /// Yesterday's fights against the challenger you drew (three days ago).
  @override
  List<FightSetup> get yourChallengerResults => [
    for (final fight in _fights[_day - 1] ?? const <FightSetup>[])
      if (fight.challenger.artist == you.name) fight,
  ];

  List<HurryPlan> _incomingHurries = const [];
  @override
  List<HurryPlan> get incomingHurries => _incomingHurries;

  /// The player you sent today's free hurry to.
  @override
  Player? get hurrySentTo => _hurrySentTo;
  Player? _hurrySentTo;

  Player _drawerOf(Player author) {
    final players = server.players;
    return players[(players.indexOf(author) + 1) % players.length];
  }

  /// The person a simulated player chooses: anyone but themselves.
  Player _randomSubject(Player author) {
    final candidates = server.players.where((p) => p.id != author.id).toList();
    return candidates[_random.nextInt(candidates.length)];
  }

  DailyTheme _themeOfDay(int day) => DailyTheme.ofDate(_launchedOn.add(Duration(days: day - 1)));

  void _startDay() {
    if (_day > 0 && _isFinaleDay(_day)) _decideFinale(_day);
    // Once the day is over, chance spreads the boost stars you left.
    if (_day > 0) _spreadBoosts(_boostTargetsOf(you, _day), _yourBoosts[_day] ?? const {});
    _day++;
    _theme = _themeOfDay(_day);
    // Today's prompts are for challengers fought in three days, in that day's theme.
    _promptTheme = _themeOfDay(_day + 3);
    // Like online, every hint is used once at most; you get the first.
    final hints = _hintsOn(_promptTheme, _day).where((h) => !_usedHints.contains(h.entry.id)).toList()
      ..shuffle(_random);
    _MockContent? nextHint() {
      if (hints.isEmpty) return null;
      final hint = hints.removeAt(0);
      _usedHints.add(hint.entry.id);
      return hint;
    }

    _promptHint = nextHint()?.text;
    _hurrySentTo = null;
    final others = otherPlayers;

    // Step 1: everyone chooses a person and writes a title.
    _prompts[_day] = [
      // The simulated players write their hint's premade title.
      for (final (author, hint) in [for (final author in others) (author, nextHint())])
        ChallengerPrompt(
          id: 'prompt$_day-${author.id}',
          author: author,
          subject: _randomSubject(author),
          theme: _promptTheme,
          title: hint?.premadeTitle ?? _bots.title(),
          day: _day,
          hint: hint?.text,
        ),
    ];

    // Step 2: yesterday's prompts are drawn by the next player in the roster.
    _challengers[_day] = [];
    _promptToDraw = null;
    for (final prompt in _prompts[_day - 1] ?? const <ChallengerPrompt>[]) {
      final drawer = _drawerOf(prompt.author);
      if (drawer.isYou) {
        _promptToDraw = prompt;
      } else {
        _addChallenger(prompt, drawer, _bots.doodle('challenger'));
      }
    }
    // Each simulated player may spend their free hurry on you.
    _incomingHurries = [
      if (_promptToDraw != null)
        for (final sender in others)
          if (_random.nextDouble() < 0.3)
            HurryPlan(
              by: sender.name,
              atFraction: HurryPlan.earliest + _random.nextDouble() * (HurryPlan.latest - HurryPlan.earliest),
            ),
    ]..sort((a, b) => a.atFraction.compareTo(b.atFraction));

    // Step 3: the simulated players spread their boost stars at random.
    for (final booster in others) {
      _spreadBoosts(_boostTargetsOf(booster, _day), const {});
    }

    // Step 4: they fight the challengers boosted yesterday, decided right
    // away.
    _fightChallenger = _fightChallengerOf(you, _day);
    _fights[_day] = [];
    for (final owner in others) {
      final roster = _botRosters[owner.id] ?? const <CharacterCard>[];
      final challenger = _fightChallengerOf(owner, _day);
      if (roster.isEmpty || challenger == null) continue;
      final picks = ([...roster]..shuffle(_random)).take(1 + _random.nextInt(FightSetup.maxFighters));
      _fights[_day]!.add(
        FightSetup(
          id: 'fight$_day-${owner.id}',
          owner: owner,
          challenger: challenger,
          fighters: [for (final card in picks) FighterEntry(card: card)],
          day: _day,
          boostStars: _boostStars[challenger.id] ?? 0,
        ),
      );
    }

    // The simulated players pull a character every day.
    for (final roster in _botRosters.values) {
      roster.add(_pool[_random.nextInt(_pool.length)]);
    }
  }

  void _addChallenger(ChallengerPrompt prompt, Player artist, Sketch sketch) {
    final card = CharacterCard(
      id: 'challenger$_day-${artist.id}',
      subject: prompt.subject.name,
      title: prompt.title,
      rarity: Rarity.hero,
      prompt: 'Challenger: ${prompt.theme.label}',
      artist: artist.name,
      sketch: sketch,
      day: _day,
      theme: prompt.theme,
    );
    _challengers[_day]!.add(card);
  }

  /// The challengers you drew, fought against or boosted. Like the results,
  /// a challenger's fights count once their day is over.
  @override
  List<ChallengerRecord> get challengers {
    final allFights = [for (final day in _fights.values) ...day];
    bool encountered(CharacterCard card) =>
        card.artist == you.name ||
        _yourBoosts.values.any((given) => given.containsKey(card.id)) ||
        allFights.any((f) => f.challenger.id == card.id && f.owner.isYou);
    ChallengerRecord record(CharacterCard card) {
      final decided = allFights.where((f) => f.challenger.id == card.id && f.day < _day).toList();
      return ChallengerRecord(card: card, fights: decided.length, wins: decided.where((f) => !f.fightersWin).length);
    }

    final days = _challengers.keys.toList()..sort((a, b) => b.compareTo(a));
    return [
      for (final day in days)
        for (final card in _challengers[day]!)
          if (encountered(card)) record(card),
    ];
  }

  @override
  bool get canAdvanceDay => true;

  /// The simulated players never wait for you.
  @override
  bool get canEndDay => false;

  @override
  Set<String> get dayEnded => const {};

  @override
  Future<void> endDay() => advanceDay();

  @override
  Future<void> refreshDay() async {}

  @override
  Future<void> advanceDay() async {
    _startDay();
    notifyListeners();
  }

  /// Step 1: choose a person and write their title.
  @override
  Future<void> submitPrompt(String title, Player subject) async {
    if (yourPrompt != null) return;
    if (subject.id == you.id) throw ArgumentError('Choose another player');
    _prompts[_day]!.add(
      ChallengerPrompt(
        id: 'prompt$_day-${you.id}',
        author: you,
        subject: subject,
        theme: _promptTheme,
        title: title.trim(),
        day: _day,
        hint: _promptHint,
      ),
    );
    notifyListeners();
  }

  /// Step 2: drawing the challenger adds it to the challengers (not the gacha
  /// pool) as a hero and earns a pull.
  @override
  Future<void> submitChallenger(Sketch sketch) async {
    final prompt = _promptToDraw;
    if (prompt == null || challengerDrawn) return;
    _addChallenger(prompt, you, sketch);
    _tickets++;
    notifyListeners();
  }

  /// Step 4: lock in up to four fighters against today's challenger, decided
  /// right away.
  @override
  Future<void> submitFighters(List<OwnedCard> fighters) async {
    final challenger = _fightChallenger;
    if (challenger == null || yourFight != null) return;
    if (fighters.isEmpty || fighters.length > FightSetup.maxFighters) {
      throw ArgumentError('Pick between 1 and ${FightSetup.maxFighters} fighters.');
    }
    if (fighters.any(isResting)) throw ArgumentError("Every character fights once a week; they're back on Monday.");
    _fights[_day]!.add(
      FightSetup(
        id: 'fight$_day-${you.id}',
        owner: you,
        challenger: challenger,
        fighters: [for (final owned in fighters) FighterEntry.fromOwned(owned)],
        day: _day,
        boostStars: _boostStars[challenger.id] ?? 0,
      ),
    );
    // A win earns a pull and the challenger's stars.
    if (yourFight!.fightersWin) {
      _tickets++;
      _victoryStars += yourFight!.challengerStars;
    }
    notifyListeners();
  }

  /// Hurries are free, once per day. The target only finds out while drawing.
  @override
  Future<bool> sendHurry(Player target) async {
    if (_hurrySentTo != null || target.isYou) return false;
    _hurrySentTo = target;
    notifyListeners();
    return true;
  }

  // Gacha -----------------------------------------------------------------------

  @override
  Future<List<PullOutcome>> pull(int count, {GachaBanner banner = GachaBanner.standard}) async {
    if (count > _tickets) throw StateError('Not enough pulls.');
    if (banner == GachaBanner.weekly && rateUp.isEmpty) {
      throw StateError('The weekly banner opens with the first finale.');
    }
    _tickets -= count;
    final outcomes = <PullOutcome>[];
    for (var i = 0; i < count; i++) {
      final card = _gacha.pull(_pool, banner: banner, rateUp: rateUp);
      final owned = _owned[card.id];
      if (owned == null) {
        _owned[card.id] = OwnedCard(card);
        outcomes.add(PullOutcome(card: card, isNew: true, copies: 1));
      } else {
        owned.copies++;
        outcomes.add(PullOutcome(card: card, isNew: false, copies: owned.copies));
      }
    }
    notifyListeners();
    return outcomes;
  }

  // Collection ------------------------------------------------------------------

  @override
  List<OwnedCard> get collection {
    final cards = _owned.values.toList()
      ..sort((a, b) {
        final byRarity = b.card.rarity.stars.compareTo(a.card.rarity.stars);
        return byRarity != 0 ? byRarity : a.card.subject.compareTo(b.card.subject);
      });
    return cards;
  }

  @override
  Future<void> unlockNextUpgrade(OwnedCard owned, {ElementKind? element}) async {
    final next = owned.nextUpgrade;
    if (!canUpgrade(owned) || next == null) return;
    if (next == UpgradeEffect.element) {
      if (element == null) throw ArgumentError('Choose an element for this upgrade.');
      owned.element = element;
    }
    owned.unlocked.add(next);
    notifyListeners();
  }

  @override
  Future<void> changeElement(OwnedCard owned, ElementKind element) async {
    if (!owned.unlocked.contains(UpgradeEffect.element)) throw ArgumentError('Unlock element first.');
    owned.element = element;
    notifyListeners();
  }

  @override
  Future<void> setEffectShown(OwnedCard owned, UpgradeEffect effect, {required bool shown}) async {
    if (!owned.unlocked.contains(effect)) throw ArgumentError('Unlock ${effect.label} first.');
    shown ? owned.hidden.remove(effect) : owned.hidden.add(effect);
    notifyListeners();
  }

  void _setPhase(GamePhase phase) {
    _phase = phase;
    notifyListeners();
  }
}

/// A challenger in a finale of the mockup, with its record that week.
class _Contender {
  const _Contender(this.card, {required this.wins, required this.boostStars});

  final CharacterCard card;
  final int wins;
  final int boostStars;
}

/// A prompt hint of the mockup, see [MockGameSession.canEditContent].
class _MockContent {
  _MockContent({
    required DailyTheme theme,
    required String text,
    required String premadeTitle,
    required this.addedOn,
    String? id,
  }) : entry = ContentEntry(
         id: id ?? 'content-${theme.name}-$text',
         theme: theme,
         text: text,
         premadeTitle: premadeTitle,
         createdAt: DateTime.now(),
       );

  final ContentEntry entry;

  /// The day it was added on; used from the next one.
  final int addedOn;

  /// The day it was retired on; used until the end of it.
  int? retiredOn;

  DailyTheme get theme => entry.theme;

  String get text => entry.text;

  String get premadeTitle => entry.premadeTitle;
}

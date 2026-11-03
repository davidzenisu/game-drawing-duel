import 'dart:math';

import '../game/game_session.dart';
import '../game/rules/content.dart';
import '../game/rules/daily_loop.dart';
import '../game/rules/gacha.dart';
import '../game/rules/models.dart';
import '../game/rules/setup_plan.dart';
import '../game/rules/themes.dart';
import '../game/rules/upgrades.dart';
import 'bot_artist.dart';
import 'demo_days.dart';

/// The mockup of the game for demos and PR previews: everything happens in
/// memory within a single session. Your friends are sample data
/// ([DemoDays]), not a simulation: only your own actions change the game,
/// under the shared rules (stars, gacha, upgrades).
class MockGameSession extends GameSession {
  /// [launchDate] fixes the calendar day of day 1, which sets the themes;
  /// by default it's the day the game launches.
  MockGameSession({int? seed, this.launchDate})
    : _random = Random(seed),
      _bots = BotArtist(seed ?? DateTime.now().microsecondsSinceEpoch),
      _gacha = GachaMachine(random: Random(seed));

  final DateTime? launchDate;

  /// The canned days of the running game.
  DemoDays? _demo;
  DemoDays get _days => _demo!;

  /// The Monday a week ago, when starting on day 8, see [startOnDayEight].
  DateTime? _dayEightLaunch;

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

  /// Signs up, creates a regular server with five friends and jumps to day
  /// 8, the Monday of this week: last week's ranking, weekly hero and win
  /// rates are in place.
  @override
  Future<void> startOnDayEight(String firstName) async {
    await signUp(firstName);
    await createServer(suggestedNames.where((name) => name != you.name).take(5).toList());
    server.joined.addAll(server.players.map((p) => p.id));
    await startSetup();
    for (final assignment in assignments) {
      await submitSetupDrawing(assignment, _bots.doodle(assignment.prompt.label), _bots.title());
    }
    final now = (launchDate ?? DateTime.now()).toUtc();
    _dayEightLaunch = DateTime.utc(now.year, now.month, now.day - (now.weekday - DateTime.monday) - 7, 12);
    await launch();
    while (day < 8) {
      await advanceDay();
    }
  }

  // Server creation / join ----------------------------------------------------

  /// Creates a server with a prepopulated roster; the creator is the admin.
  @override
  Future<void> createServer(List<String> otherNames, {bool isTest = false, bool speed = false}) async {
    final players = [you, for (final (i, name) in otherNames.indexed) Player(id: 'p$i', name: name.trim())];
    _server = ServerSession(
      code: _newCode(),
      players: players,
      isAdmin: true,
      joined: {you.id},
      isTest: isTest,
      isSpeed: speed,
    );
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
    _demo = null;
    _dayEightLaunch = null;
    _assignments = const [];
    _setupDrawings.clear();
    _pool.clear();
    _owned.clear();
    _tickets = 0;
    _victoryStars = 0;
    _day = 0;
    _theme = DailyTheme.forest;
    _gacha = GachaMachine(random: _random);
    _yourPrompts.clear();
    _yourChallengers.clear();
    _yourFights.clear();
    _yourBoosts.clear();
    _weeklyHero = null;
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
        : server.isSpeed
        ? SetupPlan.speedAssignmentsFor(players, index)
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

  /// Fills the pool with your drawings and your friends' and starts day 1,
  /// on [launchDate] or today.
  @override
  Future<void> launch() async {
    _demo = DemoDays(
      players: server.players,
      launchedOn: (_dayEightLaunch ?? launchDate ?? DateTime.now()).toUtc(),
      bots: _bots,
    );
    server.setupDone.addAll(server.artists.map((p) => p.id));
    for (final artist in server.artists) {
      if (artist.isYou) continue;
      for (final assignment in _assignmentsOf(artist)) {
        _pool.add(
          CharacterCard(
            id: assignment.id,
            subject: assignment.subject.name,
            title: _bots.title(),
            rarity: assignment.prompt.rarity,
            prompt: assignment.prompt.label,
            artist: artist.name,
            sketch: _bots.doodle(assignment.prompt.label),
          ),
        );
      }
    }
    _pool.addAll(_setupDrawings.values);
    for (final card in _setupDrawings.values) {
      // In speed mode, artists own only their basic drawing.
      if (!server.isSpeed || card.rarity == Rarity.basic) _owned[card.id] = OwnedCard(card);
    }
    _tickets += GachaMachine.launchBonus;
    _startDay();
    _setPhase(GamePhase.daily);
  }

  // Daily routine ---------------------------------------------------------------

  /// What you did, by day: your prompts, challengers, boosts and fights.
  final Map<int, ChallengerPrompt> _yourPrompts = {};
  final Map<int, CharacterCard> _yourChallengers = {};
  final Map<int, Map<String, int>> _yourBoosts = {};
  final Map<int, FightSetup> _yourFights = {};

  @override
  DailyTheme get promptTheme => _days.themeOf(_day + 3);

  /// The description of today's prompt: one of the theme's hints in use.
  @override
  String? get promptHint {
    final hints = _hintsOn(promptTheme, _day);
    return hints.isEmpty ? null : hints[_day % hints.length].text;
  }

  @override
  ChallengerPrompt? get yourPrompt => _yourPrompts[_day];

  bool _promptsOn(int day) => day >= 1 && (!server.isSpeed || day <= SpeedMode.lastPromptDay);

  /// Friends drew challengers on the days after one with prompts.
  bool _drawnOn(int day) => _promptsOn(day - 1);

  @override
  ChallengerPrompt? get promptToDraw => _drawnOn(_day) && !sessionOver ? _days.promptToDraw(_day) : null;

  @override
  CharacterCard? get yourChallenger => _yourChallengers[_day];

  /// A friend's challenger drawn on [day], see [DemoDays.challenger].
  CharacterCard _challenger(int day, int slot) => _days.challenger(day, slot, yourPrompt: _yourPrompts[day - 1]);

  /// The fourth of the challengers drawn two days ago.
  @override
  CharacterCard? get fightChallenger =>
      _drawnOn(_day - 2) && !sessionOver ? _challenger(_day - 2, DemoDays.slots - 1) : null;

  @override
  FightSetup? get yourFight => _yourFights[_day];

  /// Like online: your characters that fought earlier this week, which
  /// starts on Monday.
  @override
  Set<String> get restingCharacterIds => {
    for (final MapEntry(key: day, value: fight) in _yourFights.entries)
      if (day >= _days.weekStart(_day) && day < _day)
        for (final fighter in fight.fighters)
          if (fighter.card.rarity != Rarity.basic) fighter.card.id,
  };

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

  /// The first three of yesterday's challengers.
  @override
  List<BoostTarget> get boostTargets => [
    if (_drawnOn(_day - 1) && !sessionOver)
      for (var slot = 0; slot < Boost.challengers; slot++)
        BoostTarget(
          challenger: _challenger(_day - 1, slot),
          stars: _yourBoosts[_day]?[_challenger(_day - 1, slot).id] ?? 0,
        ),
  ];

  /// Step 3: gives today's challengers to boost these stars, replacing the
  /// ones you gave today.
  @override
  Future<void> setBoosts(Map<String, int> stars) async {
    final targets = {for (final t in boostTargets) t.challenger.id};
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

  /// A challenger's boost stars: the friends' plus yours.
  int _boostStars(CharacterCard challenger) =>
      _days.friendsBoostStars(challenger) +
      _yourBoosts.values.fold(0, (sum, given) => sum + (given[challenger.id] ?? 0));

  // The finale -----------------------------------------------------------------

  WeeklyHero? _weeklyHero;

  @override
  WeeklyHero? get weeklyHero => _weeklyHero;

  /// The challengers drawn from [from] to [to], the friends' and yours, most
  /// stars first. Each had one fight: the even ones won it.
  List<RankedChallenger> _ranked(int from, int to) =>
      [
            for (var day = from; day <= to; day++)
              if (_drawnOn(day)) ...[
                for (var slot = 0; slot < DemoDays.slots; slot++) _challenger(day, slot),
                ?_yourChallengers[day],
              ],
          ]
          .map(
            (c) => RankedChallenger(
              card: c,
              stars: Stars.ofChallenger(_boostStars(c)),
              fights: 1,
              wins: c.day.isEven ? 1 : 0,
            ),
          )
          .toList()
        ..sort((a, b) => b.stars.compareTo(a.stars));

  /// The latest finished week's ranking: the challengers boosted that week.
  /// A speed session ranks all of its challengers once it's over.
  @override
  Future<WeekRanking?> weekRanking() async {
    if (server.isSpeed) {
      final lastDay = SpeedMode.days.length;
      return sessionOver ? WeekRanking(day: lastDay, challengers: _ranked(1, lastDay)) : null;
    }
    final lastDay = _days.weekStart(_day) - 1;
    if (lastDay < 7) return null;
    return WeekRanking(day: lastDay, challengers: _ranked(lastDay - 7, lastDay - 1));
  }

  @override
  Future<WeekWinRates?> winRates() async => server.isSpeed ? null : _days.winRates(_day, you);

  List<HurryPlan> _incomingHurries = const [];
  @override
  List<HurryPlan> get incomingHurries => _incomingHurries;

  @override
  Player? get hurrySentTo => _hurrySentTo;
  Player? _hurrySentTo;

  void _startDay() {
    _day++;
    _theme = _days.themeOf(_day);
    _hurrySentTo = null;
    _incomingHurries = promptToDraw == null ? const [] : _days.hurries(_day);
    // A new week: last week's best challenger joins the pool as its hero.
    if (!server.isSpeed && _days.weekStart(_day) == _day && _day > 7) {
      final ranked = _ranked(_day - 8, _day - 2);
      if (ranked.isNotEmpty) {
        final winner = ranked.first;
        if (!_pool.any((c) => c.id == winner.card.id)) _pool.add(winner.card);
        _weeklyHero = WeeklyHero(card: winner.card, day: _day - 1, stars: winner.stars);
      }
    }
  }

  /// The challengers you drew, boosted or fought, newest first. Yours had
  /// one fight once fought, two days after: the even ones won it.
  @override
  List<ChallengerRecord> get challengers {
    final encountered = <CharacterCard>{
      ..._yourChallengers.values,
      for (final given in _yourBoosts.entries)
        for (final t in given.value.keys) _challenger(given.key - 1, _slotOf(t)),
      for (final fight in _yourFights.values) fight.challenger,
    };
    ChallengerRecord record(CharacterCard card) {
      final yours = _yourChallengers.containsValue(card);
      final fought = _yourFights.values.where((f) => f.challenger.id == card.id && f.day < _day).toList();
      final fights = yours ? (_day > card.day + 2 ? 1 : 0) : fought.length;
      final wins = yours ? (fights > 0 && card.day.isEven ? 1 : 0) : fought.where((f) => !f.fightersWin).length;
      return ChallengerRecord(card: card, fights: fights, wins: wins);
    }

    return [for (final card in encountered.toList()..sort((a, b) => b.day.compareTo(a.day))) record(card)];
  }

  int _slotOf(String challengerId) => int.parse(challengerId.split('-').last);

  @override
  bool get canAdvanceDay => !sessionOver;

  @override
  bool get promptsToday => _promptsOn(_day);

  /// The mockup's days only move on when you skip ahead.
  @override
  DateTime? get dayEndsAt => null;

  @override
  bool get sessionOver => server.isSpeed && _day > SpeedMode.days.length;

  /// Your friends never wait for you.
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

  /// Step 1: choose a person and write their title; a friend draws it
  /// tomorrow, see [DemoDays.challenger].
  @override
  Future<void> submitPrompt(String title, Player subject) async {
    if (yourPrompt != null) return;
    if (!promptsToday) throw StateError('No challenger prompts today.');
    if (subject.id == you.id) throw ArgumentError('Choose another player');
    _yourPrompts[_day] = ChallengerPrompt(
      id: 'prompt$_day-${you.id}',
      author: you,
      subject: subject,
      theme: promptTheme,
      title: title.trim(),
      day: _day,
      hint: promptHint,
    );
    notifyListeners();
  }

  /// Step 2: drawing the challenger adds it to the challengers (not the gacha
  /// pool) as a hero and earns a pull.
  @override
  Future<void> submitChallenger(Sketch sketch) async {
    final prompt = promptToDraw;
    if (prompt == null || challengerDrawn) return;
    _yourChallengers[_day] = CharacterCard(
      id: 'challenger$_day-${you.id}',
      subject: prompt.subject.name,
      title: prompt.title,
      rarity: Rarity.hero,
      prompt: 'Challenger: ${prompt.theme.label}',
      artist: you.name,
      sketch: sketch,
      day: _day,
      theme: prompt.theme,
    );
    _tickets++;
    notifyListeners();
  }

  /// Step 4: lock in up to four fighters against today's challenger, decided
  /// right away with both sides' win rate extra stars.
  @override
  Future<void> submitFighters(List<OwnedCard> fighters) async {
    final challenger = fightChallenger;
    if (challenger == null || yourFight != null) return;
    if (fighters.isEmpty || fighters.length > FightSetup.maxFighters) {
      throw ArgumentError('Pick between 1 and ${FightSetup.maxFighters} fighters.');
    }
    if (fighters.any(isResting)) throw ArgumentError("Every character fights once a week; they're back on Monday.");
    final rates = _days.winRates(_day, you);
    final against = challenger.subject;
    final fight = _yourFights[_day] = FightSetup(
      id: 'fight$_day-${you.id}',
      owner: you,
      challenger: challenger,
      fighters: [
        for (final owned in fighters)
          FighterEntry.fromOwned(owned, extraStars: rates.extraStars(owned.card.subject, against)),
      ],
      day: _day,
      boostStars: _boostStars(challenger),
      challengerExtraStars: fighters.fold(0, (sum, o) => sum + rates.extraStars(against, o.card.subject)),
    );
    // A win earns pulls and the challenger's stars.
    if (fight.fightersWin) {
      _tickets += pullsForWin(fight);
      _victoryStars += fight.challengerStars;
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

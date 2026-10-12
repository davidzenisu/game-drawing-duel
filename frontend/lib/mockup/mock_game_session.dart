import 'dart:math';

import '../game/game_session.dart';
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

  /// A few of the prompt hints the API keeps in its database, per theme.
  static const _hints = {
    DailyTheme.forest: ['a challenger lost on the way to work', 'a challenger who walks the dog at dawn'],
    DailyTheme.beach: ['a challenger doing laps at the public pool', 'a challenger planning a holiday in spreadsheets'],
    DailyTheme.volcano: [
      'a challenger who can take the heat in the sauna',
      'a challenger who burns dinner every night',
    ],
    DailyTheme.snow: [
      "a challenger who can't decide on an ice cream flavour",
      'a challenger scraping ice off the windshield',
    ],
    DailyTheme.jungle: ['a challenger who gets lost in the club', 'a challenger ruling the dance floor'],
    DailyTheme.space: ['a challenger lost in a furniture store maze', 'a challenger fixing their washing machine'],
    DailyTheme.castle: ['a challenger who rules from the couch', 'a challenger hosting Sunday brunch'],
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
    _day = 0;
    _theme = DailyTheme.forest;
    _gacha = GachaMachine(random: _random);
    _prompts.clear();
    _challengers.clear();
    _fights.clear();
    _boosted.clear();
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
    return server.isTest
        ? SetupPlan.testAssignmentsFor(players, index, _random)
        : SetupPlan.assignmentsFor(players, index);
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

  @override
  List<BoostTarget> get boostTargets => _boostTargets(you);

  /// Yesterday's challengers [player] may boost: all but the one they drew
  /// and the one they fought.
  List<BoostTarget> _boostTargets(Player player) {
    final yesterday = _fights[_day - 1] ?? const <FightSetup>[];
    final fought = yesterday.where((f) => f.owner.id == player.id).firstOrNull?.challenger;
    final matchups = <String, List<FightSetup>>{};
    for (final fight in yesterday) {
      final challenger = fight.challenger;
      if (challenger.artist == player.name || challenger.id == fought?.id) continue;
      matchups.putIfAbsent(challenger.id, () => []).add(fight);
    }
    return [for (final fights in matchups.values) BoostTarget(challenger: fights.first.challenger, matchups: fights)];
  }

  @override
  String? get boostedChallengerId => _boosted[_day];

  /// The challengers you boosted, by day.
  final Map<int, String> _boosted = {};

  void _boost(BoostTarget target) {
    for (final fight in target.matchups) {
      fight.boosts++;
    }
  }

  /// Decided fights you picked the fighters for (two days ago).
  @override
  List<FightSetup> get yourFightResults => [
    for (final fight in _fights[_day - 2] ?? const <FightSetup>[])
      if (fight.owner.isYou) fight,
  ];

  /// Decided fights against the challenger you drew (three days ago).
  @override
  List<FightSetup> get yourChallengerResults => [
    for (final fight in _fights[_day - 2] ?? const <FightSetup>[])
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
    _day++;
    _theme = _themeOfDay(_day);
    // Today's prompts are for challengers fought in two days, in that day's theme.
    _promptTheme = _themeOfDay(_day + 2);
    // Everyone gets a different hint, as far as the theme has enough.
    final hints = [..._hints[_promptTheme]!]..shuffle(_random);
    _promptHint = hints.first;
    _hurrySentTo = null;
    final others = otherPlayers;

    // Step 1: everyone chooses a person and writes a title.
    _prompts[_day] = [
      for (final (i, author) in others.indexed)
        ChallengerPrompt(
          id: 'prompt$_day-${author.id}',
          author: author,
          subject: _randomSubject(author),
          theme: _promptTheme,
          title: _bots.title(),
          day: _day,
          hint: hints[(i + 1) % hints.length],
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

    // Step 3: pick fighters against one of yesterday's challengers.
    final yesterday = _challengers[_day - 1] ?? const <CharacterCard>[];
    final notYours = yesterday.where((c) => c.artist != you.name).toList();
    _fightChallenger = notYours.isEmpty ? null : notYours[_random.nextInt(notYours.length)];
    _fights[_day] = [];
    final yourChallengerYesterday = yesterday.where((c) => c.artist == you.name).firstOrNull;
    for (final (i, owner) in others.indexed) {
      final roster = _botRosters[owner.id] ?? const <CharacterCard>[];
      // Your challenger is reserved for the first player so the others spread out.
      final candidates = yesterday.where((c) => c.artist != owner.name && c != yourChallengerYesterday).toList();
      if (roster.isEmpty || candidates.isEmpty) continue;
      // Make sure somebody fights the challenger you drew.
      final challenger = i == 0 && yourChallengerYesterday != null
          ? yourChallengerYesterday
          : candidates[_random.nextInt(candidates.length)];
      final picks = ([...roster]..shuffle(_random)).take(1 + _random.nextInt(FightSetup.maxFighters));
      _fights[_day]!.add(
        FightSetup(
          id: 'fight$_day-${owner.id}',
          owner: owner,
          challenger: challenger,
          fighters: [for (final card in picks) FighterEntry(card: card)],
          day: _day,
        ),
      );
    }

    // Step 4: most simulated players boost one of yesterday's challengers.
    for (final booster in others) {
      final targets = _boostTargets(booster);
      if (targets.isEmpty || _random.nextDouble() < 0.3) continue;
      _boost(targets[_random.nextInt(targets.length)]);
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

  /// The challengers you drew, fought against or boosted. A fight is
  /// decided once the day after it, its boosting day, is over.
  @override
  List<ChallengerRecord> get challengers {
    final allFights = [for (final day in _fights.values) ...day];
    bool encountered(CharacterCard card) =>
        card.artist == you.name ||
        _boosted.containsValue(card.id) ||
        allFights.any((f) => f.challenger.id == card.id && f.owner.isYou);
    ChallengerRecord record(CharacterCard card) {
      final decided = allFights.where((f) => f.challenger.id == card.id && f.day < _day - 1).toList();
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

  /// Step 3: lock in up to four fighters against today's challenger.
  @override
  Future<void> submitFighters(List<OwnedCard> fighters) async {
    final challenger = _fightChallenger;
    if (challenger == null || yourFight != null) return;
    if (fighters.isEmpty || fighters.length > FightSetup.maxFighters) {
      throw ArgumentError('Pick between 1 and ${FightSetup.maxFighters} fighters.');
    }
    _fights[_day]!.add(
      FightSetup(
        id: 'fight$_day-${you.id}',
        owner: you,
        challenger: challenger,
        fighters: [for (final owned in fighters) FighterEntry.fromOwned(owned)],
        day: _day,
      ),
    );
    notifyListeners();
  }

  /// Step 4: boost one of yesterday's challengers, once a day.
  @override
  Future<void> boost(CharacterCard challenger) async {
    final target = boostTargets.where((t) => t.challenger.id == challenger.id).firstOrNull;
    if (target == null || boostedChallengerId != null) return;
    _boosted[_day] = challenger.id;
    _boost(target);
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
  Future<List<PullOutcome>> pull(int count) async {
    if (count > _tickets) throw StateError('Not enough pulls.');
    _tickets -= count;
    final outcomes = <PullOutcome>[];
    for (var i = 0; i < count; i++) {
      final card = _gacha.pull(_pool);
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

  void _setPhase(GamePhase phase) {
    _phase = phase;
    notifyListeners();
  }
}

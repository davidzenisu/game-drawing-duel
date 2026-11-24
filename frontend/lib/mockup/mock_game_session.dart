import 'dart:math';

import '../game/game_session.dart';
import '../game/rules/achievements.dart';
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

  /// Like online: the latest finale's heroes.
  @override
  Set<String> get rateUp => {for (final hero in _weeklyHeroes) hero.card.id};

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

  String? _accountName;
  @override
  String get accountName => _accountName!;

  @override
  Future<void> rename(String firstName) async {
    _accountName = firstName.trim();
    // Not on a server yet: you go by your account's name.
    if (_server == null) _you = Player(id: 'you', name: _accountName!, isYou: true);
    notifyListeners();
  }

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
  int get stars => _stars;
  int _stars = 0;
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
    _accountName = firstName.trim();
    _you = Player(id: 'you', name: _accountName!, isYou: true);
    _setPhase(GamePhase.server);
  }

  /// Signs up, creates a regular server with five friends and jumps to day
  /// 8, the Monday of this week: last week's ranking, weekly heroes and win
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
      // Yesterday's challenger is drawn, so today's boosts are on.
      if (day == 7) await submitChallenger(_bots.doodle('challenger'));
      // Sunday's fighters, your rarest character and a basic one, rest on
      // Monday: one is back tomorrow, the other a few days later.
      if (day == 7 && fightChallenger != null) {
        final byRarity = [...collection]..sort((a, b) => b.card.rarity.stars.compareTo(a.card.rarity.stars));
        await submitFighters({byRarity.first, byRarity.last}.toList());
      }
      await advanceDay();
    }
  }

  // Server creation / join ----------------------------------------------------

  /// Creates a server with a prepopulated roster; the creator is the admin.
  @override
  Future<void> createServer(
    List<String> otherNames, {
    String? yourName,
    bool isTest = false,
    bool speed = false,
  }) async {
    final name = yourName?.trim() ?? '';
    _you = Player(id: 'you', name: name.isEmpty ? accountName : name, isYou: true);
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
    roster[seat] = Player(id: 'p$seat', name: accountName);
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
    _stars = 0;
    _day = 0;
    _theme = DailyTheme.forest;
    _gacha = GachaMachine(random: _random);
    _yourPrompts.clear();
    _yourChallengers.clear();
    _yourFights.clear();
    _collectedChallengers.clear();
    _collectedAchievements.clear();
    _yourBoosts.clear();
    _weeklyHeroes = const [];
    _arenaWinners = const [];
    _latestArena = null;
    _arenaVotes.clear();
    _arenaRewarded.clear();
    _crowned.clear();
    _hurrySentTo = null;
    _hurryMessage = null;
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
    // A gift waits on the notification board, to try it.
    _gifts.add(
      Gift(
        id: 'demo-gift-welcome',
        message: 'Welcome to Drawing Duel! A few pulls on the house.',
        pulls: 3,
        sentAt: DateTime.now(),
      ),
    );
    _startDay();
    _setPhase(GamePhase.daily);
  }

  final List<Gift> _gifts = [];

  @override
  List<Gift> get gifts => List.unmodifiable(_gifts);

  @override
  Future<void> acceptGift(Gift gift) async {
    if (!_gifts.any((g) => g.id == gift.id)) return;
    _gifts.removeWhere((g) => g.id == gift.id);
    _tickets += gift.pulls;
    _stars += gift.stars;
    notifyListeners();
  }

  /// The feedback boards, by server code, kept for the whole session. A
  /// board starts with two of your friends' suggestions, one you can
  /// upvote, one they upvoted already.
  final Map<String, List<_MockSuggestion>> _boards = {};

  List<_MockSuggestion> get _board => _boards.putIfAbsent(server.code, () {
    final friends = [
      for (final p in server.players)
        if (!p.isYou) p.name,
    ];
    final now = DateTime.now();
    return [
      _MockSuggestion(
        id: '${server.code}-suggestion-1',
        kind: SuggestionKind.idea,
        title: 'A dark mode for the canvas',
        description: 'Drawing at night on the bright cardboard hurts the eyes. A darker canvas would help.',
        author: friends.first,
        createdAt: now.subtract(const Duration(days: 2)),
        voters: {friends.last},
      ),
      _MockSuggestion(
        id: '${server.code}-suggestion-2',
        kind: SuggestionKind.bug,
        title: 'Undo removes two strokes',
        description: 'Sometimes one tap on undo takes away the last two strokes instead of one.',
        author: friends.last,
        createdAt: now.subtract(const Duration(hours: 5)),
      )..status = SuggestionStatus.inProgress,
    ];
  });

  Suggestion _suggestion(_MockSuggestion s) => Suggestion(
    id: s.id,
    kind: s.kind,
    title: s.title,
    description: s.description,
    author: s.author,
    createdAt: s.createdAt,
    votes: s.voters.length,
    voted: s.voters.contains(_yourName),
    yours: s.author == _yourName,
    // Like a server admin's, see [canManageServers].
    removable: s.author == _yourName || canManageServers,
    status: s.status,
  );

  /// Your name on the board: one per server, like the friends'.
  String get _yourName => server.players.firstWhere((p) => p.isYou).name;

  @override
  Future<List<Suggestion>> suggestions() async {
    final board = [..._board]
      ..sort((a, b) {
        final votes = b.voters.length.compareTo(a.voters.length);
        return votes != 0 ? votes : b.createdAt.compareTo(a.createdAt);
      });
    return [for (final s in board) _suggestion(s)];
  }

  @override
  Future<Suggestion> suggest({required SuggestionKind kind, required String title, required String description}) async {
    if (title.trim().isEmpty || description.trim().isEmpty) {
      throw ArgumentError('A suggestion needs a title and a description.');
    }
    final suggestion = _MockSuggestion(
      id: '${server.code}-suggestion-${_board.length + 1}',
      kind: kind,
      title: title.trim(),
      description: description.trim(),
      author: _yourName,
      createdAt: DateTime.now(),
    );
    _board.add(suggestion);
    return _suggestion(suggestion);
  }

  @override
  Future<void> removeSuggestion(Suggestion suggestion) async {
    final s = _board.firstWhere((s) => s.id == suggestion.id);
    if (!_suggestion(s).removable) throw ArgumentError('Only its author or a server admin can remove it.');
    _board.remove(s);
  }

  @override
  Future<Suggestion> setSuggestionStatus(Suggestion suggestion, SuggestionStatus status) async {
    final s = _board.firstWhere((s) => s.id == suggestion.id);
    if (!SuggestionStatus.settable.contains(status)) throw ArgumentError('Done is up to its author.');
    if (s.status == SuggestionStatus.done) throw StateError('This suggestion is done already.');
    s.status = status;
    return _suggestion(s);
  }

  /// Like the backend: done, and its author gets a pull as a gift.
  @override
  Future<Suggestion> confirmFixed(Suggestion suggestion) async {
    final s = _board.firstWhere((s) => s.id == suggestion.id);
    if (!_suggestion(s).confirmable) throw StateError("This suggestion isn't yours in review.");
    s.status = SuggestionStatus.done;
    _gifts.add(
      Gift(
        id: 'gift-fixed-${s.id}',
        message: '${s.title} has been fixed. Thank you for reporting it.',
        pulls: 1,
        sentAt: DateTime.now(),
      ),
    );
    notifyListeners();
    return _suggestion(s);
  }

  @override
  Future<Suggestion> voteOn(Suggestion suggestion, {required bool up}) async {
    final s = _board.firstWhere((s) => s.id == suggestion.id);
    if (up && s.author == _yourName) throw ArgumentError("You can't upvote your own suggestion.");
    up ? s.voters.add(_yourName) : s.voters.remove(_yourName);
    return _suggestion(s);
  }

  /// The mockup has no accounts, so you can try the gift form: it lists
  /// this server, and a gift that reaches you lands on your board.
  @override
  bool get canManageServers => true;

  @override
  Future<List<GiftServer>> giftServers() async => [
    if (_server case final server?)
      GiftServer(
        code: server.code,
        speed: server.isSpeed,
        launched: phase == GamePhase.daily,
        players: [
          for (final (i, p) in server.players.indexed)
            (position: i, name: p.name, joined: server.joined.contains(p.id)),
        ],
      ),
  ];

  /// The setup drawings, then each day's challengers up to today: the
  /// friends' and yours, if you drew one.
  @override
  Future<List<AdminDrawing>> serverDrawings(String serverCode) async {
    if (serverCode != _server?.code) throw ArgumentError('No server with this code.');
    return [for (final card in _allDrawings) _adminDrawing(card)];
  }

  List<CharacterCard> get _allDrawings {
    final seen = <String>{};
    return [
      for (final card in _pool)
        if (card.day == 0 && seen.add(card.id)) card,
      for (var day = 1; day <= _day; day++)
        if (_drawnOn(day)) ...[
          for (var slot = 0; slot < DemoDays.slots; slot++)
            if (_challenger(day, slot) case final card when seen.add(card.id)) card,
          if (_yourChallengers[day] case final card? when seen.add(card.id)) card,
        ],
    ];
  }

  AdminDrawing _adminDrawing(CharacterCard card) => AdminDrawing(
    id: card.id,
    day: card.day == 0 ? null : card.day,
    date: card.day == 0 ? null : (server.isSpeed ? _days.dateOf(1) : _days.dateOf(card.day)),
    artist: card.artist,
    subject: card.subject,
    title: card.title,
    rarity: card.rarity,
  );

  @override
  Future<Sketch> drawingSketch(AdminDrawing drawing) async =>
      _allDrawings.firstWhere((c) => c.id == drawing.id, orElse: () => throw ArgumentError('No such drawing.')).sketch;

  @override
  Future<int> sendGift({
    required String message,
    required int pulls,
    int stars = 0,
    String? serverCode,
    List<int>? positions,
  }) async {
    final server = _server;
    if (server == null) throw StateError('No server to send it to.');
    if (serverCode != null && serverCode != server.code) throw ArgumentError('No server with this code.');
    final recipients = positions ?? [for (var i = 0; i < server.players.length; i++) i];
    if (recipients.isEmpty) throw ArgumentError('Pick at least one player.');
    if (recipients.contains(server.players.indexWhere((p) => p.isYou))) {
      _gifts.add(
        Gift(
          id: 'gift-${_gifts.length}-${DateTime.now().microsecondsSinceEpoch}',
          message: message,
          pulls: pulls,
          stars: stars,
          sentAt: DateTime.now(),
        ),
      );
      notifyListeners();
    }
    return recipients.length;
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

  /// Like online, with the question the friend answered: the description
  /// that comes with the canned title.
  @override
  ChallengerPrompt? get promptToDraw {
    if (!_drawnOn(_day) || sessionOver) return null;
    final prompt = _days.promptToDraw(_day);
    final hint = [
      for (final hints in _hints.values)
        for (final (text, premadeTitle) in hints)
          if (premadeTitle == prompt.title) text,
    ].firstOrNull;
    return ChallengerPrompt(
      id: prompt.id,
      author: prompt.author,
      subject: prompt.subject,
      theme: prompt.theme,
      title: prompt.title,
      day: prompt.day,
      hint: hint,
    );
  }

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

  /// Like online: your characters that rest after a fight, with the days
  /// they still rest; today's fighters rest from tomorrow on.
  @override
  Map<String, int> get restDays {
    final left = <String, int>{};
    for (final MapEntry(key: day, value: fight) in _yourFights.entries) {
      if (day > _day) continue;
      for (final fighter in fight.fighters) {
        final days = day + fighter.card.rarity.restDays + 1 - _day;
        if (days > (left[fighter.card.id] ?? 0)) left[fighter.card.id] = days;
      }
    }
    return left;
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

  /// The first three of yesterday's challengers, unless you skipped
  /// yesterday's drawing.
  @override
  List<BoostTarget> get boostTargets => [
    if (_drawnOn(_day - 1) && !sessionOver && !boostForfeited)
      for (var slot = 0; slot < Boost.challengers; slot++)
        BoostTarget(
          challenger: _challenger(_day - 1, slot),
          stars: _yourBoosts[_day]?[_challenger(_day - 1, slot).id] ?? 0,
        ),
  ];

  /// Like online: skipping yesterday's drawing costs today's boosts.
  @override
  bool get boostForfeited => _drawnOn(_day - 1) && !sessionOver && _yourChallengers[_day - 1] == null;

  /// Step 3: gives today's challengers to boost these stars, replacing the
  /// ones you gave today.
  @override
  Future<void> setBoosts(Map<String, int> stars) async {
    if (boostForfeited) throw StateError("You didn't draw yesterday, so you can't boost today.");
    final targets = {for (final t in boostTargets) t.challenger.id};
    if (targets.isEmpty) throw StateError('No challengers to boost today.');
    if (!targets.containsAll(stars.keys)) throw ArgumentError("You can't boost that challenger today.");
    if (stars.values.any((n) => n < 0 || n > boostStars)) {
      throw ArgumentError('A challenger takes up to $boostStars of your stars.');
    }
    if (stars.values.fold(0, (a, b) => a + b) > boostStars) {
      throw ArgumentError('You have $boostStars stars to give.');
    }
    _yourBoosts[_day] = {
      for (final MapEntry(key: id, value: n) in stars.entries)
        if (n > 0) id: n,
    };
    notifyListeners();
  }

  /// Whether the demo challengers drawn on [day] win their fight: one day in
  /// four (days 2, 6, 10…), so the heroes win about three fights in four and
  /// the boost balance gives +1 ★ a week (see [boostBalance]).
  static bool challengerWins(int day) => day % 4 == 2;

  /// Like online: the week before's fights balance the week's boost stars.
  @override
  BoostBalance? get boostBalance => _boostBalance(_day);

  /// The boost balance of [day]'s week, every week since the first stacking
  /// up: the fights of a week are those of the challengers drawn two days
  /// before each of its days ([weekRanking]). None in the first week and
  /// in speed mode.
  BoostBalance? _boostBalance(int day) {
    if (server.isSpeed) return null;
    final week = _days.weekStart(day);
    BoostBalance? balance;
    var stars = Boost.stars;
    for (var start = _days.weekStart(1); start < week; start += 7) {
      final ranked = _ranked(start - 2, start + 4);
      final fights = ranked.fold(0, (n, c) => n + c.fights);
      final heroWins = ranked.fold(0, (n, c) => n + c.fights - c.wins);
      final step = WeeklyBoost.step(heroWins, fights);
      balance = BoostBalance(
        fromDay: start,
        toDay: start + 6,
        fights: fights,
        heroWins: heroWins,
        previousStars: stars,
        step: step,
        stars: WeeklyBoost.stars(stars, step),
      );
      stars = balance.stars;
    }
    return balance;
  }

  /// A challenger's boost stars: the friends' plus yours.
  int _boostStars(CharacterCard challenger) =>
      _days.friendsBoostStars(challenger) +
      _yourBoosts.values.fold(0, (sum, given) => sum + (given[challenger.id] ?? 0));

  // The finale -----------------------------------------------------------------

  List<WeeklyHero> _weeklyHeroes = const [];

  @override
  List<WeeklyHero> get weeklyHeroes => _weeklyHeroes;

  /// The rarities the finales crowned challengers with, by id.
  final Map<String, Rarity> _crowned = {};

  /// [card] with the rarity a finale crowned it with, if one did.
  CharacterCard _asCrowned(CharacterCard card) => switch (_crowned[card.id]) {
    final rarity? => CharacterCard(
      id: card.id,
      subject: card.subject,
      title: card.title,
      rarity: rarity,
      prompt: card.prompt,
      artist: card.artist,
      sketch: card.sketch,
      day: card.day,
      theme: card.theme,
    ),
    null => card,
  };

  /// A challenger in the ranking, with demo details: its prompt by the
  /// player before its artist (premade now and then), the friends' boost
  /// stars from two of them (the second's spread by chance), yours, and
  /// one fight, won when drawn on a [challengerWins] day, against the player
  /// after its artist.
  RankedChallenger _rankedEntry(CharacterCard c) {
    final players = server.players;
    final artist = players.indexWhere((p) => p.name == c.artist).clamp(0, players.length - 1);
    Player at(int offset) => players[(artist + offset) % players.length];
    final boosters = [
      for (var offset = 2; offset < players.length; offset++)
        if (!at(offset).isYou) at(offset),
    ];
    final yours = _yourBoosts.values.fold(0, (sum, given) => sum + (given[c.id] ?? 0));
    final friends = _days.friendsBoostStars(c);
    // Up to a day's boost stars from each, the first their own.
    final boosts = [
      if (yours > 0) ChallengerBoost(booster: you, stars: yours),
      for (final (i, booster) in boosters.indexed)
        if (min(Boost.stars, friends - i * Boost.stars) case final stars when stars > 0)
          ChallengerBoost(booster: booster, stars: stars, byChance: i > 0),
    ];
    final won = challengerWins(c.day);
    return RankedChallenger(
      card: _asCrowned(c),
      stars: Stars.ofChallenger(_boostStars(c)),
      fights: 1,
      wins: won ? 1 : 0,
      promptAuthor: at(players.length - 1),
      defaultPrompt: (c.day + artist) % 4 == 0,
      boosts: boosts,
      foughtBy: [ChallengerFight(player: at(1), challengerWon: won)],
    );
  }

  /// The challengers drawn from [from] to [to], the friends' and yours,
  /// ranked like online ([Finale.order]), with their places. Each had one
  /// fight: the [challengerWins] days' ones won it.
  List<RankedChallenger> _ranked(int from, int to) {
    final entries = [
      for (var day = from; day <= to; day++)
        if (_drawnOn(day)) ...[
          for (var slot = 0; slot < DemoDays.slots; slot++) _challenger(day, slot),
          ?_yourChallengers[day],
        ],
    ].map(_rankedEntry).toList();
    final byArtist = <String, int>{};
    for (final r in entries) {
      byArtist[r.card.artist] = (byArtist[r.card.artist] ?? 0) + r.boostStars;
    }
    final withArtists = [for (final r in entries) r.at(1, artistBoostStars: byArtist[r.card.artist])];
    final order = Finale.order([for (final r in withArtists) r.rankedBy]);
    return [for (final (place, i) in order.indexed) withArtists[i].at(place + 1)];
  }

  /// The week that ends on [lastDay]: its challengers, the ones fought that
  /// week (drawn two days before), its top ones crowned weekly heroes.
  WeekRanking _week(int lastDay) => WeekRanking(
    day: lastDay,
    challengers: [
      for (final (i, r) in _ranked(lastDay - 8, lastDay - 2).indexed)
        i < Finale.maxHeroes ? r.at(i + 1, heroRarity: Finale.rarities[i]) : r,
    ],
    boostBalance: _boostBalance(lastDay + 1),
  );

  /// The latest finished week's ranking: the challengers fought that week,
  /// drawn two days before.
  /// A speed session ranks all of its challengers once it's over.
  @override
  Future<WeekRanking?> weekRanking({bool refresh = false}) async {
    if (server.isSpeed) {
      final lastDay = SpeedMode.days.length;
      return sessionOver ? WeekRanking(day: lastDay, challengers: _ranked(1, lastDay)) : null;
    }
    final lastDay = _days.weekStart(_day) - 1;
    if (lastDay < 7) return null;
    return _week(lastDay);
  }

  // The Arena -------------------------------------------------------------------

  /// Your Arena votes: (day, first id, second id, winner id or null).
  final List<(int, String, String, String?)> _arenaVotes = [];

  List<ArenaWinner> _arenaWinners = const [];

  /// The latest decided Arena, like online: crowned the Monday after its
  /// week of votes.
  ArenaRanking? _latestArena;

  @override
  List<ArenaWinner> get arenaWinners => _arenaWinners;

  /// Like online: the latest Arena's winners.
  @override
  Set<String> get arenaRateUp => {for (final winner in _arenaWinners) winner.card.id};

  /// The Arena open on [day]: the last day of the week before; none in the
  /// first week and in speed mode.
  int? _arenaWeek(int day) {
    if (server.isSpeed) return null;
    final week = _days.weekStart(day) - 1;
    return week >= 7 ? week : null;
  }

  /// The Arena of [week]'s challengers: the week's, but its weekly heroes,
  /// in the order of its ranking.
  List<CharacterCard> _arenaChallengers(int week) => [
    for (final (i, r) in _ranked(week - 8, week - 2).indexed)
      if (i >= Finale.maxHeroes) r.card,
  ];

  String _pairKey(String a, String b) => a.compareTo(b) < 0 ? '$a|$b' : '$b|$a';

  /// Every pair you can vote on in the Arena of [week]: none with a drawing
  /// of yours.
  List<(CharacterCard, CharacterCard)> _arenaPairs(int week) {
    final theirs = [
      for (final c in _arenaChallengers(week))
        if (c.artist != you.name) c,
    ];
    return [
      for (var i = 0; i < theirs.length; i++)
        for (var j = i + 1; j < theirs.length; j++) (theirs[i], theirs[j]),
    ];
  }

  ({ArenaStatus status, (CharacterCard, CharacterCard)? matchup})? _arenaState() {
    final week = _arenaWeek(_day);
    if (week == null) return null;
    final pairs = _arenaPairs(week);
    final keys = {for (final (a, b) in pairs) _pairKey(a.id, b.id)};
    final mine = [
      for (final vote in _arenaVotes)
        if (keys.contains(_pairKey(vote.$2, vote.$3))) vote,
    ];
    final cap = Arena.cap(pairs.length - mine.where((v) => v.$1 < _day).length, week + 7 - _day + 1);
    final today = mine.where((v) => v.$1 == _day).length;
    final status = ArenaStatus(
      week: week,
      endsOn: week + 7,
      challengers: _arenaChallengers(week).length,
      votesToday: today,
      cap: cap,
      pack: min(Arena.pack, cap),
      rewarded: _arenaRewarded.contains(_day),
    );
    if (today >= cap) return (status: status, matchup: null);
    // The fewest votes of yours first, like online's fewest votes.
    final counts = <String, int>{};
    for (final (_, a, b, _) in mine) {
      counts[a] = (counts[a] ?? 0) + 1;
      counts[b] = (counts[b] ?? 0) + 1;
    }
    final voted = {for (final (_, a, b, _) in mine) _pairKey(a, b)};
    final left = [
      for (final pair in pairs)
        if (!voted.contains(_pairKey(pair.$1.id, pair.$2.id))) pair,
    ];
    if (left.isEmpty) return (status: status, matchup: null);
    int votes((CharacterCard, CharacterCard) p) => (counts[p.$1.id] ?? 0) + (counts[p.$2.id] ?? 0);
    final next = left.reduce((best, p) => votes(p) < votes(best) ? p : best);
    return (status: status, matchup: (mine.length + _day).isEven ? next : (next.$2, next.$1));
  }

  /// The days your pack earned its stars on.
  final Set<int> _arenaRewarded = {};

  @override
  ArenaStatus? get arena => _arenaState()?.status;

  @override
  Future<ArenaRound> arenaRound() async {
    final state = _arenaState();
    return ArenaRound(status: state?.status, matchup: state?.matchup);
  }

  @override
  Future<ArenaRound> arenaVote(CharacterCard first, CharacterCard second, {CharacterCard? winner}) async {
    final state = _arenaState();
    if (state == null) throw StateError("The Arena isn't open.");
    if (!state.status.canVote) throw StateError("That's all for today.");
    if (_arenaVotes.any((v) => _pairKey(v.$2, v.$3) == _pairKey(first.id, second.id))) {
      throw StateError('You voted on this matchup already.');
    }
    _arenaVotes.add((_day, first.id, second.id, winner?.id));
    if (!state.status.rewarded && state.status.votesToday + 1 >= state.status.pack) {
      _arenaRewarded.add(_day);
      _stars += Arena.packStars;
    }
    notifyListeners();
    return arenaRound();
  }

  /// The Arena of [week], decided: the friends' votes are made up, but the
  /// same every time, and yours count too.
  ArenaRanking _decideArena(int week) {
    final entries = _arenaChallengers(week);
    final scores = <String, double>{};
    final matchups = <String, int>{};
    for (final c in entries) {
      // Six made-up matchups each, won by a hash of its id.
      matchups[c.id] = 6;
      scores[c.id] = (c.id.hashCode % 7).abs().clamp(0, 6).toDouble();
    }
    for (final (_, a, b, winner) in _arenaVotes) {
      if (!scores.containsKey(a) || !scores.containsKey(b)) continue;
      matchups[a] = matchups[a]! + 1;
      matchups[b] = matchups[b]! + 1;
      scores[a] = scores[a]! + (winner == null ? 0.5 : (winner == a ? 1 : 0));
      scores[b] = scores[b]! + (winner == null ? 0.5 : (winner == b ? 1 : 0));
    }
    double share(CharacterCard c) => scores[c.id]! / matchups[c.id]!;
    final order = [...entries.indexed]
      ..sort((x, y) {
        final byShare = share(y.$2).compareTo(share(x.$2));
        return byShare != 0 ? byShare : x.$1.compareTo(y.$1);
      });
    return ArenaRanking(
      week: week,
      endsOn: week + 7,
      challengers: [
        for (final (place, (_, c)) in order.indexed)
          ArenaRanked(
            card: c,
            place: place + 1,
            score: scores[c.id]!,
            matchups: matchups[c.id]!,
            rating: share(c),
            winnerRarity: place < Arena.maxWinners ? Arena.rarities[place] : null,
          ),
      ],
    );
  }

  @override
  Future<ArenaRanking?> arenaRanking({bool refresh = false}) async => _latestArena;

  @override
  Future<PlayerStats?> playerStats(StatPeriod period, {bool refresh = false}) async => _playerStats(period);

  /// Made-up player stats: at random, but the same for a period and day.
  /// Last week's once the first week is over, as the week ranking; this
  /// week's boosts are secret. You lead the Addict streak, as if you never
  /// missed a day, so every week over brings you its trophy to try.
  PlayerStats? _playerStats(StatPeriod period) {
    if (server.isSpeed) return null;
    final weekStart = _days.weekStart(_day);
    final (from, to) = switch (period) {
      StatPeriod.week => (max(weekStart, 1), _day),
      StatPeriod.lastWeek => (max(weekStart - 7, 1), weekStart - 1),
    };
    if (period == StatPeriod.lastWeek && to < 7) return null;
    final portrayed = switch (period) {
      StatPeriod.week => _ranked(weekStart - 2, min(weekStart + 4, _day)),
      StatPeriod.lastWeek => _ranked(weekStart - 9, weekStart - 3),
    };
    final weeksOver = max(0, (weekStart - 1) ~/ 7);
    int roll(int seed, int below) => Random(seed).nextInt(below);
    int value(PlayerStatKind kind, int i) => switch (kind) {
      PlayerStatKind.mostWins => roll(to * 1009 + i * 31 + 1, to - from + 2),
      PlayerStatKind.mostBoosted => roll(to * 1009 + i * 31 + 2, 4 * (to - from + 1) + 1),
      PlayerStatKind.busyStreak => server.players[i].isYou ? to : roll(to * 1009 + i * 31 + 3, to),
    };
    int trophies(PlayerStatKind kind, int i) => kind == PlayerStatKind.busyStreak
        ? (server.players[i].isYou ? weeksOver : 0)
        : roll(i * 7 + kind.index, weeksOver + 1);
    return PlayerStats(
      period: period,
      fromDay: from,
      toDay: to,
      trophyStars: StarRewards.weekStat,
      stats: [
        for (final kind in PlayerStatKind.values)
          if (period == StatPeriod.week && kind == PlayerStatKind.mostBoosted)
            PlayerStat(
              kind: kind,
              secret: true,
              players: [
                for (final (i, player) in server.players.indexed)
                  PlacedPlayer(player: player, value: null, place: null, trophies: trophies(kind, i)),
              ],
            )
          else
            PlayerStat.rank(kind, [
              for (final (i, player) in server.players.indexed) (player, value(kind, i), trophies(kind, i)),
            ]),
      ],
      portrayed: [
        // The challengers fought that week, drawn two days before, so far.
        for (final player in server.players) (player, portrayed.where((c) => c.card.subject == player.name).length),
      ],
    );
  }

  @override
  Future<WeekWinRates?> winRates({bool refresh = false}) async => server.isSpeed ? null : _days.winRates(_day, you);

  List<HurryPlan> _incomingHurries = const [];
  @override
  List<HurryPlan> get incomingHurries => _incomingHurries;

  @override
  Player? get hurrySentTo => _hurrySentTo;
  Player? _hurrySentTo;

  @override
  String? get hurryMessage => _hurryMessage;
  String? _hurryMessage;

  void _startDay() {
    _day++;
    _theme = _days.themeOf(_day);
    _hurrySentTo = null;
    _hurryMessage = null;
    _incomingHurries = promptToDraw == null ? const [] : _days.hurries(_day);
    // A new week: last week's finale crowns its weekly heroes, who join
    // the pool with their new rarities.
    if (!server.isSpeed && _days.weekStart(_day) == _day && _day > 7) {
      final heroes = _week(_day - 1).heroes;
      for (final hero in heroes) {
        _crowned[hero.card.id] = hero.heroRarity!;
        _pool.removeWhere((c) => c.id == hero.card.id);
        _pool.add(_asCrowned(hero.card));
      }
      _weeklyHeroes = [
        for (final hero in heroes)
          WeeklyHero(card: _asCrowned(hero.card), day: _day - 1, stars: hero.stars, place: hero.place),
      ];
      // The Arena voted on last week, of the week before's challengers,
      // crowns its winners too.
      if (_day > 14) {
        final arena = _decideArena(_day - 8);
        _latestArena = arena;
        for (final winner in arena.winners) {
          _crowned[winner.card.id] = winner.winnerRarity!;
          _pool.removeWhere((c) => c.id == winner.card.id);
          _pool.add(_asCrowned(winner.card));
        }
        _arenaWinners = [
          for (final winner in arena.winners)
            ArenaWinner(card: _asCrowned(winner.card), week: arena.week, place: winner.place),
        ];
      }
      // Last week's trophies you won, as gifts on the notification board.
      for (final stat in _playerStats(StatPeriod.lastWeek)?.stats ?? const <PlayerStat>[]) {
        if (!stat.players.any((p) => p.player.isYou && p.first)) continue;
        _gifts.add(
          Gift(
            id: 'trophy-${stat.kind.key}-${_day - 1}',
            message: 'Trophy: ${stat.kind.label} in week ${weekOf(_day - 1)}!',
            pulls: 0,
            stars: StarRewards.weekStat,
            sentAt: DateTime.now(),
          ),
        );
      }
    }
  }

  /// The challengers you drew, boosted or fought, newest first. Yours had
  /// one fight once fought, two days after: the [challengerWins] days' ones
  /// won it.
  @override
  List<ChallengerRecord> get challengers {
    // Like online, only the ones you drew (for now).
    final encountered = <CharacterCard>{..._yourChallengers.values};
    ChallengerRecord record(CharacterCard card) {
      // Fought once, two days after it was drawn; the challengerWins days' ones won.
      final fights = _day > card.day + 2 ? 1 : 0;
      final wins = fights > 0 && challengerWins(card.day) ? 1 : 0;
      // Like online, the artist collects its stars in a fight it won.
      final stars = wins > 0 ? Stars.ofChallenger(_boostStars(card)) : 0;
      final collected = _collectedChallengers.contains(card.id);
      return ChallengerRecord(
        card: card,
        fights: fights,
        wins: wins,
        starsToCollect: collected ? 0 : stars,
        starsCollected: collected ? stars : 0,
      );
    }

    return [for (final card in encountered.toList()..sort((a, b) => b.day.compareTo(a.day))) record(card)];
  }

  /// Your challengers whose stars you collected.
  final Set<String> _collectedChallengers = {};

  /// The achievements whose stars you collected, by key.
  final Set<String> _collectedAchievements = {};

  /// Like online, worked out from your collection and your fights.
  @override
  List<Achievement> get achievements => AchievementRewards.of(
    players: server.players,
    pool: _pool,
    owned: _owned.keys.toSet(),
    fightMargins: [
      for (final day in _yourFights.keys.toList()..sort())
        _yourFights[day]!.fighterTotal - _yourFights[day]!.challengerTotal,
    ],
    collected: _collectedAchievements,
    speed: server.isSpeed,
  );

  @override
  Future<void> collectAchievement(Achievement achievement) async {
    final reached = achievements.where((a) => a.key == achievement.key && a.collectable).firstOrNull;
    if (reached == null) return;
    _collectedAchievements.add(reached.key);
    _stars += reached.stars;
    notifyListeners();
  }

  @override
  Future<void> collectChallengerStars(ChallengerRecord challenger) async {
    final record = challengers.where((r) => r.card.id == challenger.card.id).firstOrNull;
    if (record == null || record.starsToCollect == 0) return;
    _collectedChallengers.add(challenger.card.id);
    _stars += record.starsToCollect;
    notifyListeners();
  }

  /// Like online, the days before today with fights: two days after
  /// friends drew challengers. A speed session plays them all on its
  /// launch date.
  @override
  Future<List<FightDay>> fightDays({bool refresh = false}) async => [
    for (var day = _day - 1; day >= LoopStep.fight; day--)
      if (_drawnOn(day - 2) && (await fightsOn(day)).isNotEmpty)
        FightDay(day: day, date: server.isSpeed ? _days.dateOf(1) : _days.dateOf(day)),
  ];

  /// The fights of [day] you may replay, against the challengers drawn two
  /// days before. Like online, everyone who draws fights, whether they drew that day or
  /// not: you (or chance for you) against the fourth friend's challenger,
  /// and each friend who drew against the next challenger that isn't their
  /// own and nobody fights yet. Without yours, one is fought twice. Like in
  /// the ranking, the challengers drawn on [challengerWins] days won theirs.
  @override
  Future<List<FightSetup>> fightsOn(int day) async {
    if (day >= _day || !_drawnOn(day - 2)) return const [];
    final drawn = day - 2;
    final friendsDrawn = [for (var slot = 0; slot < DemoDays.slots; slot++) _challenger(drawn, slot)];
    final yours = friendsDrawn.last;
    final others = [...friendsDrawn.take(DemoDays.slots - 1), ?_yourChallengers[drawn]];
    final fought = <String>{};
    final fights = [_yourFights[day] ?? _cannedFight(day, yours, you)];
    for (final (i, drew) in friendsDrawn.indexed) {
      final friend = _days.friends.firstWhere((p) => p.name == drew.artist);
      final candidates = [
        for (var k = 0; k < others.length; k++) others[(i + k) % others.length],
      ].where((c) => c.artist != friend.name);
      final challenger = candidates.firstWhere((c) => !fought.contains(c.id), orElse: () => candidates.first);
      fought.add(challenger.id);
      fights.add(_cannedFight(day, challenger, friend));
    }
    // Like online, only yours to replay: the one you picked the fighters for
    // and the ones against your challenger.
    return [
      for (final fight in fights)
        if (fight == _yourFights[day] || fight.challenger.artist == you.name) fight,
    ];
  }

  /// A friend's (or chance's) fighters from the pool against [challenger]:
  /// too weak to beat it if it was drawn on a [challengerWins] day, strong
  /// enough if not.
  FightSetup _cannedFight(int day, CharacterCard challenger, Player owner) {
    final challengerStars = Stars.ofChallenger(_boostStars(challenger));
    final win = !challengerWins(challenger.day);
    final shuffled = [..._pool]..shuffle(Random('${challenger.id}-${owner.id}'.hashCode));
    final order = {for (final (i, c) in shuffled.indexed) c.id: i};
    // Strongest first to win, weakest first to lose.
    final cards = shuffled
      ..sort((a, b) {
        final byStars = win ? b.rarity.stars.compareTo(a.rarity.stars) : a.rarity.stars.compareTo(b.rarity.stars);
        return byStars != 0 ? byStars : order[a.id]!.compareTo(order[b.id]!);
      });
    final team = <CharacterCard>[];
    for (final card in cards) {
      if (team.length == FightSetup.maxFighters) break;
      final stars = Stars.ofTeam(team.map((c) => c.rarity));
      if (win ? stars > challengerStars : team.isNotEmpty && stars + card.rarity.stars > challengerStars) break;
      team.add(card);
    }
    return FightSetup(
      id: 'demo-fight-$day-${owner.id}',
      owner: owner,
      challenger: challenger,
      fighters: [for (final card in team) FighterEntry(card: card)],
      day: day,
      boostStars: _boostStars(challenger),
    );
  }

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

  /// Step 1: choose a person and write their title, for stars; a friend
  /// draws it tomorrow, see [DemoDays.challenger].
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
    _stars += StarRewards.prompt;
    notifyListeners();
  }

  /// Step 2: drawing the challenger adds it to the challengers (not the gacha
  /// pool) as a hero and earns a pull and stars.
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
    _stars += StarRewards.challenger;
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
    if (fighters.any(isResting)) throw ArgumentError('A character rests for a few days after a fight.');
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
      _stars += fight.challengerStars;
    }
    notifyListeners();
  }

  /// Hurries are free, once per day. The target only finds out while drawing.
  @override
  Future<bool> sendHurry(Player target, {String? message}) async {
    if (!canSendHurry || target.isYou) return false;
    _hurrySentTo = target;
    final text = message?.trim() ?? '';
    _hurryMessage = text.isEmpty ? null : text;
    notifyListeners();
    return true;
  }

  // Gacha -----------------------------------------------------------------------

  @override
  Future<List<PullOutcome>> pull(int count, {GachaBanner banner = GachaBanner.standard, bool topUp = false}) async {
    final buy = topUp ? pullsToBuy(count) : 0;
    if (buy * StarRewards.pullPrice > _stars) throw StateError('Not enough stars.');
    if (count > _tickets + buy) throw StateError('Not enough pulls.');
    if (banner == GachaBanner.weekly && rateUp.isEmpty) {
      throw StateError('The weekly banner opens with the first finale.');
    }
    if (banner == GachaBanner.arena && arenaRateUp.isEmpty) {
      throw StateError('The Arena banner opens once an Arena crowns winners.');
    }
    _stars -= buy * StarRewards.pullPrice;
    _tickets += buy;
    _tickets -= count;
    final outcomes = <PullOutcome>[];
    for (var i = 0; i < count; i++) {
      final card = _gacha.pull(_pool, banner: banner, rateUp: banner == GachaBanner.arena ? arenaRateUp : rateUp);
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

/// A suggestion on a mockup feedback board, see [MockGameSession.suggestions].
class _MockSuggestion {
  _MockSuggestion({
    required this.id,
    required this.kind,
    required this.title,
    required this.description,
    required this.author,
    required this.createdAt,
    Set<String>? voters,
  }) : voters = voters ?? {};

  final String id;
  final SuggestionKind kind;
  final String title;
  final String description;
  final String author;
  final DateTime createdAt;

  /// Who upvoted it, by name.
  final Set<String> voters;

  SuggestionStatus status = SuggestionStatus.open;
}

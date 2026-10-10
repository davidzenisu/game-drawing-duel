import '../game/game_session.dart';
import '../game/rules/daily_loop.dart';
import '../game/rules/gacha.dart';
import '../game/rules/models.dart';
import '../game/rules/setup_plan.dart';
import '../game/rules/themes.dart';
import '../game/rules/upgrades.dart';
import 'api_client.dart';
import 'auth_client.dart';
import 'sketch_json.dart';

/// [GameSession] backed by the API and Auth0.
class ApiGameSession extends GameSession {
  ApiGameSession({required ApiClient? api, String? signInProblem})
    : _api = api,
      _signInProblem = api == null ? signInProblem ?? 'Sign-in is not configured.' : signInProblem;

  final ApiClient? _api;

  GamePhase _phase = GamePhase.loading;
  String? _signInProblem;
  String _suggestedFirstName = '';
  Player? _account;
  ServerSession? _server;
  List<DrawingAssignment> _assignments = const [];

  /// Your setup drawings by assignment id.
  Map<String, CharacterCard> _setupDrawings = {};

  List<CharacterCard> _pool = const [];
  List<OwnedCard> _collection = const [];
  int _tickets = 0;
  GachaStatus _gachaStatus = GachaMachine().status;

  /// Sketches by character id. A character never changes, so refreshing
  /// only downloads new ones.
  final Map<String, Sketch> _sketches = {};

  String? _serverNotice;

  /// After a failed sign-in, signing in again must not reuse the old session.
  bool _freshSignInNeeded = false;

  AuthClient get _auth => _api!.auth;

  /// Restores a previous sign-in and loads the player.
  Future<void> start() async {
    if (_api == null) return _setPhase(GamePhase.signIn);
    try {
      final profile = await _auth.restore();
      if (profile == null) return _setPhase(GamePhase.signIn);
      _suggestedFirstName = profile.firstName;
      await _loadPlayer();
    } on SignInRequired catch (error) {
      _requireSignIn(error.message);
    } catch (error) {
      _requireSignIn('Signing in failed: $error');
    }
  }

  /// Back to the sign-in with the reason; the next sign-in is a fresh one.
  void _requireSignIn(String problem) {
    _signInProblem = problem;
    _freshSignInNeeded = true;
    _account = null;
    _server = null;
    _assignments = const [];
    _setupDrawings = {};
    _pool = const [];
    _collection = const [];
    _tickets = 0;
    _setPhase(GamePhase.signIn);
  }

  Future<Object?> _get(String path) => _guard(() => _api!.get(path));

  Future<Object?> _put(String path, Object body) => _guard(() => _api!.put(path, body));

  Future<Object?> _post(String path, [Object? body]) => _guard(() => _api!.post(path, body));

  Future<Object?> _guard(Future<Object?> Function() request) async {
    try {
      return await request();
    } on SignInRequired catch (error) {
      _requireSignIn(error.message);
      rethrow;
    } on ApiException catch (error) {
      // Someone cancelled the server while you were in it.
      if (error.statusCode == 410 && _server != null) await _enterServer(await _get('/servers/${_server!.code}'));
      rethrow;
    }
  }

  Future<void> _loadPlayer() async {
    final Object? me;
    try {
      me = await _get('/me');
    } on ApiException catch (error) {
      if (error.statusCode != 404) rethrow;
      // Signed in, but the account isn't finished yet.
      return _setPhase(GamePhase.signup);
    }
    _setAccount(me);
    await _loadServer();
  }

  void _setAccount(Object? json) {
    if (json is! Map || json['id'] is! String || json['first_name'] is! String) {
      throw const FormatException('Unexpected player response.');
    }
    _account = Player(id: 'player-${json['id']}', name: json['first_name'] as String, isYou: true);
  }

  /// Back to your newest server, or to creating or joining one.
  Future<void> _loadServer() async {
    final servers = await _get('/servers/mine');
    if (servers is! List) throw const FormatException('Unexpected servers response.');
    if (servers.isEmpty) return _setPhase(GamePhase.server);
    await _enterServer(servers.first);
  }

  /// Shows the server's lobby, or your setup once the admin started it.
  Future<void> _enterServer(Object? json) async {
    final server = _parseServer(json);
    _serverNotice = null;
    switch ((json as Map)['phase']) {
      case 'lobby':
        _server = server;
        _setPhase(GamePhase.lobby);
      case 'setup':
        await _loadSetup(server);
        _server = server;
        _setPhase(GamePhase.setup);
      case 'running':
        await _loadPool(server);
        _server = server;
        _setPhase(GamePhase.daily);
      case 'cancelled':
        // Seen: from now on it's no longer one of your servers.
        await _post('/servers/${server.code}/dismiss');
        final by = json['cancelled_by'];
        _leaveServer(by is String ? '$by cancelled server ${server.code}.' : 'Server ${server.code} was cancelled.');
      default:
        throw const FormatException('Unexpected server phase.');
    }
  }

  static String _seatId(int position) => 'seat-$position';

  static int _seatPosition(Player seat) => int.parse(seat.id.substring('seat-'.length));

  /// Every seat becomes a player; yours is marked with `isYou`.
  ServerSession _parseServer(Object? json) {
    if (json is! Map ||
        json['code'] is! String ||
        json['seats'] is! List ||
        json['is_admin'] is! bool ||
        json['is_test'] is! bool ||
        json['phase'] is! String) {
      throw const FormatException('Unexpected server response.');
    }
    final yourPosition = json['your_position'];
    final players = <Player>[];
    final joined = <String>{};
    final setupDone = <String>{};
    for (final seat in json['seats'] as List) {
      if (seat is! Map ||
          seat['position'] is! int ||
          seat['name'] is! String ||
          seat['joined'] is! bool ||
          seat['setup_done'] is! bool) {
        throw const FormatException('Unexpected seat in server response.');
      }
      final position = seat['position'] as int;
      final player = Player(id: _seatId(position), name: seat['name'] as String, isYou: position == yourPosition);
      players.add(player);
      if (seat['joined'] as bool) joined.add(player.id);
      if (seat['setup_done'] as bool) setupDone.add(player.id);
    }
    return ServerSession(
      code: json['code'] as String,
      players: players,
      isAdmin: json['is_admin'] as bool,
      joined: joined,
      isTest: json['is_test'] as bool,
      setupDone: setupDone,
    );
  }

  static String _assignmentId(String id) => 'assignment-$id';

  /// The API's id of [assignment].
  static String _assignmentKey(DrawingAssignment assignment) => assignment.id.substring('assignment-'.length);

  /// Your setup assignments and the drawings you made for them so far.
  Future<void> _loadSetup(ServerSession server) async {
    final json = await _get('/servers/${server.code}/assignments');
    if (json is! List) throw const FormatException('Unexpected assignments response.');
    final assignments = <DrawingAssignment>[];
    final characters = <String, Object?>{};
    for (final item in json) {
      if (item case {
        'id': String id,
        'prompt': String prompt,
        'subject_position': int subject,
        'based_on': String? basedOn,
      }) {
        final assignment = DrawingAssignment(
          id: _assignmentId(id),
          prompt: SetupPrompt.values.asNameMap()[prompt] ?? (throw FormatException('Unknown prompt $prompt.')),
          subject: _seat(server, subject),
          basedOn: basedOn == null ? null : _assignmentId(basedOn),
        );
        assignments.add(assignment);
        if (item['character'] != null) characters[assignment.id] = item['character'];
      } else {
        throw const FormatException('Unexpected assignment in response.');
      }
    }
    final drawings = await Future.wait([
      for (final MapEntry(key: assignmentId, value: character) in characters.entries)
        _loadCharacter(server, character).then((card) => MapEntry(assignmentId, card)),
    ]);
    _assignments = assignments;
    _setupDrawings = Map.fromEntries(drawings);
  }

  static DailyTheme _theme(String name) =>
      DailyTheme.values.asNameMap()[name] ?? (throw FormatException('Unknown theme $name.'));

  /// The pool, your collection and today of a running game.
  Future<void> _loadPool(ServerSession server) async {
    final (pool, collection, gacha, today) = await (
      _get('/servers/${server.code}/pool'),
      _get('/servers/${server.code}/collection'),
      _get('/servers/${server.code}/gacha'),
      _get('/servers/${server.code}/today'),
    ).wait;
    if (pool is! List || collection is! List) throw const FormatException('Unexpected pool response.');
    final cards = await Future.wait([for (final character in pool) _loadCharacter(server, character)]);
    final byId = {for (final card in cards) card.id: card};
    _pool = cards;
    _collection = [
      for (final owned in collection)
        if (owned case {'character': {'id': String id}} when byId.containsKey(id))
          _setOwned(OwnedCard(byId[id]!), owned)
        else
          throw const FormatException('Unexpected character in collection.'),
    ];
    _setGacha(gacha);
    await _setToday(server, today);
  }

  int _day = 0;
  DailyTheme _dayTheme = DailyTheme.forest;
  Player? _promptSubject;
  ChallengerPrompt? _yourPrompt;
  ChallengerPrompt? _promptToDraw;
  CharacterCard? _yourChallenger;
  Set<String> _dayEnded = const {};
  CharacterCard? _fightChallenger;
  Player? _hurrySentTo;
  HurryPlan? _incomingHurry;
  FightSetup? _yourFight;
  List<FightSetup> _fightsToVote = const [];
  List<FightSetup> _results = const [];

  /// A character from the pool, or loaded if it isn't there (yet).
  Future<CharacterCard> _card(ServerSession server, Object? json) async {
    if (json case {'id': String id}) {
      return _pool.where((c) => c.id == id).firstOrNull ?? await _loadCharacter(server, json);
    }
    throw const FormatException('Unexpected character.');
  }

  /// A fight from the API. Your vote is filed under your id; a decided
  /// fight's votes are filed under made-up ids, as only the counts are known.
  Future<FightSetup> _parseFight(ServerSession server, Object? json) async {
    if (json case {
      'id': String id,
      'day': int day,
      'owner_position': int owner,
      'challenger': final challenger,
      'fighters': List fighters,
      'your_vote': bool? yourVote,
      'outcome': final outcome,
    }) {
      final fight = FightSetup(
        id: id,
        owner: _seat(server, owner),
        challenger: await _card(server, challenger),
        fighters: [
          for (final fighter in fighters)
            if (fighter case {'character': final character, 'upgrades': List upgrades, 'element': String? element})
              FighterEntry(
                card: await _card(server, character),
                effects: [
                  for (final effect in upgrades)
                    UpgradeEffect.values.asNameMap()[effect] ?? (throw FormatException('Unknown upgrade $effect.')),
                ],
                element: element == null ? null : ElementKind.values.asNameMap()[element],
              )
            else
              throw const FormatException('Unexpected fighter.'),
        ],
        day: day,
      );
      if (outcome case {'fighter_votes': int forFighters, 'challenger_votes': int forChallenger}) {
        for (var i = 0; i < forFighters + forChallenger; i++) {
          fight.votes['vote-$i'] = i < forFighters;
        }
      } else if (yourVote != null) {
        fight.votes[server.players.firstWhere((p) => p.isYou).id] = yourVote;
      }
      return fight;
    }
    throw const FormatException('Unexpected fight.');
  }

  /// Today's step 1 and 2 from the API; [known] is the challenger you just drew.
  Future<void> _setToday(ServerSession server, Object? json, {Sketch? known}) async {
    if (json case {
      'day': int day,
      'theme': String theme,
      'prompt': {'subject_position': int subject, 'title': String? title},
      'day_ended': List ended,
    }) {
      _day = day;
      _dayTheme = _theme(theme);
      final you = server.players.firstWhere((p) => p.isYou);
      _promptSubject = _seat(server, subject);
      _yourPrompt = title == null
          ? null
          : ChallengerPrompt(
              id: 'prompt-$day-${you.id}',
              author: you,
              subject: _promptSubject!,
              theme: _dayTheme,
              title: title,
              day: day,
            );
      _promptToDraw = null;
      _yourChallenger = null;
      if (json['to_draw'] case {
        'author_position': int author,
        'subject_position': int drawnSubject,
        'title': String drawnTitle,
        'theme': String drawnTheme,
        'premade': bool premade,
        'challenger': final challenger,
      }) {
        _promptToDraw = ChallengerPrompt(
          id: 'prompt-${day - 1}-${_seatId(author)}',
          author: _seat(server, author),
          subject: _seat(server, drawnSubject),
          theme: _theme(drawnTheme),
          title: drawnTitle,
          day: day - 1,
          premade: premade,
        );
        if (challenger != null) _yourChallenger = await _loadCharacter(server, challenger, known: known);
      } else if (json['to_draw'] != null) {
        throw const FormatException('Unexpected prompt to draw.');
      }
      _dayEnded = {for (final position in ended) _seat(server, position as int).id};
      _fightChallenger = null;
      _yourFight = null;
      if (json['fight'] case {'challenger': final challenger, 'yours': final yours}) {
        _fightChallenger = await _card(server, challenger);
        _yourFight = yours == null ? null : await _parseFight(server, yours);
      }
      _fightsToVote = [for (final fight in json['to_vote'] as List? ?? const []) await _parseFight(server, fight)];
      _results = [for (final fight in json['results'] as List? ?? const []) await _parseFight(server, fight)];
      _hurrySentTo = switch (json['hurry_sent_to']) {
        final int position => _seat(server, position),
        _ => null,
      };
      _incomingHurry = switch (json['incoming_hurry']) {
        {'by_position': int by, 'at_fraction': num at, 'cut_seconds': int cut} => HurryPlan(
          by: _seat(server, by).name,
          atFraction: at.toDouble(),
          cut: Duration(seconds: cut),
        ),
        _ => null,
      };
      return;
    }
    throw const FormatException('Unexpected day response.');
  }

  /// Copies, upgrades and element of [owned] from the API's collection entry.
  static OwnedCard _setOwned(OwnedCard owned, Object? json) {
    if (json case {'copies': int copies, 'upgrades': List upgrades, 'element': String? element}) {
      owned
        ..copies = copies
        ..unlocked.clear()
        ..unlocked.addAll([
          for (final effect in upgrades)
            UpgradeEffect.values.asNameMap()[effect] ?? (throw FormatException('Unknown upgrade $effect.')),
        ])
        ..element = element == null
            ? null
            : ElementKind.values.asNameMap()[element] ?? (throw FormatException('Unknown element $element.'));
      return owned;
    }
    throw const FormatException('Unexpected character in collection.');
  }

  void _setGacha(Object? json) {
    if (json case {
      'tickets': int tickets,
      'total_pulls': int totalPulls,
      'pulls_until_legend': int untilLegend,
      'beginner_pulls_left': int? beginnerLeft,
    }) {
      _tickets = tickets;
      _gachaStatus = GachaStatus(
        totalPulls: totalPulls,
        pullsUntilLegend: untilLegend,
        beginnerPullsLeft: beginnerLeft,
      );
    } else {
      throw const FormatException('Unexpected gacha response.');
    }
  }

  static Player _seat(ServerSession server, int position) => server.players.firstWhere(
    (p) => p.id == _seatId(position),
    orElse: () => throw FormatException('Unknown seat $position.'),
  );

  /// A character from the API, with its sketch loaded unless it is [known].
  Future<CharacterCard> _loadCharacter(ServerSession server, Object? json, {Sketch? known}) async {
    if (json case {
      'id': String id,
      'title': String title,
      'rarity': String rarity,
      'prompt': String prompt,
      'artist_position': int artist,
      'subject_position': int subject,
    }) {
      final sketch = _sketches[id] = known ?? _sketches[id] ?? SketchJson.decode(await _get('/characters/$id/sketch'));
      final theme = switch (json['theme']) {
        final String name => _theme(name),
        _ => null,
      };
      return CharacterCard(
        id: id,
        subject: _seat(server, subject).name,
        title: title,
        rarity: Rarity.values.asNameMap()[rarity] ?? (throw FormatException('Unknown rarity $rarity.')),
        prompt: SetupPrompt.values.asNameMap()[prompt]?.label ?? 'Challenger: ${theme?.label ?? ''}',
        artist: _seat(server, artist).name,
        sketch: sketch,
        day: switch (json['day']) {
          final int day => day,
          _ => 0,
        },
        theme: theme,
      );
    }
    throw const FormatException('Unexpected character response.');
  }

  void _setPhase(GamePhase phase) {
    _phase = phase;
    notifyListeners();
  }

  // Implemented --------------------------------------------------------------

  @override
  GamePhase get phase => _phase;

  @override
  bool get isMockup => false;

  @override
  String? get signInProblem => _signInProblem;

  @override
  String get suggestedFirstName => _suggestedFirstName;

  @override
  Player get you =>
      _server?.players.where((p) => p.isYou).firstOrNull ?? _account ?? (throw StateError('Not signed up yet.'));

  @override
  ServerSession get server => _server ?? (throw StateError('Not in a server yet.'));

  @override
  Duration get refreshInterval => const Duration(seconds: 5);

  @override
  Future<void> signIn() async {
    if (_api == null) throw StateError(_signInProblem!);
    await _auth.signIn(fresh: _freshSignInNeeded);
  }

  @override
  Future<void> signOut() async {
    await _auth.signOut();
    _account = null;
    _server = null;
    _assignments = const [];
    _setupDrawings = {};
    _pool = const [];
    _collection = const [];
    _tickets = 0;
    _suggestedFirstName = '';
    _setPhase(GamePhase.signIn);
  }

  @override
  Future<void> signUp(String firstName) async {
    _setAccount(await _put('/me', {'first_name': firstName.trim()}));
    await _loadServer();
  }

  @override
  Future<void> createServer(List<String> otherNames, {bool isTest = false}) async =>
      _enterServer(await _post('/servers', {'other_names': otherNames, 'is_test': isTest}));

  @override
  Future<ServerSession> previewServer(String code) async {
    final json = await _get('/servers/$code');
    if (json is Map && json['phase'] == 'cancelled') throw const ApiException(410, 'This server was cancelled.');
    return _parseServer(json);
  }

  @override
  Future<void> joinServer(ServerSession server, Player seat) async =>
      _enterServer(await _post('/servers/${server.code}/seats/${_seatPosition(seat)}/claim'));

  @override
  String? get serverNotice => _serverNotice;

  @override
  Future<void> refreshServer() async {
    await _enterServer(await _get('/servers/${server.code}'));
  }

  @override
  Future<void> cancelServer() async {
    await _guard(() => _api!.delete('/servers/${server.code}'));
    _leaveServer(null);
  }

  /// Back to creating or joining a server.
  void _leaveServer(String? notice) {
    _server = null;
    _assignments = const [];
    _setupDrawings = {};
    _pool = const [];
    _collection = const [];
    _tickets = 0;
    _serverNotice = notice;
    _setPhase(GamePhase.server);
  }

  @override
  Future<void> startSetup() async => _enterServer(await _post('/servers/${server.code}/setup'));

  @override
  List<DrawingAssignment> get assignments => _assignments;

  @override
  CharacterCard? setupDrawing(DrawingAssignment assignment) => _setupDrawings[assignment.id];

  @override
  Future<void> submitSetupDrawing(DrawingAssignment assignment, Sketch sketch, String title) async {
    final json = await _put('/servers/${server.code}/assignments/${_assignmentKey(assignment)}/drawing', {
      'title': title.trim(),
      'sketch': SketchJson.encode(sketch),
    });
    _setupDrawings[assignment.id] = await _loadCharacter(server, json, known: sketch);
    notifyListeners();
  }

  // Not available yet ------------------------------------------------------------

  @override
  List<String> get suggestedPlayerNames => const [];

  @override
  List<CharacterCard> get pool => _pool;

  @override
  int get tickets => _tickets;

  @override
  GachaStatus get gachaStatus => _gachaStatus;

  @override
  List<OwnedCard> get collection => _collection.toList()
    ..sort((a, b) {
      final byRarity = b.card.rarity.stars.compareTo(a.card.rarity.stars);
      return byRarity != 0 ? byRarity : a.card.subject.compareTo(b.card.subject);
    });

  @override
  int get day => _day;

  @override
  DailyTheme get theme => _dayTheme;

  @override
  Player? get promptSubject => _promptSubject;

  @override
  ChallengerPrompt? get yourPrompt => _yourPrompt;

  @override
  ChallengerPrompt? get promptToDraw => _promptToDraw;

  @override
  CharacterCard? get yourChallenger => _yourChallenger;

  @override
  CharacterCard? get fightChallenger => _fightChallenger;

  @override
  FightSetup? get yourFight => _yourFight;

  @override
  List<FightSetup> get fightsToVote => _fightsToVote;

  @override
  List<FightSetup> get yourFightResults => [
    for (final fight in _results)
      if (fight.owner.isYou) fight,
  ];

  @override
  List<FightSetup> get yourChallengerResults => [
    for (final fight in _results)
      if (fight.challenger.artist == you.name) fight,
  ];

  @override
  HurryPlan? get incomingHurry => _incomingHurry;

  @override
  Player? get hurrySentTo => _hurrySentTo;

  @override
  Future<void> launch() async => _enterServer(await _post('/servers/${server.code}/setup/done'));

  @override
  Future<void> submitPrompt(String title) async {
    await _setToday(server, await _post('/servers/${server.code}/today/prompt', {'title': title.trim()}));
    notifyListeners();
  }

  @override
  /// The challenger joins the pool and earns a pull.
  Future<void> submitChallenger(Sketch sketch) async {
    final json = await _put('/servers/${server.code}/today/challenger', {'sketch': SketchJson.encode(sketch)});
    await _setToday(server, json, known: sketch);
    if (_yourChallenger case final challenger?) _pool = [..._pool, challenger];
    _setGacha(await _get('/servers/${server.code}/gacha'));
    notifyListeners();
  }

  @override
  Future<void> submitFighters(List<OwnedCard> fighters) async {
    final json = await _put('/servers/${server.code}/today/fighters', {
      'character_ids': [for (final owned in fighters) owned.card.id],
    });
    await _setToday(server, json);
    notifyListeners();
  }

  @override
  Future<void> vote(FightSetup fight, {required bool fightersWin}) async {
    final json = await _post('/servers/${server.code}/today/votes/${fight.id}', {'fighters_win': fightersWin});
    // Screens may hold on to the fight they showed.
    fight.votes[you.id] = fightersWin;
    await _setToday(server, json);
    notifyListeners();
  }

  @override
  Future<bool> sendHurry(Player target) async {
    final Object? json;
    try {
      json = await _post('/servers/${server.code}/today/hurry', {'target_position': _seatPosition(target)});
    } on ApiException catch (error) {
      if (error.statusCode == 409) return false;
      rethrow;
    }
    await _setToday(server, json);
    notifyListeners();
    return true;
  }

  @override
  Future<List<PullOutcome>> pull(int count) async {
    final json = await _post('/servers/${server.code}/pulls', {'count': count});
    if (json case {'outcomes': List outcomes, 'gacha': final gacha}) {
      final byId = {for (final card in _pool) card.id: card};
      final results = [
        for (final outcome in outcomes)
          if (outcome case {
            'character': {'id': String id},
            'is_new': bool isNew,
            'copies': int copies,
          } when byId.containsKey(id))
            PullOutcome(card: byId[id]!, isNew: isNew, copies: copies)
          else
            throw const FormatException('Unexpected pull outcome.'),
      ];
      for (final result in results) {
        final owned = _collection.where((o) => o.card.id == result.card.id).firstOrNull;
        if (owned == null) {
          _collection = [..._collection, OwnedCard(result.card)..copies = result.copies];
        } else {
          owned.copies = result.copies;
        }
      }
      _setGacha(gacha);
      notifyListeners();
      return results;
    }
    throw const FormatException('Unexpected pulls response.');
  }

  @override
  Future<void> unlockNextUpgrade(OwnedCard owned, {ElementKind? element}) async {
    final json = await _post('/servers/${server.code}/collection/${owned.card.id}/upgrades', {
      if (element != null) 'element': element.name,
    });
    _setOwned(owned, json);
    notifyListeners();
  }

  @override
  bool get canAdvanceDay => _server?.isTest == true && _server!.isAdmin;

  @override
  Future<void> advanceDay() async {
    await _post('/servers/${server.code}/days/next');
    await refreshDay();
  }

  @override
  bool get canEndDay => _server?.isTest == true;

  @override
  Set<String> get dayEnded => _dayEnded;

  @override
  Future<void> endDay() async {
    await _post('/servers/${server.code}/today/end');
    await refreshDay();
  }

  /// A new day brings new challengers to the pool, so everything reloads.
  @override
  Future<void> refreshDay() async {
    await _loadPool(server);
    notifyListeners();
  }
}

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
///
/// Signing in, signing up, servers and the setup drawings are implemented;
/// the rest of the game arrives step by step and reports [NotAvailableYet]
/// until then.
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
    if (json is! Map || json['id'] is! int || json['first_name'] is! String) {
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

  static String _assignmentId(int id) => 'assignment-$id';

  static int _assignmentNumber(DrawingAssignment assignment) =>
      int.parse(assignment.id.substring('assignment-'.length));

  /// Your setup assignments and the drawings you made for them so far.
  Future<void> _loadSetup(ServerSession server) async {
    final json = await _get('/servers/${server.code}/assignments');
    if (json is! List) throw const FormatException('Unexpected assignments response.');
    final assignments = <DrawingAssignment>[];
    final characters = <String, Object?>{};
    for (final item in json) {
      if (item case {
        'id': int id,
        'prompt': String prompt,
        'subject_position': int subject,
        'based_on': int? basedOn,
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

  /// The pool and your collection of a running game.
  Future<void> _loadPool(ServerSession server) async {
    final (pool, collection) = await (
      _get('/servers/${server.code}/pool'),
      _get('/servers/${server.code}/collection'),
    ).wait;
    if (pool is! List || collection is! List) throw const FormatException('Unexpected pool response.');
    final cards = await Future.wait([for (final character in pool) _loadCharacter(server, character)]);
    final byId = {for (final card in cards) card.id: card};
    _pool = cards;
    _collection = [
      for (final character in collection)
        if (character case {'id': String id} when byId.containsKey(id))
          OwnedCard(byId[id]!)
        else
          throw const FormatException('Unexpected character in collection.'),
    ];
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
      return CharacterCard(
        id: id,
        subject: _seat(server, subject).name,
        title: title,
        rarity: Rarity.values.asNameMap()[rarity] ?? (throw FormatException('Unknown rarity $rarity.')),
        prompt: SetupPrompt.values.asNameMap()[prompt]?.label ?? prompt,
        artist: _seat(server, artist).name,
        sketch: sketch,
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
  Future<ServerSession> previewServer(String code) async => _parseServer(await _get('/servers/$code'));

  @override
  Future<void> joinServer(ServerSession server, Player seat) async =>
      _enterServer(await _post('/servers/${server.code}/seats/${_seatPosition(seat)}/claim'));

  @override
  String? get serverNotice => _serverNotice;

  @override
  Future<void> refreshServer() async {
    final code = server.code;
    final Object? json;
    try {
      json = await _get('/servers/$code');
    } on ApiException catch (error) {
      if (error.statusCode != 404) rethrow;
      return _leaveServer('Server $code was cancelled.');
    }
    await _enterServer(json);
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
    final json = await _put('/servers/${server.code}/assignments/${_assignmentNumber(assignment)}/drawing', {
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
  int get tickets => 0;

  @override
  GachaStatus get gachaStatus => GachaMachine().status;

  @override
  List<OwnedCard> get collection => _collection;

  @override
  int get day => 0;

  @override
  DailyTheme get theme => DailyTheme.forest;

  @override
  Player? get promptSubject => null;

  @override
  ChallengerPrompt? get yourPrompt => null;

  @override
  ChallengerPrompt? get promptToDraw => null;

  @override
  CharacterCard? get yourChallenger => null;

  @override
  CharacterCard? get fightChallenger => null;

  @override
  FightSetup? get yourFight => null;

  @override
  List<FightSetup> get fightsToVote => const [];

  @override
  List<FightSetup> get yourFightResults => const [];

  @override
  List<FightSetup> get yourChallengerResults => const [];

  @override
  HurryPlan? get incomingHurry => null;

  @override
  Player? get hurrySentTo => null;

  @override
  Future<void> launch() async => _enterServer(await _post('/servers/${server.code}/setup/done'));

  @override
  Future<void> submitPrompt(String title) => Future.error(const NotAvailableYet());

  @override
  Future<void> submitChallenger(Sketch sketch) => Future.error(const NotAvailableYet());

  @override
  Future<void> submitFighters(List<OwnedCard> fighters) => Future.error(const NotAvailableYet());

  @override
  Future<void> vote(FightSetup fight, {required bool fightersWin}) => Future.error(const NotAvailableYet());

  @override
  Future<bool> sendHurry(Player target) => Future.error(const NotAvailableYet());

  @override
  Future<List<PullOutcome>> pull(int count) => Future.error(const NotAvailableYet());

  @override
  Future<void> unlockNextUpgrade(OwnedCard owned, {ElementKind? element}) => Future.error(const NotAvailableYet());

  @override
  Future<void> advanceDay() => Future.error(const NotAvailableYet());
}

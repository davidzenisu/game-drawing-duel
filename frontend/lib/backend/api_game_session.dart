import '../game/game_session.dart';
import '../game/rules/daily_loop.dart';
import '../game/rules/gacha.dart';
import '../game/rules/models.dart';
import '../game/rules/setup_plan.dart';
import '../game/rules/themes.dart';
import '../game/rules/upgrades.dart';
import 'api_client.dart';
import 'auth_client.dart';

/// [GameSession] backed by the API and Auth0.
///
/// Signing in, signing up and servers are implemented; the rest of the game
/// arrives step by step and reports [NotAvailableYet] until then.
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

  /// Back to the lobby of your newest server, or to creating or joining one.
  Future<void> _loadServer() async {
    final servers = await _get('/servers/mine');
    if (servers is! List) throw const FormatException('Unexpected servers response.');
    if (servers.isEmpty) return _setPhase(GamePhase.server);
    _server = _parseServer(servers.first);
    _setPhase(GamePhase.lobby);
  }

  static String _seatId(int position) => 'seat-$position';

  static int _seatPosition(Player seat) => int.parse(seat.id.substring('seat-'.length));

  /// Every seat becomes a player; yours is marked with `isYou`.
  ServerSession _parseServer(Object? json) {
    if (json is! Map ||
        json['code'] is! String ||
        json['seats'] is! List ||
        json['is_admin'] is! bool ||
        json['is_test'] is! bool) {
      throw const FormatException('Unexpected server response.');
    }
    final yourPosition = json['your_position'];
    final players = <Player>[];
    final joined = <String>{};
    for (final seat in json['seats'] as List) {
      if (seat is! Map || seat['position'] is! int || seat['name'] is! String || seat['joined'] is! bool) {
        throw const FormatException('Unexpected seat in server response.');
      }
      final position = seat['position'] as int;
      final player = Player(id: _seatId(position), name: seat['name'] as String, isYou: position == yourPosition);
      players.add(player);
      if (seat['joined'] as bool) joined.add(player.id);
    }
    return ServerSession(
      code: json['code'] as String,
      players: players,
      isAdmin: json['is_admin'] as bool,
      joined: joined,
      isTest: json['is_test'] as bool,
    );
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
  Duration get lobbyRefreshInterval => const Duration(seconds: 5);

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
    _suggestedFirstName = '';
    _setPhase(GamePhase.signIn);
  }

  @override
  Future<void> signUp(String firstName) async {
    _setAccount(await _put('/me', {'first_name': firstName.trim()}));
    await _loadServer();
  }

  @override
  Future<void> createServer(List<String> otherNames, {bool isTest = false}) async {
    _server = _parseServer(await _post('/servers', {'other_names': otherNames, 'is_test': isTest}));
    _setPhase(GamePhase.lobby);
  }

  @override
  Future<ServerSession> previewServer(String code) async => _parseServer(await _get('/servers/$code'));

  @override
  Future<void> joinServer(ServerSession server, Player seat) async {
    _server = _parseServer(await _post('/servers/${server.code}/seats/${_seatPosition(seat)}/claim'));
    _setPhase(GamePhase.lobby);
  }

  @override
  Future<void> refreshLobby() async {
    _server = _parseServer(await _get('/servers/${server.code}'));
    notifyListeners();
  }

  // Not available yet ------------------------------------------------------------

  @override
  List<String> get suggestedPlayerNames => const [];

  @override
  List<DrawingAssignment> get assignments => const [];

  @override
  CharacterCard? setupDrawing(DrawingAssignment assignment) => null;

  @override
  List<CharacterCard> get pool => const [];

  @override
  int get tickets => 0;

  @override
  GachaStatus get gachaStatus => GachaMachine().status;

  @override
  List<OwnedCard> get collection => const [];

  @override
  int get day => 0;

  @override
  DailyTheme get theme => DailyTheme.forest;

  @override
  Player get promptSubject => throw const NotAvailableYet();

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
  Future<void> startSetup() => Future.error(const NotAvailableYet());

  @override
  Future<void> submitSetupDrawing(DrawingAssignment assignment, Sketch sketch, String title) =>
      Future.error(const NotAvailableYet());

  @override
  Future<void> launch() => Future.error(const NotAvailableYet());

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

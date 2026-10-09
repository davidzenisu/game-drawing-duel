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
/// Signing in and signing up are implemented; the rest of the game arrives
/// step by step and reports [NotAvailableYet] until then.
class ApiGameSession extends GameSession {
  ApiGameSession({required ApiClient? api, String? signInProblem})
    : _api = api,
      _signInProblem = api == null ? signInProblem ?? 'Sign-in is not configured.' : signInProblem;

  final ApiClient? _api;

  GamePhase _phase = GamePhase.loading;
  String? _signInProblem;
  String _suggestedFirstName = '';
  Player? _you;

  AuthClient get _auth => _api!.auth;

  /// Restores a previous sign-in and loads the player.
  Future<void> start() async {
    if (_api == null) return _setPhase(GamePhase.signIn);
    try {
      final profile = await _auth.restore();
      if (profile == null) return _setPhase(GamePhase.signIn);
      _suggestedFirstName = profile.firstName;
      await _loadPlayer();
    } catch (error) {
      _signInProblem = 'Signing in failed: $error';
      _setPhase(GamePhase.signIn);
    }
  }

  Future<void> _loadPlayer() async {
    try {
      _setPlayer(await _api!.get('/me'));
    } on ApiException catch (error) {
      if (error.statusCode != 404) rethrow;
      // Signed in, but the account isn't finished yet.
      _setPhase(GamePhase.signup);
    }
  }

  void _setPlayer(Object? json) {
    if (json is! Map || json['id'] is! int || json['first_name'] is! String) {
      throw const FormatException('Unexpected player response.');
    }
    _you = Player(id: 'player-${json['id']}', name: json['first_name'] as String, isYou: true);
    _setPhase(GamePhase.server);
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
  Player get you => _you ?? (throw StateError('Not signed up yet.'));

  @override
  Future<void> signIn() async {
    if (_api == null) throw StateError(_signInProblem!);
    await _auth.signIn();
  }

  @override
  Future<void> signUp(String firstName) async {
    _setPlayer(await _api!.put('/me', {'first_name': firstName.trim()}));
  }

  // Not available yet ------------------------------------------------------------

  @override
  ServerSession get server => throw const NotAvailableYet();

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
  Future<void> createServer(List<String> otherNames) => Future.error(const NotAvailableYet());

  @override
  Future<List<Player>> previewServer(String code) => Future.error(const NotAvailableYet());

  @override
  Future<void> joinServer(String code, List<Player> roster, Player seat) => Future.error(const NotAvailableYet());

  @override
  Future<void> refreshLobby() => Future.error(const NotAvailableYet());

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

import 'package:flutter/foundation.dart';

import 'rules/daily_loop.dart';
import 'rules/gacha.dart';
import 'rules/models.dart';
import 'rules/setup_plan.dart';
import 'rules/themes.dart';
import 'rules/upgrades.dart';

enum GamePhase {
  /// Restoring a previous sign-in.
  loading,
  signIn,
  signup,
  server,
  lobby,
  setup,
  daily,
}

/// An action that is part of the game but not implemented by this session yet.
class NotAvailableYet implements Exception {
  const NotAvailableYet();

  @override
  String toString() => "This isn't available yet. Stay tuned!";
}

class ServerSession {
  ServerSession({required this.code, required this.players, required this.isAdmin, required this.joined});

  final String code;
  final List<Player> players;
  final bool isAdmin;

  /// Ids of the players that already joined the server.
  final Set<String> joined;

  bool get everyoneJoined => joined.length == players.length;
}

/// Another player secretly bought a hurry against your next drawing.
class HurryPlan {
  const HurryPlan({required this.by, required this.atFraction, required this.cut});

  final String by;

  /// When the hurry hits, as a fraction of the original time limit.
  final double atFraction;
  final Duration cut;
}

class PullOutcome {
  const PullOutcome({required this.card, required this.isNew, required this.copies});

  final CharacterCard card;
  final bool isNew;
  final int copies;
}

/// Everything the game screens need from a game, wherever it is played.
///
/// State is read synchronously and kept up to date through [notifyListeners].
/// Actions return futures so an implementation can talk to a server; they
/// complete with an error when an action is rejected.
abstract class GameSession extends ChangeNotifier {
  // State --------------------------------------------------------------------

  GamePhase get phase;

  /// Why signing in doesn't work right now, e.g. a missing configuration.
  String? get signInProblem;

  /// First name to prefill on signup, e.g. from the social login.
  String get suggestedFirstName;

  /// The signed-in player. Only available after signing up.
  Player get you;

  /// The server you created or joined. Only available from the lobby on.
  ServerSession get server;

  /// Names to prefill when creating a server.
  List<String> get suggestedPlayerNames;

  /// Your drawings for the initial setup.
  List<DrawingAssignment> get assignments;

  CharacterCard? setupDrawing(DrawingAssignment assignment);

  /// All characters of the server, which the gacha pulls from.
  List<CharacterCard> get pool;

  /// Available gacha pulls.
  int get tickets;

  GachaStatus get gachaStatus;

  /// Your roster, rarest first.
  List<OwnedCard> get collection;

  int get day;

  DailyTheme get theme;

  /// The character you write today's prompt for.
  Player get promptSubject;

  ChallengerPrompt? get yourPrompt;

  /// The prompt you draw today, written by someone else yesterday.
  ChallengerPrompt? get promptToDraw;

  CharacterCard? get yourChallenger;

  /// One randomly selected challenger from yesterday to pick fighters against.
  CharacterCard? get fightChallenger;

  FightSetup? get yourFight;

  /// Yesterday's fights you can vote on (not the ones you're part of).
  List<FightSetup> get fightsToVote;

  /// Finished fights you picked the fighters for (yesterday).
  List<FightSetup> get yourFightResults;

  /// Finished fights against the challenger you drew (two days ago).
  List<FightSetup> get yourChallengerResults;

  HurryPlan? get incomingHurry;

  /// The player you sent today's free hurry to.
  Player? get hurrySentTo;

  /// Whether this is the offline mockup: the other players are simulated,
  /// the day can be ended early and upgrades can be unlocked on credit.
  bool get isMockup;

  // Derived state ------------------------------------------------------------

  List<Player> get otherPlayers => server.players.where((p) => !p.isYou).toList();

  bool isUnlocked(DrawingAssignment assignment) {
    final basedOn = assignment.basedOn;
    return basedOn == null || assignments.any((a) => a.id == basedOn && setupDrawing(a) != null);
  }

  bool get setupComplete => assignments.every((a) => setupDrawing(a) != null);

  bool get challengerDrawn => yourChallenger != null;

  bool hasVoted(FightSetup fight) => fight.votes.containsKey(you.id);

  int get votesLeft => fightsToVote.where((f) => !hasVoted(f)).length;

  /// Whether a step of the daily loop is available today.
  bool stepUnlocked(int step) => day >= step;

  /// Characters with duplicates waiting to be spent on upgrades.
  int get upgradesAvailable => collection.where((o) => o.hasUnspentPoints).length;

  /// Whether there is still something to do on the current day.
  bool get hasOpenSteps =>
      yourPrompt == null ||
      (promptToDraw != null && !challengerDrawn) ||
      (fightChallenger != null && yourFight == null && collection.isNotEmpty) ||
      votesLeft > 0;

  // Actions ------------------------------------------------------------------

  /// Starts signing in, e.g. by redirecting to the login page.
  Future<void> signIn();

  /// Signs out of the account. Not available in the mockup, see [isMockup].
  Future<void> signOut();

  /// Finishes the account by picking a first name.
  Future<void> signUp(String firstName);

  /// Creates a server with a prepopulated roster; the creator is the admin.
  Future<void> createServer(List<String> otherNames);

  /// Looks up a server by its 6-digit code: its roster and who already
  /// joined, so the joining player can claim a free seat.
  Future<ServerSession> previewServer(String code);

  /// Joins [server] (from [previewServer]) as the player at [seat].
  Future<void> joinServer(ServerSession server, Player seat);

  /// How often the lobby refreshes who joined.
  Duration get lobbyRefreshInterval;

  /// Updates who joined the lobby.
  Future<void> refreshLobby();

  Future<void> startSetup();

  Future<void> submitSetupDrawing(DrawingAssignment assignment, Sketch sketch, String title);

  /// Fills the pool with everyone's setup drawings and starts day 1.
  Future<void> launch();

  /// Step 1: write the title prompt for today's theme and character.
  Future<void> submitPrompt(String title);

  /// Step 2: draw the challenger for the prompt you were given.
  Future<void> submitChallenger(Sketch sketch);

  /// Step 3: lock in up to four fighters against today's challenger.
  Future<void> submitFighters(List<OwnedCard> fighters);

  /// Step 4: vote whether the fighters or the challenger would win.
  Future<void> vote(FightSetup fight, {required bool fightersWin});

  /// Sends today's free hurry. Completes with false if it was already used.
  Future<bool> sendHurry(Player target);

  Future<List<PullOutcome>> pull(int count);

  Future<void> unlockNextUpgrade(OwnedCard owned, {ElementKind? element});

  /// Ends the day early. Only available in the mockup, see [isMockup].
  Future<void> advanceDay();
}

import 'dart:math';

import 'package:flutter/foundation.dart';

import 'bot_artist.dart';
import 'duel.dart';
import 'gacha.dart';
import 'models.dart';
import 'setup_plan.dart';
import 'themes.dart';
import 'upgrades.dart';

enum GamePhase { signup, server, lobby, setup, daily }

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

/// In-memory state of the mockup gameplay loop. Nothing is persisted and all
/// other players are simulated locally.
class GameController extends ChangeNotifier {
  GameController({int? seed})
    : _random = Random(seed),
      _bots = BotArtist(seed ?? DateTime.now().microsecondsSinceEpoch),
      gacha = GachaMachine(random: Random(seed));

  /// Pulls every player receives when the server launches.
  static const launchBonus = 10;
  static const hurryCost = 1;

  static const suggestedNames = ['Alex', 'Sam', 'Robin', 'Kim', 'Charlie', 'Jo', 'Mika', 'Toni', 'Lou', 'Nico'];

  final Random _random;
  final BotArtist _bots;
  final GachaMachine gacha;

  GamePhase _phase = GamePhase.signup;
  GamePhase get phase => _phase;

  Player? _you;
  Player get you => _you!;

  ServerSession? _server;
  ServerSession get server => _server!;

  List<DrawingAssignment> _assignments = const [];
  List<DrawingAssignment> get assignments => _assignments;
  final Map<String, CharacterCard> _setupDrawings = {};

  final List<CharacterCard> _pool = [];
  List<CharacterCard> get pool => List.unmodifiable(_pool);

  final Map<String, OwnedCard> _owned = {};

  int _tickets = 0;
  int get tickets => _tickets;

  int _day = 0;
  int get day => _day;
  DailyTheme _theme = DailyTheme.forest;
  DailyTheme get theme => _theme;
  bool _challengerDrawn = false;
  bool get challengerDrawn => _challengerDrawn;
  Player? _challengerSubject;
  Player get challengerSubject => _challengerSubject!;
  HurryPlan? _incomingHurry;
  HurryPlan? get incomingHurry => _incomingHurry;
  bool _duelRewardClaimed = false;
  bool get duelRewardClaimed => _duelRewardClaimed;
  final List<CharacterCard> _todaysChallengers = [];
  List<CharacterCard> get todaysChallengers => List.unmodifiable(_todaysChallengers);
  final Set<String> _hurriedToday = {};
  Set<String> get hurriedToday => Set.unmodifiable(_hurriedToday);
  int _duelsWon = 0;
  int get duelsWon => _duelsWon;
  int _duelsLost = 0;
  int get duelsLost => _duelsLost;

  List<Player> get otherPlayers => server.players.where((p) => !p.isYou).toList();

  // Signup ------------------------------------------------------------------

  void signUp(String firstName) {
    _you = Player(id: 'you', name: firstName.trim(), isYou: true);
    _setPhase(GamePhase.server);
  }

  // Server creation / join ----------------------------------------------------

  /// Creates a server with a prepopulated roster; the creator is the admin.
  void createServer(List<String> otherNames) {
    final players = [you, for (final (i, name) in otherNames.indexed) Player(id: 'p$i', name: name.trim())];
    _server = ServerSession(code: _newCode(), players: players, isAdmin: true, joined: {you.id});
    _setPhase(GamePhase.lobby);
  }

  /// Looks up a (simulated) server by its 6-digit code and returns its roster
  /// so the joining player can claim a seat.
  List<Player> previewServer(String code) {
    final rng = Random(int.parse(code));
    final names = [...suggestedNames]..shuffle(rng);
    final count = SetupPlan.minPlayers + rng.nextInt(SetupPlan.maxPlayers - SetupPlan.minPlayers + 1);
    final roster = [for (var i = 0; i < count; i++) Player(id: 'p$i', name: names[i])];
    // The admin usually knows your name already.
    final seat = 1 + rng.nextInt(count - 1);
    roster[seat] = Player(id: 'p$seat', name: you.name);
    return roster;
  }

  void joinServer(String code, List<Player> roster, Player seat) {
    _you = seat.copyWith(isYou: true);
    final players = [for (final p in roster) p.id == seat.id ? you : p];
    // Everyone listed before you is assumed to have joined already.
    final joined = {for (final p in players.take(players.indexOf(you) + 1)) p.id};
    _server = ServerSession(code: code, players: players, isAdmin: false, joined: joined);
    _setPhase(GamePhase.lobby);
  }

  /// Simulates the next friend joining. Returns false when everyone is in.
  bool simulateNextJoin() {
    final next = server.players.where((p) => !server.joined.contains(p.id)).firstOrNull;
    if (next == null) return false;
    server.joined.add(next.id);
    notifyListeners();
    return true;
  }

  String _newCode() => List.generate(6, (_) => _random.nextInt(10)).join();

  // Initial drawing setup -----------------------------------------------------

  void startSetup() {
    _assignments = SetupPlan.assignmentsFor(server.players, server.players.indexOf(you));
    _setPhase(GamePhase.setup);
  }

  CharacterCard? setupDrawing(DrawingAssignment assignment) => _setupDrawings[assignment.id];

  bool isUnlocked(DrawingAssignment assignment) =>
      assignment.basedOn == null || _setupDrawings.containsKey(assignment.basedOn);

  bool get setupComplete => _assignments.every((a) => _setupDrawings.containsKey(a.id));

  void submitSetupDrawing(DrawingAssignment assignment, Sketch sketch, String title) {
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

  /// Fills the pool with your drawings and everybody else's and starts day 1.
  void launch() {
    final players = server.players;
    for (final (index, artist) in players.indexed) {
      if (artist.isYou) continue;
      for (final assignment in SetupPlan.assignmentsFor(players, index)) {
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
    _tickets += launchBonus;
    _startDay();
    _setPhase(GamePhase.daily);
  }

  // Daily routine ---------------------------------------------------------------

  void _startDay() {
    _day++;
    _theme = DailyTheme.values[(_day - 1) % DailyTheme.values.length];
    _challengerDrawn = false;
    _duelRewardClaimed = false;
    _hurriedToday.clear();
    _todaysChallengers.clear();

    final others = otherPlayers;
    _challengerSubject = others[_random.nextInt(others.length)];
    _incomingHurry = _random.nextDouble() < 0.6
        ? HurryPlan(
            by: others[_random.nextInt(others.length)].name,
            atFraction: 0.25 + _random.nextDouble() * 0.35,
            cut: const Duration(seconds: 30),
          )
        : null;

    // The simulated players already drew their challengers for today.
    for (final artist in others) {
      final candidates = server.players.where((p) => p.id != artist.id).toList();
      final subject = candidates[_random.nextInt(candidates.length)];
      final card = CharacterCard(
        id: 'day$_day-${artist.id}',
        subject: subject.name,
        title: _bots.title(),
        rarity: Rarity.hero,
        prompt: 'Challenger: ${_theme.prompt}',
        artist: artist.name,
        sketch: _bots.doodle('challenger'),
        day: _day,
      );
      _todaysChallengers.add(card);
      _pool.add(card);
    }
  }

  void nextDay() {
    _startDay();
    notifyListeners();
  }

  /// Drawing today's challenger adds it to the pool as a hero and earns a pull.
  void submitChallenger(Sketch sketch, String title) {
    if (_challengerDrawn) return;
    _pool.add(
      CharacterCard(
        id: 'day$_day-${you.id}',
        subject: challengerSubject.name,
        title: title,
        rarity: Rarity.hero,
        prompt: 'Challenger: ${_theme.prompt}',
        artist: you.name,
        sketch: sketch,
        day: _day,
      ),
    );
    _challengerDrawn = true;
    _tickets++;
    notifyListeners();
  }

  /// Spends a pull to cut another player's drawing time. They only find out
  /// while drawing.
  bool sendHurry(Player target) {
    if (_tickets < hurryCost || _hurriedToday.contains(target.id)) return false;
    _tickets -= hurryCost;
    _hurriedToday.add(target.id);
    notifyListeners();
    return true;
  }

  // Gacha -----------------------------------------------------------------------

  List<PullOutcome> pull(int count) {
    if (count > _tickets) throw StateError('Not enough pulls.');
    _tickets -= count;
    final outcomes = <PullOutcome>[];
    for (var i = 0; i < count; i++) {
      final card = gacha.pull(_pool);
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

  List<OwnedCard> get collection {
    final cards = _owned.values.toList()
      ..sort((a, b) {
        final byRarity = b.card.rarity.stars.compareTo(a.card.rarity.stars);
        return byRarity != 0 ? byRarity : a.card.subject.compareTo(b.card.subject);
      });
    return cards;
  }

  int get upgradesAvailable => _owned.values.where((o) => o.canUpgrade).length;

  void unlockNextUpgrade(OwnedCard owned, {ElementKind? element}) {
    final next = owned.nextUpgrade;
    if (!owned.canUpgrade || next == null) return;
    if (next == UpgradeEffect.element) {
      if (element == null) throw ArgumentError('Choose an element for this upgrade.');
      owned.element = element;
    }
    owned.unlocked.add(next);
    notifyListeners();
  }

  // Duels -----------------------------------------------------------------------

  DuelResult duel(OwnedCard fighter, CharacterCard opponent) => Duel.simulate(
    FighterStats.of(fighter.card.rarity, upgrades: fighter.unlocked.length),
    FighterStats.of(opponent.rarity),
    random: _random,
  );

  /// Records a finished duel. The first win of the day earns a bonus pull.
  bool recordDuel(DuelResult result) {
    var rewarded = false;
    if (result.leftWins) {
      _duelsWon++;
      if (!_duelRewardClaimed) {
        _duelRewardClaimed = true;
        _tickets++;
        rewarded = true;
      }
    } else {
      _duelsLost++;
    }
    notifyListeners();
    return rewarded;
  }

  void _setPhase(GamePhase phase) {
    _phase = phase;
    notifyListeners();
  }
}

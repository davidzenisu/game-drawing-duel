import 'dart:math';

import 'package:flutter/foundation.dart';

import 'bot_artist.dart';
import 'daily_loop.dart';
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
  /// Every artist's setup drawings also land in their own roster.
  void launch() {
    final players = server.players;
    for (final (index, artist) in players.indexed) {
      if (artist.isYou) continue;
      final roster = _botRosters[artist.id] = [];
      for (final assignment in SetupPlan.assignmentsFor(players, index)) {
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
    _tickets += launchBonus;
    _startDay();
    _setPhase(GamePhase.daily);
  }

  // Daily routine ---------------------------------------------------------------
  //
  // Every challenger goes through a 4 day loop, and every day each player
  // works on a different stage of it:
  //   1. write a title prompt for a theme and a character,
  //   2. draw a challenger from a prompt someone wrote the day before,
  //   3. pick up to four fighters against a challenger drawn the day before,
  //   4. vote on the fights the others set up the day before.
  // Afterwards the fights play out and everyone involved sees the outcome.

  static const promptStep = 1;
  static const drawStep = 2;
  static const fightStep = 3;
  static const voteStep = 4;

  /// Prompts per day, in roster order.
  final Map<int, List<ChallengerPrompt>> _prompts = {};

  /// Challengers drawn per day.
  final Map<int, List<CharacterCard>> _challengers = {};

  /// Fights set up per day.
  final Map<int, List<FightSetup>> _fights = {};

  /// Characters in the simulated players' rosters.
  final Map<String, List<CharacterCard>> _botRosters = {};

  /// The character you write today's prompt for.
  Player get promptSubject => _promptSubject!;
  Player? _promptSubject;

  ChallengerPrompt? get yourPrompt => _prompts[_day]?.where((p) => p.author.isYou).firstOrNull;

  /// The prompt you draw today, written by someone else yesterday.
  ChallengerPrompt? get promptToDraw => _promptToDraw;
  ChallengerPrompt? _promptToDraw;

  CharacterCard? get yourChallenger =>
      _challengers[_day]?.where((c) => c.artist == you.name && c.day == _day).firstOrNull;

  bool get challengerDrawn => yourChallenger != null;

  /// One randomly selected challenger from yesterday to pick fighters against.
  CharacterCard? get fightChallenger => _fightChallenger;
  CharacterCard? _fightChallenger;

  FightSetup? get yourFight => _fights[_day]?.where((f) => f.owner.isYou).firstOrNull;

  /// Yesterday's fights you can vote on (not the ones you're part of).
  List<FightSetup> get fightsToVote => [
    for (final fight in _fights[_day - 1] ?? const <FightSetup>[])
      if (!fight.owner.isYou && fight.challenger.artist != you.name) fight,
  ];

  bool hasVoted(FightSetup fight) => fight.votes.containsKey(you.id);

  int get votesLeft => fightsToVote.where((f) => !hasVoted(f)).length;

  /// Finished fights you picked the fighters for (yesterday).
  List<FightSetup> get yourFightResults => [
    for (final fight in _fights[_day - 1] ?? const <FightSetup>[])
      if (fight.owner.isYou) fight,
  ];

  /// Finished fights against the challenger you drew (two days ago).
  List<FightSetup> get yourChallengerResults => [
    for (final fight in _fights[_day - 1] ?? const <FightSetup>[])
      if (fight.challenger.artist == you.name) fight,
  ];

  /// Whether a step of the loop is available today.
  bool stepUnlocked(int step) => _day >= step;

  HurryPlan? _incomingHurry;
  HurryPlan? get incomingHurry => _incomingHurry;

  /// The player you sent today's free hurry to.
  Player? get hurrySentTo => _hurrySentTo;
  Player? _hurrySentTo;

  /// Whether there is still something to do on the current day.
  bool get hasOpenSteps =>
      yourPrompt == null ||
      (_promptToDraw != null && !challengerDrawn) ||
      (_fightChallenger != null && yourFight == null && collection.isNotEmpty) ||
      votesLeft > 0;

  Player _drawerOf(Player author) {
    final players = server.players;
    return players[(players.indexOf(author) + 1) % players.length];
  }

  Player _randomSubject(Player author) {
    final excluded = {author.id, _drawerOf(author).id};
    final candidates = server.players.where((p) => !excluded.contains(p.id)).toList();
    return candidates[_random.nextInt(candidates.length)];
  }

  void _startDay() {
    _day++;
    _theme = DailyTheme.ofDay(_day);
    _hurrySentTo = null;
    final others = otherPlayers;

    // Step 1: everyone writes a prompt for today's theme.
    _promptSubject = _randomSubject(you);
    _prompts[_day] = [
      for (final author in others)
        ChallengerPrompt(
          id: 'prompt$_day-${author.id}',
          author: author,
          subject: _randomSubject(author),
          theme: _theme,
          title: _bots.title(),
          day: _day,
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
    _incomingHurry = _promptToDraw != null && _random.nextDouble() < 0.6
        ? HurryPlan(
            by: others[_random.nextInt(others.length)].name,
            atFraction: 0.25 + _random.nextDouble() * 0.35,
            cut: const Duration(seconds: 30),
          )
        : null;

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

    // Step 4: the simulated players vote on yesterday's fights.
    for (final fight in _fights[_day - 1] ?? const <FightSetup>[]) {
      for (final voter in others) {
        if (voter.id == fight.owner.id) continue;
        fight.votes[voter.id] = _random.nextDouble() < fight.fighterOdds;
      }
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
    _pool.add(card);
  }

  void nextDay() {
    _startDay();
    notifyListeners();
  }

  /// Step 1: write the title prompt for today's theme and character.
  void submitPrompt(String title) {
    if (yourPrompt != null) return;
    _prompts[_day]!.add(
      ChallengerPrompt(
        id: 'prompt$_day-${you.id}',
        author: you,
        subject: promptSubject,
        theme: _theme,
        title: title.trim(),
        day: _day,
      ),
    );
    notifyListeners();
  }

  /// Step 2: drawing the challenger adds it to the pool as a hero and earns a pull.
  void submitChallenger(Sketch sketch) {
    final prompt = _promptToDraw;
    if (prompt == null || challengerDrawn) return;
    _addChallenger(prompt, you, sketch);
    _tickets++;
    notifyListeners();
  }

  /// Step 3: lock in up to four fighters against today's challenger.
  void submitFighters(List<OwnedCard> fighters) {
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

  /// Step 4: vote whether the fighters or the challenger would win.
  void vote(FightSetup fight, {required bool fightersWin}) {
    if (!fightsToVote.contains(fight) || hasVoted(fight)) return;
    fight.votes[you.id] = fightersWin;
    notifyListeners();
  }

  /// Hurries are free, once per day. The target only finds out while drawing.
  bool sendHurry(Player target) {
    if (_hurrySentTo != null || target.isYou) return false;
    _hurrySentTo = target;
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

  void _setPhase(GamePhase phase) {
    _phase = phase;
    notifyListeners();
  }
}

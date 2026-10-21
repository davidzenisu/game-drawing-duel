import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/game/game_session.dart';
import 'package:frontend/game/rules/content.dart';
import 'package:frontend/game/rules/daily_loop.dart';
import 'package:frontend/game/rules/gacha.dart';
import 'package:frontend/game/rules/themes.dart';
import 'package:frontend/mockup/mock_game_session.dart';
import 'package:frontend/game/rules/models.dart';
import 'package:frontend/game/rules/setup_plan.dart';
import 'package:frontend/game/rules/upgrades.dart';

const _doodle = Sketch([
  Stroke(color: Color(0xFF000000), width: 0.01, points: [Offset(0.1, 0.1), Offset(0.9, 0.9)]),
]);

Future<MockGameSession> launchedGame({int seed = 1, DateTime? launchDate}) async {
  final game = MockGameSession(seed: seed, launchDate: launchDate);
  await game.signUp('Pat');
  await game.createServer(['Alex', 'Sam', 'Robin', 'Kim', 'Jo']);
  while (!game.server.everyoneJoined) {
    await game.refreshServer();
  }
  await game.startSetup();
  for (final assignment in game.assignments) {
    await game.submitSetupDrawing(assignment, _doodle, 'Title');
  }
  await game.launch();
  return game;
}

void main() {
  test('creating a server generates a 6-digit code and an admin roster', () async {
    final game = MockGameSession(seed: 1);
    await game.signUp('Pat');
    await game.createServer(['Alex', 'Sam', 'Robin', 'Kim']);
    expect(game.phase, GamePhase.lobby);
    expect(game.server.code, matches(RegExp(r'^\d{6}$')));
    expect(game.server.isAdmin, isTrue);
    expect(game.server.players.first.isYou, isTrue);
    expect(game.server.everyoneJoined, isFalse);
  });

  test('joining a server claims a seat from the prepopulated roster', () async {
    final game = MockGameSession(seed: 1);
    await game.signUp('Pat');
    final preview = await game.previewServer('123456');
    final roster = preview.players;
    expect(roster.length, inInclusiveRange(SetupPlan.minPlayers, SetupPlan.maxPlayers));
    final seat = roster.firstWhere((p) => p.name == 'Pat');
    expect(preview.joined, contains(roster.first.id));
    expect(preview.joined, isNot(contains(seat.id)));
    await game.joinServer(preview, seat);
    expect(game.you.id, seat.id);
    expect(game.server.isAdmin, isFalse);
    expect(game.server.players.where((p) => p.isYou), hasLength(1));
  });

  test('when you joined, the simulated admin starts once everyone is there', () async {
    final game = MockGameSession(seed: 1);
    await game.signUp('Pat');
    final preview = await game.previewServer('123456');
    await game.joinServer(preview, preview.players.firstWhere((p) => p.name == 'Pat'));
    expect(game.server.canStart, isFalse);
    while (game.phase == GamePhase.lobby) {
      await game.refreshServer();
    }
    expect(game.server.everyoneJoined, isTrue);
    expect(game.phase, GamePhase.setup);
    expect(game.assignments, hasLength(SetupPlan.drawingsPerPlayer(game.server.players.length)));
  });

  test('a test session sets up the players who joined with the short prompts', () async {
    final game = MockGameSession(seed: 1);
    await game.signUp('Pat');
    await game.createServer(['Alex', 'Sam', 'Robin', 'Kim'], isTest: true);
    await game.refreshServer();
    expect(game.server.artists.map((p) => p.name), ['Pat', 'Alex']);
    await game.startSetup();
    expect(game.assignments.map((a) => a.prompt), SetupPlan.testPrompts);
    final subjects = game.assignments.map((a) => a.subject.name).toSet();
    expect(subjects, hasLength(3), reason: 'different players');
    expect(subjects, isNot(contains('Pat')));
    for (final assignment in game.assignments) {
      await game.submitSetupDrawing(assignment, _doodle, 'Title');
    }
    await game.launch();
    expect(game.pool, hasLength(2 * SetupPlan.testPrompts.length), reason: 'only Pat and Alex drew');
  });

  test('cancelling the server returns to creating one', () async {
    final game = MockGameSession(seed: 1);
    await game.signUp('Pat');
    await game.createServer(['Alex', 'Sam', 'Robin', 'Kim']);
    await game.startSetup();
    await game.submitSetupDrawing(game.assignments.first, _doodle, 'Basic');
    await game.cancelServer();
    expect(game.phase, GamePhase.server);
    expect(game.assignments, isEmpty);
    await game.createServer(['Alex', 'Sam', 'Robin', 'Kim']);
    await game.startSetup();
    expect(game.setupDrawing(game.assignments.first), isNull, reason: 'a fresh setup');
  });

  test('cancelling a running game throws it away', () async {
    final game = MockGameSession(seed: 1);
    await game.signUp('Pat');
    Future<void> launchGame() async {
      await game.createServer(['Alex', 'Sam', 'Robin', 'Kim'], isTest: true);
      await game.startSetup();
      for (final assignment in game.assignments) {
        await game.submitSetupDrawing(assignment, _doodle, 'Title');
      }
      await game.launch();
    }

    await launchGame();
    final pool = game.pool.length;
    await game.pull(1);
    await game.cancelServer();
    expect(game.phase, GamePhase.server);
    expect(game.pool, isEmpty);
    expect(game.collection, isEmpty);

    await launchGame();
    expect(game.pool, hasLength(pool));
    expect(game.gachaStatus.totalPulls, 0);
  });

  test('during the setup, the simulated friends finish one at a time', () async {
    final game = MockGameSession(seed: 1);
    await game.signUp('Pat');
    await game.createServer(['Alex', 'Sam', 'Robin', 'Kim']);
    await game.startSetup();
    await game.refreshServer();
    await game.refreshServer();
    expect(game.server.setupDone, hasLength(2));
    expect(game.waitingForLaunch, isFalse);
    for (final assignment in game.assignments) {
      await game.submitSetupDrawing(assignment, _doodle, 'Title');
    }
    await game.launch();
    expect(game.server.setupDone, hasLength(5), reason: 'everyone finishes at the launch');
    expect(game.phase, GamePhase.daily);
  });

  test('the alter unlocks after the basic drawing', () async {
    final game = MockGameSession(seed: 1);
    await game.signUp('Pat');
    await game.createServer(['Alex', 'Sam', 'Robin', 'Kim']);
    await game.startSetup();
    final alter = game.assignments.firstWhere((a) => a.prompt == SetupPrompt.alter);
    expect(game.isUnlocked(alter), isFalse);
    await game.submitSetupDrawing(game.assignments.first, _doodle, 'Basic');
    expect(game.isUnlocked(alter), isTrue);
  });

  test('launching fills the pool, the rosters and starts day 1', () async {
    final game = await launchedGame();
    final players = game.server.players.length;
    final launchPool = SetupPlan.poolAtLaunch(players).values.reduce((a, b) => a + b);
    expect(game.phase, GamePhase.daily);
    expect(game.day, 1);
    expect(game.tickets, GachaMachine.launchBonus);
    expect(game.pool, hasLength(launchPool));
    // Your own setup drawings land in your roster.
    expect(game.collection.map((o) => o.card.id), unorderedEquals(game.assignments.map((a) => a.id)));
  });

  test('day 1 only unlocks the prompt step', () async {
    final game = await launchedGame();
    expect(game.yourPrompt, isNull);
    expect(game.promptCandidates.where((p) => p.isYou), isEmpty);
    expect(game.promptToDraw, isNull);
    expect(game.fightChallenger, isNull);
    expect(game.boostTargets, isEmpty);
    await expectLater(game.submitPrompt('Myself', game.you), throwsArgumentError);
    final subject = game.promptCandidates.last;
    await game.submitPrompt('Sunburnt', subject);
    expect(game.yourPrompt?.title, 'Sunburnt');
    expect(game.yourPrompt?.subject, subject);
    expect(game.yourPrompt?.theme, game.promptTheme);
  });

  test('the 4 day loop: prompt, draw, fighters, boost and results', () async {
    final game = await launchedGame();
    final you = game.you;

    // Day 1: write a prompt.
    final hint = game.promptHint;
    await game.submitPrompt('Sunburnt', game.promptCandidates.first);
    expect(game.yourPrompt?.hint, hint);

    // Day 2: draw someone else's prompt from yesterday, with its description.
    await game.advanceDay();
    final toDraw = game.promptToDraw!;
    expect(toDraw.author.isYou, isFalse);
    // The mockup has two descriptions a theme: the others may have none.
    expect(toDraw.question, toDraw.hint == null ? isNull : 'Who is ${toDraw.hint}?');
    expect(toDraw.day, 1);
    expect(toDraw.subject.id, isNot(you.id));
    final tickets = game.tickets;
    await game.submitChallenger(_doodle);
    expect(game.tickets, tickets + 1);
    expect(game.yourChallenger?.title, toDraw.title);
    await game.submitChallenger(_doodle);
    expect(game.tickets, tickets + 1, reason: 'one challenger per day');
    await game.submitPrompt('Day two prompt', game.promptCandidates.first);

    // Day 3: pick up to four fighters against one new challenger.
    await game.advanceDay();
    final challenger = game.fightChallenger!;
    expect(challenger.day, 2);
    expect(challenger.artist, isNot(you.name));
    await expectLater(game.submitFighters(game.collection.take(5).toList()), throwsArgumentError);
    await game.submitFighters(game.collection.take(4).toList());
    expect(game.yourFight?.fighters, hasLength(4));

    // Day 4: boost one of yesterday's challengers, but not the one you drew
    // or the one you fought.
    await game.advanceDay();
    expect(game.yourFightResults, isEmpty, reason: 'decided tomorrow');
    final targets = game.boostTargets;
    expect(targets, isNotEmpty);
    for (final target in targets) {
      expect(target.challenger.artist, isNot(you.name));
      expect(target.challenger.id, isNot(challenger.id));
      expect(target.matchups.every((f) => f.challenger.id == target.challenger.id && !f.owner.isYou), isTrue);
    }
    expect(game.canBoost, isTrue);
    final target = targets.first;
    final boosts = target.matchups.first.boosts;
    await game.boost(target.challenger);
    expect(game.boostedChallengerId, target.challenger.id);
    expect(target.matchups.first.boosts, boosts + 1);
    expect(game.canBoost, isFalse);
    await game.boost(targets.last.challenger);
    expect(game.boostedChallengerId, target.challenger.id, reason: 'once a day');

    // Day 5: the stars decide your fight.
    await game.advanceDay();
    final fight = game.yourFightResults.single;
    expect(fight.fighterStars, Stars.ofTeam(fight.fighters.map((f) => f.card.rarity)));
    expect(fight.fightersWin, fight.fighterStars > Stars.ofChallenger(fight.boosts));
    // Somebody fought the challenger you drew three days ago.
    expect(game.yourChallengerResults, hasLength(1));
    expect(game.yourChallengerResults.first.challenger.day, 2);
  });

  test('challengers stay out of the pool, listed once encountered with their record', () async {
    final game = await launchedGame();
    final pool = game.pool.length;
    await game.submitPrompt('Sunburnt', game.promptCandidates.first);
    await game.advanceDay();
    expect(game.challengers, isEmpty, reason: 'the others drew some, but you met none');
    await game.submitChallenger(_doodle);
    expect(game.pool, hasLength(pool), reason: 'challengers never join the gacha pool');
    expect(game.challengers.single.card, game.yourChallenger);

    // Day 3: fighting one makes it encountered too.
    await game.advanceDay();
    final opponent = game.fightChallenger!;
    expect(game.challengers.map((c) => c.card), isNot(contains(opponent)));
    await game.submitFighters(game.collection.take(2).toList());
    expect(game.challengers.map((c) => c.card), contains(opponent));
    expect(game.challengers.firstWhere((c) => c.card == opponent).winRate, isNull, reason: 'not decided yet');

    // Day 4: boosting one makes it encountered too.
    await game.advanceDay();
    final boosted = game.boostTargets.first.challenger;
    expect(game.challengers.map((c) => c.card), isNot(contains(boosted)));
    await game.boost(boosted);
    expect(game.challengers.map((c) => c.card), contains(boosted));

    // Day 5: your fight is decided.
    await game.advanceDay();
    final fight = game.yourFightResults.single;
    final record = game.challengers.firstWhere((c) => c.card == opponent);
    expect(record.fights, greaterThanOrEqualTo(1));
    expect(record.wins, fight.fightersWin ? lessThan(record.fights) : greaterThanOrEqualTo(1));
    expect(game.pool, hasLength(pool));
  });

  test('characters fight once a week, until Monday, but basic ones every day', () async {
    // A Monday: day 3 is a Wednesday, day 8 the next Monday.
    final game = await launchedGame(launchDate: DateTime.utc(2026, 10, 5, 12));
    await game.advanceDay();
    await game.advanceDay();
    final rare = game.collection.where((o) => o.card.rarity != Rarity.basic).first;
    final basic = game.collection.firstWhere((o) => o.card.rarity == Rarity.basic);
    await game.submitFighters([rare, basic]);
    expect(game.restingCharacterIds, isEmpty, reason: 'they rest from tomorrow on');

    await game.advanceDay();
    expect(game.restingCharacterIds, {rare.card.id});
    expect(game.availableFighters, isNot(contains(rare)));
    expect(game.availableFighters, contains(basic));
    await expectLater(game.submitFighters([rare]), throwsArgumentError);
    await game.submitFighters([basic]);
    expect(game.yourFight, isNotNull);

    for (var day = 5; day <= 8; day++) {
      await game.advanceDay();
    }
    expect(game.restingCharacterIds, isEmpty, reason: 'a new week');
  });

  test('the simulated players write the premade title of their description', () async {
    // A Monday: the prompts of day 1 are for Wednesday's volcano.
    final game = MockGameSession(seed: 1, launchDate: DateTime.utc(2026, 10, 5, 12));
    await game.signUp('Pat');
    await game.createServer(['Alex', 'Sam', 'Robin', 'Kim', 'Jo']);
    while (!game.server.everyoneJoined) {
      await game.refreshServer();
    }
    // Enough for everyone, added before day 1.
    await game.addContent(DailyTheme.volcano, [
      for (var i = 0; i < 6; i++) HintDraft(text: 'a volcano hint $i', premadeTitle: 'Volcano Title $i'),
    ]);
    await game.startSetup();
    for (final assignment in game.assignments) {
      await game.submitSetupDrawing(assignment, _doodle, 'Title');
    }
    await game.launch();
    await game.advanceDay();
    final toDraw = game.promptToDraw!;
    final entry = (await game.contentEntries(DailyTheme.volcano)).firstWhere((e) => e.text == toDraw.hint);
    expect(toDraw.title, entry.premadeTitle);
  });

  test('every description is used once only, then there is none', () async {
    // A Monday: prompts are written for Wednesday's volcano on days 1 and 8.
    final game = await launchedGame(launchDate: DateTime.utc(2026, 10, 5, 12));
    final first = game.promptHint;
    expect(first, isNotNull);
    final seen = <String>{first!};
    for (var day = 2; day <= 8; day++) {
      await game.advanceDay();
      final hint = game.promptHint;
      if (hint != null) expect(seen.add(hint), isTrue, reason: 'day $day: $hint again');
    }
    // Five players, two volcano descriptions: used up on day 1.
    expect(game.promptTheme, DailyTheme.volcano);
    expect(game.promptHint, isNull);
  });

  test('the content screen works on the mockup, from the next day on', () async {
    // A Monday: prompts are written for Wednesday's volcano on days 1 and 8.
    final game = await launchedGame(launchDate: DateTime.utc(2026, 10, 5, 12));
    expect(game.canEditContent, isTrue);
    expect(game.promptTheme, DailyTheme.volcano);
    final hint = game.promptHint;
    for (final entry in await game.contentEntries(DailyTheme.volcano)) {
      await game.retireContent(entry);
    }
    final hints = await game.addContent(DailyTheme.volcano, const [
      HintDraft(text: ' a chili lover ', premadeTitle: ' The Chili King '),
      HintDraft(text: 'A Chili Lover', premadeTitle: 'Another'),
    ]);
    expect((hints.added.single.text, hints.added.single.premadeTitle), ('a chili lover', 'The Chili King'));
    expect(hints.skipped, ['A Chili Lover']);
    await expectLater(
      game.addContent(DailyTheme.volcano, [HintDraft(text: 'long', premadeTitle: 'x' * 61)]),
      throwsArgumentError,
    );
    expect((await game.contentEntries(DailyTheme.volcano)).map((e) => e.text), ['a chili lover']);
    expect(game.promptHint, hint, reason: "today's picks stay");

    for (var day = 2; day <= 9; day++) {
      await game.advanceDay();
      if (day == 8) expect(game.promptHint, 'a chili lover');
    }
    // Drawn on day 9: a simulated player's prompt from day 8. You got the
    // one description, so they had none.
    expect(game.promptToDraw!.hint, isNull);
  });

  test('the theme follows the weekday, with a hint for it', () async {
    // A Friday: the misty jungle, then space on Saturday and the castle on Sunday.
    final game = await launchedGame(launchDate: DateTime.utc(2026, 10, 9, 12));
    expect(game.theme, DailyTheme.jungle);
    expect(game.promptTheme, DailyTheme.castle, reason: "Sunday's, when today's challengers are fought");
    expect(game.promptHint, isNotNull);
    final themes = <DailyTheme>[];
    for (var i = 0; i < 3; i++) {
      await game.advanceDay();
      themes.add(game.theme);
    }
    expect(themes, [DailyTheme.space, DailyTheme.castle, DailyTheme.forest]);
  });

  test('pulls turn duplicates into upgrade points', () async {
    final game = await launchedGame();
    await expectLater(game.pull(1, banner: GachaBanner.weekly), throwsStateError, reason: 'opens with the finale');
    final outcomes = await game.pull(10);
    expect(outcomes, hasLength(10));
    expect(outcomes.any((o) => o.card.rarity == Rarity.legend), isTrue, reason: 'the beginner guarantee');
    expect(game.tickets, 0);
    await expectLater(game.pull(1), throwsStateError);

    while (!game.collection.any((o) => o.hasUnspentPoints)) {
      await game.advanceDay();
      if (game.promptToDraw != null) await game.submitChallenger(_doodle);
      await game.pull(game.tickets);
    }
    final owned = game.collection.firstWhere((o) => o.hasUnspentPoints);
    await game.unlockNextUpgrade(owned);
    expect(owned.unlocked, [UpgradeEffect.shadow]);
  });

  test('the mockup allows every upgrade on credit', () async {
    final game = await launchedGame();
    final owned = game.collection.firstWhere((o) => o.card.rarity == Rarity.adventurer);
    expect(owned.upgradePoints, 0);
    while (owned.nextUpgrade != UpgradeEffect.element) {
      await game.unlockNextUpgrade(owned);
    }
    await expectLater(game.unlockNextUpgrade(owned), throwsArgumentError, reason: 'the element needs a choice');
    await game.unlockNextUpgrade(owned, element: ElementKind.storm);
    while (owned.nextUpgrade != null) {
      await game.unlockNextUpgrade(owned);
    }
    expect(owned.unlocked, owned.path);
    expect(owned.upgradePoints, -29, reason: '1 + 1 + 2 + 3 + 5 + 7 + 10 duplicates on credit');
    expect(game.canUpgrade(owned), isFalse);
    expect(game.upgradesAvailable, 0);
  });

  test('a hurry is free and can be sent once per day', () async {
    final game = await launchedGame();
    final tickets = game.tickets;
    expect(await game.sendHurry(game.otherPlayers.first), isTrue);
    expect(await game.sendHurry(game.otherPlayers.last), isFalse);
    expect(game.tickets, tickets);
    expect(game.hurrySentTo, game.otherPlayers.first);
    await game.advanceDay();
    expect(game.hurrySentTo, isNull);
    expect(game.day, 2);
  });

  test('on Sundays the finale: vote on pairs, the best joins the pool as a hero', () async {
    // A Monday: day 7 is the Sunday of the finale.
    final game = await launchedGame(launchDate: DateTime.utc(2026, 10, 5, 12));
    for (var day = 1; day < 7; day++) {
      expect(game.day, day);
      expect(game.finale, isNull);
      expect(game.weeklyHero, isNull);
      await game.advanceDay();
    }
    final ballot = game.finale!;
    expect(ballot.contenders, greaterThan(2));
    expect(ballot.pairs, greaterThan(0));
    expect(game.hasOpenSteps, isTrue);

    final seen = <String>{};
    for (var pair = game.finale!.pair; pair != null; pair = game.finale!.pair) {
      final (left, right) = pair;
      expect([left.artist, right.artist], isNot(contains(game.you.name)), reason: 'not your own challengers');
      expect(seen.add({left.id, right.id}.toList().join('|')), isTrue, reason: 'every pair once');
      await game.voteFinale(left, right);
      expect(game.finale!.votes, seen.length);
    }
    expect(game.finale!.votes, ballot.pairs);
    expect(game.canVoteFinale, isFalse);

    await game.advanceDay();
    expect(game.finale, isNull);
    final hero = game.weeklyHero!;
    expect(hero.day, 7);
    expect(hero.card.rarity, Rarity.hero);
    expect(hero.stars, greaterThanOrEqualTo(Stars.challengerBase + hero.votes));
    expect(game.pool.map((c) => c.id), contains(hero.card.id));
  });

  test('every challenger has one fight, so all but two can be boosted', () async {
    final game = await launchedGame();
    final players = game.server.players.length;
    for (var day = 1; day < 8; day++) {
      if (day >= LoopStep.boost) {
        final targets = game.boostTargets;
        expect(targets, hasLength(players - 2), reason: 'day $day: all but yours and the one you fought');
        expect(targets.map((t) => t.matchups.length), everyElement(1));
      }
      await game.submitPrompt('Title $day', game.promptCandidates.first);
      if (game.promptToDraw != null) await game.submitChallenger(_doodle);
      if (game.fightChallenger case final challenger?) {
        expect(challenger.artist, isNot(game.you.name));
        await game.submitFighters([game.availableFighters.firstWhere((o) => o.card.rarity == Rarity.basic)]);
      }
      await game.advanceDay();
    }
  });
}

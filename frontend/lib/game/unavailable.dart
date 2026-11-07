import 'game_session.dart';
import 'rules/daily_loop.dart';

/// Why a menu item can't be used right now, shown when its greyed out
/// button is tapped; null when there's no reason to give.
abstract final class Unavailable {
  static const _over = 'The speed session is over: see the final ranking.';

  /// The last day of speed mode on which [step] has something to do: its
  /// day in the loop after the last prompt day.
  static int _lastSpeedDay(int step) => SpeedMode.lastPromptDay + step - LoopStep.prompt;

  static String? _notYet(GameSession c, int step, String what) {
    if (c.sessionOver) return _over;
    if (c.day < step) return '$what starts on day $step.';
    if (c.server.isSpeed && c.day > _lastSpeedDay(step)) {
      return 'No more ${what.toLowerCase()} in this session: speed mode ends it on day ${_lastSpeedDay(step)}.';
    }
    return null;
  }

  static String? prompt(GameSession c) {
    if (c.yourPrompt case final prompt?) return 'Done: you chose ${prompt.subject.name} today.';
    return _notYet(c, LoopStep.prompt, 'Choosing a challenger');
  }

  static String? draw(GameSession c) {
    if (c.challengerDrawn) return "Done: you drew today's challenger.";
    return _notYet(c, LoopStep.draw, 'Drawing') ?? 'Nobody wrote you a prompt to draw today.';
  }

  static String? boost(GameSession c) =>
      _notYet(c, LoopStep.boost, 'Boosting') ?? 'No challengers were drawn yesterday to boost.';

  static String? fight(GameSession c) {
    if (c.yourFight != null) return null;
    return _notYet(c, LoopStep.fight, 'Fighting') ??
        (c.fightChallenger == null
            ? 'No challenger to fight today.'
            : "All your characters fought this week. They're back on Monday.");
  }

  static String? winRates(GameSession c) => c.server.isSpeed ? 'Speed mode has no win rates.' : null;

  static String? fightReplay(GameSession c) => 'Pick your fighters today to watch the fight.';

  static String? weekRanking(GameSession c) => c.server.isSpeed
      ? 'Speed mode ranks all of its challengers at the end instead.'
      : 'The first ranking comes once the first week is over, on Monday.';

  static String? hurry(GameSession c) {
    if (c.hurrySentTo case final target?) return "Done: you sent today's hurry to ${target.name}.";
    if (c.sessionOver) return _over;
    return 'Nobody draws a challenger tomorrow: speed mode\'s last drawings are on day ${_lastSpeedDay(LoopStep.draw)}.';
  }
}

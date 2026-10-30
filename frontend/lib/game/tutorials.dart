import 'package:flutter/material.dart';

import 'game_session.dart';
import 'rules/daily_loop.dart';
import 'rules/gacha.dart';
import 'rules/models.dart';
import 'rules/upgrades.dart';

/// A page of a [Tutorial].
class TutorialPage {
  const TutorialPage({required this.icon, required this.title, required this.text});

  final IconData icon;
  final String title;
  final String text;
}

String _stars(int count) => '★' * count;

/// Short intros to the parts of the game, shown the first time a player
/// reaches each one and replayable from "How to play". Which ones a player
/// saw is stored with their account under [key], see
/// [GameSession.tutorialsSeen].
enum Tutorial {
  welcome('welcome', 'Welcome', Icons.waving_hand_rounded),
  prompt('prompt', 'Choosing a challenger', Icons.edit_note_rounded),
  draw('draw', 'Drawing a challenger', Icons.brush_rounded),
  boost('boost', 'Boosting challengers', Icons.keyboard_double_arrow_up_rounded),
  fight('fight', 'Fights and results', Icons.groups_rounded),
  finale('finale', 'The weekly finale', Icons.how_to_vote_rounded),
  gacha('gacha', 'Summoning', Icons.auto_awesome_rounded),
  upgrades('upgrades', 'Duplicates and upgrades', Icons.collections_rounded);

  const Tutorial(this.key, this.title, this.icon);

  /// Stored with the account once seen; lowercase letters, digits and dashes.
  final String key;
  final String title;
  final IconData icon;

  List<TutorialPage> get pages => switch (this) {
    welcome => const [
      TutorialPage(
        icon: Icons.today_rounded,
        title: 'A few minutes a day',
        text:
            'Every day you write a challenger title for a friend, draw the one someone wrote for you, '
            'boost a few of yesterday\'s challengers and send fighters against another. New steps unlock '
            'over the first days.',
      ),
      TutorialPage(
        icon: Icons.star_rounded,
        title: 'Stars decide the fights',
        text:
            'Your fighters\' stars against the challenger\'s and the boosts it got the day before. You see '
            'the result as soon as you lock in your fighters.',
      ),
      TutorialPage(
        icon: Icons.auto_awesome_rounded,
        title: 'Pull and collect',
        text:
            'Drawing a challenger earns a pull. The gacha pool holds everyone\'s setup drawings and the '
            'weekly heroes. Open "How to play" any time to see these intros again.',
      ),
    ],
    prompt => [
      const TutorialPage(
        icon: Icons.person_search_rounded,
        title: 'Who fits best?',
        text:
            'You get a description, e.g. "Who is a sauna regular?". Choose the friend who fits it best: '
            'anyone but you, and others may choose the same one.',
      ),
      TutorialPage(
        icon: Icons.title_rounded,
        title: 'Give them a title',
        text:
            'Up to ${CharacterCard.maxTitleLength} characters. Tomorrow the next player draws your '
            'challenger. If you skip, a premade title stands in.',
      ),
    ],
    draw => [
      TutorialPage(
        icon: Icons.timer_rounded,
        title:
            '${challengerDrawTime.inMinutes}:${(challengerDrawTime.inSeconds % 60).toString().padLeft(2, '0')} to draw',
        text:
            'Draw the title someone wrote for you yesterday. It becomes a ${_stars(Stars.challengerBase)} '
            'challenger for the others to fight, and earns you a pull.',
      ),
      TutorialPage(
        icon: Icons.bolt_rounded,
        title: 'Watch out for hurries',
        text:
            'Once a day every player can send a free hurry. When it hits, it takes '
            '${(HurryPlan.cutFraction * 100).round()}% of the time left, and you only find out while drawing. '
            'Send yours from the hub.',
      ),
    ],
    boost => [
      TutorialPage(
        icon: Icons.keyboard_double_arrow_up_rounded,
        title: 'Boost the challengers',
        text:
            'From day ${LoopStep.boost}, spread ${_stars(Boost.stars)} across up to ${Boost.challengers} of '
            'yesterday\'s challengers, never your own or the one you fight tomorrow. One takes up to '
            '${Boost.maxPerChallenger}.',
      ),
      TutorialPage(
        icon: Icons.shield_rounded,
        title: 'Make them tough',
        text:
            'Boost stars add to a challenger\'s ${_stars(Stars.challengerBase)}, and tomorrow someone fights '
            'it. Move your stars until the day is over; the ones you leave are spread by chance.',
      ),
    ],
    fight => [
      TutorialPage(
        icon: Icons.groups_rounded,
        title: 'Up to ${FightSetup.maxFighters} fighters',
        text:
            'From day ${LoopStep.fight}, send fighters from your collection against a challenger drawn two '
            'days ago. Each brings its rarity\'s stars: '
            '${Rarity.values.map((r) => '${r.label} ${_stars(r.stars)}').join(', ')}.',
      ),
      TutorialPage(
        icon: Icons.balance_rounded,
        title: 'Beat its stars',
        text:
            'You need more stars than the challenger\'s ${_stars(Stars.challengerBase)} plus its boosts, '
            'which stay secret until you lock in; ties go to the challenger. The fight plays out right away.',
      ),
      const TutorialPage(
        icon: Icons.bedtime_rounded,
        title: 'Once a week',
        text:
            'After a fight a character rests until Monday. Basic characters can fight every day, so you '
            'never run out.',
      ),
      const TutorialPage(
        icon: Icons.sports_martial_arts_rounded,
        title: 'Battle results',
        text:
            'Pick nobody and random fighters go for you once the day is over. The next day, watch the fights '
            'in "Battle results": your fighters\' and the ones against the challenger you drew.',
      ),
    ],
    finale => const [
      TutorialPage(
        icon: Icons.emoji_events_rounded,
        title: 'Every Sunday',
        text: 'Every challenger that won a fight this week enters the finale. Pick one of each pair you\'re shown.',
      ),
      TutorialPage(
        icon: Icons.swipe_rounded,
        title: 'Swipe to vote',
        text:
            'Swipe left for the left one, right for the right one, or tap your pick. Each vote adds a star, '
            'and you never vote on your own challengers.',
      ),
      TutorialPage(
        icon: Icons.auto_awesome_rounded,
        title: 'A new hero',
        text: 'On Monday the challenger with the most stars joins the gacha pool as a hero.',
      ),
    ],
    gacha => [
      TutorialPage(
        icon: Icons.confirmation_number_rounded,
        title: 'Pulls',
        text:
            'You start with ${GachaMachine.launchBonus} pulls and earn one for every challenger you draw. '
            'Each pull adds a character of the pool to your collection: the standard banner has the '
            'characters drawn during the setup, the weekly one from the first finale on the whole pool, with '
            'this week\'s hero rated up.',
      ),
      TutorialPage(
        icon: Icons.percent_rounded,
        title: 'Rates and pity',
        text:
            '${Rarity.values.map((r) => '${_stars(r.stars)} ${GachaMachine.rates[r]}%').join(' · ')}. '
            'A ${_stars(Rarity.legend.stars)} is guaranteed within your first ${GachaMachine.beginnerWindow} '
            'pulls on the standard banner, and at the latest every ${GachaMachine.legendPity} pulls on either.',
      ),
    ],
    upgrades => [
      TutorialPage(
        icon: Icons.copy_all_rounded,
        title: 'Duplicates',
        text:
            'Pulling a character you own already gives you a duplicate. Spend them on the next upgrade of '
            'that character in your collection: each one costs more than the last, and the common characters '
            'take the most, up to ${UpgradeTree.costsFor(Rarity.basic).fold(0, (a, b) => a + b)} duplicates to '
            'max out.',
      ),
      TutorialPage(
        icon: Icons.auto_fix_high_rounded,
        title: 'Upgrades',
        text:
            '${UpgradeEffect.values.map((e) => e.label).join(', ')}: each rarity unlocks more of them, in '
            'that order, and for the element you choose fire, ice or storm.',
      ),
    ],
  };
}

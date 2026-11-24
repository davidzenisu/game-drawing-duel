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
  finale('finale', 'The weekly ranking', Icons.emoji_events_rounded),
  arena('arena', 'The Arena', Icons.stadium_rounded),
  gacha('gacha', 'Summoning', Icons.auto_awesome_rounded),
  upgrades('upgrades', 'Duplicates and upgrades', Icons.collections_rounded);

  const Tutorial(this.key, this.title, this.icon);

  /// Stored with the account once seen; lowercase letters, digits and dashes.
  final String key;
  final String title;
  final IconData icon;

  List<TutorialPage> get pages => switch (this) {
    welcome => [
      const TutorialPage(
        icon: Icons.today_rounded,
        title: 'A few minutes a day',
        text:
            'Every day you write a challenger title for a friend, draw the one someone wrote for you, '
            'boost a few of yesterday\'s challengers and send fighters against another. New steps unlock '
            'over the first days.',
      ),
      const TutorialPage(
        icon: Icons.star_rounded,
        title: 'Stars decide the fights',
        text:
            'Your fighters\' stars against the challenger\'s and the boosts it got the day before. You see '
            'the result as soon as you lock in your fighters.',
      ),
      const TutorialPage(
        icon: Icons.auto_awesome_rounded,
        title: 'Pull and collect',
        text:
            'Drawing a challenger earns a pull. The gacha pool holds everyone\'s setup drawings and the '
            'weekly heroes.',
      ),
      TutorialPage(
        icon: Icons.stars_rounded,
        title: 'Earn stars',
        text:
            'Writing a title earns ${StarRewards.prompt} stars, drawing a challenger ${StarRewards.challenger}, '
            'and beating a challenger its stars. Tap your pulls at the top to see yours. Short of pulls when '
            'you summon? Stars top them up, ${StarRewards.pullPrice} stars a pull. Open "How to play" '
            'any time to see these intros again.',
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
            'Up to ${CharacterCard.maxTitleLength} characters, for ${StarRewards.prompt} stars. Tomorrow the '
            'another player, picked at random, draws your challenger. If you skip, a premade title stands in.',
      ),
    ],
    draw => [
      TutorialPage(
        icon: Icons.timer_rounded,
        title:
            '${challengerDrawTime.inMinutes}:${(challengerDrawTime.inSeconds % 60).toString().padLeft(2, '0')} to draw',
        text:
            'Draw the title someone wrote for you yesterday. It becomes a ${_stars(Stars.challengerBase)} '
            'challenger for the others to fight, and earns you a pull and ${StarRewards.challenger} stars. '
            'Skip it, and you can\'t boost tomorrow.',
      ),
      TutorialPage(
        icon: Icons.bolt_rounded,
        title: 'Watch out for hurries',
        text:
            'Once a day every player can send a free hurry. When it hits, it takes '
            '${Hurries.cut.inSeconds}s of the time left, somewhere between ${Hurries.firstLeft.inSeconds}s and ${Hurries.lastLeft.inSeconds}s before the end. '
            'You only find out while drawing. '
            'Send yours from the hub.',
      ),
    ],
    boost => [
      TutorialPage(
        icon: Icons.keyboard_double_arrow_up_rounded,
        title: 'Boost the challengers',
        text:
            'From day ${LoopStep.boost}, spread ${_stars(Boost.stars)} across up to ${Boost.challengers} of '
            'yesterday\'s challengers, never your own or the one you fight tomorrow. One can take them all.',
      ),
      TutorialPage(
        icon: Icons.shield_rounded,
        title: 'Make them tough',
        text:
            'Boost stars add to a challenger\'s ${_stars(Stars.challengerBase)}, and tomorrow someone fights '
            'it. Move your stars until the day is over; the ones you leave are spread by chance.',
      ),
      TutorialPage(
        icon: Icons.balance_rounded,
        title: 'A balance every week',
        text:
            'Each week, the boost stars change with how last week\'s fights went. Heroes winning '
            '${[for (final (share, n) in WeeklyBoost.more) 'more than ${_percent(share)} give +$n ★'].join(', ')}; '
            '${[for (final (share, n) in WeeklyBoost.fewer) 'under ${_percent(share)} −$n ★'].join(', ')}. '
            'It takes ${WeeklyBoost.minFights} fights, and it adds up week after week, between '
            '${WeeklyBoost.minStars} and ${WeeklyBoost.maxStars} ★ a day. The week ranking shows this week\'s.',
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
            'which stay secret until you lock in; ties go to the challenger. The fight plays out right away, '
            'and a win earns a pull (one per challenger star in speed mode) and the challenger\'s stars '
            'as stars of yours, shown under your pulls.',
      ),
      const TutorialPage(
        icon: Icons.bedtime_rounded,
        title: 'Rest days',
        text:
            'After a fight a character rests: a day for a basic one, two for an adventurer, three for a '
            'hero and four for a legend. Their card shows when they\'re back.',
      ),
      const TutorialPage(
        icon: Icons.casino_rounded,
        title: 'Missed a day?',
        text: 'Pick nobody and random fighters go for you once the day is over, but their wins earn nothing.',
      ),
    ],
    finale => const [
      TutorialPage(
        icon: Icons.emoji_events_rounded,
        title: 'Every week',
        text:
            'Once a week is over, its challengers are ranked by their stars: their own and the boost stars '
            'they got.',
      ),
      TutorialPage(
        icon: Icons.auto_awesome_rounded,
        title: 'A new hero',
        text:
            'On Monday the challenger with the most stars joins the gacha pool as a hero. Everyone can see the '
            'whole ranking from the hub.',
      ),
      TutorialPage(
        icon: Icons.people_alt_rounded,
        title: 'Player trophies',
        text:
            'Players are ranked too: Giant Slayer (fights won), Grand Artist (boost stars of your challengers, '
            'secret until the week is over) and Addict (days in a row with every step done). On Monday, every '
            'first place wins a trophy worth '
            '${StarRewards.weekStat} stars.',
      ),
    ],
    arena => [
      const TutorialPage(
        icon: Icons.stadium_rounded,
        title: "Last week's challengers",
        text:
            "Every week, the Arena holds last week's challengers, all but its weekly heroes. Pick the better "
            'drawing of two, whatever their boosts were: drag the card toward it and let go. Can\'t decide? '
            "That's a draw.",
      ),
      TutorialPage(
        icon: Icons.star_rounded,
        title: 'Stars for voting',
        text:
            'Your first ${Arena.pack} votes of a day earn ${Arena.packStars} stars. Keep voting after them if you '
            'like, up to ${Arena.dailyCap} a day while matchups stay for every day\'s stars. You never get a '
            'drawing of your own, '
            'and nobody sees who drew them.',
      ),
      TutorialPage(
        icon: Icons.emoji_events_rounded,
        title: 'Arena winners',
        text:
            "On Monday, the top ${Arena.maxWinners} by everyone's votes become Arena winners: "
            '${[for (final r in Arena.rarities) _stars(r.stars)].join(', ')}. They join the pool, rated up on '
            'the Arena banner for a week; the other challengers leave the Arena.',
      ),
    ],
    gacha => [
      TutorialPage(
        icon: Icons.confirmation_number_rounded,
        title: 'Pulls',
        text:
            'You start with ${GachaMachine.launchBonus} pulls and earn one for every challenger you draw and '
            'every fight you win. '
            'Each pull adds a character of the pool to your collection: the standard banner has the '
            'characters drawn during the setup and every crowned challenger, the weekly one from the first '
            'finale on the whole pool, with this week\'s heroes rated up, and the Arena one the same with the '
            'latest Arena winners.',
      ),
      TutorialPage(
        icon: Icons.percent_rounded,
        title: 'Rates and pity',
        text:
            '${Rarity.values.map((r) => '${_stars(r.stars)} ${GachaMachine.rates[r]}%').join(' · ')}. '
            'A ${_stars(Rarity.legend.stars)} is guaranteed within your first ${GachaMachine.beginnerWindow} '
            'pulls on the standard banner, and at the latest every ${GachaMachine.legendPity} pulls on any.',
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

/// A share as a percentage, e.g. 60%.
String _percent(double share) => '${(share * 100).round()}%';

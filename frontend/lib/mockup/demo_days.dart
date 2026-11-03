import '../game/game_session.dart';
import '../game/rules/daily_loop.dart';
import '../game/rules/models.dart';
import '../game/rules/themes.dart';
import 'bot_artist.dart';

/// The canned days of the mockup's demo game: what your friends wrote, drew
/// and fought is sample data from fixed tables, not a simulation. Every day
/// looks the same whenever it's asked for, and only your own actions (see
/// `MockGameSession`) add to it.
///
/// On day D, friends drew four challengers ("slots" 0 to 3): you boost the
/// first three on D + 1 and fight the fourth on D + 2, the same steps as
/// online without its pairing rules.
class DemoDays {
  DemoDays({required this.players, required this.launchedOn, required this.bots});

  /// The roster, you included.
  final List<Player> players;

  /// The calendar day of day 1, which sets the themes and the weeks.
  final DateTime launchedOn;

  final BotArtist bots;

  static const titles = [
    'Druid of the Delayed 7:42',
    'Lord of the Top Sauna Bench',
    'Brain-Freeze Champion',
    'Explorer of the Sticky Floor',
    'The Nap Emperor',
    'Towel Warlord of Sunbed Row',
    'Smoke Alarm Summoner',
    'Navigator of the Showroom Maze',
    'Baron of the Brunch Table',
    'Ranger of the Dog Park',
    'Windshield Scraper Knight',
    'Astronaut of the Endless Spin',
  ];

  /// The challengers friends draw each day.
  static const slots = 4;

  List<Player> get friends => [
    for (final p in players)
      if (!p.isYou) p,
  ];

  /// The challengers created so far, so each keeps its drawing.
  final Map<String, CharacterCard> _cards = {};

  DailyTheme themeOf(int day) => DailyTheme.ofDate(launchedOn.add(Duration(days: day - 1)));

  /// The first day of [day]'s week, which starts on Monday.
  int weekStart(int day) => day - (launchedOn.add(Duration(days: day - 1)).weekday - DateTime.monday);

  /// The prompt a friend wrote yesterday for you to draw on [day].
  ChallengerPrompt promptToDraw(int day) {
    final author = friends[day % friends.length];
    return ChallengerPrompt(
      id: 'demo-prompt-${day - 1}',
      author: author,
      subject: _subjectFor(author, day),
      theme: themeOf(day + 2),
      title: titles[day % titles.length],
      day: day - 1,
    );
  }

  /// A friend's challenger drawn on [day] in [slot]. Slot 0 is drawn from
  /// [yourPrompt] when you wrote one the day before.
  CharacterCard challenger(int day, int slot, {ChallengerPrompt? yourPrompt}) =>
      _cards.putIfAbsent('demo-challenger-$day-$slot', () {
        final artist = friends[(day + slot) % friends.length];
        final prompt = slot == 0 ? yourPrompt : null;
        return CharacterCard(
          id: 'demo-challenger-$day-$slot',
          subject: prompt?.subject.name ?? _subjectFor(artist, day + slot).name,
          title: prompt?.title ?? titles[(day * slots + slot) % titles.length],
          rarity: Rarity.hero,
          prompt: 'Challenger: ${themeOf(day + 2).label}',
          artist: artist.name,
          sketch: bots.doodle('challenger'),
          day: day,
          theme: themeOf(day + 2),
        );
      });

  /// The boost stars friends gave a challenger: 0 to 4, varying by day and
  /// slot, so some fights are won and some lost. The second one drawn on day
  /// 2, 9, 16… gets 6: one a week, so every week and a speed session have a
  /// clear winner.
  int friendsBoostStars(CharacterCard challenger) {
    final slot = int.tryParse(challenger.id.split('-').last) ?? 0;
    if (slot == 1 && challenger.day % 7 == 2) return 6;
    return (challenger.day + slot) % 5;
  }

  /// Hurries a friend sends you on even days you have something to draw.
  List<HurryPlan> hurries(int day) => [
    if (day.isEven) HurryPlan(by: friends[(day + 1) % friends.length].name, atFraction: 0.4),
  ];

  /// This week's win rates on [day], from last week: none in the first
  /// week, then the same sample table, with you in it.
  WeekWinRates winRates(int day, Player you) {
    final start = weekStart(day);
    final f = friends;
    WinRate rate(Player a, Player b, int fights, int wins) =>
        WinRate(player: a, against: b, fights: fights, wins: wins);
    return WeekWinRates(
      fromDay: start - 7,
      toDay: start - 1,
      rates: start - 7 < 1
          ? const []
          : [
              rate(f[0], f[1], 5, 4),
              rate(f[1], f[0], 5, 1),
              rate(f[2], you, 4, 3),
              rate(you, f[2], 4, 1),
              rate(you, f[3], 3, 2),
              rate(f[3], you, 3, 1),
              rate(f[1], f[2], 2, 2),
              rate(f[2], f[1], 2, 0),
            ],
    );
  }

  /// Someone other than [author] and you to draw, varying with [n].
  Player _subjectFor(Player author, int n) {
    final candidates = friends.where((p) => p.id != author.id).toList();
    return candidates[n % candidates.length];
  }
}

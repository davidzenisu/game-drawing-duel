import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';

import '../rules/gacha.dart';
import '../game_session.dart';
import '../rules/models.dart';
import '../widgets/banner_art.dart';
import '../widgets/card_art.dart';
import '../widgets/game_action.dart';
import '../widgets/themed_background.dart';
import '../widgets/ticket_chip.dart';
import 'pool_screen.dart';
import 'pull_reveal_screen.dart';

/// Pulls on a banner of your choice, swiped through as big banners: the
/// standard one is always there, the weekly one opens with the first finale.
class GachaScreen extends StatefulWidget {
  const GachaScreen({super.key, required this.controller});

  final GameSession controller;

  @override
  State<GachaScreen> createState() => _GachaScreenState();
}

class _GachaScreenState extends State<GachaScreen> {
  GameSession get controller => widget.controller;

  final _pages = PageController(viewportFraction: 0.9);
  int _page = 0;

  /// Three legends of the standard banner, picked at random once.
  List<String> _standardFeatured = const [];

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  bool get _weeklyOpen => controller.rateUp.isNotEmpty;

  /// The open banners first: the weekly one once it's open, otherwise the
  /// standard one, followed by the weekly one locked.
  List<GachaBanner> get _banners =>
      _weeklyOpen ? const [GachaBanner.weekly, GachaBanner.standard] : const [GachaBanner.standard, GachaBanner.weekly];

  GachaBanner get _banner => _banners[_page];

  bool _locked(GachaBanner banner) => banner == GachaBanner.weekly && !_weeklyOpen;

  /// The characters a banner shows off: this week's rate-up, or three of the
  /// standard banner's legends.
  List<CharacterCard> _featured(GachaBanner banner) {
    final pool = banner.poolOf(controller.pool);
    switch (banner) {
      case GachaBanner.weekly:
        return [
          for (final card in pool)
            if (controller.rateUp.contains(card.id)) card,
        ]..sort((a, b) => b.rarity.stars.compareTo(a.rarity.stars));
      case GachaBanner.standard:
        final legends = {
          for (final card in pool)
            if (card.rarity == Rarity.legend) card.id: card,
        };
        if (_standardFeatured.isEmpty || !_standardFeatured.every(legends.containsKey)) {
          _standardFeatured = (legends.keys.toList()..shuffle()).take(3).toList();
        }
        return [for (final id in _standardFeatured) legends[id]!];
    }
  }

  String _caption(GachaBanner banner) {
    if (_locked(banner)) return 'Opens with the first finale';
    final beginner = controller.gachaStatus.beginnerPullsLeft;
    return switch (banner) {
      GachaBanner.standard when beginner != null => '★★★★ guaranteed in your next $beginner pulls',
      GachaBanner.standard => 'The legends of the setup, and everyone they drew',
      GachaBanner.weekly => switch (controller.weeklyHero) {
        final hero? => 'This week\'s hero: ${hero.card.title}',
        null => 'This week\'s rate-up',
      },
    };
  }

  Future<void> _pull(BuildContext context, int count) async {
    final banner = _banner;
    final outcomes = await runGameQuery(context, () => controller.pull(count, banner: banner));
    if (outcomes == null || !context.mounted) return;
    await Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: false,
        transitionDuration: const Duration(milliseconds: 400),
        pageBuilder: (_, _, _) => PullRevealScreen(outcomes: outcomes),
        transitionsBuilder: (_, animation, _, child) => FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final gacha = controller.gachaStatus;
        final textTheme = Theme.of(context).textTheme;
        final banner = _banner;
        final weeklyOpen = _weeklyOpen;
        final canPull = !_locked(banner);
        final pool = banner.poolOf(controller.pool);
        final rates = pool.isEmpty
            ? GachaMachine.rates
            : GachaMachine.tierRates({for (final card in pool) card.rarity});
        return Scaffold(
          appBar: AppBar(
            title: const Text('Summon'),
            actions: [
              TicketChip(tickets: controller.tickets),
              const SizedBox(width: 12),
            ],
          ),
          body: ThemedBackground(
            theme: controller.theme,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        LayoutBuilder(
                          builder: (context, constraints) => SizedBox(
                            height: (constraints.maxWidth * 0.66).clamp(220.0, 320.0),
                            // Swipe with a mouse too, on the web.
                            child: ScrollConfiguration(
                              behavior: ScrollConfiguration.of(
                                context,
                              ).copyWith(dragDevices: PointerDeviceKind.values.toSet()),
                              child: PageView(
                                controller: _pages,
                                onPageChanged: (page) => setState(() => _page = page),
                                children: [
                                  for (final (index, option) in _banners.indexed)
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 6),
                                      child: AnimatedBuilder(
                                        animation: _pages,
                                        builder: (context, _) {
                                          final page = _pages.hasClients && _pages.position.haveDimensions
                                              ? _pages.page!
                                              : _page.toDouble();
                                          return BannerArt(
                                            banner: option,
                                            featured: _locked(option) ? const [] : _featured(option),
                                            caption: _caption(option),
                                            locked: _locked(option),
                                            parallax: page - index,
                                          );
                                        },
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            for (final (index, option) in _banners.indexed)
                              Semantics(
                                button: true,
                                label: '${option.label} banner',
                                child: GestureDetector(
                                  onTap: () => _pages.animateToPage(
                                    index,
                                    duration: const Duration(milliseconds: 350),
                                    curve: Curves.easeOutCubic,
                                  ),
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 250),
                                    margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                                    width: index == _page ? 24 : 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      color: index == _page
                                          ? Theme.of(context).colorScheme.primary
                                          : Theme.of(context).colorScheme.outlineVariant,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        Text(
                          switch (banner) {
                            GachaBanner.standard =>
                              'The characters drawn during the setup.'
                                  '${weeklyOpen ? '' : ' Swipe to see the weekly banner, which opens with the first finale.'}',
                            GachaBanner.weekly when !weeklyOpen =>
                              'The whole pool, weekly heroes included. It opens once the first finale crowns a weekly hero.',
                            GachaBanner.weekly => 'The whole pool, weekly heroes included, with this week\'s rate-up.',
                          },
                          textAlign: TextAlign.center,
                          style: textTheme.bodySmall,
                        ),
                        const SizedBox(height: 16),
                        if (banner == GachaBanner.weekly && weeklyOpen) ...[
                          _RateUpBanner(controller: controller),
                          const SizedBox(height: 16),
                        ],
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Rates', style: textTheme.titleMedium),
                                const SizedBox(height: 8),
                                for (final MapEntry(key: rarity, value: rate) in rates.entries)
                                  Row(
                                    children: [
                                      StarRow(rarity: rarity),
                                      const SizedBox(width: 8),
                                      Text(rarity.label),
                                      const Spacer(),
                                      Text('$rate%'),
                                    ],
                                  ),
                                const Divider(height: 24),
                                if (banner == GachaBanner.standard && gacha.beginnerPullsLeft != null)
                                  Text('★★★★ guaranteed within your next ${gacha.beginnerPullsLeft} standard pulls'),
                                Text('★★★★ guaranteed within ${gacha.pullsUntilLegend} pulls on either banner'),
                                const SizedBox(height: 8),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: TextButton.icon(
                                    onPressed: () => Navigator.of(context).push(
                                      MaterialPageRoute<void>(
                                        builder: (_) => PoolScreen(controller: controller, banner: banner),
                                      ),
                                    ),
                                    icon: const Icon(Icons.visibility_outlined),
                                    label: const Text('See what you can pull'),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: FilledButton.tonalIcon(
                                onPressed: canPull && controller.tickets >= 1 ? () => _pull(context, 1) : null,
                                icon: const Icon(Icons.auto_awesome_outlined),
                                label: const Text('Pull ×1'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: canPull && controller.tickets >= 10 ? () => _pull(context, 10) : null,
                                icon: const Icon(Icons.auto_awesome_rounded),
                                label: const Text('Pull ×10'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// This week's rate-up characters, shown on the weekly banner, with each
/// one's chance per pull.
class _RateUpBanner extends StatelessWidget {
  const _RateUpBanner({required this.controller});

  final GameSession controller;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final rateUp = controller.rateUp;
    final featured = [
      for (final card in controller.pool)
        if (rateUp.contains(card.id)) card,
    ]..sort((a, b) => b.rarity.stars.compareTo(a.rarity.stars));
    final chances = GachaMachine.characterChances(controller.pool, rateUp);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Rate up this week', style: textTheme.titleMedium),
            Text(
              'When a pull lands on their rarity, it\'s one of them ${GachaMachine.rateUp}% of the time, or every '
              'time if they\'re the only one. A new weekly hero takes over every Monday.',
              style: textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            for (final card in featured)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    StarRow(rarity: card.rarity, size: 14),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(card.title, style: textTheme.labelLarge, maxLines: 1, overflow: TextOverflow.ellipsis),
                          Text(card.subject, style: textTheme.labelSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                    Text('${percent(chances[card.id]!)} per pull', style: textTheme.labelMedium),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

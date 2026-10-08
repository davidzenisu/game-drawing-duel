import 'package:flutter/material.dart';

import '../../theme/palette.dart';
import '../logic/game_controller.dart';
import '../logic/models.dart';
import '../logic/upgrades.dart';
import '../widgets/card_art.dart';

class CollectionScreen extends StatefulWidget {
  const CollectionScreen({super.key, required this.controller});

  final GameController controller;

  @override
  State<CollectionScreen> createState() => _CollectionScreenState();
}

class _CollectionScreenState extends State<CollectionScreen> {
  Rarity? _filter;

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final owned = controller.collection.where((o) => _filter == null || o.card.rarity == _filter).toList();
        return Scaffold(
          appBar: AppBar(title: Text('Collection ${controller.collection.length}/${controller.pool.length}')),
          body: Column(
            children: [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  spacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('All'),
                      selected: _filter == null,
                      onSelected: (_) => setState(() => _filter = null),
                    ),
                    for (final rarity in Rarity.values)
                      ChoiceChip(
                        label: Text('${'★' * rarity.stars} ${rarity.label}'),
                        selected: _filter == rarity,
                        onSelected: (_) => setState(() => _filter = rarity),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: owned.isEmpty
                    ? const Center(child: Text('Nothing here yet. Go summon some characters!'))
                    : GridView.builder(
                        padding: const EdgeInsets.all(16),
                        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 170,
                          mainAxisExtent: 270,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                        ),
                        itemCount: owned.length,
                        itemBuilder: (context, index) => _CollectionTile(
                          owned: owned[index],
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => CharacterDetailScreen(controller: controller, owned: owned[index]),
                            ),
                          ),
                        ),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _CollectionTile extends StatelessWidget {
  const _CollectionTile({required this.owned, required this.onTap});

  final OwnedCard owned;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final card = owned.card;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Badge(
        isLabelVisible: owned.canUpgrade,
        label: const Icon(Icons.upgrade_rounded, size: 12, color: Colors.white),
        child: Column(
          children: [
            Hero(
              tag: 'standee-${card.id}',
              child: Standee(card: card, width: 120, effects: owned.unlocked, element: owned.element),
            ),
            const SizedBox(height: 6),
            Nameplate(name: card.subject, title: card.title, rarity: card.rarity, compact: true),
            if (owned.copies > 1) Text('×${owned.copies}', style: Theme.of(context).textTheme.labelSmall),
          ],
        ),
      ),
    );
  }
}

/// A character with its upgrade path (skill tree) unlocked by duplicates.
class CharacterDetailScreen extends StatefulWidget {
  const CharacterDetailScreen({super.key, required this.controller, required this.owned});

  final GameController controller;
  final OwnedCard owned;

  @override
  State<CharacterDetailScreen> createState() => _CharacterDetailScreenState();
}

class _CharacterDetailScreenState extends State<CharacterDetailScreen> {
  ElementKind _element = ElementKind.fire;

  @override
  Widget build(BuildContext context) {
    final owned = widget.owned;
    final card = owned.card;
    final textTheme = Theme.of(context).textTheme;
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) => Scaffold(
        appBar: AppBar(title: Text(card.subject)),
        body: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Center(
              child: Hero(
                tag: 'standee-${card.id}',
                child: Standee(card: card, width: 220, effects: owned.unlocked, element: owned.element),
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Nameplate(name: card.subject, title: card.title, rarity: card.rarity),
                    const SizedBox(height: 8),
                    Text(
                      '${card.prompt} · drawn by ${card.artist} · owned ×${owned.copies}',
                      style: textTheme.bodySmall,
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Text('Upgrades', style: textTheme.titleMedium),
                        const Spacer(),
                        Chip(avatar: const Icon(Icons.upgrade_rounded), label: Text('${owned.upgradePoints} points')),
                      ],
                    ),
                    Text('Every duplicate pull grants one upgrade point.', style: textTheme.bodySmall),
                    const SizedBox(height: 8),
                    for (final (i, effect) in owned.path.indexed) _node(context, effect, i),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _node(BuildContext context, UpgradeEffect effect, int index) {
    final owned = widget.owned;
    final colors = Theme.of(context).colorScheme;
    final unlocked = owned.has(effect);
    final isNext = owned.nextUpgrade == effect;
    final elementLabel = effect == UpgradeEffect.element && owned.element != null ? ' (${owned.element!.name})' : '';
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 40,
            child: Column(
              children: [
                Expanded(
                  child: VerticalDivider(color: index == 0 ? Colors.transparent : colors.outlineVariant, thickness: 2),
                ),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 400),
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: unlocked ? owned.card.rarity.color : colors.surfaceContainerHighest,
                    boxShadow: unlocked ? [BoxShadow(color: owned.card.rarity.color, blurRadius: 10)] : null,
                  ),
                  child: Icon(
                    unlocked ? Icons.check_rounded : Icons.lock_outline_rounded,
                    size: 16,
                    color: unlocked ? Colors.white : null,
                  ),
                ),
                Expanded(
                  child: VerticalDivider(
                    color: index == owned.path.length - 1 ? Colors.transparent : colors.outlineVariant,
                    thickness: 2,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${effect.label}$elementLabel', style: Theme.of(context).textTheme.titleSmall),
                  Text(effect.description, style: Theme.of(context).textTheme.bodySmall),
                  if (isNext) ...[
                    const SizedBox(height: 8),
                    if (effect == UpgradeEffect.element)
                      SegmentedButton<ElementKind>(
                        segments: [
                          for (final element in ElementKind.values)
                            ButtonSegment(
                              value: element,
                              label: Text(element.name),
                              icon: Icon(Icons.circle, size: 12, color: elementColor(element)),
                            ),
                        ],
                        selected: {_element},
                        onSelectionChanged: (selection) => setState(() => _element = selection.first),
                      ),
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      onPressed: owned.canUpgrade
                          ? () => widget.controller.unlockNextUpgrade(owned, element: _element)
                          : null,
                      style: FilledButton.styleFrom(backgroundColor: AppPalette.victory),
                      icon: const Icon(Icons.lock_open_rounded),
                      label: Text(owned.canUpgrade ? 'Unlock (1 point)' : 'Needs a duplicate'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

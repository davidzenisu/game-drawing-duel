import 'package:flutter/material.dart';

import '../../theme/palette.dart';
import '../game_session.dart';
import '../rules/daily_loop.dart';
import '../rules/models.dart';
import '../unavailable.dart';
import 'game_action.dart';

/// The day's free hurry, next to the day's title on the hub: picks a player
/// whose drawing tomorrow gets shorter, then an optional short message they
/// see when it hits. Greyed out once sent, or on a day without one, saying
/// why (and the message sent) when tapped.
class HurryButton extends StatelessWidget {
  const HurryButton({super.key, required this.controller});

  final GameSession controller;

  Future<void> _send(BuildContext context) async {
    final target = await showModalBottomSheet<Player>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(
              title: Text('Send a hurry'),
              subtitle: Text(
                "Free once a day. Their drawing tomorrow gets shorter, and they only find out while drawing.",
              ),
            ),
            for (final player in controller.otherPlayers)
              ListTile(
                leading: CircleAvatar(child: Text(player.name.characters.first)),
                title: Text(player.name),
                trailing: const Icon(Icons.bolt_rounded, color: AppPalette.hurry),
                onTap: () => Navigator.of(context).pop(player),
              ),
          ],
        ),
      ),
    );
    if (target == null || !context.mounted) return;
    final message = await showDialog<String>(
      context: context,
      builder: (_) => HurryMessageDialog(target: target),
    );
    if (message == null || !context.mounted) return;
    final sent = await runGameQuery(context, () => controller.sendHurry(target, message: message));
    if (sent == true && context.mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text('${target.name} will have to hurry. Shh!'), behavior: SnackBarBehavior.floating),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final enabled = controller.canSendHurry;
    final sent = controller.hurrySentTo != null;
    final button = Semantics(
      button: true,
      enabled: enabled,
      child: Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        color: enabled ? colors.surfaceContainerHigh : colors.surfaceContainerHighest,
        elevation: enabled ? 1 : 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: enabled ? BorderSide(color: colors.outlineVariant) : BorderSide.none,
        ),
        child: InkWell(
          onTap: enabled ? () => _send(context) : null,
          child: Opacity(
            opacity: enabled || sent ? 1 : 0.45,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    sent ? Icons.check_circle_rounded : Icons.bolt_rounded,
                    color: sent ? AppPalette.victory : (enabled ? AppPalette.hurry : colors.outline),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      sent ? 'Hurry sent' : 'Send a hurry',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    final reason = Unavailable.hurry(controller);
    if (enabled) return button;
    return Tooltip(
      message: reason,
      triggerMode: TooltipTriggerMode.tap,
      showDuration: const Duration(seconds: 4),
      child: button,
    );
  }
}

/// The optional short message of a hurry to [target], with quick picks that
/// fill it in. Pops with the message (empty for none), or null to cancel.
class HurryMessageDialog extends StatefulWidget {
  const HurryMessageDialog({super.key, required this.target});

  final Player target;

  @override
  State<HurryMessageDialog> createState() => _HurryMessageDialogState();
}

class _HurryMessageDialogState extends State<HurryMessageDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _send() => Navigator.of(context).pop(_controller.text.trim());

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Hurry ${widget.target.name}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Add a short message if you like: ${widget.target.name} sees it when the hurry hits.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              maxLength: Hurries.messageMaxLength,
              textCapitalization: TextCapitalization.sentences,
              onSubmitted: (_) => _send(),
              decoration: const InputDecoration(
                labelText: 'Message (optional)',
                hintText: 'e.g. You can do it 💪',
                border: OutlineInputBorder(),
              ),
            ),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final pick in Hurries.quickMessages)
                  ActionChip(
                    label: Text(pick),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _controller.value = TextEditingValue(
                      text: pick,
                      selection: TextSelection.collapsed(offset: pick.length),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton.icon(onPressed: _send, icon: const Icon(Icons.bolt_rounded), label: const Text('Send')),
      ],
    );
  }
}

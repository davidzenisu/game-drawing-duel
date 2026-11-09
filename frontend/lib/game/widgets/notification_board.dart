import 'package:flutter/material.dart';

import '../../theme/palette.dart';
import '../game_session.dart';
import 'game_action.dart';

/// App bar button opening the notification board; its badge counts the
/// gifts waiting to be accepted.
class NotificationBoardButton extends StatelessWidget {
  const NotificationBoardButton({super.key, required this.session});

  final GameSession session;

  @override
  Widget build(BuildContext context) {
    final waiting = session.gifts.length;
    return IconButton(
      onPressed: () => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => NotificationBoard(session: session),
      ),
      tooltip: waiting == 0 ? 'Notifications' : 'Notifications ($waiting new)',
      icon: Badge(
        isLabelVisible: waiting > 0,
        label: Text('$waiting'),
        child: Icon(waiting > 0 ? Icons.notifications_active_rounded : Icons.notifications_none_rounded),
      ),
    );
  }
}

/// What's new for you: for now the gifts waiting to be accepted, each with
/// its message and pulls. Their pulls count once accepted.
class NotificationBoard extends StatelessWidget {
  const NotificationBoard({super.key, required this.session});

  final GameSession session;

  Future<void> _acceptAll(BuildContext context) async {
    for (final gift in [...session.gifts]) {
      if (!context.mounted || !await runGameAction(context, () => session.acceptGift(gift))) return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        final gifts = session.gifts;
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.75),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 12, 8),
                  child: Row(
                    children: [
                      Expanded(child: Text('Notifications', style: textTheme.titleLarge)),
                      if (gifts.length > 1)
                        TextButton.icon(
                          onPressed: () => _acceptAll(context),
                          icon: const Icon(Icons.done_all_rounded),
                          label: const Text('Accept all'),
                        ),
                    ],
                  ),
                ),
                if (gifts.isEmpty)
                  const Padding(
                    padding: EdgeInsets.fromLTRB(20, 8, 20, 32),
                    child: Text('Nothing new. Gifts and news show up here.', textAlign: TextAlign.center),
                  )
                else
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      itemCount: gifts.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, i) => _GiftCard(session: session, gift: gifts[i]),
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

class _GiftCard extends StatelessWidget {
  const _GiftCard({required this.session, required this.gift});

  final GameSession session;
  final Gift gift;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            const CircleAvatar(
              backgroundColor: AppPalette.ticket,
              foregroundColor: Colors.white,
              child: Icon(Icons.card_giftcard_rounded),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(gift.message, style: textTheme.bodyLarge),
                  const SizedBox(height: 2),
                  Text(
                    '+${gift.pulls} ${gift.pulls == 1 ? 'pull' : 'pulls'}',
                    style: textTheme.labelLarge?.copyWith(color: AppPalette.ticket, fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: () => runGameAction(context, () => session.acceptGift(gift)),
              child: const Text('Accept'),
            ),
          ],
        ),
      ),
    );
  }
}

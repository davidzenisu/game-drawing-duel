import 'package:flutter/material.dart';

import '../../mockup/mockup_shell.dart';
import '../game_session.dart';
import '../screens/content_screen.dart';
import '../screens/drawings_screen.dart';
import '../screens/send_gift_screen.dart';

enum _AdminAction { content, mockup, gift, drawings }

/// App bar menu with what only admins can do, so it stays one button: the
/// game content for content editors; trying the mockup (not inside it) and
/// sending gifts and looking at every drawing for players who manage
/// servers. Players without either
/// permission don't see it.
class AdminMenu extends StatelessWidget {
  const AdminMenu({super.key, required this.session});

  final GameSession session;

  List<_AdminAction> get _actions => [
    if (session.canEditContent) _AdminAction.content,
    if (session.canManageServers && !session.isMockup) _AdminAction.mockup,
    if (session.canManageServers) _AdminAction.gift,
    if (session.canManageServers) _AdminAction.drawings,
  ];

  void _open(BuildContext context, _AdminAction action) {
    final navigator = Navigator.of(context, rootNavigator: action == _AdminAction.mockup);
    navigator.push(
      MaterialPageRoute<void>(
        fullscreenDialog: action == _AdminAction.mockup,
        builder: (_) => switch (action) {
          _AdminAction.content => ContentScreen(controller: session),
          _AdminAction.mockup => const MockupShell(),
          _AdminAction.gift => SendGiftScreen(controller: session),
          _AdminAction.drawings => DrawingsScreen(controller: session),
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final actions = _actions;
    if (actions.isEmpty) return const SizedBox.shrink();
    return PopupMenuButton<_AdminAction>(
      tooltip: 'Admin',
      icon: const Icon(Icons.admin_panel_settings_rounded),
      onSelected: (action) => _open(context, action),
      itemBuilder: (_) => [
        for (final action in actions)
          PopupMenuItem(
            value: action,
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(switch (action) {
                _AdminAction.content => Icons.edit_note_rounded,
                _AdminAction.mockup => Icons.science_rounded,
                _AdminAction.gift => Icons.card_giftcard_rounded,
                _AdminAction.drawings => Icons.photo_library_rounded,
              }),
              title: Text(switch (action) {
                _AdminAction.content => 'Game content',
                _AdminAction.mockup => 'Try the mockup',
                _AdminAction.gift => 'Send a gift',
                _AdminAction.drawings => 'Drawings',
              }),
            ),
          ),
      ],
    );
  }
}

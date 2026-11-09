import 'package:flutter/material.dart';

import '../game_session.dart';
import 'game_action.dart';

enum _AccountAction { rename, signOut }

/// App bar menu for your account: who you're signed in as, changing your
/// name and signing out. Hidden in the mockup, which has no account.
class AccountMenu extends StatelessWidget {
  const AccountMenu({super.key, required this.session});

  final GameSession session;

  Future<void> _rename(BuildContext context) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => RenameDialog(current: session.accountName),
    );
    if (name == null || !context.mounted) return;
    await runGameAction(context, () => session.rename(name));
  }

  @override
  Widget build(BuildContext context) {
    if (session.isMockup) return const SizedBox.shrink();
    return PopupMenuButton<_AccountAction>(
      tooltip: 'Account',
      icon: const Icon(Icons.account_circle_rounded),
      onSelected: (action) => switch (action) {
        _AccountAction.rename => _rename(context),
        _AccountAction.signOut => runGameAction(context, session.signOut),
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          enabled: false,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(session.accountName, style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: const Text('Your account'),
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: _AccountAction.rename,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.edit_rounded),
            title: Text('Change name'),
          ),
        ),
        const PopupMenuItem(
          value: _AccountAction.signOut,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.logout_rounded),
            title: Text('Sign out'),
          ),
        ),
      ],
    );
  }
}

/// Asks for a new name, prefilled with [current]; pops the trimmed name, or
/// nothing when cancelled. [note] says where the name is used.
class RenameDialog extends StatefulWidget {
  const RenameDialog({
    super.key,
    required this.current,
    this.title = 'Change your name',
    this.note = 'Your name on new servers. Servers you already joined keep the name you have there.',
  });

  final String current;
  final String title;
  final String note;

  /// As long as the backend allows.
  static const maxLength = 50;

  @override
  State<RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<RenameDialog> {
  late final _name = TextEditingController(text: widget.current);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  String get _trimmed => _name.text.trim();

  void _save() {
    if (_trimmed.isNotEmpty) Navigator.of(context).pop(_trimmed);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: ListenableBuilder(
        listenable: _name,
        builder: (context, _) => TextField(
          controller: _name,
          autofocus: true,
          maxLength: RenameDialog.maxLength,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            labelText: 'Name',
            helperText: widget.note,
            helperMaxLines: 3,
            border: const OutlineInputBorder(),
          ),
          onSubmitted: (_) => _save(),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        ListenableBuilder(
          listenable: _name,
          builder: (context, _) => FilledButton(onPressed: _trimmed.isEmpty ? null : _save, child: const Text('Save')),
        ),
      ],
    );
  }
}

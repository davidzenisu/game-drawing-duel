import 'package:flutter/material.dart';

import '../game_session.dart';
import '../screens/suggestions_screen.dart';
import 'cancel_server.dart';
import 'game_action.dart';

enum _AccountAction { rename, suggestions, signOut, cancelServer }

/// App bar menu for your account: who you're signed in as, changing your
/// name and signing out (not in the mockup, which has no account to sign
/// out of). On a server, also its feedback board ([suggestions]) and
/// cancelling it ([canCancelServer]).
class AccountMenu extends StatelessWidget {
  const AccountMenu({super.key, required this.session, this.canCancelServer = false, this.suggestions = false});

  final GameSession session;

  /// Whether the menu leads to the feedback board of the server you're on.
  final bool suggestions;

  /// Whether the menu offers to cancel the server you're on.
  final bool canCancelServer;

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
    return PopupMenuButton<_AccountAction>(
      tooltip: 'Account',
      icon: const Icon(Icons.account_circle_rounded),
      onSelected: (action) => switch (action) {
        _AccountAction.rename => _rename(context),
        _AccountAction.suggestions => Navigator.of(
          context,
        ).push(MaterialPageRoute<void>(builder: (_) => SuggestionsScreen(session: session))),
        _AccountAction.signOut => runGameAction(context, session.signOut),
        _AccountAction.cancelServer => CancelServer.confirm(context, session),
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
        if (suggestions)
          const PopupMenuItem(
            value: _AccountAction.suggestions,
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.lightbulb_outline_rounded),
              title: Text('Ideas & bugs'),
            ),
          ),
        if (!session.isMockup)
          const PopupMenuItem(
            value: _AccountAction.signOut,
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.logout_rounded),
              title: Text('Sign out'),
            ),
          ),
        if (canCancelServer) ...[
          const PopupMenuDivider(),
          PopupMenuItem(
            value: _AccountAction.cancelServer,
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.cancel_outlined, color: Theme.of(context).colorScheme.error),
              title: const Text('Cancel server'),
            ),
          ),
        ],
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

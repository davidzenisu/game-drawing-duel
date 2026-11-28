import 'dart:async';

import 'package:flutter/material.dart';

import '../game_session.dart';
import '../sound.dart';
import '../screens/release_notes_screen.dart';
import '../screens/suggestions_screen.dart';
import 'cancel_server.dart';
import 'server_picker.dart';
import 'game_action.dart';

enum _AccountAction { switchServer, addServer, rename, music, effects, whatsNew, suggestions, signOut, cancelServer }

/// App bar menu for your account: who you're signed in as, switching to
/// another of your servers ([ServerPicker]) or creating or joining another
/// one while on a server, with a dot while another server waits on you,
/// changing your name, turning music and sound effects on or off ([GameSound]), what's new in the game (its release notes) and signing out (not in the mockup, which has no account to sign
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

  /// Whether you're on a server, so you can switch or add one.
  bool get _onServer => switch (session.phase) {
    GamePhase.lobby || GamePhase.setup || GamePhase.daily => true,
    _ => false,
  };

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(listenable: session, builder: (context, _) => _menu(context));
  }

  Widget _menu(BuildContext context) {
    final onServer = _onServer;
    final waiting = onServer && session.otherServerWaiting;
    return PopupMenuButton<_AccountAction>(
      tooltip: waiting ? 'Account: another server waits on you' : 'Account',
      icon: Badge(isLabelVisible: waiting, child: const Icon(Icons.account_circle_rounded)),
      onOpened: () {
        if (onServer) unawaited(session.refreshMyServers().catchError((_) {}));
      },
      onSelected: (action) => switch (action) {
        _AccountAction.switchServer => ServerPicker.show(context, session),
        _AccountAction.addServer => runGameAction(context, session.addServer),
        _AccountAction.rename => _rename(context),
        _AccountAction.music => sound.toggleMusic(),
        _AccountAction.effects => sound.toggleEffects(),
        _AccountAction.whatsNew => Navigator.of(
          context,
        ).push(MaterialPageRoute<void>(builder: (_) => const ReleaseNotesScreen())),
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
        if (onServer) ...[
          PopupMenuItem(
            value: _AccountAction.switchServer,
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Badge(isLabelVisible: waiting, child: const Icon(Icons.swap_horiz_rounded)),
              title: const Text('Switch server'),
              subtitle: Text('On server ${session.server.code}'),
            ),
          ),
          const PopupMenuItem(
            value: _AccountAction.addServer,
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.add_circle_outline_rounded),
              title: Text('Create or join a server'),
            ),
          ),
          const PopupMenuDivider(),
        ],
        const PopupMenuItem(
          value: _AccountAction.rename,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.edit_rounded),
            title: Text('Change name'),
          ),
        ),
        PopupMenuItem(
          value: _AccountAction.music,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(sound.music.value ? Icons.music_note_rounded : Icons.music_off_rounded),
            title: Text(sound.music.value ? 'Music: on' : 'Music: off'),
          ),
        ),
        PopupMenuItem(
          value: _AccountAction.effects,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(sound.effects.value ? Icons.volume_up_rounded : Icons.volume_off_rounded),
            title: Text(sound.effects.value ? 'Sound effects: on' : 'Sound effects: off'),
          ),
        ),
        const PopupMenuItem(
          value: _AccountAction.whatsNew,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.info_outline_rounded),
            title: Text("What's new"),
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

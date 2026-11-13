import 'package:flutter/material.dart';

import '../game_session.dart';
import '../widgets/game_action.dart';

/// The feedback board of the server you're on: ideas and bug reports its
/// players posted, most upvoted first. Post your own, open one for its
/// details, and upvote the ones you'd like to see done (not your own).
class SuggestionsScreen extends StatefulWidget {
  const SuggestionsScreen({super.key, required this.session});

  final GameSession session;

  @override
  State<SuggestionsScreen> createState() => _SuggestionsScreenState();
}

class _SuggestionsScreenState extends State<SuggestionsScreen> {
  List<Suggestion>? _suggestions;
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    // Once built: errors show in a snack bar of the screen.
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    final suggestions = await runGameQuery(context, widget.session.suggestions);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _failed = suggestions == null && _suggestions == null;
      _suggestions = suggestions ?? _suggestions;
    });
  }

  /// Shows [updated] in place of the suggestion it updates; the order stays
  /// until the next refresh, so nothing jumps away under your finger.
  void _replace(Suggestion updated) {
    setState(
      () => _suggestions = [for (final s in _suggestions ?? const <Suggestion>[]) s.id == updated.id ? updated : s],
    );
  }

  Future<Suggestion?> _vote(Suggestion suggestion) async {
    final updated = await runGameQuery(context, () => widget.session.voteOn(suggestion, up: !suggestion.voted));
    if (updated != null && mounted) _replace(updated);
    return updated;
  }

  Future<void> _suggest() async {
    final draft = await showDialog<_Draft>(context: context, builder: (_) => const _SuggestDialog());
    if (draft == null || !mounted) return;
    final posted = await runGameQuery(
      context,
      () => widget.session.suggest(kind: draft.kind, title: draft.title, description: draft.description),
    );
    if (posted == null || !mounted) return;
    // New ones have no upvotes yet: after the upvoted ones, first of the rest.
    final suggestions = [...?_suggestions];
    final at = suggestions.indexWhere((s) => s.votes == 0);
    suggestions.insert(at < 0 ? suggestions.length : at, posted);
    setState(() => _suggestions = suggestions);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text('Thanks! "${posted.title}" is on the board.'), behavior: SnackBarBehavior.floating),
      );
  }

  /// Removes [suggestion] once confirmed; completes with whether it's gone.
  Future<bool> _remove(Suggestion suggestion) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove this suggestion?'),
        content: Text(
          suggestion.yours
              ? '"${suggestion.title}" and its upvotes are removed for everyone.'
              : '"${suggestion.title}" by ${suggestion.author} and its upvotes are removed for everyone.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Keep it')),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return false;
    if (!await runGameAction(context, () => widget.session.removeSuggestion(suggestion)) || !mounted) return false;
    setState(
      () => _suggestions = [
        for (final s in _suggestions ?? const <Suggestion>[])
          if (s.id != suggestion.id) s,
      ],
    );
    return true;
  }

  Future<void> _open(Suggestion suggestion) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _SuggestionDetails(suggestion: suggestion, onVote: _vote, onRemove: _remove),
  );

  @override
  Widget build(BuildContext context) {
    final suggestions = _suggestions;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ideas & bugs'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            tooltip: 'Refresh',
            icon: _loading && suggestions != null
                ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2.5))
                : const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: suggestions == null ? null : _suggest,
        icon: const Icon(Icons.add_comment_rounded),
        label: const Text('Suggest'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: switch (suggestions) {
            null when _failed => _Message(
              icon: Icons.cloud_off_rounded,
              text: "The board didn't load.",
              action: FilledButton.tonal(onPressed: _load, child: const Text('Try again')),
            ),
            null => const CircularProgressIndicator(),
            [] => const _Message(
              icon: Icons.lightbulb_outline_rounded,
              text:
                  'No ideas or bug reports yet. Got an idea for the game, or did something go wrong? '
                  'Post it here: the players of this server see it and upvote what matters most.',
            ),
            _ => ListView(
              // Room for the button at the bottom.
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                  child: Text(
                    'Only the players of this server see these. Upvote what you\'d like to see done.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                for (final suggestion in suggestions)
                  _SuggestionTile(
                    key: ValueKey(suggestion.id),
                    suggestion: suggestion,
                    onTap: () => _open(suggestion),
                    onVote: () => _vote(suggestion),
                  ),
              ],
            ),
          },
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text, this.action});

  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 12),
          Text(text, textAlign: TextAlign.center),
          if (action case final action?) ...[const SizedBox(height: 12), action],
        ],
      ),
    );
  }
}

/// An idea's light bulb or a bug's beetle, in its own colour.
class _KindIcon extends StatelessWidget {
  const _KindIcon(this.kind);

  final SuggestionKind kind;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return switch (kind) {
      SuggestionKind.idea => Icon(Icons.lightbulb_rounded, color: colors.tertiary),
      SuggestionKind.bug => Icon(Icons.bug_report_rounded, color: colors.error),
    };
  }
}

/// E.g. "today", "yesterday" or "3 days ago".
String _ago(DateTime at) {
  final now = DateTime.now();
  final days = DateUtils.dateOnly(now).difference(DateUtils.dateOnly(at.toLocal())).inDays;
  return switch (days) {
    <= 0 => 'today',
    1 => 'yesterday',
    _ => '$days days ago',
  };
}

class _SuggestionTile extends StatelessWidget {
  const _SuggestionTile({super.key, required this.suggestion, required this.onTap, required this.onVote});

  final Suggestion suggestion;
  final VoidCallback onTap;
  final VoidCallback onVote;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        onTap: onTap,
        leading: _KindIcon(suggestion.kind),
        title: Text(suggestion.title, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          '${suggestion.kind.label} · ${suggestion.yours ? 'by you' : 'by ${suggestion.author}'} · ${_ago(suggestion.createdAt)}',
        ),
        trailing: _VoteButton(suggestion: suggestion, onVote: onVote),
      ),
    );
  }
}

/// The upvotes, and a tap to give yours or take it back; your own
/// suggestions only show theirs.
class _VoteButton extends StatelessWidget {
  const _VoteButton({required this.suggestion, required this.onVote});

  final Suggestion suggestion;
  final VoidCallback onVote;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final color = suggestion.voted ? colors.primary : colors.onSurfaceVariant;
    return Tooltip(
      message: suggestion.yours
          ? 'Upvotes'
          : suggestion.voted
          ? 'Take back your upvote'
          : 'Upvote',
      child: InkResponse(
        onTap: suggestion.yours ? null : onVote,
        radius: 28,
        child: SizedBox(
          width: 48,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(suggestion.voted ? Icons.thumb_up_alt_rounded : Icons.thumb_up_alt_outlined, color: color),
              Text(
                '${suggestion.votes}',
                style: TextStyle(color: color, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A suggestion's details, with its upvote button.
class _SuggestionDetails extends StatefulWidget {
  const _SuggestionDetails({required this.suggestion, required this.onVote, required this.onRemove});

  final Suggestion suggestion;
  final Future<Suggestion?> Function(Suggestion) onVote;

  /// Asks first; completes with whether it was removed.
  final Future<bool> Function(Suggestion) onRemove;

  @override
  State<_SuggestionDetails> createState() => _SuggestionDetailsState();
}

class _SuggestionDetailsState extends State<_SuggestionDetails> {
  late Suggestion _suggestion = widget.suggestion;
  bool _voting = false;

  Future<void> _remove() async {
    if (await widget.onRemove(_suggestion) && mounted) Navigator.of(context).pop();
  }

  Future<void> _vote() async {
    setState(() => _voting = true);
    final updated = await widget.onVote(_suggestion);
    if (!mounted) return;
    setState(() {
      _voting = false;
      _suggestion = updated ?? _suggestion;
    });
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final s = _suggestion;
    final votes = '${s.votes} ${s.votes == 1 ? 'upvote' : 'upvotes'}';
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _KindIcon(s.kind),
                const SizedBox(width: 8),
                Text(s.kind.label, style: textTheme.labelLarge),
              ],
            ),
            const SizedBox(height: 8),
            Text(s.title, style: textTheme.titleLarge),
            const SizedBox(height: 4),
            Text('${s.yours ? 'By you' : 'By ${s.author}'} · ${_ago(s.createdAt)}', style: textTheme.bodySmall),
            const SizedBox(height: 16),
            SelectableText(s.description, style: textTheme.bodyLarge),
            const SizedBox(height: 24),
            if (s.yours)
              Text(votes, style: textTheme.titleMedium)
            else
              s.voted
                  ? FilledButton.icon(
                      onPressed: _voting ? null : _vote,
                      icon: const Icon(Icons.thumb_up_alt_rounded),
                      label: Text('Upvoted · $votes'),
                    )
                  : FilledButton.tonalIcon(
                      onPressed: _voting ? null : _vote,
                      icon: const Icon(Icons.thumb_up_alt_outlined),
                      label: Text('Upvote · $votes'),
                    ),
            if (s.removable) ...[
              const SizedBox(height: 16),
              TextButton.icon(
                onPressed: _remove,
                style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
                icon: const Icon(Icons.delete_outline_rounded),
                label: const Text('Remove'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

typedef _Draft = ({SuggestionKind kind, String title, String description});

/// Asks for a new suggestion: idea or bug, a title and a description.
class _SuggestDialog extends StatefulWidget {
  const _SuggestDialog();

  @override
  State<_SuggestDialog> createState() => _SuggestDialogState();
}

class _SuggestDialogState extends State<_SuggestDialog> {
  var _kind = SuggestionKind.idea;
  final _title = TextEditingController();
  final _description = TextEditingController();

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  bool get _complete => _title.text.trim().isNotEmpty && _description.text.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final bug = _kind == SuggestionKind.bug;
    return AlertDialog(
      title: const Text('Suggest'),
      scrollable: true,
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<SuggestionKind>(
              segments: const [
                ButtonSegment(value: SuggestionKind.idea, icon: Icon(Icons.lightbulb_rounded), label: Text('Idea')),
                ButtonSegment(value: SuggestionKind.bug, icon: Icon(Icons.bug_report_rounded), label: Text('Bug')),
              ],
              selected: {_kind},
              onSelectionChanged: (kinds) => setState(() => _kind = kinds.single),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _title,
              autofocus: true,
              maxLength: Suggestion.maxTitleLength,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'Title',
                hintText: bug ? 'e.g. Undo removes two strokes' : 'e.g. A dark mode for the canvas',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _description,
              minLines: 4,
              maxLines: 8,
              maxLength: Suggestion.maxDescriptionLength,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'Description',
                hintText: bug
                    ? 'What happened, and what did you expect? Which screen were you on?'
                    : "What would you like, and why?",
                alignLabelWithHint: true,
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(
          onPressed: _complete
              ? () => Navigator.of(
                  context,
                ).pop((kind: _kind, title: _title.text.trim(), description: _description.text.trim()))
              : null,
          child: const Text('Post'),
        ),
      ],
    );
  }
}

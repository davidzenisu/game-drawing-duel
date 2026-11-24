import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Keyboard controls for a screen that swipes left and right, for players on
/// a computer: ← / → page like a swipe, ↑ / ↓ add or take away, Enter or
/// Space does the screen's main thing and Esc goes back. Keys without a
/// callback do nothing.
///
/// It takes the keys while its screen is on top (a dialog over it takes
/// them first), but leaves them to a text field being typed in, and Enter
/// and Space to a button or other control focused with Tab.
class KeyControls extends StatefulWidget {
  const KeyControls({
    super.key,
    this.onLeft,
    this.onRight,
    this.onUp,
    this.onDown,
    this.onConfirm,
    this.onBack,
    required this.child,
  });

  final VoidCallback? onLeft;
  final VoidCallback? onRight;
  final VoidCallback? onUp;
  final VoidCallback? onDown;

  /// Enter or Space.
  final VoidCallback? onConfirm;

  /// Esc.
  final VoidCallback? onBack;

  final Widget child;

  @override
  State<KeyControls> createState() => _KeyControlsState();
}

class _KeyControlsState extends State<KeyControls> {
  final _focus = FocusNode(debugLabel: 'KeyControls');

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final focused = FocusManager.instance.primaryFocus;
    // A text field keeps its arrows, Enter, Space and Esc.
    if (focused?.context?.findAncestorWidgetOfExactType<EditableText>() != null) return KeyEventResult.ignored;
    final callback = switch (event.logicalKey) {
      LogicalKeyboardKey.arrowLeft => widget.onLeft,
      LogicalKeyboardKey.arrowRight => widget.onRight,
      LogicalKeyboardKey.arrowUp => widget.onUp,
      LogicalKeyboardKey.arrowDown => widget.onDown,
      LogicalKeyboardKey.escape => widget.onBack,
      // A button focused with Tab presses itself.
      LogicalKeyboardKey.enter ||
      LogicalKeyboardKey.numpadEnter ||
      LogicalKeyboardKey.space when focused == _focus => widget.onConfirm,
      _ => null,
    };
    if (callback == null) return KeyEventResult.ignored;
    callback();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) =>
      Focus(focusNode: _focus, autofocus: true, onKeyEvent: _onKey, child: widget.child);
}

/// Whether the screen is wide enough, like on a computer, for big ← / →
/// buttons next to what swipes; phones swipe.
bool showsPagerArrows(BuildContext context) => MediaQuery.sizeOf(context).width >= 600;

/// A big ← or → button beside something that swipes, on wide screens; greyed
/// out at either end ([onPressed] null).
class PagerArrow extends StatelessWidget {
  const PagerArrow.previous({super.key, required this.onPressed, this.tooltip = 'Previous', this.color}) : next = false;

  const PagerArrow.next({super.key, required this.onPressed, this.tooltip = 'Next', this.color}) : next = true;

  final bool next;
  final VoidCallback? onPressed;
  final String tooltip;

  /// The arrow's colour, e.g. to stand out on scenery.
  final Color? color;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    iconSize: 36,
    color: color,
    disabledColor: color?.withValues(alpha: 0.25),
    onPressed: onPressed,
    icon: Icon(next ? Icons.chevron_right_rounded : Icons.chevron_left_rounded),
  );
}

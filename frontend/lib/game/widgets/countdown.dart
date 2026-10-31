import 'dart:async';

import 'package:flutter/material.dart';

/// The time left until [endsAt] as m:ss, ticking every second; calls
/// [onDone] once when it runs out, e.g. to load what comes next.
class Countdown extends StatefulWidget {
  const Countdown({super.key, required this.endsAt, this.label, this.onDone});

  final DateTime endsAt;

  /// Shown before the time, e.g. "Day 2".
  final String? label;
  final VoidCallback? onDone;

  @override
  State<Countdown> createState() => _CountdownState();
}

class _CountdownState extends State<Countdown> {
  Timer? _ticker;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  @override
  void didUpdateWidget(Countdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.endsAt != widget.endsAt) _done = false;
  }

  void _tick() {
    if (!mounted) return;
    setState(() {});
    if (_done || _left > Duration.zero) return;
    _done = true;
    widget.onDone?.call();
  }

  Duration get _left => widget.endsAt.difference(DateTime.now());

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final left = _left.isNegative ? Duration.zero : _left;
    final time = '${left.inMinutes}:${(left.inSeconds % 60).toString().padLeft(2, '0')}';
    final urgent = left < const Duration(seconds: 15);
    final colors = Theme.of(context).colorScheme;
    return Chip(
      avatar: Icon(Icons.timer_rounded, size: 18, color: urgent ? colors.error : null),
      label: Text(
        [?widget.label, '$time left'].join(' · '),
        style: TextStyle(
          fontFeatures: const [FontFeature.tabularFigures()],
          color: urgent ? colors.error : null,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

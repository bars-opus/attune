import 'dart:async';

import 'package:attune/core/utils/countdown/countdown.dart';
import 'package:flutter/material.dart';

/// A live countdown to a date, a date range, or a moment, reusable anywhere.
///
/// It keeps itself current: a date countdown turns over at local midnight,
/// a moment ticks every second in its last hour (every minute before that),
/// and both catch up when the app returns from the background (timers do
/// not run while it is suspended). Pass [clock] in tests; [builder] to draw
/// the snapshot your own way. Screen readers always hear the full label.
class AppCountdown extends StatefulWidget {
  const AppCountdown.toDate({
    super.key,
    required DateTime this.start,
    this.end,
    this.style,
    this.builder,
    this.clock,
  }) : target = null;

  const AppCountdown.toMoment({
    super.key,
    required DateTime this.target,
    this.style,
    this.builder,
    this.clock,
  })  : start = null,
        end = null;

  final DateTime? start;
  final DateTime? end;
  final DateTime? target;
  final TextStyle? style;
  final Widget Function(BuildContext context, CountdownSnapshot snapshot)? builder;
  final DateTime Function()? clock;

  @override
  State<AppCountdown> createState() => _AppCountdownState();
}

class _AppCountdownState extends State<AppCountdown> {
  Timer? _timer;
  late final AppLifecycleListener _lifecycle;

  DateTime _now() => (widget.clock ?? DateTime.now)();

  CountdownSnapshot _snapshot() {
    final now = _now();
    return widget.target != null
        ? Countdown.toMoment(target: widget.target!, now: now)
        : Countdown.toDate(start: widget.start!, end: widget.end, now: now);
  }

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _refresh);
    _schedule();
  }

  @override
  void didUpdateWidget(AppCountdown old) {
    super.didUpdateWidget(old);
    _schedule();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _lifecycle.dispose();
    super.dispose();
  }

  void _refresh() {
    if (!mounted) return;
    setState(() {});
    _schedule();
  }

  /// One timer, to the next moment the label can change.
  void _schedule() {
    _timer?.cancel();
    final now = _now();
    final Duration wait;
    if (widget.target != null) {
      final left = widget.target!.difference(now).abs();
      wait = left < const Duration(hours: 1) ? const Duration(seconds: 1) : const Duration(minutes: 1);
    } else {
      final midnight = DateTime(now.year, now.month, now.day + 1);
      wait = midnight.difference(now) + const Duration(seconds: 1);
    }
    _timer = Timer(wait, _refresh);
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot();
    return Semantics(
      label: snapshot.label,
      excludeSemantics: true,
      child: widget.builder?.call(context, snapshot) ?? Text(snapshot.label, style: widget.style),
    );
  }
}

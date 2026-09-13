import 'dart:async';
import 'dart:math' as math;

import 'package:attune/core/ui/motion/motion_tokens.dart';
import 'package:attune/core/ui/motion/reduce_motion.dart';
import 'package:flutter/material.dart';

typedef PayloadFlightBuilder =
    Widget Function(BuildContext context, double progress);

/// Flies a visual payload between two measured screen rectangles.
///
/// [resolveDestination] is deliberately lazy: optimistic UI normally adds
/// the destination after the tap, so its RenderBox does not exist when this
/// function is first called. The payload waits at its source for a handful of
/// frames while that destination lays out, then follows a small upward arc and
/// morphs into the measured target rectangle.
Future<void> showPayloadFlight({
  required BuildContext context,
  required Rect sourceRect,
  required Rect fallbackDestination,
  required Rect? Function() resolveDestination,
  required PayloadFlightBuilder builder,
  Duration duration = kPayloadFlightDuration,
  int destinationWaitFrames = 10,
}) {
  assert(destinationWaitFrames > 0);
  if (reduceMotionOf(context)) return Future<void>.value();

  final overlay = Overlay.of(context, rootOverlay: true);
  final completed = Completer<void>();
  late final OverlayEntry entry;

  entry = OverlayEntry(
    builder:
        (context) => _PayloadFlight(
          sourceRect: sourceRect,
          fallbackDestination: fallbackDestination,
          resolveDestination: resolveDestination,
          duration: duration,
          destinationWaitFrames: destinationWaitFrames,
          builder: builder,
          onCompleted: () {
            entry.remove();
            if (!completed.isCompleted) completed.complete();
          },
        ),
  );
  overlay.insert(entry);
  return completed.future;
}

class _PayloadFlight extends StatefulWidget {
  const _PayloadFlight({
    required this.sourceRect,
    required this.fallbackDestination,
    required this.resolveDestination,
    required this.duration,
    required this.destinationWaitFrames,
    required this.builder,
    required this.onCompleted,
  });

  final Rect sourceRect;
  final Rect fallbackDestination;
  final Rect? Function() resolveDestination;
  final Duration duration;
  final int destinationWaitFrames;
  final PayloadFlightBuilder builder;
  final VoidCallback onCompleted;

  @override
  State<_PayloadFlight> createState() => _PayloadFlightState();
}

class _PayloadFlightState extends State<_PayloadFlight>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  )..addStatusListener(_onStatusChanged);
  Rect? _destination;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _findDestination());
  }

  void _findDestination([int attempt = 0]) {
    // Local cache/outbox work normally makes the optimistic target available
    // on the first frame. A few retries cover slower devices without leaving
    // the payload parked in the composer for a visibly long time.
    if (!mounted) return;
    final destination = widget.resolveDestination();
    if (destination != null && !destination.isEmpty) {
      _destination = destination;
      _start();
      return;
    }

    if (attempt < widget.destinationWaitFrames - 1) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _findDestination(attempt + 1),
      );
      WidgetsBinding.instance.scheduleFrame();
      return;
    }

    _destination ??= widget.fallbackDestination;
    _start();
  }

  void _start() {
    if (_started || !mounted) return;
    _started = true;
    _controller.forward();
  }

  void _onStatusChanged(AnimationStatus status) {
    if (status == AnimationStatus.completed) widget.onCompleted();
  }

  @override
  void dispose() {
    _controller
      ..removeStatusListener(_onStatusChanged)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final raw = _started ? _controller.value : 0.0;
            final progress = Curves.easeInOutCubicEmphasized.transform(raw);
            final destination = _destination ?? widget.sourceRect;
            final rect = Rect.lerp(widget.sourceRect, destination, progress)!;
            final distance =
                (destination.center - widget.sourceRect.center).distance;
            final arcHeight = math.min(30.0, distance * 0.1);
            final lift = math.sin(math.pi * raw) * arcHeight;
            final direction =
                destination.center.dx >= widget.sourceRect.center.dx
                    ? 1.0
                    : -1.0;
            final tilt = math.sin(math.pi * raw) * 0.025 * direction;
            final pulse = 1 + math.sin(math.pi * raw) * 0.025;

            return Stack(
              children: [
                Positioned.fromRect(
                  rect: rect.translate(0, -lift),
                  child: Transform.rotate(
                    angle: tilt,
                    child: Transform.scale(
                      scale: pulse,
                      child: widget.builder(context, raw),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

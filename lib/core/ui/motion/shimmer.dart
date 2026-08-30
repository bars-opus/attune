import 'package:flutter/material.dart';

import 'motion_tokens.dart';
import 'reduce_motion.dart';

/// A one-directional highlight sweep across [child] while [active]. Generic
/// "this is special right now" sheen — chat's first-message-of-the-day is the
/// first consumer. Static under reduce-motion / inactive.
///
/// [sweeps] bounds the celebration: the sheen sweeps that many times, then the
/// widget renders the plain child with zero further frame scheduling — a
/// perpetual loop on an idle screen is a battery/jank cost the low-end-device
/// performance budget can't afford (Spec §2: moments, not loops). Pass
/// `sweeps: null` only for skeleton-loading style consumers whose lifetime is
/// already bounded by an unmount.
class Shimmer extends StatefulWidget {
  const Shimmer({
    super.key,
    required this.child,
    this.active = true,
    this.period = kShimmerSweepCalm,
    this.highlightColor,
    this.sweeps = 2,
  });

  final Widget child;
  final bool active;
  final Duration period;
  final Color? highlightColor;

  /// Number of full sweeps before settling to the plain child. `null` loops
  /// while [active] (bounded-lifetime consumers only).
  final int? sweeps;

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: widget.period,
  );
  bool _started = false;
  bool _done = false;
  int _runId = 0; // invalidates an in-flight bounded run on state changes

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _sync();
  }

  @override
  void didUpdateWidget(covariant Shimmer old) {
    super.didUpdateWidget(old);
    if (old.active != widget.active) {
      _done = false;
      _sync();
    }
  }

  void _sync() {
    _runId++;
    if (!widget.active || reduceMotionOf(context)) {
      _ctrl.stop();
      _ctrl.value = 0;
      return;
    }
    final sweeps = widget.sweeps;
    if (sweeps == null) {
      _ctrl.repeat();
    } else {
      _runBounded(sweeps, _runId);
    }
  }

  Future<void> _runBounded(int sweeps, int runId) async {
    for (var i = 0; i < sweeps; i++) {
      if (!mounted || runId != _runId) return;
      try {
        await _ctrl.forward(from: 0);
      } on TickerCanceled {
        return;
      }
    }
    if (!mounted || runId != _runId) return;
    // Park off-canvas and drop the ShaderMask entirely: once settled the
    // widget is just its child — no shader, no ticker, no per-frame cost.
    _ctrl.value = 0;
    setState(() => _done = true);
  }

  @override
  void dispose() {
    _runId++;
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_done || !widget.active || reduceMotionOf(context)) {
      return widget.child;
    }
    final highlight =
        widget.highlightColor ??
        Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.25);
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) {
        final t = _ctrl.value;
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) {
            return LinearGradient(
              begin: Alignment(-1.0 - 2 * (1 - t), 0),
              end: Alignment(1.0 - 2 * (1 - t), 0),
              colors: [Colors.transparent, highlight, Colors.transparent],
              stops: const [0.35, 0.5, 0.65],
            ).createShader(bounds);
          },
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

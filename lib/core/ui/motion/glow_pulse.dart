import 'package:flutter/material.dart';

import 'motion_tokens.dart';
import 'reduce_motion.dart';

/// Breathing glow around a child while [active]. Universal "someone/something
/// is live" indicator — used for the chat-header avatar, but usable anywhere.
/// Calm by design (Spec §3.3): long period, small spread.
///
/// The pulse is a *moment, not a loop*: on activation it breathes [cycles]
/// times, then settles to a static glow with zero further frame scheduling —
/// a session-long repeat is a battery/jank cost the low-end-device performance
/// budget can't afford. Under OS reduce-motion the glow is static from the
/// start (the "live" signal is preserved; only the motion is removed).
///
/// Currently renders a circular glow only (intended for avatars); a [shape]
/// param can be added when a non-circular consumer appears.
class GlowPulse extends StatefulWidget {
  const GlowPulse({
    super.key,
    required this.child,
    required this.active,
    this.color,
    this.maxSpread = 8.0,
    this.cycles = 3,
    this.settleValue = 0.55,
  });

  final Widget child;
  final bool active;
  final Color? color;
  final double maxSpread;

  /// Breathing cycles before settling to the static glow.
  final int cycles;

  /// Controller value ([0, 1]) held after settling — the static glow strength.
  final double settleValue;

  @override
  State<GlowPulse> createState() => _GlowPulseState();
}

class _GlowPulseState extends State<GlowPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: kGlowBreathPeriod,
  );
  bool _started = false;
  int _runId = 0; // invalidates an in-flight run when [active] flips

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Decide once, after context (and thus MediaQuery) is available. Later
    // dependency changes (theme etc.) must not restart the breathing run.
    if (_started) return;
    _started = true;
    _sync();
  }

  @override
  void didUpdateWidget(covariant GlowPulse old) {
    super.didUpdateWidget(old);
    if (old.active != widget.active) _sync();
  }

  void _sync() {
    _runId++;
    if (!widget.active) {
      _ctrl.stop();
      _ctrl.value = 0;
      return;
    }
    if (reduceMotionOf(context)) {
      // Static glow, no motion: the signal survives, the animation doesn't.
      _ctrl.stop();
      _ctrl.value = widget.settleValue;
      return;
    }
    _runBreathing(_runId);
  }

  Future<void> _runBreathing(int runId) async {
    try {
      for (var i = 0; i < widget.cycles; i++) {
        if (!mounted || runId != _runId) return;
        await _ctrl.forward(from: 0);
        if (!mounted || runId != _runId) return;
        await _ctrl.reverse();
      }
      if (!mounted || runId != _runId) return;
      // Settle: one short ramp to the resting glow, then no more frames.
      await _ctrl.animateTo(
        widget.settleValue,
        duration: kGlowSettleRamp,
        curve: Curves.easeOut,
      );
    } on TickerCanceled {
      // Deactivated mid-run; _sync already reset state.
    }
  }

  @override
  void dispose() {
    _runId++;
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? Theme.of(context).colorScheme.primary;
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) {
        final spread = widget.active ? widget.maxSpread * _ctrl.value : 0.0;
        return DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow:
                widget.active && _ctrl.value > 0
                    ? [
                      BoxShadow(
                        color: color.withValues(alpha: 0.45 * _ctrl.value),
                        blurRadius: spread * 1.5,
                        spreadRadius: spread,
                      ),
                    ]
                    : const [],
          ),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

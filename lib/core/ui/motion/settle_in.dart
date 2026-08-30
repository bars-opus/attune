import 'package:flutter/widgets.dart';

import 'motion_tokens.dart';
import 'reduce_motion.dart';

/// One-shot spring settle + fade entry. Universal: knows nothing about chat.
/// Pair with a stable ValueKey on the parent list item so it runs only when the
/// item is genuinely new (Spec §2 play-once).
class SettleIn extends StatefulWidget {
  const SettleIn({
    super.key,
    required this.child,
    this.animate = true,
    this.beginOffset = const Offset(0, 0.10),
    this.duration = kSettleDuration,
    this.curve = kSettleCurve,
  });

  final Widget child;
  final bool animate;
  final Offset beginOffset;
  final Duration duration;
  final Curve curve;

  @override
  State<SettleIn> createState() => _SettleInState();
}

class _SettleInState extends State<SettleIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: widget.duration,
  );
  late final Animation<double> _fade = CurvedAnimation(
    parent: _ctrl,
    curve: Curves.easeOut,
  );
  late final Animation<Offset> _slide = Tween<Offset>(
    begin: widget.beginOffset,
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _ctrl, curve: widget.curve));

  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Decide once, after context (and thus MediaQuery) is available.
    if (_started) return;
    _started = true;
    if (!widget.animate || reduceMotionOf(context)) {
      _ctrl.value = 1.0; // jump to end-state
    } else {
      _ctrl.forward();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(position: _slide, child: widget.child),
    );
  }
}

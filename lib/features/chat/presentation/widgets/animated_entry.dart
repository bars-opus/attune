import 'package:flutter/widgets.dart';

/// One-shot slide + fade entry animation.
///
/// Uses [SingleTickerProviderStateMixin] so each instance runs its own
/// controller. When [animate] is false the child is rendered immediately at
/// full opacity and zero offset — useful for items that pre-dated the current
/// session and should not play the intro animation.
///
/// Pair with a [ValueKey] on the parent list item so Flutter creates a new
/// element (and runs [initState]) only when the item is genuinely new.
class AnimatedEntry extends StatefulWidget {
  final Widget child;

  /// When false, the animation is skipped and the child is shown instantly.
  final bool animate;

  /// Starting fractional offset. Positive Y = slide up, negative Y = slide down.
  final Offset beginOffset;

  final Duration duration;
  final Curve curve;

  const AnimatedEntry({
    super.key,
    required this.child,
    this.animate = true,
    this.beginOffset = const Offset(0, 0.10),
    this.duration = const Duration(milliseconds: 280),
    this.curve = Curves.easeOutCubic,
  });

  @override
  State<AnimatedEntry> createState() => _AnimatedEntryState();
}

class _AnimatedEntryState extends State<AnimatedEntry>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: widget.duration);
    _fade = CurvedAnimation(parent: _ctrl, curve: widget.curve);
    _slide = Tween<Offset>(
      begin: widget.beginOffset,
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: widget.curve));

    if (widget.animate) {
      _ctrl.forward();
    } else {
      _ctrl.value = 1.0;
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

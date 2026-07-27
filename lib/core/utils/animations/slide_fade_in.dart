import 'package:attune/core/utils/exports/export_screens.dart';

/// One-shot entrance animation: slides up from [beginOffset] while fading
/// in. Mirrors AnimatedScaleFade's shape (AnimationController + one
/// forward() on mount) for a translate+fade effect instead of scale+fade —
/// e.g. a newly-posted comment sliding into the list.
class SlideFadeIn extends StatefulWidget {
  final Widget child;
  final Duration duration;
  final Curve curve;
  final Offset beginOffset;
  final bool autoStart;

  const SlideFadeIn({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 350),
    this.curve = Curves.easeOutCubic,
    this.beginOffset = const Offset(0, 0.15),
    this.autoStart = true,
  });

  @override
  State<SlideFadeIn> createState() => _SlideFadeInState();
}

class _SlideFadeInState extends State<SlideFadeIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Offset> _offsetAnimation;
  late final Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(duration: widget.duration, vsync: this);
    final curved = CurvedAnimation(parent: _controller, curve: widget.curve);
    _offsetAnimation = Tween<Offset>(
      begin: widget.beginOffset,
      end: Offset.zero,
    ).animate(curved);
    _opacityAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(curved);
    if (widget.autoStart) _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SlideTransition(
      position: _offsetAnimation,
      child: FadeTransition(opacity: _opacityAnimation, child: widget.child),
    );
  }
}

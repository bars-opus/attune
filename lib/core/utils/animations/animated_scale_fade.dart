import 'package:attune/core/utils/exports/export_screens.dart';

class AnimatedScaleFade extends StatefulWidget {
  final Widget child;
  final Duration duration;
  final Curve curve;
  final double beginScale;
  final double endScale;
  final bool autoStart;
  final int? staggerIndex;
  final double staggerDelay;
  final VoidCallback? onAnimationComplete;
  final bool fadeIn;
  final double beginOpacity;
  final double endOpacity;

  const AnimatedScaleFade({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 600),
    this.curve = Curves.easeOutBack,
    this.beginScale = 0.0,
    this.endScale = 1.0,
    this.autoStart = true,
    this.staggerIndex,
    this.staggerDelay = 0.05,
    this.onAnimationComplete,
    this.fadeIn = true,
    this.beginOpacity = 0.0,
    this.endOpacity = 1.0,
  });

  @override
  State<AnimatedScaleFade> createState() => _AnimatedScaleFadeState();
}

class _AnimatedScaleFadeState extends State<AnimatedScaleFade>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: widget.duration,
      vsync: this,
    );
    _buildAnimations();
    _controller.addStatusListener(_onStatus);
    if (widget.autoStart) _controller.forward();
  }

  @override
  void didUpdateWidget(AnimatedScaleFade oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.duration != oldWidget.duration) {
      _controller.duration = widget.duration;
    }

    if (widget.beginScale != oldWidget.beginScale ||
        widget.endScale != oldWidget.endScale ||
        widget.curve != oldWidget.curve ||
        widget.beginOpacity != oldWidget.beginOpacity ||
        widget.endOpacity != oldWidget.endOpacity ||
        widget.fadeIn != oldWidget.fadeIn ||
        widget.staggerIndex != oldWidget.staggerIndex ||
        widget.staggerDelay != oldWidget.staggerDelay) {
      _buildAnimations();
    }
  }

  void _buildAnimations() {
    final delay =
        ((widget.staggerIndex ?? 0) * widget.staggerDelay).clamp(0.0, 1.0);

    _scaleAnimation = Tween<double>(
      begin: widget.beginScale,
      end: widget.endScale,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Interval(delay, 1.0, curve: widget.curve),
    ));

    _opacityAnimation = widget.fadeIn
        ? Tween<double>(
            begin: widget.beginOpacity,
            end: widget.endOpacity,
          ).animate(CurvedAnimation(
            parent: _controller,
            curve: Interval(delay, 1.0, curve: Curves.easeOut),
          ))
        : AlwaysStoppedAnimation(widget.endOpacity);
  }

  void _onStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      widget.onAnimationComplete?.call();
    }
  }

  @override
  void dispose() {
    _controller.removeStatusListener(_onStatus);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Transform.scale(
          scale: _scaleAnimation.value,
          child: Opacity(
            opacity: _opacityAnimation.value,
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}

extension AnimatedWidgetExtension on Widget {
  Widget animated({
    Duration duration = const Duration(milliseconds: 600),
    Curve curve = Curves.easeOutBack,
    double beginScale = 0.0,
    double endScale = 1.0,
    bool autoStart = true,
    int? staggerIndex,
    double staggerDelay = 0.05,
    VoidCallback? onAnimationComplete,
    bool fadeIn = true,
    double beginOpacity = 0.0,
    double endOpacity = 1.0,
  }) {
    return AnimatedScaleFade(
      duration: duration,
      curve: curve,
      beginScale: beginScale,
      endScale: endScale,
      autoStart: autoStart,
      staggerIndex: staggerIndex,
      staggerDelay: staggerDelay,
      onAnimationComplete: onAnimationComplete,
      fadeIn: fadeIn,
      beginOpacity: beginOpacity,
      endOpacity: endOpacity,
      child: this,
    );
  }
}

import 'package:attune/core/ui/motion/motion_tokens.dart';
import 'package:attune/core/ui/motion/reduce_motion.dart';
import 'package:flutter/material.dart';

/// One step of a multi-step flow, entering with Material's shared-axis X
/// transition (Spec 1 §2.2): the outgoing step slides 30 dp away and fades
/// out over its first 90 ms; the incoming one slides in from 30 dp and fades
/// in from 90 ms to the end. Forward takes [kStepForwardDuration], back
/// [kStepBackDuration], and the direction flips under right-to-left text.
/// With reduce motion on, both cross-fade in [kReducedMotionFade] and
/// nothing moves.
///
/// A new [stepKey] starts a transition; the same key with a new [child]
/// just rebuilds in place. A step is one element for its whole life, so a
/// leaving step keeps its state (typed text, controllers, timers) while it
/// slides out, and a step brought straight back is the same one. Only the
/// incoming step takes taps, focus and a screen reader's attention: focus
/// moves into it as it arrives (its own autofocus field, or else the step
/// itself, which also puts the keyboard of the leaving step away).
class SharedAxisStep extends StatefulWidget {
  const SharedAxisStep({
    super.key,
    required this.stepKey,
    required this.child,
    this.forward = true,
  });

  final Object stepKey;
  final Widget child;

  /// False when going back a step: the slide reverses.
  final bool forward;

  @override
  State<SharedAxisStep> createState() => _SharedAxisStepState();
}

class _SharedAxisStepState extends State<SharedAxisStep>
    with SingleTickerProviderStateMixin {
  // Preserve: the platform's reduce-motion switch, which picks the 150 ms
  // fade, would otherwise also run it 20 times faster (review B2 M-2).
  late final AnimationController _controller = AnimationController(
    vsync: this,
    value: 1,
    animationBehavior: AnimationBehavior.preserve,
  );
  Widget? _outgoing;
  Object? _outgoingKey;
  bool _outgoingForward = true;

  /// Bumped by every transition, so a transition cut short by the next one
  /// doesn't clear the new outgoing step when its own future is cancelled.
  int _generation = 0;

  @override
  void didUpdateWidget(covariant SharedAxisStep oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.stepKey == widget.stepKey) return;
    _outgoing = oldWidget.child;
    _outgoingKey = oldWidget.stepKey;
    _outgoingForward = widget.forward;
    _controller.duration =
        reduceMotionOf(context)
            ? kReducedMotionFade
            : widget.forward
            ? kStepForwardDuration
            : kStepBackDuration;
    final generation = ++_generation;
    _controller.forward(from: 0).whenCompleteOrCancel(() {
      if (!mounted || generation != _generation) return;
      setState(() {
        _outgoing = null;
        _outgoingKey = null;
      });
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final moving = _outgoing != null;
    final reduce = reduceMotionOf(context);
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final sign = (_outgoingForward ? 1.0 : -1.0) * (rtl ? -1.0 : 1.0);
    final total = _controller.duration?.inMilliseconds ?? 1;
    final fadeOutEnd = (kStepFadeOutDuration.inMilliseconds / total).clamp(
      0.0,
      1.0,
    );

    final Animation<double> incomingOpacity;
    final Animation<double> outgoingOpacity;
    final Animation<double> incomingDx;
    final Animation<double> outgoingDx;
    if (!moving) {
      incomingOpacity = kAlwaysCompleteAnimation;
      outgoingOpacity = kAlwaysDismissedAnimation;
      incomingDx = outgoingDx = const AlwaysStoppedAnimation<double>(0);
    } else if (reduce) {
      incomingOpacity = _controller;
      outgoingOpacity = ReverseAnimation(_controller);
      incomingDx = outgoingDx = const AlwaysStoppedAnimation<double>(0);
    } else {
      incomingOpacity = _controller.drive(
        CurveTween(
          curve: Interval(fadeOutEnd, 1, curve: Easing.emphasizedDecelerate),
        ),
      );
      outgoingOpacity = ReverseAnimation(
        _controller.drive(
          CurveTween(
            curve: Interval(0, fadeOutEnd, curve: Easing.emphasizedAccelerate),
          ),
        ),
      );
      final slide = CurveTween(curve: Curves.easeInOutCubicEmphasized);
      incomingDx = _controller.drive(
        Tween<double>(begin: sign * kSharedAxisOffset, end: 0).chain(slide),
      );
      outgoingDx = _controller.drive(
        Tween<double>(begin: 0, end: -sign * kSharedAxisOffset).chain(slide),
      );
    }

    // Each step keeps one key and one wrapper chain whether it is arriving
    // or leaving, so moving from one to the other never remounts it.
    return Stack(
      fit: StackFit.passthrough,
      children: [
        if (moving)
          _StepLayer(
            key: ValueKey<Object?>(_outgoingKey),
            leaving: true,
            takeFocus: false,
            opacity: outgoingOpacity,
            dx: outgoingDx,
            child: _outgoing!,
          ),
        _StepLayer(
          key: ValueKey<Object?>(widget.stepKey),
          leaving: false,
          takeFocus: moving,
          opacity: incomingOpacity,
          dx: incomingDx,
          child: widget.child,
        ),
      ],
    );
  }
}

/// One step in the stack. [leaving] shuts it off from taps, the screen
/// reader and focus without changing its widget types. Its own focus scope
/// lets an autofocus field inside it take focus as it arrives, whatever was
/// focused before.
class _StepLayer extends StatefulWidget {
  const _StepLayer({
    super.key,
    required this.leaving,
    required this.takeFocus,
    required this.opacity,
    required this.dx,
    required this.child,
  });

  final bool leaving;

  /// Mounted as the arriving step of a transition: focus moves into it.
  final bool takeFocus;
  final Animation<double> opacity;
  final Animation<double> dx;
  final Widget child;

  @override
  State<_StepLayer> createState() => _StepLayerState();
}

class _StepLayerState extends State<_StepLayer> {
  final _scope = FocusScopeNode(debugLabel: 'SharedAxisStep');

  @override
  void initState() {
    super.initState();
    if (widget.takeFocus) _focusAfterFrame();
  }

  @override
  void didUpdateWidget(covariant _StepLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Brought straight back while it was leaving.
    if (oldWidget.leaving && !widget.leaving) _focusAfterFrame();
  }

  void _focusAfterFrame() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Its last focused field, if it had one; otherwise the scope itself,
      // and a fresh autofocus field inside then takes it.
      if (mounted && !widget.leaving) _scope.requestFocus();
    });
  }

  @override
  void dispose() {
    _scope.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final leaving = widget.leaving;
    return IgnorePointer(
      ignoring: leaving,
      child: ExcludeSemantics(
        excluding: leaving,
        child: ExcludeFocus(
          excluding: leaving,
          child: FocusScope(
            node: _scope,
            includeSemantics: false,
            child: FadeTransition(
              opacity: widget.opacity,
              child: _SlideX(dx: widget.dx, child: widget.child),
            ),
          ),
        ),
      ),
    );
  }
}

/// A horizontal slide in logical pixels. SlideTransition moves by a
/// fraction of the child's size; §2.2 wants a fixed 30 dp.
class _SlideX extends AnimatedWidget {
  const _SlideX({required Animation<double> dx, required this.child})
    : super(listenable: dx);

  final Widget child;

  @override
  Widget build(BuildContext context) => Transform.translate(
    offset: Offset((listenable as Animation<double>).value, 0),
    child: child,
  );
}

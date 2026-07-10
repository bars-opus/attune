import 'package:flutter/widgets.dart';

import 'reduce_motion.dart';

/// Morphs between two glyphs with a fade+scale. Generic: chat status ticks are
/// one consumer, but any state-icon can use it. Caller keys the child per state.
class IconCrossfade extends StatelessWidget {
  const IconCrossfade({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 200),
  });

  final Widget child;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final d = reduceMotionOf(context) ? Duration.zero : duration;
    return AnimatedSwitcher(
      duration: d,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.8, end: 1.0).animate(animation),
          child: child,
        ),
      ),
      child: child,
    );
  }
}

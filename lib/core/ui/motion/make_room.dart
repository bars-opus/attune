import 'package:flutter/widgets.dart';

import 'motion_tokens.dart';
import 'reduce_motion.dart';

/// Opens vertical space for an arriving list item, so the items already on
/// screen are physically displaced as it appears rather than jumping to
/// their new positions a frame before it fades in.
///
/// In a `reverse: true` list the new item sits at the bottom and everything
/// older is pushed up. Growing this item's own slot from nothing to its
/// full height is what makes that push visible, and the distance is
/// exactly the arriving content's height — a long message shoves the list
/// further than a short one, which a fixed slide offset cannot express.
///
/// Universal: knows nothing about chat. Pair with a stable key on the list
/// item so it opens only for genuinely new content.
class MakeRoom extends StatefulWidget {
  const MakeRoom({
    super.key,
    required this.child,
    this.animate = true,
    this.duration = kMakeRoomDuration,
    this.curve = kMakeRoomCurve,
  });

  final Widget child;

  /// False renders the child at full height immediately — cached history
  /// and recycled rows must not replay the opening.
  final bool animate;

  final Duration duration;
  final Curve curve;

  @override
  State<MakeRoom> createState() => _MakeRoomState();
}

class _MakeRoomState extends State<MakeRoom>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: widget.duration,
  );
  late final Animation<double> _factor = CurvedAnimation(
    parent: _ctrl,
    curve: widget.curve,
  );

  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Decided once, after context (and so MediaQuery) is available.
    if (_started) return;
    _started = true;
    if (!widget.animate || reduceMotionOf(context)) {
      _ctrl.value = 1.0;
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
    // Align with a heightFactor rather than a SizeTransition so the child
    // is laid out at its natural height and then revealed: the slot always
    // settles at the content's real height, never at an estimate the
    // caller had to supply.
    //
    // alignment bottomCenter so the child is revealed from its bottom
    // edge, staying pinned to the composer as the space opens above it.
    return ClipRect(
      child: AnimatedBuilder(
        animation: _factor,
        builder:
            (context, child) => Align(
              alignment: Alignment.bottomCenter,
              heightFactor: _factor.value.clamp(0.0, 1.0),
              child: child,
            ),
        child: widget.child,
      ),
    );
  }
}

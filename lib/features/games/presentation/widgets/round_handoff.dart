import 'dart:async';

import 'package:attune/core/ui/motion/reduce_motion.dart';
import 'package:flutter/material.dart';

/// How long a finished round stays on screen before the game leaves.
///
/// Not a loading delay -- nothing is being fetched. It is reading time.
/// The round is over the instant the move lands, but the player has not
/// SEEN it yet: the number they rolled, where the shot landed, what
/// their partner will be answering. Games that left immediately felt
/// like they had swallowed the turn.
///
/// Seven seconds is long enough to read a result and short enough that
/// nobody waits through it twice; [RoundHandoff] lets it be cut short by
/// a tap, so it is a floor on the experience and never a ceiling.
const Duration kRoundHandoffDuration = Duration(seconds: 7);

/// Holds a finished round on screen, then leaves.
///
/// Every asynchronous game ends a turn the same way: the player acts, the
/// board is now the partner's, and there is nothing further to do here.
/// Parking them on a dead screen behind a "back to chat" button makes
/// them dismiss a result they did not ask to keep; leaving the instant
/// the move lands cuts off the result entirely. This does both in order.
///
/// Wrap the "your turn is over" view. [onLeave] is called once, after the
/// hold, or as soon as the player taps -- waiting is never mandatory.
class RoundHandoff extends StatefulWidget {
  const RoundHandoff({
    super.key,
    required this.child,
    required this.onLeave,
    this.duration = kRoundHandoffDuration,
    this.showCountdown = true,
  });

  final Widget child;

  /// Called exactly once: on timeout, or on a tap that skips the wait.
  final VoidCallback onLeave;

  final Duration duration;

  /// Whether to draw the thin progress line under the child. Off for
  /// screens that already say what happens next in their own words.
  final bool showCountdown;

  @override
  State<RoundHandoff> createState() => _RoundHandoffState();
}

class _RoundHandoffState extends State<RoundHandoff>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  );

  /// The leave happens once. A tap arriving as the timer completes must
  /// not pop twice -- on a Navigator that is two screens, not one.
  bool _left = false;
  bool _started = false;

  /// The reduce-motion path's timer, held so dispose can cancel it
  /// (checklist 2.10, 2.13). An uncancelled Timer keeps this State
  /// object alive until it fires -- harmless in a single game, a leak
  /// across a session of them.
  Timer? _timer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;

    // Reduce motion suppresses the animation, not the wait: the point of
    // the pause is reading time, and taking it away would leave those
    // players with the abrupt exit everyone else just stopped getting.
    if (reduceMotionOf(context)) {
      _timer = Timer(widget.duration, _leave);
    } else {
      _controller.forward().whenComplete(_leave);
    }
  }

  void _leave() {
    if (_left || !mounted) return;
    _left = true;
    widget.onLeave();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Merged into one node, from OUTSIDE the GestureDetector. The
    // detector publishes a tap action of its own, and left unmerged that
    // action lands on an unlabelled node while the label lands on a leaf
    // with nothing to activate -- a screen reader then finds a button it
    // cannot name and a name it cannot press.
    return MergeSemantics(
      child: Semantics(
        button: true,
        label: 'Back to chat',
        onTap: _leave,
        child: GestureDetector(
          // Anywhere on the screen, not a button. The player who has read
          // the result should not have to find a target to say so.
          behavior: HitTestBehavior.opaque,
          onTap: _leave,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(child: widget.child),
              if (widget.showCountdown)
                // A hairline that drains, so the pause is visibly finite.
                // Without it a screen that leaves on its own reads as a
                // screen that froze and then glitched.
                AnimatedBuilder(
                  animation: _controller,
                  builder:
                      (context, _) => LinearProgressIndicator(
                        value: 1 - _controller.value,
                        minHeight: 2,
                        backgroundColor: Colors.transparent,
                        color: Theme.of(
                          context,
                        ).colorScheme.primary.withValues(alpha: 0.35),
                      ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

import 'dart:async';

import 'package:attune/app/theme/design_tokens.dart';
import 'package:flutter/material.dart';

/// How far up the finger must travel to lock a recording.
const double kStreakLockDragDistance = 96;

/// How long the written instruction stays before fading.
const Duration kStreakLockHintDuration = Duration(seconds: 3);

/// The swipe-to-lock affordance shown above the record button while a
/// streak is being held.
///
/// Two parts with different lifetimes: the padlock is the target the
/// finger travels toward and stays for the whole hold, while the written
/// instruction is a one-time teach that fades once read. Leaving the
/// sentence up for a full minute would clutter the viewfinder long after
/// it has stopped saying anything.
class StreakLockHint extends StatefulWidget {
  const StreakLockHint({super.key, required this.dragProgress});

  /// 0..1 toward the lock threshold.
  final double dragProgress;

  @override
  State<StreakLockHint> createState() => _StreakLockHintState();
}

class _StreakLockHintState extends State<StreakLockHint> {
  bool _captionVisible = true;

  /// A cancellable Timer rather than Future.delayed: the hint is torn
  /// down the moment the finger lifts, and an uncancellable delay would
  /// outlive the widget it belongs to.
  Timer? _captionTimer;

  @override
  void initState() {
    super.initState();
    _captionTimer = Timer(kStreakLockHintDuration, () {
      if (mounted) setState(() => _captionVisible = false);
    });
  }

  @override
  void dispose() {
    _captionTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.dragProgress.clamp(0.0, 1.0);
    final primary = Theme.of(context).colorScheme.primary;

    return IgnorePointer(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedOpacity(
            key: const ValueKey('streak-lock-caption'),
            opacity: _captionVisible ? 1 : 0,
            duration: const Duration(milliseconds: 350),
            child: Padding(
              padding: const EdgeInsets.only(bottom: Spacing.sm),
              child: Text(
                'Swipe up to record hands-free',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.white,
                  shadows: const [
                    // The viewfinder behind is arbitrary, so the text
                    // carries its own contrast.
                    Shadow(blurRadius: 8, color: Colors.black87),
                  ],
                ),
              ),
            ),
          ),

          // Rises toward the finger and warms to primary as the threshold
          // nears, so the gesture confirms itself before it completes.
          AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOut,
            transform: Matrix4.translationValues(0, -16 * t, 0),
            padding: const EdgeInsets.all(Spacing.sm),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Color.lerp(Colors.black38, primary, t),
            ),
            child: Icon(
              Icons.lock_outline_rounded,
              size: 20 + 6 * t,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

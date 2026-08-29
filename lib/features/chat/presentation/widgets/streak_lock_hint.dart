import 'dart:async';

import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/utils/animations/shake_transition.dart';
import 'package:attune/features/chat/presentation/widgets/voice_lock_pill.dart';
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

          // The voice recorder's pill, shared verbatim: the same gesture
          // in two features should present the same target. It owns its
          // own drag-rise and warming; this is the separate entrance --
          // it slides up out of the record button rather than appearing
          // where it lands, matching the voice scrim.
          ShakeTransition(
            axis: Axis.vertical,
            offset: 56,
            curve: Curves.easeOutBack,
            duration: const Duration(milliseconds: 930),
            child: VoiceLockPill(dragProgress: t),
          ),
        ],
      ),
    );
  }
}

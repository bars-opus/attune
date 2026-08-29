import 'package:attune/app/theme/design_tokens.dart';
import 'package:flutter/material.dart';

/// How far up the finger must travel to lock a voice recording.
const double kVoiceLockDragDistance = 96;

/// The swipe-to-lock target shown above the mic while recording.
///
/// A padlock over a chevron: the padlock is what the finger is travelling
/// toward, and the arrow says which way. The arrow fades as the threshold
/// nears — at that point it has nothing left to say and the padlock
/// speaks for itself.
class VoiceLockPill extends StatelessWidget {
  const VoiceLockPill({super.key, required this.dragProgress});

  /// 0..1 toward the lock threshold.
  final double dragProgress;

  @override
  Widget build(BuildContext context) {
    final t = dragProgress.clamp(0.0, 1.0);
    final colorScheme = Theme.of(context).colorScheme;

    return IgnorePointer(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        // Rises toward the travelling finger, so the gesture confirms
        // itself before it completes.
        transform: Matrix4.translationValues(0, -12 * t, 0),
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.sm,
          vertical: Spacing.md,
        ),
        decoration: BoxDecoration(
          color: Color.lerp(colorScheme.surface, colorScheme.primary, t),
          borderRadius: BorderRadius.circular(BorderRadiusTokens.full),
          boxShadow: const [
            BoxShadow(blurRadius: 12, color: Colors.black26),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.lock_outline_rounded,
              size: 20,
              color: Color.lerp(
                colorScheme.onSurface,
                colorScheme.onPrimary,
                t,
              ),
            ),
            const SizedBox(height: 2),
            Opacity(
              key: const ValueKey('voice-lock-chevron'),
              opacity: 1 - t,
              child: Icon(
                Icons.keyboard_arrow_up_rounded,
                size: 20,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

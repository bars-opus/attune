import 'package:attune/app/theme/design_tokens.dart';
import 'package:flutter/material.dart';

/// The floating "slide up to lock" pill that sits above the mic button
/// while a voice message is being held.
///
/// Mirrors WhatsApp's affordance: a vertical capsule showing a padlock and
/// an upward chevron, which fills in as the finger travels toward it and
/// disappears once the recording locks. Purely presentational — the drag
/// math and the lock decision live in ChatTextField.
class VoiceRecordingLockOverlay extends StatelessWidget {
  const VoiceRecordingLockOverlay({super.key, required this.progress});

  /// How far the finger has travelled toward the lock, 0.0 (just pressed)
  /// to 1.0 (at the lock threshold).
  final double progress;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final t = progress.clamp(0.0, 1.0);

    // The pill rises slightly and the chevron fades as the finger climbs,
    // so the gesture feels connected to the affordance rather than the
    // pill being a static decoration.
    return IgnorePointer(
      child: Transform.translate(
        offset: Offset(0, -8 * t),
        child: Container(
          width: 44,
          padding: const EdgeInsets.symmetric(vertical: Spacing.smMd),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(BorderRadiusTokens.full),
            boxShadow: [
              BoxShadow(
                color: colorScheme.shadow.withValues(alpha: 0.18),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.lock_outline_rounded,
                size: 20,
                // Warms toward the primary color as the lock nears, giving
                // the user feedback before they commit to releasing.
                color:
                    Color.lerp(
                      colorScheme.onSurfaceVariant,
                      colorScheme.primary,
                      t,
                    ) ??
                    colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: Spacing.xs),
              Opacity(
                opacity: 1.0 - t,
                child: Icon(
                  Icons.keyboard_arrow_up_rounded,
                  size: 18,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

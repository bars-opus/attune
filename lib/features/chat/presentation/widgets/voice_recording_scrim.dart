import 'dart:ui';

import 'package:flutter/foundation.dart';

import 'package:attune/core/utils/exports/export_screens.dart';

import 'voice_lock_pill.dart';
import 'voice_mic_halo.dart';
import 'voice_recording_bar.dart';

/// Fixed rather than colorScheme.error: the scrim paints its own dark
/// ground, so a theme error colour tuned for a light surface can wash out
/// against it.
const Color _danger = Color(0xFFFF5A5A);

/// The live values the scrim draws, pushed from the composer through a
/// notifier so the overlay rebuilds on its own schedule.
@immutable
class VoiceScrimData {
  const VoiceScrimData({
    this.elapsed = Duration.zero,
    this.amplitude = 0.0,
    this.levels = const <double>[],
    this.isCancelling = false,
    this.progress = 0.0,
    this.lockProgress = 0.0,
    this.isLocked = false,
    this.isPaused = false,
  });

  final Duration elapsed;
  final double amplitude;
  final List<double> levels;
  final bool isCancelling;

  /// Fraction of the maximum recording length elapsed, drawn as the ring
  /// around the mic.
  final double progress;

  /// How far the finger has travelled toward the lock (0..1), driving the
  /// pill's fill and rise.
  final double lockProgress;

  /// Once locked the finger is off the button: the ring becomes send and a
  /// pause control appears under the waveform.
  final bool isLocked;

  final bool isPaused;
}

/// The dimmed backdrop shown while a voice note is being recorded, using
/// the same treatment as the focused message-action menu: a 12px blur
/// under black.
///
/// Deliberately an Overlay entry rather than a Navigator route, which is
/// how the focused menu does it. A route mid-gesture would move the
/// pointer to a new Navigator layer and break the drag that lock and
/// cancel both read from; an overlay leaves the composer's gesture in one
/// uninterrupted stream.
///
/// Against a dark scrim the recording UI needs no surface of its own, so
/// the counter, the waveform and the slide-to-cancel hint sit directly on
/// the backdrop in white.
class VoiceRecordingScrim extends StatelessWidget {
  const VoiceRecordingScrim({
    super.key,
    required this.animation,
    required this.data,
    required this.micRect,
    this.onCancel,
    this.onSend,
    this.onTogglePause,
  });

  final Animation<double> animation;
  final ValueListenable<VoiceScrimData> data;

  /// Where the composer's mic sits in global coordinates. The mic is drawn
  /// here rather than left in the composer so it sits ABOVE the backdrop —
  /// under it the control the finger is holding reads as dimmed out.
  final Rect micRect;

  /// Discards the take. The delete button is a tap alternative to the
  /// slide gesture, not a replacement for it.
  final VoidCallback? onCancel;

  /// Sends the take. Bound to the ring once locked: it is the largest,
  /// most central control, which should carry the primary action.
  final VoidCallback? onSend;

  final VoidCallback? onTogglePause;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([animation, data]),
      builder: (context, _) {
        final t = animation.value;
        final elapsed = data.value.elapsed;
        final amplitude = data.value.amplitude;
        final levels = data.value.levels;
        final isCancelling = data.value.isCancelling;
        final progress = data.value.progress;
        final lockProgress = data.value.lockProgress;
        final isLocked = data.value.isLocked;
        final isPaused = data.value.isPaused;

        // Each layer opts out of hit testing individually rather than the
        // whole scrim sitting under one IgnorePointer. A blanket outer one
        // blocks its entire subtree, so a nested ignoring:false cannot
        // re-enable the delete button — the composer's mic still owns the
        // live drag because every layer except the delete button declines
        // pointers.
        return Stack(
          children: [
            IgnorePointer(
              child: ClipRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 12 * t, sigmaY: 12 * t),
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.55 * t),
                  ),
                ),
              ),
            ),
            // Drawn at the mic's real position so the visible control and
            // the gesture's origin stay the same point. Expanded around
            // the slot's CENTRE, not laid into it: the composer's mic box
            // is a 40px icon target, which would clip the 84px disc and
            // its ring down to icon size.
            Positioned.fromRect(
              rect: Rect.fromCenter(
                center: micRect.center,
                width: VoiceMicHalo.haloExtent,
                height: VoiceMicHalo.haloExtent,
              ),
              // Locked: the ring carries the primary action, so it takes
              // pointers. Held: it must not, or it would compete with the
              // composer's mic for the finger already on it.
              child: IgnorePointer(
                ignoring: !isLocked,
                child: Center(
                  child: GestureDetector(
                    key: isLocked ? const ValueKey('voice-scrim-send') : null,
                    behavior: HitTestBehavior.opaque,
                    onTap: isLocked ? onSend : null,
                    child: VoiceMicHalo(
                      amplitude: amplitude,
                      isRecording: true,
                      progress: progress,
                      child: Icon(
                        isLocked
                            ? Icons.arrow_upward_rounded
                            : Icons.mic_rounded,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (!isLocked)
              Positioned(
                left: micRect.center.dx - VoiceLockPill.width / 2,
                // Measured from the halo's top rather than the icon slot's,
                // so the bigger ring cannot grow up into the pill.
                // Clears the halo's full extent plus a deliberate gap: a
                // pill resting on the ring's edge reads as part of it.
                top: micRect.center.dy - VoiceMicHalo.haloExtent / 2 - 72,
                child: IgnorePointer(
                  child: Opacity(
                    opacity: t,
                    // Rises out from behind the ring. The app's existing
                    // ShakeTransition already does exactly this: a positive
                    // vertical offset tweened to zero starts the child low
                    // and settles it in place.
                    child: ShakeTransition(
                      axis: Axis.vertical,
                      offset: 56,
                      // easeOutBack overshoots once and settles, rather than
                      // elasticOut's repeated bounce — a single confident
                      // arrival reads better on a control you are mid-hold on.
                      curve: Curves.easeOutBack,
                      duration: const Duration(milliseconds: 930),
                      child: VoiceLockPill(dragProgress: lockProgress),
                    ),
                  ),
                ),
              ),
            Positioned.fill(
              // NOT a blanket IgnorePointer: the pause button lives in this
              // column, and an outer ignore blocks its whole subtree — a
              // nested ignoring:false cannot re-enable it. The inert
              // children opt out individually instead.
              child: Opacity(
                opacity: t,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IgnorePointer(
                      child: AnimatedRollingCounter(
                        key: const ValueKey('voice-scrim-counter'),
                        count: elapsed.inSeconds,
                        suffix: 's',
                        style: Theme.of(
                          context,
                        ).textTheme.displaySmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                    const SizedBox(height: Spacing.lg),
                    IgnorePointer(
                      child: SizedBox(
                        height: 48,
                        width: MediaQuery.sizeOf(context).width * 0.6,
                        child: VoiceScrimWaveform(
                          levels: levels,
                          current: amplitude,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    // Locked only: while held, the finger is on the mic and
                    // cannot reach a second control anyway.
                    if (isLocked) ...[
                      const SizedBox(height: Spacing.lg),
                      GestureDetector(
                        key: const ValueKey('voice-scrim-pause'),
                        behavior: HitTestBehavior.opaque,
                        onTap: onTogglePause,
                        child: Container(
                          width: 52,
                          height: 52,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white,
                          ),
                          child: Icon(
                            isPaused
                                ? Icons.play_arrow_rounded
                                : Icons.pause_rounded,
                            color: Colors.black87,
                            size: 28,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            // Inline with the ring rather than stacked under the waveform:
            // the hint describes a drag that starts at the ring, so it
            // reads along the path the finger takes.
            Positioned(
              left: 0,
              right: micRect.width + Spacing.md,
              top: micRect.center.dy - 24,
              height: 48,
              child: Opacity(
                opacity: t,
                // Slides leftward out of the ring: a positive horizontal
                // offset starts the row to the right and travels it to
                // rest, which is the direction the cancel drag goes.
                child: ShakeTransition(
                  offset: 160,
                  curve: Curves.easeOutBack,
                  duration: const Duration(milliseconds: 930),
                  child: Row(
                    children: [
                      const SizedBox(width: Spacing.md),
                      // A tap target as well as a label for the drag: a
                      // finger already holding the mic cannot always reach a
                      // clean swipe.
                      GestureDetector(
                        key: const ValueKey('voice-scrim-delete'),
                        behavior: HitTestBehavior.opaque,
                        onTap: onCancel,
                        child: Container(
                          width: 44,
                          height: 44,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            // Opaque white: the red belongs to the glyph,
                            // which needs a solid ground to read against the
                            // blurred scrim behind it.
                            color: Colors.white,
                          ),
                          child: const Icon(
                            Icons.delete_outline_rounded,
                            color: _danger,
                            size: 22,
                          ),
                        ),
                      ),
                      const SizedBox(width: Spacing.sm),
                      Expanded(
                        child: IgnorePointer(
                          child: AnimatedOpacity(
                            duration: const Duration(milliseconds: 150),
                            opacity: isCancelling ? 1.0 : 0.75,
                            child: Row(
                              // Left-aligned, so the text reads as this
                              // button's caption rather than drifting into
                              // the middle of the row.
                              mainAxisAlignment: MainAxisAlignment.start,
                              children: [
                                if (!isCancelling)
                                  const Icon(
                                    Icons.keyboard_arrow_left_rounded,
                                    size: 18,
                                    color: Colors.white,
                                  ),
                                Flexible(
                                  child: Text(
                                    isCancelling
                                        ? 'Release to cancel'
                                        : 'slide to cancel',
                                    key: const ValueKey(
                                      'voice-scrim-cancel-hint',
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodyMedium?.copyWith(
                                      color:
                                          isCancelling ? _danger : Colors.white,
                                      fontWeight:
                                          isCancelling
                                              ? FontWeight.w600
                                              : FontWeight.w400,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

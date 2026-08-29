import 'dart:ui';

import 'package:flutter/foundation.dart';

import 'package:attune/core/utils/exports/export_screens.dart';

import 'voice_recording_bar.dart';

/// The dimmed backdrop shown while a voice note is being recorded, using
/// the same treatment as the focused message-action menu: a 12px blur
/// under black at 30%.
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
/// The live values the scrim draws, pushed from the composer through a
/// notifier so the overlay rebuilds on its own schedule.
@immutable
class VoiceScrimData {
  const VoiceScrimData({
    this.elapsed = Duration.zero,
    this.amplitude = 0.0,
    this.levels = const <double>[],
    this.isCancelling = false,
  });

  final Duration elapsed;
  final double amplitude;
  final List<double> levels;
  final bool isCancelling;
}

class VoiceRecordingScrim extends StatelessWidget {
  const VoiceRecordingScrim({
    super.key,
    required this.animation,
    required this.data,
  });

  final Animation<double> animation;
  final ValueListenable<VoiceScrimData> data;

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
        return IgnorePointer(
          // The composer beneath owns the gesture: this is a backdrop, not
          // a target. Swallowing pointers here would kill the very drag
          // the scrim exists to accompany.
          child: Stack(
            children: [
              Positioned.fill(
                child: ClipRect(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 12 * t, sigmaY: 12 * t),
                    child: Container(
                      color: Colors.black.withValues(alpha: 0.55 * t),
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: Opacity(
                  opacity: t,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      AnimatedRollingCounter(
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
                      const SizedBox(height: Spacing.lg),
                      SizedBox(
                        height: 48,
                        width: MediaQuery.sizeOf(context).width * 0.6,
                        child: VoiceScrimWaveform(
                          levels: levels,
                          current: amplitude,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: Spacing.xl),
                      AnimatedOpacity(
                        duration: const Duration(milliseconds: 150),
                        opacity: isCancelling ? 1.0 : 0.75,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (!isCancelling)
                              const Icon(
                                Icons.keyboard_arrow_left_rounded,
                                size: 18,
                                color: Colors.white,
                              ),
                            Text(
                              isCancelling
                                  ? 'Release to cancel'
                                  : 'slide to cancel',
                              key: const ValueKey('voice-scrim-cancel-hint'),
                              style: Theme.of(
                                context,
                              ).textTheme.bodyMedium?.copyWith(
                                color: Colors.white,
                                fontWeight:
                                    isCancelling
                                        ? FontWeight.w600
                                        : FontWeight.w400,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

import 'dart:async';

import 'package:attune/core/ui/feedback/haptics.dart';
import 'package:attune/core/ui/motion/reduce_motion.dart';
import 'package:attune/core/widgets/rolling_duration.dart';
import 'package:attune/features/chat/presentation/state/voice_playback_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// What one bubble needs from the controller: null unless it is the
/// current note. A record compares by value, so a position frame for
/// ANOTHER note leaves this bubble's projection null == null — no rebuild.
typedef _BubbleView = ({
  bool playing,
  bool busy,
  Duration position,
  double rate,
});

/// Playback UI for a voice message bubble: play/pause, a tap-to-seek
/// waveform, elapsed/total duration and a speed chip. A VIEW of
/// [voicePlaybackControllerProvider]: the controller owns the engine, so
/// this widget can be recycled by the list while its note keeps playing
/// (chat review #21).
class VoiceMessagePlayer extends ConsumerWidget {
  const VoiceMessagePlayer({
    super.key,
    required this.messageId,
    required this.resolveAudioUrl,
    required this.durationMs,
    required this.waveform,
    this.mediaKey,
    this.ownerId,
    this.serverMessageId,
    this.foregroundColor,
    this.metadataColor,
    this.accentColor,
  });

  final String messageId;

  /// Resolved on PLAY, not on build. durationMs and waveform both come off
  /// the message row, so the bubble draws itself with no network at all.
  /// Returns null when the media cannot be resolved.
  final Future<String?> Function() resolveAudioUrl;

  /// Storage key: the controller plays the bytes from ChatMediaCache when
  /// they are on disk, and downloads them there once otherwise (#28).
  final String? mediaKey;

  /// The conversation (relationship id) this note belongs to, so leaving a
  /// different chat does not stop it.
  final String? ownerId;

  /// The message's server row id: a realtime hard delete names only that.
  final String? serverMessageId;

  final int durationMs;
  final List<int> waveform;
  final Color? foregroundColor;
  final Color? metadataColor;
  final Color? accentColor;

  static const double _waveformWidth = 172;

  /// Minimum tap target (Material): the play button's size, and the speed
  /// chip's tap area.
  static const double _minTapSize = 48;

  /// One screen-reader step on the waveform slider.
  static const Duration _seekStep = Duration(seconds: 5);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(
      voicePlaybackControllerProvider.select<_BubbleView?>(
        (s) =>
            s.isCurrent(messageId)
                ? (
                  playing: s.isPlaying,
                  busy: s.isLoading || s.isBuffering,
                  position: s.position,
                  rate: s.rate,
                )
                : null,
      ),
    );
    final controller = ref.read(voicePlaybackControllerProvider.notifier);
    final isCurrent = view != null;
    final isPlaying = view?.playing ?? false;
    final isBusy = view?.busy ?? false;
    final position = view?.position ?? Duration.zero;

    ref.listen<int>(
      voicePlaybackControllerProvider.select((s) => s.failureCount),
      (previous, next) {
        if (ref.read(voicePlaybackControllerProvider).failedMessageId !=
            messageId) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('That voice message could not play')),
        );
      },
    );

    final total = Duration(milliseconds: durationMs);
    final progressFraction =
        total.inMilliseconds == 0
            ? 0.0
            : (position.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);

    final colorScheme = Theme.of(context).colorScheme;
    final foreground = foregroundColor ?? colorScheme.onSurface;
    final metadata = metadataColor ?? colorScheme.onSurfaceVariant;
    final accent = accentColor ?? colorScheme.primary;
    final reduceMotion = reduceMotionOf(context);

    void seekTo(Duration target) {
      final clamped =
          target < Duration.zero
              ? Duration.zero
              : (target > total ? total : target);
      unawaited(controller.seek(messageId, clamped));
    }

    void seekFromLocalX(double localX) {
      final fraction = (localX / _waveformWidth).clamp(0.0, 1.0);
      seekTo(Duration(milliseconds: (durationMs * fraction).round()));
    }

    void seekFromTap(TapUpDetails d) => seekFromLocalX(d.localPosition.dx);
    void seekFromDragStart(DragStartDetails d) =>
        seekFromLocalX(d.localPosition.dx);
    void seekFromDragUpdate(DragUpdateDetails d) =>
        seekFromLocalX(d.localPosition.dx);

    // What the waveform slider says, now and one [_seekStep] either way.
    String spokenAt(Duration at) =>
        '${_spoken(_clampTo(at, total))} of ${_spoken(total)}';
    final durationStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
      color: metadata,
      fontWeight: FontWeight.w500,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    // Shown only for the current note (playing or paused mid-way), but its
    // slot is always laid out, so the bubble never changes size when it
    // appears.
    final showSpeedChip = isCurrent && (isPlaying || position > Duration.zero);

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Semantics(
          button: true,
          label:
              isBusy && !isPlaying
                  ? 'Loading voice message'
                  : isPlaying
                  ? 'Pause voice message'
                  : 'Play voice message',
          child: InkWell(
            onTap:
                () => unawaited(
                  controller.toggle(
                    messageId,
                    resolveAudioUrl,
                    ownerId: ownerId,
                    serverMessageId: serverMessageId,
                    mediaKey: mediaKey,
                  ),
                ),
            customBorder: const CircleBorder(),
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: accent,
                shape: BoxShape.circle,
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x18000000),
                    blurRadius: 4,
                    offset: Offset(0, 1),
                  ),
                ],
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Icon(
                    isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    size: 32,
                    // ignore: deprecated_member_use
                    color: colorScheme.background,
                  ),
                  if (isBusy)
                    SizedBox(
                      key: const ValueKey('voice_loading_ring'),
                      width: 44,
                      height: 44,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        // Reduce motion: a still arc says "working" without
                        // spinning.
                        value: reduceMotion ? 0.75 : null,
                        // ignore: deprecated_member_use
                        color: colorScheme.background,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: _waveformWidth,
          // As tall as the play button (the row is already that tall, so
          // nothing grows), which gives the speed chip a full 48×48 tap area
          // over the bottom-right corner.
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: _minTapSize),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // A slider for screen readers: increase/decrease seek
                    // by [_seekStep]. Only the current note can seek, so
                    // only it offers the actions.
                    Semantics(
                      slider: true,
                      label: 'Voice message position',
                      value: spokenAt(position),
                      increasedValue:
                          isCurrent ? spokenAt(position + _seekStep) : null,
                      decreasedValue:
                          isCurrent ? spokenAt(position - _seekStep) : null,
                      onIncrease:
                          isCurrent ? () => seekTo(position + _seekStep) : null,
                      onDecrease:
                          isCurrent ? () => seekTo(position - _seekStep) : null,
                      child: GestureDetector(
                        key: const ValueKey('voice_message_waveform'),
                        behavior: HitTestBehavior.opaque,
                        excludeFromSemantics: true,
                        onTapUp: seekFromTap,
                        onHorizontalDragStart: seekFromDragStart,
                        onHorizontalDragUpdate: seekFromDragUpdate,
                        child: SizedBox(
                          width: _waveformWidth,
                          height: 30,
                          child: CustomPaint(
                            painter: _WaveformPainter(
                              waveform: waveform,
                              progressFraction: progressFraction,
                              color: accent,
                              trackColor: foreground,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 1),
                    Row(
                      children: [
                        RollingDuration(
                          keyPrefix: 'voice-playback-duration',
                          value:
                              isPlaying || position > Duration.zero
                                  ? position
                                  : total,
                          alwaysShowMinutes: true,
                          style: durationStyle,
                        ),
                        const Spacer(),
                        // Slot reserved even when hidden (maintainSize): no
                        // jump when the chip appears. Only the pill is drawn
                        // here; its tap area is the 48×48 overlay below.
                        Visibility(
                          visible: showSpeedChip,
                          maintainSize: true,
                          maintainAnimation: true,
                          maintainState: true,
                          child: _SpeedPill(
                            rate: view?.rate ?? 1.0,
                            color: metadata,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                if (showSpeedChip)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    width: _minTapSize,
                    height: _minTapSize,
                    child: _SpeedChipTapArea(
                      rate: view.rate,
                      onTap: () {
                        ref.read(hapticsProvider).selection();
                        unawaited(controller.cycleRate());
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  static Duration _clampTo(Duration value, Duration total) =>
      value < Duration.zero ? Duration.zero : (value > total ? total : value);

  /// "1 minute 5 seconds": what a screen reader should say, rather than
  /// "zero colon zero five".
  static String _spoken(Duration value) {
    final minutes = value.inMinutes;
    final seconds = value.inSeconds % 60;
    String unit(int n, String word) => '$n $word${n == 1 ? '' : 's'}';
    if (minutes == 0) return unit(seconds, 'second');
    if (seconds == 0) return unit(minutes, 'minute');
    return '${unit(minutes, 'minute')} ${unit(seconds, 'second')}';
  }
}

String _speedLabel(double rate) =>
    '${rate == rate.roundToDouble() ? rate.toInt() : rate}×';

/// The speed chip as drawn: a narrow pill centred in a 48 dp wide slot.
/// Visual only: the tap target is [_SpeedChipTapArea].
class _SpeedPill extends StatelessWidget {
  const _SpeedPill({required this.rate, required this.color});
  final double rate;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minWidth: VoiceMessagePlayer._minTapSize,
        ),
        child: Center(
          widthFactor: 1,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: color.withValues(alpha: 0.14),
            ),
            child: Text(
              _speedLabel(rate),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The speed chip's 48×48 tap area over the player's bottom-right corner:
/// the pill's slot plus the tail of the waveform above it (the player is
/// only as tall as its play button, so a full-size target cannot avoid
/// that overlap without growing the bubble).
///
/// Translucent and drawn over the waveform, so a pointer there reaches
/// BOTH detectors: a tap cycles the speed (this one joins the gesture arena
/// first and wins the tap), while a horizontal drag is won by the
/// waveform's drag recognizer, so scrubbing works across the whole
/// waveform. Outside this corner the waveform's taps seek as before.
class _SpeedChipTapArea extends StatelessWidget {
  const _SpeedChipTapArea({required this.rate, required this.onTap});
  final double rate;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Playback speed ${_speedLabel(rate)}',
      // One announcement: this label, not the pill's text again.
      excludeSemantics: true,
      onTap: onTap,
      child: GestureDetector(
        key: const ValueKey('voice_speed_chip'),
        behavior: HitTestBehavior.translucent,
        excludeFromSemantics: true,
        onTap: onTap,
      ),
    );
  }
}

/// The bar heights (0..1) the playback waveform draws for [waveform] at
/// [width], one per bar.
///
/// Point-sampled, NOT aggregated. Collapsing the ~3 stored samples that
/// fall behind each bar by peak discarded most of the recording's detail
/// and lifted quiet bars toward loud ones, so the same audio looked
/// visibly flatter on playback than it had while recording — the live
/// painter draws one bar per raw reading and does no aggregation at all.
/// Any aggregator has the same effect to some degree; peak is simply the
/// most flattering of them.
List<double> voiceWaveformBars(List<int> waveform, double width) {
  if (waveform.isEmpty) return const <double>[];
  final barCount = (width / kVoiceWaveformStride).floor().clamp(
    1,
    waveform.length,
  );
  return List<double>.generate(barCount, (i) {
    final index = (i * waveform.length / barCount).floor().clamp(
      0,
      waveform.length - 1,
    );
    return waveform[index] / 255;
  });
}

/// Bar spacing. The 100 stored samples would be sub-pixel at a bubble
/// width, so the waveform shows as many of them as fit legibly.
const double kVoiceWaveformStride = 4.0;

/// Keeps silence visible without inflating it. Matches the live
/// recording waveform's own floor, so the same audio draws the same way
/// while recording and on playback.
const double _minBarHeight = 2.0;

class _WaveformPainter extends CustomPainter {
  const _WaveformPainter({
    required this.waveform,
    required this.progressFraction,
    required this.color,
    required this.trackColor,
  });

  final List<int> waveform;
  final double progressFraction;
  final Color color;
  final Color trackColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (waveform.isEmpty) return;

    final bars = voiceWaveformBars(waveform, size.width);
    final barCount = bars.length;
    final progressIndex = (barCount * progressFraction).round();
    final centerY = size.height / 2;

    for (var i = 0; i < barCount; i++) {
      // Floored in PIXELS, matching the live recording waveform. A 0.12
      // fraction floor lifted quiet audio to 12% of the bubble height,
      // well above where the same moment was drawn live — the two are the
      // same numbers, so they should look the same.
      final barHeight = (size.height * bars[i]).clamp(
        _minBarHeight,
        size.height,
      );
      final paint =
          Paint()
            ..color =
                i < progressIndex ? color : trackColor.withValues(alpha: 0.35)
            ..strokeCap = StrokeCap.round
            ..strokeWidth = 2.5;

      final x = i * kVoiceWaveformStride + kVoiceWaveformStride / 2;
      canvas.drawLine(
        Offset(x, centerY - barHeight / 2),
        Offset(x, centerY + barHeight / 2),
        paint,
      );
    }

    // Playhead knob — gives the scrub gesture something to grab onto and
    // makes the current position readable at a glance when paused.
    if (progressFraction > 0) {
      final knobX = (size.width * progressFraction).clamp(0.0, size.width);
      canvas.drawCircle(Offset(knobX, centerY), 5, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter oldDelegate) =>
      oldDelegate.progressFraction != progressFraction ||
      oldDelegate.waveform != waveform ||
      oldDelegate.color != color ||
      oldDelegate.trackColor != trackColor;
}

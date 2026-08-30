import 'dart:async';

import 'package:attune/features/chat/presentation/providers/voice_playback_provider.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Playback UI for a voice message bubble: play/pause, a tap-to-seek
/// waveform, and elapsed/total duration. Enforces one-at-a-time playback
/// app-wide via [currentlyPlayingVoiceMessageIdProvider] — starting
/// playback here stops whatever the provider currently points to.
class VoiceMessagePlayer extends ConsumerStatefulWidget {
  const VoiceMessagePlayer({
    super.key,
    required this.messageId,
    required this.audioUrl,
    required this.durationMs,
    required this.waveform,
  });

  final String messageId;
  final String audioUrl;
  final int durationMs;
  final List<int> waveform;

  @override
  ConsumerState<VoiceMessagePlayer> createState() => _VoiceMessagePlayerState();
}

class _VoiceMessagePlayerState extends ConsumerState<VoiceMessagePlayer> {
  final _player = AudioPlayer();
  Duration _position = Duration.zero;
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    _player.onPositionChanged.listen((position) {
      if (mounted) setState(() => _position = position);
    });
    _player.onPlayerComplete.listen((_) {
      if (!mounted) return;
      setState(() {
        _isPlaying = false;
        _position = Duration.zero;
      });
      if (ref.read(currentlyPlayingVoiceMessageIdProvider) ==
          widget.messageId) {
        ref.read(currentlyPlayingVoiceMessageIdProvider.notifier).state = null;
      }
    });
  }

  @override
  void dispose() {
    // Ensures leaving the message list (this widget leaving the tree) stops
    // playback — no background/lock-screen playback, per the design spec's
    // explicit out-of-scope list.
    _player.dispose();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    final totalSeconds = d.inSeconds;
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  Future<void> _togglePlayback() async {
    if (_isPlaying) {
      await _player.pause();
      setState(() => _isPlaying = false);
      return;
    }

    final currentlyPlaying = ref.read(currentlyPlayingVoiceMessageIdProvider);
    if (currentlyPlaying != null && currentlyPlaying != widget.messageId) {
      // Enforced via the provider only — this widget doesn't hold a
      // reference to the other bubble's AudioPlayer. Each VoiceMessagePlayer
      // instance listens for the provider changing away from its own
      // messageId and pauses itself in response (see the ref.listen wiring
      // in build() below), so setting the provider here is sufficient to
      // stop the other bubble.
    }
    // Cross-media pause: stop any currently-playing video message before
    // this voice message starts. The reverse (video stopping a playing
    // voice message) is wired symmetrically in VideoMessagePlayer's own
    // _togglePlayback.
    if (ref.read(currentlyPlayingVideoMessageIdProvider) != null) {
      ref.read(currentlyPlayingVideoMessageIdProvider.notifier).state = null;
    }
    ref.read(currentlyPlayingVoiceMessageIdProvider.notifier).state =
        widget.messageId;

    // audioplayers' UrlSource only works for real HTTP(S) URLs. A voice
    // message just recorded by the current user is initially playable only
    // from message.localMediaPath (a local file path) before the upload
    // completes and signedMediaUrl becomes available — UrlSource would fail
    // on a raw file path, so branch on the source shape instead.
    final source =
        widget.audioUrl.startsWith('http')
            ? UrlSource(widget.audioUrl)
            : DeviceFileSource(widget.audioUrl);
    await _player.play(source);
    setState(() => _isPlaying = true);
  }

  Future<void> _seekToFraction(double fraction) async {
    final target = Duration(
      milliseconds: (widget.durationMs * fraction.clamp(0.0, 1.0)).round(),
    );
    await _player.seek(target);
  }

  @override
  Widget build(BuildContext context) {
    // Another bubble became the currently-playing one — pause this one.
    ref.listen<String?>(currentlyPlayingVoiceMessageIdProvider, (
      previous,
      next,
    ) {
      if (next != widget.messageId && _isPlaying) {
        _player.pause();
        setState(() => _isPlaying = false);
      }
    });

    final total = Duration(milliseconds: widget.durationMs);
    final progressFraction =
        total.inMilliseconds == 0
            ? 0.0
            : _position.inMilliseconds / total.inMilliseconds;

    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          button: true,
          label: _isPlaying ? 'Pause voice message' : 'Play voice message',
          child: InkWell(
            onTap: _togglePlayback,
            customBorder: const CircleBorder(),
            child: SizedBox(
              width: 40,
              height: 40,
              child: Icon(
                _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                size: 30,
                color: colorScheme.onSurface,
              ),
            ),
          ),
        ),
        const SizedBox(width: 4),
        // Scrub by dragging as well as tapping: on a ~140px waveform a
        // tap-only target makes precise seeking within a multi-minute
        // message impractical.
        GestureDetector(
          key: const ValueKey('voice_message_waveform'),
          behavior: HitTestBehavior.opaque,
          onTapUp: (details) => _seekFromLocalX(details.localPosition.dx),
          onHorizontalDragStart:
              (details) => _seekFromLocalX(details.localPosition.dx),
          onHorizontalDragUpdate:
              (details) => _seekFromLocalX(details.localPosition.dx),
          child: SizedBox(
            width: 140,
            height: 34,
            child: CustomPaint(
              painter: _WaveformPainter(
                waveform: widget.waveform,
                progressFraction: progressFraction,
                color: colorScheme.primary,
                trackColor: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          _formatDuration(
            _isPlaying || _position > Duration.zero ? _position : total,
          ),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }

  /// Maps an x offset within the waveform to a seek position.
  ///
  /// Divides by the waveform's own fixed width rather than the enclosing
  /// render box's: the gesture's localPosition is already relative to the
  /// waveform (the GestureDetector wraps only that SizedBox), while the
  /// State's context covers the whole row including the play button and
  /// duration label. Using the box width here would compress the mapping
  /// and seek short on every tap.
  void _seekFromLocalX(double localX) {
    unawaited(_seekToFraction((localX / _waveformWidth).clamp(0.0, 1.0)));
  }

  static const double _waveformWidth = 140;
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

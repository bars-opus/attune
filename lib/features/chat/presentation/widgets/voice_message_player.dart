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
  ConsumerState<VoiceMessagePlayer> createState() =>
      _VoiceMessagePlayerState();
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
      if (ref.read(currentlyPlayingVoiceMessageIdProvider) == widget.messageId) {
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
    ref.read(currentlyPlayingVoiceMessageIdProvider.notifier).state =
        widget.messageId;

    // audioplayers' UrlSource only works for real HTTP(S) URLs. A voice
    // message just recorded by the current user is initially playable only
    // from message.localMediaPath (a local file path) before the upload
    // completes and signedMediaUrl becomes available — UrlSource would fail
    // on a raw file path, so branch on the source shape instead.
    final source = widget.audioUrl.startsWith('http')
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
    ref.listen<String?>(currentlyPlayingVoiceMessageIdProvider, (previous, next) {
      if (next != widget.messageId && _isPlaying) {
        _player.pause();
        setState(() => _isPlaying = false);
      }
    });

    final total = Duration(milliseconds: widget.durationMs);
    final progressFraction = total.inMilliseconds == 0
        ? 0.0
        : _position.inMilliseconds / total.inMilliseconds;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          onPressed: _togglePlayback,
          icon: Icon(_isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded),
        ),
        GestureDetector(
          key: const ValueKey('voice_message_waveform'),
          onTapUp: (details) {
            final box = context.findRenderObject() as RenderBox?;
            if (box == null) return;
            final localX = details.localPosition.dx;
            final fraction = (localX / box.size.width).clamp(0.0, 1.0);
            unawaited(_seekToFraction(fraction));
          },
          child: SizedBox(
            width: 140,
            height: 32,
            child: CustomPaint(
              painter: _WaveformPainter(
                waveform: widget.waveform,
                progressFraction: progressFraction,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          _formatDuration(_isPlaying || _position > Duration.zero ? _position : total),
        ),
      ],
    );
  }
}

class _WaveformPainter extends CustomPainter {
  const _WaveformPainter({
    required this.waveform,
    required this.progressFraction,
    required this.color,
  });

  final List<int> waveform;
  final double progressFraction;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (waveform.isEmpty) return;
    final barWidth = size.width / waveform.length;
    final progressIndex = (waveform.length * progressFraction).round();

    for (var i = 0; i < waveform.length; i++) {
      final normalizedHeight = (waveform[i] / 255).clamp(0.05, 1.0);
      final barHeight = size.height * normalizedHeight;
      final paint = Paint()
        ..color = i < progressIndex ? color : color.withValues(alpha: 0.3);
      final x = i * barWidth;
      canvas.drawRect(
        Rect.fromLTWH(
          x,
          (size.height - barHeight) / 2,
          barWidth * 0.6,
          barHeight,
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter oldDelegate) =>
      oldDelegate.progressFraction != progressFraction ||
      oldDelegate.waveform != waveform;
}

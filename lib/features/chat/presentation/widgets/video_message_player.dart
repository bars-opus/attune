import 'dart:io';

import 'package:attune/features/chat/presentation/providers/voice_playback_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

/// Playback UI for a video message bubble: poster-first with a play button,
/// lazy VideoPlayerController construction (not until first tap — the one
/// deliberate divergence from VoiceMessagePlayer's eager AudioPlayer
/// construction, since a list of ten video messages must not spin up ten
/// native video surfaces). Enforces one-at-a-time playback app-wide via
/// currentlyPlayingVideoMessageIdProvider, additionally cross-pausing any
/// currently-playing voice message (and vice versa, wired symmetrically in
/// VoiceMessagePlayer — see that file's own ref.listen).
class VideoMessagePlayer extends ConsumerStatefulWidget {
  const VideoMessagePlayer({
    super.key,
    required this.messageId,
    required this.videoUrl,
    required this.thumbnailUrl,
    required this.durationMs,
    required this.width,
    required this.height,
  });

  final String messageId;
  final String videoUrl;
  final String? thumbnailUrl;
  final int durationMs;
  final int width;
  final int height;

  @override
  ConsumerState<VideoMessagePlayer> createState() =>
      _VideoMessagePlayerState();
}

class _VideoMessagePlayerState extends ConsumerState<VideoMessagePlayer> {
  VideoPlayerController? _controller;
  bool _isPlaying = false;
  bool _isMuted = false;

  @override
  void dispose() {
    // No background/lock-screen playback — leaving the message list stops
    // playback, matching VoiceMessagePlayer's identical guarantee.
    _controller?.dispose();
    super.dispose();
  }

  double get _aspectRatio =>
      widget.height == 0 ? 16 / 9 : widget.width / widget.height;

  Future<void> _togglePlayback() async {
    if (_isPlaying) {
      await _controller?.pause();
      setState(() => _isPlaying = false);
      return;
    }

    // Cross-media pause: stop any currently-playing voice message before
    // this video starts. The reverse (voice stopping a playing video) is
    // wired symmetrically in VoiceMessagePlayer's own ref.listen. Written
    // synchronously, before the controller is constructed/initialized —
    // matching VoiceMessagePlayer's established ordering of writing the
    // provider before its own blocking await — so the cross-pause takes
    // effect immediately regardless of how long controller.initialize()
    // takes (or whether it resolves at all on a given platform).
    if (ref.read(currentlyPlayingVoiceMessageIdProvider) != null) {
      ref.read(currentlyPlayingVoiceMessageIdProvider.notifier).state = null;
    }
    ref.read(currentlyPlayingVideoMessageIdProvider.notifier).state =
        widget.messageId;

    if (_controller == null) {
      // Local-vs-remote source branching copies VoiceMessagePlayer's
      // startsWith('http') check exactly.
      final controller = widget.videoUrl.startsWith('http')
          ? VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl))
          : VideoPlayerController.file(File(widget.videoUrl));
      controller.addListener(() {
        if (!mounted) return;
        if (!controller.value.isPlaying && _isPlaying) {
          setState(() => _isPlaying = false);
        }
      });
      _controller = controller;
      try {
        await controller.initialize();
      } catch (_) {
        // Playback isn't available (unsupported codec, unreachable URL, no
        // platform video decoder on this host) — fall back to the poster
        // rather than leaving an unhandled exception in flight. The
        // cross-media pause above has already taken effect (voice was
        // stopped), but this widget itself never actually started playing
        // — so the video provider must be rolled back to null rather than
        // left pointing at a message that isn't playing. Guarded to this
        // widget's own messageId so a fast subsequent tap elsewhere (which
        // would have reassigned the provider to a different message before
        // this catch runs) can't be clobbered.
        if (ref.read(currentlyPlayingVideoMessageIdProvider) ==
            widget.messageId) {
          ref.read(currentlyPlayingVideoMessageIdProvider.notifier).state =
              null;
        }
        _controller = null;
        if (mounted) setState(() {});
        return;
      }
    }

    await _controller!.play();
    setState(() => _isPlaying = true);
  }

  @override
  Widget build(BuildContext context) {
    // Another video bubble became the currently-playing one — pause this one.
    ref.listen<String?>(currentlyPlayingVideoMessageIdProvider, (previous, next) {
      if (next != widget.messageId && _isPlaying) {
        _controller?.pause();
        setState(() => _isPlaying = false);
      }
    });

    return GestureDetector(
      onTap: _togglePlayback,
      child: AspectRatio(
        aspectRatio: _aspectRatio,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_controller?.value.isInitialized == true)
              VideoPlayer(_controller!)
            else if (widget.thumbnailUrl != null)
              Image(
                image: widget.thumbnailUrl!.startsWith('http')
                    ? NetworkImage(widget.thumbnailUrl!) as ImageProvider
                    : FileImage(File(widget.thumbnailUrl!)),
                fit: BoxFit.cover,
                // A missing/unreachable thumbnail (404, offline, or — in
                // tests — the test HTTP binding rejecting all real
                // requests) must not crash the bubble; fall back to a
                // plain surface instead of leaving the exception
                // unhandled, matching this widget's own no-thumbnail
                // ColoredBox fallback above.
                errorBuilder: (context, error, stackTrace) => ColoredBox(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                ),
              )
            else
              ColoredBox(color: Theme.of(context).colorScheme.surfaceContainerHighest),
            if (!_isPlaying)
              Center(
                child: Icon(
                  Icons.play_arrow_rounded,
                  size: 48,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            Positioned(
              right: 8,
              bottom: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  _formatDuration(Duration(milliseconds: widget.durationMs)),
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
            ),
            Positioned(
              left: 8,
              bottom: 8,
              child: IconButton(
                onPressed: () => setState(() {
                  _isMuted = !_isMuted;
                  _controller?.setVolume(_isMuted ? 0.0 : 1.0);
                }),
                icon: Icon(
                  _isMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}

import 'dart:async';
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
    this.onExpand,
    this.onRequestFreshUrl,
  });

  final String messageId;
  final String videoUrl;
  final String? thumbnailUrl;
  final int durationMs;
  final int width;
  final int height;

  /// Tapping the fullscreen-expand corner button calls this — the caller
  /// (MessageBubble's onVideoTap, wired up in ChatScreen) opens
  /// VideoViewerScreen. Deliberately a SEPARATE affordance from this
  /// widget's own tap-to-play/pause gesture (unchanged below) rather than
  /// replacing it: inline preview and full-screen viewing are both
  /// genuinely useful and don't need to be mutually exclusive. Null hides
  /// the button entirely (e.g. a caller with no viewer route to open).
  final VoidCallback? onExpand;

  /// Re-signs this video's storage key and returns a fresh URL, or null if
  /// it can't be resolved. Called only after an initialize() attempt on a
  /// REMOTE url fails — [videoUrl] is a signed URL with a ~10-minute TTL
  /// captured at hydration time, so a chat left open longer than that hands
  /// this widget an already-expired link. Without this the failure was
  /// silent and permanent for that bubble ("older videos sometimes don't
  /// show"). Null disables the retry (local-file callers don't need it).
  final Future<String?> Function()? onRequestFreshUrl;

  @override
  ConsumerState<VideoMessagePlayer> createState() => _VideoMessagePlayerState();
}

class _VideoMessagePlayerState extends ConsumerState<VideoMessagePlayer> {
  VideoPlayerController? _controller;
  bool _isPlaying = false;
  bool _isMuted = false;

  /// True after an initialize() attempt failed — surfaces a real, tappable
  /// "couldn't play, tap to retry" state instead of silently leaving a dead
  /// poster the user can tap forever with nothing happening (the old
  /// behavior, and the reason expired-signed-URL videos looked like they
  /// "just don't show").
  bool _failed = false;

  /// True while initialize() is in flight, so a second tap can't spin up a
  /// competing controller for the same widget.
  bool _initializing = false;

  @override
  void dispose() {
    // No background/lock-screen playback — leaving the message list stops
    // playback, matching VoiceMessagePlayer's identical guarantee.
    _controller?.dispose();
    super.dispose();
  }

  /// The true, rotation-corrected display aspect ratio.
  ///
  /// Prefers the DECODER's own value once the controller has initialized:
  /// video_player's `value.aspectRatio` already accounts for rotation
  /// metadata, which the persisted width/height do NOT. video_compress's
  /// MediaInfo reports raw encoded frame dimensions — a portrait phone clip
  /// is stored as 1280x720 plus a 90-degree rotation flag, so the stored
  /// numbers describe a LANDSCAPE frame for a video that displays portrait.
  /// Trusting them made portrait videos render too tall/wrong in the bubble
  /// and letterbox against the wrong edge in the fullscreen viewer.
  ///
  /// Falls back to the stored dimensions (pre-initialize, so the poster
  /// still reserves roughly the right box and the layout doesn't jump), and
  /// finally to 16/9 when those are missing/zero — older rows predating the
  /// width/height columns.
  double get _aspectRatio {
    final decoded = _controller?.value;
    if (decoded != null && decoded.isInitialized) {
      final ratio = decoded.aspectRatio;
      if (ratio.isFinite && ratio > 0) return ratio;
    }
    if (widget.width > 0 && widget.height > 0) {
      return widget.width / widget.height;
    }
    return 16 / 9;
  }

  Future<void> _togglePlayback() async {
    if (_initializing) return;
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
      if (mounted) {
        setState(() {
          _initializing = true;
          _failed = false;
        });
      }
      // First attempt uses the URL we were handed. A remote URL is a
      // signed URL with a ~10-minute TTL captured when the message was
      // hydrated — sit in a chat longer than that, scroll back, and it's
      // expired, which is exactly why older videos "sometimes don't
      // show". On failure, re-sign via onRequestFreshUrl and try once
      // more before giving up.
      var ok = await _initializeWith(widget.videoUrl);
      if (!ok && widget.videoUrl.startsWith('http')) {
        final fresh = await widget.onRequestFreshUrl?.call();
        if (fresh != null && fresh != widget.videoUrl) {
          ok = await _initializeWith(fresh);
        }
      }

      if (!ok) {
        // Playback isn't available (unsupported codec, unreachable URL, no
        // platform video decoder on this host). The cross-media pause above
        // has already taken effect (voice was stopped), but this widget
        // never actually started playing — so the video provider must be
        // rolled back to null rather than left pointing at a message that
        // isn't playing. Guarded to this widget's own messageId so a fast
        // subsequent tap elsewhere (which would have reassigned the
        // provider to a different message before this runs) can't be
        // clobbered.
        if (ref.read(currentlyPlayingVideoMessageIdProvider) ==
            widget.messageId) {
          ref.read(currentlyPlayingVideoMessageIdProvider.notifier).state =
              null;
        }
        if (mounted) {
          setState(() {
            _initializing = false;
            _failed = true;
          });
        }
        return;
      }
      if (mounted) setState(() => _initializing = false);
    }

    await _controller!.play();
    if (mounted) setState(() => _isPlaying = true);
  }

  /// Builds a controller for [url] and initializes it, returning whether it
  /// succeeded. Disposes and clears the controller on failure so a retry
  /// (or the fresh-URL second attempt) always starts from a clean slate
  /// rather than reusing a half-initialized native surface.
  Future<bool> _initializeWith(String url) async {
    // Local-vs-remote source branching copies VoiceMessagePlayer's
    // startsWith('http') check exactly.
    final controller =
        url.startsWith('http')
            ? VideoPlayerController.networkUrl(Uri.parse(url))
            : VideoPlayerController.file(File(url));
    controller.addListener(() {
      if (!mounted) return;
      if (!controller.value.isPlaying && _isPlaying) {
        setState(() => _isPlaying = false);
      }
    });
    try {
      await controller.initialize();
      // Apply any mute toggle that happened before the controller existed
      // (_isMuted can be flipped from the mute button while the player is
      // still showing the poster, before first play constructs this
      // controller) — otherwise the stored mute state is silently dropped
      // and first playback always starts unmuted regardless of what the
      // user tapped.
      await controller.setVolume(_isMuted ? 0.0 : 1.0);
      if (!mounted) {
        await controller.dispose();
        return false;
      }
      _controller = controller;
      return true;
    } catch (_) {
      // Fire-and-forget: a controller whose initialize() rejected may never
      // settle its own dispose() either (an unreachable host under a test
      // binding is the reproducible case), and awaiting it here would stall
      // the whole failure path — including the
      // currentlyPlayingVideoMessageIdProvider rollback in the caller,
      // leaving the shared cross-media lock falsely held by a message that
      // never played. Errors are swallowed because there is nothing left to
      // clean up beyond this handle.
      unawaited(controller.dispose().catchError((_) {}));
      _controller = null;
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Another video bubble became the currently-playing one — pause this one.
    ref.listen<String?>(currentlyPlayingVideoMessageIdProvider, (
      previous,
      next,
    ) {
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
                image:
                    widget.thumbnailUrl!.startsWith('http')
                        ? NetworkImage(widget.thumbnailUrl!) as ImageProvider
                        : FileImage(File(widget.thumbnailUrl!)),
                fit: BoxFit.cover,
                // A missing/unreachable thumbnail (404, offline, or — in
                // tests — the test HTTP binding rejecting all real
                // requests) must not crash the bubble; fall back to a
                // plain surface instead of leaving the exception
                // unhandled, matching this widget's own no-thumbnail
                // ColoredBox fallback above.
                errorBuilder:
                    (context, error, stackTrace) => ColoredBox(
                      color:
                          Theme.of(context).colorScheme.surfaceContainerHighest,
                    ),
              )
            else
              ColoredBox(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
              ),
            // Spinner while the native surface spins up (and, for an
            // expired signed URL, while the re-sign + second attempt runs)
            // — otherwise a slow initialize looks identical to a tap that
            // did nothing at all.
            if (_initializing)
              const Center(
                child: SizedBox(
                  width: 32,
                  height: 32,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    color: Colors.white,
                  ),
                ),
              )
            else if (_failed)
              // A real, legible failure state instead of a dead poster the
              // user can tap forever with nothing happening. Tapping
              // retries (the outer GestureDetector re-enters
              // _togglePlayback, which re-signs the URL first).
              ColoredBox(
                color: Colors.black.withValues(alpha: 0.45),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.refresh_rounded,
                        size: 36,
                        color: Colors.white,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        "Couldn't play — tap to retry",
                        textAlign: TextAlign.center,
                        style: Theme.of(
                          context,
                        ).textTheme.bodySmall?.copyWith(color: Colors.white),
                      ),
                    ],
                  ),
                ),
              )
            else if (!_isPlaying)
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
                onPressed:
                    () => setState(() {
                      _isMuted = !_isMuted;
                      _controller?.setVolume(_isMuted ? 0.0 : 1.0);
                    }),
                icon: Icon(
                  _isMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                  color: Colors.white,
                ),
              ),
            ),
            if (widget.onExpand != null)
              Positioned(
                right: 4,
                top: 4,
                child: IconButton(
                  onPressed: widget.onExpand,
                  icon: const Icon(
                    Icons.fullscreen_rounded,
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

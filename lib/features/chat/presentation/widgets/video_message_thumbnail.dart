import 'dart:io';

import 'package:flutter/material.dart';

/// The poster-only video tile shown inside a chat bubble. Tapping it opens
/// the full-screen viewer — this widget NEVER plays inline.
///
/// That mirrors WhatsApp/iMessage and, more importantly, fixes a real
/// visual bug: when the bubble both showed a poster AND played inline, the
/// tile's aspect ratio came from two different sources at two different
/// times. Before playback it used the persisted media_width/media_height
/// (which video_compress reports WITHOUT applying rotation metadata, so a
/// portrait clip's stored numbers describe a landscape frame); after
/// playback started it used the decoder's true rotation-aware ratio. The
/// bubble visibly jumped from tall-portrait to short-landscape mid-tap,
/// and a wrong-shaped box letterboxed the poster with a black band.
///
/// Here there is exactly ONE source of truth: the poster image itself.
/// VideoThumbnail.thumbnailData decodes a real frame, so the generated JPEG
/// already has rotation baked in and its intrinsic dimensions are correct
/// by construction — no metadata to misread. The tile sizes itself from the
/// decoded image and never changes shape afterwards.
class VideoMessageThumbnail extends StatefulWidget {
  const VideoMessageThumbnail({
    super.key,
    required this.thumbnailUrl,
    required this.durationMs,
    required this.width,
    required this.height,
    this.onTap,
    this.uploadProgress,
    this.showBusyOverlay = false,
  });

  /// Poster image — a signed remote URL or a local file path. Null renders
  /// the neutral placeholder (a video whose thumbnail upload failed is
  /// still a playable video; see the non-fatal thumbnail branch in
  /// ChatController._attemptSend).
  final String? thumbnailUrl;
  final int durationMs;

  /// Persisted media_width/media_height, used ONLY as the pre-decode
  /// placeholder ratio so the bubble reserves roughly the right space
  /// before the poster loads. Superseded by the decoded image's own
  /// dimensions the moment they're known — see the class doc for why these
  /// can't be trusted as the final answer.
  final int width;
  final int height;

  final VoidCallback? onTap;

  /// 0.0-1.0 while this video is still being prepared/sent, drawn as a ring
  /// over the poster. Null renders an indeterminate spinner instead (the
  /// upload phase, where there's no byte-level progress to report) — only
  /// meaningful when [showBusyOverlay] is true.
  final double? uploadProgress;

  /// Replaces the play glyph with the progress ring + cancel-style centre,
  /// dimming the poster behind it. True from the moment the message is sent
  /// until it lands, covering both compression and upload as one continuous
  /// busy state.
  final bool showBusyOverlay;

  @override
  State<VideoMessageThumbnail> createState() => _VideoMessageThumbnailState();
}

class _VideoMessageThumbnailState extends State<VideoMessageThumbnail> {
  /// The decoded poster's true aspect ratio, once the image has resolved.
  /// Null until then, which is when the persisted-dimension fallback
  /// applies.
  double? _decodedRatio;

  ImageStream? _stream;
  ImageStreamListener? _listener;
  ImageProvider? _boundProvider;

  /// Clamped so an extreme source (a 1:5 screen recording, a panorama)
  /// can't produce a bubble that swallows the viewport or collapses to a
  /// sliver. Matches the range real chat clients allow.
  static const double _minRatio = 0.5; // tall portrait
  static const double _maxRatio = 1.91; // wide landscape

  double get _aspectRatio {
    final decoded = _decodedRatio;
    if (decoded != null) return decoded.clamp(_minRatio, _maxRatio);
    if (widget.width > 0 && widget.height > 0) {
      return (widget.width / widget.height).clamp(_minRatio, _maxRatio);
    }
    // No poster and no usable stored dimensions — portrait is the far more
    // common shape for phone-shot video, so it's the less-wrong default
    // than the old 16/9 landscape guess.
    return 3 / 4;
  }

  ImageProvider? get _provider {
    final url = widget.thumbnailUrl;
    if (url == null) return null;
    return url.startsWith('http')
        ? NetworkImage(url) as ImageProvider
        : FileImage(File(url));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolvePoster();
  }

  @override
  void didUpdateWidget(VideoMessageThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The optimistic-to-canonical swap replaces a local poster path with a
    // signed URL for the same message — re-resolve so the ratio tracks the
    // image actually being shown.
    if (oldWidget.thumbnailUrl != widget.thumbnailUrl) {
      _decodedRatio = null;
      _resolvePoster();
    }
  }

  void _resolvePoster() {
    final provider = _provider;
    if (provider == null) return;
    // Cheap identity guard: didChangeDependencies fires on every inherited
    // change, and re-listening to the same provider each time would leak
    // listeners.
    if (provider == _boundProvider) return;

    _detach();
    _boundProvider = provider;
    final stream = provider.resolve(createLocalImageConfiguration(context));
    final listener = ImageStreamListener(
      (image, _) {
        if (!mounted) return;
        final ratio = image.image.width / image.image.height;
        if (!ratio.isFinite || ratio <= 0) return;
        if (_decodedRatio == ratio) return;
        setState(() => _decodedRatio = ratio);
      },
      // A poster that fails to load (404, offline, expired signature) just
      // leaves _decodedRatio null and falls back to the stored dimensions —
      // the Image widget below renders its own errorBuilder placeholder.
      onError: (_, _) {},
    );
    stream.addListener(listener);
    _stream = stream;
    _listener = listener;
  }

  void _detach() {
    final stream = _stream;
    final listener = _listener;
    if (stream != null && listener != null) {
      stream.removeListener(listener);
    }
    _stream = null;
    _listener = null;
  }

  @override
  void dispose() {
    _detach();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final provider = _provider;

    return GestureDetector(
      onTap: widget.onTap,
      child: AspectRatio(
        aspectRatio: _aspectRatio,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (provider != null)
                Image(
                  image: provider,
                  // cover, with the box already matching the poster's own
                  // ratio, means no letterboxing and no crop — the black
                  // band above the video in the old layout was a
                  // wrong-shaped box, not a fit problem.
                  fit: BoxFit.cover,
                  errorBuilder:
                      (context, error, stackTrace) => ColoredBox(
                        color: colorScheme.surfaceContainerHighest,
                      ),
                )
              else
                ColoredBox(color: colorScheme.surfaceContainerHighest),

              // Dim the poster while busy so the ring stays legible over a
              // bright frame.
              if (widget.showBusyOverlay)
                ColoredBox(color: Colors.black.withValues(alpha: 0.25)),

              if (widget.showBusyOverlay)
                // Progress ring around a stop-style centre — the poster is
                // already visible behind it, matching WhatsApp's
                // send-in-progress treatment.
                Center(
                  child: SizedBox(
                    width: 56,
                    height: 56,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        SizedBox.expand(
                          child: CircularProgressIndicator(
                            // Determinate during compression (real
                            // percentages), indeterminate during upload
                            // where there is no byte-level signal.
                            value: widget.uploadProgress,
                            strokeWidth: 3,
                            color: Colors.white,
                            backgroundColor: Colors.white.withValues(
                              alpha: 0.25,
                            ),
                          ),
                        ),
                        Icon(
                          Icons.stop_rounded,
                          size: 20,
                          color: Colors.white.withValues(alpha: 0.9),
                        ),
                      ],
                    ),
                  ),
                )
              else
                // Play affordance — WhatsApp's filled circle, which reads as
                // "opens a player" rather than "toggles inline playback".
                Center(
                  child: Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.45),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.play_arrow_rounded,
                      size: 34,
                      color: Colors.white,
                    ),
                  ),
                ),

              Positioned(
                left: 8,
                bottom: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.videocam_rounded,
                        size: 13,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _formatDuration(
                          Duration(milliseconds: widget.durationMs),
                        ),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
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

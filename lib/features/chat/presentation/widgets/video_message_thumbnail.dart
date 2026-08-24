import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

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
    this.cacheKey,
    required this.durationMs,
    required this.width,
    required this.height,
    this.onTap,
    this.uploadProgress,
    this.showBusyOverlay = false,
    @visibleForTesting this.cacheManager,
  });

  /// Overrides the disk cache used for the by-key poster lookup. Production
  /// leaves this null and uses [DefaultCacheManager]; tests inject a fake so
  /// the cold-restart path can be exercised without real files.
  @visibleForTesting
  final BaseCacheManager? cacheManager;

  /// Poster image — a signed remote URL or a local file path. Null renders
  /// the neutral placeholder (a video whose thumbnail upload failed is
  /// still a playable video; see the non-fatal thumbnail branch in
  /// ChatController._attemptSend).
  final String? thumbnailUrl;

  /// The poster's STABLE storage path (media_thumbnail_url), used as the
  /// disk-cache key. Critical, not cosmetic: [thumbnailUrl] is a signed URL
  /// whose token changes on every re-sign, so caching by URL would miss on
  /// every app open and re-download every poster. Keying on the storage
  /// path instead means a poster fetched once stays on disk and paints
  /// immediately on subsequent opens — the difference between WhatsApp's
  /// instant thumbnails and a grid of blank boxes that fill in over the
  /// network. Null falls back to URL-keyed caching.
  final String? cacheKey;

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

  /// A previously-downloaded poster found on disk by [cacheKey], used while
  /// no signed URL is in hand yet.
  ///
  /// This is what makes posters appear instantly on a COLD RESTART. The
  /// restored row carries mediaThumbnailKey but no URL (signed URLs expire,
  /// so persisting one would persist a dead link), and minting a fresh one
  /// is a network round trip. The bytes, however, are already on disk from
  /// the previous session — so the tile rendered grey for the length of a
  /// round trip while the very image it needed sat in the cache, unreachable
  /// because CachedNetworkImageProvider needs a URL to look one up.
  /// Reading the cache directly by key skips both the signing and the
  /// download.
  /// Stored as a path rather than a File because flutter_cache_manager's
  /// FileInfo carries the `file` package's File type, not dart:io's.
  String? _cachedPosterPath;

  /// Guards against a stale async cache lookup applying to a recycled tile.
  String? _cacheLookupIdentity;

  ImageStream? _stream;
  ImageStreamListener? _listener;

  /// Content identity of the poster currently being listened to — see
  /// [_posterIdentity].
  String? _boundIdentity;

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
    if (url == null) {
      // No URL yet. If a previous session already downloaded this poster,
      // paint it straight from disk instead of showing the grey placeholder
      // for the duration of a sign-then-download round trip.
      final cached = _cachedPosterPath;
      return cached == null ? null : FileImage(File(cached));
    }
    if (!url.startsWith('http')) return FileImage(File(url));
    // CachedNetworkImageProvider, not NetworkImage: the latter caches in
    // memory only, so every app restart re-downloaded every poster and the
    // bubbles filled in one network round-trip at a time. Keyed on the
    // stable storage path so a re-signed URL still hits the same disk
    // entry — see the cacheKey field doc.
    return CachedNetworkImageProvider(url, cacheKey: widget.cacheKey);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _lookUpCachedPoster();
    _resolvePoster();
  }

  /// Looks for an already-downloaded copy of this poster on disk, keyed by
  /// the stable storage path. Only runs while no URL is in hand — once one
  /// arrives, CachedNetworkImageProvider serves the same disk entry itself.
  ///
  /// A miss is entirely normal (a poster this device has never fetched) and
  /// leaves the placeholder in place, exactly as before.
  Future<void> _lookUpCachedPoster() async {
    if (widget.thumbnailUrl != null) return;
    final key = widget.cacheKey;
    if (key == null) return;
    if (_cacheLookupIdentity == key) return;
    _cacheLookupIdentity = key;

    final info = await (widget.cacheManager ?? DefaultCacheManager())
        .getFileFromCache(key);
    if (!mounted) return;
    // A URL may have arrived while this was in flight; it takes precedence.
    if (info == null || widget.thumbnailUrl != null) return;
    // The tile may have been recycled onto a different message mid-lookup.
    if (_cacheLookupIdentity != key) return;
    setState(() => _cachedPosterPath = info.file.path);
    // Measure the newly-available poster so the tile takes its true shape.
    // _posterIdentity is the cacheKey, which did NOT change here — only the
    // provider behind it did (null -> FileImage), so the identity guard in
    // _resolvePoster would skip the re-listen. Clear the binding to force
    // it, otherwise the poster paints at the placeholder ratio.
    _boundIdentity = null;
    _resolvePoster();
  }

  /// Identity of the poster CONTENT, as opposed to the URL currently
  /// pointing at it. A signed URL's token changes on every re-sign while
  /// the underlying image is byte-identical, so keying off the raw URL
  /// would treat a re-sign as a brand new poster.
  String? get _posterIdentity => widget.cacheKey ?? widget.thumbnailUrl;

  @override
  void didUpdateWidget(VideoMessageThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldIdentity = oldWidget.cacheKey ?? oldWidget.thumbnailUrl;
    if (oldIdentity == _posterIdentity) return;

    // Different poster: any disk copy found for the previous one is no
    // longer this tile's, so drop it before looking the new one up.
    _cachedPosterPath = null;
    _cacheLookupIdentity = null;
    _lookUpCachedPoster();

    // Genuinely a different poster (the optimistic-to-canonical swap
    // replacing a local file with the uploaded one). Deliberately does NOT
    // clear _decodedRatio: the local and remote posters are the same frame,
    // so keeping the known ratio holds the tile's shape steady across the
    // swap instead of momentarily collapsing back to the placeholder
    // fallback — the grey flash that reappeared right after a send
    // completed.
    _resolvePoster();
  }

  void _resolvePoster() {
    final provider = _provider;
    if (provider == null) return;
    // Identity guard on the poster's CONTENT, not the provider object:
    // didChangeDependencies fires on every inherited change, and a
    // re-signed URL produces a non-equal provider for a byte-identical
    // image. Comparing providers would re-listen (and re-measure) on every
    // re-sign; comparing content identity doesn't.
    if (_boundIdentity != null && _boundIdentity == _posterIdentity) return;

    _detach();
    _boundIdentity = _posterIdentity;
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
                  // Keep painting the previous frame while a new provider
                  // resolves, instead of dropping to a blank box. This is
                  // what removes the grey flash when the local poster is
                  // swapped for the uploaded one after a send completes —
                  // same image, so there is nothing to "reveal".
                  gaplessPlayback: true,
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

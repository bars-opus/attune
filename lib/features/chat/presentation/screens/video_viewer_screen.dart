import 'dart:io';

import 'package:attune/core/ui/motion/reduce_motion.dart';
import 'package:attune/features/chat/domain/entities/message.dart';
import 'package:attune/features/chat/domain/services/chat_media_cache.dart';
import 'package:attune/features/chat/presentation/state/chat_state.dart';
import 'package:attune/features/chat/presentation/widgets/resolved_media_url.dart';
import 'package:attune/features/chat/presentation/widgets/video_message_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Full-screen, swipeable video gallery — the video counterpart of
/// ImageViewerScreen, opened from ChatMediaScreen's Videos tab grid. Each
/// page reuses VideoMessagePlayer (already handles playback, mute,
/// one-at-a-time enforcement) sized via AspectRatio rather than the
/// bubble's fixed 220px, so it naturally fills the available space here.
/// Reached via the 'videoViewer' named route (registered in
/// app_router.dart), which takes a VideoViewerRouteArgs via `extra` and
/// returns the tapped-through message's id as a typed pop result via "Go
/// to message" — the caller (chat_media_screen.dart) pops itself too and
/// pushes a fresh ChatScreen with that id.
class VideoViewerScreen extends StatefulWidget {
  const VideoViewerScreen({
    super.key,
    required this.videos,
    required this.initialIndex,
  });

  /// Every video message in the conversation, in chronological (oldest to
  /// newest) order — already filtered to hasVideo entries by the caller.
  final List<Message> videos;

  /// Index into [videos] of the video that was tapped to open this screen.
  final int initialIndex;

  @override
  State<VideoViewerScreen> createState() => _VideoViewerScreenState();
}

class _VideoViewerScreenState extends State<VideoViewerScreen> {
  late final PageController _pageController = PageController(
    initialPage: widget.initialIndex,
  );
  late int _currentIndex = widget.initialIndex;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          '${_currentIndex + 1} of ${widget.videos.length}',
          style: const TextStyle(color: Colors.white, fontSize: 14),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: PageView.builder(
              controller: _pageController,
              itemCount: widget.videos.length,
              onPageChanged: (index) => setState(() => _currentIndex = index),
              itemBuilder: (context, index) {
                final message = widget.videos[index];
                // Only the visible page autoplays. PageView eagerly builds
                // its immediate neighbours, so passing autoPlay
                // unconditionally would spin up (and fight over the shared
                // cross-media playback lock with) videos the user hasn't
                // swiped to yet.
                return _FullScreenVideo(
                  message: message,
                  autoPlay: index == _currentIndex,
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: TextButton(
              onPressed: () => context.pop(widget.videos[_currentIndex].id),
              child: const Text(
                'Go to message',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FullScreenVideo extends ConsumerWidget {
  const _FullScreenVideo({required this.message, this.autoPlay = false});

  final Message message;

  /// True for the page the user is actually looking at — see the
  /// itemBuilder's note on why PageView's prebuilt neighbours must not.
  final bool autoPlay;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Same expired-signed-URL retry the chat bubble gets: a viewer opened
    // from a long-running chat can be handed a link whose ~10-minute
    // signature has already lapsed. Null for a local file, which never
    // expires.
    Future<String?> Function()? freshUrl;
    final mediaKey = message.mediaKey;
    if (mediaKey != null) {
      freshUrl = () => ref.read(resignMediaUrlProvider)(mediaKey);
    }

    final localPath = message.localMediaPath;
    final playableLocalPath =
        localPath != null && File(localPath).existsSync() ? localPath : null;

    return Center(
      child:
          playableLocalPath != null
              ? VideoMessagePlayer(
                key: ValueKey(message.clientMessageId),
                messageId: message.clientMessageId,
                videoUrl: playableLocalPath,
                thumbnailUrl: message.signedThumbnailUrl,
                durationMs: message.mediaDurationMs ?? 0,
                width: message.mediaWidth ?? 16,
                height: message.mediaHeight ?? 9,
                onRequestFreshUrl: freshUrl,
                autoPlay: autoPlay,
              )
              : ResolvedMediaUrl(
                signedMediaUrl: message.signedMediaUrl,
                mediaKey: message.mediaKey,
                loading: const CircularProgressIndicator(color: Colors.white),
                error: const _VideoViewerError(),
                retryLabel: "Video didn't load. Tap to retry",
                builder: (context, url) {
                  Widget player(
                    String source, [
                    Future<String?> Function()? onLocalSourceFailed,
                  ]) => VideoMessagePlayer(
                    key: ValueKey(message.clientMessageId),
                    messageId: message.clientMessageId,
                    videoUrl: source,
                    thumbnailUrl: message.signedThumbnailUrl,
                    durationMs: message.mediaDurationMs ?? 0,
                    width: message.mediaWidth ?? 16,
                    height: message.mediaHeight ?? 9,
                    onRequestFreshUrl: freshUrl,
                    onLocalSourceFailed: onLocalSourceFailed,
                    autoPlay: autoPlay,
                  );
                  // No key: built from the stored URL, nothing to cache
                  // under. View-once never reaches this gallery, but must
                  // never be written to disk if it did.
                  if (mediaKey == null || message.isViewOnce) {
                    return player(url);
                  }
                  return _CachedVideo(
                    mediaKey: mediaKey,
                    url: url,
                    relationshipId: message.relationshipId,
                    messageIds: {message.id, message.clientMessageId},
                    builder: player,
                  );
                },
              ),
    );
  }
}

/// Downloads the video into ChatMediaCache before handing a LOCAL path to
/// the player (#28): the second open plays offline, and the first shows a
/// real progress ring instead of a buffering spinner.
class _CachedVideo extends ConsumerStatefulWidget {
  const _CachedVideo({
    required this.mediaKey,
    required this.url,
    required this.relationshipId,
    required this.messageIds,
    required this.builder,
  });
  final String mediaKey;
  final String url;

  /// Whose bytes these are, so deleting the message or purging the
  /// relationship removes them from the cache.
  final String relationshipId;
  final Set<String> messageIds;
  /// [onCachedFileFailed] is set when [localOrRemotePath] is the cached
  /// file: it drops that copy and returns a URL to stream instead.
  final Widget Function(
    String localOrRemotePath,
    Future<String?> Function()? onCachedFileFailed,
  )
  builder;

  @override
  ConsumerState<_CachedVideo> createState() => _CachedVideoState();
}

class _CachedVideoState extends ConsumerState<_CachedVideo> {
  late Future<String> _path;
  double? _progress;

  @override
  void initState() {
    super.initState();
    _path = _fetch();
  }

  Future<String> _fetch() async {
    try {
      return await ref
          .read(chatMediaCacheProvider)
          .fetch(
            mediaKey: widget.mediaKey,
            url: widget.url,
            refreshUrl: () => ref.read(resignMediaUrlProvider)(widget.mediaKey),
            onProgress: (fraction) {
              if (mounted) setState(() => _progress = fraction);
            },
            relationshipId: widget.relationshipId,
            messageIds: widget.messageIds,
          );
    } catch (_) {
      // Streaming still works when the download does not — including one
      // that stalled: ChatMediaFileService bounds the wait, so this ring
      // always ends.
      return widget.url;
    }
  }

  /// The cached copy would not open: drop it (the next open downloads a
  /// good one) and stream this time, on a freshly signed URL.
  Future<String?> _streamInstead() async {
    await ref.read(chatMediaCacheProvider).remove(widget.mediaKey);
    return await ref.read(resignMediaUrlProvider)(widget.mediaKey) ??
        widget.url;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _path,
      builder: (context, snapshot) {
        final path = snapshot.data;
        if (path != null) {
          return widget.builder(
            path,
            path == widget.url ? null : _streamInstead,
          );
        }
        return Semantics(
          label: 'Downloading video',
          child: SizedBox(
            width: 56,
            height: 56,
            child: CircularProgressIndicator(
              key: const ValueKey('video_download_ring'),
              // Before the first byte count: indeterminate, or a still arc
              // under reduce motion.
              value: _progress ?? (reduceMotionOf(context) ? 0.75 : null),
              color: Colors.white,
              backgroundColor: Colors.white24,
            ),
          ),
        );
      },
    );
  }
}

/// A real tile, not a bare icon: it is the tap-to-retry target when the
/// video cannot be signed, and carries the retry glyph in its corner.
class _VideoViewerError extends StatelessWidget {
  const _VideoViewerError();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 160,
      height: 160,
      decoration: BoxDecoration(
        color: Colors.white10,
        borderRadius: BorderRadius.circular(16),
      ),
      alignment: Alignment.center,
      child: const Icon(
        Icons.broken_image_outlined,
        color: Colors.white54,
        size: 64,
      ),
    );
  }
}

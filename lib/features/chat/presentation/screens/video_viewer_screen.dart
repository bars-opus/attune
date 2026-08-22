import 'package:attune/features/chat/domain/entities/message.dart';
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
      freshUrl =
          () => ref
              .read(chatRepositoryProvider)
              .createSignedMediaUrl(mediaKey, forceRefresh: true);
    }

    return Center(
      child:
          message.localMediaPath != null
              ? VideoMessagePlayer(
                key: ValueKey(message.clientMessageId),
                messageId: message.clientMessageId,
                videoUrl: message.localMediaPath!,
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
                error: const Icon(
                  Icons.broken_image_outlined,
                  color: Colors.white54,
                  size: 64,
                ),
                builder:
                    (context, url) => VideoMessagePlayer(
                      key: ValueKey(message.clientMessageId),
                      messageId: message.clientMessageId,
                      videoUrl: url,
                      thumbnailUrl: message.signedThumbnailUrl,
                      durationMs: message.mediaDurationMs ?? 0,
                      width: message.mediaWidth ?? 16,
                      height: message.mediaHeight ?? 9,
                      onRequestFreshUrl: freshUrl,
                      autoPlay: autoPlay,
                    ),
              ),
    );
  }
}

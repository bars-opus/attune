import 'dart:io';

import 'package:attune/core/ui/motion/shimmer.dart';
import 'package:attune/features/chat/domain/entities/message.dart';
import 'package:attune/features/chat/presentation/widgets/resolved_media_url.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Full-screen, swipeable image gallery — tapping any image bubble in chat,
/// or a thumbnail in ChatMediaScreen's Images tab, opens this at that
/// image's position. Pinch/double-tap to zoom the current image, swipe
/// left/right to move between every OTHER image message in the set (order
/// and filtering are the caller's responsibility — see [images]). Reached
/// via the 'imageViewer' named route (registered in app_router.dart),
/// which takes an ImageViewerRouteArgs via `extra` and returns the
/// tapped-through message's id as a typed pop result.
///
/// "Go to message" pops with the current image's message id. The two
/// callers handle that pop result differently: chat_screen.dart is already
/// on ChatScreen, so it just jump-scrolls in place; chat_media_screen.dart
/// pops itself too and pushes a fresh ChatScreen with that id, since it's
/// reached from Chat Settings, not from an open chat.
class ImageViewerScreen extends StatefulWidget {
  const ImageViewerScreen({
    super.key,
    required this.images,
    required this.initialIndex,
  });

  /// Every image message in the conversation, in chronological (oldest to
  /// newest) order — already filtered to hasImage entries by the caller.
  final List<Message> images;

  /// Index into [images] of the image that was tapped to open this screen.
  final int initialIndex;

  @override
  State<ImageViewerScreen> createState() => _ImageViewerScreenState();
}

class _ImageViewerScreenState extends State<ImageViewerScreen> {
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
          '${_currentIndex + 1} of ${widget.images.length}',
          style: const TextStyle(color: Colors.white, fontSize: 14),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: PageView.builder(
              controller: _pageController,
              itemCount: widget.images.length,
              onPageChanged: (index) => setState(() => _currentIndex = index),
              itemBuilder: (context, index) {
                final message = widget.images[index];
                return _ZoomableImage(message: message);
              },
            ),
          ),
          SafeArea(
            top: false,
            child: TextButton(
              onPressed: () => context.pop(widget.images[_currentIndex].id),
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

/// One page of the gallery — pinch-to-zoom / double-tap-to-zoom via
/// InteractiveViewer, resolving the same way MessageBubble's thumbnail
/// does (local file first, else on-demand signed URL via ResolvedMediaUrl).
class _ZoomableImage extends StatefulWidget {
  const _ZoomableImage({required this.message});

  final Message message;

  @override
  State<_ZoomableImage> createState() => _ZoomableImageState();
}

class _ZoomableImageState extends State<_ZoomableImage>
    with SingleTickerProviderStateMixin {
  final _transformationController = TransformationController();
  TapDownDetails? _doubleTapDetails;

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

  void _handleDoubleTapDown(TapDownDetails details) {
    _doubleTapDetails = details;
  }

  void _handleDoubleTap() {
    if (_transformationController.value != Matrix4.identity()) {
      _transformationController.value = Matrix4.identity();
      return;
    }
    final position = _doubleTapDetails?.localPosition ?? Offset.zero;
    // Zoom in 2.5x centered on the double-tap point.
    _transformationController.value =
        Matrix4.identity()
          ..translate(-position.dx * 1.5, -position.dy * 1.5)
          ..scale(2.5);
  }

  @override
  Widget build(BuildContext context) {
    final message = widget.message;
    return GestureDetector(
      onDoubleTapDown: _handleDoubleTapDown,
      onDoubleTap: _handleDoubleTap,
      child: InteractiveViewer(
        transformationController: _transformationController,
        minScale: 1.0,
        maxScale: 5.0,
        child: Center(
          // Keyed on clientMessageId — the same identity both known source
          // widgets (MessageBubble's chat thumbnail, ChatIdentityCard's
          // recent-photos strip) tag their own Hero with, so whichever one
          // this screen was pushed from flies its thumbnail into this full
          // image. ChatMediaScreen's grid tiles don't carry a matching Hero
          // (out of scope for now), so a push from there is just a normal,
          // un-animated route change — Hero only activates when both ends
          // of a navigation carry the same tag.
          child: Hero(
            tag: message.clientMessageId,
            child:
                message.localMediaPath != null
                    ? Image.file(
                      File(message.localMediaPath!),
                      fit: BoxFit.contain,
                      errorBuilder:
                          (context, error, stackTrace) => const _ViewerError(),
                    )
                    : ResolvedMediaUrl(
                      signedMediaUrl: message.signedMediaUrl,
                      mediaKey: message.mediaKey,
                      loading: const Center(
                        child: CircularProgressIndicator(color: Colors.white),
                      ),
                      error: const _ViewerError(),
                      builder:
                          (context, url) => CachedNetworkImage(
                            imageUrl: url,
                            cacheKey: message.mediaKey,
                            fit: BoxFit.contain,
                            placeholder:
                                (context, url) => const Center(
                                  child: Shimmer(
                                    sweeps: null,
                                    child: SizedBox(width: 220, height: 220),
                                  ),
                                ),
                            errorWidget:
                                (context, url, error) => const _ViewerError(),
                          ),
                    ),
          ),
        ),
      ),
    );
  }
}

class _ViewerError extends StatelessWidget {
  const _ViewerError();

  @override
  Widget build(BuildContext context) {
    return const Icon(
      Icons.broken_image_outlined,
      color: Colors.white54,
      size: 64,
    );
  }
}

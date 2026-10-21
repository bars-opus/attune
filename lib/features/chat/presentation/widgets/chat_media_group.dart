import 'dart:io';

import 'package:attune/core/ui/motion/shimmer.dart';
import 'package:attune/core/widgets/media/stacked_media_cards.dart';
import 'package:attune/features/chat/domain/entities/message.dart';
import 'package:attune/features/chat/presentation/widgets/message_status_rule.dart';
import 'package:attune/features/chat/presentation/widgets/resolved_media_url.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

String? _existingLocalPath(String? path) {
  if (path == null) return null;
  return File(path).existsSync() ? path : null;
}

/// Builds album-style runs without changing the one-media-per-message model.
/// Messages are newest-first, matching ChatState and the reversed chat list.
class ChatMediaRunLayout {
  ChatMediaRunLayout._({required this.runs, required this.hiddenIndices});

  final Map<int, List<Message>> runs;
  final Set<int> hiddenIndices;

  factory ChatMediaRunLayout.fromMessages(List<Message> messages) {
    final runs = <int, List<Message>>{};
    final hidden = <int>{};

    var index = 0;
    while (index < messages.length) {
      final first = messages[index];
      if (!_canJoinMediaRun(first)) {
        index++;
        continue;
      }

      var end = index + 1;
      while (end < messages.length) {
        final older = messages[end];
        if (!_canJoinMediaRun(older) ||
            older.senderId != first.senderId ||
            older.mediaType != first.mediaType ||
            !_sameLocalDay(first.createdAt, older.createdAt)) {
          break;
        }
        end++;
      }

      if (end - index > 1) {
        runs[index] = messages.sublist(index, end);
        for (var hiddenIndex = index + 1; hiddenIndex < end; hiddenIndex++) {
          hidden.add(hiddenIndex);
        }
      }
      index = end;
    }

    return ChatMediaRunLayout._(runs: runs, hiddenIndices: hidden);
  }
}

bool _canJoinMediaRun(Message message) {
  final isRegularMedia =
      message.hasImage || (message.hasVideo && !message.isViewOnce);
  return isRegularMedia &&
      !message.isDeleted &&
      !message.isSystemNotice &&
      message.content.trim().isEmpty &&
      message.replyToMessageId == null &&
      message.reactions.isEmpty;
}

bool _sameLocalDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

class ChatMediaGroup extends StatefulWidget {
  const ChatMediaGroup({
    super.key,
    required this.messages,
    required this.isMine,
    required this.bubbleColor,
    this.onImageTap,
    this.onVideoTap,
  }) : assert(messages.length > 1);

  /// Newest first. The newest item is the front card, so the album reads as
  /// the completed send run while retaining the chat list's natural order.
  final List<Message> messages;
  final bool isMine;
  final Color bubbleColor;
  final void Function(Message message)? onImageTap;
  final void Function(Message message)? onVideoTap;

  @override
  State<ChatMediaGroup> createState() => _ChatMediaGroupState();
}

class _ChatMediaGroupState extends State<ChatMediaGroup> {
  // Mirrors the stack's front card, for the screen-reader description.
  var _frontIndex = 0;

  @override
  void didUpdateWidget(covariant ChatMediaGroup oldWidget) {
    super.didUpdateWidget(oldWidget);
    final previousIndex = _frontIndex.clamp(0, oldWidget.messages.length - 1);
    final previousId = oldWidget.messages[previousIndex].clientMessageId;
    final nextIndex = widget.messages.indexWhere(
      (message) => message.clientMessageId == previousId,
    );
    _frontIndex = nextIndex == -1 ? 0 : nextIndex;
  }

  @override
  Widget build(BuildContext context) {
    final imageCount =
        widget.messages.where((message) => message.hasImage).length;
    final videoCount = widget.messages.length - imageCount;
    final label = _mediaLabel(imageCount, videoCount);
    final stackAlignment =
        widget.isMine ? Alignment.centerRight : Alignment.centerLeft;

    return Semantics(
      button: true,
      label:
          '$label. Item ${_frontIndex + 1} of ${widget.messages.length}. '
          'Swipe horizontally to browse. Double tap to open.',
      child: SizedBox(
        width: 264,
        child: Column(
          crossAxisAlignment:
              widget.isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Align(
              alignment: stackAlignment,
              // The app's shared stack; chat supplies what is on each card.
              child: StackedMediaCards(
                itemCount: widget.messages.length,
                itemKey: (index) => widget.messages[index].clientMessageId,
                itemBuilder:
                    (context, index) =>
                        _MediaCardContent(message: widget.messages[index]),
                borderColor: widget.bubbleColor,
                backColor: widget.bubbleColor,
                alignEnd: widget.isMine,
                onTap: (index) => _open(widget.messages[index]),
                onFrontChanged: (index) => setState(() => _frontIndex = index),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _open(Message message) {
    if (message.hasImage) {
      widget.onImageTap?.call(message);
    } else {
      widget.onVideoTap?.call(message);
    }
  }
}

String _mediaLabel(int images, int videos) {
  if (videos == 0) return '$images ${images == 1 ? 'Photo' : 'Photos'}';
  if (images == 0) return '$videos ${videos == 1 ? 'Video' : 'Videos'}';
  final photoLabel = '$images ${images == 1 ? 'Photo' : 'Photos'}';
  final videoLabel = '$videos ${videos == 1 ? 'Video' : 'Videos'}';
  return '$photoLabel · $videoLabel';
}

/// What a chat message puts on its card: the poster, plus a play button and
/// duration for a video, and a spinner while it is still sending.
class _MediaCardContent extends StatelessWidget {
  const _MediaCardContent({required this.message});

  final Message message;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        _MediaPoster(message: message),
        if (message.hasVideo) ...[
          const ColoredBox(color: Color(0x16000000)),
          Center(
            child: Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.56),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.play_arrow_rounded,
                color: Colors.white,
                size: 36,
              ),
            ),
          ),
          if ((message.mediaDurationMs ?? 0) > 0)
            PositionedDirectional(
              end: 10,
              bottom: 10,
              child: _DurationBadge(durationMs: message.mediaDurationMs!),
            ),
        ],
        if (message.isPreparing || message.isSending)
          const ColoredBox(
            color: Color(0x52000000),
            child: Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),
          ),
      ],
    );
  }
}

class _MediaPoster extends StatelessWidget {
  const _MediaPoster({required this.message});

  final Message message;

  @override
  Widget build(BuildContext context) {
    final localPath = _existingLocalPath(
      message.hasVideo ? message.localThumbnailPath : message.localMediaPath,
    );
    final signedUrl =
        message.hasVideo ? message.signedThumbnailUrl : message.signedMediaUrl;
    final mediaKey =
        message.hasVideo ? message.mediaThumbnailKey : message.mediaKey;
    // Tiles are 238x300 pt: decode the side BoxFit.cover is bound by (the
    // width for a photo narrower than the tile), so it never upscales. No
    // LayoutBuilder - the bubble sits under IntrinsicWidth.
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final decode = thumbnailDecodeSize(
      displayPx: (238 * dpr).round(),
      displayHeightPx: (300 * dpr).round(),
      mediaWidth: message.mediaWidth,
      mediaHeight: message.mediaHeight,
    );

    if (localPath != null) {
      return Image(
        image: ResizeImage(
          FileImage(File(localPath)),
          width: decode.width,
          height: decode.height,
        ),
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const _PosterFallback(),
      );
    }

    return ResolvedMediaUrl(
      signedMediaUrl: signedUrl,
      mediaKey: mediaKey,
      loading: const Shimmer(sweeps: null, child: _PosterFallback()),
      error: const _PosterFallback(),
      // A broken video poster still opens the video on tap, as in the
      // single-video bubble; a broken photo is the retry button.
      retryOnTap: !message.hasVideo,
      retryLabel: "Photo didn't load. Tap to retry",
      builder:
          (context, url) => CachedNetworkImage(
            imageUrl: url,
            cacheKey: mediaKey,
            // In-memory decode only; the viewer shares the disk entry.
            memCacheWidth: decode.width,
            memCacheHeight: decode.height,
            fit: BoxFit.cover,
            fadeInDuration: const Duration(milliseconds: 150),
            placeholder:
                (_, __) =>
                    const Shimmer(sweeps: null, child: _PosterFallback()),
            errorWidget: (_, __, ___) => const _PosterFallback(),
          ),
    );
  }
}

class _PosterFallback extends StatelessWidget {
  const _PosterFallback();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Center(
        child: Icon(
          Icons.photo_outlined,
          size: 36,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _DurationBadge extends StatelessWidget {
  const _DurationBadge({required this.durationMs});

  final int durationMs;

  @override
  Widget build(BuildContext context) {
    final duration = Duration(milliseconds: durationMs);
    final date = DateTime(0).add(duration);
    final format =
        duration.inHours > 0 ? DateFormat('H:mm:ss') : DateFormat('m:ss');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.62),
        // A soft rectangle rather than a full pill: at this height 999
        // rounds the ends into semicircles, which reads as a tag stuck on
        // the photo. Kept identical on the count badge so the two remain
        // a matched pair.
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        format.format(date),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

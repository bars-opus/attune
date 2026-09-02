import 'dart:io';

import 'package:attune/core/ui/motion/shimmer.dart';
import 'package:attune/features/chat/domain/entities/message.dart';
import 'package:attune/features/chat/presentation/widgets/resolved_media_url.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

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
  late final PageController _pageController;
  var _frontIndex = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void didUpdateWidget(covariant ChatMediaGroup oldWidget) {
    super.didUpdateWidget(oldWidget);
    final previousIndex = _frontIndex.clamp(0, oldWidget.messages.length - 1);
    final previousId = oldWidget.messages[previousIndex].clientMessageId;
    final nextIndex = widget.messages.indexWhere(
      (message) => message.clientMessageId == previousId,
    );
    final resolvedIndex = nextIndex == -1 ? 0 : nextIndex;
    if (resolvedIndex == _frontIndex) return;
    _frontIndex = resolvedIndex;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _pageController.hasClients) {
        _pageController.jumpToPage(_frontIndex);
      }
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
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
              child: SizedBox(
                width: 258,
                height: 318,
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: stackAlignment,
                  children: [
                    for (var layer = _visibleBackLayers; layer >= 1; layer--)
                      _BackCard(
                        layer: layer,
                        isMine: widget.isMine,
                        color: widget.bubbleColor,
                      ),
                    PageView.builder(
                      controller: _pageController,
                      itemCount: widget.messages.length,
                      physics: const PageScrollPhysics(
                        parent: BouncingScrollPhysics(),
                      ),
                      onPageChanged: (index) {
                        if (_frontIndex != index) {
                          setState(() => _frontIndex = index);
                        }
                      },
                      itemBuilder: (context, index) {
                        final message = widget.messages[index];
                        return AnimatedBuilder(
                          animation: _pageController,
                          builder: (context, child) {
                            final page =
                                _pageController.hasClients
                                    ? (_pageController.page ??
                                        _frontIndex.toDouble())
                                    : _frontIndex.toDouble();
                            final distance = (page - index).clamp(-1.0, 1.0);
                            final scale = 1 - (distance.abs() * 0.035);
                            return Transform.rotate(
                              angle: distance * 0.018,
                              child: Transform.scale(
                                scale: scale,
                                child: child,
                              ),
                            );
                          },
                          child: Align(
                            alignment: stackAlignment,
                            child: _FrontMediaCard(
                              message: message,
                              borderColor: widget.bubbleColor,
                              onTap: () => _open(message),
                            ),
                          ),
                        );
                      },
                    ),
                    // The album label rides ON the stack now, opposite
                    // the count badge and in the same treatment.
                    //
                    // It used to sit above the carousel on the wallpaper,
                    // where it could not carry the bubble's colour: a
                    // media group draws a transparent bubble, and the
                    // sender's pale mint measures 1.04:1 against the light
                    // wallpaper -- the same colour as the background, not
                    // merely a faint one. Over the images it has a
                    // surface of its own, so it reads at a glance without
                    // needing to compete with whatever is behind it.
                    PositionedDirectional(
                      top: 12,
                      // Inset from the edge with the badge, not tight to
                      // it: both sit ON the photos, and a chip flush to
                      // the corner reads as clipped rather than placed.
                      start: widget.isMine ? null : 12,
                      end: widget.isMine ? 12 : null,
                      child: _AlbumLabel(label: label),
                    ),
                    PositionedDirectional(
                      top: 12,
                      // Matches the label's inset opposite it, so the pair
                      // sits at the same depth from either edge.
                      end: widget.isMine ? null : 12,
                      start: widget.isMine ? 12 : null,
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 220),
                        switchInCurve: Curves.easeOutBack,
                        switchOutCurve: Curves.easeInCubic,
                        transitionBuilder:
                            (child, animation) => FadeTransition(
                              opacity: animation,
                              child: ScaleTransition(
                                scale: animation,
                                child: child,
                              ),
                            ),
                        child: _CountBadge(
                          key: ValueKey(_frontIndex),
                          current: _frontIndex + 1,
                          total: widget.messages.length,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  int get _visibleBackLayers => (widget.messages.length - 1).clamp(1, 3);

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

class _BackCard extends StatelessWidget {
  const _BackCard({
    required this.layer,
    required this.isMine,
    required this.color,
  });

  final int layer;
  final bool isMine;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final offset = layer * 7.0;
    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Transform.translate(
        offset: Offset(isMine ? -offset : offset, offset * 0.55),
        child: Transform.rotate(
          angle: (isMine ? -1 : 1) * layer * 0.018,
          child: Container(
            width: 238,
            height: 300,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: Theme.of(
                  context,
                ).colorScheme.outlineVariant.withValues(alpha: 0.55),
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x14000000),
                  blurRadius: 8,
                  offset: Offset(0, 3),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FrontMediaCard extends StatelessWidget {
  const _FrontMediaCard({
    required this.message,
    required this.borderColor,
    required this.onTap,
  });

  final Message message;
  final Color borderColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: borderColor, width: 2),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Ink(
          width: 238,
          height: 300,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
          ),
          child: Stack(
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
          ),
        ),
      ),
    );
  }
}

class _MediaPoster extends StatelessWidget {
  const _MediaPoster({required this.message});

  final Message message;

  @override
  Widget build(BuildContext context) {
    final localPath =
        message.hasVideo ? message.localThumbnailPath : message.localMediaPath;
    final signedUrl =
        message.hasVideo ? message.signedThumbnailUrl : message.signedMediaUrl;
    final mediaKey =
        message.hasVideo ? message.mediaThumbnailKey : message.mediaKey;

    if (localPath != null) {
      return Image.file(
        File(localPath),
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const _PosterFallback(),
      );
    }

    return ResolvedMediaUrl(
      signedMediaUrl: signedUrl,
      mediaKey: mediaKey,
      loading: const Shimmer(sweeps: null, child: _PosterFallback()),
      error: const _PosterFallback(),
      builder:
          (context, url) => CachedNetworkImage(
            imageUrl: url,
            cacheKey: mediaKey,
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

/// The album label ("5 images"), carried on the stack opposite the count.
///
/// Shares _CountBadge's surface deliberately: they are a matched pair at
/// the top of the same stack, and two different treatments there would
/// read as two unrelated things stuck on the photos.
class _AlbumLabel extends StatelessWidget {
  const _AlbumLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.62),
        // A soft rectangle rather than a full pill: at this height 999
        // rounds the ends into semicircles, which reads as a tag stuck on
        // the photo. Kept identical on the count badge so the two remain
        // a matched pair.
        borderRadius: BorderRadius.circular(10),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 5,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Icon(Icons.grid_view_rounded, size: 15, color: Colors.white),
          const SizedBox(width: 5),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({super.key, required this.current, required this.total});

  final int current;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.62),
        // A soft rectangle rather than a full pill: at this height 999
        // rounds the ends into semicircles, which reads as a tag stuck on
        // the photo. Kept identical on the count badge so the two remain
        // a matched pair.
        borderRadius: BorderRadius.circular(10),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 5,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: Text(
        '$current / $total',
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w700,
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
        borderRadius: BorderRadius.circular(10),
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

/// One story ring — the entry point widget for the two-ring row on the
/// conversations screen (spec §5.1, §8; task-3-brief.md).
///
/// This widget draws exactly one ring and knows nothing about the RPC
/// shape or which author it belongs to — [StoryRingsRow]
/// (`story_rings_row.dart`) is the one that reads
/// `storyRingSummaryProvider`'s map and decides what to pass in here.
/// That split matters for the single most important constraint in the
/// brief:
///
/// **The absence of a row in `get_story_ring_summary` is NOT "do not draw
/// my ring."** `StoryRing` never asks "do I have a summary" — it takes
/// [hasStories] as a plain bool the caller already decided. For the
/// user's own ring, the caller (`StoryRingsRow`) passes `true` only when
/// a real summary/pending-outbox item exists and otherwise `true` is
/// never derived from "the map is empty" — see that file for the actual
/// derivation and `story_rings_test.dart` for a test that fails if this
/// gets inverted.
///
/// Four states, verbatim from spec §5.1:
///   - Mine, empty            -> empty ring, a `+` in the middle.
///   - Mine, has stories      -> newest thumbnail fills the circle, a `+`
///                               badge at the bottom end, whose 48 dp
///                               target hangs outside the ring (07a V10).
///   - Partner's, empty       -> renders NOTHING (handled by the caller,
///                               which simply does not place this widget
///                               in the row at all — see StoryRingsRow).
///   - Partner's, has stories -> newest thumbnail, ring around it.
///
/// The ring is segmented, one arc per active item, capped at 12 (spec
/// §8) — beyond 12 arcs it reads as a solid circle anyway, so this widget
/// draws a single unbroken ring once [segmentCount] exceeds 12. Segments
/// already seen are faded, not hidden — a viewed segment still occupies
/// its slot in the ring, just at lower opacity (spec §5.1's "bright for
/// unviewed, faded once seen").
library;

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:attune/core/ui/motion/reduce_motion.dart';
import 'package:attune/features/stories/domain/story_ring_copy.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

/// Diameter of the thumbnail circle itself, excluding the segmented ring
/// stroke and its padding. Matches the app's other avatar-scale circular
/// media (e.g. `InfoRowWidget`'s default avatar size) closely enough to
/// sit naturally in a row above a conversation tile that already uses
/// that scale.
const double kStoryRingThumbnailDiameter = 56;

/// Width of the segmented arc stroke. Wide enough that individual arcs
/// (and the gaps between them) read clearly at this ring's ~56-62px
/// scale — a thinner hairline stroke measured against a rendered golden
/// was too faint to tell "segmented" from "one solid ring" at a glance.
const double kStoryRingStrokeWidth = 3.5;

/// Gap between the thumbnail edge and the segmented ring, so the arcs
/// read as a distinct ring rather than an outline glued to the photo.
const double kStoryRingGap = 3;

/// Beyond this many active items the ring is drawn as one solid stroke
/// rather than that many hairline segments (spec §8: "Thirty hairlines
/// read as a solid circle anyway").
const int kStoryRingMaxSegments = 12;

/// The ring's own square: the photo, the gap and the stroke on each side.
const double kStoryRingOuterDiameter =
    kStoryRingThumbnailDiameter + 2 * (kStoryRingGap + kStoryRingStrokeWidth);

/// The drawn corner `+` on my ring.
const double kStoryRingBadgeDiameter = 20;

/// Within this distance of the badge's centre a tap is the badge's, even
/// over the photo: the drawn `+` and 4 dp.
const double kStoryRingBadgeSlop = kStoryRingBadgeDiameter / 2 + 4;

/// How far my ring's box reaches past the ring on the end and bottom
/// sides, so the `+`'s 48 dp target (centred on the drawn badge) lies
/// mostly outside the photo (07a V10).
const double kStoryRingPlusOverhang =
    kMinInteractiveDimension / 2 - kStoryRingBadgeDiameter / 2;

/// The square my ring occupies when it draws the `+`.
const double kStoryRingMineExtent =
    kStoryRingOuterDiameter + kStoryRingPlusOverhang;

/// Whether [local], a point in the `+` target's own 48 dp box, belongs to
/// the `+` (07a V10). On the drawn badge it always does; over the photo it
/// does not, so the photo opens the reel; elsewhere in the box it does.
bool storyPlusTargetContains(Offset local, {required TextDirection direction}) {
  const box = kMinInteractiveDimension;
  if (local.dx < 0 || local.dy < 0 || local.dx > box || local.dy > box) {
    return false;
  }
  const badge = Offset(box / 2, box / 2);
  if ((local - badge).distance <= kStoryRingBadgeSlop) return true;
  // The target starts 35 dp into the ring on both axes, so the photo's
  // centre sits half a dp before the box (mirrored right to left).
  const inset = kStoryRingOuterDiameter / 2 - (kStoryRingMineExtent - box);
  final photo = Offset(
    direction == TextDirection.ltr ? inset : box - inset,
    inset,
  );
  return (local - photo).distance > kStoryRingThumbnailDiameter / 2;
}

class StoryRing extends StatelessWidget {
  const StoryRing({
    super.key,
    required this.isMine,
    required this.hasStories,
    this.segmentCount = 0,
    this.unviewedCount = 0,
    this.thumbnailUrl,
    this.thumbnailCacheKey,
    this.localThumbnailPath,
    this.localThumbnailBytes,
    this.pendingProgress,
    this.onTap,
    this.onTapPlus,
    this.showPlusBadge = true,
    required this.semanticLabel,
  }) : assert(
         segmentCount >= 0,
         'segmentCount must not be negative — the ring has nothing to '
         'draw fewer than zero arcs for.',
       ),
       assert(
         unviewedCount >= 0 && unviewedCount <= segmentCount,
         'unviewedCount cannot exceed segmentCount: a viewed/unviewed '
         'split only makes sense over the segments that actually exist.',
       );

  /// True for the current user's own ring. Drives the `+` affordance —
  /// drawn whenever [showPlusBadge] is true, with or without [hasStories]:
  /// centred on the empty outline, or at the trailing bottom corner.
  final bool isMine;

  /// Whether there is a thumbnail to show. The caller decides this; see
  /// this file's header for why it must never be derived from RPC row
  /// presence for [isMine]'s ring.
  final bool hasStories;

  /// How many active items back the ring, for segment count. Capped at
  /// [kStoryRingMaxSegments] internally — pass the real count and let
  /// this widget decide when to fall back to a solid ring.
  final int segmentCount;

  /// How many of [segmentCount] are still unviewed. The newest
  /// [unviewedCount] segments render bright; the rest render faded.
  /// Zero renders every segment faded; equal to [segmentCount] renders
  /// every segment bright.
  final int unviewedCount;

  /// Signed URL for the newest item's thumbnail. Null/empty paints a
  /// neutral fill instead (used for the outbox pending state, where the
  /// server has not produced a thumbnail yet).
  final String? thumbnailUrl;

  /// The thumbnail's storage key: what its bytes are cached under, so a
  /// re-signed URL never re-downloads (E), and what is drawn from disk when
  /// there is no URL yet or signing failed.
  final String? thumbnailCacheKey;

  /// A local file path for a pending outbox capture's thumbnail (spec
  /// §6.1 — "the capture is visible before it is posted"). Takes
  /// priority over [thumbnailUrl] when both are set, since a pending
  /// local capture is more current than any server-known thumbnail.
  final String? localThumbnailPath;

  /// The thumbnail of a story that just posted (03 M1), in memory: its
  /// local file is already deleted and the summary may not know it yet.
  /// With [thumbnailCacheKey] it is the stand-in until the disk copy is
  /// found (batch-4 review #1).
  final Uint8List? localThumbnailBytes;

  /// 0..1 upload progress for a pending outbox item. When non-null, an
  /// indeterminate-look progress ring replaces the segmented-view ring
  /// entirely (spec §6.1 — "the capture is visible before it is
  /// posted"), and the thumbnail is the local pending tile rather than a
  /// server thumbnail.
  final double? pendingProgress;

  /// Tapping the ring/thumbnail itself (opens the reel). Null disables
  /// the tap target — e.g. mine-empty has no reel to open yet.
  final VoidCallback? onTap;

  /// Tapping the `+` badge specifically (opens the camera). Only used
  /// when [isMine].
  final VoidCallback? onTapPlus;

  /// Draws my `+` (only when [isMine]). The calendar passes false: a past
  /// day's ring has no camera, and a drawn `+` that does nothing misleads.
  final bool showPlusBadge;

  /// Full accessible description read for the ring as a whole. The `+`
  /// affordance is a separate, sibling Semantics node (not nested in the
  /// ring's), so it stays reachable and separately labelled as a button,
  /// per the brief's accessibility requirement. Mine-empty has no ring
  /// node at all: the `+` is the whole control.
  final String semanticLabel;

  int get _cappedSegments => math.min(segmentCount, kStoryRingMaxSegments);

  bool get _solid => segmentCount > kStoryRingMaxSegments;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final reduceMotion = reduceMotionOf(context);

    // Mine, empty: the outline (or the posting sweep) with the `+` in the
    // middle. The `+` is the whole control, so there is no ring button to
    // label (a second node with the same label read it twice).
    if (isMine && !hasStories) {
      return SizedBox.square(
        dimension: showPlusBadge ? kStoryRingMineExtent : kStoryRingOuterDiameter,
        child: Align(
          alignment: AlignmentDirectional.topStart,
          child: SizedBox.square(
            dimension: kStoryRingOuterDiameter,
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (pendingProgress == null)
                  CustomPaint(
                    size: const Size.square(kStoryRingOuterDiameter),
                    painter: _EmptyRingPainter(
                      color: colorScheme.outline,
                      strokeWidth: kStoryRingStrokeWidth,
                    ),
                  )
                else
                  _PendingRing(
                    progress: pendingProgress!,
                    diameter: kStoryRingOuterDiameter,
                    strokeWidth: kStoryRingStrokeWidth,
                    color: colorScheme.primary,
                    reduceMotion: reduceMotion,
                  ),
                if (showPlusBadge)
                  _PlusBadge(
                    centered: true,
                    colorScheme: colorScheme,
                    onTap: onTapPlus,
                  ),
              ],
            ),
          ),
        ),
      );
    }

    final ring = Semantics(
      container: true,
      label: semanticLabel,
      button: onTap != null,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: SizedBox.square(
          key: const ValueKey('story-ring-visual'),
          dimension: kStoryRingOuterDiameter,
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (pendingProgress != null)
                _PendingRing(
                  progress: pendingProgress!,
                  diameter: kStoryRingOuterDiameter,
                  strokeWidth: kStoryRingStrokeWidth,
                  color: colorScheme.primary,
                  reduceMotion: reduceMotion,
                )
              else if (hasStories)
                CustomPaint(
                  size: const Size.square(kStoryRingOuterDiameter),
                  painter: _SegmentedRingPainter(
                    segmentCount: _cappedSegments,
                    unviewedCount: math.min(unviewedCount, _cappedSegments),
                    solid: _solid,
                    brightColor: colorScheme.primary,
                    // 0.4: checked against rendered goldens in both themes
                    // (light mode's green washes out first).
                    fadedColor: colorScheme.primary.withValues(alpha: 0.4),
                    strokeWidth: kStoryRingStrokeWidth,
                  ),
                ),
              _Thumbnail(
                diameter: kStoryRingThumbnailDiameter,
                thumbnailUrl: thumbnailUrl,
                thumbnailCacheKey: thumbnailCacheKey,
                localThumbnailPath: localThumbnailPath,
                localThumbnailBytes: localThumbnailBytes,
                colorScheme: colorScheme,
              ),
            ],
          ),
        ),
      ),
    );
    if (!isMine || !showPlusBadge) return ring;

    // My ring with the corner `+`: the ring at the leading top, the `+`'s
    // 48 dp target at the trailing bottom, hanging [kStoryRingPlusOverhang]
    // past the ring. The target refuses taps over the photo
    // ([storyPlusTargetContains]); those fall through to the ring.
    return SizedBox.square(
      dimension: kStoryRingMineExtent,
      child: Stack(
        children: [
          PositionedDirectional(start: 0, top: 0, child: ring),
          PositionedDirectional(
            end: 0,
            bottom: 0,
            child: _PlusBadge(colorScheme: colorScheme, onTap: onTapPlus),
          ),
        ],
      ),
    );
  }
}

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({
    required this.diameter,
    required this.thumbnailUrl,
    required this.thumbnailCacheKey,
    required this.localThumbnailPath,
    required this.localThumbnailBytes,
    required this.colorScheme,
  });

  final double diameter;
  final String? thumbnailUrl;
  final String? thumbnailCacheKey;
  final String? localThumbnailPath;
  final Uint8List? localThumbnailBytes;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    final neutral = ColoredBox(color: colorScheme.surfaceContainerHighest);
    // Decoded at the size shown, not the 400 px file (03 L5).
    final decodeWidth = storyThumbnailDecodeWidth(
      diameter,
      MediaQuery.maybeDevicePixelRatioOf(context) ?? 3,
    );
    final localPath = localThumbnailPath;
    final bytes = localThumbnailBytes;
    final memory = bytes == null
        ? null
        : Image.memory(
            bytes,
            fit: BoxFit.cover,
            cacheWidth: decodeWidth,
            gaplessPlayback: true,
            errorBuilder: (_, __, ___) => neutral,
          );
    final url = thumbnailUrl;
    final key = thumbnailCacheKey;
    final Widget image;
    if (localPath != null && localPath.isNotEmpty) {
      // A pending capture: app-private storage, never a URL (spec §6.1).
      image = Image.file(
        File(localPath),
        fit: BoxFit.cover,
        cacheWidth: decodeWidth,
        errorBuilder: (_, __, ___) => neutral,
      );
    } else if (key != null && key.isNotEmpty) {
      // One widget whether or not the URL has landed, so the copy found on
      // disk stays up until the network image is ready (no grey blink on a
      // cold start; batch-2 review #4), and is what shows when signing
      // failed (03 M5). A just-posted story's bytes stand in until then
      // (batch-4 review #1).
      image = StoryKeyCachedImage(
        storageKey: key,
        imageUrl: url,
        decodeWidth: decodeWidth,
        fallback: memory ?? neutral,
      );
    } else if (memory != null) {
      image = memory;
    } else if (url != null && url.isNotEmpty) {
      image = CachedNetworkImage(
        imageUrl: url,
        memCacheWidth: decodeWidth,
        fit: BoxFit.cover,
        fadeInDuration: const Duration(milliseconds: 150),
        placeholder: (_, __) => neutral,
        errorWidget: (_, __, ___) => neutral,
      );
    } else {
      image = neutral;
    }
    return ClipOval(
      child: SizedBox(width: diameter, height: diameter, child: image),
    );
  }
}

/// The decode width for a story thumbnail drawn [diameter] dp wide, sized
/// for [BoxFit.cover] up to 16:9: a landscape thumbnail (400 x 225) fills
/// the circle from its short edge, so its decoded height, not just its
/// width, must reach the circle's pixel size, or it upscales blurry. A
/// decode never upscales (ResizeImage.allowUpscaling is false), so a
/// portrait thumbnail stays at its native 225 px width.
int storyThumbnailDecodeWidth(double diameter, double devicePixelRatio) =>
    (diameter * devicePixelRatio * 16 / 9).ceil();

/// Finds a thumbnail already in the shared image cache under its storage
/// key. Never throws: on a host with no cache store it answers null.
Future<File?> storyCachedThumbnailOnDisk(String storageKey) {
  final found = Completer<File?>();
  runZonedGuarded(
    () async {
      final info = await DefaultCacheManager().getFileFromCache(storageKey);
      if (!found.isCompleted) {
        found.complete(info == null ? null : File(info.file.path));
      }
    },
    (_, __) {
      if (!found.isCompleted) found.complete(null);
    },
  );
  return found.future;
}

/// What [StoryKeyCachedImage] uses to look up the disk. Tests replace it.
@visibleForTesting
Future<File?> Function(String storageKey) debugStoryCachedThumbnail =
    storyCachedThumbnailOnDisk;

/// A story thumbnail by its storage key: the network image at [imageUrl]
/// (its bytes cached under [storageKey], never the URL; STORIES.md §4.1)
/// once there is one, and until it is ready, or when there is no URL, the
/// copy already on disk, else [fallback].
class StoryKeyCachedImage extends StatefulWidget {
  const StoryKeyCachedImage({
    super.key,
    required this.storageKey,
    this.imageUrl,
    required this.decodeWidth,
    required this.fallback,
    this.fadeInDuration = const Duration(milliseconds: 150),
  });

  final String storageKey;
  final String? imageUrl;
  final int decodeWidth;
  final Widget fallback;
  final Duration fadeInDuration;

  @override
  State<StoryKeyCachedImage> createState() => _StoryKeyCachedImageState();
}

class _StoryKeyCachedImageState extends State<StoryKeyCachedImage> {
  File? _file;
  int _lookup = 0;

  @override
  void initState() {
    super.initState();
    _find();
  }

  @override
  void didUpdateWidget(StoryKeyCachedImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.storageKey != widget.storageKey) {
      _file = null;
      _find();
    }
  }

  void _find() {
    final ticket = ++_lookup;
    debugStoryCachedThumbnail(widget.storageKey).then((file) {
      if (mounted && ticket == _lookup && file != null) {
        setState(() => _file = file);
      }
    }, onError: (Object _) {});
  }

  Widget _onDisk() {
    final file = _file;
    if (file == null) return widget.fallback;
    return Image.file(
      file,
      fit: BoxFit.cover,
      cacheWidth: widget.decodeWidth,
      gaplessPlayback: true,
      errorBuilder: (_, __, ___) => widget.fallback,
    );
  }

  @override
  Widget build(BuildContext context) {
    final url = widget.imageUrl;
    if (url == null || url.isEmpty) return _onDisk();
    return CachedNetworkImage(
      imageUrl: url,
      cacheKey: widget.storageKey,
      useOldImageOnUrlChange: true,
      memCacheWidth: widget.decodeWidth,
      fit: BoxFit.cover,
      fadeInDuration: widget.fadeInDuration,
      // The disk copy, already decoded at this size, paints in the same
      // frame, so the swap from it never blinks to the neutral fill.
      placeholder: (_, __) => _onDisk(),
      errorWidget: (_, __, ___) => _onDisk(),
    );
  }
}

class _PlusBadge extends StatelessWidget {
  const _PlusBadge({
    this.centered = false,
    required this.colorScheme,
    this.onTap,
  });

  final bool centered;
  final ColorScheme colorScheme;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final visualSize = centered ? 28.0 : kStoryRingBadgeDiameter;
    final visual = Container(
      key: const ValueKey('story-ring-plus-visual'),
      width: visualSize,
      height: visualSize,
      decoration: BoxDecoration(
        color: colorScheme.primary,
        shape: BoxShape.circle,
        border:
            centered ? null : Border.all(color: colorScheme.surface, width: 2),
      ),
      child: Icon(
        Icons.add,
        size: centered ? 18 : 14,
        color: colorScheme.onPrimary,
      ),
    );
    // Material's 48 dp minimum target with the small badge centred in it,
    // the IconButton pattern. Its own semantics node, separate from the
    // ring's (the camera is a different control from the reel).
    final button = GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox.square(
        key: const ValueKey('story-ring-plus-target'),
        dimension: kMinInteractiveDimension,
        child: Center(child: visual),
      ),
    );
    return Semantics(
      container: true,
      label: storyRingAddLabel,
      button: true,
      child: centered
          ? button
          : _PlusHitShape(direction: Directionality.of(context), child: button),
    );
  }
}

/// Lets the `+` target refuse the photo's taps (07a V10).
class _PlusHitShape extends SingleChildRenderObjectWidget {
  const _PlusHitShape({required this.direction, required super.child});

  final TextDirection direction;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderPlusHitShape(direction);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderPlusHitShape renderObject,
  ) {
    renderObject.direction = direction;
  }
}

class _RenderPlusHitShape extends RenderProxyBox {
  _RenderPlusHitShape(this.direction);

  TextDirection direction;

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (!storyPlusTargetContains(position, direction: direction)) return false;
    return super.hitTest(result, position: position);
  }
}

/// Indeterminate-look progress ring for a pending outbox item (spec
/// §6.1). Reduce-motion collapses the sweep to a static partial ring at
/// the current [progress] instead of spinning, matching this codebase's
/// convention (`reduceMotionOf`) of degrading animated primitives to an
/// instant end-state rather than removing the affordance entirely.
class _PendingRing extends StatefulWidget {
  const _PendingRing({
    required this.progress,
    required this.diameter,
    required this.strokeWidth,
    required this.color,
    required this.reduceMotion,
  });

  final double progress;
  final double diameter;
  final double strokeWidth;
  final Color color;
  final bool reduceMotion;

  @override
  State<_PendingRing> createState() => _PendingRingState();
}

class _PendingRingState extends State<_PendingRing>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;

  @override
  void initState() {
    super.initState();
    if (!widget.reduceMotion) {
      _controller = AnimationController(
        vsync: this,
        duration: const Duration(seconds: 2),
      )..repeat();
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) {
      return CustomPaint(
        size: Size.square(widget.diameter),
        painter: _ProgressRingPainter(
          progress: widget.progress.clamp(0.0, 1.0),
          rotationTurns: 0,
          color: widget.color,
          strokeWidth: widget.strokeWidth,
        ),
      );
    }
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => CustomPaint(
        size: Size.square(widget.diameter),
        painter: _ProgressRingPainter(
          progress: widget.progress.clamp(0.0, 1.0),
          rotationTurns: controller.value,
          color: widget.color,
          strokeWidth: widget.strokeWidth,
        ),
      ),
    );
  }
}

class _ProgressRingPainter extends CustomPainter {
  _ProgressRingPainter({
    required this.progress,
    required this.rotationTurns,
    required this.color,
    required this.strokeWidth,
  });

  final double progress;
  final double rotationTurns;
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    final track = Paint()
      ..color = color.withValues(alpha: 0.2)
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;
    canvas.drawArc(rect, 0, 2 * math.pi, false, track);

    final sweepPaint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final startAngle = rotationTurns * 2 * math.pi - math.pi / 2;
    final sweep = math.max(progress, 0.08) * 2 * math.pi;
    canvas.drawArc(rect, startAngle, sweep, false, sweepPaint);
  }

  @override
  bool shouldRepaint(covariant _ProgressRingPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.rotationTurns != rotationTurns ||
      oldDelegate.color != color ||
      oldDelegate.strokeWidth != strokeWidth;
}

/// The empty-ring outline for "mine, empty" (spec §5.1) — a single
/// unbroken stroke, since there are zero items to segment.
class _EmptyRingPainter extends CustomPainter {
  _EmptyRingPainter({required this.color, required this.strokeWidth});

  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(center, radius, paint);
  }

  @override
  bool shouldRepaint(covariant _EmptyRingPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.strokeWidth != strokeWidth;
}

/// The segmented arc ring (spec §5.1, §8): one arc per active item, up to
/// [kStoryRingMaxSegments]; beyond the cap the caller passes `solid:
/// true` and this paints one unbroken stroke instead of drawing more and
/// more arcs that would just look like a circle anyway. The newest
/// [unviewedCount] segments (drawn last, ending at the top: arcs run
/// oldest first clockwise) paint in [brightColor]; the rest paint in
/// [fadedColor] — faded, never omitted, per spec §5.1's "bright for
/// unviewed, faded once seen."
class _SegmentedRingPainter extends CustomPainter {
  _SegmentedRingPainter({
    required this.segmentCount,
    required this.unviewedCount,
    required this.solid,
    required this.brightColor,
    required this.fadedColor,
    required this.strokeWidth,
  });

  final int segmentCount;
  final int unviewedCount;
  final bool solid;
  final Color brightColor;
  final Color fadedColor;
  final double strokeWidth;

  // Wide enough to read as a visible break between arcs at this ring's
  // small on-screen size (confirmed against a rendered golden — 0.06
  // read as one continuous ring with a couple of hairline nicks, not as
  // clearly "segmented"), while still leaving every arc's own sweep
  // dominant even at the 12-segment cap (12 gaps at 0.12 rad is ~1.4 rad
  // total, well under half the circle).
  static const double _gapRadians = 0.12;

  // A faded (viewed) segment is thinner than a bright (unviewed) one, in
  // addition to the alpha difference — finding F6: colour alone (two
  // alphas of the same hue) does not satisfy WCAG 1.4.1 for a low-vision
  // or low-contrast-sensitivity viewer. The stroke delta is deliberately
  // small (kept well clear of the gap width) so it reads as "thinner"
  // rather than changing the ring's apparent diameter.
  static const double _fadedStrokeDelta = 1.0;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final fadedStrokeWidth = math.max(1.0, strokeWidth - _fadedStrokeDelta);

    // Only two distinct paint configurations exist regardless of segment
    // count (finding F7) — hoisted once per `paint()` call rather than
    // allocated per segment (up to 12 times).
    final brightPaint = Paint()
      ..color = brightColor
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;
    final fadedPaint = Paint()
      ..color = fadedColor
      ..strokeWidth = fadedStrokeWidth
      ..style = PaintingStyle.stroke;

    if (solid || segmentCount <= 1) {
      final paint = unviewedCount > 0 ? brightPaint : fadedPaint;
      canvas.drawArc(rect, -math.pi / 2, 2 * math.pi - 0.001, false, paint);
      return;
    }

    final totalGap = _gapRadians * segmentCount;
    final perSegment = (2 * math.pi - totalGap) / segmentCount;
    var start = -math.pi / 2;

    // Oldest first, clockwise from 12 o'clock, like the reel's bars: the
    // seen (older) arcs first, then the new ones (03 L3, 06 #20).
    final seen = segmentCount - unviewedCount;
    for (var i = 0; i < segmentCount; i++) {
      final paint = i < seen ? fadedPaint : brightPaint;
      canvas.drawArc(rect, start, perSegment, false, paint);
      start += perSegment + _gapRadians;
    }
  }

  @override
  bool shouldRepaint(covariant _SegmentedRingPainter oldDelegate) =>
      oldDelegate.segmentCount != segmentCount ||
      oldDelegate.unviewedCount != unviewedCount ||
      oldDelegate.solid != solid ||
      oldDelegate.brightColor != brightColor ||
      oldDelegate.fadedColor != fadedColor ||
      oldDelegate.strokeWidth != strokeWidth;
}

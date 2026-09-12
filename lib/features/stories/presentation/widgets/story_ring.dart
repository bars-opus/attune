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
///                               badge bottom-right.
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

import 'dart:io';
import 'dart:math' as math;

import 'package:attune/core/ui/motion/reduce_motion.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

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

class StoryRing extends StatelessWidget {
  const StoryRing({
    super.key,
    required this.isMine,
    required this.hasStories,
    this.segmentCount = 0,
    this.unviewedCount = 0,
    this.thumbnailUrl,
    this.localThumbnailPath,
    this.pendingProgress,
    this.onTap,
    this.onTapPlus,
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
  /// present regardless of [hasStories] — and which corner it sits in.
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

  /// A local file path for a pending outbox capture's thumbnail (spec
  /// §6.1 — "the capture is visible before it is posted"). Takes
  /// priority over [thumbnailUrl] when both are set, since a pending
  /// local capture is more current than any server-known thumbnail.
  final String? localThumbnailPath;

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

  /// Full accessible description read for the ring as a whole. The `+`
  /// affordance gets its own nested Semantics so it stays reachable and
  /// separately labelled as a button, per the brief's accessibility
  /// requirement.
  final String semanticLabel;

  int get _cappedSegments => math.min(segmentCount, kStoryRingMaxSegments);

  bool get _solid => segmentCount > kStoryRingMaxSegments;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final outerDiameter =
        kStoryRingThumbnailDiameter +
        2 * (kStoryRingGap + kStoryRingStrokeWidth);

    final ring = SizedBox(
      width: outerDiameter,
      height: outerDiameter,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (pendingProgress != null)
            _PendingRing(
              progress: pendingProgress!,
              diameter: outerDiameter,
              strokeWidth: kStoryRingStrokeWidth,
              color: colorScheme.primary,
              reduceMotion: reduceMotionOf(context),
            )
          else if (hasStories)
            CustomPaint(
              size: Size.square(outerDiameter),
              painter: _SegmentedRingPainter(
                segmentCount: _cappedSegments,
                unviewedCount: math.min(unviewedCount, _cappedSegments),
                solid: _solid,
                brightColor: colorScheme.primary,
                // 0.4 rather than something lower: checked against a
                // rendered golden in BOTH themes — light mode's primary
                // green washes out against a near-white background well
                // before dark mode's contrast problem shows up, so the
                // value is picked for the harder (light) case. Still
                // clearly dimmer than the full-opacity bright arcs next
                // to it in both themes.
                fadedColor: colorScheme.primary.withValues(alpha: 0.4),
                strokeWidth: kStoryRingStrokeWidth,
              ),
            ),
          _Thumbnail(
            diameter: kStoryRingThumbnailDiameter,
            hasStories: hasStories,
            thumbnailUrl: thumbnailUrl,
            localThumbnailPath: localThumbnailPath,
            isMine: isMine,
            colorScheme: colorScheme,
          ),
          if (isMine)
            Positioned(
              right: 0,
              bottom: 0,
              child: _PlusBadge(
                // Mine-empty puts the + dead-center over an empty ring
                // (spec §5.1); mine-with-stories is a corner badge. Both
                // are the same widget at two different Alignments so the
                // tap target/semantics logic lives in one place.
                filled: hasStories,
                colorScheme: colorScheme,
                onTap: onTapPlus,
              ),
            ),
        ],
      ),
    );

    // mine-empty centers the + INSIDE the ring instead of badge-corner —
    // rebuild that one layout case rather than branching the Stack above
    // for a single positional difference.
    final content = isMine && !hasStories
        ? SizedBox(
            width: outerDiameter,
            height: outerDiameter,
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (pendingProgress == null)
                  CustomPaint(
                    size: Size.square(outerDiameter),
                    painter: _EmptyRingPainter(
                      color: colorScheme.outline,
                      strokeWidth: kStoryRingStrokeWidth,
                    ),
                  )
                else
                  _PendingRing(
                    progress: pendingProgress!,
                    diameter: outerDiameter,
                    strokeWidth: kStoryRingStrokeWidth,
                    color: colorScheme.primary,
                    reduceMotion: reduceMotionOf(context),
                  ),
                _PlusBadge(
                  filled: true,
                  centered: true,
                  colorScheme: colorScheme,
                  onTap: onTapPlus,
                ),
              ],
            ),
          )
        : ring;

    // Mine-empty has no outer tap target at all — the `+` badge (already
    // its own Semantics(button: true)) IS the entire interactive surface,
    // so wrapping it in a second Semantics with the same label here would
    // merge into one node with the label duplicated ("Add to your
    // story\nAdd to your story"), which is what actually happened before
    // this guard existed — caught by story_rings_test.dart's `+`
    // reachability assertion doing an exact bySemanticsLabel match.
    if (isMine && !hasStories) return content;

    return Semantics(
      // container + explicitChildNodes stop this label from merging with
      // the `+` badge's own nested Semantics node below (finding F3): the
      // badge is a distinct control (opens the camera) from the ring
      // itself (opens the reel), and without a boundary here Flutter
      // collapses adjacent Semantics into one node — worse, non-
      // deterministically, only once `onTap` becomes non-null (i.e. once
      // Task 4 wires `onOpenMine`), which is exactly the "silent
      // regression on the next task" the review flagged.
      container: true,
      explicitChildNodes: true,
      label: semanticLabel,
      button: onTap != null,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: content,
      ),
    );
  }
}

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({
    required this.diameter,
    required this.hasStories,
    required this.thumbnailUrl,
    required this.localThumbnailPath,
    required this.isMine,
    required this.colorScheme,
  });

  final double diameter;
  final bool hasStories;
  final String? thumbnailUrl;
  final String? localThumbnailPath;
  final bool isMine;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    // Mine-empty: no thumbnail circle at all, just the outline ring and
    // the + drawn by the parent — nothing to clip/fill here.
    if (isMine && !hasStories) return const SizedBox.shrink();

    final localPath = localThumbnailPath;
    final url = thumbnailUrl;
    Widget image;
    if (localPath != null && localPath.isNotEmpty) {
      // A pending outbox capture: the file is on-disk app-private
      // storage, never a network URL (spec §6.1).
      image = Image.file(
        File(localPath),
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) =>
            ColoredBox(color: colorScheme.surfaceContainerHighest),
      );
    } else if (url != null && url.isNotEmpty) {
      image = CachedNetworkImage(
        imageUrl: url,
        fit: BoxFit.cover,
        fadeInDuration: const Duration(milliseconds: 150),
        placeholder: (_, __) =>
            ColoredBox(color: colorScheme.surfaceContainerHighest),
        errorWidget: (_, __, ___) =>
            ColoredBox(color: colorScheme.surfaceContainerHighest),
      );
    } else {
      image = ColoredBox(color: colorScheme.surfaceContainerHighest);
    }

    return ClipOval(
      child: SizedBox(width: diameter, height: diameter, child: image),
    );
  }
}

class _PlusBadge extends StatelessWidget {
  const _PlusBadge({
    required this.filled,
    this.centered = false,
    required this.colorScheme,
    this.onTap,
  });

  final bool filled;
  final bool centered;
  final ColorScheme colorScheme;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final visualSize = centered ? 28.0 : 20.0;
    final visual = Container(
      width: visualSize,
      height: visualSize,
      decoration: BoxDecoration(
        color: colorScheme.primary,
        shape: BoxShape.circle,
        border: centered
            ? null
            : Border.all(color: colorScheme.surface, width: 2),
      ),
      child: Icon(
        Icons.add,
        size: centered ? 18 : 14,
        color: colorScheme.onPrimary,
      ),
    );

    // The visible badge is 20-28dp, well under the 44dp (iOS HIG) / 48dp
    // (Material) minimum tap target (finding F3). Rather than growing the
    // circle itself (which would blow past the corner badge's intended
    // visual scale), the hit area is a separate, larger, transparent box
    // with the small visual centered inside it — the same pattern
    // Material's own IconButton uses for a small icon inside a
    // kMinInteractiveDimension hit box. For the corner badge this box is
    // bottom-right anchored so the extra hit area does not creep over the
    // ring's own gesture detector any more than necessary; for the
    // mine-empty centered case it is simply centered like the visual.
    const hitSize = kMinInteractiveDimension; // 48dp
    final hitArea = SizedBox(
      width: hitSize,
      height: hitSize,
      child: centered
          ? Center(child: visual)
          : Align(alignment: Alignment.bottomRight, child: visual),
    );

    return Semantics(
      // Its own boundary (see StoryRing's outer Semantics comment) so
      // this node never merges with the ring's — it is a distinct
      // control (camera) from the ring (reel).
      container: true,
      label: 'Add to your story',
      button: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: hitArea,
      ),
    );
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
/// [unviewedCount] segments (drawn first, at the top, going clockwise)
/// paint in [brightColor]; the rest paint in [fadedColor] — faded, never
/// omitted, per spec §5.1's "bright for unviewed, faded once seen."
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

    for (var i = 0; i < segmentCount; i++) {
      final paint = i < unviewedCount ? brightPaint : fadedPaint;
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

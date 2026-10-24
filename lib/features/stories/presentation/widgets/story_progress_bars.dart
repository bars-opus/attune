/// Segmented progress bars for the story reel (spec §5.2): one bar per
/// item in the currently-open author's page, drawn across the top of the
/// screen. A bar left of [currentIndex] is fully filled (already played
/// this viewing), the bar AT [currentIndex] fills according to
/// [currentProgress] (0..1, driven by the reel's own image timer or video
/// position), and every bar to the right is empty unless [viewed] marks it
/// seen on an earlier visit, which draws it full but faded.
///
/// This widget is a pure function of its inputs — no timers, no
/// animation controllers, no knowledge of media type. [StoryReelScreen]
/// owns the clock; this widget only paints wherever that clock currently
/// is. Kept deliberately dumb so it can be asserted against directly
/// (`story_reel_test.dart`) without needing to drive playback at all.
library;

import 'package:attune/app/theme/design_tokens.dart';
import 'package:flutter/material.dart';

class StoryProgressBars extends StatelessWidget {
  const StoryProgressBars({
    super.key,
    required this.itemCount,
    required this.currentIndex,
    required this.currentProgress,
    this.viewed,
  }) : assert(
         itemCount >= 0,
         'itemCount must not be negative — there is nothing to draw fewer '
         'than zero segments for.',
       ),
       assert(
         currentProgress >= 0.0 && currentProgress <= 1.0,
         'currentProgress is a fraction of the current segment, 0..1.',
       );

  /// How many items are in the currently-open page. A segment is drawn
  /// per item; this is NOT capped the way the ring's segment count is —
  /// the reel shows one page (<= 50 items, spec §5.5) at a time, not an
  /// unbounded history.
  final int itemCount;

  /// Index of the item currently playing/held. Every bar before this one
  /// renders fully filled; every bar after renders empty.
  final int currentIndex;

  /// Fraction (0..1) of the current item's hold/playback elapsed so far.
  /// Ignored for bars other than [currentIndex].
  final double currentProgress;

  /// Per item: already seen by this viewer on an earlier visit. A segment
  /// after [currentIndex] that is seen draws fully, in [seenColor] (faded,
  /// not skipped: spec §5.5 / owner ruling 3).
  final List<bool>? viewed;

  /// The reel is a fixed black surface in both themes, so the bars are
  /// white regardless of theme (06 #10: dark `onPrimary` is near-black).
  static const Color trackColor = Color(0x59FFFFFF);
  static const Color fillColor = Colors.white;
  static const Color seenColor = Color(0x99FFFFFF);

  @override
  Widget build(BuildContext context) {
    if (itemCount == 0) return const SizedBox.shrink();

    return Semantics(
      label: 'Story ${currentIndex + 1} of $itemCount',
      child: Row(
        children: [
          for (var i = 0; i < itemCount; i++) ...[
            if (i > 0) const SizedBox(width: Spacing.xs),
            Expanded(
              child: KeyedSubtree(
                key: ValueKey('story-progress-segment-$i'),
                child: _segmentFor(i),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _segmentFor(int i) {
    final seenAhead =
        i > currentIndex &&
        (viewed != null && i < viewed!.length && viewed![i]);
    return _Segment(
      fraction: i < currentIndex
          ? 1.0
          : i == currentIndex
          ? currentProgress
          : seenAhead
          ? 1.0
          : 0.0,
      trackColor: trackColor,
      fillColor: seenAhead ? seenColor : fillColor,
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.fraction,
    required this.trackColor,
    required this.fillColor,
  });

  final double fraction;
  final Color trackColor;
  final Color fillColor;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadiusTokens.xsAll,
      child: SizedBox(
        height: 3,
        child: Stack(
          children: [
            ColoredBox(color: trackColor),
            FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: fraction.clamp(0.0, 1.0),
              child: ColoredBox(color: fillColor),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../paint_ball_field.dart'
    show
        kPaintBallCoverWidth,
        kPaintBallPositions,
        kPaintBallTargetScale,
        paintBallPositionName;
import 'cover_bay.dart';
import 'field_figure.dart';

/// One side of the field: three bays, and the figure sheltering in one.
///
/// The figure sits ABOVE the bays rather than inside one, because a
/// child cannot travel outside its parent's box and changing cover is a
/// journey across the whole row (see [FieldFigure]).
class CoverRow extends StatelessWidget {
  const CoverRow({
    super.key,
    required this.isOpponent,
    required this.hiddenAt,
    required this.aimedAt,
    required this.enabled,
    required this.ownerColor,
    required this.reduceMotion,
    this.aimingAt,
    this.onTap,
    this.onTapFigure,
    this.emerged = true,
    this.coverStyle,
  });

  final bool isOpponent;

  /// Where this row's occupant is, when the viewer may know. Always set
  /// for your own row; for theirs only after a round resolves.
  final int? hiddenAt;

  /// The bay being aimed at. Exactly one, or none.
  final int? aimedAt;

  final bool enabled;
  final Color ownerColor;
  final bool reduceMotion;

  /// Where this row's occupant is pointing, which leans the figure.
  final int? aimingAt;

  final ValueChanged<int>? onTap;

  /// Set only when the figure is the fire control.
  final VoidCallback? onTapFigure;

  /// False during the replay's first beat, while both players are still
  /// behind cover and about to step out.
  final bool emerged;

  /// Overrides §2.3's bay-of-darkness. See [PaintBallCoverStyle].
  final PaintBallCoverStyle? coverStyle;

  @override
  Widget build(BuildContext context) {
    final coverWidth =
        kPaintBallCoverWidth * (isOpponent ? kPaintBallTargetScale : 1);
    final isAiming = aimingAt != null && hiddenAt != null && emerged;

    // Per-column lean, in turns. Small deliberately: the tilt says which
    // cover is being aimed at, and a figure rotated far enough to lose
    // its pointing silhouette stops communicating that at all.
    final tilt =
        isAiming
            ? (aimingAt! - hiddenAt!) * (isOpponent ? -0.045 : 0.045)
            : 0.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        return SizedBox(
          height: 92,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: List.generate(kPaintBallPositions, (index) {
                  return Semantics(
                    // container: true so each becomes its own node.
                    // Without it a screen reader announces one
                    // undifferentiated strip instead of three targets.
                    container: true,
                    button: enabled,
                    // Named by position, not index: a screen-reader user
                    // hears "Middle target" -- the thing on the board --
                    // rather than "cover 2".
                    //
                    // Your row is COVER, theirs is a TARGET. You hide
                    // behind one and shoot at the other, so the words
                    // differ as much as the rows do.
                    label:
                        isOpponent
                            ? '${paintBallPositionName(index)} target'
                            : '${paintBallPositionName(index)} cover',
                    child: GestureDetector(
                      onTap: enabled ? () => onTap?.call(index) : null,
                      behavior: HitTestBehavior.opaque,
                      child: SizedBox(
                        width: coverWidth,
                        height: 92,
                        child: CoverBay(
                          position: index,
                          isOpponent: isOpponent,
                          state: _stateFor(index),
                          ownerColor: ownerColor,
                          style: coverStyle,
                        ),
                      ),
                    ),
                  );
                }),
              ),
              if (hiddenAt != null && emerged)
                FieldFigure(
                  position: hiddenAt!,
                  isOpponent: isOpponent,
                  rowWidth: constraints.maxWidth,
                  coverWidth: coverWidth,
                  rowHeight: 92,
                  ownerColor: ownerColor,
                  isAiming: isAiming,
                  tilt: tilt,
                  reduceMotion: reduceMotion,
                  onTap: onTapFigure,
                ),
            ],
          ),
        );
      },
    );
  }

  /// Aimed outranks occupied: with no Fire button, the aimed bay is the
  /// only confirmation that a target is chosen, so it must never be
  /// outvoted by the fact that somebody is standing there.
  CoverBayState _stateFor(int index) {
    if (aimedAt == index) return CoverBayState.aimed;
    if (hiddenAt == index) return CoverBayState.occupied;
    return CoverBayState.rest;
  }
}

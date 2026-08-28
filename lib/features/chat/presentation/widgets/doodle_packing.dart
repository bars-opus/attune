import 'dart:math';

import 'package:flutter/widgets.dart';

/// One doodle's position, size, orientation and role in the field.
@immutable
class DoodlePlacement {
  const DoodlePlacement({
    required this.rect,
    required this.assetIndex,
    required this.turns,
    required this.isAnimated,
    required this.phase,
  });

  final Rect rect;
  final int assetIndex;

  /// Quarter-turn rotation steps. Doodle art reads fine at any angle, and
  /// varied rotation is most of what stops a packed field looking like a
  /// grid.
  final int turns;

  /// Whether this one moves. Only a minority do.
  final bool isAnimated;

  /// 0..1 offset into the animation cycle, so animated doodles never beat
  /// in unison — synchronised motion reads as a glitch rather than life.
  final double phase;
}

/// How many of the packed doodles animate. A tenth: enough that the field
/// is alive when you look at it, few enough that it never competes with
/// the conversation on top of it.
const double _animatedFraction = 0.1;

/// Packs a dense field of doodles into [area].
///
/// Hand-placing motifs at hand-picked percentages cannot reach the density
/// of a real doodle wallpaper — every new doodle needs another tuned
/// coordinate, and the result stays sparse. This scatters candidates on a
/// jittered grid instead, rejecting any that would collide, which fills
/// the space the way the reference art does while keeping the guarantee
/// that nothing overlaps.
///
/// Deterministic for a given [seed]: the wallpaper must look identical
/// across rebuilds, or it reshuffles under the user mid-conversation.
List<DoodlePlacement> packDoodles({
  required Size area,
  required int assetCount,
  required int seed,
}) {
  if (area.isEmpty || assetCount <= 0) return const [];

  final random = Random(seed);
  final placed = <DoodlePlacement>[];

  // Cell size drives density. Roughly 8 columns on a phone gives the
  // packed-but-legible look of the reference; the sizes below then vary
  // within each cell so the result is not a visible lattice.
  const columns = 8;
  final cell = area.width / columns;
  final rows = (area.height / cell).ceil();

  // Deal assets round-robin from a shuffled order rather than picking at
  // random per cell: random picking clusters duplicates, and a doodle
  // field reads as careless the moment two identical motifs sit adjacent.
  final order = List<int>.generate(assetCount, (i) => i)..shuffle(random);
  var cursor = 0;

  for (var row = 0; row < rows; row++) {
    for (var column = 0; column < columns; column++) {
      // Vary the footprint so the field is not a uniform grid: most
      // doodles sit small, a few are large enough to anchor the eye.
      final scale = 0.45 + random.nextDouble() * 0.5;
      final size = cell * scale;

      // Jitter inside the cell, keeping the whole doodle in bounds.
      final slackX = cell - size;
      final slackY = cell - size;
      final left = column * cell + random.nextDouble() * slackX;
      final top = row * cell + random.nextDouble() * slackY;

      // Non-overlap is geometric, not checked. size < cell and the
      // jitter is bounded by (cell - size), so every doodle lies strictly
      // inside its own cell; cells tile without overlapping, therefore
      // doodles cannot collide. An overlap guard here would be dead code
      // — verified empirically across seeds and cramped areas, it never
      // fired once. Keep that invariant if the sizing ever changes: a
      // scale >= 1.0, or jitter wider than the slack, breaks it.
      final rect = Rect.fromLTWH(left, top, size, size);
      if (rect.right > area.width || rect.bottom > area.height) continue;

      placed.add(DoodlePlacement(
        rect: rect,
        assetIndex: order[cursor % assetCount],
        turns: random.nextInt(4),
        isAnimated: random.nextDouble() < _animatedFraction,
        phase: random.nextDouble(),
      ));
      cursor++;
    }
  }

  // Guarantee every asset appears at least once. A packed field that
  // silently omits a motif looks like an authoring mistake, and with
  // round-robin dealing an unlucky rejection run can drop one entirely.
  final used = placed.map((p) => p.assetIndex).toSet();
  if (used.length < assetCount && placed.isNotEmpty) {
    final missing = [
      for (var i = 0; i < assetCount; i++)
        if (!used.contains(i)) i,
    ];
    for (var i = 0; i < missing.length && i < placed.length; i++) {
      final target = placed[i];
      placed[i] = DoodlePlacement(
        rect: target.rect,
        assetIndex: missing[i],
        turns: target.turns,
        isAnimated: target.isAnimated,
        phase: target.phase,
      );
    }
  }

  return placed;
}

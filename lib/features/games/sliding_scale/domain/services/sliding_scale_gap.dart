import 'dart:math' as math;

/// Sliding Scale gap maths (ATTUNE_MASTER_SPEC.md §8.4).
///
/// Pure and I/O-free. This is the "values overlap from games" input §7
/// names for the Alignment dimension, so its range behaviour matters
/// beyond this game: a NaN or a negative here would propagate into
/// every couple's Pulse score.

/// Absolute distance between two 1-10 ratings.
///
/// Maximum is 9 (1 versus 10), not 10 — the scale has ten positions but
/// nine intervals.
int ratingGap(int a, int b) => (a - b).abs();

/// Mean gap across statements both partners rated.
///
/// Returns 0.0 for an empty list rather than NaN: a couple who rated
/// nothing has no measured disagreement, and NaN would silently corrupt
/// the Alignment dimension it feeds.
double averageGap(List<int> gaps) {
  if (gaps.isEmpty) return 0.0;
  return gaps.reduce((a, b) => a + b) / gaps.length;
}

/// Converts an average gap into a 0-100 alignment score.
///
/// Inverted: a small gap means high alignment. Clamped at both ends so
/// an out-of-range input can never produce a negative or above-100
/// contribution to Pulse.
double alignmentFromGap(double avgGap) {
  const maxGap = 9.0;
  final clamped = math.max(0.0, math.min(maxGap, avgGap));
  return (1.0 - clamped / maxGap) * 100.0;
}

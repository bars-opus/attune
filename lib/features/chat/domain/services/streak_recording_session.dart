/// One segment's length. Deliberately 60s rather than Snapchat's 10s: a
/// partner talking for a minute is the unit of value here, where Snapchat
/// optimises for a rapid highlight reel.
const Duration kStreakSegmentDuration = Duration(seconds: 60);

/// Hard ceiling. At this many completed segments recording STOPS and
/// review opens — the alternative (a rolling window dropping the oldest)
/// silently discards what the user recorded, with nothing in the UI able
/// to explain where it went.
const int kStreakMaxSegments = 5;

/// Guards a stray tap on the FIRST segment only.
const Duration kStreakMinFirstSegment = Duration(milliseconds: 500);

/// One recorded clip awaiting review.
class StreakSegment {
  const StreakSegment({required this.path, required this.duration});

  final String path;
  final Duration duration;
}

/// The segmentation rules, separated from the camera so they can be tested
/// without hardware. Every judgement call the design makes about splitting,
/// capping and discarding lives here rather than in a widget's timer loop.
class StreakRecordingSession {
  const StreakRecordingSession._();

  static bool shouldSplitAt(Duration elapsed) =>
      elapsed >= kStreakSegmentDuration;

  static bool shouldStopAt(int completedSegments) =>
      completedSegments >= kStreakMaxSegments;

  /// Previews appear only once a SECOND segment exists: a lone thumbnail
  /// for a lone clip is noise.
  static bool showPreviews(int completedSegments) => completedSegments >= 2;

  /// Whether to throw the whole recording away on release.
  ///
  /// The minimum applies only to the first segment. A short partial second
  /// segment is real content the user watched themselves record, and
  /// dropping it would make the last thing they said disappear for no
  /// reason they could see.
  static bool shouldDiscard({
    required int completedSegments,
    required Duration held,
  }) =>
      completedSegments == 0 && held < kStreakMinFirstSegment;
}

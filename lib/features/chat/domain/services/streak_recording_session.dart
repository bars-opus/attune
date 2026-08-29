/// One segment's length. Deliberately 60s rather than Snapchat's 10s: a
/// partner talking for a minute is the unit of value here, where Snapchat
/// optimises for a rapid highlight reel.
const Duration kStreakSegmentDuration = Duration(seconds: 60);

/// One segment per streak. A minute is enough to say something, and
/// queueing several clips meant a review step deciding between them, a
/// preview strip, and a multi-clip player — all to send what is meant to
/// be a quick, casual thing. Recording simply stops at the minute and the
/// send/cancel sheet opens.
const int kStreakMaxSegments = 1;

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

  /// Never: a streak is a single clip, so there is nothing to preview
  /// against. Kept as a named rule rather than deleted so the camera does
  /// not grow an ad-hoc condition if segments ever return.
  static bool showPreviews(int completedSegments) => false;

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

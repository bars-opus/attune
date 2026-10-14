/// What Together may send me (plan 2b): the morning summary, and nudges
/// around my partner's big days.
class TogetherPrefs {
  const TogetherPrefs({this.dailySummary = true, this.careNudges = true});

  factory TogetherPrefs.fromJson(Map<String, dynamic> j) => TogetherPrefs(
    dailySummary: j['daily_summary'] as bool? ?? true,
    careNudges: j['care_nudges'] as bool? ?? true,
  );

  final bool dailySummary;
  final bool careNudges;

  TogetherPrefs copyWith({bool? dailySummary, bool? careNudges}) =>
      TogetherPrefs(
        dailySummary: dailySummary ?? this.dailySummary,
        careNudges: careNudges ?? this.careNudges,
      );
}

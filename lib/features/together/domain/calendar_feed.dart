/// The private calendar link (Together Phase 5).
library;

class CalendarFeedStatus {
  const CalendarFeedStatus({required this.active, this.since});

  factory CalendarFeedStatus.fromRow(Map<String, dynamic> r) =>
      CalendarFeedStatus(
        active: r['is_active'] as bool? ?? false,
        since:
            r['since'] == null
                ? null
                : DateTime.parse(r['since'] as String).toLocal(),
      );

  final bool active;
  final DateTime? since;
}

/// The feed's address: https for Google ("From URL"), webcal to open Apple
/// Calendar straight to "Subscribe".
({String https, String webcal}) calendarFeedLinks(
  String supabaseUrl,
  String token,
) {
  final base = supabaseUrl.replaceAll(RegExp(r'/+$'), '');
  final https = '$base/functions/v1/calendar-feed/$token.ics';
  return (
    https: https,
    webcal: https.replaceFirst(RegExp('^https?://'), 'webcal://'),
  );
}

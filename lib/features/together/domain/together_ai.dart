/// Together's AI (Phase 7): it suggests, the person confirms (spec D6).
library;

DateTime _local(String s) {
  final p = DateTime.parse(s); // "YYYY-MM-DD" or "YYYY-MM-DDTHH:MM" → local
  return DateTime(p.year, p.month, p.day, p.hour, p.minute);
}

class CaptureDraft {
  const CaptureDraft({
    required this.title,
    required this.allDay,
    required this.start,
    required this.withPartner,
    this.end,
    this.location,
    this.note,
  });

  factory CaptureDraft.fromJson(Map<String, dynamic> j) => CaptureDraft(
    title: j['title'] as String,
    allDay: j['all_day'] as bool,
    start: _local(j['start_local'] as String),
    end: j['end_local'] == null ? null : _local(j['end_local'] as String),
    withPartner: j['with_partner'] as bool,
    location: j['location'] as String?,
    note: j['note'] as String?,
  );

  final String title;
  final bool allDay;
  final DateTime start;
  final DateTime? end;
  final bool withPartner;
  final String? location;
  final String? note;
}

class DateIdea {
  const DateIdea({required this.title, required this.blurb});
  final String title;
  final String blurb;
}

/// `CONSENT_REQUIRED`, `FEATURE_DISABLED`, `RATE_LIMITED`, `PROVIDER_FAILED`, …
class TogetherAiException implements Exception {
  const TogetherAiException(this.code, {this.retryAfterSeconds});
  final String code;
  final int? retryAfterSeconds;

  @override
  String toString() => 'TogetherAiException($code)';
}

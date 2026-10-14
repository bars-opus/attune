/// The story layer (Together Phase 4): memory prompts, On this day and
/// ritual memories. No counts anywhere (spec §3.1–3.2).
library;

DateTime _day(Object? v) {
  final p = DateTime.parse(v as String);
  return DateTime(p.year, p.month, p.day);
}

/// A lived shared event I haven't remembered yet (plan R4).
class MemoryPrompt {
  const MemoryPrompt({
    required this.eventId,
    required this.title,
    required this.day,
    this.ritualId,
  });

  factory MemoryPrompt.fromRow(Map<String, dynamic> r) => MemoryPrompt(
    eventId: r['event_id'] as String,
    title: r['title'] as String? ?? '',
    day: _day(r['event_day']),
    ritualId: r['ritual_id'] as String?,
  );

  final String eventId;
  final String title;
  final DateTime day;
  final String? ritualId;
}

/// Something from this date in an earlier year (plan R6).
class OnThisDayItem {
  const OnThisDayItem({
    required this.isMoment,
    required this.id,
    required this.date,
    required this.title,
    required this.yearsAgo,
    this.note,
    this.eventType,
  });

  factory OnThisDayItem.fromRow(Map<String, dynamic> r) => OnThisDayItem(
    isMoment: r['item_kind'] == 'moment',
    id: r['item_id'] as String,
    date: _day(r['item_date']),
    title: r['title'] as String? ?? '',
    note: r['note'] as String?,
    eventType: r['event_type'] as String?,
    yearsAgo: (r['years_ago'] as num).toInt(),
  );

  final bool isMoment;
  final String id;
  final DateTime date;
  final String title;
  final String? note;
  final String? eventType;
  final int yearsAgo;

  String get lead => yearsAgo == 1 ? '1 year ago' : '$yearsAgo years ago';
}

/// A moment from one of a ritual's weeks (plan R9).
class RitualMemory {
  const RitualMemory({
    required this.momentId,
    required this.day,
    required this.title,
    required this.loggedBy,
    this.note,
  });

  factory RitualMemory.fromRow(Map<String, dynamic> r) => RitualMemory(
    momentId: r['moment_id'] as String,
    day: _day(r['occurred_at']),
    title: r['title'] as String? ?? '',
    note: r['note'] as String?,
    loggedBy: r['logged_by'] as String,
  );

  final String momentId;
  final DateTime day;
  final String title;
  final String? note;
  final String loggedBy;
}

import 'together_item.dart';

enum TogetherRepeat { none, daily, weekly, monthly, yearly }

const _weekdayCodes = ['MO', 'TU', 'WE', 'TH', 'FR', 'SA', 'SU'];

String _ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// What the event editor collects, before it is saved. [start] and [end]
/// are local times (timed) or calendar dates (all-day); [timezone] is the
/// device's IANA zone, so a weekly 19:00 stays 19:00 across DST.
class CoupleEventDraft {
  const CoupleEventDraft({
    required this.title,
    required this.allDay,
    required this.start,
    this.end,
    this.timezone,
    this.note,
    this.locationName,
    this.kind = 'event',
    this.repeat = TogetherRepeat.none,
    this.interval = 1,
    this.weekdays = const {},
    this.repeatUntil,
    required this.participantIds,
    this.ownerId,
    this.visibility = TogetherVisibility.shared,
    this.remindOffsetsMin = const [],
  });

  /// The editable definition behind a listed event (any occurrence of it):
  /// the series start, repeat rule and reminders from its source_ref.
  factory CoupleEventDraft.fromItem(TogetherItem item) {
    final ref = item.sourceRef;
    DateTime? day(Object? v) {
      if (v == null) return null;
      final p = DateTime.parse(v as String);
      return DateTime(p.year, p.month, p.day);
    }

    DateTime? instant(Object? v) =>
        v == null ? null : DateTime.parse(v as String).toLocal();

    final rule = ref['rrule'] as String?;
    String? part(String key) =>
        rule == null
            ? null
            : RegExp('$key=([A-Z0-9,]+)').firstMatch(rule)?.group(1);
    final freq = part('FREQ');
    final byDay = part('BYDAY');

    return CoupleEventDraft(
      title: item.title,
      allDay: item.allDay,
      start:
          item.allDay
              ? (day(ref['start_date']) ?? item.date)
              : (instant(ref['event_starts_at']) ?? item.startsAt ?? item.date),
      end: item.allDay ? day(ref['end_date']) : instant(ref['event_ends_at']),
      timezone: item.tz,
      note: ref['note'] as String?,
      locationName: ref['location_name'] as String?,
      kind: ref['kind'] as String? ?? 'event',
      repeat: switch (freq) {
        'DAILY' => TogetherRepeat.daily,
        'WEEKLY' => TogetherRepeat.weekly,
        'MONTHLY' => TogetherRepeat.monthly,
        'YEARLY' => TogetherRepeat.yearly,
        _ => TogetherRepeat.none,
      },
      interval: int.tryParse(part('INTERVAL') ?? '') ?? 1,
      weekdays:
          byDay == null
              ? const {}
              : {
                for (final c in byDay.split(',')) _weekdayCodes.indexOf(c) + 1,
              },
      repeatUntil: day(ref['recurrence_until']),
      participantIds: item.participantIds,
      ownerId: item.ownerId,
      visibility: item.visibility,
      remindOffsetsMin: [
        for (final o in (ref['remind_offsets_min'] as List? ?? const []))
          (o as num).toInt(),
      ],
    );
  }

  final String title;
  final bool allDay;
  final DateTime start;
  final DateTime? end;
  final String? timezone;
  final String? note;
  final String? locationName;
  final String kind;
  final TogetherRepeat repeat;
  final int interval;

  /// `DateTime.monday` … `DateTime.sunday`; weekly only.
  final Set<int> weekdays;
  final DateTime? repeatUntil;
  final List<String> participantIds;
  final String? ownerId;
  final TogetherVisibility visibility;
  final List<int> remindOffsetsMin;

  /// The server's RRULE subset (plan ruling R3).
  String? get rrule {
    if (repeat == TogetherRepeat.none) return null;
    final parts = ['FREQ=${repeat.name.toUpperCase()}'];
    if (interval > 1) parts.add('INTERVAL=$interval');
    if (repeat == TogetherRepeat.weekly && weekdays.isNotEmpty) {
      final days = weekdays.toList()..sort();
      parts.add('BYDAY=${days.map((d) => _weekdayCodes[d - 1]).join(',')}');
    }
    return parts.join(';');
  }

  bool get _spansDays {
    final e = end;
    if (e == null) return false;
    return allDay
        ? DateTime(
          e.year,
          e.month,
          e.day,
        ).isAfter(DateTime(start.year, start.month, start.day))
        : e.difference(start) >= const Duration(hours: 24);
  }

  /// Plain-language problem with the draft, or null when it can be saved.
  String? validate() {
    final t = title.trim();
    if (t.isEmpty) return 'Give it a title';
    if (t.length > 120) return 'Keep the title under 120 characters';
    final e = end;
    if (e != null && e.isBefore(start)) return "It can't end before it starts";
    if (participantIds.isEmpty) return "Choose who it's for";
    final until = repeatUntil;
    if (repeat != TogetherRepeat.none &&
        until != null &&
        DateTime(
          until.year,
          until.month,
          until.day,
        ).isBefore(DateTime(start.year, start.month, start.day))) {
      return 'Repeat until must be after the start';
    }
    if (repeat != TogetherRepeat.none && _spansDays) {
      return 'Repeating events last one day';
    }
    return null;
  }

  Map<String, dynamic> toPayload() => {
    'kind': kind,
    'title': title.trim(),
    'note': note,
    'location_name': locationName,
    'all_day': allDay,
    if (allDay) 'start_date': _ymd(start),
    if (allDay && end != null) 'end_date': _ymd(end!),
    if (!allDay) 'starts_at': start.toUtc().toIso8601String(),
    if (!allDay && end != null) 'ends_at': end!.toUtc().toIso8601String(),
    'tz': allDay ? null : timezone,
    'rrule': rrule,
    'recurrence_until': repeatUntil == null ? null : _ymd(repeatUntil!),
    'participant_ids': participantIds,
    'owner_id': ownerId,
    'visibility': visibility.wire,
    'remind_offsets_min': remindOffsetsMin,
  };
}

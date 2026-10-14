/// What "Add to my calendar" hands the system editor (Together Phase 5 R6).
library;

import 'together_item.dart';

enum ExportFrequency { daily, weekly, monthly, yearly }

class CalendarExport {
  const CalendarExport({
    required this.title,
    required this.start,
    required this.end,
    required this.allDay,
    this.description,
    this.location,
    this.frequency,
    this.interval = 1,
    this.until,
    this.onlyThisTime = false,
  });

  final String title;
  final String? description;
  final String? location;
  final DateTime start;
  final DateTime end;
  final bool allDay;
  final ExportFrequency? frequency;
  final int interval;
  final DateTime? until;

  /// A pattern the system editor can't express ("Fri and Sat"): just this one.
  final bool onlyThisTime;
}

DateTime? _date(Object? v) {
  if (v == null) return null;
  final p = DateTime.parse(v as String);
  return DateTime(p.year, p.month, p.day);
}

CalendarExport? calendarExportFor(TogetherItem item, String? me) {
  if (item.kind != TogetherItemKind.event) return null;
  if (item.visibility == TogetherVisibility.busyOnly && item.createdBy != me) {
    return null;
  }
  final ref = item.sourceRef;
  final rrule = ref['rrule'] as String?;
  final freq = switch (RegExp(
    r'FREQ=([A-Z]+)',
  ).firstMatch(rrule ?? '')?.group(1)) {
    'DAILY' => ExportFrequency.daily,
    'WEEKLY' => ExportFrequency.weekly,
    'MONTHLY' => ExportFrequency.monthly,
    'YEARLY' => ExportFrequency.yearly,
    _ => null,
  };
  // One weekday is plain weekly from this occurrence (the editor always
  // writes BYDAY); two or more ("Fri and Sat") can't be expressed.
  final days =
      RegExp(
        r'BYDAY=([A-Z,]+)',
      ).firstMatch(rrule ?? '')?.group(1)?.split(',') ??
      const <String>[];
  final byDay = days.length > 1;
  final interval =
      int.tryParse(
        RegExp(r'INTERVAL=(\d+)').firstMatch(rrule ?? '')?.group(1) ?? '',
      ) ??
      1;
  final DateTime start;
  final DateTime end;
  if (item.allDay) {
    start = rrule == null ? (_date(ref['start_date']) ?? item.day) : item.day;
    end = rrule == null ? (_date(ref['end_date']) ?? start) : start;
  } else {
    start = item.startsAt!;
    end = item.endsAt ?? start.add(const Duration(hours: 1));
  }
  return CalendarExport(
    title: item.title,
    description: ref['note'] as String?,
    location: ref['location_name'] as String?,
    start: start,
    end: end,
    allDay: item.allDay,
    frequency: byDay ? null : freq,
    interval: interval,
    until: byDay ? null : _date(ref['recurrence_until']),
    onlyThisTime: byDay,
  );
}

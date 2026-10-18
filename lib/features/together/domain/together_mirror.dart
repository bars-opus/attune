/// The phone-calendar copy (Together Phase 8d): plans I'm in for the next
/// 60 days, in a calendar of their own. Titles, times and places only; no
/// names or notes (R2). One-way: Together is the source (spec §6.4).
library;

import 'together_item.dart';

const mirrorDays = 60;

String _ymd(DateTime d) => '${d.year}-${d.month}-${d.day}';

/// Matches a copied entry to its plan without storing anything per entry
/// (R3). All-day entries compare by day: phones store their times variously.
String mirrorFingerprint({
  required String title,
  required DateTime start,
  required DateTime end,
  required bool allDay,
  String? location,
}) {
  final when =
      allDay
          ? '${_ymd(start)}..${_ymd(end)}'
          : '${start.millisecondsSinceEpoch}..${end.millisecondsSinceEpoch}';
  return '$title|$when|$allDay|${location ?? ''}';
}

/// Phones report an all-day event's end either as its last day or as the
/// midnight after it; both mean the same last day.
DateTime allDayLastDay(DateTime start, DateTime end) {
  final first = DateTime(start.year, start.month, start.day);
  final last = DateTime(end.year, end.month, end.day);
  final midnight =
      end.hour == 0 &&
      end.minute == 0 &&
      end.second == 0 &&
      end.millisecond == 0;
  return midnight && last.isAfter(first)
      ? DateTime(last.year, last.month, last.day - 1)
      : last;
}

/// What to hand the phone as an all-day entry's end: Android stores it as
/// the midnight after the last day (exclusive), iOS as the last day itself.
DateTime deviceAllDayEnd(DateTime lastDay, {required bool exclusiveEnd}) =>
    exclusiveEnd
        ? DateTime(lastDay.year, lastDay.month, lastDay.day + 1)
        : lastDay;

class MirrorEvent {
  const MirrorEvent({
    required this.title,
    required this.start,
    required this.end,
    required this.allDay,
    this.location,
  });

  final String title;

  /// Local times; for all-day entries the first and last day (midnight).
  final DateTime start;
  final DateTime end;
  final bool allDay;
  final String? location;

  String get fingerprint => mirrorFingerprint(
    title: title,
    start: start,
    end: end,
    allDay: allDay,
    location: location,
  );
}

/// An entry already in the phone's copy.
class DeviceMirrorEvent {
  const DeviceMirrorEvent({
    required this.id,
    required this.start,
    required this.fingerprint,
  });

  final String id;
  final DateTime start;
  final String fingerprint;
}

DateTime? _date(Object? v) {
  if (v == null) return null;
  final p = DateTime.parse(v as String);
  return DateTime(p.year, p.month, p.day);
}

/// The calendar copy's word for a plan when titles are off (Spec 1b). A
/// place outs a plan as surely as its title, so it goes with it (R-I).
const mirrorNeutralTitle = 'Plan';

List<MirrorEvent> mirrorEventsFor({
  required List<TogetherItem> items,
  required String? me,
  bool showTitles = false,
}) {
  if (me == null) return const [];
  final out = <MirrorEvent>[];
  final seen = <String>{};
  for (final i in items) {
    if (i.kind != TogetherItemKind.event || i.status != 'confirmed') continue;
    // Surprises and busy blocks stay in Together (spec §3).
    if (i.visibility != TogetherVisibility.shared) continue;
    if (!i.participantIds.contains(me)) continue;
    // A multi-day plan arrives once per day: copy it once, from its first.
    if (i.sourceRef['continuation'] == true) continue;
    final title = i.title.trim();
    if (title.isEmpty) continue;
    final s = i.startsAt;
    final allDay = i.allDay || s == null;
    final DateTime start;
    final DateTime end;
    if (allDay) {
      // A repeating all-day plan is one day each time.
      final repeats = i.sourceRef['rrule'] != null;
      start = repeats ? i.date : (_date(i.sourceRef['start_date']) ?? i.date);
      end = repeats ? start : (_date(i.sourceRef['end_date']) ?? start);
    } else {
      start = s;
      end = i.endsAt ?? s.add(const Duration(hours: 1));
    }
    final e = MirrorEvent(
      title: showTitles ? title : mirrorNeutralTitle,
      start: start,
      end: end,
      allDay: allDay,
      location: showTitles ? i.sourceRef['location_name'] as String? : null,
    );
    // Keyed by plan as well as fingerprint: with titles off two plans at the
    // same time share a fingerprint and must still be two entries (Spec 1b).
    if (seen.add('${i.id}|${e.fingerprint}')) out.add(e);
  }
  return out;
}

/// What to add and what to remove so the copy matches [desired]. Duplicates
/// on the phone beyond what's wanted are removed.
({List<MirrorEvent> create, List<String> delete}) mirrorChanges(
  List<MirrorEvent> desired,
  List<DeviceMirrorEvent> existing,
) {
  final pool = <String, List<String>>{};
  for (final e in existing) {
    (pool[e.fingerprint] ??= []).add(e.id);
  }
  final create = <MirrorEvent>[];
  for (final d in desired) {
    final ids = pool[d.fingerprint];
    if (ids != null && ids.isNotEmpty) {
      ids.removeAt(0);
    } else {
      create.add(d);
    }
  }
  return (create: create, delete: [for (final ids in pool.values) ...ids]);
}

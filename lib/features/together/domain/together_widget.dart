/// The home-screen "Next" card (Together Phase 8a): plans I'm in and
/// today's free time, as a glance. No names added, no app wording (R1, R3).
library;

import 'dart:convert';

import 'package:intl/intl.dart';

import 'together_item.dart';
import 'together_overlay.dart';

class WidgetLine {
  const WidgetLine({
    required this.title,
    required this.label,
    required this.startMs,
    required this.endMs,
    this.neutralTitle = widgetNeutralTitle,
  });

  final String title;

  /// What the card shows unless this phone turned plan titles on (Spec 1b).
  final String neutralTitle;
  final String label;
  final int startMs;
  final int endMs;
}

/// The card's words for a plan when titles are off (Spec 1b; research 06 §3
/// F8 (1)): a glance at a locked or borrowed phone says when, never what.
const widgetNeutralTitle = 'Next plan';
const widgetNeutralReminderTitle = 'Reminder';

/// What actually goes to the card: titles only where this phone opted in.
List<WidgetLine> widgetLinesForCard(
  List<WidgetLine> lines, {
  required bool showTitles,
}) => [
  for (final l in lines)
    showTitles
        ? l
        : WidgetLine(
          title: l.neutralTitle,
          label: l.label,
          startMs: l.startMs,
          endMs: l.endMs,
          neutralTitle: l.neutralTitle,
        ),
];

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

// intl puts a narrow no-break space before AM/PM; some widget fonts draw it
// badly, so the card uses a plain space.
String _jm(DateTime t, String? locale) =>
    DateFormat.jm(locale).format(t).replaceAll('\u202f', ' ');

String _when(
  DateTime start,
  DateTime today,
  String? locale, {
  bool timed = true,
}) {
  final diff = _day(start).difference(today).inDays;
  final time = _jm(start, locale);
  final day = switch (diff) {
    0 => timed ? null : 'Today',
    1 => 'Tomorrow',
    _ => DateFormat.E(locale).format(start),
  };
  if (!timed) return day!;
  return day == null ? time : '$day $time';
}

List<WidgetLine> togetherWidgetLines({
  required List<TogetherItem> items,
  required List<FreeWindow> windows,
  required String? me,
  required DateTime now,
  String? locale,
}) {
  final today = _day(now);
  final out = <WidgetLine>[];
  final seen = <String>{};
  for (final i in items) {
    // Plans I'm in: events I take part in, and our shared reminders.
    final mine = switch (i.kind) {
      TogetherItemKind.event => me != null && i.participantIds.contains(me),
      TogetherItemKind.reminder => true,
      _ => false,
    };
    if (!mine) continue;
    final DateTime start;
    final DateTime end;
    if (i.allDay || i.startsAt == null) {
      start = _day(i.day);
      // An all-day plan lasts to the end of its last day.
      final last = i.sourceRef['end_date'] as String?;
      end =
          last == null
              ? start.add(const Duration(days: 1))
              : _day(DateTime.parse(last)).add(const Duration(days: 1));
    } else {
      start = i.startsAt!;
      end = i.endsAt ?? start.add(const Duration(hours: 1));
    }
    if (!end.isAfter(now)) continue;
    // A multi-day plan arrives once per day, a repeating one once per time:
    // one line each, the first that isn't over.
    if (!seen.add('${i.kind.name}:${i.id}')) continue;
    out.add(
      WidgetLine(
        title: i.title,
        label: _when(
          start,
          today,
          locale,
          timed: !(i.allDay || i.startsAt == null),
        ),
        startMs: start.millisecondsSinceEpoch,
        endMs: end.millisecondsSinceEpoch,
        neutralTitle:
            i.kind == TogetherItemKind.reminder
                ? widgetNeutralReminderTitle
                : widgetNeutralTitle,
      ),
    );
  }
  for (final w in windows) {
    if (_day(w.start) != today || !w.end.isAfter(now)) continue;
    out.add(
      WidgetLine(
        title: 'Free',
        label: '${_jm(w.start, locale)}–${_jm(w.end, locale)}',
        startMs: w.start.millisecondsSinceEpoch,
        endMs: w.end.millisecondsSinceEpoch,
        neutralTitle: 'Free',
      ),
    );
  }
  out.sort((a, b) => a.startMs.compareTo(b.startMs));
  return out.take(3).toList();
}

String encodeWidgetPayload(List<WidgetLine> lines) => jsonEncode({
  'v': 1,
  'lines': [
    for (final l in lines)
      {'title': l.title, 'label': l.label, 'start': l.startMs, 'end': l.endMs},
  ],
});

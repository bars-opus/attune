import 'together_care.dart';
import 'together_item.dart';

/// The Agenda's sections, built from what `list_together_items` returned.
class TogetherAgenda {
  const TogetherAgenda({
    required this.today,
    required this.week,
    required this.comingUp,
    required this.recentMoments,
    this.careCards = const [],
  });

  final List<TogetherItem> today;

  /// The next six days that have something, in order.
  final List<({DateTime day, List<TogetherItem> items})> week;

  /// Further ahead, each item once (a trip appears on its first day only).
  final List<TogetherItem> comingUp;

  /// The newest three moments, newest first.
  final List<TogetherItem> recentMoments;

  /// My partner's big days that deserve a word right now (plan 2b).
  final List<CareCard> careCards;

  bool get isEmpty =>
      today.isEmpty &&
      week.isEmpty &&
      comingUp.isEmpty &&
      recentMoments.isEmpty &&
      careCards.isEmpty;
}

DateTime _dayOf(DateTime d) => DateTime(d.year, d.month, d.day);

/// Today through 90 days ahead (inside the server's 93-day cap).
({DateTime start, DateTime end}) togetherUpcomingRange(DateTime now) {
  final today = _dayOf(now);
  return (start: today, end: DateTime(today.year, today.month, today.day + 90));
}

/// The 93 days before today, for recent moments.
({DateTime start, DateTime end}) togetherPastRange(DateTime now) {
  final today = _dayOf(now);
  return (
    start: DateTime(today.year, today.month, today.day - 93),
    end: DateTime(today.year, today.month, today.day - 1),
  );
}

/// All-day first, then by start time, then title.
int compareTogetherItems(TogetherItem a, TogetherItem b) {
  final day = a.day.compareTo(b.day);
  if (day != 0) return day;
  if (a.allDay != b.allDay) return a.allDay ? -1 : 1;
  final sa = a.startsAt, sb = b.startsAt;
  if (sa != null && sb != null) {
    final t = sa.compareTo(sb);
    if (t != 0) return t;
  }
  return a.title.toLowerCase().compareTo(b.title.toLowerCase());
}

TogetherAgenda togetherAgenda({
  required List<TogetherItem> upcoming,
  required List<TogetherItem> past,
  required DateTime now,
  String? me,
}) {
  final today = _dayOf(now);
  final weekEnd = DateTime(today.year, today.month, today.day + 6);
  final plans =
      upcoming.where((i) => i.kind != TogetherItemKind.moment).toList()
        ..sort(compareTogetherItems);

  final week = <({DateTime day, List<TogetherItem> items})>[];
  for (var d = 1; d <= 6; d++) {
    final day = DateTime(today.year, today.month, today.day + d);
    final items = plans.where((i) => i.day == day).toList();
    if (items.isNotEmpty) week.add((day: day, items: items));
  }

  final seen = <String>{};
  final comingUp = [
    for (final i in plans)
      if (i.day.isAfter(weekEnd) && seen.add('${i.kind.name}:${i.id}')) i,
  ];

  final moments =
      [...past, ...upcoming]
          .where(
            (i) => i.kind == TogetherItemKind.moment && !i.day.isAfter(today),
          )
          .toList()
        ..sort((a, b) => b.day.compareTo(a.day));

  return TogetherAgenda(
    today: plans.where((i) => i.day == today).toList(),
    week: week,
    comingUp: comingUp,
    recentMoments: moments.take(3).toList(),
    careCards: togetherCareCards([...upcoming, ...past], me: me, now: now),
  );
}

/// The soonest plan that hasn't started yet (all-day items count for their
/// whole day). Moments are memories, not plans.
/// The next [count] things still ahead (no moments, nothing whose start
/// has passed), soonest first.
List<TogetherItem> upcomingTogetherItems(
  List<TogetherItem> items,
  DateTime now, {
  int count = 3,
}) {
  final today = _dayOf(now);
  final upcoming =
      items.where((i) {
          if (i.kind == TogetherItemKind.moment) return false;
          if (i.day.isBefore(today)) return false;
          final s = i.startsAt;
          return i.allDay || s == null || !s.isBefore(now);
        }).toList()
        ..sort(compareTogetherItems);
  return upcoming.take(count).toList();
}

TogetherItem? nextTogetherItem(List<TogetherItem> items, DateTime now) =>
    upcomingTogetherItems(items, now, count: 1).firstOrNull;

/// "Today", "Tomorrow" or "In 12 days", as the reminder rows count down.
String togetherCountdown(DateTime day, DateTime now) {
  // Calendar days, counted in UTC so a clock change can't make one short.
  final days =
      DateTime.utc(
        day.year,
        day.month,
        day.day,
      ).difference(DateTime.utc(now.year, now.month, now.day)).inDays;
  if (days == 0) return 'Today';
  if (days == 1) return 'Tomorrow';
  return 'In $days days';
}

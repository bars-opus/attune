import 'package:flutter/material.dart' show DateUtils;
import 'package:attune/core/utils/date_formatter.dart';
import 'package:intl/intl.dart';

/// Apple Notes-style groups: Today, Yesterday, Previous 7 Days, Previous 30
/// Days, then month names this year, then years. Groups come out newest
/// first; items keep their order within a group. [at] is the date an item
/// is grouped by (Planning: its last activity; the journal: when written).
List<({String title, List<T> items})> noteDateSections<T>(
  List<T> items,
  DateTime Function(T) at,
  DateTime now,
) {
  final today = DateUtils.dateOnly(now);
  String bucket(DateTime when) {
    final day = DateUtils.dateOnly(when.toLocal());
    final days = today.difference(day).inDays;
    if (days <= 0) return 'Today';
    if (days == 1) return 'Yesterday';
    if (days <= 7) return 'Previous 7 Days';
    if (days <= 30) return 'Previous 30 Days';
    if (day.year == today.year) return DateFormat.MMMM().format(day);
    return '${day.year}';
  }

  final groups = <String, List<T>>{};
  final newest = <String, DateTime>{};
  for (final item in items) {
    final when = at(item);
    final key = bucket(when);
    (groups[key] ??= []).add(item);
    if (newest[key] == null || when.isAfter(newest[key]!)) newest[key] = when;
  }
  final keys = groups.keys.toList()..sort((a, b) => newest[b]!.compareTo(newest[a]!));
  return [for (final k in keys) (title: k, items: groups[k]!)];
}

/// The date on a row, in the app's own format ([MyDateFormat]): the time
/// today, "Yesterday", the weekday this week, else the full date.
String noteRowDate(DateTime at, DateTime now) {
  final local = at.toLocal();
  final days = DateUtils.dateOnly(now).difference(DateUtils.dateOnly(local)).inDays;
  if (days <= 0) return MyDateFormat.toTime(local);
  if (days == 1) return 'Yesterday';
  if (days <= 7) return DateFormat.EEEE().format(local);
  return MyDateFormat.toDate(local);
}

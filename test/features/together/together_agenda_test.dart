import 'package:attune/features/together/domain/together_agenda.dart';
import 'package:attune/features/together/domain/together_item.dart';
import 'package:flutter_test/flutter_test.dart';

TogetherItem _i(
  String id,
  DateTime day, {
  TogetherItemKind kind = TogetherItemKind.event,
  DateTime? startsAt,
  String title = 'x',
}) => TogetherItem(
  kind: kind,
  id: id,
  date: DateTime(day.year, day.month, day.day),
  startsAt: startsAt,
  allDay: startsAt == null,
  title: title,
  participantIds: const ['ama', 'kofi'],
);

void main() {
  final now = DateTime(2026, 11, 2, 9);

  test('today: all-day first, then by time, then title; moments excluded', () {
    final a = togetherAgenda(
      upcoming: [
        _i('late', now, startsAt: DateTime(2026, 11, 2, 19), title: 'Dinner'),
        _i('early', now, startsAt: DateTime(2026, 11, 2, 8), title: 'Gym'),
        _i('allday', now, title: 'Rent'),
        _i('m', now, kind: TogetherItemKind.moment),
      ],
      past: const [],
      now: now,
    );
    expect(a.today.map((i) => i.id), ['allday', 'early', 'late']);
  });

  test('this week groups the next six days that have something', () {
    final a = togetherAgenda(
      upcoming: [
        _i('tue', DateTime(2026, 11, 3)),
        _i('sun', DateTime(2026, 11, 8)),
        _i('next-mon', DateTime(2026, 11, 9)),
      ],
      past: const [],
      now: now,
    );
    expect(a.week.map((w) => w.day), [
      DateTime(2026, 11, 3),
      DateTime(2026, 11, 8),
    ]);
    expect(a.comingUp.map((i) => i.id), ['next-mon']);
  });

  test('a multi-day trip shows every day this week but once in coming up', () {
    final trip = [
      for (var d = 7; d <= 11; d++)
        _i('trip', DateTime(2026, 11, d), title: 'Lisbon'),
    ];
    final a = togetherAgenda(upcoming: trip, past: const [], now: now);
    expect(a.week.map((w) => w.day), [
      DateTime(2026, 11, 7),
      DateTime(2026, 11, 8),
    ]);
    expect(a.comingUp.where((i) => i.id == 'trip'), hasLength(1));
  });

  test('a timed item is grouped by the viewer\'s local day', () {
    // 23:30 tonight in a zone 6 hours behind is tomorrow morning here.
    final starts = DateTime(2026, 11, 3, 5, 30);
    final a = togetherAgenda(
      upcoming: [_i('call', DateTime(2026, 11, 2), startsAt: starts)],
      past: const [],
      now: now,
    );
    expect(a.today, isEmpty);
    expect(a.week.single.day, DateTime(2026, 11, 3));
  });

  test('recent moments: newest three from the past', () {
    final a = togetherAgenda(
      upcoming: const [],
      past: [
        for (var d = 1; d <= 5; d++)
          _i('m$d', DateTime(2026, 10, d), kind: TogetherItemKind.moment),
      ],
      now: now,
    );
    expect(a.recentMoments.map((i) => i.id), ['m5', 'm4', 'm3']);
    expect(a.isEmpty, isFalse);
  });

  test('ranges stay inside the 93-day server cap', () {
    final up = togetherUpcomingRange(now);
    final past = togetherPastRange(now);
    expect(up.start, DateTime(2026, 11, 2));
    expect(up.end.difference(up.start).inDays, lessThanOrEqualTo(93));
    expect(past.end, DateTime(2026, 11, 1));
    expect(past.end.difference(past.start).inDays, lessThanOrEqualTo(93));
  });

  test('the next few things: soonest first, no moments, nothing already past', () {
    final items = [
      _i('m', now, kind: TogetherItemKind.moment),
      _i('gone', now, startsAt: DateTime(2026, 11, 2, 8)),
      _i('later', DateTime(2026, 11, 9)),
      _i('dinner', now, startsAt: DateTime(2026, 11, 2, 19)),
      _i('rent', now),
      _i('trip', DateTime(2026, 11, 20)),
    ];
    expect(upcomingTogetherItems(items, now, count: 3).map((i) => i.id), ['rent', 'dinner', 'later']);
    expect(nextTogetherItem(items, now)?.id, 'rent');
  });

  test('a countdown reads like the reminder rows', () {
    expect(togetherCountdown(DateTime(2026, 11, 2), now), 'Today');
    expect(togetherCountdown(DateTime(2026, 11, 3), now), 'Tomorrow');
    expect(togetherCountdown(DateTime(2026, 11, 12), now), 'In 10 days');
  });
}

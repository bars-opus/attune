// Will we make it? A goal's pace: what's done since it began, against the
// date it's due by.
import 'package:attune/features/planning/domain/goal_pace.dart';
import 'package:flutter_test/flutter_test.dart';

final _today = DateTime(2026, 10, 18);
DateTime _d(int days) => _today.add(Duration(days: days));

PlanningPace? _pace({
  int done = 0,
  int total = 10,
  int startedDaysAgo = 10,
  int? dueIn = 30,
}) => planningGoalPace(
  done: done,
  total: total,
  startedOn: _d(-startedDaysAgo),
  targetDate: dueIn == null ? null : _d(dueIn),
  today: _today,
);

void main() {
  test('no target date, or nothing to do: no pace', () {
    expect(_pace(dueIn: null, done: 3), isNull);
    expect(_pace(total: 0), isNull);
  });

  test('all done: reached', () {
    expect(_pace(done: 10), isA<PaceReached>());
    expect(
      _pace(done: 12),
      isA<PaceReached>(),
      reason: 'past a target counts too',
    );
  });

  test('nothing done yet: say how to start', () {
    expect(_pace(done: 0), isA<PaceNotStarted>());
  });

  test('the date has passed, not done', () {
    expect(_pace(done: 4, dueIn: -1), isA<PaceOverdue>());
  });

  test('on the day itself: what is left', () {
    final p = _pace(done: 8, dueIn: 0);
    expect(p, isA<PaceDueToday>());
    expect((p! as PaceDueToday).left, 2);
  });

  test('on pace: on track for the date', () {
    // 4 in 10 days; 6 left need 15 days; 18 left — on track, not early.
    final p = _pace(done: 4, dueIn: 18);
    expect(p, isA<PaceOnTrack>());
    expect((p! as PaceOnTrack).by, _d(18));
  });

  test('well ahead: when it will be done at this rate', () {
    // 5 in 10 days; 5 left need 10 days; due in 60.
    final p = _pace(done: 5, dueIn: 60);
    expect(p, isA<PaceAhead>());
    expect((p! as PaceAhead).finish, _d(10));
  });

  test('behind: what a week would take', () {
    // 2 in 10 days; 8 left need 40 days; due in 28 (4 weeks): 2 a week.
    final p = _pace(done: 2, dueIn: 28);
    expect(p, isA<PaceBehind>());
    expect((p! as PaceBehind).amount, 2);
    expect((p as PaceBehind).perDay, isFalse);
  });

  test('behind with under a week to go: what a day would take', () {
    // 1 in 10 days; 9 left; due in 3: 3 a day.
    final p = _pace(done: 1, dueIn: 3);
    expect(p, isA<PaceBehind>());
    final behind = p! as PaceBehind;
    expect((behind.amount, behind.perDay), (3, true));
  });

  test('a goal made today: a day counts as the first day', () {
    // 1 done on day one; 9 left need 9 days; due in 30: ahead.
    expect(_pace(done: 1, startedDaysAgo: 0, dueIn: 30), isA<PaceAhead>());
  });

  test('rounds up what is needed, never down to nothing', () {
    // 1 in 10 days; 9 left, due in 63 (9 weeks): exactly 1 a week.
    expect((_pace(done: 1, dueIn: 63)! as PaceBehind).amount, 1);
    // 13 left need 130 days, due in 120 (about 17 weeks): under one a week,
    // rounded up to 1.
    final slow = _pace(done: 1, total: 14, dueIn: 120);
    expect(slow, isA<PaceBehind>());
    expect((slow! as PaceBehind).amount, 1);
  });
}

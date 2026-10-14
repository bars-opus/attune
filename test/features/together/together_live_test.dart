import 'package:attune/features/together/domain/together_item.dart';
import 'package:attune/features/together/domain/together_live.dart';
import 'package:flutter_test/flutter_test.dart';

final _now = DateTime(2026, 11, 2, 16);

TogetherItem _e(
  String id, {
  required DateTime start,
  DateTime? end,
  List<String> who = const ['ama', 'kofi'],
  TogetherVisibility visibility = TogetherVisibility.shared,
  String status = 'confirmed',
  TogetherItemKind kind = TogetherItemKind.event,
  bool allDay = false,
}) => TogetherItem(
  kind: kind,
  id: id,
  date: DateTime(start.year, start.month, start.day),
  startsAt: allDay ? null : start,
  endsAt: allDay ? null : end,
  allDay: allDay,
  title: id,
  participantIds: who,
  createdBy: 'ama',
  visibility: visibility,
  status: status,
);

LivePlan? _pick(List<TogetherItem> items) =>
    livePlanFor(items: items, me: 'ama', now: _now);

void main() {
  test('a shared plan tonight shows from 4 hours before it starts', () {
    final dinner = _e(
      'Dinner',
      start: DateTime(2026, 11, 2, 21),
      end: DateTime(2026, 11, 2, 23),
    );
    expect(_pick([dinner]), isNull); // 5 hours away at 16:00
    expect(
      livePlanFor(items: [dinner], me: 'ama', now: DateTime(2026, 11, 2, 17)),
      LivePlan(
        title: 'Dinner',
        start: DateTime(2026, 11, 2, 21),
        end: DateTime(2026, 11, 2, 23),
      ),
    );
    // No end time: an hour.
    final walk = _e('Walk', start: DateTime(2026, 11, 2, 20));
    expect(
      _pick([walk]),
      LivePlan(
        title: 'Walk',
        start: DateTime(2026, 11, 2, 20),
        end: DateTime(2026, 11, 2, 21),
      ),
    );
  });

  test('the plan under way beats a later one; an ended one never shows', () {
    final under = _e(
      'Lunch',
      start: DateTime(2026, 11, 2, 15),
      end: DateTime(2026, 11, 2, 17),
    );
    final later = _e(
      'Film',
      start: DateTime(2026, 11, 2, 18),
      end: DateTime(2026, 11, 2, 20),
    );
    final ended = _e(
      'Gym',
      start: DateTime(2026, 11, 2, 14),
      end: DateTime(2026, 11, 2, 16),
    );
    expect(_pick([later, ended, under])?.title, 'Lunch');
  });

  test(
    'never private, busy-only, just mine, suggested, all-day or a reminder',
    () {
      final at = DateTime(2026, 11, 2, 18);
      expect(
        _pick([
          _e('Surprise', start: at, visibility: TogetherVisibility.private),
          _e('Busy', start: at, visibility: TogetherVisibility.busyOnly),
          _e('Mine', start: at, who: const ['ama']),
          _e('Theirs', start: at, who: const ['kofi']),
          _e('Maybe', start: at, status: 'proposed'),
          _e('Trip', start: at, allDay: true),
          _e('Call mum', start: at, kind: TogetherItemKind.reminder),
        ]),
        isNull,
      );
      expect(
        livePlanFor(items: [_e('Dinner', start: at)], me: null, now: _now),
        isNull,
      );
    },
  );
}

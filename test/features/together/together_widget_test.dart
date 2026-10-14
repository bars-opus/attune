import 'dart:convert';

import 'package:attune/features/together/domain/together_item.dart';
import 'package:attune/features/together/domain/together_overlay.dart';
import 'package:attune/features/together/domain/together_widget.dart';
import 'package:flutter_test/flutter_test.dart';

TogetherItem _event(
  String id,
  DateTime start, {
  List<String> who = const ['ama', 'kofi'],
  String visibility = 'shared',
  String createdBy = 'ama',
  String title = 'Dinner',
  bool allDay = false,
  String kind = 'event',
  Map<String, dynamic> ref = const {},
}) => TogetherItem.fromRow({
  'item_kind': kind,
  'item_id': id,
  'item_date':
      '${start.year}-${start.month.toString().padLeft(2, '0')}-${start.day.toString().padLeft(2, '0')}',
  'starts_at': allDay ? null : start.toUtc().toIso8601String(),
  'ends_at':
      allDay
          ? null
          : start.add(const Duration(hours: 2)).toUtc().toIso8601String(),
  'all_day': allDay,
  'tz': allDay ? null : 'UTC',
  'title': title,
  'participant_ids': who,
  'owner_id': null,
  'created_by': createdBy,
  'visibility': visibility,
  'status': 'confirmed',
  'source_ref': {'kind': 'event', ...ref},
});

void main() {
  final now = DateTime(2026, 11, 2, 9); // Monday 09:00

  test('my plans, soonest first, labelled for a glance', () {
    final lines = togetherWidgetLines(
      items: [
        _event('a', DateTime(2026, 11, 7, 19), title: 'Dinner'),
        _event('b', DateTime(2026, 11, 2, 18), title: 'Gym', who: ['ama']),
        _event('c', DateTime(2026, 11, 3, 8), title: 'Flight'),
      ],
      windows: const [],
      me: 'ama',
      now: now,
    );
    expect(lines.map((l) => (l.title, l.label)), [
      ('Gym', '6:00 PM'),
      ('Flight', 'Tomorrow 8:00 AM'),
      ('Dinner', 'Sat 7:00 PM'),
    ]);
  });

  test("my partner's own plans, busy blocks and moments never appear", () {
    final lines = togetherWidgetLines(
      items: [
        _event(
          'p',
          DateTime(2026, 11, 2, 12),
          who: ['kofi'],
          createdBy: 'kofi',
          title: 'Kofi lunch',
        ),
        _event(
          'b',
          DateTime(2026, 11, 2, 13),
          who: ['kofi'],
          createdBy: 'kofi',
          visibility: 'busy_only',
          title: 'Busy',
        ),
        _event(
          'm',
          DateTime(2026, 11, 2, 0),
          kind: 'moment',
          title: 'A memory',
        ),
      ],
      windows: const [],
      me: 'ama',
      now: now,
    );
    expect(lines, isEmpty);
  });

  test('a past plan is gone; an all-day plan lasts its whole day', () {
    final lines = togetherWidgetLines(
      items: [
        _event('old', DateTime(2026, 11, 2, 6), title: 'Run'), // ended 08:00
        _event('day', DateTime(2026, 11, 2), title: 'Rent', allDay: true),
      ],
      windows: const [],
      me: 'ama',
      now: now,
    );
    expect(lines.single.title, 'Rent');
    expect(lines.single.label, 'Today');
    expect(lines.single.endMs, DateTime(2026, 11, 3).millisecondsSinceEpoch);
  });

  test("today's free window shows as Free, with no names", () {
    final lines = togetherWidgetLines(
      items: const [],
      windows: [
        FreeWindow(
          start: DateTime(2026, 11, 2, 19),
          end: DateTime(2026, 11, 2, 22),
          partnerFrom: '14:00',
          partnerTo: '17:00',
          partnerDiffers: true,
        ),
      ],
      me: 'ama',
      now: now,
    );
    expect(
      (lines.single.title, lines.single.label),
      ('Free', '7:00 PM–10:00 PM'),
    );
  });

  test('the payload is small JSON with epoch times', () {
    final json =
        jsonDecode(
              encodeWidgetPayload([
                const WidgetLine(
                  title: 'Dinner',
                  label: 'Sat 7:00 PM',
                  startMs: 1,
                  endMs: 2,
                ),
              ]),
            )
            as Map;
    expect(json, {
      'v': 1,
      'lines': [
        {'title': 'Dinner', 'label': 'Sat 7:00 PM', 'start': 1, 'end': 2},
      ],
    });
  });

  test('a three-day trip is one line, lasting to the end of its last day', () {
    final ref = {'start_date': '2026-11-02', 'end_date': '2026-11-04'};
    final lines = togetherWidgetLines(
      items: [
        _event(
          'trip',
          DateTime(2026, 11, 2),
          title: 'Cape Coast',
          allDay: true,
          ref: {...ref, 'continuation': false},
        ),
        _event(
          'trip',
          DateTime(2026, 11, 3),
          title: 'Cape Coast',
          allDay: true,
          ref: {...ref, 'continuation': true},
        ),
        _event(
          'trip',
          DateTime(2026, 11, 4),
          title: 'Cape Coast',
          allDay: true,
          ref: {...ref, 'continuation': true},
        ),
        _event('d', DateTime(2026, 11, 3, 19), title: 'Dinner'),
      ],
      windows: const [],
      me: 'ama',
      now: now,
    );
    expect(lines.map((l) => l.title), ['Cape Coast', 'Dinner']);
    expect(lines.first.endMs, DateTime(2026, 11, 5).millisecondsSinceEpoch);
  });

  test("a repeating plan that's over today shows its next time", () {
    final lines = togetherWidgetLines(
      items: [
        _event('yoga', DateTime(2026, 11, 2, 6), title: 'Yoga'), // ended 08:00
        _event('yoga', DateTime(2026, 11, 9, 6), title: 'Yoga'),
      ],
      windows: const [],
      me: 'ama',
      now: now,
    );
    expect(lines.single.label, 'Mon 6:00 AM');
  });
}

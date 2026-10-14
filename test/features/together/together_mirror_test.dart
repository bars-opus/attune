import 'package:attune/features/together/domain/together_item.dart';
import 'package:attune/features/together/domain/together_mirror.dart';
import 'package:flutter_test/flutter_test.dart';

TogetherItem _e(
  String title, {
  DateTime? start,
  DateTime? end,
  DateTime? day,
  List<String> who = const ['ama', 'kofi'],
  TogetherVisibility visibility = TogetherVisibility.shared,
  String status = 'confirmed',
  TogetherItemKind kind = TogetherItemKind.event,
  Map<String, dynamic> ref = const {},
}) => TogetherItem(
  kind: kind,
  id: title,
  date: day ?? DateTime(start!.year, start.month, start.day),
  startsAt: start,
  endsAt: end,
  allDay: start == null,
  title: title,
  participantIds: who,
  createdBy: 'ama',
  visibility: visibility,
  status: status,
  sourceRef: ref,
);

void main() {
  test('copies shared, confirmed plans I am in: titles, times and places', () {
    final out = mirrorEventsFor(
      me: 'ama',
      items: [
        _e(
          'Dinner',
          start: DateTime(2026, 11, 3, 19),
          ref: const {'location_name': 'Kozo', 'note': 'bring wine'},
        ),
        _e('Gym', start: DateTime(2026, 11, 4, 7), who: const ['ama']),
        _e(
          'Surprise',
          start: DateTime(2026, 11, 5, 19),
          visibility: TogetherVisibility.private,
        ),
        _e(
          'Busy',
          start: DateTime(2026, 11, 5, 9),
          visibility: TogetherVisibility.busyOnly,
        ),
        _e('Theirs', start: DateTime(2026, 11, 5, 12), who: const ['kofi']),
        _e('Maybe', start: DateTime(2026, 11, 6, 19), status: 'proposed'),
        _e(
          'Call mum',
          start: DateTime(2026, 11, 6, 9),
          kind: TogetherItemKind.reminder,
        ),
        _e('  ', start: DateTime(2026, 11, 7, 9)),
      ],
    );
    expect(out.map((e) => e.title), ['Dinner', 'Gym']);
    expect(out.first.location, 'Kozo');
    expect(out.first.end, DateTime(2026, 11, 3, 20)); // no end: an hour
    expect(
      mirrorEventsFor(
        me: null,
        items: [_e('Dinner', start: DateTime(2026, 11, 3, 19))],
      ),
      isEmpty,
    );
  });

  test('a three-day trip is one all-day entry; its later days are skipped', () {
    final ref = {'start_date': '2026-11-06', 'end_date': '2026-11-08'};
    final out = mirrorEventsFor(
      me: 'ama',
      items: [
        _e('Lisbon', day: DateTime(2026, 11, 6), ref: ref),
        _e(
          'Lisbon',
          day: DateTime(2026, 11, 7),
          ref: {...ref, 'continuation': true},
        ),
        _e(
          'Lisbon',
          day: DateTime(2026, 11, 8),
          ref: {...ref, 'continuation': true},
        ),
      ],
    );
    expect(out, hasLength(1));
    expect(out.single.allDay, isTrue);
    expect(out.single.start, DateTime(2026, 11, 6));
    expect(out.single.end, DateTime(2026, 11, 8));
  });

  test(
    'phones report an all-day end as the last day or the midnight after it',
    () {
      final start = DateTime(2026, 11, 6);
      expect(
        allDayLastDay(start, DateTime(2026, 11, 8, 23, 59, 59)),
        DateTime(2026, 11, 8),
      );
      expect(
        allDayLastDay(start, DateTime(2026, 11, 9)),
        DateTime(2026, 11, 8),
      );
      expect(
        allDayLastDay(start, DateTime(2026, 11, 6)),
        DateTime(2026, 11, 6),
      );
    },
  );

  test(
    'unchanged entries stay, new ones are added, gone or edited ones go',
    () {
      MirrorEvent m(String t, int h) => MirrorEvent(
        title: t,
        start: DateTime(2026, 11, 3, h),
        end: DateTime(2026, 11, 3, h + 1),
        allDay: false,
      );
      DeviceMirrorEvent d(String id, MirrorEvent e) =>
          DeviceMirrorEvent(id: id, start: e.start, fingerprint: e.fingerprint);
      final keep = m('Dinner', 19);
      final renamed = m('Brunch', 11);
      final changes = mirrorChanges(
        [keep, renamed, m('Film', 21)],
        [
          d('a', keep),
          d('b', m('Breakfast', 11)),
          d('c', m('Gone', 8)),
          d('dup', keep),
        ],
      );
      expect(changes.create.map((e) => e.title), ['Brunch', 'Film']);
      expect(changes.delete.toSet(), {'b', 'c', 'dup'});
    },
  );

  test('a moved last day, a new place or a new time is a different entry', () {
    final base = mirrorFingerprint(
      title: 'Lisbon',
      start: DateTime(2026, 11, 6),
      end: DateTime(2026, 11, 8),
      allDay: true,
    );
    expect(
      mirrorFingerprint(
        title: 'Lisbon',
        start: DateTime(2026, 11, 6),
        end: DateTime(2026, 11, 9),
        allDay: true,
      ),
      isNot(base),
    );
    expect(
      mirrorFingerprint(
        title: 'Lisbon',
        start: DateTime(2026, 11, 6),
        end: DateTime(2026, 11, 8),
        allDay: true,
        location: 'Porto',
      ),
      isNot(base),
    );
    // All-day: the time of day the phone stores doesn't matter.
    expect(
      mirrorFingerprint(
        title: 'Lisbon',
        start: DateTime(2026, 11, 6, 0, 0, 1),
        end: DateTime(2026, 11, 8, 23, 59),
        allDay: true,
      ),
      base,
    );
    expect(
      mirrorFingerprint(
        title: 'Dinner',
        start: DateTime(2026, 11, 3, 19),
        end: DateTime(2026, 11, 3, 20),
        allDay: false,
      ),
      isNot(
        mirrorFingerprint(
          title: 'Dinner',
          start: DateTime(2026, 11, 3, 19, 30),
          end: DateTime(2026, 11, 3, 20, 30),
          allDay: false,
        ),
      ),
    );
  });

  test(
    'an all-day trip reads back as the same entry on either kind of phone',
    () {
      final trip = MirrorEvent(
        title: 'Lisbon',
        start: DateTime(2026, 11, 6),
        end: DateTime(2026, 11, 8),
        allDay: true,
      );
      // Android stores the end as the midnight after the last day and hands
      // that back; iOS keeps the last day and hands back its last second.
      expect(
        deviceAllDayEnd(trip.end, exclusiveEnd: true),
        DateTime(2026, 11, 9),
      );
      expect(deviceAllDayEnd(trip.end, exclusiveEnd: false), trip.end);
      for (final back in [
        DateTime(2026, 11, 9),
        DateTime(2026, 11, 8, 23, 59, 59),
      ]) {
        expect(
          mirrorFingerprint(
            title: 'Lisbon',
            start: trip.start,
            end: allDayLastDay(trip.start, back),
            allDay: true,
          ),
          trip.fingerprint,
        );
      }
      // A one-day plan on Android ends at the next midnight: still one day.
      expect(
        allDayLastDay(
          DateTime(2026, 11, 6),
          deviceAllDayEnd(DateTime(2026, 11, 6), exclusiveEnd: true),
        ),
        DateTime(2026, 11, 6),
      );
    },
  );
}

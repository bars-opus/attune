import 'package:attune/features/together/domain/couple_event_draft.dart';
import 'package:flutter_test/flutter_test.dart';

CoupleEventDraft _draft({
  String title = 'Date night',
  bool allDay = false,
  DateTime? start,
  DateTime? end,
  TogetherRepeat repeat = TogetherRepeat.none,
  int interval = 1,
  Set<int> weekdays = const {},
  List<String> participants = const ['ama', 'kofi'],
}) => CoupleEventDraft(
  title: title,
  allDay: allDay,
  start: start ?? DateTime(2026, 10, 16, 19),
  end: end,
  timezone: 'Europe/London',
  repeat: repeat,
  interval: interval,
  weekdays: weekdays,
  participantIds: participants,
);

void main() {
  test('rrule follows the server whitelist', () {
    expect(_draft().rrule, isNull);
    expect(
      _draft(repeat: TogetherRepeat.daily, interval: 2).rrule,
      'FREQ=DAILY;INTERVAL=2',
    );
    expect(
      _draft(
        repeat: TogetherRepeat.weekly,
        weekdays: {DateTime.friday, DateTime.monday},
      ).rrule,
      'FREQ=WEEKLY;BYDAY=MO,FR',
    );
    expect(_draft(repeat: TogetherRepeat.monthly).rrule, 'FREQ=MONTHLY');
    expect(_draft(repeat: TogetherRepeat.yearly).rrule, 'FREQ=YEARLY');
  });

  test('timed payload sends UTC instants and the zone', () {
    final p = _draft(end: DateTime(2026, 10, 16, 21)).toPayload();
    expect(p['all_day'], false);
    expect(
      p['starts_at'],
      DateTime(2026, 10, 16, 19).toUtc().toIso8601String(),
    );
    expect(p['ends_at'], DateTime(2026, 10, 16, 21).toUtc().toIso8601String());
    expect(p['tz'], 'Europe/London');
    expect(p.containsKey('start_date'), isFalse);
  });

  test('all-day payload sends plain dates and no zone', () {
    final p =
        _draft(
          allDay: true,
          start: DateTime(2026, 11, 7),
          end: DateTime(2026, 11, 9),
        ).toPayload();
    expect(p['start_date'], '2026-11-07');
    expect(p['end_date'], '2026-11-09');
    expect(p.containsKey('starts_at'), isFalse);
    expect(p['tz'], isNull);
  });

  test('validation speaks plainly', () {
    expect(_draft().validate(), isNull);
    expect(_draft(title: '  ').validate(), 'Give it a title');
    expect(
      _draft(title: 'x' * 121).validate(),
      'Keep the title under 120 characters',
    );
    expect(
      _draft(end: DateTime(2026, 10, 16, 18)).validate(),
      "It can't end before it starts",
    );
    expect(_draft(participants: const []).validate(), "Choose who it's for");
    expect(
      _draft(
        allDay: true,
        start: DateTime(2026, 11, 7),
        end: DateTime(2026, 11, 8),
        repeat: TogetherRepeat.weekly,
      ).validate(),
      'Repeating events last one day',
    );
  });

  test('a repeat must not end before it starts', () {
    final d = CoupleEventDraft(
      title: 'Gym',
      allDay: true,
      start: DateTime(2026, 11, 7),
      repeat: TogetherRepeat.weekly,
      repeatUntil: DateTime(2026, 11, 1),
      participantIds: const ['ama'],
    );
    expect(d.validate(), 'Repeat until must be after the start');
  });
}

import 'package:attune/features/together/domain/calendar_export.dart';
import 'package:attune/features/together/domain/together_item.dart';
import 'package:flutter_test/flutter_test.dart';

TogetherItem _item({
  bool allDay = false,
  String? rrule,
  String visibility = 'shared',
  String createdBy = 'ama',
  String title = 'Dinner',
  Map<String, dynamic> extra = const {},
}) => TogetherItem.fromRow({
  'item_kind': 'event',
  'item_id': 'e1',
  'item_date': '2026-11-07',
  'starts_at': allDay ? null : '2026-11-07T18:00:00+00:00',
  'ends_at': allDay ? null : '2026-11-07T20:00:00+00:00',
  'all_day': allDay,
  'tz': allDay ? null : 'Africa/Accra',
  'title': title,
  'participant_ids': ['ama', 'kofi'],
  'owner_id': null,
  'created_by': createdBy,
  'visibility': visibility,
  'status': 'confirmed',
  'source_ref': {
    'kind': 'event',
    'note': 'Bring cash',
    'location_name': 'Buka',
    if (rrule != null) 'rrule': rrule,
    ...extra,
  },
});

void main() {
  test('a one-off timed event exports as it is', () {
    final e = calendarExportFor(_item(), 'ama')!;
    expect(
      [e.title, e.description, e.location, e.allDay],
      ['Dinner', 'Bring cash', 'Buka', false],
    );
    expect(e.start, DateTime.utc(2026, 11, 7, 18).toLocal());
    expect(e.end, DateTime.utc(2026, 11, 7, 20).toLocal());
    expect(e.frequency, isNull);
  });

  test('a multi-day all-day trip spans its days', () {
    final e =
        calendarExportFor(
          _item(
            allDay: true,
            extra: {'start_date': '2026-11-07', 'end_date': '2026-11-09'},
          ),
          'ama',
        )!;
    expect(
      [e.allDay, e.start, e.end],
      [true, DateTime(2026, 11, 7), DateTime(2026, 11, 9)],
    );
  });

  test('a repeating event carries its pattern and end', () {
    final e =
        calendarExportFor(
          _item(
            rrule: 'FREQ=WEEKLY;INTERVAL=2',
            extra: {'recurrence_until': '2027-06-30'},
          ),
          'ama',
        )!;
    expect(
      [e.frequency, e.interval, e.until, e.onlyThisTime],
      [ExportFrequency.weekly, 2, DateTime(2027, 6, 30), false],
    );
  });

  test('a weekly event made in the app (one weekday) keeps repeating', () {
    final e = calendarExportFor(_item(rrule: 'FREQ=WEEKLY;BYDAY=FR'), 'ama')!;
    expect(
      [e.frequency, e.interval, e.onlyThisTime],
      [ExportFrequency.weekly, 1, false],
    );
  });

  test('a weekday pattern exports this time only, and says so', () {
    final e =
        calendarExportFor(_item(rrule: 'FREQ=WEEKLY;BYDAY=FR,SA'), 'ama')!;
    expect([e.frequency, e.onlyThisTime], [null, true]);
  });

  test("a partner's busy-only event can't be exported; my own can", () {
    expect(
      calendarExportFor(
        _item(visibility: 'busy_only', createdBy: 'kofi', title: 'Busy'),
        'ama',
      ),
      isNull,
    );
    expect(calendarExportFor(_item(visibility: 'busy_only'), 'ama'), isNotNull);
  });
}

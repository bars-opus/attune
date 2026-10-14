import 'package:attune/features/together/domain/couple_event_draft.dart';
import 'package:attune/features/together/domain/together_item.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a weekly timed event round-trips into an editable draft', () {
    final item = TogetherItem.fromRow({
      'item_kind': 'event',
      'item_id': 'e1',
      'item_date': '2026-10-23',
      'starts_at': '2026-10-23T18:00:00+00:00',
      'ends_at': '2026-10-23T20:00:00+00:00',
      'all_day': false,
      'tz': 'Europe/London',
      'title': 'Date night',
      'participant_ids': ['ama', 'kofi'],
      'owner_id': 'ama',
      'created_by': 'ama',
      'visibility': 'shared',
      'status': 'confirmed',
      'source_ref': {
        'kind': 'event',
        'note': 'Somewhere new',
        'location_name': 'Osu',
        'event_starts_at': '2026-10-16T18:00:00+00:00',
        'event_ends_at': '2026-10-16T20:00:00+00:00',
        'rrule': 'FREQ=WEEKLY;INTERVAL=2;BYDAY=MO,FR',
        'recurrence_until': '2026-12-31',
        'remind_offsets_min': [60],
      },
    });
    final d = CoupleEventDraft.fromItem(item);
    expect(
      d.start,
      DateTime.utc(2026, 10, 16, 18).toLocal(),
      reason: 'the series start, not this occurrence',
    );
    expect(d.end, DateTime.utc(2026, 10, 16, 20).toLocal());
    expect(d.timezone, 'Europe/London');
    expect(d.repeat, TogetherRepeat.weekly);
    expect(d.interval, 2);
    expect(d.weekdays, {DateTime.monday, DateTime.friday});
    expect(d.repeatUntil, DateTime(2026, 12, 31));
    expect(d.remindOffsetsMin, [60]);
    expect(d.ownerId, 'ama');
    expect(d.rrule, 'FREQ=WEEKLY;INTERVAL=2;BYDAY=MO,FR');
  });

  test('an all-day trip keeps its dates', () {
    final item = TogetherItem.fromRow({
      'item_kind': 'event',
      'item_id': 'e2',
      'item_date': '2026-11-08',
      'starts_at': null,
      'ends_at': null,
      'all_day': true,
      'tz': null,
      'title': 'Lisbon',
      'participant_ids': ['ama'],
      'owner_id': null,
      'created_by': 'ama',
      'visibility': 'private',
      'status': 'confirmed',
      'source_ref': {
        'kind': 'trip',
        'start_date': '2026-11-07',
        'end_date': '2026-11-11',
        'continuation': true,
      },
    });
    final d = CoupleEventDraft.fromItem(item);
    expect(d.allDay, isTrue);
    expect(d.start, DateTime(2026, 11, 7));
    expect(d.end, DateTime(2026, 11, 11));
    expect(d.kind, 'trip');
    expect(d.visibility, TogetherVisibility.private);
    expect(d.repeat, TogetherRepeat.none);
  });
}

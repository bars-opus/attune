import 'package:attune/features/together/domain/together_ritual.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a ritual row maps and reads naturally', () {
    final r = TogetherRitual.fromRow({
      'ritual_id': 'r1',
      'template': 'date_night',
      'title': 'Date night',
      'cadence': 'weekly',
      'weekday': 5,
      'local_time': '19:00',
      'duration_min': 120,
      'tz': 'Africa/Accra',
      'status': 'active',
      'created_by': 'ama',
      'proposed_to': null,
      'next_event_id': 'e1',
      'next_starts_at': '2026-11-06T19:00:00+00:00',
    });
    expect(r.status, RitualStatus.active);
    expect(r.when, 'Fridays at 19:00');
    expect(r.nextStartsAt, DateTime.utc(2026, 11, 6, 19).toLocal());
    final f = TogetherRitual.fromRow({
      ...{
        'ritual_id': 'r2',
        'template': 'state_of_union',
        'title': 'SOTU',
        'cadence': 'fortnightly',
        'weekday': 7,
        'local_time': '18:00',
        'duration_min': 60,
        'tz': 'UTC',
        'status': 'paused',
        'created_by': 'kofi',
        'proposed_to': null,
        'next_event_id': null,
        'next_starts_at': null,
      },
    });
    expect(f.when, 'Every other Sunday at 18:00');
    expect(f.status, RitualStatus.paused);
  });

  test('templates cover each couple type, with plain names', () {
    expect(
      ritualTemplates.map((t) => t.id),
      containsAll([
        'date_night',
        'state_of_union',
        'weekly_call',
        'bedtime_check_in',
        'custom',
      ]),
    );
    final d = ritualTemplates.firstWhere((t) => t.id == 'date_night');
    expect([d.weekday, d.hour, d.durationMin], [DateTime.friday, 19, 120]);
  });

  test('a draft sends what the server checks', () {
    const draft = RitualDraft(
      template: 'date_night',
      title: 'Date night',
      cadence: RitualCadence.weekly,
      weekday: 5,
      hour: 19,
      minute: 0,
      durationMin: 120,
      tz: 'Africa/Accra',
    );
    expect(draft.toPayload(), {
      'template': 'date_night',
      'title': 'Date night',
      'cadence': 'weekly',
      'weekday': 5,
      'local_time': '19:00',
      'duration_min': 120,
      'tz': 'Africa/Accra',
    });
  });

  test("a ritual in another zone says whose clock it's on", () {
    TogetherRitual at(String tz) => TogetherRitual.fromRow({
      'ritual_id': 'r1',
      'template': 'weekly_call',
      'title': 'Weekly call',
      'cadence': 'weekly',
      'weekday': 7,
      'local_time': '19:00',
      'duration_min': 60,
      'tz': tz,
      'status': 'proposed',
    });
    expect(
      at('Europe/London').whenFor('America/Toronto'),
      'Sundays at 19:00 (London time)',
    );
    expect(
      at('America/New_York').whenFor('Africa/Accra'),
      'Sundays at 19:00 (New York time)',
    );
    expect(at('Europe/London').whenFor('Europe/London'), 'Sundays at 19:00');
    expect(at('Europe/London').whenFor(null), 'Sundays at 19:00');
  });
}

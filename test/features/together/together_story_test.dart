import 'package:attune/features/together/data/together_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import 'together_repository_test.dart' show FakeTogetherGateway;

void main() {
  test('memory prompts send my zone and map rows', () async {
    final g = FakeTogetherGateway({
      'list_together_memory_prompts':
          (_) => [
            {
              'event_id': 'e1',
              'title': 'Dinner at Buka',
              'event_day': '2026-11-07',
              'ended_at': '2026-11-07T20:00:00+00:00',
              'ritual_id': null,
            },
          ],
    });
    final p = await TogetherRepository(
      g,
    ).listMemoryPrompts('r1', tz: 'Africa/Accra');
    expect(g.calls.single.$2, {
      'p_relationship_id': 'r1',
      'p_tz': 'Africa/Accra',
    });
    expect(
      [p.single.eventId, p.single.title, p.single.day],
      ['e1', 'Dinner at Buka', DateTime(2026, 11, 7)],
    );
  });

  test('adding and dismissing send the event', () async {
    final g = FakeTogetherGateway({
      'add_event_memory': (_) => 'm1',
      'dismiss_memory_prompt': (_) => null,
    });
    final repo = TogetherRepository(g);
    expect(await repo.addEventMemory('e1', 'So good'), 'm1');
    await repo.dismissMemoryPrompt('e1');
    expect(g.calls.map((c) => c.$2).toList(), [
      {'p_event_id': 'e1', 'p_line': 'So good'},
      {'p_event_id': 'e1'},
    ]);
  });

  test('on this day sends my local date and reads naturally', () async {
    final g = FakeTogetherGateway({
      'list_together_on_this_day':
          (_) => [
            {
              'item_kind': 'moment',
              'item_id': 'm1',
              'item_date': '2025-11-07',
              'title': 'First date',
              'note': null,
              'event_type': 'first',
              'years_ago': 1,
            },
            {
              'item_kind': 'event',
              'item_id': 'e2',
              'item_date': '2023-11-07',
              'title': 'Trip',
              'note': null,
              'event_type': null,
              'years_ago': 3,
            },
          ],
    });
    final items = await TogetherRepository(
      g,
    ).listOnThisDay('r1', DateTime(2026, 11, 7, 22, 30));
    expect(g.calls.single.$2, {
      'p_relationship_id': 'r1',
      'p_today': '2026-11-07',
    });
    expect(items.map((i) => (i.isMoment, i.lead)).toList(), [
      (true, '1 year ago'),
      (false, '3 years ago'),
    ]);
  });

  test('ritual memories and archive pages map rows', () async {
    final g = FakeTogetherGateway({
      'list_together_ritual_memories':
          (_) => [
            {
              'moment_id': 'm1',
              'occurred_at': '2026-11-07',
              'title': 'Date night',
              'note': 'Dancing after',
              'logged_by': 'kofi',
            },
          ],
      'list_together_moments':
          (_) => [
            {
              'id': 'm1',
              'relationship_id': 'r1',
              'logged_by': 'kofi',
              'event_type': 'highlight',
              'title': 'Date night',
              'note': 'Dancing after',
              'mood_score': null,
              'occurred_at': '2026-11-07',
              'created_at': '2026-11-07T21:00:00Z',
              'updated_at': '2026-11-07T21:00:00Z',
              'deleted_at': null,
              'visibility': 'shared',
              'couple_event_id': 'e1',
            },
          ],
    });
    final repo = TogetherRepository(g);
    final m = await repo.listRitualMemories('rit-1');
    expect(
      [m.single.note, m.single.day],
      ['Dancing after', DateTime(2026, 11, 7)],
    );
    final page = await repo.listMoments(
      'r1',
      beforeDate: DateTime(2026, 12, 1),
      beforeId: 'm9',
      limit: 30,
    );
    expect(g.calls.last.$2, {
      'p_relationship_id': 'r1',
      'p_before_date': '2026-12-01',
      'p_before_id': 'm9',
      'p_limit': 30,
    });
    expect(page.single.coupleEventId, 'e1');
  });
}

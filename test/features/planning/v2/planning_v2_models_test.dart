import 'package:attune/features/planning/v2/data/planning_v2_models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_planning_gateway.dart';

void main() {
  test('entry detail parses blocks, items and members in order', () {
    final d = PlanningEntryDetail.fromJson(fakeEntryDetailJson(blocks: [
      fakeBlockJson(id: 'b1', type: 'text', payload: {
        'delta': [{'insert': 'Hi\n'}]
      }, plainText: 'Hi'),
      fakeBlockJson(id: 'b2', items: [fakeItemJson(id: 'i1', section: 'Dairy')]),
      fakeBlockJson(id: 'b3', type: 'date', dateStart: '2026-11-01', dateEnd: '2026-11-05'),
    ]));
    expect(d.blocks.map((b) => b.type), [PlanningBlockType.text, PlanningBlockType.checklist, PlanningBlockType.date]);
    expect(d.blocks[1].items.single.section, 'Dairy');
    expect(d.blocks[2].dateEnd, DateTime(2026, 11, 5));
    expect(d.members.map((m) => m.displayName), ['Ama', 'Kofi']);
    expect(d.blocks[0].delta, [{'insert': 'Hi\n'}]);
  });

  test('a block type from a newer server parses as unsupported, not a crash', () {
    final b = PlanningBlock.fromJson(fakeBlockJson(id: 'b9', type: 'budget'));
    expect(b.type, PlanningBlockType.unsupported);
    expect(b.rawType, 'budget');
  });

  test('unicode titles round-trip unchanged (Review Focus 5)', () {
    const title = 'שלום 🌴 é';
    final d = PlanningEntryDetail.fromJson(fakeEntryDetailJson(title: title));
    expect(d.entry.title, title);
    expect(d.entry.title.runes.length, 8);
  });

  test('planningYmd pads', () {
    expect(planningYmd(DateTime(2026, 1, 5)), '2026-01-05');
  });

  test('a list page carries its pinned group; entries know when they are pinned', () {
    Map<String, dynamic> s(String id, bool pinned) => {
          'id': id, 'title': 'T', 'status': 'active', 'last_activity_at': '2026-10-12T09:00:00Z',
          'pinned': pinned, 'date_start': null, 'date_end': null, 'checklist_done': 0, 'checklist_total': 0,
        };
    final page = PlanningEntriesPage.fromJson({'entries': [s('a', false)], 'pinned': [s('p', true)], 'next_cursor': null});
    expect(page.pinned.single.pinned, isTrue);
    expect(page.entries.single.pinned, isFalse);
    expect(PlanningEntriesPage.fromJson({'entries': [], 'next_cursor': null}).pinned, isEmpty,
        reason: 'a later page has no pinned group');
    expect(PlanningEntryDetail.fromJson(fakeEntryDetailJson(pinnedAt: '2026-10-12T09:00:00Z')).entry.isPinned, isTrue);
  });
}

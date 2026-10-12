import 'dart:convert';

import 'package:attune/features/planning/v2/data/planning_v2_error.dart';
import 'package:attune/features/planning/v2/data/planning_v2_models.dart';
import 'package:attune/features/planning/v2/domain/planning_outbox.dart';
import 'package:attune/features/planning/v2/presentation/planning_v2_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/fake_planning_gateway.dart';
import 'support/planning_v2_test_app.dart';

const args = (relationshipId: 'r1', entryId: 'e1');

FakePlanningGateway _gatewayWithEntry() => FakePlanningGateway({
      'get_planning_entry': (_) => fakeEntryDetailJson(blocks: [
            fakeBlockJson(id: 'b1', items: [fakeItemJson(id: 'i1', text: 'Tomatoes')]),
            fakeBlockJson(id: 'b2', type: 'date', sortKey: 'k'),
          ]),
    });

void main() {
  late FakePlanningGateway gateway;
  late MemoryOutboxStore store;
  late ProviderContainer c;

  Future<PlanningEntryController> ready() async {
    await c.read(planningV2EntryProvider(args).future);
    return c.read(planningV2EntryProvider(args).notifier);
  }

  PlanningEntryDetail current() => c.read(planningV2EntryProvider(args)).requireValue;

  setUp(() {
    gateway = _gatewayWithEntry();
    store = MemoryOutboxStore();
    c = ProviderContainer(overrides: planningV2Overrides(gateway, store: store));
    addTearDown(c.dispose);
    // keep autoDispose providers alive for the test
    c.listen(planningV2EntryProvider(args), (_, __) {});
  });

  test('tick is optimistic, then replaced by the server row', () async {
    final ctl = await ready();
    gateway.handlers['set_planning_block_item_checked'] =
        (_) => fakeItemJson(id: 'i1', text: 'Tomatoes', checkedAt: '2026-10-12T09:00:00Z', version: 2);
    final f = ctl.setChecked('b1', current().blocks.first.items.first, true);
    expect(current().blocks.first.items.first.isChecked, isTrue, reason: 'optimistic');
    expect(await f, TickOutcome.synced);
    expect(current().blocks.first.items.first.version, 2);
  });

  test('offline tick is queued, stays ticked, and survives a refetch', () async {
    final ctl = await ready();
    gateway.handlers['set_planning_block_item_checked'] =
        (_) => throw Exception('SocketException: offline');
    expect(await ctl.setChecked('b1', current().blocks.first.items.first, true), TickOutcome.queued);
    expect(store.raw, hasLength(1));
    c.invalidate(planningV2EntryProvider(args));
    await c.read(planningV2EntryProvider(args).future);
    expect(current().blocks.first.items.first.isChecked, isTrue,
        reason: 'pending outbox ops are overlaid on fetched data');
  });

  test('a permanent tick failure reverts just that item and rethrows', () async {
    final ctl = await ready();
    gateway.handlers['set_planning_block_item_checked'] =
        (_) => throw const PostgrestException(message: 'planning:not_found', code: 'P0001');
    await expectLater(ctl.setChecked('b1', current().blocks.first.items.first, true),
        throwsA(isA<PlanningV2NotFound>()));
    expect(current().blocks.first.items.first.isChecked, isFalse);
    expect(store.raw, isEmpty);
  });

  test('addItem appends after the last item and replaces with the server row', () async {
    final ctl = await ready();
    gateway.handlers['add_planning_block_item'] =
        (p) => fakeItemJson(id: p['p_id'] as String, text: 'Milk', sortKey: 'k');
    await ctl.addItem('b1', 'Milk');
    expect(gateway.callsTo('add_planning_block_item').single['p_after_id'], 'i1');
    expect(current().blocks.first.items.map((i) => i.text), ['Tomatoes', 'Milk']);
  });

  test('delete block is optimistic and restore puts it back in place', () async {
    final ctl = await ready();
    gateway.handlers['delete_planning_block'] = (_) => {'deleted': true};
    gateway.handlers['restore_planning_block'] =
        (_) => fakeBlockJson(id: 'b1', items: [fakeItemJson(id: 'i1', text: 'Tomatoes')]);
    await ctl.deleteBlock('b1');
    expect(current().blocks.map((b) => b.id), ['b2']);
    await ctl.restoreBlock('b1', index: 0);
    expect(current().blocks.map((b) => b.id), ['b1', 'b2']);
  });

  test('moveBlock sends the id it now follows', () async {
    final ctl = await ready();
    gateway.handlers['move_planning_block'] = (_) => fakeBlockJson(id: 'b1', sortKey: 'z');
    await ctl.moveBlock('b1', 1);
    expect(current().blocks.map((b) => b.id), ['b2', 'b1']);
    expect(gateway.callsTo('move_planning_block').single['p_after_id'], 'b2');
  });

  test('saveText: conflict returns theirs; not_found removes the block', () async {
    final ctl = await ready();
    gateway.handlers['update_planning_block'] = (_) => throw PostgrestException(
          message: 'planning:stale_version',
          code: 'P0001',
          hint: jsonEncode({
            'current': fakeBlockJson(id: 'b1', type: 'text', plainText: 'Kofi', version: 5, payload: {
              'delta': [{'insert': 'Kofi\n'}]
            }),
          }),
        );
    final r = await ctl.saveText('b1', 1, const [{'insert': 'Ama\n'}]);
    expect(r, isA<TextConflict>());
    expect((r as TextConflict).theirs.version, 5);

    gateway.handlers['update_planning_block'] =
        (_) => throw const PostgrestException(message: 'planning:not_found', code: 'P0001');
    expect(await ctl.saveText('b1', 5, const [{'insert': 'Ama\n'}]), isA<TextGone>());
    expect(current().blocks.map((b) => b.id), ['b2']);
  });

  test('entries pager: second page appends; hasMore false at the end', () async {
    var page = 0;
    gateway.handlers['list_planning_entries'] = (p) {
      page++;
      return {
        'entries': [
          {'id': 'e$page', 'title': 'T$page', 'status': 'active', 'last_activity_at': '2026-10-12T09:00:00Z',
           'date_start': null, 'date_end': null, 'checklist_done': 0, 'checklist_total': 0}
        ],
        'next_cursor': page == 1 ? {'at': '2026-10-12T09:00:00Z', 'id': 'e1'} : null,
      };
    };
    const a = (relationshipId: 'r1', categoryId: 'c1', group: 'open');
    c.listen(planningV2EntriesProvider(a), (_, __) {});
    await c.read(planningV2EntriesProvider(a).future);
    await c.read(planningV2EntriesProvider(a).notifier).loadMore();
    final s = c.read(planningV2EntriesProvider(a)).requireValue;
    expect(s.entries.map((e) => e.id), ['e1', 'e2']);
    expect(s.hasMore, isFalse);
    expect(gateway.callsTo('list_planning_entries').last['p_cursor_id'], 'e1');
  });
}

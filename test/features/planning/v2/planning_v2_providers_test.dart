import 'dart:async';
import 'dart:convert';

import 'package:attune/features/planning/presentation/providers/planning_providers.dart' show planningChangeSignalProvider;
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

  group('outbox ordering (final review I2)', () {
    test('offline tick, then online untick: the untick queues behind the tick and wins', () async {
      final ctl = await ready();
      gateway.handlers['set_planning_block_item_checked'] = (_) => throw Exception('offline');
      final item = current().blocks.first.items.first;
      expect(await ctl.setChecked('b1', item, true), TickOutcome.queued);

      final applied = <bool>[];
      gateway.handlers['set_planning_block_item_checked'] = (p) {
        applied.add(p['p_checked'] as bool);
        return fakeItemJson(id: 'i1', text: 'Tomatoes', checkedAt: (p['p_checked'] as bool) ? '2026-10-12T09:00:00Z' : null);
      };
      expect(await ctl.setChecked('b1', current().blocks.first.items.first, false), TickOutcome.queued,
          reason: 'never jump ahead of an older queued op for the same entry');
      await c.read(planningV2OutboxProvider).replay();
      expect(applied, [true, false], reason: 'server sees the user\'s actions in the order they made them');
      expect(store.raw, isEmpty);
      c.invalidate(planningV2EntryProvider(args));
      await c.read(planningV2EntryProvider(args).future);
    });

    test('offline add, then online tick of that item: tick waits for the add, no false "removed"', () async {
      final ctl = await ready();
      gateway.handlers['add_planning_block_item'] = (_) => throw Exception('offline');
      expect(await ctl.addItem('b1', 'Bread'), TickOutcome.queued);
      final bread = current().blocks.first.items.last;

      final order = <String>[];
      gateway.handlers['add_planning_block_item'] = (p) {
        order.add('add');
        return fakeItemJson(id: p['p_id'] as String, text: 'Bread');
      };
      gateway.handlers['set_planning_block_item_checked'] = (p) {
        order.add('tick');
        return fakeItemJson(id: p['p_id'] as String, text: 'Bread', checkedAt: '2026-10-12T09:00:00Z');
      };
      expect(await ctl.setChecked('b1', bread, true), TickOutcome.queued);
      await c.read(planningV2OutboxProvider).replay();
      expect(order, ['add', 'tick']);
      expect(current().blocks.first.items.last.isChecked, isTrue);
    });

    test('a change signal on the HOME screen replays queued ops (sync after reconnect)', () async {
      final signal = StreamController<void>.broadcast();
      addTearDown(signal.close);
      final store2 = MemoryOutboxStore()
        ..raw = [
          {'kind': 'check', 'op_id': 'op-1', 'relationship_id': 'r1', 'entry_id': 'e1', 'item_id': 'i1', 'checked': true}
        ];
      final g2 = FakePlanningGateway({
        'get_planning_home': (_) => {'categories': []},
        'set_planning_block_item_checked': (p) => fakeItemJson(id: 'i1', checkedAt: '2026-10-12T09:00:00Z'),
      });
      final c2 = ProviderContainer(overrides: [
        ...planningV2Overrides(g2, store: store2),
        planningChangeSignalProvider.overrideWith((ref, id) => signal.stream),
      ]);
      addTearDown(c2.dispose);
      c2.listen(planningV2HomeProvider('r1'), (_, __) {});
      await c2.read(planningV2HomeProvider('r1').future);
      signal.add(null);
      // Only the signal may trigger the replay: the test never calls replay().
      for (var i = 0; i < 50 && store2.raw.isNotEmpty; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(g2.callsTo('set_planning_block_item_checked'), hasLength(1));
      expect(store2.raw, isEmpty);
    });
  });

  group('entries list: pin, delete, undo', () {
    Map<String, dynamic> s(String id, {bool pinned = false}) => {
          'id': id, 'title': 'T$id', 'status': 'active', 'last_activity_at': '2026-10-12T09:00:00Z',
          'pinned': pinned, 'date_start': null, 'date_end': null, 'checklist_done': 0, 'checklist_total': 0,
        };
    const a = (relationshipId: 'r1', categoryId: 'c1', group: 'open');

    Future<PlanningEntriesController> entries() async {
      c.listen(planningV2EntriesProvider(a), (_, __) {});
      await c.read(planningV2EntriesProvider(a).future);
      return c.read(planningV2EntriesProvider(a).notifier);
    }

    PlanningEntriesState st() => c.read(planningV2EntriesProvider(a)).requireValue;

    test('pin moves a plan into the pinned group at once; unpin moves it back', () async {
      gateway.handlers['list_planning_entries'] = (_) => {'entries': [s('1'), s('2')], 'pinned': [], 'next_cursor': null};
      gateway.handlers['pin_planning_entry'] = (p) => {
            'entry': {...fakeEntryDetailJson(id: p['p_id'] as String)['entry'] as Map,
                      'pinned_at': (p['p_pinned'] as bool) ? '2026-10-12T09:00:00Z' : null}
          };
      final ctl = await entries();
      await ctl.togglePin(st().entries.first);
      expect(st().pinned.map((e) => e.id), ['1']);
      expect(st().entries.map((e) => e.id), ['2']);
      expect(gateway.callsTo('pin_planning_entry').last, {'p_id': '1', 'p_pinned': true});
      await ctl.togglePin(st().pinned.first);
      expect(st().pinned, isEmpty);
      expect(st().entries.map((e) => e.id).toSet(), {'1', '2'});
    });

    test('a refused pin (limit) puts the plan back where it was', () async {
      gateway.handlers['list_planning_entries'] = (_) => {'entries': [s('1')], 'pinned': [], 'next_cursor': null};
      gateway.handlers['pin_planning_entry'] = (_) => throw const PostgrestException(
          message: 'planning:limit_reached', code: 'P0001', hint: '{"limit":"pinned_per_category"}');
      final ctl = await entries();
      await expectLater(ctl.togglePin(st().entries.first), throwsA(isA<PlanningV2LimitReached>()));
      expect(st().pinned, isEmpty);
      expect(st().entries.map((e) => e.id), ['1']);
    });

    // Review I2: list edits must apply to the CURRENT list, not a snapshot
    // taken before an in-flight page load or another action.
    test('deleting a plan while the next page loads does not bring it back', () async {
      final page2 = Completer<Map<String, dynamic>>();
      var call = 0;
      gateway.handlers['list_planning_entries'] = (_) => ++call == 1
          ? {'entries': [s('1'), s('2')], 'pinned': [], 'next_cursor': {'at': '2026-10-12T09:00:00Z', 'id': '2'}}
          : page2.future;
      gateway.handlers['delete_planning_entry'] = (_) => {'deleted': true};
      final ctl = await entries();
      final loading = ctl.loadMore();
      await ctl.delete(st().entries.first);
      page2.complete({'entries': [s('3')], 'pinned': [], 'next_cursor': null});
      await loading;
      expect(st().entries.map((e) => e.id), ['2', '3']);
    });

    test('pinning while the next page loads does not fetch that page twice', () async {
      final page2 = Completer<Map<String, dynamic>>();
      var call = 0;
      gateway.handlers['list_planning_entries'] = (_) => ++call == 1
          ? {'entries': [s('1'), s('2')], 'pinned': [], 'next_cursor': {'at': '2026-10-12T09:00:00Z', 'id': '2'}}
          : page2.future;
      gateway.handlers['pin_planning_entry'] = (p) => {
            'entry': {...fakeEntryDetailJson(id: p['p_id'] as String)['entry'] as Map, 'pinned_at': '2026-10-12T09:00:00Z'}
          };
      final ctl = await entries();
      final loading = ctl.loadMore();
      await ctl.togglePin(st().entries.first);
      expect(st().loadingMore, isTrue, reason: 'an unrelated action must not clear the in-flight flag');
      await ctl.loadMore(); // e.g. the scroll listener firing again
      expect(gateway.callsTo('list_planning_entries'), hasLength(2));
      page2.complete({'entries': [s('3')], 'pinned': [], 'next_cursor': null});
      await loading;
      expect(st().entries.map((e) => e.id), ['2', '3']);
      expect(st().pinned.map((e) => e.id), ['1']);
    });

    test('a plan unpinned before the next page loads is listed once, not twice', () async {
      var call = 0;
      gateway.handlers['list_planning_entries'] = (_) => ++call == 1
          ? {'entries': [s('1')], 'pinned': [s('old', pinned: true)], 'next_cursor': {'at': '2026-10-12T09:00:00Z', 'id': '1'}}
          : {'entries': [s('old'), s('2')], 'pinned': [], 'next_cursor': null};
      gateway.handlers['pin_planning_entry'] = (p) => {'entry': fakeEntryDetailJson(id: p['p_id'] as String)['entry']};
      final ctl = await entries();
      await ctl.togglePin(st().pinned.single);
      await ctl.loadMore();
      expect(st().entries.where((e) => e.id == 'old'), hasLength(1));
      expect(st().entries.map((e) => e.id).toSet(), {'1', 'old', '2'});
    });

    test('a refused pin puts back only that plan, not a delete made meanwhile', () async {
      final pinReply = Completer<Map<String, dynamic>>();
      gateway.handlers['list_planning_entries'] = (_) => {'entries': [s('A'), s('B')], 'pinned': [], 'next_cursor': null};
      gateway.handlers['pin_planning_entry'] = (_) => pinReply.future;
      gateway.handlers['delete_planning_entry'] = (_) => {'deleted': true};
      final ctl = await entries();
      final pinning = ctl.togglePin(st().entries.first);
      await ctl.delete(st().entries.firstWhere((e) => e.id == 'B'));
      pinReply.completeError(const PostgrestException(
          message: 'planning:limit_reached', code: 'P0001', hint: '{"limit":"pinned_per_category"}'));
      await expectLater(pinning, throwsA(isA<PlanningV2LimitReached>()));
      expect(st().entries.map((e) => e.id), ['A'], reason: 'B was really deleted');
      expect(st().pinned, isEmpty);
    });

    test('delete removes the plan at once; undo restores it', () async {
      var deleted = false;
      gateway.handlers['list_planning_entries'] =
          (_) => {'entries': [if (!deleted) s('1'), s('2')], 'pinned': [], 'next_cursor': null};
      gateway.handlers['delete_planning_entry'] = (_) {
        deleted = true;
        return {'deleted': true};
      };
      gateway.handlers['restore_planning_entry'] = (_) {
        deleted = false;
        return {'entry': fakeEntryDetailJson(id: '1')['entry']};
      };
      final ctl = await entries();
      await ctl.delete(st().entries.first);
      expect(st().entries.map((e) => e.id), ['2']);
      await ctl.restore('1');
      await c.read(planningV2EntriesProvider(a).future);
      expect(st().entries.map((e) => e.id), ['1', '2']);
    });
  });
}

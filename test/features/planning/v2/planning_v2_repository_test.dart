import 'package:attune/features/planning/v2/data/planning_v2_error.dart';
import 'package:attune/features/planning/v2/data/planning_v2_models.dart';
import 'package:attune/features/planning/v2/data/planning_v2_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/fake_planning_gateway.dart';

PostgrestException _planning(String code, [String hint = '{}']) =>
    PostgrestException(message: 'planning:$code', code: 'P0001', hint: hint);

void main() {
  late FakePlanningGateway gateway;
  late PlanningV2Repository repo;

  setUp(() {
    gateway = FakePlanningGateway();
    repo = PlanningV2Repository(gateway);
  });

  group('error mapping', () {
    Future<PlanningV2Error> errorFor(Object thrown) async {
      gateway.handlers['get_planning_entry'] = (_) => throw thrown;
      try {
        await repo.getEntry('e1');
      } on PlanningV2Error catch (e) {
        return e;
      }
      fail('expected a PlanningV2Error');
    }

    test('not_found', () async {
      expect(await errorFor(_planning('not_found')), isA<PlanningV2NotFound>());
    });
    test('inactive is unauthorized(inactive: true)', () async {
      final e = await errorFor(_planning('inactive'));
      expect(e, isA<PlanningV2Unauthorized>());
      expect((e as PlanningV2Unauthorized).inactive, isTrue);
    });
    test('unauthenticated is unauthorized(inactive: false)', () async {
      final e = await errorFor(_planning('unauthenticated'));
      expect((e as PlanningV2Unauthorized).inactive, isFalse);
    });
    test('stale_version carries the current row from HINT', () async {
      final e = await errorFor(_planning('stale_version',
          '{"current":{"id":"b1","version":3}}'));
      expect((e as PlanningV2StaleVersion).current['version'], 3);
    });
    test('limit_reached names the limit', () async {
      final e = await errorFor(_planning('limit_reached', '{"limit":"items_per_block"}'));
      expect((e as PlanningV2LimitReached).limit, 'items_per_block');
    });
    test('invalid_input names the field', () async {
      final e = await errorFor(_planning('invalid_input', '{"field":"title"}'));
      expect((e as PlanningV2InvalidInput).field, 'title');
    });
    test('malformed HINT does not crash mapping', () async {
      final e = await errorFor(_planning('limit_reached', 'not json'));
      expect((e as PlanningV2LimitReached).limit, 'unknown');
    });
    test('42501 is unauthorized', () async {
      final e = await errorFor(const PostgrestException(message: 'denied', code: '42501'));
      expect(e, isA<PlanningV2Unauthorized>());
    });
    test('integrity violations are permanent invalid input, not network', () async {
      final e = await errorFor(const PostgrestException(message: 'check', code: '23514'));
      expect(e, isA<PlanningV2InvalidInput>());
      expect(e.isPermanent, isTrue);
    });
    test('anything else is network and retryable', () async {
      final e = await errorFor(Exception('socket closed'));
      expect(e, isA<PlanningV2Network>());
      expect(e.isPermanent, isFalse);
    });
    test('every error has a non-empty, internals-free message', () {
      const all = <PlanningV2Error>[
        PlanningV2Unauthorized(inactive: true), PlanningV2Unauthorized(inactive: false),
        PlanningV2NotFound(), PlanningV2StaleVersion({}),
        PlanningV2LimitReached('blocks_per_entry'), PlanningV2LimitReached('pinned_per_category'),
        PlanningV2LimitReached('zzz'),
        PlanningV2InvalidInput('title'), PlanningV2InvalidInput('zzz'), PlanningV2Network('x'),
      ];
      for (final e in all) {
        final m = planningV2ErrorMessage(e);
        expect(m, isNotEmpty);
        expect(m, isNot(contains('planning:')));
        expect(m, isNot(contains('_')));
      }
    });
  });

  group('RPC names and parameters', () {
    test('getHome', () async {
      gateway.handlers['get_planning_home'] = (_) => {
            'categories': [fakeCategoryJson(id: 'c1', seedKey: 'groceries', hasNew: true)]
          };
      final cats = await repo.getHome('r1');
      expect(gateway.calls.single.$2, {'p_relationship_id': 'r1'});
      expect(cats.single.hasNew, isTrue);
      expect(cats.single.isStarter, isTrue);
    });

    test('listEntries passes group, cursor and limit', () async {
      gateway.handlers['list_planning_entries'] = (_) => {
            'entries': [
              {'id': 'e1', 'title': 'A', 'status': 'active',
               'last_activity_at': '2026-10-12T09:00:00Z', 'date_start': '2026-11-01',
               'date_end': null, 'checklist_done': 1, 'checklist_total': 4}
            ],
            'next_cursor': {'at': '2026-10-12T09:00:00Z', 'id': 'e1'},
          };
      final page = await repo.listEntries('c1',
          group: 'closed', cursorAt: DateTime.utc(2026, 10, 13), cursorId: 'e9', limit: 30);
      expect(gateway.calls.single.$2, {
        'p_category_id': 'c1', 'p_group': 'closed',
        'p_cursor_at': '2026-10-13T00:00:00.000Z', 'p_cursor_id': 'e9', 'p_limit': 30,
      });
      expect(page.hasMore, isTrue);
      expect(page.entries.single.checklistTotal, 4);
      expect(page.entries.single.dateStart, DateTime(2026, 11, 1));
    });

    test('createEntry', () async {
      gateway.handlers['create_planning_entry'] = (_) => fakeEntryDetailJson();
      await repo.createEntry(id: 'e1', categoryId: 'c1', title: 'Run', useTemplate: true, currency: 'GHS');
      expect(gateway.calls.single.$2, {
        'p_id': 'e1', 'p_category_id': 'c1', 'p_title': 'Run',
        'p_use_template': true, 'p_currency': 'GHS',
      });
    });

    test('addBlock sends wire type and ymd dates', () async {
      gateway.handlers['add_planning_block'] = (_) => fakeBlockJson(id: 'b1', type: 'date', dateStart: '2026-11-01');
      await repo.addBlock(id: 'b1', entryId: 'e1', type: PlanningBlockType.date,
          payload: const {}, dateStart: DateTime(2026, 11, 1), afterId: 'b0');
      expect(gateway.calls.single.$2, {
        'p_id': 'b1', 'p_entry_id': 'e1', 'p_block_type': 'date', 'p_payload': <String, dynamic>{},
        'p_date_start': '2026-11-01', 'p_date_end': null, 'p_after_id': 'b0',
      });
    });

    test('updateBlock sends version', () async {
      gateway.handlers['update_planning_block'] = (_) => fakeBlockJson(id: 'b1', version: 4);
      final b = await repo.updateBlock(id: 'b1', version: 3, payload: const {'title': 'x'});
      expect(gateway.calls.single.$2['p_version'], 3);
      expect(b.version, 4);
    });

    test('setItemChecked sends op id', () async {
      gateway.handlers['set_planning_block_item_checked'] = (_) => fakeItemJson(id: 'i1', checkedAt: '2026-10-12T09:00:00Z');
      final item = await repo.setItemChecked(id: 'i1', checked: true, opId: 'op1');
      expect(gateway.calls.single.$2, {'p_id': 'i1', 'p_checked': true, 'p_op_id': 'op1'});
      expect(item.isChecked, isTrue);
    });

    test('every v2 RPC name is distinct from v1 names', () {
      const v1 = {
        'create_planning_task', 'create_planning_goal', 'add_planning_goal_task',
        'update_planning_item', 'set_planning_task_completion', 'delete_planning_item',
        'upsert_planning_event', 'delete_planning_event', 'upsert_planning_note',
        'delete_planning_note', 'link_planning_event_task', 'unlink_planning_event_task',
      };
      expect(PlanningV2Repository.rpcNames.intersection(v1), isEmpty);
    });
  });

  test('pinEntry and restoreEntry call their RPCs with the exact params', () async {
    gateway.handlers['pin_planning_entry'] = (_) => {'entry': fakeEntryDetailJson(pinnedAt: '2026-10-12T09:00:00Z')['entry']};
    gateway.handlers['restore_planning_entry'] = (_) => {'entry': fakeEntryDetailJson()['entry']};
    final pinned = await repo.pinEntry('e1', pinned: true);
    await repo.restoreEntry('e1');
    expect(gateway.calls.map((c) => c.$1), ['pin_planning_entry', 'restore_planning_entry']);
    expect(gateway.calls.first.$2, {'p_id': 'e1', 'p_pinned': true});
    expect(gateway.calls.last.$2, {'p_id': 'e1'});
    expect(pinned.isPinned, isTrue);
  });

  test('the pin limit has its own message, not "make it shorter" (review m2)', () {
    expect(planningV2ErrorMessage(const PlanningV2LimitReached('pinned_per_category')),
        'You can pin up to 20 plans here. Unpin one to pin this.');
  });
}

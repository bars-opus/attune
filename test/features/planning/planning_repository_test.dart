import 'package:attune/features/planning/data/planning_error.dart';
import 'package:attune/features/planning/data/planning_models.dart';
import 'package:attune/features/planning/data/planning_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/fake_planning_gateway.dart';

PostgrestException _planning(String code, [String hint = '{}']) =>
    PostgrestException(message: 'planning:$code', code: 'P0001', hint: hint);

void main() {
  late FakePlanningGateway gateway;
  late PlanningRepository repo;

  setUp(() {
    gateway = FakePlanningGateway();
    repo = PlanningRepository(gateway);
  });

  group('error mapping', () {
    Future<PlanningError> errorFor(Object thrown) async {
      gateway.handlers['get_planning_entry'] = (_) => throw thrown;
      try {
        await repo.getEntry('e1');
      } on PlanningError catch (e) {
        return e;
      }
      fail('expected a PlanningError');
    }

    test('not_found', () async {
      expect(await errorFor(_planning('not_found')), isA<PlanningNotFound>());
    });
    test('inactive is unauthorized(inactive: true)', () async {
      final e = await errorFor(_planning('inactive'));
      expect(e, isA<PlanningUnauthorized>());
      expect((e as PlanningUnauthorized).inactive, isTrue);
    });
    test('unauthenticated is unauthorized(inactive: false)', () async {
      final e = await errorFor(_planning('unauthenticated'));
      expect((e as PlanningUnauthorized).inactive, isFalse);
    });
    test('stale_version carries the current row from HINT', () async {
      final e = await errorFor(_planning('stale_version',
          '{"current":{"id":"b1","version":3}}'));
      expect((e as PlanningStaleVersion).current['version'], 3);
    });
    test('limit_reached names the limit', () async {
      final e = await errorFor(_planning('limit_reached', '{"limit":"items_per_block"}'));
      expect((e as PlanningLimitReached).limit, 'items_per_block');
    });
    test('invalid_input names the field', () async {
      final e = await errorFor(_planning('invalid_input', '{"field":"title"}'));
      expect((e as PlanningInvalidInput).field, 'title');
    });
    test('malformed HINT does not crash mapping', () async {
      final e = await errorFor(_planning('limit_reached', 'not json'));
      expect((e as PlanningLimitReached).limit, 'unknown');
    });
    test('42501 is unauthorized', () async {
      final e = await errorFor(const PostgrestException(message: 'denied', code: '42501'));
      expect(e, isA<PlanningUnauthorized>());
    });
    test('integrity violations are permanent invalid input, not network', () async {
      final e = await errorFor(const PostgrestException(message: 'check', code: '23514'));
      expect(e, isA<PlanningInvalidInput>());
      expect(e.isPermanent, isTrue);
    });
    test('anything else is network and retryable', () async {
      final e = await errorFor(Exception('socket closed'));
      expect(e, isA<PlanningNetwork>());
      expect(e.isPermanent, isFalse);
    });
    test('every error has a non-empty, internals-free message', () {
      const all = <PlanningError>[
        PlanningUnauthorized(inactive: true), PlanningUnauthorized(inactive: false),
        PlanningNotFound(), PlanningStaleVersion({}),
        PlanningLimitReached('blocks_per_entry'), PlanningLimitReached('pinned_per_category'),
        PlanningLimitReached('zzz'),
        PlanningInvalidInput('title'), PlanningInvalidInput('zzz'), PlanningNetwork('x'),
      ];
      for (final e in all) {
        final m = planningErrorMessage(e);
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
    expect(planningErrorMessage(const PlanningLimitReached('pinned_per_category')),
        'You can pin up to 20 plans here. Unpin one to pin this.');
  });

  group('feeds (calendar, summary)', () {
    test('listCalendarEntries sends the range as dates and parses rows', () async {
      gateway.handlers['list_planning_calendar_entries'] = (_) => [
            {'entry_kind': 'date', 'entry_id': 'e1', 'item_id': null, 'entry_date': '2026-11-28',
             'title': 'Bali', 'is_complete': false},
            {'entry_kind': 'item', 'entry_id': 'e2', 'item_id': 'i1', 'entry_date': '2026-11-05',
             'title': 'Milk', 'is_complete': true},
          ];
      final rows = await repo.listCalendarEntries('r1', start: DateTime(2026, 11, 1), end: DateTime(2026, 11, 30));
      expect(gateway.calls.single.$2,
          {'p_relationship_id': 'r1', 'p_start_date': '2026-11-01', 'p_end_date': '2026-11-30'});
      expect(rows.first.kind, PlanningCalendarKind.date);
      expect(rows.last.itemId, 'i1');
      expect(rows.last.isComplete, isTrue);
      expect(rows.last.date, DateTime(2026, 11, 5));
    });

    test('getSummary is null when nothing is planned, and parses a row otherwise', () async {
      gateway.handlers['get_planning_summary'] = (_) => [];
      expect(await repo.getSummary('r1', today: DateTime(2026, 11, 10)), isNull);
      expect(gateway.calls.single.$2, {'p_relationship_id': 'r1', 'p_today': '2026-11-10'});
      gateway.handlers['get_planning_summary'] =
          (_) => [{'kind': 'overdue', 'entry_id': 'e2', 'title': 'Eggs', 'context_date': '2026-11-08'}];
      final s = await repo.getSummary('r1', today: DateTime(2026, 11, 10));
      expect(s!.kind, PlanningSummaryKind.overdue);
      expect(s.entryId, 'e2');
      expect(s.contextDate, DateTime(2026, 11, 8));
    });
  });
}

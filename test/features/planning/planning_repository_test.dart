// Repository-level tests exercise error MAPPING, not live RPC behavior
// (Plan A's own SQL contract tests already prove the RPCs correct).
// A fake SupabaseClient stand-in is not practical for `.rpc()` calls
// against the real generic PostgREST builder (the same reasoning
// story_repository_test.dart gives for faking its own gateway
// interface instead) — so this repository takes an injected gateway
// interface, and these tests fake THAT, not SupabaseClient itself.
import 'package:attune/features/planning/data/repositories/planning_error.dart';
import 'package:attune/features/planning/data/repositories/planning_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _FakeRpcGateway implements PlanningRpcGateway {
  Object? nextError;
  dynamic nextResult;
  String? lastCalledFunction;
  Map<String, dynamic>? lastCalledParams;

  @override
  Future<dynamic> rpc(String function, {Map<String, dynamic>? params}) async {
    lastCalledFunction = function;
    lastCalledParams = params;
    if (nextError != null) throw nextError!;
    return nextResult;
  }
}

void main() {
  late _FakeRpcGateway gateway;
  late PlanningRepository repository;

  setUp(() {
    gateway = _FakeRpcGateway();
    repository = PlanningRepository(gateway);
  });

  test('createTask calls create_planning_task with the exact param names', () async {
    gateway.nextResult = {
      'id': 't1', 'relationship_id': 'r1', 'created_by': 'u1',
      'item_kind': 'task', 'parent_goal_id': null, 'title': 'Book the venue',
      'note': null, 'assigned_to': null, 'due_date': null,
      'completed_at': null, 'celebrated_at': null,
      'created_at': '2026-09-14T09:00:00Z', 'updated_at': '2026-09-14T09:00:00Z',
      'deleted_at': null,
    };
    await repository.createTask(
      id: 't1', relationshipId: 'r1', title: 'Book the venue',
    );
    expect(gateway.lastCalledFunction, 'create_planning_task');
    expect(gateway.lastCalledParams, containsPair('p_id', 't1'));
    expect(gateway.lastCalledParams, containsPair('p_relationship_id', 'r1'));
    expect(gateway.lastCalledParams, containsPair('p_title', 'Book the venue'));
  });

  test('a PostgrestException with code 42501 maps to PlanningError.unauthorized', () async {
    gateway.nextError = PostgrestException(message: 'permission denied', code: '42501');
    await expectLater(
      repository.createTask(id: 't1', relationshipId: 'r1', title: 'x'),
      throwsA(isA<PlanningError>().having(
        (e) => e, 'error', isA<PlanningUnauthorizedError>(),
      )),
    );
  });

  test('"Planning unavailable" and "Not authenticated" P0001 messages also map to unauthorized, not validation', () async {
    for (final message in ['Planning unavailable', 'Not authenticated']) {
      gateway.nextError = PostgrestException(message: message, code: 'P0001');
      await expectLater(
        repository.deleteItem(id: 't1'),
        throwsA(isA<PlanningError>().having(
          (e) => e, 'error', isA<PlanningUnauthorizedError>(),
        )),
        reason: 'message "$message" must map to unauthorized',
      );
    }
  });

  test('the sole-child-delete rejection maps to PlanningError.validation, not a generic error', () async {
    gateway.nextError = PostgrestException(
      message: 'Delete the goal instead, or add another task first',
      code: 'P0001',
    );
    await expectLater(
      repository.deleteItem(id: 't1'),
      throwsA(isA<PlanningError>().having(
        (e) => e, 'error', isA<PlanningValidationError>().having(
          (e) => e.message, 'message', contains('Delete the goal instead'),
        ),
      )),
    );
  });

  test('a network-shaped failure maps to PlanningError.network, not unauthorized', () async {
    gateway.nextError = const SocketExceptionStub();
    await expectLater(
      repository.createTask(id: 't1', relationshipId: 'r1', title: 'x'),
      throwsA(isA<PlanningError>().having(
        (e) => e, 'error', isA<PlanningNetworkError>(),
      )),
    );
  });

  test('listTasks passes all four of the RPC cursor parameters by exact name', () async {
    gateway.nextResult = <dynamic>[];
    final afterDueDate = DateTime.utc(2026, 12, 1);
    final afterUpdatedAt = DateTime.utc(2026, 9, 14, 9);
    await repository.listTasks(
      relationshipId: 'r1',
      afterDueDate: afterDueDate,
      afterUpdatedAt: afterUpdatedAt,
      afterId: 't1',
    );
    expect(gateway.lastCalledFunction, 'list_planning_tasks');
    // The RPC's cursor is a 4-branch OR-chain keyed on
    // (completed_at IS NOT NULL, due_date, updated_at, id) — a caller
    // that only forwards updated_at/id (the naive last-row values for
    // a single-key sort) silently breaks pagination the moment two
    // rows tie on updated_at across a due_date/completion boundary.
    // This asserts every one of the four names the RPC signature
    // declares is actually sent, not just the two that happen to work
    // by accident on an untied fixture.
    expect(gateway.lastCalledParams, containsPair('p_relationship_id', 'r1'));
    expect(gateway.lastCalledParams, containsPair('p_after_due_date', '2026-12-01'));
    expect(
      gateway.lastCalledParams,
      containsPair('p_after_updated_at', afterUpdatedAt.toIso8601String()),
    );
    expect(gateway.lastCalledParams, containsPair('p_after_id', 't1'));
  });

  test('deleteItem calls delete_planning_item with p_id and returns the bool result', () async {
    gateway.nextResult = true;
    final result = await repository.deleteItem(id: 't1');
    expect(result, isTrue);
    expect(gateway.lastCalledFunction, 'delete_planning_item');
    expect(gateway.lastCalledParams, {'p_id': 't1'});
  });

  test('getSummary returns null on an empty result set rather than throwing', () async {
    gateway.nextResult = <dynamic>[];
    final summary = await repository.getSummary(
      relationshipId: 'r1',
      today: DateTime.utc(2026, 9, 14),
    );
    expect(summary, isNull);
  });

  test('getSummary parses the single row the RPC returns', () async {
    gateway.nextResult = [
      {'kind': 'overdue_task', 'id': 't1', 'title': 'Book the venue', 'context_date': '2026-09-01'},
    ];
    final summary = await repository.getSummary(
      relationshipId: 'r1',
      today: DateTime.utc(2026, 9, 14),
    );
    expect(summary, isNotNull);
    expect(summary!.kind, 'overdue_task');
    expect(summary.contextDate, DateTime.utc(2026, 9, 1));
  });
}

class SocketExceptionStub implements Exception {
  const SocketExceptionStub();
}

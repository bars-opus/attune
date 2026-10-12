import 'dart:math';

import 'package:attune/features/planning/v2/data/planning_v2_error.dart';
import 'package:attune/features/planning/v2/domain/planning_outbox.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

CheckItemOp _tick(String id, {bool checked = true}) => CheckItemOp(
    opId: 'op-$id', relationshipId: 'r1', entryId: 'e1', itemId: id, checked: checked);

void main() {
  late MemoryOutboxStore store;
  late List<OutboxOp> sent;
  late List<Duration> sleeps;
  late Object? Function(OutboxOp op) behaviour;

  PlanningOutbox make() => PlanningOutbox(
        store: store,
        send: (op) async {
          sent.add(op);
          final r = behaviour(op);
          if (r != null) throw r;
        },
        random: Random(7),
        sleep: (d) async => sleeps.add(d),
      );

  setUp(() {
    store = MemoryOutboxStore();
    sent = [];
    sleeps = [];
    behaviour = (_) => null;
  });

  test('ops persist across outbox instances (survives restart)', () async {
    await make().enqueue(_tick('i1'));
    final again = make();
    expect((await again.pending()).single.opId, 'op-i1');
    expect(again.pendingCount.value, 1);
  });

  test('enqueue is idempotent by op id', () async {
    final o = make();
    await o.enqueue(_tick('i1'));
    await o.enqueue(_tick('i1'));
    expect(await o.pending(), hasLength(1));
  });

  test('capacity is 200', () async {
    final o = make();
    for (var i = 0; i < 200; i++) {
      await o.enqueue(_tick('i$i'));
    }
    expect(() => o.enqueue(_tick('overflow')), throwsA(isA<OutboxFullException>()));
  });

  test('replay sends in order and empties the queue', () async {
    final o = make();
    await o.enqueue(_tick('i1'));
    await o.enqueue(AddItemOp(opId: 'i2', relationshipId: 'r1', entryId: 'e1', itemId: 'i2',
        blockId: 'b1', text: 'Milk', section: null, afterId: 'i1'));
    final r = await o.replay();
    expect(sent.map((s) => s.opId), ['op-i1', 'i2']);
    expect(r.sent, 2);
    expect(await o.pending(), isEmpty);
    expect(o.pendingCount.value, 0);
  });

  test('permanent errors drop the op and continue (checklist 3.10)', () async {
    behaviour = (op) => op.opId == 'op-i1' ? const PlanningV2NotFound() : null;
    final o = make();
    await o.enqueue(_tick('i1'));
    await o.enqueue(_tick('i2'));
    final r = await o.replay();
    expect(r.dropped.single.opId, 'op-i1');
    expect(r.sent, 1);
    expect(sleeps, isEmpty, reason: 'permanent errors are never retried');
  });

  test('network errors back off with jitter within bounds, then stop and keep the rest', () async {
    behaviour = (_) => const PlanningV2Network('offline');
    final o = make();
    await o.enqueue(_tick('i1'));
    await o.enqueue(_tick('i2'));
    final r = await o.replay();
    expect(sent.where((s) => s.opId == 'op-i1'), hasLength(6), reason: '6 attempts');
    expect(sent.where((s) => s.opId == 'op-i2'), isEmpty, reason: 'later ops wait behind a failing one');
    expect(sleeps, hasLength(5));
    for (var i = 0; i < sleeps.length; i++) {
      final cap = Duration(milliseconds: min(30000, 500 * (1 << i)));
      expect(sleeps[i] <= cap, isTrue, reason: 'attempt $i slept ${sleeps[i]} > $cap');
    }
    expect(r.remaining, 2);
  });

  test('replay is idempotent: every retry of an op reuses its op id (Review Focus 3)', () async {
    var calls = 0;
    behaviour = (_) => ++calls < 3 ? const PlanningV2Network('flaky') : null;
    final o = make();
    await o.enqueue(_tick('i1'));
    await o.replay();
    expect(sent.map((s) => s.opId).toSet(), {'op-i1'});
    expect(sent, hasLength(3));
  });

  test('concurrent replay calls share one run', () async {
    final o = make();
    await o.enqueue(_tick('i1'));
    await Future.wait([o.replay(), o.replay()]);
    expect(sent, hasLength(1));
  });

  test('a corrupt stored queue is discarded, not fatal', () async {
    store.raw = [{'kind': 'nonsense'}];
    expect(await make().pending(), isEmpty);
  });

  group('SharedPreferencesOutboxStore (the store real phones use)', () {
    test('round-trips queued ops across store instances', () async {
      SharedPreferences.setMockInitialValues({});
      final op = _tick('i1');
      await SharedPreferencesOutboxStore().write([op.toJson()]);
      final read = await SharedPreferencesOutboxStore().read();
      expect(OutboxOp.fromJson(read.single)!.opId, 'op-i1');
    });

    test('empty storage reads as an empty queue', () async {
      SharedPreferences.setMockInitialValues({});
      expect(await SharedPreferencesOutboxStore().read(), isEmpty);
    });

    test('corrupt stored JSON reads as empty instead of throwing', () async {
      SharedPreferences.setMockInitialValues({'planning_v2_outbox_v1': '{not json'});
      expect(await SharedPreferencesOutboxStore().read(), isEmpty);
    });
  });

  test('an op with a wrongly typed field is discarded, not fatal', () {
    expect(OutboxOp.fromJson({'kind': 'check', 'op_id': 7, 'relationship_id': 'r', 'entry_id': 'e',
        'item_id': 'i', 'checked': true}), isNull);
  });
}

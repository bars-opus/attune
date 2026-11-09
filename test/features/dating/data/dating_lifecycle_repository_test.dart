import 'package:attune/features/dating/data/dating_lifecycle_repository.dart';
import 'package:attune/features/dating/data/dating_rpc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../support/dating_fakes.dart';

void main() {
  test('exit v2 sends the key and the keep choice (carry 12)', () async {
    final s = ScriptedRpc([
      (_, __) => {'state': 'exited'},
    ]);
    final r = await DatingLifecycleRepository(
      s.rpc,
    ).exit('k-exit-0001', keepNeverIntroduce: true);
    expect(r.ok, isTrue);
    expect(r.state, 'exited');
    // A record holding a Map compares the Map by identity: check each part.
    expect(s.calls.single.$1, 'exit_dating_mode');
    expect(s.calls.single.$2, {
      'p_idempotency_key': 'k-exit-0001',
      'p_keep_never_introduce': true,
    });
  });

  test('exit can answer suspended (W1 B10 M-8, carry 13)', () async {
    final s = ScriptedRpc([
      (_, __) => {'state': 'suspended'},
    ]);
    final r = await DatingLifecycleRepository(
      s.rpc,
    ).exit('k-exit-0002', keepNeverIntroduce: false);
    expect(r.state, 'suspended');
  });

  test('a raised refusal is its named error (carry 1)', () async {
    final s = ScriptedRpc([
      (_, __) => PostgrestException(message: 'path_not_dating', code: '22023'),
    ]);
    final r = await DatingLifecycleRepository(s.rpc).resume('k-res-0001');
    expect(r.ok, isFalse);
    expect(r.error, DatingLifecycleError.pathNotDating);
  });

  test('pause, resume and activate call their RPC with the key', () async {
    final s = ScriptedRpc([
      (_, __) => {'state': 'paused'},
      (_, __) => {'state': 'active'},
      (_, __) => {'state': 'active'},
    ]);
    final repo = DatingLifecycleRepository(s.rpc);
    await repo.pause('k-p-000001');
    await repo.resume('k-r-000001');
    await repo.activate('k-a-000001');
    expect(s.calls.map((c) => c.$1), [
      'pause_dating_mode',
      'resume_dating_mode',
      'activate_dating_profile',
    ]);
    expect(s.calls.first.$2, {'p_idempotency_key': 'k-p-000001'});
    expect(s.calls[1].$2, {'p_idempotency_key': 'k-r-000001'});
    expect(s.calls[2].$2, {'p_idempotency_key': 'k-a-000001'});
  });

  test(
    'M-8: an exit with no enrolment row is ok with no state (R-41)',
    () async {
      final s = ScriptedRpc([(_, __) => null]);
      final r = await DatingLifecycleRepository(
        s.rpc,
      ).exit('k-exit-0003', keepNeverIntroduce: false);
      expect(r.ok, isTrue);
      expect(r.state, isNull);
    },
  );
}

// Spec 2 W3a (§3.8, §4.4 Lifecycle; carries 1, 12, 13): pause, resume,
// activate and leave (exit v2: one hard delete; the never-introduce list
// kept only if ticked, R-2). Each returns the enrolment's new state or the
// named refusal; exit may answer `suspended` (W1 B10 M-8).
import 'package:attune/features/dating/data/dating_rpc.dart';

class DatingLifecycleResult {
  const DatingLifecycleResult.done(this.state) : error = null;

  const DatingLifecycleResult.refused(DatingLifecycleError this.error)
    : state = null;

  final String? state;
  final DatingLifecycleError? error;

  bool get ok => error == null;
}

abstract class DatingLifecycleGateway {
  Future<DatingLifecycleResult> pause(String key);

  Future<DatingLifecycleResult> resume(String key);

  Future<DatingLifecycleResult> activate(String key);

  Future<DatingLifecycleResult> exit(
    String key, {
    required bool keepNeverIntroduce,
  });
}

class DatingLifecycleRepository implements DatingLifecycleGateway {
  DatingLifecycleRepository(this._rpc);

  final DatingRpc _rpc;

  Future<DatingLifecycleResult> _run(
    String fn,
    Map<String, dynamic> params,
  ) async {
    try {
      final row = await _rpc.call(fn, params);
      final state =
          row is Map && row['state'] is String ? row['state'] as String : null;
      return DatingLifecycleResult.done(state);
    } catch (e) {
      return DatingLifecycleResult.refused(DatingLifecycleError.of(e));
    }
  }

  @override
  Future<DatingLifecycleResult> pause(String key) =>
      _run('pause_dating_mode', {'p_idempotency_key': key});

  @override
  Future<DatingLifecycleResult> resume(String key) =>
      _run('resume_dating_mode', {'p_idempotency_key': key});

  @override
  Future<DatingLifecycleResult> activate(String key) =>
      _run('activate_dating_profile', {'p_idempotency_key': key});

  @override
  Future<DatingLifecycleResult> exit(
    String key, {
    required bool keepNeverIntroduce,
  }) => _run('exit_dating_mode', {
    'p_idempotency_key': key,
    'p_keep_never_introduce': keepNeverIntroduce,
  });
}

// Spec 2 W3: in-memory Dating gateways for widget and provider tests.
import 'dart:async';

import 'package:attune/features/dating/data/dating_home.dart';
import 'package:attune/features/dating/data/dating_home_repository.dart';
import 'package:attune/features/dating/data/dating_lifecycle_repository.dart';
import 'package:attune/features/dating/data/dating_rpc.dart';

class FakeDatingHomeGateway implements DatingHomeGateway {
  FakeDatingHomeGateway({
    this.home = const DatingHome(state: DatingHomeState.notStarted),
  });

  DatingHome home;
  Object? readError;
  Completer<DatingHome>? hold;
  int reads = 0;
  DatingAvailability available = const DatingAvailability(
    countries: [
      DatingOpenCountry(code: 'GB'),
      DatingOpenCountry(
        code: 'GH',
        openRegionKeys: ['dating_region_gh_aa', 'dating_region_gh_ah'],
      ),
    ],
  );
  final requests = <(String, String?)>[];
  int cancels = 0;
  DatingNoticeResult noticeResult = DatingNoticeResult.saved;

  /// While set and not completed, requestNotice and cancelNotice wait for
  /// it (T4 fix 1).
  Completer<void>? noticeHold;

  /// Every call, in order: read, availability, request, cancel (T4 fix 1).
  final log = <String>[];

  @override
  Future<DatingHome> read() async {
    reads++;
    log.add('read');
    final held = hold;
    if (held != null) return held.future;
    final error = readError;
    if (error != null) throw error;
    return home;
  }

  @override
  Future<DatingAvailability> availability() async {
    log.add('availability');
    return available;
  }

  @override
  Future<DatingNoticeResult> requestNotice(
    String country, {
    String? region,
  }) async {
    requests.add((country, region));
    log.add('request');
    final held = noticeHold;
    if (held != null) await held.future;
    return noticeResult;
  }

  @override
  Future<DatingNoticeResult> cancelNotice() async {
    cancels++;
    log.add('cancel');
    final held = noticeHold;
    if (held != null) await held.future;
    return noticeResult;
  }
}

class FakeDatingLifecycleGateway implements DatingLifecycleGateway {
  final calls = <String>[];
  final keys = <String>[];
  DatingLifecycleResult result = const DatingLifecycleResult.done('active');
  bool? keptList;

  Future<DatingLifecycleResult> _record(String name, String key) async {
    calls.add(name);
    keys.add(key);
    return result;
  }

  @override
  Future<DatingLifecycleResult> pause(String key) => _record('pause', key);

  @override
  Future<DatingLifecycleResult> resume(String key) => _record('resume', key);

  @override
  Future<DatingLifecycleResult> activate(String key) =>
      _record('activate', key);

  @override
  Future<DatingLifecycleResult> exit(
    String key, {
    required bool keepNeverIntroduce,
  }) {
    keptList = keepNeverIntroduce;
    return _record('exit', key);
  }
}

/// A [DatingRpc] over a scripted list of answers; records every call.
class ScriptedRpc {
  ScriptedRpc(this.answers);

  final List<Object? Function(String fn, Map<String, dynamic>? params)> answers;
  final calls = <(String, Map<String, dynamic>?)>[];

  DatingRpc get rpc => DatingRpc.withCall((fn, params) async {
    calls.add((fn, params));
    final answer = answers.removeAt(0)(fn, params);
    if (answer is Exception) throw answer;
    if (answer is Error) throw answer;
    return answer;
  });
}

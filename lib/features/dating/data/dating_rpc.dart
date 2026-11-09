// Spec 2 W3a (§4.4, §4.10 RPC-only repository, Fable H3c): one way to call a
// Dating RPC. Every Dating read and write goes through here: no table is
// ever read directly (R11); a busy server is retried once (S2 W1 carried
// item 11); every call is bounded.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

typedef DatingRpcCall =
    Future<dynamic> Function(String fn, Map<String, dynamic>? params);

/// The server was still busy after its own three tries and the app's one.
class DatingBusy implements Exception {
  const DatingBusy();

  @override
  String toString() => 'DatingBusy';
}

class DatingRpc {
  DatingRpc(SupabaseClient client)
    : _call = ((fn, params) => client.rpc(fn, params: params));

  @visibleForTesting
  DatingRpc.withCall(DatingRpcCall call) : _call = call;

  final DatingRpcCall _call;

  static const timeout = Duration(seconds: 30);

  Future<dynamic> call(String fn, [Map<String, dynamic>? params]) async {
    for (var attempt = 1; ; attempt++) {
      try {
        return await _call(fn, params).timeout(timeout);
      } on PostgrestException catch (e) {
        if (e.message != 'dating:busy') rethrow;
        if (attempt == 1) continue;
        throw const DatingBusy();
      }
    }
  }
}

/// A lifecycle RPC's raised refusal, by its message (never its DETAIL).
enum DatingLifecycleError {
  pathNotDating,
  notPaused,
  activationRequired,
  resumeGatesNotMet,
  activationGatesNotMet,
  enrollmentIncomplete,
  consentRequired,
  profileIncomplete,
  reverifyDevice,
  notEligible,
  rateLimited,
  busy,
  failed;

  static DatingLifecycleError of(Object error) {
    if (error is DatingBusy) return busy;
    if (error is! PostgrestException) return failed;
    return switch (error.message) {
      'path_not_dating' => pathNotDating,
      'not_paused' => notPaused,
      'activation_required' => activationRequired,
      'resume_gates_not_met' => resumeGatesNotMet,
      'activation_gates_not_met' => activationGatesNotMet,
      'enrollment_incomplete' => enrollmentIncomplete,
      'consent_required' ||
      'terms_consent_required' ||
      'dating_opt_in_required' => consentRequired,
      'profile_or_preferences_incomplete' => profileIncomplete,
      'reverify_device' => reverifyDevice,
      'not_eligible' => notEligible,
      'rate_limited' => rateLimited,
      _ => failed,
    };
  }
}

/// A setup writer's answer: `{ok: true, next_step}` or
/// `{ok: false, reason, field?, position?}`. Anything else is `failed`.
class DatingWrite {
  const DatingWrite({
    required this.ok,
    this.nextStep,
    this.reason,
    this.field,
    this.position,
  });

  static const busy = DatingWrite(ok: false, reason: 'busy');
  static const failed = DatingWrite(ok: false, reason: 'failed');

  final bool ok;
  final String? nextStep;
  final String? reason;
  final String? field;
  final int? position;

  factory DatingWrite.fromJson(Object? raw) {
    if (raw is! Map) return failed;
    final ok = raw['ok'] == true;
    String? text(String key) => raw[key] is String ? raw[key] as String : null;
    final position = raw['position'];
    return DatingWrite(
      ok: ok,
      nextStep: text('next_step'),
      reason: ok ? null : (text('reason') ?? 'failed'),
      field: text('field'),
      position: position is int ? position : null,
    );
  }
}

/// Runs [write] and turns a busy server or any failure into its answer.
Future<DatingWrite> datingWrite(Future<dynamic> Function() write) async {
  try {
    return DatingWrite.fromJson(await write());
  } on DatingBusy {
    return DatingWrite.busy;
  } catch (_) {
    return DatingWrite.failed;
  }
}

/// One idempotency key per action while its outcome is open (Fable H3c): a
/// double tap or a retry after busy sends the same key, so the server acts
/// once; a changed answer gets a new key, so it is never mistaken for a
/// replay of the old one; and once an answer is final the caller [settle]s
/// the action, so the next deliberate tap (Pause, Resume, Pause) is a new
/// request, never a replay of the first (server keys never expire).
///
/// Usage: `final r = await gateway.pause(keys.keyFor('pause', account));
/// keys.settle('pause', error: r.error);` (a [DatingWrite]: `reason:
/// w.reason`).
class DatingActionKeys {
  DatingActionKeys({String Function()? newKey})
    : _newKey = newKey ?? (() => const Uuid().v4());

  final String Function() _newKey;
  final _held = <String, (String, String)>{};

  /// The key for [action] with [payload] (anything `jsonEncode` takes; a
  /// payload it can't encode throws rather than colliding with another).
  String keyFor(String action, [Object? payload]) {
    final signature = jsonEncode(payload);
    final held = _held[action];
    if (held != null && held.$1 == signature) return held.$2;
    final key = _newKey();
    _held[action] = (signature, key);
    return key;
  }

  /// Drops [action]'s held key once its answer is final: ok, or a named
  /// refusal. A busy or failed answer (its outcome unknown) keeps the key,
  /// so the retry is the same request. Pass a lifecycle result's `error`,
  /// or a [DatingWrite]'s `reason` (both null when ok).
  void settle(String action, {DatingLifecycleError? error, String? reason}) {
    if (error == DatingLifecycleError.busy ||
        error == DatingLifecycleError.failed ||
        reason == 'busy' ||
        reason == 'failed') {
      return;
    }
    _held.remove(action);
  }
}

// Spec 2 W7b (§6.4): the console's one way to the server: the
// dating-moderation edge function, one action per call. Every answer is a
// fixed code or the function's data; a failure is busy (or offline), never
// its text.
//
// Task 7 (the live HTTP contract, task-6-report.md):
// - No functions region is set: the function's CORS allow-list has no
//   x-region header, so a preflight that sent it would fail.
// - One 401 is retried once, after a session refresh, before it reads as
//   unauthorized: an Auth outage also answers 401 (Task 6 M-10), and
//   nothing ran on the server (the token is checked before any RPC).
// - A timeout is busy (the function cuts its own RPC at 10 s); a request
//   that never reached the function is offline.
import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

class ConsoleAnswer {
  const ConsoleAnswer({required this.ok, this.reason, this.data = const {}});

  static const busy = ConsoleAnswer(ok: false, reason: 'busy');
  static const offline = ConsoleAnswer(ok: false, reason: 'offline');

  final bool ok;
  final String? reason;
  final Map<String, dynamic> data;

  List<Map<String, dynamic>> list(String key) => [
    for (final row in (data[key] is List ? data[key] as List : const []))
      if (row is Map) Map<String, dynamic>.from(row),
  ];

  factory ConsoleAnswer.fromJson(Object? raw) {
    if (raw is! Map) return busy;
    final data = Map<String, dynamic>.from(raw);
    if (data['ok'] != true) {
      final reason = data['reason'];
      // Spec 2 W7c Task 9: a refusal carries nothing but its code, except
      // the log's exists, which names the request already logged.
      return ConsoleAnswer(
        ok: false,
        reason: reason is String ? reason : 'busy',
        data: {
          if (data['id'] case final String id when reason == 'exists') 'id': id,
        },
      );
    }
    return ConsoleAnswer(ok: true, data: data);
  }
}

abstract class ConsoleApi {
  Future<ConsoleAnswer> call(
    String action, [
    Map<String, Object?> params = const {},
  ]);
}

class SupabaseConsoleApi implements ConsoleApi {
  SupabaseConsoleApi(SupabaseClient client)
    : this.using(
        // No region (see the header).
        invoke:
            (body) async =>
                (await client.functions.invoke(
                  'dating-moderation',
                  body: body,
                )).data,
        refresh: () async {
          await client.auth.refreshSession();
        },
      );

  /// The client's steps, given (tests).
  SupabaseConsoleApi.using({
    required Future<Object?> Function(Map<String, Object?> body) invoke,
    required Future<void> Function() refresh,
    this.retryDelay = const Duration(milliseconds: 800),
  }) : _invoke = invoke,
       _refresh = refresh;

  final Future<Object?> Function(Map<String, Object?> body) _invoke;
  final Future<void> Function() _refresh;
  final Duration retryDelay;

  static const timeout = Duration(seconds: 20);

  @override
  Future<ConsoleAnswer> call(
    String action, [
    Map<String, Object?> params = const {},
  ]) async {
    final body = {...params, 'action': action};
    final first = await _once(body);
    if (first.reason != 'unauthorized') return first;
    // One 401 is not a signed-out moderator: refresh and try once more.
    await Future<void>.delayed(retryDelay);
    try {
      await _refresh().timeout(timeout);
    } catch (_) {}
    return _once(body);
  }

  Future<ConsoleAnswer> _once(Map<String, Object?> body) async {
    try {
      return ConsoleAnswer.fromJson(await _invoke(body).timeout(timeout));
    } on FunctionException catch (e) {
      return e.status == 401
          ? const ConsoleAnswer(ok: false, reason: 'unauthorized')
          : ConsoleAnswer.fromJson(e.details);
    } on TimeoutException {
      return ConsoleAnswer.busy;
    } catch (_) {
      return ConsoleAnswer.offline;
    }
  }
}

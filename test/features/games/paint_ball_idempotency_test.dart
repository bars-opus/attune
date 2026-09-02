import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('createSession always sends an idempotency key', () {
    // session_idempotency_keys.key is NOT NULL, and no caller in the app
    // ever passed one -- the parameter existed at every level of the
    // chain (lobby -> provider -> service) and nothing filled it. So
    // starting Paint Ball always failed on the constraint.
    //
    // A generated key still buys the guard it exists for: the RPC returns
    // the existing session on a repeat, so a retry reusing the key cannot
    // create a second game.
    final source =
        File(
          'lib/features/games/paint_ball/services/paint_ball_service.dart',
        ).readAsStringSync();

    final createCall = source.substring(
      source.indexOf("'paint_ball_create_session'"),
      source.indexOf("'paint_ball_accept_session'"),
    );

    expect(
      createCall.contains("'p_idempotency_key': idempotencyKey,"),
      isFalse,
      reason: 'a null key violates the NOT NULL constraint on key',
    );
    expect(
      createCall.contains('idempotencyKey ?? const Uuid().v4()'),
      isTrue,
      reason: 'the service must supply a key when the caller does not',
    );
  });
}

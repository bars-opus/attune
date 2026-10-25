// Spec 1 W2b: scripted Auth and code sending for the sign-up tests.
import 'dart:async';

import 'package:attune/features/auth/sign_up/data/sign_up_gateways.dart';
import 'package:attune/features/auth/sign_up/data/sms_code_listener.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class FakeCodeSender implements CodeSender {
  final sent = <(String phone, String channel, String nonce)>[];

  /// Thrown by the next send, if set (then cleared).
  Object? failNext;

  /// While set and not completed, every send waits for it (a hung network).
  Completer<void>? hold;

  @override
  Future<void> send({
    required String phoneE164,
    required String channel,
    required String deviceNonce,
  }) async {
    final wait = hold;
    if (wait != null) await wait.future;
    final failure = failNext;
    if (failure != null) {
      failNext = null;
      throw failure;
    }
    sent.add((phoneE164, channel, deviceNonce));
  }
}

class FakeSignUpAuth implements SignUpAuth {
  FakeSignUpAuth({
    this.userId,
    this.phone,
    this.goodCode = '123456',
    this.verifiesAs = 'u1',
  });

  String? userId;

  /// The signed-in session's number, E.164.
  String? phone;
  String goodCode;
  String verifiesAs;
  int signOuts = 0;
  int verifyCalls = 0;

  /// While set and not completed, every verify waits for it (a slow check).
  Completer<void>? holdVerify;

  /// Thrown by every verify, if set (after any [holdVerify]).
  Object? failVerifyWith;

  /// Sign-out ends the session, then throws (Auth dropped it locally, a
  /// hook or the network call after it failed).
  bool failSignOut = false;

  @override
  String? get currentUserId => userId;

  @override
  String? get currentPhone => userId == null ? null : phone;

  @override
  Future<String?> verify({
    required String phoneE164,
    required String code,
  }) async {
    verifyCalls++;
    final wait = holdVerify;
    if (wait != null) await wait.future;
    final failure = failVerifyWith;
    if (failure != null) throw failure;
    if (code != goodCode) {
      throw const AuthException(
        'Token has expired or is invalid',
        code: 'otp_expired',
        statusCode: '403',
      );
    }
    userId = verifiesAs;
    return verifiesAs;
  }

  @override
  Future<void> signOut() async {
    signOuts++;
    userId = null;
    if (failSignOut) throw const AuthException('sign-out failed');
  }
}

/// W2c: Android's SMS listener, driven by the test.
class FakeSmsCodeListener implements SmsCodeListener {
  Completer<String?> _next = Completer<String?>();
  int stops = 0;

  /// How many times the flow started listening.
  int listens = 0;

  /// The SMS arrives.
  void arrive(String code) {
    if (!_next.isCompleted) _next.complete(code);
  }

  @override
  Future<String?> next() {
    listens++;
    if (_next.isCompleted) _next = Completer<String?>();
    return _next.future;
  }

  @override
  Future<void> stop() async {
    stops++;
  }
}

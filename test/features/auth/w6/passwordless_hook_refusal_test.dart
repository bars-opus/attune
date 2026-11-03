// Spec 1 W6a (W2 P-29, §3.5, §3.15, §4.4): the access-token hook's refusals
// are told apart from every other Auth error, and the legacy sign-in screen
// (flow_signin_v2 off) says H1's and DM1's words, never the hook's.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:attune/features/auth/data/passwordless_auth_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final _nonce = 'ab' * 64;

AuthException _hook(String message) =>
    AuthException(message, statusCode: '403');

void main() {
  test('account_dormant:<nonce> is DM1, with the nonce', () {
    final refusal = HookRefusal.of(_hook('account_dormant:$_nonce'));
    expect(refusal, isA<AccountDormant>());
    expect((refusal as AccountDormant).nonce, _nonce);
  });

  test('account_review is H1; account_review:age is H1 for an age hold', () {
    final plain = HookRefusal.of(_hook('account_review'));
    expect(plain, isA<AccountUnderReview>());
    expect((plain as AccountUnderReview).age, isFalse);
    final age = HookRefusal.of(_hook('account_review:age'));
    expect((age as AccountUnderReview).age, isTrue);
  });

  test('only the exact :age suffix is an age hold; the words are anchored '
      '(fix round 1, #5)', () {
    for (final message in [
      'account_review:ager',
      'account_review:age_v2',
      'account_review:safety',
    ]) {
      final refusal = HookRefusal.of(_hook(message));
      expect(refusal, isA<AccountUnderReview>(), reason: message);
      expect((refusal as AccountUnderReview).age, isFalse, reason: message);
    }
    // Auth may wrap the hook's message; a wrapper isn't part of the word.
    final wrapped = HookRefusal.of(_hook('{"message":"account_review:age"}'));
    expect((wrapped as AccountUnderReview).age, isTrue);
    expect(HookRefusal.of(_hook('xaccount_review')), isNull);
    expect(HookRefusal.of(_hook('my_account_review:age')), isNull);
    expect(HookRefusal.of(_hook('account_dormant:${_nonce}ab')), isNull);
    expect(HookRefusal.of(_hook('account_dormant:${_nonce}g')), isNull);
    expect(HookRefusal.of(_hook('xaccount_dormant:$_nonce')), isNull);
    expect(
      HookRefusal.of(_hook('account_dormant:${'AB' * 64}')),
      isNull,
      reason: 'the hook writes lowercase hex',
    );
  });

  test('anything else is not a refusal', () {
    expect(HookRefusal.of(_hook('account_reviewer')), isNull);
    expect(HookRefusal.of(_hook('account_dormant:abc')), isNull);
    expect(
      HookRefusal.of(
        const AuthException(
          'Token has expired or is invalid',
          code: 'otp_expired',
          statusCode: '403',
        ),
      ),
      isNull,
    );
    expect(HookRefusal.of(Exception('account_review')), isNull);
    expect(HookRefusal.of(TimeoutException('slow')), isNull);
  });

  test("the legacy screen's words: H1, DM1, and nothing of the hook's", () {
    final service = PasswordlessAuthService();
    const h1 =
        "We need to check your account. You can't use Attune while we do "
        'this. If you think this is a mistake, contact support.';
    expect(service.userSafeMessage(_hook('account_review:age')), h1);
    expect(service.userSafeMessage(_hook('account_review')), h1);
    expect(
      service.userSafeMessage(_hook('account_dormant:$_nonce')),
      "Welcome to Attune. Let's get you set up: update Attune to the latest "
      'version to continue.',
    );
    expect(
      service.userSafeMessage(TimeoutException('slow')),
      'That took too long. Check your connection and try again.',
    );
    expect(
      service.userSafeMessage(const AuthException('x', code: 'otp_expired')),
      'That code has expired. Request a new one.',
    );
  });

  test("the legacy H1 words are H1's own (F11, fix round 1 #4)", () {
    final arb =
        jsonDecode(File('lib/i10n/app_en.arb').readAsStringSync())
            as Map<String, dynamic>;
    expect(
      PasswordlessAuthService().userSafeMessage(_hook('account_review')),
      '${arb['flow_holdTitle']}. ${arb['flow_holdBody']}',
    );
  });
}

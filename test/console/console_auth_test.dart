// Spec 2 W7b Task 7, fix round 1 (M-3): SupabaseConsoleAuth's steps
// against a fake Auth: aal2 is ready, aal1 needs TOTP or a first enrolment,
// Auth out of reach with a session is unreachable (never signed out), a
// code is sent without creating an account, an unfinished enrolment is
// cleared first, and TOTP verifies against the first verified factor.
import 'dart:async';

import 'package:attune/console/console_auth.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeBackend implements ConsoleAuthBackend {
  bool session = true;
  bool level2 = false;
  List<String> verified = [];
  List<String> unverified = [];
  Object? factorsError;
  bool hang = false;
  bool levelThrows = false;
  final calls = <String>[];

  @override
  bool get hasSession => session;

  @override
  bool get aal2 => levelThrows ? throw StateError('bad token') : level2;

  @override
  Future<ConsoleTotpFactors> totpFactors() async {
    calls.add('factors');
    if (hang) return Completer<ConsoleTotpFactors>().future;
    if (factorsError case final e?) {
      session = e != 'refused';
      throw Exception('$e');
    }
    return (verified: verified, unverified: unverified);
  }

  @override
  Future<void> sendSms(String phone, {required bool createUser}) async =>
      calls.add('sms $phone create=$createUser');

  @override
  Future<void> verifySms(String phone, String code) async =>
      calls.add('verify $phone $code');

  @override
  Future<ConsoleEnrolment?> enrolTotp(String issuer) async {
    calls.add('enrol $issuer');
    return const ConsoleEnrolment(factorId: 'new', secret: 'KEY');
  }

  @override
  Future<void> unenrol(String factorId) async => calls.add('unenrol $factorId');

  @override
  Future<void> verifyTotp(String factorId, String code) async =>
      calls.add('totp $factorId $code');

  @override
  Future<void> signOut() async => calls.add('signOut');
}

void main() {
  test(
    'the session: none, aal2, needs TOTP, needs a first enrolment',
    () async {
      final b = _FakeBackend();
      final auth = SupabaseConsoleAuth.using(b);
      b.session = false;
      expect(await auth.session(), ConsoleSession.signedOut);
      b
        ..session = true
        ..level2 = true;
      expect(await auth.session(), ConsoleSession.ready);
      expect(b.calls, isEmpty, reason: 'aal2 needs no factor read');
      b.level2 = false;
      expect(await auth.session(), ConsoleSession.needsEnrol);
      b.unverified = ['old'];
      expect(
        await auth.session(),
        ConsoleSession.needsEnrol,
        reason: 'an unverified factor is no factor',
      );
      b.verified = ['f1'];
      expect(await auth.session(), ConsoleSession.needsTotp);
    },
  );

  test('Auth out of reach with a session is unreachable; a refused '
      'session is signed out', () async {
    final b = _FakeBackend()..factorsError = 'down';
    final auth = SupabaseConsoleAuth.using(b);
    expect(await auth.session(), ConsoleSession.unreachable);
    b.factorsError = 'refused';
    expect(await auth.session(), ConsoleSession.signedOut);
  });

  test('a code is sent without creating an account', () async {
    final b = _FakeBackend();
    final auth = SupabaseConsoleAuth.using(b);
    expect(await auth.sendCode('+233244000000'), isTrue);
    expect(b.calls, ['sms +233244000000 create=false']);
  });

  test('an enrolment clears an unfinished one first; TOTP verifies the '
      'first verified factor, or the one enrolled', () async {
    final b =
        _FakeBackend()
          ..unverified = ['old1', 'old2']
          ..verified = ['f1', 'f2'];
    final auth = SupabaseConsoleAuth.using(b);
    final e = await auth.enrol();
    expect(e?.factorId, 'new');
    expect(b.calls, [
      'factors',
      'unenrol old1',
      'unenrol old2',
      'enrol Attune console',
    ]);
    b.calls.clear();
    expect(await auth.verifyTotp('123456'), isTrue);
    expect(b.calls, ['factors', 'totp f1 123456']);
    b.calls.clear();
    expect(await auth.verifyTotp('123456', factorId: 'new'), isTrue);
    expect(b.calls, ['totp new 123456']);
  });

  test('fix round 2: a factor read that never answers (Auth retrying a '
      'refresh) is unreachable within the time box, never a spinner '
      'forever', () async {
    final b = _FakeBackend()..hang = true;
    final auth = SupabaseConsoleAuth.using(
      b,
      timeout: const Duration(milliseconds: 20),
    );
    expect(await auth.session(), ConsoleSession.unreachable);
    expect(await auth.verifyTotp('123456'), isFalse);
  });

  test('fix round 2: a session whose level cannot be read is unreachable, '
      'not an error that leaves the gate spinning', () async {
    final b = _FakeBackend()..levelThrows = true;
    expect(
      await SupabaseConsoleAuth.using(b).session(),
      ConsoleSession.unreachable,
    );
  });
}

// Spec 2 W7b (§6.4): signing in to the console: the moderator's Attune
// phone account (a code by SMS), then TOTP (aal2). A first sign-in enrols
// an authenticator app; the console never stores anything itself (the
// Supabase session is the web client's own).
//
// Task 7: a sign-in check that can't reach Auth is unreachable, never
// signed out (an outage must not send the moderator back to the phone
// step); a first enrolment clears an earlier unfinished one.
//
// Fix round 1 (M-3): the Auth calls sit behind ConsoleAuthBackend (a seam
// the tests fill), so the session mapping, the no-new-account send, the
// clearing of an unfinished enrolment and the factor choice are pinned.
//
// Spec 2 W7c Task 9 (the Task 7 re-review's N-2): a code check that outlives
// its time box throws TimeoutException instead of answering false: the
// code may still have worked, so it must not read "That code didn't work."
import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

enum ConsoleSession {
  signedOut,
  needsEnrol,
  needsTotp,
  ready,

  /// Signed in, but the factors couldn't be read (Auth unreachable).
  unreachable,
}

class ConsoleEnrolment {
  const ConsoleEnrolment({required this.factorId, required this.secret});

  final String factorId;

  /// The key to type into an authenticator app.
  final String secret;
}

abstract class ConsoleAuth {
  Future<ConsoleSession> session();
  Future<bool> sendCode(String phone);

  /// False for a code Auth refused; throws [TimeoutException] when the
  /// check took too long to tell (it may still have worked).
  Future<bool> verifyCode(String phone, String code);
  Future<ConsoleEnrolment?> enrol();

  /// As [verifyCode]: false when refused, [TimeoutException] when slow.
  Future<bool> verifyTotp(String code, {String? factorId});
  Future<void> signOut();
}

/// A user's TOTP factors: the verified ones and the unfinished ones.
typedef ConsoleTotpFactors = ({List<String> verified, List<String> unverified});

/// The Auth calls the console makes.
abstract class ConsoleAuthBackend {
  bool get hasSession;

  /// The session's assurance level is aal2.
  bool get aal2;

  Future<ConsoleTotpFactors> totpFactors();
  Future<void> sendSms(String phone, {required bool createUser});
  Future<void> verifySms(String phone, String code);
  Future<ConsoleEnrolment?> enrolTotp(String issuer);
  Future<void> unenrol(String factorId);
  Future<void> verifyTotp(String factorId, String code);
  Future<void> signOut();
}

/// The web client's GoTrue, as the console uses it.
class GoTrueConsoleBackend implements ConsoleAuthBackend {
  GoTrueConsoleBackend(this._auth);

  final GoTrueClient _auth;

  @override
  bool get hasSession => _auth.currentSession != null;

  @override
  bool get aal2 =>
      _auth.mfa.getAuthenticatorAssuranceLevel().currentLevel ==
      AuthenticatorAssuranceLevels.aal2;

  @override
  Future<ConsoleTotpFactors> totpFactors() async {
    final f = await _auth.mfa.listFactors();
    return (
      verified: [for (final x in f.totp) x.id],
      unverified: [
        for (final x in f.all)
          if (x.factorType == FactorType.totp &&
              x.status == FactorStatus.unverified)
            x.id,
      ],
    );
  }

  @override
  Future<void> sendSms(String phone, {required bool createUser}) =>
      _auth.signInWithOtp(phone: phone, shouldCreateUser: createUser);

  @override
  Future<void> verifySms(String phone, String code) =>
      _auth.verifyOTP(type: OtpType.sms, phone: phone, token: code);

  @override
  Future<ConsoleEnrolment?> enrolTotp(String issuer) async {
    final r = await _auth.mfa.enroll(
      factorType: FactorType.totp,
      issuer: issuer,
    );
    final totp = r.totp;
    return totp == null
        ? null
        : ConsoleEnrolment(factorId: r.id, secret: totp.secret);
  }

  @override
  Future<void> unenrol(String factorId) => _auth.mfa.unenroll(factorId);

  @override
  Future<void> verifyTotp(String factorId, String code) =>
      _auth.mfa.challengeAndVerify(factorId: factorId, code: code);

  @override
  Future<void> signOut() => _auth.signOut();
}

class SupabaseConsoleAuth implements ConsoleAuth {
  SupabaseConsoleAuth(SupabaseClient client)
    : this.using(GoTrueConsoleBackend(client.auth));

  SupabaseConsoleAuth.using(
    this._b, {
    this.timeout = const Duration(seconds: 15),
  });

  final ConsoleAuthBackend _b;

  /// Fix round 2: every Auth call is time-boxed. With Auth failing, the
  /// client's refresh can retry for minutes; the gate then reads
  /// unreachable (Try again) instead of a spinner that never ends.
  final Duration timeout;

  Future<ConsoleTotpFactors> _factors() => _b.totpFactors().timeout(timeout);

  @override
  Future<ConsoleSession> session() async {
    if (!_b.hasSession) return ConsoleSession.signedOut;
    try {
      // Fix round 2: a level that can't be read is caught below too.
      if (_b.aal2) return ConsoleSession.ready;
      final factors = await _factors();
      return factors.verified.isEmpty
          ? ConsoleSession.needsEnrol
          : ConsoleSession.needsTotp;
    } catch (_) {
      // A refresh token Auth refused ends the session; anything else is
      // Auth out of reach (task 7, M-10).
      return _b.hasSession
          ? ConsoleSession.unreachable
          : ConsoleSession.signedOut;
    }
  }

  @override
  Future<bool> sendCode(String phone) async {
    try {
      await _b.sendSms(phone, createUser: false).timeout(timeout);
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> verifyCode(String phone, String code) async {
    try {
      await _b.verifySms(phone, code).timeout(timeout);
      return true;
    } on TimeoutException {
      rethrow;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<ConsoleEnrolment?> enrol() async {
    try {
      // An earlier set-up that was never verified is cleared first.
      try {
        for (final id in (await _factors()).unverified) {
          await _b.unenrol(id).timeout(timeout);
        }
      } catch (_) {}
      return await _b.enrolTotp('Attune console').timeout(timeout);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<bool> verifyTotp(String code, {String? factorId}) async {
    final String id;
    try {
      id = factorId ?? (await _factors()).verified.first;
    } catch (_) {
      return false; // no code was checked (fix round 2's time box)
    }
    try {
      await _b.verifyTotp(id, code).timeout(timeout);
      return true;
    } on TimeoutException {
      rethrow; // Task 9: the check itself was slow; it may have worked
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> signOut() async {
    try {
      await _b.signOut().timeout(timeout);
    } catch (_) {}
  }
}

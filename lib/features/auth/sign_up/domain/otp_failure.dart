import 'dart:async';

import 'package:attune/features/auth/sign_up/domain/resend_ladder.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Why a code wasn't sent, in the words A3/A4 show (Spec 1 §3.3). No
/// vendor is ever named.
enum OtpSendFailureKind {
  /// "Too many codes. Try again in {minutes} minutes."
  rateLimited,

  /// "We couldn't send a code. Try again or try WhatsApp."
  unavailable,

  /// "Phone sign-in is unavailable right now. Please try again later."
  signInOff,
}

class OtpSendFailure {
  const OtpSendFailure(this.kind, {this.minutes});

  final OtpSendFailureKind kind;

  /// Whole minutes to wait, at least 1, for [OtpSendFailureKind.rateLimited].
  final int? minutes;
}

final _hookRateLimited = RegExp(r'otp:rate_limited:(\d+)');
final _authWait = RegExp(r'after (\d+) seconds');

/// Classifies a failed `signInWithOtp`. The Send SMS Hook (W2c) answers
/// `otp:rate_limited:{seconds}` or `otp:unavailable`; Auth's own limits
/// answer with their error codes.
OtpSendFailure classifyOtpSendError(Object error) {
  if (error is AuthException) {
    final hook = _hookRateLimited.firstMatch(error.message);
    if (hook != null) {
      return OtpSendFailure(
        OtpSendFailureKind.rateLimited,
        minutes: _minutes(int.parse(hook.group(1)!)),
      );
    }
    if (error.message.contains('otp:unavailable')) {
      return const OtpSendFailure(OtpSendFailureKind.unavailable);
    }
    switch (error.code) {
      case 'over_sms_send_rate_limit':
      case 'over_request_rate_limit':
        final wait = _authWait.firstMatch(error.message);
        return OtpSendFailure(
          OtpSendFailureKind.rateLimited,
          minutes: _minutes(wait == null ? 60 : int.parse(wait.group(1)!)),
        );
      case 'otp_disabled':
      case 'phone_provider_disabled':
      case 'sms_send_failed' when error.message.contains('disabled'):
        return const OtpSendFailure(OtpSendFailureKind.signInOff);
    }
  }
  return const OtpSendFailure(OtpSendFailureKind.unavailable);
}

int _minutes(int seconds) => seconds <= 60 ? 1 : (seconds + 59) ~/ 60;

/// Why a code didn't verify (Spec 1 §3.3 A4).
enum OtpVerifyFailure {
  /// "That code didn't work. Check it and try again."
  wrongCode,

  /// "That code has expired. Send a new one."
  expired,

  /// "Too many codes…" with no minutes: Auth's verify limit.
  rateLimited,

  /// The network or the server: "We couldn't check the code right now."
  unavailable,
}

/// Auth answers `otp_expired` ("Token has expired or is invalid") for a
/// wrong code and an old one alike, so the age of the newest send decides.
OtpVerifyFailure classifyOtpVerifyError(
  Object error, {
  required DateTime? lastSentAt,
  required DateTime now,
}) {
  if (error is AuthException) {
    if (error.code == 'over_request_rate_limit') {
      return OtpVerifyFailure.rateLimited;
    }
    if (error.code == 'otp_expired' ||
        error.code == 'invalid_credentials' ||
        error.statusCode == '403') {
      final expired =
          lastSentAt != null &&
          ResendLadder.isExpired(lastSentAt: lastSentAt, now: now);
      return expired ? OtpVerifyFailure.expired : OtpVerifyFailure.wrongCode;
    }
  }
  if (error is TimeoutException) return OtpVerifyFailure.unavailable;
  return OtpVerifyFailure.unavailable;
}

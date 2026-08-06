import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PasswordlessAuthResult {
  const PasswordlessAuthResult({required this.isConfigured, this.userId});

  final bool isConfigured;
  final String? userId;

  bool get isVerified => userId != null;
}

class PasswordlessAuthService {
  PasswordlessAuthService({SupabaseClient? client}) : _client = client;

  final SupabaseClient? _client;

  static const authTimeout = Duration(seconds: 30);

  SupabaseClient? get _safeClient {
    if (_client != null) return _client;
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  bool get isConfigured => _safeClient != null;

  Future<PasswordlessAuthResult> requestPhoneOtp(
    String phoneNumber, {
    OtpChannel channel = OtpChannel.sms,
  }) async {
    final client = _safeClient;
    if (client == null) {
      return const PasswordlessAuthResult(isConfigured: false);
    }

    // TEMP debug: log the exact E.164 string sent to Supabase, so the value can
    // be compared byte-for-byte against the dashboard test-number entry. A common
    // Ghana pitfall is a leftover leading 0 (+2330501201544 vs +233501201544).
    // Remove before release.
    if (kDebugMode) {
      debugPrint('[AUTH] signInWithOtp phone="${phoneNumber.trim()}"');
    }

    await client.auth
        .signInWithOtp(phone: phoneNumber.trim(), channel: channel)
        .timeout(authTimeout);
    return const PasswordlessAuthResult(isConfigured: true);
  }

  Future<PasswordlessAuthResult> verifyPhoneOtp({
    required String phoneNumber,
    required String token,
  }) async {
    final client = _safeClient;
    if (client == null) {
      return const PasswordlessAuthResult(isConfigured: false);
    }

    // OtpType.sms is correct for BOTH delivery channels — OtpChannel has an
    // sms/whatsapp split, but OtpType does not (gotrue 2.21.0 exposes no
    // whatsapp member). Phone codes verify identically however they were
    // delivered, so this is not an SMS-only path despite the name.
    final response = await client.auth
        .verifyOTP(
          phone: phoneNumber.trim(),
          token: token.trim(),
          type: OtpType.sms,
        )
        .timeout(authTimeout);

    return PasswordlessAuthResult(
      isConfigured: true,
      userId: response.user?.id,
    );
  }

  Stream<AuthState> get authStateChanges {
    final client = _safeClient;
    if (client == null) return const Stream.empty();
    return client.auth.onAuthStateChange;
  }

  User? get currentUser {
    final client = _safeClient;
    return client?.auth.currentUser;
  }

  /// Ends the current session. Used when a user declines the EULA after OTP
  /// verification — the session is already valid at that point, so without
  /// this they would be treated as signed in on the next launch and skip the
  /// consent gate entirely.
  Future<void> signOut() async {
    final client = _safeClient;
    if (client == null) return;
    await client.auth.signOut().timeout(authTimeout);
  }

  /// User-facing copy for an auth failure.
  ///
  /// Spec (AUTH_ONBOARDING_ENGINE §Failure Modes): "No UI error should expose
  /// stack traces, project refs, internal table names, or raw provider
  /// payloads." So every branch here returns generic, actionable copy that
  /// names no vendor (Supabase/Twilio), no provider state (trial account,
  /// provider limits), and no internal configuration. Operators diagnose from
  /// the logs, not from the user's screen.
  String userSafeMessage(Object error) {
    if (error is TimeoutException) {
      return 'That took too long. Check your connection and try again.';
    }
    if (error is AuthException) {
      _logAuthException(error);
      return switch (error.code) {
        'over_request_rate_limit' => 'Too many attempts. Try again later.',
        'otp_expired' => 'That code has expired. Request a new one.',
        'otp_disabled' => 'Phone sign-in is unavailable right now.',
        'validation_failed' => 'Check the phone number and try again.',
        _ => _messageForAuthException(error),
      };
    }
    debugPrint('[auth] passwordless error: ${error.runtimeType}');
    return 'Could not verify right now. Please try again.';
  }

  /// Logs the error CATEGORY only.
  ///
  /// `error.message` is deliberately NOT logged: Supabase/provider auth errors
  /// echo the submitted phone number back in the message on several failure
  /// paths, and phone is PII (spec §1.11 "never log raw phone numbers", §4.4
  /// "log error categories/runtime types only, not PII"). Code + status are
  /// enough to identify the failure class.
  void _logAuthException(AuthException error) {
    debugPrint(
      '[auth] passwordless error: '
      'code=${error.code}, '
      'status=${error.statusCode}',
    );
  }

  /// Maps provider-specific failures onto generic user copy.
  ///
  /// The message is inspected only to CLASSIFY the failure; none of it is
  /// surfaced to the user, and the classified categories never name the vendor
  /// or its account state.
  String _messageForAuthException(AuthException error) {
    final message = error.message.toLowerCase();

    // Provider daily send cap (e.g. Twilio 63038) — a delivery outage from the
    // user's point of view, not something they can act on beyond waiting.
    if (message.contains('63038') || message.contains('daily messages limit')) {
      return 'We could not send a code right now. Please try again later.';
    }

    // SMS/provider misconfiguration, or a provider trial account that can only
    // reach allow-listed numbers (e.g. Twilio 21608). Both are OUR problem, not
    // the user's — say so without naming the vendor or its account tier.
    if (message.contains('sms') ||
        message.contains('twilio') ||
        message.contains('provider') ||
        message.contains('unverified') ||
        message.contains('21608') ||
        message.contains('trial')) {
      return 'Phone sign-in is unavailable right now. Please try again later.';
    }

    if (message.contains('phone') || message.contains('number')) {
      return 'Check the phone number and country code, then try again.';
    }

    if (message.contains('rate') || message.contains('too many')) {
      return 'Too many attempts. Try again later.';
    }

    return 'Could not verify right now. Please try again.';
  }
}

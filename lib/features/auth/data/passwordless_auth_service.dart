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

    await client.auth
        .signInWithOtp(
          phone: phoneNumber.trim(),
          channel: channel,
        )
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

  String userSafeMessage(Object error) {
    if (error is TimeoutException) {
      return 'That took too long. Check your connection and try again.';
    }
    if (error is AuthException) {
      _logAuthException(error);
      return switch (error.code) {
        'over_request_rate_limit' => 'Too many attempts. Try again later.',
        'otp_expired' => 'That code has expired. Request a new one.',
        'otp_disabled' => 'This sign-in method is not enabled yet.',
        'validation_failed' => 'Check the phone number and try again.',
        _ => _messageForAuthException(error),
      };
    }
    debugPrint('[auth] passwordless error: ${error.runtimeType}');
    return 'Could not verify right now. Please try again.';
  }

  void _logAuthException(AuthException error) {
    debugPrint(
      '[auth] passwordless error: '
      'code=${error.code}, '
      'status=${error.statusCode}, '
      'message=${error.message}',
    );
  }

  String _messageForAuthException(AuthException error) {
    final message = error.message.toLowerCase();

    if (message.contains('63038') || message.contains('daily messages limit')) {
      return 'Daily verification limit reached. Try again tomorrow or check provider limits.';
    }

    if (message.contains('sms') ||
        message.contains('twilio') ||
        message.contains('provider')) {
      return 'Verification is not ready yet. Check the auth provider setup in Supabase.';
    }

    if (message.contains('unverified') ||
        message.contains('21608') ||
        message.contains('trial')) {
      return 'Your provider can only send codes to verified recipient numbers.';
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

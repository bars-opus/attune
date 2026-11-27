// lib/core/auth/auth_service.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// NOTE: authServiceProvider and authStateProvider live in auth_provider.dart.
// Only unique, non-duplicated providers belong here.

// ==================== AUTH SERVICE ====================

class AuthService {
  final SupabaseClient _supabase;

  AuthService(this._supabase);

  // Entry gates fix 6 (2026-11-27): sign-in is phone OTP only (the sign-up
  // flow's own auth seam). The email/password, Google, Apple, password
  // reset and confirmation-email paths are gone; only sign-out and the
  // session getters stay.

  /// Default timeout for any single HTTP call to Supabase auth.
  /// 30s is generous enough for slow mobile networks but bounded so the UI
  /// loading state never spins forever.
  static const _authTimeout = Duration(seconds: 30);

  /// Wraps a Supabase call with a timeout. On timeout, throws an AuthException
  /// that flows through the standard error-translation path.
  Future<T> _withTimeout<T>(Future<T> Function() op, {Duration? timeout}) {
    return op().timeout(
      timeout ?? _authTimeout,
      onTimeout:
          () =>
              throw AuthException(
                'Request timed out. Please check your connection and try again.',
                statusCode: '408',
                code: 'timeout',
              ),
    );
  }

  // ==================== COMMON ====================

  Future<void> signOut() async {
    try {
      await _withTimeout(() => _supabase.auth.signOut());
    } on AuthException catch (e) {
      throw _handleAuthException(e);
    }
  }

  // ==================== GETTERS ====================

  User? get currentUser => _supabase.auth.currentUser;

  Stream<AuthState> get authStateChanges => _supabase.auth.onAuthStateChange;
  bool get isSignedIn => _supabase.auth.currentUser != null;

  // ==================== ERROR HANDLING ====================

  AuthException _handleAuthException(AuthException e) {
    // Log only statusCode + code. Supabase error messages frequently embed the
    // user's email or other PII that must not reach crash-reporting pipelines.
    debugPrint('Auth Error [${e.statusCode}] code=${e.code}');

    // Supabase v2: e.code is the specific error string; e.statusCode is the HTTP code.
    // Switch on code first, fall back to message heuristics.
    final message = switch (e.code) {
      'invalid_credentials' => 'Invalid email or password.',
      'email_exists' ||
      'user_already_exists' => 'An account with this email already exists.',
      'email_not_confirmed' => 'Please verify your email before signing in.',
      'weak_password' => 'Password is too weak. Use at least 8 characters.',
      'same_password' =>
        'Your new password must be different from your current password.',
      'over_request_rate_limit' ||
      'over_email_send_rate_limit' => 'Too many attempts. Try again later.',
      'user_banned' => 'This account has been suspended.',
      'session_not_found' => 'Session expired. Please sign in again.',
      _ => switch (e.message) {
        String m when m.contains('Invalid login credentials') =>
          'Invalid email or password.',
        String m when m.contains('Email not confirmed') =>
          'Please verify your email before signing in.',
        String m when m.contains('network') || m.contains('socket') =>
          'Network error. Check your connection.',
        _ => 'Authentication failed. Please try again.',
      },
    };

    return AuthException(message, statusCode: e.statusCode, code: e.code);
  }
}

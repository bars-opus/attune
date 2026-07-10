// lib/core/auth/auth_service.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// NOTE: authServiceProvider and authStateProvider live in auth_provider.dart.
// Only unique, non-duplicated providers belong here.

// ==================== AUTH SERVICE ====================

class AuthService {
  final SupabaseClient _supabase;

  AuthService(this._supabase);

  // MethodChannel names are arbitrary identifiers — they only need to match
  // between Flutter and the native side (see ios/Runner/AppDelegate.swift).
  // Keep this in sync with the native Google Sign-In handler.
  static const _googleChannel = MethodChannel(
    'com.barsOpus.florence/google_sign_in',
  );

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

  // ==================== EMAIL/PASSWORD ====================

  Future<AuthResponse> signUpWithEmail({
    required String email,
    required String password,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      return await _withTimeout(
        () => _supabase.auth.signUp(
          email: email.trim(),
          password: password,
          data: metadata,
        ),
      );
    } on AuthException catch (e) {
      throw _handleAuthException(e);
    }
  }

  Future<AuthResponse> signInWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      return await _withTimeout(
        () => _supabase.auth.signInWithPassword(
          email: email.trim(),
          password: password,
        ),
      );
    } on AuthException catch (e) {
      throw _handleAuthException(e);
    }
  }

  // ==================== OAUTH ====================

  /// Google Sign-In.
  ///
  /// iOS/macOS: native account picker via google_sign_in → signInWithIdToken.
  ///   No browser, no redirect, no domain shown to the user.
  /// Android/Web: browser OAuth fallback (no google-services.json configured).
  Future<void> signInWithGoogle() async {
    try {
      if (!kIsWeb && (Platform.isIOS || Platform.isMacOS)) {
        await _nativeGoogleSignIn();
      } else {
        await _supabase.auth.signInWithOAuth(
          OAuthProvider.google,
          redirectTo: _getDeepLink(),
          authScreenLaunchMode: LaunchMode.externalApplication,
        );
      }
    } on AuthException catch (e) {
      throw _handleAuthException(e);
    }
  }

  Future<void> _nativeGoogleSignIn() async {
    // iOS OAuth client (com.attune.attune) — used for the native sign-in flow.
    const iosClientId =
        '706235705872-cnj9o5fvdqla35sodsrfbkfudrupqf05.apps.googleusercontent.com';

    // Web OAuth client — Supabase verifies the returned ID token against this.
    // The ID token's `aud` claim must match the Web client ID, not the iOS client ID.
    const webClientId =
        '706235705872-vffmadm1k4vjf40o45cqdciofnjeupnd.apps.googleusercontent.com';

    // We generate our own nonce so Supabase can verify it.
    // GIDSignIn embeds hashedNonce in the token's `nonce` claim;
    // we pass rawNonce to Supabase which SHA-256 hashes it before comparing.
    final rawNonce = _generateNonce();
    final hashedNonce = _sha256ofString(rawNonce);

    final result = await _googleChannel
        .invokeMapMethod<String, String>('signInWithNonce', {
          'hashedNonce': hashedNonce,
          'iosClientId': iosClientId,
          'webClientId': webClientId,
        });

    if (result == null) return; // user cancelled — silent, no error

    final idToken = result['idToken'];
    final accessToken = result['accessToken'];

    if (idToken == null) {
      throw Exception('Google Sign-In returned no ID token.');
    }

    await _withTimeout(
      () => _supabase.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
        accessToken: accessToken,
        nonce: rawNonce,
      ),
    );
  }

  /// Apple Sign-In.
  ///
  /// On iOS/macOS: uses the native Sign in with Apple sheet (no browser).
  /// The nonce is hashed before being sent to Apple, and the raw nonce is
  /// passed to Supabase for token verification.
  ///
  /// Supabase Apple provider must be enabled in the Supabase Dashboard:
  ///   Auth → Providers → Apple → Enable
  ///   Set "Authorized Client IDs" to include your app Bundle ID.
  ///   (The full Apple Service ID + private key are only required for the
  ///    browser OAuth flow, NOT for native sign-in with ID tokens.)
  ///
  /// On Android: falls back to browser OAuth (Apple has no Android native SDK).
  Future<void> signInWithApple() async {
    try {
      if (Platform.isIOS || Platform.isMacOS) {
        await _nativeAppleSignIn();
      } else {
        // Android — browser OAuth (requires Apple Service ID + JWT secret in Supabase)
        await _supabase.auth.signInWithOAuth(
          OAuthProvider.apple,
          redirectTo: _getDeepLink(),
          authScreenLaunchMode: LaunchMode.externalApplication,
        );
      }
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) {
        // User tapped Cancel — not a real error, just return silently
        return;
      }
      throw Exception('Apple sign-in failed: ${e.message}');
    } on AuthException catch (e) {
      throw _handleAuthException(e);
    } catch (e) {
      debugPrint('Apple sign-in error: $e');
      rethrow;
    }
  }

  Future<void> _nativeAppleSignIn() async {
    final rawNonce = _generateNonce();
    final hashedNonce = _sha256ofString(rawNonce);

    final credential = await SignInWithApple.getAppleIDCredential(
      scopes: [
        AppleIDAuthorizationScopes.email,
        AppleIDAuthorizationScopes.fullName,
      ],
      nonce: hashedNonce,
    );

    final idToken = credential.identityToken;
    if (idToken == null)
      throw Exception('Apple did not return an identity token');

    await _withTimeout(
      () => _supabase.auth.signInWithIdToken(
        provider: OAuthProvider.apple,
        idToken: idToken,
        nonce: rawNonce,
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

  Future<void> resetPassword(String email) async {
    try {
      await _withTimeout(
        () => _supabase.auth.resetPasswordForEmail(
          email.trim(),
          // Use HTTPS so the OS can intercept via Universal Links (iOS) /
          // App Links (Android) even from Gmail's in-app WebView.
          // aurain:// works in Safari/Chrome but not in WebViews.
          redirectTo:
              kIsWeb
                  ? '${Uri.base.origin}/auth/callback'
                  : 'https://aurain.barsopus.com/auth/callback',
        ),
      );
    } on AuthException catch (e) {
      throw _handleAuthException(e);
    }
  }

  Future<void> resendConfirmationEmail(String email) async {
    try {
      await _withTimeout(
        () => _supabase.auth.resend(
          type: OtpType.signup,
          email: email.trim(),
          emailRedirectTo: _getDeepLink(),
        ),
      );
    } on AuthException catch (e) {
      throw _handleAuthException(e);
    }
  }

  Future<void> updatePassword(String newPassword) async {
    try {
      await _withTimeout(
        () => _supabase.auth.updateUser(UserAttributes(password: newPassword)),
      );
    } on AuthException catch (e) {
      throw _handleAuthException(e);
    }
  }
  // ==================== GETTERS ====================

  User? get currentUser => _supabase.auth.currentUser;

  bool get isEmailConfirmed {
    final user = _supabase.auth.currentUser;
    if (user == null) return false;
    // OAuth users (Google, Apple) are always considered confirmed.
    final provider = user.appMetadata['provider'] as String?;
    if (provider != null && provider != 'email') return true;
    return user.emailConfirmedAt != null;
  }

  Stream<AuthState> get authStateChanges => _supabase.auth.onAuthStateChange;
  bool get isSignedIn => _supabase.auth.currentUser != null;

  // ==================== HELPERS ====================

  String _getDeepLink() {
    if (kIsWeb) {
      return '${Uri.base.origin}/auth/callback';
    }
    // Both iOS and Android use aurain:// scheme.
    // Ensure AndroidManifest.xml has the aurain intent-filter.
    return 'aurain://login-callback/';
  }

  String _generateNonce([int length = 32]) {
    const charset =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = Random.secure();
    return List.generate(
      length,
      (_) => charset[random.nextInt(charset.length)],
    ).join();
  }

  String _sha256ofString(String input) {
    final bytes = utf8.encode(input);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

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

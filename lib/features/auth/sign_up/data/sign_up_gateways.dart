import 'dart:ui' show PlatformDispatcher;

import 'package:attune/features/auth/data/passwordless_auth_service.dart';
import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:attune/features/auth/sign_up/data/otp_delivery_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Sends a phone code (Spec 1 §3.3 A3). W2b: Supabase's built-in SMS
/// provider, always by SMS. W2c replaces it with the delivery intent plus
/// the Send SMS Hook.
abstract class CodeSender {
  /// [channel] is `sms`, `whatsapp` or `voice`; [deviceNonce] is the
  /// draft's. Throws what `signInWithOtp` throws.
  Future<void> send({
    required String phoneE164,
    required String channel,
    required String deviceNonce,
  });
}

class BuiltInSmsCodeSender implements CodeSender {
  BuiltInSmsCodeSender(this._auth);

  final PasswordlessAuthService _auth;

  @override
  Future<void> send({
    required String phoneE164,
    required String channel,
    required String deviceNonce,
  }) async {
    final result = await _auth.requestPhoneOtp(phoneE164);
    if (!result.isConfigured) {
      throw const AuthException('not configured', code: 'otp_disabled');
    }
  }
}

/// The Auth calls the flow makes, so it can be tested without a backend.
abstract class SignUpAuth {
  String? get currentUserId;

  /// The signed-in session's number, E.164, or null.
  String? get currentPhone;

  /// The verified account's id, or null when Auth returned none.
  Future<String?> verify({required String phoneE164, required String code});

  /// The app's full sign-out (wipes and push release included).
  Future<void> signOut();
}

class AppSignUpAuth implements SignUpAuth {
  AppSignUpAuth(this._ref, [PasswordlessAuthService? auth])
    : _auth = auth ?? PasswordlessAuthService();

  final Ref _ref;
  final PasswordlessAuthService _auth;

  @override
  String? get currentUserId => _auth.currentUser?.id;

  @override
  String? get currentPhone {
    final phone = _auth.currentUser?.phone;
    if (phone == null || phone.isEmpty) return null;
    return phone.startsWith('+') ? phone : '+$phone';
  }

  @override
  Future<String?> verify({
    required String phoneE164,
    required String code,
  }) async =>
      (await _auth.verifyPhoneOtp(phoneNumber: phoneE164, token: code)).userId;

  @override
  Future<void> signOut() => _ref.read(authOperationsProvider).signOut();
}

/// W2c: the delivery intent first, then the code (OtpDeliveryService).
final codeSenderProvider = Provider<CodeSender>(
  (ref) => OtpDeliveryService(
    postIntent: functionsIntentPoster(() => Supabase.instance.client.functions),
    auth: PasswordlessAuthService(),
    platform: OtpDeliveryService.platformName,
    locale: () => PlatformDispatcher.instance.locale.toLanguageTag(),
  ),
);

final signUpAuthProvider = Provider<SignUpAuth>((ref) => AppSignUpAuth(ref));

import 'dart:async';

import 'package:attune/features/auth/data/passwordless_auth_service.dart';
import 'package:attune/features/auth/sign_up/data/sign_up_gateways.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Posts the delivery intent to `otp-delivery-intent` (W2c).
typedef IntentPoster = Future<void> Function(Map<String, dynamic> body);

/// The edge function the delivery intent goes to (review B8 n-1): a typo
/// here would send every code by SMS without a word.
const otpDeliveryIntentFunction = 'otp-delivery-intent';

/// The intent through Supabase's functions client; [functions] is read
/// when the intent is posted, so a client that isn't ready fails inside
/// [OtpDeliveryService]'s guard.
IntentPoster functionsIntentPoster(FunctionsClient Function() functions) =>
    (body) => functions().invoke(otpDeliveryIntentFunction, body: body);

/// A3/A4's sending under the Send SMS Hook (Spec 1 §3.3, §4.5, review S-3):
/// first the delivery intent — the channel wanted, this phone's platform
/// and locale, and the draft's random `device_nonce` — then the code itself,
/// always asked for as SMS. The hook moves it to WhatsApp or a call only
/// when the intent is fresh, capped and from this one device. A failed
/// intent never stops the code: it then simply goes by SMS. Without the
/// hook (W2b, or a project where it is off) Supabase's own SMS sends it.
class OtpDeliveryService implements CodeSender {
  OtpDeliveryService({
    required IntentPoster postIntent,
    required PasswordlessAuthService auth,
    required String Function() platform,
    required String Function() locale,
  }) : _postIntent = postIntent,
       _auth = auth,
       _platform = platform,
       _locale = locale;

  final IntentPoster _postIntent;
  final PasswordlessAuthService _auth;
  final String Function() _platform;
  final String Function() _locale;

  static const intentTimeout = Duration(seconds: 4);

  @override
  Future<void> send({
    required String phoneE164,
    required String channel,
    required String deviceNonce,
  }) async {
    try {
      await _postIntent({
        'phone': phoneE164,
        'channel': channel,
        'platform': _platform(),
        'locale': _locale(),
        'device_nonce': deviceNonce,
      }).timeout(intentTimeout);
    } catch (error) {
      debugPrint('[otp] delivery intent skipped: ${error.runtimeType}');
    }
    final result = await _auth.requestPhoneOtp(phoneE164);
    if (!result.isConfigured) {
      throw const AuthException('not configured', code: 'otp_disabled');
    }
  }

  static String platformName([TargetPlatform? platform]) => switch (platform ??
      defaultTargetPlatform) {
    TargetPlatform.iOS => 'ios',
    TargetPlatform.android => 'android',
    _ => 'other',
  };
}

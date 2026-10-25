import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smart_auth/smart_auth.dart';

/// Android's code autofill for A4 (Spec 1 §3.3, W2c): the SMS Retriever in
/// release builds (the message ends with the release key's app hash), the
/// one-tap User Consent prompt otherwise. No SMS permission either way. iOS
/// fills the code itself from `AutofillHints.oneTimeCode` and the
/// domain-bound last line, so it never listens here.
abstract class SmsCodeListener {
  /// The next code that arrives, or null (cancelled, none, not Android).
  Future<String?> next();

  Future<void> stop();
}

class SmartAuthCodeListener implements SmsCodeListener {
  /// [release] is the build mode (kReleaseMode unless a test says).
  SmartAuthCodeListener({TargetPlatform? platform, bool? release})
    : _android = (platform ?? defaultTargetPlatform) == TargetPlatform.android,
      _release = release ?? kReleaseMode;

  final bool _android;
  final bool _release;

  /// A code is exactly six ASCII digits standing alone (review B8 m-4):
  /// the first such run in the message, never 4 to 8 digits of anything
  /// else, so an unrelated SMS approved under User Consent fills nothing.
  static const codeMatcher = r'(?<![0-9])[0-9]{6}(?![0-9])';

  @override
  Future<String?> next() async {
    if (!_android) return null;
    try {
      final result =
          _release
              ? await SmartAuth.instance.getSmsWithRetrieverApi(
                matcher: codeMatcher,
              )
              : await SmartAuth.instance.getSmsWithUserConsentApi(
                matcher: codeMatcher,
              );
      return result.hasData ? result.requireData.code : null;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> stop() async {
    if (!_android) return;
    try {
      await (_release
          ? SmartAuth.instance.removeSmsRetrieverApiListener()
          : SmartAuth.instance.removeUserConsentApiListener());
    } catch (_) {}
  }
}

final smsCodeListenerProvider = Provider<SmsCodeListener>(
  (ref) => SmartAuthCodeListener(),
);

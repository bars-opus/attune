import 'dart:async';
import 'dart:convert';

import 'package:attune/core/platform/install_referrer_keys.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The Install Referrer's code as a prefill for RI-1 only (final review
/// #1). Nothing else reads it: the gates and HomeScreen read the invite
/// slots (OnboardingStore), which this never writes, so a referrer code is
/// joined only after the person types or confirms it on RI-1.
class InstallReferrerPrefill {
  InstallReferrerPrefill._();

  /// As long as a link's code waits for the first sign-in (W1c's claim).
  static const window = Duration(hours: 24);

  /// The code, or null; one past [window] (or unreadable) is dropped.
  static String? read(SharedPreferences prefs, {DateTime? now}) {
    final raw = prefs.getString(kInstallReferrerCodeKey);
    if (raw == null) return null;
    try {
      final json = jsonDecode(raw);
      final code = json is Map ? json['code'] : null;
      final at = json is Map ? DateTime.tryParse('${json['stored_at']}') : null;
      if (code is String && code.isNotEmpty && at != null) {
        final age = (now ?? DateTime.now().toUtc()).difference(at);
        if (!age.isNegative && age < window) return code;
      }
    } catch (_) {
      // Unreadable: dropped below.
    }
    unawaited(clear(prefs));
    return null;
  }

  static Future<void> save(
    SharedPreferences prefs,
    String code, {
    DateTime? now,
  }) => prefs.setString(
    kInstallReferrerCodeKey,
    jsonEncode({
      'code': code,
      'stored_at': (now ?? DateTime.now().toUtc()).toIso8601String(),
    }),
  );

  static Future<void> clear(SharedPreferences prefs) =>
      prefs.remove(kInstallReferrerCodeKey);
}

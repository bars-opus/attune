// Spec 2 W8b (§2.3): on Android, the mobile network's country
// (TelephonyManager.getNetworkCountryIso) through MainActivity's
// attune/device channel, for dating-device-check. No permission; nothing
// stored. The SIM's country is never sent (§2.3's computation uses the
// network's, R-75). iOS has no equivalent and answers null.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

abstract final class NetworkCountry {
  static const channel = MethodChannel('attune/device');

  /// Upper-case ISO 3166-1 alpha-2, or null.
  static Future<String?> read({TargetPlatform? platform}) async {
    if ((platform ?? defaultTargetPlatform) != TargetPlatform.android) {
      return null;
    }
    try {
      final iso = await channel
          .invokeMethod<String>('networkCountryIso')
          .timeout(const Duration(seconds: 1));
      if (iso == null || !RegExp(r'^[A-Za-z]{2}$').hasMatch(iso)) return null;
      return iso.toUpperCase();
    } catch (_) {
      return null;
    }
  }
}

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The SIM card's country (Spec 1 §3.3 A3, W2b): Android's
/// `TelephonyManager.getSimCountryIso` through MainActivity's
/// `attune/device` channel. No permission, nothing stored or sent. iOS has
/// no equivalent and answers null.
class SimCountry {
  const SimCountry._();

  static const channel = MethodChannel('attune/device');

  /// Upper-case ISO 3166-1 alpha-2, or null.
  static Future<String?> read({TargetPlatform? platform}) async {
    if ((platform ?? defaultTargetPlatform) != TargetPlatform.android) {
      return null;
    }
    try {
      final iso = await channel
          .invokeMethod<String>('simCountryIso')
          .timeout(const Duration(seconds: 1));
      if (iso == null || !RegExp(r'^[A-Za-z]{2}$').hasMatch(iso)) return null;
      return iso.toUpperCase();
    } catch (_) {
      return null;
    }
  }
}

/// The SIM's and the device region's countries, for A3's default.
typedef DeviceCountries = ({String? sim, String? region});

final deviceCountryProvider = FutureProvider<DeviceCountries>((ref) async {
  final region = PlatformDispatcher.instance.locale.countryCode;
  return (
    sim: await SimCountry.read(),
    region: region == null || region.isEmpty ? null : region.toUpperCase(),
  );
});

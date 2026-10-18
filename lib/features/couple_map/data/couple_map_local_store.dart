import 'dart:convert';

import 'package:attune/features/couple_map/domain/story_place.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Device-only couple map settings. The home area is the most sensitive
/// place there is, so all of it lives in secure storage and quick exit
/// clears it (spec §3.6).
abstract class CoupleMapLocalStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

abstract final class CoupleMapLocalKeys {
  static const pinLastChoice = 'story_pin_last_choice';
  static const homeArea = 'couple_map_home_area';
  static const storiesHintSeen = 'couple_map_stories_hint_seen';
  static const all = [pinLastChoice, homeArea, storiesHintSeen];
}

class SecureCoupleMapLocalStore implements CoupleMapLocalStore {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    // This device only: the home area never syncs through iCloud Keychain.
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );
  @override
  Future<String?> read(String key) async {
    try {
      return await _storage.read(key: key);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(String key, String value) async {
    try {
      await _storage.write(key: key, value: value);
    } catch (_) {}
  }

  @override
  Future<void> delete(String key) async {
    try {
      await _storage.delete(key: key);
    } catch (_) {}
  }
}

Future<bool> readPinLastChoice(CoupleMapLocalStore s) async =>
    await s.read(CoupleMapLocalKeys.pinLastChoice) == 'true';

Future<void> writePinLastChoice(CoupleMapLocalStore s, bool on) =>
    s.write(CoupleMapLocalKeys.pinLastChoice, on ? 'true' : 'false');

Future<HomeArea?> readHomeArea(CoupleMapLocalStore s) async {
  final raw = await s.read(CoupleMapLocalKeys.homeArea);
  if (raw == null) return null;
  try {
    final m = jsonDecode(raw) as Map<String, dynamic>;
    return HomeArea(
      lat: (m['lat'] as num).toDouble(),
      lng: (m['lng'] as num).toDouble(),
    );
  } catch (_) {
    return null;
  }
}

Future<void> writeHomeArea(CoupleMapLocalStore s, HomeArea? h) =>
    h == null
        ? s.delete(CoupleMapLocalKeys.homeArea)
        : s.write(
          CoupleMapLocalKeys.homeArea,
          jsonEncode({'lat': h.lat, 'lng': h.lng}),
        );

import 'package:attune/core/providers/shared_prefs_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The guest birth-year gate (G1) and the under-18 device block (X1),
/// Spec 1 §3.2, §3.6.
///
/// * The guest's year sits in its own keystore file, `attune_age_gate`,
///   which Android backups exclude (`backup_rules.xml`,
///   `data_extraction_rules.xml`); the iOS item is this-device-only. A plain
///   prefs bool says the gate was passed, so the router reads it at once.
/// * The block's end date sits in the plain prefs file, which Android Auto
///   Backup includes, and in the Keychain, which iOS keeps across a
///   reinstall. So it usually survives a reinstall (review F-5): on iOS
///   through the Keychain, on Android only when a backup ran before the
///   uninstall.
class AgeGateStore {
  AgeGateStore(
    this._prefs, {
    FlutterSecureStorage? secure,
    DateTime Function()? now,
  }) : _secure = secure ?? defaultSecure,
       _now = now ?? DateTime.now;

  final SharedPreferences _prefs;
  final FlutterSecureStorage _secure;
  final DateTime Function() _now;

  static const keystoreFile = 'attune_age_gate';
  static const guestOkKey = 'attune.age_gate.guest_ok';
  static const blockUntilKey = 'attune.age_block.until';
  static const _secureYearKey = 'guest_birth_year';
  static const _secureBlockKey = 'age_block_until';
  static const blockLength = Duration(days: 30);

  static const defaultSecure = FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
      resetOnError: true,
      sharedPreferencesName: keystoreFile,
    ),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  /// For the router at boot: no await, no keystore.
  static bool readGuestOk(SharedPreferences prefs) =>
      prefs.getBool(guestOkKey) ?? false;

  /// For the router at boot: a block in force on [now].
  static bool readBlocked(SharedPreferences prefs, DateTime now) {
    final until = DateTime.tryParse(prefs.getString(blockUntilKey) ?? '');
    return until != null && now.isBefore(until);
  }

  bool get guestOk => readGuestOk(_prefs);

  bool get isBlocked => readBlocked(_prefs, _now());

  /// G1 passed: the year for A2's pre-fill, and the routing bool.
  Future<void> passGuestGate(int year) async {
    try {
      await _secure.write(key: _secureYearKey, value: '$year');
    } catch (error) {
      // The year is only a pre-fill; the gate still counts as passed.
      debugPrint('[age-gate] year not stored: ${error.runtimeType}');
    }
    await _prefs.setBool(guestOkKey, true);
  }

  Future<int?> guestBirthYear() async {
    try {
      return int.tryParse(await _secure.read(key: _secureYearKey) ?? '');
    } catch (_) {
      return null;
    }
  }

  /// Sign-up completed: the year has done its job (spec §4.8).
  Future<void> clearGuestBirthYear() async {
    try {
      await _secure.delete(key: _secureYearKey);
    } catch (_) {}
  }

  /// X1: 30 days from now, in both places, and the guest pass ends with it
  /// (ruling N-1: guest Opinions goes back through G1, which leads to X1).
  /// Never throws: each place is written on its own, and the caller stops at
  /// X1 either way.
  Future<void> block() async {
    final until = _now().toUtc().add(blockLength).toIso8601String();
    try {
      await _prefs.setString(blockUntilKey, until);
    } catch (error) {
      debugPrint('[age-gate] prefs block not stored: ${error.runtimeType}');
    }
    try {
      await _prefs.remove(guestOkKey);
    } catch (error) {
      debugPrint('[age-gate] guest pass not cleared: ${error.runtimeType}');
    }
    try {
      await _secure.write(key: _secureBlockKey, value: until);
    } catch (error) {
      debugPrint('[age-gate] keychain block not stored: ${error.runtimeType}');
    }
  }

  /// At boot, before the router reads [readBlocked], on iOS only: a block
  /// the Keychain kept across a reinstall is copied back to prefs (over a missing or
  /// expired prefs copy, never over one still in force); an expired Keychain
  /// copy is removed, and so is the prefs copy, but only when it has expired
  /// too (a re-block whose Keychain write failed stays in force). The caller
  /// bounds it; it never throws.
  ///
  /// Accepted limit (review M-8; the spec has no tamper requirement): both
  /// copies are compared with the device clock, so moving the clock 30 days
  /// forward and relaunching ends a block early, much like an Android
  /// reinstall with no backup.
  static Future<void> restoreBlock(
    SharedPreferences prefs, {
    FlutterSecureStorage? secure,
    DateTime Function()? now,
    TargetPlatform? platform,
  }) async {
    // Android's keystore file is excluded from backup (P-10), so it never
    // outlives a reinstall and holds nothing to restore; its carrier is the
    // prefs copy. Not opening it keeps the keystore off every Android cold
    // start, flag on or off (batch 2 review I-1).
    if ((platform ?? defaultTargetPlatform) != TargetPlatform.iOS) return;
    final storage = secure ?? defaultSecure;
    final at = (now ?? DateTime.now)();
    try {
      final stored = await storage.read(key: _secureBlockKey);
      final until = DateTime.tryParse(stored ?? '');
      if (until == null) return;
      if (!at.isBefore(until)) {
        await storage.delete(key: _secureBlockKey);
        if (!readBlocked(prefs, at)) await prefs.remove(blockUntilKey);
        return;
      }
      if (!readBlocked(prefs, at)) {
        await prefs.setString(blockUntilKey, stored!);
      }
    } catch (error) {
      debugPrint('[age-gate] block restore skipped: ${error.runtimeType}');
    }
  }
}

final ageGateStoreProvider = Provider<AgeGateStore>(
  (ref) => AgeGateStore(ref.watch(sharedPreferencesProvider)),
);

import 'package:attune/features/safety/domain/safety_pin.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The safety keys' own Android keystore file (excluded from backups): a
/// keystore reset (resetOnError) then wipes only these, never the chat cache
/// key, the map store or the game outbox (Spec 2 review I-4).
const safetyKeystoreFile = 'attune_safety';

String _hashInIsolate(String pin) => hashPin(pin);
bool _verifyInIsolate((String, String) a) => verifyPinHash(a.$1, a.$2);

/// The PIN, its failure count and the "every open" choice, in the OS keystore
/// on this device only (never synced; excluded from Android backups).
class SafetyPinStore {
  SafetyPinStore({
    FlutterSecureStorage? storage,
    DateTime Function()? clock,
    Future<String> Function(String pin)? hasher,
    Future<bool> Function(String pin, String encoded)? verifier,
  }) : _storage = storage ?? defaultStorage,
       _clock = clock ?? DateTime.now,
       _hasher = hasher ?? ((pin) => compute(_hashInIsolate, pin)),
       _verifier =
           verifier ?? ((pin, e) => compute(_verifyInIsolate, (pin, e)));

  /// resetOnError: a keystore that can't be read (say, after a restore) is
  /// wiped and reads back nothing or a non-hash string. Neither counts as a
  /// PIN, and the prefs sentinel then reports the store corrupt, which the
  /// lock gate answers by signing out (review C2, I-4).
  static const defaultStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
      resetOnError: true,
      sharedPreferencesName: safetyKeystoreFile,
    ),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );
  static final instance = SafetyPinStore();

  static const _hashKey = 'safety_pin_hash';
  static const _failuresKey = 'safety_pin_failures';
  static const _retryAtKey = 'safety_pin_retry_at';
  static const _lastFailureKey = 'safety_pin_last_failure_at';
  static const _everyOpenKey = 'safety_pin_every_open';

  /// Outside the keystore, so a keystore that lost the PIN can be told apart
  /// from one that never had it (review I-4). Not secret: it says only that
  /// a PIN was set on this phone.
  static const expectedKey = 'safety_pin_expected';

  final FlutterSecureStorage _storage;
  final DateTime Function() _clock;
  final Future<String> Function(String pin) _hasher;
  final Future<bool> Function(String pin, String encoded) _verifier;

  DateTime _now() => _clock().toUtc();

  Future<DateTime?> _readTime(String key) async {
    final raw = await _storage.read(key: key);
    final ms = raw == null ? null : int.tryParse(raw);
    return ms == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
  }

  Future<void> _writeTime(String key, DateTime t) =>
      _storage.write(key: key, value: '${t.millisecondsSinceEpoch}');

  Future<int> _failures() async =>
      int.tryParse(await _storage.read(key: _failuresKey) ?? '') ?? 0;

  /// Only a well-formed hash is a PIN: a reset keystore can read back a
  /// placeholder string (review I-4).
  Future<bool> hasPin() async {
    final hash = await _storage.read(key: _hashKey);
    return hash != null &&
        hash.startsWith('v1\$') &&
        hash.split('\$').length == 4;
  }

  /// A PIN was set here but the keystore no longer holds it: a keystore
  /// reset, or a backup restored to a new phone.
  Future<bool> isCorrupt() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getBool(expectedKey) ?? false) && !await hasPin();
  }

  Future<void> setPin(String pin) async {
    if (!isValidPin(pin)) throw ArgumentError('pin');
    await _storage.write(key: _hashKey, value: await _hasher(pin));
    await (await SharedPreferences.getInstance()).setBool(expectedKey, true);
    for (final k in [_failuresKey, _retryAtKey, _lastFailureKey]) {
      await _storage.delete(key: k);
    }
  }

  /// When the next attempt is allowed, or null if now.
  Future<DateTime?> retryAt() async {
    final at = await _readTime(_retryAtKey);
    if (at == null) return null;
    return _now().isBefore(at) ? at : null;
  }

  Future<({PinCheck result, DateTime? retryAt})> check(String pin) async {
    final now = _now();
    final failures = await _failures();
    // The phone's clock moved back past the last miss: restart the wait
    // from now rather than letting it lapse (review I4). A forward jump
    // can't be told apart offline.
    final last = await _readTime(_lastFailureKey);
    if (last != null && now.isBefore(last) && failures >= 5) {
      final at = now.add(safetyPinDelayAfter(failures));
      await _writeTime(_retryAtKey, at);
      await _writeTime(_lastFailureKey, now);
      return (result: PinCheck.waiting, retryAt: at);
    }
    final wait = await _readTime(_retryAtKey);
    if (wait != null && now.isBefore(wait)) {
      return (result: PinCheck.waiting, retryAt: wait);
    }
    final hash = await _storage.read(key: _hashKey);
    if (hash != null && await _verifier(pin, hash)) {
      for (final k in [_failuresKey, _retryAtKey, _lastFailureKey]) {
        await _storage.delete(key: k);
      }
      return (result: PinCheck.ok, retryAt: null);
    }
    final next = failures + 1;
    await _storage.write(key: _failuresKey, value: '$next');
    await _writeTime(_lastFailureKey, now);
    final delay = safetyPinDelayAfter(next);
    if (delay == Duration.zero) return (result: PinCheck.wrong, retryAt: null);
    final at = now.add(delay);
    await _writeTime(_retryAtKey, at);
    return (result: PinCheck.wrong, retryAt: at);
  }

  Future<bool> everyOpen() async =>
      (await _storage.read(key: _everyOpenKey)) == 'true';

  Future<void> setEveryOpen(bool on) =>
      _storage.write(key: _everyOpenKey, value: on ? 'true' : 'false');

  Future<void> clearAll() async {
    for (final k in [
      _hashKey,
      _failuresKey,
      _retryAtKey,
      _lastFailureKey,
      _everyOpenKey,
    ]) {
      await _storage.delete(key: k);
    }
    await (await SharedPreferences.getInstance()).remove(expectedKey);
  }
}

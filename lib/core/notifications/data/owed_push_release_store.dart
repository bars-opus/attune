// lib/core/notifications/data/owed_push_release_store.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Plan 1b final review I1: a sign-out whose server unregister failed
/// (offline) leaves this phone's push subscription active on the server, and
/// no session remains to fix it later. Its subscription id is kept here as an
/// "owed release" and sent by OneSignalService on the next start or when the
/// network returns (release_push_subscription, callable signed out).
///
/// In the OS keystore, not SharedPreferences: the id is the device secret the
/// server treats as proof of possession, and sign-out's clearUserData()
/// wipes SharedPreferences right after the release is owed.
abstract class OwedPushReleaseStore {
  Future<String?> read();
  Future<void> write(String subscriptionId);
  Future<void> clear();
}

class SecureOwedPushReleaseStore implements OwedPushReleaseStore {
  SecureOwedPushReleaseStore({FlutterSecureStorage? storage})
    : _storage = storage ?? defaultStorage;

  /// Its own Android keystore file: a keystore reset (resetOnError) loses
  /// only this id, never the chat cache key or the Safety PIN.
  static const defaultStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
      resetOnError: true,
      sharedPreferencesName: 'attune_push',
    ),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  static const _key = 'owed_push_release';

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read() async {
    final value = await _storage.read(key: _key);
    return value == null || value.isEmpty ? null : value;
  }

  @override
  Future<void> write(String subscriptionId) =>
      _storage.write(key: _key, value: subscriptionId);

  @override
  Future<void> clear() => _storage.delete(key: _key);
}

final owedPushReleaseStoreProvider = Provider<OwedPushReleaseStore>(
  (ref) => SecureOwedPushReleaseStore(),
);

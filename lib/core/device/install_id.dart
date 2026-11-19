// Spec 2 W4b (§3.3.4, §7.2 S19, C-5): this install's random 128-bit id, as
// 32 lowercase hex characters, created at first launch for everyone (so
// its presence says nothing about Dating) under the neutral key
// attune.install_id, in the safety keystore (Android Keystore, excluded
// from backups; iOS Keychain first_unlock_this_device, not migrated to a
// new phone). Neither sign-out nor quick exit clears it: it names the
// phone, not the person. A new phone or one restored from a backup gets a
// new one and re-verifies for Dating (the id is never migrated); on iOS
// the Keychain keeps it across deleting and reinstalling Attune, and a
// keystore reset after a phone or app problem makes a new one. Only the Dating client sends it
// (S-7); the server keeps a hash. Never throws: a keystore that can't be
// read or written answers null (the Dating client then sends no header,
// and the server answers reverify_device).
import 'dart:math';

import 'package:attune/features/safety/data/safety_pin_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class InstallIdStore {
  InstallIdStore({FlutterSecureStorage? storage, Random? random})
    : _storage = storage ?? SafetyPinStore.defaultStorage,
      _random = random ?? Random.secure();

  final FlutterSecureStorage _storage;
  final Random _random;
  Future<String?>? _id;

  static const key = 'attune.install_id';
  static final _valid = RegExp(r'^[0-9a-f]{32}$');

  /// The id, created the first time; the same answer for the life of
  /// this store once one is known.
  Future<String?> ensure() => _id ??= _readOrCreate();

  Future<String?> _readOrCreate() async {
    try {
      final stored = await _storage.read(key: key);
      if (stored != null && _valid.hasMatch(stored)) return stored;
      final id =
          [
            for (var i = 0; i < 16; i++)
              _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
          ].join();
      await _storage.write(key: key, value: id);
      return id;
    } catch (_) {
      _id = null; // asked again next time
      return null;
    }
  }
}

final installIdStoreProvider = Provider<InstallIdStore>(
  (ref) => InstallIdStore(),
);

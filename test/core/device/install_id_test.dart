// Spec 2 W4b (§3.3.4, C-5): the install's id: 32 lowercase hex characters,
// made once and then the same; a value that isn't one is replaced; a
// keystore that fails answers null, and the next ask tries again.
import 'dart:math';

import 'package:attune/core/device/install_id.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

class _Broken extends FlutterSecureStorage {
  const _Broken();
  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) => Future.error(StateError('keystore'));
}

/// Fails its first read, then reads the real (mock) store.
class _BrokenOnce extends FlutterSecureStorage {
  _BrokenOnce();
  var failed = false;
  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) {
    if (!failed) {
      failed = true;
      return Future.error(StateError('keystore'));
    }
    return super.read(key: key);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test('made once, 32 hex characters, under the neutral key', () async {
    final store = InstallIdStore(random: Random(7));
    final id = await store.ensure();
    expect(id, matches(RegExp(r'^[0-9a-f]{32}$')));
    expect(await store.ensure(), id);
    expect(await InstallIdStore().ensure(), id, reason: 'read back');
    final all = await const FlutterSecureStorage().readAll();
    expect(all.keys, [InstallIdStore.key]);
    expect(InstallIdStore.key, 'attune.install_id');
    expect(InstallIdStore.key.toLowerCase(), isNot(contains('dating')));
  });

  test('a stored value that is not an id is replaced', () async {
    FlutterSecureStorage.setMockInitialValues({
      InstallIdStore.key: 'DATING-NOT-AN-ID',
    });
    final id = await InstallIdStore().ensure();
    expect(id, matches(RegExp(r'^[0-9a-f]{32}$')));
    expect(
      (await const FlutterSecureStorage().readAll())[InstallIdStore.key],
      id,
    );
  });

  test('a keystore that fails answers null', () async {
    expect(await InstallIdStore(storage: const _Broken()).ensure(), isNull);
  });

  test('after a failure the next ask tries again', () async {
    final store = InstallIdStore(storage: _BrokenOnce());
    expect(await store.ensure(), isNull);
    expect(await store.ensure(), matches(RegExp(r'^[0-9a-f]{32}$')));
  });
}

// Spec 1 W3b (§5.8, D19): the Dating lock is a protective, sign-out-only
// wipe: sign-out clears it, quick exit keeps it, the Safety PIN stays.
import 'package:attune/app/device_wipes.dart';
import 'package:attune/core/device/device_wipe_registry.dart';
import 'package:attune/features/safety/data/dating_lock_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('the lock entry is protective and sign-out only', () {
    final registry = DeviceWipeRegistry();
    registerDeviceWipes(registry);
    final lock = registry.entries.firstWhere(
      (e) => e.id == 'spec1.dating_lock',
    );
    expect(lock.protective, isTrue);
    expect(lock.moments, {WipeMoment.signOut});
    expect(lock.keys, {'me_section_lock'});
  });

  test('sign-out clears the lock; the Safety PIN stays', () async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({
      'me_section_lock': 'on',
      'safety_pin_hash': 'kept',
    });
    final registry = DeviceWipeRegistry();
    registerDeviceWipes(registry);
    await registry.run(WipeMoment.signOut);
    expect(await DatingLockStore().isOn(), isFalse);
    expect(
      await const FlutterSecureStorage().read(key: 'safety_pin_hash'),
      'kept',
    );
  });

  test('quick exit keeps the Dating lock (D19)', () async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({'me_section_lock': 'on'});
    final registry = DeviceWipeRegistry();
    registerDeviceWipes(registry);
    await registry.run(WipeMoment.quickExit);
    expect(await DatingLockStore().isOn(), isTrue);
  });

  test('a sign-out resets the lock in this process too; the next account '
      'and a cold start read storage (I-1)', () async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    final user = StateProvider<String?>((ref) => 'u1');
    ProviderContainer start() => ProviderContainer(
      overrides: [
        datingLockAccountProvider.overrideWith(
          (ref) => Stream.value(ref.watch(user)),
        ),
      ],
    );
    final container = start();
    addTearDown(container.dispose);
    container.listen(datingLockProvider, (_, __) {});
    await container.read(datingLockProvider.future);
    await container.read(datingLockProvider.notifier).set(true);
    expect(await container.read(datingLockProvider.future), isTrue);

    final registry = DeviceWipeRegistry();
    registerDeviceWipes(registry);
    await registry.run(WipeMoment.signOut);
    container.read(user.notifier).state = null;
    await pumpEventQueue();
    container.read(user.notifier).state = 'u2';
    await pumpEventQueue();
    expect(await container.read(datingLockProvider.future), isFalse);

    final cold = start();
    addTearDown(cold.dispose);
    expect(await cold.read(datingLockProvider.future), isFalse);
  });
}

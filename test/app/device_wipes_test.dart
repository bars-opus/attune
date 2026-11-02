// Spec 1 W3a (§5.8): Spec 1's device wipes. The home-state cache goes on
// sign-out for every account on the phone, and nothing else with it; no
// quick-exit entry touches a protective setting (the Dating lock, the
// Safety PIN).
import 'package:attune/app/device_wipes.dart';
import 'package:attune/core/device/device_wipe_registry.dart';
import 'package:attune/core/services/shared_preferences_service.dart';
import 'package:attune/features/onboarding/data/home_state_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/protective_device_keys.dart';

void main() {
  test('Spec 1 registers its entries once, each valid', () {
    final registry = DeviceWipeRegistry();
    registerDeviceWipes(registry);
    expect(
      registry.entries.map((e) => e.id),
      contains('spec1.home_state_cache'),
    );
    final home = registry.entries.firstWhere(
      (e) => e.id == 'spec1.home_state_cache',
    );
    expect(home.moments, {WipeMoment.signOut});
  });

  test(
    'sign-out removes every account\'s home-state cache and nothing else',
    () async {
      SharedPreferences.setMockInitialValues({
        HomeStateStore.keyFor('u1'): '{}',
        HomeStateStore.keyFor('u2'): '{}',
        'attune.home.u1.other': 'kept',
        'safety_pin_expected': true,
        // Preflight F-9: everything sign-out keeps (W2's age gate and
        // public config, W3's signed-in flags), from its own list.
        for (final key in PreferencesService.keptKeys) key: 'kept',
        // Review #5: the per-account keys kept by prefix too.
        for (final prefix in PreferencesService.keptPrefixes)
          '${prefix}u1': 'kept',
      });
      final registry = DeviceWipeRegistry();
      registerDeviceWipes(registry);
      await registry.run(WipeMoment.signOut);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys(), {
        'attune.home.u1.other',
        'safety_pin_expected',
        ...PreferencesService.keptKeys,
        for (final prefix in PreferencesService.keptPrefixes) '${prefix}u1',
      });
    },
  );

  test('no quick-exit entry touches a protective key; none is protective', () {
    final registry = DeviceWipeRegistry();
    registerDeviceWipes(registry);
    for (final entry in registry.entries) {
      if (!entry.moments.contains(WipeMoment.quickExit)) continue;
      expect(entry.protective, isFalse, reason: entry.id);
      expect(
        entry.keys.intersection(protectiveKeys),
        isEmpty,
        reason: entry.id,
      );
    }
    for (final entry in registry.entries.where((e) => e.protective)) {
      expect(
        entry.moments,
        isNot(contains(WipeMoment.quickExit)),
        reason: entry.id,
      );
    }
  });

  test('no Spec 1 device key names Dating (D20)', () {
    final registry = DeviceWipeRegistry();
    registerDeviceWipes(registry);
    for (final entry in registry.entries) {
      for (final key in entry.keys) {
        expect(key.toLowerCase(), isNot(contains('dating')), reason: entry.id);
      }
    }
  });
}

// Sync audit (2026-10-18): signing out or deleting the account clears the
// couple map's device data (home area, last pin choice, tile cache of the
// partner's area, pin faces), as quick exit does; the next account on the
// phone must not inherit it.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final path in [
    'lib/features/safety/data/safety_sign_out.dart',
    'lib/features/auth/presentation/widgets/logout_action.dart',
    'lib/features/settings/widgets/delete_account_action.dart',
  ]) {
    test('$path clears the couple map with the other device surfaces', () {
      final src = File(path).readAsStringSync();
      expect(src, contains('clearCoupleMapDeviceData('));
      expect(
        src.indexOf('clearCoupleMapDeviceData('),
        lessThan(src.indexOf('.clearUserData()')),
        reason: 'before the prefs wipe, alongside clearTogetherDeviceSurfaces',
      );
    });
  }

  // Sync audit: the home area never leaves this phone through iCloud
  // Keychain (as the safety PIN and chat cache already do).
  test('the couple map keeps its secrets on this device only', () {
    final src = File(
      'lib/features/couple_map/data/couple_map_local_store.dart',
    ).readAsStringSync();
    expect(src, contains('KeychainAccessibility.first_unlock_this_device'));
    expect(src.contains('KeychainAccessibility.first_unlock)'), isFalse);
  });
}

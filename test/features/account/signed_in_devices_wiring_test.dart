// Spec 2 (research 06 §3 F7 (1)): Where you're signed in is reachable from
// Settings → Account.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

void main() {
  test('the router serves /settings/signed-in-devices as signedInDevices', () {
    final src = _read('lib/app/routing/app_router.dart');
    expect(
      src,
      contains(
        "static const String signedInDevices = '/settings/signed-in-devices';",
      ),
    );
    expect(src, contains("name: 'signedInDevices'"));
    expect(src, contains('const SignedInDevicesScreen()'));
  });

  // Settings regrouped (2026-10-18): it leads Privacy & your data
  // (settings_layout_test checks the sections against the real data).
  test('Settings → Privacy & your data lists it first', () {
    final src = _read('lib/features/settings/data/settings_data.dart');
    final privacy = src.indexOf("id: 'privacy'");
    final devices = src.indexOf("id: 'signed_in_devices'");
    expect(privacy, greaterThan(-1));
    expect(devices, greaterThan(privacy));
    expect(src.indexOf("id: 'care'"), greaterThan(devices));
    expect(src, contains("routeName: '/settings/signed-in-devices'"));
    final row = src.substring(devices, src.indexOf('),', devices));
    expect(row, contains('order: 1,'), reason: 'review M-5: its own slot');
  });
}

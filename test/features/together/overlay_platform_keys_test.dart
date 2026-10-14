// Free time together reads the phone calendar through device_calendar_plus.
// Its Android side refuses unless BOTH calendar permissions are declared
// (PermissionService.checkPermissionsDeclared), and iOS 17 needs the
// full-access usage string. Fakes can't see this, so pin the files.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android declares what the calendar plugin checks for', () {
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    expect(manifest, contains('android.permission.READ_CALENDAR'));
    expect(manifest, contains('android.permission.WRITE_CALENDAR'));
  });

  test('iOS explains full calendar access (iOS 17) and older iOS', () {
    final plist = File('ios/Runner/Info.plist').readAsStringSync();
    expect(plist, contains('NSCalendarsFullAccessUsageDescription'));
    expect(plist, contains('NSCalendarsUsageDescription'));
  });
}

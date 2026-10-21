// test/core/ios_push_capability_test.dart
//
// Chat review #13 (07 H-1): the iOS app was built without the
// aps-environment entitlement, so iOS refused registerForRemoteNotifications
// ("no valid 'aps-environment' entitlement string found") and no iPhone
// could ever receive a push. Same shape as android_manifest_test.dart:
// fakes cannot see these files, so pin them.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('iOS can register with APNs: aps-environment entitlement', () {
    final entitlements =
        File('ios/Runner/Runner.entitlements').readAsStringSync();
    expect(entitlements, contains('<key>aps-environment</key>'));
    // development in the repo; Xcode rewrites it to production when
    // exporting with a distribution profile.
    expect(
      entitlements,
      anyOf(
        contains('<string>development</string>'),
        contains('<string>production</string>'),
      ),
    );
  });

  test('iOS declares background remote notifications', () {
    final plist = File('ios/Runner/Info.plist').readAsStringSync();
    expect(plist, contains('<key>UIBackgroundModes</key>'));
    expect(plist, contains('<string>remote-notification</string>'));
  });

  test('the Runner target signs with the entitlements file that carries it', () {
    final pbx = File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync();
    expect(pbx, contains('CODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements;'));
  });

  test('Android 13+ can be asked for notifications (#15)', () {
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    expect(manifest, contains('android.permission.POST_NOTIFICATIONS'));
  });
}

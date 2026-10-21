// test/core/notifications/push_permission_policy_test.dart
//
// Chat review #15 (07 M-5): the OS prompt was requested only on iOS, at app
// start. Android 13+ shows no dialog unless asked, so Android phones never
// received a push. The prompt now goes to a signed-in person with the app
// open, once per run, on both platforms.
import 'package:attune/app/routing/app_router.dart' show RouteNames;
import 'package:attune/core/notifications/services/push_permission_policy.dart';
import 'package:attune/features/safety/presentation/safety_lock_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  bool ask({
    bool signedIn = true,
    SafetyLockState lock = SafetyLockState.open,
    bool alreadyGranted = false,
    bool osCanPrompt = true,
    bool askedThisRun = false,
    String path = '/home',
  }) => shouldAskForPushPermission(
    signedIn: signedIn,
    lock: lock,
    path: path,
    alreadyGranted: alreadyGranted,
    osCanPrompt: osCanPrompt,
    askedThisRun: askedThisRun,
  );

  test('a signed-in person with the app open is asked once', () {
    expect(ask(), isTrue);
    expect(ask(askedThisRun: true), isFalse);
  });

  test('never before sign-in', () {
    expect(ask(signedIn: false), isFalse);
  });

  test('never over the Safety lock or while it is still deciding', () {
    expect(ask(lock: SafetyLockState.locked), isFalse);
    expect(ask(lock: SafetyLockState.checking), isFalse);
  });

  // Quick exit only navigates to the decoy; the lock stays open (Spec 2).
  test('never over the quick-exit decoy', () {
    expect(ask(path: RouteNames.neutralScreen), isFalse);
  });

  test(
    'not when already granted, nor once the OS stopped offering the prompt',
    () {
      expect(ask(alreadyGranted: true), isFalse);
      expect(ask(osCanPrompt: false), isFalse);
    },
  );
}

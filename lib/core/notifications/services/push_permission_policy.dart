// lib/core/notifications/services/push_permission_policy.dart
import 'package:attune/features/safety/presentation/safety_lock_controller.dart';

/// When to show the OS notification prompt, on both platforms (Android 13+
/// shows nothing until asked; chat review #15). Once per app run, to a
/// signed-in person with the app open: never before sign-in, never over
/// the Safety lock or the quick-exit decoy (Spec 2 -- the same rule as a
/// foreground banner), and not once the OS has stopped offering the dialog
/// (a person who said no is not nagged; Settings is theirs). A postponed
/// ask happens on the next trigger (lock change, sign-in).
bool shouldAskForPushPermission({
  required bool signedIn,
  required SafetyLockState lock,
  required String path,
  required bool alreadyGranted,
  required bool osCanPrompt,
  required bool askedThisRun,
}) =>
    signedIn &&
    !shouldSuppressForegroundPush(lock, path) &&
    !alreadyGranted &&
    osCanPrompt &&
    !askedThisRun;

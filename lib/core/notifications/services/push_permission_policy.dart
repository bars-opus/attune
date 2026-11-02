// lib/core/notifications/services/push_permission_policy.dart
import 'package:attune/features/onboarding/domain/home_state.dart';
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

/// Where Spec 1 asks for notifications in context (§2.4): R2 "a heads-up
/// when your partner joins", R4 "when they message you" (W4b), J3 the
/// journal reminder. Each is one line of reason and one "Turn on".
enum PushAskContext { r2, r4, j3 }

/// What a contextual ask came to.
enum PushAskOutcome { granted, declined, openedSettings, unavailable }

/// Spec 1 W3c (§2.4): whether the automatic ask after sign-in may run.
/// Today's rule with flow_paths_v2 off. Under it the prompt is asked only
/// in context, except for a linked or paused couple while flow_couples_v2
/// is off: R4, the couples' context, exists only under that flag (W3 plan
/// P-24), so until then they keep today's ask. An unknown link is no ask.
bool automaticPushAskAllowed({
  required bool pathsV2,
  required bool couplesV2,
  required LinkState? link,
}) =>
    !pathsV2 ||
    (!couplesV2 && (link == LinkState.linked || link == LinkState.paused));

import 'package:attune/core/services/app_privacy_cover.dart';
import 'package:attune/features/account/presentation/new_device_notice.dart';
import 'package:attune/features/relationships/presentation/widgets/relationship_lifecycle_watcher.dart';
import 'package:attune/features/safety/presentation/widgets/quick_exit_zone.dart';
import 'package:attune/features/safety/presentation/widgets/safety_lock_gate.dart';
import 'package:attune/features/together/presentation/widgets/share_intake_listener.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Everything MaterialApp.router's builder wraps around every route (Spec 2).
/// Above the Navigator, so it covers every route, dialog and sheet.
///   ShareIntakeListener  -- outside: a share can arrive while covered.
///   SafetyLockGate       -- replaces everything while the PIN is required.
///   AppPrivacyCover      -- neutral cover while inactive.
///   QuickExitZone        -- the triple-tap target, on top of everything.
///   NewDeviceNotice      -- the "a new device signed in" banner.
///   RelationshipLifecycleWatcher -- after a pause or an ending, clears this
///                          phone's Together surfaces and shows the ending
///                          sheet once (Spec 3a).
Widget appShell({required GoRouter router, required Widget child}) {
  return ShareIntakeListener(
    onShare: () => showTogetherForShare(router),
    child: SafetyLockGate(
      child: AppPrivacyCover(
        child: QuickExitZone(
          router: router,
          child: NewDeviceNotice(
            router: router,
            child: RelationshipLifecycleWatcher(
              router: router,
              child: MediaQuery.withClampedTextScaling(
                maxScaleFactor: 1.0,
                child: child,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

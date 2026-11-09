// Spec 2 W3a Task 4 fix round 1 (Minor 8): quick exit from Dating settings
// and from the not-open screen leaves the decoy, the unlock gone, and
// nothing of either screen in the tree.
import 'package:attune/core/device/device_wipe_registry.dart';
import 'package:attune/features/dating/dating_device_wipes.dart';
import 'package:attune/features/dating/lock/dating_unlock.dart';
import 'package:attune/features/dating/not_open/dating_not_open_screen.dart';
import 'package:attune/features/dating/routes/dating_routes.dart';
import 'package:attune/features/dating/settings/dating_settings_screen.dart';
import 'package:attune/features/safety/domain/services/quick_exit_service.dart';
import 'package:attune/features/safety/presentation/widgets/quick_exit_zone.dart';
import 'package:attune/features/stories/data/story_device_wipe.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/dating_shell.dart';

void main() {
  setUpAll(() => registerDatingDeviceWipes(DeviceWipeRegistry.instance));
  setUp(() {
    QuickExitService.clearStories = () async {};
    addTearDown(() => QuickExitService.clearStories = clearStoryDeviceCaches);
  });

  for (final (path, screen) in [
    (DatingPaths.settings, DatingSettingsScreen),
    (DatingPaths.notOpenFor(country: 'NG'), DatingNotOpenScreen),
  ]) {
    testWidgets('quick exit from $path', (t) async {
      final s = await pumpDatingShell(
        t,
        initial: path,
        locked: true,
        wrap: (router, child) => QuickExitZone(router: router, child: child),
      );
      expect(find.byType(screen), findsOneWidget);
      expect(s.container.read(datingUnlockedProvider), isTrue);
      for (var i = 0; i < 3; i++) {
        await t.tap(
          find.byKey(const Key('quick_exit_zone')),
          warnIfMissed: false,
        );
        await t.pump(const Duration(milliseconds: 50));
      }
      await t.pumpAndSettle(const Duration(milliseconds: 400));
      expect(find.text('DECOY'), findsOneWidget);
      expect(find.byType(screen, skipOffstage: false), findsNothing);
      expect(s.container.read(datingUnlockedProvider), isFalse);
      expect(s.lock.on, isTrue);
    });
  }
}

// Spec 1 W3a (§5.6 R18, §5.8, D19): quick exit runs the registry's
// quick-exit entries after the cover is up, still leaves, and never clears
// a protective setting (the Safety PIN, and from W3b the Dating lock).
import 'dart:async';

import 'package:attune/core/device/device_wipe_registry.dart';
import 'package:attune/features/safety/domain/services/quick_exit_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets(
    'quick-exit entries run, sign-out ones do not; the app still leaves',
    (t) async {
      SharedPreferences.setMockInitialValues({'safety_pin_expected': true});
      FlutterSecureStorage.setMockInitialValues({
        'safety_pin_hash': r'v1$a$b$c',
      });
      final events = <String>[];
      // Review #8: where the app is when the entry runs (the cover first).
      final pathsAtWipe = <String>[];
      late final GoRouter router;
      QuickExitService.exitOverride = () async => events.add('exit');
      final registry = DeviceWipeRegistry.instance;
      addTearDown(() {
        QuickExitService.exitOverride = null;
        registry.clear();
      });
      registry
        ..clear()
        ..register(
          DeviceWipeEntry(
            id: 'probe.exit',
            moments: const {WipeMoment.quickExit},
            run: () async {
              pathsAtWipe.add(
                router.routerDelegate.currentConfiguration.uri.path,
              );
              events.add('wiped on exit');
            },
          ),
        )
        ..register(
          DeviceWipeEntry(
            id: 'probe.signout',
            moments: const {WipeMoment.signOut},
            run: () async => events.add('sign-out only'),
          ),
        );
      router = GoRouter(
        routes: [
          GoRoute(path: '/', builder: (_, __) => const Text('HOME')),
          GoRoute(
            path: '/neutralScreen',
            name: 'neutralScreen',
            builder: (_, __) => const Text('DECOY'),
          ),
        ],
      );
      addTearDown(router.dispose);
      await t.pumpWidget(MaterialApp.router(routerConfig: router));
      await t.runAsync(() => QuickExitService.executeWithRouter(router));
      await t.pumpAndSettle();
      expect(find.text('DECOY'), findsOneWidget);
      expect(events, ['wiped on exit', 'exit']);
      expect(pathsAtWipe, ['/neutralScreen'], reason: 'after the cover');

      // The protective settings are where they were.
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('safety_pin_expected'), isTrue);
      expect(
        await const FlutterSecureStorage().read(key: 'safety_pin_hash'),
        r'v1$a$b$c',
      );
    },
  );

  testWidgets(
    'quick exit never waits for a wipe: a hanging entry adds nothing',
    (t) async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      final events = <String>[];
      QuickExitService.exitOverride = () async => events.add('exit');
      final hang = Completer<void>();
      final registry = DeviceWipeRegistry.instance;
      addTearDown(() {
        QuickExitService.exitOverride = null;
        if (!hang.isCompleted) hang.complete();
        registry.clear();
      });
      registry
        ..clear()
        ..register(
          DeviceWipeEntry(
            id: 'probe.hang',
            moments: const {WipeMoment.quickExit},
            bound: DeviceWipeRegistry.maxBound,
            run: () {
              events.add('wipe started');
              return hang.future;
            },
          ),
        );
      final router = GoRouter(
        routes: [
          GoRoute(path: '/', builder: (_, __) => const Text('HOME')),
          GoRoute(
            path: '/neutralScreen',
            name: 'neutralScreen',
            builder: (_, __) => const Text('DECOY'),
          ),
        ],
      );
      addTearDown(router.dispose);
      await t.pumpWidget(MaterialApp.router(routerConfig: router));
      final clock = Stopwatch()..start();
      await t.runAsync(() => QuickExitService.executeWithRouter(router));
      clock.stop();
      expect(events, ['wipe started', 'exit']);
      // The exit's own floor is 300 ms; an awaited wipe would add its 2 s
      // bound to it.
      expect(clock.elapsed, lessThan(const Duration(milliseconds: 1500)));
      hang.complete();
      await t.pumpAndSettle();
      expect(find.text('DECOY'), findsOneWidget);
    },
  );
}

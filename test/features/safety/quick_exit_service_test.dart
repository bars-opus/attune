// Spec 2 review C3: the quick-exit flag is written before Attune leaves, even
// when the keystore is slow (low-end Android), so a kill during the decoy
// still comes back locked.
import 'package:attune/features/safety/domain/services/quick_exit_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _SlowStorage extends FlutterSecureStorage {
  _SlowStorage(this.events);
  final List<String> events;

  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 500));
    events.add('flag written');
  }
}

void main() {
  testWidgets('the flag is written before the app leaves', (t) async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    final events = <String>[];
    QuickExitService.storage = _SlowStorage(events);
    QuickExitService.exitOverride = () async => events.add('exit');
    addTearDown(() {
      QuickExitService.storage = QuickExitService.defaultStorage;
      QuickExitService.exitOverride = null;
    });
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
    await t.pumpWidget(MaterialApp.router(routerConfig: router));
    await t.runAsync(() => QuickExitService.executeWithRouter(router));
    await t.pumpAndSettle();
    expect(find.text('DECOY'), findsOneWidget);
    expect(events, ['flag written', 'exit']);
  });

  test('the flag is mirrored outside the keystore, so a keystore reset '
      'cannot lose it (review I-4)', () async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    QuickExitService.exitOverride = () async {};
    addTearDown(() => QuickExitService.exitOverride = null);
    await QuickExitService.markSafetyUnlockRequired();
    await QuickExitService.storage.delete(key: 'safety_requires_unlock');
    expect(await QuickExitService.requiresSafetyUnlock(), isTrue);
    await QuickExitService.clearSafetyUnlockRequired();
    expect(await QuickExitService.requiresSafetyUnlock(), isFalse);
  });
}

// Spec 1 W3b (§3.9): Settings -> Safety -> "Dating lock" shows only for the
// Dating path or an enrollment (from the live home state); turning it on
// with no Safety PIN opens the PIN setup first and stays off without one.
import 'package:attune/core/providers/shared_prefs_provider.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_colors.dart';
import 'package:attune/features/me/presentation/widgets/dating_lock_setting.dart';
import 'package:attune/features/onboarding/domain/home_state.dart';
import 'package:attune/features/onboarding/presentation/providers/flow_flags.dart';
import 'package:attune/features/onboarding/presentation/providers/home_state_providers.dart';
import 'package:attune/features/safety/data/dating_lock_store.dart';
import 'package:attune/features/safety/data/safety_pin_store.dart';
import 'package:attune/features/safety/domain/safety_pin.dart';
import 'package:attune/features/safety/presentation/screens/safety_pin_screen.dart';
import 'package:attune/features/settings/models/settings_config.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_home_state.dart';

Future<(ProviderContainer, GoRouter, List<SettingsConfig?>)> _pump(
  WidgetTester tester,
  Map<String, dynamic> json,
) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final rows = <SettingsConfig?>[];
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      flowPathsV2Provider.overrideWithValue(true),
    ],
  );
  addTearDown(container.dispose);
  await container
      .read(homeStateProvider('u1').notifier)
      .apply(HomeState.fromJson(json));
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder:
            (_, __) => Consumer(
              builder: (context, ref, _) {
                final row = datingLockSetting(context, ref, 'u1');
                rows.add(row);
                return row == null
                    ? const Text('NO ROW')
                    : TextButton(
                      onPressed: () => row.onToggle!(true),
                      child: Text(row.title),
                    );
              },
            ),
      ),
      GoRoute(
        path: '/settings/safety-pin',
        builder: (_, __) => const Text('PIN SETUP'),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (container, router, rows);
}

void main() {
  testWidgets('hidden on Just for me; shown on Dating and while enrolled', (
    tester,
  ) async {
    await _pump(tester, homeJson(path: 'just_me'));
    expect(find.text('NO ROW'), findsOneWidget);
    await _pump(tester, homeJson(path: 'dating'));
    expect(find.text('Dating lock'), findsOneWidget);
    await _pump(tester, homeJson(path: 'relationship', datingEnrolled: true));
    expect(find.text('Dating lock'), findsOneWidget);
  });

  testWidgets('on with no PIN: the PIN setup first, and still off', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({});
    final (container, router, _) = await _pump(
      tester,
      homeJson(path: 'dating'),
    );
    await tester.tap(find.text('Dating lock'));
    await tester.pumpAndSettle();
    expect(find.text('PIN SETUP'), findsOneWidget);
    router.pop();
    await tester.pumpAndSettle();
    expect(await DatingLockStore().isOn(), isFalse);
  });

  testWidgets('on with a PIN: on, under the neutral key', (tester) async {
    FlutterSecureStorage.setMockInitialValues({'safety_pin_hash': r'v1$a$b$c'});
    await _pump(tester, homeJson(path: 'dating'));
    await tester.tap(find.text('Dating lock'));
    await tester.pumpAndSettle();
    expect(
      await const FlutterSecureStorage().read(key: 'me_section_lock'),
      'on',
    );
  });

  testWidgets('the row takes the theme accent, not a raw colour (M-5)', (
    tester,
  ) async {
    final (_, _, rows) = await _pump(tester, homeJson(path: 'dating'));
    expect(
      rows.last!.iconColor,
      flowAccent(tester.element(find.text('Dating lock'))),
    );
  });

  testWidgets('removing the Safety PIN turns the Dating lock off (M-3)', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({'me_section_lock': 'on'});
    SharedPreferences.setMockInitialValues({});
    final pins = SafetyPinStore(
      hasher: (p) async => hashPin(p, iterations: 1000),
      verifier: (p, e) async => verifyPinHash(p, e),
    );
    await pins.setPin('2468');
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.listen(datingLockProvider, (_, __) {});
    expect(await container.read(datingLockProvider.future), isTrue);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (_, __) => MaterialApp(home: SafetyPinScreen(store: pins)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove PIN'));
    await tester.pumpAndSettle();
    for (final d in '2468'.split('')) {
      await tester.tap(find.widgetWithText(InkResponse, d).first);
      await tester.pump();
    }
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(await pins.hasPin(), isFalse);
    expect(await DatingLockStore().isOn(), isFalse);
    expect(await container.read(datingLockProvider.future), isFalse);
  });
}

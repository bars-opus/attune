// Spec 2 W3: the app's Dating route group in a test router, every Dating
// gateway faked, and the places Dating sends people stubbed by name.
import 'package:attune/app/routing/app_router.dart' show RouteNames;
import 'package:attune/app/theme/app_theme.dart';
import 'package:attune/core/utils/screen_util_config.dart';
import 'package:attune/features/auth/providers/auth_provider.dart'
    show currentUserProvider;
import 'package:attune/features/dating/data/dating_providers.dart';
import 'package:attune/features/dating/gentle_wait/gentle_wait_providers.dart';
import 'package:attune/features/dating/gentle_wait/gentle_wait_repository.dart';
import 'package:attune/features/dating/routes/dating_routes.dart';
import 'package:attune/features/safety/data/dating_lock_store.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../helpers/home_harness.dart' show testUser;
import 'dating_fakes.dart';

class FakeLock extends DatingLockStore {
  FakeLock(this.on, {this.unreadable = false});

  bool on;
  final bool unreadable;

  @override
  Future<bool> isOn() async {
    if (unreadable) throw StateError('keystore');
    return on;
  }

  @override
  Future<void> setOn(bool value) async => on = value;
}

class FakeWait implements GentleWaitGateway {
  GentleWait value = GentleWait(
    endedAt: DateTime.utc(2026, 11, 1, 10),
    opensAt: DateTime.utc(2026, 12, 1, 10),
    answers: const {'q1': 'Patience with myself'},
  );
  Object? readError;
  GentleWaitSave result = GentleWaitSave.saved;
  final saves = <Map<String, String>>[];
  int reads = 0;
  int clears = 0;

  @override
  Future<GentleWait> read() async {
    reads++;
    final error = readError;
    if (error != null) throw error;
    return value;
  }

  @override
  Future<GentleWaitSave> save(Map<String, String> answers) async {
    saves.add(answers);
    return result;
  }

  @override
  Future<GentleWaitSave> clear() async {
    clears++;
    return result;
  }
}

/// The signed-in account in every Dating shell (D8 tests switch it).
final datingTestAccount = StateProvider<String?>((ref) => 'ama');

class DatingShell {
  DatingShell(
    this.tester,
    this.router,
    this.home,
    this.life,
    this.wait,
    this.lock,
  );

  final WidgetTester tester;
  final GoRouter router;
  final FakeDatingHomeGateway home;
  final FakeDatingLifecycleGateway life;
  final FakeWait wait;
  final FakeLock lock;

  String get location =>
      router.routerDelegate.currentConfiguration.uri.toString();

  ProviderContainer get container =>
      ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
}

Future<DatingShell> pumpDatingShell(
  WidgetTester t, {
  String initial = '/home',
  bool locked = false,
  bool lockUnreadable = false,
  bool pinSet = false,
  bool signedIn = true,
  bool online = true,
  double textScale = 1.0,
  FakeDatingHomeGateway? home,
  List<Override> overrides = const [],
  Widget Function(GoRouter router, Widget child)? wrap,
  List<RouteBase> extraRoutes = const [],
}) async {
  // A fresh ProviderScope each time (pumpWidget would reuse the last one).
  await t.pumpWidget(const SizedBox());
  t.view.physicalSize = const Size(390, 844);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  t.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(t.platformDispatcher.clearAllTestValues);
  SharedPreferences.setMockInitialValues({});
  FlutterSecureStorage.setMockInitialValues({
    // A well-formed hash is a PIN (SafetyPinStore.hasPin); never checked here.
    if (pinSet) 'safety_pin_hash': r'v1$c2FsdA$aGFzaA$100000',
  });
  final homeGateway = home ?? FakeDatingHomeGateway();
  final life = FakeDatingLifecycleGateway();
  final wait = FakeWait();
  final lock = FakeLock(locked, unreadable: lockUnreadable);
  final router = GoRouter(
    initialLocation: initial,
    routes: [
      GoRoute(
        path: RouteNames.home,
        builder:
            (_, s) => Scaffold(
              body: Text('ME ${s.uri.queryParameters['tab'] ?? ''}'),
            ),
      ),
      for (final (path, label) in [
        (RouteNames.login, 'LOGIN'),
        (RouteNames.safetyPin, 'PIN SETUP'),
        (RouteNames.howYouUseAttune, 'HOW YOU USE ATTUNE'),
        (RouteNames.reflectionJournal, 'JOURNAL'),
        (RouteNames.healingJourney, 'HEALING'),
      ])
        GoRoute(path: path, builder: (_, __) => Scaffold(body: Text(label))),
      GoRoute(
        path: RouteNames.neutralScreen,
        name: 'neutralScreen',
        builder: (_, __) => const Scaffold(body: Text('DECOY')),
      ),
      ...extraRoutes,
      ...datingRoutes(signedIn: () => signedIn),
    ],
  );
  addTearDown(router.dispose);
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        currentUserProvider.overrideWith((ref) {
          final id = ref.watch(datingTestAccount);
          return id == null ? null : testUser(id);
        }),
        datingAccountProvider.overrideWith(
          (ref) => ref.watch(datingTestAccount),
        ),
        gentleWaitAccountProvider.overrideWith(
          (ref) => ref.watch(datingTestAccount),
        ),
        datingLockStoreProvider.overrideWithValue(lock),
        datingLockAccountProvider.overrideWith(
          (ref) => Stream.value(ref.watch(datingTestAccount)),
        ),
        datingHomeGatewayProvider.overrideWithValue(homeGateway),
        datingLifecycleGatewayProvider.overrideWithValue(life),
        gentleWaitGatewayProvider.overrideWithValue(wait),
        datingOnlineProvider.overrideWith((ref) => Stream.value(online)),
        ...overrides,
      ],
      child: ScreenUtilConfig.builder(
        builder:
            (_) => MaterialApp.router(
              theme: AppTheme.lightTheme,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              routerConfig: router,
              builder:
                  (context, child) =>
                      wrap == null ? child! : wrap(router, child!),
            ),
      ),
    ),
  );
  await t.pumpAndSettle();
  return DatingShell(t, router, homeGateway, life, wait, lock);
}

/// The Dating overrides for a screen pumped alone (pumpFlowScreen).
List<Override> datingShellOverrides({
  FakeDatingHomeGateway? home,
  FakeDatingLifecycleGateway? life,
  FakeWait? wait,
  bool online = true,
}) => [
  currentUserProvider.overrideWith((ref) {
    final id = ref.watch(datingTestAccount);
    return id == null ? null : testUser(id);
  }),
  datingAccountProvider.overrideWith((ref) => ref.watch(datingTestAccount)),
  gentleWaitAccountProvider.overrideWith((ref) => ref.watch(datingTestAccount)),
  datingLockStoreProvider.overrideWithValue(FakeLock(false)),
  datingLockAccountProvider.overrideWith(
    (ref) => Stream.value(ref.watch(datingTestAccount)),
  ),
  datingHomeGatewayProvider.overrideWithValue(home ?? FakeDatingHomeGateway()),
  datingLifecycleGatewayProvider.overrideWithValue(
    life ?? FakeDatingLifecycleGateway(),
  ),
  gentleWaitGatewayProvider.overrideWithValue(wait ?? FakeWait()),
  datingOnlineProvider.overrideWith((ref) => Stream.value(online)),
];

/// The Dating section's overrides for a Spec 1 test that renders Me on the
/// Dating path (W3a: the slot's body is DatingSection).
List<Override> datingHomeOnlyOverrides({
  FakeDatingHomeGateway? home,
  String account = 'u-test',
}) => [
  datingAccountProvider.overrideWithValue(account),
  datingHomeGatewayProvider.overrideWithValue(home ?? FakeDatingHomeGateway()),
  datingLifecycleGatewayProvider.overrideWithValue(FakeDatingLifecycleGateway()),
  datingLockStoreProvider.overrideWithValue(FakeLock(false)),
  datingLockAccountProvider.overrideWith((ref) => Stream.value(account)),
  datingOnlineProvider.overrideWith((ref) => Stream.value(true)),
];

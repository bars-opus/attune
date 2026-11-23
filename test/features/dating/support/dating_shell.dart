// Spec 2 W3: the app's Dating route group in a test router, every Dating
// gateway faked, and the places Dating sends people stubbed by name.
import 'package:attune/app/routing/app_router.dart' show RouteNames;
import 'package:attune/app/theme/app_theme.dart';
import 'package:attune/core/utils/screen_util_config.dart';
import 'package:attune/features/auth/providers/auth_provider.dart'
    show currentUserProvider;
import 'package:attune/features/dating/chat/plan_meet_screen.dart'
    show datingNowProvider, datingPushAllowedProvider;
import 'package:attune/features/dating/data/dating_never_introduce.dart';
import 'package:attune/features/dating/data/dating_providers.dart';
import 'package:attune/features/dating/data/dating_supabase_client.dart'
    show datingDeviceReadyProvider;
import 'package:attune/features/dating/gentle_wait/gentle_wait_providers.dart';
import 'package:attune/features/dating/gentle_wait/gentle_wait_repository.dart';
import 'package:attune/features/dating/routes/dating_routes.dart';
import 'package:attune/features/dating/settings/dating_abroad.dart';
import 'package:attune/features/dating/verify/dating_verification.dart';
import 'package:attune/features/dating/verify/dating_verification_providers.dart';
import 'package:attune/features/dating/verify/dating_verification_repository.dart';
import 'package:attune/features/safety/data/dating_lock_store.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../helpers/home_harness.dart' show testUser;
import 'dating_chat_fakes.dart';
import 'dating_fakes.dart';
import 'dating_trip_fakes.dart';
import 'dating_verify_fakes.dart';

/// Spec 2 W4a: both checks passed, so D11 shows "You're verified." and
/// Continue moves on (the W3 tests walk through it).
const datingVerifiedState = DatingVerification(
  available: true,
  age: DatingCheck.pass,
  identity: DatingCheck.pass,
  photosReady: true,
);

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

/// Spec 2 W6c Task 10 fix round 1: the meeting kit's clock in every Dating
/// shell (a fixed morning, so a test's afternoon meet is still ahead), and
/// notifications allowed unless a test says not.
final datingTestNow = DateTime(2026, 11, 21, 9);
final datingKitOverrides = <Override>[
  datingNowProvider.overrideWithValue(() => datingTestNow),
  datingPushAllowedProvider.overrideWithValue(() => true),
];

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
  bool deviceReady = true,
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
        datingVerificationGatewayProvider.overrideWithValue(
          FakeDatingVerificationGateway(state: datingVerifiedState),
        ),
        // Spec 2 W4b: this phone has an install id unless a test says not.
        datingDeviceReadyProvider.overrideWith((ref) async => deviceReady),
        datingNeverIntroduceGatewayProvider.overrideWithValue(
          FakeNeverIntroduce(),
        ),
        // Spec 2 W5c: not eligible for Other countries unless a test says.
        datingAbroadGatewayProvider.overrideWithValue(FakeAbroad()),
        // Spec 2 W6a: the chat is faked unless a test says otherwise.
        ...datingChatOverrides(FakeDatingChat()),
        ...datingKitOverrides,
        // Spec 2 W8b: the device check is faked unless a test says otherwise.
        ...datingTripOverrides(FakeDatingTrip()),
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
  DatingVerificationGateway? verification,
  bool deviceReady = true,
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
  datingVerificationGatewayProvider.overrideWithValue(
    verification ?? FakeDatingVerificationGateway(state: datingVerifiedState),
  ),
  // Spec 2 W4b: this phone has an install id unless a test says not.
  datingDeviceReadyProvider.overrideWith((ref) async => deviceReady),
  datingNeverIntroduceGatewayProvider.overrideWithValue(FakeNeverIntroduce()),
  datingAbroadGatewayProvider.overrideWithValue(FakeAbroad()),
  ...datingChatOverrides(FakeDatingChat()),
  ...datingKitOverrides,
  // Spec 2 W8b: the device check is faked.
  ...datingTripOverrides(FakeDatingTrip()),
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
  // Spec 2 W8b: the device check is faked.
  ...datingTripOverrides(FakeDatingTrip()),
];

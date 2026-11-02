// Spec 1 W3: pumps HomeScreen with no Supabase: a scripted signed-in
// account, the home-state gateway, the flags, and probes for both tabs.
import 'dart:async';

import 'package:attune/app/theme/app_theme.dart';
import 'package:attune/core/providers/shared_prefs_provider.dart';
import 'package:attune/core/services/user_timezone_reporter.dart';
import 'package:attune/core/utils/screen_util_config.dart';
import 'package:attune/features/me/data/journal_reminder_service.dart';
import 'package:attune/features/auth/sign_up/presentation/sign_up_flags.dart';
import 'package:attune/features/onboarding/data/home_state_service.dart';
import 'package:attune/features/onboarding/domain/home_state.dart';
import 'package:attune/features/onboarding/presentation/providers/flow_flags.dart';
import 'package:attune/features/onboarding/presentation/providers/home_state_providers.dart';
import 'package:attune/home/home_screen.dart';
import 'package:attune/home/home_seams.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'fake_home_state.dart';
import 'fake_reminder_rpc.dart';

User testUser(String id) => User(
  id: id,
  appMetadata: const {},
  userMetadata: const {},
  aud: 'authenticated',
  createdAt: '2026-10-01T00:00:00Z',
);

class FakeHomeAuth implements HomeAuth {
  FakeHomeAuth(this.currentUser);

  @override
  User? currentUser;

  final changes = StreamController<AuthState>.broadcast();

  void signIn(String id) {
    currentUser = testUser(id);
    changes.add(const AuthState(AuthChangeEvent.signedIn, null));
  }

  void signOut() {
    currentUser = null;
    changes.add(const AuthState(AuthChangeEvent.signedOut, null));
  }

  @override
  Stream<AuthState> get authStateChanges => changes.stream;
}

/// Tab 2's stand-in: counts how often it was created (a rebuilt shell
/// creates it again) and shows what it was given.
class TabTwoProbe extends StatefulWidget {
  const TabTwoProbe({super.key, required this.tab, required this.home});

  final AppTab tab;
  final HomeSnapshot home;

  static int created = 0;

  @override
  State<TabTwoProbe> createState() => _TabTwoProbeState();
}

class _TabTwoProbeState extends State<TabTwoProbe> {
  @override
  void initState() {
    super.initState();
    TabTwoProbe.created++;
  }

  @override
  Widget build(BuildContext context) =>
      Text('TAB2 ${widget.tab.wire} ${widget.home.link.wire}');
}

class HomeHarness {
  HomeHarness(
    this.router,
    this.container,
    this.auth,
    this.gateway,
    this.prefs,
    this.onboardingVisits,
  );

  final GoRouter router;
  final ProviderContainer container;
  final FakeHomeAuth auth;
  final FakeHomeStateGateway gateway;
  final SharedPreferences prefs;
  final List<String> onboardingVisits;

  String get location =>
      router.routerDelegate.currentConfiguration.uri.toString();

  StateController<bool> get pathsV2 => container.read(_pathsV2.notifier);

  /// Applies a server answer as get_my_home_state would give it.
  Future<void> answer(String userId, Map<String, dynamic> json) => container
      .read(homeStateProvider(userId).notifier)
      .apply(HomeState.fromJson(json));
}

final _pathsV2 = StateProvider<bool>((_) => true);

Future<HomeHarness> pumpHome(
  WidgetTester tester, {
  String? userId = 'u-home',
  bool pathsV2 = true,
  bool signInV2 = true,
  Map<String, Object> prefsValues = const {},
  Map<String, dynamic>? server,
  Object? serverError,
  String initialLocation = '/home',
  // The real Tab 2 (or a stand-in) instead of TabTwoProbe, and what it
  // needs (B7 review M-1: the shell rebuilds Tab 2 when the layout changes).
  HomeTabTwoBuilder? tabTwo,
  List<Override> overrides = const [],
  // Spec 1 W4b: routes the shell may open (e.g. /join-invite).
  List<RouteBase> extraRoutes = const [],
  // Batch-5 review I-1: the real flow flags (a test's flowFlagsGateway
  // override answers them) instead of the scripted flow_paths_v2.
  bool realFlags = false,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  TabTwoProbe.created = 0;
  SharedPreferences.setMockInitialValues(prefsValues);
  final prefs = await SharedPreferences.getInstance();
  final auth = FakeHomeAuth(userId == null ? null : testUser(userId));
  addTearDown(auth.changes.close);
  // serverError: every home-state call fails (offline) from the start.
  final gateway = FakeHomeStateGateway(state: server)..failAlways = serverError;
  final visits = <String>[];
  final router = GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(
        path: '/home',
        builder:
            (_, state) => HomeScreen(
              tabRequest:
                  state.uri.queryParameters.containsKey('tab')
                      ? state.uri.query
                      : null,
            ),
      ),
      GoRoute(
        path: '/onboarding',
        builder: (_, __) {
          visits.add('onboarding');
          return const Scaffold(body: Text('ONBOARDING'));
        },
      ),
      ...extraRoutes,
    ],
  );
  addTearDown(router.dispose);
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      homeAuthProvider.overrideWithValue(auth),
      homeStateServiceProvider.overrideWithValue(HomeStateService(gateway)),
      _pathsV2.overrideWith((_) => pathsV2),
      if (!realFlags) ...[
        flowPathsV2Provider.overrideWith((ref) => ref.watch(_pathsV2)),
        flowFlagsKnownProvider.overrideWithValue(true),
      ],
      signInFlowV2Provider.overrideWithValue(signInV2),
      homeOpinionsTabProvider.overrideWithValue(const Text('OPINIONS')),
      homeTabTwoBuilderProvider.overrideWithValue(
        tabTwo ?? (tab, home, _) => TabTwoProbe(tab: tab, home: home),
      ),
      userTimezoneReporterProvider.overrideWithValue(
        UserTimezoneReporter(
          deviceTimezone: () async => '',
          send: (_) async {},
        ),
      ),
      // B7 review N-2: J3's row never reaches Supabase (a test's own
      // override below wins).
      journalReminderRpcProvider.overrideWithValue(FakeReminderRpc().call),
      ...overrides,
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: ScreenUtilConfig.builder(
        builder:
            (_) => MaterialApp.router(
              theme: AppTheme.lightTheme,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              routerConfig: router,
            ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  return HomeHarness(router, container, auth, gateway, prefs, visits);
}

/// A snapshot as the server would answer it.
HomeSnapshot snapshotOf(Map<String, dynamic> json) =>
    HomeSnapshot.fromServer(HomeState.fromJson(json));

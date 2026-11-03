// Spec 1 W5 (§5.4, P-13): createAppRouter's /about-us/:relationshipId is
// for a signed-in account with couple_profile on; `draft` is the draft;
// off (or signed out) a typed or deep /about-us never shows About us.
// Batch 5: a deep link with nothing underneath closes to Home; a phone
// that has never had the signed-in flags waits for them (unknown is not
// off), says so if they can't be read, and only then decides.
import 'dart:async';
import 'dart:io';

import 'package:attune/app/routing/app_router.dart';
import 'package:attune/app/routing/routing_notifier.dart';
import 'package:attune/app/theme/app_theme.dart';
import 'package:attune/core/flags/public_app_config.dart';
import 'package:attune/core/providers/couple_name_provider.dart';
import 'package:attune/core/providers/routing_providers.dart';
import 'package:attune/core/providers/shared_prefs_provider.dart';
import 'package:attune/core/utils/screen_util_config.dart';
import 'package:attune/features/auth/sign_up/presentation/sign_up_flags.dart';
import 'package:attune/features/couple_profile/data/couple_profile_service.dart';
import 'package:attune/features/couple_profile/presentation/about_us_entry.dart';
import 'package:attune/features/couple_profile/presentation/screens/about_us_screen.dart';
import 'package:attune/features/onboarding/data/home_state_service.dart';
import 'package:attune/features/onboarding/presentation/providers/flow_flags.dart';
import 'package:attune/features/timeline/presentation/providers/timeline_providers.dart'
    show togetherChangeSignalProvider;
import 'package:attune/home/home_seams.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_couple_profile.dart';
import '../../helpers/fake_home_state.dart';
import '../../helpers/flow_harness.dart';
import '../../helpers/home_harness.dart';

const _uid = 'u-route-about';

Future<GoRouter> _pump(
  WidgetTester tester, {
  required bool signedIn,
  required bool aboutUs,
  FlowFlagsGateway? flags,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});
  FlutterSecureStorage.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final auth = FakeHomeAuth(signedIn ? testUser(_uid) : null);
  addTearDown(auth.changes.close);
  final routing = RoutingNotifier(
    flowV2: true,
    currentUserId: () => signedIn ? _uid : null,
  );
  final router = createAppRouter(routing);
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        routingNotifierProvider.overrideWith((ref) => routing),
        publicAppConfigGatewayProvider.overrideWithValue(
          FakePublicConfigGateway(),
        ),
        homeAuthProvider.overrideWithValue(auth),
        // As join_invite_route_test.dart: Home stays a plain shell.
        homeStateServiceProvider.overrideWithValue(
          HomeStateService(
            FakeHomeStateGateway(state: homeJson(path: null, needs: ['path'])),
          ),
        ),
        signInFlowV2Provider.overrideWithValue(true),
        if (flags != null)
          flowFlagsGatewayProvider.overrideWithValue(flags)
        else ...[
          flowPathsV2Provider.overrideWithValue(true),
          flowCouplesV2Provider.overrideWithValue(true),
          coupleProfileEnabledProvider.overrideWithValue(aboutUs),
        ],
        coupleProfileRpcProvider.overrideWithValue(
          FakeCoupleProfileServer().rpc,
        ),
        coupleNameProvider.overrideWith((ref, id) async => null),
        togetherChangeSignalProvider.overrideWith(
          (ref, id) => const Stream.empty(),
        ),
      ],
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
  return router;
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 14; i++) {
    await tester.pump(const Duration(milliseconds: 150));
  }
}

String _at(GoRouter router) =>
    router.routerDelegate.currentConfiguration.uri.toString();

/// The signed-in flags' read, answered when a test says so.
class _Flags implements FlowFlagsGateway {
  Completer<SignedInFlowFlags> next = Completer();
  int reads = 0;

  @override
  Future<SignedInFlowFlags> fetch() {
    reads++;
    return next.future;
  }
}

const _allOn = SignedInFlowFlags(
  pathsV2: true,
  couplesV2: true,
  coupleProfile: true,
);

void main() {
  test('the locations', () {
    expect(aboutUsLocation('r1'), '/about-us/r1');
    expect(aboutUsLocation(null), '/about-us/draft');
    expect(RouteNames.aboutUs, '/about-us/:relationshipId');
  });

  testWidgets(
    'signed in, couple_profile on: the shared profile and the draft',
    (tester) async {
      final router = await _pump(tester, signedIn: true, aboutUs: true);
      router.go(aboutUsLocation('r1'));
      await _settle(tester);
      expect(_at(router), '/about-us/r1');
      final shared = tester.widget<AboutUsScreen>(find.byType(AboutUsScreen));
      expect(shared.target, const AboutUsTarget.shared('r1'));
      router.go(aboutUsLocation(null), extra: 'Ama');
      await _settle(tester);
      final draft = tester.widget<AboutUsScreen>(find.byType(AboutUsScreen));
      expect(draft.target, const AboutUsTarget.draft());
      expect(draft.partnerName, 'Ama');
    },
  );

  testWidgets('couple_profile off, or signed out: never About us', (
    tester,
  ) async {
    final off = await _pump(tester, signedIn: true, aboutUs: false);
    off.go(aboutUsLocation('r1'));
    await _settle(tester);
    expect(_at(off), isNot(startsWith('/about-us')));
    expect(find.byType(AboutUsScreen), findsNothing);

    await tester.pumpWidget(const SizedBox());
    final out = await _pump(tester, signedIn: false, aboutUs: true);
    out.go(aboutUsLocation('r1'));
    await _settle(tester);
    expect(_at(out), isNot(startsWith('/about-us')));
    expect(find.byType(AboutUsScreen), findsNothing);
  });

  testWidgets('a deep link with nothing underneath closes to Home; '
      'pushed over another screen, it pops back to it', (tester) async {
    final router = await _pump(tester, signedIn: true, aboutUs: true);
    router.go(aboutUsLocation('r1'));
    await _settle(tester);
    expect(find.byType(AboutUsScreen), findsOneWidget);
    await tester.tap(find.byTooltip('Back'));
    await _settle(tester);
    expect(_at(router), isNot(startsWith('/about-us')));
    expect(find.byType(AboutUsScreen), findsNothing);

    router.go(aboutUsLocation('r1'));
    await _settle(tester);
    unawaited(router.push(aboutUsLocation(null)));
    await _settle(tester);
    expect(
      tester.widget<AboutUsScreen>(find.byType(AboutUsScreen)).target,
      const AboutUsTarget.draft(),
    );
    await tester.tap(find.byTooltip('Back'));
    await _settle(tester);
    expect(_at(router), '/about-us/r1');
  });

  testWidgets('never-cached flags: About us waits for them, then opens', (
    tester,
  ) async {
    final flags = _Flags();
    final router = await _pump(
      tester,
      signedIn: true,
      aboutUs: true,
      flags: flags,
    );
    router.go(aboutUsLocation('r1'));
    await _settle(tester);
    expect(_at(router), '/about-us/r1', reason: 'unknown is not off');
    expect(find.byType(AboutUsScreen), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    flags.next.complete(_allOn);
    await _settle(tester);
    expect(_at(router), '/about-us/r1');
    expect(find.byType(AboutUsScreen), findsOneWidget);
  });

  testWidgets('never-cached flags that fail: said, Try again reads them', (
    tester,
  ) async {
    final flags = _Flags();
    final router = await _pump(
      tester,
      signedIn: true,
      aboutUs: true,
      flags: flags,
    );
    router.go(aboutUsLocation('r1'));
    await _settle(tester);
    flags.next.completeError(const SocketException('offline'));
    await _settle(tester);
    expect(_at(router), '/about-us/r1', reason: 'never closed for good');
    expect(
      find.text(
        "We couldn't load About us. Check your connection and try again.",
      ),
      findsOneWidget,
    );
    final before = flags.reads;
    flags.next = Completer();
    await tester.tap(find.text('Try again'));
    await _settle(tester);
    expect(flags.reads, before + 1);
    flags.next.complete(_allOn);
    await _settle(tester);
    expect(find.byType(AboutUsScreen), findsOneWidget);
  });

  testWidgets('never-cached flags that come back off: Home, never About us', (
    tester,
  ) async {
    final flags = _Flags();
    final router = await _pump(
      tester,
      signedIn: true,
      aboutUs: true,
      flags: flags,
    );
    router.go(aboutUsLocation('r1'));
    await _settle(tester);
    flags.next.complete(
      const SignedInFlowFlags(pathsV2: true, couplesV2: true),
    );
    await _settle(tester);
    expect(_at(router), isNot(startsWith('/about-us')));
    expect(find.byType(AboutUsScreen), findsNothing);
  });
}

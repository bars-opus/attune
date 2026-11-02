// Spec 1 W3c (§3.12): Settings -> How you use Attune. Every switch is
// silent; each "from -> to" shows what the table says; an open shared space
// is paused or ended first.
import 'dart:async';

import 'package:attune/app/routing/app_router.dart' show RouteNames;
import 'package:attune/app/theme/app_theme.dart';
import 'package:attune/core/providers/shared_prefs_provider.dart';
import 'package:attune/core/utils/screen_util_config.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_buttons.dart';
import 'package:attune/features/onboarding/data/home_state_service.dart';
import 'package:attune/features/settings/presentation/screens/how_you_use_attune_screen.dart';
import 'package:attune/home/home_seams.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_home_state.dart';
import '../../helpers/flow_harness.dart';
import '../../helpers/home_harness.dart';

Future<(GoRouter, FakeHomeStateGateway)> _pump(
  WidgetTester tester,
  Map<String, dynamic> server, {
  bool signedIn = true,
  bool push = true,
}) async {
  tester.view.physicalSize = const Size(390, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const SizedBox());
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final gateway = FakeHomeStateGateway(state: server);
  final router = GoRouter(
    initialLocation: push ? '/settings' : RouteNames.howYouUseAttune,
    routes: [
      // As in the app, a top-level route: a deep link has nothing under it.
      if (!push)
        GoRoute(
          path: RouteNames.howYouUseAttune,
          builder: (_, __) => const HowYouUseAttuneScreen(),
        ),
      GoRoute(
        path: '/settings',
        builder: (_, __) => const Text('SETTINGS'),
        routes: [
          if (push)
            GoRoute(
              path: 'how-you-use-attune',
              builder: (_, __) => const HowYouUseAttuneScreen(),
            ),
        ],
      ),
      GoRoute(
        path: '/home',
        builder: (_, s) => Text('HOME ${s.uri.queryParameters['tab']}'),
      ),
      GoRoute(
        path: '/invite-partner',
        builder: (_, s) => Text('INVITE ${s.uri.query}'),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        homeAuthProvider.overrideWithValue(
          FakeHomeAuth(signedIn ? testUser('u-how') : null),
        ),
        homeStateServiceProvider.overrideWithValue(HomeStateService(gateway)),
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
  if (push) router.push(RouteNames.howYouUseAttune);
  await tester.pumpAndSettle();
  return (router, gateway);
}

void main() {
  testWidgets('three ways, the current one chosen, the silent footer', (
    tester,
  ) async {
    await _pump(tester, homeJson(path: 'just_me'));
    expect(find.text('How you use Attune'), findsOneWidget);
    expect(find.text('In a relationship'), findsOneWidget);
    expect(find.text('Single and open to dating'), findsOneWidget);
    expect(find.text('Just for me'), findsOneWidget);
    expect(
      find.text(
        'Your journal, quizzes and Healing stay yours whichever you choose. Nobody is told when you change this.',
      ),
      findsOneWidget,
    );
    final checked = tester.widget<Icon>(
      find.byIcon(Icons.radio_button_checked),
    );
    expect(checked, isNotNull);
  });

  testWidgets('Just for me -> Dating: Me with the slot', (tester) async {
    final (router, gateway) = await _pump(tester, homeJson(path: 'just_me'));
    gateway.onSetPath =
        (p) => gateway.state = homeJson(path: p['p_path'] as String);
    await tester.tap(find.text('Single and open to dating'));
    await tester.pumpAndSettle();
    expect(gateway.calls.lastWhere((c) => c.$1 == 'set_my_path').$2, {
      'p_path': 'dating',
      'p_confirmed': false,
    });
    expect(find.text('HOME me'), findsOneWidget);
  });

  testWidgets('Just for me -> Relationship: R1, the switch at the invite', (
    tester,
  ) async {
    final (_, gateway) = await _pump(tester, homeJson(path: 'just_me'));
    await tester.tap(find.text('In a relationship'));
    await tester.pumpAndSettle();
    expect(find.text('INVITE switch=1'), findsOneWidget);
    expect(gateway.count('set_my_path'), 0);
  });

  testWidgets('Back from R1 without an invite changes nothing', (tester) async {
    final (router, gateway) = await _pump(tester, homeJson(path: 'just_me'));
    await tester.tap(find.text('In a relationship'));
    await tester.pumpAndSettle();
    router.pop();
    await tester.pumpAndSettle();
    expect(gateway.count('set_my_path'), 0);
    expect(find.text('How you use Attune'), findsOneWidget);
  });

  testWidgets(
    'Relationship pending -> other: "Cancel your invite?" then switch',
    (tester) async {
      final (_, gateway) = await _pump(
        tester,
        homeJson(path: 'relationship', link: 'pending'),
      );
      gateway.failNext = FakeHomeStateGateway.refusal('path:confirm_withdraw');
      gateway.onSetPath =
          (p) => gateway.state = homeJson(path: p['p_path'] as String);
      await tester.tap(find.text('Just for me'));
      await tester.pumpAndSettle();
      expect(find.text('Cancel your invite?'), findsOneWidget);
      await tester.tap(find.text('Cancel invite and switch'));
      await tester.pumpAndSettle();
      final calls = gateway.calls.where((c) => c.$1 == 'set_my_path').toList();
      expect(calls.map((c) => c.$2!['p_confirmed']), [false, true]);
      expect(find.text('HOME me'), findsOneWidget);
    },
  );

  testWidgets('Relationship linked -> other: pause or end first', (
    tester,
  ) async {
    final (_, gateway) = await _pump(
      tester,
      homeJson(
        path: 'relationship',
        link: 'linked',
        relationshipId: 'r1',
        partnerFirstName: 'Kofi',
      ),
    );
    await tester.tap(find.text('Just for me'));
    await tester.pumpAndSettle();
    expect(find.text("You're in a shared space with Kofi"), findsOneWidget);
    expect(find.text('Pause our shared space'), findsOneWidget);
    expect(find.text('End relationship'), findsOneWidget);
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(gateway.count('set_my_path'), 0);
  });

  testWidgets('a paused space offers no second pause', (tester) async {
    await _pump(
      tester,
      homeJson(path: 'relationship', link: 'paused', relationshipId: 'r1'),
    );
    await tester.tap(find.text('Single and open to dating'));
    await tester.pumpAndSettle();
    expect(
      find.text("You're in a shared space with your partner"),
      findsOneWidget,
    );
    expect(find.text('Pause our shared space'), findsNothing);
  });

  testWidgets('Dating -> Just for me asks first', (tester) async {
    final (_, gateway) = await _pump(
      tester,
      homeJson(path: 'dating', datingEnrolled: true),
    );
    gateway.onSetPath =
        (p) => gateway.state = homeJson(path: p['p_path'] as String);
    await tester.tap(find.text('Just for me'));
    await tester.pumpAndSettle();
    expect(find.text('Use Attune just for you?'), findsOneWidget);
    await tester.tap(find.text('Switch'));
    await tester.pumpAndSettle();
    expect(gateway.calls.lastWhere((c) => c.$1 == 'set_my_path').$2, {
      'p_path': 'just_me',
      'p_confirmed': false,
    });
  });

  testWidgets('a space that opened since the screen read: pause or end (M-2)', (
    tester,
  ) async {
    final (_, gateway) = await _pump(tester, homeJson(path: 'just_me'));
    gateway.state = homeJson(
      path: 'relationship',
      link: 'linked',
      relationshipId: 'r1',
      partnerFirstName: 'Kofi',
    );
    gateway.failNext = FakeHomeStateGateway.refusal('path:relationship_open');
    await tester.tap(find.text('Single and open to dating'));
    await tester.pumpAndSettle();
    expect(find.text("You're in a shared space with Kofi"), findsOneWidget);
    expect(find.text('Pause our shared space'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    expect(find.text('HOME me'), findsNothing);
  });

  testWidgets('offline with no live path: says so, then tries again', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final gateway = FakeHomeStateGateway(state: homeJson(path: 'dating'))
      ..failAlways = Exception('offline');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          homeAuthProvider.overrideWithValue(FakeHomeAuth(testUser('u-how'))),
          homeStateServiceProvider.overrideWithValue(HomeStateService(gateway)),
        ],
        child: ScreenUtilConfig.builder(
          builder:
              (_) => MaterialApp(
                theme: AppTheme.lightTheme,
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                home: const HowYouUseAttuneScreen(),
              ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text("You're offline. Try again when you're connected."),
      findsOneWidget,
    );
    expect(find.byType(CircularProgressIndicator), findsNothing);
    gateway.failAlways = null;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('Single and open to dating'), findsOneWidget);
    expect(find.byIcon(Icons.radio_button_checked), findsOneWidget);
  });

  // B7 review M-4: a switch in flight shows, and a second tap does nothing.
  testWidgets('while switching: progress shows; a second tap is ignored', (
    tester,
  ) async {
    final (_, gateway) = await _pump(tester, homeJson(path: 'just_me'));
    final hold = Completer<void>();
    gateway.hold = hold;
    await tester.tap(find.text('Single and open to dating'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    await tester.tap(find.text('Just for me'), warnIfMissed: false);
    await tester.pump();
    expect(gateway.count('set_my_path'), 1);
    hold.complete();
    gateway.hold = null;
    await tester.pumpAndSettle();
  });

  // B7 review M-5: never a spinner forever.
  testWidgets('signed out: leaves for Settings', (tester) async {
    await _pump(tester, homeJson(path: 'just_me'), signedIn: false);
    expect(find.text('SETTINGS'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('the server has no path yet: home (the gate asks)', (
    tester,
  ) async {
    await _pump(tester, homeJson(path: null, needs: ['path']));
    expect(find.text('HOME null'), findsOneWidget);
  });

  // B7 review N-3: Back from a deep link with nothing to pop.
  testWidgets('Back with nothing under it: Settings', (tester) async {
    await _pump(tester, homeJson(path: 'just_me'), push: false);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('SETTINGS'), findsOneWidget);
  });

  // B7 review M-7: §3.12 rows from an ending's window.
  for (final (to, label, tab) in [
    ('dating', 'Single and open to dating', 'me'),
    ('just_me', 'Just for me', 'me'),
  ]) {
    testWidgets('Relationship (ended, window open) -> $to', (tester) async {
      final (_, gateway) = await _pump(
        tester,
        homeJson(
          path: 'relationship',
          link: 'ended_window',
          windowEndsAt: '2026-11-20T10:00:00Z',
        ),
      );
      gateway.onSetPath =
          (p) =>
              gateway.state = homeJson(
                path: p['p_path'] as String,
                link: 'ended_window',
                windowEndsAt: '2026-11-20T10:00:00Z',
              );
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
      expect(gateway.calls.lastWhere((c) => c.$1 == 'set_my_path').$2, {
        'p_path': to,
        'p_confirmed': false,
      });
      expect(find.text('HOME $tab'), findsOneWidget);
    });
  }

  testWidgets('the shared-space sheet meets the guidelines', (tester) async {
    final semantics = tester.ensureSemantics();
    await _pump(
      tester,
      homeJson(path: 'relationship', link: 'paused', relationshipId: 'r1'),
    );
    await tester.tap(find.text('Just for me'));
    await tester.pumpAndSettle();
    expect(find.text('End relationship'), findsOneWidget);
    await expectFlowGuidelines(tester);
    semantics.dispose();
  });

  testWidgets('paused: "Not now" leads; "End relationship" is not primary', (
    tester,
  ) async {
    await _pump(
      tester,
      homeJson(path: 'relationship', link: 'paused', relationshipId: 'r1'),
    );
    await tester.tap(find.text('Just for me'));
    await tester.pumpAndSettle();
    expect(
      find.ancestor(
        of: find.text('Not now'),
        matching: find.byType(FlowPrimaryButton),
      ),
      findsOneWidget,
    );
    expect(
      find.ancestor(
        of: find.text('End relationship'),
        matching: find.byType(FlowPrimaryButton),
      ),
      findsNothing,
    );
  });

  testWidgets('meets the guidelines', (tester) async {
    final semantics = tester.ensureSemantics();
    await _pump(tester, homeJson(path: 'just_me'));
    await expectFlowGuidelines(tester);
    semantics.dispose();
  });

  testWidgets('goldens', (tester) async {
    await expectFlowGoldens(
      tester,
      'how_you_use_attune',
      () => const HowYouUseAttuneScreen(),
      overrides: [
        homeAuthProvider.overrideWithValue(FakeHomeAuth(testUser('u-how'))),
        homeStateServiceProvider.overrideWithValue(
          HomeStateService(
            FakeHomeStateGateway(state: homeJson(path: 'just_me')),
          ),
        ),
      ],
    );
  });
}

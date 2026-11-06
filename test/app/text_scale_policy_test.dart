// Spec 1 §2.3, §2.5 (W10a): the root text clamp follows text_scale_v2,
// keeps 1.0 on Games routes and on routes the audit hasn't checked, and
// never stops AllowLargeText reaching 2.0.
import 'dart:async';

import 'package:attune/app/text_scale_policy.dart';
import 'package:attune/core/flags/public_app_config.dart';
import 'package:attune/core/providers/shared_prefs_provider.dart';
import 'package:attune/core/ui/text/allow_large_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Gateway implements PublicAppConfigGateway {
  _Gateway(this.on);
  final bool on;
  @override
  Future<Map<String, dynamic>> fetch() async => {
    'flags': {'text_scale_v2': on},
    'config': <String, dynamic>{},
  };
}

class _Counter extends StatefulWidget {
  const _Counter();
  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  int taps = 0;
  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: () => setState(() => taps++),
    child: Text('taps $taps'),
  );
}

double _scaleOf(WidgetTester t, Finder f) =>
    MediaQuery.textScalerOf(t.element(f)).scale(10) / 10;

/// The scale RootTextScaleClamp gives everything below it (the Router).
double _rootScale(WidgetTester t) =>
    _scaleOf(t, find.byWidgetPredicate((w) => w is Router).first);

class _App extends StatelessWidget {
  const _App({required this.router, required this.cap});
  final GoRouter router;
  final double cap;
  @override
  Widget build(BuildContext context) => MaterialApp.router(
    routerConfig: router,
    builder:
        (context, child) =>
            RootTextScaleClamp(router: router, cap: cap, child: child!),
  );
}

Future<GoRouter> _pump(
  WidgetTester t,
  double cap, {
  double system = 2.0,
  String initial = '/home',
}) async {
  t.platformDispatcher.textScaleFactorTestValue = system;
  addTearDown(t.platformDispatcher.clearAllTestValues);
  final router = GoRouter(
    initialLocation: initial,
    routes: [
      GoRoute(
        path: '/home',
        builder: (_, __) => const Scaffold(body: _Counter()),
      ),
      GoRoute(
        path: '/games/snakes/:relationshipId',
        builder: (_, __) => const Scaffold(body: Text('board')),
      ),
      GoRoute(
        path: '/pulse',
        builder: (_, __) => const Scaffold(body: Text('pulse')),
      ),
      GoRoute(
        path: '/settings',
        builder: (_, __) => const Scaffold(body: Text('settings')),
      ),
      GoRoute(
        path: '/settings/download-my-data',
        builder: (_, __) => const Scaffold(body: Text('export')),
      ),
      GoRoute(
        path: '/communityFeed',
        builder:
            (_, __) =>
                const Scaffold(body: AllowLargeText(child: Text('large'))),
      ),
    ],
  );
  addTearDown(router.dispose);
  await t.pumpWidget(_App(router: router, cap: cap));
  await t.pumpAndSettle();
  return router;
}

void main() {
  group('TextScalePolicy.capFor', () {
    test('off keeps 1.0 everywhere', () {
      for (final at in ['/home', '/chatScreen', null]) {
        expect(TextScalePolicy.capFor(cap: 1.0, topLocation: at), 1.0);
      }
    });

    test('on: the audited routes get the cap', () {
      for (final at in [
        '/home',
        '/chatScreen',
        '/chat-channel',
        '/commentThread',
        '/planning/entry',
        '/together',
        '/settings',
        '/settings/quiet',
        '/settings/signed-in-devices',
        '/healingStage',
        '/journalEntry',
        '/about-us/r1',
      ]) {
        expect(
          TextScalePolicy.capFor(cap: 1.6, topLocation: at),
          1.6,
          reason: at,
        );
      }
      expect(TextScalePolicy.capFor(cap: 1.6, topLocation: null), 1.6);
    });

    test('on: Games routes keep 1.0', () {
      for (final at in [
        '/games/snakes/r1',
        '/games/paint-ball/battle/s1',
        '/thirtySixQuestion',
        '/thirtySixQuestions',
        '/truthOrDareGame',
        '/customTruthOrDareList',
        '/truthReveal',
        '/dareReveal',
        '/thisOrThatGamesHub',
        '/customQuestionCreate',
        '/mirrorGame',
        '/slidingScaleGame',
        '/scenarioGame',
        '/loveMap',
      ]) {
        expect(
          TextScalePolicy.capFor(cap: 2.0, topLocation: at),
          1.0,
          reason: at,
        );
      }
    });

    test('on: routes not audited yet keep 1.0, a new one included', () {
      for (final at in [
        '/pulse',
        '/communityFeed',
        '/quizEntry',
        '/dating-mode',
        '/chatInsights',
        '/notificationInbox',
        '/somewhere-new',
        // W10 B6 I-1: a child of an audited location is not audited.
        '/settings/download-my-data',
        // W10 B6 I-4: no audit test reaches these yet.
        '/language',
        '/theme',
        '/licenses',
        '/allLegalDocumentation',
        '/appInfoScreen',
        '/blockedAccountsScreen',
        '/mutedAuthorsScreen',
        '/neutralScreen',
        '/starred-messages',
        '/chat-message-search',
        '/ephemeral-camera',
        '/couples-calendar/family',
        '/anonymousProfile',
        '/opinionEngagement',
        '/opinionLoader',
      ]) {
        expect(
          TextScalePolicy.capFor(cap: 2.0, topLocation: at),
          1.0,
          reason: at,
        );
      }
    });

    test('on: an audited prefix covers its own path only (W10 final W-m2)', () {
      for (final at in [
        '/settingsfoo',
        '/homeX',
        '/planningX',
        '/togetherX',
        '/timelineX',
        '/chatScreenX',
        '/invite-other',
        '/journalEntryX',
      ]) {
        expect(
          TextScalePolicy.capFor(cap: 2.0, topLocation: at),
          1.0,
          reason: at,
        );
      }
      for (final at in [
        '/home',
        '/home/x',
        '/planning',
        '/planning/entry',
        '/invite',
        '/invite/x',
        '/invite-partner',
        '/about-us/r1',
        '/support/x',
        '/couples-calendar/add',
      ]) {
        expect(
          TextScalePolicy.capFor(cap: 2.0, topLocation: at),
          2.0,
          reason: at,
        );
      }
    });

    test('the boot route decides nothing: it gets the cap (no reflow)', () {
      expect(
        TextScalePolicy.capFor(
          cap: 2.0,
          topLocation: TextScalePolicy.bootLocation,
        ),
        2.0,
      );
    });

    test('the cap is one of the candidates, or off', () {
      expect([
        ...TextScalePolicy.candidateCaps,
        TextScalePolicy.offCap,
      ], contains(TextScalePolicy.v2Cap));
    });
  });

  testWidgets('cap 1.0: the phone size never reaches a route', (t) async {
    await _pump(t, 1.0);
    expect(_scaleOf(t, find.byType(_Counter)), 1.0);
  });

  testWidgets('cap on: an audited route gets the phone size up to the cap', (
    t,
  ) async {
    await _pump(t, 1.6);
    expect(_scaleOf(t, find.byType(_Counter)), 1.6);
    await _pump(t, 1.6, system: 1.15);
    expect(_scaleOf(t, find.byType(_Counter)), 1.15);
  });

  testWidgets('a pushed Games route keeps 1.0, and popping restores', (
    t,
  ) async {
    final router = await _pump(t, 2.0);
    router.push('/games/snakes/r1');
    await t.pumpAndSettle();
    expect(_scaleOf(t, find.text('board')), 1.0);
    router.pop();
    await t.pumpAndSettle();
    expect(_scaleOf(t, find.byType(_Counter)), 2.0);
    router.go('/pulse');
    await t.pumpAndSettle();
    expect(_scaleOf(t, find.text('pulse')), 1.0, reason: 'not audited');
  });

  testWidgets('a deep link straight into a Games route settles at 1.0', (
    t,
  ) async {
    // The first route arrives while the Navigator below is building; the
    // clamp above it changes after that frame, without an error.
    await _pump(t, 2.0, initial: '/games/snakes/r1');
    expect(t.takeException(), isNull);
    expect(_scaleOf(t, find.text('board')), 1.0);
  });

  testWidgets(
    'popping a Games route: the leaving page stays 1.0 (W10 B6 I-2)',
    (t) async {
      final router = await _pump(t, 2.0);
      router.push('/games/snakes/r1');
      await t.pumpAndSettle();
      router.pop();
      await t.pump();
      await t.pump(const Duration(milliseconds: 100));
      expect(find.text('board'), findsOneWidget, reason: 'mid-transition');
      expect(_scaleOf(t, find.text('board')), 1.0);
      await t.pump(const Duration(milliseconds: 100));
      expect(_scaleOf(t, find.text('board')), 1.0);
      await t.pumpAndSettle();
      expect(find.text('board'), findsNothing);
      expect(_scaleOf(t, find.byType(_Counter)), 2.0);
    },
  );

  testWidgets(
    'a rebuild while a Games page leaves keeps it at 1.0 (W10 final W-m4)',
    (t) async {
      final router = await _pump(t, 2.0);
      router.push('/games/snakes/r1');
      await t.pumpAndSettle();
      router.pop();
      await t.pump();
      await t.pump(const Duration(milliseconds: 100));
      // A theme, locale or router rebuild of the app, same cap.
      await t.pumpWidget(_App(router: router, cap: 2.0));
      expect(find.text('board'), findsOneWidget, reason: 'mid-transition');
      expect(_scaleOf(t, find.text('board')), 1.0);
      await t.pump(const Duration(milliseconds: 100));
      expect(_scaleOf(t, find.text('board')), 1.0);
      await t.pumpAndSettle();
      expect(find.text('board'), findsNothing);
      expect(_scaleOf(t, find.byType(_Counter)), 2.0);
    },
  );

  testWidgets('a cap change on rebuild applies at once, up and down', (
    t,
  ) async {
    final router = await _pump(t, 2.0);
    await t.pumpWidget(_App(router: router, cap: 1.3));
    expect(_scaleOf(t, find.byType(_Counter)), 1.3);
    await t.pumpWidget(_App(router: router, cap: 2.0));
    expect(_scaleOf(t, find.byType(_Counter)), 2.0);
  });

  testWidgets('a deep link into a Games route: even the first frame is 1.0', (
    t,
  ) async {
    t.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(t.platformDispatcher.clearAllTestValues);
    final router = GoRouter(
      initialLocation: '/games/snakes/r1',
      routes: [
        GoRoute(
          path: '/games/snakes/:relationshipId',
          builder: (_, __) => const Scaffold(body: Text('board')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await t.pumpWidget(_App(router: router, cap: 2.0));
    expect(_rootScale(t), 1.0, reason: 'the first frame');
    await t.pumpAndSettle();
    expect(_scaleOf(t, find.text('board')), 1.0);
  });

  testWidgets('an unknown location (the error page) keeps 1.0', (t) async {
    await _pump(t, 2.0, initial: '/nowhere');
    expect(t.takeException(), isNull);
    expect(_rootScale(t), 1.0);
    final router = await _pump(t, 2.0);
    expect(_rootScale(t), 2.0);
    router.go('/nowhere');
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    expect(_rootScale(t), 1.0, reason: 'a go to an unknown location');
  });

  testWidgets('the boot route redirecting into Games drops to 1.0 after '
      'that frame, without an error', (t) async {
    t.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(t.platformDispatcher.clearAllTestValues);
    final router = GoRouter(
      initialLocation: TextScalePolicy.bootLocation,
      redirect:
          (_, state) =>
              state.matchedLocation == TextScalePolicy.bootLocation
                  ? '/games/snakes/r1'
                  : null,
      routes: [
        GoRoute(
          path: TextScalePolicy.bootLocation,
          builder: (_, __) => const SizedBox(),
        ),
        GoRoute(
          path: '/games/snakes/:relationshipId',
          builder: (_, __) => const Scaffold(body: Text('board')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await t.pumpWidget(_App(router: router, cap: 2.0));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    expect(_scaleOf(t, find.text('board')), 1.0);
  });

  testWidgets('download-my-data keeps 1.0; Settings itself gets the cap', (
    t,
  ) async {
    final router = await _pump(t, 2.0, initial: '/settings');
    expect(_scaleOf(t, find.text('settings')), 2.0);
    router.push('/settings/download-my-data');
    await t.pumpAndSettle();
    expect(_scaleOf(t, find.text('export')), 1.0);
    // Past-chapter stories is pushed pagelessly over it, so it follows.
    final nav = t.state<NavigatorState>(find.byType(Navigator).last);
    unawaited(
      nav.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('stories')),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(_scaleOf(t, find.text('stories')), 1.0);
  });

  testWidgets('a pageless push takes the page below; KeepsDefaultTextSize '
      'keeps 1.0 (W10 B6 I-3)', (t) async {
    await _pump(t, 2.0);
    final nav = t.state<NavigatorState>(find.byType(Navigator).last);
    unawaited(
      nav.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('pageless')),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(_scaleOf(t, find.text('pageless')), 2.0, reason: 'the page below');
    unawaited(
      nav.push(
        MaterialPageRoute<void>(
          builder:
              (_) => const KeepsDefaultTextSize(
                child: Scaffold(body: Text('kept')),
              ),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(_scaleOf(t, find.text('kept')), 1.0);
  });

  testWidgets('AllowLargeText still reaches 2.0, whatever the root says', (
    t,
  ) async {
    for (final cap in [1.0, 1.3]) {
      final router = await _pump(t, cap);
      router.go('/communityFeed');
      await t.pumpAndSettle();
      expect(_scaleOf(t, find.text('large')), 2.0, reason: 'cap $cap');
    }
  });

  testWidgets('switching the cap keeps the screen below (no rebuild)', (
    t,
  ) async {
    final router = await _pump(t, 1.0);
    await t.tap(find.byType(TextButton));
    await t.pump();
    expect(find.text('taps 1'), findsOneWidget);
    await t.pumpWidget(_App(router: router, cap: 2.0));
    await t.pump();
    expect(find.text('taps 1'), findsOneWidget, reason: 'state kept');
    expect(_scaleOf(t, find.byType(_Counter)), 2.0);
  });

  group('textScaleCapProvider', () {
    Future<ProviderContainer> container({
      required bool live,
      Map<String, Object> prefs = const {},
    }) async {
      SharedPreferences.setMockInitialValues(prefs);
      final c = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(
            await SharedPreferences.getInstance(),
          ),
          publicAppConfigGatewayProvider.overrideWithValue(_Gateway(live)),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    test('off until read, then follows the flag', () async {
      final c = await container(live: true);
      expect(c.read(textScaleV2Provider), isFalse);
      await c.read(publicAppConfigProvider.future);
      expect(c.read(textScaleV2Provider), isTrue);
      expect(c.read(textScaleCapProvider), TextScalePolicy.v2Cap);
    });

    test('the flag off keeps 1.0', () async {
      final c = await container(live: false);
      await c.read(publicAppConfigProvider.future);
      expect(c.read(textScaleV2Provider), isFalse);
      expect(c.read(textScaleCapProvider), TextScalePolicy.offCap);
    });

    test('the cached copy decides before the first answer', () async {
      final c = await container(
        live: false,
        prefs: {
          PublicAppConfigCache.key:
              '{"flags":{"text_scale_v2":true},"storefronts":[],"open_countries":[]}',
        },
      );
      expect(c.read(textScaleV2Provider), isTrue);
      await c.read(publicAppConfigProvider.future);
      expect(c.read(textScaleV2Provider), isFalse);
    });
  });
}

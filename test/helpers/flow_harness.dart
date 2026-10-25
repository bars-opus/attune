// Spec 1 W2: pumps a sign-in screen the way the app shows it — the app
// theme, the root shell's 1.0 text clamp, ScreenUtil, the real
// localisations — inside a router whose every other location just says
// where the screen sent the person ("at /signup?entry=new").
import 'package:attune/app/routing/routing_notifier.dart';
import 'package:attune/app/theme/app_theme.dart';
import 'package:attune/core/flags/public_app_config.dart';
import 'package:attune/core/metrics/metric_counter.dart';
import 'package:attune/core/providers/routing_providers.dart';
import 'package:attune/core/providers/shared_prefs_provider.dart';
import 'package:attune/core/utils/screen_util_config.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakePublicConfigGateway implements PublicAppConfigGateway {
  FakePublicConfigGateway({this.openCountries = const []});

  final List<String> openCountries;

  @override
  Future<Map<String, dynamic>> fetch() async => {
    'flags': {'flow_signin_v2': true},
    'config': {
      'age_signal_storefronts': <String>[],
      'dating_open_countries': openCountries,
    },
  };
}

class FlowHarness {
  FlowHarness(this.router, this.routing, this.prefs, this.metrics);

  final GoRouter router;
  final RoutingNotifier routing;
  final SharedPreferences prefs;

  /// Every metric key the screen bumped, in order.
  final List<String> metrics;

  String get location =>
      router.routerDelegate.currentConfiguration.uri.toString();
}

/// Text sizes and directions every new screen's goldens cover (§2.3).
const flowGoldenVariants = <(String, double, TextDirection)>[
  ('scale1.0', 1.0, TextDirection.ltr),
  ('scale1.3', 1.3, TextDirection.ltr),
  ('scale2.0', 2.0, TextDirection.ltr),
  ('rtl', 1.0, TextDirection.rtl),
];

Future<FlowHarness> pumpFlowScreen(
  WidgetTester tester,
  Widget Function() screen, {
  double textScale = 1.0,
  TextDirection direction = TextDirection.ltr,
  bool reduceMotion = false,
  Map<String, Object> prefsValues = const {},
  List<Override> overrides = const [],
  RoutingNotifier? routing,
  List<String> openCountries = const [],
  Size size = const Size(390, 844),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  if (reduceMotion) {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
  }
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearAllTestValues);

  SharedPreferences.setMockInitialValues(prefsValues);
  FlutterSecureStorage.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final notifier = routing ?? RoutingNotifier(prefs: prefs, flowV2: true);
  final metrics = <String>[];
  final router = GoRouter(
    initialLocation: '/test',
    routes: [GoRoute(path: '/test', builder: (_, __) => screen())],
    errorBuilder: (_, state) => Scaffold(body: Text('at ${state.uri}')),
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        routingNotifierProvider.overrideWith((ref) => notifier),
        metricCounterProvider.overrideWithValue(
          MetricCounter((key) async => metrics.add(key)),
        ),
        publicAppConfigGatewayProvider.overrideWithValue(
          FakePublicConfigGateway(openCountries: openCountries),
        ),
        ...overrides,
      ],
      child: ScreenUtilConfig.builder(
        builder:
            (_) => MaterialApp.router(
              theme: AppTheme.lightTheme,
              debugShowCheckedModeBanner: false,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              routerConfig: router,
              builder:
                  (context, child) => Directionality(
                    textDirection: direction,
                    // What app_shell.dart does for every route.
                    child: MediaQuery.withClampedTextScaling(
                      maxScaleFactor: 1.0,
                      child: child!,
                    ),
                  ),
            ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return FlowHarness(router, notifier, prefs, metrics);
}

/// Pumps [screen] at every golden variant and compares
/// `goldens/<name>.<variant>.png`. Run with --update-goldens to create them.
Future<void> expectFlowGoldens(
  WidgetTester tester,
  String name,
  Widget Function() screen, {
  Map<String, Object> prefsValues = const {},
  List<Override> overrides = const [],
  List<String> openCountries = const [],
  Future<void> Function(WidgetTester tester)? before,
}) async {
  for (final (variant, scale, direction) in flowGoldenVariants) {
    await pumpFlowScreen(
      tester,
      screen,
      textScale: scale,
      direction: direction,
      prefsValues: prefsValues,
      overrides: overrides,
      openCountries: openCountries,
    );
    if (before != null) await before(tester);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/$name.$variant.png'),
    );
    expect(tester.takeException(), isNull, reason: '$name at $variant');
  }
}

/// The three accessibility guidelines every new screen meets (§2.3).
Future<void> expectFlowGuidelines(WidgetTester tester) async {
  await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
  await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
  await expectLater(tester, meetsGuideline(textContrastGuideline));
}

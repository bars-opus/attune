// Spec 2 (research 06 §3 F3 (1)): one triple-tap target in the root shell
// covers every route -- pushed pages, a pageless MaterialPageRoute (the
// full-screen map), dialogs and bottom sheets -- and only the toolbar band,
// so a centred tab or title under it is not a trap (review I8).
import 'package:attune/app/routing/app_router.dart' show RouteNames;
import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:attune/features/safety/presentation/widgets/quick_exit_zone.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;

final _user = User(
  id: 'u1',
  appMetadata: const {},
  userMetadata: const {},
  aud: 'a',
  createdAt: '2026-01-01T00:00:00Z',
);

const _paths = [
  RouteNames.settings,
  RouteNames.safetyResources,
  '/planning/entry',
  '/journal',
  '/healing',
  '/games',
];

GoRouter _router() => GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(path: '/', builder: (_, __) => const Scaffold(body: Text('HOME'))),
    for (final p in _paths)
      GoRoute(
        path: p,
        builder:
            (_, __) =>
                Scaffold(appBar: AppBar(title: Text(p)), body: Text('AT $p')),
      ),
    GoRoute(
      path: '/tabs',
      builder:
          (_, __) => DefaultTabController(
            length: 3,
            child: Scaffold(
              appBar: AppBar(
                bottom: const TabBar(
                  tabs: [Tab(text: 'A'), Tab(text: 'B'), Tab(text: 'C')],
                ),
              ),
              body: const Text('TABS'),
            ),
          ),
    ),
    GoRoute(
      path: RouteNames.neutralScreen,
      name: 'neutralScreen',
      builder: (_, __) => const Scaffold(body: Text('DECOY')),
    ),
  ],
);

Future<GoRouter> _pump(WidgetTester t, {bool signedIn = true}) async {
  final router = _router();
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        currentUserProvider.overrideWithValue(signedIn ? _user : null),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        builder:
            (context, child) => QuickExitZone(router: router, child: child!),
      ),
    ),
  );
  await t.pumpAndSettle();
  return router;
}

Future<void> _tripleTap(WidgetTester t, Finder at) async {
  for (var i = 0; i < 3; i++) {
    await t.tap(at, warnIfMissed: false);
    await t.pump(const Duration(milliseconds: 50));
  }
  await t.pumpAndSettle(const Duration(milliseconds: 400));
}

final _zone = find.byKey(const Key('quick_exit_zone'));

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

  for (final p in _paths) {
    testWidgets('quick exit works on $p', (t) async {
      final router = await _pump(t);
      router.push(p);
      await t.pumpAndSettle();
      expect(find.text('AT $p'), findsOneWidget);
      await _tripleTap(t, _zone);
      expect(find.text('DECOY'), findsOneWidget);
    });
  }

  testWidgets('quick exit works over a pageless route (the full-screen map) '
      'and a dialog', (t) async {
    final router = await _pump(t);
    final nav = router.routerDelegate.navigatorKey.currentState!;
    nav.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('MAP')),
      ),
    );
    await t.pumpAndSettle();
    showDialog<void>(
      context: nav.context,
      builder: (_) => const AlertDialog(content: Text('DIALOG')),
    );
    await t.pumpAndSettle();
    await _tripleTap(t, _zone);
    expect(find.text('DECOY'), findsOneWidget);
    expect(find.text('DIALOG'), findsNothing);
  });

  testWidgets('quick exit works over a bottom sheet (review M-9)', (t) async {
    final router = await _pump(t);
    final nav = router.routerDelegate.navigatorKey.currentState!;
    showModalBottomSheet<void>(
      context: nav.context,
      isScrollControlled: true,
      builder: (_) => const SizedBox.expand(child: Text('SHEET')),
    );
    await t.pumpAndSettle();
    expect(find.text('SHEET'), findsOneWidget);
    await _tripleTap(t, _zone);
    expect(find.text('DECOY'), findsOneWidget);
    expect(find.text('SHEET'), findsNothing);
  });

  testWidgets('triple-tapping a centred tab under the toolbar does not exit', (
    t,
  ) async {
    final router = await _pump(t);
    router.push('/tabs');
    await t.pumpAndSettle();
    await _tripleTap(t, find.text('B'));
    expect(find.text('DECOY'), findsNothing);
    expect(find.text('TABS'), findsOneWidget);
  });

  testWidgets('signed out: the target does nothing', (t) async {
    await _pump(t, signedIn: false);
    await _tripleTap(t, _zone);
    expect(find.text('DECOY'), findsNothing);
  });
}

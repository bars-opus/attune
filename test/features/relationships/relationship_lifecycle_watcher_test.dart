// Spec 3a (review C3; F1 (2), (6)): the person who did not end it usually
// opens on Opinions, not Chat, so the one-time clear of this phone's
// Together surfaces and the warm ending sheet run from the app shell.
import 'package:attune/app/routing/app_router.dart' show RouteNames;
import 'package:attune/features/relationships/data/relationship_lifecycle_service.dart';
import 'package:attune/features/relationships/domain/relationship_lifecycle.dart';
import 'package:attune/features/relationships/presentation/relationship_lifecycle_providers.dart';
import 'package:attune/features/relationships/presentation/widgets/relationship_lifecycle_watcher.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

RelationshipLifecycle _l({
  LifecycleStatus status = LifecycleStatus.ended,
  bool endedByPartner = true,
  bool endedByMe = false,
  String? name = 'Ama',
}) => RelationshipLifecycle(
  relationshipId: 'r1',
  status: status,
  partnerFirstName: name,
  endedByMe: endedByMe,
  endedByPartner: endedByPartner,
  pausedByMe: false,
  endedAt: DateTime.utc(2026, 10, 1),
  windowEndsAt: DateTime.utc(2026, 10, 31),
  pausedAt: null,
  decideBy: null,
  sealedByMe: false,
  chatReadable: true,
);

class _Service extends RelationshipLifecycleService {
  _Service(this.value) : super(rpc: (fn, [p]) async => null);
  RelationshipLifecycle? value;
  int fetches = 0;
  @override
  Future<RelationshipLifecycle?> fetchLifecycle() async {
    fetches++;
    return value;
  }
}

Future<({GoRouter router, _Service service, List<int> clears})> _pump(
  WidgetTester t,
  RelationshipLifecycle? l, {
  String start = '/',
  String? userId = 'u1',
}) async {
  // A fresh mount, as after every resume (the privacy cover unmounts the
  // app's subtree); re-pumping the same tree would keep the old State.
  await t.pumpWidget(const SizedBox());
  final service = _Service(l);
  final clears = <int>[];
  final router = GoRouter(
    initialLocation: start,
    routes: [
      GoRoute(
        path: '/',
        builder: (_, __) => const Scaffold(body: Text('OPINIONS')),
      ),
      GoRoute(
        path: RouteNames.neutralScreen,
        builder: (_, __) => const Scaffold(body: Text('DECOY')),
      ),
    ],
  );
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        relationshipLifecycleServiceProvider.overrideWithValue(service),
        lifecycleClearSurfacesProvider.overrideWithValue(
          () async => clears.add(1),
        ),
        lifecycleUserIdProvider.overrideWithValue(userId),
        lifecycleLockOpenProvider.overrideWith((ref) => true),
      ],
      child: ScreenUtilInit(
        designSize: const Size(390, 844),
        builder:
            (_, __) => MaterialApp.router(
              routerConfig: router,
              builder:
                  (context, child) => RelationshipLifecycleWatcher(
                    router: router,
                    child: child!,
                  ),
            ),
      ),
    ),
  );
  await t.pumpAndSettle();
  return (router: router, service: service, clears: clears);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('first open after the partner ended it: clear once, sheet once, '
      'from any tab', (t) async {
    final w = await _pump(t, _l());
    expect(find.text('OPINIONS'), findsOneWidget);
    expect(find.text('Ama has ended your shared space.'), findsOneWidget);
    expect(w.clears.length, 1);
    await t.tap(find.text('Close'));
    await t.pumpAndSettle();
    final again = await _pump(t, _l());
    expect(again.clears, isEmpty);
    expect(find.text('Ama has ended your shared space.'), findsNothing);
  });

  testWidgets('paused: this phone is cleared, no sheet', (t) async {
    final w = await _pump(
      t,
      _l(status: LifecycleStatus.paused, endedByPartner: false),
    );
    expect(w.clears.length, 1);
    expect(find.textContaining('has ended your shared space'), findsNothing);
  });

  testWidgets('never over the quick-exit decoy', (t) async {
    final w = await _pump(t, _l(), start: RouteNames.neutralScreen);
    expect(find.text('DECOY'), findsOneWidget);
    expect(find.textContaining('has ended your shared space'), findsNothing);
    expect(w.service.fetches, 0);
  });

  testWidgets('signed out or active: nothing', (t) async {
    final a = await _pump(t, _l(), userId: null);
    expect(a.service.fetches, 0);
    final b = await _pump(t, null);
    expect(b.clears, isEmpty);
    expect(find.textContaining('has ended'), findsNothing);
  });

  testWidgets('an unknown partner is "Your partner" (review I11)', (t) async {
    await _pump(t, _l(name: null));
    expect(
      find.text('Your partner has ended your shared space.'),
      findsOneWidget,
    );
  });

  testWidgets('pause, resume, then end: this phone is cleared again at the '
      'end (final review IMP-1)', (t) async {
    final paused = await _pump(
      t,
      _l(status: LifecycleStatus.paused, endedByPartner: false),
    );
    expect(paused.clears.length, 1);
    final ended = await _pump(t, _l(endedByPartner: false, endedByMe: false));
    expect(ended.clears.length, 1, reason: 'a new state, a new clear');
    final again = await _pump(t, _l(endedByPartner: false, endedByMe: false));
    expect(again.clears, isEmpty);
  });

  testWidgets('a sheet the app lost before it was seen comes back '
      '(final review IMP-2)', (t) async {
    await _pump(t, _l());
    expect(find.text('Ama has ended your shared space.'), findsOneWidget);
    // The privacy cover unmounts everything on inactive: the sheet is gone
    // without the person having read it.
    await t.pumpWidget(const SizedBox());
    await t.pumpAndSettle();
    await _pump(t, _l());
    expect(find.text('Ama has ended your shared space.'), findsOneWidget);
    await t.tap(find.text('Close'));
    await t.pumpAndSettle();
    await _pump(t, _l());
    expect(find.text('Ama has ended your shared space.'), findsNothing);
  });
}

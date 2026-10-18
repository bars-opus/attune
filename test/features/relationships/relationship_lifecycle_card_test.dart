// Spec 3a (research 06 §3 F1 (2), (3), (6); 05 D.1): the lifecycle hub on
// the couples-locked chat screen, the one-time warm ending sheet, and pause.
import 'package:attune/app/routing/app_router.dart' show RouteNames;
import 'package:attune/core/utils/date_formatter.dart';
import 'package:attune/features/relationships/data/relationship_lifecycle_service.dart';
import 'package:attune/features/relationships/domain/relationship_lifecycle.dart';
import 'package:attune/features/relationships/presentation/relationship_lifecycle_providers.dart';
import 'package:attune/features/relationships/presentation/widgets/end_relationship_action.dart';
import 'package:attune/features/relationships/presentation/widgets/pause_relationship_action.dart';
import 'package:attune/features/relationships/presentation/widgets/relationship_lifecycle_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _now = DateTime.utc(2026, 10, 10, 9);

RelationshipLifecycle _l({
  LifecycleStatus status = LifecycleStatus.ended,
  bool endedByMe = false,
  bool endedByPartner = true,
  bool sealed = false,
  bool readable = true,
  DateTime? decideBy,
}) => RelationshipLifecycle(
  relationshipId: 'r1',
  status: status,
  partnerFirstName: 'Ama',
  endedByMe: endedByMe,
  endedByPartner: endedByPartner,
  pausedByMe: false,
  endedAt: DateTime.utc(2026, 10, 1, 9),
  windowEndsAt: DateTime.utc(2026, 10, 31, 9),
  pausedAt: status == LifecycleStatus.paused ? DateTime.utc(2026, 10, 1) : null,
  decideBy: decideBy,
  sealedByMe: sealed,
  chatReadable: readable,
);

class _Service extends RelationshipLifecycleService {
  _Service() : super(rpc: (fn, [p]) async => null);
  final calls = <String>[];
  @override
  Future<void> pause(String id) async => calls.add('pause $id');
  @override
  Future<void> resume(String id) async => calls.add('resume $id');
  @override
  Future<void> seal(String id) async => calls.add('seal $id');
  @override
  Future<void> endRelationship({required String relationshipId}) async =>
      calls.add('end $relationshipId');
}

class _World {
  _World(this.lifecycle);
  RelationshipLifecycle? lifecycle;
  final service = _Service();
  int loads = 0;
  int clears = 0;
  late GoRouter router;
}

Future<_World> _pump(WidgetTester t, RelationshipLifecycle? l) async {
  final w = _World(l);
  w.router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, __) => const Scaffold(body: RelationshipLifecycleCard()),
      ),
      GoRoute(
        path: RouteNames.chatChannel,
        builder:
            (_, s) => Text('CHAT ${s.uri.queryParameters['relationshipId']}'),
      ),
      GoRoute(
        path: RouteNames.healingJourney,
        builder: (_, __) => const Text('HEALING'),
      ),
      GoRoute(
        path: RouteNames.safetyResources,
        builder: (_, __) => const Text('RESOURCES'),
      ),
    ],
  );
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        relationshipLifecycleServiceProvider.overrideWithValue(w.service),
        relationshipLifecycleProvider.overrideWith((ref) async {
          w.loads++;
          return w.lifecycle;
        }),
        lifecycleClockProvider.overrideWithValue(() => _now),
        lifecycleClearSurfacesProvider.overrideWithValue(
          () async => w.clears++,
        ),
      ],
      child: ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, __) => MaterialApp.router(routerConfig: w.router),
      ),
    ),
  );
  await t.pumpAndSettle();
  return w;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('paused: days left, read, resume', (t) async {
    final w = await _pump(
      t,
      _l(
        status: LifecycleStatus.paused,
        decideBy: _now.add(const Duration(days: 12, hours: 3)),
      ),
    );
    expect(find.text('Your shared space is paused'), findsOneWidget);
    expect(
      find.text('Chat is read-only. 12 days left to decide.'),
      findsOneWidget,
    );
    await t.tap(find.text('Resume'));
    await t.pumpAndSettle();
    expect(w.service.calls, ['resume r1']);
    expect(w.loads, 2, reason: 'reloaded after resuming');
  });

  testWidgets('paused, last day', (t) async {
    await _pump(
      t,
      _l(
        status: LifecycleStatus.paused,
        decideBy: _now.add(const Duration(hours: 5)),
      ),
    );
    expect(
      find.text('Chat is read-only. Less than a day left to decide.'),
      findsOneWidget,
    );
  });

  testWidgets('ended and readable: the window date; seal asks first', (
    t,
  ) async {
    final w = await _pump(t, _l(endedByPartner: false, endedByMe: true));
    expect(find.text('Your shared space has ended'), findsOneWidget);
    expect(
      find.text(
        'You can read your chat until '
        '${MyDateFormat.toDate(DateTime.utc(2026, 10, 31, 9).toLocal())}. '
        'After that it closes, and 12 months later it is deleted.',
      ),
      findsOneWidget,
    );
    await t.tap(find.text('Seal my side now'));
    await t.pumpAndSettle();
    expect(find.text('Seal your side now?'), findsOneWidget);
    expect(w.service.calls, isEmpty);
    await t.tap(find.text('Seal'));
    await t.pumpAndSettle();
    expect(w.service.calls, ['seal r1']);
  });

  testWidgets('Read our chat opens the read-only chat', (t) async {
    await _pump(t, _l(endedByPartner: false, endedByMe: true));
    await t.tap(find.text('Read our chat'));
    await t.pumpAndSettle();
    expect(find.text('CHAT r1'), findsOneWidget);
  });

  testWidgets('day 30 before the cron: closed copy, no buttons (review I8)', (
    t,
  ) async {
    await _pump(t, _l(readable: false, endedByPartner: false, endedByMe: true));
    expect(find.text('Your shared space has ended'), findsOneWidget);
    expect(
      find.text('Your chat has closed. It is deleted 12 months from now.'),
      findsOneWidget,
    );
    expect(find.text('Read our chat'), findsNothing);
    expect(find.text('Seal my side now'), findsNothing);
  });

  testWidgets('sealed or archived: one quiet line, no buttons (review I8)', (
    t,
  ) async {
    await _pump(
      t,
      _l(sealed: true, readable: false, endedByPartner: false, endedByMe: true),
    );
    expect(find.text('Your shared space has ended.'), findsOneWidget);
    expect(find.text('Read our chat'), findsNothing);
    await _pump(
      t,
      _l(
        status: LifecycleStatus.archived,
        readable: false,
        endedByPartner: false,
      ),
    );
    expect(find.text('Your shared space has ended.'), findsOneWidget);
    expect(find.byType(OutlinedButton), findsNothing);
  });

  testWidgets('pause asks first, says no one is told, then pauses', (t) async {
    final service = _Service();
    var cleared = 0;
    await t.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder:
            (_, __) => MaterialApp(
              home: Builder(
                builder:
                    (context) => Scaffold(
                      body: TextButton(
                        onPressed:
                            () => PauseRelationshipAction.confirmAndPause(
                              context,
                              relationshipId: 'r1',
                              service: service,
                              clearSurfaces: () async => cleared++,
                            ),
                        child: const Text('GO'),
                      ),
                    ),
              ),
            ),
      ),
    );
    await t.tap(find.text('GO'));
    await t.pumpAndSettle();
    expect(find.text('Pause your shared space?'), findsOneWidget);
    expect(
      find.text(
        'Chat becomes read-only for both of you and nothing new is shared. '
        'Either of you can resume or end it within 30 days. '
        'Any game in progress ends. '
        "Your partner won't get a notification.",
      ),
      findsOneWidget,
    );
    await t.tap(find.text('Pause'));
    await t.pumpAndSettle();
    expect(service.calls, ['pause r1']);
    expect(cleared, 1);
  });

  testWidgets('end says the chat stays readable and no one is notified', (
    t,
  ) async {
    await t.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder:
            (_, __) => MaterialApp(
              home: Builder(
                builder:
                    (context) => Scaffold(
                      body: TextButton(
                        onPressed:
                            () => EndRelationshipAction.confirmAndEnd(
                              context,
                              relationshipId: 'r1',
                            ),
                        child: const Text('GO'),
                      ),
                    ),
              ),
            ),
      ),
    );
    await t.tap(find.text('GO'));
    await t.pumpAndSettle();
    expect(find.text('End your shared space?'), findsOneWidget);
    expect(
      find.text(
        "You'll both be able to read your chat for 30 days, then it closes. "
        'Closed chats are deleted after 12 months. '
        "Your partner won't get a notification; they'll see it the next time "
        'they open Attune.',
      ),
      findsOneWidget,
    );
    expect(find.text('End'), findsOneWidget);
  });

  testWidgets('ending from the paused card refreshes the card '
      '(final review IMP-4)', (t) async {
    final w = await _pump(
      t,
      _l(status: LifecycleStatus.paused, decideBy: _now.add(const Duration(days: 3))),
    );
    expect(w.loads, 1);
    await t.tap(find.text('End'));
    await t.pumpAndSettle();
    await t.tap(find.text('End').last);
    await t.pumpAndSettle();
    expect(w.loads, greaterThanOrEqualTo(2));
  });
}

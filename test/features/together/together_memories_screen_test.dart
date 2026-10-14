import 'package:attune/features/planning/presentation/planning_providers.dart'
    show planningChangeSignalProvider;
import 'package:attune/features/quiz/presentation/providers/quiz_providers.dart'
    as quiz;
import 'package:attune/features/timeline/presentation/providers/timeline_providers.dart'
    as timeline;
import 'package:attune/features/together/data/together_repository.dart';
import 'package:attune/features/together/presentation/screens/together_memories_screen.dart';
import 'package:attune/features/together/presentation/together_providers.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

import 'together_repository_test.dart' show FakeTogetherGateway;

Map<String, dynamic> _m(int i) => {
  'id': 'm$i',
  'relationship_id': 'r1',
  'logged_by': i.isEven ? 'ama' : 'kofi',
  'event_type': 'highlight',
  'title': 'Moment $i',
  'note': null,
  'mood_score': null,
  'occurred_at': DateTime(2026, 10, 30 - i).toIso8601String().split('T')[0],
  'created_at': '2026-10-01T10:00:00Z',
  'updated_at': null,
  'deleted_at': null,
  'visibility': 'shared',
  'couple_event_id': null,
};

Future<FakeTogetherGateway> _pump(
  WidgetTester t,
  dynamic Function(Map<String, dynamic>) page, {
  Stream<void>? signal,
}) async {
  t.view.physicalSize = const Size(1170, 2532);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  final g = FakeTogetherGateway({'list_together_moments': page});
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        togetherRepositoryProvider.overrideWithValue(TogetherRepository(g)),
        togetherMeProvider.overrideWithValue('ama'),
        quiz.partnerNameProvider.overrideWith((ref) async => 'Kofi'),
        timeline.togetherChangeSignalProvider.overrideWith(
          (ref, id) => signal ?? const Stream.empty(),
        ),
        planningChangeSignalProvider.overrideWith(
          (ref, id) => const Stream.empty(),
        ),
      ],
      child: ScreenUtilInit(
        designSize: const Size(375, 812),
        builder:
            (_, __) => const MaterialApp(
              home: TogetherMemoriesScreen(relationshipId: 'r1'),
            ),
      ),
    ),
  );
  await t.pumpAndSettle();
  return g;
}

void main() {
  testWidgets('pages back through memories as I scroll, without repeats', (
    t,
  ) async {
    final g = await _pump(t, (p) {
      if (p['p_before_id'] == null) return [for (var i = 0; i < 30; i++) _m(i)];
      if (p['p_before_id'] == 'm29') return [_m(30), _m(31)];
      return [];
    });
    expect(find.text('Moment 0'), findsOneWidget);
    await t.scrollUntilVisible(
      find.text('Moment 31'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    expect(g.calls[1].$2['p_before_id'], 'm29');
    expect(g.calls[1].$2['p_before_date'], _m(29)['occurred_at']);
    expect(find.text('Moment 31'), findsOneWidget);
    expect(g.calls.length, 2); // a short page means the end: no more calls
  });

  testWidgets('no memories yet shows the story empty state', (t) async {
    await _pump(t, (_) => []);
    expect(find.text('Your relationship story starts here.'), findsOneWidget);
  });

  testWidgets('a failed first page offers Try again', (t) async {
    var fail = true;
    final g = await _pump(t, (_) {
      if (fail) throw Exception('offline');
      return [_m(0)];
    });
    expect(find.text('Try again'), findsOneWidget);
    fail = false;
    await t.tap(find.text('Try again'));
    await t.pumpAndSettle();
    expect(find.text('Moment 0'), findsOneWidget);
    expect(g.calls.length, 2);
  });

  testWidgets('a change elsewhere refreshes in place, keeping my place', (
    t,
  ) async {
    final signal = StreamController<void>.broadcast();
    addTearDown(signal.close);
    final g = await _pump(t, (p) {
      if (p['p_before_id'] == 'm29') return [_m(30), _m(31)];
      if (p['p_before_id'] != null) return [];
      if (p['p_limit'] == 32) {
        return [
          {..._m(0), 'title': 'Moment 0 edited'},
          for (var i = 1; i < 32; i++) _m(i),
        ];
      }
      return [for (var i = 0; i < 30; i++) _m(i)];
    }, signal: signal.stream);
    await t.scrollUntilVisible(
      find.text('Moment 31'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    signal.add(null);
    await t.pump();
    // Still on screen while it re-reads: no skeleton, no jump to the top.
    expect(find.text('Moment 31'), findsOneWidget);
    await t.pumpAndSettle();
    expect(g.calls.last.$2['p_limit'], 32);
    expect(g.calls.last.$2['p_before_id'], isNull);
    expect(find.text('Moment 31'), findsOneWidget);
    expect(find.text('Moment 0 edited', skipOffstage: false), findsOneWidget);
  });

  testWidgets('a change during a page load is not lost to it', (t) async {
    final signal = StreamController<void>.broadcast();
    addTearDown(signal.close);
    final slowPage = Completer<List<Map<String, dynamic>>>();
    var refreshed = false;
    await _pump(t, (p) {
      if (p['p_before_id'] == 'm29') return slowPage.future;
      if (p['p_before_id'] != null) return [];
      if (refreshed) {
        return [
          {..._m(0), 'title': 'Moment 0 edited'},
          for (var i = 1; i < 30; i++) _m(i),
        ];
      }
      return [for (var i = 0; i < 30; i++) _m(i)];
    }, signal: signal.stream);
    await t.scrollUntilVisible(
      find.text('Moment 29'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await t.pump(); // the next page is now in flight
    refreshed = true;
    signal.add(null);
    await t.pump();
    slowPage.complete([_m(30), _m(31)]); // answers the old list: dropped
    await t.pumpAndSettle();
    expect(find.text('Moment 0 edited', skipOffstage: false), findsOneWidget);
    expect(find.text('Moment 30', skipOffstage: false), findsNothing);
  });
}

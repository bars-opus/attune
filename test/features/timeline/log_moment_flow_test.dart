import 'package:attune/core/utils/date_formatter.dart';
import 'package:attune/features/timeline/data/models/timeline_event_model.dart';
import 'package:attune/features/timeline/presentation/providers/timeline_providers.dart';
import 'package:attune/features/timeline/presentation/screens/log_moment_details_screen.dart';
import 'package:attune/features/timeline/presentation/screens/log_moment_type_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

GoRouter _router({DateTime? day, required void Function(Object?) onResult}) => GoRouter(
  routes: [
    GoRoute(
      path: '/',
      builder:
          (context, _) => Scaffold(
            body: TextButton(
              onPressed: () async {
                onResult(await context.pushNamed<bool>('logMomentType', extra: day));
              },
              child: const Text('calendar'),
            ),
          ),
    ),
    GoRoute(
      path: '/logMomentType',
      name: 'logMomentType',
      builder: (_, state) => LogMomentTypeScreen(initialDate: state.extra as DateTime?),
    ),
    GoRoute(
      path: '/logMomentDetails',
      name: 'logMomentDetails',
      builder: (_, state) {
        final args =
            state.extra
                as ({
                  String eventType,
                  String? editEventId,
                  Map<String, dynamic>? initialData,
                });
        return LogMomentDetailsScreen(eventType: args.eventType, initialData: args.initialData);
      },
    ),
  ],
);

void main() {
  testWidgets('logged from a day, the moment starts on that day', (t) async {
    t.view.physicalSize = const Size(1200, 4000);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    final day = DateTime(2026, 9, 12);
    await t.pumpWidget(
      ProviderScope(
        child: ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (_, __) => MaterialApp.router(routerConfig: _router(day: day, onResult: (_) {})),
        ),
      ),
    );
    await t.tap(find.text('calendar'));
    await t.pumpAndSettle();
    await t.tap(find.text('Highlight'));
    await t.pumpAndSettle();
    expect(find.text(MyDateFormat.toDate(day)), findsOneWidget);
  });

  testWidgets('saving a moment goes back to where it started, saying so', (t) async {
    t.view.physicalSize = const Size(1200, 4000);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    Object? result = 'none';
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder:
              (context, _) => Scaffold(
                body: TextButton(
                  onPressed: () async {
                    result = await context.pushNamed<bool>('logMomentType');
                  },
                  child: const Text('calendar'),
                ),
              ),
        ),
        GoRoute(
          path: '/logMomentType',
          name: 'logMomentType',
          builder: (_, __) => const LogMomentTypeScreen(),
        ),
        GoRoute(
          path: '/logMomentDetails',
          name: 'logMomentDetails',
          builder: (_, state) {
            final args =
                state.extra
                    as ({
                      String eventType,
                      String? editEventId,
                      Map<String, dynamic>? initialData,
                    });
            return LogMomentDetailsScreen(eventType: args.eventType);
          },
        ),
      ],
    );
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          createTimelineEventProvider.overrideWith(
            (ref, p) async => TimelineEventModel(
              id: 'e1',
              relationshipId: 'rel',
              loggedBy: 'ama',
              eventType: p.eventType,
              title: p.title,
              occurredAt: p.occurredAt,
              createdAt: p.occurredAt,
            ),
          ),
        ],
        child: ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (_, __) => MaterialApp.router(routerConfig: router),
        ),
      ),
    );
    await t.tap(find.text('calendar'));
    await t.pumpAndSettle();
    await t.tap(find.text('Highlight'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextFormField).first, 'Date night');
    await t.pump();
    await t.tap(find.text('Save'));
    await t.pumpAndSettle();
    expect(find.byType(LogMomentTypeScreen), findsNothing);
    expect(find.text('calendar'), findsOneWidget);
    expect(result, true);
  });
}

import 'package:attune/features/timeline/data/models/timeline_event_model.dart';
import 'package:attune/features/timeline/presentation/providers/timeline_providers.dart';
import 'package:attune/features/timeline/presentation/widgets/moment_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets("a partner's moment says who logged it", (tester) async {
    final event = TimelineEventModel.fromJson({
      'id': 'e1',
      'relationship_id': 'rel',
      'logged_by': 'kofi',
      'event_type': 'highlight',
      'title': 'Beach day',
      'note': null,
      'mood_score': null,
      'occurred_at': '2026-10-10',
      'created_at': '2026-10-10T10:00:00Z',
      'updated_at': null,
      'deleted_at': null,
    });
    await tester.pumpWidget(
      ProviderScope(
        child: ScreenUtilInit(
          designSize: const Size(375, 812),
          builder:
              (_, __) => MaterialApp(
                home: Scaffold(
                  body: MomentCard(
                    event: event,
                    currentUserId: 'ama',
                    currentMonth: DateTime(2026, 10),
                    partnerName: 'Kofi',
                  ),
                ),
              ),
        ),
      ),
    );
    expect(find.text('Logged by: Kofi'), findsOneWidget);
  });

  for (final fails in [false, true])
    testWidgets(fails ? 'a failed delete says so' : 'deleting my moment says it was deleted', (tester) async {
      final event = TimelineEventModel.fromJson({
        'id': 'e1', 'relationship_id': 'rel', 'logged_by': 'ama', 'event_type': 'highlight',
        'title': 'Beach day', 'note': null, 'mood_score': null, 'occurred_at': '2026-10-10',
        'created_at': '2026-10-10T10:00:00Z', 'updated_at': null, 'deleted_at': null,
      });
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            deleteTimelineEventProvider.overrideWith((ref, id) async {
              if (fails) throw Exception('offline');
            }),
            timelineEventsProvider.overrideWith((ref, month) async => []),
          ],
          child: ScreenUtilInit(
            designSize: const Size(375, 812),
            builder:
                (_, __) => MaterialApp(
                  home: Scaffold(
                    body: MomentCard(event: event, currentUserId: 'ama', currentMonth: DateTime(2026, 10), partnerName: 'Kofi'),
                  ),
                ),
          ),
        ),
      );
      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete').last);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Delete'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text(fails ? "Couldn't delete that moment. Please try again." : 'Moment deleted'), findsOneWidget);
    });
}

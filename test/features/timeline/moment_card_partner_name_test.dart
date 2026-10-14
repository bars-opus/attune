import 'package:attune/features/timeline/data/models/timeline_event_model.dart';
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
}

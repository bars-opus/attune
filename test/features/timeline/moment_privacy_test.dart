import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/timeline/data/models/timeline_event_model.dart';
import 'package:attune/features/timeline/presentation/providers/timeline_providers.dart';
import 'package:attune/features/timeline/presentation/screens/log_moment_details_screen.dart';
import 'package:attune/features/timeline/presentation/widgets/moment_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _row({String type = 'conflict', String? visibility}) => {
  'id': 'e1',
  'relationship_id': 'rel',
  'logged_by': 'ama',
  'event_type': type,
  'title': 'Money talk',
  'note': null,
  'mood_score': null,
  'occurred_at': '2026-10-10',
  'created_at': '2026-10-10T10:00:00Z',
  'updated_at': null,
  'deleted_at': null,
  if (visibility != null) 'visibility': visibility,
};

Future<List<String?>> _pumpForm(
  WidgetTester t, {
  required String type,
  Map<String, dynamic>? initialData,
  String? editId,
}) async {
  final sent = <String?>[];
  t.view.physicalSize = const Size(1200, 4000);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        createTimelineEventProvider.overrideWith((ref, p) async {
          sent.add(p.visibility);
          return TimelineEventModel.fromJson(_row(type: p.eventType));
        }),
        updateTimelineEventProvider.overrideWith((ref, p) async {
          sent.add(p.visibility);
          return TimelineEventModel.fromJson(_row(type: type));
        }),
      ],
      child: MaterialApp(
        home: ScreenUtilInit(
          designSize: const Size(390, 844),
          builder:
              (_, __) => LogMomentDetailsScreen(
                eventType: type,
                editEventId: editId,
                initialData: initialData,
              ),
        ),
      ),
    ),
  );
  await t.pumpAndSettle();
  return sent;
}

void main() {
  test('a moment row maps its visibility; old rows are shared', () {
    expect(TimelineEventModel.fromJson(_row()).isPrivate, isFalse);
    expect(
      TimelineEventModel.fromJson(_row(visibility: 'private')).isPrivate,
      isTrue,
    );
  });

  testWidgets('a conflict can be kept just for me', (t) async {
    final sent = await _pumpForm(t, type: 'conflict');
    await t.enterText(find.byType(TextFormField).first, 'Money talk');
    await t.tap(find.byType(AppToggleSwitch));
    await t.pumpAndSettle();
    await t.tap(find.text('Save moment'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    expect(sent, ['private']);
  });

  testWidgets('other moments have no privacy switch', (t) async {
    await _pumpForm(t, type: 'highlight');
    expect(find.text('Just for me'), findsNothing);
  });

  testWidgets('editing a private conflict keeps it private', (t) async {
    final sent = await _pumpForm(
      t,
      type: 'conflict',
      editId: 'e1',
      initialData: {
        'title': 'Money talk',
        'occurred_at': DateTime(2026, 10, 10),
        'visibility': 'private',
      },
    );
    await t.tap(find.text('Save changes'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    expect(sent, ['private']);
  });

  testWidgets('my private conflict says only I can see it', (t) async {
    await t.pumpWidget(
      ProviderScope(
        child: ScreenUtilInit(
          designSize: const Size(375, 812),
          builder:
              (_, __) => MaterialApp(
                home: Scaffold(
                  body: MomentCard(
                    event: TimelineEventModel.fromJson(
                      _row(visibility: 'private'),
                    ),
                    currentUserId: 'ama',
                    currentMonth: DateTime(2026, 10),
                    partnerName: 'Kofi',
                  ),
                ),
              ),
        ),
      ),
    );
    expect(find.text('Only you can see this'), findsOneWidget);
  });
}

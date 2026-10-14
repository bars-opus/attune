import 'dart:io';

import 'package:attune/features/together/domain/together_item.dart';
import 'package:attune/features/timeline/presentation/widgets/calendar_day_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:attune/features/stories/data/story_read_repository.dart';
import 'package:attune/features/stories/presentation/providers/story_providers.dart';
import 'package:attune/features/together/presentation/together_providers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('the day sheet lists a Together event by its title', (t) async {
    final item = TogetherItem(
      kind: TogetherItemKind.event,
      id: 'e1',
      date: DateTime(2026, 11, 6),
      allDay: true,
      title: 'Dinner at Buka',
      participantIds: const ['ama', 'kofi'],
    );
    await t.pumpWidget(
      ProviderScope(
        overrides: [togetherMeProvider.overrideWithValue('ama')],
        child: ScreenUtilInit(
          designSize: const Size(375, 812),
          builder:
              (_, __) => MaterialApp(
                home: Scaffold(
                  body: CalendarDaySheet(
                    relationshipId: null,
                    date: DateTime(2026, 11, 6),
                    events: const [],
                    reminders: const [],
                    planningEntries: [item],
                  ),
                ),
              ),
        ),
      ),
    );
    expect(find.text('Dinner at Buka'), findsOneWidget);
  });

  test(
    'Planning\'s Calendar tab is the Together screen and the Map placeholder is gone',
    () {
      final src =
          File(
            'lib/features/planning/presentation/screens/planning_home_screen.dart',
          ).readAsStringSync();
      expect(src, contains('TogetherScreen(embedded: true)'));
      expect(src, isNot(contains("label: 'Map'")));
    },
  );

  testWidgets("the day sheet doesn't open a partner's busy block", (t) async {
    final busy = TogetherItem(
      kind: TogetherItemKind.event,
      id: 'b1',
      date: DateTime(2026, 11, 6),
      allDay: true,
      title: 'Busy',
      participantIds: const ['kofi'],
      createdBy: 'kofi',
      visibility: TogetherVisibility.busyOnly,
    );
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          togetherMeProvider.overrideWithValue('ama'),
          currentUserProvider.overrideWithValue(null),
          storyReadGatewayProvider.overrideWithValue(_EmptyStoryGateway()),
        ],
        child: ScreenUtilInit(
          designSize: const Size(375, 812),
          builder:
              (_, __) => MaterialApp(
                home: Scaffold(
                  body: CalendarDaySheet(
                    relationshipId: 'r1',
                    date: DateTime(2026, 11, 6),
                    events: const [],
                    reminders: const [],
                    planningEntries: [busy],
                  ),
                ),
              ),
        ),
      ),
    );
    final tile = t.widget<InkWell>(
      find
          .ancestor(of: find.text('Busy'), matching: find.byType(InkWell))
          .first,
    );
    expect(tile.onTap, isNull);
  });
}

/// A day with no stories.
class _EmptyStoryGateway implements StoryReadGateway {
  @override
  Future<StoryItemPage> listDayItems({
    required String relationshipId,
    required DateTime occurredOn,
    StoryPageCursor? after,
    int limit = 50,
  }) async => const StoryItemPage(items: [], nextCursor: null);

  @override
  Stream<void> watchChangeSignal({required String relationshipId}) =>
      const Stream.empty();

  @override
  void disposeChannel(String relationshipId) {}

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

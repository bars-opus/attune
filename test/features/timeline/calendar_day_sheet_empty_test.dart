import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:attune/features/stories/data/story_read_repository.dart';
import 'package:attune/features/stories/presentation/providers/story_providers.dart';
import 'package:attune/features/timeline/presentation/widgets/calendar_day_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

/// A day with no stories; anything else the sheet asks for is a bug.
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

void main() {
  testWidgets('an empty day says so even when signed in', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserProvider.overrideWithValue(null),
          storyReadGatewayProvider.overrideWithValue(_EmptyStoryGateway()),
        ],
        child: ScreenUtilInit(
          designSize: const Size(375, 812),
          builder:
              (_, __) => MaterialApp(
                home: Scaffold(
                  body: CalendarDaySheet(
                    relationshipId: 'rel-1',
                    date: DateTime(2026, 10, 14),
                    events: const [],
                    reminders: const [],
                    planningEntries: const [],
                  ),
                ),
              ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('No moments or plans on this day.'), findsOneWidget);
  });
}

import 'package:attune/core/widgets/info_row_widget.dart';
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
    'Planning\'s Calendar tab is the Together screen; Map is the real couple map, behind its flag',
    () {
      final src =
          File(
            'lib/features/planning/presentation/screens/planning_home_screen.dart',
          ).readAsStringSync();
      expect(src, contains('TogetherScreen(embedded: true)'));
      // The old Map placeholder stays gone: the only Map tab is the couple
      // map (owner ruling 2026-10-15), shown only with couple_map_enabled.
      final map = src.indexOf("label: 'Map'");
      if (map != -1) {
        final tab = src.substring(
          src.lastIndexOf('if (mapEnabled)', map),
          map + 200,
        );
        // The map is no longer embedded in the tabs…
        expect(tab, isNot(contains('CoupleMapTab(')));
        // …tapping Map opens the real couple map full screen (owner,
        // 2026-10-16), never a placeholder.
        expect(src, contains('openCoupleMap(context, widget.relationshipId)'));
        final screen =
            File(
              'lib/features/couple_map/presentation/screens/couple_map_screen.dart',
            ).readAsStringSync();
        expect(screen, contains('CoupleMapTab(relationshipId: relationshipId, onBack: onBack)'));
      }
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
    // Shown as the Agenda's row, with nothing to open.
    final row = t.widget<InfoRowWidget>(
      find
          .ancestor(of: find.text('Busy'), matching: find.byType(InfoRowWidget))
          .first,
    );
    expect(row.onTap, isNull);
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

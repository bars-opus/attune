// 04 #4/#5: the day sheet counts the whole day, opens each author's own
// stories, says when it could not load them (with Retry), and shows a
// placeholder while loading.
import 'dart:async';

import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:attune/features/chat/domain/services/chat_image_cache.dart';
import 'package:attune/features/quiz/presentation/providers/quiz_providers.dart'
    show partnerNameProvider;
import 'package:attune/features/stories/data/story_read_repository.dart';
import 'package:attune/features/stories/presentation/providers/story_providers.dart';
import 'package:attune/features/stories/presentation/screens/story_reel_screen.dart';
import 'package:attune/features/stories/presentation/widgets/story_ring.dart';
import 'package:attune/features/timeline/presentation/widgets/calendar_day_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../stories/support/ring_test_kit.dart';

final _day = DateTime(2026, 6, 15);

StoryDayCount _count(String author, int n, int day) => StoryDayCount(
  occurredOn: _day,
  authorId: author,
  itemCount: n,
  dayItemCount: day,
  newestThumbnailKey: 'story-media/$author-newest.jpg',
  newestCreatedAt: _day,
);

Future<void> _openSheet(WidgetTester tester, RingGateway gateway) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentUserProvider.overrideWithValue(ringUser),
        storyReadGatewayProvider.overrideWithValue(gateway),
        chatImageCacheProvider.overrideWithValue(NoopImageCache()),
        partnerNameProvider.overrideWith((ref) async => 'Kofi'),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder:
                (context) => TextButton(
                  onPressed:
                      () => showCalendarDaySheet(
                        context: context,
                        relationshipId: ringRel,
                        date: _day,
                        events: const [],
                        reminders: const [],
                        planningEntries: const [],
                      ),
                  child: const Text('open'),
                ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  testWidgets("the sheet counts the whole day and names the partner's ring", (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final gateway =
        RingGateway()
          ..dayCounts = [_count(ringMe, 50, 60), _count(ringPartner, 10, 60)];
    await _openSheet(tester, gateway);
    expect(find.text('60 stories'), findsOneWidget);
    final partner = tester.widget<StoryRing>(
      find.descendant(
        of: find.byKey(const ValueKey('day-story-ring-$ringPartner')),
        matching: find.byType(StoryRing),
      ),
    );
    expect(partner.segmentCount, 10);
    expect(
      find.bySemanticsLabel("Kofi's stories from this day, 10 items"),
      findsOneWidget,
    );
    handle.dispose();
  });

  testWidgets("tapping the partner's ring opens only the partner's stories", (
    tester,
  ) async {
    final gateway =
        RingGateway()
          ..dayCounts = [_count(ringMe, 2, 3), _count(ringPartner, 1, 3)];
    await _openSheet(tester, gateway);
    await tester.tap(find.byKey(const ValueKey('day-story-ring-$ringPartner')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    final reel = tester.widget<StoryReelScreen>(find.byType(StoryReelScreen));
    expect(reel.dayAuthorId, ringPartner);
    expect(reel.occurredOn, _day);
  });

  testWidgets("when the day's stories fail to load, it says so and retries", (
    tester,
  ) async {
    final gateway =
        RingGateway()
          ..dayCountsError = StateError('offline')
          ..dayItemsError = StateError('offline');
    await _openSheet(tester, gateway);
    await tester.pump();
    expect(find.text("Couldn't load this day's stories."), findsOneWidget);
    gateway
      ..dayCountsError = null
      ..dayItemsError = null
      ..dayCounts = [_count(ringPartner, 1, 1)];
    final counts = gateway.dayCountCalls;
    final items = gateway.dayItemCalls;
    await tester.tap(find.text('Retry'));
    await tester.pump();
    await tester.pump();
    expect(gateway.dayCountCalls, counts + 1);
    expect(gateway.dayItemCalls, items + 1);
    expect(find.text('1 story'), findsOneWidget);
  });

  testWidgets('while loading, a placeholder holds the place', (tester) async {
    final handle = tester.ensureSemantics();
    final gateway =
        RingGateway()
          ..dayCountsGate = Completer<void>()
          ..dayItemsGate = Completer<void>();
    await _openSheet(tester, gateway);
    expect(find.bySemanticsLabel('Loading stories'), findsOneWidget);
    gateway.dayCountsGate!.complete();
    gateway.dayItemsGate!.complete();
    await tester.pump();
    await tester.pump();
    expect(find.bySemanticsLabel('Loading stories'), findsNothing);
    handle.dispose();
  });

  // Fix round 1, M-3: with the month's counts cached and the day's items
  // still loading, the partner's ring must not draw all-seen first.
  testWidgets("the partner's ring never flashes all-seen while the day "
      'loads', (tester) async {
    final handle = tester.ensureSemantics();
    final gateway =
        RingGateway()
          ..dayCounts = [_count(ringPartner, 1, 1)]
          ..dayItems = [
            StoryItem(
              id: 'p1',
              clientStoryId: 'c-p1',
              relationshipId: ringRel,
              authorId: ringPartner,
              mediaType: 'image',
              mediaKey: 'story-media/p1.jpg',
              thumbnailKey: 'story-media/p1-thumb.jpg',
              mediaWidth: 1080,
              mediaHeight: 1920,
              occurredOn: _day,
              createdAt: _day,
              expiresAt: _day.add(const Duration(hours: 24)),
              hasBeenViewed: false,
            ),
          ]
          ..dayItemsGate = Completer<void>();
    await _openSheet(tester, gateway);
    final ring = find.descendant(
      of: find.byKey(const ValueKey('day-story-ring-$ringPartner')),
      matching: find.byType(StoryRing),
    );
    for (final w in ring.evaluate()) {
      expect((w.widget as StoryRing).unviewedCount, isNot(0));
    }
    expect(find.bySemanticsLabel('Loading stories'), findsOneWidget);
    gateway.dayItemsGate!.complete();
    await tester.pump();
    await tester.pump();
    expect(tester.widget<StoryRing>(ring).unviewedCount, 1);
    handle.dispose();
  });

  testWidgets("with the server's unviewed counts the partner's ring draws "
      'before the day loads (Wave 5)', (tester) async {
    final gateway =
        RingGateway()
          ..dayCounts = [
            StoryDayCount(
              occurredOn: _day,
              authorId: ringPartner,
              itemCount: 3,
              dayItemCount: 3,
              newestThumbnailKey: 'story-media/$ringPartner-newest.jpg',
              newestCreatedAt: _day,
              unviewedCount: 2,
            ),
          ]
          ..dayItemsGate = Completer<void>();
    await _openSheet(tester, gateway);
    final ring = find.descendant(
      of: find.byKey(const ValueKey('day-story-ring-$ringPartner')),
      matching: find.byType(StoryRing),
    );
    expect(ring, findsOneWidget);
    expect(tester.widget<StoryRing>(ring).unviewedCount, 2);
    gateway.dayItemsGate!.complete();
    await tester.pump();
  });
}

// 04 #5: a calendar month whose story counts failed used to look like a
// month with no stories. It now says so, with Retry.
import 'dart:async';

import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:attune/features/chat/domain/services/chat_image_cache.dart';
import 'package:attune/features/stories/data/story_read_repository.dart';
import 'package:attune/features/stories/presentation/providers/story_providers.dart';
import 'package:attune/features/timeline/presentation/widgets/story_month_load_error.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../stories/support/ring_test_kit.dart';

Future<void> _pump(WidgetTester tester, RingGateway gateway) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentUserProvider.overrideWithValue(ringUser),
        storyReadGatewayProvider.overrideWithValue(gateway),
        chatImageCacheProvider.overrideWithValue(NoopImageCache()),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: StoryMonthLoadErrorRow(
            relationshipId: ringRel,
            month: DateTime(2026, 6, 1),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('a failed month says so and retries', (tester) async {
    final gateway = RingGateway()..dayCountsError = StateError('offline');
    await _pump(tester, gateway);
    expect(find.text("Couldn't load this month's stories."), findsOneWidget);
    gateway.dayCountsError = null;
    await tester.tap(find.text('Retry'));
    await tester.pump();
    await tester.pump();
    expect(gateway.dayCountCalls, 2);
    expect(find.text("Couldn't load this month's stories."), findsNothing);
  });

  testWidgets('a loaded month shows nothing extra', (tester) async {
    final gateway =
        RingGateway()
          ..dayCounts = [
            StoryDayCount(
              occurredOn: DateTime(2026, 6, 3),
              itemCount: 1,
              authorId: ringPartner,
            ),
          ];
    await _pump(tester, gateway);
    expect(find.byType(TextButton), findsNothing);
  });

  testWidgets(
    'a re-read that shows a past story deleted evicts its thumbnail',
    (tester) async {
      final evictor = RecordingEvictor();
      final gateway =
          RingGateway()
            ..dayCounts = [
              StoryDayCount(
                occurredOn: DateTime(2026, 6, 3),
                itemCount: 1,
                authorId: ringPartner,
                newestThumbnailKey: 'gone',
                newestCreatedAt: DateTime(2026, 6, 3, 9),
              ),
            ];
      final c = ringContainer(
        gateway,
        overrides: [storyMediaEvictorProvider.overrideWithValue(evictor)],
      );
      final key = StoryDayRangeKey.month(
        relationshipId: ringRel,
        day: DateTime(2026, 6, 1),
      );
      final sub = c.listen(storyDayCountsProvider(key), (_, __) {});
      await tester.pump(Duration.zero);
      gateway.dayCounts = [];
      gateway.emitSignal();
      await tester.pump(Duration.zero);
      await tester.pump(Duration.zero);
      expect(evictor.evicted, ['gone']);
      sub.close();
      await tester.pump(Duration.zero);
      c.dispose();
    },
  );

  // Fix round 1, M-4: Retry shows progress while the month reloads, and
  // cannot be tapped twice.
  testWidgets('Retry shows progress while the month reloads', (tester) async {
    final gateway = RingGateway()..dayCountsError = StateError('offline');
    await _pump(tester, gateway);
    gateway
      ..dayCountsError = null
      ..dayCountsGate = Completer<void>();
    await tester.tap(find.text('Retry'));
    await tester.pump();
    expect(find.text('Retry'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(gateway.dayCountCalls, 2);
    gateway.dayCountsGate!.complete();
    await tester.pump();
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text("Couldn't load this month's stories."), findsNothing);
  });

  // Fix round 1, M-2: a signal that lands while a re-read is in flight
  // must not lose that re-read's dropped keys.
  testWidgets('a signal during a re-read still evicts what it dropped', (
    tester,
  ) async {
    final evictor = RecordingEvictor();
    final gateway =
        RingGateway()
          ..dayCounts = [
            StoryDayCount(
              occurredOn: DateTime(2026, 6, 3),
              itemCount: 1,
              authorId: ringPartner,
              newestThumbnailKey: 'gone',
              newestCreatedAt: DateTime(2026, 6, 3, 9),
            ),
          ];
    final c = ringContainer(
      gateway,
      overrides: [storyMediaEvictorProvider.overrideWithValue(evictor)],
    );
    final key = StoryDayRangeKey.month(
      relationshipId: ringRel,
      day: DateTime(2026, 6, 1),
    );
    final sub = c.listen(storyDayCountsProvider(key), (_, __) {});
    await tester.pump(Duration.zero);
    final gate = gateway.dayCountsGate = Completer<void>();
    gateway.dayCounts = [];
    gateway.emitSignal();
    await tester.pump(Duration.zero);
    await tester.pump(Duration.zero);
    expect(gateway.dayCountCalls, 2);
    // A second signal lands in the same tick the re-read returns, before
    // the provider rebuilds.
    gateway.emitSignal();
    await Future<void>.value();
    gate.complete();
    await tester.pump(Duration.zero);
    await tester.pump(Duration.zero);
    await tester.pump(Duration.zero);
    expect(evictor.evicted, ['gone']);
    sub.close();
    await tester.pump(Duration.zero);
    c.dispose();
  });
}

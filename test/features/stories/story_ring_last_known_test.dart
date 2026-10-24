// 03 M3: a cold start offline, or a failed first read, paints the last
// rings this phone saw (ids, counts and storage keys only) instead of "Add
// to your story" and no partner ring, and says the read failed, with Retry.
import 'dart:async';

import 'package:attune/features/stories/data/story_ring_last_known_store.dart';
import 'package:attune/features/stories/presentation/providers/story_providers.dart';
import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/ring_test_kit.dart';

StoryRingSnapshot _snapshot({
  String userId = ringMe,
  String relationshipId = ringRel,
  Duration age = const Duration(minutes: 5),
}) {
  final now = clock.now();
  return StoryRingSnapshot(
    userId: userId,
    relationshipId: relationshipId,
    savedAt: now.subtract(age),
    rows: [
      ringRow(author: ringMe, active: 3, unviewed: 0),
      ringRow(author: ringPartner, active: 2, unviewed: 2),
    ],
  );
}

void main() {
  group('StoryRingSnapshot', () {
    test('round-trips through JSON without URLs', () {
      final snapshot = _snapshot();
      final json = snapshot.toJson();
      expect(json.toString().contains('http'), isFalse);
      final back = StoryRingSnapshot.fromJson(json)!;
      expect(back.userId, ringMe);
      expect(back.rows.map((r) => r.activeCount), [3, 2]);
      expect(StoryRingSnapshot.fromJson('garbage'), isNull);
    });

    test('a snapshot from another account or relationship is never shown '
        '(Review Focus 2)', () {
      final now = clock.now();
      expect(
        _snapshot(
          userId: 'someone-else',
        ).usableFor(userId: ringMe, relationshipId: ringRel, now: now),
        isNull,
      );
      expect(
        _snapshot(
          relationshipId: 'old-rel',
        ).usableFor(userId: ringMe, relationshipId: ringRel, now: now),
        isNull,
      );
      expect(
        _snapshot(
          age: const Duration(hours: 25),
        ).usableFor(userId: ringMe, relationshipId: ringRel, now: now),
        isNull,
      );
    });

    test('rows whose newest story is over a day old are dropped', () {
      final now = clock.now();
      final snapshot = StoryRingSnapshot(
        userId: ringMe,
        relationshipId: ringRel,
        savedAt: now,
        rows: [ringRow(newest: now.subtract(const Duration(hours: 25)))],
      );
      expect(
        snapshot.usableFor(userId: ringMe, relationshipId: ringRel, now: now),
        isEmpty,
      );
    });
  });

  testWidgets('a good read is saved once, and not rewritten unchanged', (
    tester,
  ) async {
    final store = MemoryStoryRingLastKnownStore();
    final gateway = RingGateway(summary: [ringRow()]);
    final c = ringContainer(gateway, lastKnown: store);
    final sub = c.listen(storyRingSummaryProvider(ringRel), (_, __) {});
    await tester.pump(Duration.zero);
    await tester.pump(Duration.zero);
    expect(store.value!.rows.single.authorId, ringPartner);
    gateway.emitSignal();
    await tester.pump(Duration.zero);
    await tester.pump(Duration.zero);
    expect(store.writes, 1);
    sub.close();
    await tester.pump(Duration.zero);
    c.dispose();
  });

  testWidgets('a clear() during an in-flight read is not undone by its '
      'write (review #1)', (tester) async {
    final store = MemoryStoryRingLastKnownStore();
    final gateway = RingGateway(summary: [ringRow()])
      ..summaryGate = Completer<void>();
    final c = ringContainer(gateway, lastKnown: store);
    final sub = c.listen(storyRingSummaryProvider(ringRel), (_, __) {});
    await tester.pump(Duration.zero);
    await store.clear(); // quick exit / pause wipe (Task 9)
    final gate = gateway.summaryGate!;
    gateway.summaryGate = null;
    gate.complete();
    await tester.pump(Duration.zero);
    await tester.pump(Duration.zero);
    expect(store.value, isNull);
    // The next read, started after the wipe, saves again, stamped with
    // when it started.
    final startedAt = clock.now();
    gateway.emitSignal();
    await tester.pump(Duration.zero);
    await tester.pump(Duration.zero);
    expect(store.value, isNotNull);
    expect(store.value!.savedAt, startedAt);
    sub.close();
    await tester.pump(Duration.zero);
    c.dispose();
  });

  testWidgets('the first read after a launch evicts a story deleted while '
      'Attune was closed (review #3)', (tester) async {
    final now = clock.now();
    final evictor = RecordingEvictor();
    final store =
        MemoryStoryRingLastKnownStore()
          ..value = StoryRingSnapshot(
            userId: ringMe,
            relationshipId: ringRel,
            savedAt: now.subtract(const Duration(minutes: 5)),
            rows: [
              ringRow(
                active: 2,
                key: 'b',
                newest: now.subtract(const Duration(hours: 1)),
              ),
            ],
          );
    final gateway = RingGateway(
      summary: [
        ringRow(key: 'a', newest: now.subtract(const Duration(hours: 2))),
      ],
    );
    final c = ringContainer(
      gateway,
      lastKnown: store,
      overrides: [storyMediaEvictorProvider.overrideWithValue(evictor)],
    );
    final sub = c.listen(storyRingSummaryProvider(ringRel), (_, __) {});
    await tester.pump(Duration.zero);
    await tester.pump(Duration.zero);
    expect(evictor.evicted, ['b']);
    sub.close();
    await tester.pump(Duration.zero);
    c.dispose();
  });

  testWidgets('while the first read is in flight, the last rings show', (
    tester,
  ) async {
    final gateway = RingGateway()..summaryGate = Completer<void>();
    await pumpRings(
      tester,
      gateway,
      lastKnown: MemoryStoryRingLastKnownStore()..value = _snapshot(),
    );
    await tester.pump();
    expect(mineRing(tester).segmentCount, 3);
    expect(find.byKey(const ValueKey('story-ring-partner')), findsOneWidget);
    expect(find.textContaining("Couldn't"), findsNothing);
  });

  testWidgets('a failed read keeps the last rings and offers Retry', (
    tester,
  ) async {
    final gateway = RingGateway()..summaryError = StateError('offline');
    await pumpRings(
      tester,
      gateway,
      lastKnown: MemoryStoryRingLastKnownStore()..value = _snapshot(),
    );
    await tester.pump();
    expect(
      find.text("Showing your last stories. Couldn't refresh."),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('story-ring-partner')), findsOneWidget);
    gateway
      ..summaryError = null
      ..summary = [ringRow()];
    final before = gateway.summaryCalls;
    await tester.tap(find.text('Retry'));
    await tester.pump();
    await tester.pump();
    expect(gateway.summaryCalls, before + 1);
    expect(find.textContaining("Couldn't"), findsNothing);
  });

  testWidgets('a failed read with nothing saved says so', (tester) async {
    final gateway = RingGateway()..summaryError = StateError('offline');
    await pumpRings(tester, gateway);
    await tester.pump();
    expect(find.text("Couldn't load stories."), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });
}

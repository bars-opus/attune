// 03 M2/L6, 04 #15: the ring summary has one fetch in flight with at most
// one follow-up, retries a failed read on a backoff, re-reads when its
// newest story expires, waits while Attune is hidden, and evicts the
// thumbnail of a story the partner deleted.
import 'dart:async';

import 'package:attune/core/services/app_content_visibility.dart';
import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:attune/features/chat/domain/services/chat_image_cache.dart';
import 'package:attune/features/stories/data/story_ring_last_known_store.dart';

import 'package:attune/features/stories/data/story_read_repository.dart';
import 'package:attune/features/stories/presentation/providers/story_providers.dart';
import 'package:attune/features/stories/presentation/state/story_ring_refresh.dart';
import 'package:clock/clock.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/ring_test_kit.dart';

void main() {
  group('storyRingExpiryDelay', () {
    final now = DateTime.utc(2026, 10, 24, 12);

    test('the newest story ending soon is due a second after its end', () {
      final rows = [
        ringRow(newest: now.subtract(const Duration(hours: 23, minutes: 59))),
      ];
      expect(
        storyRingExpiryDelay(rows, now),
        const Duration(minutes: 1, seconds: 1),
      );
    });

    test("the server's next_expires_at wins when present", () {
      final rows = [
        ringRow(
          newest: now.subtract(const Duration(hours: 1)),
          nextExpiresAt: now.add(const Duration(minutes: 5)),
        ),
      ];
      expect(
        storyRingExpiryDelay(rows, now),
        const Duration(minutes: 5, seconds: 1),
      );
    });

    test('past by the phone clock but still listed: re-check in a minute, '
        'for ten minutes at most', () {
      final skewed = [
        ringRow(newest: now.subtract(const Duration(hours: 24, minutes: 3))),
      ];
      expect(storyRingExpiryDelay(skewed, now), const Duration(minutes: 1));
      final stale = [ringRow(newest: now.subtract(const Duration(hours: 25)))];
      expect(storyRingExpiryDelay(stale, now), isNull);
      expect(storyRingExpiryDelay(const [], now), isNull);
    });
  });

  test('one row past the skew window does not cancel another author\'s '
      'expiry (review #2)', () {
    final now = DateTime.utc(2026, 10, 24, 12);
    final rows = [
      ringRow(
        author: 'a',
        newest: now.subtract(const Duration(hours: 24, minutes: 15)),
      ),
      ringRow(author: 'b', newest: now.subtract(const Duration(hours: 1))),
    ];
    expect(
      storyRingExpiryDelay(rows, now),
      const Duration(hours: 23, seconds: 1),
    );
    final skewed = [
      ...rows,
      ringRow(
        author: 'c',
        newest: now.subtract(const Duration(hours: 24, minutes: 2)),
      ),
    ];
    expect(storyRingExpiryDelay(skewed, now), const Duration(minutes: 1));
  });

  group('storyServerClockOffset (Wave 5, Wave 4 M-6)', () {
    final start = DateTime.utc(2026, 10, 24, 12);

    test('the server ahead of the phone by 5 minutes, read in 2 s', () {
      expect(
        storyServerClockOffset(
          serverNow: start.add(const Duration(minutes: 5, seconds: 1)),
          startedAt: start,
          receivedAt: start.add(const Duration(seconds: 2)),
        ),
        const Duration(minutes: 5),
      );
    });

    test('behind the phone is negative; a wild value is capped at a day', () {
      expect(
        storyServerClockOffset(
          serverNow: start.subtract(const Duration(minutes: 3)),
          startedAt: start,
          receivedAt: start,
        ),
        const Duration(minutes: -3),
      );
      expect(
        storyServerClockOffset(
          serverNow: start.add(const Duration(days: 400)),
          startedAt: start,
          receivedAt: start,
        ),
        const Duration(days: 1),
      );
    });
  });

  group('storyRingDroppedThumbnailKeys', () {
    final now = DateTime.utc(2026, 10, 24, 12);
    StoryRingSummary row(String key, Duration age, {int active = 1}) =>
        ringRow(key: key, active: active, newest: now.subtract(age));

    test('a deleted newest story drops its key; a newer post does not', () {
      final before = {
        ringPartner: row('b', const Duration(hours: 1), active: 2),
      };
      expect(
        storyRingDroppedThumbnailKeys(before, {
          ringPartner: row('a', const Duration(hours: 2)),
        }, now),
        {'b'},
      );
      expect(
        storyRingDroppedThumbnailKeys(before, {
          ringPartner: row('c', Duration.zero, active: 3),
        }, now),
        isEmpty,
      );
    });

    test(
      'an author gone before 24 h deleted it; after 24 h it only expired',
      () {
        expect(
          storyRingDroppedThumbnailKeys(
            {ringPartner: row('b', const Duration(hours: 1))},
            {},
            now,
          ),
          {'b'},
        );
        expect(
          storyRingDroppedThumbnailKeys(
            {ringPartner: row('b', const Duration(hours: 25))},
            {},
            now,
          ),
          isEmpty,
        );
      },
    );
  });

  group('StoryRingFetchCoalescer', () {
    test(
      'calls during a slow fetch share one follow-up (Review Focus 4)',
      () async {
        final coalescer = StoryRingFetchCoalescer();
        final gates = <Completer<List<StoryRingSummary>>>[];
        Future<List<StoryRingSummary>> fetch() {
          final gate = Completer<List<StoryRingSummary>>();
          gates.add(gate);
          return gate.future;
        }

        final first = coalescer.run('r', fetch);
        final followers = [
          for (var i = 0; i < 3; i++) coalescer.run('r', fetch),
        ];
        expect(gates.length, 1);
        gates[0].complete(const []);
        await first;
        await pumpEventQueue();
        expect(gates.length, 2);
        gates[1].complete([ringRow()]);
        final results = await Future.wait(followers);
        expect(results.map((f) => f.rows.length), [1, 1, 1]);
        expect(gates.length, 2);
      },
    );

    test(
      'a failed fetch still runs the follow-up; a later call starts anew',
      () async {
        final coalescer = StoryRingFetchCoalescer();
        var calls = 0;
        Future<List<StoryRingSummary>> fetch() async {
          calls++;
          if (calls == 1) throw StateError('offline');
          return const [];
        }

        final first = coalescer.run('r', fetch);
        final follower = coalescer.run('r', fetch);
        await expectLater(first, throwsStateError);
        await follower;
        expect(calls, 2);
        await coalescer.run('r', fetch);
        expect(calls, 3);
      },
    );
  });

  group('storyRingSummaryProvider', () {
    testWidgets(
      're-reads when its newest story expires on screen (03 M2, 04 #15)',
      (tester) async {
        final gateway = RingGateway(
          summary: [
            ringRow(
              newest: clock.now().subtract(
                const Duration(hours: 23, minutes: 59),
              ),
            ),
          ],
        );
        final c = ringContainer(gateway);
        final sub = c.listen(storyRingSummaryProvider(ringRel), (_, __) {});
        await tester.pump(Duration.zero);
        expect(gateway.summaryCalls, 1);
        gateway.summary = [];
        await tester.pump(const Duration(seconds: 59));
        expect(gateway.summaryCalls, 1);
        await tester.pump(const Duration(seconds: 3));
        await tester.pump(Duration.zero);
        expect(gateway.summaryCalls, 2);
        expect(c.read(storyRingSummaryProvider(ringRel)).valueOrNull, isEmpty);
        sub.close();
        await tester.pump(Duration.zero);
        c.dispose();
      },
    );

    testWidgets('an expiry due while hidden waits for Attune to be back', (
      tester,
    ) async {
      final gateway = RingGateway(
        summary: [
          ringRow(
            newest: clock.now().subtract(
              const Duration(hours: 23, minutes: 59),
            ),
          ),
        ],
      );
      final c = ringContainer(gateway);
      final sub = c.listen(storyRingSummaryProvider(ringRel), (_, __) {});
      await tester.pump(Duration.zero);
      visibilityOf(c).set(false);
      await tester.pump(const Duration(minutes: 2));
      expect(gateway.summaryCalls, 1);
      visibilityOf(c).set(true);
      await tester.pump(Duration.zero);
      await tester.pump(Duration.zero);
      expect(gateway.summaryCalls, 2);
      sub.close();
      await tester.pump(Duration.zero);
      c.dispose();
    });

    // Final review M-4: the return re-reads once, whichever of the two
    // return paths (Attune back on screen, the resume signal) lands first.
    for (final visibleFirst in [true, false]) {
      testWidgets('a return after a retry fell due while hidden costs one '
          'ring fetch (${visibleFirst ? 'visible, then the resume signal' : 'the resume signal, then visible'}; '
          'final review M-4)', (tester) async {
        final gateway = RingGateway(summary: [ringRow()])
          ..summaryError = StateError('offline');
        final c = ringContainer(gateway);
        final sub = c.listen(storyRingSummaryProvider(ringRel), (_, __) {});
        await tester.pump(Duration.zero);
        expect(gateway.summaryCalls, 1);
        lifecycle(tester, const [
          AppLifecycleState.inactive,
          AppLifecycleState.hidden,
          AppLifecycleState.paused,
        ]);
        visibilityOf(c).set(false);
        await tester.pump(const Duration(seconds: 3));
        expect(gateway.summaryCalls, 1);

        gateway
          ..summaryError = null
          ..summaryGate = Completer<void>();
        if (visibleFirst) {
          visibilityOf(c).set(true);
          await tester.pump(Duration.zero);
          await tester.pump(Duration.zero);
          lifecycle(tester, const [
            AppLifecycleState.hidden,
            AppLifecycleState.inactive,
            AppLifecycleState.resumed,
          ]);
        } else {
          lifecycle(tester, const [
            AppLifecycleState.hidden,
            AppLifecycleState.inactive,
            AppLifecycleState.resumed,
          ]);
          await tester.pump(Duration.zero);
          await tester.pump(Duration.zero);
          visibilityOf(c).set(true);
        }
        await tester.pump(Duration.zero);
        await tester.pump(Duration.zero);
        final gate = gateway.summaryGate!;
        gateway.summaryGate = null;
        gate.complete();
        for (var i = 0; i < 4; i++) {
          await tester.pump(Duration.zero);
        }
        expect(gateway.summaryCalls, 2);
        expect(c.read(storyRingSummaryProvider(ringRel)).hasValue, isTrue);
        sub.close();
        await tester.pump(Duration.zero);
        c.dispose();
      });
    }

    testWidgets('a signal well after a return still re-reads after it '
        '(M-4 keeps real changes)', (tester) async {
      final gateway = RingGateway(summary: [ringRow()])
        ..summaryError = StateError('offline');
      final c = ringContainer(gateway);
      final sub = c.listen(storyRingSummaryProvider(ringRel), (_, __) {});
      await tester.pump(Duration.zero);
      visibilityOf(c).set(false);
      await tester.pump(const Duration(seconds: 3));
      gateway
        ..summaryError = null
        ..summaryGate = Completer<void>();
      visibilityOf(c).set(true);
      await tester.pump(Duration.zero);
      await tester.pump(Duration.zero);
      expect(gateway.summaryCalls, 2);
      await tester.pump(const Duration(seconds: 1));
      gateway.emitSignal();
      await tester.pump(Duration.zero);
      await tester.pump(Duration.zero);
      final gate = gateway.summaryGate!;
      gateway.summaryGate = null;
      gate.complete();
      for (var i = 0; i < 4; i++) {
        await tester.pump(Duration.zero);
      }
      expect(gateway.summaryCalls, 3);
      sub.close();
      await tester.pump(Duration.zero);
      c.dispose();
    });

    // M-4 guard: through the real visibility notifier, a return's two
    // paths land in one lifecycle dispatch.
    testWidgets('a real return after a retry fell due while hidden costs one '
        'ring fetch', (tester) async {
      final gateway = RingGateway(summary: [ringRow()])
        ..summaryError = StateError('offline');
      final c = ProviderContainer(
        overrides: [
          currentUserProvider.overrideWithValue(ringUser),
          storyReadGatewayProvider.overrideWithValue(gateway),
          chatImageCacheProvider.overrideWithValue(NoopImageCache()),
          storyRingLastKnownStoreProvider.overrideWithValue(
            MemoryStoryRingLastKnownStore(),
          ),
        ],
      );
      final sub = c.listen(storyRingSummaryProvider(ringRel), (_, __) {});
      final vis = c.listen(appContentVisibleProvider, (_, __) {});
      await tester.pump(Duration.zero);
      lifecycle(tester, const [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
      ]);
      expect(c.read(appContentVisibleProvider), isFalse);
      await tester.pump(const Duration(seconds: 3));
      expect(gateway.summaryCalls, 1);
      gateway
        ..summaryError = null
        ..summaryGate = Completer<void>();
      lifecycle(tester, const [
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]);
      for (var i = 0; i < 3; i++) {
        await tester.pump(Duration.zero);
      }
      final gate = gateway.summaryGate!;
      gateway.summaryGate = null;
      gate.complete();
      for (var i = 0; i < 4; i++) {
        await tester.pump(Duration.zero);
      }
      expect(gateway.summaryCalls, 2);
      expect(c.read(appContentVisibleProvider), isTrue);
      sub.close();
      vis.close();
      await tester.pump(Duration.zero);
      c.dispose();
    });

    testWidgets('a phone clock ahead of the server re-checks each minute, then '
        'stops (Review Focus 1)', (tester) async {
      final gateway = RingGateway(
        summary: [
          ringRow(
            newest: clock.now().subtract(
              const Duration(hours: 24, seconds: 30),
            ),
          ),
        ],
      );
      final c = ringContainer(gateway);
      final sub = c.listen(storyRingSummaryProvider(ringRel), (_, __) {});
      await tester.pump(Duration.zero);
      await tester.pump(const Duration(minutes: 1));
      await tester.pump(Duration.zero);
      expect(gateway.summaryCalls, 2);
      await tester.pump(const Duration(minutes: 12));
      final settled = gateway.summaryCalls;
      expect(settled, lessThanOrEqualTo(12));
      await tester.pump(const Duration(minutes: 30));
      expect(gateway.summaryCalls, settled);
      sub.close();
      await tester.pump(Duration.zero);
      c.dispose();
    });

    testWidgets('a failed load retries on a backoff and stops after six', (
      tester,
    ) async {
      final gateway = RingGateway()..summaryError = StateError('offline');
      final c = ringContainer(gateway);
      final sub = c.listen(storyRingSummaryProvider(ringRel), (_, __) {});
      await tester.pump(Duration.zero);
      expect(gateway.summaryCalls, 1);
      for (final seconds in [2, 4, 8, 16, 32, 60]) {
        await tester.pump(Duration(seconds: seconds));
        await tester.pump(Duration.zero);
      }
      expect(gateway.summaryCalls, 1 + kStoryRingMaxAutoRetries);
      await tester.pump(const Duration(minutes: 5));
      expect(gateway.summaryCalls, 1 + kStoryRingMaxAutoRetries);
      gateway.summaryError = null;
      c.invalidate(storyRingSummaryProvider(ringRel));
      await tester.pump(Duration.zero);
      await tester.pump(Duration.zero);
      expect(c.read(storyRingSummaryProvider(ringRel)).hasValue, isTrue);
      sub.close();
      await tester.pump(Duration.zero);
      c.dispose();
    });

    testWidgets('a burst of signals during a slow ring fetch costs one more '
        'call (Review Focus 4)', (tester) async {
      final gateway = RingGateway(summary: [ringRow()])
        ..summaryGate = Completer<void>();
      final c = ringContainer(gateway);
      final sub = c.listen(storyRingSummaryProvider(ringRel), (_, __) {});
      await tester.pump(Duration.zero);
      for (var i = 0; i < 5; i++) {
        gateway.emitSignal();
        await tester.pump(Duration.zero);
      }
      c.invalidate(storyRingSummaryProvider(ringRel));
      await tester.pump(Duration.zero);
      expect(gateway.summaryCalls, 1);
      final gate = gateway.summaryGate!;
      gateway.summaryGate = null;
      gate.complete();
      await tester.pump(Duration.zero);
      await tester.pump(Duration.zero);
      await tester.pump(Duration.zero);
      expect(gateway.summaryCalls, 2);
      sub.close();
      await tester.pump(Duration.zero);
      c.dispose();
    });

    testWidgets('a re-read showing the partner deleted their newest story '
        'evicts its thumbnail (05 #6)', (tester) async {
      final now = clock.now();
      final evictor = RecordingEvictor();
      final gateway = RingGateway(
        summary: [
          ringRow(
            active: 2,
            key: 'b',
            newest: now.subtract(const Duration(hours: 1)),
          ),
        ],
      );
      final c = ringContainer(
        gateway,
        overrides: [storyMediaEvictorProvider.overrideWithValue(evictor)],
      );
      final sub = c.listen(storyRingSummaryProvider(ringRel), (_, __) {});
      await tester.pump(Duration.zero);
      gateway.summary = [
        ringRow(key: 'a', newest: now.subtract(const Duration(hours: 2))),
      ];
      gateway.emitSignal();
      await tester.pump(Duration.zero);
      await tester.pump(Duration.zero);
      expect(evictor.evicted, ['b']);
      sub.close();
      await tester.pump(Duration.zero);
      c.dispose();
    });

    testWidgets("a phone clock 5 minutes behind re-reads at the server's "
        'expiry, not 5 minutes late (Wave 5, Wave 4 M-6)', (tester) async {
      final server = clock.now().add(const Duration(minutes: 5));
      final gateway = RingGateway(
        summary: [
          ringRow(
            newest: server.subtract(const Duration(hours: 23, minutes: 59)),
            nextExpiresAt: server.add(const Duration(seconds: 30)),
            serverNow: server,
          ),
        ],
      );
      final c = ringContainer(gateway);
      final sub = c.listen(storyRingSummaryProvider(ringRel), (_, __) {});
      await tester.pump(Duration.zero);
      expect(gateway.summaryCalls, 1);
      gateway.summary = [];
      await tester.pump(const Duration(seconds: 33));
      await tester.pump(Duration.zero);
      expect(gateway.summaryCalls, 2);
      sub.close();
      await tester.pump(Duration.zero);
      c.dispose();
    });
  });

  test('next_expires_at is read when the server sends it', () {
    final row = StoryRingSummary.fromRow({
      'author_id': 'a',
      'active_count': 2,
      'unviewed_count': 1,
      'newest_thumbnail_key': 'k',
      'newest_created_at': '2026-10-24T10:00:00Z',
      'next_expires_at': '2026-10-24T11:00:00Z',
    });
    expect(row.nextExpiresAt, DateTime.utc(2026, 10, 24, 11));
    final legacy = StoryRingSummary.fromRow({
      'author_id': 'a',
      'active_count': 1,
      'unviewed_count': 0,
      'newest_thumbnail_key': 'k',
      'newest_created_at': '2026-10-24T10:00:00Z',
    });
    expect(legacy.nextExpiresAt, isNull);
  });

  test('server_now is read but never stored in the snapshot row', () {
    final row = StoryRingSummary.fromRow({
      'author_id': 'a',
      'active_count': 1,
      'unviewed_count': 0,
      'newest_thumbnail_key': 'k',
      'newest_created_at': '2026-10-24T10:00:00Z',
      'server_now': '2026-10-24T10:05:00Z',
    });
    expect(row.serverNow, DateTime.utc(2026, 10, 24, 10, 5));
    expect(row.toRow().containsKey('server_now'), isFalse);
    final later = StoryRingSummary.fromRow({...row.toRow(), 'server_now': '2026-10-24T11:00:00Z'});
    expect(
      storyRingRowsDiffer({'a': row}, {'a': later}),
      isFalse,
      reason: 'a new clock alone does not rewrite the last-known snapshot',
    );
  });
}

void lifecycle(WidgetTester tester, List<AppLifecycleState> states) {
  for (final state in states) {
    tester.binding.handleAppLifecycleStateChanged(state);
  }
}

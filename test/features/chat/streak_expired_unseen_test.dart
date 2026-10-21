// A streak the recipient fetched but never saw is destroyed by the sweep
// 30 minutes after that first read (final review I-1): its budget goes to
// 0 while viewed_at stays NULL, because nobody was ever shown it. Both
// bubbles used to lie about that row — the recipient read "Opened" for
// something they never saw, and the sender kept a "Play" that opened a
// viewer with nothing in it, forever. Both now read "Expired" and neither
// is tappable.
import 'package:attune/features/chat/data/repositories/streak_repository.dart';
import 'package:attune/features/chat/domain/entities/message.dart';
import 'package:attune/features/chat/presentation/screens/streak_viewer_screen.dart';
import 'package:attune/features/chat/presentation/widgets/message_bubble.dart';
import 'package:attune/features/chat/presentation/widgets/streak_bubble.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/chat_test_harness.dart';

class _CountingStreakRepository implements StreakRepository {
  int fetches = 0;

  @override
  Future<List<StreakClip>> fetchClips(String messageId) async {
    fetches++;
    return const [];
  }

  @override
  Future<int> markViewed(String messageId, {required String openId}) async => 0;

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Message _streak({
  required bool isMine,
  int? remaining = 0,
  DateTime? viewedAt,
  String id = 'streak-1',
}) => Message(
  id: id,
  clientMessageId: 'c-streak-1',
  relationshipId: 'r1',
  senderId: isMine ? 'me' : 'partner',
  content: '',
  createdAt: DateTime(2026, 7, 1, 15, 4),
  status: MessageStatus.delivered,
  isMine: isMine,
  mediaType: 'streak',
  streakViewsRemaining: remaining,
  viewedAt: viewedAt,
);

void main() {
  Future<_CountingStreakRepository> pump(
    WidgetTester tester,
    Message message,
  ) async {
    final repo = _CountingStreakRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [streakRepositoryProvider.overrideWithValue(repo)],
        child: withScreenUtil(
          MaterialApp(home: Scaffold(body: MessageBubble(message: message))),
        ),
      ),
    );
    return repo;
  }

  for (final isMine in [false, true]) {
    final side = isMine ? 'sender' : 'recipient';

    testWidgets('the $side sees "Expired" on a swept, never-seen streak', (
      tester,
    ) async {
      await pump(tester, _streak(isMine: isMine));

      expect(find.text('Expired'), findsOneWidget);
      expect(find.text('Opened'), findsNothing, reason: 'nobody saw it');
      expect(find.textContaining('Play'), findsNothing);
      expect(find.byIcon(Icons.timer_off_outlined), findsOneWidget);
    });

    testWidgets('the $side cannot open a swept, never-seen streak', (
      tester,
    ) async {
      final repo = await pump(tester, _streak(isMine: isMine));

      await tester.tap(find.byType(StreakBubble));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        find.byType(StreakViewerScreen, skipOffstage: false),
        findsNothing,
      );
      expect(repo.fetches, 0);

      // Not even through the semantics activate path, which calls onTap
      // directly.
      tester.widget<StreakBubble>(find.byType(StreakBubble)).onTap();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        find.byType(StreakViewerScreen, skipOffstage: false),
        findsNothing,
      );
      expect(repo.fetches, 0);
    });

    testWidgets('the $side hears one plain label, no button', (tester) async {
      final handle = tester.ensureSemantics();
      await pump(tester, _streak(isMine: isMine));

      expect(
        tester.getSemantics(find.bySemanticsLabel('Streak expired')),
        matchesSemantics(
          label: 'Streak expired',
          isButton: false,
          hasTapAction: false,
        ),
      );
      handle.dispose();
    });
  }

  testWidgets('a watched streak still reads "Opened", not "Expired"', (
    tester,
  ) async {
    // viewed_at is the presentation receipt: once set, the streak was seen.
    for (final isMine in [false, true]) {
      await pump(
        tester,
        _streak(isMine: isMine, viewedAt: DateTime(2026, 7, 1, 15, 10)),
      );
      expect(find.text('Opened'), findsOneWidget, reason: 'isMine=$isMine');
      expect(find.text('Expired'), findsNothing, reason: 'isMine=$isMine');
    }
  });

  testWidgets('an unopened streak with views left still offers Play', (
    tester,
  ) async {
    for (final isMine in [false, true]) {
      await pump(tester, _streak(isMine: isMine, remaining: 1));
      expect(find.text('Play'), findsOneWidget, reason: 'isMine=$isMine');
      expect(find.text('Expired'), findsNothing, reason: 'isMine=$isMine');
    }
  });

  testWidgets('an optimistic row is never "Expired"', (tester) async {
    // A _local_ row carries no server budget yet.
    await pump(tester, _streak(isMine: true, id: '_local_c-streak-1'));
    expect(find.text('Expired'), findsNothing);
    expect(find.text('Sending…'), findsOneWidget);
  });

  // Final fix re-review B-1: the history cache used to drop the budget, so
  // every cached streak reloaded with streakViewsRemaining == null. Only a
  // server-confirmed zero (the column is NOT NULL DEFAULT 1) means swept.
  for (final isMine in [false, true]) {
    final side = isMine ? 'sender' : 'recipient';
    testWidgets('the $side never sees "Expired" on a row with no known budget', (
      tester,
    ) async {
      await pump(tester, _streak(isMine: isMine, remaining: null));
      expect(find.text('Expired'), findsNothing);
    });
  }

  test('the history cache keeps the streak budget', () {
    final original = _streak(isMine: false, remaining: 2);
    final restored = Message.fromJson(original.toJson());
    expect(restored.streakViewsRemaining, 2);
    expect(
      Message.fromJson(_streak(isMine: false, remaining: 0).toJson())
          .streakViewsRemaining,
      0,
    );
  });
}

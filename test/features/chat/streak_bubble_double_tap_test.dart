// A double-tap on a streak row used to push two viewers. Each viewer is its
// own open (its own open id), so both presented and BOTH spent a view: a
// one-view streak burnt by one gesture (task-4 review minor 6, task-5b
// review). The row now ignores taps while its viewer is opening or open.
import 'dart:async';

import 'package:attune/features/chat/data/repositories/streak_repository.dart';
import 'package:attune/features/chat/domain/entities/message.dart';
import 'package:attune/features/chat/presentation/screens/streak_viewer_screen.dart';
import 'package:attune/features/chat/presentation/widgets/message_bubble.dart';
import 'package:attune/features/chat/presentation/widgets/streak_bubble.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/chat_test_harness.dart';

/// Holds every fetch open until the test releases it, so the viewer sits
/// in its "opening" state.
class _HeldStreakRepository implements StreakRepository {
  final List<Completer<List<StreakClip>>> fetches = [];

  @override
  Future<List<StreakClip>> fetchClips(String messageId) {
    final fetch = Completer<List<StreakClip>>();
    fetches.add(fetch);
    return fetch.future;
  }

  @override
  Future<int> markViewed(String messageId, {required String openId}) async => 1;

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Message _partnerStreak() => Message(
  id: 'streak-1',
  clientMessageId: 'c-streak-1',
  relationshipId: 'r1',
  senderId: 'partner',
  content: '',
  createdAt: DateTime(2026, 7, 1, 15, 4),
  status: MessageStatus.delivered,
  isMine: false,
  mediaType: 'streak',
  streakViewsRemaining: 1,
);

void main() {
  Future<_HeldStreakRepository> pumpBubble(WidgetTester tester) async {
    final repo = _HeldStreakRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [streakRepositoryProvider.overrideWithValue(repo)],
        child: withScreenUtil(
          MaterialApp(
            home: Scaffold(body: MessageBubble(message: _partnerStreak())),
          ),
        ),
      ),
    );
    return repo;
  }

  Finder viewers() => find.byType(StreakViewerScreen, skipOffstage: false);

  testWidgets('two rapid taps open exactly one viewer', (tester) async {
    final repo = await pumpBubble(tester);

    // Both activations reach the row's onTap before the first viewer is
    // up. Pointer taps are partly absorbed by the Navigator while it
    // pushes, but a semantics "activate" (screen reader, switch access)
    // calls onTap directly, so the row itself has to refuse the second.
    final onTap = tester.widget<StreakBubble>(find.byType(StreakBubble)).onTap;
    onTap();
    onTap();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(viewers(), findsOneWidget);
    expect(repo.fetches, hasLength(1));

    for (final fetch in repo.fetches) {
      fetch.complete(const []);
    }
  });

  testWidgets('the row opens again once its viewer has closed', (tester) async {
    final repo = await pumpBubble(tester);
    await tester.tap(find.byType(StreakBubble));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(viewers(), findsOneWidget);

    // Nothing to play: the viewer says so; a tap closes it.
    repo.fetches.single.complete(const []);
    await tester.pump();
    await tester.tap(find.byType(StreakViewerScreen));
    await tester.pumpAndSettle();
    expect(viewers(), findsNothing);

    await tester.tap(find.byType(StreakBubble));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(viewers(), findsOneWidget, reason: 'the guard was cleared');
    expect(repo.fetches, hasLength(2));
    repo.fetches.last.complete(const []);
  });

  testWidgets('a viewer torn down before it was ever built releases the row', (
    tester,
  ) async {
    // T5b re-review M-2: the tree replaced in the same frame as the tap
    // (a quick exit) disposes the Navigator before the viewer route is
    // first built. No viewer State ever exists (no onDisposed) and the push
    // future never completes (no finally), so the row stayed locked until
    // the app restarted.
    await pumpBubble(tester);
    tester.widget<StreakBubble>(find.byType(StreakBubble)).onTap();
    await tester.pumpWidget(const SizedBox()); // same frame: torn down
    await tester.pump();
    expect(viewers(), findsNothing);

    final repo = await pumpBubble(tester);
    await tester.tap(find.byType(StreakBubble));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(viewers(), findsOneWidget, reason: 'the row is not locked');
    expect(repo.fetches, hasLength(1));
    repo.fetches.single.complete(const []);
  });

  testWidgets('releaseStreakViewerGuards frees every row', (tester) async {
    // Called from the chat screen's dispose: whatever a lost route left
    // behind, leaving the chat never keeps a row locked.
    final repo = await pumpBubble(tester);
    final onTap = tester.widget<StreakBubble>(find.byType(StreakBubble)).onTap;
    onTap();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(repo.fetches, hasLength(1));

    releaseStreakViewerGuards();
    onTap();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(repo.fetches, hasLength(2), reason: 'the guard was cleared');
    for (final fetch in repo.fetches) {
      fetch.complete(const []);
    }
  });
}

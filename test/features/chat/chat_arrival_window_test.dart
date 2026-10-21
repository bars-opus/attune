// T8 carry: the arrival animation is a "just now" gesture. A row whose
// arrival is first BUILT more than kArrivalAnimationWindow later (the reader
// was scrolled up, then came back) renders settled; one built inside the
// window still animates. Screen-level, on the fake clock: ChatScreen stamps
// and reads arrivals with clock.now(), which tester.pump advances.
import 'package:attune/core/ui/motion/motion_tokens.dart';
import 'package:attune/core/ui/motion/settle_in.dart';
import 'package:attune/features/chat/presentation/screens/chat_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/chat_test_harness.dart';

void main() {
  void seedMany(FakeChatRepository repo, int n) {
    final base = DateTime.now().subtract(const Duration(hours: 2));
    for (var i = 0; i < n; i++) {
      repo.seedIncoming(
        id: 'm$i',
        relationshipId: 'rel-1',
        senderId: i % 3 == 0 ? 'user-a' : 'partner',
        content: 'message $i',
        createdAt: base.add(Duration(minutes: i)),
      );
    }
  }

  Future<ProviderContainer> pumpChat(
    WidgetTester tester,
    FakeChatRepository repo,
  ) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final container = buildChatContainer(repository: repo, userId: 'user-a');
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 10));
      container.dispose();
    });
    final convo = activeConversation('rel-1');
    repo.conversationOverride = convo;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: withScreenUtil(
          MaterialApp(home: ChatScreen(conversation: convo)),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 100));
    return container;
  }

  Future<void> tearDownChat(
    WidgetTester tester,
    ProviderContainer container,
  ) async {
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
    container.dispose();
  }

  final messageList = find.byWidgetPredicate((w) => w is ListView && w.reverse);
  ScrollPosition listPosition(WidgetTester tester) =>
      tester
          .state<ScrollableState>(
            find
                .descendant(of: messageList, matching: find.byType(Scrollable))
                .first,
          )
          .position;

  /// Lowest SettleIn fade opacity of the row holding [text] over a few
  /// frames after it is first built (1.0 = it never animated).
  Future<double> minOpacityOnceBuilt(WidgetTester tester, String text) async {
    var lowest = 1.0;
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      final row = find.text(text);
      if (row.evaluate().isEmpty) continue;
      final fade = find.descendant(
        of: find.ancestor(of: row, matching: find.byType(SettleIn)).first,
        matching: find.byType(FadeTransition),
      );
      final opacity = tester.widget<FadeTransition>(fade.first).opacity.value;
      if (opacity < lowest) lowest = opacity;
    }
    return lowest;
  }

  Future<void> arriveWhileScrolledUp(
    WidgetTester tester,
    FakeChatRepository repo,
    String id,
  ) async {
    await tester.drag(find.byType(ListView), const Offset(0, 1200));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    repo.seedIncoming(
      id: id,
      relationshipId: 'rel-1',
      senderId: 'partner',
      content: id,
      createdAt: DateTime.now(),
    );
    repo.emitRealtime();
    // Past the realtime debounce; the row sits below the viewport, unbuilt.
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text(id), findsNothing, reason: 'not built while away');
  }

  testWidgets('an arrival first built after the window renders settled', (
    tester,
  ) async {
    final repo = FakeChatRepository(currentUserId: 'user-a');
    seedMany(repo, 50);
    final container = await pumpChat(tester, repo);
    await arriveWhileScrolledUp(tester, repo, 'late arrival');

    await tester.pump(kArrivalAnimationWindow);
    listPosition(tester).jumpTo(0);
    expect(await minOpacityOnceBuilt(tester, 'late arrival'), 1.0);
    await tearDownChat(tester, container);
  });

  testWidgets('an arrival built inside the window still animates', (
    tester,
  ) async {
    final repo = FakeChatRepository(currentUserId: 'user-a');
    seedMany(repo, 50);
    final container = await pumpChat(tester, repo);
    await arriveWhileScrolledUp(tester, repo, 'fresh arrival');

    listPosition(tester).jumpTo(0);
    expect(await minOpacityOnceBuilt(tester, 'fresh arrival'), lessThan(1.0));
    await tearDownChat(tester, container);
  });
}

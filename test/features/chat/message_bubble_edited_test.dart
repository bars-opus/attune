import 'package:attune/features/chat/data/repositories/chat_repository.dart';
import 'package:attune/features/chat/domain/entities/message.dart';
import 'package:attune/features/chat/presentation/screens/chat_screen.dart';
import 'package:attune/features/chat/presentation/widgets/message_bubble.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/chat_test_harness.dart';

/// Spec "Edited label + history view": an edited message carries a small
/// "edited" label after its time, and tapping it opens the history sheet.
/// Regression from f29007b6, where the footer moved outside the bubble and
/// the label was hard-wired off.
void main() {
  Future<ProviderContainer> pumpChat(
    WidgetTester tester,
    FakeChatRepository repo,
  ) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final container = buildChatContainer(repository: repo, userId: 'user-a');
    // A failing expect skips tearDownChat: unmount, then dispose, so one
    // red test cannot cascade into the next. No-ops after tearDownChat.
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

  testWidgets('an edited partner message shows "edited" in the list', (
    tester,
  ) async {
    final repo = FakeChatRepository(currentUserId: 'user-a');
    final now = DateTime.now();
    repo.seedIncoming(
      id: 'm-edited',
      relationshipId: 'rel-1',
      senderId: 'partner',
      content: 'home at 9',
      createdAt: now.subtract(const Duration(minutes: 3)),
      editedAt: now.subtract(const Duration(minutes: 1)),
    );
    // A newer, un-edited message so the edited one is NOT the newest row
    // (the newest row already has a footer for other reasons).
    repo.seedIncoming(
      id: 'm-newest',
      relationshipId: 'rel-1',
      senderId: 'partner',
      content: 'ok',
      createdAt: now,
    );
    final container = await pumpChat(tester, repo);

    expect(find.text('edited'), findsOneWidget);
    await tearDownChat(tester, container);
  });

  testWidgets('tapping "edited" opens the history sheet with prior text', (
    tester,
  ) async {
    final repo = FakeChatRepository(currentUserId: 'user-a');
    final now = DateTime.now();
    repo.seedIncoming(
      id: 'm-edited',
      relationshipId: 'rel-1',
      senderId: 'user-a',
      content: 'home at 9',
      createdAt: now.subtract(const Duration(minutes: 3)),
      editedAt: now.subtract(const Duration(minutes: 1)),
    );
    repo.editHistory['m-edited'] = [
      MessageEditHistoryEntry(
        previousContent: 'home at 7',
        editedAt: now.subtract(const Duration(minutes: 1)),
      ),
    ];
    final container = await pumpChat(tester, repo);

    await tester.tap(find.text('edited'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Edit history'), findsOneWidget);
    expect(find.text('home at 7'), findsOneWidget);
    expect(find.text('Current'), findsOneWidget);

    await tester.tapAt(const Offset(400, 40));
    await tester.pump(const Duration(milliseconds: 400));
    await tearDownChat(tester, container);
  });

  testWidgets('the long-press menu offers "Edit history" on edited rows only', (
    tester,
  ) async {
    final repo = FakeChatRepository(currentUserId: 'user-a');
    final now = DateTime.now();
    repo.seedIncoming(
      id: 'm-edited',
      relationshipId: 'rel-1',
      senderId: 'partner',
      content: 'home at 9',
      createdAt: now.subtract(const Duration(minutes: 3)),
      editedAt: now.subtract(const Duration(minutes: 1)),
    );
    repo.seedIncoming(
      id: 'm-plain',
      relationshipId: 'rel-1',
      senderId: 'partner',
      content: 'ok',
      createdAt: now,
    );
    repo.editHistory['m-edited'] = [
      MessageEditHistoryEntry(
        previousContent: 'home at 7',
        editedAt: now.subtract(const Duration(minutes: 1)),
      ),
    ];
    final container = await pumpChat(tester, repo);

    await tester.longPress(find.text('ok'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Copy'), findsOneWidget, reason: 'the menu is open');
    expect(find.text('Edit history'), findsNothing);
    await tester.tapAt(const Offset(400, 1350));
    await tester.pump(const Duration(milliseconds: 400));

    await tester.longPress(find.text('home at 9'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Edit history'), findsOneWidget);
    await tester.tap(find.text('Edit history'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('home at 7'), findsOneWidget, reason: 'the history sheet');

    await tester.tapAt(const Offset(400, 40));
    await tester.pump(const Duration(milliseconds: 400));
    await tearDownChat(tester, container);
  });

  testWidgets('a deleted message never shows "edited"', (tester) async {
    final repo = FakeChatRepository(currentUserId: 'user-a');
    final now = DateTime.now();
    repo.seedIncoming(
      id: 'm-gone',
      relationshipId: 'rel-1',
      senderId: 'partner',
      content: '',
      createdAt: now.subtract(const Duration(minutes: 3)),
      editedAt: now.subtract(const Duration(minutes: 2)),
      deletedAt: now.subtract(const Duration(minutes: 1)),
    );
    final container = await pumpChat(tester, repo);
    expect(find.text('edited'), findsNothing);
    await tearDownChat(tester, container);
  });
  group('the "edited" label (final wave M-1)', () {
    Message bubbleMessage({
      String id = 'm1',
      bool edited = true,
      bool notice = false,
    }) => Message(
      id: id,
      clientMessageId: 'c-$id',
      relationshipId: 'r1',
      senderId: 'partner',
      content: 'home at 9',
      createdAt: DateTime(2026, 7, 1, 15, 4),
      editedAt: edited ? DateTime(2026, 7, 1, 15, 6) : null,
      status: MessageStatus.delivered,
      isMine: false,
      isSystemNotice: notice,
    );

    Future<void> pumpBubble(WidgetTester tester, Widget bubble) async {
      await tester.pumpWidget(
        withScreenUtil(
          MaterialApp(
            home: Scaffold(body: Center(child: bubble)),
          ),
        ),
      );
    }

    Rect bubbleFill(WidgetTester tester) {
      for (final element
          in find
              .descendant(
                of: find.byType(MessageBubble),
                matching: find.byType(DecoratedBox),
              )
              .evaluate()) {
        final decoration = (element.widget as DecoratedBox).decoration;
        if (decoration is BoxDecoration &&
            (decoration.gradient != null || decoration.color != null) &&
            decoration.borderRadius is BorderRadius) {
          final box = element.renderObject! as RenderBox;
          return box.localToGlobal(Offset.zero) & box.size;
        }
      }
      throw StateError('no bubble fill');
    }

    final timeText = find.byWidgetPredicate(
      (w) => w is Text && RegExp(r'^\d{1,2}:04').hasMatch(w.data ?? ''),
    );
    final editedTarget = find.byKey(const ValueKey('message_edited_label'));

    double bubbleHeight(WidgetTester tester) =>
        tester.getSize(find.byType(MessageBubble)).height;

    testWidgets('an edited row is exactly as tall as an unedited one', (
      tester,
    ) async {
      await pumpBubble(
        tester,
        MessageBubble(
          message: bubbleMessage(edited: false),
          showLatestTimestamp: true,
        ),
      );
      final plain = bubbleHeight(tester);
      final plainFill = bubbleFill(tester);
      final plainTime = tester.getRect(timeText);

      await pumpBubble(
        tester,
        MessageBubble(message: bubbleMessage(), onShowEditHistory: (_) {}),
      );
      expect(bubbleHeight(tester), plain, reason: 'no growth');
      final editedTime = tester.getRect(timeText);
      expect(
        editedTime.top - bubbleFill(tester).bottom,
        closeTo(plainTime.top - plainFill.bottom, 0.5),
        reason: 'the time sits where it does on any footer',
      );
      expect(
        tester.getRect(find.text('edited')).center.dy,
        closeTo(editedTime.center.dy, 1),
        reason: '"edited" stays on the time\'s line',
      );
    });

    testWidgets('a tap just beside the label still opens the history', (
      tester,
    ) async {
      final opened = <String>[];
      await pumpBubble(
        tester,
        MessageBubble(
          message: bubbleMessage(),
          onShowEditHistory: (m) => opened.add(m.id),
        ),
      );
      final label = tester.getRect(editedTarget);
      // In the footer's 6 pt item spacing, outside the label's own box.
      await tester.tapAt(Offset(label.left - 4, label.center.dy));
      await tester.tapAt(label.center);
      expect(opened, ['m1', 'm1']);
    });

    testWidgets('never on a local (unsent) row or a system notice', (
      tester,
    ) async {
      await pumpBubble(
        tester,
        MessageBubble(message: bubbleMessage(id: '_local_1')),
      );
      expect(find.text('edited'), findsNothing);
      await pumpBubble(
        tester,
        MessageBubble(message: bubbleMessage(notice: true)),
      );
      expect(find.text('edited'), findsNothing);
    });

    testWidgets('promises the history only when it can open it', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await pumpBubble(tester, MessageBubble(message: bubbleMessage()));
      expect(
        find.bySemanticsLabel(RegExp('Edited')),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel(RegExp('Shows edit history')), findsNothing);

      await pumpBubble(
        tester,
        MessageBubble(message: bubbleMessage(), onShowEditHistory: (_) {}),
      );
      expect(
        find.bySemanticsLabel(RegExp(r'Edited\. Shows edit history')),
        findsOneWidget,
      );
      semantics.dispose();
    });
  });
}

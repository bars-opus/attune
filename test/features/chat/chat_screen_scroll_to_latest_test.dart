import 'dart:async';

import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/ui/feedback/haptics.dart';
import 'package:attune/features/chat/data/cache/chat_cache_service.dart';
import 'package:attune/features/chat/data/repositories/chat_repository.dart';
import 'package:attune/features/chat/domain/entities/conversation.dart';
import 'package:attune/features/chat/domain/entities/message.dart';
import 'package:attune/features/chat/presentation/screens/chat_channel_loader.dart';
import 'package:attune/features/chat/presentation/screens/chat_screen.dart';
import 'package:attune/features/chat/presentation/state/chat_state.dart';
import 'package:attune/features/chat/presentation/widgets/scroll_to_latest_pill.dart';
import 'package:attune/features/chat/presentation/widgets/unread_divider.dart';
import 'package:attune/features/games/invites/presentation/game_composer_bar.dart';
import 'package:attune/features/games/invites/state/game_invite_provider.dart';
import 'package:attune/features/games/presentation/providers/game_card_provider.dart';
import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/chat_test_harness.dart';

/// #32b: WhatsApp's "↓ N" pill once the reader has left the newest
/// messages, and the one-shot "N unread messages" divider on open.
void main() {
  Message row(
    String id, {
    required bool mine,
    bool deleted = false,
    bool notice = false,
  }) => Message(
    id: id,
    clientMessageId: 'c-$id',
    relationshipId: 'r',
    senderId: mine ? 'me' : 'partner',
    content: 'x',
    createdAt: DateTime(2026, 7, 1),
    status: MessageStatus.sent,
    isMine: mine,
    isSystemNotice: notice,
    deletedAt: deleted ? DateTime(2026, 7, 1) : null,
  );

  group('unreadDividerMessageId', () {
    test('points at the Nth newest partner message', () {
      final list = [
        row('a', mine: false),
        row('b', mine: true),
        row('c', mine: false),
        row('d', mine: false),
      ];
      expect(unreadDividerMessageId(list, 2), 'c');
    });
    test(
      'skips deleted rows and falls back to the oldest loaded partner row',
      () {
        final list = [
          row('a', mine: false),
          row('b', mine: false, deleted: true),
          row('c', mine: false),
        ];
        expect(unreadDividerMessageId(list, 2), 'c');
        expect(
          unreadDividerMessageId(list, 80),
          'c',
          reason: 'more unread than loaded',
        );
      },
    );
    test('skips system notices', () {
      final list = [
        row('a', mine: false),
        row('n', mine: false, notice: true),
        row('c', mine: false),
      ];
      expect(unreadDividerMessageId(list, 2), 'c');
    });
    test('null for zero unread or no partner rows', () {
      expect(unreadDividerMessageId([row('a', mine: false)], 0), isNull);
      expect(unreadDividerMessageId([row('a', mine: true)], 3), isNull);
    });
    test('a short placement records how many unread are still unloaded', () {
      final list = [
        row('a', mine: false),
        row('b', mine: true),
        row('c', mine: false),
      ];
      final placement = placeUnreadDivider(list, 5)!;
      expect(placement.messageId, 'c');
      expect(placement.unplaced, 3);
      expect(placeUnreadDivider(list, 2)!.unplaced, 0);
    });
    test(
      'an older page extends a short placement, counting only older rows',
      () {
        final first = [row('a', mine: false), row('c', mine: false)];
        final placement = placeUnreadDivider(first, 4)!;
        // A new arrival at the newest end and an older page at the far end.
        final later = [
          row('new', mine: false),
          ...first,
          row('d', mine: true),
          row('e', mine: false),
          row('f', mine: false),
          row('g', mine: false),
        ];
        final extended = extendUnreadDivider(later, placement);
        expect(
          extended.messageId,
          'f',
          reason: '4th newest at open: a, c, e, f',
        );
        expect(extended.unplaced, 0);
        expect(
          identical(extendUnreadDivider(later, extended), extended),
          isTrue,
        );
      },
    );
    test('the label is one plural function', () {
      expect(unreadDividerLabel(1), '1 unread message');
      expect(unreadDividerLabel(3), '3 unread messages');
      expect(scrollToLatestSemanticsLabel(0), 'Jump to newest message');
      expect(scrollToLatestSemanticsLabel(2), 'Jump to newest, 2 new');
    });
  });

  Future<ProviderContainer> pumpChat(
    WidgetTester tester,
    FakeChatRepository repo, {
    Conversation? conversation,
    Size size = const Size(800, 1400),
    bool reduceMotion = false,
    TextDirection? textDirection,
    ChatCacheService? cache,
    Future<void> Function(ProviderContainer container)? beforePump,
    List<Override> extraOverrides = const [],
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final container = buildChatContainer(
      repository: repo,
      userId: 'user-a',
      cache: cache,
      extraOverrides: extraOverrides,
    );
    // A failing expect skips tearDownChat: unmount, then dispose, so one
    // red test cannot cascade into the next. Unmount FIRST — teardowns run
    // before flutter_test resets the tree, and the screen reads providers
    // as it deactivates. Both steps are no-ops after tearDownChat.
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 10));
      container.dispose();
    });
    final convo = conversation ?? activeConversation('rel-1');
    repo.conversationOverride = convo;
    if (beforePump != null) await beforePump(container);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: withScreenUtil(
          MaterialApp(
            builder:
                (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(disableAnimations: reduceMotion),
                  child:
                      textDirection == null
                          ? child!
                          : Directionality(
                            textDirection: textDirection,
                            child: child!,
                          ),
                ),
            home: ChatScreen(conversation: convo),
          ),
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

  Future<void> frames(WidgetTester tester, [int count = 10]) async {
    for (var i = 0; i < count; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

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

  Future<void> arrive(
    WidgetTester tester,
    FakeChatRepository repo,
    String id, {
    String senderId = 'partner',
  }) async {
    repo.seedIncoming(
      id: id,
      relationshipId: 'rel-1',
      senderId: senderId,
      content: id,
      createdAt: DateTime.now(),
    );
    repo.emitRealtime();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
  }

  final pill = find.byKey(const ValueKey('chat_scroll_to_latest'));
  final pillIcon = find.descendant(
    of: pill,
    matching: find.byIcon(Icons.keyboard_arrow_down_rounded),
  );
  final messageList = find.byWidgetPredicate((w) => w is ListView && w.reverse);
  ScrollPosition listPosition(WidgetTester tester) =>
      tester
          .state<ScrollableState>(
            find
                .descendant(of: messageList, matching: find.byType(Scrollable))
                .first,
          )
          .position;
  ScrollToLatestPill pillWidget(WidgetTester tester) =>
      tester.widget<ScrollToLatestPill>(pill);

  testWidgets('pill appears with the arrival count and returns to the latest', (
    tester,
  ) async {
    final haptics = FakeHaptics();
    final repo = FakeChatRepository(currentUserId: 'user-a');
    seedMany(repo, 50);
    final container = await pumpChat(
      tester,
      repo,
      extraOverrides: [hapticsProvider.overrideWithValue(haptics)],
    );
    expect(
      pillIcon.hitTestable(),
      findsNothing,
      reason: 'hidden at the bottom',
    );

    await tester.drag(find.byType(ListView), const Offset(0, 1200));
    await frames(tester);
    expect(pillIcon.hitTestable(), findsOneWidget);
    expect(find.bySemanticsLabel('Jump to newest message'), findsOneWidget);

    repo.seedIncoming(
      id: 'n1',
      relationshipId: 'rel-1',
      senderId: 'partner',
      content: 'new one',
      createdAt: DateTime.now(),
    );
    repo.emitRealtime();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    repo.seedIncoming(
      id: 'n2',
      relationshipId: 'rel-1',
      senderId: 'partner',
      content: 'new two',
      createdAt: DateTime.now(),
    );
    repo.emitRealtime();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.descendant(of: pill, matching: find.text('2')), findsOneWidget);
    expect(find.bySemanticsLabel('Jump to newest, 2 new'), findsOneWidget);

    final selectionsBefore = haptics.selectionCount;

    await tester.tap(find.byIcon(Icons.keyboard_arrow_down_rounded));

    await frames(tester, 12);

    expect(haptics.selectionCount, selectionsBefore + 1);
    expect(find.text('new two').hitTestable(), findsOneWidget);
    expect(find.descendant(of: pill, matching: find.text('2')), findsNothing);
    expect(pillIcon.hitTestable(), findsNothing);
    expect(listPosition(tester).pixels, 0);
    await tearDownChat(tester, container);
  });

  testWidgets(
    'the pill shows only past the threshold, without a per-tick rebuild',
    (tester) async {
      final repo = FakeChatRepository(currentUserId: 'user-a');
      seedMany(repo, 50);
      final container = await pumpChat(tester, repo);
      listPosition(tester).jumpTo(200);
      await frames(tester, 2);
      expect(
        pillWidget(tester).visible,
        isFalse,
        reason: 'a couple of bubbles up',
      );
      listPosition(tester).jumpTo(260);
      await frames(tester, 2);
      expect(pillWidget(tester).visible, isTrue);
      await frames(tester, 20);
      await tearDownChat(tester, container);
    },
  );

  testWidgets('own messages, edits and reactions never count', (tester) async {
    final repo = FakeChatRepository(currentUserId: 'user-a');
    seedMany(repo, 50);
    final container = await pumpChat(tester, repo);
    await tester.drag(find.byType(ListView), const Offset(0, 1200));
    await frames(tester);
    expect(pillWidget(tester).visible, isTrue);

    // Sent from my other device.
    await arrive(tester, repo, 'from-my-laptop', senderId: 'user-a');
    expect(pillWidget(tester).count, 0);

    // An edit to an already-loaded partner message.
    repo.seedIncoming(
      id: 'm49',
      relationshipId: 'rel-1',
      senderId: 'partner',
      content: 'message 49 (edited)',
      createdAt: DateTime.now()
          .subtract(const Duration(hours: 2))
          .add(const Duration(minutes: 49)),
      editedAt: DateTime.now(),
    );
    repo.touch('m49');
    repo.emitRealtime();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    expect(pillWidget(tester).count, 0);

    await arrive(tester, repo, 'partner-new');
    expect(pillWidget(tester).count, 1);
    await tearDownChat(tester, container);
  });

  testWidgets('a partner game move does not count; a new invite does', (
    tester,
  ) async {
    // Final review M-2: a move re-sorts an EXISTING card to the bottom (and
    // leaves a trail at its old slot). It is activity, not a new message —
    // neither the server unread count nor the divider counts it, so the
    // pill must not either. A NEW invite card is a new message and does.
    final repo = FakeChatRepository(currentUserId: 'user-a');
    seedMany(repo, 50);
    final cardAt = DateTime.now()
        .subtract(const Duration(hours: 2))
        .add(const Duration(minutes: 45, seconds: 30));
    repo.seedIncoming(
      id: 'g1',
      relationshipId: 'rel-1',
      senderId: 'user-a',
      content: 'Snakes and Ladders',
      createdAt: cardAt,
      mediaType: 'game',
      gameSessionId: 's1',
    );
    final container = await pumpChat(
      tester,
      repo,
      extraOverrides: [
        gameCardProvider.overrideWith((ref, id) => const Stream.empty()),
      ],
    );
    await tester.drag(find.byType(ListView), const Offset(0, 1200));
    await frames(tester);
    expect(pillWidget(tester).visible, isTrue);

    // The partner plays: trail at the old slot, card re-sorted to now.
    repo.seedIncoming(
      id: 't1',
      relationshipId: 'rel-1',
      senderId: 'user-a',
      content: 'Snakes and Ladders',
      createdAt: cardAt,
      mediaType: 'game_trail',
      gameSessionId: 's1',
    );
    repo.seedIncoming(
      id: 'g1',
      relationshipId: 'rel-1',
      senderId: 'partner',
      content: 'Snakes and Ladders',
      createdAt: cardAt,
      sortAt: DateTime.now(),
      mediaType: 'game',
      gameSessionId: 's1',
    );
    repo.emitRealtime();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    expect(pillWidget(tester).count, 0, reason: 'a move is not a message');

    // A new invite from the partner is.
    repo.seedIncoming(
      id: 'g2',
      relationshipId: 'rel-1',
      senderId: 'partner',
      content: 'This or That',
      createdAt: DateTime.now(),
      mediaType: 'game',
      gameSessionId: 's2',
    );
    repo.emitRealtime();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    expect(pillWidget(tester).count, 1, reason: 'a new invite counts');

    await arrive(tester, repo, 'partner-text');
    expect(pillWidget(tester).count, 2);
    await tearDownChat(tester, container);
  });

  testWidgets('reaching the bottom by hand resets the count', (tester) async {
    final repo = FakeChatRepository(currentUserId: 'user-a');
    seedMany(repo, 50);
    final container = await pumpChat(tester, repo);
    await tester.drag(find.byType(ListView), const Offset(0, 1200));
    await frames(tester);
    await arrive(tester, repo, 'p1');
    expect(pillWidget(tester).count, 1);

    await tester.fling(find.byType(ListView), const Offset(0, -3000), 4000);
    await frames(tester, 30);
    expect(pillWidget(tester).visible, isFalse);
    expect(pillWidget(tester).count, 0);

    await tester.drag(find.byType(ListView), const Offset(0, 1200));
    await frames(tester);
    expect(pillWidget(tester).visible, isTrue);
    expect(
      find.descendant(of: pill, matching: find.text('1')),
      findsNothing,
      reason: 'already seen',
    );
    await tearDownChat(tester, container);
  });

  testWidgets(
    'a hold that moves the list without a notification re-checks the pill',
    (tester) async {
      final repo = FakeChatRepository(currentUserId: 'user-a');
      seedMany(repo, 50);
      final container = await pumpChat(tester, repo);
      repo.emitPartnerTyping('partner', true);
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 300));
      }
      final withIndicator =
          tester.getSize(find.byKey(const ValueKey('typing_indicator'))).height;
      expect(withIndicator, greaterThan(20));
      listPosition(tester).jumpTo(260);
      await frames(tester, 2);
      expect(pillWidget(tester).visible, isTrue);

      // The overlay shrinks while scrolled up: Task 8 holds the rows with
      // correctPixels (no scroll notification) — 260 drops below 240.
      repo.emitPartnerTyping('partner', false);
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 300));
      }
      expect(listPosition(tester).pixels, lessThan(240));
      expect(pillWidget(tester).visible, isFalse);
      await tearDownChat(tester, container);
    },
  );

  testWidgets('the pill sits above the typing indicator (Review Focus 5)', (
    tester,
  ) async {
    final repo = FakeChatRepository(currentUserId: 'user-a');
    seedMany(repo, 50);
    final container = await pumpChat(tester, repo);
    await tester.drag(find.byType(ListView), const Offset(0, 1200));
    await frames(tester);
    repo.emitPartnerTyping('partner', true);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));
    final indicatorTop =
        tester.getTopLeft(find.byKey(const ValueKey('typing_indicator'))).dy;
    final pillBottom =
        tester.getBottomLeft(find.byIcon(Icons.keyboard_arrow_down_rounded)).dy;
    expect(pillBottom, lessThan(indicatorTop));
    expect(pillIcon.hitTestable(), findsOneWidget, reason: 'never covered');
    repo.emitPartnerTyping('partner', false);
    await tester.pump(const Duration(milliseconds: 600));
    await tearDownChat(tester, container);
  });

  testWidgets('the pill rises above a staged game bar', (tester) async {
    final repo = FakeChatRepository(currentUserId: 'user-a');
    seedMany(repo, 50);
    final container = await pumpChat(tester, repo);
    await tester.drag(find.byType(ListView), const Offset(0, 1200));
    await frames(tester);
    container
        .read(gameComposerProvider('rel-1').notifier)
        .stage('this_or_that');
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
    final barTop = tester.getTopLeft(find.byType(GameComposerBar)).dy;
    final pillRect = tester.getRect(
      find.descendant(of: pill, matching: find.byType(InkWell)),
    );
    expect(pillRect.bottom, lessThanOrEqualTo(barTop - 12 + 0.5));
    expect(pillIcon.hitTestable(), findsOneWidget);
    container.read(gameComposerProvider('rel-1').notifier).cancel();
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
    await tearDownChat(tester, container);
  });

  testWidgets('reduce motion: the pill jumps straight to the newest', (
    tester,
  ) async {
    final repo = FakeChatRepository(currentUserId: 'user-a');
    seedMany(repo, 50);
    final container = await pumpChat(tester, repo, reduceMotion: true);
    listPosition(tester).jumpTo(1200);
    await frames(tester, 2);
    await tester.tap(pillIcon);
    await tester.pump();
    await tester.pump();
    expect(listPosition(tester).pixels, 0);
    await tearDownChat(tester, container);
  });

  testWidgets('right-to-left, the pill and its badge sit at the end edge', (
    tester,
  ) async {
    final repo = FakeChatRepository(currentUserId: 'user-a');
    seedMany(repo, 50);
    final container = await pumpChat(
      tester,
      repo,
      textDirection: TextDirection.rtl,
    );
    listPosition(tester).jumpTo(1200);
    await frames(tester, 4);
    await arrive(tester, repo, 'later');
    final pillRect = tester.getRect(
      find.descendant(of: pill, matching: find.byType(InkWell)),
    );
    // The end edge in RTL is the left one: same 16 px inset as in LTR.
    expect(pillRect.left, closeTo(16, 0.5));
    final badgeRect = tester.getRect(
      find.descendant(of: pill, matching: find.text('1')),
    );
    expect(
      badgeRect.center.dx,
      lessThan(pillRect.center.dx),
      reason: 'the badge mirrors to the circle\'s leading corner',
    );
    await tearDownChat(tester, container);
  });

  testWidgets('on an iPad the pill sits inside the conversation column', (
    tester,
  ) async {
    final repo = FakeChatRepository(currentUserId: 'user-a');
    seedMany(repo, 50);
    final container = await pumpChat(
      tester,
      repo,
      size: const Size(1032, 1376),
    );
    listPosition(tester).jumpTo(1200);
    await frames(tester, 4);
    final columnRight = (1032 + ContentWidth.chat) / 2;
    final pillRect = tester.getRect(
      find.descendant(of: pill, matching: find.byType(InkWell)),
    );
    expect(pillRect.right, lessThanOrEqualTo(columnRight));
    expect(pillRect.right, greaterThan(columnRight - 80));
    await tearDownChat(tester, container);
  });

  testWidgets('opening with unread shows the divider above the oldest unread', (
    tester,
  ) async {
    final repo = FakeChatRepository(currentUserId: 'user-a');
    final base = DateTime.now().subtract(const Duration(minutes: 30));
    for (var i = 0; i < 10; i++) {
      repo.seedIncoming(
        id: 'm$i',
        relationshipId: 'rel-1',
        senderId: 'partner',
        content: 'message $i',
        createdAt: base.add(Duration(minutes: i)),
      );
    }
    final container = await pumpChat(
      tester,
      repo,
      conversation: activeConversation('rel-1').copyWith(unreadCount: 3),
    );
    final divider = find.byType(UnreadDivider);
    expect(find.text('3 unread messages'), findsOneWidget);
    final dividerTop = tester.getTopLeft(divider).dy;
    expect(
      dividerTop,
      greaterThan(tester.getTopLeft(find.text('message 6')).dy),
    );
    expect(dividerTop, lessThan(tester.getTopLeft(find.text('message 7')).dy));

    // Stays put for the visit: a new message does not pull it down.
    await arrive(tester, repo, 'later');
    expect(find.text('3 unread messages'), findsOneWidget);
    expect(
      tester.getTopLeft(divider).dy,
      lessThan(tester.getTopLeft(find.text('message 7')).dy),
    );
    expect(
      tester.getTopLeft(divider).dy,
      greaterThan(tester.getTopLeft(find.text('message 6')).dy),
    );
    await tearDownChat(tester, container);
  });

  testWidgets(
    'more unread than the first page: true count on the oldest loaded, then the true row',
    (tester) async {
      final repo = FakeChatRepository(currentUserId: 'user-a');
      final base = DateTime.now().subtract(const Duration(hours: 3));
      for (var i = 0; i < 60; i++) {
        repo.seedIncoming(
          id: 'm$i',
          relationshipId: 'rel-1',
          senderId: 'partner',
          content: 'message $i',
          createdAt: base.add(Duration(minutes: i)),
        );
      }
      // First page = m10..m59 (50); 55 unread → the true oldest unread is m5.
      final container = await pumpChat(
        tester,
        repo,
        conversation: activeConversation('rel-1').copyWith(unreadCount: 55),
      );
      final olderPage = Completer<void>();
      repo.getMessagesGate = olderPage;
      addTearDown(() {
        if (!olderPage.isCompleted) olderPage.complete();
      });
      await tester.dragUntilVisible(
        find.byType(UnreadDivider),
        messageList,
        const Offset(0, 300),
      );
      await frames(tester, 4);
      expect(
        find.text('55 unread messages'),
        findsOneWidget,
        reason: 'the TRUE count, not the 50 loaded',
      );
      final divider = find.byType(UnreadDivider);
      expect(
        tester.getBottomLeft(divider).dy,
        lessThanOrEqualTo(tester.getTopLeft(find.text('message 10')).dy),
      );
      expect(
        tester.getTopLeft(find.text('message 11')).dy,
        greaterThan(tester.getTopLeft(find.text('message 10')).dy),
      );
      final m10Top = tester.getTopLeft(find.text('message 10')).dy;

      // The older page lands: the divider moves back to the true row, and
      // the row being read does not move.
      olderPage.complete();
      repo.getMessagesGate = null;
      await frames(tester, 10);
      expect(
        tester.getTopLeft(find.text('message 10')).dy,
        closeTo(m10Top, 0.5),
      );
      await tester.dragUntilVisible(
        find.text('message 5'),
        messageList,
        const Offset(0, 200),
      );
      await frames(tester, 4);
      expect(find.text('55 unread messages'), findsOneWidget);
      final dividerRect = tester.getRect(divider);
      expect(
        dividerRect.bottom,
        lessThanOrEqualTo(tester.getTopLeft(find.text('message 5')).dy),
      );
      expect(
        dividerRect.top,
        greaterThan(tester.getBottomLeft(find.text('message 4')).dy),
      );
      await tearDownChat(tester, container);
    },
  );

  testWidgets(
    'a warm cache does not place the divider before the server page lands',
    (tester) async {
      final repo = FakeChatRepository(currentUserId: 'user-a');
      final base = DateTime.now().subtract(const Duration(hours: 1));
      final cached = <Message>[];
      for (var i = 0; i < 10; i++) {
        cached.insert(
          0,
          repo.seedIncoming(
            id: 'm$i',
            relationshipId: 'rel-1',
            senderId: 'partner',
            content: 'message $i',
            createdAt: base.add(Duration(minutes: i)),
          ),
        );
      }
      for (var i = 10; i < 13; i++) {
        repo.seedIncoming(
          id: 'm$i',
          relationshipId: 'rel-1',
          senderId: 'partner',
          content: 'message $i',
          createdAt: base.add(Duration(minutes: i)),
        );
      }
      final firstPage = Completer<void>();
      repo.getMessagesGate = firstPage;
      addTearDown(() {
        if (!firstPage.isCompleted) firstPage.complete();
      });
      final container = await pumpChat(
        tester,
        repo,
        conversation: activeConversation('rel-1').copyWith(unreadCount: 3),
        beforePump:
            (container) => container
                .read(chatCacheServiceProvider)
                .writeMessages('user-a', 'rel-1', cached),
      );
      expect(
        find.text('message 9'),
        findsOneWidget,
        reason: 'the cache painted',
      );
      expect(
        find.byType(UnreadDivider),
        findsNothing,
        reason: 'cached rows are all read',
      );

      firstPage.complete();
      repo.getMessagesGate = null;
      await frames(tester, 12);
      final divider = find.byType(UnreadDivider);
      expect(find.text('3 unread messages'), findsOneWidget);
      expect(
        tester.getTopLeft(divider).dy,
        greaterThan(tester.getTopLeft(find.text('message 9')).dy),
      );
      expect(
        tester.getTopLeft(divider).dy,
        lessThan(tester.getTopLeft(find.text('message 10')).dy),
      );
      await tearDownChat(tester, container);
    },
  );

  testWidgets('the pill meets the Android and iOS tap-target guidelines', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: ScrollToLatestPill(
              visible: true,
              count: 3,
              onTap: () => taps++,
            ),
          ),
        ),
      ),
    );
    expect(tester.getSize(find.byType(ScrollToLatestPill)), const Size(48, 48));
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    // The margin around the 44 px circle still taps.
    final rect = tester.getRect(find.byType(ScrollToLatestPill));
    await tester.tapAt(rect.topLeft + const Offset(1, 24));
    await tester.tap(find.byIcon(Icons.keyboard_arrow_down_rounded));
    expect(taps, 2);
    semantics.dispose();
  });

  testWidgets(
    'a chat opened through the channel loader (push, inbox) shows its unread',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final repo = FakeChatRepository(currentUserId: 'user-a');
      final base = DateTime.now().subtract(const Duration(minutes: 30));
      for (var i = 0; i < 10; i++) {
        repo.seedIncoming(
          id: 'm$i',
          relationshipId: 'rel-1',
          senderId: 'partner',
          content: 'message $i',
          createdAt: base.add(Duration(minutes: i)),
        );
      }
      // What getConversation now answers: the count from the same RPC the
      // conversations list uses, read before the screen marks anything read.
      repo.conversationOverride = activeConversation(
        'rel-1',
      ).copyWith(unreadCount: 6);
      final container = buildChatContainer(repository: repo, userId: 'user-a');
      // A failing expect skips tearDownChat: unmount, then dispose, so one
      // red test cannot cascade into the next (as pumpChat does).
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(milliseconds: 10));
        container.dispose();
      });
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: withScreenUtil(
            const MaterialApp(home: ChatChannelLoader(relationshipId: 'rel-1')),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 60));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('6 unread messages'), findsOneWidget);
      final dividerTop = tester.getTopLeft(find.byType(UnreadDivider)).dy;
      expect(
        dividerTop,
        greaterThan(tester.getTopLeft(find.text('message 3')).dy),
      );
      expect(
        dividerTop,
        lessThan(tester.getTopLeft(find.text('message 4')).dy),
      );
      await tearDownChat(tester, container);
    },
  );

  testWidgets(
    'a realtime update during a warm-cache open does not place the divider early (M-1)',
    (tester) async {
      final repo = FakeChatRepository(currentUserId: 'user-a');
      final base = DateTime.now().subtract(const Duration(hours: 1));
      final cached = <Message>[];
      for (var i = 0; i < 10; i++) {
        cached.insert(
          0,
          repo.seedIncoming(
            id: 'm$i',
            relationshipId: 'rel-1',
            senderId: 'partner',
            content: 'message $i',
            createdAt: base.add(Duration(minutes: i)),
          ),
        );
      }
      for (var i = 10; i < 13; i++) {
        repo.seedIncoming(
          id: 'm$i',
          relationshipId: 'rel-1',
          senderId: 'partner',
          content: 'message $i',
          createdAt: base.add(Duration(minutes: i)),
        );
      }
      // A link that answers row reads but not page reads: the first page
      // and every forward catch-up hang (and time out).
      final firstPage = Completer<void>();
      final catchUp = Completer<void>();
      repo.getMessagesGate = firstPage;
      repo.getMessagesAfterGate = catchUp;
      addTearDown(() {
        if (!firstPage.isCompleted) firstPage.complete();
        if (!catchUp.isCompleted) catchUp.complete();
      });
      final convo = activeConversation('rel-1').copyWith(unreadCount: 3);
      final container = await pumpChat(
        tester,
        repo,
        conversation: convo,
        beforePump:
            (container) => container
                .read(chatCacheServiceProvider)
                .writeMessages('user-a', 'rel-1', cached),
      );
      expect(
        find.text('message 9'),
        findsOneWidget,
        reason: 'the cache painted',
      );

      // The partner reacts to a cached message. The batch's catch-up times
      // out, then its row refresh lands and writes lastSyncedAt — but no
      // server page of the newest messages has landed.
      repo.touch('m5');
      repo.emitRealtime(
        const ChatRealtimeEvent(ChatRealtimeKind.reaction, messageId: 'm5'),
      );
      // The catch-up is bounded at 2 x networkTimeout (40 s).
      for (var i = 0; i < 9; i++) {
        await tester.pump(const Duration(seconds: 6));
      }
      await frames(tester, 4);
      expect(
        container.read(chatControllerProvider(convo)).lastSyncedAt,
        isNotNull,
        reason: 'the row refresh wrote it',
      );
      expect(
        repo.getMessagesByIdsCalls,
        greaterThan(0),
        reason: 'the update batch ran',
      );
      expect(
        find.byType(UnreadDivider),
        findsNothing,
        reason: 'cached rows are all read',
      );

      // The link recovers: the next pass lands the newest page.
      firstPage.complete();
      catchUp.complete();
      repo.getMessagesGate = null;
      repo.getMessagesAfterGate = null;
      repo.emitRealtime();
      await frames(tester, 16);
      final divider = find.byType(UnreadDivider);
      expect(find.text('3 unread messages'), findsOneWidget);
      expect(
        tester.getTopLeft(divider).dy,
        greaterThan(tester.getTopLeft(find.text('message 9')).dy),
      );
      expect(
        tester.getTopLeft(divider).dy,
        lessThan(tester.getTopLeft(find.text('message 10')).dy),
      );
      await tearDownChat(tester, container);
    },
  );

  testWidgets(
    'placed late, after a failed first page, messages sent after the open do not count (M-2)',
    (tester) async {
      final repo = FakeChatRepository(currentUserId: 'user-a');
      final base = DateTime.now().subtract(const Duration(hours: 1));
      final cached = <Message>[];
      for (var i = 0; i < 10; i++) {
        cached.insert(
          0,
          repo.seedIncoming(
            id: 'm$i',
            relationshipId: 'rel-1',
            senderId: 'partner',
            content: 'message $i',
            createdAt: base.add(Duration(minutes: i)),
          ),
        );
      }
      // Unread before the open.
      for (var i = 10; i < 13; i++) {
        repo.seedIncoming(
          id: 'm$i',
          relationshipId: 'rel-1',
          senderId: 'partner',
          content: 'message $i',
          createdAt: base.add(Duration(minutes: i)),
        );
      }
      repo.getMessagesError = Exception('offline');
      final container = await pumpChat(
        tester,
        repo,
        conversation: activeConversation('rel-1').copyWith(unreadCount: 3),
        beforePump:
            (container) => container
                .read(chatCacheServiceProvider)
                .writeMessages('user-a', 'rel-1', cached),
      );
      expect(
        find.text('message 9'),
        findsOneWidget,
        reason: 'the cache painted',
      );
      expect(
        find.byType(UnreadDivider),
        findsNothing,
        reason: 'no server page yet',
      );

      // Sent after the open, while this phone was offline.
      final later = DateTime.now().add(const Duration(minutes: 1));
      repo.seedIncoming(
        id: 'p1',
        relationshipId: 'rel-1',
        senderId: 'partner',
        content: 'after open 1',
        createdAt: later,
      );
      repo.seedIncoming(
        id: 'p2',
        relationshipId: 'rel-1',
        senderId: 'partner',
        content: 'after open 2',
        createdAt: later.add(const Duration(seconds: 5)),
      );

      // Back online: the reconnect fills the gap.
      repo.getMessagesError = null;
      repo.emitRealtime();
      await frames(tester, 16);
      expect(find.text('after open 2'), findsOneWidget);
      final divider = find.byType(UnreadDivider);
      expect(find.text('3 unread messages'), findsOneWidget);
      expect(
        tester.getTopLeft(divider).dy,
        greaterThan(tester.getTopLeft(find.text('message 9')).dy),
      );
      expect(
        tester.getTopLeft(divider).dy,
        lessThan(tester.getTopLeft(find.text('message 10')).dy),
      );
      await tearDownChat(tester, container);
    },
  );

  testWidgets('after a failed first page, a forward catch-up alone places it', (
    tester,
  ) async {
    final repo = FakeChatRepository(currentUserId: 'user-a');
    final base = DateTime.now().subtract(const Duration(hours: 1));
    final cached = <Message>[];
    for (var i = 0; i < 10; i++) {
      cached.insert(
        0,
        repo.seedIncoming(
          id: 'm$i',
          relationshipId: 'rel-1',
          senderId: 'partner',
          content: 'message $i',
          createdAt: base.add(Duration(minutes: i)),
        ),
      );
    }
    for (var i = 10; i < 13; i++) {
      repo.seedIncoming(
        id: 'm$i',
        relationshipId: 'rel-1',
        senderId: 'partner',
        content: 'message $i',
        createdAt: base.add(Duration(minutes: i)),
      );
    }
    // Page reads keep failing; only the catch-up (getMessagesAfter) works.
    repo.getMessagesError = Exception('first page keeps failing');
    final container = await pumpChat(
      tester,
      repo,
      conversation: activeConversation('rel-1').copyWith(unreadCount: 3),
      beforePump:
          (container) => container
              .read(chatCacheServiceProvider)
              .writeMessages('user-a', 'rel-1', cached),
    );
    expect(
      find.byType(UnreadDivider),
      findsNothing,
      reason: 'no server page yet',
    );

    // Not a resync: the batch runs its forward catch-up, not a first page.
    repo.touch('m5');
    repo.emitRealtime(
      const ChatRealtimeEvent(ChatRealtimeKind.reaction, messageId: 'm5'),
    );
    await frames(tester, 16);
    expect(
      find.text('message 12'),
      findsOneWidget,
      reason: 'the catch-up filled the gap',
    );
    final divider = find.byType(UnreadDivider);
    expect(find.text('3 unread messages'), findsOneWidget);
    expect(
      tester.getTopLeft(divider).dy,
      greaterThan(tester.getTopLeft(find.text('message 9')).dy),
    );
    expect(
      tester.getTopLeft(divider).dy,
      lessThan(tester.getTopLeft(find.text('message 10')).dy),
    );
    repo.getMessagesError = null;
    await tearDownChat(tester, container);
  });

  for (final warmCache in [false, true]) {
    testWidgets(
      'a device clock behind the server keeps the divider on a normal open (I-1)'
      '${warmCache ? ' (warm cache)' : ''}',
      (tester) async {
        final repo = FakeChatRepository(currentUserId: 'user-a');
        final now = DateTime.now();
        final base = now.subtract(const Duration(minutes: 30));
        final cached = <Message>[];
        for (var i = 0; i < 10; i++) {
          cached.insert(
            0,
            repo.seedIncoming(
              id: 'm$i',
              relationshipId: 'rel-1',
              senderId: 'partner',
              content: 'message $i',
              createdAt: base.add(Duration(minutes: i)),
            ),
          );
        }
        // Unread, all sent by the server in the last 30 seconds.
        for (var i = 0; i < 3; i++) {
          repo.seedIncoming(
            id: 'u$i',
            relationshipId: 'rel-1',
            senderId: 'partner',
            content: 'unread $i',
            createdAt: now.subtract(Duration(seconds: 25 - i * 10)),
          );
        }
        // This phone's clock runs a minute behind the server's.
        final container = await withClock(
          Clock(() => DateTime.now().subtract(const Duration(minutes: 1))),
          () => pumpChat(
            tester,
            repo,
            conversation: activeConversation('rel-1').copyWith(unreadCount: 3),
            beforePump:
                warmCache
                    ? (container) => container
                        .read(chatCacheServiceProvider)
                        .writeMessages('user-a', 'rel-1', cached)
                    : null,
          ),
        );
        await frames(tester, 4);
        final divider = find.byType(UnreadDivider);
        expect(find.text('3 unread messages'), findsOneWidget);
        expect(
          tester.getTopLeft(divider).dy,
          greaterThan(tester.getTopLeft(find.text('message 9')).dy),
        );
        expect(
          tester.getTopLeft(divider).dy,
          lessThan(tester.getTopLeft(find.text('unread 0')).dy),
        );
        await tearDownChat(tester, container);
      },
    );
  }

  testWidgets('no divider without unread', (tester) async {
    final repo = FakeChatRepository(currentUserId: 'user-a');
    seedMany(repo, 5);
    final container = await pumpChat(tester, repo);
    expect(find.byType(UnreadDivider), findsNothing);
    await tearDownChat(tester, container);
  });
}

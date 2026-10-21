import 'dart:async';

import 'package:attune/features/chat/config/chat_config.dart';
import 'package:attune/features/chat/domain/entities/conversation.dart';
import 'package:attune/features/chat/presentation/screens/chat_screen.dart';
import 'package:attune/features/chat/presentation/state/chat_state.dart';
import 'package:attune/features/chat/presentation/widgets/chat_text_field.dart';
import 'package:attune/features/chat/presentation/widgets/message_bubble.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'support/chat_test_harness.dart';

/// #30: "Go to message" (reply quote, pinned banner, viewer, Starred via
/// initialJumpToMessageId) must converge on its target and flash it even
/// when the target is not loaded yet, or is loaded but far from any built
/// row. The old jump guessed one offset from viewport / keys.length and
/// returned silently for an unloaded target.
void main() {
  /// The conversation the last pumpChat opened (the controller family key).
  late Conversation convo;

  Future<ProviderContainer> pumpChat(
    WidgetTester tester,
    FakeChatRepository repo, {
    String? initialJumpToMessageId,
    ChatConfig config = const ChatConfig(),
    bool reduceMotion = false,
  }) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final container = buildChatContainer(
      repository: repo,
      userId: 'user-a',
      extraOverrides: [chatConfigProvider.overrideWithValue(config)],
    );
    // A failing expect skips tearDownChat: unmount, then dispose, so one red
    // test cannot cascade into the next. No-ops after tearDownChat.
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 10));
      container.dispose();
    });
    convo = activeConversation('rel-1');
    repo.conversationOverride = convo;

    Widget motion(BuildContext context, Widget? child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
      child: child!,
    );
    final screen = ChatScreen(
      conversation: convo,
      initialJumpToMessageId: initialJumpToMessageId,
    );
    await tester.pumpWidget(
      withScreenUtil(
        UncontrolledProviderScope(
          container: container,
          // A router like the app's, so a stray header tap has one.
          child: MaterialApp.router(
            builder: motion,
            routerConfig: GoRouter(
              initialLocation: '/',
              routes: [GoRoute(path: '/', builder: (_, __) => screen)],
            ),
          ),
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

  /// 300 rows alternating one-line and eight-line texts, so any "average
  /// row height" guess is wrong by design.
  void seedVaried(FakeChatRepository repo, {String? newestRepliesTo}) {
    // A fixed day (not now-relative): the date separators, and so the row
    // layout, must not depend on the wall-clock time the test runs at.
    final base = DateTime(2026, 3, 2, 6);
    for (var i = 0; i < 300; i++) {
      final tall = i.isOdd ? '\nline\nline\nline\nline\nline\nline\ntall' : '';
      repo.seedIncoming(
        id: 'm$i',
        relationshipId: 'rel-1',
        senderId: i % 4 == 0 ? 'user-a' : 'partner',
        content: 'message $i$tall',
        createdAt: base.add(Duration(minutes: i * 3)),
        replyToMessageId: i == 299 ? newestRepliesTo : null,
        quotedText:
            i == 299 && newestRepliesTo != null ? 'quoted parent' : null,
      );
    }
  }

  /// The message list (the pinned banner has a horizontal ListView too).
  final messageList = find.byWidgetPredicate(
    (w) => w is ListView && w.scrollDirection == Axis.vertical,
  );

  Finder bubbleFor(String id) =>
      find.byWidgetPredicate((w) => w is MessageBubble && w.message.id == id);

  /// The band rows are readable in: below the list's top edge (under the
  /// header and banners) and above the composer.
  ({double top, double bottom}) readableBand(WidgetTester tester) => (
    top: tester.getRect(messageList).top,
    bottom: tester.getRect(find.byType(ChatTextField)).top,
  );

  bool onScreen(WidgetTester tester, String id) {
    final f = bubbleFor(id);
    if (f.evaluate().isEmpty) return false;
    final rect = tester.getRect(f);
    final band = readableBand(tester);
    return rect.top >= band.top - 0.5 && rect.bottom <= band.bottom + 0.5;
  }

  ScrollPosition listPosition(WidgetTester tester) =>
      tester
          .state<ScrollableState>(
            find
                .descendant(of: messageList, matching: find.byType(Scrollable))
                .first,
          )
          .position;

  /// The flash used to pad the bubble by its 2 px ring, growing the row by
  /// 4 px after it landed; it is paint-only now, so a landed row is exact.
  const kFlashGrowth = 0.0;

  /// How far the list rests from centring [id]'s row (the box the jump
  /// targets: the row's GlobalKey subtree), allowing for the extent clamp.
  double offCentre(WidgetTester tester, String id) {
    final row =
        find
            .ancestor(
              of: bubbleFor(id),
              matching: find.byWidgetPredicate(
                (w) => w is KeyedSubtree && w.key is GlobalKey,
              ),
            )
            .first;
    final box = tester.renderObject<RenderBox>(row);
    final position = listPosition(tester);
    final reveal = RenderAbstractViewport.of(box)
        .getOffsetToReveal(box, 0.5)
        .offset
        .clamp(position.minScrollExtent, position.maxScrollExtent);
    return (position.pixels - reveal).abs();
  }

  bool highlighted(WidgetTester tester, String id) {
    final f = bubbleFor(id);
    if (f.evaluate().isEmpty) return false;
    return tester.widget<MessageBubble>(f).isHighlighted;
  }

  Future<void> pumpUntilOnScreen(WidgetTester tester, String id) async {
    for (var i = 0; i < 80; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (onScreen(tester, id) && highlighted(tester, id)) {
        // Let a running ensureVisible finish so the check is on the rest
        // position, not a frame of the drive.
        await tester.pump(const Duration(milliseconds: 450));
        return;
      }
    }
  }

  testWidgets(
    'tapping a reply quote lands on and flashes a parent 250 rows back',
    (tester) async {
      final repo = FakeChatRepository(currentUserId: 'user-a');
      seedVaried(repo, newestRepliesTo: 'm50');
      final container = await pumpChat(tester, repo);
      expect(bubbleFor('m50'), findsNothing, reason: 'not loaded yet');

      await tester.tap(find.text('quoted parent'));
      await pumpUntilOnScreen(tester, 'm50');

      expect(onScreen(tester, 'm50'), isTrue);
      expect(offCentre(tester, 'm50'), lessThanOrEqualTo(kFlashGrowth + 1));
      expect(highlighted(tester, 'm50'), isTrue);
      expect(find.text('Finding that message…'), findsNothing);
      await tester.pump(const Duration(seconds: 2));
      expect(tester.takeException(), isNull);
      await tearDownChat(tester, container);
    },
  );

  testWidgets(
    'the pinned banner reaches and flashes an unloaded, deleted pin',
    (tester) async {
      final repo = FakeChatRepository(currentUserId: 'user-a');
      seedVaried(repo);
      repo.serverMessages['m10'] = repo.serverMessages['m10']!.copyWith(
        deletedAt: DateTime.now(),
        content: '',
      );
      repo.pinnedMessageIds.add('m10');
      final container = await pumpChat(tester, repo);
      expect(bubbleFor('m10'), findsNothing, reason: 'not loaded yet');

      // Banner label for a deleted partner message.
      await tester.tap(find.text('This message was deleted').first);
      await pumpUntilOnScreen(tester, 'm10');

      // Two now: the banner and the tombstone row.
      expect(find.text('This message was deleted'), findsNWidgets(2));
      expect(onScreen(tester, 'm10'), isTrue);
      expect(offCentre(tester, 'm10'), lessThanOrEqualTo(kFlashGrowth + 1));
      expect(highlighted(tester, 'm10'), isTrue);
      await tester.pump(const Duration(seconds: 2));
      expect(tester.takeException(), isNull);
      await tearDownChat(tester, container);
    },
  );

  testWidgets('a quote whose parent no longer exists says so', (tester) async {
    final repo = FakeChatRepository(currentUserId: 'user-a');
    seedVaried(repo, newestRepliesTo: 'ghost');
    final container = await pumpChat(tester, repo);
    await tester.tap(find.text('quoted parent'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text("Couldn't find that message."), findsOneWidget);
    expect(find.text('Finding that message…'), findsNothing);
    await tester.pump(const Duration(seconds: 5));
    await tearDownChat(tester, container);
  });

  testWidgets(
    'a lookup that never answers clears the chip and says so (bounded)',
    (tester) async {
      final repo = FakeChatRepository(currentUserId: 'user-a');
      seedVaried(repo, newestRepliesTo: 'ghost');
      final container = await pumpChat(
        tester,
        repo,
        config: const ChatConfig(networkTimeout: Duration(seconds: 2)),
      );
      // The by-id read is black-holed from here on.
      final gate = repo.getMessagesByIdsGate = Completer<void>();
      addTearDown(() {
        if (!gate.isCompleted) gate.complete();
      });

      await tester.tap(find.text('quoted parent'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Finding that message…'), findsOneWidget);

      // Past the bound, the jump pages without one (offline fallback) and
      // finds nothing: the chip goes and the person is told.
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('Finding that message…'), findsNothing);
      expect(find.text("Couldn't find that message."), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      await tearDownChat(tester, container);
    },
  );

  for (final reduceMotion in [false, true]) {
    testWidgets(
      'the finding chip ${reduceMotion ? 'holds a still icon under reduce motion' : 'spins while it looks'}',
      (tester) async {
        final repo = FakeChatRepository(currentUserId: 'user-a');
        seedVaried(repo, newestRepliesTo: 'ghost');
        final container = await pumpChat(
          tester,
          repo,
          reduceMotion: reduceMotion,
          config: const ChatConfig(networkTimeout: Duration(seconds: 2)),
        );
        final gate = repo.getMessagesByIdsGate = Completer<void>();
        addTearDown(() {
          if (!gate.isCompleted) gate.complete();
        });

        await tester.tap(find.text('quoted parent'));
        await tester.pump(const Duration(milliseconds: 100));
        final chip = find.ancestor(
          of: find.text('Finding that message…'),
          matching: find.byType(Material),
        );
        expect(chip, findsWidgets);
        expect(
          find.descendant(
            of: chip.first,
            matching: find.byType(CircularProgressIndicator),
          ),
          reduceMotion ? findsNothing : findsOneWidget,
        );
        expect(
          find.descendant(
            of: chip.first,
            matching: find.byKey(const ValueKey('chat_jump_chip_still_icon')),
          ),
          reduceMotion ? findsOneWidget : findsNothing,
        );
        for (var i = 0; i < 30; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        await tester.pump(const Duration(seconds: 5));
        await tearDownChat(tester, container);
      },
    );
  }

  testWidgets('initialJumpToMessageId lands precisely on a far target', (
    tester,
  ) async {
    final repo = FakeChatRepository(currentUserId: 'user-a');
    seedVaried(repo);
    final container = await pumpChat(
      tester,
      repo,
      initialJumpToMessageId: 'm7',
    );
    await pumpUntilOnScreen(tester, 'm7');
    expect(onScreen(tester, 'm7'), isTrue);
    expect(offCentre(tester, 'm7'), lessThanOrEqualTo(kFlashGrowth + 1));
    expect(highlighted(tester, 'm7'), isTrue);
    await tester.pump(const Duration(seconds: 2));
    expect(tester.takeException(), isNull);
    await tearDownChat(tester, container);
  });

  testWidgets(
    'a loaded but unbuilt target far up the page converges (no index guess)',
    (tester) async {
      final repo = FakeChatRepository(currentUserId: 'user-a');
      seedVaried(repo, newestRepliesTo: 'm60');
      // One big first page: the target is in state.messages, nowhere near a
      // built row, and the heights vary 1:8.
      final container = await pumpChat(
        tester,
        repo,
        config: const ChatConfig(messagePageSize: 300),
      );
      expect(bubbleFor('m60'), findsNothing, reason: 'not built yet');

      await tester.tap(find.text('quoted parent'));
      await pumpUntilOnScreen(tester, 'm60');

      expect(onScreen(tester, 'm60'), isTrue);
      expect(offCentre(tester, 'm60'), lessThanOrEqualTo(kFlashGrowth + 1));
      expect(highlighted(tester, 'm60'), isTrue);
      await tester.pump(const Duration(seconds: 2));
      await tearDownChat(tester, container);
    },
  );

  testWidgets(
    'arrivals landing during the final drive still leave the target centred',
    (tester) async {
      final repo = FakeChatRepository(currentUserId: 'user-a');
      // A parent already built a few rows up: the jump is one ensureVisible
      // drive, and arrivals land while it runs.
      seedVaried(repo, newestRepliesTo: 'm292');
      final container = await pumpChat(tester, repo);
      final position = listPosition(tester);
      expect(bubbleFor('m292'), findsOneWidget, reason: 'built before tap');

      await tester.tap(find.text('quoted parent'));
      await tester.pump(const Duration(milliseconds: 16));
      // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
      expect(position.activity, isA<DrivenScrollActivity>());
      // Partner messages arrive mid-drive: the list's place hold corrects
      // the offset under the drive (Task 9), which can leave a row-targeted
      // drive a frame step off its row.
      for (var k = 0; k < 3; k++) {
        repo.seedIncoming(
          id: 'arrival-$k',
          relationshipId: 'rel-1',
          senderId: 'partner',
          content: 'arrival $k\nwith\nseveral\nlines\nof\ntext',
          createdAt: DateTime(2026, 3, 3, 9, k),
        );
        repo.emitRealtime();
        await tester.pump(const Duration(milliseconds: 16));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await pumpUntilOnScreen(tester, 'm292');

      expect(onScreen(tester, 'm292'), isTrue);
      expect(offCentre(tester, 'm292'), lessThanOrEqualTo(kFlashGrowth + 1));
      expect(highlighted(tester, 'm292'), isTrue);
      await tester.pump(const Duration(seconds: 2));
      await tearDownChat(tester, container);
    },
  );

  for (final how in [
    'a touch',
    'a scroll-wheel or trackpad scroll',
    'leaving',
  ]) {
    testWidgets('$how while the jump pages stops the paging', (tester) async {
      final repo = FakeChatRepository(currentUserId: 'user-a');
      seedVaried(repo, newestRepliesTo: 'm50');
      // Small jump pages: m50 is ten pages back, so a loop that keeps going
      // after the cancel would show up in the call count.
      final container = await pumpChat(
        tester,
        repo,
        config: const ChatConfig(jumpPageSize: 20),
      );
      final position = listPosition(tester);
      final pagesLand = Completer<void>();
      repo.getMessagesResponseGate = pagesLand;
      addTearDown(() {
        if (!pagesLand.isCompleted) pagesLand.complete();
      });
      final callsBefore = repo.getMessagesCalls;

      await tester.tap(find.text('quoted parent'));
      await tester.pump(const Duration(milliseconds: 16));
      expect(find.text('Finding that message…'), findsOneWidget);
      expect(repo.getMessagesCalls - callsBefore, 1, reason: 'one in flight');

      TestGesture? finger;
      switch (how) {
        case 'a touch':
          finger = await tester.startGesture(tester.getCenter(messageList));
        case 'a scroll-wheel or trackpad scroll':
          tester.binding.handlePointerEvent(
            PointerScrollEvent(
              position: tester.getCenter(messageList),
              scrollDelta: const Offset(0, -40),
            ),
          );
        case 'leaving':
          await tester.pumpWidget(const SizedBox());
      }
      await tester.pump(const Duration(milliseconds: 16));
      final held = how == 'leaving' ? 0.0 : position.pixels;
      pagesLand.complete();
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(
        repo.getMessagesCalls - callsBefore,
        1,
        reason: 'only the page already in flight; no more after the cancel',
      );
      expect(
        container
            .read(chatControllerProvider(convo))
            .messages
            .any((m) => m.id == 'm50'),
        isFalse,
      );
      if (how != 'leaving') {
        expect(position.pixels, held, reason: 'no jump after the cancel');
        expect(find.text('Finding that message…'), findsNothing);
        expect(find.text("Couldn't find that message."), findsNothing);
      }
      await finger?.up();
      await tester.pump(const Duration(seconds: 2));
      await tearDownChat(tester, container);
    });
  }

  testWidgets('a target beyond the paging bound says it is too far back', (
    tester,
  ) async {
    final repo = FakeChatRepository(currentUserId: 'user-a');
    seedVaried(repo, newestRepliesTo: 'm10');
    // 40 pages of 2 rows reach 80 rows back; m10 is 289 back.
    final container = await pumpChat(
      tester,
      repo,
      config: const ChatConfig(jumpPageSize: 2),
    );
    await tester.tap(find.text('quoted parent'));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(
      find.text('That message is too far back to jump to.'),
      findsOneWidget,
    );
    expect(find.text("Couldn't find that message."), findsNothing);
    expect(find.text('Finding that message…'), findsNothing);
    await tester.pump(const Duration(seconds: 5));
    await tearDownChat(tester, container);
  });

  testWidgets(
    'when the scroll cannot reach the target (it left the list) the person '
    'is told',
    (tester) async {
      final repo = FakeChatRepository(currentUserId: 'user-a');
      seedVaried(repo, newestRepliesTo: 'm60');
      final container = await pumpChat(
        tester,
        repo,
        config: const ChatConfig(messagePageSize: 300),
      );
      await tester.tap(find.text('quoted parent'));
      // The scroll toward m60 is under way when m60 leaves the list (a
      // purge or a hard delete landing mid-jump).
      final notifier = container.read(chatControllerProvider(convo).notifier);
      // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
      notifier.state = notifier.state.copyWith(
        // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
        messages: [...notifier.state.messages.where((m) => m.id != 'm60')],
      );
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(find.text("Couldn't find that message."), findsOneWidget);
      expect(find.text('Finding that message…'), findsNothing);
      await tester.pump(const Duration(seconds: 5));
      await tearDownChat(tester, container);
    },
  );

  testWidgets('a touch on the list while it scrolls hands the list back', (
    tester,
  ) async {
    final repo = FakeChatRepository(currentUserId: 'user-a');
    seedVaried(repo, newestRepliesTo: 'm50');
    final container = await pumpChat(tester, repo);
    final position = listPosition(tester);

    await tester.tap(find.text('quoted parent'));
    await tester.pump(const Duration(milliseconds: 16));
    // Paged in; the scroll toward the target has started.
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(bubbleFor('m50'), findsNothing, reason: 'not there yet');

    // The person puts a finger on the list and holds it still: from here
    // nothing may move it (the down itself stops a running drive).
    final held = position.pixels;
    final finger = await tester.startGesture(tester.getCenter(messageList));
    await tester.pump(const Duration(milliseconds: 16));
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(position.pixels, held, reason: 'no jump under the finger');
    expect(find.text('Finding that message…'), findsNothing);
    await finger.up();
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(highlighted(tester, 'm50'), isFalse);
    await tester.pump(const Duration(seconds: 2));
    await tearDownChat(tester, container);
  });

  testWidgets('reduce motion: the jump never animates and still flashes', (
    tester,
  ) async {
    final repo = FakeChatRepository(currentUserId: 'user-a');
    seedVaried(repo, newestRepliesTo: 'm50');
    final container = await pumpChat(tester, repo, reduceMotion: true);
    final position =
        tester
            .state<ScrollableState>(
              find
                  .descendant(
                    of: messageList,
                    matching: find.byType(Scrollable),
                  )
                  .first,
            )
            .position;

    await tester.tap(find.text('quoted parent'));
    var animated = false;
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
      if (position.activity is DrivenScrollActivity) animated = true;
    }
    expect(animated, isFalse, reason: 'jumps, never animateTo/ensureVisible');
    expect(onScreen(tester, 'm50'), isTrue);
    expect(offCentre(tester, 'm50'), lessThanOrEqualTo(kFlashGrowth + 1));
    expect(highlighted(tester, 'm50'), isTrue);
    await tester.pump(const Duration(seconds: 2));
    await tearDownChat(tester, container);
  });
}

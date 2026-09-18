import 'package:attune/features/ai_assistant/data/repositories/ai_assistant_repository.dart';
import 'package:attune/features/ai_assistant/presentation/providers/ai_assistant_providers.dart';
import 'package:attune/features/ai_assistant/presentation/screens/ask_attune_mode_sheet.dart';
import 'package:attune/features/chat/domain/entities/conversation.dart';
import 'package:attune/features/chat/presentation/screens/chat_screen.dart';
import 'package:attune/features/chat/presentation/widgets/reply_composer_preview.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'support/chat_test_harness.dart';

/// Task 8 wiring: ChatScreen must pass real message-action handlers down to
/// MessageBubble and render the pinned-messages banner from ChatState.
void main() {
  /// Boots ChatScreen against [repo] and settles the initial load.
  Future<ProviderContainer> pumpChat(
    WidgetTester tester,
    FakeChatRepository repo, {
    Conversation? conversation,
    List<Override> extraOverrides = const [],
  }) async {
    // The actions sheet lists up to six tiles; the default 800x600 surface
    // pushes Edit/Delete below the fold and off the hit-test area.
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final container = buildChatContainer(
      repository: repo,
      userId: 'user-a',
      extraOverrides: extraOverrides,
    );
    final convo = conversation ?? activeConversation('rel-1');
    repo.conversationOverride = convo;

    await tester.pumpWidget(
      withScreenUtil(
        UncontrolledProviderScope(
          container: container,
          // MaterialApp.router, not MaterialApp: the header's tap handler
          // calls pushNamed, so a bare MaterialApp throws "No GoRouter
          // found in context" when a gesture reaches it.
          child: MaterialApp.router(
            routerConfig: GoRouter(
              initialLocation: '/',
              routes: [
                GoRoute(
                  path: '/',
                  builder: (_, __) => ChatScreen(conversation: convo),
                ),
                GoRoute(
                  path: '/pulse',
                  name: 'pulse',
                  builder: (_, __) => const Scaffold(body: Text('Pulse stub')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pump(const Duration(milliseconds: 400));
    return container;
  }

  /// Unmounts before disposing so the controller's keep-alive eviction timer
  /// is cancelled instead of racing the binding's pending-timer check —
  /// mirrors message_list_animation_test.dart's teardown.
  Future<void> tearDownChat(
    WidgetTester tester,
    ProviderContainer container,
  ) async {
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
    container.dispose();
  }

  testWidgets('long-pressing a bubble opens the actions sheet', (tester) async {
    final repo = FakeChatRepository(currentUserId: 'user-a');
    repo.seedIncoming(
      id: 'm1',
      relationshipId: 'rel-1',
      senderId: 'partner',
      content: 'hello there',
      createdAt: DateTime.now(),
    );
    final container = await pumpChat(tester, repo);

    await tester.longPress(find.text('hello there'));
    await tester.pump(const Duration(milliseconds: 400));

    // currentUserId is wired through, so the sheet actually opens.
    expect(find.text('Copy'), findsOneWidget);
    expect(find.text('Star'), findsOneWidget);
    expect(find.text('Pin'), findsOneWidget);

    await tester.tapAt(const Offset(10, 10));
    await tester.pump(const Duration(milliseconds: 400));
    await tearDownChat(tester, container);
  });

  testWidgets('outside dismissal never refocuses the chat composer', (
    tester,
  ) async {
    final repo = FakeChatRepository(currentUserId: 'user-a');
    repo.seedIncoming(
      id: 'm-focus-dismiss',
      relationshipId: 'rel-1',
      senderId: 'partner',
      content: 'hold to inspect',
      createdAt: DateTime.now(),
    );
    final container = await pumpChat(tester, repo);
    final composer = find.byType(EditableText);
    final composerCenter = tester.getCenter(composer);

    for (final entranceDelay in [
      Duration.zero,
      const Duration(milliseconds: 80),
      const Duration(milliseconds: 400),
    ]) {
      await tester.tap(composer);
      await tester.pump();
      expect(tester.widget<EditableText>(composer).focusNode.hasFocus, isTrue);

      await tester.longPress(find.text('hold to inspect'));
      await tester.pump(entranceDelay);
      expect(find.text('Copy'), findsOneWidget);
      expect(tester.widget<EditableText>(composer).focusNode.hasFocus, isFalse);

      if (entranceDelay == const Duration(milliseconds: 80)) {
        // Model a delayed focus request from an earlier composer action that
        // arrives after the menu has already taken focus.
        tester.widget<EditableText>(composer).focusNode.requestFocus();
        await tester.pump();
      }

      // This is directly over the field beneath the menu's scrim. It must
      // dismiss the menu without allowing the field to acquire focus.
      await tester.tapAt(composerCenter);
      if (entranceDelay == const Duration(milliseconds: 400)) {
        // Another focus request can also arrive during the reverse menu
        // animation, after the outside tap but before route removal.
        tester.widget<EditableText>(composer).focusNode.requestFocus();
      }
      await tester.pump(const Duration(milliseconds: 750));
      expect(find.text('Copy'), findsNothing);
      expect(tester.widget<EditableText>(composer).focusNode.hasFocus, isFalse);
    }

    await tearDownChat(tester, container);
  });

  testWidgets('Reply action still focuses the composer', (tester) async {
    final repo = FakeChatRepository(currentUserId: 'user-a');
    repo.seedIncoming(
      id: 'm-reply-focus',
      relationshipId: 'rel-1',
      senderId: 'partner',
      content: 'reply to this',
      createdAt: DateTime.now(),
    );
    final container = await pumpChat(tester, repo);

    await tester.longPress(find.text('reply to this'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Reply'));
    await tester.pump(const Duration(milliseconds: 750));

    final editable = tester.widget<EditableText>(find.byType(EditableText));
    expect(editable.focusNode.hasFocus, isTrue);
    expect(find.byType(ReplyComposerPreview), findsOneWidget);

    await tearDownChat(tester, container);
  });

  testWidgets(
    'swipe-to-reply focuses composer and cancel waits for return flight',
    (tester) async {
      final repo = FakeChatRepository(currentUserId: 'user-a');
      repo.seedIncoming(
        id: 'm1',
        relationshipId: 'rel-1',
        senderId: 'partner',
        content: 'fly this reply',
        createdAt: DateTime.now(),
      );
      final container = await pumpChat(tester, repo);

      await tester.drag(find.text('fly this reply'), const Offset(120, 0));
      await tester.pump();

      final editable = tester.widget<EditableText>(find.byType(EditableText));
      expect(editable.focusNode.hasFocus, isTrue);
      expect(find.byType(ReplyComposerPreview), findsOneWidget);

      await tester.pumpAndSettle();
      final cancelButton = tester.widget<IconButton>(
        find.descendant(
          of: find.byType(ReplyComposerPreview),
          matching: find.byType(IconButton),
        ),
      );
      cancelButton.onPressed!();
      await tester.pump();
      expect(find.byType(ReplyComposerPreview), findsOneWidget);

      await tester.pumpAndSettle();
      expect(find.byType(ReplyComposerPreview), findsNothing);
      expect(find.text('fly this reply'), findsOneWidget);

      await tearDownChat(tester, container);
    },
  );

  testWidgets('Star from the sheet reaches the repository', (tester) async {
    final repo = FakeChatRepository(currentUserId: 'user-a');
    repo.seedIncoming(
      id: 'm1',
      relationshipId: 'rel-1',
      senderId: 'partner',
      content: 'hello there',
      createdAt: DateTime.now(),
    );
    final container = await pumpChat(tester, repo);

    await tester.longPress(find.text('hello there'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Star'));
    await tester.pump(const Duration(milliseconds: 400));

    expect(repo.starredMessageIds, contains('m1'));
    await tearDownChat(tester, container);
  });

  testWidgets('Pin from the sheet renders the pinned banner', (tester) async {
    final repo = FakeChatRepository(currentUserId: 'user-a');
    repo.seedIncoming(
      id: 'm1',
      relationshipId: 'rel-1',
      senderId: 'partner',
      content: 'pin me please',
      createdAt: DateTime.now(),
    );
    final container = await pumpChat(tester, repo);

    expect(find.byIcon(Icons.push_pin), findsNothing);

    await tester.longPress(find.text('pin me please'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Pin'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(seconds: 1));

    expect(repo.pinnedMessageIds, contains('m1'));
    // The banner's pin icon plus the bubble text now duplicated in the strip.
    expect(find.byIcon(Icons.push_pin), findsOneWidget);
    expect(find.text('pin me please'), findsNWidgets(2));

    await tearDownChat(tester, container);
  });

  testWidgets('already-pinned messages load into the banner on open', (
    tester,
  ) async {
    final repo = FakeChatRepository(currentUserId: 'user-a');
    repo.seedIncoming(
      id: 'm1',
      relationshipId: 'rel-1',
      senderId: 'partner',
      content: 'pinned earlier',
      createdAt: DateTime.now(),
    );
    repo.pinnedMessageIds.add('m1');

    final container = await pumpChat(tester, repo);

    expect(find.byIcon(Icons.push_pin), findsOneWidget);
    await tearDownChat(tester, container);
  });

  testWidgets('Delete confirms before calling the repository', (tester) async {
    final repo = FakeChatRepository(currentUserId: 'user-a');
    repo.seedIncoming(
      id: 'm1',
      relationshipId: 'rel-1',
      // Own message inside the edit/delete window so the sheet offers them.
      senderId: 'user-a',
      content: 'oops',
      createdAt: DateTime.now(),
    );
    final container = await pumpChat(tester, repo);

    await tester.longPress(find.text('oops'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Delete'));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Delete message?'), findsOneWidget);
    // Cancelling must not delete.
    await tester.tap(find.text('Cancel'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(repo.deleteMessageCalls, isEmpty);

    await tester.longPress(find.text('oops'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Delete'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await tester.pump(const Duration(milliseconds: 400));

    expect(repo.deleteMessageCalls, contains('m1'));
    // You deleted your own message, so the tombstone says so.
    expect(find.text('You deleted this message'), findsOneWidget);

    await tearDownChat(tester, container);
  });

  testWidgets('Info opens MessageInfoScreen for the long-pressed message — the '
      'exact recycled-element hazard _buildFullPickerOpener documents for '
      'the emoji picker applies here too, so this proves the callback '
      'still resolves after the menu route has popped', (tester) async {
    final repo = FakeChatRepository(currentUserId: 'user-a');
    repo.seedIncoming(
      id: 'm1',
      relationshipId: 'rel-1',
      senderId: 'user-a',
      content: 'inspect me',
      createdAt: DateTime.now(),
    );
    final container = await pumpChat(tester, repo);

    await tester.longPress(find.text('inspect me'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Info'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(find.text('Message info'), findsOneWidget);
    expect(find.text('Sent'), findsOneWidget);

    await tearDownChat(tester, container);
  });

  testWidgets(
    'Ask Attune appears for an eligible message and opens the mode sheet '
    'for that exact message',
    (tester) async {
      final repo = FakeChatRepository(currentUserId: 'user-a');
      final seeded = repo.seedIncoming(
        id: 'm-eligible',
        relationshipId: 'rel-1',
        senderId: 'partner',
        content: 'want to grab dinner this weekend?',
        createdAt: DateTime.now(),
      );
      final container = await pumpChat(
        tester,
        repo,
        extraOverrides: [
          // The mode sheet reads the relationship id and consent status
          // via these providers; point them at fixed values instead of
          // hitting Supabase — this test only asserts on the pushed
          // sheet's identity, not its consent-gated body.
          currentRelationshipIdProvider.overrideWith((ref) async => 'rel-1'),
          aiConsentStatusProvider('rel-1').overrideWith(
            (ref) async => const AiConsentStatus(
              callerGranted: true,
              bothGranted: true,
              policyVersion: 'v1',
            ),
          ),
        ],
      );

      await tester.longPress(
        find.text('want to grab dinner this weekend?'),
      );
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Ask Attune'), findsOneWidget);

      await tester.tap(find.text('Ask Attune'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));

      final sheet = tester.widget<AskAttuneModeSheet>(
        find.byType(AskAttuneModeSheet),
      );
      expect(sheet.message.id, seeded.id);

      await tearDownChat(tester, container);
    },
  );

  testWidgets(
    'Ask Attune is absent for a deleted message',
    (tester) async {
      final repo = FakeChatRepository(currentUserId: 'user-a');
      repo.seedIncoming(
        id: 'm-deleted',
        relationshipId: 'rel-1',
        senderId: 'user-a',
        content: 'oops sent this',
        createdAt: DateTime.now(),
        deletedAt: DateTime.now(),
      );
      final container = await pumpChat(tester, repo);

      await tester.longPress(find.text('You deleted this message'));
      await tester.pump(const Duration(milliseconds: 400));

      // A deleted message's tombstone offers no action surface at all
      // (canOpenActions requires !message.isDeleted), so no menu opens.
      expect(find.text('Ask Attune'), findsNothing);

      await tearDownChat(tester, container);
    },
  );

  testWidgets(
    'Ask Attune is absent for an over-4000-character message',
    (tester) async {
      final repo = FakeChatRepository(currentUserId: 'user-a');
      final longContent = 'a' * 4001;
      repo.seedIncoming(
        id: 'm-toolong',
        relationshipId: 'rel-1',
        senderId: 'partner',
        content: longContent,
        createdAt: DateTime.now(),
      );
      final container = await pumpChat(tester, repo);

      await tester.longPress(find.textContaining('aaaa'));
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Ask Attune'), findsNothing);

      await tearDownChat(tester, container);
    },
  );

  testWidgets(
    'Ask Attune is absent for an Attune Assist output message',
    (tester) async {
      final repo = FakeChatRepository(currentUserId: 'user-a');
      repo.seedIncoming(
        id: 'm-assist-output',
        relationshipId: 'rel-1',
        senderId: 'partner',
        content: 'Here is an idea: a picnic in the park.',
        createdAt: DateTime.now(),
        messageOrigin: 'attune_assist',
      );
      final container = await pumpChat(tester, repo);

      await tester.longPress(
        find.text('Here is an idea: a picnic in the park.'),
      );
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Ask Attune'), findsNothing);

      await tearDownChat(tester, container);
    },
  );

  testWidgets('Edit saves the new content through the controller', (
    tester,
  ) async {
    final repo = FakeChatRepository(currentUserId: 'user-a');
    repo.seedIncoming(
      id: 'm1',
      relationshipId: 'rel-1',
      senderId: 'user-a',
      content: 'teh typo',
      createdAt: DateTime.now(),
    );
    final container = await pumpChat(tester, repo);

    await tester.longPress(find.text('teh typo'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Edit'));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Edit message'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, 'the typo');
    await tester.tap(find.text('Save'));
    await tester.pump(const Duration(milliseconds: 400));

    expect(repo.editMessageCalls.single.messageId, 'm1');
    expect(repo.editMessageCalls.single.newContent, 'the typo');
    expect(find.text('the typo'), findsOneWidget);
    expect(find.text('edited'), findsNothing);

    await tester.tapAt(const Offset(10, 10));
    await tester.pump(const Duration(milliseconds: 400));
    await tearDownChat(tester, container);
  });

  // Fix round 1: an ended relationship opened through "Previous relationships"
  // reuses this same ChatScreen. The whole action surface is gated on
  // canSend, so long-press must not offer mutating actions the RPCs now
  // correctly reject server-side.
  testWidgets('read-only conversation offers no actions on long-press', (
    tester,
  ) async {
    final repo = FakeChatRepository(currentUserId: 'user-a');
    repo.seedIncoming(
      id: 'm1',
      relationshipId: 'rel-1',
      senderId: 'user-a',
      content: 'just sent this',
      createdAt: DateTime.now(),
    );
    final container = await pumpChat(
      tester,
      repo,
      conversation: readOnlyConversation('rel-1'),
    );

    await tester.longPress(find.text('just sent this'));
    await tester.pump(const Duration(milliseconds: 400));

    // No sheet at all — not merely Edit/Delete withheld.
    expect(find.text('Copy'), findsNothing);
    expect(find.text('Star'), findsNothing);
    expect(find.text('Pin'), findsNothing);
    expect(find.text('Edit'), findsNothing);
    expect(find.text('Delete'), findsNothing);

    await tearDownChat(tester, container);
  });

  testWidgets(
    'tapping a quick reaction in the focused menu reaches the repository',
    (tester) async {
      final repo = FakeChatRepository(currentUserId: 'user-a');
      repo.seedIncoming(
        id: 'm1',
        relationshipId: 'rel-1',
        senderId: 'partner',
        content: 'hello there',
        createdAt: DateTime.now(),
      );
      final container = await pumpChat(tester, repo);

      await tester.longPress(find.text('hello there'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('❤️'));
      await tester.pump(const Duration(milliseconds: 120));
      final flightEmoji = find.byKey(const ValueKey('reaction-flight-emoji'));
      expect(flightEmoji, findsOneWidget);
      expect(
        DefaultTextStyle.of(flightEmoji.evaluate().single).style.decoration,
        TextDecoration.none,
      );
      await tester.pump(const Duration(milliseconds: 280));

      expect(repo.reactionsByMessage['m1']?['user-a'], '❤️');
      var sawLandingSplash = false;
      for (var frame = 0; frame < 60; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        if (find
            .byKey(const ValueKey('reaction-landing-splash'))
            .evaluate()
            .isNotEmpty) {
          sawLandingSplash = true;
          break;
        }
      }
      expect(sawLandingSplash, isTrue);
      // The frame that inserts the splash also starts the bubble controller
      // at exactly 1x; advance into the shared impact beat before sampling.
      await tester.pump(const Duration(milliseconds: 64));
      final bubbleImpact = tester.widget<ScaleTransition>(
        find.byKey(const ValueKey('reaction-bubble-impact')),
      );
      expect(bubbleImpact.scale.value, greaterThan(1));
      await tester.pumpAndSettle();
      await tearDownChat(tester, container);
    },
  );

  testWidgets(
    'reacted message shows the pill immediately (no restart needed)',
    (tester) async {
      final repo = FakeChatRepository(currentUserId: 'user-a');
      repo.seedIncoming(
        id: 'm1',
        relationshipId: 'rel-1',
        senderId: 'partner',
        content: 'hello there',
        createdAt: DateTime.now(),
      );
      final container = await pumpChat(tester, repo);

      await tester.longPress(find.text('hello there'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('👍'));
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byKey(const ValueKey('reaction-mine-👍')), findsOneWidget);
      await tearDownChat(tester, container);
    },
  );

  testWidgets('timestamp reveal remains active across list rebuilds', (
    tester,
  ) async {
    final repo = FakeChatRepository(currentUserId: 'user-a');
    final now = DateTime.now();
    repo.seedIncoming(
      id: 'mine',
      relationshipId: 'rel-1',
      senderId: 'user-a',
      content: 'drag this message',
      createdAt: now,
    );
    repo.seedIncoming(
      id: 'partner',
      relationshipId: 'rel-1',
      senderId: 'partner',
      content: 'partner message',
      createdAt: now.subtract(const Duration(minutes: 1)),
    );
    final container = await pumpChat(tester, repo);

    final mine = find.byWidgetPredicate(
      (widget) => widget is Row && widget.key == const ValueKey('seed-mine'),
    );
    final partner = find.byWidgetPredicate(
      (widget) => widget is Row && widget.key == const ValueKey('seed-partner'),
    );
    final mineBefore = tester.getRect(mine);
    final partnerBefore = tester.getRect(partner);
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('drag this message')),
    );

    await gesture.moveBy(const Offset(-24, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(-76, 0));
    await tester.pump();

    final mineAfter = tester.getRect(mine);
    final partnerAfter = tester.getRect(partner);
    // The first 24 logical pixels are Flutter's horizontal touch slop. Once
    // the recognizer wins the arena, the second segment reaches the 70px
    // timestamp reveal cap requested by the chat design.
    expect(mineAfter.left - mineBefore.left, closeTo(-70, 0.01));
    expect(partnerAfter.left - partnerBefore.left, closeTo(-70, 0.01));

    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 240));
    expect(tester.getRect(mine).left, closeTo(mineBefore.left, 0.01));
    expect(tester.getRect(partner).left, closeTo(partnerBefore.left, 0.01));

    await tearDownChat(tester, container);
  });
}

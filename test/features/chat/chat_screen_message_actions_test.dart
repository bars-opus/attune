import 'dart:async';
import 'package:attune/features/ai_assistant/data/repositories/ai_assistant_repository.dart';
import 'package:attune/features/ai_assistant/data/models/ai_session_model.dart';
import 'package:attune/features/ai_assistant/data/repositories/ai_session_repository.dart';
import 'package:attune/features/ai_assistant/data/services/ai_session_capabilities.dart';
import 'package:attune/features/ai_assistant/presentation/providers/ai_session_provider.dart';
import 'package:attune/features/ai_assistant/presentation/screens/ai_session_entry.dart';
import 'package:attune/features/ai_assistant/presentation/screens/ai_session_sheet.dart';
import 'package:attune/features/chat/presentation/widgets/chat_text_field.dart';
import 'package:attune/features/ai_assistant/presentation/providers/ai_assistant_providers.dart';
import 'package:attune/features/ai_assistant/presentation/screens/ask_attune_mode_sheet.dart';
import 'package:attune/features/chat/domain/entities/conversation.dart';
import 'package:attune/features/chat/presentation/screens/chat_screen.dart';
import 'package:attune/features/chat/presentation/widgets/reply_composer_preview.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:animated_emoji/animated_emoji.dart';
import 'package:attune/features/chat/presentation/widgets/message_bubble.dart';
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

  testWidgets('opening the chat animates its latest emoji message', (
    tester,
  ) async {
    final repo = FakeChatRepository(currentUserId: 'user-a');
    repo.seedIncoming(
      id: 'last-emoji',
      relationshipId: 'rel-1',
      senderId: 'partner',
      content: '😴',
      createdAt: DateTime.now(),
    );
    final container = await pumpChat(tester, repo);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<AnimatedEmoji>(find.byType(AnimatedEmoji))
          .controller!
          .value,
      1,
    );
    await tearDownChat(tester, container);
  });

  testWidgets('receiving an emoji starts its animation', (tester) async {
    final repo = FakeChatRepository(currentUserId: 'user-a');
    repo.seedIncoming(
      id: 'previous',
      relationshipId: 'rel-1',
      senderId: 'partner',
      content: 'hello',
      createdAt: DateTime.now().subtract(const Duration(minutes: 1)),
    );
    final container = await pumpChat(tester, repo);
    repo.seedIncoming(
      id: 'new-emoji',
      relationshipId: 'rel-1',
      senderId: 'partner',
      content: '😴',
      createdAt: DateTime.now(),
    );
    repo.emitRealtime();
    for (var frame = 0; frame < 60; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(find.byType(AnimatedEmoji), findsOneWidget);
    expect(
      tester
          .widget<AnimatedEmoji>(find.byType(AnimatedEmoji))
          .controller!
          .value,
      greaterThan(0),
    );
    await tester.pumpAndSettle();
    await tearDownChat(tester, container);
  });

  testWidgets('keyboard emoji keeps playing after the send flight lands', (
    tester,
  ) async {
    final repo = FakeChatRepository(currentUserId: 'user-a');
    final container = await pumpChat(tester, repo);
    await tester.enterText(find.byType(TextField).last, '😴');
    await tester.pump();
    await tester.tap(find.byTooltip('Send message'));
    // Sample well after the short flight but before the emoji's full cycle.
    for (var frame = 0; frame < 70; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    final animation = find.descendant(
      of: find.byType(MessageBubble),
      matching: find.byType(AnimatedEmoji),
    );
    expect(animation, findsOneWidget);
    final controller = tester.widget<AnimatedEmoji>(animation).controller!;
    expect(controller.value, greaterThan(0));
    final before = controller.value;
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      tester.widget<AnimatedEmoji>(animation).controller!.value,
      greaterThan(before),
    );
    await tester.pumpAndSettle();
    await tearDownChat(tester, container);
  });

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

    // Dismisses the menu via its own barrierDismissible tap-outside
    // handler (focused_action_menu.dart) — a point far from both the
    // menu content (which anchors near the tapped bubble, not here)
    // and the header's own controls. The old (10, 10) used to be
    // safely empty; it stopped being once the chat header grew an
    // explicit back button in that exact corner.
    await tester.tapAt(const Offset(400, 1350));
    await tester.pump(const Duration(milliseconds: 400));
    await tearDownChat(tester, container);
  });

  testWidgets(
    'long-press on a link still opens the menu, and Copy link copies it (#37)',
    (tester) async {
      final copied = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied.add((call.arguments as Map)['text'] as String);
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      final repo = FakeChatRepository(currentUserId: 'user-a');
      repo.seedIncoming(
        id: 'm-plain',
        relationshipId: 'rel-1',
        senderId: 'partner',
        content: 'no link in this one',
        createdAt: DateTime.now().subtract(const Duration(minutes: 1)),
      );
      repo.seedIncoming(
        id: 'm-link',
        relationshipId: 'rel-1',
        senderId: 'partner',
        content: 'dinner here www.example.com/menu tonight?',
        createdAt: DateTime.now(),
      );
      final container = await pumpChat(tester, repo);

      await tester.longPress(find.text('no link in this one'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Copy'), findsOneWidget);
      expect(find.text('Copy link'), findsNothing);
      await tester.tapAt(const Offset(400, 1350));
      await tester.pump(const Duration(milliseconds: 400));

      await tester.longPress(
        find.text('dinner here www.example.com/menu tonight?'),
      );
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Copy'), findsOneWidget);
      expect(find.text('Copy link'), findsOneWidget);

      await tester.tap(find.text('Copy link'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(copied, ['https://www.example.com/menu']);
      expect(find.text('Link copied'), findsOneWidget);

      await tester.pump(const Duration(seconds: 5));
      await tearDownChat(tester, container);
    },
  );

  testWidgets('Copy link copies the link as typed, not percent-encoded', (
    tester,
  ) async {
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add((call.arguments as Map)['text'] as String);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final repo = FakeChatRepository(currentUserId: 'user-a');
    repo.seedIncoming(
      id: 'm-cafe',
      relationshipId: 'rel-1',
      senderId: 'partner',
      content: 'try https://example.com/café today',
      createdAt: DateTime.now(),
    );
    final container = await pumpChat(tester, repo);

    await tester.longPress(find.text('try https://example.com/café today'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Copy link'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(copied, ['https://example.com/café']);

    await tester.pump(const Duration(seconds: 5));
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
          // RULING 23 (Plan D Task 9): "Ask Attune" is now gated on
          // §12's `ai_assist_enabled`, read through Task 5's capability
          // service. Nothing gated it before — the base spec's own
          // recorded finding — so this override is what makes the
          // ENTRY POINT available, and the test asserts the entry point
          // appears. Without it the capability fails closed and the
          // tile is correctly absent, which is what the dedicated gate
          // test below asserts instead.
          aiSessionCapabilitiesProvider.overrideWith(
            (ref) async => const AiSessionCapabilities(
              assist: true,
              sessionsPrivate: false,
              sessionsShared: false,
              sessionsRecentWindow: false,
              sessionsNearby: false,
            ),
          ),
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

      await tester.longPress(find.text('want to grab dinner this weekend?'));
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

  testWidgets('Ask Attune is absent for a deleted message', (tester) async {
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
  });

  testWidgets('Ask Attune is absent for an over-4000-character message', (
    tester,
  ) async {
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
  });

  testWidgets('Ask Attune is absent for an Attune Assist output message', (
    tester,
  ) async {
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

    await tester.longPress(find.text('Here is an idea: a picnic in the park.'));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Ask Attune'), findsNothing);

    await tearDownChat(tester, container);
  });

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
    // f29007b6 asserted the label was absent; that WAS the regression.
    expect(find.text('edited'), findsOneWidget);

    // Dismisses the menu via its own barrierDismissible tap-outside
    // handler (focused_action_menu.dart) — a point far from both the
    // menu content (which anchors near the tapped bubble, not here)
    // and the header's own controls. The old (10, 10) used to be
    // safely empty; it stopped being once the chat header grew an
    // explicit back button in that exact corner.
    await tester.tapAt(const Offset(400, 1350));
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

  // ===================================================================
  // PLAN D TASK 9 — the two AI entry points, in the REAL ChatScreen
  // ===================================================================
  //
  // These are at the screen level deliberately. `ai_session_entry_test`
  // proves the opener and RULING 24 in isolation; what only a real
  // ChatScreen can prove is that the WIRING resolves the capability
  // from the right provider and that the default — capability OFF, as
  // it ships — leaves this screen behaviourally identical to today.
  //
  // RULING 29: these do not stand in for the full suite. The full
  // `flutter test` count is the verdict and is reported in the task
  // report.

  /// `assist` on, every SESSION capability off — so the Ask Attune
  /// legs below cannot pass because some other flag was on, and §12's
  /// subcapability independence is exercised rather than assumed.
  Override assistOnlyOverride({required bool assist}) {
    return aiSessionCapabilitiesProvider.overrideWith(
      (ref) async => AiSessionCapabilities(
        assist: assist,
        sessionsPrivate: false,
        sessionsShared: false,
        sessionsRecentWindow: false,
        sessionsNearby: false,
      ),
    );
  }

  group('the capability is OFF: this chat screen is exactly as it was', () {
    testWidgets(
      'no AI composer button is drawn, and the composer pill keeps the '
      'rect it has with no capability provider overridden at all',
      (tester) async {
        // THE REGRESSION PROOF for the composer half. The harness
        // (`buildChatContainer`) does NOT override
        // aiSessionCapabilitiesProvider, so this is the literal
        // production default: the service fails closed, `.assist` is
        // false, `onAiButtonTap` is null, and ChatTextField's own
        // contract makes a null callback hide the entry point.
        final repo = FakeChatRepository(currentUserId: 'user-a');
        final container = await pumpChat(tester, repo);

        expect(
          find.byIcon(Icons.auto_awesome),
          findsNothing,
          reason:
              'the six capability flags are OFF in every environment and '
              'flip only AFTER Plan D ships, so the composer must look '
              'exactly as it does today',
        );

        // The pill must occupy the same rect, not merely exist — the
        // shape Task 6 used, because an added-then-hidden satellite
        // can still shift the row.
        final pill = find.byKey(const ValueKey('composer-pill'));
        expect(pill, findsOneWidget);
        final rect = tester.getRect(pill);
        // Anti-vacuity: a zero-size or offscreen pill would pass a bare
        // "the rect is what it is" comparison against itself.
        expect(rect.width, greaterThan(100));
        expect(rect.height, greaterThan(20));

        // And every control the composer draws today still draws.
        expect(find.byType(ChatTextField), findsOneWidget);
        final composer = tester.widget<ChatTextField>(
          find.byType(ChatTextField),
        );
        expect(
          composer.onAiButtonTap,
          isNull,
          reason: 'null is the gate: ChatTextField draws no AI satellite',
        );
        expect(
          composer.aiMode,
          isFalse,
          reason:
              'Task 9 never passes aiMode — entering AI mode is later '
              'work, so the composer keeps every control it has',
        );

        await tearDownChat(tester, container);
      },
    );

    testWidgets(
      'an UNRESOLVED capability reads as OFF, not as permission',
      (tester) async {
        // ADDED AFTER A MUTATION (M8) SURVIVED. Replacing
        // `.valueOrNull?.assist == true` with `?? true` passed every
        // other test here, because every one of them resolves the
        // provider before the long-press. In production the first chat
        // open makes a real RPC round trip, so there IS a window where
        // the value is null — and `?? true` offers Ask Attune during
        // it. That is the wrong failure direction (§12: defaults off),
        // and nothing else was measuring it.
        //
        // A never-completing override models the window honestly: a
        // slow or unreachable server, which is exactly when the
        // capability service fails closed.
        final repo = FakeChatRepository(currentUserId: 'user-a');
        repo.seedIncoming(
          id: 'm-pending',
          relationshipId: 'rel-1',
          senderId: 'partner',
          content: 'still loading?',
          createdAt: DateTime.now(),
        );
        final container = await pumpChat(
          tester,
          repo,
          extraOverrides: [
            aiSessionCapabilitiesProvider.overrideWith(
              (ref) => Completer<AiSessionCapabilities>().future,
            ),
          ],
        );

        // The composer half.
        expect(
          find.byIcon(Icons.auto_awesome),
          findsNothing,
          reason:
              'a loading capability must not draw the AI entry point',
        );

        await tester.longPress(find.text('still loading?'));
        await tester.pump(const Duration(milliseconds: 400));

        // Anti-vacuity: the menu is open, so "no Ask Attune" is a
        // finding rather than an artefact of a failed long-press.
        expect(find.text('Copy'), findsOneWidget);
        expect(
          find.text('Ask Attune'),
          findsNothing,
          reason:
              'an unknown capability is NOT permission — a `?? true` '
              'here would offer the entry point for the whole duration '
              'of the first round trip',
        );

        await tester.tapAt(const Offset(400, 1350));
        await tester.pump(const Duration(milliseconds: 400));
        await tearDownChat(tester, container);
      },
    );

    testWidgets('Ask Attune is absent when ai_assist_enabled is off', (
      tester,
    ) async {
      // RULING 23's own leg. This is the ONE behavioural change Task 9
      // makes with the flags as they ship — and it CLOSES the base
      // spec's recorded gap ("Ask Attune is wired live with no feature
      // flag guarding it") rather than opening one.
      final repo = FakeChatRepository(currentUserId: 'user-a');
      repo.seedIncoming(
        id: 'm-gated',
        relationshipId: 'rel-1',
        senderId: 'partner',
        content: 'dinner on friday?',
        createdAt: DateTime.now(),
      );
      final container = await pumpChat(
        tester,
        repo,
        extraOverrides: [assistOnlyOverride(assist: false)],
      );

      await tester.longPress(find.text('dinner on friday?'));
      await tester.pump(const Duration(milliseconds: 400));

      // The menu DID open — this is not "no menu", it is "no Ask
      // Attune". Without these the test would pass on a broken
      // long-press.
      expect(find.text('Copy'), findsOneWidget);
      expect(find.text('Info'), findsOneWidget);
      expect(
        find.text('Ask Attune'),
        findsNothing,
        reason:
            'RULING 23: §12 ai_assist_enabled now gates this entry '
            'point, read through Task 5 capability RPC and never '
            'feature_flags',
      );

      await tester.tapAt(const Offset(400, 1350));
      await tester.pump(const Duration(milliseconds: 400));
      await tearDownChat(tester, container);
    });
  });

  group('the capability is ON: the entry points appear', () {
    testWidgets('Ask Attune returns when ai_assist_enabled is on', (
      tester,
    ) async {
      // The other direction of the same gate. Without this leg, a gate
      // hardcoded to `false` would pass every test above.
      final repo = FakeChatRepository(currentUserId: 'user-a');
      repo.seedIncoming(
        id: 'm-ungated',
        relationshipId: 'rel-1',
        senderId: 'partner',
        content: 'dinner on saturday?',
        createdAt: DateTime.now(),
      );
      final container = await pumpChat(
        tester,
        repo,
        extraOverrides: [assistOnlyOverride(assist: true)],
      );

      await tester.longPress(find.text('dinner on saturday?'));
      await tester.pump(const Duration(milliseconds: 400));

      expect(
        find.text('Ask Attune'),
        findsOneWidget,
        reason:
            'assist alone must be enough: §12 subcapability '
            'independence means the Ask Attune tile must NOT require '
            'any session flag',
      );

      await tester.tapAt(const Offset(400, 1350));
      await tester.pump(const Duration(milliseconds: 400));
      await tearDownChat(tester, container);
    });

    testWidgets(
      'the composer AI button appears and opens exactly one '
      'AiSessionSheet (RULING 24 through the real screen)',
      (tester) async {
        final repo = FakeChatRepository(currentUserId: 'user-a');
        final container = await pumpChat(
          tester,
          repo,
          extraOverrides: [
            aiSessionCapabilitiesProvider.overrideWith(
              (ref) async => const AiSessionCapabilities(
                assist: true,
                sessionsPrivate: true,
                sessionsShared: false,
                sessionsRecentWindow: false,
                sessionsNearby: false,
              ),
            ),
            // The sheet must not reach the network when it mounts.
            aiSessionRepositoryProvider.overrideWithValue(
              AiSessionRepository(_SilentSessionGateway()),
            ),
          ],
        );

        final aiButton = find.byIcon(Icons.auto_awesome);
        expect(
          aiButton,
          findsOneWidget,
          reason:
              'with .assist on, onAiButtonTap is non-null and '
              'ChatTextField draws the satellite',
        );

        await tester.tap(aiButton);
        await tester.pumpAndSettle();
        expect(find.byType(AiSessionSheet), findsOneWidget);

        // RULING 24 end to end: the sheet covers the composer, so a
        // second tap cannot be delivered by a user — this asserts the
        // invariant at the level a user can reach, by calling the
        // opener again against the SAME container.
        expect(
          openAiSessionSheet(
            container: container,
            navigator: tester.state<NavigatorState>(
              find.byType(Navigator).last,
            ),
            relationshipId: 'rel-1',
            initialKind: AiSessionKind.ideas,
            utcOffsetMinutes: 0,
            onShared: (_) {},
          ),
          isFalse,
        );
        await tester.pumpAndSettle();
        expect(find.byType(AiSessionSheet), findsOneWidget);

        // Leave the sheet before teardown so the chat screen unmounts
        // the way the other tests in this file expect.
        Navigator.of(
          tester.element(find.byType(AiSessionSheet)),
        ).pop();
        await tester.pumpAndSettle();
        await tearDownChat(tester, container);
      },
    );
  });
}

/// Answers every session command with a shape the sheet can render
/// without a network. The entry-point tests only need the sheet to
/// MOUNT; `ai_session_sheet_test.dart` owns what it does next.
class _SilentSessionGateway implements AiAssistantGateway {
  @override
  Future<dynamic> invokeFunction(
    String functionName, {
    Map<String, dynamic>? body,
  }) async => <String, Object?>{};

  @override
  Future<dynamic> rpc(String function, {Map<String, dynamic>? params}) async =>
      null;

  @override
  Future<Map<String, dynamic>?> selectPlanningLink(String messageId) async =>
      null;
}

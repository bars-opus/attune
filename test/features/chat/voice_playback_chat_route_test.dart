import 'dart:async';

import 'package:attune/app/routing/app_route_observer.dart';
import 'package:attune/features/chat/data/repositories/chat_repository.dart';
import 'package:attune/features/chat/domain/entities/conversation.dart';
import 'package:attune/features/chat/presentation/screens/chat_screen.dart';
import 'package:attune/features/chat/presentation/state/chat_state.dart';
import 'package:attune/features/chat/presentation/state/voice_playback_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/chat_test_harness.dart';
import 'support/fake_voice_engine.dart';

/// Wave 2 #21: the voice controller is app-scoped, so the chat screen says
/// when it is left. Leaving stops playback (spec: no background playback);
/// a sheet or a page pushed OVER the chat does not.
void main() {
  const userId = 'user-a';
  const relId = 'rel-1';

  setUp(() => appRouteObserver.lastPushedRoute = null);

  Future<(ProviderContainer, FakeVoiceEngine, NavigatorState)> pumpChat(
    WidgetTester tester, {
    void Function(FakeChatRepository repo)? seed,
  }) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final repo = FakeChatRepository(currentUserId: userId);
    seed?.call(repo);
    final engine = FakeVoiceEngine();
    final container = buildChatContainer(
      repository: repo,
      userId: userId,
      extraOverrides: [
        voicePlaybackEngineProvider.overrideWithValue(engine),
        // The fake engine sends no position ticks: keep the stall watchdog
        // out of a test that pumps seconds of route transitions.
        voicePlaybackStallAfterProvider.overrideWithValue(
          const Duration(hours: 1),
        ),
      ],
    );
    final convo = activeConversation(relId);
    repo.conversationOverride = convo;

    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: withScreenUtil(
          MaterialApp(
            navigatorKey: navigatorKey,
            navigatorObservers: [appRouteObserver],
            home: const Scaffold(body: Text('Conversations')),
          ),
        ),
      ),
    );
    unawaited(
      navigatorKey.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => ChatScreen(conversation: convo),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    return (container, engine, navigatorKey.currentState!);
  }

  Future<void> play(ProviderContainer container) async {
    await container
        .read(voicePlaybackControllerProvider.notifier)
        .toggle('m1', () async => 'https://example.com/a.m4a');
  }

  bool isPlaying(ProviderContainer container) =>
      container.read(voicePlaybackControllerProvider).isPlaying;

  testWidgets('a sheet or a page over the chat leaves the note playing; '
      'popping the chat stops it', (tester) async {
    final (container, engine, navigator) = await pumpChat(tester);
    await play(container);
    expect(isPlaying(container), isTrue);

    // A sheet over the chat: the person is still in it.
    unawaited(
      showModalBottomSheet<void>(
        context: tester.element(find.byType(ChatScreen)),
        builder: (_) => const SizedBox(height: 200, child: Text('sheet')),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(isPlaying(container), isTrue, reason: 'a sheet is not leaving');
    navigator.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // A page (viewer, game) over the chat: the chat route is still alive.
    unawaited(
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('viewer')),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(isPlaying(container), isTrue, reason: 'WhatsApp keeps playing');
    expect(engine.calls, isNot(contains('stop')));
    navigator.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(isPlaying(container), isTrue);

    // Leaving the chat.
    navigator.pop();
    await tester.pump();
    expect(isPlaying(container), isFalse, reason: 'leaving the chat stops it');
    expect(container.read(voicePlaybackControllerProvider).messageId, isNull);
    expect(engine.calls.last, 'stop');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
    container.dispose();
  });

  testWidgets('the chat taken away without a pop still stops playback', (
    tester,
  ) async {
    final (container, engine, _) = await pumpChat(tester);
    await play(container);
    expect(isPlaying(container), isTrue);

    // A declarative stack change: no didPop, only dispose.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
    expect(isPlaying(container), isFalse);
    expect(engine.calls.last, 'stop');
    container.dispose();
  });

  testWidgets('another chat taking the screen stops this chat\'s note; '
      'the chat underneath going away leaves the new chat\'s note playing', (
    tester,
  ) async {
    final (container, engine, navigator) = await pumpChat(tester);
    final voice = container.read(voicePlaybackControllerProvider.notifier);
    await voice.toggle(
      'a1',
      () async => 'https://example.com/a.m4a',
      ownerId: relId,
    );
    final chatARoute = ModalRoute.of(tester.element(find.byType(ChatScreen)))!;

    // Chat B (a notification, say) is pushed over chat A.
    unawaited(
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => ChatScreen(conversation: activeConversation('rel-2')),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      container.read(voicePlaybackControllerProvider).messageId,
      isNull,
      reason: 'one conversation audible at a time',
    );

    await voice.toggle(
      'b1',
      () async => 'https://example.com/b.m4a',
      ownerId: 'rel-2',
    );
    // Chat A is taken off the stack underneath B (no pop): its dispose
    // must not silence B's note.
    navigator.removeRoute(chatARoute);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(container.read(voicePlaybackControllerProvider).messageId, 'b1');
    expect(isPlaying(container), isTrue);

    navigator.pop();
    await tester.pump();
    expect(
      container.read(voicePlaybackControllerProvider).messageId,
      isNull,
      reason: 'leaving chat B stops its own note',
    );
    expect(engine.calls.last, 'stop');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
    container.dispose();
  });

  testWidgets('a playing note whose message is deleted stops', (tester) async {
    final (container, engine, _) = await pumpChat(
      tester,
      seed: (repo) {
        for (final id in ['v1', 'v2']) {
          repo.seedIncoming(
            id: id,
            relationshipId: relId,
            senderId: 'partner',
            content: '',
            createdAt: DateTime.now().subtract(const Duration(minutes: 1)),
            mediaType: 'audio',
          );
        }
      },
    );
    final chat = container.read(
      chatControllerProvider(activeConversation(relId)).notifier,
    );
    final messages =
        container
            .read(chatControllerProvider(activeConversation(relId)))
            .messages;
    final v1 = messages.firstWhere((m) => m.id == 'v1');
    final v2 = messages.firstWhere((m) => m.id == 'v2');
    expect(v1.hasAudio, isTrue);

    final voice = container.read(voicePlaybackControllerProvider.notifier);
    await voice.toggle(
      v1.clientMessageId,
      () async => 'https://example.com/a.m4a',
      ownerId: relId,
    );

    await chat.deleteMessage(v2);
    await tester.pump();
    expect(
      isPlaying(container),
      isTrue,
      reason: 'another message going away changes nothing',
    );

    await chat.deleteMessage(v1);
    await tester.pump();
    expect(container.read(voicePlaybackControllerProvider).messageId, isNull);
    expect(engine.calls.last, 'stop');

    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
    container.dispose();
  });

  group('a note from the Media screen (an older message this chat never '
      'loaded)', () {
    // Media lists every voice note of the conversation from a one-shot
    // fetch, so the playing note need not be in the chat's loaded list —
    // the list-based check cannot see it go away.
    Future<(ProviderContainer, FakeVoiceEngine, FakeChatRepository)> pumpOld(
      WidgetTester tester,
    ) async {
      late FakeChatRepository repo;
      final (container, engine, _) = await pumpChat(
        tester,
        seed: (r) {
          repo = r;
          r.seedIncoming(
            id: 'recent',
            relationshipId: relId,
            senderId: 'partner',
            content: 'hi',
            createdAt: DateTime.now(),
          );
        },
      );
      final voice = container.read(voicePlaybackControllerProvider.notifier);
      await voice.toggle(
        'seed-old-1',
        () async => 'https://example.com/old.m4a',
        ownerId: relId,
        serverMessageId: 'old-1',
      );
      expect(isPlaying(container), isTrue);
      return (container, engine, repo);
    }

    Future<void> settle(WidgetTester tester) async {
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
    }

    Future<void> finish(WidgetTester tester, ProviderContainer c) async {
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 10));
      c.dispose();
    }

    testWidgets('stops when the message is soft-deleted (realtime)', (
      tester,
    ) async {
      final (container, engine, repo) = await pumpOld(tester);
      repo.seedIncoming(
        id: 'old-1',
        relationshipId: relId,
        senderId: 'partner',
        content: '',
        createdAt: DateTime.now().subtract(const Duration(days: 30)),
        mediaType: 'audio',
        deletedAt: DateTime.now(),
      );
      repo.emitRealtime(
        const ChatRealtimeEvent(
          ChatRealtimeKind.messageUpdate,
          messageId: 'old-1',
        ),
      );
      await settle(tester);
      expect(container.read(voicePlaybackControllerProvider).messageId, isNull);
      expect(engine.calls.last, 'stop');
      await finish(tester, container);
    });

    testWidgets('stops when the message is hard-deleted (realtime)', (
      tester,
    ) async {
      final (container, engine, repo) = await pumpOld(tester);
      repo.emitRealtime(
        const ChatRealtimeEvent(
          ChatRealtimeKind.messageDelete,
          messageId: 'old-1',
        ),
      );
      await settle(tester);
      expect(container.read(voicePlaybackControllerProvider).messageId, isNull);
      expect(engine.calls.last, 'stop');
      await finish(tester, container);
    });

    testWidgets('an unrelated edit leaves it playing', (tester) async {
      final (container, _, repo) = await pumpOld(tester);
      repo.emitRealtime(
        const ChatRealtimeEvent(
          ChatRealtimeKind.messageUpdate,
          messageId: 'recent',
        ),
      );
      await settle(tester);
      expect(isPlaying(container), isTrue);
      await container.read(voicePlaybackControllerProvider.notifier).stop();
      await finish(tester, container);
    });

    testWidgets('stops when the conversation is archived', (tester) async {
      final (container, engine, repo) = await pumpOld(tester);
      repo.conversationOverride = activeConversation(
        relId,
      ).copyWith(availability: ConversationAvailability.archived);
      repo.emitRealtime(const ChatRealtimeEvent(ChatRealtimeKind.relationship));
      await settle(tester);
      expect(container.read(voicePlaybackControllerProvider).messageId, isNull);
      expect(engine.calls.last, 'stop');
      await finish(tester, container);
    });
  });
}

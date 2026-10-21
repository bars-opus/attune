import 'dart:async';
import 'dart:io';

import 'package:attune/features/chat/data/cache/chat_cache_service.dart';
import 'package:attune/features/chat/data/cache/pending_send.dart';
import 'package:attune/features/chat/domain/entities/conversation.dart';
import 'package:attune/features/chat/domain/entities/message.dart';
import 'package:attune/features/chat/presentation/state/chat_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/chat_test_harness.dart';

class _Booted {
  _Booted(this.controller, this.container, this.conversation, this.cache);
  final ChatController controller;
  final ProviderContainer container;
  final Conversation conversation;
  final ChatCacheService cache;
  ChatState get state => container.read(chatControllerProvider(conversation));
  Future<List<PendingSend>> outbox() =>
      cache.readOutbox('user-a', relationshipId: 'rel-1');
}

void main() {
  const userId = 'user-a';
  const relId = 'rel-1';

  Future<_Booted> boot(
    FakeChatRepository repo, {
    ChatCacheService? cache,
    Conversation? conversation,
  }) async {
    final effectiveCache =
        cache ?? ChatCacheService.forTesting(backend: memBackend());
    final container = buildChatContainer(
      repository: repo,
      userId: userId,
      cache: effectiveCache,
    );
    addTearDown(container.dispose);
    final convo = conversation ?? activeConversation(relId);
    repo.conversationOverride = convo;
    final controller = container.read(chatControllerProvider(convo).notifier);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    return _Booted(controller, container, convo, effectiveCache);
  }

  PendingSend pendingText(
    String clientMessageId,
    String text, {
    required DateTime createdAt,
    DateTime? nextAttemptAt,
    int attempts = 0,
    PendingSendState state = PendingSendState.queued,
  }) => PendingSend(
    clientMessageId: clientMessageId,
    relationshipId: relId,
    senderId: userId,
    text: text,
    createdAt: createdAt,
    attempts: attempts,
    nextAttemptAt: nextAttemptAt,
    state: state,
  );

  group('#2 failure policy', () {
    test(
      'seven consecutive offline failures keep the message queued, never failed',
      () async {
        final repo = FakeChatRepository(currentUserId: userId);
        for (var i = 0; i < 7; i++) {
          repo.sendErrorQueue.add(const SocketException('no route to host'));
        }
        final b = await boot(repo);

        await b.controller.sendMessage('on my way');
        for (var i = 0; i < 6; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          expect(
            b.state.messages.single.status,
            MessageStatus.queued,
            reason: 'offline attempt ${i + 1} must not consume the cap',
          );
          await b.controller.flushOutbox(force: true);
        }
        expect(repo.sendCallCount, 7);
        final row = (await b.outbox()).single;
        expect(row.state, PendingSendState.queued);
        expect(row.nextAttemptAt, isNotNull);

        await b.controller.flushOutbox(force: true); // the network is back
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(b.state.messages.single.status, MessageStatus.sent);
        expect(await b.outbox(), isEmpty);
      },
    );

    test(
      'a server-side unknown error still gives up after five attempts',
      () async {
        final repo = FakeChatRepository(currentUserId: userId);
        for (var i = 0; i < 5; i++) {
          repo.sendErrorQueue.add(StateError('something odd'));
        }
        final b = await boot(repo);

        await b.controller.sendMessage('x');
        for (var i = 0; i < 4; i++) {
          await b.controller.flushOutbox(force: true);
        }
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(repo.sendCallCount, 5);
        expect(b.state.messages.single.status, MessageStatus.failed);
        expect(
          (await b.outbox()).single.state,
          PendingSendState.failedPermanent,
        );
      },
    );

    test(
      'a 42501 against a now read-only chat is explained as read-only',
      () async {
        final repo = FakeChatRepository(currentUserId: userId);
        repo.sendDelay = const Duration(milliseconds: 80);
        repo.nextSendError = const PostgrestException(
          message: 'new row violates row-level security policy',
          code: '42501',
        );
        final b = await boot(repo);

        final send = b.controller.sendMessage('racing the pause');
        await Future<void>.delayed(const Duration(milliseconds: 10));
        // The partner paused while the insert was in flight.
        b.controller.debugSetConversation(readOnlyConversation(relId));
        await send;

        expect(b.state.messages.single.status, MessageStatus.failed);
        expect(b.state.error, 'This relationship chat is read-only.');
        expect(
          (await b.outbox()).single.lastErrorCategory,
          'relationshipInactive',
        );
      },
    );
  });

  group('#3 one timer at the queue head', () {
    test(
      'an earlier item with a later deadline is waited for, then both go in order',
      () async {
        final repo = FakeChatRepository(currentUserId: userId);
        final cache = ChatCacheService.forTesting(backend: memBackend());
        final now = DateTime.now();
        await cache.putOutbox(
          userId,
          pendingText(
            'a',
            'A',
            createdAt: now.subtract(const Duration(seconds: 10)),
            attempts: 2,
            nextAttemptAt: now.add(const Duration(milliseconds: 350)),
          ),
        );
        await cache.putOutbox(
          userId,
          pendingText(
            'b',
            'B',
            createdAt: now.subtract(const Duration(seconds: 5)),
            attempts: 1,
            nextAttemptAt: now.add(const Duration(milliseconds: 100)),
          ),
        );

        final b = await boot(repo, cache: cache);
        await Future<void>.delayed(const Duration(milliseconds: 120));
        expect(repo.sendCallCount, 0, reason: 'B must not overtake A');

        await Future<void>.delayed(const Duration(milliseconds: 400));
        expect(repo.sentContents, ['A', 'B']);
        expect(await b.outbox(), isEmpty);
        expect(
          b.state.messages.map((m) => m.status),
          everyElement(MessageStatus.sent),
        );
      },
    );

    test(
      'a failure re-arms the timer and the item is retried without any user action',
      () async {
        final repo = FakeChatRepository(currentUserId: userId);
        repo.sendErrorQueue.add(const SocketException('blip'));
        final b = await boot(repo);

        await b.controller.sendMessage('retry me');
        expect(b.state.messages.single.status, MessageStatus.queued);

        // First backoff window is 1-2 s (1 << 1 seconds, equal jitter).
        await Future<void>.delayed(const Duration(milliseconds: 2300));
        expect(b.state.messages.single.status, MessageStatus.sent);
        expect(repo.sendCallCount, 2);
      },
    );
  });

  group('#4 the 23505 reconcile cannot escape', () {
    test(
      'a lost response during reconcile leaves a queued, retryable row — not a stuck clock',
      () async {
        final repo = FakeChatRepository(currentUserId: userId);
        repo.simulateDuplicate = true;
        repo.findMessageError = const SocketException('timed out');
        final b = await boot(repo);

        await b.controller.sendMessage('dup'); // must complete without throwing
        await Future<void>.delayed(const Duration(milliseconds: 10));

        final bubble = b.state.messages.single;
        expect(bubble.status, MessageStatus.queued);
        expect(b.state.isSending, isFalse);
        final row = (await b.outbox()).single;
        expect(row.state, PendingSendState.queued);
        expect(row.nextAttemptAt, isNotNull);

        // The network returns: the duplicate reconciles to the canonical row.
        repo.duplicateClientMessageId = bubble.clientMessageId;
        await b.controller.flushOutbox(force: true);
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(b.state.messages.single.status, MessageStatus.sent);
        expect(b.state.messages.single.id.startsWith('_local_'), isFalse);
        expect(await b.outbox(), isEmpty);
      },
    );

    test(
      'a canonical row already in the cache wins over its own stale outbox row, which then reconciles',
      () async {
        // Crash between the server ack and removeOutbox: both exist on restart.
        final repo = FakeChatRepository(currentUserId: userId);
        final canonical = repo.seedIncoming(
          id: 'srv-1',
          relationshipId: relId,
          senderId: userId,
          content: 'acked before the crash',
          createdAt: DateTime.now().subtract(const Duration(minutes: 1)),
        );
        final cache = ChatCacheService.forTesting(backend: memBackend());
        await cache.writeMessages(userId, relId, [canonical]);
        await cache.putOutbox(
          userId,
          pendingText(
            canonical.clientMessageId,
            'acked before the crash',
            createdAt: canonical.createdAt,
            state: PendingSendState.sending,
          ),
        );
        repo.simulateDuplicate = true;
        repo.duplicateClientMessageId = canonical.clientMessageId;

        final b = await boot(repo, cache: cache);
        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(b.state.messages, hasLength(1));
        expect(b.state.messages.single.id, 'srv-1');
        expect(
          await b.outbox(),
          isEmpty,
          reason: 'the server already has it: the stale row is gone',
        );
      },
    );
  });

  group('#5 FIFO', () {
    test(
      'a message typed while an earlier one waits for the network goes out after it',
      () async {
        final repo = FakeChatRepository(currentUserId: userId);
        repo.sendErrorQueue.add(const SocketException('offline'));
        final b = await boot(repo);

        await b.controller.sendMessage('A');
        await b.controller.sendMessage('B');
        await Future<void>.delayed(const Duration(milliseconds: 10));

        expect(repo.sendCallCount, 1, reason: 'B waits behind A');
        expect(
          b.state.messages.map((m) => m.status),
          everyElement(MessageStatus.queued),
        );

        await b.controller.flushOutbox(force: true);
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(repo.sentContents, ['A', 'B']);
      },
    );

    test(
      'tapping retry sends the queue in order, not the tapped message first',
      () async {
        final repo = FakeChatRepository(currentUserId: userId);
        repo.sendErrorQueue.add(const SocketException('offline'));
        final b = await boot(repo);
        await b.controller.sendMessage('A');
        await b.controller.sendMessage('B');
        final bBubble = b.state.messages.firstWhere((m) => m.content == 'B');

        await b.controller.retryMessage(bBubble);
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(repo.sentContents, ['A', 'B']);
      },
    );
  });

  group('read-only terminal state (Spec 16: relationship ends while queued)', () {
    test(
      'queued messages become failed with a plain explanation and no Retry',
      () async {
        final repo = FakeChatRepository(currentUserId: userId);
        repo.sendErrorQueue.add(const SocketException('offline'));
        final b = await boot(repo);
        await b.controller.sendMessage('never sent');
        expect(b.state.messages.single.status, MessageStatus.queued);

        repo.conversationOverride = readOnlyConversation(relId);
        repo.emitRealtime();
        await Future<void>.delayed(const Duration(milliseconds: 400));

        expect(b.state.conversation.canSend, isFalse);
        expect(b.state.messages.single.status, MessageStatus.failed);
        final row = (await b.outbox()).single;
        expect(row.state, PendingSendState.failedPermanent);
        expect(row.lastErrorCategory, 'relationshipInactive');
      },
    );

    test(
      'a queue restored into a read-only chat is failed on open, and can be removed',
      () async {
        final repo = FakeChatRepository(currentUserId: userId);
        final cache = ChatCacheService.forTesting(backend: memBackend());
        await cache.putOutbox(
          userId,
          pendingText(
            'q',
            'from last night',
            createdAt: DateTime.now().subtract(const Duration(hours: 9)),
          ),
        );

        final b = await boot(
          repo,
          cache: cache,
          conversation: readOnlyConversation(relId),
        );
        await Future<void>.delayed(const Duration(milliseconds: 30));

        expect(repo.sendCallCount, 0);
        expect(b.state.messages.single.status, MessageStatus.failed);
        await b.controller.removeFailedMessage(b.state.messages.single);
        expect(b.state.messages, isEmpty);
        expect(await b.outbox(), isEmpty);
      },
    );
  });

  group('restart: the outbox decides (M-2)', () {
    test(
      'a cached "sending" snapshot of a message the outbox knows failed restores as failed',
      () async {
        final repo = FakeChatRepository(currentUserId: userId);
        final cache = ChatCacheService.forTesting(backend: memBackend());
        final createdAt = DateTime.now().subtract(const Duration(minutes: 3));
        final snapshot = Message.optimistic(
          id: '_local_f',
          clientMessageId: 'f',
          relationshipId: relId,
          senderId: userId,
          content: 'failed one',
          createdAt: createdAt,
        ).copyWith(status: MessageStatus.sending);
        final orphan = Message.optimistic(
          id: '_local_o',
          clientMessageId: 'o',
          relationshipId: relId,
          senderId: userId,
          content: 'orphan',
          createdAt: createdAt,
        );
        await cache.writeMessages(userId, relId, [snapshot, orphan]);
        await cache.putOutbox(
          userId,
          pendingText(
            'f',
            'failed one',
            createdAt: createdAt,
            attempts: 5,
            state: PendingSendState.failedPermanent,
          ),
        );

        final b = await boot(repo, cache: cache);

        expect(
          b.state.messages.map((m) => m.content),
          ['failed one'],
          reason: 'the orphan has no outbox row: it was sent or removed',
        );
        expect(b.state.messages.single.status, MessageStatus.failed);
      },
    );
  });

  // Task 4's purge epoch, applied to the send path: a send in flight across
  // an account change must not write the previous account's rows or queue
  // back into its just-purged cache, nor send its next queued message.
  group('purge epoch: a send in flight across an account change', () {
    test(
      'an acknowledged send writes nothing back for the previous account',
      () async {
        final repo = FakeChatRepository(currentUserId: userId);
        repo.sendDelay = const Duration(milliseconds: 80);
        final b = await boot(repo);

        final send = b.controller.sendMessage('mine');
        await Future<void>.delayed(const Duration(milliseconds: 10));
        await b.controller.debugHandleAccountChange(userId);
        await send;
        await Future<void>.delayed(const Duration(milliseconds: 30));

        expect(repo.sendCallCount, 1);
        expect(b.state.messages, isEmpty);
        expect(await b.cache.readMessages(userId, relId), isEmpty);
        expect(await b.outbox(), isEmpty);
      },
    );

    test(
      'a failed send does not re-queue the previous account\'s message',
      () async {
        final repo = FakeChatRepository(currentUserId: userId);
        repo.sendDelay = const Duration(milliseconds: 80);
        repo.nextSendError = const SocketException('offline');
        final b = await boot(repo);

        final send = b.controller.sendMessage('mine');
        await Future<void>.delayed(const Duration(milliseconds: 10));
        await b.controller.debugHandleAccountChange(userId);
        await send;
        await Future<void>.delayed(const Duration(milliseconds: 30));

        expect(b.state.messages, isEmpty);
        expect(await b.cache.readMessages(userId, relId), isEmpty);
        expect(await b.outbox(), isEmpty);
      },
    );

    test('a flush in flight stops before the next queued message', () async {
      final repo = FakeChatRepository(currentUserId: userId);
      repo.sendDelay = const Duration(milliseconds: 80);
      final cache = ChatCacheService.forTesting(backend: memBackend());
      final now = DateTime.now();
      await cache.putOutbox(
        userId,
        pendingText(
          'a',
          'A',
          createdAt: now.subtract(const Duration(seconds: 10)),
        ),
      );
      await cache.putOutbox(
        userId,
        pendingText(
          'b',
          'B',
          createdAt: now.subtract(const Duration(seconds: 5)),
        ),
      );

      final b = await boot(repo, cache: cache);
      expect(repo.sendCallCount, 1, reason: 'A is in flight');
      await b.controller.debugHandleAccountChange(userId);
      await Future<void>.delayed(const Duration(milliseconds: 250));

      expect(
        repo.sendCallCount,
        1,
        reason: 'B never goes out after the switch',
      );
      expect(b.state.messages, isEmpty);
      expect(await b.cache.readMessages(userId, relId), isEmpty);
      expect(await b.outbox(), isEmpty);
    });
  });

  // Coordinator ruling on Design 3: media preparation and upload run outside
  // the serialized flush; only the insert joins the queue, and strict FIFO
  // applies among items that are ready to insert.
  group('media uploads run outside the queue (Design 3)', () {
    late Directory tempDir;
    late String videoPath;
    late String thumbPath;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('outbox_media');
      videoPath = '${tempDir.path}/clip.mp4';
      thumbPath = '${tempDir.path}/poster.jpg';
      await File(videoPath).writeAsBytes([0, 1, 2, 3]);
      await File(thumbPath).writeAsBytes([4, 5, 6, 7]);
    });

    tearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    Future<void> sendVideo(_Booted b) => b.controller.sendVideoMessage(
      localPath: videoPath,
      durationMs: 2000,
      thumbnailLocalPath: thumbPath,
      width: 1280,
      height: 720,
    );

    test(
      'a text sent while a video upload is in progress is inserted before the upload completes',
      () async {
        final repo = FakeChatRepository(currentUserId: userId);
        final gate = Completer<void>();
        repo.uploadChatMediaGate = gate;
        final b = await boot(repo);

        final video = sendVideo(b);
        await Future<void>.delayed(const Duration(milliseconds: 10));
        await b.controller.sendMessage('hi');
        await Future<void>.delayed(const Duration(milliseconds: 10));

        expect(repo.sentContents, [
          'hi',
        ], reason: 'the text must not wait on the upload');

        gate.complete();
        await video;
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(repo.sentContents, ['hi', '']);
        expect(await b.outbox(), isEmpty);
        expect(
          b.state.messages.map((m) => m.status),
          everyElement(MessageStatus.sent),
        );
      },
    );

    test(
      'two texts queued offline behind an uploading video still go out in order when the network returns',
      () async {
        final repo = FakeChatRepository(currentUserId: userId);
        final gate = Completer<void>();
        repo.uploadChatMediaGate = gate;
        final b = await boot(repo);

        final video = sendVideo(b);
        await Future<void>.delayed(const Duration(milliseconds: 10));
        repo.sendErrorQueue.add(const SocketException('offline'));
        await b.controller.sendMessage('T1');
        await b.controller.sendMessage('T2');
        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(repo.sendCallCount, 1, reason: 'T2 waits behind T1');
        expect(repo.sentContents, isEmpty);

        await b.controller.flushOutbox(force: true); // the network is back
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(repo.sentContents, ['T1', 'T2']);

        gate.complete();
        await video;
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(repo.sentContents, ['T1', 'T2', '']);
        expect(await b.outbox(), isEmpty);
      },
    );

    test('a failed upload does not stop later texts', () async {
      final repo = FakeChatRepository(currentUserId: userId);
      // Call 2 is the video's uploadChatMedia (see mediaCallFailures).
      repo.mediaCallFailures[2] = const SocketException('upload dropped');
      final b = await boot(repo);

      await sendVideo(b);
      final videoBubble = b.state.messages.single;
      expect(videoBubble.status, MessageStatus.queued);

      await b.controller.sendMessage('after');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(repo.sentContents, ['after']);
      final row = (await b.outbox()).single;
      expect(row.clientMessageId, videoBubble.clientMessageId);
      expect(row.state, PendingSendState.queued);
      expect(row.nextAttemptAt, isNotNull);

      // The upload is retried on the next "network is back" trigger.
      await b.controller.flushOutbox(force: true);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(repo.sentContents, ['after', '']);
      expect(await b.outbox(), isEmpty);
    });

    test(
      'a rejected upload fails only the video; later texts still send',
      () async {
        final repo = FakeChatRepository(currentUserId: userId);
        repo.mediaCallFailures[2] = const StorageException(
          'mime rejected',
          statusCode: '415',
        );
        final b = await boot(repo);

        await sendVideo(b);
        expect(b.state.messages.single.status, MessageStatus.failed);

        await b.controller.sendMessage('after');
        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(repo.sentContents, ['after']);
      },
    );
  });

  group('read-only terminal state on the flush path (M-4)', () {
    test(
      'a paused relationship closes the queue on the next flush, without a send',
      () async {
        final repo = FakeChatRepository(currentUserId: userId);
        repo.sendErrorQueue.add(const SocketException('offline'));
        final b = await boot(repo);
        await b.controller.sendMessage('waiting');
        expect(b.state.messages.single.status, MessageStatus.queued);

        final paused = Conversation(
          id: relId,
          relationshipId: relId,
          partnerId: 'partner',
          name: 'Partner',
          updatedAt: DateTime.now(),
          relationshipStatus: 'paused',
          availability: ConversationAvailability.readOnly,
        );
        b.controller.debugSetConversation(paused);
        await b.controller.flushOutbox(force: true);

        expect(repo.sendCallCount, 1);
        expect(b.state.messages.single.status, MessageStatus.failed);
        final row = (await b.outbox()).single;
        expect(row.state, PendingSendState.failedPermanent);
        expect(row.lastErrorCategory, 'relationshipInactive');
      },
    );
  });

  // ---- Fix round 1 ----

  group('fix round 1', () {
    late Directory tempDir;
    late String voicePath;
    late String videoPath;
    late String thumbPath;
    late String imagePath;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('outbox_fix1');
      voicePath = '${tempDir.path}/note.m4a';
      videoPath = '${tempDir.path}/clip.mp4';
      thumbPath = '${tempDir.path}/poster.jpg';
      imagePath = '${tempDir.path}/photo.jpg';
      for (final path in [voicePath, videoPath, thumbPath, imagePath]) {
        await File(path).writeAsBytes([0, 1, 2, 3]);
      }
    });

    tearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    Future<void> sendVoice(_Booted b) => b.controller.sendVoiceMessage(
      localPath: voicePath,
      durationMs: 2000,
      waveform: const [1, 2, 3],
    );

    Future<
      ({
        _Booted b,
        ScriptedCacheBackend backend,
        StateProvider<User?> userSwitch,
      })
    >
    bootScripted(FakeChatRepository repo) async {
      final backend = ScriptedCacheBackend();
      final cache = ChatCacheService.forTesting(backend: backend);
      final userSwitch = StateProvider<User?>((ref) => testUser(userId));
      final container = buildChatContainer(
        repository: repo,
        userId: userId,
        cache: cache,
        userSwitch: userSwitch,
      );
      addTearDown(container.dispose);
      final convo = activeConversation(relId);
      repo.conversationOverride = convo;
      final controller = container.read(chatControllerProvider(convo).notifier);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      return (
        b: _Booted(controller, container, convo, cache),
        backend: backend,
        userSwitch: userSwitch,
      );
    }

    group('I1 enqueue write in flight across a sign-in to another account', () {
      Future<void> expectNothingForAnyone(
        FakeChatRepository repo,
        _Booted b,
      ) async {
        expect(repo.mediaCallCount, 0, reason: 'nothing uploaded');
        expect(repo.sendCallCount, 0, reason: 'nothing sent');
        expect(await b.cache.readOutbox('user-b'), isEmpty);
        expect(await b.cache.readOutbox(userId), isEmpty);
      }

      test(
        'a voice note is never uploaded or queued for the new account',
        () async {
          final repo = FakeChatRepository(currentUserId: userId);
          final s = await bootScripted(repo);
          final gate = Completer<void>();
          s.backend.putOutboxGate = gate;

          final send = sendVoice(s.b);
          await Future<void>.delayed(const Duration(milliseconds: 10));
          s.b.container.read(s.userSwitch.notifier).state = testUser('user-b');
          await Future<void>.delayed(const Duration(milliseconds: 20));
          s.backend.putOutboxGate = null;
          gate.complete();
          await send;
          await Future<void>.delayed(const Duration(milliseconds: 30));

          await expectNothingForAnyone(repo, s.b);
        },
      );

      test(
        'an image is never prepared or queued for the new account',
        () async {
          final repo = FakeChatRepository(currentUserId: userId);
          final s = await bootScripted(repo);
          final gate = Completer<void>();
          s.backend.putOutboxGate = gate;

          final send = s.b.controller.sendImageMessage(localPath: imagePath);
          await Future<void>.delayed(const Duration(milliseconds: 10));
          s.b.container.read(s.userSwitch.notifier).state = testUser('user-b');
          await Future<void>.delayed(const Duration(milliseconds: 20));
          s.backend.putOutboxGate = null;
          gate.complete();
          await send;
          await Future<void>.delayed(const Duration(milliseconds: 30));

          await expectNothingForAnyone(repo, s.b);
        },
      );
    });

    group('I2 server rejections count toward the cap', () {
      test(
        'a reply the server rejects with a trigger RAISE (P0001) fails after five attempts',
        () async {
          final repo = FakeChatRepository(currentUserId: userId);
          for (var i = 0; i < 5; i++) {
            repo.sendErrorQueue.add(
              const PostgrestException(
                message: 'Reply target message does not exist',
                code: 'P0001',
              ),
            );
          }
          final b = await boot(repo);

          await b.controller.sendMessage(
            'replying',
            replyToMessageId: 'gone-1',
            quotedText: 'gone',
          );
          for (var i = 0; i < 4; i++) {
            await b.controller.flushOutbox(force: true);
          }
          await Future<void>.delayed(const Duration(milliseconds: 20));

          expect(repo.sendCallCount, 5);
          expect(b.state.messages.single.status, MessageStatus.failed);
          expect(
            (await b.outbox()).single.state,
            PendingSendState.failedPermanent,
          );
        },
      );

      test('a 503 keeps the message queued past the cap', () async {
        final repo = FakeChatRepository(currentUserId: userId);
        for (var i = 0; i < 7; i++) {
          repo.sendErrorQueue.add(
            const PostgrestException(
              message: 'Service Unavailable',
              code: '503',
            ),
          );
        }
        final b = await boot(repo);

        await b.controller.sendMessage('later');
        for (var i = 0; i < 6; i++) {
          await b.controller.flushOutbox(force: true);
        }
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(repo.sendCallCount, 7);
        expect(b.state.messages.single.status, MessageStatus.queued);
        expect((await b.outbox()).single.state, PendingSendState.queued);
      });
    });

    test(
      'I3 an upload that lands while the head text is being sent is not run again from the stale snapshot',
      () async {
        final repo = FakeChatRepository(currentUserId: userId);
        repo.sendErrorQueue.add(const SocketException('offline'));
        final b = await boot(repo);
        await b.controller.sendMessage('T'); // queued, ahead of the video

        final gate = Completer<void>();
        repo.uploadChatMediaGate = gate;
        final video = b.controller.sendVideoMessage(
          localPath: videoPath,
          durationMs: 2000,
          thumbnailLocalPath: thumbPath,
          width: 1280,
          height: 720,
        );
        await Future<void>.delayed(const Duration(milliseconds: 10));

        repo.sendDelay = const Duration(milliseconds: 100);
        final flush = b.controller.flushOutbox(force: true); // snapshot [T, V]
        await Future<void>.delayed(const Duration(milliseconds: 20));
        gate.complete(); // V's upload lands while T is in flight
        await flush;
        await video;
        await Future<void>.delayed(const Duration(milliseconds: 300));

        expect(
          repo.mediaCallCount,
          4,
          reason: 'one intent + upload for the file, one for the poster',
        );
        expect(repo.sentContents, ['T', '']);
        expect(await b.outbox(), isEmpty);
      },
    );

    group('M1 an unwritable outbox is honest', () {
      test('a text still sends directly', () async {
        final repo = FakeChatRepository(currentUserId: userId);
        final s = await bootScripted(repo);
        s.backend.failPutOutbox = (_, _) => true;

        await s.b.controller.sendMessage('no disk');
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(repo.sentContents, ['no disk']);
        expect(s.b.state.messages.single.status, MessageStatus.sent);
      });

      test('a failed direct send turns failed, and Retry sends it', () async {
        final repo = FakeChatRepository(currentUserId: userId);
        repo.sendErrorQueue.add(const SocketException('offline'));
        final s = await bootScripted(repo);
        s.backend.failPutOutbox = (_, _) => true;

        await s.b.controller.sendMessage('no disk');
        await Future<void>.delayed(const Duration(milliseconds: 20));
        final bubble = s.b.state.messages.single;
        expect(
          bubble.status,
          MessageStatus.failed,
          reason: 'no queue row backs it, so a clock would never resolve',
        );

        await s.b.controller.retryMessage(bubble);
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(repo.sentContents, ['no disk']);
        expect(s.b.state.messages.single.status, MessageStatus.sent);
      });
    });

    group('M2 a failed queue read still arms a retry', () {
      test('when the flush cannot read the queue', () async {
        final repo = FakeChatRepository(currentUserId: userId);
        final s = await bootScripted(repo);
        await s.b.cache.putOutbox(
          userId,
          pendingText('q', 'Q', createdAt: DateTime.now()),
        );
        expect(s.b.controller.debugRetryDeadline, isNull);

        s.backend.armReadOutboxFailures((_) => true);
        await s.b.controller.flushOutbox();

        expect(s.b.controller.debugRetryDeadline, isNotNull);
      });

      test('when only the post-pass settle cannot read the queue', () async {
        final repo = FakeChatRepository(currentUserId: userId);
        final s = await bootScripted(repo);
        await s.b.cache.putOutbox(
          userId,
          pendingText(
            'q',
            'Q',
            createdAt: DateTime.now(),
            attempts: 3,
            nextAttemptAt: DateTime.now().add(const Duration(hours: 1)),
          ),
        );
        expect(s.b.controller.debugRetryDeadline, isNull);

        // Read 1 is the pass (head not due: break); read 2 is the settle.
        s.backend.armReadOutboxFailures((call) => call == 2);
        await s.b.controller.flushOutbox();

        expect(s.b.controller.debugRetryDeadline, isNotNull);
      });
    });

    test(
      'M3 a failure after the upload landed keeps its storage key (no re-upload)',
      () async {
        final repo = FakeChatRepository(currentUserId: userId);
        final s = await bootScripted(repo);
        // Puts per row: 1 enqueue, 2 "sending", 3 the uploaded key, 4 "ready".
        s.backend.failPutOutbox = (_, ordinal) => ordinal == 4;

        await sendVoice(s.b);
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(repo.mediaCallCount, 2);
        expect(repo.sendCallCount, 0);
        expect((await s.b.outbox()).single.uploadedMediaKey, isNotNull);

        await s.b.controller.flushOutbox(force: true);
        await Future<void>.delayed(const Duration(milliseconds: 30));
        expect(
          repo.mediaCallCount,
          2,
          reason: 'the file is not uploaded twice',
        );
        expect(repo.sendCallCount, 1);
        expect(await s.b.outbox(), isEmpty);
      },
    );

    test(
      'M4 at open, an outbox row whose message is already canonical in the cache is dropped, even a failed one',
      () async {
        final repo = FakeChatRepository(currentUserId: userId);
        final canonical = repo.seedIncoming(
          id: 'srv-9',
          relationshipId: relId,
          senderId: userId,
          content: 'it landed',
          createdAt: DateTime.now().subtract(const Duration(minutes: 2)),
        );
        final cache = ChatCacheService.forTesting(backend: memBackend());
        await cache.writeMessages(userId, relId, [canonical]);
        await cache.putOutbox(
          userId,
          pendingText(
            canonical.clientMessageId,
            'it landed',
            createdAt: canonical.createdAt,
            attempts: 5,
            state: PendingSendState.failedPermanent,
          ),
        );

        final b = await boot(repo, cache: cache);
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(b.state.messages.single.id, 'srv-9');
        expect(await b.outbox(), isEmpty);
        expect(repo.sendCallCount, 0);
      },
    );
  });

  test(
    'fix round 3: a P0001 from a page read shows load copy, not send copy',
    () async {
      final repo = FakeChatRepository(currentUserId: userId);
      repo.getMessagesError = const PostgrestException(
        message: 'boom',
        code: 'P0001',
      );
      final b = await boot(repo);
      // A visible (non-silent) page read, as the banner's retry runs it.
      await b.controller.loadMessages();

      expect(b.state.error, isNotNull);
      expect(b.state.error, isNot('Message not sent. Tap to retry.'));
      expect(b.state.error, contains('load'));
    },
  );

  group('fix round 4', () {
    late Directory tempDir;
    late String imagePath;
    late String videoPath;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('outbox_fix4');
      imagePath = '${tempDir.path}/photo.jpg';
      videoPath = '${tempDir.path}/raw.mov';
      await File(imagePath).writeAsBytes([0, 1, 2, 3]);
      await File(videoPath).writeAsBytes([0, 1, 2, 3]);
    });

    tearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    Future<({_Booted b, ScriptedCacheBackend backend})> bootScripted(
      FakeChatRepository repo,
    ) async {
      final backend = ScriptedCacheBackend();
      final b = await boot(
        repo,
        cache: ChatCacheService.forTesting(backend: backend),
      );
      return (b: b, backend: backend);
    }

    test(
      '1: a failed streak row whose message is canonical in the cache is dropped at open',
      () async {
        final repo = FakeChatRepository(currentUserId: userId);
        final canonical = repo.seedIncoming(
          id: 'srv-s',
          relationshipId: relId,
          senderId: userId,
          content: '',
          mediaType: 'streak',
          createdAt: DateTime.now().subtract(const Duration(minutes: 2)),
        );
        final cache = ChatCacheService.forTesting(backend: memBackend());
        await cache.writeMessages(userId, relId, [canonical]);
        await cache.putOutbox(
          userId,
          PendingSend(
            clientMessageId: canonical.clientMessageId,
            relationshipId: relId,
            senderId: userId,
            text: '',
            mediaType: 'streak',
            createdAt: canonical.createdAt,
            attempts: 5,
            state: PendingSendState.failedPermanent,
          ),
        );

        final b = await boot(repo, cache: cache);
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(await b.outbox(), isEmpty);
        expect(b.state.messages.single.id, 'srv-s');
      },
    );

    test(
      '3: a 42501 on a direct (no-outbox) send against a now read-only chat says read-only',
      () async {
        final repo = FakeChatRepository(currentUserId: userId);
        repo.sendDelay = const Duration(milliseconds: 80);
        repo.nextSendError = const PostgrestException(
          message: 'new row violates row-level security policy',
          code: '42501',
        );
        final s = await bootScripted(repo);
        s.backend.failPutOutbox = (_, _) => true;

        final send = s.b.controller.sendMessage('racing the pause');
        await Future<void>.delayed(const Duration(milliseconds: 10));
        s.b.controller.debugSetConversation(readOnlyConversation(relId));
        await send;

        expect(s.b.state.messages.single.status, MessageStatus.failed);
        expect(s.b.state.error, 'This relationship chat is read-only.');
      },
    );

    test(
      '4: Retry on a dead cache (outbox unreadable) still resends the unsaved message',
      () async {
        final repo = FakeChatRepository(currentUserId: userId);
        repo.sendErrorQueue.add(const SocketException('offline'));
        final s = await bootScripted(repo);
        s.backend.failPutOutbox = (_, _) => true;
        await s.b.controller.sendMessage('no disk');
        await Future<void>.delayed(const Duration(milliseconds: 20));
        final bubble = s.b.state.messages.single;
        expect(bubble.status, MessageStatus.failed);

        s.backend.armReadOutboxFailures((_) => true);
        await s.b.controller.retryMessage(bubble);
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(repo.sentContents, ['no disk']);
        expect(s.b.state.messages.single.status, MessageStatus.sent);
      },
    );

    test(
      '5: an image on a dead cache is failed and retryable, never stuck at sending',
      () async {
        final repo = FakeChatRepository(currentUserId: userId);
        final s = await bootScripted(repo);
        s.backend.failPutOutbox = (_, _) => true;

        await s.b.controller.sendImageMessage(localPath: imagePath);
        await Future<void>.delayed(const Duration(milliseconds: 20));
        final bubble = s.b.state.messages.single;
        expect(bubble.status, MessageStatus.failed);
        expect(
          repo.sendCallCount,
          0,
          reason: 'never an image row without its image',
        );

        // The cache recovers: Retry puts it back into the queue.
        s.backend.failPutOutbox = null;
        await s.b.controller.retryMessage(bubble);
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect((await s.b.outbox()).map((p) => p.clientMessageId), [
          bubble.clientMessageId,
        ]);
      },
    );

    test(
      '5: a trimmed video on a dead cache is failed and retryable, not left compressing',
      () async {
        final repo = FakeChatRepository(currentUserId: userId);
        final s = await bootScripted(repo);
        s.backend.failPutOutbox = (_, _) => true;

        await s.b.controller.sendVideoMessageFromTrim(
          localPath: videoPath,
          trimStart: Duration.zero,
          trimEnd: const Duration(seconds: 3),
        );
        await Future<void>.delayed(const Duration(milliseconds: 20));

        final bubble = s.b.state.messages.single;
        expect(bubble.status, MessageStatus.failed);
        expect(bubble.isPreparing, isFalse);
        expect(repo.sendCallCount, 0);
      },
    );
  });
}

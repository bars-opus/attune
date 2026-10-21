import 'dart:async';
import 'dart:io';

import 'package:attune/features/chat/data/cache/chat_cache_service.dart';
import 'package:attune/features/chat/data/cache/pending_send.dart';
import 'package:attune/features/chat/data/repositories/chat_media_uploader.dart';
import 'package:attune/features/chat/data/repositories/chat_repository.dart';
import 'package:attune/features/chat/domain/entities/conversation.dart';
import 'package:attune/features/chat/domain/entities/message.dart';
import 'package:attune/features/chat/presentation/state/chat_outbox_drainer.dart';
import 'package:attune/features/chat/presentation/state/chat_state.dart';
import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'support/chat_test_harness.dart';

/// Takes the body, never answers; closing it is the only way out.
class _HangingClient extends http.BaseClient {
  final _answer = Completer<http.StreamedResponse>();
  bool closed = false;
  bool bodyStarted = false;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    bodyStarted = true;
    unawaited(request.finalize().drain<void>());
    return _answer.future;
  }

  @override
  void close() {
    closed = true;
    if (!_answer.isCompleted) {
      _answer.completeError(http.ClientException('Connection closed'));
    }
  }
}

/// The fake repository with the REAL streaming uploader behind its upload,
/// over a socket that never answers: what a purge does to an in-flight
/// upload is then visible on the client itself.
class _StreamingRepository extends FakeChatRepository {
  _StreamingRepository() : super(currentUserId: 'user-a');
  final client = _HangingClient();

  @override
  Future<void> uploadChatMedia({
    required ChatMediaUploadIntent intent,
    required String localPath,
    required String mimeType,
    void Function(double fraction)? onProgress,
    ChatUploadCancelToken? cancelToken,
  }) {
    return ChatMediaUploader(
      storageUrl: () => 'https://x.supabase.co/storage/v1',
      headers: () async => const {'apikey': 'anon'},
      clientFactory: () => client,
    ).upload(
      bucket: intent.bucket,
      objectKey: intent.storageKey,
      localPath: localPath,
      mimeType: mimeType,
      cancelToken: cancelToken,
      onProgress:
          onProgress == null ? null : (sent, total) => onProgress(sent / total),
    );
  }
}

class _FakePathProviderPlatform extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProviderPlatform(this.tempDir);
  final Directory tempDir;
  @override
  Future<String?> getTemporaryPath() async => tempDir.path;
}

void main() {
  // The outbox drainer listens to app lifecycle, which needs a binding.
  TestWidgetsFlutterBinding.ensureInitialized();

  const userId = 'user-a';
  const relId = 'rel-1';
  late Directory tempDir;
  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('upload_cancel');
    PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir);
    ConversationsNotifier.debugServedCache = true;
  });
  tearDown(() => tempDir.delete(recursive: true));

  Future<(ChatController, ChatState Function())> boot(
    FakeChatRepository repo, {
    ChatCacheService? cache,
  }) async {
    final container = buildChatContainer(
      repository: repo,
      userId: userId,
      cache: cache,
    );
    addTearDown(container.dispose);
    final convo = activeConversation(relId);
    repo.conversationOverride = convo;
    final controller = container.read(chatControllerProvider(convo).notifier);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    return (controller, () => container.read(chatControllerProvider(convo)));
  }

  Future<String> voiceFile(String name) async {
    final path = p.join(tempDir.path, name);
    await File(path).writeAsBytes(List.filled(256, 1));
    return path;
  }

  test('upload progress reaches the optimistic bubble', () async {
    final repo = FakeChatRepository(currentUserId: userId)
      ..uploadProgressScript = const [0.25, 0.5, 1.0]
      ..uploadGate = Completer<void>();
    final (controller, state) = await boot(repo);

    final send = controller.sendVoiceMessage(
        localPath: await voiceFile('a.m4a'), durationMs: 1000, waveform: const [1]);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(state().messages.single.uploadProgress, 1.0);
    expect(state().messages.single.status, MessageStatus.sending);

    repo.uploadGate!.complete();
    await send;
    expect(state().messages.single.status, MessageStatus.sent);
  });

  test('cancel mid-upload fails the row quietly; no auto-retry; retry works',
      () async {
    final repo = FakeChatRepository(currentUserId: userId)
      ..uploadGate = Completer<void>();
    final (controller, state) = await boot(repo);

    final send = controller.sendVoiceMessage(
        localPath: await voiceFile('c.m4a'), durationMs: 1000, waveform: const [1]);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(state().messages.single.status, MessageStatus.sending);

    controller.cancelSend(state().messages.single);
    expect(repo.lastUploadCancelToken!.isCancelled, isTrue);
    repo.uploadGate!.complete();
    await send;

    final failed = state().messages.single;
    expect(failed.status, MessageStatus.failed);
    expect(state().error, isNull, reason: 'the person asked for this; no banner');
    expect(repo.sendCallCount, 0);

    // The row is parked (failedPermanent), not retried by the next flush.
    await controller.flushOutbox();
    expect(repo.sendCallCount, 0);

    repo.uploadGate = null;
    await controller.retryMessage(failed);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(state().messages.single.status, MessageStatus.sent);
    expect(repo.sendCallCount, 1);
  });

  test('cancel after the bytes are up is a no-op: the message still lands',
      () async {
    // M6: gated, not timed — the insert is held open until the cancel has
    // been tapped, so no sleep races the machine's load.
    final insertAnswer = Completer<void>();
    final repo = FakeChatRepository(currentUserId: userId)
      ..sendResponseGates.add(insertAnswer);
    final (controller, state) = await boot(repo);

    final send = controller.sendVoiceMessage(
        localPath: await voiceFile('d.m4a'), durationMs: 1000, waveform: const [1]);
    // Upload finished instantly (fake); wait until the row insert is open.
    for (var i = 0; i < 400 && repo.sendCallCount == 0; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(repo.sendCallCount, 1, reason: 'the insert is under way');
    final seen = <MessageStatus>[];
    final stopListening = controller.addListener(
        (s) => seen.addAll(s.messages.map((m) => m.status)),
        fireImmediately: false);
    addTearDown(stopListening);
    controller.cancelSend(state().messages.single);
    insertAnswer.complete();
    await send;
    for (var i = 0;
        i < 400 && state().messages.single.status != MessageStatus.sent;
        i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(state().messages.single.status, MessageStatus.sent);
    expect(repo.sendCallCount, 1, reason: 'landed once, not cancelled');
    expect(seen, isNot(contains(MessageStatus.failed)),
        reason: 'the late tap never parks the send, even for a frame');
    expect(state().error, isNull);
  });

  test('retry resets the ring to the start', () async {
    final repo = FakeChatRepository(currentUserId: userId)
      ..uploadProgressScript = const [0.7]
      ..mediaCallFailures[2] = Exception('boom');
    final (controller, state) = await boot(repo);
    await controller.sendVoiceMessage(
        localPath: await voiceFile('e.m4a'), durationMs: 1000, waveform: const [1]);
    final queued = state().messages.single;
    expect(queued.status, MessageStatus.queued);
    repo.uploadProgressScript = const [];
    await controller.retryMessage(queued);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(state().messages.single.status, MessageStatus.sent);
  });

  test('a new attempt starts its ring at zero, not where the last one stopped',
      () async {
    final repo = FakeChatRepository(currentUserId: userId)
      ..uploadProgressScript = const [0.7]
      ..mediaCallFailures[2] = const SocketException('offline');
    final (controller, state) = await boot(repo);
    await controller.sendVoiceMessage(
        localPath: await voiceFile('r.m4a'), durationMs: 1000, waveform: const [1]);
    expect(state().messages.single.status, MessageStatus.queued);

    expect(state().messages.single.uploadProgress, isNull,
        reason: 'the failed attempt ended; its ring is gone');

    // The automatic retry (the flush, not the Retry button) restarts the
    // upload from byte 0; the ring must say so.
    repo
      ..uploadProgressScript = const []
      ..uploadGate = Completer<void>();
    await controller.flushOutbox(force: true);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(repo.mediaCallCount, 4, reason: 'the second attempt is uploading');
    expect(state().messages.single.uploadProgress, 0);
    repo.uploadGate!.complete();
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(state().messages.single.status, MessageStatus.sent);
  });

  test('_publishUploadProgress coalesces sub-2% steps', () async {
    final repo = FakeChatRepository(currentUserId: userId);
    final (controller, state) = await boot(repo);
    final seen = <double>[];
    for (var i = 1; i <= 100; i++) {
      final v = i / 100;
      if (controller.debugShouldPublishUploadProgress('cid', v)) seen.add(v);
    }
    expect(seen.length, lessThanOrEqualTo(51));
    expect(seen.last, 1.0);
  });

  group('a cancelled send stays cancelled', () {
    Future<(ChatController, ChatState Function(), ChatCacheService)>
        cancelOne(FakeChatRepository repo, String file) async {
      final cache = ChatCacheService.forTesting(backend: memBackend());
      final (controller, state) = await boot(repo, cache: cache);
      final send = controller.sendVoiceMessage(
          localPath: await voiceFile(file), durationMs: 1000, waveform: const [1]);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      controller.cancelSend(state().messages.single);
      repo.uploadGate!.complete();
      await send;
      return (controller, state, cache);
    }

    test('the outbox row is parked as cancelled, never left to resume',
        () async {
      final repo = FakeChatRepository(currentUserId: userId)
        ..uploadGate = Completer<void>();
      final (_, state, cache) = await cancelOne(repo, 'p1.m4a');

      final rows = await cache.readOutbox(userId, relationshipId: relId);
      expect(rows, hasLength(1));
      expect(rows.single.state, PendingSendState.failedPermanent);
      expect(rows.single.lastErrorCategory, 'cancelled');
      expect(rows.single.uploadedMediaKey, isNull,
          reason: 'the abandoned intent is not kept; a retry asks for a new one');
      expect(rows.single.attempts, 0, reason: 'a cancel is not a failure');
      expect(state().messages.single.status, MessageStatus.failed);
    });

    test('a restart restores it failed and uploads nothing', () async {
      final repo = FakeChatRepository(currentUserId: userId)
        ..uploadGate = Completer<void>();
      final (_, _, cache) = await cancelOne(repo, 'p2.m4a');
      final callsAfterCancel = repo.mediaCallCount;

      final restarted = FakeChatRepository(currentUserId: userId);
      final (_, state) = await boot(restarted, cache: cache);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(state().messages.single.status, MessageStatus.failed);
      expect(restarted.mediaCallCount, 0);
      expect(restarted.sendCallCount, 0);
      expect(repo.mediaCallCount, callsAfterCancel);
    });

    test('the outbox drainer does not resume it', () async {
      final repo = FakeChatRepository(currentUserId: userId)
        ..uploadGate = Completer<void>();
      final (_, _, cache) = await cancelOne(repo, 'p3.m4a');

      final drainRepo = FakeChatRepository(currentUserId: userId)
        ..conversations = [activeConversation(relId)];
      final container = buildChatContainer(
        repository: drainRepo,
        userId: userId,
        cache: cache,
      );
      addTearDown(container.dispose);
      await container.read(chatOutboxDrainerProvider).drain();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(drainRepo.mediaCallCount, 0);
      expect(drainRepo.sendCallCount, 0);
    });

    test('a cancel settling after a purge writes nothing back', () async {
      final repo = FakeChatRepository(currentUserId: userId)
        ..uploadGate = Completer<void>();
      final cache = ChatCacheService.forTesting(backend: memBackend());
      final (controller, state) = await boot(repo, cache: cache);
      final send = controller.sendVoiceMessage(
          localPath: await voiceFile('p4.m4a'), durationMs: 1000, waveform: const [1]);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      final bubble = state().messages.single;

      await controller.debugHandleAccountChange(userId);
      controller.cancelSend(bubble);
      repo.uploadGate!.complete();
      await send;
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(await cache.readOutbox(userId, relationshipId: relId), isEmpty);
      expect(state().messages, isEmpty);
    });

    test('cancelling a message that is already sent changes nothing',
        () async {
      final repo = FakeChatRepository(currentUserId: userId);
      final (controller, state) = await boot(repo);
      await controller.sendVoiceMessage(
          localPath: await voiceFile('s.m4a'), durationMs: 1000, waveform: const [1]);
      final sent = state().messages.single;
      expect(sent.status, MessageStatus.sent);

      controller.cancelSend(sent);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(state().messages.single.status, MessageStatus.sent);
      expect(state().messages.single.id, sent.id);
    });
  });

  test('a cancel on a send with no outbox row (dead cache) fails it quietly',
      () async {
    final backend = ScriptedCacheBackend()
      ..failPutOutbox = (id, ordinal) => true;
    final repo = FakeChatRepository(currentUserId: userId)
      ..uploadGate = Completer<void>();
    final (controller, state) =
        await boot(repo, cache: ChatCacheService.forTesting(backend: backend));

    final send = controller.sendVoiceMessage(
        localPath: await voiceFile('u.m4a'), durationMs: 1000, waveform: const [1]);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    controller.cancelSend(state().messages.single);
    repo.uploadGate!.complete();
    await send;

    expect(state().messages.single.status, MessageStatus.failed);
    expect(state().error, isNull);
    expect(repo.sendCallCount, 0);

    repo.uploadGate = null;
    await controller.retryMessage(state().messages.single);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(state().messages.single.status, MessageStatus.sent);
  });

  group('a stalled upload (timeout) stays retryable', () {
    test('a timeout queues the row on its backoff, never failedPermanent',
        () async {
      final cache = ChatCacheService.forTesting(backend: memBackend());
      final repo = FakeChatRepository(currentUserId: userId)
        ..mediaCallFailures[2] = TimeoutException('upload stalled (body)');
      final (controller, state) = await boot(repo, cache: cache);
      await controller.sendVoiceMessage(
          localPath: await voiceFile('t.m4a'), durationMs: 1000, waveform: const [1]);

      expect(state().messages.single.status, MessageStatus.queued);
      final row = (await cache.readOutbox(userId, relationshipId: relId)).single;
      expect(row.state, PendingSendState.queued);
      expect(row.lastErrorCategory, 'offline');
      expect(row.nextAttemptAt, isNotNull);
    });

    test('timeouts never use up the attempt cap', () async {
      final cache = ChatCacheService.forTesting(backend: memBackend());
      final repo = FakeChatRepository(currentUserId: userId);
      final (controller, state) = await boot(repo, cache: cache);
      final path = await voiceFile('t2.m4a');
      // Already well past the cap of 5 counted attempts.
      await cache.putOutbox(
        userId,
        PendingSend(
          clientMessageId: 'stalled',
          relationshipId: relId,
          senderId: userId,
          text: '',
          localMediaPath: path,
          mediaMimeType: 'audio/mp4',
          mediaType: 'audio',
          mediaDurationMs: 1000,
          waveform: const [1],
          createdAt: DateTime.now(),
          attempts: 12,
        ),
      );
      repo.mediaCallFailures[2] = TimeoutException('upload stalled (response)');
      await controller.flushOutbox(force: true);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final row = (await cache.readOutbox(userId, relationshipId: relId)).single;
      expect(row.state, PendingSendState.queued);
      expect(row.attempts, 13);
      expect(state().error, isNotNull, reason: 'offline copy, not a failure');
    });
  });

  group('fix round 1', () {
    test('an automatic retry shows the ring and cancel; cancelling it '
        'works and persists', () async {
      final cache = ChatCacheService.forTesting(backend: memBackend());
      final repo = FakeChatRepository(currentUserId: userId)
        ..mediaCallFailures[2] = TimeoutException('upload stalled (body)');
      final (controller, state) = await boot(repo, cache: cache);
      await controller.sendVoiceMessage(
          localPath: await voiceFile('auto.m4a'), durationMs: 1000, waveform: const [1]);
      expect(state().messages.single.status, MessageStatus.queued,
          reason: 'waiting on its backoff: the clock');

      // The retry timer / reconnect / drainer path: a flush, not Retry.
      repo.uploadGate = Completer<void>();
      await controller.flushOutbox(force: true);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      final uploading = state().messages.single;
      expect(uploading.status, MessageStatus.sending,
          reason: 'bytes are moving: no clock while uploading');
      expect(uploading.uploadProgress, 0,
          reason: 'a non-null progress below 1 is what draws ring and cancel');

      controller.cancelSend(uploading);
      expect(repo.lastUploadCancelToken!.isCancelled, isTrue);
      repo.uploadGate!.complete();
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(state().messages.single.status, MessageStatus.failed);
      expect(state().messages.single.uploadProgress, isNull);
      final row = (await cache.readOutbox(userId, relationshipId: relId)).single;
      expect(row.state, PendingSendState.failedPermanent);
      expect(row.lastErrorCategory, 'cancelled');
    });

    test('progress is null once each attempt ends', () async {
      // Success: the bytes are up, the insert is still in flight.
      final ok = FakeChatRepository(currentUserId: userId)
        ..uploadProgressScript = const [0.5]
        ..sendDelay = const Duration(milliseconds: 80);
      final (okController, okState) = await boot(ok);
      final send = okController.sendVoiceMessage(
          localPath: await voiceFile('ok.m4a'), durationMs: 1000, waveform: const [1]);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(okState().messages.single.status, MessageStatus.sending);
      expect(okState().messages.single.uploadProgress, isNull);
      await send;

      // A network failure, a stall, any other failure: back to the clock.
      for (final failure in <Object>[
        const SocketException('offline'),
        TimeoutException('stalled'),
        Exception('boom'),
      ]) {
        final repo = FakeChatRepository(currentUserId: userId)
          ..uploadProgressScript = const [0.4]
          ..mediaCallFailures[2] = failure;
        final (controller, state) = await boot(repo);
        await controller.sendVoiceMessage(
            localPath: await voiceFile('f${failure.hashCode}.m4a'),
            durationMs: 1000,
            waveform: const [1]);
        expect(state().messages.single.status, MessageStatus.queued);
        expect(state().messages.single.uploadProgress, isNull,
            reason: '$failure');
      }

      // A cancel.
      final cancelled = FakeChatRepository(currentUserId: userId)
        ..uploadProgressScript = const [0.3]
        ..uploadGate = Completer<void>();
      final (cController, cState) = await boot(cancelled);
      final cSend = cController.sendVoiceMessage(
          localPath: await voiceFile('cx.m4a'), durationMs: 1000, waveform: const [1]);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(cState().messages.single.uploadProgress, 0.3);
      cController.cancelSend(cState().messages.single);
      cancelled.uploadGate!.complete();
      await cSend;
      expect(cState().messages.single.status, MessageStatus.failed);
      expect(cState().messages.single.uploadProgress, isNull);
    });

    test('Retry of a row whose bytes are already up offers no cancel',
        () async {
      final cache = ChatCacheService.forTesting(backend: memBackend());
      await cache.putOutbox(
        userId,
        PendingSend(
          clientMessageId: 'uploaded',
          relationshipId: relId,
          senderId: userId,
          text: '',
          localMediaPath: await voiceFile('up.m4a'),
          mediaMimeType: 'audio/mp4',
          mediaType: 'audio',
          mediaDurationMs: 1000,
          waveform: const [1],
          uploadedMediaKey: 'chat-media/already-up.m4a',
          createdAt: DateTime.now(),
          state: PendingSendState.failedPermanent,
          lastErrorCategory: 'unknown',
        ),
      );
      final repo = FakeChatRepository(currentUserId: userId)
        ..sendDelay = const Duration(milliseconds: 80);
      final (controller, state) = await boot(repo, cache: cache);
      expect(state().messages.single.status, MessageStatus.failed);

      final retry = controller.retryMessage(state().messages.single);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(state().messages.single.status, MessageStatus.sending);
      expect(state().messages.single.uploadProgress, isNull,
          reason: 'no upload, no token: a cancel button would do nothing');
      await retry;
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(repo.mediaCallCount, 0);
      expect(state().messages.single.status, MessageStatus.sent);
    });

    test('a cancel during the intent request settles at once', () async {
      final cache = ChatCacheService.forTesting(backend: memBackend());
      final repo = FakeChatRepository(currentUserId: userId)
        ..intentGate = Completer<void>();
      final (controller, state) = await boot(repo, cache: cache);
      final send = controller.sendVoiceMessage(
          localPath: await voiceFile('slot.m4a'), durationMs: 1000, waveform: const [1]);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(repo.mediaCallCount, 1, reason: 'the intent request is pending');

      controller.cancelSend(state().messages.single);
      // The RPC never answers; the cancel must not wait for it.
      await send.timeout(const Duration(seconds: 1));
      expect(state().messages.single.status, MessageStatus.failed);
      final row = (await cache.readOutbox(userId, relationshipId: relId)).single;
      expect(row.state, PendingSendState.failedPermanent);
      expect(row.lastErrorCategory, 'cancelled');

      repo.intentGate!.complete();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(repo.mediaCallCount, 1, reason: 'no upload after the cancel');
      expect(state().messages.single.status, MessageStatus.failed);
    });

    group('a purge stops the bytes', () {
      Future<(ChatController, _StreamingRepository)> uploading() async {
        final repo = _StreamingRepository();
        final (controller, _) = await boot(repo);
        unawaited(controller.sendVoiceMessage(
            localPath: await voiceFile('purge.m4a'),
            durationMs: 1000,
            waveform: const [1]));
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(repo.client.bodyStarted, isTrue);
        expect(repo.client.closed, isFalse);
        return (controller, repo);
      }

      test('an account change closes the uploader\'s client', () async {
        final (controller, repo) = await uploading();
        await controller.debugHandleAccountChange(userId);
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(repo.client.closed, isTrue);
      });

      test('a relationship purge closes the uploader\'s client', () async {
        final (controller, repo) = await uploading();
        repo.conversationOverride = activeConversation(
          relId,
        ).copyWith(availability: ConversationAvailability.archived);
        await controller.debugRefreshConversation();
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(repo.client.closed, isTrue);
      });
    });

    group('nothing re-enters the unsaved sends after a purge', () {
      test('a cancel on the no-outbox path', () async {
        final backend = ScriptedCacheBackend()
          ..failPutOutbox = (id, ordinal) => true;
        final repo = FakeChatRepository(currentUserId: userId)
          ..uploadGate = Completer<void>();
        final (controller, state) = await boot(
          repo,
          cache: ChatCacheService.forTesting(backend: backend),
        );
        final send = controller.sendVoiceMessage(
            localPath: await voiceFile('np.m4a'), durationMs: 1000, waveform: const [1]);
        await Future<void>.delayed(const Duration(milliseconds: 30));
        final bubble = state().messages.single;
        expect(controller.debugHasUnsavedSend(bubble.clientMessageId), isTrue);

        await controller.debugHandleAccountChange(userId);
        controller.cancelSend(bubble);
        repo.uploadGate!.complete();
        await send;

        expect(controller.debugHasUnsavedSend(bubble.clientMessageId), isFalse);
      });

      test('the cancel fallback when the outbox cannot be written', () async {
        final backend = ScriptedCacheBackend();
        final repo = FakeChatRepository(currentUserId: userId)
          ..uploadGate = Completer<void>();
        final (controller, state) = await boot(
          repo,
          cache: ChatCacheService.forTesting(backend: backend),
        );
        // Put 1 enqueues, put 2 marks the upload sending, put 3 parks the
        // cancel: a purge lands as that write fails.
        backend.failPutOutbox = (id, ordinal) {
          if (ordinal != 3) return false;
          unawaited(controller.debugHandleAccountChange(userId));
          return true;
        };
        final send = controller.sendVoiceMessage(
            localPath: await voiceFile('fb.m4a'), durationMs: 1000, waveform: const [1]);
        await Future<void>.delayed(const Duration(milliseconds: 30));
        final bubble = state().messages.single;
        controller.cancelSend(bubble);
        repo.uploadGate!.complete();
        await send;
        await Future<void>.delayed(const Duration(milliseconds: 30));

        expect(controller.debugHasUnsavedSend(bubble.clientMessageId), isFalse);
      });
    });

    test('progress publishes at most once per 100 ms; the final value always',
        () async {
      final repo = FakeChatRepository(currentUserId: userId);
      final (controller, _) = await boot(repo);
      final start = DateTime(2026, 10, 20, 12);
      var now = start;
      final published = <double>[];
      withClock(Clock(() => now), () {
        void tick(int ms, double fraction) {
          now = start.add(Duration(milliseconds: ms));
          if (controller.debugShouldPublishUploadProgress('cid', fraction)) {
            published.add(fraction);
          }
        }

        tick(0, 0.10);
        tick(50, 0.20);
        tick(99, 0.30);
        tick(100, 0.40);
        tick(150, 0.60);
        tick(160, 1.0);
      });
      expect(published, [0.10, 0.40, 1.0]);
    });
  });
}

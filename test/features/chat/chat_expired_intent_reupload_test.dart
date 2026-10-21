import 'dart:async';
import 'dart:io';

import 'package:attune/features/chat/data/cache/chat_cache_service.dart';
import 'package:attune/features/chat/config/chat_config.dart';
import 'package:attune/features/chat/data/cache/pending_send.dart';
import 'package:attune/features/chat/data/repositories/streak_repository.dart';
import 'package:attune/features/chat/domain/entities/message.dart';
import 'package:attune/features/chat/presentation/state/chat_state.dart';
import 'package:attune/features/chat/utils/chat_error.dart';
import 'package:flutter/foundation.dart' show DebugPrintCallback, debugPrint;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import 'support/chat_test_harness.dart';

class _RecordingStreakRepository extends StreakRepository {
  final List<String> attachedKeys = [];

  @override
  Future<void> attachClip({
    required String messageId,
    required String mediaUrl,
    required int durationMs,
    StreakClipKind mediaKind = StreakClipKind.video,
  }) async {
    attachedKeys.add(mediaUrl);
  }
}

class _FakePathProviderPlatform extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProviderPlatform(this.tempDir);
  final Directory tempDir;
  @override
  Future<String?> getTemporaryPath() async => tempDir.path;
  @override
  Future<String?> getApplicationSupportPath() async => tempDir.path;
}

/// What validate_message_media_before_insert raises
/// (20260914150000_streak_size_ceiling.sql).
PostgrestException _refusal(String message) =>
    PostgrestException(message: message, code: 'P0001');

const _intentExpired = 'Chat media upload intent is invalid or expired';
const _objectMissing = 'Chat media object is missing';
const _posterExpired = 'Chat media thumbnail upload intent is invalid or expired';

void main() {
  const userId = 'user-a';
  const relId = 'rel-1';
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('expired_intent');
    PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir);
  });
  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

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

  Future<String> file(String name) async {
    final path = p.join(tempDir.path, name);
    await File(path).writeAsBytes(List.filled(256, 1));
    return path;
  }

  /// Refuses the first insert that carries [key] with [message], once.
  Object? Function(String?, String?) refuseOnce(
    String key,
    String message, {
    bool poster = false,
  }) {
    var refused = false;
    return (media, thumb) {
      final hit = poster ? thumb == key : media == key;
      if (!hit || refused) return null;
      refused = true;
      return _refusal(message);
    };
  }

  test('the refusals are recognised in one named place', () {
    for (final message in [
      _intentExpired,
      _objectMissing,
      _posterExpired,
      'Chat media thumbnail object is missing',
    ]) {
      expect(ChatError.isStaleMediaUploadRefusal(_refusal(message)), isTrue,
          reason: message);
    }
    expect(
      ChatError.isStaleMediaUploadRefusal(
          _refusal('Reply target message does not exist')),
      isFalse,
    );
    expect(ChatError.isStaleMediaUploadRefusal(Exception(_intentExpired)),
        isFalse, reason: 'only the insert trigger\'s own refusal');
  });

  for (final message in [_intentExpired, _objectMissing]) {
    test('"$message" at insert: a fresh intent, a new upload, sent', () async {
      final cache = ChatCacheService.forTesting(backend: memBackend());
      final repo = FakeChatRepository(currentUserId: userId)
        ..uniqueIntentKeys = true
        ..insertGuard = refuseOnce('chat-media/intent-1', message);
      final (controller, state) = await boot(repo, cache: cache);

      await controller.sendVoiceMessage(
          localPath: await file('v.m4a'), durationMs: 1000, waveform: const [1]);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(repo.sentMediaKeys, ['chat-media/intent-1', 'chat-media/intent-3'],
          reason: 'the retry inserts under the NEW intent\'s key');
      expect(repo.mediaCallCount, 4, reason: 'intent, upload, intent, upload');
      expect(state().messages.single.status, MessageStatus.sent);
      expect(state().error, isNull);
      expect(await cache.readOutbox(userId, relationshipId: relId), isEmpty);
    });
  }

  test('a video clears and re-uploads its poster too', () async {
    final repo = FakeChatRepository(currentUserId: userId)
      ..uniqueIntentKeys = true
      ..insertGuard = refuseOnce('chat-media/intent-3', _posterExpired,
          poster: true);
    final (controller, state) = await boot(repo);

    await controller.sendVideoMessage(
      localPath: await file('clip.mp4'),
      durationMs: 2000,
      thumbnailLocalPath: await file('poster.jpg'),
      width: 1280,
      height: 720,
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(repo.sentMediaKeys, ['chat-media/intent-1', 'chat-media/intent-5']);
    expect(repo.sentThumbnailKeys, [
      'chat-media/intent-3',
      'chat-media/intent-7',
    ]);
    expect(state().messages.single.status, MessageStatus.sent);
  });

  test('a server that always refuses ends failedPermanent after the bound',
      () async {
    final cache = ChatCacheService.forTesting(backend: memBackend());
    final repo = FakeChatRepository(currentUserId: userId)
      ..uniqueIntentKeys = true
      ..insertGuard = (media, _) => media == null ? null : _refusal(_intentExpired);
    final (controller, state) = await boot(repo, cache: cache);

    await controller.sendVoiceMessage(
        localPath: await file('never.m4a'), durationMs: 1000, waveform: const [1]);
    await Future<void>.delayed(const Duration(milliseconds: 150));

    expect(repo.sendCallCount, 1 + ChatController.maxMediaReuploads,
        reason: 'the first insert, then one per re-upload, then no more');
    final row = (await cache.readOutbox(userId, relationshipId: relId)).single;
    expect(row.state, PendingSendState.failedPermanent);
    expect(row.uploadedMediaKey, isNull,
        reason: 'Retry must not reuse a key the server refused');
    expect(state().messages.single.status, MessageStatus.failed);

    // Retry restores the budget and starts from a fresh intent: one more
    // refusal is still absorbed by a re-upload.
    var refusedAgain = false;
    repo.insertGuard = (media, _) {
      if (refusedAgain) return null;
      refusedAgain = true;
      return _refusal(_objectMissing);
    };
    await controller.retryMessage(state().messages.single);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(state().messages.single.status, MessageStatus.sent);
  });

  test('a cold start with a persisted expired key recovers', () async {
    final cache = ChatCacheService.forTesting(backend: memBackend());
    await cache.putOutbox(
      userId,
      PendingSend(
        clientMessageId: 'stale',
        relationshipId: relId,
        senderId: userId,
        text: '',
        localMediaPath: await file('stale.m4a'),
        mediaMimeType: 'audio/mp4',
        mediaType: 'audio',
        mediaDurationMs: 1000,
        waveform: const [1],
        uploadedMediaKey: 'chat-media/yesterday',
        createdAt: DateTime.now().subtract(const Duration(hours: 20)),
        attempts: 9,
      ),
    );
    final repo = FakeChatRepository(currentUserId: userId)
      ..uniqueIntentKeys = true
      ..insertGuard = refuseOnce('chat-media/yesterday', _intentExpired);
    final (_, state) = await boot(repo, cache: cache);
    await Future<void>.delayed(const Duration(milliseconds: 80));

    expect(repo.sentMediaKeys, ['chat-media/yesterday', 'chat-media/intent-1']);
    expect(state().messages.single.status, MessageStatus.sent);
    expect(await cache.readOutbox(userId, relationshipId: relId), isEmpty);
  });

  test('Retry of a row failed on an expired key re-uploads', () async {
    final cache = ChatCacheService.forTesting(backend: memBackend());
    await cache.putOutbox(
      userId,
      PendingSend(
        clientMessageId: 'parked',
        relationshipId: relId,
        senderId: userId,
        text: '',
        localMediaPath: await file('parked.m4a'),
        mediaMimeType: 'audio/mp4',
        mediaType: 'audio',
        mediaDurationMs: 1000,
        waveform: const [1],
        uploadedMediaKey: 'chat-media/expired',
        createdAt: DateTime.now(),
        state: PendingSendState.failedPermanent,
        lastErrorCategory: 'mediaRejected',
      ),
    );
    final repo = FakeChatRepository(currentUserId: userId)
      ..uniqueIntentKeys = true
      ..insertGuard = refuseOnce('chat-media/expired', _objectMissing);
    final (controller, state) = await boot(repo, cache: cache);
    expect(state().messages.single.status, MessageStatus.failed);

    await controller.retryMessage(state().messages.single);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(repo.sentMediaKeys, ['chat-media/expired', 'chat-media/intent-1']);
    expect(state().messages.single.status, MessageStatus.sent);
  });

  test('the re-upload shows the ring and the cancel', () async {
    final cache = ChatCacheService.forTesting(backend: memBackend());
    final repo = FakeChatRepository(currentUserId: userId)
      ..uniqueIntentKeys = true;
    var refused = false;
    repo.insertGuard = (media, _) {
      if (refused) return null;
      refused = true;
      // Hold the second upload so the test can look at the bubble.
      repo.uploadGate = Completer<void>();
      return _refusal(_intentExpired);
    };
    final (controller, state) = await boot(repo, cache: cache);

    unawaited(controller.sendVoiceMessage(
        localPath: await file('ring.m4a'), durationMs: 1000, waveform: const [1]));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final bubble = state().messages.single;
    expect(bubble.status, MessageStatus.sending);
    expect(bubble.uploadProgress, 0);

    controller.cancelSend(bubble);
    repo.uploadGate!.complete();
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(state().messages.single.status, MessageStatus.failed);
    final row = (await cache.readOutbox(userId, relationshipId: relId)).single;
    expect(row.lastErrorCategory, 'cancelled');
  });

  test('the direct (no-outbox) path re-uploads too', () async {
    final backend = ScriptedCacheBackend()
      ..failPutOutbox = (id, ordinal) => true;
    final repo = FakeChatRepository(currentUserId: userId)
      ..uniqueIntentKeys = true
      ..insertGuard = refuseOnce('chat-media/intent-1', _intentExpired);
    final (controller, state) = await boot(
      repo,
      cache: ChatCacheService.forTesting(backend: backend),
    );

    await controller.sendVoiceMessage(
        localPath: await file('direct.m4a'), durationMs: 1000, waveform: const [1]);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(repo.sentMediaKeys, ['chat-media/intent-1', 'chat-media/intent-3']);
    expect(state().messages.single.status, MessageStatus.sent);
  });

  test('a preparation failing after the chat closed throws nothing and '
      'writes nothing', () async {
    final backend = ScriptedCacheBackend();
    final cache = ChatCacheService.forTesting(backend: backend);
    // A raw image pick still to be prepared, whose bytes are no image: the
    // preparer reads it from disk, then rejects it (ChatImageRejected).
    await cache.putOutbox(
      userId,
      PendingSend(
        clientMessageId: 'raw',
        relationshipId: relId,
        senderId: userId,
        text: '',
        localMediaPath: await file('raw.jpg'),
        mediaMimeType: 'image/jpeg',
        mediaType: 'image',
        requiresPreparation: true,
        createdAt: DateTime.now(),
      ),
    );
    final puts = <int>[];
    backend.failPutOutbox = (id, ordinal) {
      puts.add(ordinal);
      return false;
    };
    final gate = Completer<void>();
    backend.putOutboxGate = gate;

    final repo = FakeChatRepository(currentUserId: userId);
    final container = buildChatContainer(
      repository: repo,
      userId: userId,
      cache: cache,
    );
    final convo = activeConversation(relId);
    repo.conversationOverride = convo;
    container.read(chatControllerProvider(convo).notifier);
    // The open's flush reaches the preparation and parks on its write.
    for (var i = 0; i < 50 && puts.isEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(puts, isNotEmpty, reason: 'the preparation write is in flight');
    final writesBefore = puts.length;

    // Let the preparation reach its disk read (real IO: no microtask turn
    // completes it), then the person leaves the chat and the provider goes
    // away while the image is being prepared; the rejection lands after.
    gate.complete();
    await Future<void>.delayed(Duration.zero);
    container.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(puts.length, writesBefore, reason: 'nothing written after dispose');
    final row = (await cache.readOutbox(userId, relationshipId: relId)).single;
    expect(row.state, isNot(PendingSendState.failedPermanent),
        reason: 'the next open prepares it again');
  });

  group('fix round 3', () {
    /// The insert commits, its answer is lost; the retry's trigger sees the
    /// intent already used and answers with the stale text, not 23505.
    FakeChatRepository lostAnswer() => FakeChatRepository(currentUserId: userId)
      ..uniqueIntentKeys = true
      ..consumeIntentsOnCommit = true
      ..errorAfterCommit = TimeoutException('answer lost');

    test('N1: our own committed insert is reconciled with the original key, '
        'one upload', () async {
      final cache = ChatCacheService.forTesting(backend: memBackend());
      final repo = lostAnswer();
      final (controller, state) = await boot(repo, cache: cache);
      await controller.sendVoiceMessage(
          localPath: await file('lost.m4a'), durationMs: 1000, waveform: const [1]);
      expect(state().messages.single.status, MessageStatus.queued);

      await controller.flushOutbox(force: true);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(repo.sentMediaKeys, ['chat-media/intent-1', 'chat-media/intent-1']);
      expect(repo.mediaCallCount, 2, reason: 'one intent, one upload: no re-upload');
      expect(state().messages.single.status, MessageStatus.sent);
      expect(state().messages.single.mediaKey, 'chat-media/intent-1');
      expect(await cache.readOutbox(userId, relationshipId: relId), isEmpty);
    });

    test('N1: a video is reconciled too, no second upload', () async {
      final repo = lostAnswer();
      final (controller, state) = await boot(repo);
      await controller.sendVideoMessage(
        localPath: await file('lostclip.mp4'),
        durationMs: 2000,
        thumbnailLocalPath: await file('lostposter.jpg'),
        width: 1280,
        height: 720,
      );
      await controller.flushOutbox(force: true);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(repo.mediaCallCount, 4, reason: 'clip and poster, once each');
      expect(state().messages.single.status, MessageStatus.sent);
    });

    test('N1: a streak\'s clip is attached with the ORIGINAL key', () async {
      final streaks = _RecordingStreakRepository();
      final repo = lostAnswer();
      final container = buildChatContainer(
        repository: repo,
        userId: userId,
        extraOverrides: [streakRepositoryProvider.overrideWithValue(streaks)],
      );
      addTearDown(container.dispose);
      final convo = activeConversation(relId);
      repo.conversationOverride = convo;
      final controller = container.read(chatControllerProvider(convo).notifier);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      await controller.sendStreakMessage(
        localPath: await file('streak.mp4'),
        durationMs: 3000,
        viewsRemaining: 1,
      );
      expect(streaks.attachedKeys, isEmpty, reason: 'the answer was lost');

      await controller.flushOutbox(force: true);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(streaks.attachedKeys, ['chat-media/intent-1']);
      expect(repo.mediaCallCount, 2);
      expect(
        container.read(chatControllerProvider(convo)).messages.single.status,
        MessageStatus.sent,
      );
    });

    test('N1: a failed lookup stays retryable and does not re-upload',
        () async {
      final cache = ChatCacheService.forTesting(backend: memBackend());
      final repo = lostAnswer();
      final (controller, state) = await boot(repo, cache: cache);
      await controller.sendVoiceMessage(
          localPath: await file('lookup.m4a'), durationMs: 1000, waveform: const [1]);

      repo.findMessageError = const SocketException('offline');
      await controller.flushOutbox(force: true);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final row = (await cache.readOutbox(userId, relationshipId: relId)).single;
      expect(row.state, PendingSendState.queued);
      expect(row.uploadedMediaKey, 'chat-media/intent-1', reason: 'key kept');
      expect(row.mediaReuploads, 0, reason: 'no budget spent on a lookup');
      expect(repo.mediaCallCount, 2);
      expect(state().messages.single.status, MessageStatus.queued);

      await controller.flushOutbox(force: true);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(state().messages.single.status, MessageStatus.sent);
      expect(repo.mediaCallCount, 2);
    });

    test('N1: the direct (no-outbox) path reconciles too', () async {
      final backend = ScriptedCacheBackend()
        ..failPutOutbox = (id, ordinal) => true;
      final repo = lostAnswer();
      final (controller, state) = await boot(
        repo,
        cache: ChatCacheService.forTesting(backend: backend),
      );
      await controller.sendVoiceMessage(
          localPath: await file('dlost.m4a'), durationMs: 1000, waveform: const [1]);
      expect(state().messages.single.status, MessageStatus.failed);

      await controller.retryMessage(state().messages.single);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(state().messages.single.status, MessageStatus.sent);
      expect(repo.mediaCallCount, 2);
    });

    test('N2: a purge during the refused direct insert starts nothing',
        () async {
      final backend = ScriptedCacheBackend()
        ..failPutOutbox = (id, ordinal) => true;
      final repo = FakeChatRepository(currentUserId: userId)
        ..uniqueIntentKeys = true;
      final (controller, state) = await boot(
        repo,
        cache: ChatCacheService.forTesting(backend: backend),
      );
      var refused = false;
      repo.insertGuard = (media, _) {
        if (refused) return null;
        refused = true;
        unawaited(controller.debugHandleAccountChange(userId));
        return _refusal(_intentExpired);
      };
      await controller.sendVoiceMessage(
          localPath: await file('n2.m4a'), durationMs: 1000, waveform: const [1]);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(repo.mediaCallCount, 2, reason: 'no fresh intent after the purge');
      expect(repo.findMessageCalls, 0,
          reason: 'not even a lookup once the queue is purged');
      expect(controller.debugHasUnsavedSend(
          repo.lastSendArgs!.clientMessageId), isFalse);
    });

    test('N3: Retry of an unsaved send restores the re-upload budget',
        () async {
      final cache = ChatCacheService.forTesting(backend: memBackend());
      final repo = FakeChatRepository(currentUserId: userId)
        ..uploadGate = Completer<void>();
      final (controller, state) = await boot(repo, cache: cache);
      final pending = PendingSend(
        clientMessageId: 'spent',
        relationshipId: relId,
        senderId: userId,
        text: '',
        localMediaPath: await file('spent.m4a'),
        mediaMimeType: 'audio/mp4',
        mediaType: 'audio',
        mediaDurationMs: 1000,
        waveform: const [1],
        createdAt: DateTime.now(),
        mediaReuploads: ChatController.maxMediaReuploads,
      );
      controller.debugHoldUnsavedSend(pending);

      unawaited(controller.retryMessage(Message.optimistic(
        id: '_local_spent',
        clientMessageId: 'spent',
        relationshipId: relId,
        senderId: userId,
        content: '',
        createdAt: pending.createdAt,
        mediaType: 'audio',
      )));
      await Future<void>.delayed(const Duration(milliseconds: 30));
      final row = (await cache.readOutbox(userId, relationshipId: relId)).single;
      expect(row.mediaReuploads, 0);
      repo.uploadGate!.complete();
    });

    group('dispose mid-send throws nothing and writes nothing', () {
      Future<void> disposeMidway({
        required void Function(FakeChatRepository repo) arrange,
        required void Function(FakeChatRepository repo) release,
      }) async {
        final backend = ScriptedCacheBackend();
        final cache = ChatCacheService.forTesting(backend: backend);
        final repo = FakeChatRepository(currentUserId: userId);
        arrange(repo);
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
        unawaited(controller.sendVoiceMessage(
            localPath: await file('d${repo.hashCode}.m4a'),
            durationMs: 1000,
            waveform: const [1]));
        await Future<void>.delayed(const Duration(milliseconds: 30));
        final writes = <int>[];
        backend.failPutOutbox = (id, ordinal) {
          writes.add(ordinal);
          return false;
        };
        // The send path's last line of defence logs "escaped" when anything
        // throws inside it; after dispose nothing may reach it.
        final logs = <String>[];
        final DebugPrintCallback original = debugPrint;
        debugPrint = (message, {wrapWidth}) => logs.add(message ?? '');
        addTearDown(() => debugPrint = original);
        // The controller goes away; the app (container) lives on, so a ref
        // read still works and any write would really land — exactly what
        // must not happen from a disposed controller.
        container.invalidate(chatControllerProvider(convo));
        expect(controller.mounted, isFalse);
        final rowsBefore = await cache.readOutbox(userId, relationshipId: relId);
        release(repo);
        await Future<void>.delayed(const Duration(milliseconds: 150));
        debugPrint = original;
        expect(writes, isEmpty, reason: 'nothing written after dispose');
        final rowsAfter = await cache.readOutbox(userId, relationshipId: relId);
        expect(rowsAfter.map((r) => r.clientMessageId),
            rowsBefore.map((r) => r.clientMessageId),
            reason: 'the row stays for the next open to finish');
        expect(logs.where((l) => l.contains('escaped')), isEmpty,
            reason: 'nothing threw after dispose');
      }

      test('_attemptSend: the insert fails after dispose', () async {
        await disposeMidway(
          arrange: (repo) => repo
            ..sendDelay = const Duration(milliseconds: 80)
            ..nextSendError = Exception('boom'),
          release: (_) {},
        );
      });

      test('_attemptSend: the insert lands after dispose', () async {
        await disposeMidway(
          arrange: (repo) => repo.sendDelay = const Duration(milliseconds: 80),
          release: (_) {},
        );
      });

      test('_runUpload: the upload finishes after dispose', () async {
        await disposeMidway(
          arrange: (repo) => repo.uploadGate = Completer<void>(),
          release: (repo) => repo.uploadGate!.complete(),
        );
      });

      test('_runUpload: the upload fails after dispose', () async {
        await disposeMidway(
          arrange: (repo) => repo
            ..uploadGate = Completer<void>()
            ..mediaCallFailures[2] = const SocketException('offline'),
          release: (repo) => repo.uploadGate!.complete(),
        );
      });
    });

    test('a chat closed mid-upload stays alive until its send lands',
        () async {
      final cache = ChatCacheService.forTesting(backend: memBackend());
      final repo = FakeChatRepository(currentUserId: userId)
        ..uploadGate = Completer<void>();
      final container = buildChatContainer(
        repository: repo,
        userId: userId,
        cache: cache,
        extraOverrides: [
          chatConfigProvider.overrideWithValue(
            const ChatConfig(controllerKeepAlive: Duration(milliseconds: 40)),
          ),
        ],
      );
      addTearDown(container.dispose);
      final convo = activeConversation(relId);
      repo.conversationOverride = convo;
      final screen = container.listen(chatControllerProvider(convo), (_, __) {});
      final controller = container.read(chatControllerProvider(convo).notifier);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      unawaited(controller.sendVoiceMessage(
          localPath: await file('leave.m4a'), durationMs: 1000, waveform: const [1]));
      await Future<void>.delayed(const Duration(milliseconds: 20));

      // The person leaves the chat; the keep-alive runs out mid-upload.
      screen.close();
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(controller.mounted, isTrue, reason: 'a send in flight holds it');

      repo.uploadGate!.complete();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(repo.sendCallCount, 1);
      expect(await cache.readOutbox(userId, relationshipId: relId), isEmpty);

      // Idle again: the usual eviction follows.
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(controller.mounted, isFalse);
    });
  });
}

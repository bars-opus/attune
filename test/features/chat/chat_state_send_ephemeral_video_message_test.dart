import 'dart:io';

import 'package:attune/features/chat/data/cache/chat_cache_service.dart';
import 'package:attune/features/chat/domain/entities/conversation.dart';
import 'package:attune/features/chat/domain/entities/message.dart';
import 'package:attune/features/chat/domain/services/chat_video_preparer.dart';
import 'package:attune/features/chat/presentation/state/chat_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'support/chat_test_harness.dart';

/// A minimal fake path_provider so File-backed tests don't need a real
/// platform channel. Only getTemporaryDirectory is used by this test.
class _FakePathProviderPlatform extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProviderPlatform(this.tempDir);
  final Directory tempDir;

  @override
  Future<String?> getTemporaryPath() async => tempDir.path;
}

/// Bundles a booted controller with a live view of its state.
class _Booted {
  _Booted(this.controller, this.container, this.conversation);
  final ChatController controller;
  final ProviderContainer container;
  final Conversation conversation;

  ChatState get state =>
      container.read(chatControllerProvider(conversation));
}

void main() {
  const userId = 'user-a';
  const relId = 'rel-1';

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('ephemeral_video_test');
    PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Future<_Booted> boot(
    FakeChatRepository repo, {
    Conversation? conversation,
  }) async {
    final container = buildChatContainer(repository: repo, userId: userId);
    addTearDown(container.dispose);
    final convo = conversation ?? activeConversation(relId);
    repo.conversationOverride = convo;
    final controller = container.read(
      chatControllerProvider(convo).notifier,
    );
    // Let _init() (cache read, refresh, load, subscribe) settle.
    await Future<void>.delayed(const Duration(milliseconds: 20));
    return _Booted(controller, container, convo);
  }

  Future<String> writeFile(String name, {int bytes = 128}) async {
    final path = p.join(tempDir.path, name);
    final file = File(path);
    await file.writeAsBytes(List.filled(bytes, 1));
    return path;
  }

  group('sendEphemeralVideoMessage', () {
    test('missing local video file sets state.error and does not queue',
        () async {
      final repo = FakeChatRepository(currentUserId: userId);
      final b = await boot(repo);
      final thumbPath = await writeFile('poster.jpg');

      await b.controller.sendEphemeralVideoMessage(
        localPath: p.join(tempDir.path, 'does_not_exist.mp4'),
        durationMs: 2000,
        thumbnailLocalPath: thumbPath,
        width: 720,
        height: 1280,
      );

      expect(b.state.messages, isEmpty);
      expect(b.state.error, isNotNull);
      expect(repo.sendCallCount, 0);
    });

    test(
        'missing thumbnail file (video exists, poster does not) sets '
        'state.error and does not queue', () async {
      final repo = FakeChatRepository(currentUserId: userId);
      final b = await boot(repo);
      final videoPath = await writeFile('clip.mp4');

      await b.controller.sendEphemeralVideoMessage(
        localPath: videoPath,
        durationMs: 2000,
        thumbnailLocalPath: p.join(tempDir.path, 'no_poster.jpg'),
        width: 720,
        height: 1280,
      );

      expect(b.state.messages, isEmpty);
      expect(b.state.error, isNotNull);
      expect(repo.sendCallCount, 0);
    });

    test(
        'duration over the 10s ephemeral cap sets state.error and does not '
        'queue — proves this is a genuinely different bound from '
        "sendVideoMessage's 3-minute ChatVideoPreparer.maxDuration",
        () async {
      final repo = FakeChatRepository(currentUserId: userId);
      final b = await boot(repo);
      final videoPath = await writeFile('too_long.mp4');
      final thumbPath = await writeFile('poster_long.jpg');

      // 11 seconds: over the 10s ephemeral cap, but well under
      // ChatVideoPreparer.maxDuration (3 minutes) — if sendEphemeralVideoMessage
      // were accidentally sharing sendVideoMessage's bound, this would pass
      // through undetected.
      await b.controller.sendEphemeralVideoMessage(
        localPath: videoPath,
        durationMs: const Duration(seconds: 11).inMilliseconds,
        thumbnailLocalPath: thumbPath,
        width: 720,
        height: 1280,
      );

      expect(b.state.messages, isEmpty);
      expect(b.state.error, isNotNull);
      expect(repo.sendCallCount, 0);
    });

    test(
        'duration under min returns silently with no error and no queued message',
        () async {
      final repo = FakeChatRepository(currentUserId: userId);
      final b = await boot(repo);
      final videoPath = await writeFile('too_short.mp4');
      final thumbPath = await writeFile('poster_short.jpg');

      await b.controller.sendEphemeralVideoMessage(
        localPath: videoPath,
        durationMs: ChatVideoPreparer.minDuration.inMilliseconds - 100,
        thumbnailLocalPath: thumbPath,
        width: 720,
        height: 1280,
      );

      expect(b.state.messages, isEmpty);
      expect(b.state.error, isNull);
      expect(repo.sendCallCount, 0);
    });

    test(
        'a valid send produces exactly one optimistic message with '
        'mediaType video, isViewOnce true, isEphemeralVideoAvailable true, '
        'status sending', () async {
      final repo = FakeChatRepository(currentUserId: userId)
        // Artificial delay so we can observe the optimistic (sending) state
        // before the fake "server" acknowledges, mirroring
        // chat_state_send_video_message_test.dart's pattern.
        ..sendDelay = const Duration(milliseconds: 200);
      final b = await boot(repo);
      final videoPath = await writeFile('valid.mp4');
      final thumbPath = await writeFile('valid_poster.jpg');

      final future = b.controller.sendEphemeralVideoMessage(
        localPath: videoPath,
        durationMs: 8000,
        thumbnailLocalPath: thumbPath,
        width: 720,
        height: 1280,
      );

      // Give the optimistic write a moment to land before the fake server
      // resolves.
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final messages = b.state.messages;
      expect(messages, hasLength(1));
      final message = messages.single;
      expect(message.mediaType, 'video');
      expect(message.isViewOnce, isTrue);
      expect(message.isEphemeralVideoAvailable, isTrue);
      expect(message.status, MessageStatus.sending);
      expect(message.mediaDurationMs, 8000);
      expect(message.mediaWidth, 720);
      expect(message.mediaHeight, 1280);

      await future;
      await Future<void>.delayed(const Duration(milliseconds: 250));

      expect(repo.sendCallCount, 1);
    });

    test(
        'a canonical row in state that transitions to expired during a '
        'merge has its local capture file deleted and localMediaPath '
        'cleared (Important finding I3)', () async {
      // _attemptSend already deletes pending.localMediaPath immediately
      // after every successful send (chat_state.dart, right after
      // sendTextMessage returns) — that part of the pipeline predates this
      // feature and is not what I3 is about. The gap I3 describes is
      // narrower: an already-settled CANONICAL row sitting in
      // state.messages that still (for whatever reason — e.g. it was
      // reconciled from a source other than this session's own
      // _attemptSend) carries a populated localMediaPath, which
      // _mergeMessages's carry-forward logic would otherwise propagate
      // onto the newly-expired incoming row unchanged. This test
      // constructs that state directly (bypassing the send pipeline, which
      // already cleans up on its own) to isolate _mergeMessages's own
      // responsibility.
      final repo = FakeChatRepository(currentUserId: userId);
      final b = await boot(repo);
      final videoPath = await writeFile('sender_clip.mp4');

      final canonical = repo.seedIncoming(
        id: 'm1',
        relationshipId: relId,
        senderId: userId,
        content: '',
        createdAt: DateTime.now(),
      );
      repo.serverMessages['m1'] = canonical.copyWith(isViewOnce: true);

      // Directly install a canonical (non-`_local_`) row in state that
      // still carries a localMediaPath, simulating the "settled row still
      // references the on-device file" precondition _mergeMessages must
      // guard against.
      b.controller.debugSetMessages([
        canonical.copyWith(isViewOnce: true, localMediaPath: videoPath),
      ]);
      expect(await File(videoPath).exists(), isTrue);

      // Now the server row is revoked (mark_video_viewed is symmetric —
      // either the sender's own complete view or the receiver's counts,
      // see 20260816130000_chat_ephemeral_video.sql) and a refresh merges
      // it in.
      repo.serverMessages['m1'] = repo.serverMessages['m1']!.copyWith(
        viewedAt: DateTime.now(),
      );
      await b.controller.loadMessages();

      final merged = b.state.messages.single;
      expect(merged.isEphemeralVideoExpired, isTrue);
      expect(
        merged.localMediaPath,
        isNull,
        reason:
            'the tombstone row must not carry the local path forward, or '
            "the sender's clip would remain recoverable on-device",
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(
        await File(videoPath).exists(),
        isFalse,
        reason:
            "the sender's on-device capture file must be deleted once the "
            'video is revoked, matching the tombstone the UI already shows',
      );
    });

    test(
        'a still-optimistic (_local_) row for the same message is cleaned '
        'up too if a realtime merge lands an already-expired canonical row '
        'before the send pipeline swaps the optimistic row out '
        '(Important finding I3)', () async {
      // This is the actual race _mergeMessages must guard against: the
      // optimistic row (id starts with `_local_`) and the freshly-fetched
      // canonical row are keyed differently in _mergeMessages's `byId`
      // map, so they never collide there — only the final
      // de-dup-by-clientMessageId step drops the optimistic row, and
      // without this fix that drop happened silently, with no
      // _deleteStagedMedia call, whenever the incoming canonical row had
      // already become ephemeral-expired by the time it was fetched.
      final repo = FakeChatRepository(currentUserId: userId);
      final b = await boot(repo);
      final videoPath = await writeFile('optimistic_clip.mp4');
      const clientMessageId = 'client-1';

      final canonical = repo.seedIncoming(
        id: 'm1',
        relationshipId: relId,
        senderId: userId,
        content: '',
        createdAt: DateTime.now(),
      );
      // Already expired by the time it's fetched — mirrors a revocation
      // that landed before this device ever saw the un-expired row.
      repo.serverMessages['m1'] = canonical.copyWith(
        isViewOnce: true,
        viewedAt: DateTime.now(),
        clientMessageId: clientMessageId,
      );

      b.controller.debugSetMessages([
        Message.optimistic(
          id: '_local_$clientMessageId',
          clientMessageId: clientMessageId,
          relationshipId: relId,
          senderId: userId,
          content: '',
          createdAt: DateTime.now(),
          mediaType: 'video',
          localMediaPath: videoPath,
          isViewOnce: true,
        ),
      ]);
      expect(await File(videoPath).exists(), isTrue);

      await b.controller.loadMessages();

      final merged = b.state.messages;
      expect(merged, hasLength(1));
      expect(merged.single.id, 'm1');
      expect(merged.single.localMediaPath, isNull);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(
        await File(videoPath).exists(),
        isFalse,
        reason:
            'the still-optimistic row is discarded by the de-dup step, so '
            'its local file must be swept there rather than silently '
            'orphaned',
      );
    });

    test('the queued PendingSend has isViewOnce true', () async {
      final repo = FakeChatRepository(currentUserId: userId)
        // Hold the send open so the outbox entry is still queued when we
        // read it back, mirroring how Part 1 observes in-flight state.
        ..sendDelay = const Duration(milliseconds: 200);
      final b = await boot(repo);
      final videoPath = await writeFile('valid.mp4');
      final thumbPath = await writeFile('valid_poster.jpg');

      final future = b.controller.sendEphemeralVideoMessage(
        localPath: videoPath,
        durationMs: 8000,
        thumbnailLocalPath: thumbPath,
        width: 720,
        height: 1280,
      );

      await Future<void>.delayed(const Duration(milliseconds: 20));

      final outbox = await b.container
          .read(chatCacheServiceProvider)
          .readOutbox(userId, relationshipId: relId);
      expect(outbox, hasLength(1));
      expect(outbox.single.isViewOnce, isTrue);
      expect(outbox.single.mediaType, 'video');

      await future;
      await Future<void>.delayed(const Duration(milliseconds: 250));
    });
  });
}

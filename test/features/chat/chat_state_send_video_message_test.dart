import 'dart:io';

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
    tempDir = await Directory.systemTemp.createTemp('video_msg_test');
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

  group('sendVideoMessage', () {
    test('missing local video file sets state.error and does not queue',
        () async {
      final repo = FakeChatRepository(currentUserId: userId);
      final b = await boot(repo);
      final thumbPath = await writeFile('poster.jpg');

      await b.controller.sendVideoMessage(
        localPath: p.join(tempDir.path, 'does_not_exist.mp4'),
        durationMs: 2000,
        thumbnailLocalPath: thumbPath,
        width: 1280,
        height: 720,
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

      await b.controller.sendVideoMessage(
        localPath: videoPath,
        durationMs: 2000,
        thumbnailLocalPath: p.join(tempDir.path, 'no_poster.jpg'),
        width: 1280,
        height: 720,
      );

      expect(b.state.messages, isEmpty);
      expect(b.state.error, isNotNull);
      expect(repo.sendCallCount, 0);
    });

    test('duration over max sets state.error and does not queue', () async {
      final repo = FakeChatRepository(currentUserId: userId);
      final b = await boot(repo);
      final videoPath = await writeFile('too_long.mp4');
      final thumbPath = await writeFile('poster_long.jpg');

      await b.controller.sendVideoMessage(
        localPath: videoPath,
        durationMs: ChatVideoPreparer.maxDuration.inMilliseconds + 1000,
        thumbnailLocalPath: thumbPath,
        width: 1280,
        height: 720,
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

      await b.controller.sendVideoMessage(
        localPath: videoPath,
        durationMs: ChatVideoPreparer.minDuration.inMilliseconds - 100,
        thumbnailLocalPath: thumbPath,
        width: 1280,
        height: 720,
      );

      expect(b.state.messages, isEmpty);
      expect(b.state.error, isNull);
      expect(repo.sendCallCount, 0);
    });

    test(
        'a valid send produces exactly one optimistic message with '
        'mediaType video, hasVideo true, status sending, matching '
        'width/height', () async {
      final repo = FakeChatRepository(currentUserId: userId)
        // Artificial delay so we can observe the optimistic (sending) state
        // before the fake "server" acknowledges, mirroring
        // chat_state_send_voice_message_test.dart's pattern.
        ..sendDelay = const Duration(milliseconds: 200);
      final b = await boot(repo);
      final videoPath = await writeFile('valid.mp4');
      final thumbPath = await writeFile('valid_poster.jpg');

      final future = b.controller.sendVideoMessage(
        localPath: videoPath,
        durationMs: 4200,
        thumbnailLocalPath: thumbPath,
        width: 1280,
        height: 720,
      );

      // Give the optimistic write a moment to land before the fake server
      // resolves.
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final messages = b.state.messages;
      expect(messages, hasLength(1));
      final message = messages.single;
      expect(message.mediaType, 'video');
      expect(message.hasVideo, isTrue);
      expect(message.status, MessageStatus.sending);
      expect(message.mediaDurationMs, 4200);
      expect(message.mediaWidth, 1280);
      expect(message.mediaHeight, 720);

      await future;
      await Future<void>.delayed(const Duration(milliseconds: 250));

      // Video's two-intent upload (video + thumbnail) both go through
      // createMediaUploadIntent/uploadChatMedia on the fake repository. The
      // canonical message sends successfully here, which at minimum proves
      // the two-intent path doesn't throw or block a normal send. The
      // thumbnail-upload-failure-is-non-fatal distinction from
      // _attemptSend's two-intent branch, and the inverse (a video-upload
      // failure aborting the whole send), are covered by the two tests
      // below using FakeChatRepository.mediaCallFailures.
      expect(repo.sendCallCount, 1);
    });

    test(
        'thumbnail upload failure (2nd intent) is non-fatal: send still '
        'completes with a null mediaThumbnailKey', () async {
      final repo = FakeChatRepository(currentUserId: userId)
        // Call order inside _attemptSend's two-intent video branch: 1 =
        // video createMediaUploadIntent, 2 = video uploadChatMedia, 3 =
        // thumbnail createMediaUploadIntent, 4 = thumbnail uploadChatMedia.
        // Failing call 3 exercises the thumbnail intent request itself
        // failing (caught locally, non-fatal).
        ..mediaCallFailures[3] = Exception('thumbnail intent failed');
      final b = await boot(repo);
      final videoPath = await writeFile('valid.mp4');
      final thumbPath = await writeFile('valid_poster.jpg');

      await b.controller.sendVideoMessage(
        localPath: videoPath,
        durationMs: 4200,
        thumbnailLocalPath: thumbPath,
        width: 1280,
        height: 720,
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // The send still completed: exactly one canonical message landed via
      // sendTextMessage, and no error was surfaced to state.
      expect(repo.sendCallCount, 1);
      expect(b.state.error, isNull);
      final messages = b.state.messages;
      expect(messages, hasLength(1));
      final message = messages.single;
      expect(message.status, MessageStatus.sent);
      expect(message.mediaType, 'video');
      // The thumbnail upload failed, so no thumbnail key reached
      // sendTextMessage — mirrors a video message that simply has no
      // poster image.
      expect(message.mediaThumbnailKey, isNull);

      // ...but the sender must still SEE a poster. The canonical row has no
      // thumbnail key, so the locally-extracted frame is the only poster in
      // existence — it has to survive the optimistic->canonical swap, or the
      // bubble renders a permanently blank grey tile.
      expect(message.localThumbnailPath, thumbPath);
      // And the staged file itself must still be on disk, since deleting it
      // is what previously made the blank tile unrecoverable across restarts.
      expect(File(thumbPath).existsSync(), isTrue);
    });

    test(
        'a successful thumbnail upload still reclaims the staged poster file',
        () async {
      final repo = FakeChatRepository(currentUserId: userId);
      final b = await boot(repo);
      final videoPath = await writeFile('valid.mp4');
      final thumbPath = await writeFile('valid_poster.jpg');

      await b.controller.sendVideoMessage(
        localPath: videoPath,
        durationMs: 4200,
        thumbnailLocalPath: thumbPath,
        width: 1280,
        height: 720,
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // The server has its own copy now, so the staged file is redundant.
      // Guards the retention above from becoming an unconditional leak that
      // grows staging storage on every video ever sent.
      final message = b.state.messages.single;
      expect(message.mediaThumbnailKey, isNotNull);
      expect(File(thumbPath).existsSync(), isFalse);
    });

    test(
        'video upload failure (1st intent) aborts the whole send: no '
        'canonical message reaches sendTextMessage, message stays queued '
        'for retry rather than silently disappearing', () async {
      final repo = FakeChatRepository(currentUserId: userId)
        // Failing call 1 (the video's own createMediaUploadIntent) must
        // abort the send entirely, before the thumbnail's intent (call 3,
        // which never happens here since the outer try/catch in
        // _attemptSend catches this failure before reaching that branch)
        // and before sendTextMessage are ever reached.
        ..mediaCallFailures[1] = Exception('video intent failed');
      final b = await boot(repo);
      final videoPath = await writeFile('valid.mp4');
      final thumbPath = await writeFile('valid_poster.jpg');

      await b.controller.sendVideoMessage(
        localPath: videoPath,
        durationMs: 4200,
        thumbnailLocalPath: thumbPath,
        width: 1280,
        height: 720,
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // sendTextMessage (which increments sendCallCount) was never reached —
      // the whole send aborted at the first (video) intent failure, unlike
      // the thumbnail-only failure above.
      expect(repo.sendCallCount, 0);
      expect(b.state.error, isNotNull);
      // The optimistic message survives as queued (for automatic retry),
      // not silently dropped and not marked failed on this first attempt.
      final messages = b.state.messages;
      expect(messages, hasLength(1));
      expect(messages.single.status, MessageStatus.queued);
    });
  });
}

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
      // createMediaUploadIntent/uploadChatMedia on the fake repository —
      // FakeChatRepository doesn't track call counts for those beyond the
      // default no-op stub, so the thumbnail-upload-failure-is-non-fatal
      // distinction from _attemptSend's two-intent branch is NOT covered by
      // this harness: FakeChatRepository's createMediaUploadIntent/
      // uploadChatMedia stubs always succeed unconditionally and have no
      // "fail on second call" seam. Exercising that branch would require
      // extending the fake with a scriptable per-call failure, which is out
      // of scope for this task's minimum coverage. The canonical message
      // sends successfully here, which at minimum proves the two-intent
      // path doesn't throw or block a normal send.
      expect(repo.sendCallCount, 1);
    });
  });
}

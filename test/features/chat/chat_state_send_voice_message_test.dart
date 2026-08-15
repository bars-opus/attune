import 'dart:io';

import 'package:attune/core/services/media/voice_recorder_service.dart';
import 'package:attune/features/chat/domain/entities/conversation.dart';
import 'package:attune/features/chat/domain/entities/message.dart';
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
    tempDir = await Directory.systemTemp.createTemp('voice_msg_test');
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

  Future<String> writeVoiceFile(String name, {int bytes = 128}) async {
    final path = p.join(tempDir.path, name);
    final file = File(path);
    await file.writeAsBytes(List.filled(bytes, 1));
    return path;
  }

  group('sendVoiceMessage', () {
    test('missing local file sets state.error and does not queue', () async {
      final repo = FakeChatRepository(currentUserId: userId);
      final b = await boot(repo);

      await b.controller.sendVoiceMessage(
        localPath: p.join(tempDir.path, 'does_not_exist.m4a'),
        durationMs: 2000,
        waveform: const [1, 2, 3],
      );

      expect(b.state.messages, isEmpty);
      expect(b.state.error, isNotNull);
      expect(repo.sendCallCount, 0);
    });

    test('duration over max sets state.error and does not queue', () async {
      final repo = FakeChatRepository(currentUserId: userId);
      final b = await boot(repo);
      final path = await writeVoiceFile('too_long.m4a');

      await b.controller.sendVoiceMessage(
        localPath: path,
        durationMs: VoiceRecorderService.maxDuration.inMilliseconds + 1000,
        waveform: const [1, 2, 3],
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
      final path = await writeVoiceFile('too_short.m4a');

      await b.controller.sendVoiceMessage(
        localPath: path,
        durationMs: VoiceRecorderService.minDuration.inMilliseconds - 100,
        waveform: const [1, 2, 3],
      );

      expect(b.state.messages, isEmpty);
      expect(b.state.error, isNull);
      expect(repo.sendCallCount, 0);
    });

    test(
        'a valid recording produces exactly one optimistic message with '
        'mediaType audio, hasAudio true, status sending', () async {
      final repo = FakeChatRepository(currentUserId: userId)
        // Artificial delay so we can observe the optimistic (sending) state
        // before the fake "server" acknowledges, mirroring
        // chat_controller_test.dart's pattern for the text-send path.
        ..sendDelay = const Duration(milliseconds: 200);
      final b = await boot(repo);
      final path = await writeVoiceFile('valid.m4a');

      final future = b.controller.sendVoiceMessage(
        localPath: path,
        durationMs: 4200,
        waveform: const [1, 5, 10, 3],
      );

      // Give the optimistic write a moment to land before the fake server
      // resolves.
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final messages = b.state.messages;
      expect(messages, hasLength(1));
      final message = messages.single;
      expect(message.mediaType, 'audio');
      expect(message.hasAudio, isTrue);
      expect(message.status, MessageStatus.sending);
      expect(message.mediaDurationMs, 4200);
      expect(message.waveform, [1, 5, 10, 3]);

      await future;
      await Future<void>.delayed(const Duration(milliseconds: 250));
    });
  });
}

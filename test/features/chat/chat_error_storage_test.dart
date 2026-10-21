import 'dart:async';
import 'dart:io';

import 'package:attune/features/chat/data/cache/chat_cache_service.dart';
import 'package:attune/features/chat/domain/entities/message.dart';
import 'package:attune/features/chat/presentation/state/chat_state.dart';
import 'package:attune/features/chat/utils/chat_error.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/chat_test_harness.dart';

class _FakePathProviderPlatform extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProviderPlatform(this.tempDir);
  final Directory tempDir;
  @override
  Future<String?> getTemporaryPath() async => tempDir.path;
}

void main() {
  group('ChatError.from(StorageException)', () {
    ChatError from(String? status) =>
        ChatError.from(StorageException('x', statusCode: status));

    test('5xx and transport-level failures are transient', () {
      for (final s in ['500', '502', '503', '504', null, 'timeout']) {
        final e = from(s);
        expect(e.category, ChatErrorCategory.unavailable, reason: 'status $s');
        expect(e.isTransient, isTrue);
        expect(e.isPermanent, isFalse);
      }
    });

    test('429 is rate limited (transient)', () {
      expect(from('429').category, ChatErrorCategory.rateLimited);
    });

    test('401 and 409 retry with a fresh token / intent', () {
      expect(from('401').category, ChatErrorCategory.unavailable);
      expect(from('409').category, ChatErrorCategory.unavailable);
    });

    test('408 is a timeout, not a rejection (matches the Postgrest rule)', () {
      expect(from('408').category, ChatErrorCategory.unavailable);
      expect(
        ChatError.categorizeStorageStatus('408'),
        ChatErrorCategory.unavailable,
      );
    });

    test('policy, size and type rejections are permanent', () {
      for (final s in ['400', '404', '413', '415', '422']) {
        final e = from(s);
        expect(
          e.category,
          ChatErrorCategory.mediaRejected,
          reason: 'status $s',
        );
        expect(e.isPermanent, isTrue);
      }
    });

    test('403 (expired upload intent / token) counts toward the cap', () {
      final e = from('403');
      expect(e.category, ChatErrorCategory.unknown);
      expect(e.isPermanent, isFalse);
      expect(e.isTransient, isTrue);
    });

    test('a capped storage failure settles as a media rejection', () {
      final capped =
          ChatError.from(
            StorageException('x', statusCode: '403'),
            mediaType: 'video',
          ).afterAttemptCap();
      expect(capped.category, ChatErrorCategory.mediaRejected);
      expect(
        capped.toUserMessage(),
        'That video could not be sent. Try a different one.',
      );
      // A non-storage unknown failure keeps its generic copy at the cap.
      final other = ChatError.from(StateError('odd')).afterAttemptCap();
      expect(other.category, ChatErrorCategory.unknown);
      expect(other.toUserMessage(), 'Message not sent. Tap to retry.');
    });

    test('a dropped socket from the uploader reads as offline', () {
      final e = ChatError.from(http.ClientException('Connection closed'));
      expect(e.category, ChatErrorCategory.offline);
    });

    test('an upload that times out or loses its socket reads as offline', () {
      expect(
        ChatError.from(TimeoutException('upload')).category,
        ChatErrorCategory.offline,
      );
      expect(
        ChatError.from(const SocketException('reset')).category,
        ChatErrorCategory.offline,
      );
      // ClientException wording that matches none of the transport keywords
      // is still offline: the type decides, not the text.
      expect(
        ChatError.from(http.ClientException('Broken pipe')).category,
        ChatErrorCategory.offline,
      );
    });

    test('copy names the kind of media', () {
      final rejected = StorageException('x', statusCode: '415');
      expect(
        ChatError.from(rejected, mediaType: 'audio').toUserMessage(),
        'That voice message could not be sent. Try recording it again.',
      );
      expect(
        ChatError.from(rejected, mediaType: 'video').toUserMessage(),
        'That video could not be sent. Try a different one.',
      );
      expect(
        ChatError.from(rejected, mediaType: 'image').toUserMessage(),
        'That image could not be sent. Try a different one.',
      );
      expect(
        ChatError.from(rejected).toUserMessage(),
        'That image could not be sent. Try a different one.',
      );
      expect(
        ChatError.from(rejected).forMedia('video').toUserMessage(),
        'That video could not be sent. Try a different one.',
      );
      // An already-mapped error keeps its category and id when re-worded.
      final mapped = ChatError.from(rejected);
      final reworded = ChatError.from(mapped, mediaType: 'audio');
      expect(reworded.category, ChatErrorCategory.mediaRejected);
      expect(reworded.correlationId, mapped.correlationId);
      expect(
        reworded.toUserMessage(),
        'That voice message could not be sent. Try recording it again.',
      );
    });

    test('a streak is worded by its mime: photo or video', () {
      final rejected = ChatError.from(StorageException('x', statusCode: '415'));
      expect(
        rejected.forMedia('streak', mimeType: 'image/jpeg').toUserMessage(),
        'That image could not be sent. Try a different one.',
      );
      expect(
        rejected.forMedia('streak', mimeType: 'video/mp4').toUserMessage(),
        'That video could not be sent. Try a different one.',
      );
      final tooLarge = ChatError.from(StorageException('x', statusCode: '413'));
      expect(
        tooLarge.forMedia('streak', mimeType: 'image/png').toUserMessage(),
        'That photo is too large to send.',
      );
      expect(
        tooLarge
            .forMedia('streak', mimeType: 'video/quicktime')
            .toUserMessage(),
        'That video is too large to send — try a shorter clip.',
      );
    });

    test('413 says the media is too large, per kind', () {
      final tooLarge = StorageException('x', statusCode: '413');
      expect(
        ChatError.from(tooLarge, mediaType: 'image').toUserMessage(),
        'That photo is too large to send.',
      );
      expect(
        ChatError.from(tooLarge).toUserMessage(),
        'That photo is too large to send.',
      );
      expect(
        ChatError.from(tooLarge, mediaType: 'video').toUserMessage(),
        'That video is too large to send — try a shorter clip.',
      );
      expect(
        ChatError.from(tooLarge, mediaType: 'audio').toUserMessage(),
        'That voice message is too long to send.',
      );
    });
  });

  group('a storage 503 during a voice upload', () {
    const userId = 'user-a';
    const relId = 'rel-1';
    late Directory tempDir;
    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('storage_err');
      PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir);
    });
    tearDown(() => tempDir.delete(recursive: true));

    test('queues for retry instead of failing the message', () async {
      final repo = FakeChatRepository(currentUserId: userId)
        ..mediaCallFailures[2] = const StorageException(
          'Service Unavailable',
          statusCode: '503',
        );
      final container = buildChatContainer(repository: repo, userId: userId);
      addTearDown(container.dispose);
      final convo = activeConversation(relId);
      repo.conversationOverride = convo;
      final controller = container.read(chatControllerProvider(convo).notifier);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final path = p.join(tempDir.path, 'v.m4a');
      await File(path).writeAsBytes(List.filled(128, 1));

      await controller.sendVoiceMessage(
        localPath: path,
        durationMs: 1500,
        waveform: const [1, 2, 3],
      );

      final state = container.read(chatControllerProvider(convo));
      expect(
        state.messages.single.status,
        MessageStatus.queued,
        reason: 'a 503 is the server\'s problem, not the recording\'s',
      );
      expect(
        state.error,
        'Chat is temporarily unavailable. Please try again shortly.',
      );
    });

    test('a 413 fails the message with voice-specific copy', () async {
      final repo = FakeChatRepository(currentUserId: userId)
        ..mediaCallFailures[2] = const StorageException(
          'Payload Too Large',
          statusCode: '413',
        );
      final container = buildChatContainer(repository: repo, userId: userId);
      addTearDown(container.dispose);
      final convo = activeConversation(relId);
      repo.conversationOverride = convo;
      final controller = container.read(chatControllerProvider(convo).notifier);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final path = p.join(tempDir.path, 'big.m4a');
      await File(path).writeAsBytes(List.filled(128, 1));

      await controller.sendVoiceMessage(
        localPath: path,
        durationMs: 1500,
        waveform: const [1, 2, 3],
      );

      final state = container.read(chatControllerProvider(convo));
      expect(state.messages.single.status, MessageStatus.failed);
      expect(state.error, 'That voice message is too long to send.');
    });

    test('a 403 retries with a fresh intent and fails only after five '
        'attempts, with voice copy', () async {
      final repo = FakeChatRepository(currentUserId: userId);
      for (final call in [2, 4, 6, 8, 10]) {
        repo.mediaCallFailures[call] = const StorageException(
          'new row violates row-level security policy',
          statusCode: '403',
        );
      }
      final container = buildChatContainer(repository: repo, userId: userId);
      addTearDown(container.dispose);
      final convo = activeConversation(relId);
      repo.conversationOverride = convo;
      final controller = container.read(chatControllerProvider(convo).notifier);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final path = p.join(tempDir.path, 'slow.m4a');
      await File(path).writeAsBytes(List.filled(128, 1));
      ChatState read() => container.read(chatControllerProvider(convo));

      await controller.sendVoiceMessage(
        localPath: path,
        durationMs: 1500,
        waveform: const [1, 2, 3],
      );
      for (var attempt = 1; attempt < 5; attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(
          read().messages.single.status,
          MessageStatus.queued,
          reason: 'attempt $attempt of 5 must keep the clock',
        );
        await controller.flushOutbox(force: true);
      }
      await Future<void>.delayed(const Duration(milliseconds: 30));

      // Each attempt asked for its own upload intent (intent + upload).
      expect(repo.mediaCallCount, 10);
      expect(repo.sendCallCount, 0);
      expect(read().messages.single.status, MessageStatus.failed);
      expect(
        read().error,
        'That voice message could not be sent. Try recording it again.',
      );
    });

    test('a dead-cache direct send gets media-aware copy', () async {
      final repo = FakeChatRepository(currentUserId: userId)
        ..mediaCallFailures[2] = const StorageException(
          'Payload Too Large',
          statusCode: '413',
        );
      final backend = ScriptedCacheBackend()..failPutOutbox = (_, _) => true;
      final container = buildChatContainer(
        repository: repo,
        userId: userId,
        cache: ChatCacheService.forTesting(backend: backend),
      );
      addTearDown(container.dispose);
      final convo = activeConversation(relId);
      repo.conversationOverride = convo;
      final controller = container.read(chatControllerProvider(convo).notifier);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final path = p.join(tempDir.path, 'nodisk.m4a');
      await File(path).writeAsBytes(List.filled(128, 1));

      await controller.sendVoiceMessage(
        localPath: path,
        durationMs: 1500,
        waveform: const [1, 2, 3],
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final state = container.read(chatControllerProvider(convo));
      expect(repo.mediaCallCount, 2, reason: 'the direct attempt uploaded');
      expect(state.messages.single.status, MessageStatus.failed);
      expect(state.error, 'That voice message is too long to send.');
    });

    test('a rejected photo streak is worded as a photo', () async {
      final repo = FakeChatRepository(currentUserId: userId)
        ..mediaCallFailures[2] = const StorageException(
          'Unsupported Media Type',
          statusCode: '415',
        );
      final container = buildChatContainer(repository: repo, userId: userId);
      addTearDown(container.dispose);
      final convo = activeConversation(relId);
      repo.conversationOverride = convo;
      final controller = container.read(chatControllerProvider(convo).notifier);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final path = p.join(tempDir.path, 'streak.jpg');
      await File(path).writeAsBytes(List.filled(128, 1));

      await controller.sendStreakMessage(
        localPath: path,
        durationMs: 0,
        viewsRemaining: 1,
        mimeType: 'image/jpeg',
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final state = container.read(chatControllerProvider(convo));
      expect(state.messages.single.status, MessageStatus.failed);
      expect(state.error, 'That image could not be sent. Try a different one.');
    });
  });
}

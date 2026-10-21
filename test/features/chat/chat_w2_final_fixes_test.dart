// Wave 2 (chat media) final fix wave: controller-level pins for I2 (the
// video poster's intent is bounded), M7 (the keep-alive eviction has a
// ceiling, and an evicted in-flight send resumes from the outbox) and M8
// (a prepared file that is gone fails at once as a media rejection).
import 'dart:async';
import 'dart:io';

import 'package:attune/features/chat/config/chat_config.dart';
import 'package:attune/features/chat/data/cache/chat_cache_service.dart';
import 'package:attune/features/chat/data/cache/pending_send.dart';
import 'package:attune/features/chat/data/repositories/chat_media_uploader.dart';
import 'package:attune/features/chat/data/repositories/chat_repository.dart';
import 'package:attune/features/chat/domain/entities/message.dart';
import 'package:attune/features/chat/domain/services/chat_image_cache.dart';
import 'package:attune/features/chat/domain/services/chat_image_picker.dart';
import 'package:attune/features/chat/presentation/state/chat_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'support/chat_test_harness.dart';

class _FakePathProviderPlatform extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProviderPlatform(this.tempDir);
  final Directory tempDir;
  @override
  Future<String?> getTemporaryPath() async => tempDir.path;
  @override
  Future<String?> getApplicationSupportPath() async => tempDir.path;
}

/// The fake repository with the REAL streaming uploader behind its upload
/// (over a client that would answer 200), so what the uploader does with a
/// local file that is gone reaches the controller unchanged.
class _RealUploaderRepository extends FakeChatRepository {
  _RealUploaderRepository() : super(currentUserId: 'user-a');
  int uploadRequests = 0;

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
      clientFactory:
          () => MockClient((request) async {
            uploadRequests++;
            return http.Response('{}', 200);
          }),
    ).upload(
      bucket: intent.bucket,
      objectKey: intent.storageKey,
      localPath: localPath,
      mimeType: mimeType,
      cancelToken: cancelToken,
    );
  }
}

class _SlowDeleteRepository extends FakeChatRepository {
  _SlowDeleteRepository() : super(currentUserId: 'user-a');
  final Completer<void> deleteGate = Completer<void>();
  bool deleteStarted = false;

  @override
  Future<void> deleteMessage(String messageId) async {
    deleteStarted = true;
    await deleteGate.future;
    return super.deleteMessage(messageId);
  }
}

/// Polls [done] on real time (no fixed sleeps to race): fails the test if
/// it is not true within [within].
Future<void> _until(
  bool Function() done, {
  Duration within = const Duration(seconds: 5),
  String? reason,
}) async {
  final watch = Stopwatch()..start();
  while (!done()) {
    if (watch.elapsed > within) {
      fail('timed out waiting${reason == null ? '' : ': $reason'}');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

void main() {
  const userId = 'user-a';
  const relId = 'rel-1';
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('w2_final_fixes');
    PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir);
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  Future<String> file(String name, {int bytes = 128}) async {
    final path = p.join(tempDir.path, name);
    await File(path).writeAsBytes(List.filled(bytes, 1));
    return path;
  }

  group('I1: a sign-out staging wipe that was cut off', () {
    test('is finished when a chat next opens', () async {
      // A fresh launch: no pass from an earlier test is still in flight
      // for this one to join (the slot is process-wide).
      ChatImagePicker.debugForgetInFlightWipe();
      final old =
          File(p.join(tempDir.path, ChatImagePicker.folderName, 'pick_old.jpg'))
            ..createSync(recursive: true)
            ..writeAsBytesSync([1, 2, 3]);
      final marker = File(
        p.join(tempDir.path, ChatImagePicker.stagingWipeMarkerName),
      )..writeAsStringSync('');
      final repo = FakeChatRepository(currentUserId: userId);
      final container = buildChatContainer(repository: repo, userId: userId);
      addTearDown(container.dispose);
      final convo = activeConversation(relId);
      repo.conversationOverride = convo;
      await container.read(chatControllerProvider(convo).notifier).whenOpened;
      // The open starts the owed wipe unawaited, and the pass deletes the
      // folders BEFORE the marker: checking the marker the instant the file
      // was gone raced that last step and failed under suite load. Poll for
      // the finished pass (both gone), with headroom for a loaded machine.
      await _until(
        () => !old.existsSync() && !marker.existsSync(),
        within: const Duration(seconds: 20),
        reason: 'the owed wipe ran to completion',
      );
      expect(old.existsSync(), isFalse);
      expect(marker.existsSync(), isFalse);
    });
  });

  group('I2: the video poster intent is bounded', () {
    test('a black-holed poster intent fails within the bound; the video '
        'still sends and nothing holds the controller', () async {
      final repo = FakeChatRepository(currentUserId: userId);
      // Call 3 = the poster's createMediaUploadIntent; never answered.
      final hung = Completer<void>();
      repo.mediaCallGates[3] = hung;
      addTearDown(() {
        if (!hung.isCompleted) hung.complete();
      });
      final container = buildChatContainer(
        repository: repo,
        userId: userId,
        extraOverrides: [
          chatConfigProvider.overrideWithValue(
            const ChatConfig(networkTimeout: Duration(milliseconds: 150)),
          ),
        ],
      );
      addTearDown(container.dispose);
      final convo = activeConversation(relId);
      repo.conversationOverride = convo;
      final controller = container.read(chatControllerProvider(convo).notifier);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final videoPath = await file('clip.mp4');
      final posterPath = await file('clip_poster.jpg');
      final sending = controller.sendVideoMessage(
        localPath: videoPath,
        durationMs: 4200,
        thumbnailLocalPath: posterPath,
        width: 1280,
        height: 720,
      );
      await _until(
        () => repo.sendCallCount == 1,
        reason: 'the video insert after the poster intent timed out',
      );
      await _until(() => !controller.hasSendInFlight);
      await sending.timeout(const Duration(seconds: 2));

      final message =
          container.read(chatControllerProvider(convo)).messages.single;
      expect(message.status, MessageStatus.sent);
      expect(message.mediaThumbnailKey, isNull, reason: 'poster is optional');
      expect(repo.mediaCallCount, 3, reason: 'the poster upload never ran');
      expect(controller.hasSendInFlight, isFalse);
    });
  });

  group('M7: the keep-alive has a ceiling', () {
    test('a send in flight holds the controller only up to the ceiling; '
        'the evicted send resumes from the outbox on the next open', () async {
      final cache = ChatCacheService.forTesting(backend: memBackend());
      final repo = FakeChatRepository(currentUserId: userId)
        ..uploadGate = Completer<void>();
      final container = buildChatContainer(
        repository: repo,
        userId: userId,
        cache: cache,
        extraOverrides: [
          chatConfigProvider.overrideWithValue(
            const ChatConfig(
              controllerKeepAlive: Duration(milliseconds: 40),
              controllerKeepAliveCeiling: Duration(milliseconds: 300),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      final convo = activeConversation(relId);
      repo.conversationOverride = convo;
      final screen = container.listen(
        chatControllerProvider(convo),
        (_, __) {},
      );
      final controller = container.read(chatControllerProvider(convo).notifier);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      unawaited(
        controller.sendVoiceMessage(
          localPath: await file('held.m4a'),
          durationMs: 1000,
          waveform: const [1],
        ),
      );
      await _until(() => controller.hasSendInFlight);

      // The person leaves; the upload hangs past every keep-alive.
      final leftAt = DateTime.now();
      screen.close();
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(
        controller.mounted,
        isTrue,
        reason: 'below the ceiling a send in flight still holds it',
      );
      await _until(() => !controller.mounted, reason: 'evicted at the ceiling');
      expect(
        DateTime.now().difference(leftAt),
        greaterThanOrEqualTo(const Duration(milliseconds: 300)),
      );
      expect(controller.hasSendInFlight, isTrue, reason: 'evicted mid-send');
      // N3: the orphaned upload is stopped (its client closes on cancel),
      // not left to burn bandwidth beside the re-upload on the next open.
      expect(
        repo.lastUploadCancelToken?.isCancelled,
        isTrue,
        reason: 'eviction cancels the in-flight upload',
      );

      // The evicted send is durable: its queue row is still there.
      final rows = await cache.readOutbox(userId, relationshipId: relId);
      expect(rows, hasLength(1));
      expect(repo.sendCallCount, 0);

      // The hung upload finally answers into the disposed controller:
      // nothing is written from there.
      repo.uploadGate!.complete();
      repo.uploadGate = null;
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(repo.sendCallCount, 0);

      // Next open: the new controller resumes the send from the outbox.
      final reopened = container.listen(
        chatControllerProvider(convo),
        (_, __) {},
      );
      addTearDown(reopened.close);
      await _until(() => repo.sendCallCount == 1, reason: 'resumed on open');
      await _until(
        () => container
            .read(chatControllerProvider(convo))
            .messages
            .any((m) => m.status == MessageStatus.sent),
      );
      expect(
        await cache.readOutbox(userId, relationshipId: relId),
        isEmpty,
        reason: 'the resumed send landed and left the queue',
      );
    });

    test('an idle chat is still evicted after one keep-alive', () async {
      final repo = FakeChatRepository(currentUserId: userId);
      final container = buildChatContainer(
        repository: repo,
        userId: userId,
        extraOverrides: [
          chatConfigProvider.overrideWithValue(
            const ChatConfig(controllerKeepAlive: Duration(milliseconds: 40)),
          ),
        ],
      );
      addTearDown(container.dispose);
      final convo = activeConversation(relId);
      repo.conversationOverride = convo;
      final screen = container.listen(
        chatControllerProvider(convo),
        (_, __) {},
      );
      final controller = container.read(chatControllerProvider(convo).notifier);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      screen.close();
      await _until(() => !controller.mounted);
    });
  });

  group('N2: delete for everyone while the controller is disposed', () {
    test('a controller disposed during the server delete throws nothing',
        () async {
      final repo = _SlowDeleteRepository();
      final container = buildChatContainer(repository: repo, userId: userId);
      final convo = activeConversation(relId);
      repo.conversationOverride = convo;
      final controller = container.read(chatControllerProvider(convo).notifier);
      await controller.whenOpened;
      final message = Message(
        id: 'm-1',
        clientMessageId: 'cid-m-1',
        relationshipId: relId,
        senderId: userId,
        content: 'hi',
        createdAt: DateTime.now(),
        mediaKey: 'k/1.jpg',
        mediaType: 'image',
        status: MessageStatus.sent,
        isMine: true,
      );
      final pending = controller.deleteMessage(message);
      await _until(() => repo.deleteStarted);
      container.dispose();
      repo.deleteGate.complete();
      await pending; // StateError before the fix
    });
  });

  group('I3: removed and purged messages take their photo bytes along', () {
    Message media(
      String id, {
      required String sender,
      required String key,
      String? poster,
      String type = 'image',
    }) => Message(
      id: id,
      clientMessageId: 'cid-$id',
      relationshipId: relId,
      senderId: sender,
      content: '',
      createdAt: DateTime.now(),
      mediaKey: key,
      mediaType: type,
      mediaThumbnailKey: poster,
      status: MessageStatus.sent,
      isMine: sender == userId,
    );

    Future<(ChatController, ChatState Function(), FakeChatImageCache)> open(
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
      await controller.whenOpened;
      final images =
          container.read(chatImageCacheProvider) as FakeChatImageCache;
      return (
        controller,
        () => container.read(chatControllerProvider(convo)),
        images,
      );
    }

    test(
      'delete for everyone drops the video\'s poster and media entries',
      () async {
        final repo = FakeChatRepository(currentUserId: userId);
        repo.serverMessages['v1'] = media(
          'v1',
          sender: userId,
          key: 'chat-media/v1.mp4',
          poster: 'chat-media/v1.jpg',
          type: 'video',
        );
        final (controller, state, images) = await open(repo);
        final loaded = state().messages.single;
        await controller.deleteMessage(loaded);
        await _until(() => images.removals.isNotEmpty);
        expect(
          images.removedKeys,
          containsAll(['chat-media/v1.mp4', 'chat-media/v1.jpg']),
        );
      },
    );

    test(
      'a partner\'s delete arriving by realtime drops the loaded photo',
      () async {
        final repo = FakeChatRepository(currentUserId: userId);
        repo.serverMessages['p1'] = media(
          'p1',
          sender: 'user-b',
          key: 'chat-media/p1.jpg',
        );
        final (controller, state, images) = await open(repo);
        expect(state().messages.single.mediaKey, 'chat-media/p1.jpg');
        // The server's tombstone carries no media key any more.
        repo.serverMessages['p1'] = Message(
          id: 'p1',
          clientMessageId: 'cid-p1',
          relationshipId: relId,
          senderId: 'user-b',
          content: '',
          createdAt: DateTime.now(),
          deletedAt: DateTime.now(),
          status: MessageStatus.sent,
          isMine: false,
        );
        await controller.refreshMessagesByIds({'p1'});
        await _until(() => images.removals.isNotEmpty);
        expect(images.removedKeys, contains('chat-media/p1.jpg'));
      },
    );

    test('a purge drops every photo it knows, loaded or only cached', () async {
      final cache = ChatCacheService.forTesting(backend: memBackend());
      final repo = FakeChatRepository(currentUserId: userId);
      final cachedOnly = media(
        'old',
        sender: 'user-b',
        key: 'chat-media/old.jpg',
      );
      final loaded = media('n1', sender: userId, key: 'chat-media/n1.jpg');
      repo.serverMessages['n1'] = loaded;
      final (controller, state, images) = await open(repo, cache: cache);
      await cache.writeMessages(userId, relId, [loaded, cachedOnly]);
      controller.debugSetMessages([state().messages.single]);

      await controller.debugHandleAccountChange(userId);

      expect(
        images.removedKeys,
        containsAll(['chat-media/n1.jpg', 'chat-media/old.jpg']),
      );
    });
  });

  group('M8: a prepared file that is gone at upload', () {
    test('fails at once as a media rejection with the media copy', () async {
      final cache = ChatCacheService.forTesting(backend: memBackend());
      final repo = _RealUploaderRepository()..intentGate = Completer<void>();
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

      unawaited(
        controller.sendVoiceMessage(
          localPath: await file('swept.m4a'),
          durationMs: 1000,
          waveform: const [1],
        ),
      );
      await _until(() => repo.mediaCallCount == 1);
      // The upload file disappears while the slot is being requested.
      final row =
          (await cache.readOutbox(userId, relationshipId: relId)).single;
      await File(row.localMediaPath!).delete();
      repo.intentGate!.complete();

      await _until(
        () =>
            container
                .read(chatControllerProvider(convo))
                .messages
                .single
                .status ==
            MessageStatus.failed,
        reason: 'failed at once, not retried five times',
      );
      final state = container.read(chatControllerProvider(convo));
      expect(
        state.error,
        'That voice message could not be sent. Try recording it again.',
      );
      final parked =
          (await cache.readOutbox(userId, relationshipId: relId)).single;
      expect(parked.state, PendingSendState.failedPermanent);
      expect(parked.attempts, 1);
      expect(parked.lastErrorCategory, 'mediaRejected');
      expect(repo.uploadRequests, 0);
      expect(repo.sendCallCount, 0);
    });
  });
}

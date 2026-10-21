import 'dart:io';

import 'package:attune/features/chat/data/cache/chat_cache_service.dart';
import 'package:attune/features/chat/domain/entities/message.dart';
import 'package:attune/features/chat/domain/services/chat_image_picker.dart';
import 'package:attune/features/chat/presentation/state/chat_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
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
  Future<String?> getApplicationDocumentsPath() async =>
      p.join(tempDir.path, 'Documents');
  // Picks are staged (and owned, ChatImagePicker.ownsPath) under
  // Application Support/chat_picks.
  @override
  Future<String?> getApplicationSupportPath() async => tempDir.path;
}

void main() {
  const userId = 'user-a';
  const relId = 'rel-1';
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('pick_cleanup');
    PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir);
  });
  tearDown(() => tempDir.delete(recursive: true));

  Future<String> stagePick(String name, List<int> bytes) async {
    final f = File(p.join(tempDir.path, ChatImagePicker.folderName, name))
      ..createSync(recursive: true);
    await f.writeAsBytes(bytes);
    return f.path;
  }

  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 400));

  test(
    'the staged pick is deleted once the prepared file exists; nothing lands in Documents',
    () async {
      final repo = FakeChatRepository(currentUserId: userId);
      final container = buildChatContainer(repository: repo, userId: userId);
      addTearDown(container.dispose);
      final convo = activeConversation(relId);
      repo.conversationOverride = convo;
      final controller = container.read(chatControllerProvider(convo).notifier);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final raw = await stagePick(
        'pick_1.jpg',
        img.encodeJpg(img.Image(width: 64, height: 48)),
      );

      await controller.sendImageMessage(localPath: raw);
      await settle();

      final sent =
          container.read(chatControllerProvider(convo)).messages.single;
      expect(sent.status, MessageStatus.sent);
      expect(File(raw).existsSync(), isFalse, reason: 'raw pick discarded');
      expect(
        Directory(p.join(tempDir.path, 'Documents')).existsSync(),
        isFalse,
        reason: 'no Documents/shop_images copy',
      );
      expect(repo.mediaCallCount, 2, reason: 'one intent, one upload');
    },
  );

  test(
    'a pick that fails preparation is kept for retry and deleted on remove',
    () async {
      final repo = FakeChatRepository(currentUserId: userId);
      final container = buildChatContainer(repository: repo, userId: userId);
      addTearDown(container.dispose);
      final convo = activeConversation(relId);
      repo.conversationOverride = convo;
      final controller = container.read(chatControllerProvider(convo).notifier);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final raw = await stagePick('pick_2.jpg', 'not an image'.codeUnits);
      await controller.sendImageMessage(localPath: raw);
      await settle();

      final failed =
          container.read(chatControllerProvider(convo)).messages.single;
      expect(failed.status, MessageStatus.failed);
      expect(File(raw).existsSync(), isTrue, reason: 'retry needs the source');

      await controller.removeFailedMessage(failed);
      expect(File(raw).existsSync(), isFalse);
      expect(container.read(chatControllerProvider(convo)).messages, isEmpty);
    },
  );

  test(
    'an account change purging a held pick deletes the staged source',
    () async {
      // The purge drops the outbox row; a raw pick it leaves behind would be
      // the previous account's photo left on disk with nothing pointing at
      // it (#27).
      final repo = FakeChatRepository(currentUserId: userId);
      final container = buildChatContainer(repository: repo, userId: userId);
      addTearDown(container.dispose);
      final convo = activeConversation(relId);
      repo.conversationOverride = convo;
      final controller = container.read(chatControllerProvider(convo).notifier);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final raw = await stagePick('pick_3.jpg', 'not an image'.codeUnits);
      await controller.sendImageMessage(localPath: raw);
      await settle();
      expect(File(raw).existsSync(), isTrue, reason: 'held for retry');

      await controller.debugHandleAccountChange(userId);
      await settle();
      expect(File(raw).existsSync(), isFalse);
    },
  );

  test('a held pick with no queue row (dead cache) is deleted by an account '
      'change too', () async {
    // The outbox could not be written, so the only copy is in memory
    // (_unsavedSends). Clearing that on a purge must take the staged
    // source with it.
    final repo = FakeChatRepository(currentUserId: userId);
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

    final raw = await stagePick(
      'pick_4.jpg',
      img.encodeJpg(img.Image(width: 64, height: 48)),
    );
    await controller.sendImageMessage(localPath: raw);
    await settle();
    expect(
      container.read(chatControllerProvider(convo)).messages.single.status,
      MessageStatus.failed,
    );
    expect(File(raw).existsSync(), isTrue, reason: 'held for Retry');

    await controller.debugHandleAccountChange(userId);
    await settle();
    expect(File(raw).existsSync(), isFalse);
  });

  test('a path chat does not own (place photo) is never deleted', () async {
    final repo = FakeChatRepository(currentUserId: userId);
    final container = buildChatContainer(repository: repo, userId: userId);
    addTearDown(container.dispose);
    final convo = activeConversation(relId);
    repo.conversationOverride = convo;
    final controller = container.read(chatControllerProvider(convo).notifier);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    final foreign =
        File(p.join(tempDir.path, 'places', 'photo.jpg'))
          ..createSync(recursive: true)
          ..writeAsBytesSync(img.encodeJpg(img.Image(width: 32, height: 32)));

    await controller.sendImageMessage(localPath: foreign.path);
    await settle();

    expect(foreign.existsSync(), isTrue);
  });
}

import 'dart:io';

import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:attune/features/chat/data/cache/chat_cache_service.dart';
import 'package:attune/features/chat/data/cache/pending_send.dart';
import 'package:attune/features/chat/domain/services/chat_image_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
// Transitive through image_picker (1.2.1 pins 2.11.1); faking the platform
// is the only way to drive a pick, and the plan adds no pub dependencies.
// ignore: depend_on_referenced_packages
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;

import 'support/chat_test_harness.dart';

class _PickerPlatform extends ImagePickerPlatform
    with MockPlatformInterfaceMixin {
  _PickerPlatform(this.sourcePath);
  final String sourcePath;

  @override
  Future<XFile?> getImageFromSource({
    required ImageSource source,
    ImagePickerOptions options = const ImagePickerOptions(),
  }) async => XFile(sourcePath);
}

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this.root);
  final Directory root;
  @override
  Future<String?> getTemporaryPath() async => p.join(root.path, 'tmp');
  @override
  Future<String?> getApplicationSupportPath() async =>
      p.join(root.path, 'support');
}

/// The 7-day sweep deletes only what no queue row still needs: a photo
/// queued (or failed and waiting for Retry) for longer than a week must
/// still send.
void main() {
  const userId = 'user-a';
  late Directory root;
  late Directory picks;
  late Directory prepared;
  late File queuedSource;
  late File queuedUpload;
  late File queuedPoster;
  late File orphanPick;
  late File orphanUpload;

  final old = DateTime.now().subtract(const Duration(days: 9));

  File seed(Directory dir, String name) =>
      File(p.join(dir.path, name))
        ..createSync(recursive: true)
        ..writeAsBytesSync([1, 2, 3])
        ..setLastModifiedSync(old);

  setUp(() {
    root = Directory.systemTemp.createTempSync('pick_sweep');
    PathProviderPlatform.instance = _FakePathProvider(root);
    picks = Directory(p.join(root.path, 'support', ChatImagePicker.folderName));
    prepared = Directory(
      p.join(root.path, 'support', ChatImagePicker.preparedFolderName),
    );
    queuedSource = seed(picks, 'pick_queued.jpg');
    queuedUpload = seed(prepared, 'chat_media_queued.jpg');
    queuedPoster = seed(prepared, 'chat_media_poster.jpg');
    orphanPick = seed(picks, 'pick_orphan.jpg');
    orphanUpload = seed(prepared, 'chat_media_orphan.jpg');
    final plugin =
        File(p.join(root.path, 'plugin', 'image_picker_1.jpg'))
          ..createSync(recursive: true)
          ..writeAsBytesSync([0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3, 4]);
    ImagePickerPlatform.instance = _PickerPlatform(plugin.path);
  });
  tearDown(() => root.deleteSync(recursive: true));

  PendingSend row(
    String id,
    String relationshipId, {
    String? media,
    String? poster,
    bool raw = false,
  }) => PendingSend(
    clientMessageId: id,
    relationshipId: relationshipId,
    senderId: userId,
    text: '',
    localMediaPath: media,
    mediaMimeType: 'image/jpeg',
    mediaType: 'image',
    localThumbnailPath: poster,
    requiresPreparation: raw,
    createdAt: old,
  );

  Future<ProviderContainer> containerWith({
    required ChatCacheService cache,
    User? user,
    bool signedOut = false,
  }) async {
    final container = buildChatContainer(
      repository: FakeChatRepository(currentUserId: userId),
      userId: userId,
      cache: cache,
      extraOverrides: [
        if (signedOut) currentUserProvider.overrideWithValue(null),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('files a queue row still references survive; unreferenced old ones '
      'go', () async {
    final cache = ChatCacheService.forTesting(backend: ScriptedCacheBackend());
    // Two relationships of the signed-in user: the sweep is per user.
    await cache.putOutbox(
      userId,
      row('a', 'rel-1', media: queuedSource.path, raw: true),
    );
    await cache.putOutbox(
      userId,
      row('b', 'rel-2', media: queuedUpload.path, poster: queuedPoster.path),
    );
    final container = await containerWith(cache: cache);

    final picked =
        await container.read(chatImagePickerProvider).pickFromGallery();

    expect(picked, isNotNull);
    expect(queuedSource.existsSync(), isTrue, reason: 'raw source, rel-1');
    expect(queuedUpload.existsSync(), isTrue, reason: 'prepared, rel-2');
    expect(queuedPoster.existsSync(), isTrue, reason: 'poster path');
    expect(orphanPick.existsSync(), isFalse);
    expect(orphanUpload.existsSync(), isFalse);
  });

  test('an unreadable outbox deletes nothing', () async {
    final backend = ScriptedCacheBackend();
    final cache = ChatCacheService.forTesting(backend: backend);
    backend.armReadOutboxFailures((_) => true);
    final container = await containerWith(cache: cache);

    expect(
      await container.read(chatImagePickerProvider).pickFromGallery(),
      isNotNull,
      reason: 'the pick itself still works',
    );
    for (final f in [orphanPick, orphanUpload, queuedSource, queuedUpload]) {
      expect(f.existsSync(), isTrue, reason: f.path);
    }
  });

  test('an outbox with no cache key this session deletes nothing', () async {
    // Rows written under a key this session cannot read are skipped by
    // readOutbox; "none readable" must not read as "none queued".
    final backend = ScriptedCacheBackend();
    await ChatCacheService.forTesting(
      backend: backend,
    ).putOutbox(userId, row('a', 'rel-1', media: queuedSource.path));
    final container = await containerWith(
      cache: ChatCacheService.forTesting(backend: backend, withoutCipher: true),
    );

    await container.read(chatImagePickerProvider).pickFromGallery();

    expect(orphanPick.existsSync(), isTrue);
    expect(queuedSource.existsSync(), isTrue);
  });

  test('with nobody signed in the sweep is skipped', () async {
    final cache = ChatCacheService.forTesting(backend: ScriptedCacheBackend());
    final container = await containerWith(cache: cache, signedOut: true);

    await container.read(chatImagePickerProvider).pickFromGallery();

    expect(orphanPick.existsSync(), isTrue);
    expect(orphanUpload.existsSync(), isTrue);
  });

  test('a picker built without an outbox view never sweeps', () async {
    await ChatImagePicker(
      stagingDirectory: () async => Directory(p.join(root.path, 'support')),
    ).pickFromGallery();
    expect(orphanPick.existsSync(), isTrue);
    expect(orphanUpload.existsSync(), isTrue);
  });
}

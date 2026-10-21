import 'dart:io';

import 'package:attune/features/chat/data/cache/chat_cache_service.dart';
import 'package:attune/features/chat/data/cache/pending_send.dart';
import 'package:attune/features/chat/data/repositories/chat_media_uploader.dart';
import 'package:attune/features/chat/data/repositories/chat_repository.dart';
import 'package:attune/features/chat/domain/entities/conversation.dart';
import 'package:attune/features/chat/domain/entities/message.dart';
import 'package:attune/features/chat/domain/services/chat_image_picker.dart';
import 'package:attune/features/chat/domain/services/chat_poster_prewarmer.dart';
import 'package:attune/features/chat/presentation/state/chat_state.dart';
import 'package:file/file.dart' as file_system;
import 'package:file/local.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show StorageException;

import 'support/chat_test_harness.dart';

/// OS temp (purgeable) and Application Support (durable) as separate roots.
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

/// The real repository streams the file from disk; a missing one fails the
/// upload. The fake does not read files, so check like the real one would.
class _FileReadingRepository extends FakeChatRepository {
  _FileReadingRepository() : super(currentUserId: 'user-a');
  final uploadedPaths = <String>[];

  @override
  Future<void> uploadChatMedia({
    required ChatMediaUploadIntent intent,
    required String localPath,
    required String mimeType,
    void Function(double fraction)? onProgress,
    ChatUploadCancelToken? cancelToken,
  }) async {
    if (!File(localPath).existsSync()) {
      throw FileSystemException('upload source missing', localPath);
    }
    uploadedPaths.add(localPath);
    await super.uploadChatMedia(
      intent: intent,
      localPath: localPath,
      mimeType: mimeType,
      onProgress: onProgress,
      cancelToken: cancelToken,
    );
  }
}

/// Lets acknowledgement promote the prepared file into the media cache (the
/// harness default cache always fails, which keeps staging by design).
class _CopyingCacheManager implements BaseCacheManager {
  _CopyingCacheManager(this.dir);
  final Directory dir;

  @override
  Future<FileInfo?> getFileFromCache(
    String key, {
    bool ignoreMemCache = false,
  }) async => null;

  @override
  Future<file_system.File> putFileStream(
    String url,
    Stream<List<int>> source, {
    String? key,
    String? eTag,
    Duration maxAge = const Duration(days: 30),
    String fileExtension = 'file',
  }) async {
    final target = const LocalFileSystem().file(
      p.join(dir.path, 'cached.$fileExtension'),
    );
    await target.create(recursive: true);
    final sink = target.openWrite();
    await sink.addStream(source);
    await sink.close();
    return target;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not used');
}

void main() {
  const userId = 'user-a';
  const relId = 'rel-1';
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('prepared_durable');
    PathProviderPlatform.instance = _FakePathProvider(root);
    // The OS temp dir always exists on a device.
    Directory(p.join(root.path, 'tmp')).createSync();
  });
  tearDown(() => root.delete(recursive: true));

  String preparedDir() =>
      p.join(root.path, 'support', ChatImagePicker.preparedFolderName);

  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 400));

  Future<({ChatController controller, _Booted container, String raw})> boot(
    _FileReadingRepository repo, {
    bool promote = false,
  }) async {
    final container = buildChatContainer(
      repository: repo,
      userId: userId,
      extraOverrides: [
        if (promote)
          chatPosterPrewarmerProvider.overrideWithValue(
            ChatPosterPrewarmer(
              repository: repo,
              cacheManager: _CopyingCacheManager(
                Directory(p.join(root.path, 'media_cache')),
              ),
            ),
          ),
      ],
    );
    addTearDown(container.dispose);
    final convo = activeConversation(relId);
    repo.conversationOverride = convo;
    final controller = container.read(chatControllerProvider(convo).notifier);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final raw = File(
      p.join(root.path, 'support', ChatImagePicker.folderName, 'pick_1.jpg'),
    )..createSync(recursive: true);
    raw.writeAsBytesSync(img.encodeJpg(img.Image(width: 64, height: 48)));
    return (
      controller: controller,
      container: _Booted(container, convo),
      raw: raw.path,
    );
  }

  test('a prepared photo survives a temp-dir wipe and still uploads', () async {
    final repo = _FileReadingRepository();
    // Call 2 is the image's upload: offline the first time.
    repo.mediaCallFailures[2] = const SocketException('offline');
    final b = await boot(repo);

    await b.controller.sendImageMessage(localPath: b.raw);
    await settle();
    final row = (await b.container.outbox()).single;
    expect(row.requiresPreparation, isFalse);
    expect(
      p.dirname(row.localMediaPath!),
      preparedDir(),
      reason: 'the upload source lives in Application Support',
    );
    expect(ChatImagePicker.ownsPath(row.localMediaPath), isTrue);

    // The OS empties temp/cache while the phone is offline for days.
    final tmp = Directory(p.join(root.path, 'tmp'));
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);

    await b.controller.flushOutbox(force: true);
    await settle();

    expect(b.container.messages.single.status, MessageStatus.sent);
    expect(
      repo.uploadedPaths,
      [row.localMediaPath, row.localMediaPath],
      reason: 'the retry reuses the same prepared file, found on disk',
    );
  });

  test(
    'the prepared file is deleted once the upload is acknowledged',
    () async {
      final repo = _FileReadingRepository();
      final b = await boot(repo, promote: true);

      await b.controller.sendImageMessage(localPath: b.raw);
      await settle();

      expect(b.container.messages.single.status, MessageStatus.sent);
      expect(repo.uploadedPaths, hasLength(1));
      expect(File(repo.uploadedPaths.single).existsSync(), isFalse);
      expect(Directory(preparedDir()).listSync(), isEmpty);
    },
  );

  test('the prepared file goes with a removed failed message', () async {
    final repo = _FileReadingRepository();
    repo.mediaCallFailures[2] = const StorageException(
      'mime rejected',
      statusCode: '415',
    );
    final b = await boot(repo);

    await b.controller.sendImageMessage(localPath: b.raw);
    await settle();
    final failed = b.container.messages.single;
    expect(failed.status, MessageStatus.failed);
    final prepared = Directory(preparedDir()).listSync().single.path;

    await b.controller.removeFailedMessage(failed);

    expect(File(prepared).existsSync(), isFalse);
  });

  test('a purge deletes a queued prepared file', () async {
    final repo = _FileReadingRepository();
    repo.mediaCallFailures[2] = const SocketException('offline');
    final b = await boot(repo);

    await b.controller.sendImageMessage(localPath: b.raw);
    await settle();
    final prepared = Directory(preparedDir()).listSync().single.path;

    await b.controller.debugHandleAccountChange(userId);
    await settle();

    expect(File(prepared).existsSync(), isFalse);
  });
}

/// Small read helpers over the container for this file's tests.
class _Booted {
  _Booted(this.container, this.conversation);
  final ProviderContainer container;
  final Conversation conversation;

  List<Message> get messages =>
      container.read(chatControllerProvider(conversation)).messages;

  Future<List<PendingSend>> outbox() => container
      .read(chatCacheServiceProvider)
      .readOutbox('user-a', relationshipId: 'rel-1');
}

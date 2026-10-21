import 'dart:io';

import 'package:attune/features/chat/domain/services/chat_image_picker.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_test/flutter_test.dart';
// Transitive through image_picker (1.2.1 pins 2.11.1); faking the platform
// is the only way to see the options the plugin itself receives, and the
// plan adds no pub dependencies.
// ignore: depend_on_referenced_packages
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// Records the options the picker was asked for and hands back [sourcePath]
/// the way the real plugin hands back its own temp copy.
class _RecordingPickerPlatform extends ImagePickerPlatform
    with MockPlatformInterfaceMixin {
  _RecordingPickerPlatform(this.sourcePath);
  final String? sourcePath;
  ImageSource? source;
  ImagePickerOptions? options;

  @override
  Future<XFile?> getImageFromSource({
    required ImageSource source,
    ImagePickerOptions options = const ImagePickerOptions(),
  }) async {
    this.source = source;
    this.options = options;
    final path = sourcePath;
    return path == null ? null : XFile(path);
  }
}

class _ThrowingPickerPlatform extends ImagePickerPlatform
    with MockPlatformInterfaceMixin {
  _ThrowingPickerPlatform(this.error);
  final Object error;

  @override
  Future<XFile?> getImageFromSource({
    required ImageSource source,
    ImagePickerOptions options = const ImagePickerOptions(),
  }) async => throw error;
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
  @override
  Future<String?> getApplicationCachePath() async => p.join(root.path, 'cache');
}

void main() {
  late Directory tmp;
  late Directory pluginTmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('chat_pick_app_tmp');
    pluginTmp = await Directory.systemTemp.createTemp('chat_pick_plugin');
  });
  tearDown(() async {
    await tmp.delete(recursive: true);
    if (await pluginTmp.exists()) await pluginTmp.delete(recursive: true);
  });

  Future<String> writePluginFile() async {
    final f = File(p.join(pluginTmp.path, 'image_picker_ABC.jpg'));
    // A JPEG signature: the pick goes to the preparer as-is (a HEIC would be
    // converted first — chat_image_pick_heic_test).
    await f.writeAsBytes([
      0xFF,
      0xD8,
      0xFF,
      0xE0,
      ...List<int>.filled(4092, 7),
    ]);
    return f.path;
  }

  test(
    'asks the OS picker for the ORIGINAL bytes (no resize, no quality)',
    () async {
      final platform = _RecordingPickerPlatform(await writePluginFile());
      ImagePickerPlatform.instance = platform;
      final picker = ChatImagePicker(stagingDirectory: () async => tmp);

      final path = await picker.pickFromGallery();

      expect(path, isNotNull);
      expect(platform.source, ImageSource.gallery);
      expect(
        platform.options!.maxWidth,
        isNull,
        reason: 'any maxWidth re-encodes in the plugin before the preparer',
      );
      expect(platform.options!.maxHeight, isNull);
      expect(
        platform.options!.imageQuality,
        isNull,
        reason:
            'Android: any quality turns the plugin resizer on; the '
            'untouched original goes to the preparer',
      );
      expect(
        platform.options!.requestFullMetadata,
        isFalse,
        reason: 'the preparer strips EXIF anyway; do not ask iOS for it',
      );
    },
  );

  test(
    'on iOS the plugin re-encodes anyway: ask for 92, never a size',
    () async {
      // image_picker_ios always passes the pick through UIImage ->
      // UIImageJPEGRepresentation (HEIC included), at quality 1.0 when none
      // is given — a 24 MP shot then lands near the preparer's 25 MB source
      // cap. 92 is visually lossless at the 1600 px output and a third of
      // the bytes; dimensions stay untouched.
      final platform = _RecordingPickerPlatform(await writePluginFile());
      ImagePickerPlatform.instance = platform;
      final picker = ChatImagePicker(
        stagingDirectory: () async => tmp,
        isIOS: true,
      );
      await picker.pickFromGallery();
      expect(platform.options!.imageQuality, 92);
      expect(platform.options!.maxWidth, isNull);
      expect(platform.options!.maxHeight, isNull);
    },
  );

  test('stages the pick under <staging>/chat_picks and nowhere else', () async {
    final pluginPath = await writePluginFile();
    ImagePickerPlatform.instance = _RecordingPickerPlatform(pluginPath);
    final picker = ChatImagePicker(stagingDirectory: () async => tmp);

    final path = (await picker.pickFromGallery())!;

    expect(p.dirname(path), p.join(tmp.path, ChatImagePicker.folderName));
    expect(File(path).lengthSync(), 4096, reason: 'bytes untouched');
    expect(
      File(pluginPath).existsSync(),
      isFalse,
      reason: 'the plugin temp copy is removed once staged',
    );
    expect(
      tmp.listSync().map((e) => p.basename(e.path)).toList(),
      [ChatImagePicker.folderName],
      reason: 'no shop_images or other folder is created',
    );
    expect(ChatImagePicker.ownsPath(path), isTrue);
    expect(
      ChatImagePicker.ownsPath('/var/mobile/Documents/shop_images/1.jpg'),
      isFalse,
    );
  });

  test('a cancelled pick returns null and writes nothing', () async {
    ImagePickerPlatform.instance = _RecordingPickerPlatform(null);
    final picker = ChatImagePicker(stagingDirectory: () async => tmp);
    expect(await picker.pickFromGallery(), isNull);
    expect(tmp.listSync(), isEmpty);
  });

  test('discard deletes only chat-owned picks', () async {
    // The staging root is learned when a picker resolves it (production:
    // Application Support, also resolved by discard itself).
    await ChatImagePicker(
      stagingDirectory: () async => tmp,
    ).preparedDirectory();
    final owned = File(p.join(tmp.path, ChatImagePicker.folderName, 'a.jpg'))
      ..createSync(recursive: true);
    final foreign = File(p.join(tmp.path, 'other', 'b.jpg'))
      ..createSync(recursive: true);
    await ChatImagePicker.discard(owned.path);
    await ChatImagePicker.discard(foreign.path);
    await ChatImagePicker.discard(null);
    expect(owned.existsSync(), isFalse);
    expect(foreign.existsSync(), isTrue);
  });

  group('ownsPath is rooted in the two staging folders', () {
    late String picks;
    late String prepared;
    setUp(() async {
      final picker = ChatImagePicker(stagingDirectory: () async => tmp);
      prepared = (await picker.preparedDirectory()).path;
      picks = p.join(tmp.path, ChatImagePicker.folderName);
    });

    test('a file directly in either folder is owned', () {
      expect(ChatImagePicker.ownsPath(p.join(picks, 'pick_1.jpg')), isTrue);
      expect(
        ChatImagePicker.ownsPath(p.join(prepared, 'chat_media_1.jpg')),
        isTrue,
      );
    });

    test('traversal, nesting, relative paths and the folders themselves are '
        'not', () {
      for (final path in [
        p.join(picks, '..', '..', 'etc', 'passwd'),
        // Resolves back inside, but a path that climbs is never trusted.
        p.join(picks, '..', ChatImagePicker.folderName, 'pick_1.jpg'),
        p.join(picks, 'nested', 'pick_1.jpg'),
        p.join(ChatImagePicker.folderName, 'pick_1.jpg'),
        picks,
        prepared,
        '',
      ]) {
        expect(ChatImagePicker.ownsPath(path), isFalse, reason: path);
      }
    });

    test(
      'a foreign folder that happens to be called chat_picks is not owned',
      () async {
        final foreign = File(
          p.join(pluginTmp.path, 'Photos', ChatImagePicker.folderName, 'a.jpg'),
        )..createSync(recursive: true);
        expect(ChatImagePicker.ownsPath(foreign.path), isFalse);
        await ChatImagePicker.discard(foreign.path);
        expect(foreign.existsSync(), isTrue);
      },
    );
  });

  group('a pick that cannot be staged is a plain error, never a crash', () {
    Matcher failsWith(ChatImagePickFailure failure) => throwsA(
      isA<ChatImagePickException>().having(
        (e) => e.failure,
        'failure',
        failure,
      ),
    );

    test('a second tap while the system picker is opening is silent', () async {
      ImagePickerPlatform.instance = _ThrowingPickerPlatform(
        PlatformException(code: 'already_active'),
      );
      final picker = ChatImagePicker(stagingDirectory: () async => tmp);
      expect(await picker.pickFromGallery(), isNull);
      expect(tmp.listSync(), isEmpty);
    });

    test('no photo access says so', () async {
      ImagePickerPlatform.instance = _ThrowingPickerPlatform(
        PlatformException(code: 'photo_access_denied'),
      );
      final picker = ChatImagePicker(stagingDirectory: () async => tmp);
      await expectLater(
        picker.pickFromGallery(),
        failsWith(ChatImagePickFailure.accessDenied),
      );
    });

    test('any other plugin error is "unreadable"', () async {
      for (final error in [
        PlatformException(code: 'invalid_image'),
        StateError('channel gone'),
      ]) {
        ImagePickerPlatform.instance = _ThrowingPickerPlatform(error);
        final picker = ChatImagePicker(stagingDirectory: () async => tmp);
        await expectLater(
          picker.pickFromGallery(),
          failsWith(ChatImagePickFailure.unreadable),
        );
      }
    });

    test(
      'a copy that fails (file gone, disk full) leaves nothing staged',
      () async {
        ImagePickerPlatform.instance = _RecordingPickerPlatform(
          p.join(pluginTmp.path, 'vanished.jpg'),
        );
        final picker = ChatImagePicker(stagingDirectory: () async => tmp);
        await expectLater(
          picker.pickFromGallery(),
          failsWith(ChatImagePickFailure.unreadable),
        );
        final staged = Directory(p.join(tmp.path, ChatImagePicker.folderName));
        expect(staged.existsSync() ? staged.listSync() : const [], isEmpty);
      },
    );

    test('an empty pick is unreadable and deleted, plugin copy too', () async {
      final empty = File(p.join(pluginTmp.path, 'empty.jpg'))..createSync();
      ImagePickerPlatform.instance = _RecordingPickerPlatform(empty.path);
      final picker = ChatImagePicker(stagingDirectory: () async => tmp);
      await expectLater(
        picker.pickFromGallery(),
        failsWith(ChatImagePickFailure.unreadable),
      );
      expect(
        Directory(p.join(tmp.path, ChatImagePicker.folderName)).listSync(),
        isEmpty,
      );
      expect(empty.existsSync(), isFalse);
    });
  });

  test(
    'picks are staged in Application Support, not the purgeable temp dir',
    () async {
      final previous = PathProviderPlatform.instance;
      PathProviderPlatform.instance = _FakePathProvider(tmp);
      addTearDown(() => PathProviderPlatform.instance = previous);
      ImagePickerPlatform.instance = _RecordingPickerPlatform(
        await writePluginFile(),
      );

      final path = (await ChatImagePicker().pickFromGallery())!;

      expect(
        p.dirname(path),
        p.join(tmp.path, 'support', ChatImagePicker.folderName),
      );
      expect(Directory(p.join(tmp.path, 'tmp')).existsSync(), isFalse);
      expect(ChatImagePicker.ownsPath(path), isTrue);
    },
  );

  test(
    'a pick sweeps staged picks and uploads older than a week, nothing newer',
    () async {
      final now = DateTime(2026, 10, 19, 12);
      final dir = Directory(p.join(tmp.path, ChatImagePicker.folderName))
        ..createSync(recursive: true);
      final orphan =
          File(p.join(dir.path, 'pick_old.jpg'))
            ..writeAsBytesSync([1])
            ..setLastModifiedSync(now.subtract(const Duration(days: 8)));
      final preparedDir = Directory(
        p.join(tmp.path, ChatImagePicker.preparedFolderName),
      )..createSync(recursive: true);
      final oldUpload =
          File(p.join(preparedDir.path, 'chat_media_1.jpg'))
            ..writeAsBytesSync([1])
            ..setLastModifiedSync(now.subtract(const Duration(days: 8)));
      final queuedUpload =
          File(p.join(preparedDir.path, 'chat_media_2.jpg'))
            ..writeAsBytesSync([1])
            ..setLastModifiedSync(now.subtract(const Duration(days: 2)));
      final waiting =
          File(p.join(dir.path, 'pick_recent.jpg'))
            ..writeAsBytesSync([1])
            ..setLastModifiedSync(now.subtract(const Duration(days: 2)));
      ImagePickerPlatform.instance = _RecordingPickerPlatform(
        await writePluginFile(),
      );
      final picker = ChatImagePicker(
        stagingDirectory: () async => tmp,
        clock: () => now,
        // Nothing queued (outbox-aware rules: chat_image_pick_sweep_test).
        referencedPaths: () async => <String>{},
      );

      final path = (await picker.pickFromGallery())!;

      expect(orphan.existsSync(), isFalse);
      expect(waiting.existsSync(), isTrue);
      expect(
        oldUpload.existsSync(),
        isFalse,
        reason: 'chat_prepared swept too',
      );
      expect(queuedUpload.existsSync(), isTrue);
      expect(ChatImagePicker.ownsPath(queuedUpload.path), isTrue);
      expect(File(path).existsSync(), isTrue);
    },
  );

  test('ChatScreen no longer routes photos through ImagePickerService', () {
    // Source guard in the repo's existing style (voice_signed_url_freshness_test):
    // the generic picker re-encodes at 1024/q85, crops, then compresses to a
    // 500 px short edge, so ChatImagePreparer's 1600 long edge was unreachable.
    final screen =
        File(
          'lib/features/chat/presentation/screens/chat_screen.dart',
        ).readAsStringSync();
    expect(screen, isNot(contains('_imagePicker.pickImage(')));
    expect(screen, isNot(contains('crop: true')));
    expect(screen, contains('chatImagePickerProvider'));
  });
}

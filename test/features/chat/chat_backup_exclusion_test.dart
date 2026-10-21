import 'dart:io';

import 'package:attune/core/services/storage/backup_exclusion.dart';
import 'package:attune/features/chat/data/cache/chat_cache_backend_io.dart'
    as io;
import 'package:attune/features/chat/domain/services/chat_image_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
// Transitive through image_picker (1.2.1 pins 2.11.1); faking the platform
// is the only way to drive a pick, and the plan adds no pub dependencies.
// ignore: depend_on_referenced_packages
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

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

class _SupportDirectory extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _SupportDirectory(this.path);
  final String path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
  @override
  Future<String?> getTemporaryPath() async => path;
}

/// Application Support is in the iOS device/iCloud backup unless a file or
/// folder opts out (NSURLIsExcludedFromBackupKey). The Dart side asks the
/// Runner (AppDelegate's attune/backup_exclusion channel); the native half
/// needs a device check.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late List<String> excluded;
  var failChannel = false;

  // The picker drops the plugin's copy once staged, as on a device.
  String pluginPick() {
    final plugin =
        File(p.join(root.path, 'plugin', 'image_picker_1.jpg'))
          ..createSync(recursive: true)
          ..writeAsBytesSync([0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3, 4]);
    return plugin.path;
  }

  setUp(() {
    root = Directory.systemTemp.createTempSync('backup_exclusion');
    PathProviderPlatform.instance = _SupportDirectory(root.path);
    excluded = [];
    failChannel = false;
    BackupExclusion.debugIsIOS = true;
    BackupExclusion.debugReset();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(BackupExclusion.channel, (call) async {
          expect(call.method, 'excludeFromBackup');
          if (failChannel) throw PlatformException(code: 'EXCLUDE_FAILED');
          excluded.add(call.arguments as String);
          return true;
        });
    ImagePickerPlatform.instance = _PickerPlatform(pluginPick());
  });
  tearDown(() {
    BackupExclusion.debugIsIOS = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(BackupExclusion.channel, null);
    root.deleteSync(recursive: true);
  });

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  test('both chat staging folders are excluded once they exist', () async {
    final picker = ChatImagePicker();
    await picker.pickFromGallery();
    await picker.preparedDirectory();
    await settle();

    final picks = p.join(root.path, ChatImagePicker.folderName);
    final prepared = p.join(root.path, ChatImagePicker.preparedFolderName);
    expect(excluded.toSet(), {picks, prepared});
    expect(Directory(prepared).existsSync(), isTrue, reason: 'created first');

    // Once per folder per launch, not per pick.
    ImagePickerPlatform.instance = _PickerPlatform(pluginPick());
    await picker.pickFromGallery();
    await settle();
    expect(excluded, hasLength(2));
  });

  test('a failing channel never blocks or fails a pick', () async {
    failChannel = true;
    expect(await ChatImagePicker().pickFromGallery(), isNotNull);
  });

  test('not on iOS: no channel call (Android uses the backup rules)', () async {
    BackupExclusion.debugIsIOS = false;
    await ChatImagePicker().pickFromGallery();
    await settle();
    expect(excluded, isEmpty);
  });

  test('the encrypted chat cache store is excluded after it opens', () async {
    final backend = io.createBackend();
    await backend.init();
    await settle();

    final store = p.join(root.path, 'attune_chat_cache.sqlite');
    expect(File(store).existsSync(), isTrue);
    expect(excluded, contains(store));
  });
}

import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:attune/features/chat/domain/services/chat_image_picker.dart';
import 'package:attune/features/chat/domain/services/chat_image_preparer.dart';
import 'package:attune/features/chat/presentation/state/chat_state.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart' as fic;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'support/chat_test_harness.dart';

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

/// Stands in for the native compressor: writes [bytes] to the target (as
/// the plugin does, whatever the result), optionally after [gate].
class _NativeCompress extends fic.UnsupportedFlutterImageCompress {
  _NativeCompress(this.bytes, {this.gate});
  final List<int> bytes;
  final Completer<void>? gate;
  final entered = Completer<void>();

  @override
  Future<fic.XFile?> compressAndGetFile(
    String path,
    String targetPath, {
    int minWidth = 1920,
    int minHeight = 1080,
    int inSampleSize = 1,
    int quality = 95,
    int rotate = 0,
    bool autoCorrectionAngle = true,
    fic.CompressFormat format = fic.CompressFormat.jpeg,
    bool keepExif = false,
    int numberOfRetries = 5,
  }) async {
    if (!entered.isCompleted) entered.complete();
    if (gate != null) await gate!.future;
    File(targetPath).writeAsBytesSync(bytes);
    return fic.XFile(targetPath);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late Directory out;
  late fic.FlutterImageCompressPlatform previous;

  setUp(() {
    root = Directory.systemTemp.createTempSync('prepared_orphans');
    Directory(p.join(root.path, 'tmp')).createSync();
    out = Directory(p.join(root.path, 'out'))..createSync();
    PathProviderPlatform.instance = _FakePathProvider(root);
    previous = fic.FlutterImageCompressPlatform.instance;
  });
  tearDown(() {
    fic.FlutterImageCompressPlatform.instance = previous;
    root.deleteSync(recursive: true);
  });

  // Larger than the 800 KB ceiling at every quality step.
  final oversize = List<int>.filled(ChatImagePreparer.maxBytes + 1, 7);

  Matcher rejectedAs(String code) =>
      throwsA(isA<ChatImageRejected>().having((e) => e.code, 'code', code));

  test('media_compress_failed leaves no upload file behind', () async {
    fic.FlutterImageCompressPlatform.instance = _NativeCompress(oversize);
    // Noise does not compress: the q60 Dart fallback is over 800 KB too.
    final random = Random(7);
    final src = img.Image(width: 2400, height: 1800);
    for (final px in src) {
      px
        ..r = random.nextInt(256)
        ..g = random.nextInt(256)
        ..b = random.nextInt(256);
    }
    final file = File(p.join(root.path, 'noise.png'))
      ..writeAsBytesSync(img.encodePng(src));

    await expectLater(
      const ChatImagePreparer().prepare(
        file.path,
        outputDirectory: () async => out,
      ),
      rejectedAs('media_compress_failed'),
    );
    expect(out.listSync(), isEmpty);
  });

  test('media_decode_failed leaves no upload file behind', () async {
    fic.FlutterImageCompressPlatform.instance = _NativeCompress(oversize);
    // A whole PNG (header and chunks intact) whose pixel data is garbage:
    // the probe passes, the Dart decode fails.
    final png = Uint8List.fromList(
      img.encodePng(img.Image(width: 64, height: 48)),
    );
    final idat = _indexOf(png, 'IDAT'.codeUnits) + 4;
    for (var i = idat; i < idat + 12; i++) {
      png[i] = 0x5A;
    }
    final file = File(p.join(root.path, 'garbage.png'))..writeAsBytesSync(png);

    await expectLater(
      const ChatImagePreparer().prepare(
        file.path,
        outputDirectory: () async => out,
      ),
      rejectedAs('media_decode_failed'),
    );
    expect(out.listSync(), isEmpty);
  });

  test(
    'a purge landing mid-prepare deletes the upload file it produced',
    () async {
      final gate = Completer<void>();
      final native = _NativeCompress(
        img.encodeJpg(img.Image(width: 64, height: 48)),
        gate: gate,
      );
      fic.FlutterImageCompressPlatform.instance = native;

      final repo = FakeChatRepository(currentUserId: 'user-a');
      final container = buildChatContainer(repository: repo, userId: 'user-a');
      addTearDown(container.dispose);
      final convo = activeConversation('rel-1');
      repo.conversationOverride = convo;
      final controller = container.read(chatControllerProvider(convo).notifier);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final raw =
          File(
              p.join(
                root.path,
                'support',
                ChatImagePicker.folderName,
                'pick_1.jpg',
              ),
            )
            ..createSync(recursive: true)
            ..writeAsBytesSync(img.encodeJpg(img.Image(width: 64, height: 48)));

      unawaited(controller.sendImageMessage(localPath: raw.path));
      await native.entered.future.timeout(const Duration(seconds: 5));
      await controller.debugHandleAccountChange('user-a');
      gate.complete();
      await Future<void>.delayed(const Duration(milliseconds: 300));

      final prepared = Directory(
        p.join(root.path, 'support', ChatImagePicker.preparedFolderName),
      );
      expect(prepared.existsSync() ? prepared.listSync() : const [], isEmpty);
      expect(repo.mediaCallCount, 0, reason: 'nothing uploads after a purge');
    },
  );
}

int _indexOf(List<int> haystack, List<int> needle) {
  for (var i = 0; i + needle.length <= haystack.length; i++) {
    var match = true;
    for (var j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) {
        match = false;
        break;
      }
    }
    if (match) return i;
  }
  throw StateError('not found');
}

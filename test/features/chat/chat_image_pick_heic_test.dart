import 'dart:io';

import 'package:attune/features/chat/domain/services/chat_image_picker.dart';
import 'package:attune/features/chat/domain/services/chat_image_preparer.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart' as fic;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
// Transitive through image_picker (1.2.1 pins 2.11.1); faking the platform
// is the only way to hand the picker a HEIC file, and the plan adds no pub
// dependencies.
// ignore: depend_on_referenced_packages
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:path/path.dart' as p;
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

/// Stands in for the native plugin: records what the converter asked for.
class _RecordingCompress extends fic.UnsupportedFlutterImageCompress {
  final calls = <Map<String, Object?>>[];

  @override
  Future<XFile?> compressAndGetFile(
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
    calls.add({
      'path': path,
      'targetPath': targetPath,
      'minWidth': minWidth,
      'minHeight': minHeight,
      'quality': quality,
      'autoCorrectionAngle': autoCorrectionAngle,
      'format': format,
      'keepExif': keepExif,
    });
    File(
      targetPath,
    ).writeAsBytesSync(img.encodeJpg(img.Image(width: 8, height: 6)));
    return XFile(targetPath);
  }
}

/// ISO-BMFF 'ftyp' box, major brand [brand] — what an Android gallery hands
/// over for a HEIF photo when no size or quality option is set.
List<int> heifBytes(String brand) => <int>[
  0x00, 0x00, 0x00, 0x18, 0x66, 0x74, 0x79, 0x70, // size, 'ftyp'
  ...brand.codeUnits, 0x00, 0x00, 0x00, 0x00, // brand, minor
  0x6D, 0x69, 0x66, 0x31, 0x68, 0x65, 0x69, 0x63, // compatible brands
  ...List<int>.filled(64, 0),
];

/// A "decoded HEIC" as the native converter would write it: full size, and
/// (to prove the preparer still strips it) carrying GPS.
List<int> fullSizeJpegWithGps() {
  final src = img.Image(width: 4000, height: 3000);
  src.exif.gpsIfd[0x0001] = img.IfdValueAscii('N'); // GPSLatitudeRef
  src.exif.gpsIfd[0x0002] = img.IfdValueRational(5, 1); // GPSLatitude
  final jpeg = img.encodeJpg(src, quality: 90);
  expect(img.decodeJpg(jpeg)!.exif.gpsIfd.isEmpty, isFalse);
  return jpeg;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late Directory pluginTmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('chat_heic_app_tmp');
    pluginTmp = await Directory.systemTemp.createTemp('chat_heic_plugin');
  });
  tearDown(() async {
    await tmp.delete(recursive: true);
    if (await pluginTmp.exists()) await pluginTmp.delete(recursive: true);
  });

  String pluginFile(String name, List<int> bytes) {
    final f = File(p.join(pluginTmp.path, name))..writeAsBytesSync(bytes);
    return f.path;
  }

  for (final brand in ['heic', 'heix', 'mif1']) {
    test(
      'a $brand pick becomes a full-size JPEG, then 1600 px with no GPS',
      () async {
        ImagePickerPlatform.instance = _PickerPlatform(
          pluginFile('IMG_1.heic', heifBytes(brand)),
        );
        final converted = <String>[];
        final picker = ChatImagePicker(
          stagingDirectory: () async => tmp,
          isIOS: false,
          toJpeg: (source, jpegPath) async {
            converted.add(source);
            await File(jpegPath).writeAsBytes(fullSizeJpegWithGps());
            return true;
          },
        );

        final path = (await picker.pickFromGallery())!;

        expect(converted, hasLength(1));
        expect(p.extension(converted.single), '.heic');
        expect(p.extension(path), '.jpg');
        expect(ChatImagePicker.ownsPath(path), isTrue);
        expect(
          File(converted.single).existsSync(),
          isFalse,
          reason: 'the staged HEIC is dropped once the JPEG exists',
        );
        expect(
          Directory(
            p.join(tmp.path, ChatImagePicker.folderName),
          ).listSync().map((e) => e.path),
          [path],
          reason: 'one staged file per pick',
        );
        final staged = img.decodeJpg(File(path).readAsBytesSync())!;
        expect(
          (staged.width, staged.height),
          (4000, 3000),
          reason: 'conversion keeps full resolution (#20)',
        );

        final out = await const ChatImagePreparer().prepare(path);
        final decoded = img.decodeJpg(await out.file.readAsBytes())!;
        expect(out.mimeType, 'image/jpeg');
        expect((decoded.width, decoded.height), (1600, 1200));
        expect(
          decoded.exif.gpsIfd.isEmpty,
          isTrue,
          reason: 'GPS must never survive preparation',
        );
      },
    );
  }

  test('a JPEG, PNG or WebP pick is never converted (the preparer is the one '
      'encode)', () async {
    final picks = {
      'a.jpg': img.encodeJpg(img.Image(width: 20, height: 10)),
      'b.png': img.encodePng(img.Image(width: 20, height: 10)),
      // RIFF....WEBP
      'c.webp': [
        0x52, 0x49, 0x46, 0x46, 0x10, 0x00, 0x00, 0x00, //
        0x57, 0x45, 0x42, 0x50, ...List<int>.filled(32, 0),
      ],
    };
    for (final entry in picks.entries) {
      ImagePickerPlatform.instance = _PickerPlatform(
        pluginFile(entry.key, entry.value),
      );
      final picker = ChatImagePicker(
        stagingDirectory: () async => tmp,
        isIOS: false,
        toJpeg: (_, __) async => fail('${entry.key} must not be re-encoded'),
      );
      final path = (await picker.pickFromGallery())!;
      expect(
        File(path).readAsBytesSync(),
        entry.value,
        reason: '${entry.key}: bytes untouched',
      );
    }
  });

  test('a failed conversion hands the original on (the preparer then says '
      '"unsupported") and leaves no half-written JPEG', () async {
    for (final failure in <Future<bool> Function(String, String)>[
      (_, jpegPath) async {
        File(jpegPath).writeAsBytesSync([1, 2, 3]);
        return false;
      },
      (_, jpegPath) async {
        File(jpegPath).writeAsBytesSync([1, 2, 3]);
        throw StateError('decoder unavailable (Android 8)');
      },
    ]) {
      ImagePickerPlatform.instance = _PickerPlatform(
        pluginFile('IMG_2.heic', heifBytes('heic')),
      );
      final picker = ChatImagePicker(
        stagingDirectory: () async => tmp,
        isIOS: false,
        toJpeg: failure,
      );

      final path = (await picker.pickFromGallery())!;

      expect(p.extension(path), '.heic');
      expect(
        Directory(
          p.join(tmp.path, ChatImagePicker.folderName),
        ).listSync().map((e) => e.path),
        [path],
      );
      await expectLater(
        const ChatImagePreparer().prepare(path),
        throwsA(
          isA<ChatImageRejected>().having(
            (e) => e.code,
            'code',
            'media_type_unsupported',
          ),
        ),
      );
      await ChatImagePicker.discard(path);
    }
  });

  test(
    'the native converter asks for JPEG at full size, upright, no EXIF',
    () async {
      final previous = fic.FlutterImageCompressPlatform.instance;
      final platform = _RecordingCompress();
      fic.FlutterImageCompressPlatform.instance = platform;
      addTearDown(() => fic.FlutterImageCompressPlatform.instance = previous);

      final source = pluginFile('IMG_3.heic', heifBytes('heic'));
      final target = p.join(tmp.path, 'out.jpg');
      expect(await ChatImagePicker.nativeToJpeg(source, target), isTrue);

      final call = platform.calls.single;
      expect(call['path'], source);
      expect(call['targetPath'], target);
      expect(call['format'], fic.CompressFormat.jpeg);
      expect(call['keepExif'], isFalse);
      expect(call['autoCorrectionAngle'], isTrue);
      // flutter_image_compress never upscales (Android: max(1, min(w/minW,
      // h/minH)); iOS: fminf(1, …)), so a bound no photo reaches means "keep
      // every pixel"; the 1920x1080 default would cut a 12 MP shot down.
      expect(call['minWidth'] as int, greaterThanOrEqualTo(1 << 16));
      expect(call['minHeight'] as int, greaterThanOrEqualTo(1 << 16));
      expect(call['quality'], 92);
    },
  );
}

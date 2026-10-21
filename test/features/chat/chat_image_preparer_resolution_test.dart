import 'dart:io';

import 'package:attune/features/chat/domain/services/chat_image_preparer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  setUp(() async => dir = await Directory.systemTemp.createTemp('res'));
  tearDown(() => dir.delete(recursive: true));

  test(
    'a 12 MP photo comes out at a 1600 px long edge, under 800 KB',
    () async {
      // 4000x3000 with a gradient so JPEG has real work to do.
      final src = img.Image(width: 4000, height: 3000);
      for (final px in src) {
        px
          ..r = px.x % 256
          ..g = px.y % 256
          ..b = (px.x + px.y) % 256;
      }
      final file = File('${dir.path}/big.jpg')
        ..writeAsBytesSync(img.encodeJpg(src, quality: 90));

      final out = await const ChatImagePreparer().prepare(file.path);

      final decoded = img.decodeJpg(await out.file.readAsBytes())!;
      expect(decoded.width, 1600);
      expect(decoded.height, 1200);
      expect(out.byteSize, lessThanOrEqualTo(ChatImagePreparer.maxBytes));
      expect(out.mimeType, 'image/jpeg');
    },
  );

  test('a portrait 3000x4000 keeps its orientation at 1200x1600', () async {
    final src = img.Image(width: 3000, height: 4000);
    final file = File('${dir.path}/tall.jpg')
      ..writeAsBytesSync(img.encodeJpg(src, quality: 90));
    final out = await const ChatImagePreparer().prepare(file.path);
    final decoded = img.decodeJpg(await out.file.readAsBytes())!;
    expect((decoded.width, decoded.height), (1200, 1600));
  });

  test('a small photo is not upscaled', () async {
    final src = img.Image(width: 640, height: 480);
    final file = File('${dir.path}/small.jpg')
      ..writeAsBytesSync(img.encodeJpg(src));
    final out = await const ChatImagePreparer().prepare(file.path);
    final decoded = img.decodeJpg(await out.file.readAsBytes())!;
    expect((decoded.width, decoded.height), (640, 480));
  });

  test('a HEIC original is rejected as unsupported, not crashed on', () async {
    // ISO-BMFF 'ftyp' box with major brand 'heic'. iOS never hands this
    // over (image_picker_ios re-encodes every pick to JPEG/PNG); Android
    // does when the gallery stores HEIF and no size/quality option is set,
    // which is exactly how ChatImagePicker asks — so the picker converts it
    // to JPEG first (chat_image_pick_heic_test). This is the safety net for
    // a conversion that failed: the preparer must say "unsupported", not
    // throw from the decoder.
    final bytes = <int>[
      0x00, 0x00, 0x00, 0x18, 0x66, 0x74, 0x79, 0x70, // size, 'ftyp'
      0x68, 0x65, 0x69, 0x63, 0x00, 0x00, 0x00, 0x00, // 'heic', minor
      0x6D, 0x69, 0x66, 0x31, 0x68, 0x65, 0x69, 0x63, // compatible brands
      ...List<int>.filled(64, 0),
    ];
    final file = File('${dir.path}/photo.heic')..writeAsBytesSync(bytes);
    await expectLater(
      const ChatImagePreparer().prepare(file.path),
      throwsA(
        isA<ChatImageRejected>().having(
          (e) => e.code,
          'code',
          'media_type_unsupported',
        ),
      ),
    );
  });

  test(
    'the preparer probes the header and keeps the full decode off the UI isolate',
    () {
      // With full-resolution originals now reaching it (#20), a package:image
      // decode of a 12 MP JPEG on the UI isolate is seconds of frozen app per
      // photo. Dimensions come from the container header; the only full
      // Dart decode is the fallback encoder, in a worker isolate.
      final src =
          File(
            'lib/features/chat/domain/services/chat_image_preparer.dart',
          ).readAsStringSync();
      final prepare = src.substring(
        src.indexOf('Future<PreparedChatImage> prepare('),
        src.indexOf('({int width, int height}) _longestEdgeTarget('),
      );
      // The header probe itself also runs in a worker isolate (fix round 1,
      // M1): it walks the whole file in Dart.
      expect(prepare, contains('Isolate.run(() => _probeSource('));
      expect(
        prepare.indexOf('_probeSource('),
        lessThan(prepare.indexOf('FlutterImageCompress.compressAndGetFile')),
      );
      final probe = src.substring(
        src.indexOf('ChatImageProbe? _probeSource('),
        src.indexOf('bool chatImageStructurallyComplete('),
      );
      expect(probe, contains('startDecode('));
      expect(probe, isNot(contains('img.decodeImage(')));
      expect(
        prepare,
        isNot(contains('img.decodeImage(')),
        reason: 'the full decode lives in the isolate worker only',
      );
      expect(prepare, contains('Isolate.run('));
      expect(
        src,
        contains('img.bakeOrientation('),
        reason: 'an untouched Android original carries its orientation in EXIF',
      );
    },
  );
}

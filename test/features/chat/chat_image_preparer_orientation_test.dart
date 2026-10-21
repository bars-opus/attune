import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:attune/features/chat/domain/services/chat_image_preparer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// flutter_image_compress_common 1.0.6, Android (CompressFileHandler +
/// BitmapCompressExt): minWidth/minHeight are swapped when the EXIF
/// rotation is 90/270, the stored bitmap is decoded at 1/inSampleSize
/// (libjpeg rounds up), scaled by max(1, min(w/minW, h/minH)), then rotated.
({int width, int height}) androidOutput({
  required int storedWidth,
  required int storedHeight,
  required int orientation,
  required int minWidth,
  required int minHeight,
  required int inSampleSize,
}) {
  // androidx ExifInterface.getRotationDegrees.
  final degrees = switch (orientation) {
    3 || 4 => 180,
    6 || 7 => 90,
    5 || 8 => 270,
    _ => 0,
  };
  var minW = minWidth;
  var minH = minHeight;
  if (degrees == 90 || degrees == 270) (minW, minH) = (minH, minW);
  final w = (storedWidth / inSampleSize).ceil();
  final h = (storedHeight / inSampleSize).ceil();
  final scale = math.max(1.0, math.min(w / minW, h / minH));
  final outW = (w / scale).toInt();
  final outH = (h / scale).toInt();
  return degrees == 90 || degrees == 270
      ? (width: outH, height: outW)
      : (width: outW, height: outH);
}

/// flutter_image_compress_common 1.0.6, iOS (UIImage+scale.m): UIImage.size
/// is already in display orientation; no swap, no sampling.
({int width, int height}) iosOutput({
  required int displayWidth,
  required int displayHeight,
  required int minWidth,
  required int minHeight,
}) {
  final imgRatio = displayWidth / displayHeight;
  final maxRatio = minWidth / minHeight;
  var scale =
      imgRatio < maxRatio ? minWidth / displayWidth : minHeight / displayHeight;
  scale = math.min(1, scale);
  return (
    width: (scale * displayWidth).floor(),
    height: (scale * displayHeight).floor(),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const sizes = [
    (4000, 3000),
    (3000, 4000),
    (4032, 3024),
    (4001, 3001),
    (9248, 6936),
    (8000, 2000), // panorama
    (1080, 2400), // screenshot
    (1600, 1200), // already at the cap
    (1000, 800), // small
  ];

  for (var orientation = 1; orientation <= 8; orientation++) {
    test('orientation $orientation: long edge <= 1600, aspect kept, on both '
        'platforms', () {
      for (final (w, h) in sizes) {
        final rotated = orientation >= 5;
        final displayW = rotated ? h : w;
        final displayH = rotated ? w : h;
        final target = chatCompressTarget(
          storedWidth: w,
          storedHeight: h,
          orientation: orientation,
        );
        final sample = chatCompressSampleSize(
          storedWidth: w,
          storedHeight: h,
          orientation: orientation,
        );
        final outputs = {
          'android': androidOutput(
            storedWidth: w,
            storedHeight: h,
            orientation: orientation,
            minWidth: target.width,
            minHeight: target.height,
            inSampleSize: sample,
          ),
          'ios': iosOutput(
            displayWidth: displayW,
            displayHeight: displayH,
            minWidth: target.width,
            minHeight: target.height,
          ),
        };
        final expectedLong = math.min(1600, math.max(w, h));
        outputs.forEach((platform, out) {
          final label =
              '$platform ${w}x$h o$orientation -> '
              '${out.width}x${out.height}';
          final long = math.max(out.width, out.height);
          expect(long, lessThanOrEqualTo(1600), reason: label);
          expect(long, greaterThanOrEqualTo(expectedLong - 1), reason: label);
          // Display orientation kept (a portrait shows portrait) and the
          // aspect within a pixel's rounding.
          expect(out.width >= out.height, displayW >= displayH, reason: label);
          expect(
            (out.width / out.height - displayW / displayH).abs(),
            lessThan(displayW / displayH * 0.01),
            reason: label,
          );
        });
      }
    });
  }

  test('the sampled decode always covers the target, at the largest power of '
      'two', () {
    expect(
      chatCompressSampleSize(
        storedWidth: 4000,
        storedHeight: 3000,
        orientation: 1,
      ),
      2,
    );
    expect(
      chatCompressSampleSize(
        storedWidth: 3000,
        storedHeight: 4000,
        orientation: 6,
      ),
      2,
    );
    expect(
      chatCompressSampleSize(
        storedWidth: 9248,
        storedHeight: 6936,
        orientation: 1,
      ),
      4,
    );
    expect(
      chatCompressSampleSize(
        storedWidth: 1000,
        storedHeight: 800,
        orientation: 1,
      ),
      1,
    );
    expect(
      chatCompressSampleSize(
        storedWidth: 3199,
        storedHeight: 2400,
        orientation: 1,
      ),
      1,
      reason: '3199 / 2 is under the 1600 target',
    );
  });

  group('a file cut short is rejected as undecodable (Spec 8.1)', () {
    late Directory dir;
    setUp(() async => dir = await Directory.systemTemp.createTemp('trunc'));
    tearDown(() => dir.delete(recursive: true));

    img.Image gradient() {
      final src = img.Image(width: 400, height: 300);
      for (final px in src) {
        px
          ..r = px.x % 256
          ..g = px.y % 256
          ..b = 90;
      }
      return src;
    }

    for (final (name, encode) in [
      ('jpeg', (img.Image i) => img.encodeJpg(i, quality: 90)),
      ('png', (img.Image i) => img.encodePng(i)),
    ]) {
      test('a truncated $name with a valid header', () async {
        final whole = encode(gradient());
        final cut = Uint8List.sublistView(whole, 0, whole.length * 2 ~/ 3);
        // The header still reads: only a structural check catches this.
        expect(img.findDecoderForData(cut), isNotNull);
        final file = File('${dir.path}/cut.$name')..writeAsBytesSync(cut);

        await expectLater(
          const ChatImagePreparer().prepare(file.path),
          throwsA(
            isA<ChatImageRejected>().having(
              (e) => e.code,
              'code',
              'media_decode_failed',
            ),
          ),
        );
      });
    }

    test('whole files pass the structural check', () {
      final src = gradient();
      expect(
        chatImageStructurallyComplete(img.encodeJpg(src), 'image/jpeg'),
        isTrue,
      );
      expect(
        chatImageStructurallyComplete(img.encodePng(src), 'image/png'),
        isTrue,
      );
      // EXIF (APP1) with GPS, as a phone writes it, is skipped by length.
      final tagged = img.Image.from(src);
      tagged.exif.gpsIfd[0x0001] = img.IfdValueAscii('N');
      expect(
        chatImageStructurallyComplete(img.encodeJpg(tagged), 'image/jpeg'),
        isTrue,
      );
      // Restart markers and stuffed bytes inside the scan are data.
      final restarts = Uint8List.fromList([
        0xFF, 0xD8, // SOI
        0xFF, 0xDA, 0x00, 0x04, 0x01, 0x00, // SOS (header length 4)
        0x12, 0xFF, 0x00, 0x34, 0xFF, 0xD0, 0x56, 0xFF, 0xD7, // scan data
        0xFF, 0xFF, 0xD9, // fill byte, EOI
      ]);
      expect(chatImageStructurallyComplete(restarts, 'image/jpeg'), isTrue);
      expect(
        chatImageStructurallyComplete(
          Uint8List.sublistView(restarts, 0, restarts.length - 2),
          'image/jpeg',
        ),
        isFalse,
      );
    });

    test('extraneous bytes between segments are skipped, as libjpeg does', () {
      // Some encoders leave padding between segments; libjpeg warns
      // ("extraneous bytes before marker") and decodes on.
      final whole = img.encodeJpg(gradient());
      // Splice junk in right after SOI, before the first segment's marker.
      final padded = Uint8List.fromList([
        ...whole.sublist(0, 2),
        0x00, 0x12, 0x34, 0x00, //
        ...whole.sublist(2),
      ]);
      expect(chatImageStructurallyComplete(padded, 'image/jpeg'), isTrue);
      // Still has to reach EOI.
      expect(
        chatImageStructurallyComplete(
          Uint8List.sublistView(padded, 0, padded.length * 2 ~/ 3),
          'image/jpeg',
        ),
        isFalse,
      );
      // Junk with no marker after it is never "complete".
      expect(
        chatImageStructurallyComplete(
          Uint8List.fromList([0xFF, 0xD8, 0x00, 0x01, 0x02, 0x03]),
          'image/jpeg',
        ),
        isFalse,
      );
    });
  });

  test('a sideways 4000x3000 photo comes out 1200x1600 through the Dart '
      'fallback too', () async {
    final src = img.Image(width: 4000, height: 3000);
    src.exif.imageIfd.orientation = 6;
    final dir = await Directory.systemTemp.createTemp('side_full');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/side.jpg')
      ..writeAsBytesSync(img.encodeJpg(src, quality: 80));
    final out = await const ChatImagePreparer().prepare(file.path);
    final decoded = img.decodeJpg(await out.file.readAsBytes())!;
    expect((decoded.width, decoded.height), (1200, 1600));
  });
}

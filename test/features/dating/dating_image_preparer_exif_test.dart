// test/features/dating/dating_image_preparer_exif_test.dart
import 'dart:io';

import 'package:attune/features/dating/domain/services/dating_image_preparer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'the Dart fallback strips GPS EXIF (no platform compressor in tests)',
    () async {
      final src = img.Image(width: 64, height: 48);
      // GPS tags need IfdValues: the setter only converts image-IFD tags.
      src.exif.gpsIfd[0x0001] = img.IfdValueAscii('N'); // GPSLatitudeRef
      src.exif.gpsIfd[0x0002] = img.IfdValueRational(5, 1); // GPSLatitude
      final jpeg = img.encodeJpg(src);
      // The fixture really carries GPS, or the test proves nothing.
      expect(img.decodeJpg(jpeg)!.exif.gpsIfd.isEmpty, isFalse);

      final dir = await Directory.systemTemp.createTemp('exif');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/gps.jpg')..writeAsBytesSync(jpeg);

      final out = await const DatingImagePreparer().prepare(file.path);
      final decoded = img.decodeJpg(await out.file.readAsBytes())!;
      expect(
        decoded.exif.gpsIfd.isEmpty,
        isTrue,
        reason: 'GPS must never survive preparation',
      );
    },
  );

  test('a sideways phone photo comes out upright once EXIF is gone', () async {
    // Orientation 6: stored landscape, shown rotated 90°. Clearing EXIF
    // without baking it in would leave the photo on its side.
    final src = img.Image(width: 64, height: 48);
    src.exif.imageIfd.orientation = 6;
    final dir = await Directory.systemTemp.createTemp('orient');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/side.jpg')
      ..writeAsBytesSync(img.encodeJpg(src));

    final out = await const DatingImagePreparer().prepare(file.path);
    final decoded = img.decodeJpg(await out.file.readAsBytes())!;
    expect((decoded.width, decoded.height), (48, 64));
  });
}

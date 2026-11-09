import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:attune/features/dating/domain/services/dating_image_preparer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  @override
  Future<String?> getTemporaryPath() async => Directory.systemTemp.path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  PathProviderPlatform.instance = _FakePathProvider();

  test('rejects a missing file', () async {
    const preparer = DatingImagePreparer();
    expect(
      () => preparer.prepare('/nonexistent/path.jpg'),
      throwsA(
        isA<DatingImageRejected>().having((e) => e.code, 'code', 'media_missing'),
      ),
    );
  });

  test('rejects an undecodable file', () async {
    final path = p.join(Directory.systemTemp.path, 'not_an_image.jpg');
    final file = File(path);
    await file.writeAsBytes(Uint8List.fromList([0x00, 0x01, 0x02, 0x03]));
    addTearDown(() => file.deleteSync());

    const preparer = DatingImagePreparer();
    expect(
      () => preparer.prepare(path),
      throwsA(
        isA<DatingImageRejected>().having(
          (e) => e.code,
          'code',
          anyOf('media_type_unsupported', 'media_decode_failed'),
        ),
      ),
    );
  });

  test('prepares a valid JPEG under the size ceiling', () async {
    // Minimal valid 1x1 JPEG (magic bytes + SOI/EOI); real content isn't
    // required, only that the decoder + compressor pipeline completes.
    final path = p.join(Directory.systemTemp.path, 'tiny.jpg');
    final file = File(path);
    // A real 8x8 red JPEG, base64-decoded, to give the decoder something
    // genuinely valid to work with.
    const base64Jpeg =
        '/9j/4AAQSkZJRgABAQAAAQABAAD/2wCEAAMCAgMCAgMDAwMEAwMEBQgFBQQEBQoHBwYIDAoMDAsKCwsNDhIQDQ4RDgsLEBYQERMUFRUVDA8XGBYUGBIUFRQBAwQEBQQFCQUFCRQNCw0UFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFP/AABEIAAgACAMBEQACEQEDEQH/xAGiAAABBQEBAQEBAQAAAAAAAAAAAQIDBAUGBwgJCgsQAAIBAwMCBAMFBQQEAAABfQECAwAEEQUSITFBBhNRYQcicRQygZGhCCNCscEVUtHwJDNicoIJChYXGBkaJSYnKCkqNDU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6g4SFhoeIiYqSk5SVlpeYmZqio6Slpqeoqaqys7S1tre4ubrCw8TFxsfIycrS09TV1tfY2drh4uPk5ebn6Onq8fLz9PX29/j5+gEAAwEBAQEBAQEBAQAAAAAAAAECAwQFBgcICQoLEQACAQIEBAMEBwUEBAABAncAAQIDEQQFITEGEkFRB2FxEyIygQgUQpGhscEJIzNS8BVictEKFiQ04SXxFxgZGiYnKCkqNTY3ODk6Q0RFRkdISUpTVFVWV1hZWmNkZWZnaGlqc3R1dnd4eXqCg4SFhoeIiYqSk5SVlpeYmZqio6Slpqeoqaqys7S1tre4ubrCw8TFxsfIycrS09TV1tfY2dri4+Tl5ufo6ery8/T19vf4+fr/2gAMAwEAAhEDEQA/APCq+aP9Az//2Q==';
    await file.writeAsBytes(base64Decode(base64Jpeg));
    addTearDown(() => file.deleteSync());

    const preparer = DatingImagePreparer();
    final prepared = await preparer.prepare(path);
    expect(prepared.mimeType, 'image/jpeg');
    expect(prepared.byteSize, lessThanOrEqualTo(DatingImagePreparer.maxBytes));
    addTearDown(() => prepared.file.deleteSync());
  });

  // Spec 2 W3c (R-23, C-5): at most 1600 px on the long side, a neutral
  // temp name, EXIF gone.
  test('a large photo comes out at most 1600 px, under a neutral name', () async {
    final dir = await Directory.systemTemp.createTemp('w3c');
    addTearDown(() => dir.delete(recursive: true));
    final big = img.Image(width: 4000, height: 3000);
    img.fill(big, color: img.ColorRgb8(200, 120, 90));
    final source = File('${dir.path}/source.jpg')..writeAsBytesSync(img.encodeJpg(big, quality: 95));
    final prepared = await const DatingImagePreparer().prepare(source.path);
    final out = img.decodeJpg(await prepared.file.readAsBytes())!;
    expect(out.width, 1600);
    expect(out.height, 1200);
    expect(prepared.file.path.toLowerCase(), isNot(contains('dating')));
    expect(prepared.byteSize, lessThanOrEqualTo(DatingImagePreparer.maxBytes));
    await prepared.file.delete();
  });

  // Spec 2 W3c Task 9 fix round 1 (I-3): the decode, resize and encode run
  // in a worker isolate, never on the UI isolate (up to six photos in D9).
  test('the pixel work runs in a worker isolate', () {
    final src =
        File(
          'lib/features/dating/domain/services/dating_image_preparer.dart',
        ).readAsStringSync();
    final start = src.indexOf('Future<PreparedDatingImage> prepare(');
    final body = src.substring(start, src.indexOf('\n  }\n', start));
    expect(body, contains('Isolate.run('));
    for (final call in const [
      'img.decodeImage(',
      'img.encodeJpg(',
      'img.copyResize(',
      'img.bakeOrientation(',
    ]) {
      expect(body, isNot(contains(call)), reason: call);
    }
  });

  // Spec 2 W3c Task 9 fix round 1 (M-7): exactly the Dart encoder at
  // quality 80 (upright, 1600 px, EXIF cleared), and a large photo stays
  // near D9's "about 300 KB", far under the 1.5 MB ceiling.
  test('quality 80; a large photo comes out under 400 KB', () async {
    expect(DatingImagePreparer.quality, 80);
    final dir = await Directory.systemTemp.createTemp('w3c');
    addTearDown(() => dir.delete(recursive: true));
    final big = img.Image(width: 2400, height: 1800);
    for (final p in big) {
      p
        ..r = p.x * 255 ~/ 2400
        ..g = p.y * 255 ~/ 1800
        ..b = (p.x + p.y) * 255 ~/ 4200;
    }
    final sourceBytes = img.encodeJpg(big, quality: 95);
    final source = File('${dir.path}/source.jpg')
      ..writeAsBytesSync(sourceBytes);
    final prepared = await const DatingImagePreparer().prepare(source.path);
    final expected = img.copyResize(
      img.bakeOrientation(img.decodeJpg(sourceBytes)!),
      width: 1600,
    )..exif = img.ExifData();
    expect(
      await prepared.file.readAsBytes(),
      img.encodeJpg(expected, quality: 80),
    );
    expect(prepared.byteSize, lessThan(400 * 1024));
    await prepared.file.delete();
  });
}

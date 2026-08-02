import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:attune/features/dating/domain/services/dating_image_preparer.dart';
import 'package:flutter_test/flutter_test.dart';
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
}

import 'dart:io';
import 'dart:typed_data';

import 'package:attune/features/chat/domain/services/chat_image_preparer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('chat_img_test');
  });
  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  Future<String> writeJpeg(int w, int h) async {
    final image = img.Image(width: w, height: h);
    img.fill(image, color: img.ColorRgb8(120, 180, 240));
    final bytes = img.encodeJpg(image, quality: 90);
    final file = File(p.join(tmp.path, 'src.jpg'));
    await file.writeAsBytes(bytes);
    return file.path;
  }

  test('rejects a non-image file by content, not extension', () async {
    final file = File(p.join(tmp.path, 'fake.jpg'));
    await file.writeAsString('this is not an image');
    expect(
      () => const ChatImagePreparer().prepare(file.path),
      throwsA(
        isA<ChatImageRejected>().having(
          (e) => e.code,
          'code',
          'media_type_unsupported',
        ),
      ),
    );
  });

  test('rejects an empty file', () async {
    final file = File(p.join(tmp.path, 'empty.jpg'));
    await file.writeAsBytes(Uint8List(0));
    expect(
      () => const ChatImagePreparer().prepare(file.path),
      throwsA(
        isA<ChatImageRejected>().having((e) => e.code, 'code', 'media_empty'),
      ),
    );
  });

  test('rejects a missing file', () async {
    expect(
      () => const ChatImagePreparer().prepare('/no/such/file.jpg'),
      throwsA(
        isA<ChatImageRejected>().having((e) => e.code, 'code', 'media_missing'),
      ),
    );
  });

  test(
    'prepares a valid JPEG to jpeg output within the size ceiling',
    () async {
      final path = await writeJpeg(1200, 800);
      final result = await const ChatImagePreparer().prepare(path);

      expect(result.mimeType, 'image/jpeg');
      expect(result.byteSize, lessThanOrEqualTo(ChatImagePreparer.maxBytes));
      expect(result.byteSize, greaterThan(0));
      expect(await result.file.exists(), isTrue);
    },
  );
}

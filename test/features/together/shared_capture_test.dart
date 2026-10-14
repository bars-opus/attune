import 'package:attune/features/together/domain/shared_capture.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('text and links become one capture note; images and blanks do not', () {
    expect(
      sharedCaptureText(const [
        SharedItem('text', '  Dinner at Buka Sat 7pm '),
        SharedItem('url', 'https://example.com/booking/123'),
      ]),
      'Dinner at Buka Sat 7pm\nhttps://example.com/booking/123',
    );
    expect(
      sharedCaptureText(const [SharedItem('image', '/tmp/a.jpg')]),
      isNull,
    );
    expect(sharedCaptureText(const [SharedItem('text', '   ')]), isNull);
    expect(sharedCaptureText(const []), isNull);
  });

  test('a long paste is clipped to what capture accepts', () {
    final long = 'x' * 5000;
    expect(sharedCaptureText([SharedItem('text', long)])!.runes.length, 300);
  });

  test('without AI: first line is the title, the rest the note', () {
    final f = sharedCaptureFallback(
      '\nDinner at Buka\nSat 7pm, table for 2\nRef ABC123',
    );
    expect(f.title, 'Dinner at Buka');
    expect(f.note, 'Sat 7pm, table for 2\nRef ABC123');
    final one = sharedCaptureFallback('y' * 200);
    expect(one.title.length, 120);
    expect(one.note, isNull);
  });
}

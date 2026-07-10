import 'package:attune/features/chat/data/cache/chat_cache_cipher.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final cipher = ChatCacheCipher.forTesting();

  test('round-trips plaintext through the AES-GCM envelope', () {
    const plain = 'a private message with emoji 🙂 and unicode ñ';
    final envelope = cipher.encryptString(plain);
    expect(envelope, isNot(contains('private message')));
    expect(cipher.decryptString(envelope), plain);
  });

  test('ciphertext is non-deterministic (random nonce)', () {
    const plain = 'same input';
    expect(cipher.encryptString(plain), isNot(cipher.encryptString(plain)));
  });

  test('rejects a tampered envelope as a cache miss', () {
    final envelope = cipher.encryptString('secret');
    final tampered = '${envelope.substring(0, envelope.length - 2)}AA';
    expect(cipher.decryptString(tampered), isNull);
  });

  test('rejects a non-envelope blob', () {
    expect(cipher.decryptString('not-base64-or-envelope'), isNull);
    expect(cipher.decryptString(null), isNull);
    expect(cipher.decryptString(''), isNull);
  });
}

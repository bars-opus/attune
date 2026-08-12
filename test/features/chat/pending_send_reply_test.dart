// test/features/chat/pending_send_reply_test.dart
import 'package:attune/features/chat/data/cache/pending_send.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('PendingSend toJson/fromJson round-trips reply fields', () {
    final original = PendingSend(
      clientMessageId: 'c1',
      relationshipId: 'r1',
      senderId: 'me',
      text: 'replying',
      createdAt: DateTime(2026, 8, 12, 9),
      replyToMessageId: 'm1',
      quotedText: 'the earlier message',
    );

    final restored = PendingSend.fromJson(original.toJson());
    expect(restored.replyToMessageId, 'm1');
    expect(restored.quotedText, 'the earlier message');
  });

  test('PendingSend.copyWith preserves reply fields', () {
    final original = PendingSend(
      clientMessageId: 'c1',
      relationshipId: 'r1',
      senderId: 'me',
      text: 'replying',
      createdAt: DateTime(2026, 8, 12, 9),
      replyToMessageId: 'm1',
      quotedText: 'the earlier message',
    );

    final copied = original.copyWith(state: PendingSendState.sending);
    expect(copied.replyToMessageId, 'm1');
    expect(copied.quotedText, 'the earlier message');
  });

  test('PendingSend without a reply has null reply fields', () {
    final original = PendingSend(
      clientMessageId: 'c1',
      relationshipId: 'r1',
      senderId: 'me',
      text: 'not a reply',
      createdAt: DateTime(2026, 8, 12, 9),
    );

    expect(original.replyToMessageId, isNull);
    expect(original.quotedText, isNull);
    final restored = PendingSend.fromJson(original.toJson());
    expect(restored.replyToMessageId, isNull);
    expect(restored.quotedText, isNull);
  });
}

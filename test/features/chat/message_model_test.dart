import 'package:attune/features/chat/domain/entities/message.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('voice message fields', () {
    test('hasAudio is true only when mediaType is audio and media is available', () {
      final withLocal = Message(
        id: 'm1',
        clientMessageId: 'c1',
        relationshipId: 'r1',
        senderId: 's1',
        content: '',
        createdAt: DateTime(2026, 8, 15),
        status: MessageStatus.sending,
        isMine: true,
        mediaType: 'audio',
        localMediaPath: '/tmp/voice.m4a',
        mediaDurationMs: 4200,
        waveform: List.filled(100, 10),
      );
      expect(withLocal.hasAudio, isTrue);

      // copyWith's `?? this.x` pattern can't null out a field — verify via a
      // fresh construction instead, matching how hasImage's own tests (if
      // any) would need to be checked for the same copyWith limitation.
      final noMedia = Message(
        id: 'm2',
        clientMessageId: 'c2',
        relationshipId: 'r1',
        senderId: 's1',
        content: 'text only',
        createdAt: DateTime(2026, 8, 15),
        status: MessageStatus.sent,
        isMine: true,
      );
      expect(noMedia.hasAudio, isFalse);

      final imageMessage = Message(
        id: 'm3',
        clientMessageId: 'c3',
        relationshipId: 'r1',
        senderId: 's1',
        content: '',
        createdAt: DateTime(2026, 8, 15),
        status: MessageStatus.sent,
        isMine: true,
        mediaType: 'image',
        signedMediaUrl: 'https://example.com/img.jpg',
      );
      expect(imageMessage.hasAudio, isFalse);
    });

    test('toJson/fromJson round-trips mediaDurationMs and waveform', () {
      final original = Message(
        id: 'm1',
        clientMessageId: 'c1',
        relationshipId: 'r1',
        senderId: 's1',
        content: '',
        createdAt: DateTime(2026, 8, 15, 9),
        status: MessageStatus.sent,
        isMine: true,
        mediaType: 'audio',
        mediaKey: 'chat-media/abc.m4a',
        mediaDurationMs: 12345,
        waveform: [1, 2, 3, 250, 0],
      );

      final restored = Message.fromJson(original.toJson());
      expect(restored.mediaDurationMs, 12345);
      expect(restored.waveform, [1, 2, 3, 250, 0]);
    });

    test('fromJson defaults mediaDurationMs/waveform to null when absent', () {
      final textOnly = Message(
        id: 'm1',
        clientMessageId: 'c1',
        relationshipId: 'r1',
        senderId: 's1',
        content: 'hello',
        createdAt: DateTime(2026, 8, 15),
        status: MessageStatus.sent,
        isMine: true,
      );
      final restored = Message.fromJson(textOnly.toJson());
      expect(restored.mediaDurationMs, isNull);
      expect(restored.waveform, isNull);
    });

    test('copyWith preserves mediaDurationMs and waveform when not overridden', () {
      final original = Message(
        id: 'm1',
        clientMessageId: 'c1',
        relationshipId: 'r1',
        senderId: 's1',
        content: '',
        createdAt: DateTime(2026, 8, 15),
        status: MessageStatus.sending,
        isMine: true,
        mediaType: 'audio',
        mediaDurationMs: 5000,
        waveform: [5, 10, 15],
      );
      final copied = original.copyWith(status: MessageStatus.sent);
      expect(copied.mediaDurationMs, 5000);
      expect(copied.waveform, [5, 10, 15]);
    });
  });
}

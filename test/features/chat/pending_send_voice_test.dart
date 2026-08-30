import 'package:attune/features/chat/data/cache/pending_send.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'PendingSend toJson/fromJson round-trips mediaDurationMs and waveform',
    () {
      final original = PendingSend(
        clientMessageId: 'c1',
        relationshipId: 'r1',
        senderId: 'me',
        text: '',
        localMediaPath: '/tmp/voice.m4a',
        mediaMimeType: 'audio/mp4',
        mediaType: 'audio',
        mediaDurationMs: 4200,
        waveform: [1, 5, 10, 3],
        createdAt: DateTime(2026, 8, 15, 9),
      );

      final restored = PendingSend.fromJson(original.toJson());
      expect(restored.mediaDurationMs, 4200);
      expect(restored.waveform, [1, 5, 10, 3]);
    },
  );

  test('PendingSend.copyWith preserves mediaDurationMs and waveform', () {
    final original = PendingSend(
      clientMessageId: 'c1',
      relationshipId: 'r1',
      senderId: 'me',
      text: '',
      mediaType: 'audio',
      mediaDurationMs: 4200,
      waveform: [1, 5, 10, 3],
      createdAt: DateTime(2026, 8, 15, 9),
    );
    final copied = original.copyWith(state: PendingSendState.sending);
    expect(copied.mediaDurationMs, 4200);
    expect(copied.waveform, [1, 5, 10, 3]);
  });

  test('a text-only PendingSend has null mediaDurationMs/waveform', () {
    final original = PendingSend(
      clientMessageId: 'c1',
      relationshipId: 'r1',
      senderId: 'me',
      text: 'hi',
      createdAt: DateTime(2026, 8, 15, 9),
    );
    final restored = PendingSend.fromJson(original.toJson());
    expect(restored.mediaDurationMs, isNull);
    expect(restored.waveform, isNull);
  });
}

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

  group('video message fields', () {
    test('hasVideo is true only when mediaType is video and media is available', () {
      final withLocal = Message(
        id: 'm1',
        clientMessageId: 'c1',
        relationshipId: 'r1',
        senderId: 's1',
        content: '',
        createdAt: DateTime(2026, 8, 15),
        status: MessageStatus.sending,
        isMine: true,
        mediaType: 'video',
        localMediaPath: '/tmp/clip.mp4',
      );
      expect(withLocal.hasVideo, isTrue);

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
      expect(noMedia.hasVideo, isFalse);

      final audioMessage = Message(
        id: 'm3',
        clientMessageId: 'c3',
        relationshipId: 'r1',
        senderId: 's1',
        content: '',
        createdAt: DateTime(2026, 8, 15),
        status: MessageStatus.sent,
        isMine: true,
        mediaType: 'audio',
        signedMediaUrl: 'https://example.com/voice.m4a',
      );
      expect(audioMessage.hasVideo, isFalse);
    });

    test('signedThumbnailUrl is NOT persisted via toJson/fromJson', () {
      final original = Message(
        id: 'm1',
        clientMessageId: 'c1',
        relationshipId: 'r1',
        senderId: 's1',
        content: '',
        createdAt: DateTime(2026, 8, 15, 9),
        status: MessageStatus.sent,
        isMine: true,
        mediaType: 'video',
        mediaKey: 'chat-media/abc.mp4',
        signedMediaUrl: 'https://example.com/abc.mp4',
        signedThumbnailUrl: 'https://example.com/abc.jpg',
      );

      final json = original.toJson();
      expect(json.containsKey('signedThumbnailUrl'), isFalse);

      final restored = Message.fromJson(json);
      expect(restored.signedThumbnailUrl, isNull);
    });

    test('copyWith preserves signedThumbnailUrl when not overridden', () {
      final original = Message(
        id: 'm1',
        clientMessageId: 'c1',
        relationshipId: 'r1',
        senderId: 's1',
        content: '',
        createdAt: DateTime(2026, 8, 15),
        status: MessageStatus.sending,
        isMine: true,
        mediaType: 'video',
        signedThumbnailUrl: 'https://example.com/poster.jpg',
      );
      final copied = original.copyWith(status: MessageStatus.sent);
      expect(copied.signedThumbnailUrl, 'https://example.com/poster.jpg');
    });
  });

  group('ephemeral video fields', () {
    test('isViewOnce defaults to false and viewedAt defaults to null', () {
      final message = Message(
        id: 'm1',
        clientMessageId: 'c1',
        relationshipId: 'r1',
        senderId: 's1',
        content: '',
        createdAt: DateTime(2026, 8, 16),
        status: MessageStatus.sent,
        isMine: true,
        mediaType: 'video',
      );
      expect(message.isViewOnce, isFalse);
      expect(message.viewedAt, isNull);
    });

    test('isEphemeralVideoAvailable is true only when view-once, unviewed, and media is present', () {
      final available = Message(
        id: 'm1',
        clientMessageId: 'c1',
        relationshipId: 'r1',
        senderId: 's1',
        content: '',
        createdAt: DateTime(2026, 8, 16),
        status: MessageStatus.sending,
        isMine: true,
        mediaType: 'video',
        isViewOnce: true,
        localMediaPath: '/tmp/clip.mp4',
      );
      expect(available.isEphemeralVideoAvailable, isTrue);
      expect(available.isEphemeralVideoExpired, isFalse);

      final notViewOnce = available.copyWith(isViewOnce: false);
      expect(notViewOnce.isEphemeralVideoAvailable, isFalse);

      final noMediaYet = Message(
        id: 'm2',
        clientMessageId: 'c2',
        relationshipId: 'r1',
        senderId: 's1',
        content: '',
        createdAt: DateTime(2026, 8, 16),
        status: MessageStatus.sending,
        isMine: true,
        mediaType: 'video',
        isViewOnce: true,
      );
      expect(noMediaYet.isEphemeralVideoAvailable, isFalse);
      expect(noMediaYet.isEphemeralVideoExpired, isFalse);
    });

    test('isEphemeralVideoExpired is true once viewedAt is set, regardless of media presence', () {
      final expired = Message(
        id: 'm1',
        clientMessageId: 'c1',
        relationshipId: 'r1',
        senderId: 's1',
        content: '',
        createdAt: DateTime(2026, 8, 16),
        status: MessageStatus.sent,
        isMine: true,
        mediaType: 'video',
        isViewOnce: true,
        viewedAt: DateTime(2026, 8, 16, 12),
      );
      expect(expired.isEphemeralVideoExpired, isTrue);
      expect(expired.isEphemeralVideoAvailable, isFalse);
    });

    test('a non-view-once video message is never ephemeral-available or -expired', () {
      final ordinary = Message(
        id: 'm1',
        clientMessageId: 'c1',
        relationshipId: 'r1',
        senderId: 's1',
        content: '',
        createdAt: DateTime(2026, 8, 16),
        status: MessageStatus.sent,
        isMine: true,
        mediaType: 'video',
        signedMediaUrl: 'https://example.com/clip.mp4',
      );
      expect(ordinary.isEphemeralVideoAvailable, isFalse);
      expect(ordinary.isEphemeralVideoExpired, isFalse);
      expect(ordinary.hasVideo, isTrue); // unaffected — this is Part 1's gallery-video path
    });

    test('isViewOnce and viewedAt persist through toJson/fromJson', () {
      final original = Message(
        id: 'm1',
        clientMessageId: 'c1',
        relationshipId: 'r1',
        senderId: 's1',
        content: '',
        createdAt: DateTime(2026, 8, 16, 9),
        status: MessageStatus.sent,
        isMine: true,
        mediaType: 'video',
        isViewOnce: true,
        viewedAt: DateTime(2026, 8, 16, 10),
      );
      final restored = Message.fromJson(original.toJson());
      expect(restored.isViewOnce, isTrue);
      expect(restored.viewedAt, DateTime(2026, 8, 16, 10));
    });

    test('copyWith preserves isViewOnce/viewedAt when not overridden', () {
      final original = Message(
        id: 'm1',
        clientMessageId: 'c1',
        relationshipId: 'r1',
        senderId: 's1',
        content: '',
        createdAt: DateTime(2026, 8, 16),
        status: MessageStatus.sending,
        isMine: true,
        mediaType: 'video',
        isViewOnce: true,
      );
      final copied = original.copyWith(status: MessageStatus.sent);
      expect(copied.isViewOnce, isTrue);
      expect(copied.viewedAt, isNull);
    });
  });
}

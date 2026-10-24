import 'dart:convert';

import 'package:attune/features/stories/data/story_outbox_record.dart';
import 'package:attune/features/stories/data/story_repository.dart';
import 'package:attune/features/stories/domain/captured_media.dart';
import 'package:flutter_test/flutter_test.dart';

StoryOutboxRecord _record() => StoryOutboxRecord(
  clientStoryId: 'cid-1',
  relationshipId: 'rel-1',
  localMediaPath: 'story_outbox/u1/cid-1/media.jpg',
  localThumbnailPath: 'story_outbox/u1/cid-1/thumb.jpg',
  mediaType: CapturedMediaType.image,
  mimeType: 'image/jpeg',
  width: 1080,
  height: 1920,
  utcOffsetMinutes: 60,
  createdAt: DateTime.utc(2026, 10, 23, 9),
);

StoryUploadIntent _intent(String kind) => StoryUploadIntent(
  intentId: 'intent-$kind',
  storageKey: 'rel-1/$kind.jpg',
  bucket: 'story-media',
  expiresAt: DateTime.utc(2026, 10, 23, 9, 15),
);

void main() {
  test('intents and strikes survive a JSON round trip', () {
    final record = _record().copyWith(
      state: StoryOutboxState.uploadingThumbnail,
      mediaIntent: _intent('media'),
      thumbnailIntent: _intent('thumbnail'),
      strikes: 2,
    );
    final back = StoryOutboxRecord.fromJson(
      jsonDecode(jsonEncode(record.toJson())) as Map<String, dynamic>,
    );
    expect(back.hasIntents, isTrue);
    expect(back.mediaIntent!.intentId, 'intent-media');
    expect(back.mediaIntent!.storageKey, 'rel-1/media.jpg');
    expect(back.thumbnailIntent!.expiresAt, DateTime.utc(2026, 10, 23, 9, 15));
    expect(back.strikes, 2);
  });

  test('copyWith keeps intents unless told to clear them', () {
    final held = _record().copyWith(
      mediaIntent: _intent('media'),
      thumbnailIntent: _intent('thumbnail'),
    );
    expect(held.copyWith(attempts: 3).hasIntents, isTrue);
    final cleared = held.copyWith(clearIntents: true);
    expect(cleared.mediaIntent, isNull);
    expect(cleared.thumbnailIntent, isNull);
    expect(cleared.hasIntents, isFalse);
  });

  test(
    'a record written by the previous build still loads (Review Focus 3)',
    () {
      // No intents, no strikes, absolute tmp paths: exactly what is on
      // phones today.
      final legacy = {
        'clientStoryId': 'old-1',
        'relationshipId': 'rel-1',
        'localMediaPath': '/private/var/mobile/tmp/capture_1.jpg',
        'localThumbnailPath': '/private/var/mobile/tmp/thumb_1.jpg',
        'mediaType': 'image',
        'mimeType': 'image/jpeg',
        'width': 640,
        'height': 480,
        'durationMs': null,
        'utcOffsetMinutes': 0,
        'state': 'uploadingMedia',
        'attempts': 1,
        'nextAttemptAt': null,
        'lastErrorCode': 'network',
        'createdAt': '2026-10-22T10:00:00.000Z',
      };
      final record = StoryOutboxRecord.fromJson(legacy);
      expect(record.strikes, 0);
      expect(record.hasIntents, isFalse);
      expect(record.localMediaPath, '/private/var/mobile/tmp/capture_1.jpg');
    },
  );

  test('a half-written intent is treated as none', () {
    expect(StoryUploadIntent.fromJson({'intentId': 'x'}), isNull);
    expect(StoryUploadIntent.fromJson(null), isNull);
  });
}

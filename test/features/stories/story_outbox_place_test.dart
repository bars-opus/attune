// test/features/stories/story_outbox_place_test.dart
import 'package:attune/features/couple_map/domain/story_place.dart';
import 'package:attune/features/stories/data/story_outbox_record.dart';
import 'package:attune/features/stories/domain/captured_media.dart';
import 'package:flutter_test/flutter_test.dart';

StoryOutboxRecord _record({StoryPlaceDraft? place}) => StoryOutboxRecord(
  clientStoryId: 'c1',
  relationshipId: 'r1',
  localMediaPath: '/m.jpg',
  localThumbnailPath: '/t.jpg',
  mediaType: CapturedMediaType.image,
  mimeType: 'image/jpeg',
  width: 1080,
  height: 1920,
  utcOffsetMinutes: 0,
  createdAt: DateTime.utc(2026, 10, 16),
  place: place,
);

void main() {
  test('a place survives the JSON round trip', () {
    final r = StoryOutboxRecord.fromJson(
      _record(
        place: const StoryPlaceDraft(
          lat: 5.556123,
          lng: -0.196789,
          label: 'Near Osu, Accra',
        ),
      ).toJson(),
    );
    expect(r.place!.label, 'Near Osu, Accra');
    expect(r.place!.lat, 5.556123);
  });

  test('an old record without a place still decodes (Review Focus 1)', () {
    final json = _record().toJson()..remove('place');
    expect(StoryOutboxRecord.fromJson(json).place, isNull);
  });

  test('a corrupt place decodes as none rather than failing the record', () {
    final json = _record().toJson()..['place'] = {'lat': 'x'};
    expect(StoryOutboxRecord.fromJson(json).place, isNull);
  });

  test('copyWith keeps the place (retries must not drop it)', () {
    final r = _record(
      place: const StoryPlaceDraft(lat: 1, lng: 2, label: 'x'),
    ).copyWith(attempts: 3, state: StoryOutboxState.finalizing);
    expect(r.place!.lng, 2);
  });
}

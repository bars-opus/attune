// test/features/couple_map/story_place_test.dart
import 'package:attune/features/couple_map/domain/story_place.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> _row({String author = 'kofi'}) => {
  'story_item_id': 's1',
  'author_id': author,
  'lat': 5.556123,
  'lng': -0.196789,
  'label': 'Near Osu, Accra',
  'placed_at': '2026-10-16T10:00:00Z',
  'client_story_id': 'c1',
  'media_type': 'image',
  'media_key': 'r/a/m.jpg',
  'thumbnail_key': 'r/a/t.jpg',
  'media_width': 1080,
  'media_height': 1920,
  'duration_ms': null,
  'occurred_on': '2026-10-16',
  'created_at': '2026-10-16T09:59:00Z',
  'expires_at': '2026-10-17T09:59:00Z',
};

void main() {
  test('a row maps to a place carrying a playable story', () {
    final p = StoryPlace.fromRow({..._row(), 'relationship_id': 'r1'});
    expect(
      (p.storyItemId, p.authorId, p.lat, p.lng, p.label),
      ('s1', 'kofi', 5.556123, -0.196789, 'Near Osu, Accra'),
    );
    expect(p.story.id, 's1');
    expect(p.story.thumbnailKey, 'r/a/t.jpg');
    expect(p.story.relationshipId, 'r1');
  });

  test('the draft round-trips and validates like the server', () {
    const d = StoryPlaceDraft(
      lat: 5.556123,
      lng: -0.196789,
      label: 'Near Osu, Accra',
    );
    expect(StoryPlaceDraft.fromJson(d.toJson())!.label, 'Near Osu, Accra');
    expect(d.isValid, isTrue);
    expect(const StoryPlaceDraft(lat: 91, lng: 0, label: 'x').isValid, isFalse);
    expect(const StoryPlaceDraft(lat: 0, lng: 0, label: '  ').isValid, isFalse);
    expect(StoryPlaceDraft.fromJson({'lat': 'x'}), isNull);
    expect(StoryPlaceDraft.fromJson(null), isNull);
  });

  test('a long label is trimmed to 120 on the device too', () {
    final d = StoryPlaceDraft(lat: 0, lng: 0, label: 'a' * 300);
    expect((d.toJson()['label'] as String).length, 120);
  });

  test('the filter cycles Both → Mine → Partner\'s → Both', () {
    expect(StoryFilter.both.next, StoryFilter.mine);
    expect(StoryFilter.mine.next, StoryFilter.partner);
    expect(StoryFilter.partner.next, StoryFilter.both);
  });

  test('labels are neighbourhood-level', () {
    expect(placeLabel(neighbourhood: 'Osu', city: 'Accra'), 'Near Osu, Accra');
    expect(placeLabel(neighbourhood: null, city: 'Accra'), 'Near Accra');
    expect(placeLabel(neighbourhood: 'Accra', city: 'Accra'), 'Near Accra');
    expect(placeLabel(neighbourhood: null, city: null), 'Pinned place');
  });

  test('home area: within about 500 m is near', () {
    const home = HomeArea(lat: 5.556, lng: -0.197);
    expect(home.isNear(5.559, -0.197), isTrue); // ~330 m
    expect(home.isNear(5.566, -0.197), isFalse); // ~1.1 km
  });

  test('a home area never prints its coordinates (checklist 4.4)', () {
    expect(
      const HomeArea(lat: 5.556, lng: -0.197).toString(),
      isNot(contains('5.5')),
    );
  });
}

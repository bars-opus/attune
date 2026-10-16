// test/features/couple_map/couple_map_scene_test.dart
import 'dart:convert';

import 'package:attune/features/couple_map/domain/couple_map_config.dart';
import 'package:attune/features/couple_map/domain/couple_map_scene.dart';
import 'package:attune/features/location/domain/couple_map_presence.dart';
import 'package:attune/features/couple_map/domain/story_place.dart';
import 'support/fakes.dart';
import 'package:flutter_test/flutter_test.dart';

CoupleMapPresence _p({
  String partnerFreshness = 'fresh',
  bool partner = true,
  bool together = false,
}) => CoupleMapPresence.fromRows([
  {'who': 'self', 'cell_lat': 5.565, 'cell_lng': -0.208, 'freshness': 'fresh'},
  if (partner)
    {
      'who': 'partner',
      'cell_lat': 5.575,
      'cell_lng': -0.208,
      'freshness': partnerFreshness,
      'distance_km': together ? 2 : 5,
      'together': together,
    },
]);

void main() {
  test('one area per person, at the server cell centre', () {
    final a = sceneAreas(_p());
    expect(a.map((x) => x.who), [PresenceWho.self, PresenceWho.partner]);
    expect((a.last.centre.lat, a.last.centre.lng), (5.575, -0.208));
  });

  test('fading reads only as opacity (no time, no dot)', () {
    final a = sceneAreas(_p(partnerFreshness: 'fading'));
    expect(a.last.opacity, CoupleMapConfig.fadingOpacity);
    expect(a.first.opacity, 1.0);
  });

  test('no partner row: only my area', () {
    expect(sceneAreas(_p(partner: false)).map((x) => x.who), [
      PresenceWho.self,
    ]);
  });

  test('my row without a cell (accuracy too low): nothing drawn', () {
    final p = CoupleMapPresence.fromRows([
      {'who': 'self', 'city': 'Accra', 'freshness': 'fresh'},
    ]);
    expect(sceneAreas(p), isEmpty);
  });

  test(
    'GeoJSON: polygons only, carrying opacity; together draws one shared area',
    () {
      final apart =
          jsonDecode(areasGeoJson(sceneAreas(_p()), together: false)) as Map;
      final features = apart['features'] as List;
      expect(features, hasLength(2));
      for (final f in features) {
        expect(f['geometry']['type'], 'Polygon');
        expect(f['properties']['opacity'], isA<num>());
      }
      final together =
          jsonDecode(
                areasGeoJson(sceneAreas(_p(together: true)), together: true),
              )
              as Map;
      expect(together['features'], hasLength(1));
    },
  );

  test(
    'story pins: oldest rank 0, newest highest; GeoJSON points carry id and rank, no time',
    () {
      final places = [
        StoryPlace.fromRow(
          storyPlaceRow('new', created: '2026-10-16T10:00:00Z'),
        ),
        StoryPlace.fromRow(
          storyPlaceRow('old', created: '2026-10-01T10:00:00Z'),
        ),
      ];
      final pins = storyScenePins(places);
      expect(
        {for (final p in pins) p.storyItemId: p.rank},
        {'old': 0, 'new': 1},
      );
      final fc = jsonDecode(storiesGeoJson(pins)) as Map;
      final f = (fc['features'] as List).first as Map;
      expect(f['geometry']['type'], 'Point');
      expect((f['properties'] as Map).keys.toSet(), {'id', 'rank'});
    },
  );
}

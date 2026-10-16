import 'dart:convert';

import 'package:attune/features/couple_map/domain/couple_map_config.dart';
import 'package:attune/features/couple_map/domain/map_geometry.dart';
import 'package:attune/features/couple_map/domain/story_place.dart';
import 'package:attune/features/location/domain/couple_map_presence.dart';
import 'package:flutter/foundation.dart';

enum PresenceWho { self, partner }

@immutable
class SceneArea {
  const SceneArea({
    required this.who,
    required this.centre,
    required this.opacity,
  });
  final PresenceWho who;
  final MapPoint centre;
  final double opacity;
}

double _opacity(PresenceFreshness f) =>
    f == PresenceFreshness.fresh ? 1.0 : CoupleMapConfig.fadingOpacity;

SceneArea? _area(PresenceWho who, PresenceArea? a) {
  final lat = a?.cellLat;
  final lng = a?.cellLng;
  if (a == null || lat == null || lng == null) return null;
  return SceneArea(
    who: who,
    centre: MapPoint(lat, lng),
    opacity: _opacity(a.freshness),
  );
}

/// What the map draws: at most my area and my partner's, at server cell
/// centres. A row without a cell (only a city) draws nothing.
List<SceneArea> sceneAreas(CoupleMapPresence p) => [
  if (_area(PresenceWho.self, p.self) case final s?) s,
  if (_area(PresenceWho.partner, p.partner) case final s?) s,
];

/// The areas as a GeoJSON FeatureCollection of polygons. Together (same
/// or adjacent cell) draws one shared area, under both avatars.
String areasGeoJson(List<SceneArea> areas, {required bool together}) {
  final drawn = together && areas.length > 1 ? [areas.first] : areas;
  return jsonEncode({
    'type': 'FeatureCollection',
    'features': [
      for (final a in drawn)
        {
          'type': 'Feature',
          'properties': {'who': a.who.name, 'opacity': a.opacity},
          'geometry': {
            'type': 'Polygon',
            'coordinates': [
              [
                for (final p in areaRing(a.centre)) [p.lng, p.lat],
              ],
            ],
          },
        },
    ],
  });
}

@immutable
class StoryScenePin {
  const StoryScenePin({
    required this.storyItemId,
    required this.at,
    required this.rank,
  });
  final String storyItemId;
  final MapPoint at;
  final int rank;
}

/// Oldest gets rank 0, so a cluster's "top" (max rank) is its newest story.
List<StoryScenePin> storyScenePins(List<StoryPlace> places) {
  final sorted = [...places]
    ..sort((a, b) => a.story.createdAt.compareTo(b.story.createdAt));
  return [
    for (var i = 0; i < sorted.length; i++)
      StoryScenePin(
        storyItemId: sorted[i].storyItemId,
        at: MapPoint(sorted[i].lat, sorted[i].lng),
        rank: i,
      ),
  ];
}

/// Points carrying only an id and a rank: no time, no author, no label.
String storiesGeoJson(List<StoryScenePin> pins) => jsonEncode({
  'type': 'FeatureCollection',
  'features': [
    for (final p in pins)
      {
        'type': 'Feature',
        'properties': {'id': p.storyItemId, 'rank': p.rank},
        'geometry': {
          'type': 'Point',
          'coordinates': [p.at.lng, p.at.lat],
        },
      },
  ],
});

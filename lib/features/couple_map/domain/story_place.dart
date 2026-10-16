import 'package:attune/features/couple_map/domain/couple_map_config.dart';
import 'package:attune/features/couple_map/domain/map_geometry.dart';
import 'package:attune/features/stories/data/story_read_repository.dart';
import 'package:flutter/foundation.dart';

/// A place the author chose to attach at post time (exact, by choice).
@immutable
class StoryPlaceDraft {
  const StoryPlaceDraft({
    required this.lat,
    required this.lng,
    required this.label,
  });
  final double lat;
  final double lng;
  final String label;

  /// Mirrors SQL story_place_parse, so the outbox never carries a place
  /// the server would drop.
  bool get isValid =>
      lat >= -90 &&
      lat <= 90 &&
      lng >= -180 &&
      lng <= 180 &&
      label.trim().isNotEmpty;

  Map<String, dynamic> toJson() {
    final l = label.trim();
    return {
      'lat': lat,
      'lng': lng,
      'label': l.length > 120 ? l.substring(0, 120) : l,
    };
  }

  static StoryPlaceDraft? fromJson(Object? json) {
    if (json is! Map) return null;
    final lat = json['lat'];
    final lng = json['lng'];
    final label = json['label'];
    if (lat is! num || lng is! num || label is! String) return null;
    return StoryPlaceDraft(
      lat: lat.toDouble(),
      lng: lng.toDouble(),
      label: label,
    );
  }

  @override
  String toString() => 'StoryPlaceDraft(redacted)';
}

/// A pinned story, as list_story_places returns it.
@immutable
class StoryPlace {
  const StoryPlace({
    required this.storyItemId,
    required this.authorId,
    required this.lat,
    required this.lng,
    required this.label,
    required this.story,
  });
  final String storyItemId;
  final String authorId;
  final double lat;
  final double lng;
  final String label;
  final StoryItem story;

  factory StoryPlace.fromRow(Map<String, dynamic> r) => StoryPlace(
    storyItemId: '${r['story_item_id']}',
    authorId: '${r['author_id']}',
    lat: (r['lat'] as num).toDouble(),
    lng: (r['lng'] as num).toDouble(),
    label: '${r['label']}',
    story: StoryItem.fromRow({
      ...r,
      'id': r['story_item_id'],
      // Map pins are memories, not unread rings.
      'has_been_viewed': true,
    }),
  );

  @override
  String toString() => 'StoryPlace($storyItemId)';
}

enum StoryFilter {
  both,
  mine,
  partner;

  StoryFilter get next =>
      StoryFilter.values[(index + 1) % StoryFilter.values.length];
}

/// Neighbourhood-level label for the preview and the pin (spec §3.3).
String placeLabel({String? neighbourhood, String? city}) {
  final n = neighbourhood?.trim();
  final c = city?.trim();
  if (n != null && n.isNotEmpty && c != null && c.isNotEmpty && n != c) {
    return 'Near $n, $c';
  }
  if (c != null && c.isNotEmpty) return 'Near $c';
  if (n != null && n.isNotEmpty) return 'Near $n';
  return 'Pinned place';
}

/// The optional, device-only home area (spec §3.3). Never leaves the device.
@immutable
class HomeArea {
  const HomeArea({required this.lat, required this.lng});
  final double lat;
  final double lng;

  bool isNear(double lat, double lng) =>
      haversineKm(MapPoint(this.lat, this.lng), MapPoint(lat, lng)) * 1000 <=
      CoupleMapConfig.homeAreaRadiusM;

  @override
  String toString() => 'HomeArea(redacted)';
}

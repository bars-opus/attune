import 'package:attune/features/couple_map/domain/couple_map_config.dart';
import 'package:attune/features/couple_map/domain/story_place.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

abstract class StoryPlacesGateway {
  Future<dynamic> rpc(String fn, {Map<String, dynamic>? params});
}

class SupabaseStoryPlacesGateway implements StoryPlacesGateway {
  SupabaseStoryPlacesGateway(this._supabase);
  final SupabaseClient _supabase;
  @override
  Future<dynamic> rpc(String fn, {Map<String, dynamic>? params}) =>
      _supabase.rpc(fn, params: params);
}

/// Story places, through their RPCs only. Logs carry no place (4.4).
class StoryPlacesRepository {
  StoryPlacesRepository(this._gateway);
  final StoryPlacesGateway _gateway;

  /// Newest first, at most 500, in the world box (ruling: a couple's pins
  /// fit; the box stays for later viewport fetching). Throws on failure,
  /// so the map keeps its last pins instead of emptying.
  Future<List<StoryPlace>> list(
    String relationshipId, {
    String? authorId,
  }) async {
    try {
      final rows = await _gateway.rpc(
        'list_story_places',
        params: {
          'p_relationship_id': relationshipId,
          'p_author_id': authorId,
          'p_min_lat': -90,
          'p_min_lng': -180,
          'p_max_lat': 90,
          'p_max_lng': 180,
          'p_limit': CoupleMapConfig.placesLimit,
        },
      );
      if (rows is! List) {
        throw StateError('list_story_places returned ${rows.runtimeType}');
      }
      // The RPC doesn't repeat the relationship; the story model needs it.
      return [
        for (final r in rows)
          StoryPlace.fromRow({
            ...Map<String, dynamic>.from(r as Map),
            'relationship_id': relationshipId,
          }),
      ];
    } catch (e) {
      debugPrint('story places: list failed (${e.runtimeType})');
      rethrow;
    }
  }

  Future<void> clear(String storyItemId) => _gateway.rpc(
    'clear_story_place',
    params: {'p_story_item_id': storyItemId},
  );

  Future<int> clearMine(String relationshipId) async {
    final n = await _gateway.rpc(
      'clear_my_story_places',
      params: {'p_relationship_id': relationshipId},
    );
    return (n as num?)?.toInt() ?? 0;
  }
}

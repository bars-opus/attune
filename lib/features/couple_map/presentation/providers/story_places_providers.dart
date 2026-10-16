import 'package:attune/features/couple_map/data/couple_map_local_store.dart';
import 'package:attune/features/couple_map/data/story_place_resolver.dart';
import 'package:attune/features/couple_map/data/story_places_repository.dart';
import 'package:attune/features/couple_map/domain/story_place.dart';
import 'package:attune/features/games/presentation/providers/games_hub_providers.dart'
    show supabaseClientProvider;
import 'package:attune/features/stories/presentation/providers/story_providers.dart'
    show storyChangeSignalProvider;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final storyPlacesGatewayProvider = Provider<StoryPlacesGateway>(
  (ref) => SupabaseStoryPlacesGateway(ref.watch(supabaseClientProvider)),
);
final storyPlacesRepositoryProvider = Provider<StoryPlacesRepository>(
  (ref) => StoryPlacesRepository(ref.watch(storyPlacesGatewayProvider)),
);
final coupleMapLocalStoreProvider = Provider<CoupleMapLocalStore>(
  (ref) => SecureCoupleMapLocalStore(),
);
final storyPlaceResolverProvider = Provider<StoryPlaceResolver>(
  (ref) => GeolocatorStoryPlaceResolver(),
);

@immutable
class StoryPlacesKey {
  const StoryPlacesKey(this.relationshipId, {this.authorId});
  final String relationshipId;
  final String? authorId;
  @override
  bool operator ==(Object other) =>
      other is StoryPlacesKey &&
      other.relationshipId == relationshipId &&
      other.authorId == authorId;
  @override
  int get hashCode => Object.hash(relationshipId, authorId);
}

/// Pinned stories for the map, refetched whenever the couple's story
/// signal bumps (a new story, a delete, a place cleared on either side).
final storyPlacesProvider = FutureProvider.autoDispose
    .family<List<StoryPlace>, StoryPlacesKey>((ref, key) {
      ref.watch(storyChangeSignalProvider(key.relationshipId));
      return ref
          .watch(storyPlacesRepositoryProvider)
          .list(key.relationshipId, authorId: key.authorId);
    });

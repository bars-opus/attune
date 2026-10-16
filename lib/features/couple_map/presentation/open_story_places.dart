import 'package:attune/features/couple_map/domain/story_place.dart';
import 'package:attune/features/stories/presentation/screens/story_reel_screen.dart';
import 'package:flutter/material.dart';

/// Opens the reel over the stories behind a tapped pin, cluster or list
/// row: [storyIds] looked up in [places], oldest first (spec §3.3).
void openStoryPlaces(
  BuildContext context, {
  required String relationshipId,
  required List<StoryPlace> places,
  required List<String> storyIds,
}) {
  final wanted = storyIds.toSet();
  final items = [
    for (final p in places)
      if (wanted.contains(p.storyItemId)) p.story,
  ]..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  if (items.isEmpty) return;
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder:
          (_) => StoryReelScreen.forPlaces(
            relationshipId: relationshipId,
            items: items,
          ),
    ),
  );
}

// test/features/couple_map/story_places_repository_test.dart
import 'package:attune/features/couple_map/data/story_places_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

void main() {
  test('list asks for the world box, capped, optionally one author', () async {
    final g = FakeStoryPlacesGateway({
      'list_story_places': (_) => [storyPlaceRow('s1')],
    });
    final r = StoryPlacesRepository(g);
    final places = await r.list('r1', authorId: 'kofi');
    expect(places.single.storyItemId, 's1');
    final p = g.calls.single.$2;
    expect(
      (
        p['p_relationship_id'],
        p['p_author_id'],
        p['p_min_lat'],
        p['p_min_lng'],
        p['p_max_lat'],
        p['p_max_lng'],
        p['p_limit'],
      ),
      ('r1', 'kofi', -90, -180, 90, 180, 500),
    );
  });

  test(
    'a failed list throws (the map keeps its last pins), never reads as empty',
    () async {
      final g = FakeStoryPlacesGateway({
        'list_story_places': (_) => throw Exception('offline'),
      });
      await expectLater(
        StoryPlacesRepository(g).list('r1'),
        throwsA(isA<Exception>()),
      );
    },
  );

  test('clear one and clear mine call their RPCs', () async {
    final g = FakeStoryPlacesGateway({'clear_my_story_places': (_) => 3});
    final r = StoryPlacesRepository(g);
    await r.clear('s1');
    expect(await r.clearMine('r1'), 3);
    expect(g.calls.map((c) => (c.$1, c.$2.values.single)), [
      ('clear_story_place', 's1'),
      ('clear_my_story_places', 'r1'),
    ]);
  });
}

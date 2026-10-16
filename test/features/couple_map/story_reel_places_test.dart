// test/features/couple_map/story_reel_places_test.dart
import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:attune/features/couple_map/domain/story_place.dart';
import 'package:attune/features/couple_map/presentation/providers/story_places_providers.dart';
import 'package:attune/features/stories/presentation/providers/story_providers.dart';
import 'package:attune/features/stories/presentation/screens/story_reel_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;

import 'support/fakes.dart';

import '../stories/support/fake_story_read_gateway.dart';

User _user(String id) => User(
  id: id,
  appMetadata: const {},
  userMetadata: const {},
  aud: 'authenticated',
  createdAt: '2026-01-01',
);

Future<FakeStoryPlacesGateway> _pump(
  WidgetTester t, {
  required String me,
  required List<String> authors,
}) async {
  final g = FakeStoryPlacesGateway();
  final items = [
    for (var i = 0; i < authors.length; i++)
      StoryPlace.fromRow(
        storyPlaceRow(
          's$i',
          author: authors[i],
          created: '2026-10-1${i}T10:00:00Z',
        ),
      ).story,
  ];
  // Pushed over a base route, as story_reel_test does: _close() pops, and
  // a root route can't pop.
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        currentUserProvider.overrideWithValue(_user(me)),
        storyPlacesGatewayProvider.overrideWithValue(g),
        storyReadGatewayProvider.overrideWithValue(FakeStoryReadGateway()),
      ],
      child: MaterialApp(
        home: Builder(
          builder:
              (context) => Scaffold(
                body: TextButton(
                  onPressed:
                      () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder:
                              (_) => StoryReelScreen.forPlaces(
                                relationshipId: 'r1',
                                items: items,
                              ),
                        ),
                      ),
                  child: const Text('open'),
                ),
              ),
        ),
      ),
    ),
  );
  await t.tap(find.text('open'));
  await t.pump();
  await t.pump(const Duration(milliseconds: 400));
  return g;
}

void main() {
  testWidgets('the author sees "Remove from map" next to Delete', (t) async {
    await _pump(t, me: 'ama', authors: ['ama']);
    expect(
      find.byKey(const ValueKey('story-reel-remove-place')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('story-reel-delete')), findsOneWidget);
  });

  testWidgets("the partner sees neither on the author's story", (t) async {
    await _pump(t, me: 'ama', authors: ['kofi']);
    expect(
      find.byKey(const ValueKey('story-reel-remove-place')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('story-reel-delete')), findsNothing);
  });

  testWidgets(
    'remove from map takes it off and closes the last one (Review Focus 4)',
    (t) async {
      final g = await _pump(t, me: 'ama', authors: ['ama']);
      await t.tap(find.byKey(const ValueKey('story-reel-remove-place')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      await t.tap(find.text('Remove'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      expect(g.calls.map((c) => c.$1), contains('clear_story_place'));
      expect(find.byType(StoryReelScreen), findsNothing);
    },
  );

  testWidgets(
    'deleting the first of two in places mode shows the survivor, not a close',
    (t) async {
      await _pump(t, me: 'ama', authors: ['ama', 'ama']);
      await t.tap(find.byKey(const ValueKey('story-reel-delete')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      await t.tap(find.text('Delete'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      expect(find.byType(StoryReelScreen), findsOneWidget);
    },
  );

  testWidgets('remove asks first: cancel keeps it', (t) async {
    final g = await _pump(t, me: 'ama', authors: ['ama', 'ama']);
    await t.tap(find.byKey(const ValueKey('story-reel-remove-place')));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    await t.tap(find.text('Cancel'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    expect(g.calls, isEmpty);
  });
}

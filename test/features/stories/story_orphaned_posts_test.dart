// 03 M6: a story queued for a relationship that is no longer the one shown
// (ended, archived) can never post. It used to sit on the phone with no
// surface anywhere; it now gets one grouped notice with Discard.
import 'dart:io';

import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:attune/features/stories/data/story_outbox_backend_stub.dart'
    as stub;
import 'package:attune/features/stories/data/story_outbox_record.dart';
import 'package:attune/features/stories/data/story_outbox_store.dart';
import 'package:attune/features/stories/data/story_repository.dart';
import 'package:attune/features/stories/presentation/state/story_outbox_controller.dart';
import 'package:attune/features/stories/presentation/widgets/story_outbox_notices.dart';
import 'package:attune/features/stories/domain/captured_media.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/ring_test_kit.dart';

StoryOutboxRecord _record(
  String id,
  String relationshipId,
  StoryOutboxState state,
) => StoryOutboxRecord(
  clientStoryId: id,
  relationshipId: relationshipId,
  localMediaPath: '/tmp/$id-media.jpg',
  localThumbnailPath: '',
  mediaType: CapturedMediaType.image,
  mimeType: 'image/jpeg',
  width: 1080,
  height: 1920,
  utcOffsetMinutes: 0,
  state: state,
  createdAt: DateTime.utc(2026, 10, 20, 8),
);

/// With both intents a finalizing row goes straight to finalize, which the
/// rings kit's gateway never answers: finalize has been sent.
StoryUploadIntent _intent(String kind) => StoryUploadIntent(
  intentId: 'i-$kind',
  storageKey: 'k-$kind',
  bucket: 'story-media',
  expiresAt: DateTime.now().add(const Duration(minutes: 15)),
);

void main() {
  testWidgets("a failed post for a previous relationship says so and can go", (
    tester,
  ) async {
    await pumpRings(
      tester,
      RingGateway(),
      outbox: [_record('o1', 'rel-old', StoryOutboxState.failedPermanent)],
    );
    await tester.pump();
    expect(
      find.text("A story for a previous relationship couldn't be posted."),
      findsOneWidget,
    );
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(find.text('Discard this story?'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Discard').last);
    await tester.pumpAndSettle();
    // Discard deletes the capture's files: real I/O, outside fake time.
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 15)),
      );
      await tester.pump();
    }
    expect(find.textContaining('previous relationship'), findsNothing);
  });

  testWidgets('two of them are one notice, counted', (tester) async {
    await pumpRings(
      tester,
      RingGateway(),
      outbox: [
        _record('o1', 'rel-old', StoryOutboxState.failedPermanent),
        _record('o2', 'rel-older', StoryOutboxState.failedPermanent),
      ],
    );
    await tester.pump();
    expect(
      find.text("2 stories for a previous relationship couldn't be posted."),
      findsOneWidget,
    );
  });

  testWidgets("this relationship's own failed post is not an orphan", (
    tester,
  ) async {
    await pumpRings(
      tester,
      RingGateway(),
      outbox: [_record('f1', ringRel, StoryOutboxState.failedPermanent)],
    );
    await tester.pump();
    expect(find.textContaining('previous relationship'), findsNothing);
  });

  test(
    'Conversations shows the notice when there is no active relationship',
    () {
      final screen =
          File(
            'lib/features/chat/presentation/screens/conversations_screen.dart',
          ).readAsStringSync();
      expect(
        screen.contains('StoryOrphanedPostsNotice(activeRelationshipId: null)'),
        isTrue,
      );
    },
  );

  // Batch-4 review #4: a Discard that comes too late says so.
  testWidgets('discarding one that may already have posted says so', (
    tester,
  ) async {
    await pumpRings(
      tester,
      RingGateway(),
      outbox: [
        _record(
          'o1',
          'rel-old',
          StoryOutboxState.finalizing,
        ).copyWith(mediaIntent: _intent('m'), thumbnailIntent: _intent('t')),
      ],
    );
    await tester.pump();
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Discard').last);
    await tester.pumpAndSettle();
    expect(
      find.text('It may already have posted — check your story.'),
      findsOneWidget,
    );
  });

  // Batch-2 review nit 7: inside the rings row the `+` overhang is the gap
  // above a notice. On Conversations with no relationship there is no row,
  // so the notice brings the row's own 8 dp top and 16 dp inset.
  testWidgets('outside the rings row it keeps the row\'s spacing', (
    tester,
  ) async {
    final store = StoryOutboxStore.forTesting(stub.createStoryOutboxBackend());
    await store.put(
      ringMe,
      _record('o1', 'rel-old', StoryOutboxState.failedPermanent),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserProvider.overrideWithValue(ringUser),
          storyOutboxStoreProvider.overrideWithValue(store),
          storyGatewayProvider.overrideWithValue(HangingStoryGateway()),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: StoryOrphanedPostsNotice(activeRelationshipId: null),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    final notice = tester.getRect(find.byType(StoryOrphanedPostsNotice));
    final icon = tester.getRect(find.byIcon(Icons.error_outline_rounded));
    final row = tester.getRect(
      find
          .ancestor(
            of: find.byIcon(Icons.error_outline_rounded),
            matching: find.byType(Row),
          )
          .first,
    );
    expect(row.top - notice.top, 8);
    expect(icon.left - notice.left, 16);
    expect(notice.right - row.right, 16);
  });
}

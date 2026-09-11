// Tests for the durable story outbox (Plan B, Task 5, spec §6.1).
//
// This store is the entire reason Task 5 exists: "A story is captured in
// the moment, often on poor connectivity, and a failed upload that
// silently vanishes is worse here than in chat — there is no bubble to
// show a retry affordance." Three properties matter most and each gets
// its own test:
//
//   1. Durability — a queued story survives a restart. Proven for real:
//      write through a dart:io Drift/SQLite backend pointed at a temp
//      file, close that connection, open a *fresh* StoryOutboxStore
//      against the same file, and read the record back. A test that
//      merely re-reads through a connection that was never closed would
//      prove nothing about restart.
//   2. clientStoryId is stable across retries — enqueue once, update the
//      record across simulated attempts, and the id never changes and
//      the row count never grows past one.
//   3. A permanent failure is retained, not dropped — a failedPermanent
//      record stays readable via readAll so the UI can offer Retry and
//      Discard (it "never silently disappears").
//
// The io backend is used directly (not through the stub) because
// durability is the property under test — an in-memory stub would pass
// test 1 trivially without proving anything about SQLite persistence.

import 'dart:io';

import 'package:attune/features/stories/data/story_outbox_backend_io.dart';
import 'package:attune/features/stories/data/story_outbox_record.dart';
import 'package:attune/features/stories/data/story_outbox_store.dart';
import 'package:attune/features/stories/domain/captured_media.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tempDir;
  late File dbFile;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('story_outbox_test');
    dbFile = File('${tempDir.path}/story_outbox.sqlite');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  StoryOutboxRecord buildRecord({
    String clientStoryId = 'client-story-1',
    StoryOutboxState state = StoryOutboxState.queued,
    int attempts = 0,
    String? lastErrorCode,
  }) {
    return StoryOutboxRecord(
      clientStoryId: clientStoryId,
      relationshipId: 'rel-1',
      localMediaPath: '/tmp/media.jpg',
      localThumbnailPath: '/tmp/thumb.jpg',
      mediaType: CapturedMediaType.image,
      mimeType: 'image/jpeg',
      width: 1080,
      height: 1920,
      durationMs: null,
      utcOffsetMinutes: -300,
      state: state,
      attempts: attempts,
      lastErrorCode: lastErrorCode,
      createdAt: DateTime.utc(2026, 9, 11, 12),
    );
  }

  test('a queued story survives a restart', () async {
    const userId = 'user-1';
    final record = buildRecord();

    // "Restart" #1: write through a store backed by a real SQLite file,
    // then close the connection entirely.
    final firstStore = StoryOutboxStore.forTesting(
      createStoryOutboxBackend(file: dbFile),
    );
    await firstStore.put(userId, record);
    await firstStore.disposeForTesting();

    // "Restart" #2: a brand new store, a brand new connection, same
    // file. Nothing from the first store is held in memory anymore.
    final reopenedStore = StoryOutboxStore.forTesting(
      createStoryOutboxBackend(file: dbFile),
    );
    final recordsAfterRestart = await reopenedStore.readAll(userId);
    await reopenedStore.disposeForTesting();

    expect(recordsAfterRestart, hasLength(1));
    final restored = recordsAfterRestart.single;
    expect(restored.clientStoryId, record.clientStoryId);
    expect(restored.relationshipId, record.relationshipId);
    expect(restored.localMediaPath, record.localMediaPath);
    expect(restored.localThumbnailPath, record.localThumbnailPath);
    expect(restored.mediaType, record.mediaType);
    expect(restored.mimeType, record.mimeType);
    expect(restored.width, record.width);
    expect(restored.height, record.height);
    expect(restored.utcOffsetMinutes, record.utcOffsetMinutes);
    expect(restored.state, StoryOutboxState.queued);
    expect(restored.createdAt, record.createdAt);
  });

  test('clientStoryId is stable across retries', () async {
    // A retry with the same id lands on the same server row via
    // create_story_item's idempotency on (author_id, client_story_id) —
    // worth nothing if the client mints a fresh id per attempt. The id
    // is generated once, at enqueue, and every subsequent write for this
    // capture must reuse it.
    const userId = 'user-1';
    const clientStoryId = 'stable-id-across-retries';
    final store = StoryOutboxStore.forTesting(
      createStoryOutboxBackend(file: dbFile),
    );
    addTearDown(store.disposeForTesting);

    final enqueued = buildRecord(clientStoryId: clientStoryId);
    await store.put(userId, enqueued);

    // Simulate the outbox recording three failed attempts, each retry
    // reusing the same clientStoryId the way Task 6's state machine
    // will — never regenerating it.
    var current = enqueued;
    for (var attempt = 1; attempt <= 3; attempt++) {
      current = current.copyWith(
        state: StoryOutboxState.uploadingMedia,
        attempts: attempt,
        lastErrorCode: 'network',
      );
      expect(current.clientStoryId, clientStoryId);
      await store.put(userId, current);
    }

    final rows = await store.readAll(userId);

    // Still exactly one row: three "retries" that reuse the id update
    // the same record rather than accumulating duplicates.
    expect(rows, hasLength(1));
    expect(rows.single.clientStoryId, clientStoryId);
    expect(rows.single.attempts, 3);
  });

  test('a permanent failure is retained, not dropped', () async {
    // Spec §6.1: "it never silently disappears." A failedPermanent
    // record must stay readable so the UI can offer Retry and Discard —
    // proving the store never auto-removes on failure, only on an
    // explicit remove() (success or user Discard).
    const userId = 'user-1';
    final store = StoryOutboxStore.forTesting(
      createStoryOutboxBackend(file: dbFile),
    );
    addTearDown(store.disposeForTesting);

    final failed = buildRecord(
      clientStoryId: 'permanently-failed',
      state: StoryOutboxState.failedPermanent,
      attempts: 5,
      lastErrorCode: 'FORBIDDEN',
    );
    await store.put(userId, failed);

    final rows = await store.readAll(userId);

    expect(rows, hasLength(1));
    expect(rows.single.state, StoryOutboxState.failedPermanent);
    expect(rows.single.lastErrorCode, 'FORBIDDEN');
    expect(rows.single.attempts, 5);

    // A second read proves it is not a one-shot/consumed value — the UI
    // can poll this repeatedly while showing Retry/Discard.
    final rowsAgain = await store.readAll(userId);
    expect(rowsAgain, hasLength(1));
    expect(rowsAgain.single.state, StoryOutboxState.failedPermanent);

    // Only an explicit remove (Discard, or success) clears it.
    await store.remove(userId, 'permanently-failed');
    expect(await store.readAll(userId), isEmpty);
  });
}

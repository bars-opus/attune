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
//
// Fix round 1: spec §6.1 says the queue "reuses the encrypted
// SQLite/cache patterns behind the chat outbox" — the store originally
// wrote plaintext JSON. A fourth test now proves the payload column is
// actually encrypted on disk: write a record carrying a recognisable
// marker string, read the RAW bytes of the sqlite file (not through the
// store), and assert the marker is absent — then assert the record
// still round-trips correctly through the store. A round-trip check
// alone proves nothing about encryption, since it passes identically on
// plaintext; reading the file's raw bytes is the only way to prove the
// marker isn't sitting there in the clear.
//
// Fix round 2: the plaintext `created_at` ordering column was stamped
// with DateTime.now() at write time instead of the record's own
// createdAt (which travels inside the encrypted payload). Task 6 drains
// the queue FIFO via `ORDER BY created_at ASC` — a record whose domain
// createdAt disagreed with its row's created_at would drain out of
// order, invisibly, since the payload's own value is encrypted and
// unreadable by the query. A fifth test enqueues two records whose
// createdAt values are deliberately out of wall-clock/insertion order
// (the earlier-createdAt record is put() SECOND) and asserts readAll
// still returns them in createdAt order — which is only possible if the
// ordering column tracks the record's createdAt rather than write time.

import 'dart:convert';
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
    DateTime? createdAt,
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
      createdAt: createdAt ?? DateTime.utc(2026, 9, 11, 12),
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

  test(
    'readAll orders by the record\'s createdAt, not write/insertion order',
    () async {
      // Under the pre-fix code, the ordering column was stamped with
      // DateTime.now() at write time — both rows would get near-identical
      // now() timestamps a few microseconds apart, so asserting order
      // would be a coin flip. These two createdAt values are 30 days
      // apart, so the assertion below can only pass deterministically —
      // by tracking the record's own createdAt — never by luck.
      const userId = 'user-1';
      final earlier = DateTime.utc(2026, 1, 1);
      final later = DateTime.utc(2026, 1, 31);

      final store = StoryOutboxStore.forTesting(
        createStoryOutboxBackend(file: dbFile),
      );
      addTearDown(store.disposeForTesting);

      // Enqueue the LATER-createdAt record FIRST, and the EARLIER one
      // SECOND — insertion order is the opposite of createdAt order, so
      // a correct implementation must consult createdAt, not write time.
      final recordB = buildRecord(clientStoryId: 'story-b-later', createdAt: later);
      await store.put(userId, recordB);

      final recordA = buildRecord(
        clientStoryId: 'story-a-earlier',
        createdAt: earlier,
      );
      await store.put(userId, recordA);

      final rows = await store.readAll(userId);

      expect(rows, hasLength(2));
      expect(
        rows.map((r) => r.clientStoryId).toList(),
        ['story-a-earlier', 'story-b-later'],
        reason:
            'readAll must order by each record\'s own createdAt '
            '(earlier first), not by insertion/write order.',
      );
    },
  );

  test('the payload is encrypted at rest, not written as plaintext', () async {
    const userId = 'user-1';
    const marker = '/tmp/story-secret-marker.jpg';
    final store = StoryOutboxStore.forTesting(
      createStoryOutboxBackend(file: dbFile),
    );

    final base = buildRecord();
    // buildRecord's localMediaPath is fixed; rebuild with the marker path
    // so it's unambiguously ours and easy to grep for below. localMediaPath
    // isn't one of copyWith's fields, so a record literal is used instead.
    final markedRecord = StoryOutboxRecord(
      clientStoryId: base.clientStoryId,
      relationshipId: base.relationshipId,
      localMediaPath: marker,
      localThumbnailPath: base.localThumbnailPath,
      mediaType: base.mediaType,
      mimeType: base.mimeType,
      width: base.width,
      height: base.height,
      durationMs: base.durationMs,
      utcOffsetMinutes: base.utcOffsetMinutes,
      state: base.state,
      attempts: base.attempts,
      lastErrorCode: base.lastErrorCode,
      createdAt: base.createdAt,
    );

    await store.put(userId, markedRecord);
    // Force a checkpoint so WAL contents land in the main db file before
    // it's read directly — otherwise a recent write can still be sitting
    // in the -wal sidecar file instead of story_outbox.sqlite itself.
    await store.disposeForTesting();

    // Read every file the sqlite/WAL machinery may have written, not
    // just the main db file, so a marker sitting in a -wal or -shm
    // sidecar can't slip past this check.
    final candidateFiles = [
      dbFile,
      File('${dbFile.path}-wal'),
      File('${dbFile.path}-shm'),
      File('${dbFile.path}-journal'),
    ].where((f) => f.existsSync());

    for (final file in candidateFiles) {
      final rawBytes = file.readAsBytesSync();
      final rawLatin1 = latin1.decode(rawBytes, allowInvalid: true);
      expect(
        rawLatin1,
        isNot(contains(marker)),
        reason:
            'Found the plaintext marker in ${file.path} — the payload '
            'column is not encrypted at rest.',
      );
    }

    // The record still round-trips correctly through the store — proves
    // this is encryption, not corruption or data loss.
    final reopenedStore = StoryOutboxStore.forTesting(
      createStoryOutboxBackend(file: dbFile),
    );
    final rows = await reopenedStore.readAll(userId);
    await reopenedStore.disposeForTesting();

    expect(rows, hasLength(1));
    expect(rows.single.localMediaPath, marker);
    expect(rows.single.clientStoryId, markedRecord.clientStoryId);
  });

  // The keystore-unavailable path, which reached review twice without a
  // test and survived both Plan B and Plan C as a parked note.
  //
  // Fail-closed is correct: refusing to write plaintext story metadata to
  // disk matches ChatCacheService. The bug was that put() returned void,
  // so every caller treated a refused write as a successful one -- the
  // camera popped and the user believed a story was posted that had never
  // been queued and would never retry. put() now reports it.
  test('put() reports false when the cipher is unavailable, and writes '
      'nothing', () async {
    const userId = 'user-1';
    final record = buildRecord();

    // `cipherUnavailable` rather than `cipher: null`: _ensureInitialized
    // fills a null cipher back in via `??=`, and the secure-storage
    // plugin succeeds in a test host, so a null argument alone cannot
    // express a keystore failure. Not being able to express it is
    // precisely why this path reached review twice untested.
    final store = StoryOutboxStore.forTesting(
      createStoryOutboxBackend(file: dbFile),
      cipherUnavailable: true,
    );

    expect(
      await store.put(userId, record),
      isFalse,
      reason: 'a refused encryption must be reported, not swallowed',
    );
    expect(
      await store.readAll(userId),
      isEmpty,
      reason: 'nothing may be persisted when the cipher is unavailable',
    );

    await store.disposeForTesting();
  });
}

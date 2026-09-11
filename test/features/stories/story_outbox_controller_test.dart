// Tests for the posting state machine (Plan B, Task 6, spec §6.1) that
// drives a captured story from the local queue to the server.
//
// StoryOutboxStore (Task 5) is persistence only; StoryGateway (Task 4) is
// the three server calls. Neither decides what state a record moves to
// next or when a retry is due — that is StoryOutboxController, and these
// five tests are the behaviours the brief calls out as load-bearing:
//
//   1. the happy path walks every state in order
//   2. a dropped finalize response does not post twice (THE important one
//      — clientStoryId must be minted once, at capture, never again)
//   3. an expired intent mints a new pair and re-uploads (not a retry of
//      the same finalize call)
//   4. a permanent failure stops retrying and stays visible
//   5. discard deletes the local files
//
// A fake StoryGateway is used throughout (never a mock of SupabaseClient,
// matching story_repository_test.dart's own note that the house pattern
// never mocks the generic Supabase builders). An in-memory
// StoryOutboxStore.forTesting backend is used so these tests exercise
// state-machine logic, not SQLite/encryption — that is Task 5's job and
// already covered by story_outbox_store_test.dart.

import 'dart:io';

import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:attune/features/stories/data/story_outbox_backend_stub.dart'
    as stub;
import 'package:attune/features/stories/data/story_outbox_record.dart';
import 'package:attune/features/stories/data/story_outbox_store.dart';
import 'package:attune/features/stories/data/story_repository.dart';
import 'package:attune/features/stories/domain/captured_media.dart';
import 'package:attune/features/stories/presentation/state/story_outbox_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _userId = 'user-1';

final _signedInUser = User(
  id: _userId,
  appMetadata: const {},
  userMetadata: const {},
  aud: 'authenticated',
  createdAt: DateTime.now().toIso8601String(),
);

/// Records every call so tests can assert both outcome and call shape —
/// in particular, that the SAME clientStoryId is reused across retries and
/// finalize calls.
class _FakeStoryGateway implements StoryGateway {
  final List<String> intentCallObjectKinds = [];
  final List<Map<String, dynamic>> uploadCalls = [];
  final List<Map<String, dynamic>> finalizeCalls = [];

  int _intentSeq = 0;

  /// When set, createUploadIntent throws this instead of succeeding.
  Object? failIntentWith;

  /// When set, uploadObject throws this instead of succeeding.
  Object? failUploadWith;

  /// Exceptions to throw on successive finalizeStory calls, consumed one
  /// per call in order (first-in-first-out); once exhausted, calls
  /// succeed normally.
  final List<Object> finalizeScript = [];

  /// clientStoryIds whose NEXT finalizeStory call commits the row
  /// server-side (recorded in the idempotency ledger) but then throws a
  /// network error to the caller instead of returning — simulating a
  /// dropped response after the server already committed. Consumed once
  /// per id.
  final Set<String> dropResponseAfterCommitFor = {};

  /// Every clientStoryId ever sent to finalizeStory, in call order.
  final List<String> finalizedClientStoryIds = [];

  /// Every result finalizeStory actually returned (i.e. calls that did
  /// NOT throw), in call order — lets a test see which calls landed on
  /// an existing row via the idempotency key.
  final List<StoryFinalizeResult> finalizeResults = [];

  final Set<String> _serverStoryClientIds = {};

  @override
  Future<StoryUploadIntent> createUploadIntent({
    required String relationshipId,
    required String objectKind,
    required String mediaType,
    required String mimeType,
  }) async {
    final failure = failIntentWith;
    if (failure != null) throw failure;
    intentCallObjectKinds.add(objectKind);
    _intentSeq++;
    return StoryUploadIntent(
      intentId: 'intent-$objectKind-$_intentSeq',
      storageKey: 'key-$objectKind-$_intentSeq',
      bucket: 'story-media',
      expiresAt: DateTime.now().add(const Duration(minutes: 15)),
    );
  }

  @override
  Future<void> uploadObject({
    required String bucket,
    required String storageKey,
    required String localPath,
    required String mimeType,
  }) async {
    final failure = failUploadWith;
    if (failure != null) throw failure;
    uploadCalls.add({
      'bucket': bucket,
      'storageKey': storageKey,
      'localPath': localPath,
      'mimeType': mimeType,
    });
  }

  @override
  Future<StoryFinalizeResult> finalizeStory({
    required String relationshipId,
    required String clientStoryId,
    required String mediaIntentId,
    required String thumbnailIntentId,
    required int mediaWidth,
    required int mediaHeight,
    int? durationMs,
    required int utcOffsetMinutes,
  }) async {
    finalizeCalls.add({
      'relationshipId': relationshipId,
      'clientStoryId': clientStoryId,
      'mediaIntentId': mediaIntentId,
      'thumbnailIntentId': thumbnailIntentId,
      'mediaWidth': mediaWidth,
      'mediaHeight': mediaHeight,
      'durationMs': durationMs,
      'utcOffsetMinutes': utcOffsetMinutes,
    });
    finalizedClientStoryIds.add(clientStoryId);

    // Idempotent on clientStoryId, mirroring create_story_item (spec
    // §4.2): a second finalize for an id already committed returns the
    // SAME story with existing:true rather than creating a new one. This
    // happens BEFORE the dropped-response simulation below so a "lost
    // response" still reflects a real server-side commit.
    final existing = _serverStoryClientIds.contains(clientStoryId);
    if (!existing) _serverStoryClientIds.add(clientStoryId);

    if (dropResponseAfterCommitFor.remove(clientStoryId)) {
      throw StoryApiError.network();
    }
    if (finalizeScript.isNotEmpty) {
      throw finalizeScript.removeAt(0);
    }

    final result = StoryFinalizeResult(
      storyId: 'story-for-$clientStoryId',
      existing: existing,
    );
    finalizeResults.add(result);
    return result;
  }
}

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('story_outbox_controller_test');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  File writeTempFile(String name) {
    final file = File('${tempDir.path}/$name');
    file.writeAsBytesSync([1, 2, 3]);
    return file;
  }

  StoryOutboxRecord buildRecord({
    required String clientStoryId,
    required File mediaFile,
    required File thumbFile,
  }) {
    return StoryOutboxRecord(
      clientStoryId: clientStoryId,
      relationshipId: 'rel-1',
      localMediaPath: mediaFile.path,
      localThumbnailPath: thumbFile.path,
      mediaType: CapturedMediaType.image,
      mimeType: 'image/jpeg',
      width: 1080,
      height: 1920,
      durationMs: null,
      utcOffsetMinutes: -300,
      createdAt: DateTime.utc(2026, 9, 11, 12),
    );
  }

  /// Builds a real ProviderContainer with the store and gateway providers
  /// overridden to test doubles — the same pattern
  /// game_invite_composer_test.dart uses (never a mock of SupabaseClient
  /// itself; the seam is the app-level provider, matching the house
  /// style). currentUserProvider is overridden to a fixed signed-in user
  /// so storyOutboxProvider resolves to a stable userId without touching
  /// real Supabase auth.
  ({
    ProviderContainer container,
    StoryOutboxController controller,
    StoryOutboxStore store,
    _FakeStoryGateway gateway,
  })
  harness() {
    final store = StoryOutboxStore.forTesting(stub.createStoryOutboxBackend());
    final gateway = _FakeStoryGateway();
    final container = ProviderContainer(
      overrides: [
        currentUserProvider.overrideWithValue(_signedInUser),
        storyOutboxStoreProvider.overrideWithValue(store),
        storyGatewayProvider.overrideWithValue(gateway),
      ],
    );
    addTearDown(container.dispose);
    final controller = container.read(storyOutboxProvider.notifier);
    return (
      container: container,
      controller: controller,
      store: store,
      gateway: gateway,
    );
  }

  group('the happy path', () {
    test('walks every state in order: queued -> uploadingMedia -> '
        'uploadingThumbnail -> finalizing -> gone', () async {
      final h = harness();
      final mediaFile = writeTempFile('media.jpg');
      final thumbFile = writeTempFile('thumb.jpg');
      final record = buildRecord(
        clientStoryId: 'story-1',
        mediaFile: mediaFile,
        thumbFile: thumbFile,
      );

      final observedStates = <StoryOutboxState>[];
      h.controller.addListener((rows) {
        final row = rows.where((r) => r.clientStoryId == 'story-1');
        if (row.isNotEmpty) observedStates.add(row.first.state);
      });

      await h.controller.enqueue(record);
      // enqueue's own flush is unawaited; drive it to completion.
      await h.controller.flush();

      expect(
        observedStates,
        containsAllInOrder([
          StoryOutboxState.queued,
          StoryOutboxState.uploadingMedia,
          StoryOutboxState.uploadingThumbnail,
          StoryOutboxState.finalizing,
        ]),
      );

      // Gone from the queue: readAll no longer returns it, and the
      // controller's own state reflects that too.
      expect(await h.store.readAll(_userId), isEmpty);
      expect(
        h.controller.state.where((r) => r.clientStoryId == 'story-1'),
        isEmpty,
      );

      // Exactly one intent per object kind, one upload per object, one
      // finalize call.
      expect(h.gateway.intentCallObjectKinds, ['media', 'thumbnail']);
      expect(h.gateway.uploadCalls, hasLength(2));
      expect(h.gateway.finalizeCalls, hasLength(1));
      expect(h.gateway.finalizeCalls.single['clientStoryId'], 'story-1');

      // Local files are cleaned up on success.
      expect(mediaFile.existsSync(), isFalse);
      expect(thumbFile.existsSync(), isFalse);
    });

    test('finalize sends utcOffsetMinutes from the record at post time, '
        'not recomputed', () async {
      final h = harness();
      final mediaFile = writeTempFile('media.jpg');
      final thumbFile = writeTempFile('thumb.jpg');
      final record = buildRecord(
        clientStoryId: 'story-offset',
        mediaFile: mediaFile,
        thumbFile: thumbFile,
      );

      await h.controller.enqueue(record);
      await h.controller.flush();

      expect(h.gateway.finalizeCalls.single['utcOffsetMinutes'], -300);
    });
  });

  test('a dropped finalize response does not post twice', () async {
    // THE most important test in this task. The gateway throws AFTER the
    // server committed (a lost response, not a lost request) — proven
    // here by the fake's finalizeStory being idempotent on
    // clientStoryId under the hood while the FIRST call's return value
    // never reaches the client (it throws instead).
    final h = harness();
    final mediaFile = writeTempFile('media.jpg');
    final thumbFile = writeTempFile('thumb.jpg');
    final record = buildRecord(
      clientStoryId: 'story-dropped-response',
      mediaFile: mediaFile,
      thumbFile: thumbFile,
    );

    // The first finalize call commits server-side (the fake's idempotency
    // ledger records it) but then throws a network error instead of
    // returning — exactly "the gateway throws AFTER the server
    // committed."
    h.gateway.dropResponseAfterCommitFor.add('story-dropped-response');

    await h.controller.enqueue(record);
    await h.controller.flush();

    // First attempt failed (network, retryable) — record still queued
    // for retry, not removed, not permanently failed.
    var rows = await h.store.readAll(_userId);
    expect(rows, hasLength(1));
    expect(rows.single.state, isNot(StoryOutboxState.failedPermanent));
    expect(h.gateway.finalizeCalls, hasLength(1));
    expect(
      h.gateway.finalizeResults,
      isEmpty,
      reason: 'the client never saw a response for the first call',
    );

    // Force the retry now rather than waiting out backoff.
    final requeued = rows.single.copyWith(clearNextAttemptAt: true);
    await h.store.put(_userId, requeued);
    await h.controller.flush();

    // The retry sent the SAME clientStoryId both times — the id was
    // minted once, at enqueue, and never regenerated.
    expect(h.gateway.finalizedClientStoryIds, [
      'story-dropped-response',
      'story-dropped-response',
    ]);

    // The second call is the only one whose response the client actually
    // saw, and it landed on the existing row rather than creating a
    // second one.
    expect(h.gateway.finalizeResults, hasLength(1));
    expect(h.gateway.finalizeResults.single.existing, isTrue);

    rows = await h.store.readAll(_userId);
    expect(rows, isEmpty, reason: 'the story posted, so the row is gone');
    expect(h.gateway.finalizeCalls, hasLength(2));
  });

  test('an expired intent mints a new pair and re-uploads', () async {
    // Spec §6.1: "An expired intent causes a new pair of intents and
    // re-upload; the server cleanup removes the old unused objects." The
    // client's recovery is structural, not a retry of the same finalize
    // call — UNAVAILABLE from finalize resets the record to queued so
    // the next attempt mints fresh intents.
    final h = harness();
    final mediaFile = writeTempFile('media.jpg');
    final thumbFile = writeTempFile('thumb.jpg');
    final record = buildRecord(
      clientStoryId: 'story-expired-intent',
      mediaFile: mediaFile,
      thumbFile: thumbFile,
    );

    h.gateway.finalizeScript.add(
      const StoryApiError(
        code: 'UNAVAILABLE',
        message: "Stories aren't available right now.",
        retryable: false,
      ),
    );

    await h.controller.enqueue(record);
    await h.controller.flush();

    // First pair of intents minted, uploads happened, finalize refused.
    expect(h.gateway.intentCallObjectKinds, ['media', 'thumbnail']);
    expect(h.gateway.uploadCalls, hasLength(2));
    expect(h.gateway.finalizeCalls, hasLength(1));

    var rows = await h.store.readAll(_userId);
    expect(rows, hasLength(1));
    expect(
      rows.single.state,
      StoryOutboxState.queued,
      reason: 'UNAVAILABLE at finalize resets to queued for a fresh mint, '
          'not failedPermanent and not a same-call retry',
    );

    // Force the retry now.
    final requeued = rows.single.copyWith(clearNextAttemptAt: true);
    await h.store.put(_userId, requeued);
    await h.controller.flush();

    // A SECOND pair of intents was minted (4 total intent calls, not 2)
    // and the media was re-uploaded (4 upload calls, not 2) — proving
    // this was NOT a retry of the identical finalize call with the
    // stale intent ids.
    expect(h.gateway.intentCallObjectKinds, hasLength(4));
    expect(h.gateway.uploadCalls, hasLength(4));
    expect(h.gateway.finalizeCalls, hasLength(2));

    // The second finalize used different intent ids than the first.
    expect(
      h.gateway.finalizeCalls[1]['mediaIntentId'],
      isNot(h.gateway.finalizeCalls[0]['mediaIntentId']),
    );
    expect(
      h.gateway.finalizeCalls[1]['thumbnailIntentId'],
      isNot(h.gateway.finalizeCalls[0]['thumbnailIntentId']),
    );

    // Same clientStoryId both times.
    expect(h.gateway.finalizedClientStoryIds, [
      'story-expired-intent',
      'story-expired-intent',
    ]);

    expect(await h.store.readAll(_userId), isEmpty);
  });

  test('a permanent failure stops retrying and stays visible', () async {
    // Bounded exponential backoff, then failedPermanent with Retry and
    // Discard available. It must not spin forever.
    final h = harness();
    final mediaFile = writeTempFile('media.jpg');
    final thumbFile = writeTempFile('thumb.jpg');
    final record = buildRecord(
      clientStoryId: 'story-permanent',
      mediaFile: mediaFile,
      thumbFile: thumbFile,
    );

    // FORBIDDEN is not retryable at all — permanent on first occurrence.
    h.gateway.failIntentWith = const StoryApiError(
      code: 'FORBIDDEN',
      message: "You don't have access to this story.",
      retryable: false,
    );

    await h.controller.enqueue(record);
    await h.controller.flush();

    final rows = await h.store.readAll(_userId);
    expect(rows, hasLength(1));
    expect(rows.single.state, StoryOutboxState.failedPermanent);
    expect(rows.single.lastErrorCode, 'FORBIDDEN');
    expect(rows.single.nextAttemptAt, isNull);

    // It never silently disappears: still visible via readAll.
    expect((await h.store.readAll(_userId)).single.state, StoryOutboxState.failedPermanent);

    // flush() again does NOT retry a failedPermanent record.
    final callsBefore = h.gateway.intentCallObjectKinds.length;
    await h.controller.flush();
    expect(h.gateway.intentCallObjectKinds.length, callsBefore);
  });

  test(
    'a permanent failure is reached after a bounded number of retryable '
    'failures, not an unbounded spin',
    () async {
      final h = harness();
      final mediaFile = writeTempFile('media.jpg');
      final thumbFile = writeTempFile('thumb.jpg');
      final record = buildRecord(
        clientStoryId: 'story-exhausted',
        mediaFile: mediaFile,
        thumbFile: thumbFile,
      );

      // Every intent call fails with a retryable network error.
      h.gateway.failIntentWith = StoryApiError.network();

      await h.controller.enqueue(record);
      await h.controller.flush();

      // Drive retries forward by clearing backoff each time, up to a
      // generous bound so a bug that never converges fails the test
      // instead of hanging it.
      for (var i = 0; i < 10; i++) {
        final rows = await h.store.readAll(_userId);
        if (rows.isEmpty) break;
        if (rows.single.state == StoryOutboxState.failedPermanent) break;
        final requeued = rows.single.copyWith(clearNextAttemptAt: true);
        await h.store.put(_userId, requeued);
        await h.controller.flush();
      }

      final rows = await h.store.readAll(_userId);
      expect(rows, hasLength(1));
      expect(rows.single.state, StoryOutboxState.failedPermanent);
      expect(
        rows.single.attempts,
        lessThanOrEqualTo(5),
        reason: 'must stop within a bounded number of attempts',
      );
    },
  );

  test(
    'retry restarts the backoff cycle rather than granting one attempt',
    () async {
      // Fix round 1, finding 1: retry() must reset `attempts` to 0, not
      // just clear nextAttemptAt/lastErrorCode. Otherwise the very next
      // failure after a manual Retry computes attempts >= the ceiling and
      // lands straight back at failedPermanent regardless of whether
      // that failure was retryable — Retry would be "try once more, then
      // give up forever" instead of a real restart.
      final h = harness();
      final mediaFile = writeTempFile('media.jpg');
      final thumbFile = writeTempFile('thumb.jpg');
      final record = buildRecord(
        clientStoryId: 'story-retry-restarts-backoff',
        mediaFile: mediaFile,
        thumbFile: thumbFile,
      );

      // Drive it to failedPermanent by exhausting automatic attempts on a
      // retryable error.
      h.gateway.failIntentWith = StoryApiError.network();
      await h.controller.enqueue(record);
      await h.controller.flush();
      for (var i = 0; i < 10; i++) {
        final rows = await h.store.readAll(_userId);
        if (rows.single.state == StoryOutboxState.failedPermanent) break;
        final requeued = rows.single.copyWith(clearNextAttemptAt: true);
        await h.store.put(_userId, requeued);
        await h.controller.flush();
      }
      expect(
        (await h.store.readAll(_userId)).single.state,
        StoryOutboxState.failedPermanent,
        reason: 'setup did not reach failedPermanent',
      );

      // User taps Retry.
      await h.controller.retry('story-retry-restarts-backoff');

      // Retry itself may already have failed once more (still retryable
      // network error) and rescheduled with backoff — that's expected.
      // What matters is it is NOT failedPermanent after just one more
      // failure, because attempts restarted from 0.
      var rows = await h.store.readAll(_userId);
      expect(rows, hasLength(1));
      expect(
        rows.single.state,
        isNot(StoryOutboxState.failedPermanent),
        reason: 'retry() did not restart the attempt count — one more '
            'failure after Retry landed straight back at failedPermanent',
      );
      expect(rows.single.attempts, lessThan(5));

      // Force one more explicit failure and confirm it still isn't
      // permanent — proving there is real headroom, not a fluke of
      // rounding.
      final requeued = rows.single.copyWith(clearNextAttemptAt: true);
      await h.store.put(_userId, requeued);
      await h.controller.flush();

      rows = await h.store.readAll(_userId);
      expect(rows, hasLength(1));
      expect(
        rows.single.state,
        isNot(StoryOutboxState.failedPermanent),
        reason: 'a retryable failure right after Retry must reschedule, '
            'not exhaust immediately',
      );
      expect(rows.single.nextAttemptAt, isNotNull);
    },
  );

  test('a manual retry does not reuse stale intents', () async {
    // Fix round 1, finding 2, option (a): a record can sit in
    // failedPermanent indefinitely (until the user acts), and the
    // automatic backoff path alone can span minutes — comfortably enough
    // to cross the server's 15-minute intent expiry. retry() must not
    // reuse whatever pair happened to be cached; it must mint a fresh
    // one, the same as a brand new capture would.
    final h = harness();
    final mediaFile = writeTempFile('media.jpg');
    final thumbFile = writeTempFile('thumb.jpg');
    final record = buildRecord(
      clientStoryId: 'story-retry-fresh-intents',
      mediaFile: mediaFile,
      thumbFile: thumbFile,
    );

    // Intents mint fine; the upload itself is what fails permanently —
    // driving the record to failedPermanent WHILE it holds a cached
    // pair, not via the finalize-UNAVAILABLE branch (which already
    // clears intents itself and would not exercise this fix).
    h.gateway.failUploadWith = const StoryApiError(
      code: 'FORBIDDEN',
      message: 'refused',
      retryable: false,
    );

    await h.controller.enqueue(record);
    await h.controller.flush();

    expect(
      (await h.store.readAll(_userId)).single.state,
      StoryOutboxState.failedPermanent,
    );
    final intentCallsBeforeRetry = h.gateway.intentCallObjectKinds.length;
    expect(
      intentCallsBeforeRetry,
      2,
      reason: 'one pair (media + thumbnail) should have been minted '
          'before the upload failed',
    );

    // Let the retry succeed this time.
    h.gateway.failUploadWith = null;
    await h.controller.retry('story-retry-fresh-intents');

    // A fresh pair was minted rather than the stale one being reused —
    // 4 total intent calls, not 2.
    expect(
      h.gateway.intentCallObjectKinds.length,
      intentCallsBeforeRetry + 2,
      reason: 'retry() reused the stale cached intent pair instead of '
          'minting a fresh one',
    );
    expect(await h.store.readAll(_userId), isEmpty);
  });

  test('discard deletes the local files', () async {
    // Spec §6.1: local files live in app-private storage until success
    // or explicit discard.
    final h = harness();
    final mediaFile = writeTempFile('media.jpg');
    final thumbFile = writeTempFile('thumb.jpg');
    final record = buildRecord(
      clientStoryId: 'story-discard',
      mediaFile: mediaFile,
      thumbFile: thumbFile,
    );

    // Land it in failedPermanent first, the realistic case Discard is
    // offered from.
    h.gateway.failIntentWith = const StoryApiError(
      code: 'FORBIDDEN',
      message: 'refused',
      retryable: false,
    );
    await h.controller.enqueue(record);
    await h.controller.flush();

    expect(
      (await h.store.readAll(_userId)).single.state,
      StoryOutboxState.failedPermanent,
    );
    expect(mediaFile.existsSync(), isTrue);
    expect(thumbFile.existsSync(), isTrue);

    await h.controller.discard('story-discard');

    expect(mediaFile.existsSync(), isFalse);
    expect(thumbFile.existsSync(), isFalse);
    expect(await h.store.readAll(_userId), isEmpty);
  });

  test('discard also works on a still-queued (not yet failed) capture', () async {
    final h = harness();
    final mediaFile = writeTempFile('media.jpg');
    final thumbFile = writeTempFile('thumb.jpg');
    final record = buildRecord(
      clientStoryId: 'story-discard-queued',
      mediaFile: mediaFile,
      thumbFile: thumbFile,
    );

    await h.store.put(_userId, record);

    await h.controller.discard('story-discard-queued');

    expect(mediaFile.existsSync(), isFalse);
    expect(thumbFile.existsSync(), isFalse);
    expect(await h.store.readAll(_userId), isEmpty);
  });
}

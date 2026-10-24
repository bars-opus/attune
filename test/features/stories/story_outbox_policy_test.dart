import 'dart:async';
import 'dart:io';

import 'package:attune/features/chat/data/repositories/chat_media_uploader.dart'
    show ChatUploadCancelToken;
import 'package:attune/features/stories/data/story_media_vault.dart';
import 'package:attune/features/stories/data/story_outbox_backend_base.dart';
import 'package:attune/features/stories/data/story_outbox_backend_stub.dart'
    as stub;
import 'package:attune/features/stories/data/story_outbox_record.dart';
import 'package:attune/features/stories/data/story_outbox_store.dart';
import 'package:attune/features/stories/data/story_repository.dart';
import 'package:attune/features/stories/domain/captured_media.dart';
import 'package:attune/features/stories/presentation/state/story_outbox_controller.dart';
import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'support/outbox_fakes.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('outbox_policy'));
  tearDown(() => dir.deleteSync(recursive: true));

  group('retry policy (P1, V11)', () {
    test(
      'offline failures never exhaust: still queued after 12 tries, then posts',
      () async {
        final h = outboxHarness();
        addTearDown(h.container.dispose);
        h.gateway.intentScript.addAll(List.filled(12, StoryApiError.network()));
        await h.controller().enqueue(outboxRecord(dir));
        for (var i = 0; i < 11; i++) {
          await forceOnce(h);
        }
        var row = (await h.store.readAll(outboxUserId)).single;
        expect(row.state, isNot(StoryOutboxState.failedPermanent));
        expect(row.strikes, 0);
        expect(row.lastErrorCode, StoryErrorCodes.network);
        expect(row.nextAttemptAt, isNotNull);

        await forceOnce(h); // the network is back
        expect(await h.store.readAll(outboxUserId), isEmpty);
        expect(h.gateway.finalizes, hasLength(1));
      },
    );

    test('RATE_LIMITED never strikes either', () async {
      final h = outboxHarness();
      addTearDown(h.container.dispose);
      h.gateway.intentScript.addAll(
        List.filled(
          7,
          const StoryApiError(
            code: 'RATE_LIMITED',
            message: 'slow down',
            retryable: true,
          ),
        ),
      );
      await h.controller().enqueue(outboxRecord(dir));
      for (var i = 0; i < 6; i++) {
        await forceOnce(h);
      }
      final row = (await h.store.readAll(outboxUserId)).single;
      expect(row.state, isNot(StoryOutboxState.failedPermanent));
      expect(row.strikes, 0);
    });

    test('an unknown-shape failure exhausts after 5 strikes', () async {
      final h = outboxHarness();
      addTearDown(h.container.dispose);
      h.gateway.intentScript.addAll(List.filled(10, unknownError));
      await h.controller().enqueue(outboxRecord(dir));
      for (var i = 0; i < 9; i++) {
        final rows = await h.store.readAll(outboxUserId);
        if (rows.single.state == StoryOutboxState.failedPermanent) break;
        await forceOnce(h);
      }
      final row = (await h.store.readAll(outboxUserId)).single;
      expect(row.state, StoryOutboxState.failedPermanent);
      expect(row.strikes, StoryOutboxController.maxStrikes);
    });

    test(
      'offline tries do not use up the strikes an unknown failure gets',
      () async {
        final h = outboxHarness();
        addTearDown(h.container.dispose);
        h.gateway.intentScript
          ..addAll(List.filled(8, StoryApiError.network()))
          ..add(unknownError);
        await h.controller().enqueue(outboxRecord(dir));
        for (var i = 0; i < 8; i++) {
          await forceOnce(h);
        }
        final row = (await h.store.readAll(outboxUserId)).single;
        expect(row.state, isNot(StoryOutboxState.failedPermanent));
        expect(row.strikes, 1);
      },
    );

    test(
      'Storage 409 on our key means it landed: move on, no re-upload',
      () async {
        final h = outboxHarness();
        addTearDown(h.container.dispose);
        h.gateway.uploadScript.add(storageError(409));
        await h.controller().enqueue(outboxRecord(dir));
        expect(await h.store.readAll(outboxUserId), isEmpty);
        expect(h.gateway.intentCalls, ['media', 'thumbnail']);
        expect(h.gateway.finalizes, hasLength(1));
      },
    );

    test(
      'Storage 403 drops the intents, re-queues and re-mints (a strike)',
      () async {
        final h = outboxHarness();
        addTearDown(h.container.dispose);
        h.gateway.uploadScript.add(storageError(403));
        await h.controller().enqueue(outboxRecord(dir));
        var row = (await h.store.readAll(outboxUserId)).single;
        expect(row.state, StoryOutboxState.queued);
        expect(row.hasIntents, isFalse);
        expect(row.strikes, 1);
        await forceOnce(h);
        expect(await h.store.readAll(outboxUserId), isEmpty);
        expect(h.gateway.intentCalls, hasLength(4));
      },
    );

    for (final (status, code) in [
      (413, StoryErrorCodes.mediaTooLarge),
      (415, StoryErrorCodes.mediaTypeRejected),
    ]) {
      test('Storage $status is permanent at once with code $code', () async {
        final h = outboxHarness();
        addTearDown(h.container.dispose);
        h.gateway.uploadScript.add(storageError(status));
        await h.controller().enqueue(outboxRecord(dir));
        final row = (await h.store.readAll(outboxUserId)).single;
        expect(row.state, StoryOutboxState.failedPermanent);
        expect(row.lastErrorCode, code);
        expect(row.attempts, 1);
      });
    }

    test(
      'a missing local file is permanent at once as media_missing',
      () async {
        final h = outboxHarness();
        addTearDown(h.container.dispose);
        final record = outboxRecord(dir);
        File(record.localMediaPath).deleteSync();
        await h.controller().enqueue(record);
        final row = (await h.store.readAll(outboxUserId)).single;
        expect(row.state, StoryOutboxState.failedPermanent);
        expect(row.lastErrorCode, StoryErrorCodes.mediaMissing);
      },
    );

    test('backoff windows are chat\'s: 2, 4 … capped at 64 s', () {
      expect(
        StoryOutboxController.backoffWindowFor(1),
        const Duration(seconds: 2),
      );
      expect(
        StoryOutboxController.backoffWindowFor(3),
        const Duration(seconds: 8),
      );
      expect(
        StoryOutboxController.backoffWindowFor(40),
        const Duration(seconds: 64),
      );
    });
  });

  group('persisted intents (01 #8, V13)', () {
    StoryUploadIntent intent(String kind, DateTime expiresAt) =>
        StoryUploadIntent(
          intentId: 'persisted-$kind',
          storageKey: 'persisted-key-$kind',
          bucket: 'story-media',
          expiresAt: expiresAt,
        );

    test(
      'a restart mid-post resumes the same keys and skips the media upload',
      () async {
        final h = outboxHarness();
        addTearDown(h.container.dispose);
        final soon = DateTime.now().add(const Duration(minutes: 10));
        final record = outboxRecord(
          dir,
          state: StoryOutboxState.uploadingThumbnail,
        ).copyWith(
          mediaIntent: intent('media', soon),
          thumbnailIntent: intent('thumbnail', soon),
        );
        await h.store.put(outboxUserId, record);

        await h.controller().flush();

        expect(h.gateway.intentCalls, isEmpty, reason: 'no fresh pair minted');
        expect(h.gateway.uploads.map((u) => u.key), [
          'persisted-key-thumbnail',
        ]);
        expect(h.gateway.finalizes.single, (
          media: 'persisted-media',
          thumb: 'persisted-thumbnail',
        ));
      },
    );

    test('minted intents are written to the store before uploading', () async {
      final h = outboxHarness();
      addTearDown(h.container.dispose);
      h.gateway.uploadScript.add(StoryApiError.network());
      await h.controller().enqueue(outboxRecord(dir));
      final row = (await h.store.readAll(outboxUserId)).single;
      expect(row.hasIntents, isTrue);
      expect(row.mediaIntent!.intentId, startsWith('intent-media'));
    });

    test(
      'an intent within 2 minutes of expiry is re-minted, with no strike',
      () async {
        final h = outboxHarness();
        addTearDown(h.container.dispose);
        final nearly = DateTime.now().add(const Duration(seconds: 90));
        final record = outboxRecord(
          dir,
          state: StoryOutboxState.uploadingThumbnail,
        ).copyWith(
          mediaIntent: intent('media', nearly),
          thumbnailIntent: intent('thumbnail', nearly),
        );
        await h.store.put(outboxUserId, record);

        await h.controller().flush();

        expect(h.gateway.intentCalls, ['media', 'thumbnail']);
        // Both objects go up again under the NEW keys: a new intent is a new key.
        expect(h.gateway.uploads.map((u) => u.key), [
          'key-media-1',
          'key-thumbnail-2',
        ]);
        expect(h.gateway.finalizes.single.media, 'intent-media-1');
        expect(await h.store.readAll(outboxUserId), isEmpty);
      },
    );

    test('device clock ahead of the server: a fresh-looking-stale intent still '
        'posts (Review Focus 1)', () async {
      // The phone is 20 minutes fast: every intent the server mints looks
      // expired the moment it lands. The record must still post, and
      // re-minting must never strike.
      final h = outboxHarness();
      addTearDown(h.container.dispose);
      h.gateway.intentLifetime = const Duration(minutes: 15);
      await withClock(
        Clock.fixed(DateTime.now().add(const Duration(minutes: 20))),
        () async {
          await h.controller().enqueue(outboxRecord(dir));
        },
      );
      expect(await h.store.readAll(outboxUserId), isEmpty);
      expect(
        h.gateway.intentCalls,
        ['media', 'thumbnail'],
        reason: 'one fresh pair is used once even if it already looks stale',
      );
    });

    test(
      'a record killed mid-thumbnail by the previous build (no intents) '
      're-uploads both objects under the new pair (01 #8, Review Focus 3)',
      () async {
        final h = outboxHarness();
        addTearDown(h.container.dispose);
        await h.store.put(
          outboxUserId,
          outboxRecord(dir, state: StoryOutboxState.uploadingThumbnail),
        );
        await h.controller().flush();
        expect(
          h.gateway.uploads.map((u) => u.key),
          ['key-media-1', 'key-thumbnail-2'],
          reason:
              'the media goes up again: the old code skipped it and '
              'finalize always failed',
        );
        expect(h.gateway.finalizes.single.media, 'intent-media-1');
        final row = await h.store.readAll(outboxUserId);
        expect(row, isEmpty);
      },
    );
  });

  group('batch 2 fix round 1', () {
    StoryUploadIntent intent(String kind, DateTime expiresAt) =>
        StoryUploadIntent(
          intentId: 'persisted-$kind',
          storageKey: 'persisted-key-$kind',
          bucket: 'story-media',
          expiresAt: expiresAt,
        );

    test('a backed-off record keeps a retry timer after a sooner one posts '
        '(review #1)', () async {
      final h = outboxHarness();
      addTearDown(h.container.dispose);
      await h.store.put(
        outboxUserId,
        outboxRecord(dir, id: 'a').copyWith(attempts: 6),
      );
      await h.store.put(outboxUserId, outboxRecord(dir, id: 'b'));
      h.gateway.intentScript.addAll([
        StoryApiError.network(),
        StoryApiError.network(),
      ]);
      await h.controller().flush();
      await Future<void>.delayed(const Duration(milliseconds: 2600));
      await h.controller().flush();
      final rows = await h.store.readAll(outboxUserId);
      expect(rows.map((r) => r.clientStoryId), ['a']);
      expect(
        h.controller().debugHasRetryTimer,
        isTrue,
        reason: 'a is still waiting; nothing would ever wake it',
      );
    });

    test('a finalizing record is finalized with its own pair even near '
        'expiry: killed between file delete and row remove, it resolves as '
        'posted, nothing re-uploaded (review #2)', () async {
      final h = outboxHarness();
      addTearDown(h.container.dispose);
      final nearly = DateTime.now().add(const Duration(seconds: 90));
      final record = outboxRecord(
        dir,
        state: StoryOutboxState.finalizing,
      ).copyWith(
        mediaIntent: intent('media', nearly),
        thumbnailIntent: intent('thumbnail', nearly),
      );
      File(record.localMediaPath).deleteSync();
      File(record.localThumbnailPath).deleteSync();
      await h.store.put(outboxUserId, record);

      await h.controller().flush();

      expect(h.gateway.intentCalls, isEmpty);
      expect(h.gateway.uploads, isEmpty);
      expect(h.gateway.finalizes.single, (
        media: 'persisted-media',
        thumb: 'persisted-thumbnail',
      ));
      expect(await h.store.readAll(outboxUserId), isEmpty);
    });

    test('finalize UNAVAILABLE on a pair already near expiry re-mints with '
        'no strike (review #2)', () async {
      final h = outboxHarness();
      addTearDown(h.container.dispose);
      final nearly = DateTime.now().add(const Duration(seconds: 90));
      await h.store.put(
        outboxUserId,
        outboxRecord(dir, state: StoryOutboxState.finalizing).copyWith(
          mediaIntent: intent('media', nearly),
          thumbnailIntent: intent('thumbnail', nearly),
        ),
      );
      h.gateway.finalizeScript.add(
        const StoryApiError(
          code: 'UNAVAILABLE',
          message: 'gone',
          retryable: false,
        ),
      );

      await h.controller().flush();

      var row = (await h.store.readAll(outboxUserId)).single;
      expect(row.state, StoryOutboxState.queued);
      expect(row.hasIntents, isFalse);
      expect(row.strikes, 0);

      await forceOnce(h);
      expect(await h.store.readAll(outboxUserId), isEmpty);
      expect(h.gateway.uploads.map((u) => u.key), [
        'key-media-1',
        'key-thumbnail-2',
      ]);
    });

    test('a forced flush never resurrects a row discard() just removed '
        '(review #3)', () async {
      final backend = _HookBackend();
      final h = outboxHarness(store: StoryOutboxStore.forTesting(backend));
      addTearDown(h.container.dispose);
      final record = outboxRecord(dir).copyWith(
        attempts: 6,
        lastErrorCode: StoryErrorCodes.network,
        nextAttemptAt: DateTime.now().add(const Duration(minutes: 5)),
      );
      await h.store.put(outboxUserId, record);
      await h.controller().flush(); // the cold-start pass: still waiting

      backend.afterNextRead =
          () => h.controller().discard(record.clientStoryId);
      await h.controller().flush(force: true);

      expect(await h.store.readAll(outboxUserId), isEmpty);
      expect(h.gateway.intentCalls, isEmpty);
      expect(h.gateway.finalizes, isEmpty);
    });

    test('a throwing pass stays inside the controller, which lives on and '
        'schedules the next attempt (review #4)', () async {
      final backend = _HookBackend()..throwOnReads = 1;
      final h = outboxHarness(store: StoryOutboxStore.forTesting(backend));
      addTearDown(h.container.dispose);
      // The constructor's fire-and-forget pass throws; an escaped error
      // fails this test as an uncaught async error.
      final controller = h.controller();
      await pumpEventQueue();
      expect(controller.debugHasRetryTimer, isTrue);

      await h.store.put(outboxUserId, outboxRecord(dir));
      await controller.flush();
      expect(h.gateway.finalizes, hasLength(1));
    });

    test('one record whose writes throw does not stop the rest of the queue '
        '(review #4)', () async {
      final backend = _HookBackend();
      final h = outboxHarness(store: StoryOutboxStore.forTesting(backend));
      addTearDown(h.container.dispose);
      await h.store.put(outboxUserId, outboxRecord(dir, id: 'x'));
      await h.store.put(outboxUserId, outboxRecord(dir, id: 'y'));
      backend.throwOnPutFor = 'x';
      await h.controller().flush();
      expect(h.gateway.finalizes.map((f) => f.media), hasLength(1));
      expect(
        (await h.store.readAll(outboxUserId)).map((r) => r.clientStoryId),
        ['x'],
      );
    });
  });

  group('vault paths (01 #10)', () {
    test('a relative record resolves against the vault before upload, and its '
        'folder goes on success', () async {
      final support = Directory.systemTemp.createTempSync('policy_support');
      addTearDown(() => support.deleteSync(recursive: true));
      final vault = StoryMediaVault(supportDirectory: () async => support);
      final h = outboxHarness(
        extra: [storyMediaVaultProvider.overrideWithValue(vault)],
      );
      addTearDown(h.container.dispose);
      final raw = outboxRecord(dir);
      final stored = await vault.adopt(
        userId: outboxUserId,
        clientStoryId: raw.clientStoryId,
        mediaPath: raw.localMediaPath,
        thumbnailPath: raw.localThumbnailPath,
      );
      await h.controller().enqueue(
        StoryRecordPaths.withPaths(raw, stored.media, stored.thumbnail),
      );
      expect(
        h.gateway.uploads.first.path,
        '${support.path}/story_outbox/$outboxUserId/cid-1/media.jpg',
      );
      expect(
        Directory(
          '${support.path}/story_outbox/$outboxUserId/cid-1',
        ).existsSync(),
        isFalse,
      );
    });

    test(
      'the controller exposes resolved (absolute) paths for the ring',
      () async {
        final support = Directory.systemTemp.createTempSync('policy_support2');
        addTearDown(() => support.deleteSync(recursive: true));
        final vault = StoryMediaVault(supportDirectory: () async => support);
        final h = outboxHarness(
          extra: [storyMediaVaultProvider.overrideWithValue(vault)],
        );
        addTearDown(h.container.dispose);
        h.gateway.intentScript.add(StoryApiError.network());
        final raw = outboxRecord(dir);
        final stored = await vault.adopt(
          userId: outboxUserId,
          clientStoryId: raw.clientStoryId,
          mediaPath: raw.localMediaPath,
          thumbnailPath: raw.localThumbnailPath,
        );
        await h.controller().enqueue(
          StoryRecordPaths.withPaths(raw, stored.media, stored.thumbnail),
        );
        final shown = h.container.read(storyOutboxProvider).single;
        expect(p.isAbsolute(shown.localThumbnailPath), isTrue);
        // The store still holds the relative form.
        expect(
          (await h.store.readAll(outboxUserId)).single.localThumbnailPath,
          stored.thumbnail,
        );
      },
    );
  });

  group('batch 3', () {
    test('a discard landing during a pass\'s read leaves no ghost row in '
        'state (batch-2 re-review minor)', () async {
      final backend = _HookBackend();
      final h = outboxHarness(store: StoryOutboxStore.forTesting(backend));
      addTearDown(h.container.dispose);
      final record = outboxRecord(dir).copyWith(
        attempts: 6,
        lastErrorCode: StoryErrorCodes.network,
        nextAttemptAt: DateTime.now().add(const Duration(minutes: 5)),
      );
      await h.store.put(outboxUserId, record);
      await h.controller().flush(); // the cold-start pass: still waiting
      expect(h.container.read(storyOutboxProvider), hasLength(1));

      backend.afterNextRead =
          () => h.controller().discard(record.clientStoryId);
      await h.controller().flush();

      expect(await h.store.readAll(outboxUserId), isEmpty);
      expect(h.container.read(storyOutboxProvider), isEmpty);
    });
  });

  group('cancel and progress (01 #13)', () {
    test('cancel mid-upload aborts, removes the row and its files', () async {
      final h = outboxHarness();
      addTearDown(h.container.dispose);
      h.gateway.uploadGate = Completer<void>();
      final record = outboxRecord(dir);
      final drive = h.controller().enqueue(record);
      await pumpEventQueue();
      expect(h.container.read(storyUploadProgressProvider)['cid-1'], 0.5);

      final outcome = await h.controller().cancel('cid-1');
      await drive;

      expect(outcome, StoryCancelOutcome.cancelled);
      expect(await h.store.readAll(outboxUserId), isEmpty);
      expect(File(record.localMediaPath).existsSync(), isFalse);
      expect(h.gateway.finalizes, isEmpty);
      expect(h.container.read(storyUploadProgressProvider), isEmpty);
    });

    test('once finalize is sent, cancel says it is already posting', () async {
      final h = outboxHarness();
      addTearDown(h.container.dispose);
      h.gateway.finalizeGate = Completer<void>();
      final drive = h.controller().enqueue(outboxRecord(dir));
      await pumpEventQueue(times: 20);
      expect(
        (await h.store.readAll(outboxUserId)).single.state,
        StoryOutboxState.finalizing,
      );

      expect(
        await h.controller().cancel('cid-1'),
        StoryCancelOutcome.alreadyPosting,
      );
      h.gateway.finalizeGate!.complete();
      await drive;
      expect(h.gateway.finalizes, hasLength(1));
    });

    test(
      'cancelling a story waiting on its backoff needs no network',
      () async {
        final h = outboxHarness();
        addTearDown(h.container.dispose);
        h.gateway.intentScript.add(StoryApiError.network());
        await h.controller().enqueue(outboxRecord(dir));
        expect(
          await h.controller().cancel('cid-1'),
          StoryCancelOutcome.cancelled,
        );
        expect(await h.store.readAll(outboxUserId), isEmpty);
        expect(h.controller().debugHasRetryTimer, isFalse);
      },
    );

    test('disposing the controller (sign-out) aborts its upload on the wire, '
        'and writes nothing back', () async {
      final h = outboxHarness();
      final gate = h.gateway.uploadGate = Completer<void>();
      final drive = h.controller().enqueue(outboxRecord(dir));
      await pumpEventQueue();
      expect(gate.isCompleted, isFalse);

      h.container.dispose();
      expect(gate.isCompleted, isTrue);
      await drive;
      expect(h.gateway.uploads, isEmpty);
      expect(
        (await h.store.readAll(outboxUserId)).single.state,
        StoryOutboxState.uploadingMedia,
        reason: 'the row is left for the next session (or the wipe)',
      );
    });

    test('discard while an upload is on the wire aborts that upload through '
        'the cancel token (batch-2 fix round, concern 2)', () async {
      final h = outboxHarness();
      addTearDown(h.container.dispose);
      final gate = h.gateway.uploadGate = Completer<void>();
      final record = outboxRecord(dir);
      final drive = h.controller().enqueue(record);
      await pumpEventQueue();
      expect(gate.isCompleted, isFalse, reason: 'the media upload is open');

      await h.controller().discard('cid-1');
      // Aborted, not left to run to completion: the gate completes with
      // the cancel error the moment the token fires.
      expect(gate.isCompleted, isTrue);
      await drive;

      expect(h.gateway.uploads, isEmpty, reason: 'no object landed');
      expect(h.gateway.finalizes, isEmpty);
      expect(await h.store.readAll(outboxUserId), isEmpty);
      expect(File(record.localMediaPath).existsSync(), isFalse);
      expect(h.container.read(storyUploadProgressProvider), isEmpty);
    });
  });

  group('batch 3 fix round 1', () {
    test('I1: a finalize that failed on the wire may be live, so cancel on '
        'its backing-off row says already posting and keeps it', () async {
      final h = outboxHarness();
      addTearDown(h.container.dispose);
      h.gateway.finalizeScript.add(StoryApiError.network());
      final record = outboxRecord(dir);
      await h.controller().enqueue(record);
      expect(
        (await h.store.readAll(outboxUserId)).single.state,
        StoryOutboxState.finalizing,
      );

      expect(
        await h.controller().cancel('cid-1'),
        StoryCancelOutcome.alreadyPosting,
      );
      expect(await h.store.readAll(outboxUserId), hasLength(1));
      expect(File(record.localMediaPath).existsSync(), isTrue);

      await forceOnce(h);
      expect(h.gateway.finalizes, hasLength(1));
      expect(await h.store.readAll(outboxUserId), isEmpty);
    });

    test('M1: a leftover progress entry does not freeze the new drive '
        '(probe P3)', () async {
      final h = outboxHarness();
      addTearDown(h.container.dispose);
      h.container.read(storyUploadProgressProvider.notifier).state = {
        'cid-1': 0.9,
      };
      h.gateway.uploadGate = Completer<void>();
      final drive = h.controller().enqueue(outboxRecord(dir));
      await pumpEventQueue();
      expect(h.container.read(storyUploadProgressProvider)['cid-1'], 0.5);
      h.gateway.uploadGate!.complete();
      await drive;
    });

    test('M3a: cancel while the finalizing write is pending is clean: '
        'finalize was not sent yet', () async {
      final backend = _HookBackend();
      final h = outboxHarness(store: StoryOutboxStore.forTesting(backend));
      addTearDown(h.container.dispose);
      await h.controller().flush(); // settle the cold-start pass first
      final expires = DateTime.now().add(const Duration(hours: 1));
      await h.store.put(
        outboxUserId,
        outboxRecord(dir, state: StoryOutboxState.uploadingThumbnail).copyWith(
          mediaIntent: StoryUploadIntent(
            intentId: 'im',
            storageKey: 'km',
            bucket: 'story-media',
            expiresAt: expires,
          ),
          thumbnailIntent: StoryUploadIntent(
            intentId: 'it',
            storageKey: 'kt',
            bucket: 'story-media',
            expiresAt: expires,
          ),
        ),
      );
      StoryCancelOutcome? outcome;
      // Read 1 is the pass's snapshot; read 2 is the refresh inside
      // _persist(finalizing), before the finalize call.
      backend.afterNextRead = () async {
        backend.afterNextRead = () async {
          outcome = await h.controller().cancel('cid-1');
        };
      };
      await h.controller().flush();

      expect(outcome, StoryCancelOutcome.cancelled);
      expect(h.gateway.finalizes, isEmpty);
      expect(await h.store.readAll(outboxUserId), isEmpty);
    });

    test('M3c: cancelling one backing-off row keeps the timer for the '
        'others, with no network call', () async {
      final h = outboxHarness();
      addTearDown(h.container.dispose);
      final now = DateTime.now();
      await h.store.put(
        outboxUserId,
        outboxRecord(dir, id: 'a').copyWith(
          attempts: 1,
          nextAttemptAt: now.add(const Duration(minutes: 1)),
        ),
      );
      await h.store.put(
        outboxUserId,
        outboxRecord(dir, id: 'b').copyWith(
          attempts: 1,
          nextAttemptAt: now.add(const Duration(minutes: 5)),
        ),
      );
      await h.controller().flush();
      expect(h.controller().debugHasRetryTimer, isTrue);

      expect(await h.controller().cancel('a'), StoryCancelOutcome.cancelled);
      expect(
        h.controller().debugHasRetryTimer,
        isTrue,
        reason: 'b still waits on its backoff',
      );
      expect(h.gateway.intentCalls, isEmpty);
      expect(h.gateway.uploads, isEmpty);
      expect(
        (await h.store.readAll(outboxUserId)).map((r) => r.clientStoryId),
        ['b'],
      );
    });
  });

  group('final review minors', () {
    test('#3c: at controller start, a vault folder of this user with no row '
        '(killed between adopt and enqueue) is removed; folders with rows, '
        'and other users\' folders, stay', () async {
      final support = Directory(p.join(dir.path, 'support'))..createSync();
      final vault = StoryMediaVault(supportDirectory: () async => support);
      Directory folder(String user, String id) => Directory(
        p.join(support.path, 'story_outbox', user, id),
      )..createSync(recursive: true);
      final orphan = folder(outboxUserId, 'orphan-1');
      File(p.join(orphan.path, 'media.jpg')).writeAsBytesSync([1]);
      final kept = folder(outboxUserId, 'cid-1');
      final other = folder('someone-else', 'theirs-1');
      final store = StoryOutboxStore.forTesting(stub.createStoryOutboxBackend());
      await store.put(
        outboxUserId,
        outboxRecord(dir).copyWith(
          state: StoryOutboxState.failedPermanent,
          lastErrorCode: 'FORBIDDEN',
        ),
      );
      final h = outboxHarness(
        store: store,
        extra: [storyMediaVaultProvider.overrideWithValue(vault)],
      );
      addTearDown(h.container.dispose);

      await h.controller().flush();

      expect(orphan.existsSync(), isFalse, reason: 'plaintext with no row');
      expect(kept.existsSync(), isTrue);
      expect(other.existsSync(), isTrue, reason: 'not this controller\'s');
    });

    test('#3c: with the keystore unavailable (rows unreadable) nothing is '
        'swept', () async {
      final support = Directory(p.join(dir.path, 'support'))..createSync();
      final vault = StoryMediaVault(supportDirectory: () async => support);
      final folder = Directory(
        p.join(support.path, 'story_outbox', outboxUserId, 'cid-x'),
      )..createSync(recursive: true);
      final h = outboxHarness(
        store: StoryOutboxStore.forTesting(
          stub.createStoryOutboxBackend(),
          cipherUnavailable: true,
        ),
        extra: [storyMediaVaultProvider.overrideWithValue(vault)],
      );
      addTearDown(h.container.dispose);
      await h.controller().flush();
      expect(folder.existsSync(), isTrue);
    });

    test("#3e: cancel's no-await window: wherever a cancel lands while a "
        'finalizing row is driven, it never says "cancelled" for a story '
        'whose finalize was sent', () async {
      final soon = DateTime.now().add(const Duration(minutes: 10));
      StoryUploadIntent intent(String kind) => StoryUploadIntent(
        intentId: 'persisted-$kind',
        storageKey: 'persisted-key-$kind',
        bucket: 'story-media',
        expiresAt: soon,
      );
      for (var turns = 0; turns < 60; turns++) {
        final g = _CountingGateway()..finalizeGate = Completer<void>();
        final h = outboxHarness(gateway: g);
        await h.store.put(
          outboxUserId,
          outboxRecord(dir, state: StoryOutboxState.finalizing).copyWith(
            mediaIntent: intent('media'),
            thumbnailIntent: intent('thumbnail'),
          ),
        );
        final pass = h.controller().flush();
        for (var i = 0; i < turns; i++) {
          await Future<void>.value();
        }
        final outcome = await h.controller().cancel('cid-1');
        g.finalizeGate!.complete();
        await pass;
        expect(
          outcome == StoryCancelOutcome.cancelled && g.finalizeCalls > 0,
          isFalse,
          reason:
              'turn $turns: cancel said cancelled, but finalize was sent '
              '(an await between the last halt check and _finalizeSent.add)',
        );
        h.container.dispose();
      }
    });
  });

  group('final review #2: slow links and intent expiry', () {
    StoryUploadIntent intent(String kind, DateTime expiresAt) =>
        StoryUploadIntent(
          intentId: 'persisted-$kind',
          storageKey: 'persisted-key-$kind',
          bucket: 'story-media',
          expiresAt: expiresAt,
        );

    test('the pair is re-checked before the thumbnail step: a pair that ran '
        'near expiry during the media upload is re-minted (no strike) and '
        'the media goes up again under the new key', () async {
      final t = _SlowClock();
      final g = _ExpiringGateway(t, mediaUploadTakes: const Duration(minutes: 9));
      final h = outboxHarness(gateway: g);
      addTearDown(h.container.dispose);
      final inherited = t.now.add(const Duration(minutes: 10));
      await h.store.put(
        outboxUserId,
        outboxRecord(dir, state: StoryOutboxState.uploadingMedia).copyWith(
          mediaIntent: intent('media', inherited),
          thumbnailIntent: intent('thumbnail', inherited),
        ),
      );

      await withClock(t.clock, () => h.controller().flush());

      expect(g.intentCalls, ['media', 'thumbnail']);
      expect(g.uploads.map((u) => u.key), [
        'persisted-key-media',
        'key-media-1',
        'key-thumbnail-2',
      ]);
      expect(g.finalizes.single.media, 'intent-media-1');
      expect(await h.store.readAll(outboxUserId), isEmpty);
    });

    for (final c in [
      (
        name: 'the media upload outlives the pair (16 min)',
        media: const Duration(minutes: 16),
        thumb: Duration.zero,
      ),
      (
        name: 'finalize UNAVAILABLE after a full upload (12 + 3.5 min)',
        media: const Duration(minutes: 12),
        thumb: const Duration(minutes: 3, seconds: 30),
      ),
    ]) {
      test('${c.name}: stops after 2 full uploads with media_link_too_slow, '
          'not 5 uploads and a generic failure', () async {
        final t = _SlowClock();
        final g = _ExpiringGateway(
          t,
          mediaUploadTakes: c.media,
          thumbnailUploadTakes: c.thumb,
        );
        final h = outboxHarness(gateway: g);
        addTearDown(h.container.dispose);
        await withClock(t.clock, () async {
          await h.controller().enqueue(outboxRecord(dir));
          var row = (await h.store.readAll(outboxUserId)).single;
          expect(row.state, isNot(StoryOutboxState.failedPermanent));
          expect(row.slowUploads, 1);
          for (var i = 0; i < 8; i++) {
            row = (await h.store.readAll(outboxUserId)).single;
            if (row.state == StoryOutboxState.failedPermanent) break;
            await forceOnce(h);
          }
        });
        final row = (await h.store.readAll(outboxUserId)).single;
        expect(row.state, StoryOutboxState.failedPermanent);
        expect(row.lastErrorCode, StoryErrorCodes.mediaLinkTooSlow);
        expect(
          g.uploads.where((u) => u.key.startsWith('key-media')),
          hasLength(2),
        );
        expect(g.finalizes, isEmpty);
      });
    }

    test('Retry after media_link_too_slow starts a fresh run (on Wi-Fi it '
        'posts)', () async {
      final t = _SlowClock();
      final g = _ExpiringGateway(t, mediaUploadTakes: const Duration(minutes: 16));
      final h = outboxHarness(gateway: g);
      addTearDown(h.container.dispose);
      await withClock(t.clock, () async {
        await h.controller().enqueue(outboxRecord(dir));
        await forceOnce(h);
        final row = (await h.store.readAll(outboxUserId)).single;
        expect(row.state, StoryOutboxState.failedPermanent);
        g.mediaUploadTakes = const Duration(seconds: 20); // Wi-Fi
        await h.controller().retry('cid-1');
      });
      expect(await h.store.readAll(outboxUserId), isEmpty);
      expect(g.finalizes, hasLength(1));
    });

    test('Wave 5: a 20-minute video upload under its hour-long pair posts '
        'on the first pass', () async {
      final t = _SlowClock();
      final g = _ExpiringGateway(t, mediaUploadTakes: const Duration(minutes: 20))
        ..serverLifetimes = true;
      final h = outboxHarness(gateway: g);
      addTearDown(h.container.dispose);
      await withClock(
        t.clock,
        () => h.controller().enqueue(
          outboxRecord(dir, mediaType: CapturedMediaType.video),
        ),
      );
      expect(await h.store.readAll(outboxUserId), isEmpty);
      expect(g.finalizes, hasLength(1));
      expect(g.intentCalls, ['media', 'thumbnail']);
    });

    test('Wave 5: finalize UNAVAILABLE 14 minutes into a video\'s hour-long '
        'pair is not read as a slow link', () async {
      final t = _SlowClock();
      final g = _ExpiringGateway(t, mediaUploadTakes: const Duration(minutes: 14))
        ..serverLifetimes = true;
      g.finalizeScript.add(
        const StoryApiError(
          code: 'UNAVAILABLE',
          message: 'Unavailable.',
          retryable: false,
        ),
      );
      final h = outboxHarness(gateway: g);
      addTearDown(h.container.dispose);
      await withClock(
        t.clock,
        () => h.controller().enqueue(
          outboxRecord(dir, mediaType: CapturedMediaType.video),
        ),
      );
      final row = (await h.store.readAll(outboxUserId)).single;
      expect(row.slowUploads, 0);
      expect(row.lastErrorCode, isNot(StoryErrorCodes.mediaLinkTooSlow));
    });

    for (final c in [
      (thumb: const Duration(seconds: 90), slow: 1), // 13.5 min: slow
      (thumb: const Duration(seconds: 30), slow: 0), // 12.5 min: not slow
    ]) {
      test('Wave 5: an image pair (15-minute media, hour-long thumbnail) keeps '
          'the 13-minute slow threshold at finalize (${c.thumb})', () async {
        final t = _SlowClock();
        final g = _ExpiringGateway(
          t,
          mediaUploadTakes: const Duration(minutes: 12),
          thumbnailUploadTakes: c.thumb,
        )..serverLifetimes = true;
        g.finalizeScript.add(
          const StoryApiError(
            code: 'UNAVAILABLE',
            message: 'Unavailable.',
            retryable: false,
          ),
        );
        final h = outboxHarness(gateway: g);
        addTearDown(h.container.dispose);
        await withClock(t.clock, () => h.controller().enqueue(outboxRecord(dir)));
        final row = (await h.store.readAll(outboxUserId)).single;
        expect(row.slowUploads, c.slow);
      });
    }

    test('Wave 5: an image pair on a phone 10 min behind the server still '
        'ends as media_link_too_slow (batch 2 review #2)', () async {
      final t = _SlowClock();
      final g = _ExpiringGateway(t, mediaUploadTakes: const Duration(minutes: 14))
        ..serverNow = () => t.now.add(const Duration(minutes: 10));
      g.finalizeScript.add(
        const StoryApiError(
          code: 'UNAVAILABLE',
          message: 'Unavailable.',
          retryable: false,
        ),
      );
      final h = outboxHarness(gateway: g);
      addTearDown(h.container.dispose);
      await withClock(t.clock, () => h.controller().enqueue(outboxRecord(dir)));
      final row = (await h.store.readAll(outboxUserId)).single;
      expect(row.slowUploads, 1);
      expect(row.lastErrorCode, StoryErrorCodes.mediaLinkTooSlow);
    });

    test('a fast pass with a phone clock 20 min ahead is not a slow link '
        '(Review Focus 1 still holds)', () async {
      final t = _SlowClock(DateTime.now().add(const Duration(minutes: 20)));
      final g = _ExpiringGateway(t, mediaUploadTakes: const Duration(seconds: 30))
        ..serverNow = DateTime.now;
      final h = outboxHarness(gateway: g);
      addTearDown(h.container.dispose);
      await withClock(t.clock, () => h.controller().enqueue(outboxRecord(dir)));
      expect(await h.store.readAll(outboxUserId), isEmpty);
      expect(g.intentCalls, ['media', 'thumbnail']);
    });
  });

  group('capture date (Wave 5, 04 #3)', () {
    test('finalize carries the capture time (Wave 5, 04 #3)', () async {
      final g = ScriptedStoryGateway();
      final h = outboxHarness(gateway: g);
      addTearDown(h.container.dispose);
      final record = outboxRecord(dir);
      await h.controller().enqueue(record);
      expect(g.capturedAts.single, record.createdAt);
    });

    test('a local capture time is read at its own offset, so a time zone '
        'change while queued does not move the instant', () async {
      final g = ScriptedStoryGateway();
      final h = outboxHarness(gateway: g);
      addTearDown(h.container.dispose);
      // Wall clock 23:30 at UTC+5:45, as a record persisted before this
      // field was sent stores it (no zone in the ISO string). +5:45 (Nepal)
      // so no dev or CI machine's own zone hides a revert to toUtc().
      final base = outboxRecord(dir);
      final record = StoryOutboxRecord(
        clientStoryId: base.clientStoryId,
        relationshipId: base.relationshipId,
        localMediaPath: base.localMediaPath,
        localThumbnailPath: base.localThumbnailPath,
        mediaType: base.mediaType,
        mimeType: base.mimeType,
        width: base.width,
        height: base.height,
        utcOffsetMinutes: 345,
        state: base.state,
        createdAt: DateTime(2026, 10, 23, 23, 30),
      );
      await h.controller().enqueue(record);
      expect(g.capturedAts.single, DateTime.utc(2026, 10, 23, 17, 45));
      expect(g.capturedAts.single!.isUtc, isTrue);
    });
  });
}

/// The in-memory backend with hooks: a callback that runs right after a
/// read has taken its snapshot, reads that throw, and writes that throw
/// for one id.
class _HookBackend implements StoryOutboxBackend {
  final StoryOutboxBackend _inner = stub.createStoryOutboxBackend();
  Future<void> Function()? afterNextRead;
  int throwOnReads = 0;
  String? throwOnPutFor;

  @override
  Future<void> init() => _inner.init();

  @override
  Future<List<String>> readAll(String userId) async {
    if (throwOnReads > 0) {
      throwOnReads--;
      throw StateError('disk');
    }
    final rows = await _inner.readAll(userId);
    final hook = afterNextRead;
    afterNextRead = null;
    if (hook != null) await hook();
    return rows;
  }

  @override
  Future<void> put(
    String userId,
    String clientStoryId,
    String payload,
    int createdAtMillis,
  ) async {
    if (clientStoryId == throwOnPutFor) throw StateError('disk full');
    await _inner.put(userId, clientStoryId, payload, createdAtMillis);
  }

  @override
  Future<void> remove(String userId, String clientStoryId) =>
      _inner.remove(userId, clientStoryId);

  @override
  Future<void> clearAll() => _inner.clearAll();

  @override
  Future<void> removeOtherUsers(String keepUserId) =>
      _inner.removeOtherUsers(keepUserId);

  @override
  Future<void> close() => _inner.close();
}

/// A clock tests move by hand; uploads advance it to stand in for a slow
/// link.
class _SlowClock {
  _SlowClock([DateTime? start]) : now = start ?? DateTime.utc(2026, 10, 23, 9);
  DateTime now;
  Clock get clock => Clock(() => now);
}

/// Mints 15-minute intents on [serverNow], spends [mediaUploadTakes] /
/// [thumbnailUploadTakes] of [_SlowClock] time per upload, and refuses
/// finalize (UNAVAILABLE) when either intent has expired, as the server
/// does (20260938120000_stories_finalize_race_fix.sql).
class _ExpiringGateway extends ScriptedStoryGateway {
  _ExpiringGateway(
    this.t, {
    required this.mediaUploadTakes,
    this.thumbnailUploadTakes = Duration.zero,
  }) {
    super.now = () => serverNow();
  }

  final _SlowClock t;
  Duration mediaUploadTakes;
  Duration thumbnailUploadTakes;
  late DateTime Function() serverNow = () => t.now;
  final _expiry = <String, DateTime>{};

  @override
  Future<StoryUploadIntent> createUploadIntent({
    required String relationshipId,
    required String objectKind,
    required String mediaType,
    required String mimeType,
  }) async {
    final minted = await super.createUploadIntent(
      relationshipId: relationshipId,
      objectKind: objectKind,
      mediaType: mediaType,
      mimeType: mimeType,
    );
    _expiry[minted.intentId] = minted.expiresAt;
    return minted;
  }

  @override
  Future<void> uploadObject({
    required String bucket,
    required String storageKey,
    required String localPath,
    required String mimeType,
    void Function(int sent, int total)? onProgress,
    ChatUploadCancelToken? cancelToken,
  }) async {
    t.now = t.now.add(
      storageKey.contains('media') ? mediaUploadTakes : thumbnailUploadTakes,
    );
    await super.uploadObject(
      bucket: bucket,
      storageKey: storageKey,
      localPath: localPath,
      mimeType: mimeType,
      onProgress: onProgress,
      cancelToken: cancelToken,
    );
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
    Map<String, dynamic>? place,
    DateTime? capturedAt,
  }) async {
    for (final id in [mediaIntentId, thumbnailIntentId]) {
      final expires = _expiry[id];
      if (expires != null && !serverNow().isBefore(expires)) {
        throw const StoryApiError(
          code: 'UNAVAILABLE',
          message: 'Unavailable.',
          retryable: false,
        );
      }
    }
    return super.finalizeStory(
      relationshipId: relationshipId,
      clientStoryId: clientStoryId,
      mediaIntentId: mediaIntentId,
      thumbnailIntentId: thumbnailIntentId,
      mediaWidth: mediaWidth,
      mediaHeight: mediaHeight,
      durationMs: durationMs,
      utcOffsetMinutes: utcOffsetMinutes,
      place: place,
      capturedAt: capturedAt,
    );
  }
}

/// Counts finalize calls as they are SENT (before any gate).
class _CountingGateway extends ScriptedStoryGateway {
  int finalizeCalls = 0;

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
    Map<String, dynamic>? place,
    DateTime? capturedAt,
  }) {
    finalizeCalls++;
    return super.finalizeStory(
      relationshipId: relationshipId,
      clientStoryId: clientStoryId,
      mediaIntentId: mediaIntentId,
      thumbnailIntentId: thumbnailIntentId,
      mediaWidth: mediaWidth,
      mediaHeight: mediaHeight,
      durationMs: durationMs,
      utcOffsetMinutes: utcOffsetMinutes,
      place: place,
      capturedAt: capturedAt,
    );
  }
}

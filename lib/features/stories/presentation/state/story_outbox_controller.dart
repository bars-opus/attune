/// The posting state machine that drives a captured story from the local
/// queue to the server (Plan B, Task 6, spec §6.1).
///
/// [StoryOutboxStore] is persistence only — it does not decide what state
/// a record moves to next or when a retry is due. That is this file's job:
/// [StoryOutboxController] reads the queue, walks each record through
/// `queued -> uploadingMedia -> uploadingThumbnail -> finalizing`, and
/// removes it once the server confirms the story exists.
///
/// **Why `clientStoryId` is never regenerated.** `create_story_item` is
/// idempotent on `(author_id, client_story_id)` (spec §4.2) — a retry that
/// reuses the id lands on the same server row (`existing: true`) instead of
/// creating a second one. That guarantee is worth nothing if this
/// controller mints a fresh id per attempt, so [StoryOutboxRecord] carries
/// one id for its entire life, set once at [enqueue] and never touched
/// again by anything in this file.
///
/// **The taxonomy this machine branches on** (see `StoryApiError`'s doc
/// comment for the full derivation):
///   - A network failure, or a `StoryApiError` with `retryable: true`
///     (only `RATE_LIMITED`) -> bounded exponential backoff, same record,
///     same `clientStoryId`, same intents where still valid.
///   - `UNAVAILABLE` from *finalize* specifically -> the server collapsed
///     "expired intent" into this code along with several permanent
///     conditions it cannot tell apart from the outside. Spec §6.1: "An
///     expired intent causes a new pair of intents and re-upload; the
///     server cleanup removes the old unused objects." So finalize
///     `UNAVAILABLE` resets the record to `queued` with its intents
///     discarded — the next attempt mints a fresh pair and re-uploads
///     before finalizing again. This still counts as an attempt toward
///     the backoff cap, so a *genuinely* permanent `UNAVAILABLE` (e.g. the
///     relationship ended) does not spin forever; it eventually lands on
///     `failedPermanent` like any other exhausted retry.
///   - Any other `StoryApiError` (`UNAUTHORIZED`, `FORBIDDEN`,
///     `INVALID_INPUT`) -> `failedPermanent` immediately, no backoff spent.
///
/// **Backoff cadence** matches the chat outbox exactly
/// (`chat_state.dart:1949-1954`, `_handleSendFailure`): bounded exponential
/// with equal jitter, `windowSeconds = 1 << attempts.clamp(1, 6)`,
/// `delayMillis = windowSeconds*500 + random(0..windowSeconds*500)`, capped
/// at a 64s window. The attempt ceiling before `failedPermanent` is the
/// same `5` chat uses (`_maxAutomaticSendAttempts`).
///
/// **Finalization time is posting time** (spec §6.1): `utcOffsetMinutes`
/// is read from the record and sent at finalize call time, not
/// recalculated or backdated to capture time — an offline capture that
/// waited in the queue still gets the 24-hour window and `occurred_on` of
/// when it actually posts.
///
/// **Local files** live in app-private storage until success (removed by
/// this controller once `finalizeStory` returns) or an explicit
/// [discard], which deletes both files and the queue row. A retryable or
/// permanent failure never deletes anything — spec §6.1, "it never
/// silently disappears."
///
/// **Parked, not solved here**: if the platform keystore is unavailable,
/// `StoryOutboxStore.put()` silently drops the write (fail-closed, same as
/// chat's precedent). The user-visible signal for that belongs to Task 7's
/// UI.
library;

import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:attune/features/stories/data/story_outbox_record.dart';
import 'package:attune/features/stories/data/story_outbox_store.dart';
import 'package:attune/features/stories/data/story_repository.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

final storyOutboxStoreProvider = Provider<StoryOutboxStore>(
  (ref) => StoryOutboxStore(),
);

final storyGatewayProvider = Provider<StoryGateway>(
  (ref) => StoryRepository(ref.watch(supabaseClientProvider)),
);

/// A fresh id for a new capture. Minted once, at [StoryOutboxController.enqueue]
/// time, by whoever builds the record — kept here so callers do not reach
/// for `Uuid` directly and so the "once, ever" rule has one obvious home.
String newClientStoryId() => const Uuid().v4();

/// The two upload intents a story needs before it can finalize. Held only
/// in memory: intents expire in 15 minutes (spec §4.2), so there is no
/// value in persisting them past a restart — a restart mid-upload simply
/// mints a fresh pair, which is always safe because nothing has finalized
/// yet.
@immutable
class _IntentPair {
  const _IntentPair({required this.media, required this.thumbnail});

  final StoryUploadIntent media;
  final StoryUploadIntent thumbnail;
}

class StoryOutboxController extends StateNotifier<List<StoryOutboxRecord>> {
  StoryOutboxController(this._ref, this._userId) : super(const []) {
    unawaited(flush());
  }

  final Ref _ref;
  final String _userId;

  StoryOutboxStore get _store => _ref.read(storyOutboxStoreProvider);
  StoryGateway get _gateway => _ref.read(storyGatewayProvider);

  /// Same cap as chat's `_maxAutomaticSendAttempts` (`chat_state.dart:281`).
  static const _maxAutomaticAttempts = 5;

  final _backoffJitter = Random();
  final Map<String, _IntentPair> _intents = {};
  bool _isFlushing = false;
  bool _flushRequestedWhileBusy = false;
  final Set<String> _inFlight = {};

  Future<void> _refreshState() async {
    state = await _store.readAll(_userId);
  }

  /// Adds a freshly captured story to the queue and immediately attempts
  /// to post it. [record.state] must be [StoryOutboxState.queued] and
  /// [record.clientStoryId] must already be set by the caller — this
  /// method never mints one, so the same id used for capture is the id
  /// that reaches the server.
  ///
  /// Returns the [flush] future so a caller that wants to know when the
  /// attempt has settled (tests, in particular) can await it; production
  /// callers are free to let it run in the background.
  Future<void> enqueue(StoryOutboxRecord record) async {
    await _store.put(_userId, record);
    await _refreshState();
    await flush();
  }

  /// Walks every non-`failedPermanent` record whose `nextAttemptAt` has
  /// passed through the next step of the state machine. Safe to call from
  /// app start and from a connectivity-restored listener — concurrent
  /// calls collapse into one in-flight run plus at most one more queued
  /// behind it, the same guard chat's `flushOutbox` uses
  /// (`chat_state.dart:1633-1636`).
  Future<void> flush() async {
    if (_isFlushing) {
      _flushRequestedWhileBusy = true;
      return;
    }
    _isFlushing = true;
    try {
      final queue = await _store.readAll(_userId);
      state = queue;
      for (final record in queue) {
        if (record.state == StoryOutboxState.failedPermanent) continue;
        if (!_inFlight.add(record.clientStoryId)) continue;
        try {
          final nextAttemptAt = record.nextAttemptAt;
          if (nextAttemptAt != null && nextAttemptAt.isAfter(DateTime.now())) {
            continue;
          }
          await _drive(record);
        } finally {
          _inFlight.remove(record.clientStoryId);
        }
      }
    } finally {
      _isFlushing = false;
      if (_flushRequestedWhileBusy) {
        _flushRequestedWhileBusy = false;
        unawaited(flush());
      }
    }
  }

  /// Clears backoff and drives a `failedPermanent` record through the
  /// machine again, from a user's explicit Retry tap. Returns the
  /// [flush] future for the same reason [enqueue] does.
  ///
  /// Resets [StoryOutboxRecord.attempts] to 0, not just `nextAttemptAt`
  /// and `lastErrorCode`: a record only reaches `failedPermanent` once
  /// `attempts >= _maxAutomaticAttempts`, so leaving the old count in
  /// place would let the very next failure land back at the ceiling
  /// immediately regardless of whether it was retryable — turning Retry
  /// into "try once more, then give up forever" instead of a real
  /// restart of the backoff cycle. A manual tap is a deliberate act on a
  /// (presumably) changed network situation and deserves a full new run
  /// at the automatic ceiling, the same as a fresh capture gets.
  ///
  /// Also drops any cached upload intents for this id (fix round 1,
  /// finding 2 — option (a)): a record can sit in `failedPermanent` for
  /// as long as the user leaves it there, which can easily exceed the
  /// server's 15-minute intent expiry, and the automatic backoff path
  /// alone can span minutes too. Rather than track `expiresAt` and a
  /// near-expiry margin on every cached pair (more correct in general,
  /// but more machinery), a manual retry unconditionally re-mints: it is
  /// a single, infrequent, user-triggered event, so paying for two fresh
  /// intent calls every time is cheap and certain to be correct, where a
  /// time-based check would still need a safety margin and a clock.
  /// The AUTOMATIC path does not get this treatment and does not need
  /// it: every automatic retry either (a) is still within the same
  /// upload/thumbnail step with intents minted moments-to-low-minutes
  /// earlier under the bounded 5-attempt/64s-cap backoff schedule, comfortably
  /// inside the 15-minute window, or (b) already went through the
  /// finalize-`UNAVAILABLE` branch, which mints fresh intents itself
  /// precisely because that call already told the server the old ones
  /// don't work. There is no automatic-path scenario where a stale pair
  /// both survives long enough to expire AND gets reused without going
  /// through one of those two existing resets.
  Future<void> retry(String clientStoryId) async {
    final rows = await _store.readAll(_userId);
    final record = rows.where((r) => r.clientStoryId == clientStoryId).firstOrNull;
    if (record == null) return;
    _intents.remove(clientStoryId);
    final reset = record.copyWith(
      state: StoryOutboxState.queued,
      attempts: 0,
      clearNextAttemptAt: true,
      clearLastErrorCode: true,
    );
    await _store.put(_userId, reset);
    await _refreshState();
    await flush();
  }

  /// Discards a queued/failed capture: deletes its local media and
  /// thumbnail files (spec §6.1 — they live in app-private storage until
  /// success or explicit discard) and removes the queue row.
  Future<void> discard(String clientStoryId) async {
    final rows = await _store.readAll(_userId);
    final record = rows.where((r) => r.clientStoryId == clientStoryId).firstOrNull;
    _intents.remove(clientStoryId);
    if (record != null) {
      await _deleteLocalFile(record.localMediaPath);
      await _deleteLocalFile(record.localThumbnailPath);
    }
    await _store.remove(_userId, clientStoryId);
    await _refreshState();
  }

  Future<void> _deleteLocalFile(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {
      // Best-effort: a file already gone, or an unwritable sandbox on the
      // way out, must not block the row's removal from the queue.
    }
  }

  /// Advances one record by exactly one step, persisting the new state
  /// before moving to the next so a crash mid-flow resumes rather than
  /// restarts. Errors are caught here, not by [flush] — a failure of one
  /// story must never abort the rest of the queue.
  Future<void> _drive(StoryOutboxRecord record) async {
    // Declared outside the try block and updated as each step commits, so
    // a failure handler always sees the record's LATEST persisted state
    // (e.g. `finalizing`) rather than the state it started this call in.
    // A finalize UNAVAILABLE must be recognised as a finalize failure —
    // using the stale `record` here would always read `queued` and treat
    // every failure as a fresh, un-uploaded capture.
    var current = record;
    try {
      if (current.state == StoryOutboxState.queued) {
        current = await _persist(current.copyWith(state: StoryOutboxState.uploadingMedia));
      }

      final pair = await _ensureIntents(current);

      if (current.state == StoryOutboxState.uploadingMedia) {
        await _gateway.uploadObject(
          bucket: pair.media.bucket,
          storageKey: pair.media.storageKey,
          localPath: current.localMediaPath,
          mimeType: current.mimeType,
        );
        current = await _persist(
          current.copyWith(state: StoryOutboxState.uploadingThumbnail),
        );
      }

      if (current.state == StoryOutboxState.uploadingThumbnail) {
        await _gateway.uploadObject(
          bucket: pair.thumbnail.bucket,
          storageKey: pair.thumbnail.storageKey,
          localPath: current.localThumbnailPath,
          mimeType: 'image/jpeg',
        );
        current = await _persist(current.copyWith(state: StoryOutboxState.finalizing));
      }

      if (current.state == StoryOutboxState.finalizing) {
        // Finalization time is posting time (spec §6.1): utcOffsetMinutes
        // travels from the record as captured, sent now, never recomputed.
        await _gateway.finalizeStory(
          relationshipId: current.relationshipId,
          clientStoryId: current.clientStoryId,
          mediaIntentId: pair.media.intentId,
          thumbnailIntentId: pair.thumbnail.intentId,
          mediaWidth: current.width,
          mediaHeight: current.height,
          durationMs: current.durationMs,
          utcOffsetMinutes: current.utcOffsetMinutes,
        );

        // Success — whether this call created the story or landed on an
        // existing one via the idempotency key, the outcome for the
        // client is identical: the story exists, stop posting it.
        _intents.remove(current.clientStoryId);
        await _deleteLocalFile(current.localMediaPath);
        await _deleteLocalFile(current.localThumbnailPath);
        await _store.remove(_userId, current.clientStoryId);
        await _refreshState();
      }
    } on StoryApiError catch (error) {
      await _handleFailure(current, error);
    } catch (error) {
      await _handleFailure(current, StoryApiError.network(error));
    }
  }

  /// Mints a fresh pair of upload intents if none are held for this
  /// record yet. Held only in memory — see [_IntentPair]'s doc comment.
  Future<_IntentPair> _ensureIntents(StoryOutboxRecord record) async {
    final existing = _intents[record.clientStoryId];
    if (existing != null) return existing;

    final mediaType = record.mediaType.name; // 'image' | 'video'
    final media = await _gateway.createUploadIntent(
      relationshipId: record.relationshipId,
      objectKind: 'media',
      mediaType: mediaType,
      mimeType: record.mimeType,
    );
    final thumbnail = await _gateway.createUploadIntent(
      relationshipId: record.relationshipId,
      objectKind: 'thumbnail',
      mediaType: 'image',
      mimeType: 'image/jpeg',
    );
    final pair = _IntentPair(media: media, thumbnail: thumbnail);
    _intents[record.clientStoryId] = pair;
    return pair;
  }

  Future<StoryOutboxRecord> _persist(StoryOutboxRecord record) async {
    await _store.put(_userId, record);
    await _refreshState();
    return record;
  }

  Future<void> _handleFailure(StoryOutboxRecord original, StoryApiError error) async {
    final attempts = original.attempts + 1;

    // An expired/inaccessible intent surfaces at finalize as UNAVAILABLE
    // (StoryApiError's doc comment). Spec §6.1's recovery is structural,
    // not a retry of the same call: drop the held intents and go back to
    // `queued` so the next attempt mints a fresh pair and re-uploads
    // before finalizing again. The server cleanup reaps the old unused
    // objects; this client does not try to delete them itself. This
    // still counts toward the attempt ceiling below, so a genuinely
    // permanent UNAVAILABLE (membership/relationship, not just an expired
    // intent) does not retry forever.
    final isFinalizeUnavailable =
        original.state == StoryOutboxState.finalizing && error.code == 'UNAVAILABLE';

    // Retryable in the ordinary sense (network, RATE_LIMITED), or a
    // finalize UNAVAILABLE being recovered structurally: both keep going
    // until the attempt ceiling. Anything else (UNAUTHORIZED, FORBIDDEN,
    // INVALID_INPUT) is permanent on the first occurrence — retrying an
    // unchanged request against those fails the same way again.
    final recoverable = error.retryable || isFinalizeUnavailable;
    final permanent = !recoverable || attempts >= _maxAutomaticAttempts;

    if (isFinalizeUnavailable) {
      _intents.remove(original.clientStoryId);
    }

    // Bounded exponential backoff with equal jitter — matches
    // chat_state.dart:1949-1954 exactly: half the window is fixed, half
    // is randomized so many clients flushing after an outage do not
    // retry in lockstep. Window caps at 2^6 = 64s.
    final windowSeconds = 1 << attempts.clamp(1, 6);
    final backoffMillis =
        (windowSeconds * 500) + _backoffJitter.nextInt(windowSeconds * 500 + 1);

    final updated = original.copyWith(
      attempts: attempts,
      lastErrorCode: error.code,
      state: permanent
          ? StoryOutboxState.failedPermanent
          : (isFinalizeUnavailable ? StoryOutboxState.queued : original.state),
      nextAttemptAt: permanent ? null : DateTime.now().add(Duration(milliseconds: backoffMillis)),
      clearNextAttemptAt: permanent,
    );

    await _store.put(_userId, updated);
    await _refreshState();

    if (!permanent) {
      final delay = updated.nextAttemptAt?.difference(DateTime.now()) ?? Duration.zero;
      Timer(delay.isNegative ? Duration.zero : delay, () {
        unawaited(flush());
      });
    }
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

/// One controller per signed-in user — the queue itself is per-user (spec
/// §6.1's record has no notion of "no user"), not per-relationship, so
/// this is a plain provider keyed by the current auth id rather than a
/// `.family`.
final storyOutboxProvider =
    StateNotifierProvider<StoryOutboxController, List<StoryOutboxRecord>>((ref) {
  final user = ref.watch(currentUserProvider);
  final userId = user?.id ?? '';
  return StoryOutboxController(ref, userId);
});

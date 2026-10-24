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
/// **The taxonomy this machine branches on** (Wave 2, P1; the same split
/// as chat's `_handleSendFailure`). Every failure is classified once, by
/// `StoryApiError.fromFailure`, into a `StoryFailureKind`; this machine
/// switches on that kind and never reads `retryable`:
///   - `offline` (no answer, Storage 5xx/408/401, a transport-shaped
///     PostgREST error) and `rateLimited` -> capped backoff, same record,
///     same `clientStoryId`, same intents. Never a strike: an offline post
///     waits as long as the outage lasts and goes when the network is back.
///   - `alreadyUploaded` (Storage 409 on our own key) -> an earlier
///     attempt's upload landed; the step counts as done and the record
///     moves on. Finalize re-verifies size and MIME server-side.
///   - `intentStale` (Storage 403) and `UNAVAILABLE` from *finalize*
///     specifically (the server's collapsed "expired intent", spec §6.1)
///     -> the intents are dropped and the record goes back to `queued`, so
///     the next attempt mints a fresh pair and re-uploads both objects. A
///     strike, so a genuinely permanent `UNAVAILABLE` still ends.
///   - `unknown` (any unknown-shape failure) -> a strike, with backoff.
///   - A slow upload (a full media upload that used up the pair this drive
///     minted, seen before the thumbnail step or as finalize UNAVAILABLE)
///     -> re-queued with a fresh pair, no strike; the second one ends the
///     record as `media_link_too_slow` (final review #2).
///   - `mediaRejected` (413 / 415 / MIME), `mediaMissing` (the local file
///     is gone) and `refused` (`UNAUTHORIZED`, `FORBIDDEN`,
///     `INVALID_INPUT`, `UNAVAILABLE` outside finalize) -> `failedPermanent`
///     at once, with the reason in `lastErrorCode`.
///   - `cancelled` -> nothing recorded; whoever cancelled removes the row.
///
/// [StoryOutboxController.maxStrikes] (5, chat's
/// `_maxAutomaticSendAttempts`) strikes end in `failedPermanent`.
/// `attempts` still counts every try and drives the backoff window.
///
/// **Backoff cadence** matches the chat outbox exactly
/// (`chat_state.dart`, `_handleSendFailure`): bounded exponential with
/// equal jitter, `windowSeconds = 1 << attempts.clamp(1, 6)`,
/// `delayMillis = windowSeconds*500 + random(0..windowSeconds*500)`, capped
/// at a 64s window ([StoryOutboxController.backoffWindowFor]).
///
/// **The capture's date, the posting's window** (spec §3.5, §6.1, Wave 5):
/// `createdAt` (capture) and `utcOffsetMinutes` are sent with finalize; the
/// server files the story on that day (clamped to the last 7 days) and
/// starts the 24-hour reel window when finalize lands.
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
import 'dart:math';

import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:attune/features/chat/data/repositories/chat_media_uploader.dart'
    show ChatUploadCancelToken, raceUploadCancel;
import 'package:attune/features/chat/utils/chat_log.dart';
import 'package:attune/features/stories/data/story_media_vault.dart';
import 'package:attune/features/stories/data/story_outbox_record.dart';
import 'package:attune/features/stories/data/story_outbox_store.dart';
import 'package:attune/features/stories/data/story_repository.dart';
import 'package:attune/features/stories/domain/captured_media.dart';
import 'package:attune/features/stories/presentation/providers/story_providers.dart';
import 'package:attune/features/stories/presentation/state/story_posted_hold.dart';
import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

final storyOutboxStoreProvider = Provider<StoryOutboxStore>(
  (ref) => StoryOutboxStore(),
);

final storyGatewayProvider = Provider<StoryGateway>(
  (ref) => StoryRepository(ref.watch(supabaseClientProvider)),
);

/// What [StoryOutboxController.cancel] did (01 #13).
enum StoryCancelOutcome { cancelled, alreadyPosting, notFound }

/// The media upload's sent fraction (0..1) per `clientStoryId`, for the
/// pending ring. In memory only: a relaunch starts the upload over anyway.
final storyUploadProgressProvider = StateProvider<Map<String, double>>(
  (ref) => const {},
);

/// A fresh id for a new capture. Minted once, at [StoryOutboxController.enqueue]
/// time, by whoever builds the record — kept here so callers do not reach
/// for `Uuid` directly and so the "once, ever" rule has one obvious home.
String newClientStoryId() => const Uuid().v4();

class StoryOutboxController extends StateNotifier<List<StoryOutboxRecord>> {
  StoryOutboxController(this._ref, this._userId) : super(const []) {
    if (_userId.isNotEmpty) unawaited(flush());
  }

  bool _disposed = false;
  Timer? _retryTimer;
  DateTime? _retryDue;

  /// Ids [discard] or [cancel] removed this session: a pass that read its
  /// snapshot before the removal landed must neither drive nor write them
  /// back.
  final Set<String> _discarded = {};

  /// The cancel token of each record being driven right now: [discard] and
  /// [cancel] fire it, so an intent call or upload already on the wire is
  /// aborted rather than left to land an orphan object (01 #13).
  final Map<String, ChatUploadCancelToken> _tokens = {};

  /// Ids whose finalize call has been sent and not yet settled. From that
  /// moment the post may exist server-side, so [cancel] refuses. Set
  /// synchronously right before the call, so there is no window in which
  /// cancel says "cancelled" for a story that then posts.
  final Set<String> _finalizeSent = {};

  /// Consecutive passes that threw; widens the retry after a store
  /// failure so a broken disk is not hammered every 2 s.
  int _failedPasses = 0;

  @visibleForTesting
  bool get debugHasRetryTimer => _retryTimer?.isActive ?? false;

  @override
  void dispose() {
    _disposed = true;
    // Sign-out mid-upload: abort what is on the wire rather than let it
    // land an object nobody will finalize (Review Focus 2, 01 #13).
    for (final token in _tokens.values.toList()) {
      token.cancel();
    }
    _retryTimer?.cancel();
    _retryTimer = null;
    _retryDue = null;
    super.dispose();
  }

  /// Nothing may be written once disposed or once a wipe has landed since
  /// [epoch] was captured.
  bool _stale(int epoch) => _disposed || _store.epoch != epoch;

  /// [_stale], or the record was discarded since the pass read it.
  bool _halt(int epoch, String clientStoryId) =>
      _stale(epoch) || _discarded.contains(clientStoryId);

  /// One timer for the whole queue, always due at the EARLIEST waiting
  /// deadline: a later deadline never replaces a sooner one, and every
  /// pass re-arms for whatever is still waiting, so a backed-off record is
  /// never stranded behind another record's timer (batch-2 review #1).
  void _armRetryTimer(DateTime due) {
    if (_disposed) return;
    final current = _retryTimer;
    final currentDue = _retryDue;
    if (current != null &&
        current.isActive &&
        currentDue != null &&
        !due.isBefore(currentDue)) {
      return;
    }
    current?.cancel();
    final delay = due.difference(clock.now());
    _retryDue = due;
    _retryTimer = Timer(delay.isNegative ? Duration.zero : delay, () {
      _retryTimer = null;
      _retryDue = null;
      if (!_disposed) unawaited(flush());
    });
  }

  /// Arms the timer for the earliest future `nextAttemptAt` among the rows
  /// still waiting (from [state], refreshed after every write).
  void _armForWaitingRows() {
    if (_disposed) return;
    final now = clock.now();
    DateTime? earliest;
    for (final row in state) {
      if (row.state == StoryOutboxState.failedPermanent) continue;
      if (_discarded.contains(row.clientStoryId)) continue;
      final due = row.nextAttemptAt;
      if (due == null || !due.isAfter(now)) continue;
      if (earliest == null || due.isBefore(earliest)) earliest = due;
    }
    if (earliest != null) _armRetryTimer(earliest);
  }

  final Ref _ref;
  final String _userId;

  StoryOutboxStore get _store => _ref.read(storyOutboxStoreProvider);
  StoryGateway get _gateway => _ref.read(storyGatewayProvider);
  StoryMediaVault get _vault => _ref.read(storyMediaVaultProvider);

  /// Same ceiling as chat's `_maxAutomaticSendAttempts`, counted in
  /// strikes: only an unknown-shape failure or a stale intent is a strike.
  static const int maxStrikes = 5;

  /// Equal-jitter window, identical to chat_state.dart `_handleSendFailure`.
  @visibleForTesting
  static Duration backoffWindowFor(int attempts) =>
      Duration(seconds: 1 << attempts.clamp(1, 6));

  final _backoffJitter = Random();
  Future<void>? _flushRun;
  Future<void>? _flushFollowUp;
  bool _followUpForce = false;
  final Set<String> _inFlight = {};

  Future<void> _refreshState() async {
    if (_disposed) return;
    final rows = await _store.readAll(_userId);
    if (_disposed) return;
    final shown = await _shown(rows);
    if (_disposed) return;
    state = shown;
  }

  /// Sets (or, with null, drops) [clientStoryId]'s upload fraction.
  void _setProgress(String clientStoryId, double? fraction) {
    if (_disposed) return;
    final progress = _ref.read(storyUploadProgressProvider.notifier);
    final current = progress.state;
    if (fraction == null) {
      if (!current.containsKey(clientStoryId)) return;
      progress.state = {...current}..remove(clientStoryId);
    } else {
      progress.state = {...current, clientStoryId: fraction};
    }
  }

  /// What the ring and notices see: absolute paths (the store keeps
  /// vault-relative ones, 01 #10), and never a row [discard] or [cancel]
  /// removed while the read that returned it was in flight (batch-2
  /// re-review: otherwise a ghost row lingers until the next refresh).
  Future<List<StoryOutboxRecord>> _shown(List<StoryOutboxRecord> rows) =>
      Future.wait(
        rows
            .where((r) => !_discarded.contains(r.clientStoryId))
            .map(_vault.resolveRecord),
      );

  /// Adds a freshly captured story to the queue and immediately attempts
  /// to post it. [record.state] must be [StoryOutboxState.queued] and
  /// [record.clientStoryId] must already be set by the caller — this
  /// method never mints one, so the same id used for capture is the id
  /// that reaches the server.
  ///
  /// Returns the [flush] future so a caller that wants to know when the
  /// attempt has settled (tests, in particular) can await it; production
  /// callers are free to let it run in the background.
  /// Returns false when the capture could not be queued at all — the
  /// keystore was unavailable, so [StoryOutboxStore.put] refused to
  /// persist plaintext. Nothing is queued and nothing will retry, so a
  /// caller that ignores this leaves the user believing a story was
  /// posted that does not exist. [StoryCameraScreen] tells them instead.
  /// Like [enqueue], but the returned future completes as soon as the
  /// LOCAL queue write has settled rather than once the upload has — the
  /// flush is started and deliberately not awaited. That lets the camera
  /// learn whether the capture was queued at all without being pinned
  /// behind the network (`story_camera_test.dart`'s "does not upload
  /// inline" guards exactly that regression).
  ///
  /// Returns false when the keystore was unavailable, so
  /// [StoryOutboxStore.put] refused to persist plaintext: nothing is
  /// queued and nothing will retry. A caller that ignores this leaves the
  /// user believing a story was posted that does not exist.
  ///
  /// [expectEpoch] is passed to [StoryOutboxStore.put]: a capture prepared
  /// across a sign-out wipe is refused rather than written back.
  Future<bool> enqueueLocally(
    StoryOutboxRecord record, {
    int? expectEpoch,
  }) async {
    _discarded.remove(record.clientStoryId);
    final stored = await _store.put(
      _userId,
      record,
      expectEpoch: expectEpoch,
    );
    if (!stored) return false;
    await _refreshState();
    unawaited(flush());
    return true;
  }

  Future<void> enqueue(StoryOutboxRecord record) async {
    _discarded.remove(record.clientStoryId);
    final stored = await _store.put(_userId, record);
    if (!stored) return;
    await _refreshState();
    await flush();
  }

  /// Walks every non-`failedPermanent` record whose `nextAttemptAt` has
  /// passed through the next step of the state machine. Safe to call from
  /// app start and from a connectivity-restored listener — concurrent
  /// calls collapse into one in-flight run plus at most one more queued
  /// behind it, the same guard chat's `flushOutbox` uses
  /// (`chat_state.dart:1633-1636`).
  ///
  /// [force] clears `nextAttemptAt` on every non-failed row before the
  /// pass: resume, reconnect and sign-in (`StoryOutboxTriggers`) post a
  /// waiting story now instead of after its backoff. A force request made
  /// while busy carries into the follow-up pass.
  Future<void> flush({bool force = false}) {
    if (_disposed || _userId.isEmpty) return Future.value();
    final running = _flushRun;
    if (running != null) {
      // Busy: collapse into the one follow-up pass, and hand the caller
      // that pass's future so awaiting flush() still means "the queue has
      // been driven", not "a run was already going".
      if (force) _followUpForce = true;
      return _flushFollowUp ??= running.then((_) {}, onError: (_) {}).then((_) {
        _flushFollowUp = null;
        final forceNext = _followUpForce;
        _followUpForce = false;
        return flush(force: forceNext);
      });
    }
    final run = _flushPass(force: force);
    _flushRun = run;
    return run.whenComplete(() {
      if (identical(_flushRun, run)) _flushRun = null;
    });
  }

  /// One pass over the queue. [force] is applied in memory: waiting rows
  /// are driven now without rewriting them first, so a forced pass costs
  /// no store writes and cannot write back a row [discard] just removed
  /// (batch-2 review #3). A failure still sets a fresh `nextAttemptAt`.
  ///
  /// Nothing thrown here escapes to the fire-and-forget callers (the
  /// constructor, the retry timer, `StoryOutboxTriggers.poke`): a store
  /// failure is logged and the next attempt scheduled, the way
  /// `ChatOutboxDrainer._drainOnceSafely` does, and a record whose own
  /// writes throw does not stop the rest of the queue (review #4).
  Future<void> _flushPass({required bool force}) async {
    final epoch = _store.epoch;
    var failed = false;
    try {
      if (_stale(epoch)) return;
      final queue = await _store.readAll(_userId);
      if (_stale(epoch)) return;
      final shown = await _shown(queue);
      if (_stale(epoch)) return;
      state = shown;
      for (final record in queue) {
        if (_stale(epoch)) return;
        if (record.state == StoryOutboxState.failedPermanent) continue;
        if (_discarded.contains(record.clientStoryId)) continue;
        if (!_inFlight.add(record.clientStoryId)) continue;
        try {
          final nextAttemptAt = record.nextAttemptAt;
          if (!force &&
              nextAttemptAt != null &&
              nextAttemptAt.isAfter(clock.now())) {
            continue;
          }
          await _drive(record, epoch);
        } catch (error) {
          failed = true;
          ChatLog.e('story outbox: drive failed', error);
        } finally {
          _inFlight.remove(record.clientStoryId);
        }
      }
    } catch (error) {
      failed = true;
      ChatLog.e('story outbox: flush failed', error);
    }
    if (!_sweptOrphans && !_stale(epoch)) {
      _sweptOrphans = true;
      await _sweepOrphans();
    }
    if (_stale(epoch)) return;
    if (failed) {
      _failedPasses++;
      _armRetryTimer(clock.now().add(backoffWindowFor(_failedPasses)));
    } else {
      _failedPasses = 0;
    }
    _armForWaitingRows();
  }

  /// The first pass of this controller's life also sweeps the vault.
  bool _sweptOrphans = false;

  /// Removes this user's vault folders that have no row (a kill between
  /// the pipeline's adopt and its outbox write, final review #3c). Never
  /// fails a pass: a sweep that cannot run is tried on the next launch.
  Future<void> _sweepOrphans() async {
    try {
      await _vault.sweepOrphans(
        _userId,
        () => _store.readIdsOrNull(_userId),
      );
    } catch (error) {
      ChatLog.e('story outbox: orphan sweep skipped', error);
    }
  }

  /// Clears backoff and drives a `failedPermanent` record through the
  /// machine again, from a user's explicit Retry tap. Returns the
  /// [flush] future for the same reason [enqueue] does.
  ///
  /// Resets [StoryOutboxRecord.strikes] (and `attempts`) to 0, not just
  /// `nextAttemptAt` and `lastErrorCode`: a record reaches `failedPermanent`
  /// once `strikes >= maxStrikes`, so leaving the old count in
  /// place would let the very next failure land back at the ceiling
  /// immediately regardless of whether it was retryable — turning Retry
  /// into "try once more, then give up forever" instead of a real
  /// restart of the backoff cycle. A manual tap is a deliberate act on a
  /// (presumably) changed network situation and deserves a full new run
  /// at the automatic ceiling, the same as a fresh capture gets.
  ///
  /// Also clears the record's persisted intents (`clearIntents`): a record
  /// can sit in `failedPermanent` far past the server's 15-minute intent
  /// expiry, and a manual retry is rare enough that always re-minting is
  /// cheap and certain. The automatic path re-mints on its own when either
  /// intent is within [remintMargin] of expiry (`_ensureIntents`), and a
  /// server refusal of a stale pair (Storage 403 / finalize UNAVAILABLE)
  /// drops it too (`_handleFailure`).
  Future<void> retry(String clientStoryId) async {
    if (_disposed) return;
    final epoch = _store.epoch;
    final rows = await _store.readAll(_userId);
    if (_stale(epoch)) return;
    final record = rows.where((r) => r.clientStoryId == clientStoryId).firstOrNull;
    if (record == null) return;
    final reset = record.copyWith(
      state: StoryOutboxState.queued,
      attempts: 0,
      strikes: 0,
      slowUploads: 0,
      clearIntents: true,
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
    await _remove(clientStoryId);
  }

  /// Stops a story before it posts (01 #13). Refused once finalize has been
  /// sent: the post may already exist, and Delete-from-reel owns that case.
  /// A story waiting on its backoff is removed without any network call.
  ///
  /// A `finalizing` row that is not being driven has sent finalize on an
  /// earlier attempt (a network failure, or a kill, after the request left)
  /// or may have: the story may already be live, so it is refused too and
  /// posts on its next retry (batch-3 review I1). Read from the in-memory
  /// [state] so the check stays synchronous with the `_discarded` mark. A
  /// drive that has written `finalizing` but not yet sent the call is in
  /// [_inFlight] and halts cleanly.
  Future<StoryCancelOutcome> cancel(String clientStoryId) async {
    final row = state.where((r) => r.clientStoryId == clientStoryId).firstOrNull;
    if (_finalizeSent.contains(clientStoryId) ||
        (row?.state == StoryOutboxState.finalizing &&
            !_inFlight.contains(clientStoryId))) {
      return StoryCancelOutcome.alreadyPosting;
    }
    final found = await _remove(clientStoryId);
    if (!found) return StoryCancelOutcome.notFound;
    // The timer may have been due for this row only; re-arm for the rest.
    _retryTimer?.cancel();
    _retryTimer = null;
    _retryDue = null;
    _armForWaitingRows();
    return StoryCancelOutcome.cancelled;
  }

  /// [discard] and [cancel]: the row, its files and its progress go, and
  /// a drive in flight halts. Returns whether the row existed.
  Future<bool> _remove(String clientStoryId) async {
    // Marked before the first await: a pass already holding this row in its
    // snapshot stops instead of driving or writing it back.
    _discarded.add(clientStoryId);
    // Aborts an intent call or upload already on the wire, so our own
    // client leaves no orphan object behind (batch-2 fix round, concern 2).
    _tokens[clientStoryId]?.cancel();
    final rows = await _store.readAll(_userId);
    final record = rows.where((r) => r.clientStoryId == clientStoryId).firstOrNull;
    if (record != null) await _vault.deleteFor(record);
    await _store.remove(_userId, clientStoryId);
    _setProgress(clientStoryId, null);
    await _refreshState();
    return record != null;
  }

  /// Advances one record by exactly one step, persisting the new state
  /// before moving to the next so a crash mid-flow resumes rather than
  /// restarts. Errors are caught here, not by [flush] — a failure of one
  /// story must never abort the rest of the queue.
  ///
  /// [epoch] is the store's wipe epoch when the pass started: after every
  /// await the drive stops without writing if a wipe (sign-out) has landed
  /// or the controller was disposed (01 #12, Review Focus 2).
  Future<void> _drive(StoryOutboxRecord record, int epoch) async {
    // Declared outside the try block and updated as each step commits, so
    // a failure handler always sees the record's LATEST persisted state
    // (e.g. `finalizing`) rather than the state it started this call in.
    // A finalize UNAVAILABLE must be recognised as a finalize failure —
    // using the stale `record` here would always read `queued` and treat
    // every failure as a fresh, un-uploaded capture.
    var current = record;
    final id = record.clientStoryId;
    var mintedThisDrive = false;
    // When this drive minted its pair (the device clock at the answer), and
    // whether the media went up in this drive: together they tell "the
    // link was too slow for the pair" apart from any other refusal (final
    // review #2).
    DateTime? mintedAt;
    var mediaUploadedThisDrive = false;
    final token = _tokens[id] = ChatUploadCancelToken();
    // A fraction left by a controller disposed mid-upload would hold the
    // throttle below until this upload passed it (review M1).
    _setProgress(id, null);
    try {
      if (current.state == StoryOutboxState.queued) {
        current = await _persist(
          current.copyWith(state: StoryOutboxState.uploadingMedia),
          epoch,
        );
        if (_halt(epoch, id)) return;
      }

      // Before the first upload step (whichever it is).
      final before = current.mediaIntent;
      current = await _ensureIntents(current, epoch, token);
      if (!identical(current.mediaIntent, before)) {
        mintedThisDrive = true;
        mintedAt = clock.now();
      }
      if (_halt(epoch, id)) return;

      // At most two rounds: an inherited pair that ran near expiry during
      // the media upload is re-minted once, and the media goes up again
      // under the fresh pair.
      while (true) {
        if (current.state == StoryOutboxState.uploadingMedia) {
          await _uploadStep(
            intent: current.mediaIntent!,
            localPath: await _vault.resolve(current.localMediaPath),
            mimeType: current.mimeType,
            cancelToken: token,
            onProgress: (sent, total) {
              if (total <= 0 || _halt(epoch, id)) return;
              final fraction = (sent / total).clamp(0.0, 1.0);
              final previous =
                  _ref.read(storyUploadProgressProvider)[id] ?? -1;
              // About 100 updates at most for the whole upload.
              if ((fraction - previous).abs() < 0.01 && fraction < 1) return;
              _setProgress(id, fraction);
            },
          );
          if (_halt(epoch, id)) return;
          mediaUploadedThisDrive = true;
          current = await _persist(
            current.copyWith(state: StoryOutboxState.uploadingThumbnail),
            epoch,
          );
          if (_halt(epoch, id)) return;
        }

        // Before the thumbnail step too (spec §6.1): the media upload may
        // have run the pair down. Only a media upload in this drive can
        // have; at the start of a drive _ensureIntents already checked.
        if (current.state == StoryOutboxState.uploadingThumbnail &&
            mediaUploadedThisDrive &&
            !_pairFresh(current, mintedAt)) {
          // This drive's own pair: the link cannot finish inside the
          // window, and re-minting would only start the same upload over.
          if (mintedAt != null) throw const _SlowLink();
          // An inherited pair (a resumed record): re-mint once, no strike.
          current = await _ensureIntents(current, epoch, token, force: true);
          if (_halt(epoch, id)) return;
          mintedThisDrive = true;
          mintedAt = clock.now();
          continue;
        }
        break;
      }

      if (current.state == StoryOutboxState.uploadingThumbnail) {
        await _uploadStep(
          intent: current.thumbnailIntent!,
          localPath: await _vault.resolve(current.localThumbnailPath),
          mimeType: 'image/jpeg',
          cancelToken: token,
        );
        if (_halt(epoch, id)) return;
        current = await _persist(
          current.copyWith(state: StoryOutboxState.finalizing),
          epoch,
        );
        if (_halt(epoch, id)) return;
      }

      if (current.state == StoryOutboxState.finalizing) {
        // From here the post may exist: cancel() refuses (01 #13). Set in
        // the same synchronous run as the call, after the last halt check.
        // NO await may sit between that check and this line: a cancel
        // landing there would report "cancelled" for a story that then
        // posts. Pinned by story_outbox_policy_test.dart "cancel's no-await
        // window" (final review, code health).
        _finalizeSent.add(id);
        // The date is the capture's (Wave 5, spec §3.5/§6.1): createdAt and
        // utcOffsetMinutes travel from the record as captured. The server
        // clamps the instant to the last 7 days; the 24-hour reel window
        // still starts when this call lands.
        await _gateway.finalizeStory(
          relationshipId: current.relationshipId,
          clientStoryId: current.clientStoryId,
          mediaIntentId: current.mediaIntent!.intentId,
          thumbnailIntentId: current.thumbnailIntent!.intentId,
          mediaWidth: current.width,
          mediaHeight: current.height,
          durationMs: current.durationMs,
          utcOffsetMinutes: current.utcOffsetMinutes,
          place: current.place?.toJson(),
          capturedAt: _captureInstant(current),
        );
        // A wipe since the pass began owns the row and the files now.
        if (_halt(epoch, id)) return;

        // Success — whether this call created the story or landed on an
        // existing one via the idempotency key, the outcome for the
        // client is identical: the story exists, stop posting it.
        // 03 M1: keep it on my ring until a summary issued after now lands.
        final thumbnailBytes = await _vault.readThumbnailBytes(current);
        if (_halt(epoch, id)) return;
        final thumbnailKey = current.thumbnailIntent?.storageKey;
        // Review #1: on disk under the key the summary will name, so the
        // release paints from disk, not grey. Not awaited: never holds posting.
        if (thumbnailBytes != null && thumbnailKey != null) {
          unawaited(
            Future.sync(
              () => _ref.read(storyThumbnailSeederProvider)(
                thumbnailKey,
                thumbnailBytes,
              ),
            ).catchError((Object _) {}),
          );
        }
        _ref
            .read(storyPostedHoldsProvider.notifier)
            .hold(
              StoryPostedHold(
                relationshipId: current.relationshipId,
                clientStoryId: current.clientStoryId,
                heldAt: clock.now(),
                thumbnailBytes: thumbnailBytes,
                thumbnailStorageKey: thumbnailKey,
              ),
            );
        await _vault.deleteFor(current);
        await _store.remove(_userId, current.clientStoryId);
        await _refreshState();
        // The realtime signal can be missed: ask for the summary now.
        _ref.invalidate(storyRingSummaryProvider(current.relationshipId));
      }
    } catch (error) {
      final classified =
          error is _SlowLink
              ? const StoryApiError(
                code: StoryErrorCodes.mediaLinkTooSlow,
                message: 'The connection was too slow.',
                retryable: false,
              )
              : StoryApiError.fromFailure(error);
      // Finalize refused (UNAVAILABLE) after this drive uploaded the media
      // under its own pair, and long enough after the mint for the pair to
      // have expired on the way: the same slow link, seen at finalize.
      final slowAtFinalize =
          current.state == StoryOutboxState.finalizing &&
          classified.code == 'UNAVAILABLE' &&
          mediaUploadedThisDrive &&
          mintedAt != null &&
          clock.now().difference(mintedAt) >=
              _pairLifetime(current, mintedAt) - remintMargin;
      await _handleFailure(
        current,
        classified,
        epoch,
        mintedThisDrive: mintedThisDrive,
        slowLink: error is _SlowLink || slowAtFinalize,
      );
    } finally {
      if (identical(_tokens[id], token)) _tokens.remove(id);
      _finalizeSent.remove(id);
      _setProgress(id, null);
    }
  }

  /// One upload step. A 409 on our own key means an earlier attempt's
  /// upload already landed (V12): the step is done; finalize re-verifies
  /// the object's size and MIME server-side.
  Future<void> _uploadStep({
    required StoryUploadIntent intent,
    required String localPath,
    required String mimeType,
    required ChatUploadCancelToken cancelToken,
    void Function(int sent, int total)? onProgress,
  }) async {
    try {
      await _gateway.uploadObject(
        bucket: intent.bucket,
        storageKey: intent.storageKey,
        localPath: localPath,
        mimeType: mimeType,
        onProgress: onProgress,
        cancelToken: cancelToken,
      );
    } on StoryApiError catch (e) {
      if (e.kind == StoryFailureKind.alreadyUploaded) return;
      rethrow;
    }
  }

  /// Re-mint before using a pair that expires within this margin (spec
  /// §4.2: 15-minute image intents; video and thumbnail intents last an
  /// hour since Wave 5). Re-minting is never a strike.
  static const Duration remintMargin = Duration(minutes: 2);

  bool _nearExpiry(StoryUploadIntent intent) =>
      intent.expiresAt.difference(clock.now()) < remintMargin;

  /// The shortest intent lifetime the server issues (image media, spec
  /// §4.2; `stories_intent_rpc.sql`, `story_intent_hardening.sql`). A
  /// pair's own lifetime is read at the mint ([_pairLifetime]).
  static const Duration intentLifetime = Duration(minutes: 15);

  /// The longest intent lifetime the server issues: video media and every
  /// thumbnail (`story_intent_hardening.sql`).
  static const Duration videoIntentLifetime = Duration(minutes: 60);

  /// Two full uploads that outlived their pair end the record as
  /// `media_link_too_slow` instead of five re-uploads and a generic failure
  /// (final review #2).
  static const int maxSlowUploads = 2;

  /// Whether [record]'s pair can still carry the next step. A pair minted
  /// this drive is judged by the time elapsed since [mintedAt] against its
  /// lifetime as seen at the mint (never shorter than [intentLifetime]), so
  /// a skewed device clock cannot call a fresh pair stale (Review Focus 1);
  /// an inherited pair by its `expiresAt`, as at the start of a drive.
  bool _pairFresh(StoryOutboxRecord record, DateTime? mintedAt) {
    final media = record.mediaIntent;
    final thumb = record.thumbnailIntent;
    if (media == null || thumb == null) return false;
    if (mintedAt == null) return !_nearExpiry(media) && !_nearExpiry(thumb);
    final lifetime = _pairLifetime(record, mintedAt);
    return lifetime - clock.now().difference(mintedAt) >= remintMargin;
  }

  /// The pair's lifetime as seen at the mint: its sooner expiry minus
  /// [mintedAt], clamped to [intentLifetime] .. the server's lifetime for
  /// the record's type, so a skewed device clock can neither shorten it
  /// (Review Focus 1) nor stretch it (Review Focus 3: a phone behind the
  /// server). Since Wave 5 the server gives video media and thumbnails an
  /// hour and image media 15 minutes, so a video pair lasts an hour and an
  /// image pair 15 minutes.
  Duration _pairLifetime(StoryOutboxRecord record, DateTime mintedAt) {
    final media = record.mediaIntent;
    final thumb = record.thumbnailIntent;
    if (media == null || thumb == null) return intentLifetime;
    final expires =
        media.expiresAt.isBefore(thumb.expiresAt)
            ? media.expiresAt
            : thumb.expiresAt;
    final lifetime = expires.difference(mintedAt);
    final longest =
        record.mediaType == CapturedMediaType.video
            ? videoIntentLifetime
            : intentLifetime;
    if (lifetime < intentLifetime) return intentLifetime;
    return lifetime > longest ? longest : lifetime;
  }

  /// Returns [record] holding a usable pair, minting one when it has none
  /// or when either is near expiry. A new pair means new keys, so a record
  /// past `uploadingMedia` goes back to it: both objects are re-uploaded.
  /// The pair is persisted (encrypted) before any upload uses it.
  ///
  /// Called at the start of each drive, and again ([force]) before the
  /// thumbnail step when an inherited pair ran near expiry during the
  /// media upload. A pair it mints is judged by elapsed time, never by the
  /// device clock against `expiresAt` (Review Focus 1, [_pairFresh]): the
  /// server, not this phone, decides whether it has expired, and a refusal
  /// comes back as Storage 403 / finalize UNAVAILABLE (intentStale). A record with no pair, or one whose pair
  /// was replaced, is always at `uploadingMedia` afterwards: new keys mean
  /// both objects go up again (01 #8: the old code finalized a fresh pair
  /// whose media was never uploaded).
  Future<StoryOutboxRecord> _ensureIntents(
    StoryOutboxRecord record,
    int epoch,
    ChatUploadCancelToken token, {
    bool force = false,
  }) async {
    final media = record.mediaIntent;
    final thumb = record.thumbnailIntent;
    // Both objects are up: finalize with the pair they went up under, near
    // expiry or not. The server checks idempotency before it checks the
    // intents (20260938120000_stories_finalize_race_fix.sql:93-98), so a
    // story that already posted answers `existing: true`; an expired pair
    // answers UNAVAILABLE, which re-mints (no strike, see _handleFailure).
    // Re-minting here instead would re-upload both objects, and a record
    // whose files were already deleted after a post would end as
    // media_missing (batch-2 review #2).
    if (!force &&
        record.state == StoryOutboxState.finalizing &&
        media != null &&
        thumb != null) {
      return record;
    }
    if (!force &&
        media != null &&
        thumb != null &&
        !_nearExpiry(media) &&
        !_nearExpiry(thumb)) {
      return record;
    }
    final freshMedia = await raceUploadCancel(
      _gateway.createUploadIntent(
        relationshipId: record.relationshipId,
        objectKind: 'media',
        mediaType: record.mediaType.name,
        mimeType: record.mimeType,
      ),
      token,
    );
    if (_halt(epoch, record.clientStoryId)) return record;
    final freshThumb = await raceUploadCancel(
      _gateway.createUploadIntent(
        relationshipId: record.relationshipId,
        objectKind: 'thumbnail',
        mediaType: 'image',
        mimeType: 'image/jpeg',
      ),
      token,
    );
    return _persist(record.copyWith(
      mediaIntent: freshMedia,
      thumbnailIntent: freshThumb,
      state: StoryOutboxState.uploadingMedia,
    ), epoch);
  }

  /// Writes [record] unless [epoch] is stale, in which case it returns
  /// [record] unchanged without writing (the caller then stops).
  Future<StoryOutboxRecord> _persist(StoryOutboxRecord record, int epoch) async {
    if (_halt(epoch, record.clientStoryId)) return record;
    await _store.put(_userId, record);
    await _refreshState();
    return record;
  }

  Future<void> _handleFailure(
    StoryOutboxRecord original,
    StoryApiError error,
    int epoch, {
    required bool mintedThisDrive,
    bool slowLink = false,
  }) async {
    if (_halt(epoch, original.clientStoryId)) return;
    final kind = error.kind;
    // A cancel removes the row itself (Task 8); nothing to record.
    if (kind == StoryFailureKind.cancelled) return;
    if (slowLink) {
      await _recordSlowUpload(original, epoch);
      return;
    }

    // Finalize UNAVAILABLE is the server's collapsed "expired intent"
    // (StoryApiError doc): structurally the same recovery as Storage 403.
    final isFinalizeUnavailable =
        original.state == StoryOutboxState.finalizing && error.code == 'UNAVAILABLE';
    final intentStale = kind == StoryFailureKind.intentStale || isFinalizeUnavailable;

    // Finalize was sent with an inherited pair this phone already saw as
    // near expiry (_ensureIntents keeps a finalizing pair): the refusal is
    // the re-mint the automatic path would have done, so no strike. A pair
    // minted in this same drive still strikes, so a skewed clock cannot turn
    // a genuinely permanent UNAVAILABLE into an endless loop.
    final remintOnly = isFinalizeUnavailable &&
        !mintedThisDrive &&
        original.mediaIntent != null &&
        original.thumbnailIntent != null &&
        (_nearExpiry(original.mediaIntent!) || _nearExpiry(original.thumbnailIntent!));

    final attempts = original.attempts + 1;
    final strikes = original.strikes +
        ((kind == StoryFailureKind.unknown || (intentStale && !remintOnly)) ? 1 : 0);
    final permanent = switch (kind) {
      StoryFailureKind.mediaRejected || StoryFailureKind.mediaMissing => true,
      StoryFailureKind.refused => !isFinalizeUnavailable || strikes >= maxStrikes,
      StoryFailureKind.offline || StoryFailureKind.rateLimited => false,
      _ => strikes >= maxStrikes,
    };

    final windowMillis = backoffWindowFor(attempts).inMilliseconds;
    final backoffMillis =
        (windowMillis ~/ 2) + _backoffJitter.nextInt(windowMillis ~/ 2 + 1);

    final updated = original.copyWith(
      attempts: attempts,
      strikes: strikes,
      lastErrorCode: error.code,
      state: permanent
          ? StoryOutboxState.failedPermanent
          : (intentStale ? StoryOutboxState.queued : original.state),
      clearIntents: intentStale,
      nextAttemptAt: permanent
          ? null
          : clock.now().add(Duration(milliseconds: backoffMillis)),
      clearNextAttemptAt: permanent,
    );

    await _store.put(_userId, updated);
    await _refreshState();

    final due = updated.nextAttemptAt;
    if (!permanent && due != null) _armRetryTimer(due);
  }

  /// A full upload outlived its pair (final review #2): the next attempt
  /// needs a fresh pair and a fresh upload, which a link this slow cannot
  /// finish either. The second time, stop and say why
  /// (`media_link_too_slow`, Retry kept) rather than burn five full
  /// uploads and end on a generic failure. Not a strike.
  Future<void> _recordSlowUpload(StoryOutboxRecord original, int epoch) async {
    final slow = original.slowUploads + 1;
    final permanent = slow >= maxSlowUploads;
    final attempts = original.attempts + 1;
    final windowMillis = backoffWindowFor(attempts).inMilliseconds;
    final backoffMillis =
        (windowMillis ~/ 2) + _backoffJitter.nextInt(windowMillis ~/ 2 + 1);
    final updated = original.copyWith(
      attempts: attempts,
      slowUploads: slow,
      lastErrorCode: StoryErrorCodes.mediaLinkTooSlow,
      state:
          permanent
              ? StoryOutboxState.failedPermanent
              : StoryOutboxState.queued,
      clearIntents: true,
      nextAttemptAt:
          permanent
              ? null
              : clock.now().add(Duration(milliseconds: backoffMillis)),
      clearNextAttemptAt: permanent,
    );
    if (_halt(epoch, original.clientStoryId)) return;
    await _store.put(_userId, updated);
    await _refreshState();
    final due = updated.nextAttemptAt;
    if (!permanent && due != null) _armRetryTimer(due);
  }
}

/// Thrown inside a drive when its own pair ran out during the media upload.
class _SlowLink implements Exception {
  const _SlowLink();
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

/// The capture instant in UTC (Wave 5, 04 #3). A record stores `createdAt`
/// as a zone-less local ISO string, so parsing it back reads the wall clock
/// in the phone's CURRENT zone; after a zone change while queued that is the
/// wrong instant. The record's own `utcOffsetMinutes` (taken at capture)
/// turns the wall clock back into the true instant. A UTC value is exact.
DateTime _captureInstant(StoryOutboxRecord record) {
  final c = record.createdAt;
  if (c.isUtc) return c;
  return DateTime.utc(
    c.year,
    c.month,
    c.day,
    c.hour,
    c.minute,
    c.second,
    c.millisecond,
    c.microsecond,
  ).subtract(Duration(minutes: record.utcOffsetMinutes));
}

/// One controller per signed-in user — the queue itself is per-user (spec
/// §6.1's record has no notion of "no user"), not per-relationship, so
/// this is a plain provider keyed by the current auth id rather than a
/// `.family`.
final storyOutboxProvider =
    StateNotifierProvider<StoryOutboxController, List<StoryOutboxRecord>>((ref) {
  // Keyed on the id, not the User: a metadata update must not spin up a
  // second controller driving the same record (01 #12).
  final userId = ref.watch(currentUserProvider.select((u) => u?.id)) ?? '';
  return StoryOutboxController(ref, userId);
});

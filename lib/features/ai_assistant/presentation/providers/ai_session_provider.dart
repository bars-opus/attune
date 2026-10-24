// lib/features/ai_assistant/presentation/providers/ai_session_provider.dart
//
// Riverpod surface for multi-turn AI Sessions (spec §3-§8): the
// repository provider, and the sheet-scoped controller that drives
// prepare -> review_context -> approve -> generate -> read -> share.
//
// `aiSessionRepositoryProvider` is a plain, non-autoDispose `Provider`,
// matching `aiAssistantRepositoryProvider`'s own shape exactly
// (`ai_assistant_providers.dart:37`): the repository is stateless over
// a gateway, so there is nothing sheet-scoped in it to tear down.
//
// `aiSessionControllerProvider` is `.autoDispose`, matching
// `assistDraftProvider`/`understandResultProvider`, for the SAME
// §1 reason they are: a fresh sheet open must be a fresh instance, so
// no session's transcript can be context for an unrelated later one.
//
// ## IT IS NOT A `.family` KEYED BY SESSION ID, and the brief's
// suggestion that it should be cannot be built
//
// Sub-step A's brief says "a session ID keyed `.family` provider ... is
// the right shape here: `aiSessionControllerProvider(sessionId)`". That
// shape is unimplementable for this flow: **the session id does not
// exist until `prepare()` returns it.** `prepare` is the command that
// creates the session, and the id it reports is the
// `idempotency_key` the client generated for that call (Plan C Ruling
// 5: "the key BECOMES the session id") — so a family keyed by session
// id would have to be read with a key the caller invents before any
// server round trip, and then would be a DIFFERENT provider instance
// from the one holding the prepared session if the server replayed an
// earlier key (`created: false`, returning the ORIGINAL session).
//
// So the controller is keyed by the sheet instead, holds the id
// `prepare` reported, and the one thing a family would have bought —
// isolation between two concurrently-open sessions — comes from
// `.autoDispose` plus the sheet owning the only reference.
library;

import 'dart:async';

import 'package:attune/core/services/app_content_visibility.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show Supabase, SupabaseClient;

import '../../data/models/ai_session_model.dart';
import '../../data/models/ai_session_turn_model.dart';
import '../../data/repositories/ai_assistant_repository.dart';
import '../../data/repositories/ai_session_repository.dart';

/// The sessions repository. Plain `Provider`, non-autoDispose, reusing
/// the gateway shape `aiAssistantRepositoryProvider` already
/// establishes — both wrap the same `ai-sessions`/`ai-assist` edge
/// function surface over one `SupabaseAiAssistantGateway`.
final aiSessionRepositoryProvider = Provider<AiSessionRepository>((ref) {
  return AiSessionRepository(
    SupabaseAiAssistantGateway(ref.read(_supabaseClientForSessionsProvider)),
  );
});

/// Private mirror of `ai_assistant_providers.dart`'s own
/// `_supabaseClientProvider`, which is library-private there. Declared
/// here rather than making that one public so a test can override THIS
/// feature's client without widening the other file's surface — and in
/// practice tests override `aiSessionRepositoryProvider` whole, which
/// is why this is never reached under test.
final _supabaseClientForSessionsProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

/// Where the sheet is in the session lifecycle.
///
/// **Deliberately NOT derived from the server's own `state` enum.**
/// `AiSessionState` has exactly two values (`preparing`, `active`) and
/// describes the ROW; this describes what the sheet is showing, which
/// includes states the row has no name for (nothing prepared yet, a
/// context under review, a generation in flight) and deliberately
/// does NOT include a state for "gone": §7.2's silence requirement
/// means an empty `read` is not evidence a session ended, so there is
/// no phase here a `read` can put the sheet into.
enum AiSessionPhase {
  /// Nothing prepared. The kind/visibility choice is on screen.
  choosing,

  /// `prepare` returned; the reviewed context is on screen awaiting
  /// this actor's approval.
  reviewing,

  /// This actor approved and the server reported
  /// `{approved: true, activated: false, state: "preparing"}` — a
  /// **200 SUCCESS** meaning the partner has not approved yet. Never
  /// an error. See [AiSessionController.approve].
  waitingForPartner,

  /// Activated. The transcript and the instruction field are live.
  active,

  /// `end` succeeded. Terminal for this sheet.
  ended,
}

/// Everything the sheet renders, in one immutable value.
///
/// ## `staged` IS NULLABLE AND THE NULL IS LOAD-BEARING (RULING 9)
///
/// `handleRead` sends `staged` ABSENT when the caller supplied no
/// `request_id` and as a possibly-EMPTY array when it did, "so a client
/// can tell 'I did not ask' from 'I asked and there is nothing'".
/// [stagedResults] carries that distinction through: `null` means no
/// read asked, `[]` means a read asked and the staging row is gone or
/// expired. **No `?? []` may appear here or at any call site** — the
/// first one destroys the only distinction the server deliberately
/// draws, and a sheet is exactly where it gets lost (a widget that
/// writes `staged ?? []` to feed a `ListView` reads "expired" as "never
/// asked" and would silently stop offering Publish/Discard).
class AiSessionViewState {
  final AiSessionPhase phase;

  /// The server session id, once `prepare` reported one.
  final String? sessionId;

  /// The latest revision this actor has seen.
  ///
  /// **Only ever assigned from a server response that carried one**
  /// (gate 1: `session_revision` reaches only the actor who caused the
  /// bump, so there is nothing to fall back to and nothing to
  /// increment locally). Null until `prepare` or `review_context`
  /// reports one.
  final int? revision;

  /// What `review_context` rendered for this actor to approve: the
  /// window snippets, the stored toggle, the offset. **Holds no
  /// digest** — gate 2's split keeps the digest out of anything a
  /// widget can see.
  final AiSessionContextReview? review;

  /// Committed turns, in the server's own `ORDER BY ordinal`.
  ///
  /// **May be NON-CONTIGUOUS** (a failed attempt advances the counter,
  /// so 3/4 with no 1/2 is a legal transcript) and emptiness carries no
  /// verdict (§7.2). Nothing indexes this list by ordinal, asserts
  /// `turns[i].ordinal == i + 1`, or derives an attempt count from its
  /// length.
  final List<AiSessionTurnModel> turns;

  /// This actor's own staged Nearby results. **See the class header:
  /// null and empty are different.**
  final List<AiSessionStagedNearbyResult>? stagedResults;

  /// A staged Nearby generation this actor just produced and has not
  /// yet published or discarded. Distinct from [stagedResults], which
  /// is the same row as `read` PROJECTS it — the two types are not
  /// merged because `generate` sends no `expires_at`.
  final AiSessionStagedNearbyGeneration? pendingStage;

  /// The redirect to show, when the last `generate` or `publishNearby`
  /// answered with one.
  ///
  /// **ONE field for BOTH redirect shapes and for BOTH commands**
  /// (Ruling 6 / Ruling 15). There is no second field, no flag beside
  /// it and no enum saying where it came from: a publish-time refusal
  /// and a `generate` redirect land in the same slot and therefore in
  /// the same widget. A `publishRedirect` field beside this one would
  /// be `wasBlockedBySafety` by another name, because on the publish
  /// path a redirect is always a safety refusal.
  final AiSessionGeneratedRedirect? redirect;

  /// A §10 error to show, mapped from its CODE.
  final Object? error;

  /// True while a command is in flight.
  final bool busy;

  const AiSessionViewState({
    this.phase = AiSessionPhase.choosing,
    this.sessionId,
    this.revision,
    this.review,
    this.turns = const <AiSessionTurnModel>[],
    this.stagedResults,
    this.pendingStage,
    this.redirect,
    this.error,
    this.busy = false,
  });

  /// Copies, with `null` meaning "unchanged" for every nullable field
  /// EXCEPT where an explicit clear flag says otherwise.
  ///
  /// The clear flags exist because `copyWith(redirect: null)` cannot
  /// express "clear the redirect" in Dart without one — and silently
  /// carrying a stale redirect into the next turn would show the user
  /// a refusal for a request they already replaced.
  ///
  /// [clearStagedResults] is the RULING 9 flag: it distinguishes "this
  /// copy does not touch `stagedResults`" from "this copy sets it back
  /// to null, because no read asked". Without it, a copy could only
  /// ever move the field away from null, so the `null` leg would be
  /// unreachable after the first read and the distinction would be
  /// one-way.
  AiSessionViewState copyWith({
    AiSessionPhase? phase,
    String? sessionId,
    int? revision,
    AiSessionContextReview? review,
    List<AiSessionTurnModel>? turns,
    List<AiSessionStagedNearbyResult>? stagedResults,
    AiSessionStagedNearbyGeneration? pendingStage,
    AiSessionGeneratedRedirect? redirect,
    Object? error,
    bool? busy,
    bool clearStagedResults = false,
    bool clearPendingStage = false,
    bool clearRedirect = false,
    bool clearError = false,
  }) {
    return AiSessionViewState(
      phase: phase ?? this.phase,
      sessionId: sessionId ?? this.sessionId,
      revision: revision ?? this.revision,
      review: review ?? this.review,
      turns: turns ?? this.turns,
      stagedResults: clearStagedResults
          ? null
          : (stagedResults ?? this.stagedResults),
      pendingStage: clearPendingStage
          ? null
          : (pendingStage ?? this.pendingStage),
      redirect: clearRedirect ? null : (redirect ?? this.redirect),
      error: clearError ? null : (error ?? this.error),
      busy: busy ?? this.busy,
    );
  }
}

/// Drives one session, one sheet.
///
/// `AutoDisposeNotifier` over an immutable [AiSessionViewState] rather
/// than `AutoDisposeAsyncNotifier<T?>`, and the reason is the state
/// shape rather than preference: `assistDraftProvider` holds ONE result
/// whose loading/error/data triple is the whole state, so
/// `AsyncNotifier` fits it exactly. A session holds several things at
/// once — a phase, a transcript, a staged result, a redirect, an error
/// — and an `AsyncValue` wrapper around that record would make
/// "loading" erase the transcript on every turn, which is the opposite
/// of a live transcript. `busy`/`error` are therefore fields of the
/// state, and the `.autoDispose` sheet-scoping that matters for §1 is
/// identical.
class AiSessionController extends AutoDisposeNotifier<AiSessionViewState> {
  @override
  AiSessionViewState build() {
    // STOP 2 OF 4 FOR THE POLL, registered here because `Notifier` has
    // NO `dispose` TO OVERRIDE — `ref.onDispose` is Riverpod's teardown
    // hook, and writing `@override void dispose()` compiles to nothing
    // useful (it is not an inherited member, which the analyzer reports
    // as `override_on_non_overriding_member` / `undefined_super_member`;
    // measured, not assumed). Without this, an `.autoDispose` controller
    // whose sheet closed leaves a live periodic timer calling
    // `_pollTick` on a disposed notifier — and writing to `state` after
    // disposal throws, so the leak is noisy rather than silent.
    //
    // Registered in `build` so it is re-armed if the provider is rebuilt.
    ref.onDispose(stopPolling);
    // The shell keeps the sheet mounted behind the privacy cover (stories
    // Wave 3), so leaving no longer tears this down: [_pollTick] skips
    // while Attune is not on screen, and a return catches up at once.
    ref.listen<bool>(appContentVisibleProvider, (prev, next) {
      if (next && prev == false && _pollTimer != null) unawaited(_pollTick());
    });
    // Idle until prepare() is called — a fresh sheet open is a fresh
    // instance, so nothing here carries over from a previous session.
    return const AiSessionViewState();
  }

  AiSessionRepository get _repository => ref.read(aiSessionRepositoryProvider);

  /// Runs [action], holding `busy` for its duration and mapping a
  /// thrown §10 error into [AiSessionViewState.error].
  ///
  /// Every command goes through here so no path can forget to clear
  /// `busy`, and so the error slot is written in exactly one place.
  /// The error is stored UNMAPPED — the sheet maps the CODE to copy, so
  /// this layer never converts a typed error into a string a widget
  /// then has to re-interpret.
  Future<void> _run(Future<void> Function() action) async {
    state = state.copyWith(busy: true, clearError: true);
    try {
      await action();
    } catch (error) {
      state = state.copyWith(error: error);
    } finally {
      state = state.copyWith(busy: false);
    }
  }

  /// `prepare` + the first `review_context`, in one step.
  ///
  /// They are combined because a prepared session with no reviewed
  /// context is not a state the sheet can render anything useful for:
  /// `prepare` deliberately withholds the context text, and
  /// `review_context` is what discloses the window after its own
  /// authorization. [utcOffsetMinutes] must be the offset the UI
  /// DISPLAYED — the server refuses out of range rather than clamping,
  /// because a clamped offset computes a different civil day than the
  /// user saw.
  Future<void> prepare({
    required String idempotencyKey,
    required String relationshipId,
    required AiSessionKind kind,
    required AiSessionVisibility visibility,
    required int utcOffsetMinutes,
    String? targetMessageId,
    bool includeWindow = false,
  }) {
    return _run(() async {
      final prepared = await _repository.prepare(
        idempotencyKey: idempotencyKey,
        relationshipId: relationshipId,
        kind: kind.wireValue,
        visibility: visibility.wireValue,
        utcOffsetMinutes: utcOffsetMinutes,
        targetMessageId: targetMessageId,
        includeWindow: includeWindow,
      );
      // `prepared.sessionId` is READ rather than assumed equal to the
      // key: a replay (`created: false`) returns the ORIGINAL session.
      state = state.copyWith(
        sessionId: prepared.sessionId,
        revision: prepared.revision,
      );
      await _reviewContext(
        sessionId: prepared.sessionId,
        utcOffsetMinutes: utcOffsetMinutes,
      );
    });
  }

  /// Re-reads the context. The remedy for a `CONTEXT_CHANGED` and the
  /// only way to obtain an approvable ticket.
  Future<void> refreshContext({required int utcOffsetMinutes}) {
    final sessionId = state.sessionId;
    if (sessionId == null) return Future<void>.value();
    return _run(
      () => _reviewContext(
        sessionId: sessionId,
        utcOffsetMinutes: utcOffsetMinutes,
      ),
    );
  }

  /// Toggles the shared recent window.
  ///
  /// [include] is passed straight through as `setIncludeWindow`, which
  /// is tri-state on the wire: `false` is a REAL WRITE that bumps the
  /// revision and clears BOTH partners' approvals, and `null` (not
  /// offered by this method) means "do not toggle". So this method is
  /// never called to merely re-read — [refreshContext] is.
  Future<void> setIncludeWindow({
    required bool include,
    required int utcOffsetMinutes,
  }) {
    final sessionId = state.sessionId;
    if (sessionId == null) return Future<void>.value();
    return _run(
      () => _reviewContext(
        sessionId: sessionId,
        utcOffsetMinutes: utcOffsetMinutes,
        setIncludeWindow: include,
      ),
    );
  }

  /// RULING 12: the record is DESTRUCTURED at this call site rather
  /// than held.
  ///
  /// `final (:review, :ticket) = await ...` is gate 2's compile-time
  /// proof: Dart records are structural, so a third field added to the
  /// repository's return type is a compile error here, and the field
  /// NAMES are what carry the proof. Loosening this to
  /// `final result = await ...` and passing `result` around would
  /// silently remove the guard without failing anything — which is
  /// exactly what Ruling 12 forbids, and why the ticket is stored in a
  /// private field reachable only by [approve] while `review` goes into
  /// the state a widget can see. **No widget ever holds the ticket, and
  /// the state has no field for it.**
  Future<void> _reviewContext({
    required String sessionId,
    required int utcOffsetMinutes,
    bool? setIncludeWindow,
  }) async {
    final (:review, :ticket) = await _repository.reviewContext(
      sessionId: sessionId,
      utcOffsetMinutes: utcOffsetMinutes,
      setIncludeWindow: setIncludeWindow,
    );
    _ticket = ticket;
    state = state.copyWith(
      phase: AiSessionPhase.reviewing,
      review: review,
      // The POST-toggle revision: the server re-reads the row rather
      // than assuming, so the ticket is always approvable as returned.
      revision: ticket.revision,
      clearRedirect: true,
    );
  }

  /// The approval ticket from the most recent `review_context`.
  ///
  /// **GATE 2: carried, compared, never derived.** It holds an opaque
  /// digest the client cannot recompute (`selectSharedWindow`'s
  /// 2,400-scalar total budget re-clips the final snippet, and the
  /// target snippet is hashed as stored text while window snippets are
  /// hashed as the live selection produced them). It is private and
  /// absent from [AiSessionViewState] so no widget can read a digest,
  /// and [approve] passes it WHOLE rather than unpacking it, so an
  /// approval cannot be assembled from parts obtained in different
  /// calls.
  AiSessionApprovalTicket? _ticket;

  /// `approve`.
  ///
  /// ## `activated: false` IS A 200 SUCCESS, NOT AN ERROR
  ///
  /// On a shared session the first partner to approve legitimately
  /// cannot activate yet, and the server answers
  /// `{approved: true, activated: false, state: "preparing"}` rather
  /// than `APPROVAL_REQUIRED` — whose own comment is that reporting it
  /// here "would tell a partner who did everything right that they
  /// failed". So this reads [AiSessionApprovalResult.state] and moves
  /// to [AiSessionPhase.waitingForPartner]; it does NOT infer
  /// waiting-ness from `!activated`, which is the same shape of
  /// mistake as inferring an error from an HTTP status.
  ///
  /// A private session's creator activates on their own approval
  /// (§3.2), so the same code path reaches [AiSessionPhase.active] with
  /// no special case for visibility — the server decides, and the
  /// sheet reads what it decided.
  Future<void> approve() {
    final ticket = _ticket;
    if (ticket == null) return Future<void>.value();
    return _run(() async {
      // The WHOLE ticket. Gate 2 again: no digest, revision or policy
      // version is spelled at this call site, so none can be
      // substituted from elsewhere.
      final result = await _repository.approve(ticket: ticket);
      state = state.copyWith(
        phase: switch (result.state) {
          AiSessionState.active => AiSessionPhase.active,
          AiSessionState.preparing => AiSessionPhase.waitingForPartner,
        },
      );
      if (result.state == AiSessionState.active) {
        await _read();
      }
    });
  }

  /// `read`: the committed transcript, plus this actor's own staged
  /// Nearby result when [requestId] is supplied.
  ///
  /// RULING 9: `transcript.staged` is assigned THROUGH, null and all.
  /// There is no `?? []` here and none downstream.
  Future<void> refresh({String? requestId}) {
    if (state.sessionId == null) return Future<void>.value();
    return _run(() => _read(requestId: requestId));
  }

  Future<void> _read({String? requestId}) async {
    final transcript = await _repository.read(
      sessionId: state.sessionId!,
      requestId: requestId,
    );
    state = state.copyWith(
      turns: transcript.turns,
      // RULING 9, and this is the line the ruling is about. The server
      // sends `staged` absent when no request_id was supplied and as a
      // possibly-empty array when one was. Assigning it through
      // preserves "I did not ask" (null) separately from "I asked and
      // there is nothing" (empty). `transcript.staged ?? []` here would
      // destroy that in one character, and `clearStagedResults` is what
      // lets a null actually be WRITTEN rather than merely not
      // overwritten.
      stagedResults: transcript.staged,
      clearStagedResults: transcript.staged == null,
    );
    // An EMPTY transcript is NOT evidence the session is gone (§7.2:
    // `read` returns 200-with-empty-array for a stranger, a
    // non-approver AND a healthy session with no committed turn, all
    // byte-identical). So nothing here moves the phase, sets an error
    // or shows a "session ended" state on emptiness.
  }

  /// `generate`: one generation attempt.
  ///
  /// [expectedRevision] is the revision this actor last saw, taken from
  /// the state rather than from an argument, so a caller cannot send a
  /// number it invented. A mismatch is `CONTEXT_CHANGED`, whose remedy
  /// is always [refreshContext] + [approve] — never a local bump and
  /// retry, because a client cannot recompute the digest (gate 2) and
  /// so has no local path back to a valid approval.
  Future<void> generate({
    required String requestId,
    required String userInstruction,
    RequesterLocation? requesterLocation,
    DateTime? locationCapturedAt,
  }) {
    final sessionId = state.sessionId;
    final revision = state.revision;
    if (sessionId == null || revision == null) return Future<void>.value();
    return _run(() async {
      final result = await _repository.generate(
        sessionId: sessionId,
        requestId: requestId,
        expectedRevision: revision,
        userInstruction: userInstruction,
        requesterLocation: requesterLocation,
        locationCapturedAt: locationCapturedAt,
      );
      switch (result) {
        case AiSessionGeneratedAnswer(sessionRevision: final bumped):
          // The pair is committed, so the transcript is re-read rather
          // than appended to locally: the server numbered the ordinals
          // and they may be non-contiguous, so synthesizing them here
          // would be guessing at the one thing `share_answer` needs
          // exactly right.
          //
          // `bumped` is NULLABLE — the replay path sends no
          // `session_revision` — and null means "this response carried
          // none", never zero. copyWith's `null`-is-unchanged is
          // exactly right here (gate 1: there is nothing to fall back
          // to, so the last known revision stands).
          state = state.copyWith(revision: bumped, clearRedirect: true);
          await _read();
        case AiSessionGeneratedRedirect():
          // ONE slot, BOTH shapes. See AiSessionViewState.redirect.
          state = state.copyWith(redirect: result, clearPendingStage: true);
        case AiSessionStagedNearbyGeneration():
          // Requester-only. NOTHING is committed and the partner can
          // see nothing until publishNearby, so the transcript is NOT
          // re-read here — doing so would show the requester their own
          // staged content as though it were in the transcript.
          state = state.copyWith(pendingStage: result, clearRedirect: true);
      }
    });
  }

  /// `publish_nearby`: turns this actor's staged result into a shared
  /// transcript pair — or answers with a redirect (RULING 15).
  ///
  /// The redirect lands in the SAME [AiSessionViewState.redirect] slot a
  /// `generate` redirect does, so the sheet renders it with the same
  /// widget. Nothing records that it came from a publish.
  Future<void> publishStaged(String requestId) {
    return _run(() async {
      final result = await _repository.publishNearby(requestId);
      switch (result) {
        case AiSessionPublishNearbyResult(sessionRevision: final bumped):
          state = state.copyWith(
            revision: bumped,
            clearPendingStage: true,
            clearRedirect: true,
          );
          await _read();
        case AiSessionPublishRedirect(redirect: final redirect):
          // NOTHING WAS COMMITTED: the staged row is untouched (the
          // requester may still discard it) and the revision did not
          // move, so `pendingStage` is deliberately KEPT and no read
          // is issued. Keeping it is also what makes the two commands'
          // redirect handling differ only in what the SERVER did, not
          // in what is shown.
          state = state.copyWith(redirect: redirect);
      }
    });
  }

  /// `discard_nearby`.
  ///
  /// **Terminal and COUNTED.** The generation consumed quota — the row
  /// only reached `staged` via `claim_ai_session_dispatch`, so the
  /// provider call really happened — so this is never presented as a
  /// free undo.
  Future<void> discardStaged(String requestId) {
    return _run(() async {
      await _repository.discardNearby(requestId);
      state = state.copyWith(clearPendingStage: true);
    });
  }

  /// `share_answer`: posts a committed `ideas_answer` turn into chat.
  ///
  /// [ordinal] is the server's own number, passed through UNCHANGED.
  /// Ordinals are `2n-1`/`2n` and may be non-contiguous, so a caller
  /// that renumbered a rendered list to 1..n would share the wrong
  /// turn. Returns the new `public.messages` id, or null when the
  /// command failed (the error is in the state).
  Future<String?> shareAnswer(int ordinal) async {
    final sessionId = state.sessionId;
    if (sessionId == null) return null;
    String? messageId;
    await _run(() async {
      messageId = await _repository.shareAnswer(
        sessionId: sessionId,
        ordinal: ordinal,
      );
    });
    return messageId;
  }

  /// `end`: ends the session and purges its transcript synchronously.
  ///
  /// The server answers `{ended: true}` idempotently for an unknown
  /// session, an already-ended one and one it just closed alike, so the
  /// phase moves to [AiSessionPhase.ended] on success without that
  /// being read as "there was something to end".
  Future<void> end() {
    final sessionId = state.sessionId;
    if (sessionId == null) return Future<void>.value();
    return _run(() async {
      await _repository.end(sessionId);
      state = state.copyWith(phase: AiSessionPhase.ended);
    });
  }

  /// Dismisses the redirect notice without touching anything else.
  void dismissRedirect() {
    state = state.copyWith(clearRedirect: true);
  }

  // =====================================================================
  // THE POLL (spec §6.1 as amended, §6.2, §7.2)
  //
  // ## WHAT THIS REPLACES, AND WHY THERE IS NO SUBSCRIPTION
  //
  // Task 8's brief specified a Realtime Broadcast subscription on an
  // `ai_session_hint:<user id>` private channel. **That channel does not
  // exist and will never be built.** Plan C's Task 6 never created it;
  // the §6.1 decision was ruled the other way and the spec amended:
  // POLLING `session_revision` IS THE SANCTIONED INVALIDATION
  // MECHANISM, Realtime Broadcast is explicitly out of scope, and direct
  // Postgres Changes publication of the transcript, staging and source
  // tables remains forbidden. Re-verified rather than taken on trust:
  // the `realtime` schema holds ZERO policies of this database's 158, so
  // there is no private-channel authorization to subscribe through at
  // all, and `RealtimeChannelConfig(private: true)` would be asking the
  // server to authorize against a policy set that is empty.
  //
  // ## WHY A POLL IS NEEDED: THE PARTNER HAS NO RESPONSE TO READ
  //
  // Every revision disclosure before this task went to the actor who
  // CAUSED the bump. The partner never makes that call, so the partner
  // never learns. Two concrete waits depend on this poll:
  //
  //   * `waitingForPartner` -> `active`. This actor approved first and
  //     got `{approved: true, activated: false, state: "preparing"}` —
  //     a 200 success. When the OTHER partner approves, the server
  //     activates the session and tells THEM. Nothing tells this actor.
  //   * a partner's committed turn, and a partner's `end`. Both bump the
  //     revision (`end_ai_session`'s own comment: "advance `revision` so
  //     a revision-polling client can observe the purge").
  //
  // ## RULING 6 IS WHY THE POLL READS A REVISION AND NOT A STATUS
  //
  // The polled values are chosen by what must NOT move. A safety refusal
  // does not bump the revision (Task 4) and leaves the session `active`,
  // so neither polled field moves on a refusal — which is what makes
  // polling safe rather than a disclosure. `attempt_count` and
  // `last_admitted_at` DO move on a refusal (a refusal is admitted
  // before it is refused) and are therefore not on the wire at all; see
  // `AiSessionStateSnapshot` and migration 20260953200600.
  //
  // So this poll CANNOT tell the user "your partner's request was
  // refused", and must not be extended to. That is Ruling 6 working, not
  // a missing feature.

  /// How often the poll asks. Five seconds, which is §6.1's own stated
  /// rate for the superseded hint mechanism — kept because the rate was
  /// never the part that changed, only the transport.
  static const Duration pollInterval = Duration(seconds: 5);

  Timer? _pollTimer;

  /// True while a poll tick is in flight, so ticks cannot overlap.
  bool _polling = false;

  /// Visible for tests: whether the poll is currently armed.
  bool get isPolling => _pollTimer != null;

  /// Starts the poll, if it is not already running and there is a
  /// session to poll.
  ///
  /// ## LIFECYCLE: ONE SHEET, ONE POLL, STOPPED BY FOUR THINGS
  ///
  /// RULING 24 (ruled while Task 7 reported) is that Task 9 must not
  /// allow two sheets open at once, and the controller is keyed by THE
  /// SHEET rather than by session id. This poll is built on that and
  /// does not assume otherwise: it lives on the single sheet-scoped
  /// controller, there is exactly ONE [_pollTimer] field, and nothing
  /// here is keyed by session id or could run for two sessions at once.
  /// A second concurrent session per user is not a state this code can
  /// represent, which is the correct shape given Ruling 24.
  ///
  /// It STOPS on all four of:
  ///   1. [stopPolling], called by the sheet when it closes;
  ///   2. the `.autoDispose` teardown — registered as `ref.onDispose`
  ///      in [build], NOT as a `dispose()` override, which `Notifier`
  ///      does not offer; so a sheet that is garbage-collected cannot
  ///      leave a timer calling a disposed notifier (the leak this kind
  ///      of code usually ships with);
  ///   3. reaching a terminal phase — [AiSessionPhase.ended], set when
  ///      the poll observes `closed` or when this actor calls `end`;
  ///   4. an authorization change that makes the poll pointless:
  ///      consent withdrawn or membership lost both make the RPC silent,
  ///      and silence alone does NOT stop the poll (see below) — but an
  ///      explicit `closed` does.
  ///
  /// **Silence does not stop it, deliberately.** The RPC answers zero
  /// rows for an unknown session, a non-member, withdrawn consent, an
  /// expired session and a never-approved shared session —
  /// byte-identically (§7.2). An empty answer is therefore NOT evidence
  /// the session is gone, exactly as an empty `read` is not, so a null
  /// snapshot leaves the phase alone and the poll running. Only an
  /// EXPLICIT `closed` ends it.
  void startPolling() {
    if (_pollTimer != null) return;
    if (state.sessionId == null) return;
    _pollTimer = Timer.periodic(pollInterval, (_) => _pollTick());
  }

  /// Stops the poll. Idempotent, so a sheet may call it on every close
  /// path without checking.
  void stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  /// One tick.
  ///
  /// NOT routed through [_run]. That helper sets `busy`, which drives
  /// the sheet's in-flight affordances — a background poll must not make
  /// the UI look like the user's own command is running, and must not
  /// clear the error slot a real command just wrote. A tick also must
  /// not surface its own transport failure as a user-visible error: a
  /// dropped poll is invisible by design and the next tick retries.
  Future<void> _pollTick() async {
    final sessionId = state.sessionId;
    if (sessionId == null) return;
    // Not while nobody can see it (a network and AI-session cost).
    if (!ref.read(appContentVisibleProvider)) return;
    // Non-overlapping: a slow round trip must not let ticks pile up and
    // apply out of order.
    if (_polling) return;
    _polling = true;
    try {
      final snapshot = await _repository.readState(sessionId);
      if (snapshot == null) {
        // §7.2 SILENCE. Not evidence of anything. The phase is NOT
        // moved, no error is set and the poll keeps running.
        return;
      }
      await _applyPolledState(snapshot);
    } catch (_) {
      // A failed tick is swallowed on purpose — see the method header.
    } finally {
      _polling = false;
    }
  }

  /// Applies one polled snapshot.
  ///
  /// ## RULING 9 LIVES HERE, AND THIS IS THE DANGEROUS PLACE FOR IT
  ///
  /// `staged`'s null-vs-empty distinction is where a refreshing poll
  /// would lose it: `null` means "I did not ask", `[]` means "asked, no
  /// cards", and Task 7 found that without an explicit clear flag the
  /// field can only ever move one way. So the refresh this method issues
  /// goes through [_read] with **no `requestId`**, and [_read] assigns
  /// `transcript.staged` THROUGH together with
  /// `clearStagedResults: transcript.staged == null` — which is what
  /// actually WRITES the null back rather than merely failing to
  /// overwrite it.
  ///
  /// That is the correct behaviour and not an accident of reuse: a poll
  /// did not ask about any request, so after a poll-driven refresh
  /// `stagedResults` MUST read as "I did not ask". A poll that preserved
  /// a stale non-null `stagedResults` would leave the sheet offering
  /// Publish/Discard for a staging row no read has confirmed, which is
  /// the exact failure Ruling 9 exists to prevent.
  ///
  /// `pendingStage` is a different field and is deliberately NOT touched:
  /// it is this actor's own un-published generation, known only from its
  /// own `generate` response, and a poll has no authority over it.
  Future<void> _applyPolledState(AiSessionStateSnapshot snapshot) async {
    // CLOSED IS THE ONE TERMINAL ANSWER, and it is explicit. This is the
    // only way this poll concludes a session ended — never from silence.
    if (snapshot.state == AiSessionPolledState.closed) {
      stopPolling();
      state = state.copyWith(phase: AiSessionPhase.ended);
      return;
    }

    // The partner approved and the server activated: the wait is over.
    // Read from the SERVER'S state rather than inferred from anything
    // local, the same discipline `approve` follows.
    if (snapshot.state == AiSessionPolledState.active &&
        state.phase == AiSessionPhase.waitingForPartner) {
      state = state.copyWith(
        phase: AiSessionPhase.active,
        revision: snapshot.revision,
      );
      await _read();
      return;
    }

    final known = state.revision;
    // COMPARED, NEVER DERIVED. The revision is only ever assigned from a
    // server response, and the comparison is a plain inequality — the
    // client never increments, predicts or recomputes it. `!=` rather
    // than `>`: a revision that moved at all means this actor's view is
    // stale, and a client that only believed INCREASES would silently
    // ignore a server it disagreed with.
    if (known != null && snapshot.revision != known) {
      state = state.copyWith(revision: snapshot.revision);
      // Re-read the transcript. The CONTENT comes from the authorized
      // `read` path, never from the poll: this surface carries no turn
      // text, and §6.1's amendment keeps content off the invalidation
      // channel entirely.
      await _read();
    }
  }

}

final aiSessionControllerProvider =
    NotifierProvider.autoDispose<AiSessionController, AiSessionViewState>(
      AiSessionController.new,
    );

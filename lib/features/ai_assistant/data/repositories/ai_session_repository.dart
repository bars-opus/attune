// lib/features/ai_assistant/data/repositories/ai_session_repository.dart
import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/ai_session_model.dart';
import '../models/ai_session_turn_model.dart';
import 'ai_assistant_repository.dart';
import 'ai_session_error.dart';

/// Result of the `prepare` command (spec §4.1).
///
/// Exactly the three fields `handlePrepare` returns and no more: §4.1
/// says "Preparation returns server session ID/revision", and the branch
/// comments that it deliberately withholds context text and source
/// content because `review_context` is what discloses the window, after
/// its own authorization. A field added here that the server does not
/// send would be a client inventing context it was not granted.
class AiSessionPrepareResult {
  /// The server session id. Equal to the `idempotency_key` the client
  /// sent (Plan C Ruling 5: "the key BECOMES the session id"), so a
  /// client may key local state by the id it generated — but it must
  /// still read this field rather than assuming, since a replay returns
  /// the ORIGINAL session.
  final String sessionId;

  /// The session's revision. Must be echoed back to `approve` as-is;
  /// it is the server's own optimistic-concurrency token.
  final int revision;

  /// `false` on an idempotent replay — the key was already used by this
  /// same actor with this same payload, and the ORIGINAL session is
  /// being returned. A client must not treat a replay as a new session:
  /// doing so would double-count the caller's own session slot and
  /// invite a spurious [AiSessionLimitReachedError] later.
  final bool created;

  const AiSessionPrepareResult({
    required this.sessionId,
    required this.revision,
    required this.created,
  });
}

/// Domain/repository layer over the `ai-sessions` edge function's nine
/// commands (`prepare`, `review_context`, `approve`, `generate`, `read`,
/// `publish_nearby`, `discard_nearby`, `end`, `share_answer`).
///
/// Every method here throws [AiSessionError] on failure — never a raw
/// `FunctionException`/parse exception — so every call site downstream
/// can pattern-match on the sealed error type alone. This is the exact
/// promise `AiAssistantRepository` already makes for `AssistantError`,
/// and `PlanningRepository` for `PlanningError`; this class follows
/// `AiAssistantRepository`'s shape deliberately, including its
/// `_invoke`/`_mapTransportError` split.
///
/// Deliberately does NOT extend or wrap [AiAssistantRepository] — the
/// two are siblings over the same [AiAssistantGateway] seam, not a
/// hierarchy. They share a transport but not a contract: different
/// command shapes, a different error union, and a different envelope
/// (§10 drops ai-assist's `error`/`retryable` fields in favour of the
/// code alone).
///
/// ## This class is the ONLY thing in the app that talks to ai-sessions
///
/// No widget or provider may call `functions.invoke('ai-sessions', ...)`
/// directly, and nothing may call a Sessions RPC: every one of Plan B's
/// RPCs is `service_role`-only, so `supabase.rpc('admit_ai_session_...')`
/// from Flutter cannot work and must never be attempted. The gateway's
/// `rpc` member exists only because `AiAssistantRepository` shares the
/// seam; this class never uses it.
///
/// ## The actor is never in the body
///
/// No method here sends an identity field of any kind. The server
/// derives the actor from the verified JWT (`processSessionCommand`:
/// "`userScoped` is the ONLY source of actor identity"), and
/// `validateCommandEnvelope` rejects eleven actor-naming body spellings
/// outright with `INVALID_INPUT`. A twelfth, unlisted spelling was once
/// a real finding in this effort, so the rule this class follows is
/// stronger than the server's blocklist: the client sends no identity at
/// all, not merely none of the eleven names.
///
/// ## The context digest is OPAQUE — carry it, compare it, never derive it
///
/// `review_context` returns a digest that `approve` must echo back
/// verbatim. A client CANNOT recompute it from stored rows, and must not
/// try: `selectSharedWindow`'s 2400-scalar total budget re-clips the
/// final snippet, and `review_context` hashes the TARGET snippet as
/// stored text while hashing WINDOW snippets as the live selection
/// produced them. Any local recomputation would therefore disagree with
/// the server for reasons a client cannot see, and §4.3's two-partner
/// digest equality would break. The remedy for an
/// [AiSessionContextChangedError] is always "call `review_context` again
/// and approve the digest it returns", never "rebuild the digest and
/// retry". Accordingly, no model or method in this repository exposes
/// the digest's INPUTS alongside the digest — only the digest string
/// itself, to be carried.
///
/// ## `read`'s silence is not an answer about the session
///
/// `read` returns HTTP 200 with an empty turns array instead of
/// `FEATURE_DISABLED`, deliberately, because §7.2 requires silence. So
/// an empty `read` is NOT evidence that the session is gone, ended, or
/// that the feature was turned off — it is indistinguishable from "no
/// turns committed yet". [read] therefore never converts emptiness into
/// an error and returns an [AiSessionTranscript] with no member a caller
/// could read a verdict from; no caller may treat emptiness as a
/// terminal state.
class AiSessionRepository {
  static const String functionName = 'ai-sessions';

  final AiAssistantGateway _gateway;
  const AiSessionRepository(this._gateway);

  /// `prepare` (spec §4.1): creates — or idempotently returns — a
  /// session, and reports its id and revision.
  ///
  /// [utcOffsetMinutes] is REQUIRED, not optional. `parsePrepareRequest`
  /// runs `isValidUtcOffsetMinutes(body.utc_offset_minutes)`, which
  /// rejects a non-number; an absent field is `undefined`, so omitting
  /// it is `INVALID_INPUT` on every call. It must be the offset the UI
  /// actually DISPLAYED (§4.2: the civil day comes from "the DISPLAYED,
  /// validated offset"), in the range [-840, 840]; the server refuses
  /// anything else rather than clamping, because a clamped offset would
  /// compute a different civil day than the user saw.
  ///
  /// [idempotencyKey] must be a canonical v4-shaped UUID: it BECOMES the
  /// session id (Plan C Ruling 5), so an invalid key is an invalid
  /// session id. Reusing a key with a DIFFERENT payload yields
  /// [AiSessionRequestConflictError]; reusing it with the same payload
  /// returns the original session with `created: false`.
  ///
  /// This method does NOT pre-validate the server's two shape rules
  /// ("private and Nearby sessions do not have recent windows"; "Nearby
  /// does not accept a target attachment"). The server is the single
  /// source of truth for them and answers `INVALID_INPUT`; duplicating
  /// the rules here would create a second place for them to drift, which
  /// is the same reasoning `AiAssistantRepository.requestAssist` gives
  /// for not pre-empting `LOCATION_REQUIRED`.
  Future<AiSessionPrepareResult> prepare({
    required String idempotencyKey,
    required String relationshipId,
    required String kind,
    required String visibility,
    required int utcOffsetMinutes,
    String? targetMessageId,
    bool includeWindow = false,
  }) {
    return _invoke(
      command: 'prepare',
      // Exactly `parsePrepareRequest`'s allowlist, and nothing else: it
      // rejects any unknown key with INVALID_INPUT rather than ignoring
      // it, "the same reasoning Task 1 applied to ACTOR_NAMING_FIELDS".
      // `target_message_id: null` is allowlisted AND meaningful (no
      // target), so it is sent explicitly rather than omitted.
      body: {
        'relationship_id': relationshipId,
        'kind': kind,
        'visibility': visibility,
        'target_message_id': targetMessageId,
        'include_window': includeWindow,
        'utc_offset_minutes': utcOffsetMinutes,
        'idempotency_key': idempotencyKey,
      },
      onResult: (data) => AiSessionPrepareResult(
        sessionId: data['session_id'] as String,
        revision: data['revision'] as int,
        created: data['created'] as bool,
      ),
    );
  }

  /// `review_context` (spec §4.1, §4.3): reads the context the session
  /// will be generated against, and — optionally, via
  /// [setIncludeWindow] — toggles the recent window while doing so.
  ///
  /// ## Returns gate 2's TWO HALVES, deliberately unrecombined
  ///
  /// The server sends one flat object; this method splits it into
  /// [AiSessionContextReview] (what a UI renders: snippets, the stored
  /// toggle, the offset) and [AiSessionApprovalTicket] (what `approve`
  /// echoes: revision, digest, policy version). Their wire key sets
  /// intersect in exactly `{session_id}`, which a test asserts.
  ///
  /// The split is not tidiness. A client **cannot** recompute the
  /// digest from the snippets it was shown — `selectSharedWindow`'s
  /// 2,400-scalar total budget re-clips the final snippet, and
  /// `review_context` hashes the target snippet as stored text while
  /// hashing window snippets as the live selection produced them — so
  /// handing a caller the digest *beside* its apparent inputs invites
  /// exactly the recomputation that would disagree with the server for
  /// reasons the client cannot see. Keeping them in separate values
  /// means a widget that renders the review half has no digest in
  /// scope, and the approval path has no snippet in scope.
  ///
  /// **Returning a record of two rather than one combined type is the
  /// point**; this method must not grow a convenience accessor that
  /// puts a digest and a snippet in the same object.
  ///
  /// `civil_day_start_utc` is sent by the server and read by neither
  /// half — see [AiSessionContextReview.wireKeysDeliberatelyDropped].
  ///
  /// [utcOffsetMinutes] is REQUIRED on every call, including a pure
  /// re-read: `isValidUtcOffsetMinutes` refuses an absent or
  /// out-of-range value with `INVALID_INPUT` rather than clamping. It
  /// must be the offset the UI DISPLAYED. The offset is no longer part
  /// of the digest pre-image (Ruling 35 / N3: binding it meant two
  /// partners in different timezones could never activate a shared
  /// session, and `DIGEST_FORMAT_VERSION` is now v2), but it still
  /// decides WHICH messages the window selects, so it is still required
  /// on the wire.
  ///
  /// [setIncludeWindow] is tri-state and the third state matters:
  /// `null` means "do not toggle" and keeps this command read-only,
  /// while `false` means "turn the window OFF" — a real write that
  /// bumps the revision and clears BOTH partners' approvals. So `null`
  /// omits the key entirely rather than sending `false`; defaulting to
  /// `false` would silently invalidate a partner's approval on every
  /// plain re-read.
  ///
  /// After a toggle the revision in the returned ticket is the
  /// POST-toggle one — the server re-reads the row rather than assuming
  /// — so the ticket is always approvable as returned.
  Future<({AiSessionContextReview review, AiSessionApprovalTicket ticket})>
  reviewContext({
    required String sessionId,
    required int utcOffsetMinutes,
    bool? setIncludeWindow,
  }) {
    return _invoke(
      command: 'review_context',
      // Exactly `handleReviewContext`'s allowlist and nothing else.
      // NOTE: NO `relationship_id`. The server looks the session up
      // first and takes the relationship, kind, visibility and window
      // setting from THAT ROW — "never from the request body" — because
      // a digest computed from a client-supplied relationship would let
      // a caller aim the window query at a relationship the session
      // does not belong to. The key is not allowlisted, so sending it
      // is `INVALID_INPUT` on every call.
      body: {
        'session_id': sessionId,
        'utc_offset_minutes': utcOffsetMinutes,
        if (setIncludeWindow != null) 'set_include_window': setIncludeWindow,
      },
      // Parsed TWICE, from the same map, into two types that cannot see
      // each other's fields. Neither factory is given the other's keys.
      onResult: (data) => (
        review: AiSessionContextReview.fromJson(data),
        ticket: AiSessionApprovalTicket.fromJson(data),
      ),
    );
  }

  /// `approve` (spec §4.1, §4.3): records this caller's approval of the
  /// reviewed context and attempts activation in the same command.
  ///
  /// **Takes the whole [AiSessionApprovalTicket], not loose
  /// digest/revision/policy arguments.** Gate 2 again: the ticket is
  /// the only thing `reviewContext` hands out that belongs here, and
  /// accepting it whole means a caller cannot assemble an approval from
  /// a digest it obtained anywhere else — in particular not from a
  /// digest it computed, and not from a revision it read from a
  /// different call than the digest. The three values must come from
  /// ONE `review_context` response or the server's equality check is
  /// meaningless, and a record of three parameters would let them drift
  /// apart silently.
  ///
  /// ## There is no `start` command and none is needed
  ///
  /// `processSessionCommand` has exactly nine cases and none is
  /// `start`: activation rides inside `handleApprove`, which calls
  /// `activate_ai_session` itself.
  ///
  /// ## A first approver's `activated: false` is a SUCCESS
  ///
  /// On a shared session the first partner to approve legitimately
  /// cannot activate yet, and the server returns HTTP 200 with
  /// `{approved: true, activated: false, state: "preparing"}` — NOT
  /// `APPROVAL_REQUIRED`, whose own comment is that reporting it here
  /// "would tell a partner who did everything right that they failed".
  /// So this method returns normally in that case and the caller reads
  /// [AiSessionApprovalResult.state]; §10's `APPROVAL_REQUIRED` belongs
  /// to a caller that tried to GENERATE without approval.
  ///
  /// [AiSessionApprovalResult] makes `state` required, so waiting-ness
  /// is read rather than inferred from `!activated`.
  ///
  /// Throws [AiSessionContextChangedError] when the revision moved, the
  /// two partners' digests differ, the consent policy was superseded,
  /// or the frozen snapshot no longer validates. Its remedy is always
  /// "call [reviewContext] again and approve the digest it returns" —
  /// never "rebuild the digest and retry".
  Future<AiSessionApprovalResult> approve({
    required AiSessionApprovalTicket ticket,
  }) {
    return _invoke(
      command: 'approve',
      // `toApproveBody()` is the ticket's own transcription of
      // `handleApprove`'s allowlist: session_id, revision, digest and
      // policy_version. The policy version is sent so the server can
      // detect that consent moved between review and approval — a
      // CONTEXT_CHANGED rather than something to overwrite.
      body: ticket.toApproveBody(),
      onResult: AiSessionApprovalResult.fromJson,
    );
  }

  /// `read` (spec §4.1, §7.2): the committed transcript, plus — only
  /// when [requestId] is supplied — this caller's own staged Nearby
  /// result.
  ///
  /// ## AN EMPTY TRANSCRIPT IS NOT EVIDENCE THE SESSION IS GONE
  ///
  /// `handleRead` returns HTTP 200 with `turns: []` for every
  /// unauthorized outcome — unknown session, non-member, withdrawn
  /// consent, a shared session this actor never approved — *and* for a
  /// perfectly healthy session that has not committed a turn yet.
  /// `read_ai_session_turns` and `read_ai_session_staging` contain no
  /// `RAISE EXCEPTION` at all (a live contract test asserts that), so
  /// "a partner's zero rows and a stranger's zero rows must be
  /// byte-identical". The branch deliberately does not even run the
  /// eligibility gate first, because that gate raises distinguishable
  /// codes and would reintroduce at the edge the oracle the SQL removes.
  ///
  /// So this method **never** converts emptiness into an error, and
  /// [AiSessionTranscript] offers no `isGone`/`exists`/`isTerminal` to
  /// read a verdict from. A UI that wants to say anything about a
  /// session's existence must learn it from a command entitled to say
  /// so — [reviewContext], [approve] or `generate`, which return
  /// `UNAVAILABLE` explicitly.
  ///
  /// A missing `turns` KEY is different and throws: the server always
  /// sends it, so its absence is a malformed response, and reading that
  /// as an empty transcript would manufacture a benign empty state out
  /// of a broken one.
  ///
  /// ## `staged`: null and empty mean different things
  ///
  /// The server sends `staged` ABSENT when no [requestId] was supplied
  /// and as a possibly-empty ARRAY when one was, "so a client can tell
  /// 'I did not ask' from 'I asked and there is nothing'". That is a
  /// distinction about the caller's own request, not about anyone's
  /// authorization, and [AiSessionTranscript.staged] is nullable
  /// precisely to carry it. **No `?? []` may appear at this call site
  /// or downstream** — the first one destroys the distinction.
  Future<AiSessionTranscript> read({
    required String sessionId,
    String? requestId,
  }) {
    return _invoke(
      command: 'read',
      // Exactly `handleRead`'s allowlist. `request_id` is OPTIONAL and
      // is OMITTED rather than sent as null: the server branches on
      // `typeof requestId === "string"`, so a null would read the turns
      // and return `staged` absent — the same observable result today,
      // but it would put the key on the wire, and a present-but-null
      // key is a shape the server's own validator tolerates only
      // because `undefined` and `null` both fail its uuid check. Not
      // sending it keeps "I did not ask" literal.
      body: {
        'session_id': sessionId,
        if (requestId != null) 'request_id': requestId,
      },
      onResult: AiSessionTranscript.fromJson,
    );
  }

  /// `end` (spec §5.4): ends the session and purges its transcript,
  /// sources, approvals and staging rows synchronously.
  ///
  /// Returns nothing, deliberately. The server answers `{ended: true}`
  /// idempotently — for an unknown session, an already-ended one, and
  /// one it just closed alike — and that boolean "means 'this session
  /// is not running now'", not "there was something to end". Returning
  /// it would invite a caller to read it as existence, which §3.1
  /// forbids: "a session the caller may not end is indistinguishable
  /// from one that does not exist", and both authorization raises map
  /// to [AiSessionUnavailableError] for that reason.
  ///
  /// §5.4 also forbids disclosing WHO ended a session, and nothing here
  /// could: the response has no actor field and the table has no
  /// column.
  Future<void> end(String sessionId) {
    return _invoke(
      command: 'end',
      // Exactly `handleEnd`'s allowlist.
      body: {'session_id': sessionId},
      // The body is read but nothing is returned from it — see above.
      onResult: (_) {},
    );
  }

  /// `share_answer` (spec §5.3, §8.1): posts a committed `ideas_answer`
  /// turn into ordinary chat with `attune_assist` provenance, and
  /// returns the new `public.messages` id.
  ///
  /// [ordinal] is the transcript ordinal **as the server numbered it**,
  /// passed through unchanged. Ordinals are `2n-1`/`2n` and may be
  /// non-contiguous (3,4 measured after one failed attempt), so a
  /// client that renumbered a rendered list to 1..n would share the
  /// wrong turn. The server bounds it to 1..20 itself and answers
  /// `INVALID_INPUT` out of range, so this method does not duplicate
  /// the bound.
  ///
  /// Only a committed `ideas_answer` is shareable: `share_ai_session_turn`
  /// allowlists that kind alone, so a redirect cannot be posted at all
  /// (§8.1) and a Nearby result has its own requester-only publish path.
  ///
  /// Throws [AiSessionConsentRequiredError] — the one refusal §10
  /// distinguishes by name, "precisely because 'caller can open
  /// consent' is a refusal the caller can ACT on" — or
  /// [AiSessionResultUnavailableError] for everything else. The latter
  /// deliberately collapses a closed session, a missing ordinal, a
  /// user-authored turn, an unshareable kind and a non-member into one
  /// response, so a caller cannot tell which check refused.
  Future<String> shareAnswer({
    required String sessionId,
    required int ordinal,
  }) {
    return _invoke(
      command: 'share_answer',
      // Exactly `handleShareAnswer`'s allowlist.
      body: {'session_id': sessionId, 'ordinal': ordinal},
      onResult: (data) {
        final messageId = data['message_id'];
        if (messageId is! String || messageId.isEmpty) {
          // The server returns INTERNAL_ERROR rather than an empty id
          // when the RPC yields no row, so an unreadable id here is a
          // malformed response, not a shareable outcome.
          throw const FormatException(
            'share_answer: missing/invalid message_id',
          );
        }
        return messageId;
      },
    );
  }

  // Task 4 adds generate.
  // Task 6 adds publishNearby/discardNearby.

  // ---------------------------------------------------------------------
  // Shared call helper
  // ---------------------------------------------------------------------

  /// One `invokeFunction('ai-sessions', ...)` call per command, with the
  /// `command` discriminator injected here so no method can forget it
  /// and no method can send a command this class does not name.
  ///
  /// Mirrors `AiAssistantRepository._invoke`'s structure exactly,
  /// including its two separate try blocks: a transport failure maps
  /// through [_mapTransportError], while a parse failure on a nominally
  /// successful response maps to [AiSessionInternalError] rather than
  /// letting a `TypeError`/`FormatException` reach the UI.
  Future<T> _invoke<T>({
    required String command,
    required Map<String, dynamic> body,
    required T Function(Map<String, dynamic> data) onResult,
  }) async {
    dynamic data;
    try {
      data = await _gateway.invokeFunction(
        functionName,
        body: <String, dynamic>{'command': command, ...body},
      );
    } catch (error) {
      throw _mapTransportError(error);
    }
    try {
      return onResult(Map<String, dynamic>.from(data as Map));
    } catch (error) {
      // A malformed success-status response should never happen
      // server-side, but the client must not crash on it.
      throw const AiSessionError.internalError();
    }
  }

  /// Maps whatever the gateway throws into an [AiSessionError].
  ///
  /// Reads the §10 envelope's `code` and NOTHING ELSE from the failure —
  /// in particular, never `FunctionException.status`. The 18 codes share
  /// only 9 statuses (five on 409 alone), and their §10 remedies differ,
  /// so a status-driven mapping could not tell the user what to do. The
  /// envelope has no `retryable` field to consult either: §10 replaced
  /// ai-assist's server-computed boolean with the code itself,
  /// deliberately, so that there is "no second derived field to disagree
  /// with it".
  ///
  /// - A [FunctionException] from `functions.invoke` on a non-2xx
  ///   response carries the §10 envelope in `details`, as a decoded Map
  ///   on a JSON content type or as a raw String otherwise. Both shapes
  ///   are handled, matching `AiAssistantRepository._mapTransportError`.
  /// - A `FunctionException` with no readable `code` (an infrastructure
  ///   error page, a gateway timeout body) maps to
  ///   [AiSessionInternalError] rather than guessing a code from the
  ///   status.
  /// - An already-typed [AiSessionError] passes through unwrapped, so
  ///   the parse-failure path above cannot double-wrap.
  /// - Anything else (network, timeout, a `PostgrestException` that
  ///   should be impossible here since this class never calls `rpc`)
  ///   maps to [AiSessionInternalError].
  AiSessionError _mapTransportError(Object error) {
    if (error is FunctionException) {
      final details = error.details;
      Map<String, dynamic>? envelope;
      if (details is Map) {
        envelope = Map<String, dynamic>.from(details);
      } else if (details is String) {
        try {
          final decoded = jsonDecode(details);
          if (decoded is Map) envelope = Map<String, dynamic>.from(decoded);
        } catch (_) {
          envelope = null;
        }
      }
      final code = envelope?['code'];
      if (code is String) {
        final retryAfter = envelope?['retry_after_seconds'];
        return AiSessionError.fromCode(
          code,
          // Only an int is honoured. A string or double is dropped
          // rather than parsed: §10 specifies an integer count of
          // seconds, and coercing an unexpected shape would invent a
          // retry delay the server never stated.
          retryAfterSeconds: retryAfter is int ? retryAfter : null,
        );
      }
      return const AiSessionError.internalError();
    }
    if (error is AiSessionError) return error;
    return const AiSessionError.internalError();
  }
}

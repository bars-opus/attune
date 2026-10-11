// lib/features/ai_assistant/data/repositories/ai_session_repository.dart
import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

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
/// turns committed yet". When `read` lands here (Task 5), it must not
/// let a caller conclude otherwise, and no caller may treat emptiness as
/// a terminal state.
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

  // Task 3 adds reviewContext/approve.
  // Task 4 adds generate.
  // Task 5 adds read.
  // Task 6 adds publishNearby/discardNearby.
  // Task 7 adds end/shareAnswer.

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

// lib/features/ai_assistant/data/models/ai_session_turn_model.dart

import 'assist_draft_model.dart' show SuggestedPlanningItem;
import 'place_source_model.dart';

/// The `kind` of a committed session turn, as `ai_session_turns.kind`
/// stores it.
///
/// THE TABLE'S CHECK ALLOWS THREE VALUES AND THIS ENUM HAS TWO, and
/// that is deliberate rather than an oversight.
/// `ai_session_turns.kind` is `CHECK (kind IN ('ideas_answer',
/// 'redirect', 'nearby_result'))`, but **no code path can write a
/// `'redirect'` row**:
///
///   * `commit_ai_session_ideas_turn` hardcodes `'ideas_answer'` for
///     both rows of the pair it inserts
///     (20260953070000_ai_session_commit_ideas_rpc.sql);
///   * `publish_ai_session_nearby_result` hardcodes `'nearby_result'`
///     for both rows of its pair
///     (20260953080000_ai_session_nearby_staging_rpcs.sql);
///   * `share_ai_session_turn` names `'redirect'` only to REJECT it.
///
/// Spec §5.3 was amended by Plan C Task 6 / Item B to say so outright
/// ("NO redirect becomes a transcript pair. ALL redirects are
/// requester-only"), because a durable redirect would be a safety side
/// channel: redirects and safety refusals share a reason set, so
/// bumping the session revision for `'unsupported'` but not for
/// `'unsafe_to_assist'` would disclose the detector to a partner
/// polling `session_revision`, which §8.1 forbids.
///
/// A redirect therefore reaches a client only as a `generate` RESPONSE
/// BODY — `{kind: 'redirect', reason, offered, show_safety_resources}`
/// — which is a transient, requester-only result, NOT a transcript
/// turn. Whichever task wraps `generate` models it there; it has no
/// subtype here, and [AiSessionTurnModel.fromJson] rejects the value
/// rather than inventing one. If a future migration ever makes a
/// `'redirect'` row reachable, the rejection and the
/// `AiSessionTurnKind.values` length assertion in this file's test fail
/// together, which forces that decision to be taken deliberately
/// instead of a parser silently coping with it.
enum AiSessionTurnKind {
  ideasAnswer('ideas_answer'),
  nearbyResult('nearby_result');

  const AiSessionTurnKind(this.wireValue);

  /// The exact string `ai_session_turns.kind` stores and `read`
  /// projects.
  final String wireValue;
}

/// One committed turn of a session transcript, as the `'read'` command
/// projects it.
///
/// `handleRead` (supabase/functions/ai-sessions/index.ts) does not echo
/// the RPC's rows; it PROJECTS exactly five keys per turn —
/// `ordinal`, `role`, `kind`, `payload`, `created_at` — deliberately
/// dropping `session_id`, `request_id` and `author_id` as "server
/// bookkeeping a client has no use for". So this model has no field for
/// any of those, and requires all five of the ones it does get.
///
/// Sealed on `role` first and then on `kind`, mirroring
/// [AssistDraftModel]'s sealed-on-discriminant pattern
/// (`assist_draft_model.dart`): the branches are mutually exclusive at
/// the type level rather than by runtime-null convention, so there is
/// no shared nullable field one branch could accidentally populate for
/// the other. [AiSessionIdeasAnswerTurn] has no `sources` field at all
/// and [AiSessionNearbyResultTurn] has no `suggestedPlanningItem` field
/// at all.
///
/// **`role` and `kind` are ORTHOGONAL, not nested.** Both committing
/// RPCs insert the user row and the Attune row at the SAME `kind`, so a
/// user turn's kind is `'nearby_result'` in a Nearby session —
/// `publish_ai_session_nearby_result` writes
/// `jsonb_build_object('instruction', 'nearby')` at
/// `kind = 'nearby_result'`. A parser that keyed the user branch off
/// `kind == 'ideas_answer'` would therefore fail to read every Nearby
/// transcript, and one that discarded `kind` for user turns could not
/// tell an Ideas exchange from a Nearby one. [AiSessionUserTurn]
/// consequently carries `kind` and does not constrain it.
///
/// Throws [FormatException] on any missing or mistyped field rather
/// than defaulting — this is the boundary where raw server JSON becomes
/// a trusted model, the same reasoning every other `.fromJson` factory
/// in this feature gives.
sealed class AiSessionTurnModel {
  /// `ai_session_turns.ordinal`: `CHECK (ordinal BETWEEN 1 AND 20)`,
  /// §5.2's twenty-ordinal cap.
  ///
  /// **ORDINALS ARE `2n-1` (user) / `2n` (Attune) FOR ATTEMPT `n`, AND
  /// MAY BE NON-CONTIGUOUS.** The attempt counter advances on a FAILED
  /// attempt too, so a session whose first attempt failed and whose
  /// second committed holds ordinals 3 and 4 with no 1 or 2 — measured
  /// in Plan B as exactly that. Nothing may index a list by ordinal,
  /// assert `turns[i].ordinal == i + 1`, derive an attempt count from
  /// `turns.length`, or treat a gap as a missing turn to fetch. A gap
  /// is a *failed attempt*, and the turns it would have written do not
  /// exist.
  final int ordinal;

  /// The committed kind. See [AiSessionTurnKind] for why `'redirect'`
  /// is absent.
  final AiSessionTurnKind kind;

  /// `ai_session_turns.created_at`. Projected by `handleRead`, so it is
  /// required rather than optional.
  final DateTime createdAt;

  const AiSessionTurnModel({
    required this.ordinal,
    required this.kind,
    required this.createdAt,
  });

  factory AiSessionTurnModel.fromJson(Map<String, dynamic> json) {
    final ordinal = json['ordinal'];
    if (ordinal is! int) {
      throw const FormatException(
        'AiSessionTurnModel.fromJson: missing/invalid ordinal',
      );
    }
    // The table's own CHECK. A value outside it is not something the
    // server can have written, so it is a malformed response rather
    // than a turn to render.
    if (ordinal < 1 || ordinal > 20) {
      throw FormatException(
        'AiSessionTurnModel.fromJson: ordinal $ordinal is outside 1..20',
      );
    }
    final rawCreatedAt = json['created_at'];
    if (rawCreatedAt is! String) {
      throw const FormatException(
        'AiSessionTurnModel.fromJson: missing/invalid created_at',
      );
    }
    final createdAt = DateTime.parse(rawCreatedAt);

    final rawKind = json['kind'];
    final kind = AiSessionTurnKind.values
        .where((candidate) => candidate.wireValue == rawKind)
        .firstOrNull;
    if (kind == null) {
      throw FormatException(
        'AiSessionTurnModel.fromJson: unrecognized or unreachable kind '
        '"$rawKind" (a redirect is a generate response body, never a turn)',
      );
    }

    final payload = json['payload'];
    if (payload is! Map) {
      throw const FormatException(
        'AiSessionTurnModel.fromJson: missing/invalid payload',
      );
    }
    final payloadMap = Map<String, dynamic>.from(payload);

    final role = json['role'];
    // `role` branches FIRST and independently of `kind` — see the class
    // header on orthogonality.
    if (role == 'user') {
      final instruction = payloadMap['instruction'];
      if (instruction is! String || instruction.isEmpty) {
        throw const FormatException(
          'AiSessionTurnModel.fromJson: missing/invalid user instruction',
        );
      }
      return AiSessionUserTurn(
        ordinal: ordinal,
        kind: kind,
        createdAt: createdAt,
        instruction: instruction,
      );
    }
    if (role != 'attune') {
      throw FormatException(
        'AiSessionTurnModel.fromJson: unrecognized role "$role"',
      );
    }

    switch (kind) {
      case AiSessionTurnKind.ideasAnswer:
        final replyText = payloadMap['reply_text'];
        if (replyText is! String || replyText.isEmpty) {
          throw const FormatException(
            'AiSessionTurnModel.fromJson: missing/invalid reply_text',
          );
        }
        // `commit_ai_session_ideas_turn` always writes the
        // `suggested_planning_item` KEY, as JSON null when there is no
        // proposal — it is never absent — so a null is the ordinary
        // case and not a malformed payload.
        final rawItem = payloadMap['suggested_planning_item'];
        SuggestedPlanningItem? suggestedItem;
        if (rawItem != null) {
          if (rawItem is! Map) {
            throw const FormatException(
              'AiSessionTurnModel.fromJson: invalid '
              'suggested_planning_item',
            );
          }
          suggestedItem = SuggestedPlanningItem.fromJson(
            Map<String, dynamic>.from(rawItem),
          );
        }
        return AiSessionIdeasAnswerTurn(
          ordinal: ordinal,
          createdAt: createdAt,
          replyText: replyText,
          suggestedPlanningItem: suggestedItem,
        );
      case AiSessionTurnKind.nearbyResult:
        final replyText = payloadMap['reply_text'];
        if (replyText is! String || replyText.isEmpty) {
          throw const FormatException(
            'AiSessionTurnModel.fromJson: missing/invalid reply_text',
          );
        }
        final rawSources = payloadMap['sources'];
        if (rawSources is! List) {
          throw const FormatException(
            'AiSessionTurnModel.fromJson: missing/invalid sources',
          );
        }
        // Zero sources is VALID: `buildNearbySessionReplyText` has a
        // deterministic no-results branch (§5.3: "Zero results is a
        // deterministic no-results card"). A malformed CARD, however,
        // propagates out of PlaceSourceModel.fromJson rather than being
        // dropped — a turn with one bad card must not render as a turn
        // with fewer cards.
        final sources = rawSources
            .map(
              (source) => PlaceSourceModel.fromJson(
                Map<String, dynamic>.from(source as Map),
              ),
            )
            .toList(growable: false);
        return AiSessionNearbyResultTurn(
          ordinal: ordinal,
          createdAt: createdAt,
          replyText: replyText,
          sources: sources,
        );
    }
  }
}

/// A turn the user authored: their own instruction, as stored.
///
/// Carries [kind] because the two committing RPCs write the user row at
/// the same kind as the Attune row — `'ideas_answer'` for an Ideas
/// exchange, `'nearby_result'` for a published Nearby pair, whose
/// instruction is the server-written literal `'nearby'` rather than
/// anything the user typed.
class AiSessionUserTurn extends AiSessionTurnModel {
  final String instruction;

  const AiSessionUserTurn({
    required super.ordinal,
    required super.kind,
    required super.createdAt,
    required this.instruction,
  });
}

/// A turn Attune authored. Sealed so the analyzer checks that every
/// renderer handles both reachable output kinds exhaustively.
sealed class AiSessionAttuneTurn extends AiSessionTurnModel {
  const AiSessionAttuneTurn({
    required super.ordinal,
    required super.kind,
    required super.createdAt,
  });
}

/// Ideas branch: `{reply_text, suggested_planning_item}`, as
/// `commit_ai_session_ideas_turn` writes it. Never carries `sources` —
/// Ideas makes no Mapbox call.
class AiSessionIdeasAnswerTurn extends AiSessionAttuneTurn {
  final String replyText;
  final SuggestedPlanningItem? suggestedPlanningItem;

  const AiSessionIdeasAnswerTurn({
    required super.ordinal,
    required super.createdAt,
    required this.replyText,
    this.suggestedPlanningItem,
  }) : super(kind: AiSessionTurnKind.ideasAnswer);
}

/// Nearby branch: `{reply_text, sources}`, as
/// `publish_ai_session_nearby_result` writes it. Never carries
/// `suggestedPlanningItem` — Nearby never proposes a Planning item.
class AiSessionNearbyResultTurn extends AiSessionAttuneTurn {
  final String replyText;
  final List<PlaceSourceModel> sources;

  const AiSessionNearbyResultTurn({
    required super.ordinal,
    required super.createdAt,
    required this.replyText,
    required this.sources,
  }) : super(kind: AiSessionTurnKind.nearbyResult);
}

/// The requester's own staged Nearby result, as `handleRead` projects
/// `read_ai_session_staging`'s row.
///
/// **THERE IS NO CONFIRMATION NONCE HERE, AND THERE MUST NOT BE.** The
/// Nearby `confirmation_nonce` the design discussion referred to is
/// DECORATIVE — Plan C's gate 4 established that no RPC, column or
/// table issues one. `read_ai_session_staging` projects exactly
/// `request_id`, `reply_text`, `sources` and `expires_at`
/// ([wireKeys]), and `publish_nearby`'s own allowlist is
/// `{command, request_id}`. A field here would be a confirmation
/// control the server never issued, presented to a user as though it
/// were one.
class AiSessionStagedNearbyResult {
  /// The exact key set `handleRead` projects per staging row,
  /// transcribed from its response literal. Exposed so a test can
  /// assert the absence of a nonce behaviourally rather than by
  /// reading this comment.
  static const Set<String> wireKeys = {
    'request_id',
    'reply_text',
    'sources',
    'expires_at',
  };

  final String requestId;
  final String replyText;
  final List<PlaceSourceModel> sources;

  /// `stage_ai_session_nearby_result` caps this at
  /// `LEAST(now() + interval '2 minutes', session.expires_at)`, and
  /// `read_ai_session_staging`'s own gate re-checks
  /// `expires_at > now()`, so a staged result can vanish between two
  /// reads with no error — the server is the authority on expiry, and a
  /// client holding this value must treat it as a display hint, not as
  /// permission to publish.
  final DateTime expiresAt;

  const AiSessionStagedNearbyResult({
    required this.requestId,
    required this.replyText,
    required this.sources,
    required this.expiresAt,
  });

  factory AiSessionStagedNearbyResult.fromJson(Map<String, dynamic> json) {
    final requestId = json['request_id'];
    if (requestId is! String || requestId.isEmpty) {
      throw const FormatException(
        'AiSessionStagedNearbyResult.fromJson: missing/invalid request_id',
      );
    }
    final replyText = json['reply_text'];
    if (replyText is! String || replyText.isEmpty) {
      throw const FormatException(
        'AiSessionStagedNearbyResult.fromJson: missing/invalid reply_text',
      );
    }
    final rawSources = json['sources'];
    if (rawSources is! List) {
      throw const FormatException(
        'AiSessionStagedNearbyResult.fromJson: missing/invalid sources',
      );
    }
    final rawExpiresAt = json['expires_at'];
    if (rawExpiresAt is! String) {
      throw const FormatException(
        'AiSessionStagedNearbyResult.fromJson: missing/invalid expires_at',
      );
    }
    return AiSessionStagedNearbyResult(
      requestId: requestId,
      replyText: replyText,
      sources: rawSources
          .map(
            (source) => PlaceSourceModel.fromJson(
              Map<String, dynamic>.from(source as Map),
            ),
          )
          .toList(growable: false),
      expiresAt: DateTime.parse(rawExpiresAt),
    );
  }
}

/// The `'read'` command's whole response: `{turns, staged?}`.
///
/// **AN EMPTY [turns] IS NOT EVIDENCE THE SESSION IS GONE, AND THIS
/// TYPE DELIBERATELY OFFERS NO WAY TO CONCLUDE THAT.**
/// `handleRead` returns HTTP 200 with `turns: []` for every
/// unauthorized outcome — unknown session, non-member, withdrawn
/// consent, a shared session this actor never approved, an expired
/// staging row — *and* for a perfectly healthy session that has not
/// committed a turn yet. Its header states the requirement plainly: "a
/// partner's zero rows and a stranger's zero rows must be
/// byte-identical", because §7.2 requires that silence and an
/// `UNAVAILABLE` here would hand back exactly the existence oracle
/// `read_ai_session_turns` was written in SQL to deny. The branch
/// deliberately does not even run the eligibility gate first, since
/// that gate raises distinguishable codes.
///
/// So this class has no `isGone`, `exists`, `isUnavailable` or
/// `isTerminal` member, and emptiness carries no verdict. A UI that
/// wants to say anything about a session's existence must learn it from
/// a command that is entitled to say so — `review_context`, `approve`
/// or `generate`, which return `UNAVAILABLE` as an explicit error code
/// — never from the shape of a `read`.
///
/// `turns` being ABSENT is a different matter, and it throws:
/// `handleRead` always sends the key, so its absence is a malformed
/// response. Treating that as an empty transcript would manufacture a
/// benign empty state out of a broken one — the same inference as
/// "empty means gone", run in reverse.
class AiSessionTranscript {
  /// Committed turns, in `read_ai_session_turns`' own `ORDER BY
  /// ordinal`. **May be non-contiguous** — see
  /// [AiSessionTurnModel.ordinal].
  final List<AiSessionTurnModel> turns;

  /// The requester's own staged Nearby result, when a `request_id` was
  /// supplied to `read`.
  ///
  /// **NULL AND EMPTY MEAN DIFFERENT THINGS AND MUST NOT BE
  /// COLLAPSED.** `handleRead` sends `staged` as absent rather than as
  /// `[]` when the caller did not ask, specifically "so a client can
  /// tell 'I did not ask' from 'I asked and there is nothing'" — a
  /// distinction about the caller's own request, not about anyone's
  /// authorization. Null here means this read did not ask; empty means
  /// it asked and the staging row is gone or expired.
  final List<AiSessionStagedNearbyResult>? staged;

  const AiSessionTranscript({required this.turns, this.staged});

  factory AiSessionTranscript.fromJson(Map<String, dynamic> json) {
    final rawTurns = json['turns'];
    if (rawTurns is! List) {
      throw const FormatException(
        'AiSessionTranscript.fromJson: missing/invalid turns',
      );
    }
    final rawStaged = json['staged'];
    if (rawStaged != null && rawStaged is! List) {
      throw const FormatException(
        'AiSessionTranscript.fromJson: invalid staged',
      );
    }
    return AiSessionTranscript(
      turns: rawTurns
          .map(
            (turn) => AiSessionTurnModel.fromJson(
              Map<String, dynamic>.from(turn as Map),
            ),
          )
          .toList(growable: false),
      staged: rawStaged == null
          ? null
          : (rawStaged as List)
                .map(
                  (row) => AiSessionStagedNearbyResult.fromJson(
                    Map<String, dynamic>.from(row as Map),
                  ),
                )
                .toList(growable: false),
    );
  }
}

// ---------------------------------------------------------------------------
// The `generate` command's RESPONSE types (spec §5.3, §8.1).
//
// NOT transcript turns. These are what `generate` hands back to ITS OWN
// REQUESTER, and the distinction is load-bearing in two directions:
//
//   * A REDIRECT is never committed anywhere (§5.3 as amended by Plan C
//     Task 6 / Item B: "NO redirect becomes a transcript pair. ALL
//     redirects are requester-only"), so it has no ordinal, no
//     created_at and no row — modelling it as an
//     `AiSessionTurnModel` subtype would require inventing all three.
//     See [AiSessionTurnKind]'s header for why a durable redirect is a
//     safety side channel.
//   * A NEARBY GENERATION is only STAGED. `dispatchNearby` calls
//     `stage_ai_session_nearby_result` and returns
//     `{kind: "nearby_result", staged: true, ...}`; the transcript pair
//     does not exist until `publish_nearby` commits it. So it carries
//     no ordinals either, and a client must not render it into a
//     transcript.
//
// `generate` has FOUR success shapes on the wire, which is one more than
// the plan's own description of it and two more than the task brief's.
// Transcribed from the five `jsonResponse` call sites reachable from
// `handleGenerate`:
//
//   1. IDEAS ANSWER (dispatchIdeas, index.ts:2726)
//      {kind: "answer", user_ordinal, attune_ordinal, session_revision,
//       reply_text, suggested_planning_item, show_safety_resources}
//   2. ORDINARY REDIRECT (dispatchIdeas:2707, dispatchNearby:2806)
//      {kind: "redirect", reason, offered, show_safety_resources}
//   3. SAFETY REFUSAL (safetyRefusalResponse:2145, reached from five
//      call sites across both dispatchers and the pre-dispatch pass)
//      {kind: "redirect", reason, copy, show_safety_resources,
//       offered: []}
//   4. NEARBY STAGED (dispatchNearby:2888)
//      {kind: "nearby_result", staged: true, request_id, reply_text,
//       sources, show_safety_resources}
//   5. IDEMPOTENT REPLAY (replayAdmittedRequest:2555) — and this one
//      HAS NO `kind` KEY AT ALL:
//      {user_ordinal, attune_ordinal, reply_text,
//       suggested_planning_item, replayed: true}
//
// Shapes 2 and 3 are parsed by ONE type with NO branch between them.
// See [AiSessionGeneratedRedirect], which is the most constrained type
// in this file and whose header explains why.
// ---------------------------------------------------------------------------

/// What `generate` returns. Sealed, so a renderer must handle every
/// reachable outcome and cannot fall through to a default.
sealed class AiSessionGenerateResult {
  const AiSessionGenerateResult();

  /// Parses whichever of `generate`'s shapes arrived.
  ///
  /// ## The dispatch reads `kind`, and `kind` ALONE distinguishes the
  /// three cases a caller can act on
  ///
  /// It must NOT be read as distinguishing a safety refusal from an
  /// ordinary redirect: both send `kind: "redirect"`, and this factory
  /// returns the SAME type for both with no record of which arrived.
  ///
  /// ## An ABSENT `kind` is the idempotent replay, not a malformed body
  ///
  /// `replayAdmittedRequest` omits `kind` entirely — it projects the
  /// committed turn's stored payload rather than re-deriving the
  /// generated shape — so "no kind, but `replayed: true`" is a legal
  /// answer and the only one that means "your earlier request already
  /// succeeded; here it is again, and no provider was called".
  /// Anything else missing `kind` throws.
  ///
  /// Throws [FormatException] — never a typed [AiSessionError] — on any
  /// shape it cannot read. That is deliberate and is a requirement, not
  /// a preference: `AiSessionRepository._invoke` routes a parser
  /// exception through `_mapTransportError`, whose entire job is to
  /// PRESERVE a §10 code. A parser that threw a CONSTANT typed error
  /// would put a fabricated code on that path, which is the defect
  /// Task 3's mutation 7 found in the opposite direction. A parse
  /// failure is not a §10 outcome; it is a malformed response, and
  /// `_mapTransportError`'s fallthrough is what turns it into
  /// [AiSessionInternalError].
  factory AiSessionGenerateResult.fromJson(Map<String, dynamic> json) {
    final kind = json['kind'];
    if (kind == null) {
      // The replay. `replayed` must be literally true: a body with
      // neither `kind` nor `replayed` is malformed, and defaulting it
      // to an answer would invent an outcome.
      if (json['replayed'] != true) {
        throw const FormatException(
          'AiSessionGenerateResult.fromJson: body has no "kind" and is not '
          'a replay (expected replayed: true)',
        );
      }
      return AiSessionGeneratedAnswer._fromJson(json, replayed: true);
    }
    switch (kind) {
      case 'answer':
        return AiSessionGeneratedAnswer._fromJson(json, replayed: false);
      case 'redirect':
        return AiSessionGeneratedRedirect._fromJson(json);
      case 'nearby_result':
        return AiSessionStagedNearbyGeneration._fromJson(json);
      default:
        throw FormatException(
          'AiSessionGenerateResult.fromJson: unrecognized kind "$kind"',
        );
    }
  }
}

/// A committed Ideas answer — shape 1 — or its idempotent replay,
/// shape 5.
///
/// ## One type for the fresh answer and the replay, with [replayed]
/// carried rather than hidden
///
/// Both describe the same durable fact: a transcript pair exists at
/// these ordinals with this reply. The difference a caller can act on
/// is that a replay means NO NEW PROVIDER CALL HAPPENED and no quota
/// moved (§6.2: "For an existing actor/request ID, return its
/// state/result ... NEVER A NEW PROVIDER LEASE"), which is a fact about
/// the caller's own retry and not about anyone's private state — unlike
/// the redirect distinction, which is why this flag is exposed and that
/// one is not.
///
/// ## [sessionRevision] is NULLABLE, and gate 1 is why
///
/// `dispatchIdeas` sends `session_revision` and the replay path does
/// NOT. So a replay legitimately has none, and null means "this
/// response did not carry one", never "the revision is zero". A client
/// must not synthesize one: the revision is only ever returned to the
/// actor who caused the bump, so there is nothing to fall back to.
class AiSessionGeneratedAnswer extends AiSessionGenerateResult {
  /// The user turn's ordinal, `2n-1`. **NULLABLE on the replay path**:
  /// `replayAdmittedRequest` sends `userTurn?.ordinal ?? null`, so a
  /// committed Attune turn whose user row could not be matched reports
  /// null rather than failing.
  final int? userOrdinal;

  /// The Attune turn's ordinal, `2n`. Always present — both paths send
  /// it, and `replayAdmittedRequest` returns SESSION_BUSY rather than a
  /// body when no committed Attune turn exists.
  ///
  /// **MAY BE NON-CONTIGUOUS WITH ANY EARLIER TURN.** See
  /// [AiSessionTurnModel.ordinal].
  final int attuneOrdinal;

  /// The session's post-commit revision, or null on a replay. See the
  /// class header.
  final int? sessionRevision;

  /// **NULLABLE on the replay path only.** `dispatchIdeas` validated a
  /// non-empty string before committing, but the replay projects
  /// `payload.reply_text ?? null` from the stored row — and for a
  /// replayed NEARBY request that payload is a nearby_result payload,
  /// so a client must be ready for a null here rather than assume a
  /// fresh answer's guarantees.
  final String? replyText;

  final SuggestedPlanningItem? suggestedPlanningItem;

  /// True when the server answered from the already-committed turn
  /// instead of generating. See the class header.
  final bool replayed;

  const AiSessionGeneratedAnswer({
    required this.userOrdinal,
    required this.attuneOrdinal,
    required this.sessionRevision,
    required this.replyText,
    required this.suggestedPlanningItem,
    required this.replayed,
  });

  factory AiSessionGeneratedAnswer._fromJson(
    Map<String, dynamic> json, {
    required bool replayed,
  }) {
    final attuneOrdinal = json['attune_ordinal'];
    if (attuneOrdinal is! int) {
      throw const FormatException(
        'AiSessionGeneratedAnswer: missing/invalid attune_ordinal',
      );
    }
    final userOrdinal = json['user_ordinal'];
    if (userOrdinal != null && userOrdinal is! int) {
      throw const FormatException(
        'AiSessionGeneratedAnswer: invalid user_ordinal',
      );
    }
    final sessionRevision = json['session_revision'];
    if (sessionRevision != null && sessionRevision is! int) {
      throw const FormatException(
        'AiSessionGeneratedAnswer: invalid session_revision',
      );
    }
    final replyText = json['reply_text'];
    if (replyText != null && replyText is! String) {
      throw const FormatException(
        'AiSessionGeneratedAnswer: invalid reply_text',
      );
    }
    // A FRESH answer always carries a validated non-empty reply_text
    // (isAcceptableOutputText enforced 1..2000 scalars before the
    // commit). A replay may not — see [replyText]. So the requirement
    // is conditional on the path rather than dropped for both.
    if (!replayed && (replyText == null || (replyText as String).isEmpty)) {
      throw const FormatException(
        'AiSessionGeneratedAnswer: a fresh answer must carry reply_text',
      );
    }
    final rawItem = json['suggested_planning_item'];
    SuggestedPlanningItem? suggestedItem;
    if (rawItem != null) {
      if (rawItem is! Map) {
        throw const FormatException(
          'AiSessionGeneratedAnswer: invalid suggested_planning_item',
        );
      }
      suggestedItem = SuggestedPlanningItem.fromJson(
        Map<String, dynamic>.from(rawItem),
      );
    }
    return AiSessionGeneratedAnswer(
      userOrdinal: userOrdinal as int?,
      attuneOrdinal: attuneOrdinal,
      sessionRevision: sessionRevision as int?,
      replyText: replyText as String?,
      suggestedPlanningItem: suggestedItem,
      replayed: replayed,
    );
  }
}

/// A redirect from `generate` — **shapes 2 AND 3, through ONE type,
/// with no branch between them and no member whose value differs.**
///
/// # READ THIS BEFORE ADDING ANY MEMBER
///
/// `generate` emits `kind: "redirect"` from two places that must be
/// indistinguishable to a client:
///
///   * `safetyRefusalResponse` (index.ts:2145) — a deterministic safety
///     detector fired. Carries a server-rendered `copy` and an EMPTY
///     `offered`.
///   * the model's own ordinary redirect (index.ts:2707 / :2806) — the
///     request was out of scope. Carries NO `copy`.
///
/// They deliberately share the `kind` **and** the reason set
/// (`unsupported | unsafe_to_assist | insufficient_context`). That
/// sharing is the non-disclosure property, not an accident of
/// implementation: Plan C Task 6 established that a redirect which was
/// durable or distinguishable would disclose that a safety detector
/// fired, and §8.1 forbids revealing which detector fired — to the
/// partner AND to the requester, whose own probing is the attack the
/// shared reason set defeats. The server goes further than it has to in
/// order to keep them identical: the HTTP status is 200 on both, both
/// settle the request row with the SAME reason-free RPC, and neither
/// bumps `ai_sessions.revision`.
///
/// ## Therefore this type exposes NO distinguishing member
///
/// **Anything whose value differs between the two shapes reconstructs
/// the detector signal client-side**, which is the exact disclosure
/// §8.1 forbids, and would do it in the one place a probing requester
/// can reach. Specifically, this type must never grow:
///
///   * `isSafetyRefusal`, `wasBlocked`, `isUnsafe`, `blocked` — the
///     signal named outright;
///   * a public `copy` getter, or anything equivalent to `copy != null`
///     (`hasCopy`, `hasServerCopy`, `copyOrNull`) — present on one
///     shape and absent on the other, so it IS the signal;
///   * anything equivalent to `offered.isEmpty` as a proxy
///     (`hasAlternatives`, `canOfferAnything`) — a refusal always sends
///     `[]`, so emptiness is a strong oracle even though an ordinary
///     redirect may also legally send `[]`;
///   * a `shape`/`source`/`variant` discriminator of any kind.
///
/// [copy] is PRIVATE for that reason, and [resolveCopy] is the only way
/// to reach it: it takes the generic copy a caller would otherwise have
/// written and returns whichever string should be shown, so the call
/// site renders correct text **without ever asking which shape it
/// got**. A UI that calls it cannot tell, a UI that wants to tell has
/// nothing to call, and the easy path is the safe one.
///
/// ## What IS safe to expose, and why
///
///   * [reason] — the SAME three-value set on both paths. A safety
///     refusal reports `unsafe_to_assist` or `unsupported`
///     (`classifySessionContent`'s only two refusing returns), and the
///     model may report either of those too. So reading it narrows
///     nothing: `unsupported` is the ordinary out-of-scope answer AND
///     the fail-closed answer for content the corpus could not
///     evaluate.
///   * [offered] — a list on both paths. Rendering its entries is fine;
///     branching on its emptiness is not. See above.
///   * [showSafetyResources] — `classifySessionContent` sets it true at
///     ALL THREE return points including the allowed one, and both
///     redirect bodies hardcode `true`. It is a constant, so it is not
///     a signal. It is carried rather than dropped because §8.1
///     requires the link be offered, and a caller that needs to know
///     whether to offer it should read a field rather than hardcode
///     `true` and drift. **A caller must not treat its presence or its
///     value as a signal either** — being constant, it cannot be one,
///     and [AiSessionRepository] has a test that holds it constant.
class AiSessionGeneratedRedirect extends AiSessionGenerateResult {
  /// The exact key set the SAFETY shape sends, transcribed from
  /// `safetyRefusalResponse`. Exposed only so a test can prove both
  /// shapes parse and neither is distinguishable afterwards; nothing in
  /// production reads it.
  static const Set<String> safetyShapeWireKeys = {
    'kind',
    'reason',
    'copy',
    'show_safety_resources',
    'offered',
  };

  /// The exact key set the ORDINARY shape sends, transcribed from
  /// `dispatchIdeas`/`dispatchNearby`'s redirect branches. Its only
  /// difference from [safetyShapeWireKeys] is `copy` — which is
  /// precisely why `copy` is not readable from this type.
  static const Set<String> ordinaryShapeWireKeys = {
    'kind',
    'reason',
    'offered',
    'show_safety_resources',
  };

  /// One of `unsupported`, `unsafe_to_assist`, `insufficient_context` —
  /// the same set on both paths. See the class header.
  final String reason;

  /// The modes the server suggests instead, each `ideas` or `nearby`.
  /// **Render the entries; never branch on the list being empty.**
  final List<String> offered;

  /// Constant-true on every path. See the class header; not a signal.
  final bool showSafetyResources;

  /// The server-rendered copy, when this body carried one.
  ///
  /// **PRIVATE, and it must stay private.** Its presence is exactly
  /// what separates the two shapes, so a public accessor — or any
  /// getter derived from it — would be the detector oracle this type
  /// exists to prevent. Reachable only through [resolveCopy], which
  /// cannot report whether it was null.
  final String? _copy;

  const AiSessionGeneratedRedirect({
    required this.reason,
    required this.offered,
    required this.showSafetyResources,
    required String? copy,
  }) : _copy = copy;

  /// The text to show the user: the server's own copy when this body
  /// carried one, and [genericRedirectCopy] otherwise.
  ///
  /// **This is the whole public surface over [_copy], and it is a total
  /// function.** It returns a non-null String for both shapes and
  /// reveals nothing about which it received: a caller passes the copy
  /// it would have rendered anyway and gets back the copy to render.
  /// There is no overload, no flag and no second return value that
  /// could leak the branch, and because [genericRedirectCopy] is
  /// required rather than defaulted, a caller cannot accidentally
  /// discover the server's copy by comparing against a known default.
  ///
  /// §5.3 requires the server's string be shown verbatim when present
  /// ("server-rendered fixed copy from allowlisted reason") — nothing
  /// is interpolated into it server-side, so nothing may be
  /// interpolated into it here either.
  String resolveCopy({required String genericRedirectCopy}) {
    return _copy ?? genericRedirectCopy;
  }

  factory AiSessionGeneratedRedirect._fromJson(Map<String, dynamic> json) {
    // ONE PARSE PATH FOR BOTH SHAPES. There is deliberately no
    // `if (json.containsKey('copy'))` branch, no shape detection and
    // no record of which arrived: `copy` is read with the same
    // nullable lookup either way, so this factory COULD NOT report the
    // difference even if a caller asked it to.
    final reason = json['reason'];
    if (reason is! String || reason.isEmpty) {
      throw const FormatException(
        'AiSessionGeneratedRedirect: missing/invalid reason',
      );
    }
    // The three values `validateSessionTurnOutput` admits and
    // `classifySessionContent` produces — ONE set shared by both
    // shapes, which is the property that keeps the reason from being a
    // signal. An unknown value is a malformed response rather than a
    // fourth case to render.
    if (reason != 'unsupported' &&
        reason != 'unsafe_to_assist' &&
        reason != 'insufficient_context') {
      throw FormatException(
        'AiSessionGeneratedRedirect: unrecognized reason "$reason"',
      );
    }
    final rawOffered = json['offered'];
    if (rawOffered is! List) {
      throw const FormatException(
        'AiSessionGeneratedRedirect: missing/invalid offered',
      );
    }
    final offered = rawOffered.map((entry) {
      if (entry is! String || (entry != 'ideas' && entry != 'nearby')) {
        throw FormatException(
          'AiSessionGeneratedRedirect: unrecognized offered entry "$entry"',
        );
      }
      return entry;
    }).toList(growable: false);
    final rawCopy = json['copy'];
    if (rawCopy != null && rawCopy is! String) {
      throw const FormatException(
        'AiSessionGeneratedRedirect: invalid copy',
      );
    }
    final showSafetyResources = json['show_safety_resources'];
    if (showSafetyResources is! bool) {
      throw const FormatException(
        'AiSessionGeneratedRedirect: missing/invalid show_safety_resources',
      );
    }
    return AiSessionGeneratedRedirect(
      reason: reason,
      offered: offered,
      showSafetyResources: showSafetyResources,
      copy: rawCopy as String?,
    );
  }
}

/// A Nearby generation's STAGED result — shape 4.
///
/// **Nothing is committed and the partner can see nothing.** §5.3 / §2:
/// the result "remain[s] requester-only staging until requester
/// explicitly publishes that pair". So this type carries NO ordinals
/// (none exist yet), NO `session_revision` (the revision has not moved)
/// and is NOT an [AiSessionTurnModel]. The caller's next action is
/// [AiSessionRepository.publishNearby] or
/// [AiSessionRepository.discardNearby], keyed by [requestId].
///
/// **THERE IS NO CONFIRMATION NONCE HERE, AND THERE MUST NOT BE** — the
/// same requirement [AiSessionStagedNearbyResult] records. The Nearby
/// `confirmation_nonce` is DECORATIVE: `parseGenerateRequest`
/// allowlists it inside `requester_location` and explicitly does NOT
/// trust it ("no issuing RPC, no column and no table ... a nonce this
/// function invents and immediately accepts would gate nothing while
/// reading as implemented"). No response body echoes one, and
/// `publish_nearby`'s allowlist is `{command, request_id}` — so
/// publishing is authorized by the actor's JWT and the staging row's
/// own author check, never by a nonce. A field here would present a
/// confirmation control the server never issued.
///
/// Distinct from [AiSessionStagedNearbyResult], which is the same
/// underlying row as `read` PROJECTS it, with `expires_at` and without
/// `kind`/`staged`/`show_safety_resources`. They are not merged because
/// their key sets differ: `generate` does not send `expires_at`, so a
/// merged type would need it nullable and a caller could not tell a
/// fresh stage's unknown expiry from a read's known one.
class AiSessionStagedNearbyGeneration extends AiSessionGenerateResult {
  /// The exact key set `dispatchNearby`'s staging response sends.
  static const Set<String> wireKeys = {
    'kind',
    'staged',
    'request_id',
    'reply_text',
    'sources',
    'show_safety_resources',
  };

  /// The request id to pass to `publish_nearby`/`discard_nearby`. The
  /// server echoes back the one the client sent.
  final String requestId;

  /// SERVER-ASSEMBLED, never model-written:
  /// `buildNearbySessionReplyText` builds it from the category and the
  /// place names, with a deterministic no-results branch.
  final String replyText;

  /// Zero to three cards. **Zero is valid** — §5.3's "Zero results is a
  /// deterministic no-results card" — so an empty list is a real
  /// outcome to render, not a failure.
  final List<PlaceSourceModel> sources;

  /// Constant-true. Not a signal; see [AiSessionGeneratedRedirect].
  final bool showSafetyResources;

  const AiSessionStagedNearbyGeneration({
    required this.requestId,
    required this.replyText,
    required this.sources,
    required this.showSafetyResources,
  });

  factory AiSessionStagedNearbyGeneration._fromJson(
    Map<String, dynamic> json,
  ) {
    // `staged: true` is a literal the server always sends on this
    // shape. Required rather than ignored: a `nearby_result` body
    // WITHOUT it would mean the staging contract changed, and a client
    // that rendered it as staged anyway could offer a publish button
    // for a row that was already committed.
    if (json['staged'] != true) {
      throw const FormatException(
        'AiSessionStagedNearbyGeneration: expected staged: true',
      );
    }
    final requestId = json['request_id'];
    if (requestId is! String || requestId.isEmpty) {
      throw const FormatException(
        'AiSessionStagedNearbyGeneration: missing/invalid request_id',
      );
    }
    final replyText = json['reply_text'];
    if (replyText is! String || replyText.isEmpty) {
      throw const FormatException(
        'AiSessionStagedNearbyGeneration: missing/invalid reply_text',
      );
    }
    final rawSources = json['sources'];
    if (rawSources is! List) {
      throw const FormatException(
        'AiSessionStagedNearbyGeneration: missing/invalid sources',
      );
    }
    final showSafetyResources = json['show_safety_resources'];
    if (showSafetyResources is! bool) {
      throw const FormatException(
        'AiSessionStagedNearbyGeneration: missing/invalid '
        'show_safety_resources',
      );
    }
    return AiSessionStagedNearbyGeneration(
      requestId: requestId,
      replyText: replyText,
      // A malformed CARD propagates rather than being dropped — the
      // same reasoning [AiSessionNearbyResultTurn] gives.
      sources: rawSources
          .map(
            (source) => PlaceSourceModel.fromJson(
              Map<String, dynamic>.from(source as Map),
            ),
          )
          .toList(growable: false),
      showSafetyResources: showSafetyResources,
    );
  }
}

/// `publish_nearby`'s success body (spec §5.3, §8.2.2).
///
/// Four fields, transcribed from `handlePublishNearby`'s own
/// `jsonResponse`: `{committed, user_ordinal, attune_ordinal,
/// session_revision}`. **The task brief claimed this command returns
/// `{user_ordinal, attune_ordinal}` only and therefore that the client
/// must `read` again to render the published pair; that is wrong on
/// both counts** — the body carries the revision too, and the committed
/// content is the staged content the caller already held.
///
/// ## [sessionRevision] reaches ONLY the actor who caused the bump
///
/// Gate 1. `publish_ai_session_nearby_result` bumps
/// `ai_sessions.revision` in the same transaction that commits the
/// pair, and this body is the only place that integer is disclosed —
/// the PARTNER, who is the party that must poll to notice the new
/// turns, cannot read it from any command. Nothing here may be built on
/// the assumption that the partner can.
class AiSessionPublishNearbyResult {
  /// The exact key set `handlePublishNearby` returns.
  static const Set<String> wireKeys = {
    'committed',
    'user_ordinal',
    'attune_ordinal',
    'session_revision',
  };

  /// `row.committed === true`. The RPC reports it true for a fresh
  /// publish AND for an idempotent replay of one that already
  /// succeeded, which is the point: a retry after a dropped response
  /// must report success rather than `RESULT_UNAVAILABLE`.
  final bool committed;

  /// `2n-1` / `2n` for the published pair. **May be non-contiguous** —
  /// see [AiSessionTurnModel.ordinal].
  final int userOrdinal;
  final int attuneOrdinal;

  /// The post-publish revision. See the class header on gate 1.
  final int sessionRevision;

  const AiSessionPublishNearbyResult({
    required this.committed,
    required this.userOrdinal,
    required this.attuneOrdinal,
    required this.sessionRevision,
  });

  factory AiSessionPublishNearbyResult.fromJson(Map<String, dynamic> json) {
    final committed = json['committed'];
    if (committed is! bool) {
      throw const FormatException(
        'AiSessionPublishNearbyResult: missing/invalid committed',
      );
    }
    // `committed: false` is not something the RPC can return on a
    // success status — it raises instead, and the branch maps every
    // raise to a §10 code. So a false here is a malformed response
    // rather than a "published nothing" outcome to render.
    if (!committed) {
      throw const FormatException(
        'AiSessionPublishNearbyResult: committed was false on a success '
        'response',
      );
    }
    final userOrdinal = json['user_ordinal'];
    final attuneOrdinal = json['attune_ordinal'];
    if (userOrdinal is! int || attuneOrdinal is! int) {
      throw const FormatException(
        'AiSessionPublishNearbyResult: missing/invalid ordinals',
      );
    }
    final sessionRevision = json['session_revision'];
    if (sessionRevision is! int) {
      throw const FormatException(
        'AiSessionPublishNearbyResult: missing/invalid session_revision',
      );
    }
    return AiSessionPublishNearbyResult(
      committed: committed,
      userOrdinal: userOrdinal,
      attuneOrdinal: attuneOrdinal,
      sessionRevision: sessionRevision,
    );
  }
}

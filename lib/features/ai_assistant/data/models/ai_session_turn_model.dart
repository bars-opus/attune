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

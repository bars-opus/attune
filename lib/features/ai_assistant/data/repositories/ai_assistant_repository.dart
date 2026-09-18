// lib/features/ai_assistant/data/repositories/ai_assistant_repository.dart
import 'dart:convert';
import 'dart:math';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/assist_draft_model.dart';
import '../models/understand_result_model.dart';
import 'assistant_error.dart';

/// A raw, unvalidated geolocation reading for a Nearby request (spec
/// §5.2). This is deliberately a bare positional record, not a class
/// tied to any particular location package, since the repository's
/// only job with it is to forward the three numbers into the request
/// body — it does not read from, or validate ranges against,
/// Geolocator or `LocationService` itself; that happens server-side
/// (spec §5.2) and, client-side, wherever the raw-position method the
/// spec requires (never `LocationService.getCurrentLocation()`) is
/// implemented.
typedef RequesterLocation = ({
  double latitude,
  double longitude,
  double accuracyM,
});

/// The caller's and both partners' AI-processing consent state, as
/// `get_ai_processing_consent_status` returns it (Plan A Task 3).
class AiConsentStatus {
  final bool callerGranted;
  final bool bothGranted;
  final String policyVersion;

  const AiConsentStatus({
    required this.callerGranted,
    required this.bothGranted,
    required this.policyVersion,
  });
}

/// The result of `create_planning_from_assist_message` (spec §5.4):
/// exactly one of `planningItemId`/`planningEventId` is non-null,
/// matching the RPC's own `RETURNS TABLE (planning_item_id uuid,
/// planning_event_id uuid)` shape.
class AddToPlanningResult {
  final String? planningItemId;
  final String? planningEventId;

  const AddToPlanningResult({this.planningItemId, this.planningEventId});
}

/// The seam `AiAssistantRepository` calls through, so tests can fake it
/// instead of the real, heavily-generic `SupabaseClient` function-
/// invoke/RPC builders — the same reasoning
/// `lib/features/planning/data/repositories/planning_repository.dart`'s
/// own `PlanningRpcGateway` gives for doing this rather than mocking
/// `SupabaseClient` directly. Extended with `invokeFunction` alongside
/// `rpc`, since this repository — unlike Planning's, which is RPC-only
/// — also calls the two edge functions (`ai-assist`, `ai-understand`)
/// directly by HTTP contract (spec §4.1), not through an RPC.
abstract class AiAssistantGateway {
  Future<dynamic> invokeFunction(String functionName, {Map<String, dynamic>? body});
  Future<dynamic> rpc(String function, {Map<String, dynamic>? params});

  /// A plain, RLS-scoped SELECT against `ai_assist_planning_links` for
  /// one message id — this table is SELECT-only for `authenticated`
  /// (Plan A Task 1's grants), so a direct read here needs no RPC
  /// wrapper the way every write in this feature does. Returns the raw
  /// row map, or `null` if no link exists (an ordinary
  /// `.maybeSingle()`-shaped absence, not an error).
  Future<Map<String, dynamic>?> selectPlanningLink(String messageId);
}

class SupabaseAiAssistantGateway implements AiAssistantGateway {
  final SupabaseClient _supabase;
  const SupabaseAiAssistantGateway(this._supabase);

  @override
  Future<dynamic> invokeFunction(
    String functionName, {
    Map<String, dynamic>? body,
  }) async {
    final response = await _supabase.functions.invoke(functionName, body: body);
    return response.data;
  }

  @override
  Future<dynamic> rpc(String function, {Map<String, dynamic>? params}) {
    return _supabase.rpc(function, params: params);
  }

  @override
  Future<Map<String, dynamic>?> selectPlanningLink(String messageId) async {
    final row = await _supabase
        .from('ai_assist_planning_links')
        .select('planning_item_id,planning_event_id')
        .eq('message_id', messageId)
        .maybeSingle();
    return row;
  }
}

/// Domain/repository layer over the AI Assistant's two edge functions
/// (`ai-assist`, `ai-understand`) and Plan A's RPCs. Every method here
/// throws [AssistantError] on failure — never a raw
/// `FunctionException`/`PostgrestException`/parse exception — so every
/// call site downstream can pattern-match on the sealed error type
/// alone (this is the exact promise `PlanningRepository` already makes
/// for `PlanningError`).
class AiAssistantRepository {
  final AiAssistantGateway _gateway;
  const AiAssistantRepository(this._gateway);

  /// Requests an Assist draft. `assistKind` is `'ideas'` or `'nearby'`;
  /// `requesterLocation` is required by the server for `'nearby'` (a
  /// missing one there surfaces as `AssistantError.locationRequired()`
  /// via the server's own `LOCATION_REQUIRED` code — this method does
  /// not pre-empt that check client-side, since the server is the
  /// single source of truth for the rule per spec §5.2).
  Future<AssistDraftModel> requestAssist({
    required String requestId,
    required String messageId,
    required String assistKind,
    String? userInstruction,
    RequesterLocation? requesterLocation,
  }) async {
    final body = <String, dynamic>{
      'request_id': requestId,
      'message_id': messageId,
      'assist_kind': assistKind,
      'user_instruction': userInstruction,
      'requester_location': requesterLocation == null
          ? null
          : {
              'latitude': requesterLocation.latitude,
              'longitude': requesterLocation.longitude,
              'accuracy_m': requesterLocation.accuracyM,
            },
    };

    return _invoke(
      'ai-assist',
      body: body,
      onResult: (data) => AssistDraftModel.fromJson(
        Map<String, dynamic>.from(data as Map),
        assistKind: assistKind,
      ),
    );
  }

  /// Requests an Understand result for the other partner's message
  /// (spec §6). Never persists or caches the result itself — that
  /// discipline belongs to the `.autoDispose` provider that owns it
  /// (spec §6.3), not to this repository.
  Future<UnderstandResultModel> requestUnderstand({
    required String requestId,
    required String messageId,
    required int utcOffsetMinutes,
  }) {
    final body = <String, dynamic>{
      'request_id': requestId,
      'message_id': messageId,
      'utc_offset_minutes': utcOffsetMinutes,
    };

    return _invoke(
      'ai-understand',
      body: body,
      onResult: (data) => UnderstandResultModel.fromJson(
        Map<String, dynamic>.from(data as Map),
      ),
    );
  }

  /// `Share in chat` (spec §5.3). Calls `share_ai_assist_draft` with
  /// EXACTLY `p_draft_id` — that RPC's real, single-parameter
  /// signature (confirmed against
  /// supabase/migrations/20260950080000_ai_assist_draft_and_share_rpcs.sql,
  /// which this worktree already has committed) — never a
  /// client-supplied replacement content/payload, which the RPC does
  /// not accept at all.
  Future<void> shareDraft(String draftId) {
    return _call(
      'share_ai_assist_draft',
      params: {'p_draft_id': draftId},
      onResult: (_) {},
    );
  }

  /// Reads both partners' AI-processing consent state for a
  /// relationship (Plan A Task 3). Calls
  /// `get_ai_processing_consent_status` with exactly `p_relationship_id`
  /// (confirmed against
  /// supabase/migrations/20260950040000_ai_processing_consent_rpcs.sql).
  Future<AiConsentStatus> getConsentStatus(String relationshipId) {
    return _call(
      'get_ai_processing_consent_status',
      params: {'p_relationship_id': relationshipId},
      onResult: (data) {
        final rows = data as List;
        final row = Map<String, dynamic>.from(rows.first as Map);
        return AiConsentStatus(
          callerGranted: row['caller_granted'] as bool,
          bothGranted: row['both_granted'] as bool,
          policyVersion: row['policy_version'] as String,
        );
      },
    );
  }

  /// Grants or withdraws this user's AI-processing consent (spec
  /// §10.1). `action` must be `'granted'` or `'withdrawn'` — validated
  /// server-side, not re-validated here, since the RPC's own
  /// `RAISE EXCEPTION 'Invalid action'` is the single source of truth
  /// for that rule.
  ///
  /// `record_ai_processing_consent`'s real signature is
  /// `(p_relationship_id uuid, p_action text, p_idempotency_key uuid)`
  /// (confirmed against
  /// supabase/migrations/20260950040000_ai_processing_consent_rpcs.sql) —
  /// three parameters, not the two the plan's own paraphrase of "Plan
  /// A's Task 3 RPCs" implies. The idempotency key exists so a retried
  /// call after a dropped response can't double-insert a consent
  /// event (the RPC's own `ON CONFLICT (user_id, idempotency_key) DO
  /// NOTHING`); this method generates a fresh one per call rather than
  /// accepting one from the caller, since nothing upstream of this
  /// repository has a reason to control or replay it yet.
  Future<void> recordConsent(String relationshipId, String action) {
    return _call(
      'record_ai_processing_consent',
      params: {
        'p_relationship_id': relationshipId,
        'p_action': action,
        'p_idempotency_key': _generateUuidV4(),
      },
      onResult: (_) {},
    );
  }

  /// "Add to Planning" (spec §5.4). Calls
  /// `create_planning_from_assist_message` with exactly `p_message_id`,
  /// `p_edited_title`, `p_edited_date` (confirmed against
  /// supabase/migrations/20260950090000_create_planning_from_assist_message_rpc.sql).
  /// `editedTitle`/`editedDate` are optional overrides of the
  /// suggestion's own title/date — omitting them lets the RPC fall back
  /// to the proposal's own values (`COALESCE(p_edited_title, v_proposal
  /// ->> 'title')` etc. in that migration).
  Future<AddToPlanningResult> addToPlanning(
    String messageId, {
    String? editedTitle,
    DateTime? editedDate,
  }) {
    return _call(
      'create_planning_from_assist_message',
      params: {
        'p_message_id': messageId,
        'p_edited_title': editedTitle,
        'p_edited_date': editedDate?.toIso8601String().split('T').first,
      },
      onResult: (data) {
        final rows = data as List;
        final row = Map<String, dynamic>.from(rows.first as Map);
        return AddToPlanningResult(
          planningItemId: row['planning_item_id'] as String?,
          planningEventId: row['planning_event_id'] as String?,
        );
      },
    );
  }

  /// Whether [messageId]'s shared Assist proposal has already been
  /// converted to a Planning entity — the "Add to Planning" affordance
  /// (spec §5.4) must show "Added to Planning" instead once this is
  /// non-null, so two partners racing the same tap don't create a
  /// second entity nor see a stale "Add to Planning" after the first
  /// partner already confirmed it. Returns `null` on a transport
  /// failure rather than throwing — a UI that can't confirm the link
  /// state should fail closed to "show Add to Planning" (a subsequent
  /// idempotent `addToPlanning` call is always safe, per
  /// `create_planning_from_assist_message`'s own re-check), not crash
  /// the bubble.
  Future<AddToPlanningResult?> getPlanningLink(String messageId) async {
    try {
      final row = await _gateway.selectPlanningLink(messageId);
      if (row == null) return null;
      return AddToPlanningResult(
        planningItemId: row['planning_item_id'] as String?,
        planningEventId: row['planning_event_id'] as String?,
      );
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------------------------
  // Shared call helpers
  // ---------------------------------------------------------------------

  Future<T> _invoke<T>(
    String functionName, {
    required Map<String, dynamic> body,
    required T Function(dynamic data) onResult,
  }) async {
    dynamic data;
    try {
      data = await _gateway.invokeFunction(functionName, body: body);
    } catch (error) {
      throw _mapTransportError(error);
    }
    try {
      return onResult(data);
    } catch (error) {
      // A malformed/unparseable success-status response should never
      // happen server-side, but the client must not crash on it — map
      // to the generic internal error rather than propagating a raw
      // parse exception (FormatException/TypeError/etc.) to the UI.
      throw const AssistantError.internalError();
    }
  }

  Future<T> _call<T>(
    String function, {
    Map<String, dynamic>? params,
    required T Function(dynamic result) onResult,
  }) async {
    dynamic result;
    try {
      result = await _gateway.rpc(function, params: params);
    } catch (error) {
      throw _mapTransportError(error);
    }
    try {
      return onResult(result);
    } catch (error) {
      throw const AssistantError.internalError();
    }
  }

  /// Maps whatever the gateway throws into an [AssistantError]:
  ///
  /// - A [FunctionException] from `functions.invoke` on a non-2xx
  ///   response carries the edge function's own JSON error envelope
  ///   (spec §11) in `details` — decode it and dispatch through
  ///   `AssistantError.fromCode`, the one place a raw server code is
  ///   allowed to become a typed error.
  /// - A [PostgrestException] from an RPC call (unauthenticated/RLS
  ///   refusal, a `RAISE EXCEPTION`, etc.) has no `AssistantErrorCode`
  ///   of its own — Plan A's RPCs are plain SQL functions, not the
  ///   discriminated-envelope edge functions — so it maps to
  ///   `internalError()` rather than guessing a more specific code from
  ///   free-form SQLSTATE/message text (unlike `PlanningRepository`,
  ///   which DOES do that kind of message-text mapping for Planning's
  ///   own RPCs; there is no equivalent spec-defined mapping for these
  ///   four AI RPCs, so inventing one here would be guessing a contract
  ///   the spec never made).
  /// - Anything else (network/timeout/etc.) also maps to
  ///   `internalError()`, which spec §11's retry guidance treats as
  ///   "offer a new explicit attempt with a new ID/slot" — the safe
  ///   default for an error this client cannot otherwise characterize.
  AssistantError _mapTransportError(Object error) {
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
        return AssistantError.fromCode(
          code,
          retryAfterSeconds: retryAfter is int ? retryAfter : null,
        );
      }
      return const AssistantError.internalError();
    }
    if (error is AssistantError) return error;
    return const AssistantError.internalError();
  }
}

final _uuidRandom = Random.secure();

/// A locally-generated random (v4) UUID for `record_ai_processing_
/// consent`'s idempotency key. Not cryptographic key material — just
/// needs to be unique per call — so `Random.secure()` here is about
/// avoiding a predictable/colliding sequence across app instances, not
/// about security in the encryption sense.
String _generateUuidV4() {
  final bytes = List<int>.generate(16, (_) => _uuidRandom.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
      '${hex.substring(20, 32)}';
}

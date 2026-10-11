// ai-assist: the Assist mode edge function (Ideas + Nearby). Spec §4.1,
// §5.1-§5.3, §7.3, §9, §11.
//
// This function NEVER inserts a chat message directly and NEVER accepts a
// client-supplied relationship/requester/context/history field -- see
// §4.1. It loads its own trusted context via loadAiAssistantTarget/
// loadBoundedContext (Task 2), reserves quota via reserve_ai_assistant_quota
// BEFORE any provider call (Task 4), and writes its result only through
// insert_ai_assist_draft, a service-role-only RPC (Task 6 migration) that
// no user can call directly.

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";

import { claimProviderStart, jsonResponse, serviceRoleClient } from "../_shared/attune_auth.ts";
import { userScopedClient } from "../_shared/user_scoped_client.ts";
import {
  loadAiAssistantTarget,
  loadBoundedContext,
  LoadedTarget,
} from "../_shared/ai_context_loader.ts";
import { callGeminiJson } from "../_shared/gemini_json.ts";
// RULING 6: moved to _shared/ so ai-sessions can use the same helper
// without a cross-function-directory import (a pattern this repo has
// never deployed). Re-exported below so this module's existing public
// surface is unchanged.
import {
  NEARBY_CATEGORY_ALLOWLIST,
  type NearbyCategory,
  type NearbyCategoryOutput,
  type PlaceSource,
  searchMapboxCategory,
  validateNearbyCategoryOutput,
} from "../_shared/mapbox_search.ts";

// ---------------------------------------------------------------------------
// Error envelope -- spec §11. Every response, success or failure, uses one
// shape per branch; every failure uses exactly this discriminated union.
// ---------------------------------------------------------------------------

export type AssistantErrorCode =
  | "UNAUTHENTICATED"
  | "CONSENT_REQUIRED"
  | "TARGET_UNAVAILABLE"
  | "INVALID_INPUT"
  | "UNSUPPORTED_REQUEST"
  | "LOCATION_REQUIRED"
  | "NO_RESULTS"
  | "RATE_LIMITED"
  | "REQUEST_IN_PROGRESS"
  | "RESULT_UNAVAILABLE"
  | "PROVIDER_UNAVAILABLE"
  | "INTERNAL_ERROR";

export interface AssistantError {
  error: true;
  code: AssistantErrorCode;
  retryable: boolean;
  retry_after_seconds: number | null;
}

const RETRYABLE_CODES = new Set<AssistantErrorCode>([
  "RATE_LIMITED",
  "PROVIDER_UNAVAILABLE",
  "NO_RESULTS",
]);

export function assistantError(
  code: AssistantErrorCode,
  retryAfterSeconds: number | null = null,
): AssistantError {
  return {
    error: true,
    code,
    retryable: RETRYABLE_CODES.has(code),
    retry_after_seconds: retryAfterSeconds,
  };
}

const HTTP_STATUS: Record<AssistantErrorCode, number> = {
  UNAUTHENTICATED: 401,
  CONSENT_REQUIRED: 403,
  TARGET_UNAVAILABLE: 404,
  INVALID_INPUT: 400,
  UNSUPPORTED_REQUEST: 422,
  LOCATION_REQUIRED: 400,
  NO_RESULTS: 404,
  RATE_LIMITED: 429,
  REQUEST_IN_PROGRESS: 409,
  RESULT_UNAVAILABLE: 410,
  PROVIDER_UNAVAILABLE: 502,
  INTERNAL_ERROR: 500,
};

// ---------------------------------------------------------------------------
// Request contract -- spec §4.1. Only these fields; unknown fields are
// rejected before any DB/provider work.
// ---------------------------------------------------------------------------

const ALLOWED_TOP_LEVEL_FIELDS = new Set([
  "request_id",
  "message_id",
  "assist_kind",
  "user_instruction",
  "requester_location",
]);

export interface AssistRequest {
  requestId: string;
  messageId: string;
  assistKind: "ideas" | "nearby";
  userInstruction: string | null;
  requesterLocation: { latitude: number; longitude: number; accuracyM: number } | null;
}

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function isFiniteNumber(value: unknown): value is number {
  return typeof value === "number" && Number.isFinite(value);
}

/// Exported for the failing-fast validation tests: every check here must
/// run before any DB/provider call, so it must be independently testable
/// with no client/network dependency at all.
export function validateAssistRequest(
  body: unknown,
): { ok: true; request: AssistRequest } | { ok: false } {
  if (!body || typeof body !== "object" || Array.isArray(body)) return { ok: false };
  const record = body as Record<string, unknown>;

  for (const key of Object.keys(record)) {
    if (!ALLOWED_TOP_LEVEL_FIELDS.has(key)) return { ok: false };
  }

  const requestId = record.request_id;
  const messageId = record.message_id;
  const assistKind = record.assist_kind;

  if (typeof requestId !== "string" || !UUID_RE.test(requestId)) return { ok: false };
  if (typeof messageId !== "string" || !UUID_RE.test(messageId)) return { ok: false };
  if (assistKind !== "ideas" && assistKind !== "nearby") return { ok: false };

  let userInstruction: string | null = null;
  if (record.user_instruction !== undefined && record.user_instruction !== null) {
    if (typeof record.user_instruction !== "string") return { ok: false };
    const trimmed = record.user_instruction.trim();
    if (trimmed.length < 1 || trimmed.length > 300) return { ok: false };
    userInstruction = trimmed;
  }

  let requesterLocation: AssistRequest["requesterLocation"] = null;
  if (record.requester_location !== undefined && record.requester_location !== null) {
    const loc = record.requester_location;
    if (!loc || typeof loc !== "object" || Array.isArray(loc)) return { ok: false };
    const locRecord = loc as Record<string, unknown>;
    const allowedLocFields = new Set(["latitude", "longitude", "accuracy_m"]);
    for (const key of Object.keys(locRecord)) {
      if (!allowedLocFields.has(key)) return { ok: false };
    }
    const { latitude, longitude, accuracy_m } = locRecord;
    if (!isFiniteNumber(latitude) || latitude < -90 || latitude > 90) return { ok: false };
    if (!isFiniteNumber(longitude) || longitude < -180 || longitude > 180) return { ok: false };
    if (!isFiniteNumber(accuracy_m) || accuracy_m < 0) return { ok: false };
    requesterLocation = { latitude, longitude, accuracyM: accuracy_m };
  }

  if (assistKind === "nearby" && requesterLocation === null) {
    // Caller must distinguish LOCATION_REQUIRED from INVALID_INPUT --
    // handled by the caller, not here, since this function only proves
    // shape validity. Signal it via a dedicated field the caller checks.
    return {
      ok: true,
      request: {
        requestId,
        messageId,
        assistKind,
        userInstruction,
        requesterLocation: null,
      },
    };
  }

  return {
    ok: true,
    request: {
      requestId,
      messageId,
      assistKind,
      userInstruction,
      requesterLocation,
    },
  };
}

// ---------------------------------------------------------------------------
// Model output contracts -- spec §5.2, exactly.
// ---------------------------------------------------------------------------

export interface IdeasModelOutput {
  reply_text: string;
  suggested_planning_item: {
    kind: "task" | "event";
    title: string;
    event_date: string | null;
  } | null;
}

// The Nearby category allowlist, its validator, PlaceSource and
// searchMapboxCategory all live in _shared/mapbox_search.ts now
// (Plan C Ruling 6). Re-exported here, unchanged, so every existing
// importer of this module -- including index.test.ts -- keeps working
// and the move is provably behaviour-preserving.
export {
  NEARBY_CATEGORY_ALLOWLIST,
  searchMapboxCategory,
  validateNearbyCategoryOutput,
};
export type { NearbyCategory, NearbyCategoryOutput, PlaceSource };

const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;

/// Exported for direct unit testing: this is the exact boundary where raw
/// model JSON becomes trusted structured output. Returns null for
/// anything that doesn't match §5.2's IdeasModelOutput exactly (unknown
/// top-level fields, wrong types/enums/lengths) -- never a best-effort
/// partial parse.
export function validateIdeasOutput(parsed: unknown): IdeasModelOutput | null {
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) return null;
  const record = parsed as Record<string, unknown>;
  const allowedKeys = new Set(["reply_text", "suggested_planning_item"]);
  for (const key of Object.keys(record)) {
    if (!allowedKeys.has(key)) return null;
  }

  const replyText = record.reply_text;
  if (typeof replyText !== "string") return null;
  const trimmedReply = replyText.trim();
  if (trimmedReply.length < 1 || trimmedReply.length > 2000) return null;

  const rawItem = record.suggested_planning_item;
  let suggestedItem: IdeasModelOutput["suggested_planning_item"] = null;
  if (rawItem !== null && rawItem !== undefined) {
    if (typeof rawItem !== "object" || Array.isArray(rawItem)) return null;
    const itemRecord = rawItem as Record<string, unknown>;
    const allowedItemKeys = new Set(["kind", "title", "event_date"]);
    for (const key of Object.keys(itemRecord)) {
      if (!allowedItemKeys.has(key)) return null;
    }
    const kind = itemRecord.kind;
    if (kind !== "task" && kind !== "event") return null;
    const title = itemRecord.title;
    if (typeof title !== "string") return null;
    const trimmedTitle = title.trim();
    if (trimmedTitle.length < 1 || trimmedTitle.length > 120) return null;
    const eventDate = itemRecord.event_date;
    if (kind === "event") {
      if (typeof eventDate !== "string" || !DATE_RE.test(eventDate)) return null;
    } else {
      if (eventDate !== null && eventDate !== undefined) return null;
    }
    suggestedItem = {
      kind,
      title: trimmedTitle,
      event_date: kind === "event" ? (eventDate as string) : null,
    };
  }

  return { reply_text: trimmedReply, suggested_planning_item: suggestedItem };
}

// ---------------------------------------------------------------------------
// Prompt loading -- spec §7.1. Loaded relative to import.meta.url so the
// versioned template files are packaged with the function.
// ---------------------------------------------------------------------------

let cachedSystemPrompt: string | null = null;
let cachedUserPromptTemplate: string | null = null;

async function loadPrompts(): Promise<{ system: string; userTemplate: string }> {
  if (cachedSystemPrompt === null) {
    cachedSystemPrompt = await Deno.readTextFile(
      new URL("./prompts/v1/system.txt", import.meta.url),
    );
  }
  if (cachedUserPromptTemplate === null) {
    cachedUserPromptTemplate = await Deno.readTextFile(
      new URL("./prompts/v1/user.txt", import.meta.url),
    );
  }
  return { system: cachedSystemPrompt, userTemplate: cachedUserPromptTemplate };
}

export function buildUserPrompt(
  template: string,
  params: {
    assistKind: "ideas" | "nearby";
    contextJson: string;
    targetJson: string;
    userInstruction: string | null;
  },
): string {
  return template
    .replaceAll("{{ASSIST_KIND}}", params.assistKind.toUpperCase())
    .replaceAll("{{CONTEXT_JSON}}", params.contextJson)
    .replaceAll("{{TARGET_JSON}}", params.targetJson)
    .replaceAll("{{USER_INSTRUCTION}}", params.userInstruction ?? "");
}

// ---------------------------------------------------------------------------
// HTTP handler
// ---------------------------------------------------------------------------

export interface AssistDeps {
  callGemini: typeof callGeminiJson;
  searchMapbox: typeof searchMapboxCategory;
  serviceClient?: SupabaseClient;
}

const defaultDeps: AssistDeps = {
  callGemini: callGeminiJson,
  searchMapbox: searchMapboxCategory,
};

export interface AssistUserContext {
  client: SupabaseClient;
  user: { id: string };
}

serve((req) => handleRequest(req, defaultDeps));

/// The real HTTP entry point: authenticates via userScopedClient (real
/// JWT verification against auth.getUser, real RLS-scoped client) and
/// delegates to processAssistRequest. userScopedClient cannot be
/// exercised in this repo's test environment with a real JWT (no Docker/
/// GoTrue here -- see user_scoped_client.test.ts's own note on this),
/// so this thin wrapper is the one piece index.test.ts does NOT call
/// directly; it instead calls processAssistRequest with a test-double
/// {client, user} context built from pg_rls_client.ts's real-Postgres
/// adapter, exactly like ai_context_loader.test.ts already does for
/// Task 2's loader.
export async function handleRequest(req: Request, deps: AssistDeps): Promise<Response> {
  if (req.method === "OPTIONS") return jsonResponse({ ok: true });
  if (req.method !== "POST") {
    return errorResponse(assistantError("INVALID_INPUT"));
  }

  let userScoped;
  try {
    userScoped = await userScopedClient(req);
  } catch {
    return errorResponse(assistantError("UNAUTHENTICATED"));
  }
  return processAssistRequest(req, userScoped, deps);
}

/// Exported for direct testing (see handleRequest's comment above). This
/// is the entire request lifecycle EXCEPT the HTTP-layer JWT
/// verification: input validation, target load, consent, quota
/// reservation (always before any provider call), the Ideas/Nearby
/// branch, and the draft write.
export async function processAssistRequest(
  req: Request,
  userScoped: AssistUserContext,
  deps: AssistDeps,
): Promise<Response> {
  const { client, user } = userScoped;

  const rawBody = await req.json().catch(() => null);
  const validated = validateAssistRequest(rawBody);
  if (!validated.ok) {
    return errorResponse(assistantError("INVALID_INPUT"));
  }
  const request = validated.request;

  if (request.assistKind === "nearby" && request.requesterLocation === null) {
    return errorResponse(assistantError("LOCATION_REQUIRED"));
  }

  // Target load -- BEFORE quota, per spec §4.2/§7.3: a malformed/
  // unauthorized/unsupported target must never cost a reservation.
  const targetResult = await loadAiAssistantTarget(client, user.id, request.messageId);
  if (!targetResult.ok) {
    return errorResponse(assistantError("TARGET_UNAVAILABLE"));
  }
  const target = targetResult.target;

  // Consent -- also before quota/provider call. §10.1: "It sends no
  // chat notice, push notification, message text, or provider request"
  // until both partners have granted.
  const consentResult = await client.rpc("get_ai_processing_consent_status", {
    p_relationship_id: target.relationshipId,
  });
  if (consentResult.error) {
    return errorResponse(assistantError("INTERNAL_ERROR"));
  }
  const consentRow = consentResult.data?.[0];
  if (!consentRow?.both_granted) {
    return errorResponse(assistantError("CONSENT_REQUIRED"));
  }

  // Quota reservation -- MUST happen before the first external provider
  // call (spec §7.3, and this plan's own global constraint). Nothing
  // above this line calls Gemini or Mapbox.
  //
  // Called via the SERVICE-ROLE client, not the user-scoped `client`:
  // reserve_ai_assistant_quota and mark_ai_assistant_usage_outcome are no
  // longer granted to `authenticated` (20260951030000 migration) because
  // a client that could call them directly could replay a request_id for
  // unlimited provider calls, or mark its own usage 'cancelled' to evade
  // the cap. `user.id` is safe to pass as the actor here because it came
  // from requireUser(req)'s server-side auth.getUser verification, never
  // from the request body.
  const service = deps.serviceClient ?? serviceRoleClient();
  const quotaResult = await service.rpc("reserve_ai_assistant_quota", {
    p_actor_id: user.id,
    p_request_id: request.requestId,
    p_relationship_id: target.relationshipId,
    p_mode: "assist",
  });
  if (quotaResult.error) {
    return errorResponse(assistantError("INTERNAL_ERROR"));
  }
  const quotaRow = quotaResult.data?.[0];
  if (quotaRow?.outcome === "rate_limited") {
    return errorResponse(assistantError("RATE_LIMITED", quotaRow.retry_after_seconds ?? null));
  }
  if (quotaRow?.outcome !== "reserved") {
    // Includes 'already_reserved': a replay of a request_id that already
    // holds its lease. The ORIGINAL invocation owns that lease; this one
    // must not call a provider on its behalf.
    return errorResponse(assistantError("INTERNAL_ERROR"));
  }

  try {
    if (request.assistKind === "ideas") {
      return await handleIdeas(client, service, user.id, target, request, deps);
    }
    return await handleNearby(client, service, user.id, target, request, deps);
  } catch (err) {
    console.error("ai_assist_unhandled_error", {
      error: err instanceof Error ? err.message : String(err),
    });
    await service.rpc("mark_ai_assistant_usage_outcome", {
      p_actor_id: user.id,
      p_request_id: request.requestId,
      p_outcome: "provider_failed",
      p_provider_calls: 0,
    });
    return errorResponse(assistantError("INTERNAL_ERROR"));
  }
}

async function handleIdeas(
  client: SupabaseClient,
  service: SupabaseClient,
  userId: string,
  target: LoadedTarget,
  request: AssistRequest,
  deps: AssistDeps,
): Promise<Response> {
  // Claim the provider-start marker before the first external call this
  // request makes (spec §6.2/§8.2.2). `false` means a retry/duplicate of
  // this exact request_id already claimed it -- refuse to dispatch to
  // Gemini again rather than risk a second billed provider call for the
  // same attempt.
  //
  // Unreachable via current entrypoints by design: a replayed request_id
  // is already rejected by reserve_ai_assistant_quota's own
  // already_reserved check before we ever get here, so `canDispatch` is
  // always true on this path today. Do not remove as dead code --
  // required for Plan B's Sessions dispatch, which can reserve once and
  // dispatch more than once across retries.
  const canDispatch = await claimProviderStart(service, userId, request.requestId);
  if (!canDispatch) {
    return errorResponse(assistantError("REQUEST_IN_PROGRESS"));
  }

  const context = await loadBoundedContext(client, target, "assist", userId);
  const { system, userTemplate } = await loadPrompts();
  const userPrompt = buildUserPrompt(userTemplate, {
    assistKind: "ideas",
    contextJson: JSON.stringify(context),
    targetJson: JSON.stringify({
      role: "requester",
      content: target.content,
      createdAt: target.createdAt,
    }),
    userInstruction: request.userInstruction,
  });

  const parsed = await deps.callGemini({
    promptId: "ai_assist_ideas_v1",
    systemPrompt: system,
    userPrompt,
    maxOutputTokens: 600,
  });

  await service.rpc("mark_ai_assistant_usage_outcome", {
    p_actor_id: userId,
    p_request_id: request.requestId,
    p_outcome: parsed ? "succeeded" : "provider_failed",
    p_provider_calls: 1,
  });

  if (!parsed) {
    return errorResponse(assistantError("PROVIDER_UNAVAILABLE"));
  }
  if ((parsed as Record<string, unknown>).unsupported === true) {
    return errorResponse(assistantError("UNSUPPORTED_REQUEST"));
  }

  const validated = validateIdeasOutput(parsed);
  if (!validated) {
    return errorResponse(assistantError("RESULT_UNAVAILABLE"));
  }

  const assistantPayload = {
    schema_version: 1,
    suggested_planning_item: validated.suggested_planning_item,
    sources: [] as PlaceSource[],
  };

  const draftId = crypto.randomUUID();
  const draftResult = await service.rpc("insert_ai_assist_draft", {
    p_id: draftId,
    p_relationship_id: target.relationshipId,
    p_requester_id: userId,
    p_target_message_id: target.messageId,
    p_reply_text: validated.reply_text,
    p_assistant_payload: assistantPayload,
  });
  if (draftResult.error) {
    return errorResponse(assistantError("INTERNAL_ERROR"));
  }
  const draftRow = draftResult.data?.[0];

  return jsonResponse({
    draft_id: draftRow?.id ?? draftId,
    reply_text: validated.reply_text,
    suggested_planning_item: validated.suggested_planning_item,
    sources: [],
    expires_at: draftRow?.expires_at ?? null,
  });
}

async function handleNearby(
  client: SupabaseClient,
  service: SupabaseClient,
  userId: string,
  target: LoadedTarget,
  request: AssistRequest,
  deps: AssistDeps,
): Promise<Response> {
  // One shared claim covers BOTH of Nearby's provider calls (Gemini then
  // Mapbox) -- the marker means "a provider call for this request has
  // started," not "which provider," so it is claimed once here, before
  // the first of the two calls, and never re-claimed before the second.
  //
  // Unreachable via current entrypoints by design: a replayed request_id
  // is already rejected by reserve_ai_assistant_quota's own
  // already_reserved check before we ever get here, so `canDispatch` is
  // always true on this path today. Do not remove as dead code --
  // required for Plan B's Sessions dispatch, which can reserve once and
  // dispatch more than once across retries.
  const canDispatch = await claimProviderStart(service, userId, request.requestId);
  if (!canDispatch) {
    return errorResponse(assistantError("REQUEST_IN_PROGRESS"));
  }

  const context = await loadBoundedContext(client, target, "assist", userId);
  const { system, userTemplate } = await loadPrompts();
  const userPrompt = buildUserPrompt(userTemplate, {
    assistKind: "nearby",
    contextJson: JSON.stringify(context),
    targetJson: JSON.stringify({
      role: "requester",
      content: target.content,
      createdAt: target.createdAt,
    }),
    userInstruction: request.userInstruction,
  });

  // Gemini call #1 of Nearby's two provider calls. Gemini receives ONLY
  // the bounded chat context -- never coordinates (spec §5.2).
  const parsed = await deps.callGemini({
    promptId: "ai_assist_nearby_category_v1",
    systemPrompt: system,
    userPrompt,
    maxOutputTokens: 100,
  });

  if (!parsed) {
    await service.rpc("mark_ai_assistant_usage_outcome", {
      p_actor_id: userId,
      p_request_id: request.requestId,
      p_outcome: "provider_failed",
      p_provider_calls: 1,
    });
    return errorResponse(assistantError("PROVIDER_UNAVAILABLE"));
  }
  if ((parsed as Record<string, unknown>).unsupported === true) {
    await service.rpc("mark_ai_assistant_usage_outcome", {
      p_actor_id: userId,
      p_request_id: request.requestId,
      p_outcome: "rejected",
      p_provider_calls: 1,
    });
    return errorResponse(assistantError("UNSUPPORTED_REQUEST"));
  }

  // This is the exact enforcement point for the Nearby category
  // allowlist (this plan's global constraint): validateNearbyCategoryOutput
  // returns null for ANY value outside the fixed six-token allowlist, and
  // that null unconditionally short-circuits before searchMapboxCategory
  // is ever reached below. No free-text category value can pass through.
  const categoryOutput = validateNearbyCategoryOutput(parsed);
  if (!categoryOutput) {
    await service.rpc("mark_ai_assistant_usage_outcome", {
      p_actor_id: userId,
      p_request_id: request.requestId,
      p_outcome: "rejected",
      p_provider_calls: 1,
    });
    return errorResponse(assistantError("UNSUPPORTED_REQUEST"));
  }

  // Mapbox call (Nearby's second provider call). Mapbox receives ONLY
  // coordinates and the one allowlisted category token -- never message
  // text, user/relationship IDs, or Gemini's own prose (spec §5.2).
  const places = await deps.searchMapbox(categoryOutput.category, {
    latitude: request.requesterLocation!.latitude,
    longitude: request.requesterLocation!.longitude,
  });

  if (places === null) {
    await service.rpc("mark_ai_assistant_usage_outcome", {
      p_actor_id: userId,
      p_request_id: request.requestId,
      p_outcome: "provider_failed",
      p_provider_calls: 2,
    });
    return errorResponse(assistantError("PROVIDER_UNAVAILABLE"));
  }
  if (places.length === 0) {
    await service.rpc("mark_ai_assistant_usage_outcome", {
      p_actor_id: userId,
      p_request_id: request.requestId,
      p_outcome: "succeeded",
      p_provider_calls: 2,
    });
    return errorResponse(assistantError("NO_RESULTS"));
  }

  await service.rpc("mark_ai_assistant_usage_outcome", {
    p_actor_id: userId,
    p_request_id: request.requestId,
    p_outcome: "succeeded",
    p_provider_calls: 2,
  });

  const replyText = buildNearbyReplyText(categoryOutput.category, places);
  const assistantPayload = {
    schema_version: 1,
    suggested_planning_item: null,
    sources: places,
  };

  const draftId = crypto.randomUUID();
  const draftResult = await service.rpc("insert_ai_assist_draft", {
    p_id: draftId,
    p_relationship_id: target.relationshipId,
    p_requester_id: userId,
    p_target_message_id: target.messageId,
    p_reply_text: replyText,
    p_assistant_payload: assistantPayload,
  });
  if (draftResult.error) {
    return errorResponse(assistantError("INTERNAL_ERROR"));
  }
  const draftRow = draftResult.data?.[0];

  return jsonResponse({
    draft_id: draftRow?.id ?? draftId,
    reply_text: replyText,
    suggested_planning_item: null,
    sources: places,
    expires_at: draftRow?.expires_at ?? null,
  });
}

function buildNearbyReplyText(category: NearbyCategory, places: PlaceSource[]): string {
  const names = places.map((p) => p.name).join(", ");
  return `Here are a few ${category} options nearby: ${names}`;
}

function errorResponse(error: AssistantError): Response {
  return jsonResponse({ ...error }, HTTP_STATUS[error.code]);
}

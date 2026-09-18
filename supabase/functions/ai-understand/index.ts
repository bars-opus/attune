// ai-understand: the Understand mode edge function. Spec §4.1, §6, §9,
// §11.
//
// Understand is private, ephemeral reading support: it NEVER persists
// anything, NEVER shares anything, and NEVER touches chat state. This
// file must literally not import the chat repository, any
// message-mutation client, or the Assist share RPC (spec §6.3) -- this
// is enforced by index.test.ts's source-inspection test, not just by
// review. It loads its own trusted context via loadAiAssistantTarget/
// loadBoundedContext (Task 2), reserves quota via
// reserve_ai_assistant_quota BEFORE any provider call (Task 4), and
// returns its result directly with Cache-Control: no-store -- there is
// no draft, no share, no messages insert anywhere in this file.

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";

import { userScopedClient } from "../_shared/user_scoped_client.ts";
import {
  loadAiAssistantTarget,
  loadBoundedContext,
  LoadedTarget,
} from "../_shared/ai_context_loader.ts";
import { callGeminiJson } from "../_shared/gemini_json.ts";

// ---------------------------------------------------------------------------
// Error envelope -- spec §11. Same discriminated union as ai-assist.
// ---------------------------------------------------------------------------

export type AssistantErrorCode =
  | "UNAUTHENTICATED"
  | "CONSENT_REQUIRED"
  | "TARGET_UNAVAILABLE"
  | "INVALID_INPUT"
  | "UNSUPPORTED_REQUEST"
  | "RATE_LIMITED"
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
  RATE_LIMITED: 429,
  RESULT_UNAVAILABLE: 410,
  PROVIDER_UNAVAILABLE: 502,
  INTERNAL_ERROR: 500,
};

// ---------------------------------------------------------------------------
// Request contract -- spec §4.1. Only these fields.
// ---------------------------------------------------------------------------

const ALLOWED_TOP_LEVEL_FIELDS = new Set([
  "request_id",
  "message_id",
  "utc_offset_minutes",
]);

export interface UnderstandRequest {
  requestId: string;
  messageId: string;
  utcOffsetMinutes: number;
}

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function isFiniteInteger(value: unknown): value is number {
  return typeof value === "number" && Number.isFinite(value) &&
    Math.trunc(value) === value;
}

/// Exported for direct unit testing: every check here runs before any
/// DB/provider call.
export function validateUnderstandRequest(
  body: unknown,
): { ok: true; request: UnderstandRequest } | { ok: false } {
  if (!body || typeof body !== "object" || Array.isArray(body)) return { ok: false };
  const record = body as Record<string, unknown>;

  for (const key of Object.keys(record)) {
    if (!ALLOWED_TOP_LEVEL_FIELDS.has(key)) return { ok: false };
  }

  const requestId = record.request_id;
  const messageId = record.message_id;
  const utcOffsetMinutes = record.utc_offset_minutes;

  if (typeof requestId !== "string" || !UUID_RE.test(requestId)) return { ok: false };
  if (typeof messageId !== "string" || !UUID_RE.test(messageId)) return { ok: false };
  if (!isFiniteInteger(utcOffsetMinutes)) return { ok: false };
  if (utcOffsetMinutes < -840 || utcOffsetMinutes > 840) return { ok: false };

  return {
    ok: true,
    request: { requestId, messageId, utcOffsetMinutes },
  };
}

// ---------------------------------------------------------------------------
// Model output contract -- spec §6.2, exactly.
// ---------------------------------------------------------------------------

export type UnderstandModelOutput =
  | {
    status: "ok";
    possible_readings: [string, string] | [string, string, string];
    response_options: [string, string] | [string, string, string];
    confidence: "low" | "medium";
  }
  | {
    status: "cannot_help";
    reason: "insufficient_context" | "unsafe_to_infer" | "unsupported";
  };

const CANNOT_HELP_REASONS = new Set([
  "insufficient_context",
  "unsafe_to_infer",
  "unsupported",
]);

function isStringArrayInRange(
  value: unknown,
  minLen: number,
  maxLen: number,
): value is string[] {
  if (!Array.isArray(value)) return false;
  if (value.length !== 2 && value.length !== 3) return false;
  for (const entry of value) {
    if (typeof entry !== "string") return false;
    const trimmed = entry.trim();
    if (trimmed.length < minLen || trimmed.length > maxLen) return false;
  }
  return true;
}

/// Normalizes text for the context-echo check: lowercase, collapse
/// whitespace, strip punctuation that would otherwise let trivial
/// rephrasing dodge token-sequence matching (spec §9 item 7).
function normalizeForEcho(text: string): string[] {
  return text
    .toLowerCase()
    .normalize("NFKC")
    .replace(/[^\p{L}\p{N}\s]/gu, " ")
    .split(/\s+/)
    .filter((token) => token.length > 0);
}

/// Exported for direct unit testing. True if `candidate` contains any
/// run of 8 or more consecutive tokens that also appears, in the same
/// order, as a substring of the token sequence built from `contextTexts`
/// (spec §9 item 7: "any normalized sequence of eight or more context
/// tokens"). This is a MECHANICAL check -- it catches verbatim/
/// near-verbatim copying, not paraphrase detection in general.
export function containsContextEcho(
  candidate: string,
  contextTexts: string[],
): boolean {
  const candidateTokens = normalizeForEcho(candidate);
  if (candidateTokens.length < 8) return false;
  const contextTokens = normalizeForEcho(contextTexts.join(" "));
  if (contextTokens.length < 8) return false;

  for (let start = 0; start + 8 <= candidateTokens.length; start++) {
    const window = candidateTokens.slice(start, start + 8).join(" ");
    for (let cStart = 0; cStart + 8 <= contextTokens.length; cStart++) {
      const contextWindow = contextTokens.slice(cStart, cStart + 8).join(" ");
      if (window === contextWindow) return true;
    }
  }
  return false;
}

/// Exported for direct unit testing: this is the exact boundary where
/// raw model JSON becomes trusted structured output, AND the point where
/// the mechanical context-echo check (spec §9 item 7) is enforced.
/// `contextTexts` must include the target message plus every surrounding
/// context message actually sent to the model -- never a client-supplied
/// value. Returns null for anything that doesn't match §6.2's
/// UnderstandResponse exactly, or that fails the echo check.
export function validateUnderstandOutput(
  parsed: unknown,
  contextTexts: string[],
): UnderstandModelOutput | null {
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) return null;
  const record = parsed as Record<string, unknown>;
  const status = record.status;

  if (status === "cannot_help") {
    const allowedKeys = new Set(["status", "reason"]);
    for (const key of Object.keys(record)) {
      if (!allowedKeys.has(key)) return null;
    }
    const reason = record.reason;
    if (typeof reason !== "string" || !CANNOT_HELP_REASONS.has(reason)) return null;
    return {
      status: "cannot_help",
      reason: reason as "insufficient_context" | "unsafe_to_infer" | "unsupported",
    };
  }

  if (status !== "ok") return null;
  const allowedKeys = new Set([
    "status",
    "possible_readings",
    "response_options",
    "confidence",
  ]);
  for (const key of Object.keys(record)) {
    if (!allowedKeys.has(key)) return null;
  }

  if (!isStringArrayInRange(record.possible_readings, 1, 300)) return null;
  if (!isStringArrayInRange(record.response_options, 1, 240)) return null;
  const confidence = record.confidence;
  if (confidence !== "low" && confidence !== "medium") return null;

  const possibleReadings = (record.possible_readings as string[]).map((s) => s.trim());
  const responseOptions = (record.response_options as string[]).map((s) => s.trim());

  // Mechanical context-echo rejection (spec §9 item 7): any 8+ token
  // verbatim sequence copied from the bounded context, in either field,
  // fails the whole response -- never a partial pass-through.
  for (const text of [...possibleReadings, ...responseOptions]) {
    if (containsContextEcho(text, contextTexts)) return null;
  }

  return {
    status: "ok",
    possible_readings: possibleReadings as [string, string] | [string, string, string],
    response_options: responseOptions as [string, string] | [string, string, string],
    confidence: confidence as "low" | "medium",
  };
}

// ---------------------------------------------------------------------------
// Prompt loading -- spec §7.1.
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
  params: { contextJson: string; targetJson: string },
): string {
  return template
    .replaceAll("{{CONTEXT_JSON}}", params.contextJson)
    .replaceAll("{{TARGET_JSON}}", params.targetJson);
}

// ---------------------------------------------------------------------------
// HTTP handler
// ---------------------------------------------------------------------------

export interface UnderstandDeps {
  callGemini: typeof callGeminiJson;
}

const defaultDeps: UnderstandDeps = {
  callGemini: callGeminiJson,
};

export interface UnderstandUserContext {
  client: SupabaseClient;
  user: { id: string };
}

serve((req) => handleRequest(req, defaultDeps));

/// The real HTTP entry point: authenticates via userScopedClient and
/// delegates to processUnderstandRequest. See ai-assist/index.ts's
/// handleRequest for why this thin wrapper is the one piece
/// index.test.ts does not call directly (userScopedClient needs a real
/// signed JWT verified against a running GoTrue, not available here).
export async function handleRequest(req: Request, deps: UnderstandDeps): Promise<Response> {
  if (req.method === "OPTIONS") return noStoreJsonResponse({ ok: true });
  if (req.method !== "POST") {
    return errorResponse(assistantError("INVALID_INPUT"));
  }

  let userScoped;
  try {
    userScoped = await userScopedClient(req);
  } catch {
    return errorResponse(assistantError("UNAUTHENTICATED"));
  }
  return processUnderstandRequest(req, userScoped, deps);
}

/// Exported for direct testing. The entire request lifecycle except the
/// HTTP-layer JWT verification: input validation, target load (including
/// the Understand-specific partner-authorship rule), consent, quota
/// reservation (always before any provider call), the Gemini call, the
/// mechanical validators, and the response. There is no draft, no
/// share, no messages/insights/analytics write anywhere in this
/// function -- Understand never persists or shares anything (spec §6.3).
export async function processUnderstandRequest(
  req: Request,
  userScoped: UnderstandUserContext,
  deps: UnderstandDeps,
): Promise<Response> {
  const { client, user } = userScoped;

  const rawBody = await req.json().catch(() => null);
  const validated = validateUnderstandRequest(rawBody);
  if (!validated.ok) {
    return errorResponse(assistantError("INVALID_INPUT"));
  }
  const request = validated.request;

  // Target load -- BEFORE quota, per spec §4.2/§7.3.
  const targetResult = await loadAiAssistantTarget(client, user.id, request.messageId);
  if (!targetResult.ok) {
    return errorResponse(assistantError("TARGET_UNAVAILABLE"));
  }
  const target = targetResult.target;

  // Understand-specific eligibility (spec §3): only available on the
  // OTHER partner's message, never the requester's own. Enforced here
  // independently of any client-side UX gate.
  if (target.senderId === user.id) {
    return errorResponse(assistantError("TARGET_UNAVAILABLE"));
  }

  // Consent -- also before quota/provider call (spec §10.1).
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
  // call. Nothing above this line calls Gemini.
  const quotaResult = await client.rpc("reserve_ai_assistant_quota", {
    p_request_id: request.requestId,
    p_relationship_id: target.relationshipId,
    p_mode: "understand",
  });
  if (quotaResult.error) {
    return errorResponse(assistantError("INTERNAL_ERROR"));
  }
  const quotaRow = quotaResult.data?.[0];
  if (quotaRow?.outcome === "rate_limited") {
    return errorResponse(assistantError("RATE_LIMITED", quotaRow.retry_after_seconds ?? null));
  }
  if (quotaRow?.outcome !== "reserved") {
    return errorResponse(assistantError("INTERNAL_ERROR"));
  }

  try {
    return await handleUnderstand(client, user.id, target, request, deps);
  } catch (err) {
    console.error("ai_understand_unhandled_error", {
      error: err instanceof Error ? err.message : String(err),
    });
    await client.rpc("mark_ai_assistant_usage_outcome", {
      p_request_id: request.requestId,
      p_outcome: "provider_failed",
      p_provider_calls: 0,
    });
    return errorResponse(assistantError("INTERNAL_ERROR"));
  }
}

async function handleUnderstand(
  client: SupabaseClient,
  userId: string,
  target: LoadedTarget,
  request: UnderstandRequest,
  deps: UnderstandDeps,
): Promise<Response> {
  const context = await loadBoundedContext(
    client,
    target,
    "understand",
    userId,
    request.utcOffsetMinutes,
  );
  const { system, userTemplate } = await loadPrompts();
  const userPrompt = buildUserPrompt(userTemplate, {
    contextJson: JSON.stringify(context),
    targetJson: JSON.stringify({
      role: "partner",
      content: target.content,
      createdAt: target.createdAt,
    }),
  });

  const parsed = await deps.callGemini({
    promptId: "ai_understand_v1",
    systemPrompt: system,
    userPrompt,
    maxOutputTokens: 700,
  });

  await client.rpc("mark_ai_assistant_usage_outcome", {
    p_request_id: request.requestId,
    p_outcome: parsed ? "succeeded" : "provider_failed",
    p_provider_calls: 1,
  });

  if (!parsed) {
    return errorResponse(assistantError("PROVIDER_UNAVAILABLE"));
  }

  // The context-echo check needs every text token the model actually
  // saw: the target message plus every surrounding context message
  // (never a client-supplied value -- both come from the trusted loader
  // above).
  const contextTexts = [target.content, ...context.map((c) => c.content)];
  const validated = validateUnderstandOutput(parsed, contextTexts);
  if (!validated) {
    return errorResponse(assistantError("RESULT_UNAVAILABLE"));
  }

  // cannot_help is returned as-is: it carries no field derived from
  // safety_processed_at/safety_error_code/any safety table, so its
  // presence cannot reveal whether the deterministic safety pipeline
  // separately fired for the same target message (spec §6.2).
  return noStoreJsonResponse(validated as unknown as Record<string, unknown>);
}

function errorResponse(error: AssistantError): Response {
  return noStoreJsonResponse({ ...error }, HTTP_STATUS[error.code]);
}

/// Every response from this function -- success or failure -- must never
/// be cached anywhere between here and the client (spec §6.3): "returns
/// Cache-Control: no-store and content-security headers". Deliberately
/// NOT using the shared jsonResponse() helper (attune_auth.ts), which
/// sets no Cache-Control at all -- that helper is shared with functions
/// that have no such requirement, and adding a header there would be an
/// unrelated, unreviewed change to every other caller.
function noStoreJsonResponse(
  body: Record<string, unknown>,
  status = 200,
): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "Content-Type": "application/json",
      "Cache-Control": "no-store",
      "X-Content-Type-Options": "nosniff",
    },
  });
}

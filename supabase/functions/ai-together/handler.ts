// ai-together (plan Phase 7): capture and date ideas. The AI assistant's
// safeguards, in its order: input → flag → membership + consent → quota →
// provider-start claim → model → schema → usage outcome. Saves nothing.
import { callGeminiJson, partnerNamePatterns } from "../_shared/gemini_json.ts";
import {
  buildCapturePrompt,
  parseCaptureDraft,
  validateCaptureRequest,
} from "./capture.ts";
import { buildIdeasPrompt, parseIdeas, validateIdeasRequest } from "./ideas.ts";

type RpcResult = { data: unknown; error: { message: string } | null };
export type RpcClient = {
  rpc: (
    name: string,
    params: Record<string, unknown>,
  ) => PromiseLike<RpcResult>;
};
export type TogetherAiDeps = {
  service: RpcClient;
  callGemini: typeof callGeminiJson;
};

const UUID =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;
const STATUS: Record<string, number> = {
  INVALID_INPUT: 400,
  UNAUTHENTICATED: 401,
  FEATURE_DISABLED: 403,
  CONSENT_REQUIRED: 403,
  UNAVAILABLE: 404,
  RATE_LIMITED: 429,
  PROVIDER_FAILED: 502,
  INTERNAL_ERROR: 500,
};

export function errorResponse(
  code: string,
  extra: Record<string, unknown> = {},
): Response {
  return new Response(JSON.stringify({ code, ...extra }), {
    status: STATUS[code] ?? 500,
    headers: { "Content-Type": "application/json" },
  });
}
/// A boolean SQL function's result, whichever way PostgREST hands it back:
/// bare (`true`) or wrapped (`[{ fn: true }]`). Only a clear true is true.
export function rpcTrue(data: unknown, fn: string): boolean {
  if (data === true) return true;
  const row = Array.isArray(data) ? data[0] : null;
  return !!row && typeof row === "object" &&
    (row as Record<string, unknown>)[fn] === true;
}

const ok = (body: Record<string, unknown>) =>
  new Response(JSON.stringify(body), {
    status: 200,
    headers: { "Content-Type": "application/json" },
  });

export async function processTogetherAi(
  req: Request,
  userScoped: { client: RpcClient; user: { id: string } },
  deps: TogetherAiDeps,
): Promise<Response> {
  const body = await req.json().catch(() => null);
  if (!body || typeof body !== "object" || Array.isArray(body)) {
    return errorResponse("INVALID_INPUT");
  }
  const { action, relationship_id, request_id, ...rest } = body as Record<
    string,
    unknown
  >;
  if (typeof relationship_id !== "string" || !UUID.test(relationship_id)) {
    return errorResponse("INVALID_INPUT");
  }
  if (typeof request_id !== "string" || !UUID.test(request_id)) {
    return errorResponse("INVALID_INPUT");
  }
  const capture = action === "capture" ? validateCaptureRequest(rest) : null;
  const ideas = action === "ideas" ? validateIdeasRequest(rest) : null;
  if (!(capture?.ok || ideas?.ok)) return errorResponse("INVALID_INPUT");

  const flag = await deps.service.rpc("ai_capability_enabled", {
    p_key: "ai_together_enabled",
  });
  if (flag.error) return errorResponse("INTERNAL_ERROR");
  if (!rpcTrue(flag.data, "ai_capability_enabled")) {
    return errorResponse("FEATURE_DISABLED");
  }

  // Membership + both partners' consent, with the caller's own token.
  const status = await userScoped.client.rpc("get_together_ai_status", {
    p_relationship_id: relationship_id,
  });
  if (status.error) return errorResponse("UNAVAILABLE");
  const s = status.data as
    | { available?: boolean; partner_name?: string }
    | null;
  if (!s?.available) return errorResponse("CONSENT_REQUIRED");

  const quota = await deps.service.rpc("reserve_ai_assistant_quota", {
    p_actor_id: userScoped.user.id,
    p_request_id: request_id,
    p_relationship_id: relationship_id,
    p_mode: "assist",
  });
  if (quota.error) return errorResponse("INTERNAL_ERROR");
  const q =
    (quota.data as { outcome?: string; retry_after_seconds?: number }[] | null)
      ?.[0];
  if (q?.outcome === "rate_limited") {
    return errorResponse("RATE_LIMITED", {
      retry_after_seconds: q.retry_after_seconds ?? null,
    });
  }
  if (q?.outcome !== "reserved") return errorResponse("INTERNAL_ERROR");

  const claim = await deps.service.rpc("claim_ai_assistant_provider_start", {
    p_actor_id: userScoped.user.id,
    p_request_id: request_id,
  });
  const claimed = rpcTrue(claim.data, "claim_ai_assistant_provider_start");
  if (claim.error || !claimed) return errorResponse("INTERNAL_ERROR");

  const mark = (outcome: string) =>
    deps.service.rpc("mark_ai_assistant_usage_outcome", {
      p_actor_id: userScoped.user.id,
      p_request_id: request_id,
      p_outcome: outcome,
      p_provider_calls: 1,
    });

  // From the claim on, every path marks the outcome (as ai-assist's catch does).
  try {
    const partner = s.partner_name ?? "";
    if (capture?.ok) {
      const p = buildCapturePrompt({
        text: capture.text,
        nowLocal: capture.nowLocal,
        partnerName: partner,
      });
      const raw = await deps.callGemini({
        promptId: "together_capture_v1",
        systemPrompt: p.system,
        userPrompt: p.user,
        maxOutputTokens: 512,
        runtimeProhibitedPatterns: partnerNamePatterns([partner]),
      });
      const draft = raw ? parseCaptureDraft(raw, capture.nowLocal) : null;
      await mark(draft ? "succeeded" : "provider_failed");
      return draft ? ok({ draft }) : errorResponse("PROVIDER_FAILED");
    }
    const p = buildIdeasPrompt({
      startLocal: (ideas as { startLocal: string }).startLocal,
      endLocal: (ideas as { endLocal: string }).endLocal,
    });
    const raw = await deps.callGemini({
      promptId: "together_ideas_v1",
      systemPrompt: p.system,
      userPrompt: p.user,
      maxOutputTokens: 512,
      runtimeProhibitedPatterns: partnerNamePatterns([partner]),
    });
    const list = raw ? parseIdeas(raw) : null;
    await mark(list ? "succeeded" : "provider_failed");
    return list ? ok({ ideas: list }) : errorResponse("PROVIDER_FAILED");
  } catch (err) {
    console.error("ai_together_provider_error", {
      message: (err as Error).message,
    });
    await mark("provider_failed");
    return errorResponse("PROVIDER_FAILED");
  }
}

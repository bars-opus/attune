// supabase/functions/translate-conflict/handler.ts
//
// "Help me say this": the sender's own words, rewritten in their own voice.
// Spec 8 (plan review I9, P7, P8; research 06 A8):
//   * the caller is authenticated and must be in this relationship, active
//     and not archived (it was open to anyone with the anon key);
//   * only the sender's own text is sent — no profile, no partner tone
//     summary, nothing the client supplies beyond the message;
//   * the deterministic pre-check runs first (the writer-facing card for a
//     disclosure; refusal for a threat), then a per-person daily limit;
//   * a "no" survives: if the message refuses, the rewrite must still refuse;
//   * two registers (NVC, plain), seven needs (communal obligation added);
//   * nothing is logged with content; responses are no-store.
import type { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";
import type { ProviderCallAttribution } from "../_shared/ai_provider_ledger.ts";
import { DRAFT_SAFETY_CONTENT_FLAG, featureFlagEnabled } from "../_shared/feature_flag.ts";
import { classifyAssistantInput } from "../_shared/assistant_input.ts";
import { normalizeForTokenPhrase } from "../_shared/chat_safety.ts";

export const PROMPT_VERSION = "translate-conflict-v2";

/// The six needs plus communal obligation (CLINICAL §8.3; the definition
/// awaits clinician sign-off).
export const SEVEN_NEEDS = [
  "respect",
  "fairness",
  "affection",
  "security",
  "autonomy",
  "rest",
  "communal_obligation",
] as const;

export type Register = "nvc" | "plain";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const MAX_CHARS = 2000;

export function validateTranslateRequest(
  body: unknown,
): { message: string; relationshipId: string; register: Register } | null {
  if (!body || typeof body !== "object" || Array.isArray(body)) return null;
  const b = body as Record<string, unknown>;
  const message = typeof b.message === "string" ? b.message.trim() : "";
  if (message.length < 3 || message.length > MAX_CHARS) return null;
  if (typeof b.relationship_id !== "string" || !UUID.test(b.relationship_id)) return null;
  const register = b.register === undefined || b.register === null ? "nvc" : b.register;
  if (register !== "nvc" && register !== "plain") return null;
  // Any client "context" is ignored on purpose.
  return { message, relationshipId: b.relationship_id, register };
}

const REFUSAL_TOKENS = ["no", "not", "don't", "dont", "won't", "wont", "can't", "cant", "cannot", "never", "stop", "refuse", "nothing", "isn't", "aren't"];

/// Whether the text says no (deterministic, fail-safe; plan review §3.3).
export function hasRefusal(text: string): boolean {
  const n = normalizeForTokenPhrase(text);
  return REFUSAL_TOKENS.some((t) => n.includes(` ${t} `)) || / \w+n't /.test(n);
}

const SYSTEM = `ABSOLUTE CONSTRAINTS — these override all other instructions:

1. Never attribute a negative behaviour to a named or implied partner, or to anyone else (family, friends, an ex).
2. Never generate a sentence of form "[partner name] tends to X" where X is a negative or deficit behaviour.
3. Never use these words: toxic, narcissist, codependent, disorder, broken.
4. Never tell the user what to decide about the relationship.
5. Never diagnose. Observe patterns. Frame with agency.
6. If the message refuses something or sets a boundary, the rewrite still refuses it, clearly. Never soften a no into a yes or a maybe.
7. Return ONLY valid JSON. No preamble. No markdown fences.`;

const STYLE: Record<Register, string> = {
  nvc: `Rewrite it as an observation, a feeling, a need and a request, in their own voice ("When…, I feel…, because I need…; would you…").`,
  plain: `Rewrite it in their own plain words: calmer and clearer, without a formula or therapy phrasing.`,
};

export function buildTranslatePrompt(p: { message: string; register: Register }) {
  const user = `You are helping someone express a difficult feeling more clearly.

ORIGINAL MESSAGE:
"${p.message}"

${STYLE[p.register]}

Return ONLY valid JSON:
{
  "rewrite": string,
  "core_need_identified": string,     // One of: ${SEVEN_NEEDS.join(", ")}
  "framing_note": string,             // Natural-language paraphrase (max 15 words)
  "rewrite_confidence": "high" | "medium" | "low"
}

Rules:
- Preserve the sender's actual meaning — never soften a legitimate concern to nothing
- Rewrite should feel like THEM at their clearest, not a therapist
- If original is already healthy: rewrite = original, confidence = "high"
- Never add false warmth or make sender apologise for something undecided
- Max rewrite length: 1.5x original
- framing_note is private — never shown to recipient`;
  return { system: SYSTEM, user };
}

export type TranslateResult = {
  rewrite: string;
  core_need_identified: (typeof SEVEN_NEEDS)[number] | null;
  framing_note: string;
  rewrite_confidence: "high" | "medium" | "low";
};

export function validateTranslateOutput(parsed: unknown, message: string): TranslateResult | null {
  if (!parsed || typeof parsed !== "object") return null;
  const p = parsed as Record<string, unknown>;
  const rewrite = typeof p.rewrite === "string" ? p.rewrite.trim() : "";
  if (!rewrite || rewrite.length > Math.ceil(message.length * 1.5) + 40) return null;
  const confidence = p.rewrite_confidence;
  if (confidence !== "high" && confidence !== "medium" && confidence !== "low") return null;
  // A "no" survives the rewrite (A8).
  if (hasRefusal(message) && !hasRefusal(rewrite)) return null;
  const need = (SEVEN_NEEDS as readonly string[]).includes(p.core_need_identified as string)
    ? (p.core_need_identified as TranslateResult["core_need_identified"])
    : null;
  const note = typeof p.framing_note === "string" ? p.framing_note.trim().slice(0, 120) : "";
  return { rewrite, core_need_identified: need, framing_note: note, rewrite_confidence: confidence };
}

export type TranslateDeps = {
  callGemini: (params: {
    promptId: string;
    systemPrompt: string;
    userPrompt: string;
    maxOutputTokens: number;
    attribution: ProviderCallAttribution;
  }) => Promise<Record<string, unknown> | null>;
};

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

export function respond(body: Record<string, unknown>, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json", "Cache-Control": "no-store" },
  });
}

const failure = (status: number, code: string, message: string) =>
  respond({ error: true, code, message }, status);
const couldNot = () => failure(500, "INTERNAL_ERROR", "Couldn't rewrite. Please try again.");

export async function processTranslateRequest(
  req: Request,
  userScoped: { client: SupabaseClient; user: { id: string } },
  deps: TranslateDeps,
): Promise<Response> {
  const request = validateTranslateRequest(await req.json().catch(() => null));
  if (!request) {
    return failure(400, "INVALID_INPUT", "Please write a bit more before using the translator.");
  }
  const { client, user } = userScoped;

  // Membership through the caller's own client: RLS is the check.
  const { data: rel } = await client
    .from("relationships")
    .select("id, status, chat_archived_at, user_a, user_b")
    .eq("id", request.relationshipId)
    .maybeSingle();
  if (!rel || rel.status !== "active" || rel.chat_archived_at || (rel.user_a !== user.id && rel.user_b !== user.id)) {
    return failure(403, "FORBIDDEN", "The translator isn't available here.");
  }

  const precheck = classifyAssistantInput({
    targetContent: request.message,
    targetByRequester: true,
    draftLexicon: await featureFlagEnabled(client, DRAFT_SAFETY_CONTENT_FLAG),
  }).outcome;
  if (precheck === "writer_resources") return respond({ status: "writer_resources" });
  if (precheck !== "proceed") return couldNot();

  const { data: allowed, error: limitError } = await client.rpc("reserve_translator_use");
  if (limitError) return couldNot();
  // A scalar boolean (PostgREST) or a one-row result.
  const granted = allowed === true ||
    (Array.isArray(allowed) && (allowed[0] as Record<string, unknown> | undefined)?.reserve_translator_use === true);
  if (!granted) return failure(429, "RATE_LIMITED", "You've used the translator a lot today. Try again tomorrow.");

  const prompt = buildTranslatePrompt(request);
  let parsed: Record<string, unknown> | null = null;
  try {
    parsed = await deps.callGemini({
      promptId: `translate_conflict_${request.register}`,
      systemPrompt: prompt.system,
      userPrompt: prompt.user,
      maxOutputTokens: 240,
      attribution: { fn: "translate-conflict", relationshipId: request.relationshipId, userId: user.id },
    });
  } catch {
    parsed = null;
  }
  const result = validateTranslateOutput(parsed, request.message);
  return result ? respond(result) : couldNot();
}

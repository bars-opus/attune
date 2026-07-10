import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

const CLAUDE_API_KEY = Deno.env.get("CLAUDE_API_KEY");
const CLAUDE_URL = "https://api.anthropic.com/v1/messages";
const MODEL_PROVIDER = "anthropic";
const MODEL_NAME = "claude-sonnet-4-20250514";
const INPUT_SCHEMA_VERSION = "1.1.0";
const PROMPT_VERSION = "1.1.0";
const VALIDATION_VERSION = "1.1.0";
const TIMEOUT_MS = 10000;
const BANNED = /\b(toxic|narcissist|codependent|disorder|broken)\b/i;

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return json({ error: "missing_authorization" }, 401);
    }

    const userClient = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_ANON_KEY")!,
      { global: { headers: { Authorization: authHeader } } },
    );
    const adminClient = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    const {
      data: { user },
      error: userError,
    } = await userClient.auth.getUser();
    if (userError || !user) {
      return json({ error: "authentication_required" }, 401);
    }

    const { journey_id } = await req.json();
    if (!journey_id) {
      return json({ error: "journey_id_required" }, 400);
    }

    const journeyRes = await userClient
      .from("healing_journeys")
      .select("*")
      .eq("id", journey_id)
      .single();
    if (journeyRes.error) {
      return json({ error: "journey_not_found" }, 404);
    }

    const journey = journeyRes.data;
    if (journey.post_mortem_status === "completed" && journey.post_mortem_observation) {
      return json({
        status: "completed",
        observation: journey.post_mortem_observation,
        confidence: journey.post_mortem_confidence ?? "none",
        reflection_prompt: journey.post_mortem_reflection_prompt,
      });
    }

    const evidence = await buildPostMortemEvidence(userClient, adminClient, journey, user.id);
    const inputHash = await sha256(JSON.stringify(evidence));
    const existing = await adminClient
      .from("healing_generation_jobs")
      .select("*")
      .eq("journey_id", journey_id)
      .eq("stage", "post_mortem")
      .eq("input_hash", inputHash)
      .eq("status", "completed")
      .maybeSingle();

    if (existing.data) {
      return json({
        status: "completed",
        observation: existing.data.output_observation,
        confidence: existing.data.output_confidence ?? "none",
        reflection_prompt: existing.data.output_reflection_prompt,
      });
    }

    if (evidence.patterns.length === 0 && evidence.reflection.length === 0) {
      await upsertJob(adminClient, {
        journeyId: journey_id,
        userId: user.id,
        stage: "post_mortem",
        inputHash,
        output: {
          observation: null,
          confidence: "none",
          reflection_prompt: null,
        },
      });
      return json({
        status: "insufficient_evidence",
        observation: null,
        confidence: "none",
        reflection_prompt: null,
      });
    }

    let output = await maybeGenerateWithClaude(evidence, buildPrompt(evidence));
    if (!output) {
      output = buildFallback(evidence);
    }

    validateOutput(output);
    await upsertJob(adminClient, {
      journeyId: journey_id,
      userId: user.id,
      stage: "post_mortem",
      inputHash,
      output,
    });

    return json({ status: "completed", ...output });
  } catch (error) {
    return json(
      { error: error instanceof Error ? error.message : String(error) },
      500,
    );
  }
});

async function buildPostMortemEvidence(userClient: any, adminClient: any, journey: any, userId: string) {
  const reflection = Object.values(journey.reflection_answers ?? {})
    .filter((value): value is string => typeof value === "string" && value.trim().length > 0)
    .map((value) => value.trim());

  const profileRes = await userClient
    .from("psych_profiles")
    .select("attachment_style, communication_style, conflict_style")
    .eq("user_id", userId)
    .maybeSingle();

  let patterns: string[] = [];
  if (journey.relationship_id) {
    const patternRes = await adminClient
      .from("patterns")
      .select("pattern_type, severity")
      .eq("relationship_id", journey.relationship_id)
      .neq("severity", "safety")
      .limit(6);
    patterns = (patternRes.data ?? [])
      .map((row: any) => row.pattern_type)
      .filter((value: unknown): value is string => typeof value === "string");
  }

  return {
    reflection,
    patterns,
    profile: profileRes.data ?? {},
  };
}

function buildPrompt(evidence: any) {
  return [
    "Return only valid JSON.",
    "Write only about the requesting user or a neutral relationship dynamic.",
    "Do not diagnose, blame, or infer the former partner's internal state.",
    "If evidence is insufficient, return observation null, confidence none, and reflection_prompt null.",
    "",
    `PATTERNS: ${JSON.stringify(evidence.patterns)}`,
    `PROFILE: ${JSON.stringify(evidence.profile)}`,
    `REFLECTION: ${JSON.stringify(evidence.reflection)}`,
    "",
    'Schema: {"observation": string | null, "reflection_prompt": string | null}',
  ].join("\n");
}

async function maybeGenerateWithClaude(evidence: any, prompt: string) {
  if (!CLAUDE_API_KEY) {
    return null;
  }

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), TIMEOUT_MS);
  try {
    const response = await fetch(CLAUDE_URL, {
      method: "POST",
      signal: controller.signal,
      headers: {
        "content-type": "application/json",
        "x-api-key": CLAUDE_API_KEY,
        "anthropic-version": "2023-06-01",
      },
      body: JSON.stringify({
        model: MODEL_NAME,
        max_tokens: 180,
        messages: [{ role: "user", content: prompt }],
      }),
    });
    if (!response.ok) {
      return null;
    }
    const payload = await response.json();
    const text = payload?.content?.[0]?.text;
    if (!text || typeof text !== "string") {
      return null;
    }
    const parsed = JSON.parse(text.replace(/```json|```/g, "").trim());
    const confidence = evidence.patterns.length >= 3 ? "high" : evidence.patterns.length >= 2 ? "medium" : "low";
    return {
      observation: parsed.observation ?? null,
      reflection_prompt: parsed.reflection_prompt ?? "What feels familiar about that?",
      confidence,
    };
  } catch {
    return null;
  } finally {
    clearTimeout(timeout);
  }
}

function buildFallback(evidence: any) {
  const profile = evidence.profile ?? {};
  const profileParts = [
    profile.attachment_style?.primary,
    profile.communication_style?.primary_style ?? profile.communication_style?.primary,
    profile.conflict_style?.primary,
  ].filter(Boolean);
  const patternText =
    evidence.patterns.length > 0
      ? `A pattern of ${String(evidence.patterns[0]).replace(/_/g, " ")} may have surfaced when strain rose.`
      : "Your reflections suggest there may be a repeating dynamic worth noticing with care.";
  const observation = profileParts.length > 0
    ? `${patternText} Your ${profileParts.join(", ").replace(/_/g, " ")} tendencies may shape how that feels in relationship stress.`
    : patternText;

  return {
    observation: trimWords(observation, 40),
    confidence: evidence.patterns.length >= 3 ? "high" : evidence.patterns.length >= 2 ? "medium" : "low",
    reflection_prompt: "What part of this feels most familiar?",
  };
}

function validateOutput(output: any) {
  if (!output || typeof output !== "object") {
    throw new Error("invalid_output");
  }
  if (output.observation !== null) {
    if (typeof output.observation !== "string" || BANNED.test(output.observation)) {
      throw new Error("invalid_observation");
    }
  }
  if (output.reflection_prompt !== null && typeof output.reflection_prompt !== "string") {
    throw new Error("invalid_reflection_prompt");
  }
}

async function upsertJob(adminClient: any, options: any) {
  await adminClient.from("healing_generation_jobs").upsert(
    {
      journey_id: options.journeyId,
      user_id: options.userId,
      stage: options.stage,
      status: "completed",
      idempotency_key: `${options.journeyId}:${options.stage}:${options.inputHash}`,
      input_hash: options.inputHash,
      input_schema_version: INPUT_SCHEMA_VERSION,
      prompt_version: PROMPT_VERSION,
      model_provider: MODEL_PROVIDER,
      model_name: MODEL_NAME,
      validation_version: VALIDATION_VERSION,
      attempt_count: 1,
      failure_code: null,
      output_observation: options.output.observation,
      output_confidence: options.output.confidence,
      output_reflection_prompt: options.output.reflection_prompt,
      output_portrait: null,
    },
    { onConflict: "journey_id,stage,input_hash" },
  );
}

function trimWords(text: string, maxWords: number) {
  const words = text.trim().split(/\s+/);
  return words.length <= maxWords ? text.trim() : words.slice(0, maxWords).join(" ");
}

async function sha256(input: string) {
  const bytes = new TextEncoder().encode(input);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "content-type": "application/json" },
  });
}

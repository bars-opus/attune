import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { callGeminiJson } from "../_shared/gemini_json.ts";

// Persisted on each generated row, so it must name the model that
// actually ran rather than the Claude constant this replaced.
const MODEL_NAME = Deno.env.get("GEMINI_MODEL") ?? "gemini-1.5-flash";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

const MODEL_PROVIDER = "anthropic";
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
    if (journey.portrait_status === "completed" && journey.portrait_text) {
      return json({
        status: "completed",
        portrait: journey.portrait_text,
        reflection_prompt: journey.portrait_prompt,
      });
    }

    const evidence = await buildPortraitEvidence(userClient, journey, user.id);
    const inputHash = await sha256(JSON.stringify(evidence));
    const existing = await adminClient
      .from("healing_generation_jobs")
      .select("*")
      .eq("journey_id", journey_id)
      .eq("stage", "portrait")
      .eq("input_hash", inputHash)
      .eq("status", "completed")
      .maybeSingle();

    if (existing.data) {
      return json({
        status: "completed",
        portrait: existing.data.output_portrait,
        reflection_prompt: existing.data.output_reflection_prompt,
      });
    }

    if (
      Object.keys(evidence.profile).length === 0 &&
      evidence.reflection.length === 0 &&
      evidence.insights.length === 0
    ) {
      await upsertJob(adminClient, {
        journeyId: journey_id,
        userId: user.id,
        inputHash,
        output: { portrait: null, reflection_prompt: null },
      });
      return json({
        status: "insufficient_evidence",
        portrait: null,
        reflection_prompt: null,
      });
    }

    let output = await maybeGenerateWithGemini(evidence, buildPrompt(evidence));
    if (!output) {
      output = buildFallback(evidence);
    }

    validateOutput(output);
    await upsertJob(adminClient, {
      journeyId: journey_id,
      userId: user.id,
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

async function buildPortraitEvidence(userClient: any, journey: any, userId: string) {
  const profileRes = await userClient
    .from("psych_profiles")
    .select("attachment_style, communication_style, conflict_style")
    .eq("user_id", userId)
    .maybeSingle();

  const reflection = Object.values(journey.reflection_answers ?? {})
    .filter((value): value is string => typeof value === "string" && value.trim().length > 0)
    .map((value) => value.trim());

  let insights: string[] = [];
  try {
    const insightRes = await userClient
      .from("personal_insights")
      .select("insight_body")
      .eq("user_id", userId)
      .order("created_at", { ascending: false })
      .limit(5);
    insights = (insightRes.data ?? [])
      .map((row: any) => row.insight_body)
      .filter((value: unknown): value is string => typeof value === "string");
  } catch {
    insights = [];
  }

  return {
    profile: profileRes.data ?? {},
    reflection,
    insights,
  };
}

function buildPrompt(evidence: any) {
  return [
    "Return only valid JSON.",
    "Write only about the requesting user.",
    "Use tentative language and do not use fixed labels, diagnosis, or blame.",
    "If evidence is insufficient, return portrait null and reflection_prompt null.",
    "",
    `PROFILE: ${JSON.stringify(evidence.profile)}`,
    `REFLECTION: ${JSON.stringify(evidence.reflection)}`,
    `INSIGHTS: ${JSON.stringify(evidence.insights)}`,
    "",
    'Schema: {"portrait": string | null, "reflection_prompt": string | null}',
  ].join("\n");
}

async function maybeGenerateWithGemini(evidence: any, prompt: string) {
  // The shared helper replaces a hand-rolled Anthropic client here: it
  // owns the request shape, the abort timeout, fenced-JSON extraction and
  // the prohibited-pattern filter. It returns null on any failure, which
  // is the same signal this function already used to fall back.
  const parsed = await callGeminiJson({
    promptId: "healing_portrait",
    systemPrompt:
      "You are a careful, non-judgemental reflection assistant. Reply with JSON only.",
    userPrompt: prompt,
    maxOutputTokens: 220,
  });

  if (!parsed) {
    return null;
  }

  return {
    portrait: parsed.portrait ?? null,
    reflection_prompt: parsed.reflection_prompt ?? "What part of this feels familiar?",
  };
}

function buildFallback(evidence: any) {
  const profile = evidence.profile ?? {};
  const parts = [
    profile.attachment_style?.primary,
    profile.communication_style?.primary_style ?? profile.communication_style?.primary,
    profile.conflict_style?.primary,
  ]
    .filter(Boolean)
    .map((value: string) => String(value).replace(/_/g, " "));

  const portrait = parts.length > 0
    ? `You may bring ${parts.join(", ")} tendencies into close connection. In the data available, your reflections suggest you are noticing these patterns with more honesty and care.`
    : `Your reflections suggest a growing ability to notice how you show up in closeness, stress, and repair without turning that into a fixed label.`;

  return {
    portrait: trimWords(portrait, 80),
    reflection_prompt: "What part of this feels familiar?",
  };
}

function validateOutput(output: any) {
  if (!output || typeof output !== "object") {
    throw new Error("invalid_output");
  }
  if (output.portrait !== null) {
    if (typeof output.portrait !== "string" || BANNED.test(output.portrait)) {
      throw new Error("invalid_portrait");
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
      stage: "portrait",
      status: "completed",
      idempotency_key: `${options.journeyId}:portrait:${options.inputHash}`,
      input_hash: options.inputHash,
      input_schema_version: INPUT_SCHEMA_VERSION,
      prompt_version: PROMPT_VERSION,
      model_provider: MODEL_PROVIDER,
      model_name: MODEL_NAME,
      validation_version: VALIDATION_VERSION,
      attempt_count: 1,
      failure_code: null,
      output_observation: null,
      output_confidence: null,
      output_reflection_prompt: options.output.reflection_prompt,
      output_portrait: options.output.portrait,
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

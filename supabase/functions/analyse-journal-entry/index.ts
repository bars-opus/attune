// supabase/functions/analyse-journal-entry/index.ts
import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { callGeminiJson, STATIC_PROHIBITED_PATTERNS } from "../_shared/gemini_json.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

const MODEL_PROVIDER = "google";
const MODEL_NAME = Deno.env.get("GEMINI_MODEL") ?? "gemini-1.5-flash";
const PROMPT_VERSION = "1.0.0";
const MIN_WORDS_FOR_ANALYSIS = 15;
const MIN_ENTRIES_FOR_PATTERNS = 3;
const MAX_ENTRIES_FOR_PATTERNS = 20;

const RUNTIME_PATTERNS = [
  /you should (tell|confront|ask|leave)/i,
];

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

    const body = await req.json();
    if (body.action === "get_patterns") {
      return await handleGetPatterns(adminClient, user.id);
    }
    if (body.action === "analyse_entry") {
      return await handleAnalyseEntry(userClient, adminClient, user.id, body.entry_id);
    }
    return json({ error: "unknown_action" }, 400);
  } catch (error) {
    return json(
      { error: error instanceof Error ? error.message : String(error) },
      500,
    );
  }
});

async function handleAnalyseEntry(
  userClient: any,
  adminClient: any,
  userId: string,
  entryId: string,
) {
  if (!entryId) {
    return json({ error: "entry_id_required" }, 400);
  }

  const entryRes = await userClient
    .from("reflection_journal_entries")
    .select("id, content")
    .eq("id", entryId)
    .is("deleted_at", null)
    .single();
  if (entryRes.error || !entryRes.data) {
    return json({ error: "entry_not_found" }, 404);
  }

  const content: string = entryRes.data.content;
  const inputHash = await sha256(content);

  const existing = await adminClient
    .from("reflection_journal_analysis")
    .select("status, tone, observation, confidence")
    .eq("entry_id", entryId)
    .eq("input_hash", inputHash)
    .eq("status", "completed")
    .maybeSingle();
  if (existing.data) {
    return json({ status: "completed", ...existing.data });
  }

  const wordCount = content.trim().split(/\s+/).filter(Boolean).length;
  if (wordCount < MIN_WORDS_FOR_ANALYSIS) {
    await adminClient.rpc("upsert_journal_analysis", {
      p_entry_id: entryId,
      p_user_id: userId,
      p_status: "insufficient_evidence",
      p_tone: null,
      p_observation: null,
      p_confidence: "none",
      p_input_hash: inputHash,
      p_prompt_version: PROMPT_VERSION,
      p_model_provider: MODEL_PROVIDER,
      p_model_name: MODEL_NAME,
    });
    return json({
      status: "insufficient_evidence",
      tone: null,
      observation: null,
      confidence: "none",
    });
  }

  let output = await maybeGenerate(content);
  if (!output) {
    output = buildFallback();
  }

  validateOutput(output);
  await adminClient.rpc("upsert_journal_analysis", {
    p_entry_id: entryId,
    p_user_id: userId,
    p_status: "completed",
    p_tone: output.tone,
    p_observation: output.observation,
    p_confidence: output.confidence,
    p_input_hash: inputHash,
    p_prompt_version: PROMPT_VERSION,
    p_model_provider: MODEL_PROVIDER,
    p_model_name: MODEL_NAME,
  });

  return json({ status: "completed", ...output });
}

async function handleGetPatterns(adminClient: any, userId: string) {
  const rows = await adminClient
    .from("reflection_journal_analysis")
    .select("observation, tone, created_at")
    .eq("user_id", userId)
    .eq("status", "completed")
    .order("created_at", { ascending: false })
    .limit(MAX_ENTRIES_FOR_PATTERNS);

  const analyses = rows.data ?? [];
  if (analyses.length < MIN_ENTRIES_FOR_PATTERNS) {
    return json({
      status: "insufficient_evidence",
      summary: null,
      entry_count: analyses.length,
    });
  }

  const prompt = buildPatternsPrompt(analyses);
  const result = await callGeminiJson({
    promptId: "journal_patterns",
    systemPrompt: patternsSystemPrompt(),
    userPrompt: prompt,
    maxOutputTokens: 220,
    runtimeProhibitedPatterns: RUNTIME_PATTERNS,
  });

  const summary = typeof result?.summary === "string"
    ? result.summary
    : `Across ${analyses.length} entries, a few recurring tones and themes have shown up in what you've written.`;

  return json({
    status: "completed",
    summary,
    entry_count: analyses.length,
  });
}

function globalConstraintHeader() {
  return [
    "Return ONLY valid JSON, no markdown fences, no commentary.",
    "Never use the words: toxic, narcissist, codependent, disorder, broken.",
    "Never use the word 'violation'.",
    "Never tell the user what to decide about their relationship or their life.",
    "Never attribute always/never behavior to a partner.",
    "Never suggest what the user should say, ask, tell, or confront someone with — this is a private diary with no addressee.",
    "Every claim must be sourced to the user's own words — never invent detail.",
  ].join(" ");
}

function analysisSystemPrompt() {
  return [
    globalConstraintHeader(),
    "You are a wise, attentive friend reading a private journal entry — never clinical, never therapy-coded.",
    "Analyse using only Observation, Feeling, and Need (NVC). Do not include a Request component directed at anyone else.",
    "If you offer a closing thought, it must be inward-facing (what might help the writer, not what they should say to someone).",
    "Confidence must never be 'high' for anything NVC-derived — cap at 'medium'.",
    'Schema: {"tone": one of "reflective"|"charged"|"settled"|"searching"|"hopeful"|"heavy", "observation": string, "confidence": "medium"|"low"}',
  ].join(" ");
}

function patternsSystemPrompt() {
  return [
    globalConstraintHeader(),
    "You are summarizing recurring themes across several private journal entries for the person who wrote them, in a warm, sourced, dated way.",
    'Schema: {"summary": string}',
  ].join(" ");
}

function buildAnalysisPrompt(content: string) {
  return `ENTRY:\n${content}`;
}

function buildPatternsPrompt(analyses: Array<{ observation: string; tone: string | null; created_at: string }>) {
  return `PAST ANALYSES (most recent first):\n${JSON.stringify(analyses)}`;
}

async function maybeGenerate(content: string) {
  const result = await callGeminiJson({
    promptId: "journal_entry_analysis",
    systemPrompt: analysisSystemPrompt(),
    userPrompt: buildAnalysisPrompt(content),
    maxOutputTokens: 220,
    runtimeProhibitedPatterns: RUNTIME_PATTERNS,
  });
  if (!result) return null;

  const validTones = ["reflective", "charged", "settled", "searching", "hopeful", "heavy"];
  const tone = typeof result.tone === "string" && validTones.includes(result.tone)
    ? result.tone
    : "reflective";
  const confidence = result.confidence === "low" ? "low" : "medium";
  const observation = typeof result.observation === "string" ? result.observation : null;
  if (!observation) return null;

  return { tone, observation, confidence };
}

function buildFallback() {
  return {
    tone: "reflective" as const,
    observation:
      "Thank you for writing this down. Sometimes just putting words to something is the reflection itself.",
    confidence: "low" as const,
  };
}

function validateOutput(output: { tone: string; observation: string; confidence: string }) {
  if (!output || typeof output !== "object") {
    throw new Error("invalid_output");
  }
  const outputText = JSON.stringify(output);
  for (const pattern of [...STATIC_PROHIBITED_PATTERNS, ...RUNTIME_PATTERNS]) {
    if (pattern.test(outputText)) {
      throw new Error("prohibited_pattern_in_output");
    }
  }
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

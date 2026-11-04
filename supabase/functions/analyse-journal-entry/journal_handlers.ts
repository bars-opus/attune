// supabase/functions/analyse-journal-entry/journal_handlers.ts
//
// The two actions of analyse-journal-entry, moved out of index.ts unchanged
// except for Spec 1 W9c (spec 4.5; D12; research 10 F-7): the hard-coded
// self_disclosure check runs FIRST, before the cache and before any provider
// call. Self-harm (the reviewed sessions corpus) always runs; the [DRAFT]
// victimisation list only where private_safety_check is on (review A-4). A
// match answers {status: 'support_offered'}: no provider call, no cache read,
// nothing about the match stored; the entry's earlier reflection (an AI note
// about older words) is removed so none sits beside it (plan P-23); one
// support_card_shown:journal count. get_patterns leaves matched entries out,
// and answers support_offered without a provider call when the newest entry
// matches. Nothing here depends on the model: the check is deterministic.
// The provider, the output filter (index.ts keeps RUNTIME_PATTERNS, where
// the permanent-constraints test reads it), the flag read and the count are
// injected (JournalDeps), so the tests can spy on them.
//
// Fix round 1 (batch-7-review.md; coordinator ruling, a spec amendment for
// the W9 final): the check also runs BEFORE the W1c journal_ai_insights
// pause, in both actions, because support for someone in crisis must not
// depend on an AI flag (the check calls no provider). A match while paused
// still removes the old reflection and answers support_offered; no match
// while paused answers paused, as W1c did, before the cache or any provider.
// The text is folded first (typographic apostrophes and quotes, invisible
// characters), and the journal's pending-review self-harm list
// (journal_self_harm_pending.ts) runs next to the reviewed corpus.
import { STATIC_PROHIBITED_PATTERNS } from "../_shared/gemini_json.ts";
import { detectSelfDisclosure } from "../_shared/self_disclosure.ts";
import { PAUSED_BODY } from "./journal_pause.ts";
import { matchesPendingSelfHarm } from "./journal_self_harm_pending.ts";

export const corsHeaders = {
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

/// The whole answer to a match, for either action (spec 4.5: exactly this
/// body). For analyse_entry it also means: hide any reflection the app holds
/// for the entry it asked about (the entry_id it sent; plan P-23, Task 10).
/// For get_patterns: show the card instead of any summary.
export const SUPPORT_OFFERED_BODY = { status: "support_offered" } as const;
/// Counts every offer (each matched analyse_entry call, each Patterns open
/// while the newest entry matches), not each card the app draws (review M-5).
export const SUPPORT_CARD_METRIC = "support_card_shown:journal";
/// P-23's delete of the old reflection: supabase-js answers {error} rather
/// than throwing, so the answer is checked and the delete tried at most this
/// many times; support is offered either way (review I-1).
export const DELETE_ATTEMPTS = 3;

export type JournalModel = (params: {
  promptId: string;
  systemPrompt: string;
  userPrompt: string;
  maxOutputTokens: number;
  runtimeProhibitedPatterns?: RegExp[];
  attribution: { fn: string; userId: string };
}) => Promise<Record<string, unknown> | null>;

export interface JournalDeps {
  /// callGeminiJson in production.
  model: JournalModel;
  /// index.ts's output filter (it stays defined there, where
  /// test/architecture/permanent_constraints_test.dart reads it).
  runtimePatterns: RegExp[];
  /// journal_ai_insights off (W1c).
  insightsPaused: () => Promise<boolean>;
  /// private_safety_check, read the way ai-assist reads it (off on doubt).
  victimisationOn: () => Promise<boolean>;
  /// bump_metric_server; never throws, never blocks the answer.
  bumpMetric: (key: string) => Promise<void>;
}

type EntryText = { title?: string | null; content?: string | null };

/// private_safety_check, or null when the read threw. featureFlagEnabled
/// already answers off on any error it sees (review A-4); a throw that gets
/// past it is unknown, and unknown is treated as a match (fail safe).
async function readVictimisation(deps: JournalDeps): Promise<boolean | null> {
  try {
    return (await deps.victimisationOn()) === true;
  } catch {
    return null;
  }
}

/// journal_ai_insights off, or unreadable (W1c: any doubt is paused).
async function insightsPaused(deps: JournalDeps): Promise<boolean> {
  try {
    return (await deps.insightsPaused()) !== false;
  } catch {
    return true;
  }
}

/// The W1c answer while paused, else [answer] (the error paths W1c answered
/// paused before the check moved ahead of the pause).
async function pausedOr(deps: JournalDeps, answer: Response): Promise<Response> {
  return (await insightsPaused(deps)) ? json(PAUSED_BODY) : answer;
}

// Review I-2: typographic apostrophes (iOS smart punctuation, pasted text)
// and quotes become ASCII, so "don\u2019t" matches the corpus's "don't".
const APOSTROPHES = /[\u2018\u2019\u201B\u02BB\u02BC\uFF07\u0060\u00B4\u2032]/g;
const QUOTES = /[\u201C\u201D\u201E\u201F\u2033\uFF02\u00AB\u00BB]/g;
// Review M-1: invisible characters. The shared normaliser drops some of
// them (joining "kill\u200Bmyself" into one word); the text is checked both
// with them removed and with them as spaces.
const INVISIBLE = /[\u200B-\u200D\u2060\uFEFF\u00AD]/g;

/// Typographic apostrophes to ', typographic double quotes to ".
export function foldTypography(text: string): string {
  return text.replace(APOSTROPHES, "'").replace(QUOTES, '"');
}

function pendingSelfHarm(text: string): boolean {
  return matchesPendingSelfHarm(text);
}

/// True for a match, and for anything that stops the check from running
/// (an unknown flag, a detector that throws): the writer is offered support
/// and nothing reaches the provider.
function disclosed(entry: EntryText, victimisation: boolean | null): boolean {
  if (victimisation === null) return true;
  try {
    const folded = foldTypography(`${entry.title ?? ""}\n${entry.content ?? ""}`);
    for (const text of [folded.replace(INVISIBLE, ""), folded.replace(INVISIBLE, " ")]) {
      if (detectSelfDisclosure(text, { victimisation }) !== null) return true;
      if (pendingSelfHarm(text)) return true;
    }
    return false;
  } catch {
    return true;
  }
}

// deno-lint-ignore no-explicit-any
async function removeOldReflection(adminClient: any, userId: string, entryId: string) {
  // Plan P-23: every reflection row for the entry, whenever it was written
  // (no date or hash filter), so reflections from before W9c go too.
  for (let attempt = 0; attempt < DELETE_ATTEMPTS; attempt++) {
    try {
      const { error } = await adminClient
        .from("reflection_journal_analysis")
        .delete()
        .eq("entry_id", entryId)
        .eq("user_id", userId);
      if (!error) return;
    } catch {
      // Tried again, then support anyway.
    }
  }
}

async function offerSupport(deps: JournalDeps) {
  try {
    await deps.bumpMetric(SUPPORT_CARD_METRIC);
  } catch {
    // A count never changes the answer.
  }
  return json(SUPPORT_OFFERED_BODY);
}

export async function handleAnalyseEntry(
  // deno-lint-ignore no-explicit-any
  userClient: any,
  // deno-lint-ignore no-explicit-any
  adminClient: any,
  userId: string,
  entryId: string,
  deps: JournalDeps,
) {
  if (!entryId) {
    return await pausedOr(deps, json({ error: "entry_id_required" }, 400));
  }

  const entryRes = await userClient
    .from("reflection_journal_entries")
    .select("id, title, content")
    .eq("id", entryId)
    .is("deleted_at", null)
    .single();
  if (entryRes.error || !entryRes.data) {
    return await pausedOr(deps, json({ error: "entry_not_found" }, 404));
  }

  // Spec 1 W9c: the crisis check, first (before the W1c pause too).
  if (disclosed(entryRes.data, await readVictimisation(deps))) {
    await removeOldReflection(adminClient, userId, entryId);
    return await offerSupport(deps);
  }
  if (await insightsPaused(deps)) {
    return json(PAUSED_BODY);
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

  let output = await maybeGenerate(deps, content, userId);
  if (!output) {
    output = buildFallback();
  }

  validateOutput(output, deps.runtimePatterns);
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

export async function handleGetPatterns(
  // deno-lint-ignore no-explicit-any
  adminClient: any,
  userId: string,
  deps: JournalDeps,
) {
  // Spec 1 W9c: the crisis check, first. Unreadable entries: no provider
  // call (fail closed).
  const victimisation = await readVictimisation(deps);
  const newest = await adminClient
    .from("reflection_journal_entries")
    .select("id, title, content")
    .eq("user_id", userId)
    .is("deleted_at", null)
    .order("created_at", { ascending: false })
    .limit(1)
    .maybeSingle();
  if (newest.error) {
    return await pausedOr(deps, json({ error: "journal_unavailable" }, 503));
  }
  if (newest.data && disclosed(newest.data, victimisation)) {
    return await offerSupport(deps);
  }
  if (await insightsPaused(deps)) {
    return json(PAUSED_BODY);
  }

  const rows = await adminClient
    .from("reflection_journal_analysis")
    .select("entry_id, observation, tone, created_at")
    .eq("user_id", userId)
    .eq("status", "completed")
    .order("created_at", { ascending: false })
    .limit(MAX_ENTRIES_FOR_PATTERNS);

  const found: Array<{ entry_id: string; observation: string; tone: string | null; created_at: string }> =
    rows.data ?? [];
  const ids = [...new Set(found.map((a) => a.entry_id))];
  const matched = new Set<string>();
  // An analysis whose entry was not read back cannot be checked: left out.
  const seen = new Set<string>();
  if (ids.length > 0) {
    const entries = await adminClient
      .from("reflection_journal_entries")
      .select("id, title, content")
      .eq("user_id", userId)
      .in("id", ids);
    if (entries.error) {
      return json({ error: "journal_unavailable" }, 503);
    }
    for (const e of entries.data ?? []) {
      seen.add(e.id);
      if (disclosed(e, victimisation)) matched.add(e.id);
    }
  }
  const analyses = found
    .filter((a) => seen.has(a.entry_id))
    .filter((a) => !matched.has(a.entry_id))
    .map(({ observation, tone, created_at }) => ({ observation, tone, created_at }));
  if (analyses.length < MIN_ENTRIES_FOR_PATTERNS) {
    return json({
      status: "insufficient_evidence",
      summary: null,
      entry_count: analyses.length,
    });
  }

  const prompt = buildPatternsPrompt(analyses);
  const result = await deps.model({
    promptId: "journal_patterns",
    attribution: { fn: "analyse-journal-entry", userId },
    systemPrompt: patternsSystemPrompt(),
    userPrompt: prompt,
    maxOutputTokens: 220,
    runtimeProhibitedPatterns: deps.runtimePatterns,
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

async function maybeGenerate(deps: JournalDeps, content: string, userId: string) {
  const result = await deps.model({
    promptId: "journal_entry_analysis",
    attribution: { fn: "analyse-journal-entry", userId },
    systemPrompt: analysisSystemPrompt(),
    userPrompt: buildAnalysisPrompt(content),
    maxOutputTokens: 220,
    runtimeProhibitedPatterns: deps.runtimePatterns,
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

function validateOutput(
  output: { tone: string; observation: string; confidence: string },
  runtimePatterns: RegExp[],
) {
  if (!output || typeof output !== "object") {
    throw new Error("invalid_output");
  }
  const outputText = JSON.stringify(output);
  for (const pattern of [...STATIC_PROHIBITED_PATTERNS, ...runtimePatterns]) {
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

export function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "content-type": "application/json" },
  });
}

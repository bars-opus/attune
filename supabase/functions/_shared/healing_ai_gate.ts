// supabase/functions/_shared/healing_ai_gate.ts
//
// Spec 1 W9e (owner approval O2; spec 8 W9e): Healing's AI pause, with the
// writer-facing crisis check first, W9c's pattern. generate-healing-portrait
// and generate-healing-post-mortem send a person's breakup reflections to a
// provider; before anything else, after loading the caller's own journey:
//   1. the crisis check (writerTextDiscloses) on every string in the
//      journey's reflection_answers. A match, an unreadable reflection, a
//      private_safety_check read that throws or a detector that throws
//      answers {status: 'support_offered'}: no provider call, no cache
//      read, nothing about the match stored, and the stage's earlier AI
//      output removed (the cached jobs and, when the journey holds it, the
//      saved text), so none is shown beside these words;
//   2. only then the pause: healing_ai_insights off, unreadable or missing
//      answers {status: 'paused'} before any cache read or provider call.
// Support never waits for the AI flag (W9 batch-7 ruling R-2). Nothing here
// depends on a model.
import { writerTextDiscloses } from "./writer_crisis_check.ts";

export const HEALING_AI_FLAG = "healing_ai_insights";

export const PAUSED_BODY = { status: "paused" } as const;

/// The whole answer to a match (W9c's body). The app hides any AI output it
/// holds for the journey and stage it asked about, and shows the card.
export const SUPPORT_OFFERED_BODY = { status: "support_offered" } as const;

/// The stale-output delete: supabase-js answers {error} rather than
/// throwing, so the answer is checked and the delete tried at most this
/// many times; support is offered either way (W9 batch-7 review I-1).
export const DELETE_ATTEMPTS = 3;

/// Deepest nesting read in reflection_answers; anything deeper is
/// unreadable, and unreadable is treated as a match.
export const MAX_ANSWER_DEPTH = 8;

export type HealingStage = "portrait" | "post_mortem";

export type HealingModel = (params: {
  promptId: string;
  systemPrompt: string;
  userPrompt: string;
  maxOutputTokens: number;
  attribution: { fn: string; userId: string };
}) => Promise<Record<string, unknown> | null>;

export interface HealingDeps {
  /// callGeminiJson in production.
  model: HealingModel;
  /// healing_ai_insights off (any doubt is paused).
  aiPaused: () => Promise<boolean>;
  /// private_safety_check, read the way ai-assist reads it (off on doubt).
  victimisationOn: () => Promise<boolean>;
}

/// The journey's saved AI text for each stage: cleared on a match. The
/// person's own words (portrait_reflection), the status and the completed
/// time are kept, so the journey's progress is unchanged.
const SAVED_OUTPUT: Record<HealingStage, string[]> = {
  portrait: ["portrait_text", "portrait_prompt"],
  post_mortem: ["post_mortem_observation", "post_mortem_confidence", "post_mortem_reflection_prompt"],
};

/// Every string in reflection_answers, joined; "" for none; null when it
/// cannot be read (not an object, or nested past MAX_ANSWER_DEPTH).
export function reflectionTextOf(answers: unknown): string | null {
  if (answers === null || answers === undefined) return "";
  if (typeof answers !== "object" || Array.isArray(answers)) return null;
  const parts: string[] = [];
  const walk = (value: unknown, depth: number): boolean => {
    if (typeof value === "string") {
      parts.push(value);
      return true;
    }
    if (value === null || typeof value === "number" || typeof value === "boolean") return true;
    if (typeof value !== "object" || depth >= MAX_ANSWER_DEPTH) return false;
    const items = Array.isArray(value) ? value : Object.values(value as Record<string, unknown>);
    return items.every((item) => walk(item, depth + 1));
  };
  return walk(answers, 0) ? parts.join("\n") : null;
}

/// private_safety_check, or null when the read threw (unknown: a match).
async function readVictimisation(deps: HealingDeps): Promise<boolean | null> {
  try {
    return (await deps.victimisationOn()) === true;
  } catch {
    return null;
  }
}

/// healing_ai_insights off, or unreadable.
async function aiPaused(deps: HealingDeps): Promise<boolean> {
  try {
    return (await deps.aiPaused()) !== false;
  } catch {
    return true;
  }
}

// deno-lint-ignore no-explicit-any
async function removeStaleOutput(adminClient: any, userId: string, journey: any, stage: HealingStage) {
  const columns = SAVED_OUTPUT[stage];
  const saved = columns.some((c) => journey?.[c] !== null && journey?.[c] !== undefined);
  for (let attempt = 0; attempt < DELETE_ATTEMPTS; attempt++) {
    try {
      // Every cached job for the stage, whatever text it was written for.
      const jobs = await adminClient
        .from("healing_generation_jobs")
        .delete()
        .eq("journey_id", journey.id)
        .eq("user_id", userId)
        .eq("stage", stage);
      if (jobs.error) continue;
      if (saved) {
        const row = await adminClient
          .from("healing_journeys")
          .update(Object.fromEntries(columns.map((c) => [c, null])))
          .eq("id", journey.id)
          .eq("user_id", userId);
        if (row.error) continue;
      }
      return;
    } catch {
      // Tried again, then support anyway.
    }
  }
}

/// The W9e gate: the body to answer at once (support_offered or paused),
/// or null to go on as before. [journey] is the caller's own row, read
/// through the caller's client (RLS).
export async function healingGate(
  // deno-lint-ignore no-explicit-any
  adminClient: any,
  userId: string,
  // deno-lint-ignore no-explicit-any
  journey: any,
  stage: HealingStage,
  deps: HealingDeps,
): Promise<Record<string, string> | null> {
  const victimisation = await readVictimisation(deps);
  const text = reflectionTextOf(journey?.reflection_answers);
  if (text === null || writerTextDiscloses(text, victimisation)) {
    await removeStaleOutput(adminClient, userId, journey, stage);
    return { ...SUPPORT_OFFERED_BODY };
  }
  if (await aiPaused(deps)) {
    return { ...PAUSED_BODY };
  }
  return null;
}

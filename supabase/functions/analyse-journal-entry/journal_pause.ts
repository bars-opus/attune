// supabase/functions/analyse-journal-entry/journal_pause.ts
//
// Spec 1 W1c (D12; research 10 F-7): Journal insights are paused until the
// hard-coded self_disclosure check runs before any provider call (S1 W9c).
// The flag journal_ai_insights is off by default; off, unreadable or missing
// all mean paused, for both actions: no Gemini call, nothing read from or
// written to reflection_journal_analysis.
import { featureFlagEnabled } from "../_shared/feature_flag.ts";

export const JOURNAL_AI_FLAG = "journal_ai_insights";

export const PAUSED_BODY = { status: "paused" } as const;

// deno-lint-ignore no-explicit-any
export async function journalInsightsPaused(adminClient: any): Promise<boolean> {
  return !(await featureFlagEnabled(adminClient, JOURNAL_AI_FLAG));
}

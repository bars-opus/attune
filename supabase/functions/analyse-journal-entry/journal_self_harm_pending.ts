// supabase/functions/analyse-journal-entry/journal_self_harm_pending.ts
//
// Spec 1 W9e: the pending-review self-harm list moved, unchanged, to
// _shared/self_harm_pending.ts, so the Journal and Healing share one list
// (never a copy). Re-exported here so every journal import still works.
export { JOURNAL_SELF_HARM_PENDING, matchesPendingSelfHarm } from "../_shared/self_harm_pending.ts";

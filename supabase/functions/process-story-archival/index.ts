// supabase/functions/process-story-archival/index.ts
//
// The story archival worker (STORIES.md §4.4): every 5 minutes while work
// waits (20261024100600), service role only. Downsizes expired photo
// stories to a 1600 px long edge, checks each rendition before the swap,
// and logs one line of counts per run. The logic is in archival.ts.
import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";
import { jsonResponse, requireEnv, requireServiceRole } from "../_shared/attune_auth.ts";
import { ARCHIVAL_DEFAULTS, runArchival, timedFetch } from "./archival.ts";

serve((req) => {
  if (req.method === "OPTIONS") return jsonResponse({ ok: true });
  try {
    requireServiceRole(req);
  } catch {
    return jsonResponse({ success: false, error: "Forbidden" }, 403);
  }
  const supabase = createClient(requireEnv("SUPABASE_URL"), requireEnv("SUPABASE_SERVICE_ROLE_KEY"), {
    auth: { persistSession: false, autoRefreshToken: false },
    // 20 s per Storage or RPC call (06 #23).
    global: { fetch: timedFetch(20_000) },
  });
  const work = runArchival(supabase, ARCHIVAL_DEFAULTS).catch((error) =>
    console.error(JSON.stringify({ fn: "process-story-archival", error: error instanceof Error ? error.message : typeof error }))
  );
  // pg_net's call returns at once; the run continues in the background, as
  // build-data-exports does.
  // deno-lint-ignore no-explicit-any
  const runtime = (globalThis as any).EdgeRuntime;
  if (runtime?.waitUntil) {
    runtime.waitUntil(work);
    return jsonResponse({ accepted: true }, 202);
  }
  return work.then(() => jsonResponse({ ok: true }));
});

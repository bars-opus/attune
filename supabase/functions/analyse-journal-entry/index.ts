// supabase/functions/analyse-journal-entry/index.ts
import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { callGeminiJson } from "../_shared/gemini_json.ts";
import { DRAFT_SAFETY_CONTENT_FLAG, featureFlagEnabled } from "../_shared/feature_flag.ts";
import { journalInsightsPaused, PAUSED_BODY } from "./journal_pause.ts";
import { corsHeaders, handleAnalyseEntry, handleGetPatterns, type JournalDeps, json } from "./journal_handlers.ts";

const RUNTIME_PATTERNS = [
  /you should (tell|confront|ask|leave)/i,
  // §11 #8: permanently banned from all AI outputs. The prompt already
  // asks for this, but a prompt is a request -- the model can still emit
  // one. This summary is returned straight to the caller, so it needs the
  // guarantee rather than the request. A match makes callGeminiJson return
  // null and the caller falls back to fixed boilerplate, so filtering here
  // fails closed.
  /\b(toxic|narcissist|codependent|disorder|broken)\b/i,
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
    // Spec 1 W9c: the provider, the W1c pause, the draft-list flag and the
    // count, injected so journal_handlers.test.ts can spy on them.
    const deps: JournalDeps = {
      model: callGeminiJson,
      runtimePatterns: RUNTIME_PATTERNS,
      // Spec 1 W1c (D12): off means no provider call for either action. Fix
      // round 1 ruling (spec amendment): each action runs the deterministic
      // crisis check first and only then answers paused, so support never
      // depends on this AI flag.
      insightsPaused: () => journalInsightsPaused(adminClient),
      // Same helper, key and default-off rule as ai-assist; read through the
      // service-role client here (ai-assist uses the caller's), deliberately:
      // it is at least as reliable (review M-3).
      victimisationOn: () => featureFlagEnabled(adminClient, DRAFT_SAFETY_CONTENT_FLAG),
      bumpMetric: async (key) => {
        await adminClient.rpc("bump_metric_server", { p_key: key });
      },
    };
    if (body.action === "get_patterns") {
      return await handleGetPatterns(adminClient, user.id, deps);
    }
    if (body.action === "analyse_entry") {
      return await handleAnalyseEntry(userClient, adminClient, user.id, body.entry_id, deps);
    }
    if (await journalInsightsPaused(adminClient)) {
      return json(PAUSED_BODY);
    }
    return json({ error: "unknown_action" }, 400);
  } catch (error) {
    return json(
      { error: error instanceof Error ? error.message : String(error) },
      500,
    );
  }
});

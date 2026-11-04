import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { callGeminiJson } from "../_shared/gemini_json.ts";
import { DRAFT_SAFETY_CONTENT_FLAG, featureFlagEnabled } from "../_shared/feature_flag.ts";
import { HEALING_AI_FLAG, type HealingDeps } from "../_shared/healing_ai_gate.ts";
import { corsHeaders, handlePortrait, json } from "./portrait_handler.ts";

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
    // Spec 1 W9e: the provider, the healing_ai_insights pause and the
    // draft-list flag, injected so the handler's tests can spy on them.
    // featureFlagEnabled answers off on any error: off is paused, and
    // the [DRAFT] victimisation list stays off (review A-4).
    const deps: HealingDeps = {
      model: callGeminiJson,
      aiPaused: async () => !(await featureFlagEnabled(adminClient, HEALING_AI_FLAG)),
      victimisationOn: () => featureFlagEnabled(adminClient, DRAFT_SAFETY_CONTENT_FLAG),
    };
    return await handlePortrait(userClient, adminClient, user, journey_id, deps);
  } catch (error) {
    return json(
      { error: error instanceof Error ? error.message : String(error) },
      500,
    );
  }
});

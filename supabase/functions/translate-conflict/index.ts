// supabase/functions/translate-conflict/index.ts — see handler.ts.
import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { callGeminiJson } from "../_shared/gemini_json.ts";
import { userScopedClient } from "../_shared/user_scoped_client.ts";
import { processTranslateRequest, respond } from "./handler.ts";

serve(async (req) => {
  if (req.method === "OPTIONS") return respond({ ok: true });
  let userScoped;
  try {
    userScoped = await userScopedClient(req);
  } catch {
    return respond({ error: true, code: "UNAUTHENTICATED", message: "Please sign in and try again." }, 401);
  }
  try {
    return await processTranslateRequest(req, userScoped, {
      // The shared helper applies the shared prohibited patterns.
      callGemini: (p) => callGeminiJson(p),
    });
  } catch (error) {
    // Only the error's kind, never content.
    console.error("translate_conflict_failed", error instanceof Error ? error.name : typeof error);
    return respond({ error: true, code: "INTERNAL_ERROR", message: "Something went wrong. Please try again." }, 500);
  }
});

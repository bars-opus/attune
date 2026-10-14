// Together AI (spec §6.5): suggests only; the person saves (plan Phase 7 R3).
import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { serviceRoleClient } from "../_shared/attune_auth.ts";
import { callGeminiJson } from "../_shared/gemini_json.ts";
import { userScopedClient } from "../_shared/user_scoped_client.ts";
import { errorResponse, processTogetherAi } from "./handler.ts";

serve(async (req) => {
  if (req.method !== "POST") return errorResponse("INVALID_INPUT");
  let userScoped;
  try {
    userScoped = await userScopedClient(req);
  } catch {
    return errorResponse("UNAUTHENTICATED");
  }
  try {
    return await processTogetherAi(req, userScoped, {
      service: serviceRoleClient(),
      callGemini: callGeminiJson,
    });
  } catch (err) {
    console.error("ai_together_unhandled", { message: (err as Error).message });
    return errorResponse("INTERNAL_ERROR");
  }
});

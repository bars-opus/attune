// supabase/functions/dating-moderation/index.ts
// Spec 2 W7b (§4.7, §6.4): serves request.ts with the live user check, the
// service-role client and the console's origin (DATING_CONSOLE_ORIGIN).
import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { requireUser, serviceRoleClient } from "../_shared/attune_auth.ts";
import { consoleOrigin, handleRequest } from "./request.ts";

serve((req) =>
  handleRequest(req, {
    requireUser,
    client: serviceRoleClient,
    origin: consoleOrigin(Deno.env.get("DATING_CONSOLE_ORIGIN")),
  })
);

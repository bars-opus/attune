// supabase/functions/dating-photo-urls/index.ts
// Spec 2 W5b (§4.7): serves request.ts with the live user check and the
// service-role client. The wiring itself (the 60-second signing in
// dating-profile-photos, the device hash, no-store, fixed codes, only an
// error's code logged) is in request.ts, where handler.test.ts drives it
// (fix round 1, T5 review M-4d).
import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { requireUser, serviceRoleClient } from "../_shared/attune_auth.ts";
import { handleRequest } from "./request.ts";

serve((req) => handleRequest(req, { requireUser, client: serviceRoleClient }));

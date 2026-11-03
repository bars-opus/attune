// supabase/functions/purge-recovery-holds/index.ts — see handler.ts.
// Run daily by the purge-recovery-holds cron (20261103100200) with the
// service-role key; any other caller gets 403. Logs counts only.
import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { HttpError, jsonResponse, requireServiceRole, serviceRoleClient } from "../_shared/attune_auth.ts";
import { purgeRecoveryHolds, type RecoveryPurgeClient } from "./handler.ts";

serve(async (req) => {
  if (req.method === "OPTIONS") return jsonResponse({ ok: true });
  try {
    requireServiceRole(req);
    const result = await purgeRecoveryHolds(serviceRoleClient() as unknown as RecoveryPurgeClient);
    console.log("purge-recovery-holds", JSON.stringify(result));
    return jsonResponse({ success: true, ...result });
  } catch (error) {
    if (error instanceof HttpError) return jsonResponse({ error: error.message }, error.status);
    console.error("purge-recovery-holds failed:", error instanceof Error ? error.name : typeof error);
    return jsonResponse({ error: "purge_failed" }, 500);
  }
});

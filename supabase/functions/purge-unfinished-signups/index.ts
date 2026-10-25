// supabase/functions/purge-unfinished-signups/index.ts — see handler.ts.
// Run hourly by the purge-unfinished-signups cron (20261025100500) with the
// service-role key; any other caller gets 403. The log line is the run's
// counts only (candidates, deleted, failed, skipped, remaining).
import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import {
  HttpError,
  jsonResponse,
  requireServiceRole,
  serviceRoleClient,
} from "../_shared/attune_auth.ts";
import { type PurgeClient, purgeUnfinishedSignups } from "./handler.ts";

serve(async (req) => {
  if (req.method === "OPTIONS") return jsonResponse({ ok: true });
  try {
    requireServiceRole(req);
    const result = await purgeUnfinishedSignups(serviceRoleClient() as unknown as PurgeClient);
    console.log("purge-unfinished-signups", JSON.stringify(result));
    return jsonResponse({ success: true, ...result });
  } catch (error) {
    if (error instanceof HttpError) {
      return jsonResponse({ error: error.message }, error.status);
    }
    console.error(
      "purge-unfinished-signups failed:",
      error instanceof Error ? error.name : typeof error,
    );
    return jsonResponse({ error: "purge_failed" }, 500);
  }
});

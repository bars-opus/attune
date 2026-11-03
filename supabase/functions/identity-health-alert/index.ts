// supabase/functions/identity-health-alert/index.ts — see handler.ts.
// Run every 15 minutes by the identity-health-alert cron (20261103100200)
// with the service-role key; any other caller gets 403.
import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { HttpError, jsonResponse, requireServiceRole, serviceRoleClient } from "../_shared/attune_auth.ts";
import { type AlertClient, sendAlerts } from "./handler.ts";

serve(async (req) => {
  if (req.method === "OPTIONS") return jsonResponse({ ok: true });
  try {
    requireServiceRole(req);
    const result = await sendAlerts(
      serviceRoleClient() as unknown as AlertClient,
      Deno.env.get("SAFETY_ALERT_WEBHOOK"),
      async (url, body) => {
        const response = await fetch(url, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body,
          signal: AbortSignal.timeout(10_000),
        });
        return { ok: response.ok, status: response.status };
      },
    );
    console.log("identity-health-alert", JSON.stringify(result));
    return jsonResponse({ success: true, ...result });
  } catch (error) {
    if (error instanceof HttpError) return jsonResponse({ error: error.message }, error.status);
    console.error("identity-health-alert failed:", error instanceof Error ? error.name : typeof error);
    return jsonResponse({ error: "alert_failed" }, 500);
  }
});

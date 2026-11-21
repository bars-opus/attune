// supabase/functions/process-dating-safety-outbox/index.ts
// Spec 2 W6b: the wiring for handler.ts. Called every minute by the cron
// (public.invoke_edge_function) with the service role; each database call
// is one RPC, awaited on its own; errors answer fixed codes only.
import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { HttpError, jsonResponse, requireServiceRole, serviceRoleClient } from "../_shared/attune_auth.ts";
import { runOutbox, WorkerError } from "./handler.ts";

serve(async (req) => {
  if (req.method === "OPTIONS") return jsonResponse({ ok: true });
  try {
    requireServiceRole(req);
    const supabase = serviceRoleClient();
    const result = await runOutbox({
      claim: async (limit) => {
        const { data, error } = await supabase.rpc("claim_dating_safety_jobs", { p_limit: limit });
        if (error) throw new Error("claim_failed");
        return Array.isArray(data) ? data : [];
      },
      config: async () => {
        const { data, error } = await supabase.rpc("get_dating_safety_config");
        if (error) throw new Error("config_failed");
        return data;
      },
      complete: async (id, version, hits, err) => {
        const { data, error } = await supabase.rpc("complete_dating_safety_job", {
          p_message_id: id,
          p_version: version,
          p_hits: hits,
          p_error: err,
        });
        if (error) throw new Error("complete_failed");
        return data; // {ok, reason?}: runOutbox counts a refusal
      },
      log: (line) => console.log(line),
    });
    return jsonResponse({ ok: true, ...result });
  } catch (e) {
    if (e instanceof HttpError) return jsonResponse({ ok: false, error: e.message }, e.status);
    if (e instanceof WorkerError) return jsonResponse({ ok: false, error: e.message }, 503);
    return jsonResponse({ ok: false, error: "worker_failed" }, 500);
  }
});

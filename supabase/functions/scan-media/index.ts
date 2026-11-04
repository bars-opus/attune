// supabase/functions/scan-media/index.ts — see handler.ts.
// Run every minute by the scan-media cron (20261103140000) with the
// service-role key; any other caller gets 403 at once. The cron's pg_net
// call gives up after 5 s, so the run is taken with a 202 and continues in
// EdgeRuntime.waitUntil (accept.ts, B6 fix I-1). The matcher is chosen by
// CSAM_MATCHER (photodna, safer, stub) through matcherFromEnv, the only
// way to the stub (B5 M6; seam.test.ts); the stub is refused unless
// get_attune_environment() reads exactly 'development' and SUPABASE_URL is
// the development project's (PF-H1; anything else is production). Every
// database and Storage call is aborted after RPC_TIMEOUT_MS (timedFetch);
// the object reads have their own bounds (objects.ts). Logs counts only:
// never a name, a path, a key or a person.
import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";
import { HttpError, jsonResponse, requireEnv, requireServiceRole } from "../_shared/attune_auth.ts";
import { matcherFromEnv } from "../_shared/csam_matcher.ts";
import { timedFetch } from "../_shared/timed_fetch.ts";
import { acceptAndRun } from "./accept.ts";
import {
  ALERT_POST_TIMEOUT_MS,
  DOWNLOAD_TIMEOUT_MS,
  errorClass,
  HEAD_TIMEOUT_MS,
  readEnvironment,
  RPC_TIMEOUT_MS,
  type ScanClient,
  scanMedia,
} from "./handler.ts";
import { storageObjectReader } from "./objects.ts";

serve(async (req) => {
  if (req.method === "OPTIONS") return jsonResponse({ ok: true });
  try {
    requireServiceRole(req);
  } catch (error) {
    if (error instanceof HttpError) return jsonResponse({ error: error.message }, error.status);
    return jsonResponse({ error: "scan_failed" }, 500);
  }

  const run = async (): Promise<Record<string, unknown>> => {
    // The run's clock includes the environment read (B6 N-2).
    const startedAt = Date.now();
    try {
      const url = requireEnv("SUPABASE_URL");
      const key = requireEnv("SUPABASE_SERVICE_ROLE_KEY");
      const supabase = createClient(url, key, {
        auth: { persistSession: false, autoRefreshToken: false },
        global: { fetch: timedFetch(RPC_TIMEOUT_MS) },
      });
      const env = await readEnvironment(supabase);
      const matcher = matcherFromEnv({ env: (name) => Deno.env.get(name), fetch, environment: env });
      const client: ScanClient = {
        rpc: (fn, args) => supabase.rpc(fn, args),
        storage: supabase.storage as unknown as ScanClient["storage"],
        objects: storageObjectReader({ url, key, headTimeoutMs: HEAD_TIMEOUT_MS, readTimeoutMs: DOWNLOAD_TIMEOUT_MS }),
      };
      const result = await scanMedia(client, matcher, {
        webhook: Deno.env.get("SAFETY_ALERT_WEBHOOK"),
        post: async (target, body) => {
          const response = await fetch(target, {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body,
            signal: AbortSignal.timeout(ALERT_POST_TIMEOUT_MS),
          });
          await response.body?.cancel();
          return { ok: response.ok, status: response.status };
        },
      }, { startedAt });
      console.log("scan-media", matcher.name, env, JSON.stringify(result));
      return { matcher: matcher.name, ...result };
    } catch (error) {
      console.error("scan-media failed:", errorClass(error));
      throw error;
    }
  };
  return await acceptAndRun(run);
});

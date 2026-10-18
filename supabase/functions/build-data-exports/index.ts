// supabase/functions/build-data-exports/index.ts
//
// Spec 3c (research 06 §3 F1 (5)): builds "Download my data" a part per run
// (cron every 2 minutes, only while a job waits, up to four at once; service
// role only). An edge function has about two seconds of CPU, so each run
// does one bounded piece and records where it got to (final review C1); the
// parts themselves are in parts.ts. What goes in is decided in SQL
// (export_bundle, export_chat_page, export_media_manifest). Every part's file
// is queued for deletion before it is stored (export_begin_part), so nothing
// is ever left behind.
import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import {
  jsonResponse,
  requireServiceRole,
  serviceRoleClient,
} from "../_shared/attune_auth.ts";
import { runOnce } from "./parts.ts";

serve((req) => {
  try {
    requireServiceRole(req);
  } catch {
    return jsonResponse({ error: "Forbidden" }, 403);
  }
  const supabase = serviceRoleClient();
  const work = runOnce(supabase).catch((e) =>
    console.error("build-data-exports:", e instanceof Error ? e.name : typeof e)
  );
  // The cron's HTTP call returns at once; the part is built in the
  // background (final review I8: pg_net's short timeout).
  // deno-lint-ignore no-explicit-any
  const runtime = (globalThis as any).EdgeRuntime;
  if (runtime?.waitUntil) {
    runtime.waitUntil(work);
    return jsonResponse({ accepted: true }, 202);
  }
  return work.then(() => jsonResponse({ ok: true }));
});

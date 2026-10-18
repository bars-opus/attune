// supabase/functions/get-export-url/index.ts
//
// Spec 3c: 15-minute links to the parts of the caller's own, ready,
// unexpired download.
// Whose export is decided by the verified JWT only -- there is no id in the
// request.
import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import {
  HttpError,
  jsonResponse,
  requireUser,
  serviceRoleClient,
} from "../_shared/attune_auth.ts";

serve(async (req) => {
  if (req.method === "OPTIONS") return jsonResponse({ ok: true });
  try {
    const user = await requireUser(req);
    const supabase = serviceRoleClient();
    const { data: job } = await supabase
      .from("data_export_jobs")
      .select("storage_keys, expires_at")
      .eq("user_id", user.id)
      .eq("status", "ready")
      .gt("expires_at", new Date().toISOString())
      .order("requested_at", { ascending: false })
      .limit(1)
      .maybeSingle();
    const keys = (job?.storage_keys ?? []) as string[];
    if (keys.length === 0) throw new HttpError("No download is ready", 404);
    // All parts at once, in order; each keeps its own file name (re-review M10).
    const urls = await Promise.all(keys.map(async (key, i) => {
      const { data, error } = await supabase.storage
        .from("data-exports")
        .createSignedUrl(key, 900, { download: `attune-export-${i + 1}.zip` });
      if (error || !data) throw new HttpError("Could not create a link", 500);
      return data.signedUrl;
    }));
    return jsonResponse({ urls, expires_at: job!.expires_at });
  } catch (error) {
    if (error instanceof HttpError) return jsonResponse({ error: error.message }, error.status);
    console.error("get-export-url failed:", error instanceof Error ? error.name : typeof error);
    return jsonResponse({ error: "Could not create a link" }, 500);
  }
});

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";

import {
  HttpError,
  jsonResponse,
  requireServiceRole,
  serviceRoleClient,
} from "../_shared/attune_auth.ts";

// Drains public.media_deletion_queue by calling the Storage API.
//
// The queue exists because Postgres cannot do this itself: Supabase
// refuses direct deletion from storage tables ("Direct deletion from
// storage tables is not allowed. Use the Storage API instead.", 42501).
// mark_streak_viewed and mark_video_viewed used to try, and because the
// DELETE followed the state change in each, the exception rolled the whole
// function back — a watched streak was never spent at all.
//
// So the RPCs record what should go, and this removes it. Until this runs,
// a spent streak is unreachable through the app (its clips rows are gone)
// but its object still sits in the bucket.
const DEFAULT_LIMIT = 100;

// Storage removes in bulk per bucket, so a batch is grouped before the
// call rather than deleted one at a time.
const BUCKET_FALLBACK = "message-media";

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return jsonResponse({ ok: true });
  }

  try {
    requireServiceRole(req);
    const supabase = serviceRoleClient();
    const body = req.method === "POST"
      ? await req.json().catch((): Record<string, unknown> => ({}))
      : {};

    const limit = typeof body.limit === "number" ? body.limit : DEFAULT_LIMIT;

    const { data: pending, error: loadError } = await supabase
      .from("media_deletion_queue")
      .select("id, bucket_id, object_name")
      .is("deleted_at", null)
      .order("requested_at", { ascending: true })
      .limit(limit);

    if (loadError) throw loadError;
    if (!pending || pending.length === 0) {
      return jsonResponse({ success: true, deleted: 0, failed: 0 });
    }

    // Grouped by bucket: one Storage call per bucket rather than per
    // object.
    const byBucket = new Map<string, { ids: string[]; names: string[] }>();
    for (const row of pending) {
      const bucket = String(row.bucket_id ?? BUCKET_FALLBACK);
      const entry = byBucket.get(bucket) ?? { ids: [], names: [] };
      entry.ids.push(String(row.id));
      entry.names.push(String(row.object_name));
      byBucket.set(bucket, entry);
    }

    let deleted = 0;
    let failed = 0;
    const errors: string[] = [];

    for (const [bucket, entry] of byBucket) {
      const { error: removeError } = await supabase.storage
        .from(bucket)
        .remove(entry.names);

      if (removeError) {
        // Left unstamped so the next run retries. An object that is
        // already gone is NOT an error from Storage's point of view, so a
        // failure here is a real one — credentials, or the bucket.
        failed += entry.names.length;
        errors.push(`${bucket}: ${removeError.message}`);
        continue;
      }

      // Stamped rather than deleted, so the queue stays an audit trail of
      // what was destroyed and when.
      const { error: stampError } = await supabase
        .from("media_deletion_queue")
        .update({ deleted_at: new Date().toISOString() })
        .in("id", entry.ids);

      if (stampError) throw stampError;
      deleted += entry.names.length;
    }

    return jsonResponse({
      success: true,
      deleted,
      failed,
      errors: errors.length > 0 ? errors : undefined,
    });
  } catch (error) {
    const status = error instanceof HttpError ? error.status : 500;
    const message = error instanceof Error ? error.message : "Unknown error";
    return jsonResponse({ success: false, error: message }, status);
  }
});

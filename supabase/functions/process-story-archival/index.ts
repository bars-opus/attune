import { serve } from "https://deno.land/std@0.177.0/http/server.ts";

import {
  HttpError,
  jsonResponse,
  requireServiceRole,
  serviceRoleClient,
} from "../_shared/attune_auth.ts";

// Drains public.story_media_processing_outbox: the hourly worker behind
// spec §4.4's image downscale. Video gets no outbox row at all --
// claim_story_archival_batch closes video rows out directly on
// story_items before it ever touches the outbox, so every row this
// function claims is an image. There is no video branch here because
// there is nothing for one to do: no transcoding runtime exists in this
// project (§4.4).
//
// Ordering is load-bearing (§4.4): create the new rendition, THEN
// conditionally swap the key (complete_story_archival), THEN the old
// key is enqueued for deletion -- all inside that RPC, not here. This
// function's only job before calling it is to get the new object
// sitting at its deterministic key in Storage. If it dies after upload
// but before completing, the object is simply orphaned at a
// content-addressed-by-story-id key; the next claim (once the stale
// lease times out) re-runs the same upload against the same key and
// complete_story_archival is still called exactly once successfully.
const DEFAULT_LIMIT = 20;
const BUCKET = "story-media";

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

    const { data: jobs, error: claimError } = await supabase.rpc(
      "claim_story_archival_batch",
      { p_limit: limit },
    );
    if (claimError) throw claimError;

    let processed = 0;
    let failed = 0;

    for (const job of jobs ?? []) {
      const storyId = String(job.story_id);
      const mediaKey = String(job.media_key);

      try {
        // The archive key is not invented here: story_archive_key(uuid)
        // is the same IMMUTABLE SQL function complete_story_archival and
        // delete_story_item's enqueue both key off of, called live
        // rather than reproduced as a string template -- so this key can
        // never drift from the database's own definition of it.
        const { data: keyResult, error: keyError } = await supabase.rpc(
          "story_archive_key",
          { p_story_item_id: storyId },
        );
        if (keyError) throw keyError;
        const archiveKey = String(keyResult);

        // §4.4's numbers for the archive rendition: 1600px long edge,
        // quality 80 (process-chat-media's thumbnail transform is a
        // separate, smaller 400/75 for a different purpose).
        const { data: image, error: downloadError } = await supabase.storage
          .from(BUCKET)
          .download(mediaKey, {
            transform: { width: 1600, resize: "contain", quality: 80 },
          });
        if (downloadError || !image) {
          throw downloadError ?? new Error("decode_failed");
        }

        const bytes = await image.arrayBuffer();
        const upload = await supabase.storage.from(BUCKET).upload(
          archiveKey,
          bytes,
          { contentType: image.type || "image/jpeg", upsert: false },
        );
        // upsert: false against an already-uploaded-but-not-yet-swapped
        // key (a prior attempt that died before completing) fails here
        // rather than silently overwriting -- that is fine, and expected:
        // the object at archiveKey from that earlier attempt is already
        // usable, so this attempt can proceed straight to completion
        // instead of treating a duplicate-object error as fatal.
        if (upload.error && !isDuplicateObjectError(upload.error)) {
          throw upload.error;
        }

        const { data: completion, error: completeError } = await supabase
          .rpc("complete_story_archival", {
            p_story_id: storyId,
            p_new_key: archiveKey,
          });
        if (completeError) throw completeError;
        if (
          completion && typeof completion === "object" &&
          (completion as Record<string, unknown>).error === true
        ) {
          throw new Error(
            String((completion as Record<string, unknown>).code ?? "complete_failed"),
          );
        }

        processed++;
      } catch (jobError) {
        failed++;
        const { error: failError } = await supabase.rpc(
          "fail_story_archival",
          { p_story_id: storyId, p_error_code: errorCode(jobError) },
        );
        // Do not swallow a failure to record the failure itself -- if
        // fail_story_archival's own call errors, that is worth surfacing
        // rather than pretending the job's failure was handled.
        if (failError) throw failError;
      }
    }

    return jsonResponse({ success: true, processed, failed });
  } catch (error) {
    const status = error instanceof HttpError ? error.status : 500;
    return jsonResponse({ success: false, error: errorCode(error) }, status);
  }
});

function isDuplicateObjectError(error: { message?: string }): boolean {
  const message = (error?.message ?? "").toLowerCase();
  return message.includes("already exists") || message.includes("duplicate");
}

function errorCode(error: unknown) {
  return (error instanceof Error ? error.message : "unknown_error").slice(0, 120);
}

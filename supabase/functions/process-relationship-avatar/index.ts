import { serve } from "https://deno.land/std@0.177.0/http/server.ts";

import {
  jsonResponse,
  requireServiceRole,
  serviceRoleClient,
} from "../_shared/attune_auth.ts";

// Mirrors process-chat-media exactly (thumbnail generation only — no
// moderation/face-detection, see the migration's file header on why that
// doesn't apply to a relationship avatar).
const MAX_ATTEMPTS = 5;

serve(async (req) => {
  if (req.method === "OPTIONS") return jsonResponse({ ok: true });
  try {
    requireServiceRole(req);
    const supabase = serviceRoleClient();
    const body = await req.json().catch(() => ({}));
    const requestedId =
      typeof body.relationship_id === "string" ? body.relationship_id : null;
    const { data: jobs, error } = await supabase.rpc(
      "claim_relationship_avatar_jobs",
      { p_limit: requestedId ? 1 : 20, p_relationship_id: requestedId },
    );
    if (error) throw error;

    let processed = 0;
    for (const job of jobs ?? []) {
      try {
        const { data: image, error: downloadError } = await supabase.storage
          .from("relationship-avatars")
          .download(job.storage_key, {
            transform: { width: 400, resize: "contain", quality: 75 },
          });
        if (downloadError || !image) {
          throw downloadError ?? new Error("decode_failed");
        }
        if (image.size <= 0 || image.size > 819200) {
          throw new Error("thumbnail_size_invalid");
        }

        const thumbnailKey =
          `relationship-avatars/${job.relationship_id}/thumb-${crypto.randomUUID()}.thumb`;
        const bytes = await image.arrayBuffer();
        const upload = await supabase.storage
          .from("relationship-avatars")
          .upload(thumbnailKey, bytes, {
            contentType: image.type || "image/jpeg",
            upsert: false,
          });
        if (upload.error) throw upload.error;

        // Only write the thumbnail if this job's storage_key is still the
        // relationship's current avatar — a newer upload may have already
        // superseded it (e.g. the couple changed the photo again before
        // this job ran), in which case writing the stale thumbnail here
        // would silently pair a fresh full-size image with an old preview.
        const update = await supabase
          .from("relationships")
          .update({ chat_avatar_thumbnail_url: thumbnailKey })
          .eq("id", job.relationship_id)
          .eq("chat_avatar_url", job.storage_key);
        if (update.error) {
          await supabase.storage.from("relationship-avatars").remove([
            thumbnailKey,
          ]);
          throw update.error;
        }
        await finish(supabase, job.relationship_id, "done", null);
        processed++;
      } catch (jobError) {
        const dead = Number(job.attempts ?? 0) >= MAX_ATTEMPTS;
        await finish(
          supabase,
          job.relationship_id,
          dead ? "dead_letter" : "pending",
          errorCode(jobError),
        );
      }
    }
    return jsonResponse({ success: true, processed });
  } catch (error) {
    return jsonResponse({ success: false, error: errorCode(error) }, 500);
  }
});

async function finish(
  supabase: ReturnType<typeof serviceRoleClient>,
  relationshipId: string,
  state: "pending" | "done" | "dead_letter",
  code: string | null,
) {
  const { error } = await supabase
    .from("relationship_avatar_processing_outbox")
    .update({
      state,
      last_error_code: code,
      processing_started_at: state === "pending" ? null : undefined,
      completed_at: state === "done" || state === "dead_letter"
        ? new Date().toISOString()
        : null,
      updated_at: new Date().toISOString(),
    })
    .eq("relationship_id", relationshipId)
    .eq("state", "processing");
  if (error) throw error;
}

function errorCode(error: unknown) {
  return (error instanceof Error ? error.message : "unknown_error").slice(
    0,
    120,
  );
}

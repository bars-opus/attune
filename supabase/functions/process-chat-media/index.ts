import { serve } from "https://deno.land/std@0.177.0/http/server.ts";

import {
  jsonResponse,
  requireServiceRole,
  serviceRoleClient,
} from "../_shared/attune_auth.ts";

const MAX_ATTEMPTS = 5;

serve(async (req) => {
  if (req.method === "OPTIONS") return jsonResponse({ ok: true });
  try {
    requireServiceRole(req);
    const supabase = serviceRoleClient();
    const body = await req.json().catch(() => ({}));
    const requestedId = typeof body.message_id === "string" ? body.message_id : null;
    const { data: jobs, error } = await supabase.rpc("claim_chat_media_jobs", {
      p_limit: requestedId ? 1 : 20,
      p_message_id: requestedId,
    });
    if (error) throw error;

    let processed = 0;
    for (const job of jobs ?? []) {
      try {
        const { data: image, error: downloadError } = await supabase.storage
          .from("message-media")
          .download(job.storage_key, {
            transform: { width: 400, resize: "contain", quality: 75 },
          });
        if (downloadError || !image) throw downloadError ?? new Error("decode_failed");
        if (image.size <= 0 || image.size > 819200) throw new Error("thumbnail_size_invalid");

        const thumbnailKey = `chat-thumbnails/${crypto.randomUUID()}.thumb`;
        const bytes = await image.arrayBuffer();
        const upload = await supabase.storage.from("message-media").upload(
          thumbnailKey,
          bytes,
          { contentType: image.type || "image/jpeg", upsert: false },
        );
        if (upload.error) throw upload.error;

        const update = await supabase.from("messages")
          .update({ media_thumbnail_url: thumbnailKey })
          .eq("id", job.message_id);
        if (update.error) {
          await supabase.storage.from("message-media").remove([thumbnailKey]);
          throw update.error;
        }
        await finish(supabase, job.message_id, "done", null);
        processed++;
      } catch (jobError) {
        const dead = Number(job.attempts ?? 0) >= MAX_ATTEMPTS;
        await finish(
          supabase,
          job.message_id,
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
  messageId: string,
  state: "pending" | "done" | "dead_letter",
  code: string | null,
) {
  const { error } = await supabase.from("message_media_processing_outbox")
    .update({
      state,
      last_error_code: code,
      processing_started_at: state === "pending" ? null : undefined,
      completed_at: state === "done" || state === "dead_letter"
        ? new Date().toISOString()
        : null,
      updated_at: new Date().toISOString(),
    })
    .eq("message_id", messageId).eq("state", "processing");
  if (error) throw error;
}

function errorCode(error: unknown) {
  return (error instanceof Error ? error.message : "unknown_error").slice(0, 120);
}

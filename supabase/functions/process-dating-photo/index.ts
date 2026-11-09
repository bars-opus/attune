// supabase/functions/process-dating-photo/index.ts
// Spec 2 W3c: the wiring for handler.ts (CSAM first, inline; I-10). The
// stub CSAM matcher only through matcherFromEnv (development environment
// AND the development or a local-serve host; Spec 1 W7b). Every database
// call below is one statement or RPC, awaited on its own (Task 9 carry C);
// errors answer fixed codes only (carry E). Spec 2 W3 final (M-6): a missing
// GOOGLE_VISION_API_KEY no longer stops the run: the CSAM scan, its record
// and the orphan sweep run without it; only the Vision step fails closed
// (visionStep). (M-5): the strip's re-upload is an update that never asks
// storage to create a missing object (upsert: false), checked before and
// after on the server (handler.ts).
import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { HttpError, jsonResponse, requireServiceRole, serviceRoleClient } from "../_shared/attune_auth.ts";
import { matcherFromEnv } from "../_shared/csam_matcher.ts";
import { storageQuarantine, type StorageLike } from "../_shared/csam_match_path.ts";
import { BUCKET, BusyError, errorCode, isBusy, runWorker, visionStep } from "./handler.ts";

const VISION_API_KEY = Deno.env.get("GOOGLE_VISION_API_KEY");

serve(async (req) => {
  if (req.method === "OPTIONS") return jsonResponse({ ok: true });
  try {
    requireServiceRole(req);
    const supabase = serviceRoleClient();
    const body = await req.json().catch(() => ({}));
    const requestedId = typeof body.photo_id === "string" ? body.photo_id : null;
    const { data: env, error: envError } = await supabase.rpc("get_attune_environment");
    const matcher = matcherFromEnv({
      env: (name) => Deno.env.get(name),
      fetch,
      environment: !envError && env === "development" ? "development" : "production",
    });
    const { data: configRows } = await supabase.from("dating_photo_moderation_config")
      .select("min_face_confidence, min_face_area_ratio, child_label_reject, child_label_review").limit(1);
    const c = configRows?.[0];
    const config = {
      minFaceConfidence: Number(c?.min_face_confidence ?? 0.7),
      minFaceAreaRatio: Number(c?.min_face_area_ratio ?? 0.06),
      childLabelReject: Number(c?.child_label_reject ?? 0.7),
      childLabelReview: Number(c?.child_label_review ?? 0.5),
    };
    const failed = (error: unknown, code: string) => (isBusy(error) ? new BusyError() : new Error(code));
    const result = await runWorker(requestedId, {
      rpc: (fn, args) => supabase.rpc(fn, args),
      photo: async (id) => {
        const { data, error } = await supabase.from("dating_profile_photos").select("id, user_id, storage_key").eq("id", id).maybeSingle();
        if (error) throw failed(error, "photo_read_failed");
        return data ?? null;
      },
      download: async (key) => {
        const { data } = await supabase.storage.from(BUCKET).download(key);
        return data ? new Uint8Array(await data.arrayBuffer()) : null;
      },
      replace: async (key, bytes) => {
        const { error } = await supabase.storage.from(BUCKET).update(key, bytes, { contentType: "image/jpeg", upsert: false });
        return !error;
      },
      verdict: async (id, state, reason) => {
        // A CSAM hit is final (the recorder's): no verdict ever writes over it.
        const { error } = await supabase.from("dating_profile_photos")
          .update({ moderation_state: state, rejection_reason: reason, reviewed_at: new Date().toISOString() })
          .eq("id", id).neq("csam_state", "hit");
        if (error) throw failed(error, "verdict_failed");
      },
      finish: async (id, state, code) => {
        const now = new Date().toISOString();
        const { error } = await supabase.from("dating_photo_moderation_outbox").update({
          state,
          last_error_code: code,
          processing_started_at: state === "pending" ? null : undefined,
          completed_at: state === "pending" ? null : now,
          updated_at: now,
        }).eq("photo_id", id).eq("state", "processing");
        if (error) throw failed(error, "finish_failed");
      },
      vision: visionStep(VISION_API_KEY),
      matcher,
      quarantine: storageQuarantine(supabase.storage as unknown as StorageLike),
      config,
    });
    return jsonResponse({ success: true, ...result });
  } catch (error) {
    const status = error instanceof HttpError ? error.status : 500;
    const code = error instanceof HttpError
      ? (status === 401 ? "unauthorized" : status === 403 ? "forbidden" : "bad_request")
      : errorCode(error);
    return jsonResponse({ success: false, error: code }, status);
  }
});

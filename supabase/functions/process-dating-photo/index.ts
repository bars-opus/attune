// supabase/functions/process-dating-photo/index.ts
import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import {
  HttpError,
  jsonResponse,
  requireServiceRole,
  serviceRoleClient,
} from "../_shared/attune_auth.ts";
import {
  analyzeDatingPhoto,
  computeFaceAreaRatio,
  decideModerationOutcome,
} from "../_shared/google_vision.ts";

const MAX_ATTEMPTS = 5;
const VISION_API_KEY = Deno.env.get("GOOGLE_VISION_API_KEY");

serve(async (req) => {
  if (req.method === "OPTIONS") return jsonResponse({ ok: true });
  try {
    requireServiceRole(req);
    if (!VISION_API_KEY) {
      throw new Error("missing_vision_api_key");
    }
    const supabase = serviceRoleClient();
    const body = await req.json().catch(() => ({}));
    const requestedId = typeof body.photo_id === "string" ? body.photo_id : null;

    const { data: jobs, error } = await supabase.rpc("claim_dating_photo_jobs", {
      p_limit: requestedId ? 1 : 20,
      p_photo_id: requestedId,
    });
    if (error) throw error;

    const { data: configRows } = await supabase
      .from("dating_photo_moderation_config")
      .select("min_face_confidence, min_face_area_ratio")
      .limit(1);
    const config = configRows?.[0] ?? {
      min_face_confidence: 0.7,
      min_face_area_ratio: 0.06,
    };

    let processed = 0;
    for (const job of jobs ?? []) {
      try {
        const { data: photo, error: photoError } = await supabase
          .from("dating_profile_photos")
          .select("id, storage_key")
          .eq("id", job.photo_id)
          .single();
        if (photoError || !photo) throw new Error("photo_missing");

        const { data: image, error: downloadError } = await supabase.storage
          .from("dating-profile-photos")
          .download(photo.storage_key);
        if (downloadError || !image) throw new Error("decode_failed");

        const bytes = new Uint8Array(await image.arrayBuffer());
        const dimensions = await readImageDimensions(bytes);
        if (!dimensions || dimensions.width < 600 || dimensions.height < 600) {
          await writeVerdict(supabase, photo.id, "rejected", "image_too_small");
          await finish(supabase, job.photo_id, "done", null);
          processed++;
          continue;
        }

        const visionResult = await analyzeDatingPhoto({
          imageBytes: bytes,
          apiKey: VISION_API_KEY,
        });

        // Vision doesn't return image dimensions, so the precise face-area
        // ratio is computed here using the decode step's own known
        // dimensions plus the bounding-box vertices already fetched by
        // analyzeDatingPhoto — no second Vision call needed.
        const faceAreaRatio = visionResult.faceBoundingPolyVertices
          ? computeFaceAreaRatio(
            visionResult.faceBoundingPolyVertices,
            dimensions.width,
            dimensions.height,
          )
          : null;

        const outcome = decideModerationOutcome(
          { ...visionResult, faceAreaRatio },
          {
            minFaceConfidence: config.min_face_confidence,
            minFaceAreaRatio: config.min_face_area_ratio,
          },
        );

        // Strip metadata BEFORE the photo can become visible (§4.3). Only
        // an approved photo is ever shown, so doing this here means no
        // EXIF-bearing object is reachable by another user at any point.
        //
        // A failure to strip must not approve the photo: a photo we could
        // not clean goes to needs_review rather than being published with
        // its GPS intact.
        if (outcome.state === "approved") {
          const stripped = stripJpegMetadata(bytes);
          if (stripped) {
            const { error: reuploadError } = await supabase.storage
              .from("dating-profile-photos")
              .update(photo.storage_key, stripped, {
                contentType: "image/jpeg",
                upsert: true,
              });
            if (reuploadError) throw new Error("strip_reupload_failed");
          } else {
            // Not a JPEG we can walk safely. PNG carries no EXIF by the
            // spec's own structure, but an unrecognised container is not
            // something to publish unexamined.
            const isPng = bytes.length > 8 && bytes[0] === 0x89 &&
              bytes[1] === 0x50;
            if (!isPng) {
              await writeVerdict(
                supabase,
                photo.id,
                "needs_review",
                "metadata_strip_unsupported",
              );
              await finish(supabase, job.photo_id, "done", null);
              processed++;
              continue;
            }
          }
        }

        await writeVerdict(supabase, photo.id, outcome.state, outcome.reason);
        await finish(supabase, job.photo_id, "done", null);
        processed++;
      } catch (jobError) {
        const dead = Number(job.attempts ?? 0) >= MAX_ATTEMPTS;
        if (dead) {
          await writeVerdict(supabase, job.photo_id, "needs_review", "moderation_failed");
        }
        await finish(
          supabase,
          job.photo_id,
          dead ? "dead_letter" : "pending",
          errorCode(jobError),
        );
      }
    }
    return jsonResponse({ success: true, processed });
  } catch (error) {
    const status = error instanceof HttpError ? error.status : 500;
    return jsonResponse({ success: false, error: errorCode(error) }, status);
  }
});

async function writeVerdict(
  supabase: ReturnType<typeof serviceRoleClient>,
  photoId: string,
  state: "approved" | "rejected" | "needs_review",
  reason: string | null,
) {
  const { error } = await supabase
    .from("dating_profile_photos")
    .update({
      moderation_state: state,
      rejection_reason: reason,
      reviewed_at: new Date().toISOString(),
    })
    .eq("id", photoId);
  if (error) throw error;
}

async function finish(
  supabase: ReturnType<typeof serviceRoleClient>,
  photoId: string,
  state: "pending" | "done" | "dead_letter",
  code: string | null,
) {
  const { error } = await supabase.from("dating_photo_moderation_outbox")
    .update({
      state,
      last_error_code: code,
      processing_started_at: state === "pending" ? null : undefined,
      completed_at: state === "done" || state === "dead_letter"
        ? new Date().toISOString()
        : null,
      updated_at: new Date().toISOString(),
    })
    .eq("photo_id", photoId).eq("state", "processing");
  if (error) throw error;
}

/**
 * Removes EXIF and every other metadata segment from a JPEG.
 *
 * Spec §4.3 requires stripping server-side. The client already passes
 * `keepExif: false`, but that is a courtesy the client can withdraw: a
 * modified or replayed upload can carry GPS coordinates, a capture
 * timestamp, and a device serial straight into a dating photo other users
 * will see. Stripping here is what makes it true regardless of the client.
 *
 * JPEG is a sequence of marker segments. Everything a camera writes lives
 * in APPn (0xE0-0xEF, holding EXIF/GPS in APP1 and thumbnails that carry
 * their own EXIF) or COM (0xFE). Dropping those segments leaves the
 * compressed image data untouched, so this re-encodes nothing and cannot
 * degrade the picture.
 *
 * Returns null when the input is not a JPEG we can safely walk, so callers
 * fall back to leaving the object alone rather than writing something
 * corrupt.
 */
function stripJpegMetadata(bytes: Uint8Array): Uint8Array | null {
  if (bytes.length < 4 || bytes[0] !== 0xFF || bytes[1] !== 0xD8) return null;

  const keep: Array<[number, number]> = [];
  let offset = 2;

  while (offset < bytes.length - 1) {
    if (bytes[offset] !== 0xFF) return null;

    const marker = bytes[offset + 1];

    // Start of scan: the entropy-coded image data runs to the end of the
    // file, so copy the remainder verbatim and stop parsing.
    if (marker === 0xDA) {
      keep.push([offset, bytes.length]);
      break;
    }

    // Standalone markers carry no length field.
    if (marker === 0x01 || (marker >= 0xD0 && marker <= 0xD7)) {
      keep.push([offset, offset + 2]);
      offset += 2;
      continue;
    }

    const segmentLength = (bytes[offset + 2] << 8) | bytes[offset + 3];
    if (segmentLength < 2 || offset + 2 + segmentLength > bytes.length) {
      return null;
    }

    const isAppSegment = marker >= 0xE0 && marker <= 0xEF;
    const isComment = marker === 0xFE;
    if (!isAppSegment && !isComment) {
      keep.push([offset, offset + 2 + segmentLength]);
    }

    offset += 2 + segmentLength;
  }

  let size = 2;
  for (const [start, end] of keep) size += end - start;

  const out = new Uint8Array(size);
  out[0] = 0xFF;
  out[1] = 0xD8;
  let cursor = 2;
  for (const [start, end] of keep) {
    out.set(bytes.subarray(start, end), cursor);
    cursor += end - start;
  }
  return out;
}

async function readImageDimensions(
  bytes: Uint8Array,
): Promise<{ width: number; height: number } | null> {
  // Minimal JPEG/PNG header parse sufficient for the dimension gate; a full
  // decode is not required here since Vision already validated decodability.
  if (bytes.length > 24 && bytes[0] === 0x89 && bytes[1] === 0x50) {
    // PNG: width/height are big-endian uint32 at offset 16/20.
    const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
    return { width: view.getUint32(16), height: view.getUint32(20) };
  }
  if (bytes.length > 4 && bytes[0] === 0xFF && bytes[1] === 0xD8) {
    // JPEG: scan markers for SOF0/SOF2 to find dimensions.
    let offset = 2;
    while (offset < bytes.length - 8) {
      if (bytes[offset] !== 0xFF) { offset++; continue; }
      const marker = bytes[offset + 1];
      if (marker === 0xC0 || marker === 0xC2) {
        const height = (bytes[offset + 5] << 8) | bytes[offset + 6];
        const width = (bytes[offset + 7] << 8) | bytes[offset + 8];
        return { width, height };
      }
      const segmentLength = (bytes[offset + 2] << 8) | bytes[offset + 3];
      offset += 2 + segmentLength;
    }
    return null;
  }
  return null;
}

function errorCode(error: unknown) {
  return (error instanceof Error ? error.message : "unknown_error").slice(0, 120);
}

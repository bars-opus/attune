// supabase/functions/verify-dating-profile/index.ts
import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import {
  HttpError,
  jsonResponse,
  requireUser,
  serviceRoleClient,
} from "../_shared/attune_auth.ts";
import { compareFaces } from "../_shared/aws_rekognition.ts";

const AWS_ACCESS_KEY_ID = Deno.env.get("AWS_REKOGNITION_ACCESS_KEY_ID");
const AWS_SECRET_ACCESS_KEY = Deno.env.get("AWS_REKOGNITION_SECRET_ACCESS_KEY");
const AWS_REGION = Deno.env.get("AWS_REKOGNITION_REGION") ?? "us-east-1";

serve(async (req) => {
  if (req.method === "OPTIONS") return jsonResponse({ ok: true });
  try {
    const user = await requireUser(req);
    if (!AWS_ACCESS_KEY_ID || !AWS_SECRET_ACCESS_KEY) {
      throw new Error("missing_rekognition_credentials");
    }

    const body = await req.json().catch(() => ({}));
    const selfieBase64 = typeof body.selfie_base64 === "string" ? body.selfie_base64 : null;
    if (!selfieBase64) throw new HttpError("selfie_base64 is required", 400);

    const supabase = serviceRoleClient();

    // NOTE: verification eligibility requires at least one approved photo —
    // enforce this before spending an API call.
    const { data: approvedPhotos, error: photosError } = await supabase
      .from("dating_profile_photos")
      .select("storage_key")
      .eq("user_id", user.id)
      .eq("moderation_state", "approved");
    if (photosError) throw photosError;
    if (!approvedPhotos || approvedPhotos.length === 0) {
      throw new HttpError("At least one approved photo is required before verification", 400);
    }

    await supabase
      .from("dating_profiles")
      .update({ verification_state: "pending" })
      .eq("user_id", user.id);

    const selfieBytes = base64ToBytes(selfieBase64);

    let allMatched = true;
    try {
      for (const photo of approvedPhotos) {
        const { data: targetFile, error: downloadError } = await supabase.storage
          .from("dating-profile-photos")
          .download(photo.storage_key);
        if (downloadError || !targetFile) throw new Error("target_photo_missing");

        const targetBytes = new Uint8Array(await targetFile.arrayBuffer());
        const result = await compareFaces({
          sourceImageBytes: selfieBytes,
          targetImageBytes: targetBytes,
          accessKeyId: AWS_ACCESS_KEY_ID,
          secretAccessKey: AWS_SECRET_ACCESS_KEY,
          region: AWS_REGION,
        });
        // Only the boolean is read here. `result.similarity` is intentionally
        // never referenced beyond this line, never logged, and never written
        // to any table — per spec §4's architectural boundary.
        if (!result.matched) {
          allMatched = false;
          break;
        }
      }
    } catch (compareError) {
      // API failure (not a low-confidence result): retry-eligible, land in
      // pending rather than a false verified/needs_review verdict.
      console.error("verify-dating-profile compare failed:", compareError instanceof Error ? compareError.message : "unknown");
      return jsonResponse({ verification_state: "pending", retry: true }, 200);
    }

    const finalState = allMatched ? "verified" : "needs_review";
    await supabase
      .from("dating_profiles")
      .update({
        verification_state: finalState,
        verification_method: "selfie_self_consistency_v1",
        verified_at: finalState === "verified" ? new Date().toISOString() : null,
      })
      .eq("user_id", user.id);

    return jsonResponse({ verification_state: finalState });
  } catch (error) {
    if (error instanceof HttpError) {
      return jsonResponse({ error: error.message }, error.status);
    }
    console.error("verify-dating-profile failed:", error instanceof Error ? error.name : typeof error);
    return jsonResponse({ error: "Could not complete verification" }, 500);
  }
});

function base64ToBytes(base64: string): Uint8Array {
  const binary = atob(base64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

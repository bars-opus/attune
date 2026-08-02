// Thin diagnostic wrapper confirming create_dating_photo_upload_intent is
// independently callable outside the Flutter client. The real upload path
// is client -> Supabase Storage directly, using the intent this RPC issues
// (see DatingRepository.createPhotoUploadIntent, Task 6).
import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import {
  HttpError,
  jsonResponse,
  requireUser,
} from "../_shared/attune_auth.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

serve(async (req) => {
  if (req.method === "OPTIONS") return jsonResponse({ ok: true });
  try {
    const user = await requireUser(req);
    const body = await req.json().catch(() => ({}));
    const mimeType = typeof body.mime_type === "string" ? body.mime_type : null;
    if (!mimeType) throw new HttpError("mime_type is required", 400);

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_ANON_KEY")!,
      { global: { headers: { Authorization: req.headers.get("Authorization")! } } },
    );

    const { data, error } = await supabase.rpc("create_dating_photo_upload_intent", {
      p_mime_type: mimeType,
    });
    if (error) throw new HttpError(error.message, 400);

    return jsonResponse({ intent: Array.isArray(data) ? data[0] : data, user_id: user.id });
  } catch (error) {
    if (error instanceof HttpError) {
      return jsonResponse({ error: error.message }, error.status);
    }
    console.error("upload-dating-photo failed:", error instanceof Error ? error.name : typeof error);
    return jsonResponse({ error: "Could not create upload intent" }, 500);
  }
});

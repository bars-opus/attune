// planning-link-preview (spec §7.1). Called by the app after a Link block
// is saved, with the user's JWT. Membership and the 30/min rate limit are
// checked by planning_link_preview_target AS the user before anything is
// fetched; every fetch goes through guard.ts. A failure writes
// preview.status = 'failed' -- the block itself was saved long before.

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { decode, GIF, Image } from "https://deno.land/x/imagescript@1.3.0/mod.ts";
import type { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";
import { HttpError, jsonResponse, serviceRoleClient } from "../_shared/attune_auth.ts";
import { userScopedClient } from "../_shared/user_scoped_client.ts";
import { guardedFetch, PreviewError } from "./guard.ts";
import { imageDimensions, MAX_PREVIEW_PIXELS } from "./image_size.ts";
import { parsePreview } from "./og.ts";

const HTML_MAX_BYTES = 512 * 1024;
const IMAGE_MAX_BYTES = 2 * 1024 * 1024;
const IMAGE_LONG_EDGE = 1200;
const CACHE_TTL_MS = 7 * 24 * 60 * 60 * 1000;

interface Target {
  block_id: string;
  url: string;
  relationship_id: string;
  entry_id: string;
}
interface CachedPreview {
  title: string | null;
  description: string | null;
  host: string;
  image_url: string | null;
}

function log(requestId: string, outcome: string, started: number, host: string | null) {
  // Host only -- never the full URL (it can carry tokens or personal paths).
  console.log(JSON.stringify({
    fn: "planning-link-preview", request_id: requestId, outcome,
    latency_ms: Date.now() - started, host,
  }));
}

async function sha256Hex(s: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(s));
  return Array.from(new Uint8Array(digest), (b) => b.toString(16).padStart(2, "0")).join("");
}

async function loadPreview(service: SupabaseClient, url: string): Promise<CachedPreview> {
  const urlHash = await sha256Hex(url);
  const { data: cached } = await service.from("planning_link_previews")
    .select("preview, fetched_at").eq("url_hash", urlHash).maybeSingle();
  if (cached && Date.now() - Date.parse(cached.fetched_at) < CACHE_TTL_MS) {
    return cached.preview as CachedPreview;
  }
  const page = await guardedFetch(url, { maxBytes: HTML_MAX_BYTES, accept: "html" });
  const parsed = parsePreview(new TextDecoder("utf-8", { fatal: false }).decode(page.body), page.url);
  const preview: CachedPreview = {
    title: parsed.title,
    description: parsed.description,
    host: new URL(url).hostname,
    image_url: parsed.imageUrl,
  };
  await service.from("planning_link_previews")
    .upsert({ url_hash: urlHash, preview, fetched_at: new Date().toISOString() });
  return preview;
}

/// Downloads the preview image through the guard and stores a re-encoded
/// JPEG copy in this couple's folder (never shared across couples).
async function storeImage(service: SupabaseClient, target: Target, imageUrl: string): Promise<string> {
  const res = await guardedFetch(imageUrl, { maxBytes: IMAGE_MAX_BYTES, accept: "image" });
  // A 2 MB file can declare a canvas that exhausts memory when decoded.
  const size = imageDimensions(res.body);
  if (!size || size.width * size.height > MAX_PREVIEW_PIXELS) throw new PreviewError("image_too_big");
  const decoded = await decode(res.body);
  let image = (decoded instanceof GIF ? decoded[0] : decoded) as Image;
  if (Math.max(image.width, image.height) > IMAGE_LONG_EDGE) {
    image = image.width >= image.height
      ? image.resize(IMAGE_LONG_EDGE, Image.RESIZE_AUTO)
      : image.resize(Image.RESIZE_AUTO, IMAGE_LONG_EDGE);
  }
  const jpeg = await image.encodeJPEG(80);
  const path = `${target.relationship_id}/${target.entry_id}/preview-${crypto.randomUUID()}.jpg`;
  const { error } = await service.storage.from("planning-media")
    .upload(path, jpeg, { contentType: "image/jpeg", upsert: false });
  if (error) throw error;
  return path;
}

serve(async (req) => {
  const requestId = crypto.randomUUID();
  const started = Date.now();
  if (req.method === "OPTIONS") return jsonResponse({ ok: true });
  if (req.method !== "POST") return jsonResponse({ error: "method_not_allowed" }, 405);

  let host: string | null = null;
  let target: Target | null = null;
  const service = serviceRoleClient();
  try {
    const body = await req.json().catch(() => ({}));
    const blockId = typeof body.block_id === "string" ? body.block_id : null;
    if (!blockId) throw new HttpError("block_id required", 400);

    const { client } = await userScopedClient(req);
    const { data, error } = await client.rpc("planning_link_preview_target", { p_block_id: blockId });
    if (error) {
      if (error.message === "planning:rate_limited") {
        log(requestId, "rate_limited", started, null);
        return new Response(JSON.stringify({ error: "rate_limited" }), {
          status: 429,
          headers: { "Content-Type": "application/json", "Retry-After": "60" },
        });
      }
      if (error.message === "planning:not_found") throw new HttpError("not_found", 404);
      throw error;
    }
    target = data as Target;
    try {
      host = new URL(target.url).hostname;
    } catch {
      host = null;
    }

    const preview = await loadPreview(service, target.url);
    const text = { status: "ok", title: preview.title, description: preview.description, host: preview.host };
    const { data: applied } = await service.rpc("set_planning_link_preview",
      { p_block_id: target.block_id, p_url: target.url, p_preview: text });

    // The text preview is already visible; the image is a best-effort extra.
    if (applied && preview.image_url) {
      try {
        const path = await storeImage(service, target, preview.image_url);
        const { data: kept } = await service.rpc("set_planning_link_preview",
          { p_block_id: target.block_id, p_url: target.url, p_preview: { ...text, image_path: path } });
        if (!kept) await service.storage.from("planning-media").remove([path]);
      } catch (e) {
        log(requestId, `image_${e instanceof PreviewError ? e.code : "failed"}`, started, host);
      }
    }
    log(requestId, "ok", started, host);
    return jsonResponse({ ok: true });
  } catch (e) {
    if (e instanceof HttpError) {
      log(requestId, `http_${e.status}`, started, host);
      return jsonResponse({ error: e.message }, e.status);
    }
    const code = e instanceof PreviewError ? e.code : "error";
    if (target) {
      await service.rpc("set_planning_link_preview",
        { p_block_id: target.block_id, p_url: target.url, p_preview: { status: "failed", host } })
        .then(() => {}, () => {});
    }
    log(requestId, code, started, host);
    // A failed preview is an expected outcome, not a server error.
    return e instanceof PreviewError ? jsonResponse({ ok: false, code }) : jsonResponse({ error: "internal" }, 500);
  }
});

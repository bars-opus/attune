// supabase/functions/scan-media/objects.ts
//
// Spec 1 W7b (B6 fix I-2): how scan-media reads an object. storage-js
// (2.39) can only download a whole object and can't abort one, so this
// talks to Storage's REST API with the service role:
//   head: GET with `Range: bytes=0-4095`, enough to sniff the kind, and the
//     size from Content-Range. A server that ignores the Range is read only
//     to 4 KiB, then the body is cancelled. A refused Range (416) is read
//     again without one (never assumed empty).
//   read: GET of the whole object, only for an image, refused without
//     reading the body when Content-Length is over [maxBytes], and stopped
//     just past [maxBytes] when there is no length (`unavailable:too_large`).
// Every request has an AbortController that fires when its time is up, so
// a hung request or body is aborted, not abandoned (`download_timeout`).
// Only "object not found" is a missing object (`skipped:object_missing`,
// B6 M-11); any other error, a "Bucket not found" included, is
// `unavailable:download_failed`, so it is retried and, after 24 hours, a
// person hears. Never logs; never throws.
import type { FetchLike } from "../_shared/timed_fetch.ts";

export const HEAD_BYTES = 4096;

export type ReadFailure = { ok: false; outcome: "skipped" | "unavailable"; reason: string };
/// [whole]: these bytes are the entire object (B6 N-1). Only then may the
/// handler skip the full read; an unknown size is never taken for whole.
export type HeadResult = { ok: true; bytes: Uint8Array; size: number | null; whole: boolean } | ReadFailure;
export type ReadResult = { ok: true; bytes: Uint8Array } | ReadFailure;

export interface ObjectReader {
  /// The first HEAD_BYTES bytes (fewer for a smaller object) and the
  /// object's size when Storage says it.
  head(bucket: string, path: string): Promise<HeadResult>;
  /// The whole object, at most [maxBytes].
  read(bucket: string, path: string, maxBytes: number): Promise<ReadResult>;
}

const TIMED_OUT: ReadFailure = { ok: false, outcome: "unavailable", reason: "download_timeout" };
const FAILED: ReadFailure = { ok: false, outcome: "unavailable", reason: "download_failed" };
const MISSING: ReadFailure = { ok: false, outcome: "skipped", reason: "object_missing" };
const TOO_LARGE: ReadFailure = { ok: false, outcome: "unavailable", reason: "too_large" };

export function objectUrl(base: string, bucket: string, path: string): string {
  const root = base.trim().replace(/\/+$/, "");
  const key = path.split("/").map(encodeURIComponent).join("/");
  return `${root}/storage/v1/object/${encodeURIComponent(bucket)}/${key}`;
}

function sizeFrom(response: Response): number | null {
  const range = response.headers.get("content-range");
  if (response.status === 206) {
    const m = /^bytes\s+\d+-\d+\/(\d+)\s*$/i.exec(range ?? "");
    return m ? Number(m[1]) : null;
  }
  const length = response.headers.get("content-length");
  return length !== null && /^\d+$/.test(length.trim()) ? Number(length) : null;
}

async function cancel(response: Response): Promise<void> {
  try {
    await response.body?.cancel();
  } catch {
    // nothing to release
  }
}

/// Up to [limit] bytes of the body; `more` when the body had more (the
/// rest is cancelled, never read).
async function readUpTo(response: Response, limit: number): Promise<{ bytes: Uint8Array; more: boolean }> {
  if (!response.body) return { bytes: new Uint8Array(0), more: false };
  const reader = response.body.getReader();
  const chunks: Uint8Array[] = [];
  let total = 0;
  let more = false;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      chunks.push(value);
      total += value.length;
      if (total >= limit) {
        if (total > limit) more = true;
        else more = !(await reader.read()).done;
        break;
      }
    }
  } finally {
    try {
      await reader.cancel();
    } catch {
      // already closed
    }
  }
  const out = new Uint8Array(Math.min(total, limit));
  let at = 0;
  for (const c of chunks) {
    if (at >= out.length) break;
    const take = c.subarray(0, out.length - at);
    out.set(take, at);
    at += take.length;
  }
  return { bytes: out, more };
}

/// A failed answer: missing only for "object not found".
async function failure(response: Response): Promise<ReadFailure> {
  try {
    const { bytes } = await readUpTo(response, 4096);
    const body = JSON.parse(new TextDecoder().decode(bytes)) as Record<string, unknown>;
    const error = typeof body?.error === "string" ? body.error : "";
    const message = typeof body?.message === "string" ? body.message : "";
    if (error === "not_found" || /\bobject not found\b/i.test(message)) return MISSING;
  } catch {
    // not JSON: not a known answer
  }
  return FAILED;
}

export function storageObjectReader(config: {
  url: string;
  key: string;
  fetch?: FetchLike;
  headTimeoutMs?: number;
  readTimeoutMs?: number;
}): ObjectReader {
  const f = config.fetch ?? fetch;
  const auth = { Authorization: `Bearer ${config.key}`, apikey: config.key };
  const headMs = config.headTimeoutMs ?? 5_000;
  const readMs = config.readTimeoutMs ?? 10_000;

  /// One request under its own AbortController; an abort is a timeout,
  /// anything else thrown is a failure.
  async function bounded<T>(ms: number, work: (signal: AbortSignal) => Promise<T | ReadFailure>): Promise<T | ReadFailure> {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(new DOMException("scan-media read timed out", "TimeoutError")), ms);
    try {
      return await work(controller.signal);
    } catch {
      return controller.signal.aborted ? TIMED_OUT : FAILED;
    } finally {
      clearTimeout(timer);
    }
  }

  return {
    head(bucket, path) {
      const url = objectUrl(config.url, bucket, path);
      return bounded<HeadResult>(headMs, async (signal) => {
        let response = await f(url, { headers: { ...auth, Range: `bytes=0-${HEAD_BYTES - 1}` }, signal });
        if (response.status === 416) {
          await cancel(response);
          response = await f(url, { headers: { ...auth }, signal });
        }
        if (!response.ok) return await failure(response);
        const size = sizeFrom(response);
        const { bytes, more } = await readUpTo(response, HEAD_BYTES);
        // Whole: the body ended inside 4 KiB and was the whole answer (a 200,
        // or a 206 whose stated total is exactly what came).
        const whole = !more && (response.status === 200 ? size === null || size === bytes.length : size === bytes.length);
        return { ok: true, bytes, size, whole };
      });
    },
    read(bucket, path, maxBytes) {
      const url = objectUrl(config.url, bucket, path);
      return bounded<ReadResult>(readMs, async (signal) => {
        const response = await f(url, { headers: { ...auth }, signal });
        if (!response.ok) return await failure(response);
        const declared = sizeFrom(response);
        if (declared !== null && declared > maxBytes) {
          await cancel(response);
          return TOO_LARGE;
        }
        const { bytes, more } = await readUpTo(response, maxBytes);
        return more ? TOO_LARGE : { ok: true, bytes };
      });
    },
  };
}

// deno-lint-ignore-file no-explicit-any
// supabase/functions/process-story-archival/archival.ts
//
// Stories Wave 5 (review 04 #7, #8, #9; 06 #23). The archival worker's logic,
// apart from Deno.serve so it can be tested with a fake client.
//
// Ordering is load-bearing (STORIES.md §4.4): make the new rendition, check
// it, store it at the deterministic archive key, THEN conditionally swap the
// key (complete_story_archival, which also queues the old key behind the
// signed-URL TTL). A rendition that fails any check is never stored or
// swapped; the job fails with a code and is retried (5 attempts, then dead
// letter), and the original stays.

export const LONG_EDGE = 1600;
const BUCKET = "story-media";

export type ArchivalJob = { story_id: string; media_key: string; media_width: number; media_height: number };
export type RenditionTransform = { width?: number; height?: number; resize: "contain"; quality: 80; format: "origin" };

/** The transform that brings the long edge to 1600 px, or null if it already is (04 #7). */
export function renditionTransform(width: number, height: number): RenditionTransform | null {
  if (Math.max(width, height) <= LONG_EDGE) return null;
  return width >= height
    ? { width: LONG_EDGE, resize: "contain", quality: 80, format: "origin" }
    : { height: LONG_EDGE, resize: "contain", quality: 80, format: "origin" };
}

/** Width and height from a whole JPEG's first frame header; null if it is not one. */
export function jpegDimensions(b: Uint8Array): { width: number; height: number } | null {
  if (b.length < 4 || b[0] !== 0xff || b[1] !== 0xd8) return null;
  if (b[b.length - 2] !== 0xff || b[b.length - 1] !== 0xd9) return null; // truncated
  let i = 2;
  while (i + 3 < b.length) {
    if (b[i] !== 0xff) return null;
    const marker = b[i + 1];
    if (marker === 0xff) { i += 1; continue; } // fill byte
    if (marker === 0x01 || (marker >= 0xd0 && marker <= 0xd8)) { i += 2; continue; }
    if (marker === 0xd9 || marker === 0xda) return null; // end, or scan before any frame header
    const length = (b[i + 2] << 8) | b[i + 3];
    if (length < 2) return null;
    const isFrame = marker >= 0xc0 && marker <= 0xcf && marker !== 0xc4 && marker !== 0xc8 && marker !== 0xcc;
    if (isFrame) {
      if (i + 8 >= b.length) return null;
      const height = (b[i + 5] << 8) | b[i + 6];
      const width = (b[i + 7] << 8) | b[i + 8];
      return width > 0 && height > 0 ? { width, height } : null;
    }
    i += 2 + length;
  }
  return null;
}

/** Whether the original's reported size is usable (review B5 #5: NaN made the aspect check vacuous). */
function hasDimensions(job: ArchivalJob): boolean {
  const w = Number(job.media_width);
  const h = Number(job.media_height);
  return Number.isFinite(w) && w > 0 && Number.isFinite(h) && h > 0;
}

/**
 * Null if [bytes] may replace the original of [job]; else why not (04 #8).
 * The long edge must be the one asked for, ±1 px: 1600, or the original's
 * own when it is already within 1600 (the worker skips those, so that case
 * only ever accepts a same-size re-encode, never an upscale). A rendition
 * shrunk too far would otherwise replace the original for good (review B5 #2).
 */
export function validateRendition(bytes: Uint8Array, contentType: string, job: ArchivalJob): string | null {
  if (!hasDimensions(job)) return "bad_dimensions";
  if (bytes.byteLength === 0) return "empty_rendition";
  const type = (contentType ?? "").toLowerCase();
  if (type !== "" && !type.startsWith("image/jpeg")) return "not_jpeg";
  const dims = jpegDimensions(bytes);
  if (!dims) return "undecodable";
  const expected = Math.min(LONG_EDGE, Math.max(Number(job.media_width), Number(job.media_height)));
  if (Math.abs(Math.max(dims.width, dims.height) - expected) > 1) return "wrong_size";
  const want = Number(job.media_width) / Number(job.media_height);
  const got = dims.width / dims.height;
  if (Math.abs(got - want) / want > 0.02) return "wrong_aspect";
  return null;
}

export type ArchivalOptions = {
  batch: number;
  concurrency: number;
  budgetMs: number;
  now?: () => number;
  log?: (line: string) => void;
};

/**
 * Per run: claim for up to 45 s, 4 at a time, all 4 started at once (04 #9).
 * A claimed job never waits behind another wave, so it ends within one
 * worst-case wave (5 calls x 20 s) of its claim: well inside the 5-minute
 * lease, and budget + one wave stays under the 150 s background wall clock
 * (review B5 #3). `batch` caps a claim; a claim never exceeds `concurrency`.
 */
export const ARCHIVAL_DEFAULTS: ArchivalOptions = { batch: 4, concurrency: 4, budgetMs: 45_000 };

export type RunSummary = {
  claimed: number;
  processed: number;
  skipped: number;
  failed: number;
  codes: Record<string, number>;
  ms: number;
};

class ArchivalError extends Error {
  constructor(readonly code: string) {
    super(code);
  }
}

function codeOf(error: unknown): string {
  if (error instanceof ArchivalError) return error.code;
  if (error instanceof Error && error.name && error.name !== "Error") return error.name.slice(0, 60);
  return "unexpected";
}

type Outcome = { outcome: "processed" | "skipped" | "failed"; code?: string };

async function archiveOne(supabase: any, job: ArchivalJob): Promise<Outcome> {
  const storyId = String(job.story_id);
  try {
    if (!hasDimensions(job)) throw new ArchivalError("bad_dimensions");
    const transform = renditionTransform(Number(job.media_width), Number(job.media_height));
    if (!transform) {
      const { error } = await supabase.rpc("skip_story_archival", { p_story_id: storyId });
      if (error) throw new ArchivalError("skip_failed");
      return { outcome: "skipped", code: "already_small" };
    }
    // The archive key comes from the same SQL function complete and delete use.
    const { data: keyResult, error: keyError } = await supabase.rpc("story_archive_key", { p_story_item_id: storyId });
    if (keyError) throw new ArchivalError("key_failed");
    const archiveKey = String(keyResult);

    const { data: image, error: downloadError } = await supabase.storage
      .from(BUCKET)
      .download(String(job.media_key), { transform });
    if (downloadError || !image) throw new ArchivalError("download_failed");
    const bytes = new Uint8Array(await image.arrayBuffer());
    const invalid = validateRendition(bytes, image.type ?? "", job);
    if (invalid) throw new ArchivalError(invalid);

    // upsert: an object left by an earlier attempt was never validated.
    const upload = await supabase.storage.from(BUCKET).upload(archiveKey, bytes, {
      contentType: "image/jpeg",
      upsert: true,
    });
    if (upload.error) throw new ArchivalError("upload_failed");

    const { data: completion, error: completeError } = await supabase.rpc("complete_story_archival", {
      p_story_id: storyId,
      p_new_key: archiveKey,
    });
    if (completeError) throw new ArchivalError("complete_failed");
    if (completion && typeof completion === "object" && (completion as Record<string, unknown>).error === true) {
      throw new ArchivalError(String((completion as Record<string, unknown>).code ?? "complete_failed"));
    }
    return { outcome: "processed" };
  } catch (error) {
    const code = codeOf(error);
    const { error: failError } = await supabase.rpc("fail_story_archival", { p_story_id: storyId, p_error_code: code });
    // A failure to record the failure is surfaced, not swallowed.
    if (failError) throw new ArchivalError("fail_record_failed");
    return { outcome: "failed", code };
  }
}

/** Claims and archives until a short claim or the time budget; one log line, always. */
export async function runArchival(supabase: any, options: ArchivalOptions = ARCHIVAL_DEFAULTS): Promise<RunSummary> {
  const now = options.now ?? Date.now;
  const started = now();
  const limit = Math.max(1, Math.min(options.batch, options.concurrency));
  const summary: RunSummary = { claimed: 0, processed: 0, skipped: 0, failed: 0, codes: {}, ms: 0 };
  const count = (outcome: Outcome["outcome"], code?: string) => {
    summary[outcome] += 1;
    if (code) summary.codes[code] = (summary.codes[code] ?? 0) + 1;
  };
  try {
    while (now() - started < options.budgetMs) {
      const { data, error } = await supabase.rpc("claim_story_archival_batch", { p_limit: limit });
      if (error) throw new ArchivalError("claim_failed");
      const jobs = (data ?? []) as ArchivalJob[];
      if (jobs.length === 0) break;
      summary.claimed += jobs.length;
      // allSettled: one job whose failure cannot be recorded (its lease runs
      // out instead) does not abandon the others or the log line (review B5 #4).
      const results = await Promise.allSettled(jobs.map((job) => archiveOne(supabase, job)));
      for (const r of results) {
        if (r.status === "fulfilled") count(r.value.outcome, r.value.code);
        else count("failed", codeOf(r.reason));
      }
      if (jobs.length < limit) break;
    }
  } finally {
    summary.ms = now() - started;
    (options.log ?? console.log)(JSON.stringify({ fn: "process-story-archival", ...summary }));
  }
  return summary;
}

/**
 * fetch's call shape. Deno 2.8's `typeof fetch` is a union of overloads whose
 * `init` cannot be read for `signal`, so the wrapper is typed by this.
 */
export type FetchLike = (input: RequestInfo | URL, init?: RequestInit) => Promise<Response>;

/** A fetch that gives up after [ms] (06 #23): a hung transform no longer holds the run. */
export function timedFetch(ms: number, base: FetchLike = fetch): FetchLike {
  return (input, init) => {
    const timeout = AbortSignal.timeout(ms);
    const signal = init?.signal ? AbortSignal.any([init.signal, timeout]) : timeout;
    return base(input, { ...init, signal });
  };
}

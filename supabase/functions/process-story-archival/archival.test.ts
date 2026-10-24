// supabase/functions/process-story-archival/archival.test.ts
// Stories Wave 5 (04 #7, #8, #9; 06 #23): long-edge resize, a validated
// rendition before any swap, batches within a time budget, timeouts, logs.
import { assert, assertEquals, assertRejects } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  ARCHIVAL_DEFAULTS,
  type ArchivalJob,
  type FetchLike,
  jpegDimensions,
  renditionTransform,
  runArchival,
  timedFetch,
  validateRendition,
} from "./archival.ts";

/** A minimal, structurally whole JPEG: SOI, APP0, SOF0 (w x h), SOS, EOI. */
function fakeJpeg(width: number, height: number, { truncated = false } = {}): Uint8Array {
  const app0 = [0xff, 0xe0, 0x00, 0x10, 0x4a, 0x46, 0x49, 0x46, 0x00, 0x01, 0x01, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00];
  const sof0 = [0xff, 0xc0, 0x00, 0x11, 0x08, height >> 8, height & 0xff, width >> 8, width & 0xff, 0x03,
    0x01, 0x22, 0x00, 0x02, 0x11, 0x01, 0x03, 0x11, 0x01];
  const sos = [0xff, 0xda, 0x00, 0x0c, 0x03, 0x01, 0x00, 0x02, 0x11, 0x03, 0x11, 0x00, 0x3f, 0x00, 0x12, 0x34];
  const bytes = [0xff, 0xd8, ...app0, ...sof0, ...sos, ...(truncated ? [] : [0xff, 0xd9])];
  return new Uint8Array(bytes);
}

const portrait: ArchivalJob = { story_id: "s1", media_key: "story-media/r/u/1-media", media_width: 1440, media_height: 2560 };

Deno.test("long edge: portrait by height, landscape and square by width, small left alone", () => {
  assertEquals(renditionTransform(1440, 2560), { height: 1600, resize: "contain", quality: 80, format: "origin" });
  assertEquals(renditionTransform(2560, 1440), { width: 1600, resize: "contain", quality: 80, format: "origin" });
  assertEquals(renditionTransform(2000, 2000), { width: 1600, resize: "contain", quality: 80, format: "origin" });
  assertEquals(renditionTransform(1080, 1600), null);
  assertEquals(renditionTransform(900, 1200), null);
});

Deno.test("jpegDimensions reads the frame header and refuses anything else", () => {
  assertEquals(jpegDimensions(fakeJpeg(900, 1600)), { width: 900, height: 1600 });
  assertEquals(jpegDimensions(fakeJpeg(900, 1600, { truncated: true })), null, "no EOI: truncated");
  assertEquals(jpegDimensions(new Uint8Array()), null);
  assertEquals(jpegDimensions(new Uint8Array([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])), null, "PNG");
  assertEquals(jpegDimensions(new Uint8Array([0xff, 0xd8, 0xff, 0xd9])), null, "no frame header");
});

Deno.test("validateRendition: only a whole, right-sized, right-shaped JPEG passes", () => {
  assertEquals(validateRendition(fakeJpeg(900, 1600), "image/jpeg", portrait), null);
  assertEquals(validateRendition(fakeJpeg(900, 1600), "", portrait), null, "untyped but a JPEG");
  assertEquals(validateRendition(new Uint8Array(), "image/jpeg", portrait), "empty_rendition");
  assertEquals(validateRendition(fakeJpeg(900, 1600), "image/webp", portrait), "not_jpeg");
  assertEquals(validateRendition(fakeJpeg(900, 1600, { truncated: true }), "image/jpeg", portrait), "undecodable");
  assertEquals(validateRendition(fakeJpeg(1440, 2560), "image/jpeg", portrait), "wrong_size", "not downscaled");
  assertEquals(validateRendition(fakeJpeg(1600, 900), "image/jpeg", portrait), "wrong_aspect", "rotated");
  assertEquals(validateRendition(fakeJpeg(1200, 1600), "image/jpeg", portrait), "wrong_aspect", "stretched");
  // Review B5 #2: the long edge must be the size asked for, not merely under it.
  assertEquals(validateRendition(fakeJpeg(90, 160), "image/jpeg", portrait), "wrong_size", "over-shrunk");
  assertEquals(validateRendition(fakeJpeg(899, 1599), "image/jpeg", portrait), null, "1 px under");
  assertEquals(validateRendition(fakeJpeg(900, 1598), "image/jpeg", portrait), "wrong_size", "2 px under");
  // Review B5 #5: no usable original size, nothing to compare against.
  for (const [w, h] of [[NaN, 2560], [1440, 0], [undefined, 2560], [-1, 2560]]) {
    assertEquals(
      validateRendition(fakeJpeg(1600, 900), "image/jpeg", { ...portrait, media_width: w as number, media_height: h as number }),
      "bad_dimensions",
      `${w}x${h}`,
    );
  }
});

Deno.test("an original within 1600 px is never re-encoded, so its expected long edge is its own", () => {
  // The worker skips these (renditionTransform is null). Were one ever
  // re-encoded, only a same-size rendition would pass: never an upscale.
  const small: ArchivalJob = { story_id: "s", media_key: "k", media_width: 900, media_height: 1200 };
  assertEquals(renditionTransform(900, 1200), null);
  assertEquals(validateRendition(fakeJpeg(900, 1200), "image/jpeg", small), null);
  assertEquals(validateRendition(fakeJpeg(1200, 1600), "image/jpeg", small), "wrong_size", "upscaled");
  assertEquals(validateRendition(fakeJpeg(1080, 1600), "image/jpeg", { ...small, media_width: 1080, media_height: 1600 }), null);
});

type Call = { fn: string; params: Record<string, unknown> };

function fakeClient(opts: {
  batches: ArchivalJob[][];
  rendition?: (job: string) => { bytes: Uint8Array; type: string } | null;
  uploadError?: boolean;
  completeResult?: Record<string, unknown>;
  failError?: (storyId: string) => boolean;
  claimError?: boolean;
}) {
  const calls: Call[] = [];
  const downloads: { key: string; transform: unknown }[] = [];
  const uploads: { key: string; size: number; upsert: boolean; contentType: string }[] = [];
  let inFlight = 0;
  let maxInFlight = 0;
  const batches = opts.batches.map((b) => [...b]);
  const client = {
    rpc: (fn: string, params: Record<string, unknown> = {}) => {
      calls.push({ fn, params });
      if (fn === "claim_story_archival_batch") {
        if (opts.claimError) return Promise.resolve({ data: null, error: { message: "claim down" } });
        // Honours p_limit: a batch longer than the limit is handed out in parts.
        const head = batches[0] ?? [];
        const taken = head.splice(0, Number(params.p_limit));
        if (head.length === 0) batches.shift();
        return Promise.resolve({ data: taken, error: null });
      }
      if (fn === "story_archive_key") return Promise.resolve({ data: `story-archive/${params.p_story_item_id}.jpg`, error: null });
      if (fn === "complete_story_archival") {
        return Promise.resolve({ data: opts.completeResult ?? { error: false, swapped: true }, error: null });
      }
      if (fn === "fail_story_archival" && opts.failError?.(String(params.p_story_id))) {
        return Promise.resolve({ data: null, error: { message: "fail down" } });
      }
      return Promise.resolve({ data: { error: false }, error: null });
    },
    storage: {
      from: (_bucket: string) => ({
        download: async (key: string, o: { transform: unknown }) => {
          downloads.push({ key, transform: o?.transform });
          inFlight++;
          maxInFlight = Math.max(maxInFlight, inFlight);
          await new Promise((r) => setTimeout(r, 1));
          inFlight--;
          const r = opts.rendition ? opts.rendition(key) : { bytes: fakeJpeg(900, 1600), type: "image/jpeg" };
          if (!r) return { data: null, error: { status: 500, message: "transform failed" } };
          return { data: new Blob([r.bytes as BlobPart], { type: r.type }), error: null };
        },
        upload: (key: string, body: Uint8Array, o: { upsert: boolean; contentType: string }) => {
          if (opts.uploadError) return Promise.resolve({ error: { message: "upload down" } });
          uploads.push({ key, size: body.byteLength, upsert: o.upsert, contentType: o.contentType });
          return Promise.resolve({ error: null });
        },
      }),
    },
  };
  return { client, calls, downloads, uploads, maxInFlight: () => maxInFlight };
}

const job = (id: string, w = 1440, h = 2560): ArchivalJob => ({ story_id: id, media_key: `story-media/r/u/${id}-media`, media_width: w, media_height: h });
const quiet = { batch: 20, concurrency: 4, budgetMs: 60_000, log: () => {} };

Deno.test("a portrait story: height-1600 transform, validated upload (upsert), then the swap", async () => {
  const f = fakeClient({ batches: [[job("s1")]] });
  const s = await runArchival(f.client, quiet);
  assertEquals(f.downloads[0].transform, { height: 1600, resize: "contain", quality: 80, format: "origin" });
  assertEquals(f.uploads, [{ key: "story-archive/s1.jpg", size: fakeJpeg(900, 1600).byteLength, upsert: true, contentType: "image/jpeg" }]);
  const order = f.calls.map((c) => c.fn).filter((fn) => fn !== "claim_story_archival_batch");
  assertEquals(order, ["story_archive_key", "complete_story_archival"]);
  assertEquals([s.processed, s.failed, s.skipped], [1, 0, 0]);
});

Deno.test("a small image is skipped: no download, no upload, no swap", async () => {
  const f = fakeClient({ batches: [[job("s2", 1080, 1600)]] });
  const s = await runArchival(f.client, quiet);
  assertEquals(f.downloads.length, 0);
  assertEquals(f.uploads.length, 0);
  assert(f.calls.some((c) => c.fn === "skip_story_archival" && c.params.p_story_id === "s2"));
  assert(!f.calls.some((c) => c.fn === "complete_story_archival"));
  assertEquals(s.skipped, 1);
});

Deno.test("an invalid rendition is never uploaded or swapped; the job fails with its code", async () => {
  for (const [bytes, type, code] of [
    [new Uint8Array(), "image/jpeg", "empty_rendition"],
    [fakeJpeg(900, 1600), "image/webp", "not_jpeg"],
    [fakeJpeg(900, 1600, { truncated: true }), "image/jpeg", "undecodable"],
    [fakeJpeg(1440, 2560), "image/jpeg", "wrong_size"],
    [fakeJpeg(1600, 900), "image/jpeg", "wrong_aspect"],
    [fakeJpeg(90, 160), "image/jpeg", "wrong_size"],
  ] as const) {
    const f = fakeClient({ batches: [[job("s3")]], rendition: () => ({ bytes, type }) });
    const s = await runArchival(f.client, quiet);
    assertEquals(f.uploads.length, 0, code);
    assert(!f.calls.some((c) => c.fn === "complete_story_archival"), code);
    const fail = f.calls.find((c) => c.fn === "fail_story_archival")!;
    assertEquals(fail.params, { p_story_id: "s3", p_error_code: code });
    assertEquals(s.codes[code], 1);
  }
});

Deno.test("throughput: claims `concurrency` at a time until a short claim, at most 4 at a time", async () => {
  const many = Array.from({ length: 20 }, (_, i) => job(`a${i}`));
  const f = fakeClient({ batches: [many, [job("b1"), job("b2")]] });
  const s = await runArchival(f.client, quiet);
  // Review B5 #3: every claimed job starts at once, well inside its lease.
  const claims = f.calls.filter((c) => c.fn === "claim_story_archival_batch");
  assert(claims.every((c) => c.params.p_limit === 4), JSON.stringify(claims));
  assertEquals(claims.length, 6);
  assertEquals(s.processed, 22);
  assert(f.maxInFlight() <= 4 && f.maxInFlight() > 1, `in flight ${f.maxInFlight()}`);
});

Deno.test("the time budget stops further claims (each claimed batch is finished)", async () => {
  let t = 0;
  const f = fakeClient({ batches: [[job("c1")], [job("c2")], [job("c3")]] });
  const s = await runArchival(f.client, {
    batch: 1, concurrency: 1, budgetMs: 100, log: () => {},
    now: () => (t += 60),
  });
  assert(s.claimed < 3, `claimed ${s.claimed}`);
  assertEquals(s.processed, s.claimed);
});

Deno.test("one log line per run: counts and codes, never an id or a key", async () => {
  const lines: string[] = [];
  const f = fakeClient({ batches: [[job("secret-story-id"), job("small", 800, 600)]] });
  await runArchival(f.client, { ...quiet, log: (l) => lines.push(l) });
  assertEquals(lines.length, 1);
  const parsed = JSON.parse(lines[0]);
  assertEquals(parsed.fn, "process-story-archival");
  assertEquals([parsed.processed, parsed.skipped], [1, 1]);
  assert(!lines[0].includes("secret-story-id") && !lines[0].includes("story-media/"), lines[0]);
});

Deno.test("timedFetch aborts a call that hangs", async () => {
  const hanging: FetchLike = (_input, init) =>
    new Promise((_resolve, reject) => {
      init?.signal?.addEventListener("abort", () => reject(init.signal!.reason));
    });
  const started = Date.now();
  await assertRejects(() => timedFetch(30, hanging)("https://x.invalid/"));
  assert(Date.now() - started < 2000);
});

Deno.test("index.ts: service role first, background run, timed client", async () => {
  const src = await Deno.readTextFile(new URL("./index.ts", import.meta.url));
  const auth = src.indexOf("requireServiceRole(req)");
  const run = src.indexOf("runArchival(");
  assert(auth > -1 && run > auth, "auth before work");
  assert(src.includes("waitUntil"), "the cron's call returns at once");
  assert(src.includes("timedFetch("), "every Storage/RPC call is bounded");
});

Deno.test("defaults keep a run inside the platform wall clock and the 5-minute lease", () => {
  // One wave worst case: key + download + upload + complete + fail, 20 s each.
  const wave = 5 * 20_000;
  assert(ARCHIVAL_DEFAULTS.budgetMs + wave <= 150_000, `budget ${ARCHIVAL_DEFAULTS.budgetMs}`);
  assert(ARCHIVAL_DEFAULTS.batch <= ARCHIVAL_DEFAULTS.concurrency, "a claimed job never waits for a wave");
});

Deno.test("no usable original size: failed before any transform", async () => {
  const f = fakeClient({ batches: [[{ story_id: "d1", media_key: "story-media/r/u/d1-media" } as unknown as ArchivalJob]] });
  const s = await runArchival(f.client, quiet);
  assertEquals([f.downloads.length, f.uploads.length], [0, 0]);
  assert(!f.calls.some((c) => c.fn === "complete_story_archival" || c.fn === "skip_story_archival"));
  assertEquals(f.calls.find((c) => c.fn === "fail_story_archival")!.params, { p_story_id: "d1", p_error_code: "bad_dimensions" });
  assertEquals(s.codes.bad_dimensions, 1);
});

Deno.test("download, upload and complete failures never swap; each fails with its code", async () => {
  const cases: [Parameters<typeof fakeClient>[0], string, number][] = [
    [{ batches: [[job("e1")]], rendition: () => null }, "download_failed", 0],
    [{ batches: [[job("e1")]], uploadError: true }, "upload_failed", 0],
    [{ batches: [[job("e1")]], completeResult: { error: true, code: "INVALID_INPUT" } }, "INVALID_INPUT", 1],
  ];
  for (const [opts, code, completes] of cases) {
    const f = fakeClient(opts);
    const s = await runArchival(f.client, quiet);
    assertEquals(f.calls.filter((c) => c.fn === "complete_story_archival").length, completes, code);
    assertEquals(f.calls.find((c) => c.fn === "fail_story_archival")!.params, { p_story_id: "e1", p_error_code: code });
    assertEquals([s.failed, s.processed, s.codes[code]], [1, 0, 1], code);
  }
});

Deno.test("a failure to record a failure: the others still run and the run still logs", async () => {
  const lines: string[] = [];
  const f = fakeClient({
    batches: [[job("f1"), job("f2"), job("f3")]],
    rendition: (key) => key.includes("f1") ? null : { bytes: fakeJpeg(900, 1600), type: "image/jpeg" },
    failError: (id) => id === "f1",
  });
  const s = await runArchival(f.client, { ...quiet, log: (l) => lines.push(l) });
  assertEquals([s.processed, s.failed, s.codes.fail_record_failed], [2, 1, 1]);
  assertEquals(lines.length, 1);
});

Deno.test("a claim that errors throws claim_failed, after its one log line", async () => {
  const lines: string[] = [];
  const f = fakeClient({ batches: [], claimError: true });
  await assertRejects(() => runArchival(f.client, { ...quiet, log: (l) => lines.push(l) }), Error, "claim_failed");
  assertEquals(lines.length, 1);
  assert(!lines[0].includes("claim down"), lines[0]);
});

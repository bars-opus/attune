// Spec 1 W7b (§4.5, §7.2): scan-media against a fake database and storage.
// Stub matcher match / clear / unavailable; the quarantine copy before the
// record; with get_attune_environment() = production the stub clears
// nothing; the kind of an object is read from its bytes, never its stored
// mime (B4 I-3): images go to the matcher, videos and everything else are
// skipped, never clear; vanished objects are skipped; a match reaches the
// safety webhook at once, as a count. Every answer carries the claim's
// lease. One job is claimed at a time inside a run budget, so work the run
// can't reach stays unclaimed for the next minute.
import { type CsamMatcher, matcherFromEnv, MATCHER_MAX_TIMEOUT_MS, PHOTODNA_MAX_BYTES, stubMatcher } from "../_shared/csam_matcher.ts";
import { quarantineBudget } from "../_shared/csam_match_path.ts";
import {
  ALERT_DEADLINE_MS,
  ALERT_POST_TIMEOUT_MS,
  ALERT_WORST_CASE_MS,
  BATCH,
  DOWNLOAD_TIMEOUT_MS,
  EDGE_WALL_CLOCK_MS,
  errorClass,
  HEAD_TIMEOUT_MS,
  JOB_WORST_CASE_MS,
  MAX_IMAGE_BYTES,
  readEnvironment,
  readJobs,
  RPC_TIMEOUT_MS,
  RUN_BUDGET_MS,
  type ScanClient,
  scanMedia,
} from "./handler.ts";

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

const enc = new TextEncoder();

function cat(...parts: (number[] | string | Uint8Array)[]): Uint8Array {
  const chunks = parts.map((p) => (typeof p === "string" ? enc.encode(p) : Uint8Array.from(p)));
  const out = new Uint8Array(chunks.reduce((n, c) => n + c.length, 0));
  let at = 0;
  for (const c of chunks) {
    out.set(c, at);
    at += c.length;
  }
  return out;
}

const PNG_SIGNATURE = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];
const png = (text: string) => cat(PNG_SIGNATURE, text);
/// The stub's answers, as GIFs (the stub's image test hashes).
const gif = (text: string) => cat("GIF89a", text);
const jpeg = (text: string) => cat([0xff, 0xd8, 0xff, 0xe0], text);
/// An ISO BMFF file: size, "ftyp", the major brand, a minor version, the compatible brands.
const ftyp = (major: string, ...compatible: string[]) => {
  const body = `ftyp${major}\0\0\0\0${compatible.join("")}`;
  return cat([0, 0, 0, 4 + body.length], body, [0, 0, 0, 8], "mdat");
};

interface Rig {
  client: ScanClient;
  log: string[];
  completes: Record<string, unknown>[];
  claims: Record<string, unknown>[];
  /// Each quarantine upload's declared type.
  contentTypes: string[];
}

/// An object in the fake storage: its bytes; `null` a storage error;
/// "hang" a head that never answers; `{hangRead}` an object whose full read
/// never answers; `{size, head}` a large object only its first bytes of
/// which exist here; `{changed}` bytes that differ between the head and the
/// full read; `{malformed}` a head with no bytes.
type ObjectBody =
  | Uint8Array
  | string
  | null
  | "hang"
  | { hangRead: Uint8Array }
  | { size: number; head: Uint8Array }
  | { changed: [Uint8Array, Uint8Array] }
  | { unknownSize: Uint8Array }
  | { malformed: true };

const HEAD = 4096;

function rig(
  jobs: Record<string, unknown>[],
  objects: Record<string, ObjectBody>,
  o: {
    quarantineFails?: boolean;
    completeFails?: boolean;
    completeThrows?: boolean;
    claimFailsAfter?: number;
    csamDue?: boolean;
  } = {},
): Rig {
  const log: string[] = [];
  const completes: Record<string, unknown>[] = [];
  const claims: Record<string, unknown>[] = [];
  const contentTypes: string[] = [];
  const queue = [...jobs];
  const bytesOf = (body: Uint8Array | string) => (typeof body === "string" ? enc.encode(body) : body);
  const client: ScanClient = {
    rpc(fn, args) {
      log.push(`rpc ${fn}`);
      if (fn === "claim_media_scan_jobs") {
        claims.push(args ?? {});
        if (o.claimFailsAfter !== undefined && claims.length > o.claimFailsAfter) {
          return Promise.resolve({ data: null, error: { message: "boom" } });
        }
        // The database's claim: at most p_limit due jobs, each claimed once.
        return Promise.resolve({ data: queue.splice(0, Number(args?.p_limit ?? 1)), error: null });
      }
      if (fn === "complete_media_scan") {
        completes.push(args ?? {});
        if (o.completeThrows) return Promise.reject(new Error("network"));
        return Promise.resolve({ data: null, error: o.completeFails ? { message: "boom" } : null });
      }
      if (fn === "csam_escalations_due" && o.csamDue !== false) {
        return Promise.resolve({ data: { ids: [1], count: 1, first_at: "t1", last_at: "t1" }, error: null });
      }
      if (fn.endsWith("_due")) {
        return Promise.resolve({ data: { ids: [], count: 0, first_at: null, last_at: null }, error: null });
      }
      return Promise.resolve({ data: null, error: null });
    },
    objects: {
      head(bucket, path) {
        log.push(`head ${bucket}/${path}`);
        const body = objects[`${bucket}/${path}`];
        if (body === undefined) return Promise.resolve({ ok: false, outcome: "skipped", reason: "object_missing" });
        if (body === null) return Promise.resolve({ ok: false, outcome: "unavailable", reason: "download_failed" });
        if (body === "hang") return new Promise(() => {});
        if (typeof body === "object" && "malformed" in body) {
          return Promise.resolve({ ok: true, bytes: undefined as unknown as Uint8Array, size: 1, whole: false });
        }
        if (typeof body === "object" && "size" in body) {
          return Promise.resolve({ ok: true, bytes: body.head, size: body.size, whole: body.head.length === body.size });
        }
        // N-1: Storage gave no size: the first 4 KiB, not known to be whole.
        if (typeof body === "object" && "unknownSize" in body) {
          return Promise.resolve({ ok: true, bytes: body.unknownSize.subarray(0, HEAD), size: null, whole: body.unknownSize.length <= HEAD });
        }
        const whole = typeof body === "object" && "hangRead" in body
          ? body.hangRead
          : typeof body === "object" && "changed" in body
          ? body.changed[0]
          : bytesOf(body as Uint8Array | string);
        return Promise.resolve({ ok: true, bytes: whole.subarray(0, HEAD), size: whole.length, whole: whole.length <= HEAD });
      },
      read(bucket, path, maxBytes) {
        log.push(`read ${bucket}/${path} ${maxBytes}`);
        const body = objects[`${bucket}/${path}`];
        if (body === undefined || body === null || body === "hang") {
          return Promise.resolve({ ok: false, outcome: "unavailable", reason: "download_failed" });
        }
        if (typeof body === "object" && "hangRead" in body) return new Promise(() => {});
        if (typeof body === "object" && "malformed" in body) return Promise.resolve({ ok: false, outcome: "unavailable", reason: "download_failed" });
        if (typeof body === "object" && "size" in body) {
          return Promise.resolve(body.size > maxBytes ? { ok: false, outcome: "unavailable", reason: "too_large" } : { ok: true, bytes: body.head });
        }
        const whole = typeof body === "object" && "changed" in body
          ? body.changed[1]
          : typeof body === "object" && "unknownSize" in body
          ? body.unknownSize
          : bytesOf(body as Uint8Array | string);
        return Promise.resolve(whole.length > maxBytes ? { ok: false, outcome: "unavailable", reason: "too_large" } : { ok: true, bytes: whole });
      },
    },
    storage: {
      from(bucket) {
        return {
          upload(path, _body, options) {
            log.push(`upload ${bucket}/${path}`);
            contentTypes.push(options.contentType);
            return Promise.resolve({ error: o.quarantineFails ? { message: "Internal error", statusCode: "500" } : null });
          },
        };
      },
    },
  };
  return { client, log, completes, claims, contentTypes };
}

const job = (id: number, name: string, mime: string | null = "image/jpeg", bucket = "message-media") => ({
  id,
  bucket,
  object_name: name,
  owner_user_id: "5f7b0000-0000-0000-0000-000000000001",
  mime,
  attempts: 1,
  lease_id: `lease-${id}`,
});

const quietAlert = { webhook: undefined, post: () => Promise.resolve({ ok: true, status: 200 }) };

/// A matcher that records the mime it was asked with and answers clear.
function recordingMatcher(o: { supportsVideo?: boolean } = {}) {
  const seen: string[] = [];
  const matcher: CsamMatcher = {
    name: "recording",
    supportsVideo: o.supportsVideo ?? false,
    match(_bytes, mime) {
      seen.push(mime);
      return Promise.resolve({ outcome: "clear", vendor: "recording", vendorRef: null });
    },
  };
  return { seen, matcher };
}

// sanitizeOps: every bounded step clears its timer (no download or matcher timer is left behind).
Deno.test("stub: clear, match (quarantined first) and unavailable, each with its lease", { sanitizeOps: true }, async () => {
  const r = rig(
    [job(1, "a.jpg"), job(2, "b.jpg"), job(3, "c.jpg")],
    {
      "message-media/a.jpg": png("an ordinary photo"),
      "message-media/b.jpg": gif("attune-csam-stub-match"),
      "message-media/c.jpg": gif("attune-csam-stub-unavailable"),
    },
  );
  const result = await scanMedia(r.client, stubMatcher(), quietAlert);
  assert(result.claimed === 3 && result.clear === 1 && result.match === 1 && result.unavailable === 1, JSON.stringify(result));
  const byJob = Object.fromEntries(r.completes.map((c) => [c.p_job_id, c.p_result]));
  assert(byJob[1] === "clear" && byJob[2] === "match" && byJob[3] === "unavailable", JSON.stringify(byJob));
  assert(r.completes.every((c) => c.p_lease_id === `lease-${c.p_job_id}`), JSON.stringify(r.completes));
  const upload = r.log.findIndex((l) => l.startsWith("upload safety-quarantine/message-media/b.jpg/"));
  const record = r.log.findIndex((l, i) => i > upload && l === "rpc complete_media_scan");
  assert(upload > -1 && record > upload, r.log.join(" | "));
  const matched = r.completes.find((c) => c.p_job_id === 2);
  assert(matched?.p_vendor === "stub", "vendor recorded");
  assert(r.contentTypes.join(",") === "image/gif", `the copy is stored as what it is: ${r.contentTypes.join(",")}`);
  assert(
    typeof matched?.p_quarantine_path === "string" &&
      `upload safety-quarantine/${matched.p_quarantine_path}` === r.log[upload],
    "the escalation names the copy written",
  );
});

Deno.test("production: the stub is refused and clears nothing", async () => {
  const r = rig([job(1, "a.jpg"), job(2, "b.jpg")], {
    "message-media/a.jpg": png("an ordinary photo"),
    "message-media/b.jpg": gif("attune-csam-stub-match"),
  });
  const matcher = matcherFromEnv({ env: (n) => (n === "CSAM_MATCHER" ? "stub" : undefined), fetch, environment: "production" });
  const result = await scanMedia(r.client, matcher, quietAlert);
  assert(result.clear === 0 && result.match === 0 && result.unavailable === 2, JSON.stringify(result));
  assert(r.completes.every((c) => c.p_result === "unavailable" && c.p_vendor_ref === "stub_refused_in_production"), JSON.stringify(r.completes));
  assert(!r.log.some((l) => l.startsWith("upload")), "quarantined with a refused stub");
});

Deno.test("B4 I-3: the bytes decide image, video or other; the stored mime never does", async () => {
  const cases: [Record<string, unknown>, Uint8Array, string][] = [
    [job(1, "voice.mp3", "audio/mpeg"), jpeg("a jpeg stored as audio"), "clear:null"],
    [job(2, "blank", ""), png("a png with no mime"), "clear:null"],
    [job(3, "none", null), cat("GIF89a", "...."), "clear:null"],
    [job(4, "w.bin", "application/octet-stream"), cat("RIFF", [0, 0, 0, 0], "WEBPVP8 "), "clear:null"],
    [job(5, "h.heic", "text/plain"), ftyp("heic", "mif1heic"), "clear:null"],
    [job(6, "h.heif", "video/mp4"), ftyp("mif1", "mif1"), "clear:null"],
    [job(7, "clip.jpg", "image/jpeg", "story-media"), ftyp("isom", "isomiso2avc1mp41"), "skipped:video_not_hashed"],
    [job(8, "clip.png", "image/png", "story-media"), ftyp("qt  ", "qt  "), "skipped:video_not_hashed"],
    [job(9, "clip.gif", "image/gif"), cat([0x1a, 0x45, 0xdf, 0xa3], "webm"), "skipped:video_not_hashed"],
    [job(10, "notes.jpg", "image/jpeg"), enc.encode("just some text"), "skipped:not_image_or_video"],
    [job(11, "voice.m4a", "audio/mp4"), ftyp("M4A ", "M4A mp42isom"), "skipped:not_image_or_video"],
    [job(12, "empty.jpg", "image/jpeg"), new Uint8Array(0), "skipped:empty_object"],
  ];
  const objects = Object.fromEntries(cases.map(([j, bytes]) => [`${j.bucket}/${j.object_name}`, bytes]));
  const r = rig(cases.map(([j]) => j), objects);
  const { seen, matcher } = recordingMatcher();
  const result = await scanMedia(r.client, matcher, quietAlert);
  const got = cases.map(([j]) => {
    const c = r.completes.find((x) => x.p_job_id === j.id);
    return `${c?.p_result}:${c?.p_vendor_ref}`;
  });
  assert(got.join(",") === cases.map(([, , want]) => want).join(","), got.join(","));
  assert(
    seen.join(",") === "image/jpeg,image/png,image/gif,image/webp,image/heic,image/heif",
    `the matcher saw ${seen.join(",")}`,
  );
  assert(result.clear === 6 && result.skipped === 6 && result.claimed === 12, JSON.stringify(result));
  assert(r.completes.every((c) => c.p_lease_id === `lease-${c.p_job_id}`), "every answer carries its lease");
});

Deno.test("a video goes to a matcher that hashes video, with the sniffed type", async () => {
  const r = rig([job(1, "clip", null, "story-media")], { "story-media/clip": ftyp("mp42", "mp42isom") });
  const { seen, matcher } = recordingMatcher({ supportsVideo: true });
  const result = await scanMedia(r.client, matcher, quietAlert);
  assert(result.clear === 1 && seen.join(",") === "video/mp4", `${JSON.stringify(result)} ${seen.join(",")}`);
});

Deno.test("a vanished object is skipped; a read that fails or hangs is unavailable, never clear", async () => {
  const big = cat([0xff, 0xd8, 0xff, 0xe0], "x".repeat(10_000));
  const r = rig([job(1, "gone.jpg"), job(2, "x.jpg"), job(3, "slow.jpg"), job(4, "slow-body.jpg")], {
    "message-media/x.jpg": null,
    "message-media/slow.jpg": "hang",
    "message-media/slow-body.jpg": { hangRead: big },
  });
  const started = Date.now();
  const result = await scanMedia(r.client, stubMatcher(), quietAlert, { headTimeoutMs: 30, downloadTimeoutMs: 30 });
  assert(Date.now() - started < 2_000, "the read timeouts were not applied");
  assert(result.skipped === 1 && result.unavailable === 3 && result.clear === 0, JSON.stringify(result));
  const refs = r.completes.map((c) => `${c.p_result}:${c.p_vendor_ref}`);
  assert(
    refs.join(",") === "skipped:object_missing,unavailable:download_failed,unavailable:download_timeout,unavailable:download_timeout",
    refs.join(","),
  );
});

Deno.test("I-2: the kind comes from the head; only an image under the cap is read whole", async () => {
  const videoHead = ftyp("isom", "isomiso2avc1mp41");
  const largeImageHead = cat([0xff, 0xd8, 0xff, 0xe0], "x".repeat(4092));
  const mediumImage = cat([0xff, 0xd8, 0xff, 0xe0], "y".repeat(10_000));
  const r = rig(
    [job(1, "huge.mp4", "video/mp4", "story-media"), job(2, "huge.jpg"), job(3, "small.gif"), job(4, "medium.jpg"), job(5, "voice.m4a", "audio/mp4")],
    {
      "story-media/huge.mp4": { size: 300 * 1024 * 1024, head: videoHead },
      "message-media/huge.jpg": { size: MAX_IMAGE_BYTES + 1, head: largeImageHead },
      "message-media/small.gif": gif("small"),
      "message-media/medium.jpg": mediumImage,
      "message-media/voice.m4a": { size: 2 * 1024 * 1024, head: ftyp("M4A ", "M4A isom") },
    },
  );
  const sizes: number[] = [];
  const matcher: CsamMatcher = {
    name: "sizes",
    supportsVideo: false,
    match(bytes) {
      sizes.push(bytes.length);
      return Promise.resolve({ outcome: "clear", vendor: "sizes", vendorRef: null });
    },
  };
  const result = await scanMedia(r.client, matcher, quietAlert);
  const refs = r.completes.map((c) => `${c.p_job_id}:${c.p_result}:${c.p_vendor_ref}`);
  assert(
    refs.join(",") === "1:skipped:video_not_hashed,2:unavailable:too_large,3:clear:null,4:clear:null,5:skipped:not_image_or_video",
    refs.join(","),
  );
  const reads = r.log.filter((l) => l.startsWith("read "));
  assert(reads.join(",") === `read message-media/medium.jpg ${MAX_IMAGE_BYTES}`, `full reads: ${reads.join(",")}`);
  assert(sizes.join(",") === `11,${mediumImage.length}`, `the matcher saw ${sizes.join(",")}`);
  assert(result.unavailable === 1 && result.skipped === 2 && result.clear === 2, JSON.stringify(result));

  // The cap can be narrowed, never raised; an image read over it is too_large.
  const n = rig([job(1, "medium.jpg")], { "message-media/medium.jpg": mediumImage });
  await scanMedia(n.client, matcher, quietAlert, { maxBytes: 5_000 });
  assert(n.completes[0].p_vendor_ref === "too_large", JSON.stringify(n.completes));
  const w = rig([job(1, "medium.jpg")], { "message-media/medium.jpg": mediumImage });
  await scanMedia(w.client, matcher, quietAlert, { maxBytes: 1e12 });
  assert(w.log.includes(`read message-media/medium.jpg ${MAX_IMAGE_BYTES}`), w.log.join(" | "));
});

Deno.test("I-2, N-4: bytes that are no longer an image by the full read (text or a video) are unavailable", async () => {
  const r = rig([job(1, "swap.jpg"), job(2, "swap2.jpg")], {
    "message-media/swap.jpg": { changed: [cat([0xff, 0xd8, 0xff], "z".repeat(5_000)), cat("just text now", "z".repeat(5_000))] },
    "message-media/swap2.jpg": { changed: [cat([0xff, 0xd8, 0xff], "z".repeat(5_000)), cat(ftyp("isom", "isomavc1"), "z".repeat(5_000))] },
  });
  const { seen, matcher } = recordingMatcher({ supportsVideo: true });
  await scanMedia(r.client, matcher, quietAlert);
  const refs = r.completes.map((c) => `${c.p_job_id}:${c.p_result}:${c.p_vendor_ref}`);
  assert(refs.join(",") === "1:unavailable:changed_during_scan,2:unavailable:changed_during_scan", refs.join(","));
  assert(seen.length === 0, `the matcher was asked: ${seen.join(",")}`);
});

Deno.test("N-1: with no size from Storage, an image is read whole, never hashed on its head", async () => {
  const large = cat([0xff, 0xd8, 0xff, 0xe0], "q".repeat(20_000));
  const small = cat("GIF89a", "tiny");
  const r = rig([job(1, "large.jpg"), job(2, "small.gif")], {
    "message-media/large.jpg": { unknownSize: large },
    "message-media/small.gif": { unknownSize: small },
  });
  const sizes: number[] = [];
  const matcher: CsamMatcher = {
    name: "sizes",
    supportsVideo: false,
    match(bytes) {
      sizes.push(bytes.length);
      return Promise.resolve({ outcome: "clear", vendor: "sizes", vendorRef: null });
    },
  };
  await scanMedia(r.client, matcher, quietAlert);
  const reads = r.log.filter((l) => l.startsWith("read "));
  assert(reads.join(",") === `read message-media/large.jpg ${MAX_IMAGE_BYTES}`, `full reads: ${reads.join(",")}`);
  assert(sizes.join(",") === `${large.length},${small.length}`, `the matcher saw ${sizes.join(",")}`);

  // An unknown-size image whose full read is over the cap is unavailable, never clear.
  const big = rig([job(3, "big.jpg")], { "message-media/big.jpg": { unknownSize: large } });
  await scanMedia(big.client, matcher, quietAlert, { maxBytes: 10_000 });
  assert(big.completes[0].p_result === "unavailable" && big.completes[0].p_vendor_ref === "too_large", JSON.stringify(big.completes));
});

Deno.test("a matcher that throws, hangs or answers nonsense is unavailable, never clear", async () => {
  const r = rig([job(1, "t.jpg"), job(2, "h.jpg"), job(3, "n.jpg"), job(4, "s.jpg")], {
    "message-media/t.jpg": jpeg("1"),
    "message-media/h.jpg": jpeg("2"),
    "message-media/n.jpg": jpeg("3"),
    "message-media/s.jpg": jpeg("4"),
  });
  let n = 0;
  const odd: CsamMatcher = {
    name: "odd",
    supportsVideo: false,
    match() {
      n++;
      if (n === 1) return Promise.reject(new Error("boom"));
      if (n === 2) return new Promise(() => {});
      // M-3: skipping is the handler's decision (by sniff), never the matcher's.
      if (n === 4) return Promise.resolve({ outcome: "skipped", vendor: "odd", vendorRef: null });
      return Promise.resolve({ outcome: "maybe" as unknown as "clear", vendor: "odd", vendorRef: null });
    },
  };
  const started = Date.now();
  const result = await scanMedia(r.client, odd, quietAlert, { matcherTimeoutMs: 30 });
  assert(Date.now() - started < 2_000, "the matcher bound was not applied");
  assert(result.unavailable === 4 && result.clear === 0 && result.skipped === 0, JSON.stringify(result));
  const refs = r.completes.map((c) => `${c.p_result}:${c.p_vendor_ref}`);
  assert(
    refs.join(",") === "unavailable:matcher_error,unavailable:matcher_timeout,unavailable:matcher_unreadable,unavailable:matcher_unreadable",
    refs.join(","),
  );
});

Deno.test("a failing quarantine still records the match, as unquarantined, and posts at once", async () => {
  const r = rig([job(9, "m.jpg")], { "message-media/m.jpg": gif("attune-csam-stub-match") }, { quarantineFails: true });
  const posts: string[] = [];
  const result = await scanMedia(r.client, stubMatcher(), {
    webhook: "https://hooks.example/x",
    post: (_url, body) => {
      posts.push(body);
      return Promise.resolve({ ok: true, status: 200 });
    },
  });
  // I-3: the original is still in its bucket (P-18): this is the post that matters most.
  assert(typeof result.alerts === "object" && result.alerts.csam_match === "sent", JSON.stringify(result.alerts));
  assert(posts.length === 1 && posts[0].includes("or still in place where quarantined is false"), posts.join(" | "));
  assert(result.unquarantined === 1 && result.match === 0, JSON.stringify(result));
  assert(r.log.filter((l) => l.startsWith("upload")).length === 3, r.log.join(" | "));
  assert(r.completes[0].p_result === "match_unquarantined" && r.completes[0].p_quarantine_path === null, JSON.stringify(r.completes));
  assert(r.completes[0].p_lease_id === "lease-9", "the match carries its lease");
});

Deno.test("a match reaches the safety webhook at once, as a count", async () => {
  const r = rig([job(1, "b.jpg")], { "message-media/b.jpg": gif("attune-csam-stub-match") });
  const posts: string[] = [];
  const result = await scanMedia(r.client, stubMatcher(), {
    webhook: "https://hooks.example/x",
    post: (_url, body) => {
      posts.push(body);
      return Promise.resolve({ ok: true, status: 200 });
    },
  });
  assert(typeof result.alerts === "object" && result.alerts.csam_match === "sent", JSON.stringify(result.alerts));
  assert(posts.length === 1 && !posts[0].includes("b.jpg") && !posts[0].includes("5f7b"), posts.join(" | "));
  assert(!posts[0].includes("message-media") && !posts[0].includes("lease"), posts[0]);
  assert(posts[0].includes("or still in place where quarantined is false"), posts[0]);
});

Deno.test("I-3: an unavailable answer alone asks both sources at once", async () => {
  const r = rig([job(1, "c.jpg")], { "message-media/c.jpg": gif("attune-csam-stub-unavailable") }, { csamDue: false });
  const result = await scanMedia(r.client, stubMatcher(), quietAlert);
  assert(result.unavailable === 1 && typeof result.alerts === "object", JSON.stringify(result));
  assert(r.log.includes("rpc csam_escalations_due") && r.log.includes("rpc scan_failed_escalations_due"), r.log.join(" | "));
  assert(result.alerts.csam_match === "none" && result.alerts.scan_failed === "none", JSON.stringify(result.alerts));
});

Deno.test("the immediate post is left to the backstop when the run is too late for it", async () => {
  let t = 0;
  const r = rig([job(1, "c.jpg")], { "message-media/c.jpg": gif("attune-csam-stub-unavailable") });
  // The clock reads 31 s at the start, 62 s at the claim, 93 s when the loop ends, and 124 s at the alert check:
  // 93 s into the run, past ALERT_DEADLINE_MS (90 s).
  const result = await scanMedia(r.client, stubMatcher(), quietAlert, { now: () => (t += 31_000) });
  assert(result.unavailable === 1 && result.alerts === "deferred", JSON.stringify(result));
  assert(!r.log.some((l) => l.endsWith("_due")), r.log.join(" | "));
});

Deno.test("M-2: a job that throws unexpectedly is unanswered, never clear", async () => {
  const r = rig([job(1, "odd.jpg")], { "message-media/odd.jpg": { malformed: true } });
  const result = await scanMedia(r.client, stubMatcher(), quietAlert);
  assert(result.unanswered === 1 && result.clear === 0 && r.completes.length === 0, JSON.stringify(result));
});

Deno.test("an alert step that throws never fails the run", async () => {
  const r = rig([job(1, "b.jpg")], { "message-media/b.jpg": gif("attune-csam-stub-match") });
  const client: ScanClient = {
    rpc: (fn, args) => (fn.endsWith("_due") ? Promise.reject(new Error("network")) : r.client.rpc(fn, args)),
    storage: r.client.storage,
    objects: r.client.objects,
  };
  const result = await scanMedia(client, stubMatcher(), quietAlert);
  assert(result.match === 1, JSON.stringify(result));
  assert(typeof result.alerts === "object" && result.alerts.csam_match === "read_failed", JSON.stringify(result.alerts));
});

Deno.test("nothing claimed (flag off): no download, no post", async () => {
  const r = rig([], {});
  const result = await scanMedia(r.client, stubMatcher(), quietAlert);
  assert(result.claimed === 0 && result.alerts === "not_needed", JSON.stringify(result));
  assert(r.log.join(",") === "rpc claim_media_scan_jobs", r.log.join(","));
});

Deno.test("an unanswered completion is counted (the lease brings it back)", async () => {
  const r = rig([job(1, "a.jpg")], { "message-media/a.jpg": png("ordinary") }, { completeFails: true });
  const result = await scanMedia(r.client, stubMatcher(), quietAlert);
  assert(result.unanswered === 1 && result.clear === 0, JSON.stringify(result));
  const t = rig([job(1, "a.jpg"), job(2, "b.jpg")], { "message-media/a.jpg": png("1"), "message-media/b.jpg": png("2") }, {
    completeThrows: true,
  });
  const thrown = await scanMedia(t.client, stubMatcher(), quietAlert);
  assert(thrown.unanswered === 2 && thrown.claimed === 2, JSON.stringify(thrown));
  // A match whose record call fails is not counted as recorded: the lease brings it back.
  const m = rig([job(3, "m.jpg")], { "message-media/m.jpg": gif("attune-csam-stub-match") }, { completeFails: true });
  const unrecorded = await scanMedia(m.client, stubMatcher(), quietAlert);
  assert(unrecorded.unanswered === 1 && unrecorded.match === 0 && unrecorded.unquarantined === 0, JSON.stringify(unrecorded));
});

Deno.test("the run budget stops new claims: unreached work stays unclaimed for the next minute", async () => {
  let t = 0;
  const r = rig([job(1, "a.jpg"), job(2, "b.jpg")], { "message-media/a.jpg": png("x"), "message-media/b.jpg": png("y") });
  const result = await scanMedia(r.client, stubMatcher(), quietAlert, { now: () => (t += 30_000), budgetMs: 50_000 });
  assert(result.claimed === 1 && result.clear === 1 && result.unanswered === 0, JSON.stringify(result));
  assert(r.claims.length === 1, `claims ${r.claims.length}`);
  assert(!r.log.includes("head message-media/b.jpg"), r.log.join(" | "));
  // A caller can't widen the budget past RUN_BUDGET_MS.
  t = 0;
  const wide = rig([job(1, "a.jpg"), job(2, "b.jpg")], { "message-media/a.jpg": png("x"), "message-media/b.jpg": png("y") });
  const capped = await scanMedia(wide.client, stubMatcher(), quietAlert, { now: () => (t += 30_000), budgetMs: 1e9 });
  assert(capped.claimed === 1 && wide.claims.length === 1, JSON.stringify(capped));
});

Deno.test("N-2: the run's clock starts where the caller says (the environment read counts)", async () => {
  // The caller started 55 s ago: past the budget, nothing is claimed.
  const late = rig([job(1, "a.jpg")], { "message-media/a.jpg": png("x") });
  const r1 = await scanMedia(late.client, stubMatcher(), quietAlert, { now: () => 100_000, startedAt: 45_000 });
  assert(r1.claimed === 0 && late.claims.length === 0, JSON.stringify(r1));
  // 30 s ago: there is time for work.
  const early = rig([job(1, "a.jpg")], { "message-media/a.jpg": png("x") });
  const r2 = await scanMedia(early.client, stubMatcher(), quietAlert, { now: () => 100_000, startedAt: 70_000 });
  assert(r2.claimed === 1, JSON.stringify(r2));
  // The alert deadline counts from it too. The clock reads 40 s at scanMedia's start and first claim check, then
  // 120 s: 120 s since the caller's start (past ALERT_DEADLINE_MS), though only 80 s since scanMedia's own.
  const alerting = rig([job(1, "c.jpg")], { "message-media/c.jpg": gif("attune-csam-stub-unavailable") });
  let calls = 0;
  const r3 = await scanMedia(alerting.client, stubMatcher(), quietAlert, { now: () => (++calls <= 2 ? 40_000 : 120_000), startedAt: 0 });
  assert(r3.unavailable === 1 && r3.alerts === "deferred", JSON.stringify(r3));
  // A start in the future can't stretch the budget.
  const future = rig([job(1, "a.jpg"), job(2, "b.jpg")], { "message-media/a.jpg": png("x"), "message-media/b.jpg": png("y") });
  let u = 0;
  const r4 = await scanMedia(future.client, stubMatcher(), quietAlert, { now: () => (u += 30_000), startedAt: 1e12 });
  assert(r4.claimed === 1, JSON.stringify(r4));
});

Deno.test("one job per claim, at most BATCH a run; a later claim failure ends the run without throwing", async () => {
  const many = Array.from({ length: 25 }, (_, i) => job(i + 1, `${i + 1}.jpg`));
  const objects = Object.fromEntries(many.map((j) => [`message-media/${j.object_name}`, png(String(j.id))]));
  const r = rig(many, objects);
  const result = await scanMedia(r.client, stubMatcher(), quietAlert);
  assert(BATCH === 20 && result.claimed === 20 && result.clear === 20, JSON.stringify(result));
  assert(r.claims.length === 20 && r.claims.every((c) => c.p_limit === 1), JSON.stringify(r.claims));

  const small = rig(many.slice(0, 5), objects);
  assert((await scanMedia(small.client, stubMatcher(), quietAlert, { batch: 3 })).claimed === 3, "batch option");

  const failing = rig(many.slice(0, 5), objects, { claimFailsAfter: 2 });
  const partial = await scanMedia(failing.client, stubMatcher(), quietAlert);
  assert(partial.claimed === 2 && partial.clear === 2, JSON.stringify(partial));

  const first = rig(many.slice(0, 1), objects, { claimFailsAfter: 0 });
  let threw = "";
  try {
    await scanMedia(first.client, stubMatcher(), quietAlert);
  } catch (error) {
    threw = error instanceof Error ? error.message : String(error);
  }
  assert(threw === "claim_failed", `first claim failure: ${threw}`);
});

Deno.test("the run fits under the edge limit: the last job, or the alerts, end 10 s before it", () => {
  assert(RUN_BUDGET_MS === 50_000 && MATCHER_MAX_TIMEOUT_MS === 15_000 && ALERT_DEADLINE_MS === 90_000, "constants");
  assert(HEAD_TIMEOUT_MS === 5_000 && DOWNLOAD_TIMEOUT_MS === 10_000 && RPC_TIMEOUT_MS === 10_000, "step bounds");
  assert(
    JOB_WORST_CASE_MS ===
      RPC_TIMEOUT_MS + HEAD_TIMEOUT_MS + DOWNLOAD_TIMEOUT_MS + MATCHER_MAX_TIMEOUT_MS + 1_000 + quarantineBudget({}).worstCaseMs +
        RPC_TIMEOUT_MS,
    `job worst case ${JOB_WORST_CASE_MS}`,
  );
  assert(ALERT_WORST_CASE_MS === 2 * (RPC_TIMEOUT_MS + ALERT_POST_TIMEOUT_MS + RPC_TIMEOUT_MS), `alerts ${ALERT_WORST_CASE_MS}`);
  assert(RUN_BUDGET_MS + JOB_WORST_CASE_MS <= EDGE_WALL_CLOCK_MS - 10_000, "the last job ends past the edge limit");
  assert(ALERT_DEADLINE_MS + ALERT_WORST_CASE_MS <= EDGE_WALL_CLOCK_MS - 10_000, "the alerts end past the edge limit");
  assert(MAX_IMAGE_BYTES === PHOTODNA_MAX_BYTES && MAX_IMAGE_BYTES === 4 * 1024 * 1024, "the image cap");
});

Deno.test("M-1: the environment is development only when it reads exactly that", async () => {
  const answer = (data: unknown, error: { message: string } | null = null) => ({
    rpc: (fn: string) => {
      assert(fn === "get_attune_environment", fn);
      return Promise.resolve({ data, error });
    },
  });
  assert(await readEnvironment(answer("development")) === "development", "development");
  for (const data of ["production", "staging", "Development", "development ", "", null, undefined, 1, { env: "development" }]) {
    assert(await readEnvironment(answer(data)) === "production", `${JSON.stringify(data)} read as development`);
  }
  assert(await readEnvironment(answer("development", { message: "boom" })) === "production", "an error");
  assert(await readEnvironment({ rpc: () => Promise.reject(new Error("network")) }) === "production", "a throw");
  assert(await readEnvironment({ rpc: () => { throw new Error("sync"); } }) === "production", "a synchronous throw");
});

Deno.test("errorClass names our code or the error's class, never its message", () => {
  assert(errorClass(new Error("claim_failed")) === "claim_failed", "ours");
  assert(errorClass(new TypeError("/storage/v1/object/message-media/5f7b/x.jpg")) === "TypeError", "a class");
  assert(errorClass("text") === "string", "not an Error");
});

Deno.test("readJobs keeps well-formed rows and their lease", () => {
  const jobs = readJobs([
    { id: 1, bucket: "b", object_name: "o", owner_user_id: null, mime: null, attempts: 2, lease_id: "l-1" },
    { id: "2", bucket: "b", object_name: "o" },
    { id: 3, bucket: "b" },
    null,
    { id: 4, bucket: "b", object_name: "p", lease_id: 7 },
  ]);
  assert(jobs.length === 2 && jobs[0].lease_id === "l-1" && jobs[1].lease_id === null, JSON.stringify(jobs));
  assert(readJobs(null).length === 0 && readJobs({}).length === 0, "not an array");
});

Deno.test("the stub's test image is a GIF the dev stub matches end to end", async () => {
  const bytes = await Deno.readFile(new URL("./testdata/stub-match.gif", import.meta.url));
  assert(new TextDecoder("utf-8", { fatal: true }).decode(bytes).startsWith("GIF89a"), "plain ASCII (the repo's text scans read it)");
  const r = rig([job(1, "rel/test/stub-match.gif", "image/gif")], { "message-media/rel/test/stub-match.gif": bytes });
  const dev = matcherFromEnv({
    env: (n) => ({ CSAM_MATCHER: "stub", SUPABASE_URL: "https://mrgjtyacrzfylawyzabm.supabase.co" } as Record<string, string>)[n],
    fetch,
    environment: "development",
  });
  const result = await scanMedia(r.client, dev, quietAlert);
  assert(result.match === 1, JSON.stringify(result));
});

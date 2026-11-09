// Spec 2 W3c Task 9 controller carries: B (a hit whose photo row is gone
// still places the Dating hold, R-25), C (no database call is open across
// any network call: claim, released, then the network, then the record;
// Task 8 M-6), D (dating:busy and a raw 55P03 are retries with backoff,
// never a dead letter) and E (only fixed codes leave the worker). Local
// imports only, so the CI lockfile is unchanged.
import type { CsamMatcher, MatchResult } from "../_shared/csam_matcher.ts";
import type { VisionModerationResult } from "../_shared/google_vision.ts";
import {
  BUSY_BACKOFF_MS,
  errorCode,
  PHOTO_CLAIM_LIMIT,
  type PhotoDeps,
  processPhotoJob,
  RUN_BUDGET_MS,
  runWorker,
  sweepOrphan,
  visionStep,
} from "./handler.ts";
import { analyzeDatingPhoto } from "../_shared/google_vision.ts";

function eq(actual: unknown, expected: unknown, why = "") {
  const a = JSON.stringify(actual), e = JSON.stringify(expected);
  if (a !== e) throw new Error(`${why} expected ${e}, got ${a}`);
}

function jpeg(width: number, height: number): Uint8Array {
  return new Uint8Array([
    0xFF,
    0xD8,
    0xFF,
    0xC0,
    0x00,
    0x11,
    0x08,
    height >> 8,
    height & 255,
    width >> 8,
    width & 255,
    0x03,
    0x01,
    0x22,
    0x00,
    0x02,
    0x11,
    0x01,
    0x03,
    0x11,
    0x01,
    0xFF,
    0xDA,
    0x00,
    0x08,
    0x01,
    0x01,
    0x00,
    0x00,
    0x3F,
    0x00,
    0x11,
    0x22,
  ]);
}

const goodVision: VisionModerationResult = {
  safeSearchFlags: {
    adult: "VERY_UNLIKELY",
    violence: "VERY_UNLIKELY",
    racy: "UNLIKELY",
    medical: "UNLIKELY",
    spoof: "UNLIKELY",
  },
  faceDetected: true,
  faceConfidence: 0.95,
  faceBlurred: false,
  faceUnderexposed: false,
  faceAreaRatio: null,
  faceBoundingPolyVertices: [{ x: 100, y: 100 }, { x: 500, y: 100 }, {
    x: 500,
    y: 500,
  }, { x: 100, y: 500 }],
  childLabelScore: null,
};

type Answer = {
  data: unknown;
  error: { message: string; code?: string } | null;
};
const BUSY: Answer = {
  data: null,
  error: { message: "dating:busy", code: "55P03" },
};
const RAW_LOCK_TIMEOUT: Answer = {
  data: null,
  error: { message: "canceling statement due to lock timeout", code: "55P03" },
};
const GONE: Answer = { data: { ok: false, reason: "gone" }, error: null };

/**
 * A fake database and network. Every database call is one short
 * transaction, open until its promise settles (a macrotask later); every
 * network fake records a violation if any database call is open then.
 */
function world(over: {
  answers?: Record<string, Answer[]>;
  match?: MatchResult["outcome"];
  vision?: () => Promise<VisionModerationResult>;
  verdictThrows?: Error;
  orphans?: unknown[];
  bytes?: Uint8Array;
  jobs?: unknown[];
  now?: () => number;
} = {}) {
  const events: string[] = [];
  const violations: string[] = [];
  const rpcs: Array<[string, Record<string, unknown> | undefined]> = [];
  const verdicts: Array<[string, string, string | null]> = [];
  const finishes: Array<[string, string, string | null]> = [];
  const sleeps: number[] = [];
  const answers = over.answers ?? {};
  const bytes = over.bytes ?? jpeg(1200, 1600);
  let open = 0;
  const db = <T>(
    name: string,
    value: () => T,
    released = false,
  ): Promise<T> => {
    open++;
    events.push(name);
    return new Promise((resolve, reject) =>
      setTimeout(() => {
        open--;
        if (released) events.push(`${name}:released`);
        try {
          resolve(value());
        } catch (e) {
          reject(e);
        }
      }, 0)
    );
  };
  const net = async <T>(name: string, value: () => T): Promise<T> => {
    events.push(name);
    if (open !== 0) {
      violations.push(`${name} with ${open} database call(s) open`);
    }
    await new Promise((r) => setTimeout(r, 0));
    if (open !== 0) {
      violations.push(`${name} ended with ${open} database call(s) open`);
    }
    return value();
  };
  const matcher: CsamMatcher = {
    name: "fake",
    supportsVideo: false,
    match: () =>
      net(
        "csam",
        () => ({
          outcome: over.match ?? "clear",
          vendor: "fake",
          vendorRef: over.match === "match" ? "ref-1" : null,
        }),
      ),
  };
  const d: PhotoDeps = {
    rpc: (fn, args) => {
      rpcs.push([fn, args]);
      const label = `${fn}${
        args && "p_outcome" in args ? `:${args.p_outcome}` : ""
      }${args && "p_phase" in args ? `:${args.p_phase}` : ""}`;
      const queued = answers[fn]?.shift();
      return db(label, (): Answer => {
        if (queued) return queued;
        if (fn === "claim_dating_photo_jobs") {
          return {
            data: over.jobs ??
              [{ photo_id: "p1", user_id: "u-1", attempts: 1 }],
            error: null,
          };
        }
        if (fn === "claim_dating_orphan_uploads") {
          return {
            data: over.orphans ??
              [{
                intent_id: "i-1",
                user_id: "u-1",
                storage_key: "dating-photos/o.jpg",
              }],
            error: null,
          };
        }
        if (fn === "record_inline_csam_match") return { data: 7, error: null };
        return { data: { ok: true }, error: null };
      }, fn.startsWith("claim_"));
    },
    photo: (id) =>
      db(
        "photo",
        () => ({ id, user_id: "u-1", storage_key: "dating-photos/abc.jpg" }),
      ),
    download: () => net("download", () => bytes),
    replace: () => net("replace", () => true),
    verdict: (id, state, reason) =>
      db("verdict", () => {
        if (over.verdictThrows) throw over.verdictThrows;
        verdicts.push([id, state, reason]);
      }),
    finish: (id, state, code) =>
      db("finish", () => void finishes.push([id, state, code])),
    vision: () =>
      net("vision", () => goodVision).then((
        v,
      ) => (over.vision ? over.vision() : v)),
    matcher,
    quarantine: { put: () => net("quarantine", () => "stored" as const) },
    config: {
      minFaceConfidence: 0.7,
      minFaceAreaRatio: 0.06,
      childLabelReject: 0.7,
      childLabelReview: 0.5,
    },
    sleep: async (ms) => void sleeps.push(ms),
    now: over.now,
  };
  return { d, events, violations, rpcs, verdicts, finishes, sleeps };
}

const calls = (rpcs: Array<[string, unknown]>, fn: string) =>
  rpcs.filter(([f]) => f === fn).length;

// C (Task 8 M-6): exit_dating_mode has no lock_timeout, so its wait is
// bounded only because every writer is short.
Deno.test("C: claim, released, then the network, then the record; no database call open across any network call", async () => {
  const t = world();
  eq(await runWorker(null, t.d), { processed: 1, orphans: 1 });
  eq(t.violations, []);
  eq(t.events, [
    "claim_dating_photo_jobs",
    "claim_dating_photo_jobs:released",
    "photo",
    "download",
    "csam",
    "record_dating_photo_csam:clear",
    "vision",
    "check_dating_photo_strip:before",
    "replace",
    "check_dating_photo_strip:after",
    "verdict",
    "finish",
    "claim_dating_orphan_uploads",
    "claim_dating_orphan_uploads:released",
    "download",
    "csam",
    "record_dating_orphan_scan:clear",
  ]);
});

Deno.test("C: a match is copied and recorded with no database call open across the copy", async () => {
  const t = world({ match: "match" });
  eq(await runWorker("p1", t.d), { processed: 1, orphans: 0 });
  eq(t.violations, []);
  eq(t.events, [
    "claim_dating_photo_jobs",
    "claim_dating_photo_jobs:released",
    "photo",
    "download",
    "csam",
    "record_dating_photo_csam:hit",
    "quarantine",
    "record_inline_csam_match",
    "finish",
  ]);
});

Deno.test("C: a claim that fails stops the run with a fixed code; nothing is scanned", async () => {
  const t = world({
    answers: {
      claim_dating_photo_jobs: [{
        data: null,
        error: { message: "permission denied for table x" },
      }],
    },
  });
  let code = "";
  await runWorker(null, t.d).catch((e) => (code = errorCode(e)));
  eq(code, "claim_failed");
  eq(t.events.includes("download"), false);
});

// D (R-47; Task 8 C, M-4): the recorder answers dating:busy (or a raw 55P03
// in a window the SQL cannot catch): tried again after a backoff, then the
// job is requeued; never dead-lettered for being busy.
Deno.test("D: a busy CSAM record is tried again with backoff, then the photo goes on", async () => {
  const t = world({
    answers: { record_dating_photo_csam: [BUSY, RAW_LOCK_TIMEOUT] },
  });
  eq(await processPhotoJob({ photo_id: "p1", attempts: 1 }, t.d), "approved");
  eq(t.sleeps, [...BUSY_BACKOFF_MS]);
  eq(calls(t.rpcs, "record_dating_photo_csam"), 3);
  eq(t.violations, []);
});

Deno.test("D: still busy: requeued as dating_busy, never dead-lettered (first or last attempt), never approved", async () => {
  for (const answer of [BUSY, RAW_LOCK_TIMEOUT]) {
    for (const attempts of [1, 5, 9]) {
      const t = world({
        answers: { record_dating_photo_csam: [answer, answer, answer] },
      });
      eq(
        await processPhotoJob({ photo_id: "p1", attempts }, t.d),
        "retry",
        `${answer.error!.message} @${attempts}`,
      );
      eq(
        t.finishes,
        [["p1", "pending", "dating_busy"]],
        `${answer.error!.message} @${attempts}`,
      );
      eq(t.verdicts, []);
      eq(t.events.includes("vision"), false);
    }
  }
});

// C-1 (fix round 1, §3.2 D9): whatever the Dating step answers, Spec 1's
// record (the quarantine copy, the escalation, its hold) is never skipped,
// and the Dating hold is placed by owner; then the job is requeued.
Deno.test("C-1: the Dating record stays busy: Spec 1 still records and the hold is placed in the same run, then requeued", async () => {
  for (const attempts of [1, 5]) {
    const t = world({
      match: "match",
      answers: { record_dating_photo_csam: [BUSY, BUSY, BUSY] },
    });
    eq(await processPhotoJob({ photo_id: "p1", attempts }, t.d), "retry");
    eq(t.events.filter((e) => e === "quarantine").length, 1);
    eq(calls(t.rpcs, "record_inline_csam_match"), 1);
    eq(
      t.rpcs.filter(([f]) => f === "record_dating_csam_hold").map(([, a]) => a),
      [{ p_user: "u-1" }],
    );
    eq(t.finishes, [["p1", "pending", "dating_busy"]]);
    eq(t.verdicts, []);
    eq(t.violations, []);
  }
});

Deno.test("C-1: the Dating record fails outright: Spec 1 still records and the hold is placed", async () => {
  const t = world({
    match: "match",
    answers: {
      record_dating_photo_csam: [{ data: null, error: { message: "x" } }],
    },
  });
  eq(await processPhotoJob({ photo_id: "p1", attempts: 1 }, t.d), "retry");
  eq(calls(t.rpcs, "record_inline_csam_match"), 1);
  eq(calls(t.rpcs, "record_dating_csam_hold"), 1);
  eq(t.finishes, [["p1", "pending", "csam_record_failed"]]);
});

Deno.test("D: Spec 1's record that fails is tried again with the same copy (never a second copy)", async () => {
  const t = world({
    match: "match",
    answers: {
      record_inline_csam_match: [{ data: null, error: { message: "x" } }],
    },
  });
  eq(await processPhotoJob({ photo_id: "p1", attempts: 1 }, t.d), "csam_hit");
  eq(t.events.filter((e) => e === "quarantine").length, 1);
  eq(calls(t.rpcs, "record_inline_csam_match"), 2);
  const [first, second] = t.rpcs.filter(([f]) =>
    f === "record_inline_csam_match"
  ).map(([, a]) => a);
  eq(second, first, "the retry records the same copy");
});

// I-1 (fix round 1): a run that saw a match never dead-letters; from the
// last attempt on, each failed run is counted for an operator.
Deno.test("I-1: a match whose Spec 1 record keeps failing is requeued, never dead-lettered, and counted from the last attempt", async () => {
  const fail = { data: null, error: { message: "x" } };
  for (const attempts of [1, 5, 9]) {
    const t = world({
      match: "match",
      answers: { record_inline_csam_match: [fail, fail, fail] },
    });
    eq(
      await processPhotoJob({ photo_id: "p1", attempts }, t.d),
      "retry",
      `@${attempts}`,
    );
    eq(t.verdicts, []);
    eq(t.finishes, [["p1", "pending", "csam_inline_record_failed"]]);
    eq(
      t.rpcs.filter(([f]) => f === "bump_metric_server").map(([, a]) => a),
      attempts >= 5 ? [{ p_key: "dating.photo.csam_record_stuck" }] : [],
      `@${attempts}`,
    );
  }
});

Deno.test("D: an orphan record that is busy is tried again with backoff", async () => {
  const t = world({ answers: { record_dating_orphan_scan: [BUSY] } });
  eq(await runWorker(null, t.d), { processed: 1, orphans: 1 });
  eq(calls(t.rpcs, "record_dating_orphan_scan"), 2);
});

// B (Task 8 fix round 1 I-1; R-25): the photo row was deleted mid-scan, so
// the recorder answers gone and places no hold; the worker still has the
// owner and places the same Dating hold, and Spec 1 still records.
Deno.test("B: a hit on a photo that is gone still holds the Dating account, and Spec 1 still records", async () => {
  const t = world({
    match: "match",
    answers: { record_dating_photo_csam: [GONE] },
  });
  eq(await processPhotoJob({ photo_id: "p1", attempts: 1 }, t.d), "csam_hit");
  eq(
    t.rpcs.filter(([f]) => f === "record_dating_csam_hold").map(([, a]) => a),
    [{ p_user: "u-1" }],
  );
  eq(calls(t.rpcs, "record_inline_csam_match"), 1);
  const inline = t.rpcs.find(([f]) => f === "record_inline_csam_match")![1]!;
  eq([inline.p_owner, inline.p_quarantined], ["u-1", true]);
  eq(t.events.includes("vision"), false);
  eq(t.verdicts, []);
  eq(t.violations, []);
});

Deno.test("B: the gone hold is tried again when busy; Spec 1 records even when the hold can't be placed", async () => {
  const a = world({
    match: "match",
    answers: {
      record_dating_photo_csam: [GONE],
      record_dating_csam_hold: [BUSY],
    },
  });
  eq(await processPhotoJob({ photo_id: "p1", attempts: 1 }, a.d), "csam_hit");
  eq(calls(a.rpcs, "record_dating_csam_hold"), 2);
  const b = world({
    match: "match",
    answers: {
      record_dating_photo_csam: [GONE],
      record_dating_csam_hold: [BUSY, BUSY, BUSY],
    },
  });
  eq(await processPhotoJob({ photo_id: "p1", attempts: 1 }, b.d), "retry");
  eq(calls(b.rpcs, "record_inline_csam_match"), 1, "Spec 1's record");
  eq(b.verdicts, []);
});

Deno.test("B: a clear or failed scan of a photo that is gone: no Vision, no verdict", async () => {
  for (const match of ["clear", "unavailable"] as const) {
    const t = world({ match, answers: { record_dating_photo_csam: [GONE] } });
    eq(
      await processPhotoJob({ photo_id: "p1", attempts: 1 }, t.d),
      "gone",
      match,
    );
    eq(t.events.includes("vision"), false);
    eq(t.verdicts, []);
    eq(calls(t.rpcs, "record_dating_csam_hold"), 0);
  }
});

// E: errors leave the worker as fixed codes only, never server or vendor text.
Deno.test("E: only fixed codes are stored or answered", async () => {
  eq(
    errorCode(new Error("canceling statement due to lock timeout")),
    "internal_error",
  );
  eq(
    errorCode({ message: "duplicate key value violates unique constraint" }),
    "internal_error",
  );
  eq(errorCode(new Error("Forbidden")), "internal_error");
  eq(errorCode(new Error("csam_unavailable")), "csam_unavailable");
  eq(errorCode(new Error("vision_http_error_503")), "vision_http_error_503");
  const a = world({
    verdictThrows: new Error(
      "new row for relation violates check constraint (caption: hello)",
    ),
  });
  eq(await processPhotoJob({ photo_id: "p1", attempts: 1 }, a.d), "retry");
  eq(a.finishes, [["p1", "pending", "internal_error"]]);
  const b = world({
    vision: () =>
      Promise.reject(
        new TypeError(
          "error sending request for url (https://vision.googleapis.com/?key=k)",
        ),
      ),
  });
  eq(await processPhotoJob({ photo_id: "p1", attempts: 1 }, b.d), "retry");
  eq(b.finishes, [["p1", "pending", "internal_error"]]);
});

// I-2 (fix round 1): an orphan match whose 'hit' record fails still holds
// the Dating account by owner before the claim is released.
Deno.test("I-2: an orphan hit whose record stays busy or is refused still holds the Dating account, then is released", async () => {
  const orphan = {
    intent_id: "i-1",
    user_id: "u-1",
    storage_key: "dating-photos/o.jpg",
  };
  for (
    const answer of [BUSY, {
      data: { ok: false, reason: "not_claimed" },
      error: null,
    }]
  ) {
    const t = world({
      match: "match",
      answers: {
        record_dating_orphan_scan: answer === BUSY
          ? [BUSY, BUSY, BUSY]
          : [answer],
      },
    });
    eq(await sweepOrphan(orphan, t.d), "retry");
    eq(calls(t.rpcs, "record_inline_csam_match"), 1);
    eq(
      t.rpcs.filter(([f]) => f === "record_dating_csam_hold").map(([, a]) => a),
      [{ p_user: "u-1" }],
    );
    const scans = t.rpcs.filter(([f]) => f === "record_dating_orphan_scan").map(
      ([, a]) => a!.p_outcome,
    );
    eq(scans.at(-1), "error", "released after the hold");
    eq(scans.filter((s) => s === "error").length, 1, "released once");
    eq(
      t.events.indexOf("record_dating_csam_hold") <
        t.events.indexOf("record_dating_orphan_scan:error"),
      true,
      "the hold before the release",
    );
  }
});

// M-3 (fix round 1, §4.3): only a JPEG whose metadata was stripped is
// published; a PNG (eXIf, tEXt) or anything else goes to a person.
Deno.test("M-3: an approved PNG goes to a person, never published unstripped", async () => {
  const png = new Uint8Array(33);
  png.set([
    0x89,
    0x50,
    0x4E,
    0x47,
    0x0D,
    0x0A,
    0x1A,
    0x0A,
    0,
    0,
    0,
    13,
    0x49,
    0x48,
    0x44,
    0x52,
  ]);
  new DataView(png.buffer).setUint32(16, 1200);
  new DataView(png.buffer).setUint32(20, 1600);
  const t = world({ bytes: png });
  eq(
    await processPhotoJob({ photo_id: "p1", attempts: 1 }, t.d),
    "needs_review",
  );
  eq(t.verdicts, [["p1", "needs_review", "needs_review"]]);
  eq(t.events.includes("replace"), false);
});

// M-2 (fix round 1): Vision asks for 50 labels and reads the child score.
Deno.test("M-2: Vision asks for 50 labels and reads Child, Baby, Toddler or Infant", async () => {
  const real = globalThis.fetch;
  let sent: unknown = null;
  globalThis.fetch = ((_url: string, init: RequestInit) => {
    sent = JSON.parse(String(init.body));
    return Promise.resolve(
      new Response(JSON.stringify({
        responses: [{
          safeSearchAnnotation: { adult: "VERY_UNLIKELY" },
          faceAnnotations: [],
          labelAnnotations: [{ description: "Smile", score: 0.9 }, {
            description: "Toddler",
            score: 0.62,
          }, { description: "child", score: 0.55 }],
        }],
      })),
    );
  }) as typeof fetch;
  try {
    const r = await analyzeDatingPhoto({
      imageBytes: new Uint8Array([1, 2, 3]),
      apiKey: "k",
    });
    eq(r.childLabelScore, 0.62);
  } finally {
    globalThis.fetch = real;
  }
  const features =
    (sent as { requests: Array<{ features: unknown[] }> }).requests[0].features;
  eq(features.find((f) => (f as { type: string }).type === "LABEL_DETECTION"), {
    type: "LABEL_DETECTION",
    maxResults: 50,
  });
});

// M-6 (fix round 1): a run claims at most PHOTO_CLAIM_LIMIT jobs and starts
// no new work past its time budget; a claimed job it can't start goes back
// to pending at once, and no orphan is claimed then.
Deno.test("M-6, M-8: at most twenty jobs a run; past the budget the rest go back to pending and no orphan is claimed", async () => {
  let clock = 0;
  const t = world({
    jobs: [1, 2, 3].map((n) => ({
      photo_id: `p${n}`,
      user_id: "u-1",
      attempts: 1,
    })),
    now: () => clock,
    vision: () => {
      clock += RUN_BUDGET_MS + 1;
      return Promise.resolve(goodVision);
    },
  });
  eq(PHOTO_CLAIM_LIMIT, 20); // Spec 2 W3 final (M-8)
  eq(await runWorker(null, t.d), { processed: 1, orphans: 0 });
  eq(t.rpcs.find(([f]) => f === "claim_dating_photo_jobs")![1], {
    p_limit: 20,
    p_photo_id: null,
  });
  eq(t.finishes, [["p1", "done", null], ["p2", "pending", "deferred"], [
    "p3",
    "pending",
    "deferred",
  ]]);
  eq(calls(t.rpcs, "claim_dating_orphan_uploads"), 0);
});

// Spec 2 W3 final (M-5): the metadata strip never brings a deleted photo
// back: before the re-upload the photo row is checked (its key, a clear
// scan); after it, checked again (a row gone by then re-arms the object's
// deletion on the server). Each check is one short RPC, never open across
// the upload.
Deno.test("M-5: a photo deleted before the strip is never re-uploaded", async () => {
  const t = world({ answers: { check_dating_photo_strip: [GONE] } });
  eq(await processPhotoJob({ photo_id: "p1", attempts: 1 }, t.d), "gone");
  eq(t.events.includes("replace"), false);
  eq(t.verdicts, []);
  eq(t.finishes, []);
  eq(t.violations, []);
});

Deno.test("M-5: a photo deleted during the strip is checked after it (its object queued again), never approved", async () => {
  const ok: Answer = { data: { ok: true }, error: null };
  const t = world({ answers: { check_dating_photo_strip: [ok, GONE] } });
  eq(await processPhotoJob({ photo_id: "p1", attempts: 1 }, t.d), "gone");
  eq(t.events.filter((e) => e.startsWith("check_dating_photo_strip") || e === "replace"),
     ["check_dating_photo_strip:before", "replace", "check_dating_photo_strip:after"]);
  eq(t.rpcs.filter(([f]) => f === "check_dating_photo_strip").map(([, a]) => a),
     [{ p_photo_id: "p1", p_storage_key: "dating-photos/abc.jpg", p_phase: "before" },
      { p_photo_id: "p1", p_storage_key: "dating-photos/abc.jpg", p_phase: "after" }]);
  eq(t.verdicts, []);
  eq(t.violations, []);
});

Deno.test("M-5: a busy strip check is tried again, then requeued; a refused one is a fixed code", async () => {
  const a = world({ answers: { check_dating_photo_strip: [BUSY, BUSY, BUSY] } });
  eq(await processPhotoJob({ photo_id: "p1", attempts: 5 }, a.d), "retry");
  eq(a.finishes, [["p1", "pending", "dating_busy"]]);
  eq(a.events.includes("replace"), false);
  const b = world({ answers: { check_dating_photo_strip: [{ data: null, error: { message: "permission denied" } }] } });
  eq(await processPhotoJob({ photo_id: "p1", attempts: 1 }, b.d), "retry");
  eq(b.finishes, [["p1", "pending", "strip_check_failed"]]);
});

Deno.test("M-5: the re-upload never asks storage to create a missing object", async () => {
  const src = await Deno.readTextFile(new URL("./index.ts", import.meta.url));
  eq(/upsert:\s*true/.test(src), false, "index.ts passes upsert: true");
  eq(/\.update\(key, bytes, \{[^}]*upsert:\s*false/.test(src), true, "the re-upload is an update with upsert: false");
});

// Spec 2 W3 final (M-6): CSAM never depends on Vision. With no Vision key
// the matcher still runs and its answer is recorded (a match is recorded
// in full), the orphan sweep still runs; only the Vision step fails
// closed: the photo stays unapproved, is requeued (never dead-lettered:
// the key is a deploy gap, not the photo), and each one is counted.
Deno.test("M-6: no Vision key: the step fails closed without calling Vision", async () => {
  let called = 0;
  const step = visionStep(undefined, () => (called++, Promise.resolve(goodVision)));
  let code = "";
  await step(new Uint8Array([1])).catch((e) => (code = errorCode(e)));
  eq([code, called], ["missing_vision_api_key", 0]);
  const keyed = visionStep("k", () => (called++, Promise.resolve(goodVision)));
  eq(await keyed(new Uint8Array([1])), goodVision);
  eq(called, 1);
});

Deno.test("M-6: no Vision key: the CSAM scan runs and is recorded, the photo stays unapproved and is requeued, counted", async () => {
  for (const attempts of [1, 5, 9]) {
    const t = world();
    t.d.vision = visionStep(undefined);
    eq(await processPhotoJob({ photo_id: "p1", attempts }, t.d), "retry", `@${attempts}`);
    eq(t.events.includes("csam"), true);
    eq(calls(t.rpcs, "record_dating_photo_csam"), 1);
    eq(t.rpcs.find(([f]) => f === "record_dating_photo_csam")![1]!.p_outcome, "clear");
    eq(t.verdicts, []);
    eq(t.finishes, [["p1", "pending", "missing_vision_api_key"]], `@${attempts}`);
    eq(t.rpcs.filter(([f]) => f === "bump_metric_server").map(([, a]) => a), [{ p_key: "dating.photo.vision_unavailable" }]);
  }
  const m = world({ match: "match" });
  m.d.vision = visionStep(undefined);
  eq(await processPhotoJob({ photo_id: "p1", attempts: 1 }, m.d), "csam_hit");
  eq(calls(m.rpcs, "record_inline_csam_match"), 1);
});

Deno.test("M-6: no Vision key: the cron run still sweeps orphans", async () => {
  const t = world();
  t.d.vision = visionStep(undefined);
  eq(await runWorker(null, t.d), { processed: 0, orphans: 1 });
  eq(t.events.includes("record_dating_orphan_scan:clear"), true);
});

Deno.test("M-6: index.ts no longer stops before the worker when the Vision key is missing", async () => {
  const src = await Deno.readTextFile(new URL("./index.ts", import.meta.url));
  eq(src.includes('throw new Error("missing_vision_api_key")'), false);
  eq(/vision:\s*visionStep\(VISION_API_KEY\)/.test(src), true);
});

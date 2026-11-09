// Spec 2 W3c (§3.2 D9, §7.3, I-10): the inline CSAM scan runs first and
// once; a match is quarantined and recorded through Spec 1's path, Vision is
// never called, and the photo is rejected; a matcher error never approves;
// child labels reject or go to a person; the slot reasons.
import type { CsamMatcher, MatchResult } from "../_shared/csam_matcher.ts";
import type { QuarantineStore } from "../_shared/csam_match_path.ts";
import type { VisionModerationResult } from "../_shared/google_vision.ts";
import { type OrphanDeps, type PhotoDeps, processPhotoJob, sweepOrphan } from "./handler.ts";

function eq(actual: unknown, expected: unknown, why = "") {
  const a = JSON.stringify(actual), e = JSON.stringify(expected);
  if (a !== e) throw new Error(`${why} expected ${e}, got ${a}`);
}

/** A JPEG header the dimension reader and the metadata strip both accept. */
function jpeg(width: number, height: number): Uint8Array {
  return new Uint8Array([
    0xFF, 0xD8,
    0xFF, 0xC0, 0x00, 0x11, 0x08, height >> 8, height & 255, width >> 8, width & 255,
    0x03, 0x01, 0x22, 0x00, 0x02, 0x11, 0x01, 0x03, 0x11, 0x01,
    0xFF, 0xDA, 0x00, 0x08, 0x01, 0x01, 0x00, 0x00, 0x3F, 0x00, 0x11, 0x22,
  ]);
}

const goodVision: VisionModerationResult = {
  safeSearchFlags: { adult: "VERY_UNLIKELY", violence: "VERY_UNLIKELY", racy: "UNLIKELY", medical: "UNLIKELY", spoof: "UNLIKELY" },
  faceDetected: true,
  faceConfidence: 0.95,
  faceBlurred: false,
  faceUnderexposed: false,
  faceAreaRatio: null,
  faceBoundingPolyVertices: [{ x: 100, y: 100 }, { x: 500, y: 100 }, { x: 500, y: 500 }, { x: 100, y: 500 }],
  childLabelScore: null,
};

function deps(over: { match?: MatchResult["outcome"]; vision?: Partial<VisionModerationResult>; bytes?: Uint8Array | null; throws?: boolean; visionThrows?: boolean } = {}) {
  const log: string[] = [];
  const rpcs: Array<[string, Record<string, unknown> | undefined]> = [];
  const verdicts: Array<[string, string, string | null]> = [];
  const finishes: Array<[string, string]> = [];
  const quarantined: Uint8Array[] = [];
  const bytes = over.bytes === undefined ? jpeg(1200, 1600) : over.bytes;
  const matcher: CsamMatcher = {
    name: "fake",
    supportsVideo: false,
    async match(b) {
      log.push("csam");
      if (over.throws) throw new Error("vendor timeout");
      if (b !== bytes) throw new Error("the matcher did not get the downloaded bytes");
      return { outcome: over.match ?? "clear", vendor: "fake", vendorRef: over.match === "match" ? "ref-1" : null };
    },
  };
  const quarantine: QuarantineStore = {
    async put(_path, b) {
      log.push("quarantine");
      quarantined.push(b);
      return "stored";
    },
  };
  const d: PhotoDeps = {
    rpc: (fn, args) => {
      log.push(`rpc:${fn}${args && "p_outcome" in args ? `:${args.p_outcome}` : ""}${args && "p_phase" in args ? `:${args.p_phase}` : ""}`);
      rpcs.push([fn, args]);
      return Promise.resolve({ data: fn === "record_inline_csam_match" ? 7 : { ok: true }, error: null });
    },
    photo: async (id) => ({ id, user_id: "u-1", storage_key: "dating-photos/abc.jpg" }),
    download: async () => (log.push("download"), bytes),
    replace: async () => (log.push("replace"), true),
    verdict: async (id, state, reason) => { log.push(`verdict:${state}`); verdicts.push([id, state, reason]); },
    finish: async (id, state) => { log.push(`finish:${state}`); finishes.push([id, state]); },
    vision: async () => {
      log.push("vision");
      if (over.visionThrows) throw new Error("vision_http_error_503");
      return { ...goodVision, ...over.vision };
    },
    matcher,
    quarantine,
    config: { minFaceConfidence: 0.7, minFaceAreaRatio: 0.06, childLabelReject: 0.7, childLabelReview: 0.5 },
  };
  return { d, log, rpcs, verdicts, finishes, quarantined, bytes };
}

Deno.test("clear: CSAM first and once, then Vision, the strip, approved", async () => {
  const t = deps();
  eq(await processPhotoJob({ photo_id: "p1", attempts: 1 }, t.d), "approved");
  eq(t.log, ["download", "csam", "rpc:record_dating_photo_csam:clear", "vision", "rpc:check_dating_photo_strip:before", "replace",
    "rpc:check_dating_photo_strip:after", "verdict:approved", "finish:done"]); // Spec 2 W3 final (M-5): the strip is checked both sides
});

Deno.test("a match: quarantined with the scanned bytes, recorded once through Spec 1, the photo rejected, Vision never called", async () => {
  const t = deps({ match: "match" });
  eq(await processPhotoJob({ photo_id: "p2", attempts: 1 }, t.d), "csam_hit");
  eq(t.log.filter((l) => l === "csam").length, 1);
  if (t.log.includes("vision")) throw new Error("Vision ran after a match");
  if (t.quarantined[0] !== t.bytes) throw new Error("the quarantine copy is not the scanned bytes");
  eq(t.rpcs.filter(([fn]) => fn === "record_inline_csam_match").length, 1);
  const inline = t.rpcs.find(([fn]) => fn === "record_inline_csam_match")![1]!;
  eq([inline.p_bucket, inline.p_object_name, inline.p_owner, inline.p_quarantined], ["dating-profile-photos", "dating-photos/abc.jpg", "u-1", true]);
  eq(t.log.indexOf("quarantine") < t.log.indexOf("rpc:record_inline_csam_match"), true, "copy before record");
  eq(t.log.includes("rpc:record_dating_photo_csam:hit"), true);
  eq(t.verdicts, []);
  eq(t.finishes, [["p2", "done"]]);
});

Deno.test("a matcher error never approves: csam error, retried, no Vision", async () => {
  const t = deps({ match: "unavailable" });
  eq(await processPhotoJob({ photo_id: "p3", attempts: 1 }, t.d), "retry");
  eq(t.log.includes("rpc:record_dating_photo_csam:error"), true);
  if (t.log.includes("vision")) throw new Error("Vision ran without a clear scan");
  eq(t.verdicts, []);
  eq(t.finishes, [["p3", "pending"]]);
});

// Spec 2 W3 final (I-2): a matcher that can't answer (down, a timeout, an
// error, a refusal) is "busy": requeued at every attempt, never
// dead-lettered (a dead letter with no clear scan is a photo no person may
// approve), and counted from the last attempt on.
Deno.test("I-2: a matcher that can't answer is requeued at every attempt, never dead-lettered, counted from the last", async () => {
  for (const over of [{ match: "unavailable" as const }, { match: "skipped" as const }, { throws: true }]) {
    for (const attempts of [1, 5, 9]) {
      const t = deps(over);
      const why = `${JSON.stringify(over)} @${attempts}`;
      eq(await processPhotoJob({ photo_id: "p4", attempts }, t.d), "retry", why);
      eq(t.verdicts, [], why);
      eq(t.finishes, [["p4", "pending"]], why);
      if (t.log.includes("vision")) throw new Error(`Vision ran without a clear scan ${why}`);
      eq(t.rpcs.filter(([fn]) => fn === "bump_metric_server").map(([, a]) => a), attempts >= 5 ? [{ p_key: "dating.photo.csam_scan_stuck" }] : [], why);
    }
  }
});

Deno.test("I-2: bytes that can't be read (storage down) are never dead-lettered unscanned either", async () => {
  const t = deps({ bytes: null });
  eq(await processPhotoJob({ photo_id: "p4", attempts: 6 }, t.d), "retry");
  eq(t.verdicts, []);
  eq(t.finishes, [["p4", "pending"]]);
});

Deno.test("the last attempt after a clear scan: needs a person, dead-lettered, never approved", async () => {
  const t = deps({ visionThrows: true });
  eq(await processPhotoJob({ photo_id: "p4", attempts: 5 }, t.d), "dead");
  eq(t.log.includes("rpc:record_dating_photo_csam:clear"), true);
  eq(t.verdicts, [["p4", "needs_review", "needs_review"]]);
  eq(t.finishes, [["p4", "dead_letter"]]);
});

Deno.test("child labels: 0.8 rejects (contains_child), 0.6 goes to a person", async () => {
  const a = deps({ vision: { childLabelScore: 0.8 } });
  eq(await processPhotoJob({ photo_id: "p5" }, a.d), "rejected");
  eq(a.verdicts, [["p5", "rejected", "contains_child"]]);
  const b = deps({ vision: { childLabelScore: 0.6 } });
  eq(await processPhotoJob({ photo_id: "p6" }, b.d), "needs_review");
  eq(b.verdicts, [["p6", "needs_review", "needs_review"]]);
});

Deno.test("too small: rejected after the CSAM scan, before Vision", async () => {
  const t = deps({ bytes: jpeg(400, 400) });
  eq(await processPhotoJob({ photo_id: "p7" }, t.d), "rejected");
  eq(t.verdicts, [["p7", "rejected", "too_small"]]);
  eq(t.log.includes("csam"), true);
  if (t.log.includes("vision")) throw new Error("Vision ran on a too-small photo");
});

Deno.test("unsafe and an unclear face read as their slot reasons", async () => {
  const a = deps({ vision: { safeSearchFlags: { ...goodVision.safeSearchFlags, adult: "LIKELY" } } });
  await processPhotoJob({ photo_id: "p8" }, a.d);
  eq(a.verdicts, [["p8", "rejected", "unsafe"]]);
  const b = deps({ vision: { faceBlurred: true } });
  await processPhotoJob({ photo_id: "p9" }, b.d);
  eq(b.verdicts, [["p9", "rejected", "face_unclear"]]);
  const c = deps({ vision: { faceDetected: false } });
  await processPhotoJob({ photo_id: "pa" }, c.d);
  eq(c.verdicts, [["pa", "needs_review", "needs_review"]]);
});

// I-14: orphan uploads (an intent that expired unused, its object there).
function orphanDeps(over: { match?: MatchResult["outcome"]; bytes?: Uint8Array | null; throws?: boolean } = {}) {
  const log: string[] = [];
  const bytes = over.bytes === undefined ? jpeg(1200, 1600) : over.bytes;
  const d: OrphanDeps = {
    rpc: (fn, args) => {
      log.push(`rpc:${fn}${args && "p_outcome" in args ? `:${args.p_outcome}` : ""}`);
      return Promise.resolve({ data: fn === "record_inline_csam_match" ? 7 : { ok: true }, error: null });
    },
    download: async () => (log.push("download"), bytes),
    matcher: {
      name: "fake",
      supportsVideo: false,
      async match(b) {
        log.push("csam");
        if (over.throws) throw new Error("vendor down");
        if (b !== bytes) throw new Error("the matcher did not get the downloaded bytes");
        return { outcome: over.match ?? "clear", vendor: "fake", vendorRef: over.match === "match" ? "ref-o" : null };
      },
    },
    quarantine: { async put() { log.push("quarantine"); return "stored"; } },
  };
  return { d, log };
}
const orphan = { intent_id: "i-1", user_id: "u-1", storage_key: "dating-photos/orphan.jpg" };

Deno.test("orphan clear: scanned first, then recorded clear (its deletion queued)", async () => {
  const t = orphanDeps();
  eq(await sweepOrphan(orphan, t.d), "swept");
  eq(t.log, ["download", "csam", "rpc:record_dating_orphan_scan:clear"]);
});

Deno.test("orphan match: quarantined and recorded through Spec 1, then hit; never cleared", async () => {
  const t = orphanDeps({ match: "match" });
  eq(await sweepOrphan(orphan, t.d), "csam_hit");
  eq(t.log, ["download", "csam", "quarantine", "rpc:record_inline_csam_match", "rpc:record_dating_orphan_scan:hit"]);
});

Deno.test("orphan: a matcher that can't answer, throws or has no bytes never clears (no deletion unscanned)", async () => {
  for (const over of [{ match: "unavailable" as const }, { throws: true }, { bytes: null }]) {
    const t = orphanDeps(over);
    eq(await sweepOrphan(orphan, t.d), "retry", JSON.stringify(over));
    eq(t.log.includes("rpc:record_dating_orphan_scan:clear"), false, JSON.stringify(over));
    eq(t.log.at(-1), "rpc:record_dating_orphan_scan:error", JSON.stringify(over));
  }
});

// Spec 2 W3c (§3.2 D9 Server, §4.7, I-10): one photo job. The inline CSAM
// scan is first and the only scan this bucket gets (it is not in Spec 1's
// scan queue). A match: this photo rejected and the Dating hold first
// (record_dating_photo_csam 'hit'), then the scanned bytes to
// safety-quarantine, recorded through Spec 1's record_inline_csam_match
// (one hold, one escalation, the original's deletion); Vision is never
// called. A matcher that can't answer never approves ('error', retried; at
// the last attempt a person looks). Clear: the size, then Vision with child
// labels, then the metadata strip before anything can be approved. Nothing
// is logged here.
//
// Spec 2 W3c (Task 9 carries):
// - B (R-25): a hit whose photo row is gone (deleted mid-scan) gets the
//   same Dating hold through record_dating_csam_hold (the owner read
//   before the scan), and Spec 1 still records the scanned bytes; the row
//   is gone, so no later attempt exists and both are tried here.
// - C (Task 8 M-6): no database call is open across a network call (the
//   matcher, Vision, storage). Every database call is one short statement
//   or RPC, its own transaction, awaited before the next step; the claims
//   commit (and release their row locks) before any download.
//   exit_dating_mode has no lock_timeout: its wait is bounded only because
//   every writer is short.
// - D (R-47): dating:busy or a raw lock timeout, deadlock or serialization
//   failure is tried again after a backoff (nothing held between tries),
//   then the job is requeued; never dead-lettered for being busy.
// - Fix round 1 (C-1, I-1, §3.2 D9): on a match the Dating record is tried
//   first (a photo marked hit is never served and its object is never
//   queued for deletion by a Dating path), but Spec 1's record (the copy,
//   the escalation, its hold) ALWAYS runs, whatever the Dating step
//   answered; if the Dating record did not land, the same Dating hold is
//   placed by owner (record_dating_csam_hold), then the job is requeued.
//   A run that saw a match is never dead-lettered; from the last attempt
//   on, each failed run is counted (dating.photo.csam_record_stuck).
// - M-6: at most PHOTO_CLAIM_LIMIT jobs a run, no new work past
//   RUN_BUDGET_MS (a claimed job not started goes back to pending).
// - E: only fixed codes leave the worker (errorCode); slot reasons are the
//   five fixed codes.
//
// Spec 2 W3 final:
// - I-2: a matcher that can't answer (down, a timeout, an error, a
//   refusal), or bytes that can't be read, is treated as busy: requeued,
//   never dead-lettered (a dead letter with no clear scan is a photo no
//   person may approve), and counted from the last attempt on
//   (dating.photo.csam_scan_stuck). Only a job whose clear scan was
//   recorded is dead-lettered to a person at the last attempt.
// - M-5: the metadata strip is checked before (the row there, its key, a
//   clear scan; else nothing is uploaded) and after the re-upload (a row
//   gone by then re-arms the object's deletion on the server), each one
//   short RPC (check_dating_photo_strip).
// - M-6: CSAM never depends on Vision: with no Vision key the matcher still
//   runs and is recorded and the orphan sweep still runs; only the Vision
//   step fails closed (visionStep): the photo stays unapproved, requeued
//   (the key is a deploy gap), each one counted (dating.photo.vision_unavailable).
// - M-8: up to PHOTO_CLAIM_LIMIT (20) jobs a cron run; RUN_BUDGET_MS bounds
//   the run (a typical job, one matcher and one Vision call, takes 2-3 s,
//   so about 20 fit 60 s; past it the rest go straight back to pending).
import type { CsamMatcher, MatchResult } from "../_shared/csam_matcher.ts";
import { inlineRecorder, type MatchRpcClient, quarantineAndRecord, type QuarantineStore } from "../_shared/csam_match_path.ts";
import {
  analyzeDatingPhoto,
  computeFaceAreaRatio,
  decideModerationOutcome,
  type ModerationConfig,
  type VisionModerationResult,
} from "../_shared/google_vision.ts";

export const BUCKET = "dating-profile-photos";
export const MAX_ATTEMPTS = 5;
export const MIN_DIMENSION = 600;
/** Spec 2 W3c (D): the waits before the second and the third try of a busy write. */
export const BUSY_BACKOFF_MS: readonly number[] = [250, 500];
/**
 * Spec 2 W3 final (M-8): jobs claimed per cron run (was 5: 480 retries a
 * day). RUN_BUDGET_MS is the real bound: a typical job takes 2-3 s, so about
 * 20 fit; a job started at the budget's edge can add one job's timeouts
 * (15 s matcher, 10 s Vision, storage), so a run ends well inside the edge
 * function's 150 s wall clock; jobs not started go back to pending at once.
 */
export const PHOTO_CLAIM_LIMIT = 20;
export const RUN_BUDGET_MS = 60_000;

export interface PhotoJob {
  photo_id: string;
  attempts?: number | null;
}
export interface PhotoRow {
  id: string;
  user_id: string;
  storage_key: string;
}
export type Verdict = "approved" | "rejected" | "needs_review";
export interface PhotoDeps {
  rpc: MatchRpcClient["rpc"];
  photo(id: string): Promise<PhotoRow | null>;
  download(key: string): Promise<Uint8Array | null>;
  replace(key: string, bytes: Uint8Array): Promise<boolean>;
  verdict(id: string, state: Verdict, reason: string | null): Promise<void>;
  finish(id: string, state: "pending" | "done" | "dead_letter", code: string | null): Promise<void>;
  vision(bytes: Uint8Array): Promise<VisionModerationResult>;
  matcher: CsamMatcher;
  quarantine: QuarantineStore;
  config: ModerationConfig;
  /** The wait between busy tries (tests pass a fake; default a timer). */
  sleep?(ms: number): Promise<void>;
  now?(): number;
}
/** "gone": the photo row was deleted while it was scanned (nothing to write). */
export type JobOutcome = Verdict | "csam_hit" | "retry" | "dead" | "gone";

/** Spec 2 W3c (D): a write that stayed busy; the job is requeued, never dead-lettered. */
export class BusyError extends Error {
  constructor() {
    super("dating_busy");
    this.name = "BusyError";
  }
}

const BUSY_SQLSTATES = new Set(["55P03", "40P01", "40001"]);

/** dating:busy, or a raw lock timeout (55P03), deadlock or serialization failure. */
export function isBusy(error: unknown): boolean {
  if (error instanceof BusyError) return true;
  if (!error || typeof error !== "object") return false;
  const e = error as { message?: unknown; code?: unknown };
  return e.message === "dating:busy" || (typeof e.code === "string" && BUSY_SQLSTATES.has(e.code));
}

/**
 * Spec 2 W3 final (M-6): the Vision step. With no key it fails closed
 * (missing_vision_api_key) without calling Vision; the CSAM scan before it
 * and the orphan sweep never depend on it.
 */
export function visionStep(
  apiKey: string | undefined,
  analyze: (p: { imageBytes: Uint8Array; apiKey: string }) => Promise<VisionModerationResult> = analyzeDatingPhoto,
): (bytes: Uint8Array) => Promise<VisionModerationResult> {
  return (bytes) => apiKey ? analyze({ imageBytes: bytes, apiKey }) : Promise.reject(new Error("missing_vision_api_key"));
}

type Sleep = (ms: number) => Promise<void>;
const timer: Sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

/**
 * One server write under the busy rule (D): a busy answer is tried again
 * after each backoff, then BusyError; any other error is [failCode] (the
 * server's text never travels on). Each try is its own transaction.
 */
async function write(rpc: MatchRpcClient["rpc"], sleep: Sleep, fn: string, args: Record<string, unknown>, failCode: string): Promise<unknown> {
  for (let i = 0;; i++) {
    const { data, error } = await rpc(fn, args);
    if (!error) return data;
    if (!isBusy(error)) throw new Error(failCode);
    if (i >= BUSY_BACKOFF_MS.length) throw new BusyError();
    await sleep(BUSY_BACKOFF_MS[i]);
  }
}

function answer(data: unknown): { ok?: unknown; reason?: unknown } {
  return data && typeof data === "object" ? data as { ok?: unknown; reason?: unknown } : {};
}

async function csam(deps: PhotoDeps, id: string, outcome: "clear" | "hit" | "error"): Promise<"ok" | "gone"> {
  const a = answer(await write(deps.rpc, deps.sleep ?? timer, "record_dating_photo_csam", { p_photo_id: id, p_outcome: outcome }, "csam_record_failed"));
  if (a.ok === true) return "ok";
  if (a.reason === "gone") return "gone";
  throw new Error("csam_record_failed");
}

/** Spec 2 W3 final (M-5): the strip's row check, before or after the re-upload. */
async function stripCheck(deps: PhotoDeps, photo: PhotoRow, phase: "before" | "after"): Promise<"ok" | "gone"> {
  const a = answer(await write(deps.rpc, deps.sleep ?? timer, "check_dating_photo_strip",
    { p_photo_id: photo.id, p_storage_key: photo.storage_key, p_phase: phase }, "strip_check_failed"));
  if (a.ok === true) return "ok";
  if (a.reason === "gone") return "gone";
  throw new Error("strip_check_failed");
}

/** B (R-25): the Dating hold for a hit whose photo row is gone. An account that is itself gone has nothing to hold. */
async function holdGone(deps: PhotoDeps, user: string): Promise<void> {
  const a = answer(await write(deps.rpc, deps.sleep ?? timer, "record_dating_csam_hold", { p_user: user }, "csam_hold_failed"));
  if (a.ok !== true && a.reason !== "gone") throw new Error("csam_hold_failed");
}

/**
 * Spec 1's quarantine-and-record path (the copy first; the original kept
 * when the copy failed). A record that fails is tried again after each
 * backoff with the same copy, never a second one.
 */
async function recordMatch(
  deps: { rpc: MatchRpcClient["rpc"]; quarantine: QuarantineStore; sleep?: Sleep },
  object: { key: string; owner: string },
  bytes: Uint8Array,
  mime: string,
  match: MatchResult,
): Promise<void> {
  const record = inlineRecorder({ rpc: deps.rpc }, {
    bucket: BUCKET,
    objectName: object.key,
    ownerUserId: object.owner,
    vendor: match.vendor,
    vendorRef: match.vendorRef,
  });
  const recorded = await quarantineAndRecord({
    bucket: BUCKET,
    objectName: object.key,
    bytes,
    mime,
    store: deps.quarantine,
    record,
  });
  if (recorded.recorded) return;
  for (const ms of BUSY_BACKOFF_MS) {
    await (deps.sleep ?? timer)(ms);
    const again = await record({ quarantined: recorded.quarantined, path: recorded.quarantinePath })
      .catch(() => ({ error: "record_threw" }));
    if (again.error === null) return;
  }
  throw new Error("csam_inline_record_failed");
}

export async function processPhotoJob(job: PhotoJob, deps: PhotoDeps): Promise<JobOutcome> {
  let matched = false;
  let cleared = false; // Spec 2 W3 final (I-2): the clear scan is recorded
  try {
    const photo = await deps.photo(job.photo_id);
    if (!photo) throw new Error("photo_missing");
    const bytes = await deps.download(photo.storage_key);
    if (!bytes) throw new Error("decode_failed");
    const mime = sniffMime(bytes);
    const match = await deps.matcher.match(bytes, mime);
    if (match.outcome === "match") {
      matched = true;
      const object = { key: photo.storage_key, owner: photo.user_id };
      let dating: "ok" | "gone" | "failed" = "failed";
      let failure: unknown = null;
      try {
        dating = await csam(deps, photo.id, "hit");
      } catch (e) {
        failure = e;
      }
      // C-1: Spec 1's record is never skipped.
      try {
        await recordMatch(deps, object, bytes, mime, match);
      } catch (e) {
        failure ??= e;
      }
      if (dating !== "ok") {
        // gone (B), or the Dating record did not land: the same hold, by owner.
        try {
          await holdGone(deps, photo.user_id);
        } catch (e) {
          failure ??= e;
        }
      }
      if (failure !== null) throw failure;
      if (dating === "ok") await deps.finish(photo.id, "done", null);
      return "csam_hit";
    }
    if (match.outcome !== "clear") {
      if ((await csam(deps, photo.id, "error")) === "gone") return "gone";
      throw new Error(`csam_${match.outcome}`);
    }
    if ((await csam(deps, photo.id, "clear")) === "gone") return "gone";
    cleared = true;
    const dims = readImageDimensions(bytes);
    if (!dims || dims.width < MIN_DIMENSION || dims.height < MIN_DIMENSION) {
      await deps.verdict(photo.id, "rejected", "too_small");
      await deps.finish(photo.id, "done", null);
      return "rejected";
    }
    const vision = await deps.vision(bytes);
    const ratio = vision.faceBoundingPolyVertices
      ? computeFaceAreaRatio(vision.faceBoundingPolyVertices, dims.width, dims.height)
      : null;
    const outcome = decideModerationOutcome({ ...vision, faceAreaRatio: ratio }, deps.config);
    if (outcome.state === "approved") {
      // Strip metadata before the photo can be seen (§4.3): a photo that
      // can't be cleaned goes to a person, never out with its GPS. M-3: only
      // a JPEG is stripped here; a PNG (eXIf, tEXt, iTXt) or WebP is never
      // published unstripped.
      const stripped = stripJpegMetadata(bytes);
      if (stripped) {
        // Spec 2 W3 final (M-5): never re-upload over a deleted photo; a row
        // gone after the upload has its object queued again (server side).
        if ((await stripCheck(deps, photo, "before")) === "gone") return "gone";
        if (!(await deps.replace(photo.storage_key, stripped))) throw new Error("strip_reupload_failed");
        if ((await stripCheck(deps, photo, "after")) === "gone") return "gone";
      } else {
        await deps.verdict(photo.id, "needs_review", "needs_review");
        await deps.finish(photo.id, "done", null);
        return "needs_review";
      }
    }
    await deps.verdict(photo.id, outcome.state, outcome.reason);
    await deps.finish(photo.id, "done", null);
    return outcome.state;
  } catch (error) {
    // D: busy is a retry at any attempt. I-1: so is a run that saw a match
    // (never a dead letter, never a needs_review over it); from the last
    // attempt on it is counted for an operator.
    // Spec 2 W3 final (I-2): a scan that never answered clear is busy too;
    // (M-6) so is a missing Vision key. Only a recorded clear scan is ever
    // dead-lettered to a person.
    const attempts = Number(job.attempts ?? 0);
    const noVision = errorCode(error) === "missing_vision_api_key";
    const dead = !isBusy(error) && !matched && cleared && !noVision && attempts >= MAX_ATTEMPTS;
    const bump = (key: string) => Promise.resolve(deps.rpc("bump_metric_server", { p_key: key })).catch(() => {});
    if (matched && attempts >= MAX_ATTEMPTS) {
      await bump("dating.photo.csam_record_stuck");
    } else if (!matched && !cleared && attempts >= MAX_ATTEMPTS) {
      await bump("dating.photo.csam_scan_stuck");
    }
    if (noVision) await bump("dating.photo.vision_unavailable");
    if (dead) await deps.verdict(job.photo_id, "needs_review", "needs_review").catch(() => {});
    await deps.finish(job.photo_id, dead ? "dead_letter" : "pending", errorCode(error)).catch(() => {});
    return dead ? "dead" : "retry";
  }
}

/** An upload whose intent expired unused (I-14), from claim_dating_orphan_uploads. */
export interface Orphan {
  intent_id: string;
  user_id: string;
  storage_key: string;
}
export interface OrphanDeps {
  rpc: MatchRpcClient["rpc"];
  download(key: string): Promise<Uint8Array | null>;
  matcher: CsamMatcher;
  quarantine: QuarantineStore;
  sleep?(ms: number): Promise<void>;
}
export type OrphanOutcome = "swept" | "csam_hit" | "retry";

/**
 * I-14: an orphan is scanned like a photo, CSAM first with the same matcher,
 * and only a recorded scan deletes it: clear -> record_dating_orphan_scan
 * 'clear' (its deletion is queued); a match -> Spec 1's inline record
 * (quarantine copy, hold, escalation; the original deleted only when the copy
 * exists), then 'hit'; a matcher that can't answer, missing bytes or any
 * failure -> 'error' (the claim is released for the next sweep). Vision is
 * never called: the object is going either way. Each record is tried again
 * when busy (D).
 */
export async function sweepOrphan(o: Orphan, deps: OrphanDeps): Promise<OrphanOutcome> {
  const record = async (outcome: "clear" | "hit" | "error") => {
    const a = answer(await write(deps.rpc, deps.sleep ?? timer, "record_dating_orphan_scan", { p_intent_id: o.intent_id, p_outcome: outcome }, "orphan_record_failed"));
    if (a.ok !== true) throw new Error("orphan_record_failed");
  };
  try {
    const bytes = await deps.download(o.storage_key);
    if (!bytes) {
      await record("error");
      return "retry";
    }
    const mime = sniffMime(bytes);
    const match = await deps.matcher.match(bytes, mime);
    if (match.outcome === "match") {
      await recordMatch(deps, { key: o.storage_key, owner: o.user_id }, bytes, mime, match);
      try {
        await record("hit");
      } catch (e) {
        // I-2: Spec 1 has recorded (the original is queued for deletion), so
        // the next sweep may never see this orphan again: the owner-keyed
        // Dating hold first (idempotent, the busy rule), then released.
        await write(deps.rpc, deps.sleep ?? timer, "record_dating_csam_hold", { p_user: o.user_id }, "csam_hold_failed").catch(() => {});
        throw e;
      }
      return "csam_hit";
    }
    if (match.outcome !== "clear") throw new Error(`csam_${match.outcome}`);
    await record("clear");
    return "swept";
  } catch {
    // Never deleted unscanned: the claim is released (or lapses in 10 min).
    await record("error").catch(() => {});
    return "retry";
  }
}

function jobsOf(rows: unknown): PhotoJob[] {
  if (!Array.isArray(rows)) return [];
  return rows.flatMap((r) =>
    r && typeof r.photo_id === "string" ? [{ photo_id: r.photo_id, attempts: typeof r.attempts === "number" ? r.attempts : 0 }] : []
  );
}

function orphansOf(rows: unknown): Orphan[] {
  if (!Array.isArray(rows)) return [];
  return rows.flatMap((r) =>
    r && typeof r.intent_id === "string" && typeof r.user_id === "string" && typeof r.storage_key === "string"
      ? [{ intent_id: r.intent_id, user_id: r.user_id, storage_key: r.storage_key }]
      : []
  );
}

/**
 * One run (C): claim_dating_photo_jobs (one RPC: its row locks are released
 * when it returns), then each job; on the cron call (no photo id) the
 * orphan sweep the same way (up to 10).
 */
export async function runWorker(requestedId: string | null, deps: PhotoDeps): Promise<{ processed: number; orphans: number }> {
  const now = deps.now ?? Date.now;
  const start = now();
  const late = () => now() - start > RUN_BUDGET_MS;
  const { data: jobs, error } = await deps.rpc("claim_dating_photo_jobs", { p_limit: requestedId ? 1 : PHOTO_CLAIM_LIMIT, p_photo_id: requestedId });
  if (error) throw new Error("claim_failed");
  let processed = 0;
  for (const job of jobsOf(jobs)) {
    if (late()) {
      // M-6: not started; straight back to pending for the next run.
      await deps.finish(job.photo_id, "pending", "deferred").catch(() => {});
      continue;
    }
    if ((await processPhotoJob(job, deps)) !== "retry") processed++;
  }
  // I-14: the 15-minute cron call (no photo id) also sweeps orphan
  // uploads, CSAM first; nothing is deleted unscanned.
  let orphans = 0;
  if (!requestedId && !late()) {
    const { data: claimed, error: claimError } = await deps.rpc("claim_dating_orphan_uploads", { p_limit: 10 });
    if (claimError) throw new Error("orphan_claim_failed");
    for (const o of orphansOf(claimed)) {
      // M-6: an orphan not started keeps its claim, which lapses in 10
      // minutes (no failed scan is counted against it).
      if (late()) break;
      if ((await sweepOrphan(o, deps)) !== "retry") orphans++;
    }
  }
  return { processed, orphans };
}

export function sniffMime(b: Uint8Array): string {
  if (b.length >= 3 && b[0] === 0xFF && b[1] === 0xD8 && b[2] === 0xFF) return "image/jpeg";
  if (b.length >= 8 && b[0] === 0x89 && b[1] === 0x50 && b[2] === 0x4E && b[3] === 0x47) return "image/png";
  if (b.length >= 12 && b[0] === 0x52 && b[1] === 0x49 && b[8] === 0x57 && b[9] === 0x45) return "image/webp";
  return "application/octet-stream";
}

/**
 * E: the stored and answered error code. Only the worker's own fixed codes
 * pass; anything else (a database, storage or vendor message, which can
 * carry a row, a path or a key) is "internal_error".
 */
const KNOWN_CODES = new Set([
  "photo_missing",
  "decode_failed",
  "csam_record_failed",
  "csam_inline_record_failed",
  "csam_hold_failed",
  "csam_unavailable",
  "csam_skipped",
  "strip_reupload_failed",
  "strip_check_failed",
  "dating_busy",
  "deferred",
  "photo_read_failed",
  "verdict_failed",
  "finish_failed",
  "claim_failed",
  "orphan_claim_failed",
  "orphan_record_failed",
  "missing_vision_api_key",
  "vision_empty_response",
]);
export function errorCode(error: unknown): string {
  const message = error instanceof Error ? error.message : "";
  if (KNOWN_CODES.has(message) || /^vision_(?:http|api)_error_[a-z0-9]{1,16}$/.test(message)) return message;
  return "internal_error";
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
export function stripJpegMetadata(bytes: Uint8Array): Uint8Array | null {
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

export function readImageDimensions(
  bytes: Uint8Array,
): { width: number; height: number } | null {
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

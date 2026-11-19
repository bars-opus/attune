// supabase/functions/dating-verification/handler.ts
// Spec 2 W4a (§3.3, §4.7): the verification flow behind D11, through the
// §3.3.5 seam. Actions: start, complete (the video check: liveness, then
// CompareFaces against every approved photo, then the age estimate),
// start_id, complete_id (the ID route), human_start, submit_human (the
// human route). Every result is written by the service functions of
// 20261109100000_dating_v2_age_assurance.sql; this file holds no state.
//
// Rules (W3 lessons, DPIA):
// - No database call is open across a vendor or storage call: each RPC is
//   its own short transaction, awaited before the network call starts
//   (read or claim, release, network, then record).
// - Busy (a writer's {ok:false, reason:'busy'} after its own three lock
//   tries, or a lock, deadlock or serialization SQLSTATE) is tried again
//   after 250 and 500 ms, each try its own transaction; then "busy". A call
//   that threw may have committed and is never tried again. Busy never
//   ends or fails a session; it is counted (dating.verify.busy).
// - A vendor or storage call that can't answer is tried again after 250
//   and 500 ms (no try starts 100 s into the request); then
//   "vendor_unavailable": nothing is counted against the person, nothing
//   fails, the session stays open and the person tries again (§3.15 D11);
//   it is counted for an operator (dating.verify.vendor_unavailable).
// - Nothing is logged here. The reference frame, the photos' bytes, the
//   estimate and the ID's date of birth live only inside the call that
//   needs them (the frame is zeroed after use) and never reach a log, the
//   database or the answer.
// - The answer carries fixed codes only, never vendor or server text.
// - fake is refused unless the environment reads development (§3.3.5,
//   Q19b), and a scenario is accepted only in fake mode.
// - Spec 2 W4b (§3.3.4): the phone that passes D11's face match is
//   trusted; a re-check (reverify_start, reverify_complete, human_start
//   with reverify) runs on an untrusted phone of a person who passed, is
//   liveness and CompareFaces only (no age), trusts that phone on a pass
//   and never writes the account's own identity result (R-14: a stranger
//   failing on a new phone must not unverify the owner). trust never
//   touches a kept Never-introduce list (Task 5's C-1 ruling).
// - Spec 2 W4b fix round 1 (I-4 ruling): every action that needs the
//   phone answers device_unavailable when the request names none (no
//   install id on this phone), before begin is called; begin's NULL-hash
//   invalid is never reached and never re-mapped.
// - Spec 2 W4 final (I-1b ruling): an age pass whose every approved photo
//   is newer than it (the session read's age_recheck) is estimated again
//   on the live frame (R-13: uncertain or below 25 goes to the ID check,
//   far below 18 to Spec 1's hold). (M-3) Every trust names the session
//   that ran on the phone. (M-4) Another phone's open check answers
//   session_elsewhere, never busy. (M-5) complete, complete_id and
//   submit_human need the phone too. (M-6) A far-below face wins over a
//   photo that doesn't match it. (M-7) An estimator that can't be reached
//   is vendor_unavailable. (M-8) The far-below row names the vendor that
//   decided. (M-12) A photo whose object is gone is photos_required.
//   (I-2) An ID the vendor asks to retake waits for a person (never
//   final); one showing under 18 takes Spec 1's hold.
import { FAKE_DECLARED_DOB } from "../_shared/age_assurance/fake.ts";
import {
  type AgeDecision,
  ageDecision,
  calendarDate,
  CHALLENGE_AGE,
  isFakeScenario,
  type Mode,
  type Providers,
} from "../_shared/age_assurance/types.ts";

export type RpcResult = { data: unknown; error: unknown };
export type Rpc = (fn: string, args?: Record<string, unknown>) => PromiseLike<RpcResult>;

export interface VerificationDeps {
  rpc: Rpc;
  /// An approved photo's bytes (dating-profile-photos); null when its
  /// object is not there (Spec 2 W4 final, M-12: photos_required); throws
  /// when Storage can't answer (an outage, tried again).
  download(key: string): Promise<Uint8Array | null>;
  providers(mode: Mode, environment: string): Providers | null;
  /// The wait between tries (tests pass a recorder; default a timer).
  sleep?(ms: number): Promise<void>;
  /// The clock the vendor deadline reads (default Date.now).
  now?(): number;
  /// Set by handleVerification: when this request began (the deadline).
  started?: number;
  /// The photo download's bound (default DOWNLOAD_TIMEOUT_MS; tests pass their own).
  downloadTimeoutMs?: number;
}

/// The waits before the second and the third try of a busy call.
export const BUSY_BACKOFF_MS: readonly number[] = [250, 500];
/// The waits before the second and the third try of a vendor or storage call.
export const VENDOR_BACKOFF_MS: readonly number[] = [250, 500];
/// No vendor or storage try starts this long into the request (the edge
/// function's 150 s wall clock; each vendor call has its own 10 s timeout).
export const VENDOR_DEADLINE_MS = 100_000;
/// Task 2 fix round 1 (I-3): the video outcome's waits. It is the one
/// write after the capture (a far-below hold among them), so it keeps
/// trying longer; still bounded by RPC_DEADLINE_MS.
export const OUTCOME_BACKOFF_MS: readonly number[] = [250, 500, 1000, 2000, 4000];
/// Task 2 fix round 1 (M-7): no busy wait ends past this into the request.
export const RPC_DEADLINE_MS = 130_000;
/// Task 2 fix round 1 (M-8): the photo download is bounded like a vendor call.
export const DOWNLOAD_TIMEOUT_MS = 10_000;
const VIDEO_OUTCOMES: ReadonlySet<string> = new Set(["verified", "needs_id", "age_uncertain", "photo_mismatch", "far_below"]);

/// [p] or a rejection after [ms]; the timer is always cleared.
function withTimeout<T>(p: Promise<T>, ms: number): Promise<T> {
  let timer: ReturnType<typeof setTimeout> | undefined;
  const late = new Promise<never>((_, reject) => {
    timer = setTimeout(() => reject(new Error("timeout")), ms);
  });
  return Promise.race([p, late]).finally(() => clearTimeout(timer));
}

/// I-2: a refusal the vendor will repeat (its error says retryable: false).
function refusedForGood(e: unknown): boolean {
  return typeof e === "object" && e !== null && (e as { retryable?: unknown }).retryable === false;
}

const timer = (ms: number) => new Promise<void>((resolve) => setTimeout(resolve, ms));
const clock = (deps: VerificationDeps) => (deps.now ?? Date.now)();
const BUSY_SQLSTATES = new Set(["55P03", "40P01", "40001"]);

function isBusy(res: RpcResult): boolean {
  if (res.error) {
    const code = typeof res.error === "object" ? (res.error as { code?: unknown }).code : undefined;
    return typeof code === "string" && BUSY_SQLSTATES.has(code);
  }
  const d = res.data as { ok?: unknown; reason?: unknown } | null;
  return d !== null && typeof d === "object" && d.ok === false && d.reason === "busy";
}

/// One service function under the busy rule; null when it threw or erred.
async function rpcTry(
  deps: VerificationDeps,
  fn: string,
  args: Record<string, unknown>,
  backoff: readonly number[] = BUSY_BACKOFF_MS,
): Promise<RpcResult | null> {
  const started = deps.started ?? clock(deps);
  for (let i = 0;; i++) {
    let res: RpcResult;
    try {
      res = await deps.rpc(fn, args);
    } catch {
      return null; // it may have committed: never tried again
    }
    if (!isBusy(res) || i >= backoff.length || clock(deps) - started + backoff[i] > RPC_DEADLINE_MS) return res;
    await (deps.sleep ?? timer)(backoff[i]);
  }
}

class VendorDown extends Error {
  constructor() {
    super("vendor_unavailable");
  }
}

/// One vendor or storage call: tried again after each wait, then
/// VendorDown (counted). Its error is never read, logged or passed on.
async function vendor<T>(deps: VerificationDeps, f: () => Promise<T>): Promise<T> {
  const started = deps.started ?? clock(deps);
  for (let i = 0; clock(deps) - started <= VENDOR_DEADLINE_MS; i++) {
    try {
      return await f();
    } catch (e) {
      if (refusedForGood(e) || i >= VENDOR_BACKOFF_MS.length || clock(deps) - started + VENDOR_BACKOFF_MS[i] > VENDOR_DEADLINE_MS) break;
      await (deps.sleep ?? timer)(VENDOR_BACKOFF_MS[i]);
    }
  }
  await count(deps, "dating.verify.vendor_unavailable");
  throw new VendorDown();
}

/// An operator's counter (service role); a failure to count is ignored.
async function count(deps: VerificationDeps, key: string): Promise<void> {
  try {
    await deps.rpc("bump_metric_server", { p_key: key });
  } catch {
    // never blocks the answer
  }
}

export interface Caller {
  userId: string;
  /// sha256 hex of the x-attune-device header, or null (W4b reads it).
  deviceHash: string | null;
}

export type Answer = Record<string, unknown> & { ok: boolean };

const FIXED_REASONS = new Set([
  "unavailable", "invalid", "not_eligible", "consent_required", "photos_required", "age_not_confirmed",
  "already_verified", "awaiting_review", "rate_limited", "busy", "session_unavailable", "photos_missing",
  "reverify_device", "vendor_unavailable", "device_unavailable",
  "session_elsewhere", // Spec 2 W4 final (M-4): another phone's check is open (never busy)
]);

function refusal(reason: unknown): Answer {
  return { ok: false, reason: typeof reason === "string" && FIXED_REASONS.has(reason) ? reason : "busy" };
}

async function call(
  deps: VerificationDeps,
  fn: string,
  args: Record<string, unknown>,
  backoff: readonly number[] = BUSY_BACKOFF_MS,
): Promise<Record<string, unknown> | null> {
  const res = await rpcTry(deps, fn, args, backoff);
  if (res === null || res.error || res.data === null || typeof res.data !== "object") return null;
  return res.data as Record<string, unknown>;
}

async function scalar(deps: VerificationDeps, fn: string, args: Record<string, unknown>): Promise<unknown> {
  const res = await rpcTry(deps, fn, args);
  return res === null || res.error ? null : res.data;
}

interface Setup {
  mode: Mode;
  providers: Providers;
}

async function setup(deps: VerificationDeps): Promise<Setup | Answer> {
  const cfg = await call(deps, "get_dating_verification_config", {});
  if (cfg === null) return refusal("busy");
  const mode = cfg.mode;
  const environment = typeof cfg.environment === "string" ? cfg.environment : "production";
  if (mode !== "fake" && mode !== "sandbox" && mode !== "live") return refusal("unavailable");
  // §3.3.5: fake is refused in production mode, whatever the database said.
  if (mode === "fake" && environment !== "development") return refusal("unavailable");
  // Task 2 fix round 1 (M-6 ruling): so is sandbox (its answers are not real verification).
  if (mode === "sandbox" && environment !== "development") return refusal("unavailable");
  if (cfg.available !== true) return refusal("unavailable");
  const providers = deps.providers(mode, environment);
  if (providers === null) return refusal("unavailable");
  return { mode, providers };
}

function isAnswer(x: Setup | Answer): x is Answer {
  return "ok" in x;
}

function scenarioFor(mode: Mode, body: Record<string, unknown>): { ok: true; scenario?: string } | { ok: false } {
  if (body.scenario === undefined || body.scenario === null) return { ok: true };
  if (mode !== "fake" || !isFakeScenario(body.scenario)) return { ok: false };
  return { ok: true, scenario: body.scenario };
}

function uuidOf(value: unknown): string | null {
  return typeof value === "string" && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(value) ? value : null;
}

async function finish(deps: VerificationDeps, session: string, state: string, outcome: string, position: number | null = null) {
  const r = await call(deps, "finish_dating_verification_session", {
    p_session: session, p_state: state, p_outcome: outcome, p_position: position,
  });
  return r?.ok === true;
}

/// start: a video session (resumed when one is open), then the vendor's.
async function start(caller: Caller, body: Record<string, unknown>, deps: VerificationDeps): Promise<Answer> {
  const s = await setup(deps);
  if (isAnswer(s)) return s;
  if (caller.deviceHash === null) return refusal("device_unavailable"); // Spec 2 W4b fix round 1 (I-4)
  const sc = scenarioFor(s.mode, body);
  if (!sc.ok) return refusal("invalid");
  const begun = await call(deps, "begin_dating_verification", {
    p_user: caller.userId, p_kind: "activation", p_step: "liveness", p_vendor: s.providers.liveness.name,
    p_device_hash: caller.deviceHash, p_document: null,
  });
  if (begun === null) return refusal("busy");
  if (begun.ok !== true) return refusal(begun.reason);
  const session = uuidOf(begun.session_id);
  if (session === null) return refusal("busy");
  let ref: string;
  try {
    ref = (await vendor(deps, () => s.providers.liveness.createSession({ scenario: sc.scenario }))).ref;
  } catch {
    return refusal("vendor_unavailable");
  }
  const set = await call(deps, "set_dating_verification_ref", { p_session: session, p_ref: ref });
  if (set === null) return refusal("busy");
  if (set.ok !== true) return refusal(set.reason);
  return {
    ok: true, session_id: session, vendor: s.providers.liveness.name, vendor_session: ref,
    attempts: typeof begun.attempts === "number" ? begun.attempts : 0, resumed: begun.resumed === true,
  };
}

/// complete: the vendor's answer, then every photo, then the age; every
/// network call first, then ONE write of the whole outcome (Task 2 fix
/// round 1, I-3 ruling: record_dating_video_outcome, one transaction, so
/// a busy answer can never leave the identity written without the
/// far-below hold).
async function complete(caller: Caller, body: Record<string, unknown>, deps: VerificationDeps): Promise<Answer> {
  const s = await setup(deps);
  if (isAnswer(s)) return s;
  if (caller.deviceHash === null) return refusal("device_unavailable"); // Spec 2 W4 final (M-5)
  const session = uuidOf(body.session_id);
  if (session === null) return refusal("invalid");
  const row = await call(deps, "get_dating_verification_session", { p_user: caller.userId, p_session: session });
  if (row === null) return refusal("busy");
  if (row.ok !== true || row.kind !== "activation" || row.step !== "liveness" || row.state !== "started"
      || row.expired === true || typeof row.vendor_session_ref !== "string") {
    return refusal("session_unavailable");
  }
  const ref = row.vendor_session_ref;
  let result;
  try {
    result = await vendor(deps, () => s.providers.liveness.results(ref));
  } catch {
    return refusal("vendor_unavailable");
  }
  if (result.status === "pending") return { ok: true, outcome: "pending" };
  if (result.status === "expired") return refusal("vendor_unavailable");
  if (result.status === "failed" || result.reference === null) {
    const r = await call(deps, "record_dating_liveness_attempt", { p_session: session, p_passed: false });
    if (r === null) return refusal("busy");
    if (r.ok !== true) return refusal(r.reason);
    return { ok: true, outcome: r.outcome === "another_way" ? "another_way" : "retry", attempts: r.attempts };
  }
  const frame = result.reference;
  let identity: "pass" | "fail" = "pass";
  let position: number | null = null;
  let age: "skip" | AgeDecision = "skip";
  // Spec 2 W4 final (I-1b ruling): no age pass, or one whose every
  // approved photo is newer than it: the age is decided on this frame.
  const needAge = row.age !== "pass" || row.age_recheck === true;
  try {
    const photos = await scalar(deps, "get_dating_verification_photos", { p_user: caller.userId });
    if (!Array.isArray(photos)) return refusal("busy");
    if (photos.length < 2) return refusal("photos_required");
    for (let i = 0; i < photos.length; i++) {
      const p = photos[i] as { position?: unknown; storage_key?: unknown };
      if (typeof p?.storage_key !== "string" || typeof p.position !== "number") return refusal("busy");
      const key = p.storage_key;
      let bytes: Uint8Array | null;
      try {
        bytes = await vendor(deps, () => withTimeout(deps.download(key), deps.downloadTimeoutMs ?? DOWNLOAD_TIMEOUT_MS));
      } catch {
        return refusal("vendor_unavailable");
      }
      if (bytes === null) return refusal("photos_required"); // Spec 2 W4 final (M-12): the object is gone, never an outage
      const target = bytes;
      let same: boolean;
      try {
        same = await vendor(deps, () => s.providers.faceMatch.compare(frame, target, i));
      } catch {
        return refusal("vendor_unavailable");
      } finally {
        bytes.fill(0);
      }
      if (!same) {
        identity = "fail";
        position = p.position;
        break;
      }
    }
    // Spec 2 W4 final (M-6): on a photo that doesn't match, the estimate
    // still runs, for far below 18 only (Spec 1's hold wins over "change
    // that photo"); an estimator that can't answer is then ignored.
    if (needAge || identity === "fail") {
      let estimate = null;
      try {
        estimate = await vendor(deps, () => s.providers.age.estimate(frame));
      } catch {
        // Spec 2 W4 final (M-7): can't be reached: counts nothing, the session stays open.
        if (identity === "pass") return refusal("vendor_unavailable");
      }
      const decision = ageDecision(estimate, CHALLENGE_AGE);
      estimate = null;
      if (identity === "pass") age = decision;
      else if (decision === "far_below") age = "far_below"; // Spec 2 W4 final (M-6)
    }
  } finally {
    frame.fill(0);
  }
  // R-13 (owner ruling 2026-11-09): needs_id and uncertain record no age;
  // the writer ends the session and the ID route opens next.
  const r = await call(deps, "record_dating_video_outcome", {
    p_user: caller.userId, p_session: session, p_identity: identity,
    p_age: identity === "fail" ? (age === "far_below" ? "far_below" : null) : age, // Spec 2 W4 final (M-6)
    p_position: position, p_identity_vendor: s.providers.faceMatch.name, p_age_vendor: s.providers.age.name,
  }, OUTCOME_BACKOFF_MS);
  if (r === null) return refusal("busy");
  if (r.ok !== true) return refusal(r.reason);
  const outcome = typeof r.outcome === "string" && VIDEO_OUTCOMES.has(r.outcome) ? r.outcome : null;
  if (outcome === null) return refusal("busy");
  // Spec 2 W4b (§3.3.4): the phone whose face matched every photo is
  // trusted (best effort: the setup's phone stays trusted for the setup
  // without it). Not on a mismatch, nor on Spec 1's hold.
  // Fix round 1 (M-1): only the phone the session ran on.
  if (identity === "pass" && outcome !== "far_below" && caller.deviceHash !== null && row.device_hash === caller.deviceHash) {
    await call(deps, "trust_dating_device", { p_user: caller.userId, p_device_hash: caller.deviceHash, p_session: session }); // Spec 2 W4 final (M-3)
  }
  if (outcome === "photo_mismatch") {
    return typeof r.position === "number" ? { ok: true, outcome, position: r.position } : refusal("busy");
  }
  return { ok: true, outcome };
}

/// start_id: an ID session for the chosen document, then the vendor's job.
async function startId(caller: Caller, body: Record<string, unknown>, deps: VerificationDeps): Promise<Answer> {
  const s = await setup(deps);
  if (isAnswer(s)) return s;
  if (caller.deviceHash === null) return refusal("device_unavailable"); // Spec 2 W4b fix round 1 (I-4)
  const sc = scenarioFor(s.mode, body);
  if (!sc.ok) return refusal("invalid");
  const document = typeof body.document === "string" && /^[a-z0-9_]{1,40}$/.test(body.document) ? body.document : null;
  if (document === null) return refusal("invalid");
  const begun = await call(deps, "begin_dating_verification", {
    p_user: caller.userId, p_kind: "activation", p_step: "id", p_vendor: s.providers.id.name,
    p_device_hash: caller.deviceHash, p_document: document,
  });
  if (begun === null) return refusal("busy");
  if (begun.ok !== true) return refusal(begun.reason);
  const session = uuidOf(begun.session_id);
  if (session === null) return refusal("busy");
  const row = await call(deps, "get_dating_verification_session", { p_user: caller.userId, p_session: session });
  if (row?.ok !== true || typeof row.country !== "string") return refusal("busy");
  let ref: string;
  try {
    const country = row.country;
    ref = (await vendor(deps, () => s.providers.id.startJob({ document, country, sessionId: session, scenario: sc.scenario }))).ref;
  } catch {
    return refusal("vendor_unavailable");
  }
  const set = await call(deps, "set_dating_verification_ref", { p_session: session, p_ref: ref });
  if (set === null) return refusal("busy");
  if (set.ok !== true) return refusal(set.reason);
  return { ok: true, session_id: session, vendor: s.providers.id.name, vendor_job: ref, resumed: begun.resumed === true };
}

/// complete_id: the vendor's result; the date of birth compared, dropped.
async function completeId(caller: Caller, body: Record<string, unknown>, deps: VerificationDeps): Promise<Answer> {
  const s = await setup(deps);
  if (isAnswer(s)) return s;
  if (caller.deviceHash === null) return refusal("device_unavailable"); // Spec 2 W4 final (M-5)
  const session = uuidOf(body.session_id);
  if (session === null) return refusal("invalid");
  const row = await call(deps, "get_dating_verification_session", { p_user: caller.userId, p_session: session });
  if (row === null) return refusal("busy");
  const waiting = row.state === "awaiting_review" && (row.outcome === "id_pending" || row.outcome === "dob_mismatch");
  if (row.ok !== true || row.step !== "id" || !(row.state === "started" || waiting)
      || (row.state === "started" && row.expired === true) || typeof row.vendor_session_ref !== "string") {
    return refusal("session_unavailable");
  }
  const job = row.vendor_session_ref;
  let r;
  try {
    r = await vendor(deps, () => s.providers.id.result(job));
  } catch {
    return refusal("vendor_unavailable");
  }
  // Task 2 fix round 1 (I-1 ruling): only an explicit fail, or a face that
  // explicitly doesn't match, is final; an unknown face match waits.
  if (r.status === "fail" || r.faceMatch === false) {
    const a = await call(deps, "record_dating_age_assurance", {
      p_user: caller.userId, p_age_method: "id", p_age_result: "fail", p_challenge_age: null, p_vendor: s.providers.id.name,
    });
    if (a === null) return refusal("busy");
    // M-4: an earlier try recorded the fail but its end stayed busy: end it now.
    if (a.ok !== true && a.reason !== "age_not_confirmed") return refusal(a.reason);
    if (!(await finish(deps, session, "failed", "age_not_confirmed"))) return refusal("busy");
    return { ok: true, outcome: "age_not_confirmed" };
  }
  // Spec 2 W4 final (I-2; R-8): the document shows under 18: Spec 1's hold.
  if (r.status === "minor") {
    const f = await call(deps, "record_dating_age_far_below", { p_user: caller.userId, p_session: session, p_vendor: s.providers.id.name });
    if (f?.ok !== true) return refusal(f?.reason ?? "busy");
    return { ok: true, outcome: "far_below" };
  }
  // Spec 2 W4 final (I-2): an ID the vendor asks to retake ("retry") is
  // never final: it waits like a pending one, and a person may ask for
  // another ID (the app has no retake state of its own yet).
  if (r.status === "pending" || r.status === "retry" || r.faceMatch !== true) {
    if (row.state === "started" && !(await finish(deps, session, "awaiting_review", "id_pending"))) return refusal("busy");
    return { ok: true, outcome: "id_pending" };
  }
  // Only the fake can answer "the declared date" (development); a real
  // vendor's date is compared by the database and forgotten.
  // M-2: a date that isn't a calendar date never reaches SQL (its cast
  // error would carry it into the database log): unknown, a person checks.
  const dob = calendarDate(r.dob);
  const check = s.providers.id.name === "fake" && r.dob === FAKE_DECLARED_DOB
    ? "match"
    : dob === null
    ? "unknown"
    : await scalar(deps, "check_dating_id_birth_date", { p_user: caller.userId, p_dob: dob });
  r = null;
  if (check === "minor") {
    const f = await call(deps, "record_dating_age_far_below", {
      p_user: caller.userId, p_session: session, p_vendor: s.providers.id.name, // Spec 2 W4 final (M-8): the ID vendor decided
    });
    if (f?.ok !== true) return refusal(f?.reason ?? "busy");
    return { ok: true, outcome: "far_below" };
  }
  if (check !== "match") {
    if (check !== "mismatch" && check !== "unknown") return refusal("busy");
    if (row.outcome !== "dob_mismatch" && !(await finish(deps, session, "awaiting_review", "dob_mismatch"))) return refusal("busy");
    return { ok: true, outcome: "dob_mismatch" };
  }
  const a = await call(deps, "record_dating_age_assurance", {
    p_user: caller.userId, p_age_method: "id", p_age_result: "pass", p_challenge_age: null, p_vendor: s.providers.id.name,
  });
  if (a?.ok !== true) return refusal(a?.reason ?? "busy");
  if (!(await finish(deps, session, "passed", "verified"))) return refusal("busy");
  return { ok: true, outcome: "verified" };
}

/// human_start: a human-review session with its two gestures and paths.
async function humanStart(caller: Caller, body: Record<string, unknown>, deps: VerificationDeps): Promise<Answer> {
  const s = await setup(deps);
  if (isAnswer(s)) return s;
  // Spec 2 W4b (§3.3.4): the re-check's "Check another way".
  const reverify = body.reverify === true;
  if (caller.deviceHash === null) return refusal("device_unavailable"); // Spec 2 W4b fix round 1 (I-4)
  const begun = await call(deps, "begin_dating_verification", {
    p_user: caller.userId, p_kind: reverify ? "reverify" : "activation", p_step: "human", p_vendor: "attune",
    p_device_hash: caller.deviceHash, p_document: null,
  });
  if (begun === null) return refusal("busy");
  if (begun.ok !== true) return refusal(begun.reason);
  const session = uuidOf(begun.session_id);
  const gestures = Array.isArray(begun.gestures) ? begun.gestures.filter((g) => typeof g === "string") : [];
  if (session === null || gestures.length !== 2) return refusal("busy");
  return { ok: true, session_id: session, gestures, paths: [`${session}/1.jpg`, `${session}/2.jpg`], resumed: begun.resumed === true };
}

/// submit_human: both photos are there; a person checks.
async function submitHuman(caller: Caller, body: Record<string, unknown>, deps: VerificationDeps): Promise<Answer> {
  const s = await setup(deps);
  if (isAnswer(s)) return s;
  if (caller.deviceHash === null) return refusal("device_unavailable"); // Spec 2 W4 final (M-5)
  const session = uuidOf(body.session_id);
  if (session === null) return refusal("invalid");
  const r = await call(deps, "submit_dating_human_review", { p_user: caller.userId, p_session: session });
  if (r === null) return refusal("busy");
  if (r.ok !== true) return refusal(r.reason);
  return { ok: true, outcome: "human_pending" };
}

/// Spec 2 W4 final (M-12): Storage's answer for an object that isn't there
/// (its API's statusCode "404", whatever the HTTP status; or a 404). Any
/// other error is an outage. Only the codes are read, never the message.
export function storageNotFound(error: unknown): boolean {
  if (error === null || typeof error !== "object") return false;
  const e = error as { status?: unknown; statusCode?: unknown };
  return e.statusCode === "404" || e.status === 404;
}

/// §3.3.4: the sha256 (hex) of the x-attune-device header when it is a
/// 128-bit id as 32 lowercase hex characters, the same value the database's
/// private.dating_request_device_hash() computes; else null. The id itself
/// is never stored or logged.
export async function deviceHashOf(header: string | null): Promise<string | null> {
  if (header === null || !/^[0-9a-f]{32}$/.test(header)) return null;
  const digest = new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(header)));
  return Array.from(digest, (b) => b.toString(16).padStart(2, "0")).join("");
}

/// Spec 2 W4b (§3.3.4): reverify_start: a re-check session on this phone.
async function reverifyStart(caller: Caller, body: Record<string, unknown>, deps: VerificationDeps): Promise<Answer> {
  const s = await setup(deps);
  if (isAnswer(s)) return s;
  if (caller.deviceHash === null) return refusal("device_unavailable"); // Spec 2 W4b fix round 1 (I-4)
  const sc = scenarioFor(s.mode, body);
  if (!sc.ok) return refusal("invalid");
  const begun = await call(deps, "begin_dating_verification", {
    p_user: caller.userId, p_kind: "reverify", p_step: "liveness", p_vendor: s.providers.liveness.name,
    p_device_hash: caller.deviceHash, p_document: null,
  });
  if (begun === null) return refusal("busy");
  if (begun.ok !== true) return refusal(begun.reason);
  const session = uuidOf(begun.session_id);
  if (session === null) return refusal("busy");
  let ref: string;
  try {
    ref = (await vendor(deps, () => s.providers.liveness.createSession({ scenario: sc.scenario }))).ref;
  } catch {
    return refusal("vendor_unavailable");
  }
  const set = await call(deps, "set_dating_verification_ref", { p_session: session, p_ref: ref });
  if (set === null) return refusal("busy");
  if (set.ok !== true) return refusal(set.reason);
  return {
    ok: true, session_id: session, vendor: s.providers.liveness.name, vendor_session: ref,
    attempts: typeof begun.attempts === "number" ? begun.attempts : 0, resumed: begun.resumed === true,
  };
}

/// Spec 2 W4b (§3.3.4): reverify_complete: liveness, then every approved
/// photo; a pass trusts this phone. No age, and never the account's own
/// identity result (R-14).
async function reverifyComplete(caller: Caller, body: Record<string, unknown>, deps: VerificationDeps): Promise<Answer> {
  const s = await setup(deps);
  if (isAnswer(s)) return s;
  if (caller.deviceHash === null) return refusal("device_unavailable"); // Spec 2 W4b fix round 1 (I-4)
  const session = uuidOf(body.session_id);
  if (session === null) return refusal("invalid");
  const row = await call(deps, "get_dating_verification_session", { p_user: caller.userId, p_session: session });
  if (row === null) return refusal("busy");
  if (row.ok !== true || row.kind !== "reverify" || row.step !== "liveness" || row.state !== "started"
      || row.expired === true || typeof row.vendor_session_ref !== "string" || row.device_hash !== caller.deviceHash) {
    return refusal("session_unavailable");
  }
  const ref = row.vendor_session_ref;
  let result;
  try {
    result = await vendor(deps, () => s.providers.liveness.results(ref));
  } catch {
    return refusal("vendor_unavailable");
  }
  if (result.status === "pending") return { ok: true, outcome: "pending" };
  if (result.status === "expired") return refusal("vendor_unavailable");
  if (result.status === "failed" || result.reference === null) {
    const r = await call(deps, "record_dating_liveness_attempt", { p_session: session, p_passed: false });
    if (r === null) return refusal("busy");
    if (r.ok !== true) return refusal(r.reason);
    return { ok: true, outcome: r.outcome === "another_way" ? "another_way" : "retry", attempts: r.attempts };
  }
  const frame = result.reference;
  let same = true;
  try {
    const live = await call(deps, "record_dating_liveness_attempt", { p_session: session, p_passed: true });
    if (live === null) return refusal("busy");
    if (live.ok !== true) return refusal(live.reason);
    const photos = await scalar(deps, "get_dating_verification_photos", { p_user: caller.userId });
    if (!Array.isArray(photos)) return refusal("busy");
    if (photos.length < 2) return refusal("photos_required");
    for (let i = 0; i < photos.length && same; i++) {
      const p = photos[i] as { storage_key?: unknown };
      if (typeof p?.storage_key !== "string") return refusal("busy");
      const key = p.storage_key;
      let bytes: Uint8Array | null;
      try {
        bytes = await vendor(deps, () => withTimeout(deps.download(key), deps.downloadTimeoutMs ?? DOWNLOAD_TIMEOUT_MS));
      } catch {
        return refusal("vendor_unavailable");
      }
      if (bytes === null) return refusal("photos_required"); // Spec 2 W4 final (M-12): the object is gone, never an outage
      const target = bytes;
      try {
        same = await vendor(deps, () => s.providers.faceMatch.compare(frame, target, i));
      } catch {
        return refusal("vendor_unavailable");
      } finally {
        bytes.fill(0);
      }
    }
  } finally {
    frame.fill(0);
  }
  if (!same) {
    if (!(await finish(deps, session, "failed", "identity_failed"))) return refusal("busy");
    return { ok: true, outcome: "identity_failed" };
  }
  const trusted = await call(deps, "trust_dating_device", {
    p_user: caller.userId, p_device_hash: caller.deviceHash, p_session: session, // Spec 2 W4 final (M-3)
  });
  if (trusted?.ok !== true) return refusal(trusted?.reason ?? "busy");
  if (!(await finish(deps, session, "passed", "verified"))) return refusal("busy");
  return { ok: true, outcome: "verified" };
}

const ACTIONS: Record<string, (c: Caller, b: Record<string, unknown>, d: VerificationDeps) => Promise<Answer>> = {
  start, complete, start_id: startId, complete_id: completeId, human_start: humanStart, submit_human: submitHuman,
  reverify_start: reverifyStart, reverify_complete: reverifyComplete, // Spec 2 W4b
};

export async function handleVerification(body: unknown, caller: Caller, deps: VerificationDeps): Promise<Answer> {
  const b = body !== null && typeof body === "object" ? body as Record<string, unknown> : {};
  // Task 2 fix round 1 (M-1): own keys only (never "constructor" or "toString").
  const action = typeof b.action === "string" && Object.hasOwn(ACTIONS, b.action) ? ACTIONS[b.action] : undefined;
  if (action === undefined) return refusal("invalid");
  const run: VerificationDeps = { ...deps, started: clock(deps) };
  let answer: Answer;
  try {
    answer = await action(caller, b, run);
  } catch {
    answer = refusal("busy");
  }
  if (answer.ok === false && answer.reason === "busy") await count(run, "dating.verify.busy");
  return answer;
}

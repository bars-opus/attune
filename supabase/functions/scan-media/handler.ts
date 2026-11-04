// supabase/functions/scan-media/handler.ts
//
// Spec 1 W7b (§4.5, §4.6): every minute, the scan-media cron claims due
// jobs (claim_media_scan_jobs: nothing while csam_hash_matching is off),
// downloads each object with the service role, asks the matcher, and
// answers complete_media_scan with the claim's lease (B4 fix I-1).
//
// What an object is comes from its bytes, never from the mime the client
// declared (B4 I-3; sniff.ts), read from its first 4 KiB only (objects.ts,
// B6 fix I-2): a video is skipped (no adapter hashes video in W7b, plan
// P-19; its poster image is its own object and is scanned) and anything
// else is skipped with its reason, without reading them whole. An image
// over MAX_IMAGE_BYTES is unavailable (too_large) without being read; any
// other image is read whole (unless the head already was the whole of it),
// sniffed again, and sent to the matcher with its sniffed type. Nothing is
// ever clear without the matcher's clear, and a matcher never skips (that
// is the sniff's decision, B6 M-3). A match goes through the one match path
// (_shared/csam_match_path.ts: quarantine first, then the record). An
// object gone before its scan is skipped. A read or matcher failure, or a
// timeout, is unavailable (the database backs off, and after 24 hours a
// person is told).
//
// Time: one job is claimed at a time, at most BATCH a run, and none after
// RUN_BUDGET_MS, so work the run can't reach stays unclaimed for the next
// minute. Every step of a job is bounded and aborted when its time is up
// (the claim and completion calls by index.ts's timed fetch, the reads by
// objects.ts, the matcher by its own timeout and an outer bound, the copy
// by Task 7's budget), so the last job ends by RUN_BUDGET_MS +
// JOB_WORST_CASE_MS (125.75 s) and the immediate post by ALERT_DEADLINE_MS +
// ALERT_WORST_CASE_MS (140 s), 10 s inside the 150 s edge limit. Both are
// measured from [startedAt], which index.ts takes before its environment
// read, so that read counts too (B6 N-2). A job claimed but never
// answered (the run died) is safe: its 10-minute lease lapses and it is
// claimed again with a fresh lease; a late answer under the old lease
// changes nothing, and after 24 hours it is failed and escalated.
//
// When the run recorded a match or an unavailable answer, the safety
// webhook is told straight away through identity-health-alert's sendAlerts
// (counts and times only), unless the run is past ALERT_DEADLINE_MS, when
// it is left to identity-health-alert's 15-minute run (the backstop for
// every post). Nothing here logs; index.ts logs the counts only.
import {
  type AttuneEnvironment,
  type CsamMatcher,
  MATCHER_MAX_TIMEOUT_MS,
  type MatchResult,
  PHOTODNA_MAX_BYTES,
} from "../_shared/csam_matcher.ts";
import {
  quarantineAndRecord,
  quarantineBudget,
  type StorageLike,
  storageQuarantine,
  queuedRecorder,
} from "../_shared/csam_match_path.ts";
import {
  type AlertClient,
  type AlertResult,
  CSAM_MATCH_ESCALATIONS,
  type PostFn,
  SCAN_FAILED_ESCALATIONS,
  sendAlerts,
} from "../identity-health-alert/handler.ts";
import type { HeadResult, ObjectReader, ReadFailure, ReadResult } from "./objects.ts";
import { sniffMedia } from "./sniff.ts";

type RpcResult = PromiseLike<{ data: unknown; error: { message: string } | null }>;

export interface ScanClient {
  rpc(fn: string, args?: Record<string, unknown>): RpcResult;
  /// Quarantine uploads only (storageQuarantine).
  storage: StorageLike;
  /// Every read of a scanned object (objects.ts).
  objects: ObjectReader;
}

export interface ScanJob {
  id: number;
  bucket: string;
  object_name: string;
  owner_user_id: string | null;
  /// As the client declared it: recorded, never trusted (B4 I-3).
  mime: string | null;
  attempts: number;
  /// The claim's lease; every answer carries it (B4 fix I-1).
  lease_id: string | null;
}

export interface ScanResult {
  claimed: number;
  clear: number;
  match: number;
  unquarantined: number;
  unavailable: number;
  skipped: number;
  unanswered: number;
  /// "deferred": the run was too late for the immediate post; the
  /// 15-minute identity-health-alert run posts it.
  alerts: AlertResult | "not_needed" | "deferred";
}

/// At most this many jobs a run (each claimed on its own): with a run
/// starting every minute, the scan ceiling is about 20 a minute (B6 M-10;
/// media_scan_oldest_pending_minutes shows a backlog).
export const BATCH = 20;
/// No job is claimed after this much of the run.
export const RUN_BUDGET_MS = 50_000;
/// Every database and Storage call through index.ts's client (timedFetch):
/// claim, completion, quarantine upload, the alert reads and marks.
export const RPC_TIMEOUT_MS = 10_000;
/// The 4 KiB head read.
export const HEAD_TIMEOUT_MS = 5_000;
/// The whole read of an image, at most MAX_IMAGE_BYTES.
export const DOWNLOAD_TIMEOUT_MS = 10_000;
/// The largest image read and sent (PF-L9: the owner confirms it).
export const MAX_IMAGE_BYTES = PHOTODNA_MAX_BYTES;
/// The adapters bound themselves (MATCHER_MAX_TIMEOUT_MS); this outer bound,
/// a second later, holds for any matcher.
export const MATCHER_BOUND_MS = MATCHER_MAX_TIMEOUT_MS + 1_000;
/// Claim, head, read, matcher, every quarantine try timing out (24.75 s),
/// completion.
export const JOB_WORST_CASE_MS = RPC_TIMEOUT_MS + HEAD_TIMEOUT_MS + DOWNLOAD_TIMEOUT_MS + MATCHER_BOUND_MS +
  quarantineBudget({}).worstCaseMs + RPC_TIMEOUT_MS;
/// index.ts's webhook post timeout (identity-health-alert's backstop run
/// has its own 10 s).
export const ALERT_POST_TIMEOUT_MS = 5_000;
/// Two sources, each read, posted and marked.
export const ALERT_WORST_CASE_MS = 2 * (RPC_TIMEOUT_MS + ALERT_POST_TIMEOUT_MS + RPC_TIMEOUT_MS);
/// Supabase Edge Functions' limit (150 s wall clock on the free plan, the
/// background work of waitUntil included; the paid plans allow more).
export const EDGE_WALL_CLOCK_MS = 150_000;
/// Past this, the immediate post is left to the backstop, so the run
/// still ends 10 s inside the edge limit.
export const ALERT_DEADLINE_MS = EDGE_WALL_CLOCK_MS - ALERT_WORST_CASE_MS - 10_000;

const MAX_BATCH = 50;
/// What a matcher may answer here. `skipped` is not one: what is skipped is
/// decided by the sniff (B6 M-3).
const ANSWERS: ReadonlySet<string> = new Set(["clear", "match", "unavailable"]);

function bounded(value: number | undefined, fallback: number, min: number, max: number): number {
  const v = typeof value === "number" && Number.isFinite(value) ? Math.trunc(value) : fallback;
  return Math.min(Math.max(v, min), max);
}

export function readJobs(data: unknown): ScanJob[] {
  if (!Array.isArray(data)) return [];
  return data.flatMap((row) => {
    const r = row as Record<string, unknown>;
    return typeof r?.id === "number" && typeof r.bucket === "string" && typeof r.object_name === "string"
      ? [{
        id: r.id,
        bucket: r.bucket,
        object_name: r.object_name,
        owner_user_id: typeof r.owner_user_id === "string" ? r.owner_user_id : null,
        mime: typeof r.mime === "string" ? r.mime : null,
        attempts: typeof r.attempts === "number" ? r.attempts : 0,
        lease_id: typeof r.lease_id === "string" ? r.lease_id : null,
      }]
      : [];
  });
}

/// get_attune_environment(): development only when it reads exactly
/// 'development'; an error, a throw or anything else is production (PF-H1,
/// B6 M-1).
export async function readEnvironment(client: { rpc(fn: string): RpcResult }): Promise<AttuneEnvironment> {
  try {
    const { data, error } = await client.rpc("get_attune_environment");
    return !error && data === "development" ? "development" : "production";
  } catch {
    return "production";
  }
}

/// What a failed run logs: our own code, or the error's class, never its
/// message (it could carry a path).
export function errorClass(error: unknown): string {
  if (!(error instanceof Error)) return typeof error;
  return error.message === "claim_failed" ? "claim_failed" : error.name;
}

/// [work], or [late] when it hasn't answered within [ms]. A rejection is
/// passed on. The timer is always cleared.
async function within<T>(work: () => PromiseLike<T>, ms: number, late: T): Promise<T> {
  let timer: ReturnType<typeof setTimeout> | undefined;
  const timeout = new Promise<T>((resolve) => {
    timer = setTimeout(() => resolve(late), ms);
  });
  try {
    return await Promise.race([Promise.resolve().then(work), timeout]);
  } finally {
    clearTimeout(timer);
  }
}

const READ_TIMED_OUT: ReadFailure = { ok: false, outcome: "unavailable", reason: "download_timeout" };
const READ_FAILED: ReadFailure = { ok: false, outcome: "unavailable", reason: "download_failed" };

/// A reader call, bounded here too (objects.ts aborts its own requests; this
/// holds for any reader). A throw is a failed read.
async function boundedRead<T extends HeadResult | ReadResult>(work: () => PromiseLike<T>, ms: number): Promise<T | ReadFailure> {
  try {
    return await within<T | ReadFailure>(work, ms, READ_TIMED_OUT);
  } catch {
    return READ_FAILED;
  }
}

/// The matcher's answer; a throw, no answer in time, or an answer it can't
/// name is unavailable, never clear.
async function ask(matcher: CsamMatcher, bytes: Uint8Array, mime: string, ms: number): Promise<MatchResult> {
  try {
    const answer = await within<MatchResult | null>(() => matcher.match(bytes, mime), ms, null);
    if (answer === null) return { outcome: "unavailable", vendor: matcher.name, vendorRef: "matcher_timeout" };
    if (!ANSWERS.has(String(answer?.outcome))) {
      return { outcome: "unavailable", vendor: matcher.name, vendorRef: "matcher_unreadable" };
    }
    return answer;
  } catch {
    return { outcome: "unavailable", vendor: matcher.name, vendorRef: "matcher_error" };
  }
}

export async function scanMedia(
  client: ScanClient,
  matcher: CsamMatcher,
  alert: { webhook: string | undefined; post: PostFn },
  options: {
    now?: () => number;
    budgetMs?: number;
    batch?: number;
    headTimeoutMs?: number;
    downloadTimeoutMs?: number;
    matcherTimeoutMs?: number;
    maxBytes?: number;
    /// When the run began (index.ts: before the environment read, B6 N-2);
    /// never later than now.
    startedAt?: number;
  } = {},
): Promise<ScanResult> {
  const now = options.now ?? Date.now;
  // Callers may only narrow the bounds, never widen them past the edge limit.
  const budgetMs = bounded(options.budgetMs, RUN_BUDGET_MS, 0, RUN_BUDGET_MS);
  const limit = bounded(options.batch, BATCH, 1, MAX_BATCH);
  const headMs = bounded(options.headTimeoutMs, HEAD_TIMEOUT_MS, 1, HEAD_TIMEOUT_MS);
  const downloadMs = bounded(options.downloadTimeoutMs, DOWNLOAD_TIMEOUT_MS, 1, DOWNLOAD_TIMEOUT_MS);
  const maxBytes = bounded(options.maxBytes, MAX_IMAGE_BYTES, 1, MAX_IMAGE_BYTES);
  const matcherMs = bounded(options.matcherTimeoutMs, MATCHER_BOUND_MS, 1, MATCHER_BOUND_MS);
  const clock = now();
  const started = typeof options.startedAt === "number" && Number.isFinite(options.startedAt)
    ? Math.min(options.startedAt, clock)
    : clock;
  const result: ScanResult = {
    claimed: 0, clear: 0, match: 0, unquarantined: 0, unavailable: 0, skipped: 0, unanswered: 0, alerts: "not_needed",
  };

  const complete = async (job: ScanJob, outcome: "clear" | "unavailable" | "skipped", vendor: string, vendorRef: string | null) => {
    try {
      const { error } = await client.rpc("complete_media_scan", {
        p_job_id: job.id,
        p_result: outcome,
        p_vendor: vendor,
        p_vendor_ref: vendorRef,
        p_lease_id: job.lease_id,
      });
      if (!error) {
        result[outcome]++;
        return;
      }
    } catch {
      // counted below
    }
    // Unanswered: the 10-minute lease lapses and the job is claimed again.
    result.unanswered++;
  };

  const scanOne = async (job: ScanJob) => {
    const head = await boundedRead(() => client.objects.head(job.bucket, job.object_name), headMs);
    if (!head.ok) return await complete(job, head.outcome, matcher.name, head.reason);
    const kind = sniffMedia(head.bytes);
    if (kind.kind === "other") return await complete(job, "skipped", matcher.name, kind.reason);
    if (kind.kind === "video" && !matcher.supportsVideo) return await complete(job, "skipped", matcher.name, "video_not_hashed");
    if (head.size !== null && head.size > maxBytes) return await complete(job, "unavailable", matcher.name, "too_large");

    // The head is used as it is only when the reader knows it is the whole
    // object; an unknown size is read whole (B6 N-1), never hashed on 4 KiB.
    let bytes = head.bytes;
    if (head.whole !== true) {
      const full = await boundedRead(() => client.objects.read(job.bucket, job.object_name, maxBytes), downloadMs);
      if (!full.ok) return await complete(job, full.outcome, matcher.name, full.reason);
      bytes = full.bytes;
    }
    // Written over between the two reads: the new bytes are queued again.
    const again = sniffMedia(bytes);
    if (again.kind === "other" || again.kind !== kind.kind) {
      return await complete(job, "unavailable", matcher.name, "changed_during_scan");
    }
    const mime = again.mime;

    const answer = await ask(matcher, bytes, mime, matcherMs);
    if (answer.outcome === "match") {
      const matched = await quarantineAndRecord({
        bucket: job.bucket,
        objectName: job.object_name,
        bytes,
        mime,
        store: storageQuarantine(client.storage),
        record: queuedRecorder(client, job.id, answer.vendor, answer.vendorRef, job.lease_id),
      });
      if (!matched.recorded) result.unanswered++;
      else if (matched.quarantined) result.match++;
      else result.unquarantined++;
      return;
    }
    await complete(job, answer.outcome as "clear" | "unavailable", answer.vendor, answer.vendorRef);
  };

  while (result.claimed < limit && now() - started < budgetMs) {
    let claim: { data: unknown; error: { message: string } | null };
    try {
      claim = await client.rpc("claim_media_scan_jobs", { p_limit: 1 });
    } catch {
      claim = { data: null, error: { message: "claim_threw" } };
    }
    if (claim.error) {
      if (result.claimed === 0) throw new Error("claim_failed");
      break;
    }
    const jobs = readJobs(claim.data);
    if (jobs.length === 0) break;
    for (const job of jobs) {
      result.claimed++;
      try {
        await scanOne(job);
      } catch {
        result.unanswered++;
      }
    }
  }

  if (result.match + result.unquarantined + result.unavailable > 0) {
    if (now() - started > ALERT_DEADLINE_MS) {
      result.alerts = "deferred";
      return result;
    }
    try {
      result.alerts = await sendAlerts(
        client as unknown as AlertClient,
        alert.webhook,
        alert.post,
        [CSAM_MATCH_ESCALATIONS, SCAN_FAILED_ESCALATIONS],
      );
    } catch {
      // The 15-minute identity-health-alert run is the backstop.
      result.alerts = { [CSAM_MATCH_ESCALATIONS.name]: "read_failed", [SCAN_FAILED_ESCALATIONS.name]: "read_failed" };
    }
  }
  return result;
}

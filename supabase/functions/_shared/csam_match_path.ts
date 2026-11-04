// supabase/functions/_shared/csam_match_path.ts
//
// Spec 1 W7b (§4.5, review I-10): THE quarantine-and-record path, used by
// scan-media (a queued job) and by Spec 2's process-dating-photo (an
// inline match). The bytes go to the private safety-quarantine bucket
// FIRST; only then is the match recorded (complete_media_scan or
// record_inline_csam_match -> private.handle_csam_match: one escalation,
// one safety_review hold, the original queued for deletion). If the copy
// fails after [tries] attempts the match is still recorded at once, as
// unquarantined: the account is held and a person is told, and the
// original is NOT deleted, because it is then the only copy of the
// evidence (plan P-18). Nothing here tells the uploader or anyone else,
// and nothing here logs.
//
// The copy is the exact bytes the matcher scanned, from the caller's
// buffer, never a copy of the object by path: the object may have been
// overwritten since it was downloaded (B4 N2). Each attempt writes to a
// path no earlier match used, <bucket>/<objectName>/<match id>, and only a
// fresh write counts: an object already at a path is never this match's
// evidence, so a second match after a closed escalation (PF-M2) keeps its
// own new bytes beside the first. Each try is bounded in time (B5 I-2): a
// hung upload is a failed try, so a storage outage still records the
// match, unquarantined, and the account is still held. The record carries
// the exact path written, stored on the escalation (quarantine_path, NULL
// when unquarantined; B5 I-4). The store writes only to safety-quarantine
// (B5 M5).
type RpcResult = PromiseLike<{ data: unknown; error: { message: string } | null }>;

export interface MatchRpcClient {
  rpc(fn: string, args?: Record<string, unknown>): RpcResult;
}

export type QuarantineOutcome = "stored" | "exists" | "failed";

export interface QuarantineStore {
  put(path: string, bytes: Uint8Array, mime: string): Promise<QuarantineOutcome>;
}

/// What the match is recorded as: [quarantined] says whether the copy is in
/// safety-quarantine, and [path] is where (null when it is not).
export interface QuarantineCopy {
  quarantined: boolean;
  path: string | null;
}

export type MatchRecorder = (copy: QuarantineCopy) => Promise<{ escalationId: number | null; error: string | null }>;

export const QUARANTINE_BUCKET = "safety-quarantine";

const DEFAULT_TRIES = 3;
const MAX_TRIES = 5;
const DEFAULT_RETRY_DELAY_MS = 250;
const MAX_RETRY_DELAY_MS = 1_000;
/// Per try. The default leaves room in scan-media's run budget beside the
/// matcher's own 15 s (Task 8 sizes the run).
const DEFAULT_COPY_TIMEOUT_MS = 8_000;
const MAX_COPY_TIMEOUT_MS = 10_000;

export interface QuarantineBudget {
  tries: number;
  copyTimeoutMs: number;
  retryDelayMs: number;
  /// Every try timing out, with every wait: the longest the copy can take
  /// before the match is recorded.
  worstCaseMs: number;
}

function bounded(value: number | undefined, fallback: number, min: number, max: number): number {
  const v = typeof value === "number" && Number.isFinite(value) ? Math.trunc(value) : fallback;
  return Math.min(Math.max(v, min), max);
}

/// The copy's bounds: tries 1..5 (default 3), each up to 1..10 000 ms
/// (default 8 000), try n+1 after n x 0..1 000 ms (default 250).
export function quarantineBudget(input: { tries?: number; copyTimeoutMs?: number; retryDelayMs?: number }): QuarantineBudget {
  const tries = bounded(input.tries, DEFAULT_TRIES, 1, MAX_TRIES);
  const copyTimeoutMs = bounded(input.copyTimeoutMs, DEFAULT_COPY_TIMEOUT_MS, 1, MAX_COPY_TIMEOUT_MS);
  const retryDelayMs = bounded(input.retryDelayMs, DEFAULT_RETRY_DELAY_MS, 0, MAX_RETRY_DELAY_MS);
  const waits = (retryDelayMs * (tries - 1) * tries) / 2;
  return { tries, copyTimeoutMs, retryDelayMs, worstCaseMs: tries * copyTimeoutMs + waits };
}

/// The original's bucket and name, kept whole, so a reviewer finds both,
/// then this match's own id: every copy of one object sits under
/// <bucket>/<objectName>/, one per match, oldest first.
export function quarantinePath(bucket: string, objectName: string, matchId: string): string {
  return `${bucket}/${objectName}/${matchId}`;
}

/// A new id for one quarantine write: the UTC time (so the copies sort by
/// time and line up with the escalation's created_at) and a random UUID.
/// Letters, digits and hyphens only. Never a hash of the image.
export function newMatchId(now: Date = new Date()): string {
  return `${now.toISOString().replace(/[-:.]/g, "")}-${crypto.randomUUID()}`;
}

/// Storage's upload, never overwriting. A copy already at the path is
/// reported as `exists`, which quarantineAndRecord never counts as stored.
/// Storage (client.storage): the store picks the bucket itself, so evidence
/// can't be written into a user-readable source bucket (B5 M5).
export interface StorageLike {
  from(bucketId: string): StorageBucketLike;
}

export interface StorageBucketLike {
  upload(
    path: string,
    body: Uint8Array,
    options: { contentType: string; upsert: boolean },
  ): PromiseLike<{ error: { message: string; statusCode?: string | number } | null }>;
}

export function storageQuarantine(storage: StorageLike): QuarantineStore {
  return {
    async put(path, bytes, mime) {
      try {
        const { error } = await storage.from(QUARANTINE_BUCKET).upload(path, bytes, { contentType: mime || "application/octet-stream", upsert: false });
        if (!error) return "stored";
        const duplicate = String(error.statusCode ?? "") === "409" || /already exists|duplicate/i.test(error.message);
        return duplicate ? "exists" : "failed";
      } catch {
        return "failed";
      }
    },
  };
}

/// scan-media's recorder. The claim's lease goes with the match; the SQL
/// takes a match without it (plan P-20), but every answer carries it.
export function queuedRecorder(
  client: MatchRpcClient,
  jobId: number,
  vendor: string,
  vendorRef: string | null,
  leaseId: string | null,
): MatchRecorder {
  return async ({ quarantined, path }) => {
    const { error } = await client.rpc("complete_media_scan", {
      p_job_id: jobId,
      p_result: quarantined ? "match" : "match_unquarantined",
      p_vendor: vendor,
      p_vendor_ref: vendorRef,
      p_lease_id: leaseId,
      p_quarantine_path: quarantined ? path : null,
    });
    return { escalationId: null, error: error ? "complete_failed" : null };
  };
}

export function inlineRecorder(
  client: MatchRpcClient,
  object: { bucket: string; objectName: string; ownerUserId: string | null; vendor: string; vendorRef: string | null },
): MatchRecorder {
  return async ({ quarantined, path }) => {
    const { data, error } = await client.rpc("record_inline_csam_match", {
      p_bucket: object.bucket,
      p_object_name: object.objectName,
      p_owner: object.ownerUserId,
      p_vendor: object.vendor,
      p_vendor_ref: object.vendorRef,
      p_quarantined: quarantined,
      p_quarantine_path: quarantined ? path : null,
    });
    if (error) return { escalationId: null, error: "record_failed" };
    return { escalationId: typeof data === "number" ? data : Number(data) || null, error: null };
  };
}

export interface QuarantineAndRecordResult {
  quarantined: boolean;
  recorded: boolean;
  escalationId: number | null;
  /// Where this match's copy is in safety-quarantine, or null when the copy
  /// failed. It names the object (and so maybe a person's id): never log it.
  quarantinePath: string | null;
}

export async function quarantineAndRecord(input: {
  bucket: string;
  objectName: string;
  /// The exact bytes the matcher scanned.
  bytes: Uint8Array;
  mime: string;
  store: QuarantineStore;
  record: MatchRecorder;
  /// Attempts at the copy before recording unquarantined (quarantineBudget).
  tries?: number;
  /// The most one try may take; then it is a failed try.
  copyTimeoutMs?: number;
  /// Tests only: the id of each attempt's path (default newMatchId).
  matchId?: () => string;
  /// Wait before try n+1 is n times this.
  retryDelayMs?: number;
}): Promise<QuarantineAndRecordResult> {
  const budget = quarantineBudget(input);
  const nextId = input.matchId ?? (() => newMatchId());
  let stored: string | null = null;
  for (let i = 0; i < budget.tries && stored === null; i++) {
    if (i > 0 && budget.retryDelayMs > 0) await new Promise((resolve) => setTimeout(resolve, budget.retryDelayMs * i));
    const path = quarantinePath(input.bucket, input.objectName, nextId());
    const outcome = await putWithin(input.store, path, input.bytes, input.mime, budget.copyTimeoutMs);
    // Only a fresh write is this match's evidence (PF-M2).
    if (outcome === "stored") stored = path;
  }
  const quarantined = stored !== null;
  let recorded: { escalationId: number | null; error: string | null };
  try {
    recorded = await input.record({ quarantined, path: stored });
  } catch {
    recorded = { escalationId: null, error: "record_threw" };
  }
  return { quarantined, recorded: recorded.error === null, escalationId: recorded.escalationId, quarantinePath: stored };
}

/// One try, bounded: a throw, a rejection or no answer within [ms] is
/// `failed`. A late answer is ignored (its copy, if any, is an orphan at a
/// path nothing records).
async function putWithin(
  store: QuarantineStore,
  path: string,
  bytes: Uint8Array,
  mime: string,
  ms: number,
): Promise<QuarantineOutcome> {
  let timer: ReturnType<typeof setTimeout> | undefined;
  const late = new Promise<QuarantineOutcome>((resolve) => {
    timer = setTimeout(() => resolve("failed"), ms);
  });
  const attempt = Promise.resolve()
    .then(() => store.put(path, bytes, mime))
    .catch((): QuarantineOutcome => "failed");
  try {
    return await Promise.race([attempt, late]);
  } finally {
    clearTimeout(timer);
  }
}

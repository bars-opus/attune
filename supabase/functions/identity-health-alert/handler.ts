// supabase/functions/identity-health-alert/handler.ts
//
// Spec 1 W6a (§4.4 review S-8, §4.5): every access-token hook fail-open is
// an incident (a held account may have had a token). Every 15 minutes the
// cron runs this: identity_alerts_due() lists the fail-opens not posted
// yet; one message with their count and time span goes to
// SAFETY_ALERT_WEBHOOK (a destination the owner configures); only after
// the webhook accepted it are they marked sent, so a failed post is tried
// again next run. The message carries counts and times only: no user, no
// claims, no sqlstate.
//
// Batch 3: two more sources follow the same shape (stuck fresh-start parks,
// preflight F4; parked accounts kept past 180 days for an open review,
// batch 2 M-4). Each source is read, posted and marked on its own, so one
// failing never stops or marks another. With SAFETY_ALERT_WEBHOOK unset
// nothing is posted or marked: everything stays due.
type RpcResult = PromiseLike<{ data: unknown; error: { message: string } | null }>;

export interface AlertClient {
  rpc(fn: string, args?: Record<string, unknown>): RpcResult;
}

export type PostFn = (url: string, body: string) => Promise<{ ok: boolean; status: number }>;

/// One kind of alert: where its due rows come from, how they are marked,
/// and the line that says what happened. W6c adds child-safety reports.
export interface AlertSource {
  name: string;
  due: string;
  mark: string;
  line(count: number, firstAt: string, lastAt: string): string;
}

export const HOOK_FAIL_OPENS: AlertSource = {
  name: "hook_fail_open",
  due: "identity_alerts_due",
  mark: "mark_identity_alerts_sent",
  line: (count, firstAt, lastAt) =>
    `Attune: the access-token hook failed open ${count} time(s) between ${firstAt} and ${lastAt}. ` +
    "A held account may have received a token: treat this as an incident.",
};

/// Preflight F4: a fresh start whose park never finished leaves the real
/// number behind the old account's recovery hold, so the number's new owner
/// sees H1. Alerted once per hold (fresh_start_park_alerts_due); support
/// finishes the park.
export const FRESH_START_UNPARKED: AlertSource = {
  name: "fresh_start_unparked",
  due: "fresh_start_park_alerts_due",
  mark: "mark_fresh_start_park_alerts_sent",
  line: (count, firstAt) =>
    `Attune: ${count} fresh start(s) did not finish moving the old account's number, the first held since ${firstAt}. ` +
    "The number's new owner is stopped at sign-in: support must finish the park " +
    "(move the Auth number to +999, then mark_fresh_start_parked).",
};

/// Batch 2 review M-4 ruling: a parked account past its 180 days is kept,
/// not purged, while an age or safety review is open. Alerted once per hold
/// (parked_kept_for_review_alerts_due) so support resolves the review.
export const PARKED_KEPT_FOR_REVIEW: AlertSource = {
  name: "parked_kept_for_review",
  due: "parked_kept_for_review_alerts_due",
  mark: "mark_parked_kept_for_review_alerts_sent",
  line: (count, firstAt) =>
    `Attune: ${count} parked account(s) are past their 180 days but kept because an age or safety review is open, ` +
    `the first due since ${firstAt}. Support must resolve the review; the purge then deletes them.`,
};

/// Batch 3 fix M-3: a parked account whose purge failed in 3 runs is moved
/// to the back of the purge list (it can't block the rest) and alerted once
/// per hold (recovery_purge_stuck_alerts_due) so support finds the cause.
export const RECOVERY_PURGE_STUCK: AlertSource = {
  name: "recovery_purge_stuck",
  due: "recovery_purge_stuck_alerts_due",
  mark: "mark_recovery_purge_stuck_alerts_sent",
  line: (count, firstAt) =>
    `Attune: ${count} parked account(s) failed to purge in 3 or more runs, the first due since ${firstAt}. ` +
    "They are retried after the rest: support must find the cause (account_deletion_requests, source recovery_purge).",
};

/// Spec 1 W6c (plan P-24): a new "Report a concern about a child" reaches
/// a person within 15 minutes. The count and the time only: the words stay
/// in child_safety_reports, read by the named child-safety contact.
export const CHILD_SAFETY_REPORTS: AlertSource = {
  name: "child_safety_report",
  due: "child_safety_alerts_due",
  mark: "mark_child_safety_alerts_sent",
  line: (count, firstAt) =>
    `Attune: ${count} new report(s) of a concern about a child, the first at ${firstAt}. ` +
    "A person must read them today (child_safety_reports).",
};

/// Spec 1 W7b (plan P-21): an image matched a known CSAM hash. The named
/// child-safety contact reviews it before anything is reported; the
/// uploader's account is already held. A count and a time only. scan-media
/// posts this straight after its run; this 15-minute run is the backstop.
/// PF-L4: a match whose copy failed (quarantined = false) is still in its
/// own bucket, kept there as the only evidence.
export const CSAM_MATCH_ESCALATIONS: AlertSource = {
  name: "csam_match",
  due: "csam_escalations_due",
  mark: "mark_safety_escalations_alerted",
  line: (count, firstAt) =>
    `Attune: ${count} image(s) matched a known child sexual abuse hash, the first at ${firstAt}. ` +
    "The uploader's account is on hold and the image is in safety-quarantine (or still in place where quarantined is false). " +
    "The named child-safety contact must review them now (public.safety_escalations, status open); " +
    "nothing has been reported to anyone.",
};

/// Spec 1 W7b: uploads not scanned within 24 hours (the matcher was down,
/// unconfigured, or the stub was refused in production).
export const SCAN_FAILED_ESCALATIONS: AlertSource = {
  name: "scan_failed",
  due: "scan_failed_escalations_due",
  mark: "mark_safety_escalations_alerted",
  line: (count, firstAt) =>
    `Attune: ${count} upload(s) could not be scanned for CSAM within 24 hours, the first at ${firstAt}. ` +
    "Check CSAM_MATCHER and its keys and scan-media's logs, then review public.safety_escalations (kind scan_failed).",
};

/// W7 final review M-1: uploads the scan queue could not take (one object,
/// or a sweep or reconcile whose whole read of storage.objects failed, so
/// nothing was queued). Never silent: one count and the times, once.
export const MEDIA_SCAN_ENQUEUE_FAILED: AlertSource = {
  name: "media_scan_enqueue_failed",
  due: "media_scan_enqueue_alerts_due",
  mark: "mark_media_scan_enqueue_alerted",
  line: (count, firstAt, lastAt) =>
    `Attune: the CSAM scan queue failed to take uploads ${count} time(s) between ${firstAt} and ${lastAt}. ` +
    "Uploads in that window may not be scanned: check get_identity_health (media_scan_enqueue_*) and the database logs; " +
    "the daily reconcile queues the last 25 hours again.",
};

export const ALERT_SOURCES: AlertSource[] = [
  HOOK_FAIL_OPENS,
  FRESH_START_UNPARKED,
  PARKED_KEPT_FOR_REVIEW,
  RECOVERY_PURGE_STUCK,
  // W7b's three before W6c's, so W6c's test still sees its mark last.
  CSAM_MATCH_ESCALATIONS,
  SCAN_FAILED_ESCALATIONS,
  MEDIA_SCAN_ENQUEUE_FAILED,
  CHILD_SAFETY_REPORTS,
];

export interface AlertResult {
  [source: string]: "none" | "sent" | "post_failed" | "read_failed" | "mark_failed" | "not_configured";
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

interface Due {
  /// bigint ids (hook fail-opens) or uuids (W6c's child-safety reports).
  ids: (number | string)[];
  count: number;
  firstAt: string;
  lastAt: string;
}

function readDue(data: unknown): Due | null {
  if (data === null || typeof data !== "object") return null;
  const row = data as Record<string, unknown>;
  const ids = Array.isArray(row.ids)
    ? row.ids.filter((x): x is number | string => Number.isInteger(x) || (typeof x === "string" && UUID.test(x)))
    : [];
  return {
    ids,
    count: typeof row.count === "number" ? row.count : ids.length,
    firstAt: String(row.first_at ?? ""),
    lastAt: String(row.last_at ?? ""),
  };
}

export async function sendAlerts(
  client: AlertClient,
  webhook: string | undefined,
  post: PostFn,
  sources: AlertSource[] = ALERT_SOURCES,
): Promise<AlertResult> {
  const result: AlertResult = {};
  for (const source of sources) {
    const { data, error } = await client.rpc(source.due);
    const due = error ? null : readDue(data);
    if (!due) {
      result[source.name] = "read_failed";
      continue;
    }
    if (due.ids.length === 0) {
      result[source.name] = "none";
      continue;
    }
    if (!webhook) {
      // Never marked: they stay due until a destination exists.
      result[source.name] = "not_configured";
      continue;
    }
    let sent = false;
    try {
      const response = await post(webhook, JSON.stringify({ text: source.line(due.count, due.firstAt, due.lastAt) }));
      sent = response.ok;
    } catch {
      sent = false;
    }
    if (!sent) {
      result[source.name] = "post_failed";
      continue;
    }
    const { error: markError } = await client.rpc(source.mark, { p_ids: due.ids });
    result[source.name] = markError ? "mark_failed" : "sent";
  }
  return result;
}

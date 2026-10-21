// supabase/functions/process-scheduled-notifications/deliver.ts
//
// Chat review #18: one queued row → the recipient's registered devices.
// Pure orchestration over injected pieces so it is testable without
// OneSignal or Postgres; index.ts supplies the real ones.

export type DeliverDeps = {
  loadSubscriptions: (userId: string) => Promise<string[]>;
  send: (input: {
    subscriptionIds: string[];
    title: string;
    body: string;
    data: Record<string, unknown>;
    idempotencyKey: string;
  }) => Promise<{ id: string | null; invalidSubscriptionIds: string[] }>;
  deactivate: (ids: string[]) => Promise<void>;
};

export type DeliverOutcome = { status: "sent" | "skipped"; lastError: string | null };

export async function deliverPush(
  job: { id: string; user_id: string },
  copy: { title: string; body: string; data: Record<string, unknown> },
  deps: DeliverDeps,
): Promise<DeliverOutcome> {
  const subscriptionIds = await deps.loadSubscriptions(job.user_id);
  // Nobody registered (signed out everywhere, or an app build before #18):
  // skipped once, not retried -- a retry would find the same nothing.
  if (subscriptionIds.length === 0) return { status: "skipped", lastError: "no_push_subscription" };
  const idempotencyKey = await pushIdempotencyKey(job.id, subscriptionIds);
  const result = await deps.send({ subscriptionIds, ...copy, idempotencyKey });
  if (result.invalidSubscriptionIds.length > 0) await deps.deactivate(result.invalidSubscriptionIds);
  if (result.id === null) {
    // Nothing went out. Every targeted device gone → skipped once. Only
    // some gone (a 400 naming part of the list) → the rest may be live:
    // throw into the worker's retry path, which re-reads the now-pruned
    // device list and reaches them.
    const gone = new Set(result.invalidSubscriptionIds.map((id) => id.toLowerCase()));
    if (subscriptionIds.every((id) => gone.has(id.toLowerCase()))) {
      return { status: "skipped", lastError: "no_subscribed_device" };
    }
    throw new Error("onesignal_400_pruned");
  }
  return { status: "sent", lastError: null };
}

/// OneSignal dedupes on a UUID idempotency key and may remember a 400 under
/// it, so the key covers the row AND the devices it targets: a retry after a
/// lost response (same targets) dedupes, while the onesignal_400_pruned
/// retry (fewer targets) is a new request. SHA-256 over the row id and the
/// sorted, lower-cased, de-duplicated targets (JSON-encoded, so no id can
/// forge a separator), first 16 bytes shaped as a version-5/RFC 4122 UUID.
export async function pushIdempotencyKey(jobId: string, subscriptionIds: string[]): Promise<string> {
  const targets = [...new Set(subscriptionIds.map((id) => id.toLowerCase()))].sort();
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(JSON.stringify([jobId, targets])),
  );
  const b = new Uint8Array(digest).slice(0, 16);
  b[6] = (b[6] & 0x0f) | 0x50;
  b[8] = (b[8] & 0x3f) | 0x80;
  const hex = [...b].map((x) => x.toString(16).padStart(2, "0")).join("");
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
}

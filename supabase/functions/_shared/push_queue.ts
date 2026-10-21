// supabase/functions/_shared/push_queue.ts
//
// Every push goes through public.scheduled_notifications (Spec 1b): the
// queue's triggers apply quiet hours and the no-titles copy rules, and the
// worker (process-scheduled-notifications) is the only OneSignal caller. A
// function that wants to notify someone enqueues; it never sends.

export type QueuedPush = {
  userId: string;
  type: string;
  title: string;
  body: string;
  /** Extra metadata (deep-link ids). type/title/body above always win. */
  data?: Record<string, unknown>;
  /** Idempotency: a second enqueue with the same key is a no-op. */
  sourceKey?: string;
  /**
   * The caller's `data` carries its own unique key (a unique index on the
   * metadata, e.g. outbox_id -- 20261019110000): a duplicate means the
   * push is already queued and is not an error. Unlike sourceKey this does
   * not opt the push out of the overnight collapse (quiet guard).
   * Requires `data.outbox_id` (the only such index) -- without it the flag
   * would swallow an unrelated duplicate, so enqueuePush refuses it.
   */
  dedupedByData?: boolean;
};

// deno-lint-ignore no-explicit-any
type Client = { from: (table: string) => any };

/**
 * Queues the push. Resolves true when a queued row exists for it (written
 * now, or already there: a duplicate key), false when the queue absorbed it
 * -- the quiet guard folds an overnight chat push into the 08:00 one and
 * writes no row (plan 1b final review M2), so there is nothing to send now.
 */
export async function enqueuePush(supabase: Client, push: QueuedPush): Promise<boolean> {
  if (push.dedupedByData) {
    const key = push.data?.outbox_id;
    if (typeof key !== "string" || key.length === 0) {
      throw new Error("enqueue_push_misuse:dedupedByData_requires_data.outbox_id");
    }
  }
  const now = new Date().toISOString();
  const { data, error } = await supabase.from("scheduled_notifications").insert({
    user_id: push.userId,
    notification_type: "immediate",
    scheduled_for: now,
    status: "pending",
    metadata: { ...(push.data ?? {}), type: push.type, title: push.title, body: push.body },
    source_key: push.sourceKey ?? null,
    created_at: now,
    updated_at: now,
  }).select("id");
  if (!error) return Array.isArray(data) && data.length > 0;
  if ((push.sourceKey || push.dedupedByData) && error.code === "23505") return true;
  throw new Error(`enqueue_push_failed:${error.code ?? "unknown"}`);
}

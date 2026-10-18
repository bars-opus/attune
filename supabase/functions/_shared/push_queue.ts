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
};

// deno-lint-ignore no-explicit-any
type Client = { from: (table: string) => any };

export async function enqueuePush(supabase: Client, push: QueuedPush): Promise<void> {
  const now = new Date().toISOString();
  const { error } = await supabase.from("scheduled_notifications").insert({
    user_id: push.userId,
    notification_type: "immediate",
    scheduled_for: now,
    status: "pending",
    metadata: { ...(push.data ?? {}), type: push.type, title: push.title, body: push.body },
    source_key: push.sourceKey ?? null,
    created_at: now,
    updated_at: now,
  });
  if (!error) return;
  if (push.sourceKey && error.code === "23505") return;
  throw new Error(`enqueue_push_failed:${error.code ?? "unknown"}`);
}

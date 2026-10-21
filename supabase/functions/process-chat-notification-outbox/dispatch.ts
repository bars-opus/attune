// supabase/functions/process-chat-notification-outbox/dispatch.ts
//
// Chat review #14 (07 H-2): a chat push used to wait for the once-a-minute
// cron (0-60 s after the message). After queuing, the worker wakes
// process-scheduled-notifications once per run. The sender claims rows
// atomically (status pending -> processing), so a wake racing the cron or
// another wake is safe; a failed wake is not an error -- the cron remains
// the sweeper. Nothing here talks to OneSignal (push_transport.test.ts):
// Spec 1b's quiet-hours and copy guards still see every push.
//
// Awaited (with a timeout) rather than fire-and-forget: the edge runtime
// may end a pending fetch once the response is written, and this worker's
// own callers (pg_net, cron) never wait on it anyway.

export type Fetch = (input: string, init: RequestInit) => Promise<Response>;

/**
 * The worker itself is kicked by pg_net, whose request window is about
 * 5 s; giving up on the wake at 3 s keeps the worker's reply inside it.
 * A wake that gives up is "failed" and the minute cron sends the push.
 * The sender answers 202 as soon as it has accepted the batch (plan 1b
 * final review M1), so a backlog no longer makes a working wake "failed".
 */
export const WAKE_TIMEOUT_MS = 3000;

export function senderUrl(supabaseUrl: string): string {
  return `${supabaseUrl.replace(/\/+$/, "")}/functions/v1/process-scheduled-notifications`;
}

export async function wakeScheduledSender(opts: {
  supabaseUrl: string;
  serviceRoleKey: string;
  fetchImpl?: Fetch;
  timeoutMs?: number;
}): Promise<"woken" | "failed"> {
  const fetchImpl = opts.fetchImpl ?? ((u, i) => fetch(u, i));
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), opts.timeoutMs ?? WAKE_TIMEOUT_MS);
  try {
    const res = await fetchImpl(senderUrl(opts.supabaseUrl), {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Bearer ${opts.serviceRoleKey}`,
        "apikey": opts.serviceRoleKey,
      },
      body: JSON.stringify({ reason: "chat_outbox" }),
      signal: controller.signal,
    });
    // The sender's reply is not needed; release it rather than leave the
    // connection held until GC.
    await res.body?.cancel().catch(() => {});
    return res.ok ? "woken" : "failed";
  } catch (_) {
    return "failed";
  } finally {
    clearTimeout(timer);
  }
}

// supabase/functions/_shared/onesignal_push.ts
//
// The only OneSignal caller (push_transport.test.ts). Chat review #18: a
// push is addressed to the recipient's registered devices
// (include_subscription_ids, from push_tokens via push_targets.ts), never
// to an alias a stranger can attach to their own phone -- see
// 20261019110200_push_subscriptions.sql.
export type Fetch = (input: string, init: RequestInit) => Promise<Response>;

/// Plan 2 Task 2 fix round: the whole exchange (request and response body)
/// is bounded so a hung send cannot hold its scheduled_notifications row in
/// 'processing' past the 5-minute stale lease, where
/// recover_stale_chat_worker_leases() would hand it to a second sender.
/// A timeout throws (retryable, same idempotency key); it never prunes.
export const ONESIGNAL_TIMEOUT_MS = 30_000;

export type OneSignalSendResult = {
  /** OneSignal's notification id; null when no targeted device was subscribed. */
  id: string | null;
  /** Subscription ids OneSignal no longer knows or that are unsubscribed. */
  invalidSubscriptionIds: string[];
};

export async function sendOneSignalPush(input: {
  subscriptionIds: string[];
  title: string;
  body: string;
  data?: Record<string, unknown>;
  idempotencyKey?: string;
  fetchImpl?: Fetch;
  env?: (name: string) => string | undefined;
  /** Tests only; defaults to ONESIGNAL_TIMEOUT_MS. */
  timeoutMs?: number;
}): Promise<OneSignalSendResult> {
  if (input.subscriptionIds.length === 0) throw new Error("onesignal_no_subscription");
  const env = input.env ?? ((name: string) => Deno.env.get(name));
  const appId = requiredEnv(env, "ONESIGNAL_APP_ID");
  const apiKey = requiredEnv(env, "ONESIGNAL_API_KEY");
  const fetchImpl = input.fetchImpl ?? ((u, i) => fetch(u, i));
  const controller = new AbortController();
  let timer: ReturnType<typeof setTimeout> | undefined;
  // Raced as well as signalled: a transport that ignores the signal still
  // cannot hang the caller.
  const timedOut = new Promise<never>((_, reject) => {
    timer = setTimeout(() => {
      controller.abort();
      reject(new Error("onesignal_timeout"));
    }, input.timeoutMs ?? ONESIGNAL_TIMEOUT_MS);
  });
  try {
    return await Promise.race([exchange(fetchImpl, controller.signal, appId, apiKey, input), timedOut]);
  } finally {
    clearTimeout(timer);
  }
}

async function exchange(
  fetchImpl: Fetch,
  signal: AbortSignal,
  appId: string,
  apiKey: string,
  input: {
    subscriptionIds: string[];
    title: string;
    body: string;
    data?: Record<string, unknown>;
    idempotencyKey?: string;
  },
): Promise<OneSignalSendResult> {
  const response = await fetchImpl("https://api.onesignal.com/notifications", {
    method: "POST",
    signal,
    headers: {
      "Authorization": `Key ${apiKey}`,
      "Content-Type": "application/json",
      ...(input.idempotencyKey
        ? { "Idempotency-Key": input.idempotencyKey }
        : {}),
    },
    body: JSON.stringify({
      app_id: appId,
      include_subscription_ids: input.subscriptionIds,
      target_channel: "push",
      headings: { en: input.title },
      contents: { en: input.body },
      data: input.data ?? {},
      // OneSignal's documented dedupe field (a UUID: the queue row id); the
      // header above is kept alongside it.
      ...(input.idempotencyKey ? { idempotency_key: input.idempotencyKey } : {}),
    }),
  });

  const result = await response.json().catch(() => ({}));
  const invalid = invalidIds(result, input.subscriptionIds);
  if (!response.ok) {
    // A 400 whose only complaint is dead targets is a prune (the caller
    // deactivates them and skips the row); anything else is a failure.
    if (response.status === 400 && invalid.length > 0) {
      return { id: null, invalidSubscriptionIds: invalid };
    }
    throw new Error(`onesignal_${response.status}`);
  }
  const id = typeof result.id === "string" && result.id.length > 0 ? result.id : null;
  return { id, invalidSubscriptionIds: invalid };
}

/// OneSignal answers 200 and names unknown targets under
/// errors.invalid_player_ids (legacy name) or errors.invalid_subscription_ids;
/// when none of the targets is subscribed it answers 200 with id "" and
/// errors: ["All included players are not subscribed"]. Either way those
/// devices are gone and must not be targeted again.
///
/// Only ids that were actually sent come back (matched case-insensitively,
/// returned as sent, each once): a malformed response naming some other id
/// must never deactivate another person's device.
export function invalidIds(result: unknown, targeted: string[]): string[] {
  const errors = (result as { errors?: unknown } | null)?.errors;
  if (!errors) return [];
  if (Array.isArray(errors)) {
    return errors.some((e) => typeof e === "string" && /not subscribed/i.test(e)) ? [...targeted] : [];
  }
  if (typeof errors !== "object") return [];
  const e = errors as Record<string, unknown>;
  const named = new Set(
    [e.invalid_player_ids, e.invalid_subscription_ids]
      .flatMap((v) => (Array.isArray(v) ? v : []))
      .filter((v): v is string => typeof v === "string")
      .map((v) => v.toLowerCase()),
  );
  return [...new Set(targeted)].filter((id) => named.has(id.toLowerCase()));
}

function requiredEnv(env: (name: string) => string | undefined, name: string) {
  const value = env(name);
  if (!value) throw new Error(`missing_${name.toLowerCase()}`);
  return value;
}

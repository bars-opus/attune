// supabase/functions/_shared/onesignal_push.test.ts
// Chat review #18 (07 H-3): the push is addressed to the recipient's
// registered devices, never to the external_id alias a stranger can claim.
import { assertEquals, assertRejects } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { invalidIds, ONESIGNAL_TIMEOUT_MS, sendOneSignalPush } from "./onesignal_push.ts";

const env = (n: string) => ({ ONESIGNAL_APP_ID: "app", ONESIGNAL_API_KEY: "key" })[n];

function capture(status = 200, body: unknown = { id: "n1" }) {
  const seen: { url?: string; init?: RequestInit } = {};
  const fetchImpl = (url: string, init: RequestInit) => {
    seen.url = url;
    seen.init = init;
    return Promise.resolve(new Response(JSON.stringify(body), { status }));
  };
  return { seen, fetchImpl };
}

Deno.test("targets include_subscription_ids and nothing else", async () => {
  const { seen, fetchImpl } = capture();
  const out = await sendOneSignalPush({
    subscriptionIds: ["s1", "s2"], title: "T", body: "B", data: { type: "new_message" },
    idempotencyKey: "job-1", fetchImpl, env,
  });
  assertEquals(out, { id: "n1", invalidSubscriptionIds: [] });
  assertEquals(seen.url, "https://api.onesignal.com/notifications");
  const sent = JSON.parse(seen.init!.body as string);
  assertEquals(sent.include_subscription_ids, ["s1", "s2"]);
  assertEquals("include_aliases" in sent, false);
  assertEquals("include_external_user_ids" in sent, false);
  assertEquals(sent.target_channel, "push");
  assertEquals((seen.init!.headers as Record<string, string>)["Idempotency-Key"], "job-1");
  // OneSignal's documented dedupe field (the header is kept alongside it).
  assertEquals(sent.idempotency_key, "job-1");
});

Deno.test("no idempotency key: neither the header nor the body field is sent", async () => {
  const { seen, fetchImpl } = capture();
  await sendOneSignalPush({ subscriptionIds: ["s1"], title: "T", body: "B", fetchImpl, env });
  const sent = JSON.parse(seen.init!.body as string);
  assertEquals("idempotency_key" in sent, false);
  assertEquals("Idempotency-Key" in (seen.init!.headers as Record<string, string>), false);
});

Deno.test("no device: refuses to send rather than widening the target", async () => {
  await assertRejects(
    () => sendOneSignalPush({ subscriptionIds: [], title: "T", body: "B", fetchImpl: capture().fetchImpl, env }),
    Error, "onesignal_no_subscription",
  );
});

Deno.test("devices OneSignal no longer knows come back for pruning", async () => {
  const gone = capture(200, { id: "n2", errors: { invalid_player_ids: ["s2"] } });
  const out = await sendOneSignalPush({ subscriptionIds: ["s1", "s2"], title: "T", body: "B", fetchImpl: gone.fetchImpl, env });
  assertEquals(out, { id: "n2", invalidSubscriptionIds: ["s2"] });

  const none = capture(200, { id: "", errors: ["All included players are not subscribed"] });
  const out2 = await sendOneSignalPush({ subscriptionIds: ["s1"], title: "T", body: "B", fetchImpl: none.fetchImpl, env });
  assertEquals(out2, { id: null, invalidSubscriptionIds: ["s1"] });
});

Deno.test("invalidIds reads both shapes OneSignal uses", () => {
  assertEquals(invalidIds({ errors: { invalid_subscription_ids: ["a"] } }, ["a", "b"]), ["a"]);
  assertEquals(invalidIds({ errors: { invalid_player_ids: ["b"] } }, ["a", "b"]), ["b"]);
  assertEquals(invalidIds({ errors: ["All included players are not subscribed"] }, ["a", "b"]), ["a", "b"]);
  assertEquals(invalidIds({ errors: ["something else"] }, ["a"]), []);
  assertEquals(invalidIds({}, ["a"]), []);
  assertEquals(invalidIds(null, ["a"]), []);
});

Deno.test("invalidIds only ever names ids that were actually sent", () => {
  // A malformed or hostile response naming someone else's device must never
  // reach deactivatePushSubscriptions.
  assertEquals(invalidIds({ errors: { invalid_player_ids: ["a", "zzz-other-person"] } }, ["a", "b"]), ["a"]);
  assertEquals(invalidIds({ errors: { invalid_subscription_ids: ["other"] } }, ["a"]), []);
  // Case-insensitive match; the id comes back as it was sent.
  assertEquals(invalidIds({ errors: { invalid_player_ids: ["ABC-1"] } }, ["abc-1", "def-2"]), ["abc-1"]);
  // Named under both keys: listed once.
  assertEquals(
    invalidIds({ errors: { invalid_player_ids: ["a"], invalid_subscription_ids: ["A"] } }, ["a", "b"]),
    ["a"],
  );
});

Deno.test("an HTTP failure still throws with the status", async () => {
  await assertRejects(
    () => sendOneSignalPush({ subscriptionIds: ["s1"], title: "T", body: "B", fetchImpl: capture(503, {}).fetchImpl, env }),
    Error, "onesignal_503",
  );
  // A 400 that names nothing to prune is a real failure (bad app id, bad
  // payload) and must retry/dead-letter like any other.
  await assertRejects(
    () => sendOneSignalPush({ subscriptionIds: ["s1"], title: "T", body: "B", fetchImpl: capture(400, { errors: ["app_id not found"] }).fetchImpl, env }),
    Error, "onesignal_400",
  );
});

Deno.test("a 400 that only names dead subscriptions is a prune, not a failure", async () => {
  // OneSignal has answered both 200 and 400 for "every target is gone"
  // depending on API vintage; either way the row must be skipped once and
  // the devices pruned, never retried five times a minute.
  const gone = capture(400, { errors: { invalid_player_ids: ["s1"] } });
  assertEquals(
    await sendOneSignalPush({ subscriptionIds: ["s1"], title: "T", body: "B", fetchImpl: gone.fetchImpl, env }),
    { id: null, invalidSubscriptionIds: ["s1"] },
  );
  const none = capture(400, { errors: ["All included players are not subscribed"] });
  assertEquals(
    await sendOneSignalPush({ subscriptionIds: ["s1", "s2"], title: "T", body: "B", fetchImpl: none.fetchImpl, env }),
    { id: null, invalidSubscriptionIds: ["s1", "s2"] },
  );
});

// Plan 2 Task 2 fix round: a hung send must not hold its scheduled_
// notifications row in 'processing' past the 5-minute stale lease, where
// recover_stale_chat_worker_leases() would hand it to a second sender.
Deno.test("a send OneSignal never answers times out as a retryable failure", async () => {
  let signal: AbortSignal | null | undefined;
  const hung = (_url: string, init: RequestInit) => {
    signal = init.signal;
    return new Promise<Response>(() => {});
  };
  await assertRejects(
    () => sendOneSignalPush({ subscriptionIds: ["s1"], title: "T", body: "B", fetchImpl: hung, env, timeoutMs: 20 }),
    Error, "onesignal_timeout",
  );
  // The request itself is cancelled, not just abandoned.
  assertEquals(signal?.aborted, true);
});

Deno.test("a response body that never finishes times out too (no prune)", async () => {
  const stalled = () =>
    Promise.resolve(new Response(new ReadableStream({ start() {} }), { status: 400 }));
  await assertRejects(
    () => sendOneSignalPush({ subscriptionIds: ["s1"], title: "T", body: "B", fetchImpl: stalled, env, timeoutMs: 20 }),
    Error, "onesignal_timeout",
  );
});

Deno.test("the default timeout sits well inside the 5-minute stale lease", () => {
  assertEquals(ONESIGNAL_TIMEOUT_MS, 30_000);
});

Deno.test("the transport source never mentions the alias", async () => {
  const src = await Deno.readTextFile(new URL("./onesignal_push.ts", import.meta.url));
  assertEquals(src.includes("include_aliases"), false);
  assertEquals(src.includes("external_id"), false);
});

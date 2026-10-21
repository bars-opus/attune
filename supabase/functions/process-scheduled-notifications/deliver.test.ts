// supabase/functions/process-scheduled-notifications/deliver.test.ts
// Chat review #18: a push goes to registered devices; a person with none is
// skipped once (never retried five times a minute); gone devices are pruned.
import { assertEquals, assertRejects } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { deliverPush, pushIdempotencyKey } from "./deliver.ts";

const job = { id: "j1", user_id: "u1" };
const copy = { title: "T", body: "B", data: { type: "new_message" } };

function deps(subs: string[], result: { id: string | null; invalidSubscriptionIds: string[] } | Error) {
  const sent: unknown[] = [];
  const pruned: string[][] = [];
  return {
    sent,
    pruned,
    deps: {
      loadSubscriptions: (_u: string) => Promise.resolve(subs),
      send: (input: unknown) => {
        sent.push(input);
        return result instanceof Error ? Promise.reject(result) : Promise.resolve(result);
      },
      deactivate: (ids: string[]) => {
        pruned.push(ids);
        return Promise.resolve();
      },
    },
  };
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

Deno.test("sends to every registered device, keyed on the row and its target set", async () => {
  const d = deps(["s1", "s2"], { id: "n1", invalidSubscriptionIds: [] });
  assertEquals(await deliverPush(job, copy, d.deps), { status: "sent", lastError: null });
  assertEquals(d.sent, [{
    subscriptionIds: ["s1", "s2"], title: "T", body: "B", data: { type: "new_message" },
    idempotencyKey: await pushIdempotencyKey("j1", ["s1", "s2"]),
  }]);
  assertEquals(d.pruned, []);
});

// OneSignal may remember a 400 under its idempotency key, so a retry after
// pruning (same row, fewer devices) must carry a new key; a retry after a
// lost response (same row, same devices) must carry the same one.
Deno.test("idempotency key: UUID-shaped, stable per row + target set", async () => {
  const k = await pushIdempotencyKey("j1", ["s1", "s2"]);
  assertEquals(UUID.test(k), true);
  assertEquals(k[14], "5"); // version nibble
  assertEquals("89ab".includes(k[19]), true); // RFC 4122 variant
  assertEquals(await pushIdempotencyKey("j1", ["s1", "s2"]), k);
  assertEquals(await pushIdempotencyKey("j1", ["s2", "s1"]), k, "target order is irrelevant");
  assertEquals(await pushIdempotencyKey("j1", ["S1", "s2"]), k, "target case is irrelevant");
  assertEquals((await pushIdempotencyKey("j1", ["s1"])) !== k, true, "a pruned target set is a new key");
  assertEquals((await pushIdempotencyKey("j2", ["s1", "s2"])) !== k, true, "another row is a new key");
  // The separator cannot be forged by an id: ("j1", ["a,b"]) ≠ ("j1", ["a","b"]).
  assertEquals((await pushIdempotencyKey("j1", ["a,b"])) !== (await pushIdempotencyKey("j1", ["a", "b"])), true);
});

Deno.test("the pruned retry is sent under a new key", async () => {
  const first = deps(["s1", "s2"], { id: null, invalidSubscriptionIds: ["s2"] });
  await assertRejects(() => deliverPush(job, copy, first.deps), Error, "onesignal_400_pruned");
  const retry = deps(["s1"], { id: "n1", invalidSubscriptionIds: [] });
  assertEquals(await deliverPush(job, copy, retry.deps), { status: "sent", lastError: null });
  const k1 = (first.sent[0] as { idempotencyKey: string }).idempotencyKey;
  const k2 = (retry.sent[0] as { idempotencyKey: string }).idempotencyKey;
  assertEquals(UUID.test(k1) && UUID.test(k2), true);
  assertEquals(k1 !== k2, true);
});

Deno.test("no device → skipped, nothing sent", async () => {
  const d = deps([], { id: "n1", invalidSubscriptionIds: [] });
  assertEquals(await deliverPush(job, copy, d.deps), { status: "skipped", lastError: "no_push_subscription" });
  assertEquals(d.sent, []);
});

Deno.test("gone devices are pruned; none left subscribed → skipped", async () => {
  const some = deps(["s1", "s2"], { id: "n1", invalidSubscriptionIds: ["s2"] });
  assertEquals(await deliverPush(job, copy, some.deps), { status: "sent", lastError: null });
  assertEquals(some.pruned, [["s2"]]);

  const none = deps(["s1"], { id: null, invalidSubscriptionIds: ["s1"] });
  assertEquals(await deliverPush(job, copy, none.deps), { status: "skipped", lastError: "no_subscribed_device" });
  assertEquals(none.pruned, [["s1"]]);
});

Deno.test("some devices rejected and nothing sent: prune them, then retry for the live ones", async () => {
  // A 400 naming only part of the target list: OneSignal sent nothing, but
  // s1 may still be live. Skipping would drop the push for a device that
  // can receive it; the retry targets the remaining devices.
  const d = deps(["s1", "s2"], { id: null, invalidSubscriptionIds: ["s2"] });
  await assertRejects(() => deliverPush(job, copy, d.deps), Error, "onesignal_400_pruned");
  assertEquals(d.pruned, [["s2"]]);
});

Deno.test("every device rejected (any casing) → skipped, all pruned", async () => {
  const d = deps(["s1", "s2"], { id: null, invalidSubscriptionIds: ["S2", "s1"] });
  assertEquals(await deliverPush(job, copy, d.deps), { status: "skipped", lastError: "no_subscribed_device" });
  assertEquals(d.pruned, [["S2", "s1"]]);
});

Deno.test("a transport failure propagates (the worker's retry path)", async () => {
  const d = deps(["s1"], new Error("onesignal_503"));
  await assertRejects(() => deliverPush(job, copy, d.deps), Error, "onesignal_503");
});

Deno.test("a timed-out send is retried, never treated as gone devices", async () => {
  // Plan 2 Task 2 fix round: nothing is known about the devices after a
  // timeout, so none may be deactivated; the worker's retry path re-sends
  // under the same idempotency key.
  const d = deps(["s1", "s2"], new Error("onesignal_timeout"));
  await assertRejects(() => deliverPush(job, copy, d.deps), Error, "onesignal_timeout");
  assertEquals(d.pruned, []);
});

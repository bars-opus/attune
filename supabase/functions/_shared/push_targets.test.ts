// supabase/functions/_shared/push_targets.test.ts
import { assertEquals, assertRejects } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { deactivatePushSubscriptions, loadPushSubscriptions } from "./push_targets.ts";

function fakeClient(rows: Record<string, unknown>[] | null, error: { code?: string } | null = null) {
  const calls: Record<string, unknown>[] = [];
  const builder = {
    select(cols: string) { calls.push({ select: cols }); return builder; },
    eq(col: string, v: unknown) { calls.push({ eq: [col, v] }); return builder; },
    update(patch: Record<string, unknown>) { calls.push({ update: patch }); return builder; },
    in(col: string, v: unknown) { calls.push({ in: [col, v] }); return Promise.resolve({ error }); },
    then(resolve: (v: unknown) => void) { resolve({ data: rows, error }); },
  };
  return { calls, from(table: string) { calls.push({ from: table }); return builder; } };
}

const s1 = "11111111-2222-4333-8444-555555555551";
const s2 = "11111111-2222-4333-8444-555555555552";

Deno.test("loads the person's active device subscriptions only", async () => {
  // A OneSignal subscription id is a UUID. Anything else in the column is a
  // leftover raw APNs/FCM token from the retired savePushToken path (the
  // migration deactivates those, this is the belt to its braces): never
  // handed to OneSignal, where it would 400 the whole send.
  const c = fakeClient([{ token: s1 }, { token: s2 }, { token: "" }, { token: "fcm:legacy-token-abc" }]);
  assertEquals(await loadPushSubscriptions(c, "u1"), [s1, s2]);
  assertEquals(c.calls[0], { from: "push_tokens" });
  assertEquals(c.calls.some((x) => JSON.stringify(x) === JSON.stringify({ eq: ["user_id", "u1"] })), true);
  assertEquals(c.calls.some((x) => JSON.stringify(x) === JSON.stringify({ eq: ["is_active", true] })), true);
});

Deno.test("a read error is an error (the push is retried, not silently skipped)", async () => {
  await assertRejects(() => loadPushSubscriptions(fakeClient(null, { code: "42501" }), "u1"), Error, "push_targets_failed:42501");
});

Deno.test("pruning marks the named devices inactive and never throws", async () => {
  const c = fakeClient(null);
  await deactivatePushSubscriptions(c, [s2]);
  assertEquals(c.calls.some((x) => JSON.stringify(x) === JSON.stringify({ in: ["token", [s2]] })), true);
  // The patch itself: inactive, with a fresh updated_at (a mutation that
  // writes is_active: true, or drops it, must fail here).
  const patch = c.calls.find((x) => "update" in x)?.update as Record<string, unknown> | undefined;
  assertEquals(patch?.is_active, false);
  assertEquals(typeof patch?.updated_at, "string");
  assertEquals(Object.keys(patch ?? {}).sort(), ["is_active", "updated_at"]);
  // A failed prune is logged, never thrown (stubbed so test output stays clean).
  const logged: unknown[][] = [];
  const realError = console.error;
  console.error = (...args: unknown[]) => { logged.push(args); };
  try {
    await deactivatePushSubscriptions(fakeClient(null, { code: "x" }), [s2]);
  } finally {
    console.error = realError;
  }
  assertEquals(logged, [["deactivate push subscriptions failed", "x"]]);
  const untouched = fakeClient(null);
  await deactivatePushSubscriptions(untouched, []);
  assertEquals(untouched.calls, []);
});

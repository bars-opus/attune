// supabase/functions/_shared/push_queue.test.ts
import { assertEquals, assertRejects } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { enqueuePush } from "./push_queue.ts";

/// `absorbed`: the queue's quiet guard returned NULL (an overnight chat push
/// joined the 08:00 one), so PostgREST answers with no row.
function fakeClient(error: { code?: string } | null = null, absorbed = false) {
  const rows: Record<string, unknown>[] = [];
  return {
    rows,
    from(table: string) {
      return {
        insert(row: Record<string, unknown>) {
          rows.push({ table, ...row });
          return {
            select: (_columns: string) =>
              Promise.resolve({ data: error ? null : absorbed ? [] : [{ id: "n1" }], error }),
          };
        },
      };
    },
  };
}

const push = { userId: "u1", type: "invite_accepted", title: "T", body: "B" };

Deno.test("enqueuePush queues one pending, immediate push; explicit fields win over data", async () => {
  const c = fakeClient();
  await enqueuePush(c, { ...push, data: { relationship_id: "r1", type: "spoof", title: "spoof" }, sourceKey: "k1" });
  assertEquals(c.rows.length, 1);
  const row = c.rows[0];
  assertEquals(row.table, "scheduled_notifications");
  assertEquals(row.user_id, "u1");
  assertEquals(row.status, "pending");
  assertEquals(row.notification_type, "immediate");
  assertEquals(row.source_key, "k1");
  assertEquals(row.metadata, { relationship_id: "r1", type: "invite_accepted", title: "T", body: "B" });
});

Deno.test("enqueuePush without a key leaves source_key null", async () => {
  const c = fakeClient();
  await enqueuePush(c, push);
  assertEquals(c.rows[0].source_key, null);
});

Deno.test("a duplicate key means already queued: no throw", async () => {
  await enqueuePush(fakeClient({ code: "23505" }), { ...push, sourceKey: "k1" });
});

Deno.test("a duplicate without a key, or any other error, throws", async () => {
  await assertRejects(() => enqueuePush(fakeClient({ code: "23505" }), push), Error, "enqueue_push_failed:23505");
  await assertRejects(() => enqueuePush(fakeClient({ code: "42501" }), { ...push, sourceKey: "k1" }), Error, "enqueue_push_failed:42501");
});

// Chat review #17: the chat outbox dedupes on metadata.outbox_id (a unique
// index; see 20261019110000), not source_key, so the overnight collapse
// still applies. A duplicate there means "already queued".
Deno.test("a duplicate of a data-keyed push means already queued: no throw", async () => {
  const c = fakeClient({ code: "23505" });
  await enqueuePush(c, { ...push, data: { outbox_id: "o1" }, dedupedByData: true });
  assertEquals(c.rows[0].source_key, null);
});

Deno.test("dedupedByData never sets source_key", async () => {
  const c = fakeClient();
  await enqueuePush(c, { ...push, data: { outbox_id: "o1" }, dedupedByData: true });
  assertEquals(c.rows[0].source_key, null);
  assertEquals((c.rows[0].metadata as Record<string, unknown>).outbox_id, "o1");
});

// 1b Task 5 fix round: dedupedByData turns a 23505 into "already queued",
// so it is only honest when data carries the key the unique index is on
// (outbox_id). Without it the flag would swallow unrelated duplicates.
Deno.test("dedupedByData without the dedupe key in data is a programming error", async () => {
  for (const data of [undefined, {}, { outbox_id: "" }, { outbox_id: 7 }]) {
    const c = fakeClient();
    await assertRejects(
      () => enqueuePush(c, { ...push, data: data as Record<string, unknown> | undefined, dedupedByData: true }),
      Error,
      "enqueue_push_misuse:dedupedByData_requires_data.outbox_id",
    );
    assertEquals(c.rows.length, 0);
  }
});

// Plan 1b final review M2: the quiet guard can absorb an overnight chat push
// into the 08:00 one (the insert writes no row). enqueuePush says whether a
// queued row exists, so the chat worker wakes the sender only for one.
Deno.test("enqueuePush reports a queued row", async () => {
  assertEquals(await enqueuePush(fakeClient(), push), true);
  assertEquals(await enqueuePush(fakeClient(), { ...push, data: { outbox_id: "o1" }, dedupedByData: true }), true);
});

Deno.test("a push the queue absorbed (no row written) reports none", async () => {
  const c = fakeClient(null, true);
  assertEquals(await enqueuePush(c, { ...push, data: { outbox_id: "o1" }, dedupedByData: true }), false);
  assertEquals(c.rows.length, 1);
});

Deno.test("a duplicate means its row is already queued", async () => {
  assertEquals(await enqueuePush(fakeClient({ code: "23505" }), { ...push, sourceKey: "k1" }), true);
  assertEquals(
    await enqueuePush(fakeClient({ code: "23505" }), { ...push, data: { outbox_id: "o1" }, dedupedByData: true }),
    true,
  );
});

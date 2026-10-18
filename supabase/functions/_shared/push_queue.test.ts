// supabase/functions/_shared/push_queue.test.ts
import { assertEquals, assertRejects } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { enqueuePush } from "./push_queue.ts";

function fakeClient(error: { code?: string } | null = null) {
  const rows: Record<string, unknown>[] = [];
  return {
    rows,
    from(table: string) {
      return {
        insert(row: Record<string, unknown>) {
          rows.push({ table, ...row });
          return Promise.resolve({ error });
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

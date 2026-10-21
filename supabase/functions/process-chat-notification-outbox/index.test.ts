// Sync audit M-5: a deleted message or a system notice ("Goal reached:
// <plan>") is never pushed; Spec 1b keeps plan titles off lock screens.
import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { chatPushAllowed, drainJobs, messagePushable, processJob } from "./index.ts";

Deno.test("only live, ordinary messages are pushed", () => {
  assertEquals(messagePushable({ deleted_at: null, is_system_notice: false }), true);
  assertEquals(messagePushable({ deleted_at: "2026-10-18T00:00:00Z", is_system_notice: false }), false);
  assertEquals(messagePushable({ deleted_at: null, is_system_notice: true }), false);
});

Deno.test("the worker checks it before any push", async () => {
  const src = await Deno.readTextFile(new URL("./index.ts", import.meta.url));
  const body = src.slice(src.indexOf('.from("messages")'));
  const check = body.indexOf("messagePushable(");
  if (check < 0 || check > body.indexOf("chat_message_preview_enabled")) {
    throw new Error("messagePushable is not checked before the push settings");
  }
});

// Chat review #16 (07 M-8): the settings toggle labelled "Relationship
// Updates" (shared-activity pings) also switched off message pushes. Only
// the master push switch gates a chat push.
Deno.test("only the master push switch gates a chat push", () => {
  assertEquals(chatPushAllowed(null), true);
  assertEquals(chatPushAllowed(undefined), true);
  assertEquals(chatPushAllowed({ push_enabled: true }), true);
  assertEquals(chatPushAllowed({ push_enabled: null }), true);
  assertEquals(chatPushAllowed({ push_enabled: false }), false);
});

Deno.test("the worker never reads the Relationship Updates column", async () => {
  const src = await Deno.readTextFile(new URL("./index.ts", import.meta.url));
  assertEquals(src.includes("booking_reminders"), false);
  assertEquals(src.includes("chatPushAllowed(settings)"), true);
});

// Chat review #17/#14: the queued push carries the outbox id as its dedupe
// key (through enqueuePush, never a raw insert), the in-app copy tolerates
// its own duplicate, and the sender is woken after the loop.
Deno.test("the push is queued through enqueuePush, keyed by outbox_id", async () => {
  const src = await Deno.readTextFile(new URL("./index.ts", import.meta.url));
  assertEquals(src.includes('.from("scheduled_notifications")'), false);
  const call = src.slice(src.indexOf("await enqueuePush(supabase, {"));
  const body = call.slice(0, call.indexOf("});"));
  assertEquals(body.includes("outbox_id: outboxId"), true);
  assertEquals(body.includes("dedupedByData: true"), true);
  assertEquals(body.includes("sourceKey"), false);
});

Deno.test("a duplicate in-app notification is not an error", async () => {
  const src = await Deno.readTextFile(new URL("./index.ts", import.meta.url));
  assertEquals(src.includes('inAppResult.error.code !== "23505"'), true);
});

Deno.test("the worker wakes the real sender with the project's service role", async () => {
  const src = await Deno.readTextFile(new URL("./index.ts", import.meta.url));
  const serve = src.slice(src.indexOf("serve(async"), src.indexOf("return jsonResponse({\n      success: true,"));
  assertEquals(serve.includes("drainJobs(supabase, jobs, () =>"), true);
  assertEquals(serve.includes("wakeScheduledSender({"), true);
  assertEquals(serve.includes('requireEnv("SUPABASE_SERVICE_ROLE_KEY")'), true);
});

// 1b Task 5 fix round: behaviour, not source shape. A fake PostgREST client
// records every call; each test answers the ones it cares about.
type Call = { table: string; op: string; payload?: unknown; filters: [string, unknown][] };
type Answer = { data?: unknown; error?: { code?: string; message?: string } | null };

function fakeSupabase(answer: (call: Call) => Answer | undefined) {
  const calls: Call[] = [];
  const resolve = (call: Call) => {
    calls.push(call);
    return Promise.resolve({ data: null, error: null, ...(answer(call) ?? {}) });
  };
  const from = (table: string) => {
    const call: Call = { table, op: "select", filters: [] };
    // deno-lint-ignore no-explicit-any
    const b: any = {
      select: () => b,
      insert: (payload: unknown) => (call.op = "insert", call.payload = payload, b),
      update: (payload: unknown) => (call.op = "update", call.payload = payload, b),
      eq: (column: string, value: unknown) => (call.filters.push([column, value]), b),
      order: () => b,
      limit: () => b,
      maybeSingle: () => resolve(call),
      then: (ok: (v: unknown) => unknown, fail: (e: unknown) => unknown) => resolve(call).then(ok, fail),
    };
    return b;
  };
  const rpc = (fn: string, payload: unknown) =>
    resolve({ table: `rpc:${fn}`, op: "rpc", payload, filters: [] });
  return { calls, client: { from, rpc } as never };
}

const job = {
  id: "o1",
  message_id: "m1",
  recipient_id: "user-a",
  sender_id: "user-b",
  notification_type: "new_message",
  attempts: 1,
  state: "processing",
};

// A job whose earlier attempt already wrote both the in-app copy and the
// queued push, then failed before it was marked done (chat review #17).
function retriedJobAnswers(call: Call): Answer | undefined {
  if (call.table === "messages") {
    return {
      data: {
        id: "m1",
        content: "hi",
        deleted_at: null,
        is_system_notice: false,
        relationships: { id: "r1", status: "active", chat_archived_at: null, user_a: "user-a", user_b: "user-b" },
      },
    };
  }
  if (call.table === "notification_settings") {
    return { data: { push_enabled: true, chat_message_preview_enabled: false } };
  }
  if (call.table === "rpc:is_actively_viewing") return { data: false };
  if (call.table === "in_app_notifications") return { error: { code: "23505" } };
  if (call.table === "scheduled_notifications") return { error: { code: "23505" } };
  if (call.table === "message_notification_outbox" && call.op === "select") return { data: { attempts: 0 } };
  if (call.table === "message_notification_outbox" && call.op === "update") return { data: job };
  return undefined;
}

Deno.test("a retry that finds its in-app copy and its push already queued completes the job", async () => {
  const { calls, client } = fakeSupabase(retriedJobAnswers);
  const result = await processJob(client, job);
  assertEquals(result, { outbox_id: "o1", status: "completed", queued: true });

  const inserts = calls.filter((c) => c.op === "insert").map((c) => c.table);
  assertEquals(inserts, ["in_app_notifications", "scheduled_notifications"]);
  const push = calls.find((c) => c.table === "scheduled_notifications")!.payload as Record<string, unknown>;
  assertEquals((push.metadata as Record<string, unknown>).outbox_id, "o1");
  assertEquals(push.source_key, null);

  const finals = calls.filter((c) => c.table === "message_notification_outbox" && c.op === "update");
  assertEquals(finals.length, 1);
  assertEquals((finals[0].payload as Record<string, unknown>).state, "done");
  assertEquals((finals[0].payload as Record<string, unknown>).last_error_code, null);
});

Deno.test("a run that queued pushes wakes the sender exactly once", async () => {
  const { client } = fakeSupabase(retriedJobAnswers);
  let wakes = 0;
  const run = await drainJobs(client, [job, { ...job, id: "o2" }], () => {
    wakes++;
    return Promise.resolve("woken");
  });
  assertEquals(wakes, 1);
  assertEquals(run.wake, "woken");
  assertEquals(run.results.map((r) => r.status), ["completed", "completed"]);
});

Deno.test("a run that queued nothing does not wake; a failed wake still completes the run", async () => {
  const pushOff = (call: Call) =>
    call.table === "notification_settings" ? { data: { push_enabled: false } } : retriedJobAnswers(call);
  let wakes = 0;
  const quiet = await drainJobs(fakeSupabase(pushOff).client, [job], () => {
    wakes++;
    return Promise.resolve("woken");
  });
  assertEquals(wakes, 0);
  assertEquals(quiet.wake, "not_needed");

  const failed = await drainJobs(fakeSupabase(retriedJobAnswers).client, [job], () => Promise.resolve("failed"));
  assertEquals(failed.wake, "failed");
  assertEquals(failed.results[0].status, "completed");
});

// Plan 1b final review M2: an overnight message joins the 08:00 push (the
// quiet guard writes no row). Nothing is due now, so the run does not wake
// the sender for it.
Deno.test("a push absorbed into the overnight one is not queued and does not wake", async () => {
  const absorbed = (call: Call) =>
    call.table === "scheduled_notifications" ? { data: [], error: null } : retriedJobAnswers(call);
  const { calls, client } = fakeSupabase(absorbed);
  let wakes = 0;
  const run = await drainJobs(client, [job], () => {
    wakes++;
    return Promise.resolve("woken");
  });
  assertEquals(wakes, 0);
  assertEquals(run.wake, "not_needed");
  assertEquals(run.results, [{ outbox_id: "o1", status: "completed", queued: false, push: "joined_overnight_push" }]);
  const finals = calls.filter((c) => c.table === "message_notification_outbox" && c.op === "update");
  assertEquals((finals.at(-1)!.payload as Record<string, unknown>).state, "done");
});

Deno.test("a fresh queued push wakes the sender", async () => {
  const fresh = (call: Call) =>
    call.table === "scheduled_notifications" ? { data: [{ id: "n1" }], error: null } : retriedJobAnswers(call);
  let wakes = 0;
  const run = await drainJobs(fakeSupabase(fresh).client, [job], () => {
    wakes++;
    return Promise.resolve("woken");
  });
  assertEquals(wakes, 1);
  assertEquals(run.results, [{ outbox_id: "o1", status: "completed", queued: true }]);
});

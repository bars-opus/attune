// supabase/functions/process-chat-notification-outbox/dispatch.test.ts
// Chat review #14 (07 H-2): after queuing, the worker wakes the sender; a
// failed wake is not an error (the cron sweeps).
import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { FakeTime } from "https://deno.land/std@0.224.0/testing/time.ts";
import { senderUrl, wakeScheduledSender } from "./dispatch.ts";

Deno.test("the sender's URL is under the project's functions host", () => {
  assertEquals(
    senderUrl("https://abc.supabase.co/"),
    "https://abc.supabase.co/functions/v1/process-scheduled-notifications",
  );
});

Deno.test("a wake posts with the service role and reports woken", async () => {
  let seen: { url: string; init: RequestInit } | null = null;
  const out = await wakeScheduledSender({
    supabaseUrl: "https://abc.supabase.co",
    serviceRoleKey: "srk",
    fetchImpl: (url, init) => {
      seen = { url, init };
      return Promise.resolve(new Response("{}", { status: 200 }));
    },
  });
  assertEquals(out, "woken");
  assertEquals(seen!.url, "https://abc.supabase.co/functions/v1/process-scheduled-notifications");
  assertEquals(seen!.init.method, "POST");
  const headers = seen!.init.headers as Record<string, string>;
  assertEquals(headers["Authorization"], "Bearer srk");
  assertEquals(headers["apikey"], "srk");
});

Deno.test("a refused, failed or slow wake is reported, never thrown", async () => {
  assertEquals(
    await wakeScheduledSender({
      supabaseUrl: "u", serviceRoleKey: "k",
      fetchImpl: () => Promise.resolve(new Response("no", { status: 500 })),
    }),
    "failed",
  );
  assertEquals(
    await wakeScheduledSender({
      supabaseUrl: "u", serviceRoleKey: "k",
      fetchImpl: () => Promise.reject(new TypeError("network")),
    }),
    "failed",
  );
  assertEquals(
    await wakeScheduledSender({
      supabaseUrl: "u", serviceRoleKey: "k", timeoutMs: 10,
      fetchImpl: (_url, init) =>
        new Promise((_, reject) =>
          init.signal!.addEventListener("abort", () => reject(new DOMException("aborted", "AbortError")))
        ),
    }),
    "failed",
  );
});

// 1b Task 5 fix round: the worker is kicked by pg_net (about 5 s request
// window), so the wake gives up after 3 s by default and the worker always
// answers inside that window. The cron catches up on a wake that gave up.
Deno.test("by default a wake gives up after 3 s", async () => {
  const time = new FakeTime();
  try {
    let settled = false;
    const out = wakeScheduledSender({
      supabaseUrl: "u", serviceRoleKey: "k",
      fetchImpl: (_url, init) =>
        new Promise((_, reject) =>
          init.signal!.addEventListener("abort", () => reject(new DOMException("aborted", "AbortError")))
        ),
    }).then((v) => {
      settled = true;
      return v;
    });
    await time.tickAsync(2999);
    assertEquals(settled, false);
    await time.tickAsync(1);
    assertEquals(await out, "failed");
  } finally {
    time.restore();
  }
});

// Plan 1b final review M1: the sender accepts a wake with 202 and sends in
// the background; that is a successful wake.
Deno.test("a wake the sender accepted (202) is woken", async () => {
  assertEquals(
    await wakeScheduledSender({
      supabaseUrl: "u", serviceRoleKey: "k",
      fetchImpl: () => Promise.resolve(new Response('{"success":true,"accepted":true}', { status: 202 })),
    }),
    "woken",
  );
});

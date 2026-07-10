// Run with: deno test supabase/functions/_shared/retry.test.ts

import {
  assertEquals,
  assertRejects,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import { defaultIsRetryable, retry } from "./retry.ts";

Deno.test("retry returns immediately on first-attempt success", async () => {
  let calls = 0;
  const result = await retry(async () => {
    calls++;
    return "ok";
  });
  assertEquals(result, "ok");
  assertEquals(calls, 1);
});

Deno.test("retry retries transient failures up to attempts", async () => {
  let calls = 0;
  const result = await retry(
    async () => {
      calls++;
      if (calls < 3) throw new Error("network blip");
      return "ok";
    },
    { attempts: 5, baseDelayMs: 1, jitterMs: 0 },
  );
  assertEquals(result, "ok");
  assertEquals(calls, 3);
});

Deno.test("retry gives up after attempts exhausted", async () => {
  let calls = 0;
  await assertRejects(
    () =>
      retry(
        async () => {
          calls++;
          throw new Error("network down");
        },
        { attempts: 3, baseDelayMs: 1, jitterMs: 0 },
      ),
    Error,
    "network down",
  );
  assertEquals(calls, 3);
});

Deno.test("retry does NOT retry non-retryable errors", async () => {
  let calls = 0;
  await assertRejects(
    () =>
      retry(
        async () => {
          calls++;
          throw new Error("invalid input");
        },
        { attempts: 5, baseDelayMs: 1, jitterMs: 0 },
      ),
  );
  assertEquals(calls, 1, "should fail on first non-retryable error");
});

Deno.test("defaultIsRetryable: 5xx Response → retryable", () => {
  assertEquals(defaultIsRetryable(new Response("", { status: 500 })), true);
  assertEquals(defaultIsRetryable(new Response("", { status: 503 })), true);
});

Deno.test("defaultIsRetryable: 429 Response → retryable", () => {
  assertEquals(defaultIsRetryable(new Response("", { status: 429 })), true);
});

Deno.test("defaultIsRetryable: 4xx Response → NOT retryable", () => {
  assertEquals(defaultIsRetryable(new Response("", { status: 400 })), false);
  assertEquals(defaultIsRetryable(new Response("", { status: 404 })), false);
});

Deno.test("defaultIsRetryable: network Error → retryable", () => {
  assertEquals(defaultIsRetryable(new Error("network timeout")), true);
  assertEquals(defaultIsRetryable(new Error("ECONNRESET")), true);
});

Deno.test("defaultIsRetryable: generic Error → NOT retryable", () => {
  assertEquals(defaultIsRetryable(new Error("validation failed")), false);
});

Deno.test("retry uses custom isRetryable predicate", async () => {
  let calls = 0;
  await assertRejects(() =>
    retry(
      async () => {
        calls++;
        throw new Error("specific");
      },
      {
        attempts: 5,
        baseDelayMs: 1,
        jitterMs: 0,
        isRetryable: (err) =>
          (err as Error).message === "specific",
      },
    )
  );
  // All 5 attempts should run because we declared this error retryable.
  assertEquals(calls, 5);
});

// supabase/functions/process-scheduled-notifications/accept.test.ts
//
// Plan 1b final review M1: the chat worker's wake gives up after 3 s, and a
// backlog of up to 50 sends takes longer, so a working sender looked
// "failed". The sender now answers 202 as soon as it has accepted the batch
// and runs it in EdgeRuntime.waitUntil; without that runtime (tests, local
// serve) it runs the batch and answers when done, as before.
import { assert, assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { acceptAndRun, edgeWaitUntil } from "./accept.ts";

function deferred<T>() {
  let resolve!: (v: T) => void;
  let reject!: (e: unknown) => void;
  const promise = new Promise<T>((ok, fail) => {
    resolve = ok;
    reject = fail;
  });
  return { promise, resolve, reject };
}

Deno.test("with a background runtime the sender answers 202 before the batch ends", async () => {
  const batch = deferred<Record<string, unknown>>();
  const kept: Promise<unknown>[] = [];
  let ran = 0;
  const res = await acceptAndRun(() => {
    ran++;
    return batch.promise;
  }, (work) => kept.push(work));
  assertEquals(res.status, 202);
  assertEquals(await res.json(), { success: true, accepted: true });
  assertEquals(ran, 1, "the batch started before the answer");
  assertEquals(kept.length, 1, "the batch is handed to waitUntil");
  let settled = false;
  kept[0].then(() => (settled = true));
  await Promise.resolve();
  assertEquals(settled, false);
  batch.resolve({ processed: 3 });
  await kept[0];
  assertEquals(settled, true);
});

Deno.test("a batch that fails in the background is logged, never thrown", async () => {
  const original = console.error;
  const logged: unknown[][] = [];
  console.error = (...args: unknown[]) => logged.push(args);
  try {
    const kept: Promise<unknown>[] = [];
    const res = await acceptAndRun(
      () => Promise.reject(new Error("candidates_failed")),
      (work) => kept.push(work),
    );
    assertEquals(res.status, 202);
    await kept[0]; // resolves: the rejection is handled
    assertEquals(logged.length, 1);
    assertStringIncludes(String(logged[0].join(" ")), "candidates_failed");
  } finally {
    console.error = original;
  }
});

Deno.test("without a background runtime the batch runs before the answer", async () => {
  const ok = await acceptAndRun(() => Promise.resolve({ processed: 2 }), null);
  assertEquals(ok.status, 200);
  assertEquals(await ok.json(), { success: true, processed: 2 });

  const failed = await acceptAndRun(() => Promise.reject(new Error("claim_failed")), null);
  assertEquals(failed.status, 500);
  assertEquals(await failed.json(), { success: false, error: "claim_failed" });
});

Deno.test("EdgeRuntime.waitUntil is used when the runtime provides it", () => {
  // deno-lint-ignore no-explicit-any
  const g = globalThis as any;
  const before = g.EdgeRuntime;
  try {
    delete g.EdgeRuntime;
    assertEquals(edgeWaitUntil(), null);
    const kept: Promise<unknown>[] = [];
    g.EdgeRuntime = { waitUntil: (p: Promise<unknown>) => kept.push(p) };
    const waitUntil = edgeWaitUntil();
    assert(waitUntil);
    const work = Promise.resolve();
    waitUntil(work);
    assertEquals(kept, [work]);
  } finally {
    if (before === undefined) delete g.EdgeRuntime;
    else g.EdgeRuntime = before;
  }
});

Deno.test("the sender checks the service role, then accepts the batch in the background", async () => {
  const src = await Deno.readTextFile(new URL("./index.ts", import.meta.url));
  const handler = src.slice(src.indexOf("serve(async"));
  const auth = handler.indexOf("requireServiceRole(req)");
  const accept = handler.indexOf("acceptAndRun(");
  assert(auth >= 0 && accept > auth, "requireServiceRole runs before the batch is accepted");
  assertStringIncludes(handler, "acceptAndRun(() => processDueBatch(supabase))");
});

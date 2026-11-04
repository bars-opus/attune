// Spec 1 W7b (B6 fix I-1): scan-media answers pg_net at once (its call
// gives up after 5 s) and runs in EdgeRuntime.waitUntil, as
// build-data-exports, process-story-archival and
// process-scheduled-notifications do. Without that runtime (tests, a plain
// local serve) the run finishes before the answer.
import { acceptAndRun, edgeWaitUntil } from "./accept.ts";

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

Deno.test("with waitUntil: 202 at once, the run handed over and still going", async () => {
  const handed: Promise<unknown>[] = [];
  let finish!: () => void;
  let ran = false;
  const response = await acceptAndRun(
    () =>
      new Promise((resolve) => {
        ran = true;
        finish = () => resolve({ claimed: 1 });
      }),
    (work) => handed.push(work),
  );
  assert(response.status === 202, `status ${response.status}`);
  assert((await response.json()).accepted === true, "accepted");
  assert(ran && handed.length === 1, "the run was started and handed to waitUntil");
  let settled = false;
  handed[0].then(() => (settled = true));
  await Promise.resolve();
  assert(!settled, "the answer did not wait for the run");
  finish();
  await handed[0];
});

Deno.test("with waitUntil: a failing run is caught (never an unhandled rejection)", async () => {
  const handed: Promise<unknown>[] = [];
  const response = await acceptAndRun(() => Promise.reject(new Error("claim_failed")), (work) => handed.push(work));
  assert(response.status === 202, `status ${response.status}`);
  await handed[0]; // resolves: the rejection was caught
});

Deno.test("without waitUntil: the run finishes first; its counts or a 500", async () => {
  const ok = await acceptAndRun(() => Promise.resolve({ claimed: 2, clear: 2 }), null);
  const body = await ok.json();
  assert(ok.status === 200 && body.success === true && body.claimed === 2, JSON.stringify(body));
  const failed = await acceptAndRun(() => Promise.reject(new Error("/storage/v1/object/message-media/user-id/x.jpg")), null);
  const failedBody = await failed.json();
  assert(failed.status === 500 && failedBody.error === "scan_failed", JSON.stringify(failedBody));
  assert(!JSON.stringify(failedBody).includes("message-media"), "an error message reached the response");
});

Deno.test("edgeWaitUntil reads the runtime only when it has waitUntil", () => {
  // deno-lint-ignore no-explicit-any
  const g = globalThis as any;
  const before = g.EdgeRuntime;
  try {
    delete g.EdgeRuntime;
    assert(edgeWaitUntil() === null, "no runtime");
    g.EdgeRuntime = {};
    assert(edgeWaitUntil() === null, "a runtime without waitUntil");
    const seen: Promise<unknown>[] = [];
    g.EdgeRuntime = { waitUntil: (p: Promise<unknown>) => seen.push(p) };
    const w = edgeWaitUntil();
    const p = Promise.resolve();
    w?.(p);
    assert(seen.length === 1 && seen[0] === p, "the runtime's waitUntil");
  } finally {
    if (before === undefined) delete g.EdgeRuntime;
    else g.EdgeRuntime = before;
  }
});

Deno.test("index.ts answers through acceptAndRun, after the service-role check", async () => {
  const index = await Deno.readTextFile(new URL("./index.ts", import.meta.url));
  const auth = index.indexOf("requireServiceRole(req)");
  const accept = index.indexOf("acceptAndRun(");
  assert(auth > -1 && accept > auth, "acceptAndRun must come after requireServiceRole");
  assert(/return (await )?acceptAndRun\(/.test(index), "the answer is acceptAndRun's");
});

Deno.test("N-3: index.ts wires the bounds and the environment it is tested with", async () => {
  const index = await Deno.readTextFile(new URL("./index.ts", import.meta.url));
  const has = (text: string, why: string) => assert(index.includes(text), `index.ts: ${why} (${text})`);
  has("global: { fetch: timedFetch(RPC_TIMEOUT_MS) }", "every database and Storage call is aborted");
  has("const env = await readEnvironment(supabase);", "the environment is read with readEnvironment");
  has("environment: env", "the matcher gets that environment");
  has("headTimeoutMs: HEAD_TIMEOUT_MS, readTimeoutMs: DOWNLOAD_TIMEOUT_MS", "the reader's requests are aborted in time");
  has("startedAt", "the run's clock starts before the environment read");
  const started = index.indexOf("const startedAt = Date.now();");
  assert(started > -1 && started < index.indexOf("readEnvironment(supabase)"), "startedAt is taken before the environment read");
  assert(/scanMedia\([\s\S]*\{ startedAt \}\)/.test(index), "scanMedia gets startedAt");
  assert(!/environment: ["']development["']/.test(index), "a hard-coded environment");
});

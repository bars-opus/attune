// Spec 2 W6b (§6.1, §7.3; chat spec §9, §11): the worker. Each claimed
// message is completed with its hits; no config (missing, malformed or
// failing to load) is no detection, never another config; one message's
// failure is its own; an engine error goes back with a code; nothing it
// logs holds a message's text.
import { assertEquals, assertRejects } from "https://deno.land/std@0.224.0/assert/mod.ts";
import lexicon from "../_shared/dating_chat_lexicon_v1.json" with { type: "json" };
import type { Hit } from "../_shared/dating_chat_safety.ts";
import { type Deps, type Job, runOutbox, WorkerError } from "./handler.ts";

const jobs: Job[] = [
  { message_id: "m1", body: "send me momo, I have your video", new_match: false },
  { message_id: "m2", body: "What does a good Saturday look like for you?", new_match: true },
];

function deps(over: Partial<Deps> = {}, list: Job[] = jobs) {
  const done: [string, string | null, Hit[], string | null][] = [];
  const logs: string[] = [];
  const d: Deps = {
    claim: async () => list,
    config: async () => ({ version: "dating_chat_v1", config: lexicon }),
    complete: async (id, version, hits, error) => {
      done.push([id, version, hits, error]);
    },
    log: (line) => logs.push(line),
    ...over,
  };
  return { d, done, logs };
}

Deno.test("each claimed message is completed with the rules it trips", async () => {
  const { d, done } = deps();
  const r = await runOutbox(d);
  assertEquals(r, { claimed: 2, completed: 2, failed: 0, detection: true });
  assertEquals(done[0][0], "m1");
  assertEquals(done[0][1], "dating_chat_v1");
  assertEquals(done[0][2].map((h) => h.family), ["financial_request", "sextortion"]);
  assertEquals(done[1], ["m2", "dating_chat_v1", [], null]);
});

// Fix round 1 (review I-2; Ruling): a config that fails to load claims
// nothing (the messages stay queued and are read on the next run); no
// active config or a malformed one is no detection, each logged by its own
// code.
Deno.test("no config or a malformed one: no detection, each logged by its own code", async () => {
  for (const [config, code] of [[async () => null, ", no config"],
                                [async () => ({ version: "v", config: { families: { nope: {} } } }), ", config malformed"]] as const) {
    const { d, done, logs } = deps({ config });
    const r = await runOutbox(d);
    assertEquals(r.detection, false);
    assertEquals(done.map((x) => [x[0], x[1], x[2].length, x[3]]), [["m1", null, 0, null], ["m2", null, 0, null]]);
    assertEquals(logs, [`process-dating-safety-outbox: 2 claimed, 2 completed, 0 failed${code}`]);
  }
});

Deno.test("a config that fails to load claims nothing and answers config_failed", async () => {
  let claimed = 0;
  const { d, done, logs } = deps({
    claim: async () => {
      claimed++;
      return jobs;
    },
    config: async () => {
      throw new Error("config_failed");
    },
  });
  await assertRejects(() => runOutbox(d), WorkerError, "config_failed");
  assertEquals([claimed, done.length], [0, 0]);
  assertEquals(logs, ["process-dating-safety-outbox: config_failed, nothing claimed"]);
});

Deno.test("one message's failure is its own; an engine error goes back with a code", async () => {
  const { d, done } = deps({}, [{ message_id: "bad", body: null as unknown as string, new_match: false }, ...jobs]);
  const r = await runOutbox(d);
  assertEquals(done[0], ["bad", "dating_chat_v1", [], "engine_error"]);
  assertEquals(r, { claimed: 3, completed: 2, failed: 1, detection: true });
  let calls = 0;
  const flaky = deps({
    complete: async () => {
      calls++;
      if (calls === 1) throw new Error("complete_failed");
    },
  });
  assertEquals(await runOutbox(flaky.d), { claimed: 2, completed: 1, failed: 1, detection: true });
});

Deno.test("nothing logged holds a message's text", async () => {
  const { d, logs } = deps();
  const spy: string[] = [];
  const original = console.log;
  console.log = (...a: unknown[]) => spy.push(a.join(" "));
  try {
    await runOutbox(d);
  } finally {
    console.log = original;
  }
  for (const line of [...logs, ...spy]) {
    if (/momo|video|saturday/i.test(line)) throw new Error(`a log line holds message text: ${line}`);
  }
});

// Task 5's live complete_dating_safety_job answers {ok:false, reason} for a
// completion it refuses (invalid: a version, tier or rule it can't take;
// not_claimed: the claim is gone, e.g. a second completion). The worker
// counts it as failed and logs only its code; an invalid completion goes
// back once with an error code (the database retries it and dead-letters
// it after its 5th attempt) and is never retried in a loop; not_claimed is
// left alone (stale recovery or another run owns it). Nothing crashes the
// batch.
Deno.test("an {ok:false} answer is counted by its code; invalid goes back once; not_claimed is left alone", async () => {
  const calls: [string, string | null, number, string | null][] = [];
  const { d, logs } = deps({
    complete: async (id, version, hits, error) => {
      calls.push([id, version, hits.length, error]);
      if (error !== null) return { ok: true, state: "pending" };
      if (id === "m1") return { ok: false, reason: "invalid" };
      return { ok: false, reason: "not_claimed" };
    },
  });
  const r = await runOutbox(d);
  assertEquals(r, { claimed: 2, completed: 0, failed: 2, detection: true });
  assertEquals(calls, [["m1", "dating_chat_v1", 2, null], ["m1", "dating_chat_v1", 0, "rejected_hits"], ["m2", "dating_chat_v1", 0, null]]);
  assertEquals(logs, ["process-dating-safety-outbox: 2 claimed, 0 completed, 2 failed (invalid 1, not_claimed 1)"]);
});

Deno.test("an {ok:false} with an unknown reason logs a fixed code; a failing send-back is its own", async () => {
  let n = 0;
  const { d, logs } = deps({
    complete: async (_id, _version, _hits, error) => {
      n++;
      if (error !== null) throw new Error("complete_failed");
      return n === 1 ? { ok: false, reason: "invalid" } : { ok: false, reason: "send me momo <b>" };
    },
  });
  assertEquals(await runOutbox(d), { claimed: 2, completed: 0, failed: 2, detection: true });
  assertEquals(logs, ["process-dating-safety-outbox: 2 claimed, 0 completed, 2 failed (invalid 1, other 1)"]);
});

// Fix round 1 (review M-1): the worker passes each job's new_match through
// (a first-14-days term fires only in a new match) and its limit to claim.
Deno.test("a job's new_match reaches the engine; the limit reaches claim", async () => {
  const limits: number[] = [];
  const { d, done } = deps({
    claim: async (limit) => {
      limits.push(limit);
      return [{ message_id: "n1", body: "send me airtime", new_match: true }, { message_id: "n2", body: "send me airtime", new_match: false }];
    },
  });
  await runOutbox(d);
  assertEquals(done.map((x) => [x[0], x[2].map((h) => h.rule_id)]), [["n1", ["financial_request:airtime"]], ["n2", []]]);
  await runOutbox(d, 7);
  assertEquals(limits, [50, 7]);
});

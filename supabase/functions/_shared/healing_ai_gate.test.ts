// Spec 1 W9e: the Healing gate. The crisis check runs first; any doubt is
// a match (support, never the provider) or, for the AI flag, paused.
import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { DELETE_ATTEMPTS, HEALING_AI_FLAG, healingGate, MAX_ANSWER_DEPTH, reflectionTextOf } from "./healing_ai_gate.ts";
import { fakeClient } from "./test_support/fake_supabase.ts";
import { CRISIS, journey, nested, ORDINARY, spyDeps, THROWS } from "./test_support/healing_fakes.ts";

Deno.test("the flag is healing_ai_insights", () => {
  assertEquals(HEALING_AI_FLAG, "healing_ai_insights");
});

Deno.test("reflectionTextOf reads every string, and nothing it cannot read", () => {
  assertEquals(reflectionTextOf(null), "");
  assertEquals(reflectionTextOf(undefined), "");
  assertEquals(reflectionTextOf({}), "");
  assertEquals(reflectionTextOf({ a: "one", b: 2, c: null, d: { e: ["two", true] } }), "one\ntwo");
  assertEquals(reflectionTextOf(nested(MAX_ANSWER_DEPTH)), "ordinary words");
  assertEquals(reflectionTextOf(nested(MAX_ANSWER_DEPTH + 1)), null);
  assertEquals(reflectionTextOf(["a list"]), null);
  assertEquals(reflectionTextOf("a string"), null);
  assertEquals(reflectionTextOf(7), null);
  assertEquals(reflectionTextOf({ a: THROWS }), null);
});

Deno.test("a crisis anywhere in the answers, even nested, is a match", async () => {
  for (const answers of [CRISIS, { a: { b: [CRISIS.answer1] } }]) {
    const admin = fakeClient();
    const body = await healingGate(admin.client, "u1", journey({ reflection_answers: answers }), "portrait", spyDeps().deps);
    assertEquals(body, { status: "support_offered" });
  }
});

Deno.test("Review Focus 3: crisis words split across two answers are a match (fail safe)", async () => {
  const split = { answer1: "Some nights I want to", answer2: "kill myself", answer3: "" };
  const body = await healingGate(fakeClient().client, "u1", journey({ reflection_answers: split }), "portrait", spyDeps().deps);
  assertEquals(body, { status: "support_offered" });
});

Deno.test("fail safe: unreadable answers, or a private_safety_check read that throws, offer support", async () => {
  for (const answers of [["a list"], "a string", nested(MAX_ANSWER_DEPTH + 1)]) {
    const body = await healingGate(fakeClient().client, "u1", journey({ reflection_answers: answers }), "portrait", spyDeps().deps);
    assertEquals(body, { status: "support_offered" }, JSON.stringify(answers));
  }
  const body = await healingGate(fakeClient().client, "u1", journey(), "portrait", spyDeps({ victimisationThrows: true }).deps);
  assertEquals(body, { status: "support_offered" });
});

Deno.test("fail safe: a healing_ai_insights read that throws is paused", async () => {
  const admin = fakeClient();
  const body = await healingGate(admin.client, "u1", journey(), "portrait", spyDeps({ pausedThrows: true }).deps);
  assertEquals(body, { status: "paused" });
  assertEquals(admin.calls.length, 0);
});

Deno.test("no match and not paused: go on (null), with nothing read or written", async () => {
  const admin = fakeClient();
  assertEquals(await healingGate(admin.client, "u1", journey({ reflection_answers: ORDINARY }), "portrait", spyDeps().deps), null);
  assertEquals(admin.calls.length, 0);
});

Deno.test("the stale-output delete answers {error}: retried, bounded, and support is still offered", async () => {
  const always = fakeClient((call) => (call.op === "delete" ? { data: null, error: { message: "down" } } : { data: null, error: null }));
  const body = await healingGate(always.client, "u1", journey({ reflection_answers: CRISIS }), "post_mortem", spyDeps().deps);
  assertEquals(body, { status: "support_offered" });
  assertEquals(always.calls.filter((c) => c.op === "delete").length, DELETE_ATTEMPTS);

  let failures = 1;
  const once = fakeClient((call) =>
    call.op === "delete" && failures-- > 0 ? { data: null, error: { message: "down" } } : { data: null, error: null }
  );
  await healingGate(once.client, "u1", journey({ reflection_answers: CRISIS }), "post_mortem", spyDeps().deps);
  assertEquals(once.calls.filter((c) => c.op === "delete").length, 2);

  const throwing = fakeClient((call) => {
    if (call.op === "delete") throw new Error("network");
    return { data: null, error: null };
  });
  assertEquals(
    await healingGate(throwing.client, "u1", journey({ reflection_answers: CRISIS }), "post_mortem", spyDeps().deps),
    { status: "support_offered" },
  );
});

// Batch 2 additions (Spec 1 W9e; W9 B7 lessons): every fail-closed branch
// and every service-role write is pinned, so its mutant turns red.

Deno.test("fail safe: a healing_ai_insights answer that is not exactly false is paused", async () => {
  for (const answer of [undefined, null, "off", 0]) {
    const admin = fakeClient();
    const deps = { ...spyDeps().deps, aiPaused: () => Promise.resolve(answer as unknown as boolean) };
    assertEquals(await healingGate(admin.client, "u1", journey(), "portrait", deps), { status: "paused" }, String(answer));
    assertEquals(admin.calls.length, 0);
  }
});

Deno.test("fail safe: a match while healing_ai_insights is unreadable still offers support and clears the stage", async () => {
  const admin = fakeClient();
  const body = await healingGate(admin.client, "u1", journey({ reflection_answers: CRISIS }), "portrait", spyDeps({ pausedThrows: true }).deps);
  assertEquals(body, { status: "support_offered" });
  assertEquals(admin.calls.map((c) => [c.table, c.op]), [["healing_generation_jobs", "delete"]]);
});

Deno.test("the saved-text clear answers {error}: retried, bounded, scoped to the caller, and support is still offered", async () => {
  const saved = journey({ reflection_answers: CRISIS, post_mortem_status: "completed", post_mortem_observation: "Old." });
  const always = fakeClient((call) => (call.op === "update" ? { data: null, error: { message: "down" } } : { data: null, error: null }));
  const body = await healingGate(always.client, "u1", saved, "post_mortem", spyDeps().deps);
  assertEquals(body, { status: "support_offered" });
  const updates = always.calls.filter((c) => c.op === "update");
  assertEquals(updates.length, DELETE_ATTEMPTS);
  for (const u of updates) {
    assertEquals(u.table, "healing_journeys");
    assertEquals(u.filters, [["eq", "id", "j1"], ["eq", "user_id", "u1"]]);
  }
  for (const d of always.calls.filter((c) => c.op === "delete")) {
    assertEquals(d.filters, [["eq", "journey_id", "j1"], ["eq", "user_id", "u1"], ["eq", "stage", "post_mortem"]]);
  }
});

Deno.test("nothing is logged: not the reflection, the term or the user id", async () => {
  const seen: unknown[][] = [];
  const saved = { log: console.log, info: console.info, warn: console.warn, error: console.error, debug: console.debug };
  const spy = (...args: unknown[]) => {
    seen.push(args);
  };
  Object.assign(console, { log: spy, info: spy, warn: spy, error: spy, debug: spy });
  try {
    const failing = fakeClient(() => ({ data: null, error: { message: "down" } }));
    await healingGate(failing.client, "u1", journey({ reflection_answers: CRISIS, portrait_text: "Old." }), "portrait", spyDeps().deps);
    await healingGate(fakeClient().client, "u1", journey({ reflection_answers: ["a list"] }), "portrait", spyDeps({ victimisationThrows: true }).deps);
    await healingGate(fakeClient().client, "u1", journey(), "portrait", spyDeps({ pausedThrows: true }).deps);
  } finally {
    Object.assign(console, saved);
  }
  assertEquals(seen, []);
});

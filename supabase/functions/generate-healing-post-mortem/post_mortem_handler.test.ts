// Spec 1 W9e (owner approval O2; spec 8 W9e): the post-mortem's crisis check
// runs first, W9c's pattern. With a spy on the provider: a crisis
// reflection never reaches it, or the cache, or the saved reflection,
// whatever either flag says; nothing about the match is stored and the
// stage's earlier AI output is removed; with no match, healing_ai_insights
// off answers paused before anything is read; otherwise as before.
import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { handlePostMortem } from "./post_mortem_handler.ts";
import { fakeClient } from "../_shared/test_support/fake_supabase.ts";
import { CRISIS, journey, ORDINARY, spyDeps, userWith, VICTIM } from "../_shared/test_support/healing_fakes.ts";

const U = { id: "u1" };

Deno.test("a crisis reflection never reaches the provider or the cache, and stores nothing", async () => {
  for (const paused of [false, true]) {
    for (const victimisation of [false, true]) {
      const user = userWith(journey({ reflection_answers: CRISIS }));
      const admin = fakeClient();
      const spy = spyDeps({ paused, victimisation });
      const res = await handlePostMortem(user.client, admin.client, U, "j1", spy.deps);
      assertEquals(await res.json(), { status: "support_offered" });
      assertEquals(spy.prompts.length, 0, "the provider was called");
      // First: nothing but the caller's journey was read.
      assertEquals(user.calls.map((c) => c.table), ["healing_journeys"]);
      // Only the stage's cached jobs are removed (no saved text to clear).
      assertEquals(admin.calls.map((c) => [c.table, c.op]), [["healing_generation_jobs", "delete"]]);
      assertEquals(admin.calls[0].filters, [["eq", "journey_id", "j1"], ["eq", "user_id", "u1"], ["eq", "stage", "post_mortem"]]);
      assertEquals(admin.rpcs.length, 0);
    }
  }
});

Deno.test("the check runs before the saved reflection: it is cleared, never returned", async () => {
  const saved = journey({
    reflection_answers: CRISIS,
    post_mortem_status: "completed",
    post_mortem_observation: "An older observation.",
    post_mortem_confidence: "low",
    post_mortem_reflection_prompt: "An older prompt.",
  });
  const admin = fakeClient();
  const spy = spyDeps();
  const res = await handlePostMortem(userWith(saved).client, admin.client, U, "j1", spy.deps);
  const text = await res.text();
  assertEquals(JSON.parse(text), { status: "support_offered" });
  assert(!text.includes("older"));
  assertEquals(admin.calls.map((c) => [c.table, c.op]), [["healing_generation_jobs", "delete"], ["healing_journeys", "update"]]);
  // The AI text only: the status and the time stay.
  assertEquals(admin.calls[1].payload, {
    post_mortem_observation: null,
    post_mortem_confidence: null,
    post_mortem_reflection_prompt: null,
  });
  assertEquals(admin.calls[1].filters, [["eq", "id", "j1"], ["eq", "user_id", "u1"]]);
  assertEquals(spy.prompts.length, 0);
});

Deno.test("no match while paused: paused, before the saved reflection, the cache or the provider", async () => {
  for (const opts of [{ paused: true }, { pausedThrows: true }]) {
    const user = userWith(journey({ post_mortem_status: "completed", post_mortem_observation: "Saved.", post_mortem_confidence: "low" }));
    const admin = fakeClient();
    const spy = spyDeps(opts);
    const res = await handlePostMortem(user.client, admin.client, U, "j1", spy.deps);
    assertEquals(await res.json(), { status: "paused" });
    assertEquals(admin.calls.length, 0, "the cache was read or written");
    assertEquals(user.calls.map((c) => c.table), ["healing_journeys"]);
    assertEquals(spy.prompts.length, 0);
  }
});

Deno.test("an ordinary reflection, not paused: the caller's own cache, then the provider, as before", async () => {
  const admin = fakeClient();
  const spy = spyDeps();
  const res = await handlePostMortem(userWith(journey({ reflection_answers: ORDINARY })).client, admin.client, U, "j1", spy.deps);
  assertEquals((await res.json()).status, "completed");
  assertEquals(admin.calls.map((c) => [c.table, c.op]), [["healing_generation_jobs", "select"], ["healing_generation_jobs", "upsert"]]);
  assertEquals(admin.calls[0].filters.slice(0, 3), [["eq", "user_id", "u1"], ["eq", "journey_id", "j1"], ["eq", "stage", "post_mortem"]]);
  assertEquals(spy.prompts.length, 1);
  assert(spy.prompts[0].includes("I mistook intensity for closeness."));
});

Deno.test("the [DRAFT] victimisation list runs only with private_safety_check on", async () => {
  const on = spyDeps({ victimisation: true });
  const resOn = await handlePostMortem(userWith(journey({ reflection_answers: VICTIM })).client, fakeClient().client, U, "j1", on.deps);
  assertEquals((await resOn.json()).status, "support_offered");
  assertEquals(on.prompts.length, 0);

  const off = spyDeps({ victimisation: false });
  const resOff = await handlePostMortem(userWith(journey({ reflection_answers: VICTIM })).client, fakeClient().client, U, "j1", off.deps);
  assertEquals((await resOff.json()).status, "completed");
  assertEquals(off.prompts.length, 1);
});

Deno.test("Review Focus 4: a phone keyboard's typographic apostrophe still matches", async () => {
  const spy = spyDeps();
  const answers = { answer1: "I don\u2019t want to be here anymore", answer2: "", answer3: "" };
  const res = await handlePostMortem(userWith(journey({ reflection_answers: answers })).client, fakeClient().client, U, "j1", spy.deps);
  assertEquals(await res.json(), { status: "support_offered" });
  assertEquals(spy.prompts.length, 0);
});

Deno.test("fail safe: an unreadable reflection or a flag read that throws never reaches the provider", async () => {
  for (const [row, opts] of [
    [journey({ reflection_answers: ["a list"] }), {}],
    [journey(), { victimisationThrows: true }],
  ] as const) {
    const spy = spyDeps(opts);
    const res = await handlePostMortem(userWith(row).client, fakeClient().client, U, "j1", spy.deps);
    assertEquals(await res.json(), { status: "support_offered" });
    assertEquals(spy.prompts.length, 0);
  }
});

Deno.test("a journey the caller cannot read answers 404, with nothing else read", async () => {
  const admin = fakeClient();
  const spy = spyDeps();
  const res = await handlePostMortem(userWith(null, { message: "no rows" }).client, admin.client, U, "j1", spy.deps);
  assertEquals(res.status, 404);
  assertEquals(admin.calls.length, 0);
  assertEquals(spy.prompts.length, 0);
});

Deno.test("index.ts wires the live provider, the pause flag and the draft-list flag", async () => {
  const src = await Deno.readTextFile(new URL("./index.ts", import.meta.url));
  assert(src.includes("model: callGeminiJson,"));
  assert(src.includes("aiPaused: async () => !(await featureFlagEnabled(adminClient, HEALING_AI_FLAG)),"));
  assert(src.includes("victimisationOn: () => featureFlagEnabled(adminClient, DRAFT_SAFETY_CONTENT_FLAG),"));
  assert(src.includes("return await handlePostMortem(userClient, adminClient, user, journey_id, deps);"));
  assert(!src.includes("generate("), "no provider call left in index.ts");
});

// Batch 2 additions (Spec 1 W9e; W9 B7 I-3): the user-scoping of every read
// and write is pinned, and a missing row reaches nothing.

Deno.test("a journey read that answers no row and no error answers 404, with nothing else read", async () => {
  const admin = fakeClient();
  const spy = spyDeps();
  const user = userWith(null);
  const res = await handlePostMortem(user.client, admin.client, U, "j1", spy.deps);
  assertEquals(res.status, 404);
  assertEquals(user.calls.map((c) => c.table), ["healing_journeys"]);
  assertEquals(admin.calls.length, 0);
  assertEquals(spy.prompts.length, 0);
});

Deno.test("every read and write is the caller's own: profile, ending snapshot, the relationship's non-safety patterns, cache, job", async () => {
  const user = userWith(journey({ relationship_id: "r1" }));
  const admin = fakeClient((call) =>
    call.table === "patterns" ? { data: [{ pattern_type: "withdrawal" }], error: null } : { data: null, error: null }
  );
  const spy = spyDeps();
  const res = await handlePostMortem(user.client, admin.client, U, "j1", spy.deps);
  assertEquals((await res.json()).status, "completed");
  assertEquals(user.calls.map((c) => c.table), ["healing_journeys", "psych_profiles"]);
  assertEquals(user.calls[1].filters, [["eq", "user_id", "u1"]]);
  assertEquals(admin.calls.map((c) => [c.table, c.op]), [
    ["healing_ending_snapshots", "select"],
    ["patterns", "select"],
    ["healing_generation_jobs", "select"],
    ["healing_generation_jobs", "upsert"],
  ]);
  assertEquals(admin.calls[0].filters, [["eq", "user_id", "u1"], ["eq", "relationship_id", "r1"]]);
  // patterns has no user_id: it is the relationship's, and the relationship
  // is the one on the caller's own journey (read through RLS).
  assertEquals(admin.calls[1].filters, [["eq", "relationship_id", "r1"], ["neq", "severity", "safety"], ["limit", "", 6]]);
  const cache = admin.calls[2].filters;
  assertEquals(cache.length, 5);
  assertEquals(cache.slice(0, 3), [["eq", "user_id", "u1"], ["eq", "journey_id", "j1"], ["eq", "stage", "post_mortem"]]);
  assertEquals(cache[4], ["eq", "status", "completed"]);
  assert(spy.prompts[0].includes("withdrawal"));
  const job = admin.calls[3].payload as Record<string, unknown>;
  assertEquals([job.user_id, job.journey_id, job.stage], ["u1", "j1", "post_mortem"]);
});

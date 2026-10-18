// Spec 8 (F15 (1), row 8; research 05 P0-11; plan review I14, I18): the
// adversarial Verdict suite. A model output that blames, names a partner,
// hands down a verdict, leaks safety context, blames a third party or cites
// evidence that does not exist is never published; too little data never
// reaches the model; stonewalling and contempt are not evidence while their
// flag is off.
import { assertEquals, assertRejects } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { buildEvidence, processJob, runVerdict, validateModelOutput } from "./index.ts";

const pulse = (id: string, delta = -6) => ({
  id,
  computed_at: "2026-10-01T00:00:00Z",
  overall_score: 75,
  communication: 70,
  connection: 70,
  conflict_health: 60,
  alignment: 60,
  delta_vs_previous: { connection: delta },
  data_confidence: "medium",
});

function context(overrides: Record<string, unknown> = {}) {
  const pulseHistory = [pulse("p1"), pulse("p2"), pulse("p3")];
  const sessions = [1, 2, 3].map((i) => ({ id: `s${i}`, ended_at: "2026-10-02T00:00:00Z", message_count: 10 }));
  const evidence = buildEvidence({ pulseHistory, patterns: [], sessions, timeline: [], gameInsights: [], hostilitySignals: false });
  return {
    relationship: { id: "r1", user_a: "a", user_b: "b" },
    pulseHistory,
    patterns: [],
    sessions,
    timeline: [],
    gameInsights: [],
    sharedProfiles: [],
    metadata: { eligible_session_count: 5 },
    partnerNames: ["Ama", "Kofi"],
    evidence,
    ...overrides,
  };
}

function goodOutput(ids: string[]) {
  return {
    headline: "A steady month with room to reconnect",
    strengths: [{ title: "Connection", body: "Connection held up across the month.", evidence_ids: [ids[0]] }],
    watch_areas: [{ title: "A dip", body: "Connection dipped in recent weeks.", evidence_ids: [ids[1]] }],
    one_action: "Plan one unhurried evening together.",
    one_action_evidence_ids: [ids[0]],
    patterns_referenced: [],
  };
}

const ids = (c: ReturnType<typeof context>) => c.evidence.map((e: { evidence_id: string }) => e.evidence_id);

Deno.test("a well-formed, sourced output is published", async () => {
  const c = context();
  const out = await runVerdict(c, { callGemini: () => Promise.resolve(goodOutput(ids(c))) });
  assertEquals(out.headline, "A steady month with room to reconnect");
});

const attacks: Array<[string, (o: ReturnType<typeof goodOutput>) => void]> = [
  ["blame", (o) => (o.watch_areas[0].body = "Your partner always shuts down when things get hard.")],
  ["named attribution", (o) => (o.watch_areas[0].body = "Kofi tends to withdraw after an argument.")],
  ["named attribution, lower case", (o) => (o.strengths[0].body = "ama keeps the peace for both of you.")],
  ["verdict language", (o) => (o.headline = "Your relationship is in trouble")],
  ["a decision for them", (o) => (o.one_action = "You should leave if this keeps happening.")],
  ["diagnosis", (o) => (o.watch_areas[0].body = "This looks like a toxic cycle.")],
  ["safety leakage", (o) => (o.watch_areas[0].body = "A safety check suggests one of you feels unsafe.")],
  ["abuse wording", (o) => (o.watch_areas[0].body = "Some messages read as abusive.")],
  ["self-harm leakage", (o) => (o.watch_areas[0].body = "There were signs of self-harm this month.")],
  ["third-party attribution", (o) => (o.watch_areas[0].body = "Your mother is always the problem here.")],
  ["fabricated evidence id", (o) => (o.watch_areas[0].evidence_ids = ["pattern:made-up"])],
  ["no evidence ids", (o) => (o.strengths[0].evidence_ids = [])],
  ["unsourced action", (o) => (o.one_action_evidence_ids = [])],
  ["fabricated action source", (o) => (o.one_action_evidence_ids = ["session:nope"])],
  ["extra key", (o) => ((o as Record<string, unknown>).diagnosis = "x")],
];

for (const [name, mutate] of attacks) {
  Deno.test(`refused: ${name}`, async () => {
    const c = context();
    const out = goodOutput(ids(c));
    mutate(out);
    await assertRejects(() => runVerdict(c, { callGemini: () => Promise.resolve(out) }));
  });
}

Deno.test("too little data never reaches the model (degrades to not enough data)", async () => {
  let called = 0;
  const thin = context({ pulseHistory: [pulse("p1")] });
  await assertRejects(
    () => runVerdict(thin, { callGemini: () => (called++, Promise.resolve(goodOutput(ids(thin)))) }),
    Error,
    "not_enough_pulse_data",
  );
  // Nothing to watch: no pattern, no conflict, no drop.
  const flat = [pulse("p1", 0), pulse("p2", 0), pulse("p3", 0)];
  const calm = context({
    pulseHistory: flat,
    evidence: buildEvidence({ pulseHistory: flat, patterns: [], sessions: [], timeline: [], gameInsights: [], hostilitySignals: false }),
  });
  await assertRejects(
    () => runVerdict(calm, { callGemini: () => (called++, Promise.resolve(goodOutput(ids(calm)))) }),
    Error,
    "insufficient_evidence",
  );
  assertEquals(called, 0);
});

Deno.test("a model that returns nothing publishes nothing", async () => {
  const c = context();
  await assertRejects(() => runVerdict(c, { callGemini: () => Promise.resolve(null) }));
});

Deno.test("stonewalling and contempt are not evidence while their flag is off", () => {
  const patterns = [
    { id: "x1", pattern_type: "stonewalling", severity: "watch", occurrence_count: 4, last_seen_at: "2026-10-01" },
    { id: "x2", pattern_type: "contempt_in_conflict", severity: "act", occurrence_count: 2, last_seen_at: "2026-10-01" },
    { id: "x3", pattern_type: "character_attack", severity: "watch", occurrence_count: 2, last_seen_at: "2026-10-01" },
    { id: "x4", pattern_type: "pursue_withdraw", severity: "watch", occurrence_count: 3, last_seen_at: "2026-10-01" },
  ];
  const off = buildEvidence({ pulseHistory: [], patterns, sessions: [], timeline: [], gameInsights: [], hostilitySignals: false });
  assertEquals(off.map((e: { evidence_id: string }) => e.evidence_id), ["pattern:x4"]);
  const on = buildEvidence({ pulseHistory: [], patterns, sessions: [], timeline: [], gameInsights: [], hostilitySignals: true });
  assertEquals(on.length, 4);
});

Deno.test("validateModelOutput holds even without the provider's own filter", () => {
  const c = context();
  const out = goodOutput(ids(c));
  out.watch_areas[0].body = "Your partner never listens.";
  let threw = false;
  try {
    validateModelOutput(out, c.evidence, c.partnerNames);
  } catch {
    threw = true;
  }
  assertEquals(threw, true);
});

Deno.test("a queued job for a suppressed couple is cancelled before any read", async () => {
  const src = await Deno.readTextFile(new URL("./index.ts", import.meta.url));
  const body = src.slice(src.indexOf("async function processJob"));
  const gate = body.indexOf("relationshipAiSuppression(");
  if (gate < 0) throw new Error("processJob does not ask about suppression");
  if (gate > body.indexOf("buildVerdictContext(")) throw new Error("suppression is checked after the reads");
  if (!body.slice(gate, gate + 600).includes('"cancelled"')) throw new Error("a suppressed job is not cancelled");
});

// Final review I-1: a suppression answer that cannot be read leaves the job
// queued for the next run; only a definite yes cancels it.
Deno.test("an unreadable suppression answer leaves the job queued", async () => {
  const touched: string[] = [];
  const client = {
    rpc: () => Promise.resolve({ data: null, error: { message: "db down" } }),
    from: (t: string) => {
      touched.push(t);
      throw new Error("touched " + t);
    },
  };
  const result = await processJob(client, { id: "j1", relationship_id: "r1", attempt_count: 0 });
  assertEquals(result, { job_id: "j1", status: "deferred" });
  assertEquals(touched, []);
});

Deno.test("a definite yes cancels the job", async () => {
  const updates: unknown[] = [];
  const builder = {
    update: (v: unknown) => (updates.push(v), builder),
    eq: () => builder,
    in: () => Promise.resolve({ error: null }),
  };
  const client = {
    rpc: () => Promise.resolve({ data: true, error: null }),
    from: () => builder,
  };
  const result = await processJob(client, { id: "j1", relationship_id: "r1", attempt_count: 0 });
  assertEquals(result, { job_id: "j1", status: "suppressed" });
  assertEquals(updates, [{ status: "cancelled", last_error: null }]);
});

// Final review m-3: only the service role drains the queue; a member may
// only nudge their own couple's job.
Deno.test("who may run generate-verdict", async () => {
  const { resolveVerdictScope } = await import("./index.ts");
  const deps = {
    isServiceToken: (t: string) => t === "service",
    userIdFor: (t: string) => Promise.resolve(t === "member" || t === "stranger" ? t : null),
    isMember: (u: string, rel: string) => Promise.resolve(u === "member" && rel === "r1"),
  };
  assertEquals(await resolveVerdictScope("service", {}, deps), { ok: true, scope: {} });
  assertEquals(
    await resolveVerdictScope("member", { relationship_id: "r1", job_id: "j9" }, deps),
    { ok: true, scope: { relationshipId: "r1" } },
  );
  assertEquals(await resolveVerdictScope("member", {}, deps), { ok: false, status: 400 });
  assertEquals(await resolveVerdictScope("stranger", { relationship_id: "r1" }, deps), { ok: false, status: 403 });
  assertEquals(await resolveVerdictScope("", { relationship_id: "r1" }, deps), { ok: false, status: 401 });
  assertEquals(await resolveVerdictScope("garbage", { relationship_id: "r1" }, deps), { ok: false, status: 401 });
});

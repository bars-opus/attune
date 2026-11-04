// Spec 1 W9c (spec 4.5, 7.2, 7.4): the journal's crisis check runs first.
// With a spy on the provider: a matching entry never reaches it (whatever
// private_safety_check says), the check runs before the cache read, nothing
// about the match is written (the entry's earlier reflection is removed),
// one support_card_shown:journal count; the [DRAFT] victimisation list only
// with private_safety_check on; get_patterns leaves matched entries out and
// answers support_offered when the newest entry matches; an unreadable
// journal never reaches the provider.
import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  DELETE_ATTEMPTS,
  foldTypography,
  handleAnalyseEntry,
  handleGetPatterns,
  type JournalDeps,
  type JournalModel,
  SUPPORT_CARD_METRIC,
} from "./journal_handlers.ts";
import { JOURNAL_SELF_HARM_PENDING } from "./journal_self_harm_pending.ts";

type Call = { table: string; op: string; filters: Array<[string, string, unknown]> };

/// A supabase-js-shaped fake: every chain is recorded; [answer] decides what
/// a finished chain resolves to.
function fakeClient(answer: (call: Call) => { data: unknown; error: unknown }) {
  const calls: Call[] = [];
  const rpcs: Array<{ fn: string; params: Record<string, unknown> }> = [];
  function chain(call: Call) {
    const done = () => Promise.resolve(answer(call));
    const c: Record<string, unknown> = {
      select(_cols: string) {
        call.op = call.op === "delete" ? "delete" : "select";
        return c;
      },
      delete() {
        call.op = "delete";
        return c;
      },
      eq(col: string, v: unknown) {
        call.filters.push(["eq", col, v]);
        return c;
      },
      is(col: string, v: unknown) {
        call.filters.push(["is", col, v]);
        return c;
      },
      in(col: string, v: unknown) {
        call.filters.push(["in", col, v]);
        return c;
      },
      order(col: string, o: unknown) {
        call.filters.push(["order", col, o]);
        return c;
      },
      limit(n: number) {
        call.filters.push(["limit", "", n]);
        return c;
      },
      single: done,
      maybeSingle: done,
      then(resolve: (v: unknown) => unknown, reject: (e: unknown) => unknown) {
        return done().then(resolve, reject);
      },
    };
    return c;
  }
  return {
    calls,
    rpcs,
    client: {
      from(table: string) {
        const call: Call = { table, op: "", filters: [] };
        calls.push(call);
        return chain(call);
      },
      rpc(fn: string, params: Record<string, unknown>) {
        rpcs.push({ fn, params });
        return Promise.resolve({ data: null, error: null });
      },
    },
  };
}

function spyDeps(opts: { victimisation?: boolean; paused?: boolean; reply?: Record<string, unknown> | null } = {}) {
  const prompts: string[] = [];
  const metrics: string[] = [];
  const model: JournalModel = (params) => {
    prompts.push(params.userPrompt);
    return Promise.resolve(opts.reply === undefined ? { tone: "settled", observation: "You sound settled.", confidence: "medium" } : opts.reply);
  };
  const deps: JournalDeps = {
    model,
    runtimePatterns: [/\b(toxic|narcissist|codependent|disorder|broken)\b/i],
    insightsPaused: () => Promise.resolve(opts.paused ?? false),
    victimisationOn: () => Promise.resolve(opts.victimisation ?? false),
    bumpMetric: (key) => {
      metrics.push(key);
      return Promise.resolve();
    },
  };
  return { deps, prompts, metrics };
}

const LONG = "Work was long today and I kept thinking about the weekend plans we made, the market and the walk by the lagoon.";
const CRISIS = "I want to kill myself";
const VICTIM = "he hit me last night and I don't know what to do";

function entryUser(entry: { title?: string | null; content: string }) {
  return fakeClient((call) =>
    call.table === "reflection_journal_entries"
      ? { data: { id: "e1", title: entry.title ?? null, content: entry.content }, error: null }
      : { data: null, error: null }
  );
}

Deno.test("a crisis entry never reaches the provider, or the cache, and stores nothing", async () => {
  for (const victimisation of [true, false]) {
    for (const entry of [{ content: CRISIS }, { title: CRISIS, content: LONG }]) {
      const user = entryUser(entry);
      const admin = fakeClient(() => ({ data: null, error: null }));
      const spy = spyDeps({ victimisation });
      const res = await handleAnalyseEntry(user.client, admin.client, "u1", "e1", spy.deps);
      assertEquals(await res.json(), { status: "support_offered" });
      assertEquals(spy.prompts.length, 0, "the provider was called");
      assertEquals(admin.rpcs.length, 0, "something was written");
      assertEquals(admin.calls.filter((c) => c.op === "select").length, 0, "the cache was read");
      // Only the entry's earlier reflection is removed.
      assertEquals(admin.calls.map((c) => [c.table, c.op]), [["reflection_journal_analysis", "delete"]]);
      assertEquals(admin.calls[0].filters, [["eq", "entry_id", "e1"], ["eq", "user_id", "u1"]]);
      assertEquals(spy.metrics, [SUPPORT_CARD_METRIC]);
    }
  }
});

Deno.test("the [DRAFT] victimisation list runs only with private_safety_check on", async () => {
  const on = spyDeps({ victimisation: true });
  const resOn = await handleAnalyseEntry(entryUser({ content: VICTIM }).client, fakeClient(() => ({ data: null, error: null })).client, "u1", "e1", on.deps);
  assertEquals((await resOn.json()).status, "support_offered");
  assertEquals(on.prompts.length, 0);

  const off = spyDeps({ victimisation: false });
  const resOff = await handleAnalyseEntry(
    entryUser({ content: `${VICTIM} ${LONG}` }).client,
    fakeClient(() => ({ data: null, error: null })).client,
    "u1",
    "e1",
    off.deps,
  );
  assertEquals((await resOff.json()).status, "completed");
  assertEquals(off.prompts.length, 1);
});

Deno.test("an ordinary entry reads the cache first, then the provider, as before", async () => {
  const admin = fakeClient(() => ({ data: null, error: null }));
  const spy = spyDeps();
  const res = await handleAnalyseEntry(entryUser({ content: LONG }).client, admin.client, "u1", "e1", spy.deps);
  assertEquals((await res.json()).status, "completed");
  assertEquals(admin.calls[0].table, "reflection_journal_analysis");
  assertEquals(admin.calls[0].op, "select");
  assertEquals(spy.prompts.length, 1);
  assertEquals(admin.rpcs.map((r) => r.fn), ["upsert_journal_analysis"]);
  assertEquals(spy.metrics, []);
});

/// get_patterns' admin client: the newest entry, the analyses, and the
/// entries they belong to.
function patternsAdmin(opts: {
  newest: { id: string; title?: string | null; content: string } | null;
  analyses: Array<{ entry_id: string; observation: string }>;
  entries: Array<{ id: string; title?: string | null; content: string }>;
  entriesError?: boolean;
}) {
  return fakeClient((call) => {
    if (call.table === "reflection_journal_entries" && call.filters.some(([k]) => k === "in")) {
      return opts.entriesError ? { data: null, error: { message: "down" } } : { data: opts.entries, error: null };
    }
    if (call.table === "reflection_journal_entries") return { data: opts.newest, error: null };
    return {
      data: opts.analyses.map((a, i) => ({ ...a, tone: "settled", created_at: `2026-11-0${9 - i}T10:00:00Z` })),
      error: null,
    };
  });
}

Deno.test("get_patterns: the newest entry matches, so support and no provider call", async () => {
  const admin = patternsAdmin({ newest: { id: "e9", content: CRISIS }, analyses: [], entries: [] });
  const spy = spyDeps();
  const res = await handleGetPatterns(admin.client, "u1", spy.deps);
  assertEquals(await res.json(), { status: "support_offered" });
  assertEquals(spy.prompts.length, 0);
  assertEquals(spy.metrics, [SUPPORT_CARD_METRIC]);
  assertEquals(admin.calls.filter((c) => c.table === "reflection_journal_analysis").length, 0);
});

Deno.test("get_patterns leaves matched entries out of what the provider sees", async () => {
  const admin = patternsAdmin({
    newest: { id: "e1", content: LONG },
    analyses: [
      { entry_id: "e1", observation: "obs one" },
      { entry_id: "e2", observation: "obs two crisis" },
      { entry_id: "e3", observation: "obs three" },
      { entry_id: "e4", observation: "obs four" },
    ],
    entries: [
      { id: "e1", content: LONG },
      { id: "e2", title: CRISIS, content: LONG },
      { id: "e3", content: LONG },
      { id: "e4", content: LONG },
    ],
  });
  const spy = spyDeps({ reply: { summary: "A summary." } });
  const res = await handleGetPatterns(admin.client, "u1", spy.deps);
  const body = await res.json();
  assertEquals(body, { status: "completed", summary: "A summary.", entry_count: 3 });
  assertEquals(spy.prompts.length, 1);
  assert(!spy.prompts[0].includes("obs two crisis"), "a matched entry reached the provider");
  assert(!spy.prompts[0].includes("entry_id"), "entry ids reached the provider");
});

Deno.test("get_patterns: too few left after leaving matches out", async () => {
  const admin = patternsAdmin({
    newest: { id: "e1", content: LONG },
    analyses: [
      { entry_id: "e1", observation: "a" },
      { entry_id: "e2", observation: "b" },
      { entry_id: "e3", observation: "c" },
    ],
    entries: [{ id: "e1", content: LONG }, { id: "e2", content: CRISIS }, { id: "e3", content: LONG }],
  });
  const spy = spyDeps();
  const res = await handleGetPatterns(admin.client, "u1", spy.deps);
  assertEquals(await res.json(), { status: "insufficient_evidence", summary: null, entry_count: 2 });
  assertEquals(spy.prompts.length, 0);
});

Deno.test("get_patterns: an unreadable journal never reaches the provider", async () => {
  const admin = patternsAdmin({
    newest: { id: "e1", content: LONG },
    analyses: [{ entry_id: "e1", observation: "a" }, { entry_id: "e2", observation: "b" }, { entry_id: "e3", observation: "c" }],
    entries: [],
    entriesError: true,
  });
  const spy = spyDeps();
  const res = await handleGetPatterns(admin.client, "u1", spy.deps);
  assertEquals(res.status, 503);
  assertEquals(spy.prompts.length, 0);

  const down = fakeClient(() => ({ data: null, error: { message: "down" } }));
  const res2 = await handleGetPatterns(down.client, "u1", spy.deps);
  assertEquals(res2.status, 503);
  assertEquals(spy.prompts.length, 0);
});

Deno.test("index.ts wires the live provider, the flag and the count", async () => {
  const index = await Deno.readTextFile(new URL("./index.ts", import.meta.url));
  assert(index.includes("model: callGeminiJson,"), "the provider is not callGeminiJson");
  assert(index.includes("runtimePatterns: RUNTIME_PATTERNS,"), "the output filter is not index.ts's RUNTIME_PATTERNS");
  assert(index.includes("featureFlagEnabled(adminClient, DRAFT_SAFETY_CONTENT_FLAG)"), "private_safety_check is not read");
  assert(index.includes('adminClient.rpc("bump_metric_server", { p_key: key })'), "the count does not go through bump_metric_server");
  assert(index.includes("insightsPaused: () => journalInsightsPaused(adminClient),"), "the W1c pause is not injected");
  assert(index.includes("handleAnalyseEntry(userClient, adminClient,"), "the entry is not read through the caller's own client");
  // Fix round 1 ruling: the crisis check runs before the W1c pause, so the
  // actions are dispatched before index.ts answers paused.
  const pause = index.indexOf("if (await journalInsightsPaused(adminClient))");
  assert(pause > index.indexOf('body.action === "analyse_entry"'), "index.ts answers paused before the crisis check");
});

// Batch 7 fail-safe rulings: whatever throws while deciding whether an entry
// is a crisis, the writer is offered support and nothing reaches the provider.
const THROWS = { toString(): string { throw new Error("unreadable"); } } as unknown as string;

function throwingFlagDeps() {
  const spy = spyDeps();
  spy.deps.victimisationOn = () => Promise.reject(new Error("flag read failed"));
  return spy;
}

Deno.test("fail safe: a flag read that throws offers support, never the provider", async () => {
  const spy = throwingFlagDeps();
  const admin = fakeClient(() => ({ data: null, error: null }));
  const res = await handleAnalyseEntry(entryUser({ content: LONG }).client, admin.client, "u1", "e1", spy.deps);
  assertEquals(await res.json(), { status: "support_offered" });
  assertEquals(spy.prompts.length, 0, "the provider was called");
  assertEquals(admin.rpcs.length, 0, "something was written");
  assertEquals(spy.metrics, [SUPPORT_CARD_METRIC]);

  const p = throwingFlagDeps();
  const patterns = patternsAdmin({
    newest: { id: "e1", content: LONG },
    analyses: [{ entry_id: "e1", observation: "a" }, { entry_id: "e2", observation: "b" }, { entry_id: "e3", observation: "c" }],
    entries: [{ id: "e1", content: LONG }, { id: "e2", content: LONG }, { id: "e3", content: LONG }],
  });
  const res2 = await handleGetPatterns(patterns.client, "u1", p.deps);
  assertEquals(await res2.json(), { status: "support_offered" });
  assertEquals(p.prompts.length, 0, "the provider was called");
});

Deno.test("fail safe: a detector that throws offers support, never the provider", async () => {
  const spy = spyDeps();
  const admin = fakeClient(() => ({ data: null, error: null }));
  const res = await handleAnalyseEntry(entryUser({ content: THROWS }).client, admin.client, "u1", "e1", spy.deps);
  assertEquals(await res.json(), { status: "support_offered" });
  assertEquals(spy.prompts.length, 0, "the provider was called");
  assertEquals(admin.calls.filter((c) => c.op === "select").length, 0, "the cache was read");

  const newest = spyDeps();
  const res2 = await handleGetPatterns(patternsAdmin({ newest: { id: "e1", content: THROWS }, analyses: [], entries: [] }).client, "u1", newest.deps);
  assertEquals(await res2.json(), { status: "support_offered" });
  assertEquals(newest.prompts.length, 0);

  // An older entry that cannot be checked is left out, like a match.
  const older = spyDeps({ reply: { summary: "A summary." } });
  const res3 = await handleGetPatterns(
    patternsAdmin({
      newest: { id: "e1", content: LONG },
      analyses: [
        { entry_id: "e1", observation: "obs one" },
        { entry_id: "e2", observation: "obs two unreadable" },
        { entry_id: "e3", observation: "obs three" },
        { entry_id: "e4", observation: "obs four" },
      ],
      entries: [{ id: "e1", content: LONG }, { id: "e2", content: THROWS }, { id: "e3", content: LONG }, { id: "e4", content: LONG }],
    }).client,
    "u1",
    older.deps,
  );
  assertEquals(await res3.json(), { status: "completed", summary: "A summary.", entry_count: 3 });
  assert(!older.prompts[0].includes("obs two unreadable"), "an unchecked entry reached the provider");
});

Deno.test("fail safe: a failed reflection delete or count still offers support", async () => {
  const admin = fakeClient((call) => {
    if (call.op === "delete") throw new Error("delete failed");
    return { data: null, error: null };
  });
  const spy = spyDeps();
  spy.deps.bumpMetric = () => Promise.reject(new Error("count failed"));
  const res = await handleAnalyseEntry(entryUser({ content: CRISIS }).client, admin.client, "u1", "e1", spy.deps);
  assertEquals(res.status, 200);
  assertEquals(await res.json(), { status: "support_offered" });
  assertEquals(spy.prompts.length, 0);
});

Deno.test("get_patterns: the [DRAFT] victimisation list runs only with private_safety_check on", async () => {
  const admin = () =>
    patternsAdmin({
      newest: { id: "e1", content: `${VICTIM} ${LONG}` },
      analyses: [{ entry_id: "e1", observation: "a" }, { entry_id: "e2", observation: "b" }, { entry_id: "e3", observation: "c" }],
      entries: [{ id: "e1", content: `${VICTIM} ${LONG}` }, { id: "e2", content: LONG }, { id: "e3", content: LONG }],
    });
  const on = spyDeps({ victimisation: true });
  assertEquals(await (await handleGetPatterns(admin().client, "u1", on.deps)).json(), { status: "support_offered" });
  assertEquals(on.prompts.length, 0);

  const off = spyDeps({ victimisation: false, reply: { summary: "A summary." } });
  assertEquals(await (await handleGetPatterns(admin().client, "u1", off.deps)).json(), {
    status: "completed",
    summary: "A summary.",
    entry_count: 3,
  });
  assertEquals(off.prompts.length, 1);
});

Deno.test("get_patterns: an analysis whose entry was not read back is left out", async () => {
  const spy = spyDeps({ reply: { summary: "A summary." } });
  const res = await handleGetPatterns(
    patternsAdmin({
      newest: { id: "e1", content: LONG },
      analyses: [
        { entry_id: "e1", observation: "obs one" },
        { entry_id: "e2", observation: "obs two" },
        { entry_id: "e3", observation: "obs three" },
        { entry_id: "e4", observation: "obs four unseen" },
      ],
      entries: [{ id: "e1", content: LONG }, { id: "e2", content: LONG }, { id: "e3", content: LONG }],
    }).client,
    "u1",
    spy.deps,
  );
  assertEquals(await res.json(), { status: "completed", summary: "A summary.", entry_count: 3 });
  assert(!spy.prompts[0].includes("obs four unseen"), "an unchecked entry reached the provider");
});

Deno.test("nothing about a match is logged", async () => {
  const logged: unknown[] = [];
  const names = ["log", "info", "warn", "error", "debug", "trace"] as const;
  const saved = names.map((n) => console[n]);
  for (const n of names) console[n] = (...a: unknown[]) => void logged.push(a);
  try {
    const spy = spyDeps({ victimisation: true });
    await handleAnalyseEntry(entryUser({ title: CRISIS, content: VICTIM }).client, fakeClient(() => ({ data: null, error: null })).client, "u1", "e1", spy.deps);
    await handleGetPatterns(patternsAdmin({ newest: { id: "e9", content: CRISIS }, analyses: [], entries: [] }).client, "u1", spy.deps);
    await handleGetPatterns(patternsAdmin({ newest: { id: "e9", content: THROWS }, analyses: [], entries: [] }).client, "u1", throwingFlagDeps().deps);
  } finally {
    names.forEach((n, i) => (console[n] = saved[i]));
  }
  assertEquals(logged, []);
});

// ---- Fix round 1 (batch-7-review.md) ----

Deno.test("I-1: a delete that answers {error} is retried, a bounded number of times, and support is still offered", async () => {
  for (const failures of [1, DELETE_ATTEMPTS, DELETE_ATTEMPTS + 5]) {
    let deletes = 0;
    const admin = fakeClient((call) => {
      if (call.op === "delete") {
        deletes++;
        return deletes <= failures ? { data: null, error: { message: "down" } } : { data: null, error: null };
      }
      return { data: null, error: null };
    });
    const spy = spyDeps();
    const res = await handleAnalyseEntry(entryUser({ content: CRISIS }).client, admin.client, "u1", "e1", spy.deps);
    assertEquals(await res.json(), { status: "support_offered" });
    assertEquals(deletes, Math.min(failures + 1, DELETE_ATTEMPTS), `delete attempts after ${failures} failures`);
    assertEquals(spy.prompts.length, 0);
    assertEquals(spy.metrics, [SUPPORT_CARD_METRIC]);
  }
  assert(DELETE_ATTEMPTS >= 2 && DELETE_ATTEMPTS <= 5, "the retry must be bounded");
  // A first delete that succeeds is not repeated.
  let deletes = 0;
  const once = fakeClient((call) => {
    if (call.op === "delete") deletes++;
    return { data: null, error: null };
  });
  await handleAnalyseEntry(entryUser({ content: CRISIS }).client, once.client, "u1", "e1", spyDeps().deps);
  assertEquals(deletes, 1);
});

const APOSTROPHES = ["\u2019", "\u2018", "\u201B", "\u02BB", "\u02BC", "\uFF07", "`", "\u00B4", "\u2032"];

Deno.test("I-2: typographic apostrophes and quotes are folded before the check", async () => {
  const texts: Array<[string, boolean]> = [];
  for (const a of APOSTROPHES) {
    texts.push([`I don${a}t want to be here anymore`, false]);
    texts.push([`I${a}m scared of him`, true]);
    texts.push([`he won${a}t let me leave the house`, true]);
  }
  texts.push(["\u201CI want to kill myself\u201D", false]);
  texts.push(["\u201EI don\u2019t want to be here anymore\u201F", false]);
  texts.push(["\uFF02I don\u2019t want to be here anymore\uFF02", false]);
  for (const [text, victimisation] of texts) {
    const spy = spyDeps({ victimisation });
    const res = await handleAnalyseEntry(entryUser({ content: `${LONG} ${text}` }).client, fakeClient(() => ({ data: null, error: null })).client, "u1", "e1", spy.deps);
    assertEquals((await res.json()).status, "support_offered", JSON.stringify(text));
    assertEquals(spy.prompts.length, 0);
  }
});

Deno.test("I-2: the fold itself, apostrophes to ' and double quotes to \"", () => {
  for (const a of APOSTROPHES) assertEquals(foldTypography(`don${a}t`), "don't");
  for (const q of ["\u201C", "\u201D", "\u201E", "\u201F", "\u2033", "\uFF02", "\u00AB", "\u00BB"]) {
    assertEquals(foldTypography(`${q}hi${q}`), '"hi"');
  }
  assertEquals(foldTypography("plain 'text' \"here\""), "plain 'text' \"here\"");
});

Deno.test("M-1: zero-width and invisible characters neither split nor join a phrase away", async () => {
  for (const zw of ["\u200B", "\u200C", "\u200D", "\u2060", "\uFEFF", "\u00AD"]) {
    for (
      const text of [
        `I want to kill${zw}myself`,
        `I want to ki${zw}ll myself`,
        `I want to kill ${zw}myself`,
        `I want to end${zw}my life`,
        `there is no reason${zw}to go on`,
      ]
    ) {
      const spy = spyDeps();
      const res = await handleAnalyseEntry(entryUser({ content: `${LONG} ${text}` }).client, fakeClient(() => ({ data: null, error: null })).client, "u1", "e1", spy.deps);
      assertEquals((await res.json()).status, "support_offered", JSON.stringify(text));
      assertEquals(spy.prompts.length, 0);
    }
  }
});

Deno.test("I-5: the pending-review self-harm phrases always run, whatever private_safety_check says", async () => {
  const samples = [
    "i want to die",
    "I wanna die",
    "I feel suicidal",
    "I keep thinking about suicide",
    "thinking about ending my life",
    "I want to take my own life",
    "I've been cutting myself",
    "I cut myself again",
    "I keep hurting myself",
    "self harm",
    "self-harm",
    "I don't want to live anymore",
    "I dont want to live anymore",
    "I can't go on",
    "I cant go on like this",
    "I just want it to end",
    "kill my self",
    "killmyself",
    "I dont want to be here anymore",
  ];
  for (const victimisation of [false, true]) {
    for (const text of samples) {
      const spy = spyDeps({ victimisation });
      const res = await handleAnalyseEntry(entryUser({ title: text, content: LONG }).client, fakeClient(() => ({ data: null, error: null })).client, "u1", "e1", spy.deps);
      assertEquals((await res.json()).status, "support_offered", text);
      assertEquals(spy.prompts.length, 0);
    }
  }
  // The same list leaves a matching entry out of Patterns.
  const spy = spyDeps({ reply: { summary: "A summary." } });
  const res = await handleGetPatterns(
    patternsAdmin({
      newest: { id: "e1", content: LONG },
      analyses: [
        { entry_id: "e1", observation: "a" },
        { entry_id: "e2", observation: "obs suicidal" },
        { entry_id: "e3", observation: "c" },
        { entry_id: "e4", observation: "d" },
      ],
      entries: [{ id: "e1", content: LONG }, { id: "e2", content: "I feel suicidal" }, { id: "e3", content: LONG }, { id: "e4", content: LONG }],
    }).client,
    "u1",
    spy.deps,
  );
  assertEquals((await res.json()).entry_count, 3);
  assert(!spy.prompts[0].includes("obs suicidal"));
});

Deno.test("I-5: the pending list is marked for clinician review and written in the detector's form", () => {
  assert(JOURNAL_SELF_HARM_PENDING.review_status.startsWith("PENDING CLINICIAN REVIEW"));
  for (const p of ["want to die", "suicidal", "cutting myself"]) {
    assert((JOURNAL_SELF_HARM_PENDING.phrases as readonly string[]).includes(p), p);
  }
  for (const p of JOURNAL_SELF_HARM_PENDING.phrases) {
    assert(/^[a-z0-9' ]+$/.test(p) && p.trim() === p && !p.includes("  "), `not in normalised form: ${p}`);
  }
});

// W9 final I-2: obvious crisis phrasings the first pending list missed
// (overdose, "end it all", "nobody would miss me", ...). One sample per
// added phrase, so dropping any one of them turns this red.
const W9_FINAL_I2_SAMPLES: Array<[string, string]> = [
  ["end it all", "im going to end it all"],
  ["ending it all", "I keep thinking about ending it all"],
  ["took all my pills", "I took all my pills tonight"],
  ["take all my pills", "I want to take all my pills"],
  ["taking all my pills", "I'm thinking of taking all my pills"],
  ["overdose", "I'm going to overdose"],
  ["overdosed", "I overdosed last night"],
  ["overdosing", "I keep thinking about overdosing"],
  ["no point living", "there is no point living"],
  ["no point in living", "there's no point in living"],
  ["no reason to live", "I have no reason to live"],
  ["nobody would miss me", "nobody would miss me if I was gone"],
  ["no one would miss me", "no one would miss me"],
  ["burden to everyone", "I feel like a burden to everyone"],
  ["dont want to exist", "i dont want to exist"],
  ["don't want to exist", "I just don't want to exist"],
  ["do not want to exist", "I do not want to exist"],
  ["dont want to be here any more", "I dont want to be here any more"],
  ["don't want to be here any more", "I don't want to be here any more"],
  ["do not want to be here any more", "I do not want to be here any more"],
  ["don't want to be here anymore", "I don't want to be here anymore"],
];

Deno.test("W9 final I-2: the added crisis phrasings answer support_offered and never reach the provider", async () => {
  for (const victimisation of [false, true]) {
    for (const [, text] of W9_FINAL_I2_SAMPLES) {
      const spy = spyDeps({ victimisation });
      const res = await handleAnalyseEntry(entryUser({ content: `${LONG} ${text}` }).client, fakeClient(() => ({ data: null, error: null })).client, "u1", "e1", spy.deps);
      assertEquals((await res.json()).status, "support_offered", text);
      assertEquals(spy.prompts.length, 0, text);
    }
  }
  // Curly apostrophes fold first.
  const spy = spyDeps({});
  const res = await handleAnalyseEntry(entryUser({ title: "I don\u2019t want to exist", content: LONG }).client, fakeClient(() => ({ data: null, error: null })).client, "u1", "e1", spy.deps);
  assertEquals((await res.json()).status, "support_offered");
  assertEquals(spy.prompts.length, 0);
});

Deno.test("W9 final I-2: every added phrase is in the pending list, which stays marked for clinician review", () => {
  assert(JOURNAL_SELF_HARM_PENDING.review_status.startsWith("PENDING CLINICIAN REVIEW"));
  const phrases = JOURNAL_SELF_HARM_PENDING.phrases as readonly string[];
  for (const [p] of W9_FINAL_I2_SAMPLES) assert(phrases.includes(p), p);
  assertEquals(phrases.length, 52);
  assertEquals(new Set(phrases).size, phrases.length, "duplicate phrase");
});

// W9 final re-review N-1: near variants of the I-2 phrases (filler words,
// other verbs, "over-dose"), matched by the pending patterns.
const W9_FINAL_N1_SAMPLES = [
  "I took all of my pills",
  "I swallowed all my pills",
  "I might over-dose",
  "I swallowed all of my tablets tonight",
  "I'm taking all of my pills",
  "I want to take all of my tablets",
  "thinking about an over dose",
  "I over\u2011dosed last year",
  "I feel like a burden to everybody",
  "nobody would even miss me",
  "no one would even miss me",
];

Deno.test("W9 final N-1: near variants of the crisis phrasings answer support_offered", async () => {
  for (const victimisation of [false, true]) {
    for (const text of W9_FINAL_N1_SAMPLES) {
      const spy = spyDeps({ victimisation });
      const res = await handleAnalyseEntry(entryUser({ content: `${LONG} ${text}` }).client, fakeClient(() => ({ data: null, error: null })).client, "u1", "e1", spy.deps);
      assertEquals((await res.json()).status, "support_offered", text);
      assertEquals(spy.prompts.length, 0, text);
    }
  }
});

Deno.test("W9 final N-1: ordinary medicine and dose talk still reaches the reflection", async () => {
  for (const text of ["I took my pills this morning", "I take my tablets with food", "the dose was over the limit, the nurse said"]) {
    const spy = spyDeps({});
    const res = await handleAnalyseEntry(entryUser({ content: `${LONG} ${text}` }).client, fakeClient(() => ({ data: null, error: null })).client, "u1", "e1", spy.deps);
    assertEquals((await res.json()).status, "completed", text);
    assertEquals(spy.prompts.length, 1, text);
  }
});

Deno.test("W9 final N-1: the pending patterns are marked for clinician review", () => {
  assert(JOURNAL_SELF_HARM_PENDING.review_status.startsWith("PENDING CLINICIAN REVIEW"));
  assertEquals(JOURNAL_SELF_HARM_PENDING.patterns.length, 4);
});

Deno.test("I-3: get_patterns only ever reads the caller's own, newest, live entry and own analyses", async () => {
  const admin = patternsAdmin({
    newest: { id: "e1", content: LONG },
    analyses: [{ entry_id: "e1", observation: "a" }, { entry_id: "e2", observation: "b" }, { entry_id: "e3", observation: "c" }],
    entries: [{ id: "e1", content: LONG }, { id: "e2", content: LONG }, { id: "e3", content: LONG }],
  });
  await handleGetPatterns(admin.client, "u1", spyDeps({ reply: { summary: "s" } }).deps);
  const [newest, analyses, entries] = admin.calls;
  assertEquals([newest.table, newest.op], ["reflection_journal_entries", "select"]);
  assertEquals(newest.filters, [
    ["eq", "user_id", "u1"],
    ["is", "deleted_at", null],
    ["order", "created_at", { ascending: false }],
    ["limit", "", 1],
  ]);
  assertEquals(analyses.table, "reflection_journal_analysis");
  assertEquals(analyses.filters.filter(([k, c]) => k === "eq" && c === "user_id"), [["eq", "user_id", "u1"]]);
  assertEquals(entries.table, "reflection_journal_entries");
  assertEquals(entries.filters.filter(([k, c]) => k === "eq" && c === "user_id"), [["eq", "user_id", "u1"]], "M-4");
  assertEquals(entries.filters.filter(([k]) => k === "in"), [["in", "id", ["e1", "e2", "e3"]]]);
});

Deno.test("I-3: analyse_entry reads the entry through the caller's own client, live only", async () => {
  const user = entryUser({ content: LONG });
  const admin = fakeClient(() => ({ data: null, error: null }));
  await handleAnalyseEntry(user.client, admin.client, "u1", "e1", spyDeps().deps);
  assertEquals(user.calls.map((c) => [c.table, c.op]), [["reflection_journal_entries", "select"]]);
  assertEquals(user.calls[0].filters, [["eq", "id", "e1"], ["is", "deleted_at", null]]);
  assertEquals(admin.calls.filter((c) => c.table === "reflection_journal_entries").length, 0);
});

Deno.test("ruling: the crisis check runs before the W1c pause, for both actions", async () => {
  // A match while paused: the old reflection goes, support is offered.
  const admin = fakeClient(() => ({ data: null, error: null }));
  const spy = spyDeps({ paused: true });
  const res = await handleAnalyseEntry(entryUser({ content: CRISIS }).client, admin.client, "u1", "e1", spy.deps);
  assertEquals(await res.json(), { status: "support_offered" });
  assertEquals(admin.calls.map((c) => [c.table, c.op]), [["reflection_journal_analysis", "delete"]]);
  assertEquals(spy.metrics, [SUPPORT_CARD_METRIC]);
  assertEquals(spy.prompts.length, 0);

  const p = spyDeps({ paused: true });
  const pres = await handleGetPatterns(patternsAdmin({ newest: { id: "e9", content: CRISIS }, analyses: [], entries: [] }).client, "u1", p.deps);
  assertEquals(await pres.json(), { status: "support_offered" });
  assertEquals(p.metrics, [SUPPORT_CARD_METRIC]);
});

Deno.test("ruling: no match while paused answers paused, with nothing read from or written to the analyses", async () => {
  const pausedDeps = () => {
    const s = spyDeps({ paused: true });
    return s;
  };
  const throwing = () => {
    const s = spyDeps();
    s.deps.insightsPaused = () => Promise.reject(new Error("flag read failed"));
    return s;
  };
  for (const make of [pausedDeps, throwing]) {
    const admin = fakeClient(() => ({ data: null, error: null }));
    const spy = make();
    const res = await handleAnalyseEntry(entryUser({ content: LONG }).client, admin.client, "u1", "e1", spy.deps);
    assertEquals(await res.json(), { status: "paused" });
    assertEquals(admin.calls, [], "the analyses were touched while paused");
    assertEquals(admin.rpcs, []);
    assertEquals(spy.prompts.length, 0);
    assertEquals(spy.metrics, []);

    // The other answers W1c gave while paused are kept.
    const missing = await handleAnalyseEntry(entryUser({ content: LONG }).client, admin.client, "u1", "", make().deps);
    assertEquals(await missing.json(), { status: "paused" });
    const notFound = fakeClient(() => ({ data: null, error: { message: "no rows" } }));
    const nf = await handleAnalyseEntry(notFound.client, admin.client, "u1", "e1", make().deps);
    assertEquals(await nf.json(), { status: "paused" });

    const padmin = patternsAdmin({
      newest: { id: "e1", content: LONG },
      analyses: [{ entry_id: "e1", observation: "a" }, { entry_id: "e2", observation: "b" }, { entry_id: "e3", observation: "c" }],
      entries: [{ id: "e1", content: LONG }, { id: "e2", content: LONG }, { id: "e3", content: LONG }],
    });
    const ps = make();
    const pres = await handleGetPatterns(padmin.client, "u1", ps.deps);
    assertEquals(await pres.json(), { status: "paused" });
    assertEquals(padmin.calls.filter((c) => c.table === "reflection_journal_analysis"), []);
    assertEquals(ps.prompts.length, 0);
    const down = fakeClient(() => ({ data: null, error: { message: "down" } }));
    assertEquals(await (await handleGetPatterns(down.client, "u1", make().deps)).json(), { status: "paused" });
  }
});

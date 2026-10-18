import { assert, assertEquals } from "https://deno.land/std@0.208.0/assert/mod.ts";
import { processTogetherAi, type TogetherAiDeps } from "./handler.ts";

const REL = "11111111-1111-4111-8111-111111111111";
const REQ = "22222222-2222-4222-8222-222222222222";
const USER = "33333333-3333-4333-8333-333333333333";

type Call = { name: string; params: Record<string, unknown> };

function fakes(opts: {
  flag?: boolean; available?: boolean; quota?: string; claim?: boolean;
  model?: Record<string, unknown> | null;
} = {}) {
  const calls: Call[] = [];
  let modelCalls = 0;
  const rpc = (name: string, params: Record<string, unknown>) => {
    calls.push({ name, params });
    const data = {
      ai_capability_enabled: opts.flag ?? true,
      get_together_ai_status: { available: opts.available ?? true, partner_name: "Kofi" },
      reserve_ai_assistant_quota: [{ outcome: opts.quota ?? "reserved", retry_after_seconds: 3600 }],
      claim_ai_assistant_provider_start: [{ claim_ai_assistant_provider_start: opts.claim ?? true }],
      mark_ai_assistant_usage_outcome: null,
    }[name];
    return Promise.resolve({ data, error: null });
  };
  const deps: TogetherAiDeps = {
    service: { rpc },
    callGemini: () => {
      modelCalls++;
      return Promise.resolve(opts.model === undefined
        ? { title: "Dinner", all_day: false, start_local: "2026-11-07T19:00", end_local: null, with_partner: true, location: null, note: null }
        : opts.model);
    },
  };
  return { deps, calls, client: { rpc }, user: { id: USER }, models: () => modelCalls };
}

const req = (body: Record<string, unknown>) =>
  new Request("http://x/ai-together", { method: "POST", body: JSON.stringify(body) });
const capture = (extra: Record<string, unknown> = {}) =>
  req({ action: "capture", relationship_id: REL, request_id: REQ, text: "dinner Sat 7pm", now_local: "2026-11-02T09:00", ...extra });

Deno.test("happy path: a draft comes back and the usage is marked succeeded", async () => {
  const f = fakes();
  const res = await processTogetherAi(capture(), { client: f.client, user: f.user }, f.deps);
  assertEquals(res.status, 200);
  assertEquals((await res.json()).draft.title, "Dinner");
  const names = f.calls.map((c) => c.name);
  assertEquals(names, ["ai_capability_enabled", "get_together_ai_status", "reserve_ai_assistant_quota",
    "claim_ai_assistant_provider_start", "mark_ai_assistant_usage_outcome"]);
  assertEquals(f.calls.at(-1)!.params.p_outcome, "succeeded");
  assertEquals(f.calls[2].params.p_mode, "assist");
});

Deno.test("flag off: FEATURE_DISABLED before anything else", async () => {
  const f = fakes({ flag: false });
  const res = await processTogetherAi(capture(), { client: f.client, user: f.user }, f.deps);
  assertEquals([res.status, (await res.json()).code], [403, "FEATURE_DISABLED"]);
  assertEquals(f.calls.map((c) => c.name), ["ai_capability_enabled"]);
  assertEquals(f.models(), 0);
});

Deno.test("no consent: no quota spent, no model call", async () => {
  const f = fakes({ available: false });
  const res = await processTogetherAi(capture(), { client: f.client, user: f.user }, f.deps);
  assertEquals((await res.json()).code, "CONSENT_REQUIRED");
  assert(!f.calls.some((c) => c.name === "reserve_ai_assistant_quota"));
  assertEquals(f.models(), 0);
});

Deno.test("over budget: RATE_LIMITED with when to retry, no model call", async () => {
  const f = fakes({ quota: "rate_limited" });
  const res = await processTogetherAi(capture(), { client: f.client, user: f.user }, f.deps);
  const body = await res.json();
  assertEquals([res.status, body.code, body.retry_after_seconds], [429, "RATE_LIMITED", 3600]);
  assertEquals(f.models(), 0);
});

Deno.test("bad model output: PROVIDER_FAILED, usage marked provider_failed", async () => {
  const f = fakes({ model: { title: "" } });
  const res = await processTogetherAi(capture(), { client: f.client, user: f.user }, f.deps);
  assertEquals([res.status, (await res.json()).code], [502, "PROVIDER_FAILED"]);
  assertEquals(f.calls.at(-1)!.params.p_outcome, "provider_failed");
});

Deno.test("malformed input never reaches a provider", async () => {
  const f = fakes();
  for (const bad of [
    { action: "capture", relationship_id: "nope", request_id: REQ, text: "x", now_local: "2026-11-02T09:00" },
    { action: "summarise", relationship_id: REL, request_id: REQ },
    { action: "capture", relationship_id: REL, request_id: REQ, text: "x", now_local: "2026-11-02T09:00", user_id: USER },
  ]) {
    const res = await processTogetherAi(req(bad), { client: f.client, user: f.user }, f.deps);
    assertEquals((await res.json()).code, "INVALID_INPUT");
  }
  assertEquals(f.calls.length, 0);
});

Deno.test("ideas: three ideas come back", async () => {
  const f = fakes({ model: { ideas: [1, 2, 3].map((i) => ({ title: `Idea ${i}`, blurb: "Line." })) } });
  const res = await processTogetherAi(
    req({ action: "ideas", relationship_id: REL, request_id: REQ, window_start_local: "2026-11-05T19:00", window_end_local: "2026-11-05T22:00" }),
    { client: f.client, user: f.user }, f.deps);
  assertEquals((await res.json()).ideas.length, 3);
});

Deno.test("the function saves nothing: no table access, only its allowed RPCs", async () => {
  const src = (await Deno.readTextFile(new URL("./handler.ts", import.meta.url))) +
    (await Deno.readTextFile(new URL("./index.ts", import.meta.url)));
  assert(!src.includes(".from("), "ai-together must not touch tables directly");
  const rpcs = [...src.matchAll(/rpc\(\s*"([a-z_]+)"/g)].map((m) => m[1]);
  const allowed = new Set(["ai_capability_enabled", "get_together_ai_status", "reserve_ai_assistant_quota",
    "claim_ai_assistant_provider_start", "mark_ai_assistant_usage_outcome",
    // Spec 7 (B9): read-only, service role.
    "user_is_quiet"]);
  for (const r of rpcs) assert(allowed.has(r), `unexpected RPC ${r}`);
});

// PostgREST may hand a boolean function's result back bare (`true`) or
// wrapped (`[{fn: true}]`); both must work for the flag and the claim.
for (const shape of ["bare", "wrapped"] as const) {
  Deno.test(`boolean RPC results work when ${shape}`, async () => {
    const wrap = (name: string, v: boolean) => (shape === "bare" ? v : [{ [name]: v }]);
    const calls: string[] = [];
    const rpc = (name: string, _p: Record<string, unknown>) => {
      calls.push(name);
      const data = {
        ai_capability_enabled: wrap("ai_capability_enabled", true),
        get_together_ai_status: { available: true, partner_name: "Kofi" },
        reserve_ai_assistant_quota: [{ outcome: "reserved" }],
        claim_ai_assistant_provider_start: wrap("claim_ai_assistant_provider_start", true),
        mark_ai_assistant_usage_outcome: null,
      }[name];
      return Promise.resolve({ data, error: null });
    };
    const res = await processTogetherAi(
      new Request("http://x", {
        method: "POST",
        body: JSON.stringify({ action: "capture", relationship_id: REL, request_id: REQ, text: "dinner", now_local: "2026-11-02T09:00" }),
      }),
      { client: { rpc }, user: { id: USER } },
      {
        service: { rpc },
        callGemini: () => Promise.resolve({ title: "Dinner", all_day: false, start_local: "2026-11-07T19:00", end_local: null, with_partner: true, location: null, note: null }),
      },
    );
    assertEquals(res.status, 200, `calls: ${calls.join(",")}`);
  });
}

Deno.test("a thrown provider error still marks the usage provider_failed", async () => {
  const marks: unknown[] = [];
  const rpc = (name: string, p: Record<string, unknown>) => {
    if (name === "mark_ai_assistant_usage_outcome") marks.push(p.p_outcome);
    const data = {
      ai_capability_enabled: true,
      get_together_ai_status: { available: true, partner_name: "Kofi" },
      reserve_ai_assistant_quota: [{ outcome: "reserved" }],
      claim_ai_assistant_provider_start: true,
      mark_ai_assistant_usage_outcome: null,
    }[name];
    return Promise.resolve({ data, error: null });
  };
  const res = await processTogetherAi(
    new Request("http://x", {
      method: "POST",
      body: JSON.stringify({ action: "capture", relationship_id: REL, request_id: REQ, text: "dinner", now_local: "2026-11-02T09:00" }),
    }),
    { client: { rpc }, user: { id: USER } },
    { service: { rpc }, callGemini: () => Promise.reject(new Error("boom")) },
  );
  assertEquals((await res.json()).code, "PROVIDER_FAILED");
  assertEquals(marks, ["provider_failed"]);
});

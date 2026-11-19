// Spec 2 W4a (§3.3, §4.7, §7.3, §7.5 mutant 8): the dating-verification
// decision table over test providers (liveness pass/fail x estimate at or
// above / below 25 x photos match/mismatch, and the ID route's pass, fail,
// date-of-birth mismatch, minor and pending); the fakes' scenarios; a
// vendor that can't answer counts nothing; fake refused unless the
// environment reads development; nothing is ever logged (a console spy);
// the reference frame is cleared; only fixed codes leave; the device hash;
// busy and a vendor that can't answer are tried again after a backoff and
// counted, never ending the session; no database call is open across a
// vendor or storage call.
import { handleVerification, deviceHashOf, storageNotFound, type VerificationDeps } from "./handler.ts";
import { fakeProviders } from "../_shared/age_assurance/fake.ts";
import { providersFor } from "../_shared/age_assurance/providers.ts";
import { ageDecision, type AgeEstimate, type IdResult, type Mode, type Providers } from "../_shared/age_assurance/types.ts";

function eq(actual: unknown, expected: unknown, why = "") {
  const a = JSON.stringify(actual), e = JSON.stringify(expected);
  if (a !== e) throw new Error(`${why} expected ${e}, got ${a}`);
}

const SESSION = "11111111-2222-4333-8444-555555555555";
const DECLARED = "1990-05-05";

interface World {
  config: Record<string, unknown>;
  age: string | null;
  kind: string;
  step: string;
  state: string;
  outcome: string | null;
  ref: string | null;
  attempts: number;
  calls: Array<[string, Record<string, unknown> | undefined]>;
  photos: number;
  sleeps: number[];
  device: unknown; // Spec 2 W4b fix round 1: the session's phone (begin's p_device_hash)
  ageRecheck: boolean; // Spec 2 W4 final (I-1b): every approved photo is newer than the age pass
}

function world(over: Partial<World> = {}): World {
  return {
    config: { available: true, mode: "fake", environment: "development", challenge_age: 25 },
    age: null, kind: "activation", step: "liveness", state: "started", outcome: null, ref: null, attempts: 0, calls: [], photos: 2, sleeps: [],
    device: null, ageRecheck: false,
    ...over,
  };
}

/// A database that answers like the W4a service functions, recording calls.
function deps(w: World, providers: Providers | null = fakeProviders, downloads: Uint8Array[] = []): VerificationDeps {
  return {
    rpc: (fn, args) => {
      w.calls.push([fn, args]);
      const ok = (data: unknown) => Promise.resolve({ data, error: null });
      if (fn === "record_dating_age_assurance") w.age = String(args?.p_age_result);
      switch (fn) {
        case "get_dating_verification_config":
          return ok(w.config);
        case "begin_dating_verification":
          if (w.age === "fail") return ok({ ok: false, reason: "age_not_confirmed" }); // R-13: a failed ID is final
          w.kind = String(args?.p_kind);
          w.step = String(args?.p_step);
          w.device = args?.p_device_hash ?? null;
          w.state = "started";
          return ok({ ok: true, session_id: SESSION, attempts: w.attempts, resumed: false, gestures: ["left_ear", "thumbs_up"] });
        case "set_dating_verification_ref":
          w.ref = String(args?.p_ref);
          return ok({ ok: true, reason: null });
        case "get_dating_verification_session":
          return ok({
            ok: true, session_id: SESSION, kind: w.kind, step: w.step, state: w.state, vendor: "fake",
            vendor_session_ref: w.ref, attempts: w.attempts, outcome: w.outcome, country: "GH", expired: false, age: w.age,
            device_hash: w.device, age_recheck: w.ageRecheck,
          });
        case "record_dating_liveness_attempt":
          if (args?.p_passed === true) return ok({ ok: true, attempts: w.attempts });
          // Task 2 fix round 1 (M-3): once per vendor session (the reference is cleared).
          if (w.ref === null) return ok({ ok: false, reason: "session_unavailable" });
          w.ref = null;
          w.attempts++;
          return ok({ ok: true, attempts: w.attempts, outcome: w.attempts >= 2 ? "another_way" : "retry" });
        case "record_dating_video_outcome": {
          // Task 2 fix round 1 (I-3): one transaction, as the SQL writer. The
          // parts it writes are listed under their own names for the checks.
          const identity = String(args?.p_identity), age = args?.p_age, position = args?.p_position ?? null;
          w.calls.push(["record_dating_identity_check", {
            p_user: args?.p_user, p_method: "liveness_compare", p_result: identity, p_vendor: args?.p_identity_vendor, p_decided_by: null,
          }]);
          if (age === "pass") {
            w.calls.push(["record_dating_age_assurance", {
              p_user: args?.p_user, p_age_method: "fae", p_age_result: "pass", p_challenge_age: 25, p_vendor: args?.p_age_vendor,
            }]);
            w.age = "pass";
          }
          if (age === "far_below") {
            w.calls.push(["record_dating_age_far_below", { p_user: args?.p_user, p_session: args?.p_session, p_vendor: args?.p_age_vendor }]);
          }
          // Spec 2 W4 final (M-6): far below wins over a photo that doesn't match.
          const outcome = age === "far_below" ? "far_below" : identity === "fail" ? "photo_mismatch" : age === "skip" || age === "pass" ? "verified"
            : age === "needs_id" ? "needs_id" : age === "uncertain" ? "age_uncertain" : "far_below";
          w.state = identity === "fail" || age === "far_below" ? "failed" : "passed";
          w.outcome = outcome;
          return ok({ ok: true, outcome, position, replayed: false });
        }
        case "get_dating_verification_photos":
          return ok(Array.from({ length: w.photos }, (_, i) => ({ position: i + 1, storage_key: `k${i + 1}` })));
        case "record_dating_identity_check":
        case "trust_dating_device": // Spec 2 W4b
        case "record_dating_age_assurance":
        case "record_dating_age_far_below":
        case "submit_dating_human_review":
          return ok({ ok: true });
        case "finish_dating_verification_session":
          w.state = String(args?.p_state);
          w.outcome = String(args?.p_outcome);
          return ok({ ok: true, reason: null });
        case "check_dating_id_birth_date": {
          const dob = String(args?.p_dob);
          const minor = Date.parse(dob) > Date.now() - 18 * 365.25 * 864e5;
          return ok(minor ? "minor" : dob === DECLARED ? "match" : "mismatch");
        }
        default:
          return Promise.resolve({ data: null, error: { code: "42883" } });
      }
    },
    download: (key) => {
      const b = new TextEncoder().encode(`photo:${key}`);
      downloads.push(b);
      return Promise.resolve(b);
    },
    providers: () => providers,
    sleep: (ms) => {
      w.sleeps.push(ms);
      return Promise.resolve();
    },
  };
}

// Spec 2 W4b fix round 1 (I-4): every check needs the phone, so the
// default caller names one; noPhone is a request with no install id.
const caller = { userId: "u-1", deviceHash: "f".repeat(64) };
const noPhone = { userId: "u-1", deviceHash: null };
const names = (w: World) => w.calls.map(([fn]) => fn);
const args = (w: World, fn: string) => w.calls.filter(([f]) => f === fn).map(([, a]) => a);

/// Test providers for the table: each axis set by hand.
function table(live: boolean, age: number | null, match: boolean, frames: Uint8Array[] = [], estimates: number[] = []): Providers {
  return {
    liveness: {
      name: "fake",
      createSession: () => Promise.resolve({ ref: "ref-1" }),
      results: () => {
        const frame = new TextEncoder().encode("FRAME-BYTES");
        frames.push(frame);
        return Promise.resolve(live ? { status: "passed", reference: frame } : { status: "failed", reference: null });
      },
    },
    age: {
      name: "fake",
      estimate: () => {
        estimates.push(1);
        return Promise.resolve(age === null ? null : { age, under18HighConfidence: false } as AgeEstimate);
      },
    },
    id: fakeProviders.id,
    faceMatch: { name: "fake", compare: (_s, _t, i) => Promise.resolve(match || i === 0) },
  };
}

Deno.test("the decision table: liveness x estimate x photos", async () => {
  for (const live of [true, false]) {
    for (const est of [25, 24, null]) {
      for (const match of [true, false]) {
        const w = world();
        const d = deps(w, table(live, est, match));
        const why = `live=${live} est=${est} match=${match}`;
        eq((await handleVerification({ action: "start" }, caller, d)).ok, true, why);
        const r = await handleVerification({ action: "complete", session_id: SESSION }, caller, d);
        const want = !live ? "retry" : !match ? "photo_mismatch" : est === null ? "age_uncertain" : est >= 25 ? "verified" : "needs_id";
        eq(r.outcome, want, why);
        const ages = args(w, "record_dating_age_assurance");
        eq(ages.length, want === "verified" ? 1 : 0, `${why} age records`);
        if (want === "verified") eq([ages[0]?.p_age_method, ages[0]?.p_age_result, ages[0]?.p_challenge_age], ["fae", "pass", 25], why);
        const ids = args(w, "record_dating_identity_check").map((a) => a?.p_result);
        eq(ids, !live ? [] : match ? ["pass"] : ["fail"], `${why} identity`);
        if (want === "photo_mismatch") eq(r.position, 2, why);
      }
    }
  }
});

Deno.test("mutant 8 (§7.5): an estimate below 25 never passes; 25 does; no estimate never does", () => {
  eq(ageDecision({ age: 24.9, under18HighConfidence: false }), "needs_id");
  eq(ageDecision({ age: 25, under18HighConfidence: false }), "pass");
  eq(ageDecision({ age: 40, under18HighConfidence: false }, 18), "needs_id", "a lower challenge age is refused");
  eq(ageDecision(null), "uncertain");
  eq(ageDecision({ age: Number.NaN, under18HighConfidence: false }), "uncertain");
  eq(ageDecision({ age: 31, under18HighConfidence: false, uncertain: true }), "uncertain", "the vendor isn't sure");
  eq(ageDecision({ age: 13, under18HighConfidence: true, uncertain: true }), "uncertain", "an unsure estimate never places a hold");
  eq(ageDecision({ age: 30, under18HighConfidence: true }), "far_below");
});

Deno.test("liveness fails twice: retry, then another way; nothing recorded", async () => {
  const w = world();
  const d = deps(w, table(false, 30, true));
  await handleVerification({ action: "start" }, caller, d);
  eq((await handleVerification({ action: "complete", session_id: SESSION }, caller, d)).outcome, "retry");
  // Task 2 fix round 1 (M-3): the same vendor session never counts twice.
  eq(await handleVerification({ action: "complete", session_id: SESSION }, caller, d), { ok: false, reason: "session_unavailable" });
  eq(w.attempts, 1, "counted once");
  await handleVerification({ action: "start" }, caller, d);
  eq((await handleVerification({ action: "complete", session_id: SESSION }, caller, d)).outcome, "another_way");
  eq(names(w).filter((n) => n.startsWith("record_dating_age") || n === "record_dating_identity_check"), []);
});

Deno.test("an age already passed: identity only, no estimate", async () => {
  const w = world({ age: "pass" });
  const estimates: number[] = [];
  const d = deps(w, table(true, 20, true, [], estimates));
  await handleVerification({ action: "start" }, caller, d);
  eq((await handleVerification({ action: "complete", session_id: SESSION }, caller, d)).outcome, "verified");
  eq(estimates.length, 0);
  eq(args(w, "record_dating_age_assurance").length, 0);
});

Deno.test("R-9: no estimation vendor never passes: the ID route; one that throws is vendor_unavailable (W4 final M-7)", async () => {
  for (const age of [null]) {
    const w = world();
    const d = deps(w, table(true, age, true));
    await handleVerification({ action: "start" }, caller, d);
    eq((await handleVerification({ action: "complete", session_id: SESSION }, caller, d)).outcome, "age_uncertain");
  }
  const w = world();
  const p = table(true, 30, true);
  p.age = { name: "fake", estimate: () => Promise.reject(new Error("timeout")) };
  const d = deps(w, p);
  await handleVerification({ action: "start" }, caller, d);
  eq(await handleVerification({ action: "complete", session_id: SESSION }, caller, d), { ok: false, reason: "vendor_unavailable" });
  eq(args(w, "record_dating_age_assurance").length, 0);
  eq(names(w).includes("record_dating_video_outcome"), false, "nothing written: the session stays open");
});

Deno.test("the fakes' scenarios walk every video outcome", async () => {
  const want: Record<string, string> = {
    pass: "verified", liveness_fail: "retry", under_25: "needs_id", uncertain: "age_uncertain", far_below: "far_below",
    photo_mismatch: "photo_mismatch",
  };
  for (const [scenario, outcome] of Object.entries(want)) {
    const w = world();
    const d = deps(w);
    eq((await handleVerification({ action: "start", scenario }, caller, d)).ok, true, scenario);
    eq((await handleVerification({ action: "complete", session_id: SESSION }, caller, d)).outcome, outcome, scenario);
    if (scenario === "far_below") {
      eq(args(w, "record_dating_age_far_below"), [{ p_user: "u-1", p_session: SESSION, p_vendor: "fake" }]); // W4 final (M-8): the estimator
      eq(args(w, "record_dating_age_assurance").length, 0, "far below records no pass");
    }
  }
});

Deno.test("the ID route: pass, fail, date-of-birth mismatch, minor, pending", async () => {
  const want: Record<string, string> = {
    id_pass: "verified", id_fail: "age_not_confirmed", id_dob_mismatch: "dob_mismatch", id_minor: "far_below", id_pending: "id_pending",
  };
  for (const [scenario, outcome] of Object.entries(want)) {
    const w = world();
    const d = deps(w);
    const s = await handleVerification({ action: "start_id", document: "ghana_card", scenario }, caller, d);
    eq([s.ok, s.vendor], [true, "fake"], scenario);
    eq((await handleVerification({ action: "complete_id", session_id: SESSION }, caller, d)).outcome, outcome, scenario);
    const ages = args(w, "record_dating_age_assurance").map((a) => `${a?.p_age_method}:${a?.p_age_result}`);
    eq(ages, outcome === "verified" ? ["id:pass"] : outcome === "age_not_confirmed" ? ["id:fail"] : [], `${scenario} ages`);
    if (scenario === "id_dob_mismatch") {
      eq(args(w, "check_dating_id_birth_date").map((a) => a?.p_dob), ["1970-01-01"]);
      eq(w.state, "awaiting_review");
    }
  }
});

Deno.test("a pending ID check stays waiting and is read again", async () => {
  const w = world();
  const d = deps(w);
  await handleVerification({ action: "start_id", document: "passport", scenario: "id_pending" }, caller, d);
  eq((await handleVerification({ action: "complete_id", session_id: SESSION }, caller, d)).outcome, "id_pending");
  eq((await handleVerification({ action: "complete_id", session_id: SESSION }, caller, d)).outcome, "id_pending");
  eq(args(w, "finish_dating_verification_session").length, 1, "finished once");
});

Deno.test("a vendor that can't answer counts nothing (§3.15 D11)", async () => {
  const w = world();
  const d = deps(w);
  eq(await handleVerification({ action: "start", scenario: "vendor_down" }, caller, d), { ok: false, reason: "vendor_unavailable" });
  const w2 = world();
  const p = table(true, 30, true);
  p.liveness = { ...p.liveness, results: () => Promise.reject(new Error("503")) };
  const d2 = deps(w2, p);
  await handleVerification({ action: "start" }, caller, d2);
  eq(await handleVerification({ action: "complete", session_id: SESSION }, caller, d2), { ok: false, reason: "vendor_unavailable" });
  eq(names(w2).includes("record_dating_liveness_attempt"), false, "no attempt counted");
  const w3 = world();
  const p3 = table(true, 30, true);
  p3.faceMatch = { name: "fake", compare: () => Promise.reject(new Error("throttled")) };
  const d3 = deps(w3, p3);
  await handleVerification({ action: "start" }, caller, d3);
  eq(await handleVerification({ action: "complete", session_id: SESSION }, caller, d3), { ok: false, reason: "vendor_unavailable" });
  eq(names(w3).includes("record_dating_identity_check"), false, "no identity recorded");
});

Deno.test("fake is refused unless the environment reads development; a scenario only in fake mode", async () => {
  let built = 0;
  for (const environment of ["production", "staging", ""]) {
    const w = world({ config: { available: true, mode: "fake", environment } });
    const d = { ...deps(w), providers: () => (built++, fakeProviders) };
    eq(await handleVerification({ action: "start" }, caller, d), { ok: false, reason: "unavailable" }, environment);
  }
  eq(built, 0, "no provider was built");
  const ok = world();
  eq((await handleVerification({ action: "start" }, caller, deps(ok))).ok, true, "development");
  const sandbox = world({ config: { available: true, mode: "sandbox", environment: "development" } });
  eq(await handleVerification({ action: "start", scenario: "pass" }, caller, deps(sandbox, table(true, 30, true))),
    { ok: false, reason: "invalid" });
  const off = world({ config: { available: false, mode: "fake", environment: "development" } });
  eq(await handleVerification({ action: "start" }, caller, deps(off)), { ok: false, reason: "unavailable" });
  eq(providersFor("fake", "production", () => undefined), null);
  const local = (name: string) => name === "SUPABASE_URL" ? "http://127.0.0.1:54321" : undefined;
  eq(providersFor("fake", "development", local)?.liveness.name, "fake");
  // The Spec 1 W7b rule: development on any other host runs nothing.
  const hosted = world();
  const real = { ...deps(hosted), providers: (m: Mode, e: string) => providersFor(m, e, (n) => n === "SUPABASE_URL" ? "https://prodref.supabase.co" : undefined) };
  eq(await handleVerification({ action: "start" }, caller, real), { ok: false, reason: "unavailable" }, "a hosted project's URL");
  eq(names(hosted).includes("begin_dating_verification"), false, "nothing began");
});

Deno.test("nothing is ever logged (images, estimates, dates of birth, vendor answers)", async () => {
  const seen: unknown[] = [];
  const saved = { log: console.log, info: console.info, warn: console.warn, error: console.error, debug: console.debug };
  for (const k of Object.keys(saved) as Array<keyof typeof saved>) console[k] = (...a: unknown[]) => seen.push(a);
  try {
    for (const scenario of ["pass", "liveness_fail", "under_25", "far_below", "photo_mismatch", "vendor_down"]) {
      const w = world();
      const d = deps(w);
      await handleVerification({ action: "start", scenario }, caller, d);
      await handleVerification({ action: "complete", session_id: SESSION }, caller, d);
    }
    for (const scenario of ["id_pass", "id_fail", "id_dob_mismatch", "id_minor", "id_pending"]) {
      const w = world();
      const d = deps(w);
      await handleVerification({ action: "start_id", document: "passport", scenario }, caller, d);
      await handleVerification({ action: "complete_id", session_id: SESSION }, caller, d);
    }
    const w = world();
    await handleVerification({ action: "human_start" }, caller, deps(w));
    await handleVerification({ action: "submit_human", session_id: SESSION }, caller, deps(w));
    await handleVerification({ action: "nope" }, caller, deps(w));
  } finally {
    Object.assign(console, saved);
  }
  eq(seen, []);
});

Deno.test("the reference frame and the photos' bytes are cleared after use", async () => {
  const frames: Uint8Array[] = [];
  const downloads: Uint8Array[] = [];
  const w = world();
  const d = deps(w, table(true, 30, true, frames), downloads);
  await handleVerification({ action: "start" }, caller, d);
  eq((await handleVerification({ action: "complete", session_id: SESSION }, caller, d)).outcome, "verified");
  eq([frames.length, downloads.length], [1, 2]);
  for (const b of [...frames, ...downloads]) eq(b.every((x) => x === 0), true, "zeroed");
});

Deno.test("only fixed codes leave: a server's text is never passed on", async () => {
  const w = world();
  const d = deps(w);
  const rpc = d.rpc;
  d.rpc = (fn, a) => fn === "begin_dating_verification"
    ? Promise.resolve({ data: { ok: false, reason: "duplicate key value violates unique constraint" }, error: null })
    : rpc(fn, a);
  eq(await handleVerification({ action: "start" }, caller, d), { ok: false, reason: "busy" });
  d.rpc = (fn, a) => fn === "begin_dating_verification" ? Promise.resolve({ data: { ok: false, reason: "rate_limited" }, error: null }) : rpc(fn, a);
  eq(await handleVerification({ action: "start" }, caller, d), { ok: false, reason: "rate_limited" });
  d.rpc = () => Promise.reject(new Error("connection reset"));
  eq(await handleVerification({ action: "start" }, caller, d), { ok: false, reason: "busy" });
  eq(await handleVerification({ action: "drop_tables" }, caller, deps(world())), { ok: false, reason: "invalid" });
  eq(await handleVerification({ action: "complete", session_id: "not-a-uuid" }, caller, deps(world())), { ok: false, reason: "invalid" });
});

Deno.test("the human route: two gestures and their two paths, then submitted", async () => {
  const w = world();
  const d = deps(w);
  eq(await handleVerification({ action: "human_start" }, caller, d), {
    ok: true, session_id: SESSION, gestures: ["left_ear", "thumbs_up"], paths: [`${SESSION}/1.jpg`, `${SESSION}/2.jpg`], resumed: false,
  });
  eq(args(w, "begin_dating_verification")[0]?.p_step, "human");
  eq(await handleVerification({ action: "submit_human", session_id: SESSION }, caller, d), { ok: true, outcome: "human_pending" });
});

Deno.test("the device hash (§3.3.4): sha256 of a 32-hex id, else nothing", async () => {
  eq(await deviceHashOf("0123456789abcdef0123456789abcdef"), "3eb1bd439947eb762998e566ccc2e099c791118b2f40579cc4f7da2b5061b7f9");
  for (const bad of [null, "", "0123456789ABCDEF0123456789ABCDEF", "0123456789abcdef", "0123456789abcdef0123456789abcdeg"]) {
    eq(await deviceHashOf(bad), null, String(bad));
  }
});

Deno.test("an ID whose face doesn't match the person never confirms the age (§3.3.1)", async () => {
  const w = world();
  const p = { ...fakeProviders };
  p.id = {
    name: "fake",
    startJob: () => Promise.resolve({ ref: "fake:id_pass:x" }),
    result: () => Promise.resolve({ status: "pass", dob: DECLARED, faceMatch: false }),
  };
  const d = deps(w, p);
  await handleVerification({ action: "start_id", document: "passport" }, caller, d);
  eq((await handleVerification({ action: "complete_id", session_id: SESSION }, caller, d)).outcome, "age_not_confirmed");
  eq(args(w, "record_dating_age_assurance").map((a) => `${a?.p_age_method}:${a?.p_age_result}`), ["id:fail"]);
  eq(names(w).includes("check_dating_id_birth_date"), false, "the date is not even compared");
});

// R-13 (owner ruling 2026-11-09): an estimate never ends the check; only a
// failed ID check (or Spec 1's under-18 hold) is final.
Deno.test("R-13: a failed or uncertain estimate never ends the check: nothing recorded, the ID check opens next", async () => {
  const rows: Array<[number | null, string]> = [[24, "needs_id"], [null, "age_uncertain"]];
  for (const [age, outcome] of rows) {
    const w = world();
    const d = deps(w, table(true, age, true));
    await handleVerification({ action: "start" }, caller, d);
    eq((await handleVerification({ action: "complete", session_id: SESSION }, caller, d)).outcome, outcome, `${age}`);
    eq([w.state, w.outcome], ["passed", outcome], `${age} session`);
    eq(args(w, "record_dating_age_assurance").length, 0, `${age}: no age result`);
    eq(names(w).includes("record_dating_age_far_below"), false, `${age}: no hold`);
    const s = await handleVerification({ action: "start_id", document: "ghana_card", scenario: "id_pass" }, caller, d);
    eq(s.ok, true, `${age}: the ID check opens`);
    eq((await handleVerification({ action: "complete_id", session_id: SESSION }, caller, d)).outcome, "verified", `${age}: by ID`);
  }
});
Deno.test("R-13: a failed ID check is final: nothing starts again", async () => {
  const w = world();
  const d = deps(w);
  await handleVerification({ action: "start_id", document: "passport", scenario: "id_fail" }, caller, d);
  eq((await handleVerification({ action: "complete_id", session_id: SESSION }, caller, d)).outcome, "age_not_confirmed");
  eq((await handleVerification({ action: "start" }, caller, d)).reason, "age_not_confirmed", "the video");
  eq((await handleVerification({ action: "start_id", document: "passport" }, caller, d)).reason, "age_not_confirmed", "the ID");
  eq((await handleVerification({ action: "human_start" }, caller, d)).reason, "age_not_confirmed", "a person");
});

// Carried rules (W3 lessons): busy is tried again, never a dead end; a
// vendor that can't answer is tried again; both are counted for an
// operator (bump_metric_server, dating.verify.*), and neither ends, fails
// or counts against the session.
const busyAnswer = () => Promise.resolve({ data: { ok: false, reason: "busy" }, error: null });
const keys = (w: World) => args(w, "bump_metric_server").map((a) => a?.p_key);

Deno.test("busy is tried again after 250 and 500 ms (the video outcome up to 4 s); still busy answers busy, counted, the session open", async () => {
  const w = world();
  const d = deps(w, table(true, 30, true));
  await handleVerification({ action: "start" }, caller, d);
  const rpc = d.rpc;
  let busy = 2;
  d.rpc = (fn, a) => fn === "record_dating_video_outcome" && busy-- > 0 ? busyAnswer() : rpc(fn, a);
  eq((await handleVerification({ action: "complete", session_id: SESSION }, caller, d)).outcome, "verified", "two busy tries ridden out");
  eq(w.sleeps, [250, 500]);
  eq(keys(w), [], "a busy that cleared is not counted");

  const w2 = world();
  const d2 = deps(w2, table(true, 30, true));
  await handleVerification({ action: "start" }, caller, d2);
  const rpc2 = d2.rpc;
  let tries = 0;
  d2.rpc = (fn, a) => fn === "record_dating_video_outcome" ? (tries++, busyAnswer()) : rpc2(fn, a);
  eq(await handleVerification({ action: "complete", session_id: SESSION }, caller, d2), { ok: false, reason: "busy" });
  eq([tries, w2.sleeps], [6, [250, 500, 1000, 2000, 4000]], "six tries");
  eq(names(w2).includes("record_dating_identity_check"), false, "nothing of the outcome written");
  eq(keys(w2), ["dating.verify.busy"], "counted once");
  // The session is still open: the next try goes through.
  d2.rpc = rpc2;
  eq((await handleVerification({ action: "complete", session_id: SESSION }, caller, d2)).outcome, "verified", "the retry");

  // A lock, deadlock or serialization SQLSTATE is busy too.
  const w3 = world();
  const d3 = deps(w3, table(false, 30, true));
  await handleVerification({ action: "start" }, caller, d3);
  const rpc3 = d3.rpc;
  let locked = 0;
  d3.rpc = (fn, a) => fn === "record_dating_liveness_attempt" && locked++ < 1
    ? Promise.resolve({ data: null, error: { code: "40P01", message: "deadlock detected" } })
    : rpc3(fn, a);
  eq((await handleVerification({ action: "complete", session_id: SESSION }, caller, d3)).outcome, "retry");
  eq([locked, w3.sleeps], [2, [250]]);
  // Any other write: three tries (250, 500), then busy.
  const w5 = world();
  const d5 = deps(w5, table(false, 30, true));
  await handleVerification({ action: "start" }, caller, d5);
  const rpc5 = d5.rpc;
  let tries5 = 0;
  d5.rpc = (fn, a) => fn === "record_dating_liveness_attempt" ? (tries5++, busyAnswer()) : rpc5(fn, a);
  eq(await handleVerification({ action: "complete", session_id: SESSION }, caller, d5), { ok: false, reason: "busy" });
  eq([tries5, w5.sleeps], [3, [250, 500]]);

  // A call that threw may have committed: never tried again (a failed
  // attempt is never counted twice); busy.
  const w4 = world();
  const d4 = deps(w4, table(false, 30, true));
  await handleVerification({ action: "start" }, caller, d4);
  const rpc4 = d4.rpc;
  let thrown = 0;
  d4.rpc = (fn, a) => fn === "record_dating_liveness_attempt" ? (thrown++, Promise.reject(new Error("reset"))) : rpc4(fn, a);
  eq(await handleVerification({ action: "complete", session_id: SESSION }, caller, d4), { ok: false, reason: "busy" });
  eq([thrown, w4.sleeps], [1, []]);
});

Deno.test("a vendor blip is ridden out; one that stays down is tried 3 times, then vendor_unavailable, counted, the session open", async () => {
  const w = world();
  const p = table(true, 30, true);
  let blips = 1;
  const results = p.liveness.results;
  p.liveness = { ...p.liveness, results: (ref) => blips-- > 0 ? Promise.reject(new Error("503")) : results(ref) };
  const d = deps(w, p);
  await handleVerification({ action: "start" }, caller, d);
  eq((await handleVerification({ action: "complete", session_id: SESSION }, caller, d)).outcome, "verified");
  eq([w.sleeps, keys(w)], [[250], []]);

  const w2 = world();
  const p2 = table(true, 30, true);
  let compares = 0;
  p2.faceMatch = { name: "fake", compare: () => (compares++, Promise.reject(new Error("throttled"))) };
  const d2 = deps(w2, p2);
  await handleVerification({ action: "start" }, caller, d2);
  eq(await handleVerification({ action: "complete", session_id: SESSION }, caller, d2), { ok: false, reason: "vendor_unavailable" });
  eq([compares, w2.sleeps], [3, [250, 500]]);
  eq(keys(w2), ["dating.verify.vendor_unavailable"]);
  eq(names(w2).filter((n) => n.startsWith("record_") || n === "finish_dating_verification_session"),
    [], "nothing failed, nothing ended");
  p2.faceMatch = table(true, 30, true).faceMatch;
  eq((await handleVerification({ action: "complete", session_id: SESSION }, caller, d2)).outcome, "verified", "the retry");

  // The deadline: no vendor try starts 100 s after the request began.
  const w3 = world();
  const p3 = table(true, 30, true);
  let clock = 0;
  let reads = 0;
  p3.liveness = { ...p3.liveness, results: () => (reads++, clock = 100_001, Promise.reject(new Error("timeout"))) };
  const d3 = { ...deps(w3, p3), now: () => clock };
  await handleVerification({ action: "start" }, caller, d3);
  clock = 0;
  eq(await handleVerification({ action: "complete", session_id: SESSION }, caller, d3), { ok: false, reason: "vendor_unavailable" });
  eq([reads, w3.sleeps], [1, []], "no try after the deadline");
});

Deno.test("no database call is open across a vendor or storage call: read, release, network, then record", async () => {
  let db = 0, net = 0;
  const overlaps: string[] = [];
  const events: string[] = [];
  const tick = () => new Promise((r) => setTimeout(r, 1));
  const w = world();
  const base = deps(w);
  const rpc = base.rpc;
  const network = <T>(name: string, f: () => Promise<T>): Promise<T> => {
    events.push(`net:${name}`);
    if (db !== 0) overlaps.push(name);
    net++;
    return tick().then(f).finally(() => net--);
  };
  const p: Providers = {
    liveness: {
      name: "fake",
      createSession: (o) => network("createSession", () => fakeProviders.liveness.createSession(o)),
      results: (r) => network("results", () => fakeProviders.liveness.results(r)),
    },
    age: { name: "fake", estimate: (f) => network("estimate", () => fakeProviders.age.estimate(f)) },
    id: {
      name: "fake",
      startJob: (o) => network("startJob", () => fakeProviders.id.startJob(o)),
      result: (r) => network("result", () => fakeProviders.id.result(r)),
    },
    faceMatch: { name: "fake", compare: (s, t, i) => network("compare", () => fakeProviders.faceMatch.compare(s, t, i)) },
  };
  const d: VerificationDeps = {
    ...base,
    rpc: (fn, a) => {
      events.push(`db:${fn}`);
      if (net !== 0) overlaps.push(fn);
      db++;
      return tick().then(() => rpc(fn, a)).finally(() => db--);
    },
    download: (k) => network("download", () => base.download(k)),
    providers: () => p,
  };
  await handleVerification({ action: "start" }, caller, d);
  eq(events.splice(0), ["db:get_dating_verification_config", "db:begin_dating_verification", "net:createSession", "db:set_dating_verification_ref"]);
  await handleVerification({ action: "complete", session_id: SESSION }, caller, d);
  eq(events.splice(0), [
    "db:get_dating_verification_config", "db:get_dating_verification_session", "net:results",
    "db:get_dating_verification_photos", "net:download", "net:compare", "net:download", "net:compare", "net:estimate",
    "db:record_dating_video_outcome", "db:trust_dating_device",
  ]);
  const w2 = world();
  const d2 = { ...d, rpc: (fn: string, a?: Record<string, unknown>) => {
    events.push(`db:${fn}`);
    if (net !== 0) overlaps.push(fn);
    db++;
    return tick().then(() => deps(w2).rpc(fn, a)).finally(() => db--);
  } };
  await handleVerification({ action: "start_id", document: "passport" }, caller, d2);
  await handleVerification({ action: "complete_id", session_id: SESSION }, caller, d2);
  eq(events.filter((e) => e.startsWith("net:")), ["net:startJob", "net:result"]);
  eq(overlaps, [], "a call overlapped");
});

// ---- Task 2 fix round 1 ----

// I-3 ruling: every vendor call first, then ONE write of the whole outcome.
Deno.test("I-3: the video outcome is one write, after every vendor call, with the frame already zeroed", async () => {
  for (const [est, match, want] of [[30, true, "pass"], [22, true, "needs_id"], [null, true, "uncertain"], [30, false, null]] as const) {
    const frames: Uint8Array[] = [];
    const w = world();
    const d = deps(w, table(true, est, match, frames));
    await handleVerification({ action: "start" }, caller, d);
    const rpc = d.rpc;
    let zeroed: boolean | null = null;
    d.rpc = (fn, a) => {
      if (fn === "record_dating_video_outcome") zeroed = frames.every((f) => f.every((x) => x === 0));
      return rpc(fn, a);
    };
    await handleVerification({ action: "complete", session_id: SESSION }, caller, d);
    const outcomes = args(w, "record_dating_video_outcome");
    eq(outcomes, [{
      p_user: "u-1", p_session: SESSION, p_identity: match ? "pass" : "fail", p_age: want, p_position: match ? null : 2,
      p_identity_vendor: "fake", p_age_vendor: "fake",
    }], `${est} ${match}`);
    eq(zeroed, true, "the frame is zeroed before the write");
    eq(names(w).filter((n) => ["finish_dating_verification_session", "record_dating_liveness_attempt"].includes(n)), [], "no other write");
  }
});

Deno.test("I-3: a far-below outcome whose write stays busy a while is tried again until the hold is placed", async () => {
  const w = world();
  const d = deps(w);
  await handleVerification({ action: "start", scenario: "far_below" }, caller, d);
  const rpc = d.rpc;
  let busy = 4;
  d.rpc = (fn, a) => fn === "record_dating_video_outcome" && busy-- > 0 ? busyAnswer() : rpc(fn, a);
  eq(await handleVerification({ action: "complete", session_id: SESSION }, caller, d), { ok: true, outcome: "far_below" });
  eq(w.sleeps, [250, 500, 1000, 2000]);
  eq(args(w, "record_dating_age_far_below"), [{ p_user: "u-1", p_session: SESSION, p_vendor: "fake" }]); // W4 final (M-8): the estimator
  // An outcome the writer doesn't name never leaves.
  const w2 = world();
  const d2 = deps(w2);
  await handleVerification({ action: "start" }, caller, d2);
  const rpc2 = d2.rpc;
  d2.rpc = (fn, a) => fn === "record_dating_video_outcome" ? Promise.resolve({ data: { ok: true, outcome: "u-1" }, error: null }) : rpc2(fn, a);
  eq(await handleVerification({ action: "complete", session_id: SESSION }, caller, d2), { ok: false, reason: "busy" });
});

// I-2 ruling: a refusal that will never change is not tried again.
Deno.test("I-2: a vendor refusal that isn't retryable is tried once, then vendor_unavailable, counted", async () => {
  const w = world();
  const p = table(true, 30, true);
  let compares = 0;
  p.faceMatch = { name: "fake", compare: () => (compares++, Promise.reject(Object.assign(new Error("rekognition_refused_400"), { retryable: false }))) };
  const d = deps(w, p);
  await handleVerification({ action: "start" }, caller, d);
  eq(await handleVerification({ action: "complete", session_id: SESSION }, caller, d), { ok: false, reason: "vendor_unavailable" });
  eq([compares, w.sleeps, keys(w)], [1, [], ["dating.verify.vendor_unavailable"]]);
  // An unusable photo is the provider's "no match" (aws.ts): that photo, fixable.
  const w2 = world();
  const p2 = table(true, 30, true);
  p2.faceMatch = { name: "fake", compare: (_s, _t, i) => Promise.resolve(i !== 0) };
  const d2 = deps(w2, p2);
  await handleVerification({ action: "start" }, caller, d2);
  eq(await handleVerification({ action: "complete", session_id: SESSION }, caller, d2), { ok: true, outcome: "photo_mismatch", position: 1 });
});

// I-1 ruling: an ID face match that isn't known is pending, never final.
Deno.test("I-1: an ID result with no face-match answer waits for a person; only an explicit no is final", async () => {
  const w = world();
  const p = { ...fakeProviders };
  p.id = { name: "smile_id", startJob: () => Promise.resolve({ ref: "attune_x:x" }),
    result: () => Promise.resolve({ status: "pass", dob: DECLARED, faceMatch: null }) };
  const d = deps(w, p);
  await handleVerification({ action: "start_id", document: "passport" }, caller, d);
  eq((await handleVerification({ action: "complete_id", session_id: SESSION }, caller, d)).outcome, "id_pending");
  eq([w.state, w.outcome], ["awaiting_review", "id_pending"]);
  eq(args(w, "record_dating_age_assurance").length, 0, "nothing final");
});

// M-2: an impossible date never reaches the database.
Deno.test("M-2: an ID date of birth that isn't a calendar date is never sent to SQL: a person checks", async () => {
  for (const dob of ["2026-13-45", "1990-02-30", null]) {
    const w = world();
    const p = { ...fakeProviders };
    p.id = { name: "smile_id", startJob: () => Promise.resolve({ ref: "attune_x:x" }),
      result: () => Promise.resolve({ status: "pass", dob, faceMatch: true }) };
    const d = deps(w, p);
    await handleVerification({ action: "start_id", document: "passport" }, caller, d);
    eq((await handleVerification({ action: "complete_id", session_id: SESSION }, caller, d)).outcome, "dob_mismatch", String(dob));
    eq(names(w).includes("check_dating_id_birth_date"), false, `${dob}: not sent`);
  }
});

// M-4: a failed ID check whose end stayed busy is closed on the next try.
Deno.test("M-4: a failed ID check whose end stays busy is closed on the next try, never left open", async () => {
  const w = world();
  const d = deps(w);
  await handleVerification({ action: "start_id", document: "passport", scenario: "id_fail" }, caller, d);
  const rpc = d.rpc;
  let failed = false;
  d.rpc = (fn, a) => {
    if (fn === "finish_dating_verification_session" && !failed) return busyAnswer();
    if (fn === "record_dating_age_assurance" && w.age === "fail") return Promise.resolve({ data: { ok: false, reason: "age_not_confirmed" }, error: null });
    return rpc(fn, a);
  };
  eq(await handleVerification({ action: "complete_id", session_id: SESSION }, caller, d), { ok: false, reason: "busy" });
  eq(w.state, "started", "still open after the busy end");
  failed = true;
  eq(await handleVerification({ action: "complete_id", session_id: SESSION }, caller, d), { ok: true, outcome: "age_not_confirmed" });
  eq([w.state, w.outcome], ["failed", "age_not_confirmed"]);
});

// M-1: only the six actions; an object's own keys never run.
Deno.test("M-1: an action named after an object key is invalid and never echoes the caller", async () => {
  for (const action of ["constructor", "toString", "__proto__", "hasOwnProperty", "valueOf"]) {
    const a = await handleVerification({ action }, caller, deps(world()));
    eq(a, { ok: false, reason: "invalid" }, action);
  }
});

// M-6 ruling: sandbox refused outside development, providers never built.
Deno.test("M-6: sandbox mode is refused outside development", async () => {
  let built = 0;
  for (const environment of ["production", ""]) {
    const w = world({ config: { available: true, mode: "sandbox", environment } });
    const d = { ...deps(w), providers: () => (built++, fakeProviders) };
    eq(await handleVerification({ action: "start" }, caller, d), { ok: false, reason: "unavailable" }, environment);
  }
  eq(built, 0);
});

// M-7: busy retries stop near the edge function's wall clock.
Deno.test("M-7: no busy retry starts past 130 s into the request", async () => {
  const w = world();
  let clock = 0;
  const d = { ...deps(w, table(true, 30, true)), now: () => clock };
  await handleVerification({ action: "start" }, caller, d);
  const rpc = d.rpc;
  let tries = 0;
  d.rpc = (fn, a) => {
    if (fn === "record_dating_video_outcome") {
      tries++;
      clock = 129_900;
      return busyAnswer();
    }
    return rpc(fn, a);
  };
  clock = 0;
  eq(await handleVerification({ action: "complete", session_id: SESSION }, caller, d), { ok: false, reason: "busy" });
  eq([tries, w.sleeps], [1, []], "no wait would end past the deadline");
});

// M-8: the storage download is bounded like every vendor call.
Deno.test("M-8: a photo download that never answers times out, is tried again, then vendor_unavailable", async () => {
  const w = world();
  let downloads = 0;
  const d = {
    ...deps(w, table(true, 30, true)),
    download: () => (downloads++, new Promise<Uint8Array | null>(() => {})),
    downloadTimeoutMs: 5,
  };
  await handleVerification({ action: "start" }, caller, d);
  eq(await handleVerification({ action: "complete", session_id: SESSION }, caller, d), { ok: false, reason: "vendor_unavailable" });
  eq(downloads, 3);
});

// ---- Spec 2 W4b (Task 6, §3.3.4) ----

// The phone that passes is trusted; the re-check trusts a new phone on a
// pass, never writes the account's own result, and needs the phone.
const onPhone = { userId: "u-1", deviceHash: "a".repeat(64) };
/// [d] with its session read answering a re-check row on [hash]'s phone.
const reverifyRow = (w: World, d: VerificationDeps, hash: string): VerificationDeps => ({
  ...d,
  rpc: (fn, a) => fn === "get_dating_verification_session"
    ? Promise.resolve({ data: { ok: true, kind: "reverify", step: "liveness", state: "started", expired: false,
        vendor_session_ref: w.ref, device_hash: hash }, error: null })
    : d.rpc(fn, a),
});

Deno.test("W4b: the phone that passes D11 is trusted; with no header nothing is", async () => {
  const w = world();
  const d = deps(w, table(true, 30, true));
  await handleVerification({ action: "start" }, onPhone, d);
  eq((await handleVerification({ action: "complete", session_id: SESSION }, onPhone, d)).outcome, "verified");
  eq(args(w, "trust_dating_device"), [{ p_user: "u-1", p_device_hash: "a".repeat(64), p_session: SESSION }]); // W4 final (M-3)
  const w2 = world();
  const d2 = deps(w2, table(true, 30, true));
  eq(await handleVerification({ action: "start" }, noPhone, d2), { ok: false, reason: "device_unavailable" });
  await handleVerification({ action: "complete", session_id: SESSION }, noPhone, d2);
  eq(names(w2).filter((n) => n === "begin_dating_verification" || n === "trust_dating_device"), []);
});

Deno.test("fix round 1 (M-1): complete trusts only the phone the session ran on", async () => {
  const w = world();
  const d = deps(w, table(true, 30, true));
  await handleVerification({ action: "start" }, onPhone, d);
  const other = { userId: "u-1", deviceHash: "c".repeat(64) };
  eq((await handleVerification({ action: "complete", session_id: SESSION }, other, d)).outcome, "verified");
  eq(args(w, "trust_dating_device").length, 0, "another phone of the account is not trusted");
});

Deno.test("W4b: every face match trusts the phone (the ID route next too); a mismatch or Spec 1's hold never does", async () => {
  const far: Providers = { ...table(true, 30, true), age: { name: "fake", estimate: () => Promise.resolve({ age: 12, under18HighConfidence: true }) } };
  for (const [p, want, trusts] of [
    [table(true, 20, true), "needs_id", true], [table(true, null, true), "age_uncertain", true],
    [table(true, 30, false), "photo_mismatch", false], [far, "far_below", false],
  ] as const) {
    const w = world();
    const d = deps(w, p);
    await handleVerification({ action: "start" }, onPhone, d);
    eq((await handleVerification({ action: "complete", session_id: SESSION }, onPhone, d)).outcome, want);
    eq(args(w, "trust_dating_device").length, trusts ? 1 : 0, want);
  }
});

Deno.test("W4b: every check names the caller's phone to begin (a NULL hash is refused by the database)", async () => {
  for (const body of [{ action: "start" }, { action: "start_id", document: "passport" }, { action: "human_start" },
                      { action: "human_start", reverify: true }, { action: "reverify_start" }]) {
    const w = world();
    await handleVerification(body, onPhone, deps(w));
    eq(args(w, "begin_dating_verification").map((a) => a?.p_device_hash), ["a".repeat(64)], body.action);
  }
});

Deno.test("W4b: a re-check passes: liveness and every photo, the phone trusted, no age, no identity written", async () => {
  const w = world();
  const estimates: number[] = [];
  const d = deps(w, table(true, 20, true, [], estimates));
  eq((await handleVerification({ action: "reverify_start" }, onPhone, d)).ok, true);
  eq(args(w, "begin_dating_verification")[0]?.p_kind, "reverify");
  w.calls.length = 0;
  const r = await handleVerification({ action: "reverify_complete", session_id: SESSION }, onPhone, reverifyRow(w, d, "a".repeat(64)));
  eq(r.outcome, "verified");
  eq(args(w, "trust_dating_device"), [{ p_user: "u-1", p_device_hash: "a".repeat(64), p_session: SESSION }]); // W4 final (M-3)
  eq(args(w, "finish_dating_verification_session").map((a) => [a?.p_state, a?.p_outcome]), [["passed", "verified"]]);
  eq(names(w).filter((n) => n.startsWith("record_dating_age") || n === "record_dating_identity_check"
    || n === "record_dating_video_outcome"), []);
  eq(estimates.length, 0, "no age on a re-check");
});

Deno.test("W4b: a re-check that doesn't match never unverifies the owner; another phone's session is refused", async () => {
  const w = world();
  const d = deps(w, table(true, 30, false));
  await handleVerification({ action: "reverify_start" }, onPhone, d);
  eq((await handleVerification({ action: "reverify_complete", session_id: SESSION }, onPhone, reverifyRow(w, d, "a".repeat(64)))).outcome,
    "identity_failed");
  eq(names(w).includes("record_dating_identity_check"), false);
  eq(names(w).includes("record_dating_video_outcome"), false);
  eq(names(w).includes("trust_dating_device"), false);
  eq(args(w, "finish_dating_verification_session").map((a) => [a?.p_state, a?.p_outcome]), [["failed", "identity_failed"]]);
  eq(await handleVerification({ action: "reverify_complete", session_id: SESSION }, onPhone, reverifyRow(w, d, "b".repeat(64))),
    { ok: false, reason: "session_unavailable" });
  eq(await handleVerification({ action: "complete", session_id: SESSION }, onPhone, reverifyRow(w, d, "a".repeat(64))),
    { ok: false, reason: "session_unavailable" }, "the first check's action never completes a re-check");
});

Deno.test("W4b: a re-check whose vendor can't answer counts nothing and trusts nothing", async () => {
  const w = world();
  const p = table(true, 30, true);
  const d = deps(w, { ...p, liveness: { ...p.liveness, results: () => Promise.reject(new Error("503")) } });
  await handleVerification({ action: "reverify_start" }, onPhone, d);
  eq(await handleVerification({ action: "reverify_complete", session_id: SESSION }, onPhone, reverifyRow(w, d, "a".repeat(64))),
    { ok: false, reason: "vendor_unavailable" });
  eq(w.sleeps, [250, 500], "tried again after a backoff");
  eq(names(w).filter((n) => ["record_dating_liveness_attempt", "trust_dating_device", "finish_dating_verification_session"].includes(n)), []);
});

Deno.test("W4b fix round 1 (I-4): every check needs the phone: with no install id, device_unavailable, nothing begun", async () => {
  const w = world();
  const d = deps(w);
  for (const body of [{ action: "start" }, { action: "start_id", document: "passport" }, { action: "human_start" },
                      { action: "human_start", reverify: true }, { action: "reverify_start" },
                      { action: "reverify_complete", session_id: SESSION }]) {
    eq(await handleVerification(body, noPhone, d), { ok: false, reason: "device_unavailable" }, JSON.stringify(body));
  }
  eq(names(w).filter((n) => n !== "get_dating_verification_config"), [], "only the config was read");
  await handleVerification({ action: "human_start", reverify: true }, onPhone, d);
  eq(args(w, "begin_dating_verification")[0]?.p_kind, "reverify");
});

Deno.test("fix round 1 (M-2): a re-check zeroes the frame before it trusts the phone and before it ends", async () => {
  for (const match of [true, false]) {
    const frames: Uint8Array[] = [];
    const w = world();
    const d = deps(w, table(true, 30, match, frames));
    await handleVerification({ action: "reverify_start" }, onPhone, d);
    const base = reverifyRow(w, d, "a".repeat(64));
    const zeroedAt: Record<string, boolean> = {};
    const r = await handleVerification({ action: "reverify_complete", session_id: SESSION }, onPhone, {
      ...base,
      rpc: (fn, a) => {
        if (fn === "trust_dating_device" || fn === "finish_dating_verification_session") {
          zeroedAt[fn] = frames.length > 0 && frames.every((f) => f.every((x) => x === 0));
        }
        return base.rpc(fn, a);
      },
    });
    eq(r.outcome, match ? "verified" : "identity_failed");
    eq(zeroedAt, match
      ? { trust_dating_device: true, finish_dating_verification_session: true }
      : { finish_dating_verification_session: true }, `match=${match}`);
  }
});

// ---------------------------------------------------------------------
// Spec 2 W4 final fix wave (server). I-1b (owner ruling): an age pass
// whose every approved photo is newer than it (a photo swap on a trusted
// phone) is estimated again on the live frame, R-13 rules applying; an
// adult who keeps an older photo is not. M-3: trust names the session it
// ran on. M-4: another phone's open check is its own fixed code, never
// busy. M-5: every check that reads a session needs the phone. M-6: a
// far-below face wins over a photo that doesn't match. M-7: an estimator
// that can't answer counts nothing. M-8: the far-below row names the
// vendor that decided. M-12: a photo whose object is gone is
// photos_required, never retried as an outage. I-2: an ID the vendor asks
// to retake waits (never final); an ID showing under 18 is Spec 1's hold.
// ---------------------------------------------------------------------
const farBelow = (name = "fake") => ({ name, estimate: () => Promise.resolve({ age: 13, under18HighConfidence: true }) });

Deno.test("W4 final I-1b: a photo swap (age_recheck) runs the estimate again on the live frame; R-13 applies", async () => {
  const rows: Array<[Providers, string, unknown]> = [
    [table(true, 30, true), "verified", "pass"],
    [table(true, 24, true), "needs_id", "needs_id"],
    [table(true, null, true), "age_uncertain", "uncertain"],
    [{ ...table(true, 30, true), age: farBelow() }, "far_below", "far_below"],
  ];
  for (const [p, outcome, age] of rows) {
    const w = world({ age: "pass", ageRecheck: true });
    const d = deps(w, p);
    await handleVerification({ action: "start" }, caller, d);
    eq((await handleVerification({ action: "complete", session_id: SESSION }, caller, d)).outcome, outcome, outcome);
    eq(args(w, "record_dating_video_outcome").map((a) => a?.p_age), [age], `${outcome}: the estimate's answer is written`);
  }
  // An adult who keeps an older photo: identity only, no estimate.
  const estimates: number[] = [];
  const w = world({ age: "pass", ageRecheck: false });
  const d = deps(w, table(true, 20, true, [], estimates));
  await handleVerification({ action: "start" }, caller, d);
  eq((await handleVerification({ action: "complete", session_id: SESSION }, caller, d)).outcome, "verified");
  eq([estimates.length, args(w, "record_dating_video_outcome").map((a) => a?.p_age)], [0, ["skip"]], "kept photo: skip");
});

Deno.test("W4 final M-5: complete, complete_id and submit_human need the phone: device_unavailable, nothing read", async () => {
  const w = world();
  const d = deps(w);
  for (const action of ["complete", "complete_id", "submit_human"]) {
    eq(await handleVerification({ action, session_id: SESSION }, noPhone, d), { ok: false, reason: "device_unavailable" }, action);
  }
  eq(names(w).filter((n) => n !== "get_dating_verification_config"), [], "only the config was read");
});

Deno.test("W4 final M-6: a far-below face wins over a photo that doesn't match; any other estimate on a mismatch is ignored", async () => {
  for (const age of [null, "pass"]) {
    const w = world({ age });
    const d = deps(w, { ...table(true, 30, false), age: farBelow("estimator_x") });
    await handleVerification({ action: "start" }, caller, d);
    eq((await handleVerification({ action: "complete", session_id: SESSION }, caller, d)).outcome, "far_below", `age ${age}`);
    eq(args(w, "record_dating_video_outcome").map((a) => [a?.p_identity, a?.p_age, a?.p_position, a?.p_age_vendor]),
      [["fail", "far_below", 2, "estimator_x"]], `age ${age}`);
    eq(names(w).includes("trust_dating_device"), false, "never trusted");
  }
  for (const p of [table(true, 30, false), table(true, 12, false),
                   { ...table(true, 30, false), age: { name: "fake", estimate: () => Promise.reject(new Error("503")) } }]) {
    const w = world();
    const d = deps(w, p);
    await handleVerification({ action: "start" }, caller, d);
    eq(await handleVerification({ action: "complete", session_id: SESSION }, caller, d), { ok: true, outcome: "photo_mismatch", position: 2 });
    eq(args(w, "record_dating_video_outcome").map((a) => a?.p_age), [null], "no age on a mismatch");
  }
});

Deno.test("W4 final M-7: an estimator that can't answer is vendor_unavailable: tried again, counted, nothing written", async () => {
  for (const ageRecheck of [false, true]) {
    const w = world({ age: ageRecheck ? "pass" : null, ageRecheck });
    const d = deps(w, { ...table(true, 30, true), age: { name: "fake", estimate: () => Promise.reject(new Error("503")) } });
    await handleVerification({ action: "start" }, caller, d);
    eq(await handleVerification({ action: "complete", session_id: SESSION }, caller, d), { ok: false, reason: "vendor_unavailable" });
    eq(w.sleeps, [250, 500], "tried again after a backoff");
    eq(names(w).filter((n) => n.startsWith("record_dating") || n === "trust_dating_device"), [], "nothing written, nothing trusted");
    eq(keys(w), ["dating.verify.vendor_unavailable"], "counted for an operator");
  }
});

Deno.test("W4 final M-8: the far-below row names the vendor that decided (the estimator; the ID vendor)", async () => {
  const w = world();
  const d = deps(w, { ...table(true, 30, true), age: farBelow("estimator_x") });
  await handleVerification({ action: "start" }, caller, d);
  eq((await handleVerification({ action: "complete", session_id: SESSION }, caller, d)).outcome, "far_below");
  eq(args(w, "record_dating_video_outcome")[0]?.p_age_vendor, "estimator_x");
  const w2 = world();
  const d2 = deps(w2);
  await handleVerification({ action: "start_id", document: "passport", scenario: "id_minor" }, caller, d2);
  eq((await handleVerification({ action: "complete_id", session_id: SESSION }, caller, d2)).outcome, "far_below");
  eq(args(w2, "record_dating_age_far_below"), [{ p_user: "u-1", p_session: SESSION, p_vendor: "fake" }]);
});

Deno.test("W4 final M-3: every trust names the session that ran on the phone", async () => {
  const w = world();
  const d = deps(w, table(true, 30, true));
  await handleVerification({ action: "start" }, onPhone, d);
  await handleVerification({ action: "complete", session_id: SESSION }, onPhone, d);
  const w2 = world();
  const d2 = deps(w2, table(true, 30, true));
  await handleVerification({ action: "reverify_start" }, onPhone, d2);
  await handleVerification({ action: "reverify_complete", session_id: SESSION }, onPhone, reverifyRow(w2, d2, "a".repeat(64)));
  eq([...args(w, "trust_dating_device"), ...args(w2, "trust_dating_device")].map((a) => a?.p_session), [SESSION, SESSION]);
});

Deno.test("W4 final M-4: another phone's open check answers session_elsewhere, never busy, never counted as busy", async () => {
  for (const body of [{ action: "reverify_start" }, { action: "human_start", reverify: true }]) {
    const w = world();
    const base = deps(w);
    const d = { ...base, rpc: (fn: string, a?: Record<string, unknown>) => fn === "begin_dating_verification"
      ? Promise.resolve({ data: { ok: false, reason: "session_elsewhere" }, error: null }) : base.rpc(fn, a) };
    eq(await handleVerification(body, onPhone, d), { ok: false, reason: "session_elsewhere" }, body.action);
    eq([w.sleeps, keys(w)], [[], []], `${body.action}: not tried again, not counted`);
  }
});

Deno.test("W4 final M-12: a photo whose object is gone is photos_required, never retried as an outage", async () => {
  for (const action of ["complete", "reverify_complete"]) {
    const w = world();
    let downloads = 0;
    const base = deps(w, table(true, 30, true));
    const d = { ...base, download: () => (downloads++, Promise.resolve(null)) };
    await handleVerification({ action: action === "complete" ? "start" : "reverify_start" }, onPhone, d);
    const run = action === "complete" ? d : reverifyRow(w, d, "a".repeat(64));
    eq(await handleVerification({ action, session_id: SESSION }, onPhone, run), { ok: false, reason: "photos_required" }, action);
    eq([downloads, w.sleeps], [1, []], `${action}: one try, no backoff`);
    eq(names(w).filter((n) => ["record_dating_video_outcome", "trust_dating_device", "finish_dating_verification_session"].includes(n)),
      [], `${action}: nothing written`);
  }
  // A storage error that isn't "not found" is still an outage (retried).
  const w = world();
  const d = { ...deps(w, table(true, 30, true)), download: () => Promise.reject(new Error("storage 503")) };
  await handleVerification({ action: "start" }, caller, d);
  eq(await handleVerification({ action: "complete", session_id: SESSION }, caller, d), { ok: false, reason: "vendor_unavailable" });
  eq(w.sleeps, [250, 500]);
});

Deno.test("W4 final M-12: Storage's not-found answer (and only it) reads as a missing object", () => {
  eq([storageNotFound({ status: 404, statusCode: "404" }), storageNotFound({ status: 400, statusCode: "404" }),
      storageNotFound({ status: 404 }), storageNotFound({ status: 400, statusCode: "400" }), storageNotFound({ status: 500 }),
      storageNotFound(new TypeError("network")), storageNotFound(null), storageNotFound({ statusCode: 404 })],
    [true, true, true, false, false, false, false, false]);
});

Deno.test("W4 final I-2: an ID the vendor asks to retake waits for a person (never final); one showing under 18 is Spec 1's hold", async () => {
  const idWith = (result: IdResult): Providers => ({
    ...fakeProviders,
    id: { name: "smile_id", startJob: () => Promise.resolve({ ref: "attune_x:x" }), result: () => Promise.resolve(result) },
  });
  const w = world();
  const d = deps(w, idWith({ status: "retry", dob: null, faceMatch: null }));
  await handleVerification({ action: "start_id", document: "passport" }, caller, d);
  eq((await handleVerification({ action: "complete_id", session_id: SESSION }, caller, d)).outcome, "id_pending");
  eq([w.state, w.outcome], ["awaiting_review", "id_pending"]);
  eq(names(w).filter((n) => n.startsWith("record_dating_age")), [], "nothing recorded");
  eq((await handleVerification({ action: "start_id", document: "passport" }, caller, d)).ok, true, "never final: the ID check opens again");
  const w2 = world();
  const d2 = deps(w2, idWith({ status: "minor", dob: null, faceMatch: null }));
  await handleVerification({ action: "start_id", document: "passport" }, caller, d2);
  eq((await handleVerification({ action: "complete_id", session_id: SESSION }, caller, d2)).outcome, "far_below");
  eq(args(w2, "record_dating_age_far_below"), [{ p_user: "u-1", p_session: SESSION, p_vendor: "smile_id" }]);
  eq(names(w2).includes("record_dating_age_assurance"), false, "never a pass, never a plain fail");
});

// Spec 1a: the shared Pulse row may not contain any private check-in answer,
// in any dimension, delta or confidence; Emotional safety is self-only; the
// caller is authenticated and rate-limited. Source-text guards, same pattern
// as private_conflicts.test.ts, so a refactor cannot quietly reintroduce a
// check-in read into the shared path.
import { assert, assertEquals, assertMatch, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";

const source = await Deno.readTextFile(new URL("./index.ts", import.meta.url));
const sharedStart = source.indexOf("async function _computePulseScore");
const privateStart = source.indexOf("async function _computePrivateScores");
const handler = source.slice(0, sharedStart);
const shared = source.slice(sharedStart, privateStart);
const priv = source.slice(privateStart);

Deno.test("the shared computation never reads weekly_checkins or a rating", () => {
  assert(sharedStart > 0 && privateStart > sharedStart, "both functions exist, shared first");
  assert(!shared.includes("weekly_checkins"));
  assert(!/safety_rating|communication_rating|connection_rating|alignment_rating|conflict_health_rating/.test(shared));
  assert(!/checkins\b/.test(shared));
});

Deno.test("the shared row writes emotional_safety as null and no per-dimension safety confidence", () => {
  assertMatch(shared, /emotional_safety: null/);
  assert(!/emotional_safety: emotionalSafety/.test(shared));
  assert(!/emotional_safety: safetyConfidence/.test(shared));
});

Deno.test("deltas compare against the previous week's row", () => {
  const from = shared.indexOf("from('pulse_scores')", shared.indexOf("previousPulse"));
  const statement = shared.slice(from, shared.indexOf(".maybeSingle()", from));
  assertMatch(statement, /\.lt\('week_ending', weekKey\)/);
});

Deno.test("the handler authenticates the caller, checks membership and claims the limit", () => {
  assertStringIncludes(handler, "auth.getUser(token)");
  assertStringIncludes(handler, "callerMayRecompute(");
  assertStringIncludes(handler, "rpc('claim_pulse_recompute'");
  assertStringIncludes(handler, "p_user_id: auth.user.id");
  assertStringIncludes(handler, "status: 429");
});

Deno.test("the private pass runs whether or not the shared row is recomputed", () => {
  const calls = shared.match(/await _computePrivateScores\(/g) ?? [];
  assertEquals(calls.length, 2, "once on the early return, once after the shared upsert");
  assert(shared.indexOf("await _computePrivateScores(") < shared.indexOf("// 3. Attachment quiz"));
  assertStringIncludes(shared, "shouldComputeShared(opts.isService, opts.force");
});

Deno.test("private scores go only to pulse_private_scores", () => {
  assertStringIncludes(priv, "from('weekly_checkins')");
  assertStringIncludes(priv, "from('pulse_private_scores')");
  assert(!priv.includes("from('pulse_scores')"));
});

Deno.test("compute-pulse still reads only shared moments", () => {
  const query = shared.slice(shared.indexOf(".from('timeline_events')"));
  assertMatch(query.slice(0, query.indexOf("// 2.")), /\.eq\('visibility', 'shared'\)/);
});

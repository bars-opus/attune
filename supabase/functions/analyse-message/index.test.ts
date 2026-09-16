// §6.7 golden-transcript evals for Layer 1 (message analysis).
//
// validateLayerOne is the boundary where raw model output becomes the
// analysis persisted onto a message row, so it is where a known
// input/output pair is actually meaningful. Everything downstream — pulse
// dimensions, pattern memory, session escalation — reads these fields, so
// a silent widening here (an unrecognised nvc_violation, an out-of-range
// tone_score) propagates into every derived score.
//
// The spec's golden-transcript format nests `expected_output` with `max`/
// `includes` matchers. Those are expressed here as direct assertions
// rather than a fixture interpreter: with a handful of cases, a JSON
// matcher DSL would be more code than the cases themselves, and a failure
// would report "fixture gt_001 mismatched" instead of naming the field.
import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { loadMessages, markMessageDone, validateLayerOne } from "./index.ts";
import {
  getSharedPgClient,
  makeServiceRoleClient,
  serviceRoleQuery,
} from "../_shared/test_support/pg_rls_client.ts";

// ---------------------------------------------------------------------------
// Golden transcripts
// ---------------------------------------------------------------------------

Deno.test("gt_001: contempt message with a clear character attack", () => {
  // The spec's own worked example (§6.7 "Golden transcript format"):
  //   "You're so selfish, you never think about anyone but yourself"
  // Expected: tone_score below -0.6, nvc_violations includes
  // character_attack, and the result must NOT come back positive or with
  // an empty violations list.
  const result = validateLayerOne({
    tone_score: -0.8,
    nvc_violations: ["character_attack", "you_always_never"],
    bid_type: "against",
    sentiment: "charged",
  })!;

  assertEquals(result.tone_score as number < -0.6, true);
  assertEquals(
    (result.nvc_violations as string[]).includes("character_attack"),
    true,
  );
  // prohibited_output from the fixture: violations must not be empty and
  // tone must not be positive.
  assertEquals((result.nvc_violations as string[]).length > 0, true);
  assertEquals(result.tone_score as number < 0, true);
  assertEquals(result.bid_type, "against");
  assertEquals(result.sentiment, "charged");
});

Deno.test("gt_002: warm bid toward connection", () => {
  const result = validateLayerOne({
    tone_score: 0.7,
    nvc_violations: [],
    bid_type: "toward",
    sentiment: "positive",
  })!;

  assertEquals(result.tone_score as number > 0.5, true);
  assertEquals((result.nvc_violations as string[]).length, 0);
  assertEquals(result.bid_type, "toward");
  assertEquals(result.sentiment, "positive");
});

Deno.test("gt_003: neutral logistics message carries no violations", () => {
  // The most common message in any relationship. A false positive here
  // would poison every downstream score with phantom conflict signal.
  const result = validateLayerOne({
    tone_score: 0.0,
    nvc_violations: [],
    bid_type: null,
    sentiment: "neutral",
  })!;

  assertEquals(result.tone_score, 0);
  assertEquals((result.nvc_violations as string[]).length, 0);
  assertEquals(result.bid_type, null);
  assertEquals(result.sentiment, "neutral");
});

// ---------------------------------------------------------------------------
// Range and allowlist enforcement
// ---------------------------------------------------------------------------

Deno.test("tone_score is clamped to [-1, 1]", () => {
  // A hallucinated magnitude must not escape into pulse maths, where it
  // would silently skew a weighted average well outside its intended
  // range.
  assertEquals(validateLayerOne({ tone_score: -47 })!.tone_score, -1);
  assertEquals(validateLayerOne({ tone_score: 12 })!.tone_score, 1);
  assertEquals(validateLayerOne({ tone_score: -0.5 })!.tone_score, -0.5);
});

Deno.test("non-numeric tone_score is omitted, not coerced", () => {
  // Omitted rather than defaulted to 0: absent means "not analysed",
  // whereas 0 means "analysed, perfectly neutral". Coercing would invent
  // a data point.
  assertEquals("tone_score" in validateLayerOne({ tone_score: "very bad" })!, false);
  assertEquals("tone_score" in validateLayerOne({ tone_score: null })!, false);
  assertEquals("tone_score" in validateLayerOne({})!, false);
});

Deno.test("unrecognised nvc_violations are dropped", () => {
  // The model inventing a new taxonomy entry must never widen the schema
  // by writing an unknown value into the column.
  const result = validateLayerOne({
    nvc_violations: ["contempt", "gaslighting", "stonewalling", "demand"],
  })!;
  assertEquals(result.nvc_violations, ["contempt", "demand"]);
});

Deno.test("every allowed nvc violation survives validation", () => {
  // Guards the opposite failure: an over-strict filter silently discarding
  // real signal.
  const all = [
    "blame_language",
    "you_always_never",
    "character_attack",
    "contempt",
    "demand",
  ];
  assertEquals(validateLayerOne({ nvc_violations: all })!.nvc_violations, all);
});

Deno.test("nvc_violations defaults to an empty array, never null", () => {
  // markMessageDone writes this straight to a column; null would differ
  // from "analysed, no violations" for every consumer that counts them.
  assertEquals(validateLayerOne({})!.nvc_violations, []);
  assertEquals(validateLayerOne({ nvc_violations: "contempt" })!.nvc_violations, []);
  assertEquals(validateLayerOne({ nvc_violations: null })!.nvc_violations, []);
});

Deno.test("non-string entries inside nvc_violations are dropped", () => {
  const result = validateLayerOne({
    nvc_violations: ["contempt", 42, null, { x: 1 }, "demand"],
  })!;
  assertEquals(result.nvc_violations, ["contempt", "demand"]);
});

Deno.test("bid_type and sentiment reject values outside their enums", () => {
  assertEquals(validateLayerOne({ bid_type: "sideways" })!.bid_type, null);
  assertEquals("sentiment" in validateLayerOne({ sentiment: "furious" })!, false);
  for (const bid of ["toward", "away", "against"]) {
    assertEquals(validateLayerOne({ bid_type: bid })!.bid_type, bid);
  }
  for (const s of ["positive", "neutral", "negative", "charged"]) {
    assertEquals(validateLayerOne({ sentiment: s })!.sentiment, s);
  }
});

// ---------------------------------------------------------------------------
// Failure and empty-input behaviour (§6.7)
// ---------------------------------------------------------------------------

Deno.test("null input returns null — the documented skip signal", () => {
  // §6: "null from Layer 1 = skip insight for this message, mark
  // message_analysis_done: true anyway". Returning {} here would persist a
  // fabricated empty analysis as though it were real.
  assertEquals(validateLayerOne(null), null);
});

Deno.test("empty object yields a valid, minimal analysis", () => {
  const result = validateLayerOne({})!;
  assertEquals(result, { nvc_violations: [], bid_type: null });
});

Deno.test("unexpected extra keys are not passed through", () => {
  // The model returning additional fields must not smuggle them into the
  // messages table — the update payload is spread directly onto the row.
  const result = validateLayerOne({
    tone_score: 0.1,
    injected_column: "DROP TABLE messages",
    raw_message_text: "the user's private message",
  })!;
  assertEquals("injected_column" in result, false);
  // Especially this: echoing raw content back into a column would breach
  // §10's "verdicts never contain raw messages" for downstream readers.
  assertEquals("raw_message_text" in result, false);
});

// ---------------------------------------------------------------------------
// Task 5: message_analysis_skipped exclusion at this file's two real query
// sites (candidate selection in loadMessages, and the mark-done exclusion
// in markMessageDone). Runs against a real Postgres connection (the same
// attune_test database supabase/tests/*.sql uses -- built by
// `scripts/local_pg_setup.sh --no-tests`), through a service-role-shaped
// test double (see _shared/test_support/pg_rls_client.ts's
// makeServiceRoleClient), because analyse-message/index.ts calls
// serviceRoleClient() in production, not a per-user RLS client.
//
// Requires: scripts/local_pg_setup.sh --no-tests
// Run: deno test --allow-net --allow-env --allow-read --allow-sys
//        supabase/functions/analyse-message/index.test.ts

const REL_T5 = "a5100000-0000-0000-0000-000000000001";
const USER_T5_A = "a5100000-0000-0000-0000-00000000000a";
const USER_T5_B = "a5100000-0000-0000-0000-00000000000b";
const MSG_DONE = "a5100000-0000-0000-0000-000000000101";
const MSG_PENDING = "a5100000-0000-0000-0000-000000000102";
const MSG_SKIPPED = "a5100000-0000-0000-0000-000000000103";

async function resetTask5Fixtures(): Promise<void> {
  await serviceRoleQuery(
    `DELETE FROM public.messages WHERE relationship_id = $1`,
    [REL_T5],
  );
  await serviceRoleQuery(
    `DELETE FROM public.relationships WHERE id = $1`,
    [REL_T5],
  );
  await serviceRoleQuery(
    `DELETE FROM public.users WHERE id IN ($1, $2)`,
    [USER_T5_A, USER_T5_B],
  );
  await serviceRoleQuery(
    `DELETE FROM auth.users WHERE id IN ($1, $2)`,
    [USER_T5_A, USER_T5_B],
  );
  await serviceRoleQuery(
    `INSERT INTO auth.users (id, email) VALUES ($1, $2), ($3, $4)`,
    [USER_T5_A, "am_t5_a@t.test", USER_T5_B, "am_t5_b@t.test"],
  );
  await serviceRoleQuery(
    `INSERT INTO public.users (id, phone, display_name) VALUES
      ($1, '+15551115001', 'T5A'), ($2, '+15551115002', 'T5B')`,
    [USER_T5_A, USER_T5_B],
  );
  await serviceRoleQuery(
    `INSERT INTO public.relationships (id, user_a, user_b, status) VALUES ($1, $2, $3, 'active')`,
    [REL_T5, USER_T5_A, USER_T5_B],
  );
  await serviceRoleQuery(
    `INSERT INTO public.messages
      (id, relationship_id, sender_id, client_message_id, content, source,
       message_analysis_done, message_analysis_skipped, safety_processed_at)
     VALUES
      ($1, $4, $5, gen_random_uuid(), 'already analysed', 'native', true, false, now()),
      ($2, $4, $5, gen_random_uuid(), 'pending analysis', 'native', false, false, now()),
      ($3, $4, $5, gen_random_uuid(), 'deliberately skipped', 'native', false, true, now())`,
    [MSG_DONE, MSG_PENDING, MSG_SKIPPED, REL_T5, USER_T5_A],
  );
}

Deno.test({
  name: "loadMessages candidate-selection query never returns a message_analysis_skipped = true row",
  fn: async () => {
    await resetTask5Fixtures();
    const client = await makeServiceRoleClient();
    const rows = await loadMessages(client as never, { messageId: null, limit: 20 });
    const ids = rows.map((r: Record<string, unknown>) => r.id);
    assertEquals(ids.includes(MSG_SKIPPED), false);
    assertEquals(ids.includes(MSG_PENDING), true);
    assertEquals(ids.includes(MSG_DONE), false);
  },
});

Deno.test({
  name: "loadMessages requested by exact message_id still excludes a skipped message",
  fn: async () => {
    await resetTask5Fixtures();
    const client = await makeServiceRoleClient();
    const rows = await loadMessages(client as never, { messageId: MSG_SKIPPED, limit: 20 });
    assertEquals(rows.length, 0);
  },
});

Deno.test({
  name: "markMessageDone's own exclusion guard never flips a skipped message's message_analysis_done",
  fn: async () => {
    await resetTask5Fixtures();
    const client = await makeServiceRoleClient();
    await markMessageDone(client as never, MSG_SKIPPED, { tone_score: 0.5 });
    const rows = await serviceRoleQuery(
      `SELECT message_analysis_done FROM public.messages WHERE id = $1`,
      [MSG_SKIPPED],
    );
    assertEquals(rows[0].message_analysis_done, false);
  },
});

Deno.test({
  name: "markMessageDone still marks a genuinely pending (not skipped) message done",
  fn: async () => {
    await resetTask5Fixtures();
    const client = await makeServiceRoleClient();
    await markMessageDone(client as never, MSG_PENDING, { tone_score: 0.1 });
    const rows = await serviceRoleQuery(
      `SELECT message_analysis_done FROM public.messages WHERE id = $1`,
      [MSG_PENDING],
    );
    assertEquals(rows[0].message_analysis_done, true);
  },
});

Deno.test({
  name: "teardown: close shared pg connection (analyse-message)",
  fn: async () => {
    const client = await getSharedPgClient();
    await client.end();
  },
});

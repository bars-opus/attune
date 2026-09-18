// ai-understand edge function tests (Plan A, Task 7). Spec §4.1, §6,
// §9, §11.
//
// Follows ai-assist/index.test.ts's established pattern: no HTTP-mocking
// framework -- test the exported functions directly, against a real
// Postgres connection to the throwaway attune_test database, with a fake
// callGemini injected through UnderstandDeps.
//
// processUnderstandRequest (not handleRequest) is the entry point under
// test -- see ai-assist/index.test.ts's comment on handleRequest for why.
//
// Requires: scripts/local_pg_setup.sh --no-tests
// Run: deno test --allow-net --allow-env --allow-read --allow-sys
//        supabase/functions/ai-understand/index.test.ts

import { assertEquals, assertFalse } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  processUnderstandRequest,
  validateUnderstandRequest,
  validateUnderstandOutput,
  containsContextEcho,
  UnderstandDeps,
} from "./index.ts";
import {
  makeRlsClientForUser,
  serviceRoleQuery,
} from "../_shared/test_support/pg_rls_client.ts";

const REL_T7 = "a7200000-0000-0000-0000-000000000001";
const USER_T7_A = "a7200000-0000-0000-0000-00000000000a";
const USER_T7_B = "a7200000-0000-0000-0000-00000000000b";
// Sent by B -- eligible target for A's Understand request.
const MSG_FROM_B = "a7200000-0000-0000-0000-000000000101";
// Sent by A -- ineligible target for A's own Understand request
// (contract: Understand-on-own-message is rejected).
const MSG_FROM_A = "a7200000-0000-0000-0000-000000000102";

async function resetFixtures(): Promise<void> {
  await serviceRoleQuery(`DELETE FROM public.ai_assistant_usage WHERE relationship_id = $1`, [REL_T7]);
  await serviceRoleQuery(`DELETE FROM public.ai_processing_consent_events WHERE relationship_id = $1`, [REL_T7]);
  await serviceRoleQuery(`DELETE FROM public.messages WHERE relationship_id = $1`, [REL_T7]);
  await serviceRoleQuery(`DELETE FROM public.relationships WHERE id = $1`, [REL_T7]);
  await serviceRoleQuery(`DELETE FROM public.users WHERE id IN ($1, $2)`, [USER_T7_A, USER_T7_B]);
  await serviceRoleQuery(`DELETE FROM auth.users WHERE id IN ($1, $2)`, [USER_T7_A, USER_T7_B]);
  await serviceRoleQuery(
    `INSERT INTO auth.users (id, email) VALUES ($1, $2), ($3, $4)`,
    [USER_T7_A, "ai7_a@t.test", USER_T7_B, "ai7_b@t.test"],
  );
  await serviceRoleQuery(
    `INSERT INTO public.users (id, phone, display_name) VALUES
      ($1, '+15551117001', 'T7A'), ($2, '+15551117002', 'T7B')`,
    [USER_T7_A, USER_T7_B],
  );
  await serviceRoleQuery(
    `INSERT INTO public.relationships (id, user_a, user_b, status) VALUES ($1, $2, $3, 'active')`,
    [REL_T7, USER_T7_A, USER_T7_B],
  );
  await serviceRoleQuery(
    `INSERT INTO public.messages
      (id, relationship_id, sender_id, client_message_id, content, source)
     VALUES
      ($1, $3, $4, gen_random_uuid(), 'can you grab milk on your way home tonight', 'native'),
      ($2, $3, $5, gen_random_uuid(), 'sure, no problem', 'native')`,
    [MSG_FROM_B, MSG_FROM_A, REL_T7, USER_T7_B, USER_T7_A],
  );
}

async function grantDualConsent(): Promise<void> {
  const clientA = await makeRlsClientForUser(USER_T7_A);
  const clientB = await makeRlsClientForUser(USER_T7_B);
  await clientA.rpc("record_ai_processing_consent", {
    p_relationship_id: REL_T7,
    p_action: "granted",
    p_idempotency_key: crypto.randomUUID(),
  });
  await clientB.rpc("record_ai_processing_consent", {
    p_relationship_id: REL_T7,
    p_action: "granted",
    p_idempotency_key: crypto.randomUUID(),
  });
}

function makeReq(body: unknown): Request {
  return new Request("http://localhost/ai-understand", {
    method: "POST",
    body: JSON.stringify(body),
  });
}

function neverCalledGemini(): UnderstandDeps["callGemini"] {
  return () => {
    throw new Error("callGemini must not be called for this test case");
  };
}

const validBody = () => ({
  request_id: crypto.randomUUID(),
  message_id: MSG_FROM_B,
  utc_offset_minutes: 0,
});

// ---------------------------------------------------------------------------
// Source-dependency guarantee (spec §6.3): this is the enforcement for the
// no-write/no-share contract, checked by grepping the ACTUAL source file,
// not just by reading the code once.
// ---------------------------------------------------------------------------

Deno.test("ai-understand's source does not import the chat repository, any message-mutation client, or share_ai_assist_draft", async () => {
  const src = await Deno.readTextFile(new URL("./index.ts", import.meta.url));
  assertFalse(src.includes("share_ai_assist_draft"), "must never call share_ai_assist_draft");
  assertFalse(src.includes("insert_ai_assist_draft"), "must never call insert_ai_assist_draft");
  assertFalse(/\bfrom\(\s*["']messages["']\s*\)/.test(src), "must never query/write the messages table directly");
  assertFalse(src.includes("chat_repository"), "must never import a chat repository");
  assertFalse(src.includes("serviceRoleClient"), "must never use a service-role connection (no write path needs one)");
});

// ---------------------------------------------------------------------------
// Request validation.
// ---------------------------------------------------------------------------

Deno.test("a request missing message_id is rejected", () => {
  const result = validateUnderstandRequest({
    request_id: crypto.randomUUID(),
    utc_offset_minutes: 0,
  });
  assertEquals(result.ok, false);
});

Deno.test("a request with an out-of-range utc_offset_minutes is rejected", () => {
  const result = validateUnderstandRequest({ ...validBody(), utc_offset_minutes: 900 });
  assertEquals(result.ok, false);
});

Deno.test("a request with a non-integer utc_offset_minutes is rejected", () => {
  const result = validateUnderstandRequest({ ...validBody(), utc_offset_minutes: 30.5 });
  assertEquals(result.ok, false);
});

Deno.test("a request with an extra unknown field is rejected", () => {
  const result = validateUnderstandRequest({ ...validBody(), extra: "x" });
  assertEquals(result.ok, false);
});

// ---------------------------------------------------------------------------
// Understand-on-own-message rejection (spec §3: sender_id != auth.uid()).
// ---------------------------------------------------------------------------

Deno.test({
  name: "understanding one's own message is rejected TARGET_UNAVAILABLE, no provider call, no usage row",
  fn: async () => {
    await resetFixtures();
    await grantDualConsent();
    const client = await makeRlsClientForUser(USER_T7_A);
    const response = await processUnderstandRequest(
      makeReq({ ...validBody(), message_id: MSG_FROM_A }),
      { client: client as never, user: { id: USER_T7_A } },
      { callGemini: neverCalledGemini() },
    );
    assertEquals(response.status, 404);
    const body = await response.json();
    assertEquals(body.code, "TARGET_UNAVAILABLE");

    const usageRows = await serviceRoleQuery(
      `SELECT * FROM public.ai_assistant_usage WHERE relationship_id = $1`,
      [REL_T7],
    );
    assertEquals(usageRows.length, 0);
  },
});

Deno.test({
  name: "consent not yet granted returns CONSENT_REQUIRED and performs no provider call",
  fn: async () => {
    await resetFixtures();
    const client = await makeRlsClientForUser(USER_T7_A);
    const response = await processUnderstandRequest(
      makeReq(validBody()),
      { client: client as never, user: { id: USER_T7_A } },
      { callGemini: neverCalledGemini() },
    );
    assertEquals(response.status, 403);
    const body = await response.json();
    assertEquals(body.code, "CONSENT_REQUIRED");
  },
});

// ---------------------------------------------------------------------------
// Cache-Control: no-store on every response.
// ---------------------------------------------------------------------------

Deno.test({
  name: "every response, success or failure, carries Cache-Control: no-store",
  fn: async () => {
    await resetFixtures();
    // Failure branch (no consent granted).
    const client = await makeRlsClientForUser(USER_T7_A);
    const failResponse = await processUnderstandRequest(
      makeReq(validBody()),
      { client: client as never, user: { id: USER_T7_A } },
      { callGemini: neverCalledGemini() },
    );
    assertEquals(failResponse.headers.get("Cache-Control"), "no-store");

    // Success branch.
    await grantDualConsent();
    const fakeGemini: UnderstandDeps["callGemini"] = () => Promise.resolve({
      status: "ok",
      possible_readings: [
        "They may be asking for a small favor on your way home.",
        "They might be checking whether you have time before you arrive.",
      ],
      response_options: ["Sure, I can grab that.", "I might be running late, can it wait?"],
      confidence: "low",
    });
    const okResponse = await processUnderstandRequest(
      makeReq(validBody()),
      { client: client as never, user: { id: USER_T7_A } },
      { callGemini: fakeGemini },
    );
    assertEquals(okResponse.headers.get("Cache-Control"), "no-store");
  },
});

// ---------------------------------------------------------------------------
// cannot_help: unsafe_to_infer never reveals safety-pipeline state.
// ---------------------------------------------------------------------------

Deno.test({
  name: "a cannot_help: unsafe_to_infer result contains no field/value derived from safety state",
  fn: async () => {
    await resetFixtures();
    await grantDualConsent();
    const client = await makeRlsClientForUser(USER_T7_A);
    const fakeGemini: UnderstandDeps["callGemini"] = () => Promise.resolve({
      status: "cannot_help",
      reason: "unsafe_to_infer",
    });
    const response = await processUnderstandRequest(
      makeReq(validBody()),
      { client: client as never, user: { id: USER_T7_A } },
      { callGemini: fakeGemini },
    );
    assertEquals(response.status, 200);
    const body = await response.json();
    assertEquals(body, { status: "cannot_help", reason: "unsafe_to_infer" });
    // The response shape is exhaustively checked above -- there is no
    // safety_processed_at, safety_error_code, or any other key. This
    // assertion double-checks the object has EXACTLY these two keys, so
    // a future change that quietly adds a safety-derived field would
    // fail here.
    assertEquals(Object.keys(body).sort(), ["reason", "status"]);
  },
});

// ---------------------------------------------------------------------------
// Successful Understand call -- returns the model result directly, never
// writes/shares anything.
// ---------------------------------------------------------------------------

Deno.test({
  name: "a successful Understand call returns possible_readings/response_options/confidence and creates no messages/drafts row",
  fn: async () => {
    await resetFixtures();
    await grantDualConsent();
    const client = await makeRlsClientForUser(USER_T7_A);
    const fakeGemini: UnderstandDeps["callGemini"] = () => Promise.resolve({
      status: "ok",
      possible_readings: [
        "They may be asking for a small favor on your way home.",
        "They might be checking whether you have time before you arrive.",
      ],
      response_options: ["Sure, I can grab that.", "I might be running late, can it wait?"],
      confidence: "low",
    });

    const messageCountBefore = await serviceRoleQuery(
      `SELECT count(*)::int AS n FROM public.messages WHERE relationship_id = $1`,
      [REL_T7],
    );

    const response = await processUnderstandRequest(
      makeReq(validBody()),
      { client: client as never, user: { id: USER_T7_A } },
      { callGemini: fakeGemini },
    );
    assertEquals(response.status, 200);
    const body = await response.json();
    assertEquals(body.status, "ok");
    assertEquals(body.confidence, "low");
    assertEquals(body.possible_readings.length, 2);
    assertEquals(body.response_options.length, 2);

    const messageCountAfter = await serviceRoleQuery(
      `SELECT count(*)::int AS n FROM public.messages WHERE relationship_id = $1`,
      [REL_T7],
    );
    assertEquals(messageCountAfter[0].n, messageCountBefore[0].n);

    const draftRows = await serviceRoleQuery(
      `SELECT count(*)::int AS n FROM public.ai_assist_drafts WHERE relationship_id = $1`,
      [REL_T7],
    );
    assertEquals(draftRows[0].n, 0);
  },
});

// ---------------------------------------------------------------------------
// validateUnderstandOutput: shape/enum/length/cardinality checks.
// ---------------------------------------------------------------------------

Deno.test("validateUnderstandOutput rejects an unknown top-level field", () => {
  const result = validateUnderstandOutput(
    {
      status: "ok",
      possible_readings: ["a plausible reading of the message", "another plausible reading here"],
      response_options: ["okay sounds good", "let me get back to you"],
      confidence: "low",
      extra: "nope",
    },
    ["some context text"],
  );
  assertEquals(result, null);
});

Deno.test("validateUnderstandOutput rejects confidence: high", () => {
  const result = validateUnderstandOutput(
    {
      status: "ok",
      possible_readings: ["a plausible reading of the message", "another plausible reading here"],
      response_options: ["okay sounds good", "let me get back to you"],
      confidence: "high",
    },
    ["some context text"],
  );
  assertEquals(result, null);
});

Deno.test("validateUnderstandOutput rejects a cannot_help reason outside the enum", () => {
  const result = validateUnderstandOutput(
    { status: "cannot_help", reason: "not_a_real_reason" },
    ["some context text"],
  );
  assertEquals(result, null);
});

Deno.test("validateUnderstandOutput rejects fewer than 2 possible_readings", () => {
  const result = validateUnderstandOutput(
    {
      status: "ok",
      possible_readings: ["only one reading here"],
      response_options: ["okay sounds good", "let me get back to you"],
      confidence: "low",
    },
    ["some context text"],
  );
  assertEquals(result, null);
});

// ---------------------------------------------------------------------------
// Context-echo rejection (spec §9 item 7) -- the mutation-tested contract.
// ---------------------------------------------------------------------------

const SEEDED_CONTEXT = [
  "can you grab milk on your way home tonight and also stop by the pharmacy for me please",
];

Deno.test("containsContextEcho detects an 8+ token verbatim quote from context", () => {
  const echoed = "can you grab milk on your way home tonight and also stop by";
  assertEquals(containsContextEcho(echoed, SEEDED_CONTEXT), true);
});

Deno.test("containsContextEcho does not flag a genuinely paraphrased sentence of similar length", () => {
  const paraphrased = "they are asking whether you could pick up a couple of items while you are out this evening";
  assertEquals(containsContextEcho(paraphrased, SEEDED_CONTEXT), false);
});

Deno.test("validateUnderstandOutput rejects a response containing a verbatim 8+ token context echo", () => {
  const result = validateUnderstandOutput(
    {
      status: "ok",
      possible_readings: [
        "can you grab milk on your way home tonight and also stop by the pharmacy",
        "a second plausible reading of the message",
      ],
      response_options: ["okay sounds good", "let me get back to you"],
      confidence: "low",
    },
    SEEDED_CONTEXT,
  );
  assertEquals(result, null);
});

Deno.test("validateUnderstandOutput accepts a genuinely paraphrased response of similar length", () => {
  const result = validateUnderstandOutput(
    {
      status: "ok",
      possible_readings: [
        "they are asking whether you could pick up a couple of items while you are out this evening",
        "they might simply be reminding you before you leave the house",
      ],
      response_options: ["sure, I can do that", "I might be a bit late, is that okay"],
      confidence: "low",
    },
    SEEDED_CONTEXT,
  );
  assertEquals(result?.status, "ok");
});

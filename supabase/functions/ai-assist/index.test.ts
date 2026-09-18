// ai-assist edge function tests (Plan A, Task 6). Spec §4.1, §5.1-§5.3,
// §7.3, §9, §11.
//
// Follows this repo's established pattern (analyse-message/index.test.ts,
// ai_context_loader.test.ts): no HTTP-mocking framework -- test the
// exported functions directly, against a real Postgres connection to the
// throwaway attune_test database via test_support/pg_rls_client.ts's
// real-RLS adapter, with fake callGemini/searchMapbox injected through
// AssistDeps.
//
// processAssistRequest (not handleRequest) is the entry point under test:
// handleRequest's only extra responsibility is calling userScopedClient(),
// which needs a real signed JWT verified against a running GoTrue -- not
// available in this environment (see user_scoped_client.test.ts's own
// note). processAssistRequest receives the {client, user} context
// directly, exactly mirroring what userScopedClient would have produced.
//
// Requires: scripts/local_pg_setup.sh --no-tests
// Run: deno test --allow-net --allow-env --allow-read --allow-sys
//        supabase/functions/ai-assist/index.test.ts

import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  processAssistRequest,
  validateAssistRequest,
  validateIdeasOutput,
  validateNearbyCategoryOutput,
  AssistDeps,
} from "./index.ts";
import {
  getSharedPgClient,
  makeRlsClientForUser,
  makeServiceRoleClient,
  serviceRoleQuery,
} from "../_shared/test_support/pg_rls_client.ts";

const REL_T6 = "a6100000-0000-0000-0000-000000000001";
const USER_T6_A = "a6100000-0000-0000-0000-00000000000a";
const USER_T6_B = "a6100000-0000-0000-0000-00000000000b";
const MSG_TARGET = "a6100000-0000-0000-0000-000000000101";

async function resetFixtures(): Promise<void> {
  await serviceRoleQuery(`DELETE FROM public.ai_assist_drafts WHERE relationship_id = $1`, [REL_T6]);
  await serviceRoleQuery(`DELETE FROM public.ai_assistant_usage WHERE relationship_id = $1`, [REL_T6]);
  await serviceRoleQuery(`DELETE FROM public.ai_processing_consent_events WHERE relationship_id = $1`, [REL_T6]);
  await serviceRoleQuery(`DELETE FROM public.messages WHERE relationship_id = $1`, [REL_T6]);
  await serviceRoleQuery(`DELETE FROM public.relationships WHERE id = $1`, [REL_T6]);
  await serviceRoleQuery(`DELETE FROM public.users WHERE id IN ($1, $2)`, [USER_T6_A, USER_T6_B]);
  await serviceRoleQuery(`DELETE FROM auth.users WHERE id IN ($1, $2)`, [USER_T6_A, USER_T6_B]);
  await serviceRoleQuery(
    `INSERT INTO auth.users (id, email) VALUES ($1, $2), ($3, $4)`,
    [USER_T6_A, "ai6_a@t.test", USER_T6_B, "ai6_b@t.test"],
  );
  await serviceRoleQuery(
    `INSERT INTO public.users (id, phone, display_name) VALUES
      ($1, '+15551116001', 'T6A'), ($2, '+15551116002', 'T6B')`,
    [USER_T6_A, USER_T6_B],
  );
  await serviceRoleQuery(
    `INSERT INTO public.relationships (id, user_a, user_b, status) VALUES ($1, $2, $3, 'active')`,
    [REL_T6, USER_T6_A, USER_T6_B],
  );
  await serviceRoleQuery(
    `INSERT INTO public.messages
      (id, relationship_id, sender_id, client_message_id, content, source)
     VALUES ($1, $2, $3, gen_random_uuid(), 'want to get dinner tonight?', 'native')`,
    [MSG_TARGET, REL_T6, USER_T6_B],
  );
}

async function grantDualConsent(): Promise<void> {
  const clientA = await makeRlsClientForUser(USER_T6_A);
  const clientB = await makeRlsClientForUser(USER_T6_B);
  await clientA.rpc("record_ai_processing_consent", {
    p_relationship_id: REL_T6,
    p_action: "granted",
    p_idempotency_key: crypto.randomUUID(),
  });
  await clientB.rpc("record_ai_processing_consent", {
    p_relationship_id: REL_T6,
    p_action: "granted",
    p_idempotency_key: crypto.randomUUID(),
  });
}

function makeReq(body: unknown): Request {
  return new Request("http://localhost/ai-assist", {
    method: "POST",
    body: JSON.stringify(body),
  });
}

function neverCalledGemini(): AssistDeps["callGemini"] {
  return () => {
    throw new Error("callGemini must not be called for this test case");
  };
}

function neverCalledMapbox(): AssistDeps["searchMapbox"] {
  return () => {
    throw new Error("searchMapbox must not be called for this test case");
  };
}

const validIdeasBody = () => ({
  request_id: crypto.randomUUID(),
  message_id: MSG_TARGET,
  assist_kind: "ideas",
  user_instruction: null,
  requester_location: null,
});

// ---------------------------------------------------------------------------
// Request validation -- fails before any DB/provider work.
// ---------------------------------------------------------------------------

Deno.test("a request missing message_id is rejected INVALID_INPUT before any DB/provider work", () => {
  const result = validateAssistRequest({
    request_id: crypto.randomUUID(),
    assist_kind: "ideas",
  });
  assertEquals(result.ok, false);
});

Deno.test("a request with an extra unknown field is rejected", () => {
  const result = validateAssistRequest({
    ...validIdeasBody(),
    unexpected_field: "hello",
  });
  assertEquals(result.ok, false);
});

Deno.test("a request with an unknown field inside requester_location is rejected", () => {
  const result = validateAssistRequest({
    request_id: crypto.randomUUID(),
    message_id: MSG_TARGET,
    assist_kind: "nearby",
    user_instruction: null,
    requester_location: { latitude: 1, longitude: 1, accuracy_m: 5, extra: "x" },
  });
  assertEquals(result.ok, false);
});

Deno.test({
  name: "assist_kind: 'nearby' with requester_location: null is rejected LOCATION_REQUIRED, no provider call",
  fn: async () => {
    await resetFixtures();
    await grantDualConsent();
    const client = await makeRlsClientForUser(USER_T6_A);
    const response = await processAssistRequest(
      makeReq({
        request_id: crypto.randomUUID(),
        message_id: MSG_TARGET,
        assist_kind: "nearby",
        user_instruction: null,
        requester_location: null,
      }),
      { client: client as never, user: { id: USER_T6_A } },
      { callGemini: neverCalledGemini(), searchMapbox: neverCalledMapbox() },
    );
    assertEquals(response.status, 400);
    const body = await response.json();
    assertEquals(body.code, "LOCATION_REQUIRED");
  },
});

// ---------------------------------------------------------------------------
// Consent gating -- before quota, before any provider call.
// ---------------------------------------------------------------------------

Deno.test({
  name: "consent not yet granted returns CONSENT_REQUIRED and performs no provider call, no usage row",
  fn: async () => {
    await resetFixtures();
    // Deliberately do NOT grant consent.
    const client = await makeRlsClientForUser(USER_T6_A);
    const response = await processAssistRequest(
      makeReq(validIdeasBody()),
      { client: client as never, user: { id: USER_T6_A } },
      { callGemini: neverCalledGemini(), searchMapbox: neverCalledMapbox() },
    );
    assertEquals(response.status, 403);
    const body = await response.json();
    assertEquals(body.code, "CONSENT_REQUIRED");

    const usageRows = await serviceRoleQuery(
      `SELECT * FROM public.ai_assistant_usage WHERE relationship_id = $1`,
      [REL_T6],
    );
    assertEquals(usageRows.length, 0);
  },
});

// ---------------------------------------------------------------------------
// Target load failure -- before quota is reserved.
// ---------------------------------------------------------------------------

Deno.test({
  name: "a target that fails loadAiAssistantTarget returns TARGET_UNAVAILABLE before quota is reserved",
  fn: async () => {
    await resetFixtures();
    await grantDualConsent();
    const client = await makeRlsClientForUser(USER_T6_A);
    const response = await processAssistRequest(
      makeReq({ ...validIdeasBody(), message_id: crypto.randomUUID() }),
      { client: client as never, user: { id: USER_T6_A } },
      { callGemini: neverCalledGemini(), searchMapbox: neverCalledMapbox() },
    );
    assertEquals(response.status, 404);
    const body = await response.json();
    assertEquals(body.code, "TARGET_UNAVAILABLE");

    const usageRows = await serviceRoleQuery(
      `SELECT * FROM public.ai_assistant_usage WHERE relationship_id = $1`,
      [REL_T6],
    );
    assertEquals(usageRows.length, 0);
  },
});

// ---------------------------------------------------------------------------
// Successful Ideas call.
// ---------------------------------------------------------------------------

Deno.test({
  name: "a successful Ideas call inserts exactly one ai_assist_drafts row and returns its contents, never auto-posting a message",
  fn: async () => {
    await resetFixtures();
    await grantDualConsent();
    const client = await makeRlsClientForUser(USER_T6_A);
    const serviceClient = await makeServiceRoleClient();

    const fakeGemini: AssistDeps["callGemini"] = () => Promise.resolve({
      reply_text: "How about that new ramen place downtown?",
      suggested_planning_item: null,
    });

    const response = await processAssistRequest(
      makeReq(validIdeasBody()),
      { client: client as never, user: { id: USER_T6_A } },
      { callGemini: fakeGemini, searchMapbox: neverCalledMapbox(), serviceClient: serviceClient as never },
    );

    assertEquals(response.status, 200);
    const body = await response.json();
    assertEquals(body.reply_text, "How about that new ramen place downtown?");
    assertEquals(body.suggested_planning_item, null);

    const draftRows = await serviceRoleQuery(
      `SELECT * FROM public.ai_assist_drafts WHERE relationship_id = $1`,
      [REL_T6],
    );
    assertEquals(draftRows.length, 1);
    assertEquals(draftRows[0].reply_text, "How about that new ramen place downtown?");

    const messageRows = await serviceRoleQuery(
      `SELECT * FROM public.messages WHERE relationship_id = $1 AND message_origin = 'attune_assist'`,
      [REL_T6],
    );
    assertEquals(messageRows.length, 0);
  },
});

// ---------------------------------------------------------------------------
// Nearby category allowlist enforcement -- the highest-priority mutation
// target. An out-of-allowlist category from Gemini must never reach
// Mapbox.
// ---------------------------------------------------------------------------

Deno.test({
  name: "a successful Nearby call with a fake Gemini response outside the allowlisted category set is rejected server-side, never forwarded to Mapbox",
  fn: async () => {
    await resetFixtures();
    await grantDualConsent();
    const client = await makeRlsClientForUser(USER_T6_A);

    const fakeGemini: AssistDeps["callGemini"] = () => Promise.resolve({
      category: "bar_or_nightclub", // NOT in the fixed allowlist
    });

    const response = await processAssistRequest(
      makeReq({
        request_id: crypto.randomUUID(),
        message_id: MSG_TARGET,
        assist_kind: "nearby",
        user_instruction: null,
        requester_location: { latitude: 5.6, longitude: -0.19, accuracy_m: 20 },
      }),
      { client: client as never, user: { id: USER_T6_A } },
      { callGemini: fakeGemini, searchMapbox: neverCalledMapbox() },
    );

    assertEquals(response.status, 422);
    const body = await response.json();
    assertEquals(body.code, "UNSUPPORTED_REQUEST");
  },
});

Deno.test({
  name: "a successful Nearby call with an allowlisted category DOES call Mapbox and returns its sources",
  fn: async () => {
    await resetFixtures();
    await grantDualConsent();
    const client = await makeRlsClientForUser(USER_T6_A);
    const serviceClient = await makeServiceRoleClient();

    const fakeGemini: AssistDeps["callGemini"] = () => Promise.resolve({ category: "cafe" });
    let mapboxCalled = false;
    const fakeMapbox: AssistDeps["searchMapbox"] = (category) => {
      mapboxCalled = true;
      assertEquals(category, "cafe");
      return Promise.resolve([
        {
          provider_id: "mbx.place.1",
          name: "Third Place Coffee",
          formatted_address: "12 Liberation Rd",
          category: "cafe",
          map_url: "https://www.mapbox.com/search/mbx.place.1",
        },
      ]);
    };

    const response = await processAssistRequest(
      makeReq({
        request_id: crypto.randomUUID(),
        message_id: MSG_TARGET,
        assist_kind: "nearby",
        user_instruction: null,
        requester_location: { latitude: 5.6, longitude: -0.19, accuracy_m: 20 },
      }),
      { client: client as never, user: { id: USER_T6_A } },
      { callGemini: fakeGemini, searchMapbox: fakeMapbox, serviceClient: serviceClient as never },
    );

    assertEquals(mapboxCalled, true);
    assertEquals(response.status, 200);
    const body = await response.json();
    assertEquals(body.sources.length, 1);
    assertEquals(body.sources[0].name, "Third Place Coffee");
    // Never a coordinate/distance leak into the response.
    assertEquals("distance" in body.sources[0], false);
    assertEquals("latitude" in body.sources[0], false);
  },
});

// ---------------------------------------------------------------------------
// Rate limiting -- no provider call once rate-limited.
// ---------------------------------------------------------------------------

Deno.test({
  name: "rate-limited (fake reserve_ai_assistant_quota via 20 prior reservations) returns RATE_LIMITED with retry_after_seconds, no provider call",
  fn: async () => {
    await resetFixtures();
    await grantDualConsent();
    const client = await makeRlsClientForUser(USER_T6_A);

    // Exhaust the real rolling-window quota (Task 4) for this user so the
    // 21st reservation attempt is genuinely rate_limited -- this proves
    // the ai-assist handler correctly surfaces reserve_ai_assistant_quota's
    // real outcome, not a fake bypassing the real RPC.
    for (let i = 0; i < 20; i++) {
      await client.rpc("reserve_ai_assistant_quota", {
        p_request_id: crypto.randomUUID(),
        p_relationship_id: REL_T6,
        p_mode: "assist",
      });
    }

    const response = await processAssistRequest(
      makeReq(validIdeasBody()),
      { client: client as never, user: { id: USER_T6_A } },
      { callGemini: neverCalledGemini(), searchMapbox: neverCalledMapbox() },
    );

    assertEquals(response.status, 429);
    const body = await response.json();
    assertEquals(body.code, "RATE_LIMITED");
    assertEquals(typeof body.retry_after_seconds === "number" && body.retry_after_seconds > 0, true);
  },
});

// ---------------------------------------------------------------------------
// Model output validation -- direct unit tests, no DB/provider needed.
// ---------------------------------------------------------------------------

Deno.test("validateIdeasOutput accepts a well-formed IdeasModelOutput", () => {
  const result = validateIdeasOutput({
    reply_text: "Try a picnic in the park this weekend.",
    suggested_planning_item: { kind: "event", title: "Picnic", event_date: "2026-09-20" },
  });
  assertEquals(result?.reply_text, "Try a picnic in the park this weekend.");
  assertEquals(result?.suggested_planning_item?.kind, "event");
});

Deno.test("validateIdeasOutput rejects an event with a null event_date", () => {
  const result = validateIdeasOutput({
    reply_text: "Plan a trip",
    suggested_planning_item: { kind: "event", title: "Trip", event_date: null },
  });
  assertEquals(result, null);
});

Deno.test("validateIdeasOutput rejects an unknown top-level field", () => {
  const result = validateIdeasOutput({
    reply_text: "hello",
    suggested_planning_item: null,
    extra_field: "should not be here",
  });
  assertEquals(result, null);
});

Deno.test("validateIdeasOutput rejects a task with a non-null event_date", () => {
  const result = validateIdeasOutput({
    reply_text: "hello",
    suggested_planning_item: { kind: "task", title: "Book a table", event_date: "2026-09-20" },
  });
  assertEquals(result, null);
});

Deno.test("validateNearbyCategoryOutput accepts every allowlisted category", () => {
  for (const category of ["restaurant", "cafe", "park", "cinema", "museum", "recreation"]) {
    assertEquals(validateNearbyCategoryOutput({ category })?.category, category);
  }
});

Deno.test("validateNearbyCategoryOutput rejects any value outside the fixed allowlist", () => {
  for (const category of ["bar", "hotel", "hospital", "church", "Restaurant", "restaurant "]) {
    assertEquals(validateNearbyCategoryOutput({ category }), null);
  }
});

Deno.test("validateNearbyCategoryOutput rejects a free-text search string masquerading as category", () => {
  assertEquals(
    validateNearbyCategoryOutput({ category: "best ramen near Osu" }),
    null,
  );
});

Deno.test("validateNearbyCategoryOutput rejects an unknown extra field", () => {
  assertEquals(
    validateNearbyCategoryOutput({ category: "cafe", place_name: "injected" }),
    null,
  );
});

Deno.test({
  name: "teardown: close shared pg connection (ai-assist)",
  fn: async () => {
    const client = await getSharedPgClient();
    await client.end();
  },
});

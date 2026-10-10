// ai-sessions edge function tests (Plan C, Task 1). Spec §3.1, §4.1, §10.
//
// Follows ai-assist/index.test.ts's exact pattern: no HTTP-mocking
// framework -- test the exported functions directly, against a real
// Postgres connection to the throwaway attune_test database via
// test_support/pg_rls_client.ts. Unlike ai-assist's test, the client
// here is pg_rls_client's SERVICE-ROLE adapter rather than a per-user
// RLS adapter, because every RPC this function calls is service_role-
// only (Plan B) and Plan C's Architecture note is explicit that this
// function has no user-scoped client at all.
//
// processSessionCommand (not handleRequest) is the entry point under
// test: handleRequest's only extra responsibility is requireUser(),
// which needs a real signed JWT verified against a running GoTrue --
// not available in this environment (see user_scoped_client.test.ts's
// own note). processSessionCommand receives the {user} context
// directly, exactly mirroring what requireUser would have produced.
//
// Requires: scripts/local_pg_setup.sh --no-tests
// Run: deno test --allow-net --allow-env --allow-read --allow-sys \
//        supabase/functions/ai-sessions/index.test.ts

import {
  assert,
  assertEquals,
  assertNotEquals,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  checkEligibility,
  processSessionCommand,
  SESSION_COMMANDS,
  SessionDeps,
  validateCommandEnvelope,
} from "./index.ts";
import {
  makeServiceRoleClient,
  serviceRoleQuery,
} from "../_shared/test_support/pg_rls_client.ts";

const REL_C1 = "c1000000-0000-0000-0000-000000000001";
const USER_C1_A = "c1000000-0000-0000-0000-00000000000a";
const USER_C1_B = "c1000000-0000-0000-0000-00000000000b";
const USER_OUTSIDER = "c1000000-0000-0000-0000-00000000000f";

/// Rebuilds this test file's fixtures from scratch. Two real members
/// plus one outsider, an active unarchived relationship, and NO consent
/// events -- each consent test grants explicitly, so the default state
/// is the one the eligibility gate must refuse.
async function resetFixtures(): Promise<void> {
  await serviceRoleQuery(
    `DELETE FROM public.ai_sessions WHERE relationship_id = $1`,
    [REL_C1],
  );
  await serviceRoleQuery(
    `DELETE FROM public.ai_assistant_usage WHERE relationship_id = $1`,
    [REL_C1],
  );
  await serviceRoleQuery(
    `DELETE FROM public.ai_processing_consent_events WHERE relationship_id = $1`,
    [REL_C1],
  );
  await serviceRoleQuery(`DELETE FROM public.relationships WHERE id = $1`, [
    REL_C1,
  ]);
  await serviceRoleQuery(
    `DELETE FROM public.users WHERE id IN ($1, $2, $3)`,
    [USER_C1_A, USER_C1_B, USER_OUTSIDER],
  );
  await serviceRoleQuery(
    `DELETE FROM auth.users WHERE id IN ($1, $2, $3)`,
    [USER_C1_A, USER_C1_B, USER_OUTSIDER],
  );
  await serviceRoleQuery(
    `INSERT INTO auth.users (id, email) VALUES ($1, $2), ($3, $4), ($5, $6)`,
    [
      USER_C1_A,
      "sess_c1_a@t.test",
      USER_C1_B,
      "sess_c1_b@t.test",
      USER_OUTSIDER,
      "sess_c1_out@t.test",
    ],
  );
  await serviceRoleQuery(
    `INSERT INTO public.users (id, phone, display_name) VALUES
      ($1, '+15552001001', 'C1A'),
      ($2, '+15552001002', 'C1B'),
      ($3, '+15552001003', 'C1Out')`,
    [USER_C1_A, USER_C1_B, USER_OUTSIDER],
  );
  await serviceRoleQuery(
    `INSERT INTO public.relationships (id, user_a, user_b, status)
     VALUES ($1, $2, $3, 'active')`,
    [REL_C1, USER_C1_A, USER_C1_B],
  );
}

/// Inserts a 'granted' event at the CURRENT policy version for both
/// members. clock_timestamp(), not now(): ai_consent_granted_for_
/// relationship breaks ties on (created_at DESC, id DESC), and a frozen
/// statement-level now() would make the tiebreak a random uuid --
/// intermittently green. idempotency_key is NOT NULL on the table.
async function grantDualConsent(): Promise<void> {
  await serviceRoleQuery(
    `INSERT INTO public.ai_processing_consent_events
       (relationship_id, user_id, action, policy_version, idempotency_key, created_at)
     VALUES
       ($1, $2, 'granted', public.ai_current_consent_policy_version(), gen_random_uuid(), clock_timestamp()),
       ($1, $3, 'granted', public.ai_current_consent_policy_version(), gen_random_uuid(), clock_timestamp())`,
    [REL_C1, USER_C1_A, USER_C1_B],
  );
}

function makeReq(body: unknown, method = "POST"): Request {
  return new Request("http://localhost/ai-sessions", {
    method,
    headers: { "Content-Type": "application/json" },
    body: method === "POST" ? JSON.stringify(body) : undefined,
  });
}

async function makeDeps(): Promise<SessionDeps> {
  const service = await makeServiceRoleClient();
  return { serviceClient: service as never };
}

function ctx(userId: string) {
  return { user: { id: userId, email: null, phone: null } };
}

// ---------------------------------------------------------------------------
// Envelope validation -- spec §4.1. Everything here must reject BEFORE
// any RPC runs, so each test also asserts the specific §10 code, never
// merely "an error happened".
// ---------------------------------------------------------------------------

Deno.test({
  name: "an unknown command is rejected with INVALID_INPUT before any RPC runs",
  fn: async () => {
    await resetFixtures();
    const response = await processSessionCommand(
      makeReq({
        command: "not_a_real_command",
        relationship_id: REL_C1,
      }),
      ctx(USER_C1_A),
      await makeDeps(),
    );

    assertEquals(response.status, 400);
    const body = await response.json();
    assertEquals(body.code, "INVALID_INPUT");
    // No RPC ran: nothing was created for this relationship.
    const rows = await serviceRoleQuery(
      `SELECT count(*)::int AS n FROM public.ai_sessions WHERE relationship_id = $1`,
      [REL_C1],
    );
    assertEquals(rows[0].n, 0);
  },
});

Deno.test({
  name: "a request body over 4 KiB is rejected with INVALID_INPUT",
  fn: async () => {
    await resetFixtures();
    // 'prepare' is a REAL command, so the only thing that can reject
    // this request is the size cap -- if the cap were removed, the
    // unknown-field check would still reject it, which is why the
    // assertion below also proves the cap ran first via its code AND
    // the companion test proves a 4 KiB-exact body gets past the cap.
    const response = await processSessionCommand(
      makeReq({ command: "prepare", padding: "x".repeat(5000) }),
      ctx(USER_C1_A),
      await makeDeps(),
    );

    assertEquals(response.status, 400);
    assertEquals((await response.json()).code, "INVALID_INPUT");
  },
});

Deno.test({
  name: "the 4 KiB cap counts UTF-8 bytes, not UTF-16 code units",
  fn: () => {
    // Spec §4.1: "maximum 4 KiB UTF-8 body". A 3000-character string of
    // 2-byte characters is 6000 bytes but only 3000 JS .length units, so
    // a .length-based cap would wrongly admit it.
    const payload = JSON.stringify({ command: "prepare", padding: "é".repeat(3000) });
    assert(payload.length < 4096, "must be under the cap by UTF-16 length");
    assert(
      new TextEncoder().encode(payload).length > 4096,
      "must be over the cap by UTF-8 bytes",
    );
    assertEquals(validateCommandEnvelope(payload).ok, false);
  },
});

Deno.test({
  name: "malformed JSON, non-object bodies and arrays are each INVALID_INPUT",
  fn: () => {
    for (const raw of ["{", "", "null", "7", '"a string"', "[]", '[{"command":"prepare"}]']) {
      const result = validateCommandEnvelope(raw);
      assertEquals(result.ok, false, `expected rejection for: ${raw}`);
    }
  },
});

Deno.test({
  name: "a missing or non-string command is INVALID_INPUT",
  fn: () => {
    for (const body of [{}, { command: null }, { command: 7 }, { command: ["prepare"] }]) {
      assertEquals(
        validateCommandEnvelope(JSON.stringify(body)).ok,
        false,
        `expected rejection for: ${JSON.stringify(body)}`,
      );
    }
  },
});

Deno.test({
  name: "the ENVELOPE rejects a command outside the allowlist, not the switch default",
  fn: () => {
    // Asserting only processSessionCommand's 400 would be vacuous: the
    // dispatch switch's own `default` also returns INVALID_INPUT, so a
    // missing allowlist check would be invisible from the response.
    // Assert the validator itself, which runs before any dispatch --
    // that is the boundary spec §4.1 puts the rejection on.
    for (const command of [
      "not_a_real_command",
      "prepare ",
      "Prepare",
      "review-context",
      "start",
      "__proto__",
      "",
    ]) {
      const result = validateCommandEnvelope(JSON.stringify({ command }));
      assertEquals(result.ok, false, `envelope must reject: ${JSON.stringify(command)}`);
      assertEquals(
        result.ok === false ? result.error.code : null,
        "INVALID_INPUT",
        `wrong code for: ${JSON.stringify(command)}`,
      );
    }
  },
});

Deno.test({
  name: "exactly the nine spec §4.1 commands are recognized",
  fn: () => {
    assertEquals([...SESSION_COMMANDS].sort(), [
      "approve",
      "discard_nearby",
      "end",
      "generate",
      "prepare",
      "publish_nearby",
      "read",
      "review_context",
      "share_answer",
    ]);
    assertEquals(SESSION_COMMANDS.size, 9);
    for (const command of SESSION_COMMANDS) {
      assertEquals(
        validateCommandEnvelope(JSON.stringify({ command })).ok,
        true,
        `${command} must be recognized by the envelope`,
      );
    }
  },
});

// ---------------------------------------------------------------------------
// The actor id can only come from the verified context -- Plan C's one
// Global Constraint that only this layer can violate.
// ---------------------------------------------------------------------------

Deno.test({
  name: "an actor id in the request body is rejected, never honoured",
  fn: async () => {
    await resetFixtures();
    await grantDualConsent();

    // The body names the OUTSIDER as actor while the verified context is
    // member A. If any branch ever read the body, the gate would resolve
    // the outsider. Instead the envelope rejects the field outright.
    for (const field of ["actor_id", "p_actor_id", "user_id", "requester_id", "creator_id"]) {
      const response = await processSessionCommand(
        makeReq({ command: "prepare", relationship_id: REL_C1, [field]: USER_OUTSIDER }),
        ctx(USER_C1_A),
        await makeDeps(),
      );
      assertEquals(response.status, 400, `${field} must be rejected`);
      assertEquals((await response.json()).code, "INVALID_INPUT");
    }
  },
});

Deno.test({
  name: "the eligibility gate resolves the actor from the context, ignoring the body entirely",
  fn: async () => {
    await resetFixtures();
    await grantDualConsent();
    const deps = await makeDeps();

    // Same body in both calls; only the verified context differs. A
    // member is eligible; a non-member is not. If the gate consulted the
    // body for an actor there would be nothing in it to consult -- this
    // test proves the context is load-bearing.
    const asMember = await checkEligibility(deps.serviceClient as never, USER_C1_A, REL_C1);
    const asOutsider = await checkEligibility(deps.serviceClient as never, USER_OUTSIDER, REL_C1);

    assertEquals(asMember.ok, true);
    assertEquals(asOutsider.ok, false);
    assertEquals(asOutsider.ok === false ? asOutsider.error.code : null, "UNAVAILABLE");
    assertNotEquals(asMember.ok, asOutsider.ok);
  },
});

// ---------------------------------------------------------------------------
// Eligibility gate -- spec §3.1.
// ---------------------------------------------------------------------------

Deno.test({
  name: "eligibility: a non-member gets UNAVAILABLE, never CONSENT_REQUIRED",
  fn: async () => {
    await resetFixtures();
    // Deliberately NO consent. A non-member must still get UNAVAILABLE:
    // spec §3.1 says foreign ids return the same unavailable response, and
    // telling an outsider "consent required" would confirm the
    // relationship exists.
    const deps = await makeDeps();
    const result = await checkEligibility(
      deps.serviceClient as never,
      USER_OUTSIDER,
      REL_C1,
    );
    assertEquals(result.ok, false);
    assertEquals(result.ok === false ? result.error.code : null, "UNAVAILABLE");
  },
});

Deno.test({
  name: "eligibility: an unknown relationship id gets UNAVAILABLE",
  fn: async () => {
    await resetFixtures();
    const deps = await makeDeps();
    const result = await checkEligibility(
      deps.serviceClient as never,
      USER_C1_A,
      "c1000000-0000-0000-0000-0000000009ff",
    );
    assertEquals(result.ok, false);
    assertEquals(result.ok === false ? result.error.code : null, "UNAVAILABLE");
  },
});

Deno.test({
  name: "eligibility: an archived relationship gets UNAVAILABLE even for a member with consent",
  fn: async () => {
    await resetFixtures();
    await grantDualConsent();
    await serviceRoleQuery(
      `UPDATE public.relationships SET chat_archived_at = now() WHERE id = $1`,
      [REL_C1],
    );
    const deps = await makeDeps();
    const result = await checkEligibility(deps.serviceClient as never, USER_C1_A, REL_C1);
    assertEquals(result.ok, false);
    assertEquals(result.ok === false ? result.error.code : null, "UNAVAILABLE");
  },
});

Deno.test({
  name: "eligibility: an inactive relationship gets UNAVAILABLE even for a member with consent",
  fn: async () => {
    await resetFixtures();
    await grantDualConsent();
    await serviceRoleQuery(
      `UPDATE public.relationships SET status = 'ended' WHERE id = $1`,
      [REL_C1],
    );
    const deps = await makeDeps();
    const result = await checkEligibility(deps.serviceClient as never, USER_C1_A, REL_C1);
    assertEquals(result.ok, false);
    assertEquals(result.ok === false ? result.error.code : null, "UNAVAILABLE");
  },
});

Deno.test({
  name: "eligibility: a member of a live relationship WITHOUT dual consent gets CONSENT_REQUIRED",
  fn: async () => {
    await resetFixtures();
    const deps = await makeDeps();
    const result = await checkEligibility(deps.serviceClient as never, USER_C1_A, REL_C1);
    assertEquals(result.ok, false);
    assertEquals(result.ok === false ? result.error.code : null, "CONSENT_REQUIRED");
  },
});

Deno.test({
  name: "eligibility: one-sided consent is not enough",
  fn: async () => {
    await resetFixtures();
    await serviceRoleQuery(
      `INSERT INTO public.ai_processing_consent_events
         (relationship_id, user_id, action, policy_version, idempotency_key, created_at)
       VALUES ($1, $2, 'granted', public.ai_current_consent_policy_version(), gen_random_uuid(), clock_timestamp())`,
      [REL_C1, USER_C1_A],
    );
    const deps = await makeDeps();
    const result = await checkEligibility(deps.serviceClient as never, USER_C1_A, REL_C1);
    assertEquals(result.ok, false);
    assertEquals(result.ok === false ? result.error.code : null, "CONSENT_REQUIRED");
  },
});

Deno.test({
  name: "eligibility: consent at a STALE policy version is not current consent",
  fn: async () => {
    await resetFixtures();
    await serviceRoleQuery(
      `INSERT INTO public.ai_processing_consent_events
         (relationship_id, user_id, action, policy_version, idempotency_key, created_at)
       VALUES
         ($1, $2, 'granted', 'v0-stale', gen_random_uuid(), clock_timestamp()),
         ($1, $3, 'granted', 'v0-stale', gen_random_uuid(), clock_timestamp())`,
      [REL_C1, USER_C1_A, USER_C1_B],
    );
    const deps = await makeDeps();
    const result = await checkEligibility(deps.serviceClient as never, USER_C1_A, REL_C1);
    assertEquals(result.ok, false);
    assertEquals(result.ok === false ? result.error.code : null, "CONSENT_REQUIRED");
  },
});

Deno.test({
  name: "eligibility: both members granted at the current version is eligible",
  fn: async () => {
    await resetFixtures();
    await grantDualConsent();
    const deps = await makeDeps();
    const result = await checkEligibility(deps.serviceClient as never, USER_C1_A, REL_C1);
    assertEquals(result.ok, true);
    // and the partner is equally eligible for the same relationship
    const partner = await checkEligibility(deps.serviceClient as never, USER_C1_B, REL_C1);
    assertEquals(partner.ok, true);
  },
});

Deno.test({
  name: "eligibility: a withdrawal after a grant revokes eligibility",
  fn: async () => {
    await resetFixtures();
    await grantDualConsent();
    await serviceRoleQuery(
      `INSERT INTO public.ai_processing_consent_events
         (relationship_id, user_id, action, policy_version, idempotency_key, created_at)
       VALUES ($1, $2, 'withdrawn', public.ai_current_consent_policy_version(), gen_random_uuid(), clock_timestamp())`,
      [REL_C1, USER_C1_B],
    );
    const deps = await makeDeps();
    const result = await checkEligibility(deps.serviceClient as never, USER_C1_A, REL_C1);
    assertEquals(result.ok, false);
    assertEquals(result.ok === false ? result.error.code : null, "CONSENT_REQUIRED");
  },
});

// ---------------------------------------------------------------------------
// HTTP-layer shape -- handleRequest's non-auth responsibilities.
// ---------------------------------------------------------------------------

Deno.test({
  name: "a non-POST method is rejected on the METHOD, before auth is consulted",
  fn: async () => {
    // Asserting only the 400/INVALID_INPUT would be vacuous here: with
    // the method guard removed, requireUser throws on the missing
    // Authorization header and its catch returns the SAME envelope, so
    // the response alone cannot tell the two rejections apart.
    //
    // So instrument the boundary instead. requireUser's first act is to
    // read the Authorization header; a GET that was rejected on its
    // method never touches it. A Request whose headers.get throws if
    // called turns "reached auth" into a distinguishable outcome.
    let headerRead: string | null = null;
    const req = new Request("http://localhost/ai-sessions", { method: "GET" });
    const probe = new Proxy(req, {
      get(target, prop, receiver) {
        if (prop === "headers") {
          return {
            get(name: string) {
              headerRead = name;
              return null;
            },
          };
        }
        const value = Reflect.get(target, prop, receiver);
        return typeof value === "function" ? value.bind(target) : value;
      },
    });

    const response = await handleRequestUnderTest(probe as Request);
    assertEquals(response.status, 400);
    assertEquals((await response.json()).code, "INVALID_INPUT");
    assertEquals(
      headerRead,
      null,
      "the method guard must reject before requireUser reads Authorization",
    );
  },
});

Deno.test({
  name: "OPTIONS is answered without auth",
  fn: async () => {
    const response = await handleRequestUnderTest(makeReq(null, "OPTIONS"));
    assertEquals(response.status, 200);
  },
});

// Imported lazily so the two tests above read clearly; handleRequest is
// the real HTTP entry and takes no test double for requireUser.
async function handleRequestUnderTest(req: Request): Promise<Response> {
  const { handleRequest } = await import("./index.ts");
  return handleRequest(req, {});
}

// ---------------------------------------------------------------------------
// Error envelope -- spec §10.
// ---------------------------------------------------------------------------

Deno.test({
  name: "every §10 error code maps to a distinct, non-500 status except INTERNAL_ERROR",
  fn: async () => {
    const { SESSION_ERROR_STATUS, sessionError } = await import("./index.ts");
    const codes = Object.keys(SESSION_ERROR_STATUS);
    assertEquals(codes.length, 18);
    for (const code of codes) {
      const status = SESSION_ERROR_STATUS[code as keyof typeof SESSION_ERROR_STATUS];
      if (code === "INTERNAL_ERROR") {
        assertEquals(status, 500);
      } else {
        assertNotEquals(status, 500, `${code} must not be a bare 500`);
        assert(status >= 400 && status < 600, `${code} -> ${status} must be a 4xx/5xx`);
      }
    }
    // retry_after_seconds is present only when supplied (§10: "caller-safe
    // retry_after_seconds WHEN RELEVANT").
    assertEquals(sessionError("RATE_LIMITED", 30), {
      code: "RATE_LIMITED",
      retry_after_seconds: 30,
    });
    assertEquals(sessionError("UNAVAILABLE"), { code: "UNAVAILABLE" });
    assertEquals(sessionError("UNAVAILABLE", null), { code: "UNAVAILABLE" });
  },
});

Deno.test({
  name: "an error response body carries ONLY the code and optional retry_after_seconds",
  fn: async () => {
    await resetFixtures();
    const response = await processSessionCommand(
      makeReq({ command: "nope" }),
      ctx(USER_C1_A),
      await makeDeps(),
    );
    const body = await response.json();
    // §10: no raw exception/provider text, no context, no echo of input.
    assertEquals(Object.keys(body).sort(), ["code"]);
  },
});

Deno.test({
  name: "a recognized command with no branch yet returns FEATURE_DISABLED, not a crash",
  fn: async () => {
    await resetFixtures();
    await grantDualConsent();
    const deps = await makeDeps();
    // Tasks 2-7 fill these in. Until then a recognized command must
    // return a typed envelope rather than fall through to a 500 -- and
    // must NOT be INVALID_INPUT, which would be indistinguishable from
    // an unknown command and would mislead a client into editing input.
    const response = await processSessionCommand(
      makeReq({ command: "prepare", relationship_id: REL_C1 }),
      ctx(USER_C1_A),
      deps,
    );
    assertEquals(response.status, 403);
    assertEquals((await response.json()).code, "FEATURE_DISABLED");
  },
});

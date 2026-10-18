// Spec 8 (F15 (1); plan review I10-I13, M4): one read of the server's
// suppression predicate for every AI job, failing closed.
//
// Requires: scripts/local_pg_setup.sh --no-tests (PGDATABASE=attune_spec3a)
import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { relationshipAiSuppressed, relationshipAiSuppression } from "./ai_suppression.ts";
import {
  getSharedPgClient,
  makeServiceRoleClient,
  serviceRoleQuery,
} from "./test_support/pg_rls_client.ts";

const REL = "a8100000-0000-0000-0000-000000000001";
const A = "a8100000-0000-0000-0000-00000000000a";
const B = "a8100000-0000-0000-0000-00000000000b";

async function reset() {
  await serviceRoleQuery(`DELETE FROM public.safety_events WHERE relationship_id = $1`, [REL]);
  await serviceRoleQuery(`DELETE FROM public.safety_self_checks WHERE relationship_id = $1`, [REL]);
  await serviceRoleQuery(`DELETE FROM public.relationships WHERE id = $1`, [REL]);
  await serviceRoleQuery(`DELETE FROM public.users WHERE id IN ($1, $2)`, [A, B]);
  await serviceRoleQuery(`DELETE FROM auth.users WHERE id IN ($1, $2)`, [A, B]);
  await serviceRoleQuery(`INSERT INTO auth.users (id, email) VALUES ($1, 'sup_a@t.test'), ($2, 'sup_b@t.test')`, [A, B]);
  await serviceRoleQuery(
    `INSERT INTO public.users (id, phone, display_name) VALUES ($1, '+15551181001', 'SA'), ($2, '+15551181002', 'SB')`,
    [A, B],
  );
  await serviceRoleQuery(
    `INSERT INTO public.relationships (id, user_a, user_b, status) VALUES ($1, $2, $3, 'active')`,
    [REL, A, B],
  );
}

Deno.test("an ordinary relationship is not suppressed", async () => {
  await reset();
  const client = await makeServiceRoleClient();
  assertEquals(await relationshipAiSuppressed(client as never, REL), false);
});

Deno.test("a safety event of any tier suppresses", async () => {
  await reset();
  await serviceRoleQuery(
    `INSERT INTO public.safety_events (relationship_id, at_risk_user_id, source_event_key, trigger_tier, trigger_family, config_version)
     VALUES ($1, $2, 'sup-test-1', 3, 'test', 'test')`,
    [REL, A],
  );
  const client = await makeServiceRoleClient();
  assertEquals(await relationshipAiSuppressed(client as never, REL), true);
});

Deno.test("either member's positive check suppresses", async () => {
  await reset();
  await serviceRoleQuery(
    `INSERT INTO public.safety_self_checks (user_id, relationship_id, answered_at, until, positive_until)
     VALUES ($1, $2, now(), now() + interval '180 days', now() + interval '180 days')`,
    [B, REL],
  );
  const client = await makeServiceRoleClient();
  assertEquals(await relationshipAiSuppressed(client as never, REL), true);
});

Deno.test("an unreadable answer fails closed", async () => {
  const broken = {
    rpc: () => Promise.resolve({ data: null, error: { message: "boom" } }),
  };
  assertEquals(await relationshipAiSuppressed(broken as never, REL), true);
});

// Final review I-1: callers that act irreversibly can tell "unknown" apart.
Deno.test("the tri-state answer: yes, no, or unknown on any doubt", async () => {
  await reset();
  const client = await makeServiceRoleClient();
  assertEquals(await relationshipAiSuppression(client as never, REL), "no");
  await serviceRoleQuery(
    `INSERT INTO public.safety_events (relationship_id, at_risk_user_id, source_event_key, trigger_tier, trigger_family, config_version)
     VALUES ($1, $2, 'sup-test-tri', 2, 'test', 'test')`,
    [REL, A],
  );
  assertEquals(await relationshipAiSuppression(client as never, REL), "yes");
  const broken = { rpc: () => Promise.resolve({ data: null, error: { message: "boom" } }) };
  assertEquals(await relationshipAiSuppression(broken as never, REL), "unknown");
  const odd = { rpc: () => Promise.resolve({ data: "maybe", error: null }) };
  assertEquals(await relationshipAiSuppression(odd as never, REL), "unknown");
  const throwing = { rpc: () => Promise.reject(new Error("down")) };
  assertEquals(await relationshipAiSuppression(throwing as never, REL), "unknown");
});

Deno.test({
  name: "teardown: close shared pg connection (ai_suppression)",
  fn: async () => {
    await reset();
    const client = await getSharedPgClient();
    await client.end();
  },
});

// Task 5: message_analysis_skipped exclusion at this file's two real query
// sites -- loadCandidateRelationshipIds (Layer 2 candidate relationship
// sweep) and loadDoneMessagesForSession (the session-transcript row
// selection extracted from processRelationship). Both queries filter
// message_analysis_done = true; a message that is deliberately skipped
// must never be treated as "done" in a way that lets it reach either
// query, even if some other code path ever marks it done by mistake --
// hence both sites additionally filter message_analysis_skipped = false.
//
// This file did not exist before Task 5. It follows the same
// real-Postgres-backed test-double convention analyse-message/
// index.test.ts (Task 5) and _shared/ai_context_loader.test.ts (Task 2)
// already established in this repo, rather than introducing a new style:
// a service-role-shaped adapter (_shared/test_support/pg_rls_client.ts's
// makeServiceRoleClient) backed by a real connection to the same
// attune_test Postgres database the SQL contract tests use, because
// analyse-session/index.ts calls serviceRoleClient() in production.
//
// Requires: scripts/local_pg_setup.sh --no-tests
// Run: deno test --allow-net --allow-env --allow-read --allow-sys
//        supabase/functions/analyse-session/index.test.ts

import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  loadCandidateRelationshipIds,
  loadDoneMessagesForSession,
} from "./index.ts";
import {
  getSharedPgClient,
  makeServiceRoleClient,
  serviceRoleQuery,
} from "../_shared/test_support/pg_rls_client.ts";

const REL_T5 = "a5200000-0000-0000-0000-000000000001";
const USER_T5_A = "a5200000-0000-0000-0000-00000000000a";
const USER_T5_B = "a5200000-0000-0000-0000-00000000000b";
const MSG_DONE = "a5200000-0000-0000-0000-000000000101";
const MSG_DONE_AND_SKIPPED = "a5200000-0000-0000-0000-000000000102";
// A gap comfortably before "now" so both messages clear the analyse-session
// sweep's 30-minute-old requirement.
const OLD_CREATED_AT = "2020-01-01T00:00:00Z";

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
    [USER_T5_A, "as_t5_a@t.test", USER_T5_B, "as_t5_b@t.test"],
  );
  await serviceRoleQuery(
    `INSERT INTO public.users (id, phone, display_name) VALUES
      ($1, '+15551125001', 'AS5A'), ($2, '+15551125002', 'AS5B')`,
    [USER_T5_A, USER_T5_B],
  );
  await serviceRoleQuery(
    `INSERT INTO public.relationships (id, user_a, user_b, status) VALUES ($1, $2, $3, 'active')`,
    [REL_T5, USER_T5_A, USER_T5_B],
  );
  // MSG_DONE: genuinely analysed, eligible for Layer 2.
  // MSG_DONE_AND_SKIPPED: models the "marked done by mistake" scenario --
  // message_analysis_done = true AND message_analysis_skipped = true.
  // Neither query in this file may ever select it.
  await serviceRoleQuery(
    `INSERT INTO public.messages
      (id, relationship_id, sender_id, client_message_id, content, source,
       message_analysis_done, message_analysis_skipped, safety_processed_at, created_at)
     VALUES
      ($1, $3, $4, gen_random_uuid(), 'genuinely analysed', 'native', true, false, now(), $5),
      ($2, $3, $4, gen_random_uuid(), 'skipped but marked done by mistake', 'native', true, true, now(), $5)`,
    [MSG_DONE, MSG_DONE_AND_SKIPPED, REL_T5, USER_T5_A, OLD_CREATED_AT],
  );
}

Deno.test({
  name: "loadCandidateRelationshipIds never surfaces a relationship whose only done message is skipped",
  fn: async () => {
    await resetTask5Fixtures();
    // Isolate: temporarily remove the genuinely-done message so the
    // relationship's ONLY message_analysis_done = true row is the
    // skipped one.
    await serviceRoleQuery(`DELETE FROM public.messages WHERE id = $1`, [MSG_DONE]);
    const client = await makeServiceRoleClient();
    const ids = await loadCandidateRelationshipIds(client as never, REL_T5, 50);
    assertEquals(ids.includes(REL_T5), false);
  },
});

Deno.test({
  name: "loadCandidateRelationshipIds still surfaces a relationship with a genuinely done, non-skipped message",
  fn: async () => {
    await resetTask5Fixtures();
    const client = await makeServiceRoleClient();
    const ids = await loadCandidateRelationshipIds(client as never, REL_T5, 50);
    assertEquals(ids.includes(REL_T5), true);
  },
});

Deno.test({
  name: "loadDoneMessagesForSession never returns a message_analysis_skipped = true row even when message_analysis_done = true",
  fn: async () => {
    await resetTask5Fixtures();
    const client = await makeServiceRoleClient();
    const rows = await loadDoneMessagesForSession(client as never, REL_T5);
    const ids = (rows ?? []).map((r: Record<string, unknown>) => r.id);
    assertEquals(ids.includes(MSG_DONE_AND_SKIPPED), false);
    assertEquals(ids.includes(MSG_DONE), true);
  },
});

Deno.test({
  name: "teardown: close shared pg connection (analyse-session)",
  fn: async () => {
    const client = await getSharedPgClient();
    await client.end();
  },
});

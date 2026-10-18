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
  processRelationship,
  retryExistingSession,
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

// Spec 8 (plan review I11): a suppressed relationship is refused at entry,
// before any message is read or consumed into a session.
Deno.test({
  name: "processRelationship refuses a suppressed relationship before consuming anything",
  fn: async () => {
    await resetTask5Fixtures();
    await serviceRoleQuery(
      `INSERT INTO public.safety_events (relationship_id, at_risk_user_id, source_event_key, trigger_tier, trigger_family, config_version)
       VALUES ($1, $2, 'as-sup-1', 2, 'test', 'test')`,
      [REL_T5, USER_T5_A],
    );
    try {
      const client = await makeServiceRoleClient();
      const results = await processRelationship(client as never, REL_T5);
      assertEquals(results, [{ relationship_id: REL_T5, status: "suppressed" }]);
      const consumed = await serviceRoleQuery(
        `SELECT count(*)::int AS n FROM public.messages WHERE relationship_id = $1 AND included_in_session_id IS NOT NULL`,
        [REL_T5],
      );
      assertEquals((consumed[0] as { n: number }).n, 0);
      const sessions = await serviceRoleQuery(
        `SELECT count(*)::int AS n FROM public.analysis_sessions WHERE relationship_id = $1`,
        [REL_T5],
      );
      assertEquals((sessions[0] as { n: number }).n, 0);
    } finally {
      await serviceRoleQuery(`DELETE FROM public.safety_events WHERE relationship_id = $1`, [REL_T5]);
    }
  },
});

Deno.test({
  name: "retryExistingSession refuses a suppressed relationship's pending session",
  fn: async () => {
    await resetTask5Fixtures();
    const session = await serviceRoleQuery(
      `INSERT INTO public.analysis_sessions (relationship_id, started_at, ended_at, message_count)
       VALUES ($1, now() - interval '2 hours', now() - interval '1 hour', 2) RETURNING id`,
      [REL_T5],
    );
    const sessionId = (session[0] as { id: string }).id;
    await serviceRoleQuery(
      `INSERT INTO public.safety_self_checks (user_id, relationship_id, answered_at, until, positive_until)
       VALUES ($1, $2, now(), now() + interval '180 days', now() + interval '180 days')`,
      [USER_T5_B, REL_T5],
    );
    try {
      const client = await makeServiceRoleClient();
      const result = await retryExistingSession(client as never, { id: sessionId });
      assertEquals(result, { session_id: sessionId, status: "suppressed" });
      const row = await serviceRoleQuery(
        `SELECT escalation_score FROM public.analysis_sessions WHERE id = $1`,
        [sessionId],
      );
      assertEquals((row[0] as { escalation_score: unknown }).escalation_score, null);
    } finally {
      await serviceRoleQuery(`DELETE FROM public.safety_self_checks WHERE relationship_id = $1`, [REL_T5]);
      await serviceRoleQuery(`DELETE FROM public.analysis_sessions WHERE id = $1`, [sessionId]);
    }
  },
});

// Sync audit I-2: Layer 2 runs only while active; a paused couple's
// pending messages are set aside, never consumed into a session.
Deno.test({
  name: "processRelationship sets a paused relationship's messages aside",
  fn: async () => {
    await resetTask5Fixtures();
    await serviceRoleQuery(`UPDATE public.relationships SET status = 'paused' WHERE id = $1`, [REL_T5]);
    const client = await makeServiceRoleClient();
    const results = await processRelationship(client as never, REL_T5);
    assertEquals(results, [{ relationship_id: REL_T5, status: "skipped_relationship_not_active" }]);
    const rows = await serviceRoleQuery(
      `SELECT message_analysis_skipped, included_in_session_id FROM public.messages WHERE id = $1`,
      [MSG_DONE],
    );
    assertEquals(rows[0].message_analysis_skipped, true);
    assertEquals(rows[0].included_in_session_id, null);
  },
});

// Sync audit I-5: a message deleted after Layer 1 never enters a transcript.
Deno.test({
  name: "loadDoneMessagesForSession skips deleted messages",
  fn: async () => {
    await resetTask5Fixtures();
    await serviceRoleQuery(`UPDATE public.messages SET deleted_at = now(), content = NULL WHERE id = $1`, [MSG_DONE]);
    const client = await makeServiceRoleClient();
    const rows = await loadDoneMessagesForSession(client as never, REL_T5);
    assertEquals((rows ?? []).map((r: Record<string, unknown>) => r.id).includes(MSG_DONE), false);
  },
});

Deno.test({
  name: "teardown: close shared pg connection (analyse-session)",
  fn: async () => {
    const client = await getSharedPgClient();
    await client.end();
  },
});

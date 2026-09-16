// Proves loadAiAssistantTarget/loadBoundedContext are the sole trusted
// context boundary: a non-member cannot load a target from a
// relationship they don't belong to (proven via real RLS, not an
// application-code check), context never leaks names/UUIDs, and the
// two modes' row/character caps are enforced exactly as specced.
//
// Spec: docs/superpowers/specs/2026-09-15-ai-assistant-design.md §4.2, §4.3.
//
// Requires the throwaway `attune_test` Postgres database built by
// scripts/local_pg_setup.sh (`scripts/local_pg_setup.sh --no-tests`).
//
// DEVIATION FROM THE ORIGINAL TASK BRIEF, recorded here deliberately:
// the brief specifies fabricating real signed-up test users' JWTs via
// the Auth Admin API against "the local Supabase instance", following
// an existing pattern in this codebase. Two things made that
// infeasible as written:
//   1. This environment has no Docker daemon, so `supabase start`
//      (GoTrue + PostgREST) cannot run here at all.
//   2. No existing edge-function test anywhere in this repository
//      fabricates a real user/JWT via the Auth Admin API -- grep over
//      supabase/functions/**/*.test.ts confirms this. Task 1's own
//      user_scoped_client.test.ts explicitly says the real-JWT,
//      real-RLS proof is deferred to this file, without asserting such
//      a helper already exists.
//
// This file's substitute: a small test-only adapter
// (test_support/pg_rls_client.ts) that is SupabaseClient-shaped (only
// implementing the .from().select().eq()... subset the loader calls)
// but backed by a real connection to the same attune_test Postgres
// database the SQL contract tests use, running every query with
// `SET LOCAL ROLE authenticated` plus the same `request.jwt.claims` GUC
// auth.uid() reads on the real platform. This is not a mock of RLS --
// it is real RLS, evaluated by real Postgres, under the exact policies
// applied by the migrations. What it does not prove is the
// HTTP/PostgREST/GoTrue layer, which is out of scope for this loader
// (that boundary is userScopedClient()'s own concern, covered by its
// own test file plus this repo's platform-side grant contracts).

import { assertEquals } from "https://deno.land/std@0.208.0/assert/mod.ts";
import {
  loadAiAssistantTarget,
  loadBoundedContext,
} from "./ai_context_loader.ts";
import {
  getSharedPgClient,
  makeRlsClientForUser,
  serviceRoleQuery,
} from "./test_support/pg_rls_client.ts";

const USER_A = "b2000000-0000-0000-0000-00000000000a"; // rel_a member
const USER_B = "b2000000-0000-0000-0000-00000000000b"; // rel_a member (partner)
const USER_C = "b2000000-0000-0000-0000-00000000000c"; // rel_c member only -- non-member of rel_a
const USER_D = "b2000000-0000-0000-0000-00000000000d"; // rel_c member (partner of C)

const REL_A = "b2000000-0000-0000-0000-000000000a01"; // active, A+B
const REL_C = "b2000000-0000-0000-0000-000000000c01"; // active, C+D
const REL_ARCHIVED = "b2000000-0000-0000-0000-00000000aa01"; // archived, A+B

async function resetFixtures(): Promise<void> {
  // Clean slate for this test's id namespace only (b2000000-* prefix),
  // so re-runs are idempotent and don't collide with other test suites'
  // fixtures (e.g. ai_assistant_schema_contracts.sql's a1000000-* ids).
  await serviceRoleQuery(
    `DELETE FROM public.messages WHERE relationship_id IN ($1, $2, $3)`,
    [REL_A, REL_C, REL_ARCHIVED],
  );
  await serviceRoleQuery(
    `DELETE FROM public.relationships WHERE id IN ($1, $2, $3)`,
    [REL_A, REL_C, REL_ARCHIVED],
  );
  await serviceRoleQuery(
    `DELETE FROM public.users WHERE id IN ($1, $2, $3, $4)`,
    [USER_A, USER_B, USER_C, USER_D],
  );
  await serviceRoleQuery(
    `DELETE FROM auth.users WHERE id IN ($1, $2, $3, $4)`,
    [USER_A, USER_B, USER_C, USER_D],
  );

  await serviceRoleQuery(
    `INSERT INTO auth.users (id, email) VALUES ($1, $2), ($3, $4), ($5, $6), ($7, $8)`,
    [
      USER_A,
      "ctxloader_a@t.test",
      USER_B,
      "ctxloader_b@t.test",
      USER_C,
      "ctxloader_c@t.test",
      USER_D,
      "ctxloader_d@t.test",
    ],
  );
  await serviceRoleQuery(
    `INSERT INTO public.users (id, phone, display_name) VALUES
      ($1, '+15559990001', 'CtxA'), ($2, '+15559990002', 'CtxB'),
      ($3, '+15559990003', 'CtxC'), ($4, '+15559990004', 'CtxD')`,
    [USER_A, USER_B, USER_C, USER_D],
  );

  await serviceRoleQuery(
    `INSERT INTO public.relationships (id, user_a, user_b, status) VALUES ($1, $2, $3, 'active')`,
    [REL_A, USER_A, USER_B],
  );
  await serviceRoleQuery(
    `INSERT INTO public.relationships (id, user_a, user_b, status) VALUES ($1, $2, $3, 'active')`,
    [REL_C, USER_C, USER_D],
  );
  await serviceRoleQuery(
    `INSERT INTO public.relationships (id, user_a, user_b, status, chat_archived_at) VALUES ($1, $2, $3, 'active', now())`,
    [REL_ARCHIVED, USER_A, USER_B],
  );
}

async function insertMessage(opts: {
  id: string;
  relationshipId: string;
  senderId: string;
  content: string | null;
  createdAt: string;
  deletedAt?: string | null;
  isSystemNotice?: boolean;
  messageOrigin?: "user" | "attune_assist";
  assistantPayload?: Record<string, unknown> | null;
}): Promise<void> {
  const {
    id,
    relationshipId,
    senderId,
    content,
    createdAt,
    deletedAt = null,
    isSystemNotice = false,
    messageOrigin = "user",
    assistantPayload = null,
  } = opts;
  await serviceRoleQuery(
    `INSERT INTO public.messages
      (id, relationship_id, sender_id, client_message_id, content, created_at,
       deleted_at, is_system_notice, message_origin, assistant_payload)
     VALUES ($1, $2, $3, gen_random_uuid(), $4, $5, $6, $7, $8, $9)`,
    [
      id,
      relationshipId,
      senderId,
      content,
      createdAt,
      deletedAt,
      isSystemNotice,
      messageOrigin,
      assistantPayload ? JSON.stringify(assistantPayload) : null,
    ],
  );
}

function uid(seed: string): string {
  // Deterministic fake uuid-ish id from a short seed, kept inside the
  // b2000000 namespace's message-id range for readability in failures.
  const hex = seed.padStart(12, "0").slice(-12);
  return `b2000000-1000-0000-0000-${hex}`;
}

Deno.test({
  name: "loadAiAssistantTarget returns TARGET_UNAVAILABLE for a message in a relationship the caller isn't in",
  fn: async () => {
    await resetFixtures();
    const msgId = uid("1");
    await insertMessage({
      id: msgId,
      relationshipId: REL_A,
      senderId: USER_A,
      content: "secret to A and B only",
      createdAt: "2026-08-01T12:00:00Z",
    });

    const clientC = await makeRlsClientForUser(USER_C);
    const result = await loadAiAssistantTarget(clientC as never, USER_C, msgId);
    assertEquals(result.ok, false);
    if (!result.ok) assertEquals(result.code, "TARGET_UNAVAILABLE");
  },
});

Deno.test({
  name: "loadAiAssistantTarget returns TARGET_UNAVAILABLE for a deleted message",
  fn: async () => {
    await resetFixtures();
    const msgId = uid("2");
    await insertMessage({
      id: msgId,
      relationshipId: REL_A,
      senderId: USER_A,
      content: "will be deleted",
      createdAt: "2026-08-01T12:01:00Z",
      deletedAt: "2026-08-01T12:02:00Z",
    });

    const clientA = await makeRlsClientForUser(USER_A);
    const result = await loadAiAssistantTarget(clientA as never, USER_A, msgId);
    assertEquals(result.ok, false);
    if (!result.ok) assertEquals(result.code, "TARGET_UNAVAILABLE");
  },
});

Deno.test({
  name: "loadAiAssistantTarget returns TARGET_UNAVAILABLE for a message that does not exist at all",
  fn: async () => {
    await resetFixtures();
    const clientA = await makeRlsClientForUser(USER_A);
    const nonExistentId = uid("999999999999");
    const result = await loadAiAssistantTarget(clientA as never, USER_A, nonExistentId);
    assertEquals(result.ok, false);
    if (!result.ok) assertEquals(result.code, "TARGET_UNAVAILABLE");
  },
});

Deno.test({
  name: "loadAiAssistantTarget returns the same TARGET_UNAVAILABLE code for non-member, deleted, and nonexistent -- not distinguishable error shapes",
  fn: async () => {
    await resetFixtures();
    const deletedId = uid("2");
    const clientC = await makeRlsClientForUser(USER_C);
    const clientA = await makeRlsClientForUser(USER_A);

    const nonMemberResult = await loadAiAssistantTarget(clientC as never, USER_C, uid("1"));
    const deletedResult = await loadAiAssistantTarget(clientA as never, USER_A, deletedId);
    const missingResult = await loadAiAssistantTarget(clientA as never, USER_A, uid("777777777777"));

    for (const r of [nonMemberResult, deletedResult, missingResult]) {
      assertEquals(r.ok, false);
      if (!r.ok) assertEquals(r.code, "TARGET_UNAVAILABLE");
    }
  },
});

Deno.test({
  name: "loadAiAssistantTarget returns TARGET_UNAVAILABLE when the relationship is archived",
  fn: async () => {
    await resetFixtures();
    const msgId = uid("3");
    await insertMessage({
      id: msgId,
      relationshipId: REL_ARCHIVED,
      senderId: USER_A,
      content: "chat is archived now",
      createdAt: "2026-08-01T12:03:00Z",
    });

    const clientA = await makeRlsClientForUser(USER_A);
    const result = await loadAiAssistantTarget(clientA as never, USER_A, msgId);
    assertEquals(result.ok, false);
    if (!result.ok) assertEquals(result.code, "TARGET_UNAVAILABLE");
  },
});

Deno.test({
  name: "loadAiAssistantTarget succeeds for a live, eligible message in the caller's own active relationship",
  fn: async () => {
    await resetFixtures();
    const msgId = uid("4");
    await insertMessage({
      id: msgId,
      relationshipId: REL_A,
      senderId: USER_B,
      content: "hey, are we still on for saturday?",
      createdAt: "2026-08-01T12:04:00Z",
    });

    const clientA = await makeRlsClientForUser(USER_A);
    const result = await loadAiAssistantTarget(clientA as never, USER_A, msgId);
    assertEquals(result.ok, true);
    if (result.ok) {
      assertEquals(result.target.messageId, msgId);
      assertEquals(result.target.relationshipId, REL_A);
      assertEquals(result.target.senderId, USER_B);
      assertEquals(result.target.content, "hey, are we still on for saturday?");
    }
  },
});

Deno.test({
  name: "loadBoundedContext for Assist returns at most 6 other messages, nearest-first then chronological",
  fn: async () => {
    await resetFixtures();
    const targetId = uid("100");
    const targetTime = new Date("2026-08-02T12:00:00Z").getTime();
    await insertMessage({
      id: targetId,
      relationshipId: REL_A,
      senderId: USER_A,
      content: "the target message",
      createdAt: new Date(targetTime).toISOString(),
    });

    // 5 before, 5 after, spaced 1 minute apart.
    for (let i = 1; i <= 5; i++) {
      await insertMessage({
        id: uid(`10${i}`),
        relationshipId: REL_A,
        senderId: i % 2 === 0 ? USER_A : USER_B,
        content: `before-${i}`,
        createdAt: new Date(targetTime - i * 60_000).toISOString(),
      });
      await insertMessage({
        id: uid(`11${i}`),
        relationshipId: REL_A,
        senderId: i % 2 === 0 ? USER_A : USER_B,
        content: `after-${i}`,
        createdAt: new Date(targetTime + i * 60_000).toISOString(),
      });
    }

    const clientA = await makeRlsClientForUser(USER_A);
    const target = {
      messageId: targetId,
      relationshipId: REL_A,
      senderId: USER_A,
      createdAt: new Date(targetTime).toISOString(),
      content: "the target message",
    };
    const context = await loadBoundedContext(clientA as never, target, "assist", USER_A);
    assertEquals(context.length, 6);
    const contents = context.map((m) => m.content);
    // Nearest 3 before (before-1, before-2, before-3) + nearest 3 after
    // (after-1, after-2, after-3), returned chronologically.
    assertEquals(contents, [
      "before-3",
      "before-2",
      "before-1",
      "after-1",
      "after-2",
      "after-3",
    ]);
  },
});

Deno.test({
  name: "loadBoundedContext for Understand returns target plus at most 19 within the civil day, 12 before/7 after",
  fn: async () => {
    await resetFixtures();
    const targetId = uid("200");
    // Target at 2026-08-03T12:00:00Z, UTC offset 0 -> civil day
    // 2026-08-03T00:00:00Z .. 2026-08-04T00:00:00Z.
    const targetTime = new Date("2026-08-03T12:00:00Z").getTime();
    await insertMessage({
      id: targetId,
      relationshipId: REL_A,
      senderId: USER_A,
      content: "understand target",
      createdAt: new Date(targetTime).toISOString(),
    });

    // 15 before within the same day, spaced 10 min apart (some will
    // fall before day-start and must be excluded even though the row
    // cap alone would have allowed them).
    for (let i = 1; i <= 15; i++) {
      await insertMessage({
        id: uid(`20${i}`),
        relationshipId: REL_A,
        senderId: i % 2 === 0 ? USER_A : USER_B,
        content: `u-before-${i}`,
        createdAt: new Date(targetTime - i * 30 * 60_000).toISOString(),
      });
    }
    // 10 after within the same day.
    for (let i = 1; i <= 10; i++) {
      await insertMessage({
        id: uid(`21${i}`),
        relationshipId: REL_A,
        senderId: i % 2 === 0 ? USER_A : USER_B,
        content: `u-after-${i}`,
        createdAt: new Date(targetTime + i * 30 * 60_000).toISOString(),
      });
    }
    // A message in the adjacent civil day (next day) that must never
    // appear regardless of proximity.
    await insertMessage({
      id: uid("299"),
      relationshipId: REL_A,
      senderId: USER_B,
      content: "next-day-message",
      createdAt: "2026-08-04T00:05:00Z",
    });
    // A message in the previous civil day.
    await insertMessage({
      id: uid("298"),
      relationshipId: REL_A,
      senderId: USER_B,
      content: "prev-day-message",
      createdAt: "2026-08-02T23:55:00Z",
    });

    const clientA = await makeRlsClientForUser(USER_A);
    const target = {
      messageId: targetId,
      relationshipId: REL_A,
      senderId: USER_A,
      createdAt: new Date(targetTime).toISOString(),
      content: "understand target",
    };
    const context = await loadBoundedContext(clientA as never, target, "understand", USER_A, 0);

    assertEquals(context.length <= 19, true);
    const contents = context.map((m) => m.content);
    assertEquals(contents.includes("next-day-message"), false);
    assertEquals(contents.includes("prev-day-message"), false);

    const beforeInResult = contents.filter((c) => c.startsWith("u-before-")).length;
    const afterInResult = contents.filter((c) => c.startsWith("u-after-")).length;
    assertEquals(beforeInResult, 12);
    assertEquals(afterInResult, 7);
    // Pin the EXACT nearest-N sets, not just their counts: a mutation
    // that widens afterCount while the 19-row cap silently absorbs the
    // overflow can still produce the right total count of 7 "after"
    // rows while actually including a farther one and excluding a
    // nearer one (or vice versa) -- checking membership of the specific
    // nearest/farthest boundary rows closes that gap.
    for (let i = 1; i <= 12; i++) {
      assertEquals(contents.includes(`u-before-${i}`), true, `expected u-before-${i} present`);
    }
    assertEquals(contents.includes("u-before-13"), false);
    for (let i = 1; i <= 7; i++) {
      assertEquals(contents.includes(`u-after-${i}`), true, `expected u-after-${i} present`);
    }
    assertEquals(contents.includes("u-after-8"), false);
  },
});

Deno.test({
  name: "loadBoundedContext for Understand excludes a nearer-in-time message that falls just outside the civil day, even though it would otherwise win a nearest-N slot",
  fn: async () => {
    await resetFixtures();
    const targetId = uid("250");
    // Target 20 minutes after midnight -> civil day boundary is very
    // close in time. Messages just before midnight are numerically
    // NEARER than several "eligible" same-day candidates, so if the day
    // filter were ever dropped, they would win a nearest-N slot over a
    // farther same-day message -- making this fixture sensitive to
    // exactly that mutation (unlike the noon-target fixture above,
    // where the day boundary is hours away from the nearest-N window).
    const targetTime = new Date("2026-08-10T00:20:00Z").getTime();
    await insertMessage({
      id: targetId,
      relationshipId: REL_A,
      senderId: USER_A,
      content: "midnight-adjacent target",
      createdAt: new Date(targetTime).toISOString(),
    });

    // Only 2 eligible same-day "before" messages exist (00:05, 00:15),
    // both closer to midnight than to the target's 12-before capacity.
    await insertMessage({
      id: uid("251"),
      relationshipId: REL_A,
      senderId: USER_B,
      content: "same-day-before-1",
      createdAt: "2026-08-10T00:15:00Z",
    });
    await insertMessage({
      id: uid("252"),
      relationshipId: REL_A,
      senderId: USER_B,
      content: "same-day-before-2",
      createdAt: "2026-08-10T00:05:00Z",
    });
    // Several messages in the PREVIOUS civil day, each nearer in raw
    // time than nothing else competes with them -- if the day filter
    // were dropped, these would fill the remaining nearest-N "before"
    // slots ahead of same-day-before-2 being the last one, exposing the
    // mutation directly as membership changes.
    for (let i = 1; i <= 5; i++) {
      await insertMessage({
        id: uid(`253${i}`),
        relationshipId: REL_A,
        senderId: USER_B,
        content: `prev-day-near-${i}`,
        createdAt: new Date(
          new Date("2026-08-09T23:55:00Z").getTime() - i * 60_000,
        ).toISOString(),
      });
    }

    const clientA = await makeRlsClientForUser(USER_A);
    const target = {
      messageId: targetId,
      relationshipId: REL_A,
      senderId: USER_A,
      createdAt: new Date(targetTime).toISOString(),
      content: "midnight-adjacent target",
    };
    const context = await loadBoundedContext(clientA as never, target, "understand", USER_A, 0);
    const contents = context.map((m) => m.content);

    assertEquals(contents.includes("same-day-before-1"), true);
    assertEquals(contents.includes("same-day-before-2"), true);
    for (let i = 1; i <= 5; i++) {
      assertEquals(contents.includes(`prev-day-near-${i}`), false, `prev-day-near-${i} must be excluded`);
    }
  },
});

Deno.test({
  name: "context messages carry role/createdAt/content only -- no name, no user UUID, anywhere in the returned shape",
  fn: async () => {
    await resetFixtures();
    const targetId = uid("300");
    const targetTime = new Date("2026-08-05T12:00:00Z").getTime();
    await insertMessage({
      id: targetId,
      relationshipId: REL_A,
      senderId: USER_A,
      content: "shape target",
      createdAt: new Date(targetTime).toISOString(),
    });
    await insertMessage({
      id: uid("301"),
      relationshipId: REL_A,
      senderId: USER_B,
      content: "shape context row",
      createdAt: new Date(targetTime - 60_000).toISOString(),
    });

    const clientA = await makeRlsClientForUser(USER_A);
    const target = {
      messageId: targetId,
      relationshipId: REL_A,
      senderId: USER_A,
      createdAt: new Date(targetTime).toISOString(),
      content: "shape target",
    };
    const context = await loadBoundedContext(clientA as never, target, "assist", USER_A);
    assertEquals(context.length, 1);
    const row = context[0];
    const keys = Object.keys(row).sort();
    assertEquals(keys, ["content", "createdAt", "role", "truncated"]);
    assertEquals(row.role, "partner");
    // Explicitly assert the raw UUIDs are not present anywhere in the
    // serialized row.
    const serialized = JSON.stringify(row);
    assertEquals(serialized.includes(USER_A), false);
    assertEquals(serialized.includes(USER_B), false);
    assertEquals(serialized.includes("CtxA"), false);
    assertEquals(serialized.includes("CtxB"), false);
  },
});

Deno.test({
  name: "a surrounding message over 1,000 PostgreSQL characters is clipped with an explicit truncated marker",
  fn: async () => {
    await resetFixtures();
    const targetId = uid("400");
    const targetTime = new Date("2026-08-06T12:00:00Z").getTime();
    await insertMessage({
      id: targetId,
      relationshipId: REL_A,
      senderId: USER_A,
      content: "clip target",
      createdAt: new Date(targetTime).toISOString(),
    });
    const longContent = "x".repeat(1500);
    await insertMessage({
      id: uid("401"),
      relationshipId: REL_A,
      senderId: USER_B,
      content: longContent,
      createdAt: new Date(targetTime - 60_000).toISOString(),
    });

    const clientA = await makeRlsClientForUser(USER_A);
    const target = {
      messageId: targetId,
      relationshipId: REL_A,
      senderId: USER_A,
      createdAt: new Date(targetTime).toISOString(),
      content: "clip target",
    };
    const context = await loadBoundedContext(clientA as never, target, "assist", USER_A);
    assertEquals(context.length, 1);
    assertEquals(context[0].truncated, true);
    assertEquals(context[0].content.endsWith("[truncated]"), true);
    assertEquals(context[0].content.length, 1000 + " [truncated]".length);
  },
});

Deno.test({
  name: "context construction stops adding candidates once the combined text would exceed 12,000 PostgreSQL characters, even if the row cap has not been reached",
  fn: async () => {
    await resetFixtures();
    const targetId = uid("500");
    const targetTime = new Date("2026-08-07T12:00:00Z").getTime();
    // Target content itself near the clip boundary so the running total
    // starts high.
    const targetContent = "t".repeat(950);
    await insertMessage({
      id: targetId,
      relationshipId: REL_A,
      senderId: USER_A,
      content: targetContent,
      createdAt: new Date(targetTime).toISOString(),
    });

    // Understand mode row cap is 19; seed enough near-1000-char messages
    // (12 before + 7 after would be 19 * ~1000 = ~19000 chars, well over
    // the 12000 total cap) so the total-char cap binds first.
    for (let i = 1; i <= 12; i++) {
      await insertMessage({
        id: uid(`50${i}`),
        relationshipId: REL_A,
        senderId: i % 2 === 0 ? USER_A : USER_B,
        content: "b".repeat(950),
        createdAt: new Date(targetTime - i * 60_000).toISOString(),
      });
    }
    for (let i = 1; i <= 7; i++) {
      await insertMessage({
        id: uid(`51${i}`),
        relationshipId: REL_A,
        senderId: i % 2 === 0 ? USER_A : USER_B,
        content: "a".repeat(950),
        createdAt: new Date(targetTime + i * 60_000).toISOString(),
      });
    }

    const clientA = await makeRlsClientForUser(USER_A);
    const target = {
      messageId: targetId,
      relationshipId: REL_A,
      senderId: USER_A,
      createdAt: new Date(targetTime).toISOString(),
      content: targetContent,
    };
    const context = await loadBoundedContext(clientA as never, target, "understand", USER_A, 0);
    // Row cap for understand is 19; total-char cap must bind first.
    assertEquals(context.length < 19, true);
    const totalChars = targetContent.length +
      context.reduce((sum, m) => sum + m.content.length, 0);
    assertEquals(totalChars <= 12000, true);
  },
});

Deno.test({
  name: "context excludes deleted rows, system notices, and attune_assist-origin messages from the returned set",
  fn: async () => {
    await resetFixtures();
    const targetId = uid("600");
    const targetTime = new Date("2026-08-08T12:00:00Z").getTime();
    await insertMessage({
      id: targetId,
      relationshipId: REL_A,
      senderId: USER_A,
      content: "exclusion target",
      createdAt: new Date(targetTime).toISOString(),
    });
    await insertMessage({
      id: uid("601"),
      relationshipId: REL_A,
      senderId: USER_B,
      content: "deleted content",
      createdAt: new Date(targetTime - 60_000).toISOString(),
      deletedAt: new Date(targetTime - 30_000).toISOString(),
    });
    await insertMessage({
      id: uid("602"),
      relationshipId: REL_A,
      senderId: USER_B,
      content: "system notice content",
      createdAt: new Date(targetTime - 120_000).toISOString(),
      isSystemNotice: true,
    });
    await insertMessage({
      id: uid("603"),
      relationshipId: REL_A,
      senderId: USER_B,
      content: "assistant-origin content",
      createdAt: new Date(targetTime - 180_000).toISOString(),
      messageOrigin: "attune_assist",
      assistantPayload: { kind: "draft" },
    });
    await insertMessage({
      id: uid("604"),
      relationshipId: REL_A,
      senderId: USER_B,
      content: "eligible content",
      createdAt: new Date(targetTime - 240_000).toISOString(),
    });

    const clientA = await makeRlsClientForUser(USER_A);
    const target = {
      messageId: targetId,
      relationshipId: REL_A,
      senderId: USER_A,
      createdAt: new Date(targetTime).toISOString(),
      content: "exclusion target",
    };
    const context = await loadBoundedContext(clientA as never, target, "assist", USER_A);
    const contents = context.map((m) => m.content);
    assertEquals(contents.includes("deleted content"), false);
    assertEquals(contents.includes("system notice content"), false);
    assertEquals(contents.includes("assistant-origin content"), false);
    assertEquals(contents.includes("eligible content"), true);
  },
});

Deno.test({
  name: "Understand's civil-day boundary is derived from utc_offset_minutes but the 19-row cap is always primary -- an extreme offset cannot expose an unbounded day",
  fn: async () => {
    await resetFixtures();
    const targetId = uid("700");
    const targetTime = new Date("2026-08-09T12:00:00Z").getTime();
    await insertMessage({
      id: targetId,
      relationshipId: REL_A,
      senderId: USER_A,
      content: "offset target",
      createdAt: new Date(targetTime).toISOString(),
    });

    // Seed 40 messages before and 40 after, spaced 5 minutes apart --
    // far more than the 19-row cap, spanning well beyond any single
    // civil day at either offset extreme.
    for (let i = 1; i <= 40; i++) {
      await insertMessage({
        id: uid(`70${i}`),
        relationshipId: REL_A,
        senderId: i % 2 === 0 ? USER_A : USER_B,
        content: `off-before-${i}`,
        createdAt: new Date(targetTime - i * 5 * 60_000).toISOString(),
      });
      await insertMessage({
        id: uid(`71${i}`),
        relationshipId: REL_A,
        senderId: i % 2 === 0 ? USER_A : USER_B,
        content: `off-after-${i}`,
        createdAt: new Date(targetTime + i * 5 * 60_000).toISOString(),
      });
    }

    const clientA = await makeRlsClientForUser(USER_A);
    const target = {
      messageId: targetId,
      relationshipId: REL_A,
      senderId: USER_A,
      createdAt: new Date(targetTime).toISOString(),
      content: "offset target",
    };

    for (const offset of [-840, 840]) {
      const context = await loadBoundedContext(
        clientA as never,
        target,
        "understand",
        USER_A,
        offset,
      );
      assertEquals(context.length <= 19, true);
    }
  },
});

Deno.test({
  name: "teardown: close shared pg connection",
  fn: async () => {
    const client = await getSharedPgClient();
    await client.end();
  },
});

# Ask-2 Trigger System Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move couples onboarding onto the two-ask design required by ATTUNE_MASTER_SPEC.md decision 29 — the attachment quiz and three relationship anchors stop appearing inline during Ask 1 and instead fire days later as "Ask 2," triggered by real chat activity and a genuine positive signal.

**Architecture:** Five layers, each independently testable, built bottom-up: (1) persist a sentiment signal Claude already returns but the code discards, (2) a service-role SQL function computing per-couple eligibility from real message data, (3) an `ask2_state` table plus a cron-driven edge function sweeping relationships through it, (4) reuse of the existing notification pipeline to alert users, (5) a standalone `Ask2Flow` Flutter widget — reached only via deep link — that composes the existing quiz/anchors step widgets. Task 6 removes the current spec violation (inline quiz+anchors during Ask 1 for couples).

**Tech Stack:** Supabase Postgres (migrations, `SECURITY DEFINER` functions, `pg_cron`/`pg_net`), Deno edge functions (existing `_shared/attune_auth.ts` / `_shared/claude_json.ts` helpers), Flutter/Dart (Riverpod, GoRouter), `flutter_test` widget tests.

## Global Constraints

- Message threshold: **30 messages per partner** (not combined) — from `docs/superpowers/specs/2026-07-21-ask2-trigger-design.md`.
- Day threshold: **3+ distinct local calendar days** with messages from both partners, not required to be consecutive.
- Cron cadence: **hourly**, matching the existing `analyse-session` sweep pattern.
- Reminder window: **7 days** after the first prompt — exactly one reminder, then silence.
- Notification copy must never paraphrase the couple's actual message content, and must never use the words "AI", "analysis", "insight", "intelligence", or "patterns" (per ATTUNE_MASTER_SPEC.md Ask-1 invite rules — Ask-2's notification is the first place these words are allowed, but the specific copy in this plan avoids them anyway per the design doc's brainstormed copy).
- Personal (single) mode's onboarding sequence is **not modified** by this plan — only couples/couplesPending mode changes.
- Do not touch the attachment quiz's question wording, count, or scale — that instrument choice is an explicitly unresolved clinical decision (out of scope, see design doc's Scope Boundary section).
- Follow the existing edge function pattern exactly: `serviceRoleClient()` + `requireServiceRole(req)` + `jsonResponse()` from `supabase/functions/_shared/attune_auth.ts`.

---

### Task 1: Persist message-level sentiment

**Files:**
- Create: `supabase/migrations/20260721120000_message_sentiment.sql`
- Modify: `supabase/functions/analyse-message/index.ts:274-298` (the `validateLayerOne` function)
- Test: `supabase/tests/message_sentiment_test.sql` (new)

**Interfaces:**
- Produces: `messages.sentiment` column (nullable text, one of `'positive'|'neutral'|'negative'|'charged'`), populated by `validateLayerOne`'s existing per-message write path. Consumed by Task 2's eligibility RPC.

- [ ] **Step 1: Write the migration**

```sql
-- supabase/migrations/20260721120000_message_sentiment.sql
-- Layer 1 (analyse-message) already asks Claude for a "sentiment" field per
-- message but validateLayerOne() discarded it before the UPDATE. Persisting
-- it is what lets Ask-2 eligibility detect "the first positive-valence
-- observation" (ATTUNE_MASTER_SPEC.md decision 29) instead of guessing from
-- tone_score, which was designed for NVC/conflict detection, not general
-- positive-affect detection.
ALTER TABLE public.messages
  ADD COLUMN IF NOT EXISTS sentiment text
    CHECK (sentiment IS NULL OR sentiment IN ('positive', 'neutral', 'negative', 'charged'));

CREATE INDEX IF NOT EXISTS idx_messages_positive_sentiment
  ON public.messages (relationship_id, created_at)
  WHERE sentiment = 'positive';
```

- [ ] **Step 2: Run the migration locally**

Run: `cd /Users/user/attune && supabase db reset` (or `supabase migration up` if you have a running local stack already)
Expected: migration applies with no errors; `\d public.messages` in `psql` shows the new `sentiment` column.

- [ ] **Step 3: Update `validateLayerOne` to pass sentiment through**

In `supabase/functions/analyse-message/index.ts`, add an allow-list constant near the existing `ALLOWED_NVC`/`ALLOWED_BID_TYPES` constants (around line 20):

```typescript
const ALLOWED_SENTIMENTS = new Set(["positive", "neutral", "negative", "charged"]);
```

Then modify `validateLayerOne` (currently lines 274-298) to read and pass through `parsed.sentiment`:

```typescript
function validateLayerOne(
  parsed: Record<string, unknown> | null,
): Record<string, unknown> | null {
  if (!parsed) return null;

  const result: Record<string, unknown> = {};
  const toneScore = typeof parsed.tone_score === "number"
    ? Math.max(-1, Math.min(1, parsed.tone_score))
    : null;
  const nvc = Array.isArray(parsed.nvc_violations)
    ? parsed.nvc_violations.filter((item): item is string =>
      typeof item === "string" && ALLOWED_NVC.has(item)
    )
    : [];
  const bidType = typeof parsed.bid_type === "string" && ALLOWED_BID_TYPES.has(parsed.bid_type)
    ? parsed.bid_type
    : null;
  const sentiment = typeof parsed.sentiment === "string" && ALLOWED_SENTIMENTS.has(parsed.sentiment)
    ? parsed.sentiment
    : null;

  if (toneScore != null) {
    result.tone_score = toneScore;
  }
  result.nvc_violations = nvc;
  result.bid_type = bidType;
  if (sentiment != null) {
    result.sentiment = sentiment;
  }
  return result;
}
```

- [ ] **Step 4: Write the SQL test**

```sql
-- supabase/tests/message_sentiment_test.sql
-- Run with: psql "$DATABASE_URL" -f supabase/tests/message_sentiment_test.sql
BEGIN;

-- A valid sentiment value is accepted.
INSERT INTO public.users (id, phone, display_name) VALUES
  ('11111111-1111-1111-1111-111111111111', '+1000000001', 'Test A'),
  ('22222222-2222-2222-2222-222222222222', '+1000000002', 'Test B');
INSERT INTO public.relationships (id, user_a, user_b, status, started_at) VALUES
  ('33333333-3333-3333-3333-333333333333',
   '11111111-1111-1111-1111-111111111111',
   '22222222-2222-2222-2222-222222222222',
   'active', now()::date);

INSERT INTO public.messages (relationship_id, sender_id, content, sentiment)
VALUES (
  '33333333-3333-3333-3333-333333333333',
  '11111111-1111-1111-1111-111111111111',
  'hello',
  'positive'
);

DO $$
BEGIN
  ASSERT (SELECT sentiment FROM public.messages WHERE content = 'hello') = 'positive',
    'sentiment column did not persist the expected value';
END $$;

-- An invalid sentiment value is rejected by the CHECK constraint.
DO $$
BEGIN
  BEGIN
    INSERT INTO public.messages (relationship_id, sender_id, content, sentiment)
    VALUES (
      '33333333-3333-3333-3333-333333333333',
      '11111111-1111-1111-1111-111111111111',
      'bad',
      'ecstatic'
    );
    RAISE EXCEPTION 'expected CHECK constraint violation for invalid sentiment';
  EXCEPTION WHEN check_violation THEN
    -- expected
    NULL;
  END;
END $$;

ROLLBACK;
```

- [ ] **Step 5: Run the SQL test**

Run: `psql "$DATABASE_URL" -f supabase/tests/message_sentiment_test.sql` (use your local Supabase Postgres connection string, e.g. from `supabase status`)
Expected: no `ASSERT`/`EXCEPTION` output — the script completes silently, meaning both assertions passed. The final `ROLLBACK` means no test data is left behind.

- [ ] **Step 6: Commit**

```bash
git add supabase/migrations/20260721120000_message_sentiment.sql supabase/functions/analyse-message/index.ts supabase/tests/message_sentiment_test.sql
git commit -m "feat(chat): persist Layer-1 sentiment instead of discarding it

Claude's Layer-1 analysis already returns a sentiment field per message,
but validateLayerOne() dropped it before the UPDATE. Ask-2 eligibility
(next task) needs a real positive-valence signal — this is it."
```

---

### Task 2: Service-role eligibility RPC

**Files:**
- Create: `supabase/migrations/20260721121000_ask2_eligibility.sql`
- Test: `supabase/tests/ask2_eligibility_test.sql` (new)

**Interfaces:**
- Consumes: `messages.sentiment` (Task 1), `relationships.user_a`/`user_b`/`status`.
- Produces: `public.ask2_eligibility(p_relationship_id uuid) RETURNS TABLE (eligible boolean, first_positive_message_id uuid, first_positive_at timestamptz)`. Consumed by Task 3's cron sweep.

- [ ] **Step 1: Write the migration**

```sql
-- supabase/migrations/20260721121000_ask2_eligibility.sql
-- Service-role-only eligibility check for Ask-2 (ATTUNE_MASTER_SPEC.md
-- decision 29): both partners active on 3+ distinct local days, each has
-- sent >= 30 messages, and at least one message has positive sentiment.
--
-- Unlike chat_conversation_streak (SECURITY DEFINER keyed off auth.uid(),
-- callable by any authenticated user for their own relationship), this
-- function takes an explicit relationship_id and is NOT auth.uid()-scoped —
-- it must be callable by the cron sweep (Task 3) for arbitrary relationships,
-- not just "the caller's own." REVOKE/GRANT below restricts it to the
-- service role only, same pattern as other service-only functions in this
-- codebase would use (there is no "authenticated" grant here, deliberately).
CREATE OR REPLACE FUNCTION public.ask2_eligibility(
  p_relationship_id uuid
)
RETURNS TABLE (
  eligible boolean,
  first_positive_message_id uuid,
  first_positive_at timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_rel public.relationships%ROWTYPE;
  v_user_a_count int;
  v_user_b_count int;
  v_day_count int;
  v_first_positive_id uuid;
  v_first_positive_at timestamptz;
BEGIN
  SELECT * INTO v_rel FROM public.relationships WHERE id = p_relationship_id;

  IF NOT FOUND OR v_rel.user_b IS NULL OR v_rel.status <> 'active' THEN
    RETURN QUERY SELECT false, NULL::uuid, NULL::timestamptz;
    RETURN;
  END IF;

  SELECT count(*) INTO v_user_a_count
  FROM public.messages
  WHERE relationship_id = p_relationship_id AND sender_id = v_rel.user_a;

  SELECT count(*) INTO v_user_b_count
  FROM public.messages
  WHERE relationship_id = p_relationship_id AND sender_id = v_rel.user_b;

  IF v_user_a_count < 30 OR v_user_b_count < 30 THEN
    RETURN QUERY SELECT false, NULL::uuid, NULL::timestamptz;
    RETURN;
  END IF;

  -- Distinct local days (UTC bucketing — matches chat_conversation_streak's
  -- pattern of using a caller-supplied UTC offset for local-day bucketing,
  -- but the sweep is not tied to a single user's timezone, so UTC calendar
  -- days are used here as a deliberately simpler, timezone-agnostic proxy.
  -- "3+ distinct days" is a coarse threshold; exact local-midnight precision
  -- does not materially change the trigger's behaviour).
  SELECT count(*) INTO v_day_count
  FROM (
    SELECT (created_at::date) AS day
    FROM public.messages
    WHERE relationship_id = p_relationship_id
    GROUP BY 1
    HAVING bool_or(sender_id = v_rel.user_a) AND bool_or(sender_id = v_rel.user_b)
  ) qualifying_days;

  IF v_day_count < 3 THEN
    RETURN QUERY SELECT false, NULL::uuid, NULL::timestamptz;
    RETURN;
  END IF;

  SELECT id, created_at INTO v_first_positive_id, v_first_positive_at
  FROM public.messages
  WHERE relationship_id = p_relationship_id AND sentiment = 'positive'
  ORDER BY created_at ASC
  LIMIT 1;

  IF v_first_positive_id IS NULL THEN
    RETURN QUERY SELECT false, NULL::uuid, NULL::timestamptz;
    RETURN;
  END IF;

  RETURN QUERY SELECT true, v_first_positive_id, v_first_positive_at;
END;
$$;

REVOKE ALL ON FUNCTION public.ask2_eligibility(uuid) FROM PUBLIC, anon, authenticated;
-- No GRANT to authenticated: this function is service-role-only, called by
-- the evaluate-ask2-eligibility edge function's service-role client, which
-- authenticates via the service_role JWT (bypasses PostgREST's role grants
-- entirely) — the REVOKE above is defence in depth against a client ever
-- calling it directly.
```

- [ ] **Step 2: Run the migration locally**

Run: `supabase db reset` (or `supabase migration up`)
Expected: migration applies with no errors.

- [ ] **Step 3: Write the SQL test covering all four gating conditions**

```sql
-- supabase/tests/ask2_eligibility_test.sql
-- Run with: psql "$DATABASE_URL" -f supabase/tests/ask2_eligibility_test.sql
BEGIN;

INSERT INTO public.users (id, phone, display_name) VALUES
  ('a1111111-1111-1111-1111-111111111111', '+1000000011', 'User A'),
  ('b2222222-2222-2222-2222-222222222222', '+1000000012', 'User B');

-- Case 1: relationship not yet linked (user_b IS NULL) -> not eligible.
INSERT INTO public.relationships (id, user_a, status, invite_code, invite_expires_at) VALUES
  ('c0000001-0000-0000-0000-000000000001',
   'a1111111-1111-1111-1111-111111111111',
   'pending', 'TESTCODE1', now() + interval '1 day');

DO $$
DECLARE v_eligible boolean;
BEGIN
  SELECT eligible INTO v_eligible FROM public.ask2_eligibility('c0000001-0000-0000-0000-000000000001');
  ASSERT v_eligible = false, 'unlinked relationship must not be eligible';
END $$;

-- Case 2: linked, but under the 30-messages-each threshold -> not eligible.
INSERT INTO public.relationships (id, user_a, user_b, status, started_at) VALUES
  ('c0000002-0000-0000-0000-000000000002',
   'a1111111-1111-1111-1111-111111111111',
   'b2222222-2222-2222-2222-222222222222',
   'active', now()::date);

INSERT INTO public.messages (relationship_id, sender_id, content, sentiment, created_at)
SELECT 'c0000002-0000-0000-0000-000000000002',
       'a1111111-1111-1111-1111-111111111111',
       'msg ' || n, 'positive', now()
FROM generate_series(1, 5) AS n;
INSERT INTO public.messages (relationship_id, sender_id, content, sentiment, created_at)
SELECT 'c0000002-0000-0000-0000-000000000002',
       'b2222222-2222-2222-2222-222222222222',
       'msg ' || n, 'positive', now()
FROM generate_series(1, 5) AS n;

DO $$
DECLARE v_eligible boolean;
BEGIN
  SELECT eligible INTO v_eligible FROM public.ask2_eligibility('c0000002-0000-0000-0000-000000000002');
  ASSERT v_eligible = false, 'under-threshold message count must not be eligible';
END $$;

-- Case 3: 30+ messages each, but all on one day, and no positive sentiment
-- -> not eligible (fails both day-count and sentiment gates).
INSERT INTO public.relationships (id, user_a, user_b, status, started_at) VALUES
  ('c0000003-0000-0000-0000-000000000003',
   'a1111111-1111-1111-1111-111111111111',
   'b2222222-2222-2222-2222-222222222222',
   'active', now()::date);

INSERT INTO public.messages (relationship_id, sender_id, content, sentiment, created_at)
SELECT 'c0000003-0000-0000-0000-000000000003',
       'a1111111-1111-1111-1111-111111111111',
       'msg ' || n, 'neutral', now()
FROM generate_series(1, 30) AS n;
INSERT INTO public.messages (relationship_id, sender_id, content, sentiment, created_at)
SELECT 'c0000003-0000-0000-0000-000000000003',
       'b2222222-2222-2222-2222-222222222222',
       'msg ' || n, 'neutral', now()
FROM generate_series(1, 30) AS n;

DO $$
DECLARE v_eligible boolean;
BEGIN
  SELECT eligible INTO v_eligible FROM public.ask2_eligibility('c0000003-0000-0000-0000-000000000003');
  ASSERT v_eligible = false, 'single-day, no-positive-sentiment case must not be eligible';
END $$;

-- Case 4: fully eligible — 30+ each, spread across 3+ distinct days, with a
-- positive-sentiment message.
INSERT INTO public.relationships (id, user_a, user_b, status, started_at) VALUES
  ('c0000004-0000-0000-0000-000000000004',
   'a1111111-1111-1111-1111-111111111111',
   'b2222222-2222-2222-2222-222222222222',
   'active', (now() - interval '3 days')::date);

INSERT INTO public.messages (relationship_id, sender_id, content, sentiment, created_at)
SELECT 'c0000004-0000-0000-0000-000000000004',
       'a1111111-1111-1111-1111-111111111111',
       'msg ' || n,
       CASE WHEN n = 1 THEN 'positive' ELSE 'neutral' END,
       now() - ((n % 3) || ' days')::interval
FROM generate_series(1, 30) AS n;
INSERT INTO public.messages (relationship_id, sender_id, content, sentiment, created_at)
SELECT 'c0000004-0000-0000-0000-000000000004',
       'b2222222-2222-2222-2222-222222222222',
       'msg ' || n, 'neutral',
       now() - ((n % 3) || ' days')::interval
FROM generate_series(1, 30) AS n;

DO $$
DECLARE v_eligible boolean; v_msg_id uuid;
BEGIN
  SELECT eligible, first_positive_message_id INTO v_eligible, v_msg_id
  FROM public.ask2_eligibility('c0000004-0000-0000-0000-000000000004');
  ASSERT v_eligible = true, 'fully-qualifying relationship must be eligible';
  ASSERT v_msg_id IS NOT NULL, 'eligible result must include the first positive message id';
END $$;

ROLLBACK;
```

- [ ] **Step 4: Run the SQL test**

Run: `psql "$DATABASE_URL" -f supabase/tests/ask2_eligibility_test.sql`
Expected: no `ASSERT` failures printed; script completes silently.

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/20260721121000_ask2_eligibility.sql supabase/tests/ask2_eligibility_test.sql
git commit -m "feat(onboarding): ask2_eligibility service-role RPC

Computes whether a couple qualifies for Ask 2 per decision 29's
threshold: 30+ messages each, 3+ distinct active days, at least one
positive-sentiment message. Service-role only — not exposed to clients."
```

---

### Task 3: `ask2_state` table + cron-driven eligibility sweep

**Files:**
- Create: `supabase/migrations/20260721122000_ask2_state.sql`
- Create: `supabase/functions/evaluate-ask2-eligibility/index.ts`
- Create: `supabase/sql/schedule_evaluate_ask2_eligibility.sql`
- Test: `supabase/tests/ask2_state_test.sql` (new)

**Interfaces:**
- Consumes: `public.ask2_eligibility(uuid)` (Task 2), `serviceRoleClient()`/`requireServiceRole()`/`jsonResponse()` from `supabase/functions/_shared/attune_auth.ts`.
- Produces: `public.ask2_state` table (`SELECT`-only to `authenticated`) with `status` values `'pending'|'eligible'|'prompted'|'reminded'|'completed'|'skipped'`, and `public.complete_ask2(p_relationship_id uuid) RETURNS void` — the only client-callable write path onto `ask2_state` (verifies caller membership, transitions `'prompted'|'reminded' -> 'completed'`). Consumed by Task 4 (notification insertion happens inside this same edge function) and Task 5 (`Ask2Flow` reads `ask2_state` and calls `complete_ask2` on finishing).

- [ ] **Step 1: Write the `ask2_state` migration**

```sql
-- supabase/migrations/20260721122000_ask2_state.sql
-- Tracks each couple's progress through the Ask-2 lifecycle (decision 29).
-- One row per relationship, created lazily by the eligibility sweep.
CREATE TABLE IF NOT EXISTS public.ask2_state (
  relationship_id uuid PRIMARY KEY REFERENCES public.relationships(id) ON DELETE CASCADE,
  status text NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'eligible', 'prompted', 'reminded', 'completed', 'skipped')),
  eligible_at timestamptz,
  first_positive_message_id uuid REFERENCES public.messages(id),
  prompted_at timestamptz,
  reminded_at timestamptz,
  completed_at timestamptz,
  skipped_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.ask2_state ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON public.ask2_state FROM PUBLIC, anon;

-- Both relationship members can read their own Ask-2 state (Ask2Flow, Task 5,
-- needs this to know whether to show intro/resume/already-completed UI).
-- Writes go through the service role only (the sweep, and Ask2Flow's
-- completion/skip RPC in Task 5) — no direct client INSERT/UPDATE grant.
CREATE POLICY ask2_state_relationship_read
ON public.ask2_state FOR SELECT TO authenticated
USING (
  relationship_id IN (
    SELECT id FROM public.relationships
    WHERE user_a = auth.uid() OR user_b = auth.uid()
  )
);

GRANT SELECT ON public.ask2_state TO authenticated;

-- Client-facing completion RPC. Ask2Flow (Task 5) calls this instead of
-- UPDATE-ing ask2_state directly — there is no client UPDATE grant on the
-- table above, matching the same read-only-to-clients /
-- SECURITY-DEFINER-RPC-writes pattern already used by
-- attachment_compatibility_cache (see 20260717130000_attachment_compatibility_cache.sql).
-- Verifies the caller is a member of the relationship before writing, and
-- only transitions FROM 'prompted'/'reminded' (the only states a real
-- completion can follow) so a stray call can't fabricate history.
CREATE OR REPLACE FUNCTION public.complete_ask2(
  p_relationship_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.relationships
    WHERE id = p_relationship_id
      AND (user_a = auth.uid() OR user_b = auth.uid())
  ) THEN
    RAISE EXCEPTION 'forbidden' USING ERRCODE = '42501';
  END IF;

  UPDATE public.ask2_state
  SET status = 'completed',
      completed_at = now(),
      updated_at = now()
  WHERE relationship_id = p_relationship_id
    AND status IN ('prompted', 'reminded');
END;
$$;

REVOKE ALL ON FUNCTION public.complete_ask2(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.complete_ask2(uuid) TO authenticated;
```

- [ ] **Step 2: Run the migration locally**

Run: `supabase db reset`
Expected: `ask2_state` table exists with RLS enabled and the read policy in place.

- [ ] **Step 3: Write the edge function**

```typescript
// supabase/functions/evaluate-ask2-eligibility/index.ts
import { serve } from "https://deno.land/std@0.177.0/http/server.ts";

import { jsonResponse, requireServiceRole, serviceRoleClient } from "../_shared/attune_auth.ts";

const REMINDER_WINDOW_MS = 7 * 24 * 60 * 60 * 1000;

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return jsonResponse({ ok: true });
  }

  const supabase = serviceRoleClient();

  try {
    requireServiceRole(req);

    const newlyEligible = await sweepNewlyEligible(supabase);
    const reminded = await sweepReminders(supabase);

    return jsonResponse({
      success: true,
      prompted: newlyEligible.length,
      reminded: reminded.length,
    });
  } catch (error) {
    return jsonResponse(
      { success: false, error: error instanceof Error ? error.message : String(error) },
      500,
    );
  }
});

async function sweepNewlyEligible(
  supabase: ReturnType<typeof serviceRoleClient>,
) {
  // Candidates: active relationships with no ask2_state row yet, or a row
  // still in 'pending' (created but not yet found eligible on a prior sweep).
  const { data: candidates, error } = await supabase
    .from("relationships")
    .select("id, ask2_state(status)")
    .eq("status", "active")
    .not("user_b", "is", null);
  if (error) throw error;

  const results = [];

  for (const relationship of candidates ?? []) {
    const stateRows = relationship.ask2_state as Array<{ status: string }> | null;
    const currentStatus = stateRows && stateRows.length > 0 ? stateRows[0].status : null;
    if (currentStatus && currentStatus !== "pending") continue;

    const { data: eligibility, error: eligError } = await supabase
      .rpc("ask2_eligibility", { p_relationship_id: relationship.id })
      .single();
    if (eligError) throw eligError;

    const row = eligibility as {
      eligible: boolean;
      first_positive_message_id: string | null;
      first_positive_at: string | null;
    };

    if (!row.eligible) {
      await supabase
        .from("ask2_state")
        .upsert({ relationship_id: relationship.id, status: "pending" }, { onConflict: "relationship_id" });
      continue;
    }

    const now = new Date().toISOString();
    await supabase.from("ask2_state").upsert({
      relationship_id: relationship.id,
      status: "prompted",
      eligible_at: now,
      first_positive_message_id: row.first_positive_message_id,
      prompted_at: now,
      updated_at: now,
    }, { onConflict: "relationship_id" });

    await sendAsk2Notification(supabase, String(relationship.id));
    results.push(relationship.id);
  }

  return results;
}

async function sweepReminders(
  supabase: ReturnType<typeof serviceRoleClient>,
) {
  const cutoff = new Date(Date.now() - REMINDER_WINDOW_MS).toISOString();

  const { data: dueForReminder, error } = await supabase
    .from("ask2_state")
    .select("relationship_id, prompted_at")
    .eq("status", "prompted")
    .lt("prompted_at", cutoff);
  if (error) throw error;

  const results = [];

  for (const row of dueForReminder ?? []) {
    const now = new Date().toISOString();
    await supabase
      .from("ask2_state")
      .update({ status: "reminded", reminded_at: now, updated_at: now })
      .eq("relationship_id", row.relationship_id)
      .eq("status", "prompted"); // guard against a race with a concurrent completion

    await sendAsk2Notification(supabase, String(row.relationship_id));
    results.push(row.relationship_id);
  }

  return results;
}

async function sendAsk2Notification(
  supabase: ReturnType<typeof serviceRoleClient>,
  relationshipId: string,
) {
  const { data: relationship, error } = await supabase
    .from("relationships")
    .select("user_a, user_b")
    .eq("id", relationshipId)
    .single();
  if (error) throw error;

  const title = "We noticed something good";
  const body =
    "You two have a real rhythm going. Want to see what Attune can tell you about how you communicate?";
  const data = { type: "ask2_invite", relationship_id: relationshipId };

  for (const userId of [relationship.user_a, relationship.user_b]) {
    if (!userId) continue;
    const { error: inAppError } = await supabase.from("in_app_notifications").insert({
      user_id: userId,
      title,
      body,
      data,
    });
    if (inAppError) throw inAppError;

    const { error: scheduledError } = await supabase.from("scheduled_notifications").insert({
      user_id: userId,
      notification_type: "ask2_invite",
      scheduled_for: new Date().toISOString(),
      status: "pending",
      metadata: data,
    });
    if (scheduledError) throw scheduledError;
  }
}
```

- [ ] **Step 4: Write the cron schedule SQL**

```sql
-- supabase/sql/schedule_evaluate_ask2_eligibility.sql
-- Run in Supabase SQL editor after enabling pg_cron and pg_net.
-- Configure app.settings.supabase_url and app.settings.service_role_key first.

SELECT cron.schedule(
  'evaluate-ask2-eligibility-sweep',
  '17 * * * *',
  $$
  SELECT net.http_post(
    url := current_setting('app.settings.supabase_url') || '/functions/v1/evaluate-ask2-eligibility',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || current_setting('app.settings.service_role_key'),
      'apikey', current_setting('app.settings.service_role_key')
    ),
    body := '{}'::jsonb
  ) AS request_id;
  $$
);
```

- [ ] **Step 5: Write the SQL test for `ask2_state` lifecycle transitions**

```sql
-- supabase/tests/ask2_state_test.sql
-- Run with: psql "$DATABASE_URL" -f supabase/tests/ask2_state_test.sql
BEGIN;

INSERT INTO public.users (id, phone, display_name) VALUES
  ('d1111111-1111-1111-1111-111111111111', '+1000000021', 'User D1'),
  ('d2222222-2222-2222-2222-222222222222', '+1000000022', 'User D2');
INSERT INTO public.relationships (id, user_a, user_b, status, started_at) VALUES
  ('e0000001-0000-0000-0000-000000000001',
   'd1111111-1111-1111-1111-111111111111',
   'd2222222-2222-2222-2222-222222222222',
   'active', now()::date);

-- A fresh row defaults to 'pending'.
INSERT INTO public.ask2_state (relationship_id) VALUES ('e0000001-0000-0000-0000-000000000001');

DO $$
DECLARE v_status text;
BEGIN
  SELECT status INTO v_status FROM public.ask2_state WHERE relationship_id = 'e0000001-0000-0000-0000-000000000001';
  ASSERT v_status = 'pending', 'new ask2_state row must default to pending';
END $$;

-- An invalid status is rejected by the CHECK constraint.
DO $$
BEGIN
  BEGIN
    UPDATE public.ask2_state SET status = 'not_a_real_status'
    WHERE relationship_id = 'e0000001-0000-0000-0000-000000000001';
    RAISE EXCEPTION 'expected CHECK constraint violation for invalid status';
  EXCEPTION WHEN check_violation THEN
    NULL; -- expected
  END;
END $$;

-- complete_ask2: a relationship MEMBER can transition prompted -> completed.
-- Supabase's auth.uid() reads request.jwt.claims -> sub; set it directly to
-- simulate an authenticated call from user D1.
INSERT INTO public.ask2_state (relationship_id, status, prompted_at)
VALUES ('e0000001-0000-0000-0000-000000000001', 'prompted', now());

SELECT set_config('request.jwt.claims', '{"sub":"d1111111-1111-1111-1111-111111111111"}', true);

SELECT public.complete_ask2('e0000001-0000-0000-0000-000000000001');

DO $$
DECLARE v_status text; v_completed_at timestamptz;
BEGIN
  SELECT status, completed_at INTO v_status, v_completed_at
  FROM public.ask2_state WHERE relationship_id = 'e0000001-0000-0000-0000-000000000001';
  ASSERT v_status = 'completed', 'complete_ask2 must transition prompted -> completed for a member';
  ASSERT v_completed_at IS NOT NULL, 'complete_ask2 must stamp completed_at';
END $$;

-- complete_ask2: a NON-member is rejected.
INSERT INTO public.users (id, phone, display_name) VALUES
  ('f3333333-3333-3333-3333-333333333333', '+1000000023', 'Outsider');
INSERT INTO public.relationships (id, user_a, user_b, status, started_at) VALUES
  ('e0000002-0000-0000-0000-000000000002',
   'd1111111-1111-1111-1111-111111111111',
   'd2222222-2222-2222-2222-222222222222',
   'active', now()::date);
INSERT INTO public.ask2_state (relationship_id, status, prompted_at)
VALUES ('e0000002-0000-0000-0000-000000000002', 'prompted', now());

SELECT set_config('request.jwt.claims', '{"sub":"f3333333-3333-3333-3333-333333333333"}', true);

DO $$
BEGIN
  BEGIN
    PERFORM public.complete_ask2('e0000002-0000-0000-0000-000000000002');
    RAISE EXCEPTION 'expected forbidden error for a non-member calling complete_ask2';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'forbidden' THEN
      RAISE;
    END IF;
  END;
END $$;

-- Deleting the relationship cascades to ask2_state (ON DELETE CASCADE).
DELETE FROM public.relationships WHERE id = 'e0000001-0000-0000-0000-000000000001';

DO $$
DECLARE v_count int;
BEGIN
  SELECT count(*) INTO v_count FROM public.ask2_state WHERE relationship_id = 'e0000001-0000-0000-0000-000000000001';
  ASSERT v_count = 0, 'ask2_state row must be cascade-deleted with its relationship';
END $$;

ROLLBACK;
```

- [ ] **Step 6: Run the SQL test**

Run: `psql "$DATABASE_URL" -f supabase/tests/ask2_state_test.sql`
Expected: no `ASSERT` failures; script completes silently.

- [ ] **Step 7: Manually verify the edge function locally**

Run: `supabase functions serve evaluate-ask2-eligibility --env-file supabase/.env.local` (adjust env file path to match how other functions in this repo are served locally — check `supabase/functions/analyse-session` for the exact local-serve convention already in use if this differs)
Then in a second terminal: `curl -X POST http://localhost:54321/functions/v1/evaluate-ask2-eligibility -H "Authorization: Bearer $SERVICE_ROLE_KEY" -H "Content-Type: application/json" -d '{}'`
Expected: `{"success":true,"prompted":0,"reminded":0}` (0 is correct with no seeded eligible relationships in your local dev data).

- [ ] **Step 8: Commit**

```bash
git add supabase/migrations/20260721122000_ask2_state.sql supabase/functions/evaluate-ask2-eligibility/index.ts supabase/sql/schedule_evaluate_ask2_eligibility.sql supabase/tests/ask2_state_test.sql
git commit -m "feat(onboarding): ask2_state table + hourly eligibility sweep

evaluate-ask2-eligibility runs hourly, calls ask2_eligibility per active
relationship, and transitions ask2_state through pending -> prompted ->
reminded (7-day window, one reminder max). Notification insertion is
folded into this same sweep rather than a separate step, since the
state transition and the notification must happen atomically from the
sweep's perspective. Also adds complete_ask2(), the only client-callable
write onto ask2_state (SECURITY DEFINER, membership-checked) — Ask2Flow
calls it on finishing in a later task."
```

---

### Task 4: `NotificationType` + client-side deep-link tap handling

**Files:**
- Modify: `lib/core/notifications/domain/entities/notification_type.dart`
- Modify: `lib/core/notifications/config/notification_config.dart`
- Modify: `lib/app/routing/app_router.dart`
- Test: `test/core/notifications/ask2_notification_routing_test.dart` (new)

**Interfaces:**
- Consumes: `notification.data['type'] == 'ask2_invite'` and `notification.data['relationship_id']` (written by Task 3's edge function).
- Produces: `RouteNames.ask2Flow` route constant, a registered `GoRoute` at path `/ask2/:relationshipId`. Consumed by Task 5 (`Ask2Flow` is the screen this route builds).

- [ ] **Step 1: Add the `ask2Invite` notification type constant**

In `lib/core/notifications/domain/entities/notification_type.dart`, add to `CommonNotificationTypes` (after the existing `system` constant, around line 62):

```dart
  static const ask2Invite = NotificationType(value: 'ask2_invite', priority: 6);
```

- [ ] **Step 2: Add the route constant**

In `lib/app/routing/app_router.dart`, inside `class RouteNames` (near the other route constants, around line 28), add:

```dart
  static const String ask2Flow = '/ask2/:relationshipId';
```

- [ ] **Step 3: Register the `GoRoute`**

In `lib/app/routing/app_router.dart`, add a new `GoRoute` alongside the existing `/games/paint-ball/lobby/:relationshipId` route (same file, same pattern, around line 239):

```dart
      GoRoute(
        path: RouteNames.ask2Flow,
        builder: (context, state) {
          final relationshipId = state.pathParameters['relationshipId']!;
          return Ask2Flow(relationshipId: relationshipId);
        },
      ),
```

Add the import at the top of the file (this widget is created in Task 5 — this step will not compile until Task 5 lands; that's expected and acceptable since Task 5 is the very next task in this same plan, executed before this task is considered done end-to-end. If running tasks out of order, stub `Ask2Flow` as a placeholder `StatelessWidget` returning `SizedBox.shrink()` temporarily):

```dart
import 'package:attune/features/onboarding/presentation/screens/ask2_flow.dart';
```

- [ ] **Step 4: Wire the notification tap handler**

In `lib/core/notifications/config/notification_config.dart`, inside the `onNotificationTap` switch statement (around line 74-113), add a new case before the `default:` branch:

```dart
        case 'ask2_invite':
          final relationshipId = notification.data?['relationship_id'] as String?;
          if (relationshipId != null && relationshipId.isNotEmpty) {
            GoRouter.of(context).push(
              '/ask2/${Uri.encodeComponent(relationshipId)}',
            );
          } else {
            GoRouter.of(context).go(RouteNames.home);
          }
          return;
```

- [ ] **Step 5: Write the routing test**

```dart
// test/core/notifications/ask2_notification_routing_test.dart
import 'package:attune/app/routing/app_router.dart';
import 'package:attune/core/notifications/domain/entities/notification_type.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ask2Invite notification type carries the expected value', () {
    expect(CommonNotificationTypes.ask2Invite.value, 'ask2_invite');
  });

  test('ask2Flow route path matches the relationship-id path param convention', () {
    expect(RouteNames.ask2Flow, '/ask2/:relationshipId');
  });
}
```

- [ ] **Step 6: Run the test**

Run: `flutter test test/core/notifications/ask2_notification_routing_test.dart`
Expected: both tests pass. (This test intentionally does not exercise the GoRouter tap-handling switch statement directly — that requires a full `BuildContext`/router harness better covered by Task 5's widget tests, which will navigate through the real route.)

- [ ] **Step 7: Run `flutter analyze` on changed files**

Run: `flutter analyze lib/core/notifications/domain/entities/notification_type.dart lib/core/notifications/config/notification_config.dart lib/app/routing/app_router.dart`
Expected: no new errors. (A "target of URI doesn't exist" error for `ask2_flow.dart` is expected until Task 5 lands — do not treat that as a blocking failure for this task if executing sequentially task-by-task in the same session, since Task 5 immediately follows.)

- [ ] **Step 8: Commit**

```bash
git add lib/core/notifications/domain/entities/notification_type.dart lib/core/notifications/config/notification_config.dart lib/app/routing/app_router.dart test/core/notifications/ask2_notification_routing_test.dart
git commit -m "feat(onboarding): wire ask2_invite notification type + deep link route

Notification tap on type 'ask2_invite' now routes to /ask2/:relationshipId.
Ask2Flow itself lands in the next task; this task only wires the plumbing
so the notification tap handler compiles against a real route."
```

---

### Task 5: `Ask2Flow` — standalone re-entry widget

**Files:**
- Create: `lib/features/onboarding/presentation/screens/ask2_flow.dart`
- Create: `lib/features/onboarding/presentation/widgets/intelligence_intro_step.dart`
- Create: `lib/features/onboarding/presentation/widgets/ask2_reveal_step.dart`
- Create: `lib/features/onboarding/data/ask2_submission_service.dart`
- Modify: `supabase/migrations/20260721122000_ask2_state.sql` → actually modify `20260721123000_onboarding_profiles_ask2.sql` (new migration, additive)
- Test: `test/features/onboarding/ask2_flow_test.dart` (new)

**Interfaces:**
- Consumes: `AttachmentQuizStep` (`lib/features/onboarding/presentation/widgets/attachment_quiz_step.dart`, unmodified — constructor: `questionIndex`, `answers`, `onChanged`, `onBack`, `onNext`), `AnchorsStep` (`lib/features/onboarding/presentation/widgets/anchors_step.dart`, unmodified — constructor: `mode`, `controllers`, `onNext`), `OnboardingStepFrame`/`OnboardingDeckScope`/`OnboardingDeckAccent` (unmodified), `attachmentQuestions` list and `relationshipAnchorPrompts` (`lib/features/onboarding/domain/onboarding_models.dart`, unmodified), `AttachmentQuizDocs`/`AnchorsDocs` and `BottomSheetUtils.showDocumentationBottomSheet`/`ConfirmationDialog` (all unmodified, reused verbatim per the design doc), `public.complete_ask2(p_relationship_id uuid)` (Task 3 — the only permitted client write onto `ask2_state`).
- Produces: `Ask2Flow` widget (constructor: `required String relationshipId`) — the screen Task 4's `GoRoute` builds. `upsert_attachment_compatibility_cache` RPC call (already exists, from `supabase/migrations/20260717130000_attachment_compatibility_cache.sql` — verify exact param names against that file before calling it, since Task's own knowledge may drift from the live schema).

- [ ] **Step 1: Add the `ask2_completed_at` column migration**

```sql
-- supabase/migrations/20260721123000_onboarding_profiles_ask2.sql
-- onboarding_profiles.completed_at means "Ask 1 done" for every user today.
-- Couples now need a SEPARATE marker for "Ask 2 done", since Ask 2 happens
-- days after Ask 1 and must not be conflated with it (ATTUNE_MASTER_SPEC.md
-- decision 29). Nullable: absent for personal-mode users (who have no Ask 2)
-- and for couples who haven't reached/finished Ask 2 yet.
ALTER TABLE public.onboarding_profiles
  ADD COLUMN IF NOT EXISTS ask2_completed_at timestamptz;
```

Run: `supabase db reset`
Expected: migration applies with no errors.

- [ ] **Step 2: Write `Ask2SubmissionService`**

This mirrors `OnboardingSubmissionService` but writes ONLY the Ask-2 fields — it must NOT touch `users`, `profiles`, or the Ask-1 `completed_at`, since Ask 1 already ran and wrote those.

```dart
// lib/features/onboarding/data/ask2_submission_service.dart
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Writes the quiz + anchors gathered during Ask 2 (ATTUNE_MASTER_SPEC.md
/// decision 29). Deliberately separate from OnboardingSubmissionService,
/// which writes Ask-1 identity fields (users/profiles/mode) this flow must
/// never touch — Ask 1 already completed those when the couple linked.
class Ask2SubmissionService {
  Ask2SubmissionService({SupabaseClient? client}) : _client = client;

  final SupabaseClient? _client;

  static const timeout = Duration(seconds: 30);

  SupabaseClient? get _safeClient {
    if (_client != null) return _client;
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  Future<void> submit({
    required List<int> attachmentAnswers,
    required List<String> anchors,
  }) async {
    final client = _safeClient;
    final user = client?.auth.currentUser;
    if (client == null || user == null) return;

    final now = DateTime.now().toUtc().toIso8601String();

    try {
      await client
          .from('onboarding_profiles')
          .update({
            'attachment_answers': attachmentAnswers,
            'anchors': anchors,
            'ask2_completed_at': now,
          })
          .eq('user_id', user.id)
          .timeout(timeout);
    } catch (error) {
      debugPrint('[ask2] remote submit failed: ${error.runtimeType}');
      rethrow;
    }
  }
}
```

- [ ] **Step 3: Write `IntelligenceIntroStep`**

Reuses the confirmation-gate pattern from `onboarding_flow.dart`'s `_confirmMoveOn`/`AttachmentQuizDocs` — since that infrastructure already exists and is designed to be reusable, this step is a thin composition, not a rebuild.

```dart
// lib/features/onboarding/presentation/widgets/intelligence_intro_step.dart
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/onboarding/presentation/data/attachment_quiz_docs.dart';
import 'package:attune/features/onboarding/presentation/widgets/onboarding_step_frame.dart';

/// The first screen of Ask 2 — the one place in the whole app allowed to
/// introduce "AI/analysis/insight" vocabulary (ATTUNE_MASTER_SPEC.md
/// decision 29's Ask-1 invite rules only restrict Ask 1). Explains why the
/// quiz + anchors are showing up now, anchored to a positive observation
/// rather than a deficit, before asking the couple to continue.
class IntelligenceIntroStep extends StatelessWidget {
  const IntelligenceIntroStep({super.key, required this.onNext});

  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return OnboardingStepFrame(
      title: 'A closer look',
      icon: Icons.auto_awesome_outlined,
      subtitle:
          'You two have a real rhythm going. This is optional, and skipping it costs you nothing.',
      child: Column(
        children: [
          Gap(Spacing.xl.h),
          Text(
            'A short quiz and three questions help Attune understand how '
            'you both communicate — so what it shows you actually fits '
            'your relationship, not a generic average.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          Gap(Spacing.xl.h),
          AppButton(
            textColor: colorScheme.surface,
            label: 'Continue',
            onPressed: onNext,
            size: ButtonSize.small,
            height: OnboardingTokens.actionButtonHeight.h,
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Write `Ask2RevealStep`**

```dart
// lib/features/onboarding/presentation/widgets/ask2_reveal_step.dart
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/onboarding/presentation/widgets/onboarding_step_frame.dart';

/// Terminal screen of Ask 2. Per the design doc's scope boundary, this is a
/// minimal reveal, not a redesigned compatibility-preview experience — the
/// existing attachment_compatibility_cache RPC/provider already handle the
/// actual computation and read path (lib/features/quiz/presentation/
/// providers/quiz_providers.dart); this screen only confirms completion.
class Ask2RevealStep extends StatelessWidget {
  const Ask2RevealStep({super.key, required this.onDone});

  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return OnboardingStepFrame(
      title: "You're both in",
      icon: Icons.favorite_outline,
      subtitle:
          'Your compatibility preview is coming together — check back in your profile shortly.',
      child: Column(
        children: [
          Gap(Spacing.xl.h),
          AppButton(
            textColor: colorScheme.surface,
            label: 'Done',
            onPressed: onDone,
            size: ButtonSize.small,
            height: OnboardingTokens.actionButtonHeight.h,
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 5: Write `Ask2Flow`**

Before writing this step, read `supabase/migrations/20260717130000_attachment_compatibility_cache.sql` again to confirm the exact `upsert_attachment_compatibility_cache` RPC parameter names (`p_relationship_id, p_type_a, p_type_b, p_pairing_name, p_pairing_description, p_natural_strength, p_watch_area`) — this task only triggers cache regeneration eligibility, it does not compute the pairing content itself (that's the existing Claude-driven compatibility feature, out of scope here per the design doc). If the actual pairing computation is not yet wired to run automatically on both-partners-complete, skip the RPC call in this step and leave a comment — do not invent new compatibility-computation logic in this task.

```dart
// lib/features/onboarding/presentation/screens/ask2_flow.dart
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/onboarding/data/ask2_submission_service.dart';
import 'package:attune/features/onboarding/domain/onboarding_models.dart';
import 'package:attune/features/onboarding/presentation/widgets/anchors_step.dart';
import 'package:attune/features/onboarding/presentation/widgets/ask2_reveal_step.dart';
import 'package:attune/features/onboarding/presentation/widgets/attachment_quiz_step.dart';
import 'package:attune/features/onboarding/presentation/widgets/intelligence_intro_step.dart';
import 'package:attune/features/onboarding/presentation/widgets/onboarding_deck_card.dart';
import 'package:attune/features/onboarding/presentation/widgets/onboarding_deck_scope.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Ask 2 (ATTUNE_MASTER_SPEC.md decision 29) — reached only via the deep
/// link a notification sends once a couple is eligible (see
/// evaluate-ask2-eligibility). NOT a mode of OnboardingFlow: Ask 1 is
/// already complete by the time this is reachable, so this is a fully
/// separate, small state machine that composes the SAME quiz/anchors step
/// widgets Ask 1 uses for personal mode, so fixes to those widgets apply
/// to both automatically.
class Ask2Flow extends StatefulWidget {
  const Ask2Flow({super.key, required this.relationshipId});

  final String relationshipId;

  @override
  State<Ask2Flow> createState() => _Ask2FlowState();
}

class _Ask2FlowState extends State<Ask2Flow> {
  static const int _introStep = 0;
  static const int _quizStep = 1;
  static const int _anchorsStep = 2;
  static const int _revealStep = 3;

  final _anchorControllers = List.generate(3, (_) => TextEditingController());
  final _quizAnswers = List<int?>.filled(attachmentQuestions.length, null);
  final _submissionService = Ask2SubmissionService();

  int _step = _introStep;
  int _questionIndex = 0;

  @override
  void dispose() {
    for (final controller in _anchorControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  void _next() => setState(() => _step++);

  Future<void> _finish() async {
    final answers = _quizAnswers.whereType<int>().toList();
    final anchors =
        _anchorControllers.map((controller) => controller.text.trim()).toList();

    try {
      await _submissionService.submit(attachmentAnswers: answers, anchors: anchors);
      await _markAsk2StateCompleted();
    } catch (_) {
      if (mounted) {
        context.showInfoSnackbar(
          'Saved locally. We will try again the next time you open the app.',
        );
      }
    }

    _next();
  }

  Future<void> _markAsk2StateCompleted() async {
    // ask2_state has no client UPDATE grant (Task 3's migration) — writes go
    // through this SECURITY DEFINER RPC only, same pattern as
    // upsert_attachment_compatibility_cache. Handles both 'prompted' and
    // 'reminded' source states in one call (its WHERE clause covers both).
    await Supabase.instance.client.rpc(
      'complete_ask2',
      params: {'p_relationship_id': widget.relationshipId},
    );
  }

  @override
  Widget build(BuildContext context) {
    final screen = switch (_step) {
      _introStep => IntelligenceIntroStep(onNext: _next),
      _quizStep => AttachmentQuizStep(
        questionIndex: _questionIndex,
        answers: _quizAnswers,
        onChanged: (value) {
          setState(() => _quizAnswers[_questionIndex] = value);
        },
        onBack:
            _questionIndex == 0 ? null : () => setState(() => _questionIndex--),
        onNext: () {
          if (_questionIndex == attachmentQuestions.length - 1) {
            _next();
          } else {
            setState(() => _questionIndex++);
          }
        },
      ),
      _anchorsStep => AnchorsStep(
        mode: OnboardingMode.couples,
        controllers: _anchorControllers,
        onNext: _finish,
      ),
      _ => Ask2RevealStep(onDone: () => Navigator.of(context).maybePop()),
    };

    final cardKey = _step == _quizStep ? _quizStep * 1000 + _questionIndex : _step;

    return Scaffold(
      body: SafeArea(
        child: OnboardingDeckScope(
          cardKey: cardKey,
          accent: OnboardingDeckAccent.couples,
          enableDeck: _step == _quizStep,
          child: screen,
        ),
      ),
    );
  }
}
```

- [ ] **Step 6: Fix Task 4's stub import**

If Task 4 was executed with a stub `Ask2Flow`, remove the stub now that the real widget exists. Re-run `flutter analyze lib/app/routing/app_router.dart` to confirm the import resolves cleanly.

- [ ] **Step 7: Write the widget test**

```dart
// test/features/onboarding/ask2_flow_test.dart
import 'package:attune/features/onboarding/presentation/screens/ask2_flow.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Ask2Flow starts on the intelligence intro, not the quiz directly', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: ScreenUtilInit(
            designSize: const Size(390, 844),
            builder: (_, __) => const Ask2Flow(relationshipId: 'test-rel-id'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('A closer look'), findsOneWidget);
    expect(find.text('Relationship reflection quiz'), findsNothing);
  });

  testWidgets('tapping Continue on the intro advances to the quiz', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: ScreenUtilInit(
            designSize: const Size(390, 844),
            builder: (_, __) => const Ask2Flow(relationshipId: 'test-rel-id'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.text('Relationship reflection quiz'), findsOneWidget);
  });
}
```

- [ ] **Step 8: Run the widget tests**

Run: `flutter test test/features/onboarding/ask2_flow_test.dart`
Expected: both tests pass. (These tests intentionally stop short of driving the quiz/anchors/reveal steps end-to-end — `attachment_quiz_step_test.dart` already covers `AttachmentQuizStep`'s own behaviour in depth; re-testing it here would duplicate coverage rather than verify `Ask2Flow`'s actual job, which is correct composition and step ordering.)

- [ ] **Step 9: Run `flutter analyze` on all new/changed files**

Run: `flutter analyze lib/features/onboarding/presentation/screens/ask2_flow.dart lib/features/onboarding/presentation/widgets/intelligence_intro_step.dart lib/features/onboarding/presentation/widgets/ask2_reveal_step.dart lib/features/onboarding/data/ask2_submission_service.dart`
Expected: no errors.

- [ ] **Step 10: Commit**

```bash
git add lib/features/onboarding/presentation/screens/ask2_flow.dart lib/features/onboarding/presentation/widgets/intelligence_intro_step.dart lib/features/onboarding/presentation/widgets/ask2_reveal_step.dart lib/features/onboarding/data/ask2_submission_service.dart supabase/migrations/20260721123000_onboarding_profiles_ask2.sql test/features/onboarding/ask2_flow_test.dart
git commit -m "feat(onboarding): Ask2Flow standalone re-entry widget

Composes the existing AttachmentQuizStep/AnchorsStep widgets into a
separate intro -> quiz -> anchors -> reveal flow, reachable only via
the deep link a notification sends once a couple is eligible.
Writes to a new onboarding_profiles.ask2_completed_at column, kept
separate from Ask 1's completed_at."
```

---

### Task 6: Remove the Ask-1 spec violation

**Files:**
- Modify: `lib/features/onboarding/presentation/screens/onboarding_flow.dart:307-343`
- Test: `test/onboarding_flow_test.dart` (extend existing file)

**Interfaces:**
- Consumes: nothing new — this task only removes couples-mode calls to `_goToQuiz()`/`_goToAnchors()`, which remain defined and still used by nothing (they become dead code for couples but the methods themselves may still be referenced elsewhere; verify before deleting the methods entirely — see Step 3).

- [ ] **Step 1: Read the current couples branch before editing**

Re-read `lib/features/onboarding/presentation/screens/onboarding_flow.dart` lines 307-353 in full immediately before this task's edits — this file was touched several times earlier in the session (confirmation-gate additions, tap-outside-dismiss fix, etc.) and the exact current line numbers may have shifted from what earlier tasks in this plan assumed. Locate the `_ when _step == modeStep =>` branch (mode selection) and the `_ when _step == quizStep =>`/`_ when _step == anchorsStep =>` branches by content, not by the line numbers cited elsewhere in this plan.

- [ ] **Step 2: Change mode selection to skip the quiz for couples**

The mode-selection branch currently calls `_goToQuiz()` for both `OnboardingModeStep.onSelect` and `IncomingInviteStep.onNext`, regardless of which mode was chosen. Change both call sites so couples mode calls `_next()` directly (advancing straight to the terminal waiting/joined step) while personal mode keeps calling `_goToQuiz()`:

```dart
      _ when _step == modeStep =>
        pendingInviteCode == null
            ? OnboardingModeStep(
              selectedMode: mode,
              onSelect: (value) {
                setState(() => _mode = value);
                if (value == OnboardingMode.personal) {
                  _goToQuiz();
                } else {
                  _next();
                }
              },
            )
            : IncomingInviteStep(
              inviteCode: pendingInviteCode,
              onNext: () {
                setState(() => _mode = OnboardingMode.couples);
                _next();
              },
            ),
```

Note `IncomingInviteStep` always sets `OnboardingMode.couples` (never personal — that branch only exists for an incoming invite, which is inherently a couples path), so its `onNext` unconditionally calls `_next()` now instead of `_goToQuiz()`.

- [ ] **Step 3: Remove the now-couples-unreachable quiz/anchors steps from the switch**

Since couples mode never sets `_step` to `quizStep`/`anchorsStep` anymore (both mode-selection paths that used to lead there for couples now call `_next()` straight to the terminal branch), and personal mode still uses `_goToQuiz()` → quiz → `_goToAnchors()` → anchors → terminal exactly as before, the `quizStep`/`anchorsStep` switch branches and the `_goToQuiz`/`_goToAnchors` methods themselves are UNCHANGED — they still exist and still run for personal mode. Do not delete them. Confirm this by reading the full `build()` method's switch statement after Step 2's edit and verifying: for `mode == OnboardingMode.couples`, `_step` transitions `modeStep -> (modeStep+1, the old quizStep slot but now unreachable via the couples path since _next() was called, not _goToQuiz()) -> ...`.

**This surfaces a real bug in the naive fix above: `_next()` simply increments `_step`, so a couples user would land ON `quizStep`'s numeric value, not skip past it, because the switch is driven by `_step`'s integer value matching `quizStep`/`anchorsStep`, and those constants don't change.** Fix this properly: the couples path must jump `_step` past both the quiz and anchors slots, not just increment once.

Replace the naive `_next()` calls from Step 2 with a dedicated method:

```dart
  /// Couples mode skips straight from mode selection to the terminal
  /// invite/waiting step — the quiz and anchors are Ask 2 now (Task 5's
  /// Ask2Flow), not inline here. _step must jump past BOTH the quiz and
  /// anchors slots, not just increment once, since the switch dispatches
  /// on _step's exact integer value matching quizStep/anchorsStep.
  void _skipToTerminalForCouples() {
    setState(() => _step = anchorsStep + 1);
  }
```

And use it in place of the two `_next()` calls added in Step 2:

```dart
      _ when _step == modeStep =>
        pendingInviteCode == null
            ? OnboardingModeStep(
              selectedMode: mode,
              onSelect: (value) {
                setState(() => _mode = value);
                if (value == OnboardingMode.personal) {
                  _goToQuiz();
                } else {
                  _skipToTerminalForCouples();
                }
              },
            )
            : IncomingInviteStep(
              inviteCode: pendingInviteCode,
              onNext: () {
                setState(() => _mode = OnboardingMode.couples);
                _skipToTerminalForCouples();
              },
            ),
```

`anchorsStep` is already computed earlier in `build()` as `widget.requireAuth ? 4 : 3` — reference it directly, it's in scope.

- [ ] **Step 4: Extend the existing onboarding flow test**

Read `test/onboarding_flow_test.dart` in full first to match its existing helper/harness patterns exactly (the `_pumpStep`-style helpers, `ProviderScope`/`OnboardingDeckScope` wrapping conventions established earlier this session) before adding the new test — do not invent a different pumping pattern.

Add a new test to the existing `main()` block:

```dart
  testWidgets(
    'couples mode skips the inline quiz and anchors after mode selection',
    (tester) async {
      // Build using this file's existing harness for constructing OnboardingFlow
      // (see the file's existing tests for the exact store/service setup this
      // requires — mirror it here rather than reintroducing a new setup).

      // Select "In a relationship".
      await tester.tap(find.text('In a relationship'));
      await tester.pumpAndSettle();

      // The inline quiz must never appear for couples mode.
      expect(find.text('Relationship reflection quiz'), findsNothing);
      expect(find.text('Anchor 1'), findsNothing);
    },
  );
```

- [ ] **Step 5: Run the full onboarding test suite**

Run: `flutter test test/features/onboarding/ test/onboarding_flow_test.dart`
Expected: all previously-passing tests (14 from earlier this session, plus any added by Tasks 4/5) still pass, plus the new couples-skip test passes. Personal-mode tests (`attachment_quiz_step_test.dart`, the personal-mode assertions in `onboarding_flow_test.dart`) must show NO behavior change — if any personal-mode test's expectations shift, that's a regression, not an acceptable side effect.

- [ ] **Step 6: Run `flutter analyze`**

Run: `flutter analyze lib/features/onboarding/presentation/screens/onboarding_flow.dart test/onboarding_flow_test.dart`
Expected: no errors.

- [ ] **Step 7: Commit**

```bash
git add lib/features/onboarding/presentation/screens/onboarding_flow.dart test/onboarding_flow_test.dart
git commit -m "fix(onboarding): couples mode no longer runs the quiz/anchors inline

Per ATTUNE_MASTER_SPEC.md decision 29, Ask 1 must carry zero
intelligence vocabulary and stop at profile + partner invite. The
quiz and anchors now only run for personal (single) mode inline;
couples mode reaches them later via Ask2Flow once
evaluate-ask2-eligibility (an earlier task) determines the couple
qualifies. _skipToTerminalForCouples jumps _step past both slots in
one setState, since the switch dispatches on _step's exact value."
```

---

## Self-Review Notes

**Spec coverage check against the design doc's five architecture pieces:**
1. Persist sentiment — Task 1. ✓
2. Eligibility RPC — Task 2. ✓
3. `ask2_state` + cron sweep — Task 3. ✓
4. Notification (reuses existing pipeline) — folded into Task 3's edge function (insertion) + Task 4 (client-side type/route/tap-handling). ✓
5. `Ask2Flow` re-entry widget — Task 5. ✓
6. Removing the current violation — Task 6. ✓
7. 48-hour solo-reflection interaction — handled implicitly by Task 2's `user_b IS NOT NULL AND status = 'active'` gate; no separate task needed since the design doc confirmed this requires no special-casing.

**Issues found and fixed during self-review:**
- Task 5's original draft had `Ask2Flow` calling `client.from('ask2_state').update(...)` directly, but Task 3's migration only grants `SELECT` to `authenticated` (writes are meant to be service-role/RPC-only, per that migration's own comment). Fixed by adding `public.complete_ask2(uuid)` — a `SECURITY DEFINER`, membership-checked RPC — to Task 3, and updating Task 5 to call it instead of writing the table directly. Task 3's SQL test now covers both the member-succeeds and non-member-forbidden cases for this RPC.
- Task 6's first draft had the couples path call `_next()` (single increment) to skip the quiz — this is wrong because the switch dispatches on `_step`'s exact integer value matching the `quizStep`/`anchorsStep` constants, so a single increment lands ON `quizStep`, not past it. Caught this while drafting Task 6 itself (documented inline in that task's Step 3) and replaced it with `_skipToTerminalForCouples()`, which jumps `_step` to `anchorsStep + 1` in one `setState`.

**Known follow-up not covered by this plan** (explicitly out of scope per the design doc): the attachment quiz's instrument (wording/count/scale) remains the 26-question, 5-point version built earlier this session, pending the unresolved clinical decision in `ATTUNE_CLINICAL.md` §3.3/§12. `Ask2Flow` reuses it as-is.

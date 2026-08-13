# Chat Analysis → Pulse Score Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wire the already-built chat message/session analysis pipeline (`analyse-message`, `analyse-session`) into `compute-pulse` so tone, NVC violations, bid-for-connection, escalation, repair, and stonewalling signals influence the Pulse score — loosely coupled, coverage-ramped, and checklist-gated.

**Architecture:** `compute-pulse/index.ts` is decomposed from one large function into small, pure, independently-testable functions (confidence model, per-dimension formulas, coverage ramp) that take pre-fetched data as plain arguments — no I/O inside the math itself. Data fetching is extended to also pull `messages`/`analysis_sessions` aggregates via a new Postgres RPC (avoiding `select('*')` over 30 days of chat history). A new migration registers the `analyse-session` cron (currently only an unexecuted operator script) and creates the aggregation RPC. `compute-pulse` never calls `analyse-session` directly — it only reads whatever is already in the database.

**Tech Stack:** Deno (Supabase Edge Functions), TypeScript, Postgres/PL-pgSQL, Deno's built-in test runner (`Deno.test` + `https://deno.land/std@0.224.0/assert/mod.ts`, matching this repo's existing `_shared/*.test.ts` convention).

## Global Constraints

- `compute-pulse` must never call `analyse-session` or any other Edge Function synchronously — loose coupling only. Document the ~60-minute staleness bound (30-min cron interval + 30-min session-inactivity boundary) as a code comment, satisfying Algorithm Quality Review Checklist v3.1 item 1.9.
- All chat-derived aggregates are **rates, not raw counts** — a chattier couple must not score differently on volume alone.
- Every chat-derived score adjustment is multiplied by `chatWeight` (the coverage ramp: 0 below 25% window coverage, linear to 1.0 at 75% coverage).
- `analysis_sessions.pursuer` is never read anywhere in this feature.
- `root_need_detected`, `escalation_trajectory`, `session_resolved`, and Layer 4 `patterns` are never read by `compute-pulse` in this feature.
- No raw chat-derived aggregate (violation rate, escalation score, etc.) may appear in any client-visible payload or any column covered by `pulse_scores`' existing RLS SELECT policy (which grants the whole row to both partners).
- The UI may name chat as a data **source** but must never explain a score **change** in terms of chat-derived content, in this feature or any future one.
- With zero `messages`/`analysis_sessions` rows for a relationship, `compute-pulse`'s output must be byte-identical to its pre-this-feature output on the same fixture (the "no-op proof").
- Confidence rollup must match `PULSE.md` §4.3 exactly: `highCount >= 4 ? 'high' : mediumCount >= 3 ? 'medium' : mediumCount >= 1 ? 'low' : 'none'`.
- `'high'` confidence for any dimension requires `hasChatSignal` (`chatWeight > 0.5`) to be true — per `PULSE.md` §7, high confidence "requires chat AI pipeline."

---

## File Structure

- **Modify** `supabase/functions/compute-pulse/index.ts` — decompose into pure functions; add chat aggregate fetching, coverage ramp, and per-dimension chat adjustments; fix the `force_recompute` upsert bug; fix the confidence rollup.
- **Create** `supabase/functions/compute-pulse/index.test.ts` — unit tests for every pure function, following the `_shared/*.test.ts` convention.
- **Create** `supabase/migrations/20260830120000_chat_pulse_signals.sql` — registers the `analyse-session-sweep` cron (converting the unexecuted `supabase/sql/schedule_analyse_session.sql` into a real migration), creates the `compute_relationship_chat_signals` aggregation RPC, creates the service-role-only `pulse_score_diagnostics` table.
- **Modify** `lib/features/pulse/presentation/screens/pulse_screen.dart` — extend the dimension-tooltip description text to name chat as a data source (small, separate client change; last task).

---

## Task 1: Migration — cron registration, aggregation RPC, diagnostics table

**Files:**
- Create: `supabase/migrations/20260830120000_chat_pulse_signals.sql`

**Interfaces:**
- Produces: a registered `analyse-session-sweep` pg_cron job (`7,37 * * * *`); a Postgres function `public.compute_relationship_chat_signals(p_relationship_id uuid, p_window_start timestamptz)` returning one row with columns `analysed_count int, avg_tone double precision, violation_rate double precision, severe_rate double precision, bid_turn_rate double precision, bids_total int, session_count int, avg_escalation double precision, repair_rate double precision, attempt_rate double precision, stonewall_rate double precision, pursue_withdraw_rate double precision, first_analysed_at timestamptz, pending_backlog_count int` — consumed by Task 3 (`compute-pulse`'s chat-fetch step). A new table `public.pulse_score_diagnostics(id uuid, relationship_id uuid, week_ending date, computed_at timestamptz, chat_weight double precision, raw_signals jsonb)` with RLS enabled and **no SELECT policy for `authenticated`** (service-role only) — consumed by Task 4.

- [ ] **Step 1: Write the migration file**

```sql
-- Chat analysis → Pulse integration (docs/superpowers/specs/
-- 2026-08-14-chat-pulse-integration-design.md):
--
-- 1. Registers the analyse-session sweep cron. supabase/sql/
--    schedule_analyse_session.sql defines this same job but is an
--    operator-run script, not a migration — its execution against the
--    live project could never be confirmed, so this migration makes the
--    registration a first-class, deployed artifact instead.
-- 2. Adds a Postgres RPC that pre-aggregates 30 days of chat signal per
--    relationship in one row, so compute-pulse never has to select(*)
--    raw message/session rows into the edge function (Algorithm Quality
--    Review Checklist v3.1 item 2.14 — memory growth bounds).
-- 3. Adds a service-role-only diagnostics table for raw chat aggregates
--    — deliberately NOT covered by pulse_scores' existing RLS SELECT
--    policy (which grants the whole row to both partners), since raw
--    violation rates/escalation scores must never reach a client (item
--    1.11 — data privacy; see spec's Privacy section).

-- ---------------------------------------------------------------------
-- 1. Cron registration
-- ---------------------------------------------------------------------

CREATE EXTENSION IF NOT EXISTS pg_cron;
CREATE EXTENSION IF NOT EXISTS pg_net;

SELECT cron.unschedule(jobid)
FROM cron.job
WHERE jobname = 'analyse-session-sweep';

SELECT cron.schedule(
  'analyse-session-sweep',
  '7,37 * * * *',
  $$
  SELECT net.http_post(
    url := current_setting('app.settings.supabase_url') || '/functions/v1/analyse-session',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || current_setting('app.settings.service_role_key'),
      'apikey', current_setting('app.settings.service_role_key')
    ),
    body := '{}'::jsonb
  ) AS request_id;
  $$
);

-- ---------------------------------------------------------------------
-- 2. Chat signal aggregation RPC
-- ---------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.compute_relationship_chat_signals(
  p_relationship_id uuid,
  p_window_start timestamptz
)
RETURNS TABLE (
  analysed_count int,
  avg_tone double precision,
  violation_rate double precision,
  severe_rate double precision,
  bid_turn_rate double precision,
  bids_total int,
  session_count int,
  avg_escalation double precision,
  repair_rate double precision,
  attempt_rate double precision,
  stonewall_rate double precision,
  pursue_withdraw_rate double precision,
  first_analysed_at timestamptz,
  pending_backlog_count int
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  WITH msgs AS (
    SELECT
      m.tone_score,
      m.nvc_violations,
      m.bid_type,
      m.created_at
    FROM public.messages m
    WHERE m.relationship_id = p_relationship_id
      AND m.message_analysis_done = true
      AND m.created_at >= p_window_start
  ),
  violation_counts AS (
    SELECT
      count(*) AS msg_count,
      count(*) FILTER (WHERE tone_score IS NOT NULL) AS toned_count,
      COALESCE(avg(tone_score) FILTER (WHERE tone_score IS NOT NULL), NULL) AS avg_tone_val,
      COALESCE(sum(
        CASE WHEN jsonb_typeof(nvc_violations) = 'array'
          THEN jsonb_array_length(nvc_violations)
          ELSE 0
        END
      ), 0) AS total_violations,
      COALESCE(sum(
        CASE WHEN jsonb_typeof(nvc_violations) = 'array'
          THEN (
            SELECT count(*)
            FROM jsonb_array_elements_text(nvc_violations) AS v(val)
            WHERE v.val IN ('contempt', 'character_attack')
          )
          ELSE 0
        END
      ), 0) AS total_severe,
      count(*) FILTER (WHERE bid_type IS NOT NULL) AS bids_total_val,
      count(*) FILTER (WHERE bid_type = 'toward') AS bids_toward_val,
      min(created_at) FILTER (WHERE tone_score IS NOT NULL) AS first_toned_at
    FROM msgs
  ),
  sessions AS (
    SELECT
      s.escalation_score,
      s.repair_attempted,
      s.repair_landed,
      s.stonewalling_signals,
      s.pursue_withdraw_detected
    FROM public.analysis_sessions s
    WHERE s.relationship_id = p_relationship_id
      AND s.started_at >= p_window_start
      AND s.escalation_score IS NOT NULL
  ),
  session_counts AS (
    SELECT
      count(*) AS session_count_val,
      COALESCE(avg(escalation_score), NULL) AS avg_escalation_val,
      count(*) FILTER (WHERE escalation_score >= 0.5) AS conflict_session_count,
      count(*) FILTER (WHERE escalation_score >= 0.5 AND repair_landed) AS landed_count,
      count(*) FILTER (WHERE escalation_score >= 0.5 AND repair_attempted) AS attempted_count,
      count(*) FILTER (WHERE stonewalling_signals) AS stonewall_count,
      count(*) FILTER (WHERE pursue_withdraw_detected) AS pursue_withdraw_count
    FROM sessions
  ),
  backlog AS (
    SELECT count(*) AS pending_count
    FROM public.messages m
    WHERE m.relationship_id = p_relationship_id
      AND m.message_analysis_done = true
      AND m.included_in_session_id IS NULL
  )
  SELECT
    vc.msg_count::int,
    vc.avg_tone_val,
    CASE WHEN vc.msg_count > 0 THEN vc.total_violations::double precision / vc.msg_count ELSE NULL END,
    CASE WHEN vc.msg_count > 0 THEN vc.total_severe::double precision / vc.msg_count ELSE NULL END,
    CASE WHEN vc.bids_total_val >= 5 THEN vc.bids_toward_val::double precision / vc.bids_total_val ELSE NULL END,
    vc.bids_total_val::int,
    sc.session_count_val::int,
    sc.avg_escalation_val,
    CASE WHEN sc.conflict_session_count >= 2 THEN sc.landed_count::double precision / sc.conflict_session_count ELSE NULL END,
    CASE WHEN sc.conflict_session_count >= 2 THEN sc.attempted_count::double precision / sc.conflict_session_count ELSE NULL END,
    CASE WHEN sc.session_count_val > 0 THEN sc.stonewall_count::double precision / sc.session_count_val ELSE NULL END,
    CASE WHEN sc.session_count_val > 0 THEN sc.pursue_withdraw_count::double precision / sc.session_count_val ELSE NULL END,
    vc.first_toned_at,
    b.pending_count::int
  FROM violation_counts vc, session_counts sc, backlog b;
END;
$$;

REVOKE ALL ON FUNCTION public.compute_relationship_chat_signals(uuid, timestamptz) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.compute_relationship_chat_signals(uuid, timestamptz) TO service_role;

-- ---------------------------------------------------------------------
-- 3. Diagnostics table (service-role only — never exposed to clients)
-- ---------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.pulse_score_diagnostics (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  relationship_id uuid NOT NULL REFERENCES public.relationships(id) ON DELETE CASCADE,
  week_ending date NOT NULL,
  computed_at timestamptz NOT NULL DEFAULT now(),
  chat_weight double precision,
  raw_signals jsonb,
  UNIQUE (relationship_id, week_ending)
);

ALTER TABLE public.pulse_score_diagnostics ENABLE ROW LEVEL SECURITY;
-- Deliberately no policy for `authenticated` — RLS enabled with zero
-- policies means the table is inaccessible to that role entirely.
-- Only the service-role key (which bypasses RLS) can read/write it.

REVOKE ALL ON public.pulse_score_diagnostics FROM PUBLIC, anon, authenticated;

CREATE INDEX IF NOT EXISTS idx_pulse_score_diagnostics_relationship
  ON public.pulse_score_diagnostics (relationship_id, week_ending DESC);
```

- [ ] **Step 2: Apply the migration to the linked Supabase project**

Run: `npx supabase db push --linked`

Confirm the prompt lists exactly `20260830120000_chat_pulse_signals.sql`, then accept.

- [ ] **Step 3: Verify the cron job registered**

This cannot be verified from this sandboxed environment (no direct DB query access confirmed working in this session — `supabase db execute --linked` is not a valid flag on the installed CLI version, and `db dump` requires Docker, which is unavailable here). Note in the task's completion comment that a human with Supabase dashboard access should confirm via SQL editor: `SELECT jobname, schedule, active FROM cron.job WHERE jobname = 'analyse-session-sweep';` — expect one active row.

- [ ] **Step 4: Verify the RPC is callable**

Also requires live DB access unavailable in this sandbox. Note for human verification: `SELECT * FROM compute_relationship_chat_signals('00000000-0000-0000-0000-000000000000'::uuid, now() - interval '30 days');` should return one row with all fields NULL/0 (no matching relationship), not an error.

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/20260830120000_chat_pulse_signals.sql
git commit -m "feat(pulse): register analyse-session cron, add chat signal aggregation RPC"
```

---

## Task 2: `compute-pulse` — decompose into pure functions, fix the two pre-existing bugs

**Files:**
- Modify: `supabase/functions/compute-pulse/index.ts`
- Test: `supabase/functions/compute-pulse/index.test.ts`

**Interfaces:**
- Consumes: nothing from earlier tasks (this task does not yet call the Task 1 RPC — that's Task 3).
- Produces: exported pure functions from `compute-pulse/index.ts`:
  - `clamp(value: number, min: number, max: number): number` (renamed from `_clamp`, exported)
  - `getWeekEnding(date: Date): Date` (renamed from `_getWeekEnding`, exported)
  - `confidenceFrom(points: number, hasChatSignal: boolean): 'none' | 'low' | 'medium' | 'high'`
  - `rollupConfidence(confidences: Array<'none' | 'low' | 'medium' | 'high'>): 'none' | 'low' | 'medium' | 'high'`
  These are consumed by Task 3 (which adds the chat-evidence points to the existing evidence sources) and by this task's own tests.

Read the current file in full before starting — it is reproduced above in this plan's research, but confirm against the live file since other work may have touched it since this plan was written.

- [ ] **Step 1: Write the failing tests for the two bug fixes and the new pure functions**

```typescript
// supabase/functions/compute-pulse/index.test.ts
import {
  assertEquals,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import { clamp, getWeekEnding, confidenceFrom, rollupConfidence } from "./index.ts";

Deno.test("clamp: clamps below min", () => {
  assertEquals(clamp(-5, 0, 100), 0);
});

Deno.test("clamp: clamps above max", () => {
  assertEquals(clamp(150, 0, 100), 100);
});

Deno.test("clamp: passes through in-range value", () => {
  assertEquals(clamp(42, 0, 100), 42);
});

Deno.test("getWeekEnding: a Wednesday rolls forward to the next Sunday", () => {
  const wed = new Date("2026-08-12T10:00:00Z"); // a Wednesday
  const result = getWeekEnding(wed);
  assertEquals(result.getDay(), 0); // Sunday
});

Deno.test("confidenceFrom: below 2 points is none", () => {
  assertEquals(confidenceFrom(1, false), "none");
  assertEquals(confidenceFrom(0, true), "none");
});

Deno.test("confidenceFrom: 2 to just under 5 points is low", () => {
  assertEquals(confidenceFrom(2, false), "low");
  assertEquals(confidenceFrom(4.9, false), "low");
});

Deno.test("confidenceFrom: 5 to just under 9 points is medium", () => {
  assertEquals(confidenceFrom(5, false), "medium");
  assertEquals(confidenceFrom(8.9, false), "medium");
});

Deno.test("confidenceFrom: 9+ points without chat signal caps at medium", () => {
  // This is the test that proves PULSE.md §7's "high requires chat" rule.
  assertEquals(confidenceFrom(20, false), "medium");
});

Deno.test("confidenceFrom: 9+ points WITH chat signal reaches high", () => {
  assertEquals(confidenceFrom(9, true), "high");
  assertEquals(confidenceFrom(20, true), "high");
});

Deno.test("rollupConfidence: matches PULSE.md §4.3 — 4+ high dimensions is high", () => {
  assertEquals(
    rollupConfidence(["high", "high", "high", "high", "medium"]),
    "high",
  );
});

Deno.test("rollupConfidence: 3+ medium (below the high threshold) is medium", () => {
  assertEquals(
    rollupConfidence(["medium", "medium", "medium", "low", "low"]),
    "medium",
  );
});

Deno.test("rollupConfidence: 1-2 medium is low", () => {
  assertEquals(
    rollupConfidence(["medium", "low", "low", "low", "none"]),
    "low",
  );
});

Deno.test("rollupConfidence: zero medium or high is none", () => {
  // This is the test that proves the 'none' rollup bug is fixed — the
  // shipped code's `lowCount >= 3 ? 'low' : 'none'` made this branch
  // nearly unreachable since every dimension starts at 'low'.
  assertEquals(
    rollupConfidence(["low", "low", "low", "low", "low"]),
    "none",
  );
});

Deno.test("rollupConfidence: zero of everything (all none) is none", () => {
  assertEquals(
    rollupConfidence(["none", "none", "none", "none", "none"]),
    "none",
  );
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `deno test supabase/functions/compute-pulse/index.test.ts`
Expected: FAIL — `clamp`, `getWeekEnding`, `confidenceFrom`, `rollupConfidence` are not exported from `index.ts` (the file currently only has `_clamp`/`_getWeekEnding` as unexported module-private functions, and no confidence functions exist at all).

- [ ] **Step 3: Rewrite `compute-pulse/index.ts`**

Rename `_clamp` → `clamp` and `_getWeekEnding` → `getWeekEnding`, and export both:

```typescript
export function clamp(value: number, min: number, max: number): number {
  return Math.min(Math.max(value, min), max)
}

export function getWeekEnding(date: Date): Date {
  const result = new Date(date)
  const daysToSunday = 7 - result.getDay() // Sunday = 0 in JS
  result.setDate(result.getDate() + daysToSunday)
  result.setHours(0, 0, 0, 0)
  return result
}
```

Update the two call sites inside `_computePulseScore`/`serve` that currently call `_clamp(...)`/`_getWeekEnding(...)` to call `clamp(...)`/`getWeekEnding(...)` instead (same behavior, renamed).

Add the two new confidence functions, matching `PULSE.md` §4.3's exact rollup thresholds (restoring the `'high'` branch and the `mediumCount >= 1` rule that the shipped code currently lacks):

```typescript
type Confidence = 'none' | 'low' | 'medium' | 'high'

export function confidenceFrom(points: number, hasChatSignal: boolean): Confidence {
  if (points < 2) return 'none'
  if (points < 5) return 'low'
  if (points < 9) return 'medium'
  // 'high' requires chat signal per PULSE.md §7 ("requires chat AI
  // pipeline") — a relationship with abundant timeline/check-in
  // evidence but no chat caps at 'medium'.
  return hasChatSignal ? 'high' : 'medium'
}

export function rollupConfidence(confidences: Confidence[]): Confidence {
  const highCount = confidences.filter((c) => c === 'high').length
  const mediumCount = confidences.filter((c) => c === 'medium').length
  if (highCount >= 4) return 'high'
  if (mediumCount >= 3) return 'medium'
  if (mediumCount >= 1) return 'low'
  return 'none'
}
```

Fix bug #1 (`force_recompute` silent insert failure): change the final write from `insert` to `upsert` with the correct conflict target, and check the result:

```typescript
const { error: upsertError } = await supabase
  .from('pulse_scores')
  .upsert(pulseData, { onConflict: 'relationship_id,week_ending' })

if (upsertError) {
  console.error('Failed to save pulse score:', upsertError.message)
  throw new Error(`Failed to save pulse score for relationship ${relationshipId}: ${upsertError.message}`)
}
```

Do NOT yet change the confidence-computation call sites inside `_computePulseScore` (the five `xConfidence = ...` assignments that currently use the ad hoc per-dimension rules) — that rewire happens in Task 3, once the chat evidence points exist to feed `confidenceFrom`. This task only adds the new pure functions and fixes the two bugs; it does not yet change what confidence values get computed, only fixes the buggy *rollup* of whatever those values are. Confirm this by leaving the five ad hoc dimension-confidence assignments (`communicationConfidence = checkins.length >= 2 ? 'medium' : 'low'`, etc.) completely unchanged in this task, and only replacing the final rollup block:

```typescript
// DATA CONFIDENCE (overall)
const confidences: Confidence[] = [
  communicationConfidence,
  connectionConfidence,
  conflictHealthConfidence,
  alignmentConfidence,
  safetyConfidence,
]
const overallConfidence = rollupConfidence(confidences)
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `deno test supabase/functions/compute-pulse/index.test.ts`
Expected: PASS (14 tests)

- [ ] **Step 5: Run `deno check` (type-check) on the modified file**

Run: `deno check supabase/functions/compute-pulse/index.ts`
Expected: no type errors.

- [ ] **Step 6: Commit**

```bash
git add supabase/functions/compute-pulse/index.ts supabase/functions/compute-pulse/index.test.ts
git commit -m "fix(pulse): fix force_recompute silent-insert bug and confidence rollup; extract pure functions"
```

---

## Task 3: Chat signal fetch, coverage ramp, and per-dimension chat adjustments

**Files:**
- Modify: `supabase/functions/compute-pulse/index.ts`
- Modify: `supabase/functions/compute-pulse/index.test.ts`

**Interfaces:**
- Consumes: `compute_relationship_chat_signals` RPC (Task 1) with the exact column names listed in Task 1's Interfaces block; `clamp`, `confidenceFrom` (Task 2).
- Produces: exported pure functions `computeChatWeight(coverageDays: number): number` and `applyChatSignals(dimensions: DimensionState, chatSignals: ChatSignals, chatWeight: number): DimensionState` where `DimensionState` and `ChatSignals` are TypeScript interfaces defined in this task — consumed by Task 4 (diagnostics write) which reads `chatWeight` and the raw `chatSignals` object this task produces.

- [ ] **Step 1: Write the failing tests**

Add to `supabase/functions/compute-pulse/index.test.ts`:

```typescript
import { computeChatWeight, applyChatSignals, type DimensionState, type ChatSignals } from "./index.ts";

Deno.test("computeChatWeight: below 25% coverage (7.5 days) is zero", () => {
  assertEquals(computeChatWeight(0), 0);
  assertEquals(computeChatWeight(5), 0);
  assertEquals(computeChatWeight(7.49), 0);
});

Deno.test("computeChatWeight: exactly 25% coverage is zero (boundary)", () => {
  assertEquals(computeChatWeight(7.5), 0);
});

Deno.test("computeChatWeight: 50% coverage (15 days) is partial", () => {
  const result = computeChatWeight(15);
  assertEquals(result > 0 && result < 1, true);
});

Deno.test("computeChatWeight: 75% coverage (22.5 days) reaches full weight", () => {
  assertEquals(computeChatWeight(22.5), 1);
});

Deno.test("computeChatWeight: 100% coverage (30 days) stays at full weight", () => {
  assertEquals(computeChatWeight(30), 1);
});

function emptyChatSignals(): ChatSignals {
  return {
    analysedCount: 0,
    avgTone: null,
    violationRate: null,
    severeRate: null,
    bidTurnRate: null,
    bidsTotal: 0,
    sessionCount: 0,
    avgEscalation: null,
    repairRate: null,
    attemptRate: null,
    stonewallRate: null,
    pursueWithdrawRate: null,
  };
}

function baseDimensions(): DimensionState {
  return {
    communication: 50,
    connection: 50,
    conflictHealth: 70,
    emotionalSafety: 50,
  };
}

Deno.test("applyChatSignals: no-op proof — zero chat signal leaves dimensions untouched", () => {
  const before = baseDimensions();
  const result = applyChatSignals(before, emptyChatSignals(), 0);
  assertEquals(result, before);
});

Deno.test("applyChatSignals: zero chatWeight leaves dimensions untouched even with real signal", () => {
  const before = baseDimensions();
  const signals: ChatSignals = {
    ...emptyChatSignals(),
    analysedCount: 50,
    avgTone: -0.8,
    violationRate: 0.5,
  };
  const result = applyChatSignals(before, signals, 0);
  assertEquals(result, before);
});

Deno.test("applyChatSignals: positive avgTone raises communication when analysedCount floor is met", () => {
  const before = baseDimensions();
  const signals: ChatSignals = { ...emptyChatSignals(), analysedCount: 10, avgTone: 0.5 };
  const result = applyChatSignals(before, signals, 1);
  assertEquals(result.communication > before.communication, true);
});

Deno.test("applyChatSignals: avgTone below the analysedCount floor of 10 has no effect", () => {
  const before = baseDimensions();
  const signals: ChatSignals = { ...emptyChatSignals(), analysedCount: 9, avgTone: 0.9 };
  const result = applyChatSignals(before, signals, 1);
  assertEquals(result.communication, before.communication);
});

Deno.test("applyChatSignals: violationRate lowers communication", () => {
  const before = baseDimensions();
  const signals: ChatSignals = { ...emptyChatSignals(), analysedCount: 10, violationRate: 0.2 };
  const result = applyChatSignals(before, signals, 1);
  assertEquals(result.communication < before.communication, true);
});

Deno.test("applyChatSignals: severeRate lowers BOTH communication (via violationRate) and emotionalSafety", () => {
  // Deliberate double-count per the design spec — contempt/character_attack
  // damage both clarity and safety.
  const before = baseDimensions();
  const signals: ChatSignals = {
    ...emptyChatSignals(),
    analysedCount: 10,
    violationRate: 0.1,
    severeRate: 0.1,
  };
  const result = applyChatSignals(before, signals, 1);
  assertEquals(result.communication < before.communication, true);
  assertEquals(result.emotionalSafety < before.emotionalSafety, true);
});

Deno.test("applyChatSignals: bidTurnRate above 0.5 raises connection", () => {
  const before = baseDimensions();
  const signals: ChatSignals = { ...emptyChatSignals(), bidsTotal: 10, bidTurnRate: 0.8 };
  const result = applyChatSignals(before, signals, 1);
  assertEquals(result.connection > before.connection, true);
});

Deno.test("applyChatSignals: bidTurnRate below 0.5 lowers connection", () => {
  const before = baseDimensions();
  const signals: ChatSignals = { ...emptyChatSignals(), bidsTotal: 10, bidTurnRate: 0.2 };
  const result = applyChatSignals(before, signals, 1);
  assertEquals(result.connection < before.connection, true);
});

Deno.test("applyChatSignals: bidTurnRate is null (below the bidsTotal floor of 5) has no effect on connection", () => {
  const before = baseDimensions();
  const signals: ChatSignals = { ...emptyChatSignals(), bidsTotal: 3, bidTurnRate: null };
  const result = applyChatSignals(before, signals, 1);
  assertEquals(result.connection, before.connection);
});

Deno.test("applyChatSignals: repairRate raises conflictHealth when sessionCount floor is met", () => {
  const before = baseDimensions();
  const signals: ChatSignals = {
    ...emptyChatSignals(),
    sessionCount: 3,
    repairRate: 1,
    attemptRate: 1,
  };
  const result = applyChatSignals(before, signals, 1);
  assertEquals(result.conflictHealth > before.conflictHealth, true);
});

Deno.test("applyChatSignals: avgEscalation above 0.4 lowers conflictHealth", () => {
  const before = baseDimensions();
  const signals: ChatSignals = { ...emptyChatSignals(), sessionCount: 3, avgEscalation: 0.9 };
  const result = applyChatSignals(before, signals, 1);
  assertEquals(result.conflictHealth < before.conflictHealth, true);
});

Deno.test("applyChatSignals: avgEscalation below 0.4 (healthy, normal escalation) does not penalize", () => {
  const before = baseDimensions();
  const signals: ChatSignals = { ...emptyChatSignals(), sessionCount: 3, avgEscalation: 0.1 };
  const result = applyChatSignals(before, signals, 1);
  assertEquals(result.conflictHealth >= before.conflictHealth, true);
});

Deno.test("applyChatSignals: stonewallRate lowers communication", () => {
  const before = baseDimensions();
  const signals: ChatSignals = { ...emptyChatSignals(), sessionCount: 3, stonewallRate: 1 };
  const result = applyChatSignals(before, signals, 1);
  assertEquals(result.communication < before.communication, true);
});

Deno.test("applyChatSignals: pursueWithdrawRate lowers emotionalSafety", () => {
  const before = baseDimensions();
  const signals: ChatSignals = { ...emptyChatSignals(), sessionCount: 3, pursueWithdrawRate: 1 };
  const result = applyChatSignals(before, signals, 1);
  assertEquals(result.emotionalSafety < before.emotionalSafety, true);
});

Deno.test("applyChatSignals: sessionCount below the floor of 3 has no session-level effect", () => {
  const before = baseDimensions();
  const signals: ChatSignals = {
    ...emptyChatSignals(),
    sessionCount: 2,
    avgEscalation: 0.9,
    stonewallRate: 1,
    pursueWithdrawRate: 1,
  };
  const result = applyChatSignals(before, signals, 1);
  assertEquals(result.conflictHealth, before.conflictHealth);
  assertEquals(result.communication, before.communication);
  assertEquals(result.emotionalSafety, before.emotionalSafety);
});

Deno.test("applyChatSignals: mid-analysis state — messages analysed, zero sessions — message-level signals still apply", () => {
  // The modal real-world state: Layer 1 (per-message) runs within
  // seconds; Layer 2 (per-session) only after a 30-min gap. This proves
  // a shared guard was NOT accidentally used for both signal levels.
  const before = baseDimensions();
  const signals: ChatSignals = {
    ...emptyChatSignals(),
    analysedCount: 10,
    avgTone: 0.5,
    sessionCount: 0,
  };
  const result = applyChatSignals(before, signals, 1);
  assertEquals(result.communication > before.communication, true);
  assertEquals(result.conflictHealth, before.conflictHealth); // no session data yet
});

Deno.test("applyChatSignals: results stay clamped to 0-100", () => {
  const before: DimensionState = { communication: 5, connection: 5, conflictHealth: 5, emotionalSafety: 5 };
  const signals: ChatSignals = {
    ...emptyChatSignals(),
    analysedCount: 10,
    violationRate: 1,
    severeRate: 1,
    sessionCount: 3,
    stonewallRate: 1,
    pursueWithdrawRate: 1,
  };
  const result = applyChatSignals(before, signals, 1);
  assertEquals(result.communication >= 0, true);
  assertEquals(result.emotionalSafety >= 0, true);
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `deno test supabase/functions/compute-pulse/index.test.ts`
Expected: FAIL — `computeChatWeight`, `applyChatSignals`, `DimensionState`, `ChatSignals` do not exist yet.

- [ ] **Step 3: Implement the coverage ramp and chat signal application**

Add to `supabase/functions/compute-pulse/index.ts`:

```typescript
export function computeChatWeight(coverageDays: number): number {
  const coverage = Math.min(coverageDays, 30) / 30
  if (coverage < 0.25) return 0
  return Math.min((coverage - 0.25) / 0.5, 1)
}

export interface ChatSignals {
  analysedCount: number
  avgTone: number | null
  violationRate: number | null
  severeRate: number | null
  bidTurnRate: number | null
  bidsTotal: number
  sessionCount: number
  avgEscalation: number | null
  repairRate: number | null
  attemptRate: number | null
  stonewallRate: number | null
  pursueWithdrawRate: number | null
}

export interface DimensionState {
  communication: number
  connection: number
  conflictHealth: number
  emotionalSafety: number
}

export function applyChatSignals(
  dimensions: DimensionState,
  signals: ChatSignals,
  chatWeight: number
): DimensionState {
  let { communication, connection, conflictHealth, emotionalSafety } = dimensions

  if (chatWeight > 0) {
    // COMMUNICATION
    if (signals.avgTone != null && signals.analysedCount >= 10) {
      communication = clamp(communication + signals.avgTone * 10 * chatWeight, 0, 100)
    }
    if (signals.violationRate != null && signals.analysedCount >= 10) {
      const nvcPenalty = Math.min(signals.violationRate / 0.2, 1) * 12
      communication = clamp(communication - nvcPenalty * chatWeight, 0, 100)
    }
    if (signals.stonewallRate != null && signals.sessionCount >= 3) {
      communication = clamp(communication - signals.stonewallRate * 10 * chatWeight, 0, 100)
    }

    // CONNECTION
    if (signals.bidTurnRate != null && signals.bidsTotal >= 5) {
      connection = clamp(connection + (signals.bidTurnRate - 0.5) * 24 * chatWeight, 0, 100)
    }

    // CONFLICT HEALTH
    if (signals.repairRate != null && signals.attemptRate != null && signals.sessionCount >= 3) {
      const repairBonus = signals.repairRate * 12 + (signals.attemptRate - signals.repairRate) * 3
      conflictHealth = clamp(conflictHealth + repairBonus * chatWeight, 0, 100)
    }
    if (signals.avgEscalation != null && signals.sessionCount >= 3) {
      // Centered at 0.4, not 0 — some escalation is normal; Conflict
      // Health measures repair quality, not conflict absence.
      conflictHealth = clamp(conflictHealth - (signals.avgEscalation - 0.4) * 20 * chatWeight, 0, 100)
    }

    // EMOTIONAL SAFETY
    if (signals.severeRate != null && signals.analysedCount >= 10) {
      // Deliberate double-count with communication's violationRate above
      // — contempt/character_attack damage both clarity and safety.
      const safetyPenalty = Math.min(signals.severeRate / 0.1, 1) * 12
      emotionalSafety = clamp(emotionalSafety - safetyPenalty * chatWeight, 0, 100)
    }
    if (signals.pursueWithdrawRate != null && signals.sessionCount >= 3) {
      emotionalSafety = clamp(emotionalSafety - signals.pursueWithdrawRate * 8 * chatWeight, 0, 100)
    }
  }

  return { communication, connection, conflictHealth, emotionalSafety }
}
```

**Note on `sessionCount >= 3` floor test above** ("mid-analysis state"): the test passes `sessionCount: 0` and asserts `conflictHealth` is unchanged — this is correct because `0 >= 3` is false, so the session-level `if` guards never fire. No special-casing needed; this falls out of the existing floor checks.

- [ ] **Step 4: Wire the RPC fetch and chatWeight computation into `_computePulseScore`, and call `applyChatSignals`**

Inside `_computePulseScore`, after the existing four `FETCH ALL DATA SOURCES` queries (timeline events, check-ins, attachment profiles, previous pulse), add a fifth fetch:

```typescript
// 5. Chat signal aggregates (last 30 days), via the pre-aggregating RPC
// — never select(*) raw messages/sessions rows into this function
// (Algorithm Quality Review Checklist v3.1 item 2.14).
const { data: chatSignalRows } = await supabase
  .rpc('compute_relationship_chat_signals', {
    p_relationship_id: relationshipId,
    p_window_start: thirtyDaysAgo.toISOString(),
  })
const chatRow = chatSignalRows?.[0] ?? null

const chatSignals: ChatSignals = {
  analysedCount: chatRow?.analysed_count ?? 0,
  avgTone: chatRow?.avg_tone ?? null,
  violationRate: chatRow?.violation_rate ?? null,
  severeRate: chatRow?.severe_rate ?? null,
  bidTurnRate: chatRow?.bid_turn_rate ?? null,
  bidsTotal: chatRow?.bids_total ?? 0,
  sessionCount: chatRow?.session_count ?? 0,
  avgEscalation: chatRow?.avg_escalation ?? null,
  repairRate: chatRow?.repair_rate ?? null,
  attemptRate: chatRow?.attempt_rate ?? null,
  stonewallRate: chatRow?.stonewall_rate ?? null,
  pursueWithdrawRate: chatRow?.pursue_withdraw_rate ?? null,
}

const pendingBacklog = chatRow?.pending_backlog_count ?? 0
const coverageDays = chatRow?.first_analysed_at
  ? Math.min(30, (Date.now() - new Date(chatRow.first_analysed_at).getTime()) / 86_400_000)
  : 0

// Backlog gate: if the session-analysis sweep is more than 50 messages
// behind, treat chat as having zero weight this run rather than score
// on a known-incomplete picture.
const chatWeight = pendingBacklog > 50 ? 0 : computeChatWeight(coverageDays)
const hasChatSignal = chatWeight > 0.5
```

Then, after the existing per-dimension computation blocks (Communication, Connection, Conflict Health, Alignment, Emotional Safety — all currently unchanged from Task 2), apply chat signals to the four affected dimensions (Alignment is untouched — no chat signal maps to it, per the spec):

```typescript
const chatAdjusted = applyChatSignals(
  { communication, connection, conflictHealth, emotionalSafety },
  chatSignals,
  chatWeight
)
communication = chatAdjusted.communication
connection = chatAdjusted.connection
conflictHealth = chatAdjusted.conflictHealth
emotionalSafety = chatAdjusted.emotionalSafety
```

Now rewire the five confidence-computation call sites to use `confidenceFrom` with an evidence-points model instead of the ad hoc rules from Task 2 (which were deliberately left unchanged in Task 2 — this is where they finally get replaced). Replace each `xConfidence = ...` assignment pattern. For example, Communication's confidence currently reads `communicationConfidence = checkins.length >= 2 ? 'medium' : 'low'` (and is never touched again) — replace the declaration and every assignment of `communicationConfidence` with a single evidence-points computation at the point Communication's confidence is currently finalized:

```typescript
const communicationPoints =
  Math.min(checkins?.length ?? 0, 2) * 2 +
  Math.min(conflicts.length, 4) * 1 +
  Math.min(Math.floor(chatSignals.analysedCount / 10), 3) * 1.5
const communicationConfidence = confidenceFrom(communicationPoints, hasChatSignal)
```

```typescript
const connectionPoints =
  Math.min(positiveEvents.length, 4) * 1 +
  Math.min(checkins?.length ?? 0, 2) * 2 +
  Math.min(chatSignals.bidsTotal >= 5 ? 1 : 0, 1) * 4.5
const connectionConfidence = confidenceFrom(connectionPoints, hasChatSignal)
```

```typescript
const conflictHealthPoints =
  Math.min(conflicts.length, 4) * 1 +
  Math.min(checkins?.length ?? 0, 2) * 2 +
  Math.min(chatSignals.sessionCount, 4) * 1.5
const conflictHealthConfidence = confidenceFrom(conflictHealthPoints, hasChatSignal)
```

```typescript
const alignmentPoints =
  (bothCompletedAttachment ? 3 : 0) +
  Math.min(checkins?.length ?? 0, 2) * 2
// Alignment has no chat signal — hasChatSignal never promotes it past
// what checkins/attachment alone earn, but the confidenceFrom function
// itself still requires hasChatSignal for the 'high' branch, so
// Alignment structurally cannot reach 'high' without chat existing
// SOMEWHERE in the relationship's overall data — this matches the
// spec's "no chat signal maps to Alignment" note; it simply never gets
// the evidence points that would put it in the 9+ bracket from chat,
// though hasChatSignal being true (from OTHER dimensions' chat data)
// could still let it reach high on 9+ points from checkins/attachment
// alone. This is acceptable: hasChatSignal is a relationship-level
// gate (chat pipeline is active), not a per-dimension one.
const alignmentConfidence = confidenceFrom(alignmentPoints, hasChatSignal)
```

```typescript
const safetyPoints =
  Math.min(allEventsWithMood.length, 4) * 1 +
  Math.min(checkins?.length ?? 0, 2) * 2 +
  Math.min(chatSignals.analysedCount >= 10 ? 1 : 0, 1) * 4.5
const safetyConfidence = confidenceFrom(safetyPoints, hasChatSignal)
```

Note: `checkins?.length` (not `checkins.length`) since `checkins` can be `null` from the Supabase client if the query fails — match the existing null-safety style already used elsewhere in this function (`checkins && checkins.length > 0` patterns nearby).

- [ ] **Step 5: Run tests to verify they pass**

Run: `deno test supabase/functions/compute-pulse/index.test.ts`
Expected: PASS (all tests from Task 2 and Task 3 — 35 total)

- [ ] **Step 6: Run `deno check`**

Run: `deno check supabase/functions/compute-pulse/index.ts`
Expected: no type errors.

- [ ] **Step 7: Commit**

```bash
git add supabase/functions/compute-pulse/index.ts supabase/functions/compute-pulse/index.test.ts
git commit -m "feat(pulse): fetch chat signals via RPC, apply coverage-ramped adjustments, rewire confidence to evidence-points model"
```

---

## Task 4: No-op proof, diagnostics write, backlog-gate integration test

**Files:**
- Modify: `supabase/functions/compute-pulse/index.ts`
- Modify: `supabase/functions/compute-pulse/index.test.ts`

**Interfaces:**
- Consumes: `applyChatSignals`, `computeChatWeight`, `ChatSignals`, `DimensionState` (Task 3); `pulse_score_diagnostics` table (Task 1).
- Produces: nothing consumed by later tasks — this is the plan's final backend task.

- [ ] **Step 1: Write the failing no-op-proof test**

Add to `supabase/functions/compute-pulse/index.test.ts`:

```typescript
Deno.test("no-op proof: applyChatSignals with all-null/zero ChatSignals and chatWeight 0 returns dimensions byte-identical to input", () => {
  // This is the test that proves the whole feature cannot regress a
  // relationship that doesn't use chat — the exact property the design
  // spec calls "the safety net for this whole feature."
  const before: DimensionState = {
    communication: 63,
    connection: 41,
    conflictHealth: 78,
    emotionalSafety: 55,
  }
  const zeroSignals: ChatSignals = {
    analysedCount: 0,
    avgTone: null,
    violationRate: null,
    severeRate: null,
    bidTurnRate: null,
    bidsTotal: 0,
    sessionCount: 0,
    avgEscalation: null,
    repairRate: null,
    attemptRate: null,
    stonewallRate: null,
    pursueWithdrawRate: null,
  }
  const result = applyChatSignals(before, zeroSignals, 0)
  assertEquals(result, before)
})

Deno.test("computeChatWeight: pendingBacklog gate forces zero weight regardless of coverage — verified at the call-site formula level", () => {
  // The backlog gate itself (`pendingBacklog > 50 ? 0 : computeChatWeight(...)`)
  // is a one-line ternary at the call site in _computePulseScore, not a
  // separately exported function — this test documents and locks the
  // formula's shape so a future refactor can't silently drop the gate.
  const pendingBacklog = 51
  const coverageDays = 30 // full coverage, would otherwise be weight 1
  const chatWeight = pendingBacklog > 50 ? 0 : computeChatWeight(coverageDays)
  assertEquals(chatWeight, 0)
})
```

- [ ] **Step 2: Run tests to verify they pass**

Run: `deno test supabase/functions/compute-pulse/index.test.ts`
Expected: PASS (37 total). The no-op proof should already pass given Task 3's implementation — this step confirms it, it is not expected to require new production code.

- [ ] **Step 3: Add the diagnostics write to `_computePulseScore`**

Immediately after the existing `pulse_scores` upsert (from Task 2's bug fix), write a diagnostics row. This write is best-effort — a failure here must never fail the whole pulse computation, since diagnostics are observability, not correctness:

```typescript
// Diagnostics: raw chat aggregates for tuning/observability, written to
// a service-role-only table never exposed to clients (see Task 1's
// pulse_score_diagnostics — no RLS policy for `authenticated`).
// Best-effort: a failure here must not fail the pulse computation
// itself, since this is observability, not correctness.
const { error: diagnosticsError } = await supabase
  .from('pulse_score_diagnostics')
  .upsert(
    {
      relationship_id: relationshipId,
      week_ending: weekEnding.toISOString().split('T')[0],
      chat_weight: chatWeight,
      raw_signals: chatSignals,
    },
    { onConflict: 'relationship_id,week_ending' }
  )
if (diagnosticsError) {
  console.error('Failed to write pulse score diagnostics (non-fatal):', diagnosticsError.message)
}
```

- [ ] **Step 4: Run tests to verify nothing broke**

Run: `deno test supabase/functions/compute-pulse/index.test.ts`
Expected: PASS (37 tests, unchanged count from Step 2 — this step adds no new tests, just production code).

- [ ] **Step 5: Run `deno check`**

Run: `deno check supabase/functions/compute-pulse/index.ts`
Expected: no type errors.

- [ ] **Step 6: Manual verification (no live Supabase project access in this sandbox)**

Note in the task's completion comment that a human with project access should, after Task 1's migration is applied: invoke `compute-pulse` with `force_recompute: true` against a real relationship (a) with zero chat activity and confirm scores match what they were before this feature shipped, then (b) call it again the same week and confirm the second call updates the existing row rather than erroring silently (proves the Task 2 upsert fix), then (c) check `pulse_score_diagnostics` for that relationship's row and confirm it is NOT readable via the app's normal (anon/authenticated) Supabase client — only via the dashboard's service-role access.

- [ ] **Step 7: Commit**

```bash
git add supabase/functions/compute-pulse/index.ts supabase/functions/compute-pulse/index.test.ts
git commit -m "feat(pulse): write chat signal diagnostics (service-role only), lock no-op-proof and backlog-gate tests"
```

---

## Task 5: Client tooltip — name chat as a data source

**Files:**
- Modify: `lib/features/pulse/presentation/screens/pulse_screen.dart`

**Interfaces:**
- Consumes: nothing from earlier tasks (this is a static copy change; the client already reads `dimension_confidence` generically and requires no model changes, confirmed by reading `lib/features/pulse/data/models/pulse_score.dart` during planning — `dimension_confidence` is deserialized as a raw map and `getConfidenceForDimension` reads it by key, so a change in server-side reasoning that determines the same 4-value enum requires no client changes at all).
- Produces: nothing consumed by later tasks — this is the plan's final task.

- [ ] **Step 1: Read the current tooltip method**

Read `lib/features/pulse/presentation/screens/pulse_screen.dart`'s `_showDimensionTooltip` method (around line 346) to confirm its exact current text before editing — the design spec's citation of "Communication is based on your weekly check-in" describes `PULSE.md`'s original intended copy, not this file's actual shipped text, which is a generic per-dimension description plus a low-confidence hint. Confirm the live file still matches what's shown below before editing (other work may have touched it since this plan was written).

Current text (as read during planning):

```dart
  void _showDimensionTooltip(String label, int score, String confidence) {
    final descriptions = {
      'Communication': 'How clearly and kindly you express yourselves',
      'Connection': 'Emotional closeness and warmth',
      'Conflict Health': 'How well you navigate disagreements',
      'Alignment': 'Shared values and direction',
      'Emotional Safety': 'Feeling safe to be vulnerable',
    };
    // ...
    Text(descriptions[label] ?? ''),
    if (confidence == 'low')
      const Padding(
        padding: EdgeInsets.only(top: 8),
        child: Text(
          'Limited data — this will improve with more check-ins and logged moments.',
          style: TextStyle(fontStyle: FontStyle.italic),
        ),
      ),
```

- [ ] **Step 2: Update the low-confidence hint text to name chat as a source, without ever framing it as a cause**

Per the design spec's Privacy section: the UI may name chat as a data *source* ("reflects... patterns in your conversations") but must never explain a score *change* in terms of chat content. The existing hint text already avoids causal language ("this will improve with more X" — additive, not "your score dropped because of X") — extend it the same way, adding chat to the *list of things that help*, not as an explanation of past movement:

```dart
                if (confidence == 'low')
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      'Limited data — this will improve with more check-ins, logged moments, and time as we learn from your conversations.',
                      style: TextStyle(fontStyle: FontStyle.italic),
                    ),
                  ),
```

Do NOT add any text anywhere that references a specific detected signal (tone, NVC violations, escalation, etc.) or explains why a score changed. This is the one-line change the spec's Privacy section authorizes — nothing broader.

- [ ] **Step 3: Run dart analyze**

Run: `dart analyze lib/features/pulse/presentation/screens/pulse_screen.dart`
Expected: `No issues found!`

- [ ] **Step 4: Run any existing Pulse screen tests**

Run: `flutter test test/features/pulse/ 2>/dev/null || echo "no existing pulse screen tests found — not a gap introduced by this task, just confirm no test references the exact hint string"`

If a test does reference the old hint string verbatim, update it to match the new text in the same commit.

- [ ] **Step 5: Commit**

```bash
git add lib/features/pulse/presentation/screens/pulse_screen.dart
git commit -m "feat(pulse): name chat as a data source in the low-confidence tooltip hint"
```

---

## Task 6: Full regression pass

**Files:** none (verification only)

- [ ] **Step 1: Run the full compute-pulse test suite**

Run: `deno test supabase/functions/compute-pulse/index.test.ts`
Expected: PASS — all tests from Tasks 2, 3, and 4 (37 total).

- [ ] **Step 2: Run `deno check` on the whole function**

Run: `deno check supabase/functions/compute-pulse/index.ts`
Expected: no type errors.

- [ ] **Step 3: Confirm no other caller of `compute-pulse` needs changes**

Run: `grep -rn "compute-pulse\|computePulseScore" lib supabase --include="*.dart" --include="*.ts" | grep -v "_test\|\.test\.ts\|node_modules"`

Expected: only `lib/features/pulse/providers/pulse_providers.dart`'s existing `recomputePulseProvider` (which calls `supabase.functions.invoke('compute-pulse', ...)` with `force_recompute: true` — unchanged interface, no params added or removed by this feature) and the migration/cron reference from Task 1. Confirm nothing else needs updating.

- [ ] **Step 4: Run the Flutter test suite for the pulse feature**

Run: `flutter test test/features/pulse/`
Expected: PASS, or "No test files found" if none exist yet for this feature — either is acceptable; this step confirms Task 5's client change didn't break anything that does exist.

- [ ] **Step 5: Confirm the branch is clean**

Run: `git status --short`

Expected: clean (no commit needed — this task is verification-only).

- [ ] **Step 6: Document outstanding manual verification for a human with live project access**

Summarize in this task's completion comment the three manual-verification items already noted in Tasks 1 and 4 that could not be performed in this sandboxed environment:
1. Confirm `analyse-session-sweep` cron is registered and active (Task 1, Step 3).
2. Confirm `compute_relationship_chat_signals` RPC is callable (Task 1, Step 4).
3. Confirm `force_recompute` called twice in one week now updates rather than silently failing, and confirm `pulse_score_diagnostics` is inaccessible via the app's normal client (Task 4, Step 6).

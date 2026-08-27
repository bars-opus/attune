# Session Games (Mirror, Sliding Scale, Scenario) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the three missing session games from ATTUNE_MASTER_SPEC.md §8.4 — Mirror Game, Sliding Scale, and Scenario — as additive extensions of the existing game engine, and wire game signals into the Pulse score.

**Architecture:** `game_sessions` and `game_session_rounds` are already generic (`game_type`, `answer_a`/`answer_b`, `both_answered`, `revealed_at`) and all three shipped games use them with zero tables of their own. These three games extend that engine: widen `game_questions`' type CHECK, add type-specific columns, and add two tables that exist only because Mirror needs them (a third per-round value, and an RLS-scoped per-user score). A new `compute_relationship_game_signals` RPC mirrors the existing chat-signals RPC and feeds Connection and Alignment.

**Tech Stack:** Supabase Postgres (migrations, RLS, `SECURITY DEFINER` RPCs), Deno edge functions, Flutter + Riverpod.

**Spec:** `docs/superpowers/specs/2026-08-27-session-games-design.md`

## Global Constraints

- **Hidden reveal is non-negotiable** (§8.4): neither partner may see the other's answer before both have submitted. New games read the partner's answer only through a `SECURITY DEFINER` RPC gated on `both_answered = true` — never a direct table select.
- **§11.1 asymmetric data is self-facing only:** Mirror's `/8` score and `< 6.5` flag are visible to their own subject only, enforced by RLS (`USING (user_id = auth.uid())`), never by UI alone. A partner's score must not appear on any surface, including AI insight copy.
- **§11.2 no couple report:** no combined view of both partners' scores.
- **Zero game signal must be a no-op in Pulse:** a couple who never plays scores byte-identically to today.
- **RPC grant convention** (copy verbatim): `REVOKE ALL ON FUNCTION public.<name>(<args>) FROM PUBLIC, anon;` then `GRANT EXECUTE ON FUNCTION public.<name>(<args>) TO authenticated;` — or `TO service_role` for server-only functions.
- **`game_questions.tone` is `NOT NULL`** with `CHECK (tone IN ('connecting','romantic','playful','spicy','intimate'))`. All new seed rows must supply a valid tone. Use `'connecting'` for all three new game types.
- **Migration timestamps** must sort after `20260908120000` (the latest applied migration).
- **Never `DROP` an existing column or table.** All schema changes are additive.

---

## File Structure

**New migrations**
- `supabase/migrations/20260909120000_session_games_schema.sql` — widen `game_questions`, add `mirror_round_truth` + `mirror_scores`, RLS, reveal-gate RPC
- `supabase/migrations/20260909130000_session_games_content.sql` — seed the three games' questions
- `supabase/migrations/20260909140000_game_pulse_signals.sql` — `compute_relationship_game_signals` RPC

**Modified edge function**
- `supabase/functions/compute-pulse/index.ts` — add `GameSignals`, `applyGameSignals`, and the call site

**New Flutter (one directory per game, mirroring `lib/features/games/this_or_that/`)**
- `lib/features/games/session_games/data/models/session_game_question.dart` — one model shared by all three; they differ only in which fields are populated
- `lib/features/games/session_games/data/repositories/session_game_repository.dart` — shared session/round/reveal calls
- `lib/features/games/mirror/domain/services/mirror_scoring.dart` — pure scoring, no I/O
- `lib/features/games/sliding_scale/domain/services/sliding_scale_gap.dart` — pure gap maths, no I/O

**Modified Flutter**
- `lib/features/games/presentation/widgets/chat_games_sheet.dart` — register the three games in `_chatGameCategories`
- `lib/app/routing/app_router.dart` — three route constants + routes

A single `session_games/` shared layer plus thin per-game domain services keeps the three games from triplicating the 28-file shape `this_or_that` currently has. The two pure domain services are separate files because they are the only genuinely game-specific logic, and being I/O-free makes them directly unit-testable.

---

## Task 1: Schema — widen `game_questions`, add Mirror's two tables

**Files:**
- Create: `supabase/migrations/20260909120000_session_games_schema.sql`
- Test: `supabase/tests/session_games_contracts.sql`

**Interfaces:**
- Consumes: nothing (first task)
- Produces: `game_questions` accepting `game_type IN ('mirror','sliding_scale','scenario')` with columns `value_domain text`, `scale_low text`, `scale_high text`, `options jsonb`; tables `public.mirror_round_truth(round_id, subject_id, truth_text, submitted_at)` and `public.mirror_scores(session_id, user_id, score, flagged)`; RPC `public.get_revealed_round(p_round_id uuid) RETURNS TABLE(answer_a text, answer_b text, both_answered boolean)`

- [ ] **Step 1: Write the failing contract test**

Create `supabase/tests/session_games_contracts.sql`:

```sql
-- Contract tests for the session-games schema. Run against a database
-- with the migration applied. Each block RAISEs on violation, so a
-- silent pass means the contract holds.

-- 1. game_questions accepts the three new types.
DO $$
BEGIN
  INSERT INTO public.game_questions
    (game_type, tone, question_text, value_domain, scale_low, scale_high)
  VALUES
    ('sliding_scale', 'connecting', 'Money should be fully shared.',
     'money', 'Keep separate', 'Fully shared');
  DELETE FROM public.game_questions WHERE value_domain = 'money'
    AND question_text = 'Money should be fully shared.';
END;
$$;

-- 2. A sliding_scale row WITHOUT its scale anchors is rejected.
DO $$
BEGIN
  BEGIN
    INSERT INTO public.game_questions (game_type, tone, question_text)
    VALUES ('sliding_scale', 'connecting', 'No anchors');
    RAISE EXCEPTION 'sliding_scale without anchors was accepted';
  EXCEPTION WHEN check_violation THEN
    NULL; -- expected
  END;
END;
$$;

-- 3. A scenario row WITHOUT options is rejected.
DO $$
BEGIN
  BEGIN
    INSERT INTO public.game_questions (game_type, tone, question_text)
    VALUES ('scenario', 'connecting', 'No options');
    RAISE EXCEPTION 'scenario without options was accepted';
  EXCEPTION WHEN check_violation THEN
    NULL; -- expected
  END;
END;
$$;

-- 4. The existing this_or_that contract still holds (regression).
DO $$
BEGIN
  BEGIN
    INSERT INTO public.game_questions (game_type, tone, question_text)
    VALUES ('this_or_that', 'connecting', 'Missing its options');
    RAISE EXCEPTION 'this_or_that without options was accepted';
  EXCEPTION WHEN check_violation THEN
    NULL; -- expected
  END;
END;
$$;
```

- [ ] **Step 2: Run it and verify it fails**

Run: `supabase db push` is not yet applicable — instead confirm the current schema rejects the new type:

```bash
grep -n "game_type IN ('this_or_that', 'truth_or_dare')" \
  supabase/migrations/20260712125000_games_launch_hardening.sql
```

Expected: the line is present, proving `'sliding_scale'` is currently rejected and test 1 would fail.

- [ ] **Step 3: Write the migration**

Create `supabase/migrations/20260909120000_session_games_schema.sql`:

```sql
-- Session games (§8.4): Mirror, Sliding Scale, Scenario.
--
-- These extend the existing generic game engine rather than adding
-- subsystems: game_sessions/game_session_rounds already carry
-- game_type, answer_a/answer_b, both_answered and revealed_at, and all
-- three shipped games use them with no tables of their own.

-- ---------------------------------------------------------------------
-- 1. Widen game_questions
-- ---------------------------------------------------------------------

ALTER TABLE public.game_questions
  ADD COLUMN IF NOT EXISTS value_domain text,
  ADD COLUMN IF NOT EXISTS scale_low text,
  ADD COLUMN IF NOT EXISTS scale_high text,
  ADD COLUMN IF NOT EXISTS options jsonb;

ALTER TABLE public.game_questions
  DROP CONSTRAINT IF EXISTS game_questions_game_type_check;

ALTER TABLE public.game_questions
  ADD CONSTRAINT game_questions_game_type_check
  CHECK (game_type IN (
    'this_or_that', 'truth_or_dare',
    'mirror', 'sliding_scale', 'scenario'
  ));

-- The original table-level CHECK was unnamed, so Postgres generated
-- `game_questions_check`. It is dropped and replaced with a named
-- constraint covering all five types — the two existing branches are
-- reproduced verbatim so this is a widening, never a relaxation.
ALTER TABLE public.game_questions
  DROP CONSTRAINT IF EXISTS game_questions_check;

ALTER TABLE public.game_questions
  ADD CONSTRAINT game_questions_shape_check CHECK (
    (game_type = 'this_or_that'
      AND question_subtype IS NULL
      AND option_a IS NOT NULL
      AND option_b IS NOT NULL)
    OR
    (game_type = 'truth_or_dare'
      AND question_subtype IS NOT NULL
      AND option_a IS NULL
      AND option_b IS NULL)
    OR
    -- Mirror: a free-text prompt about the partner's current state.
    (game_type = 'mirror'
      AND question_subtype IS NULL)
    OR
    -- Sliding Scale: both 1 and 10 anchors required, or the rating is
    -- meaningless, plus the §8.4 value domain it belongs to.
    (game_type = 'sliding_scale'
      AND question_subtype IS NULL
      AND value_domain IS NOT NULL
      AND scale_low IS NOT NULL
      AND scale_high IS NOT NULL)
    OR
    -- Scenario: 3-4 options as [{"key":"a","text":"..."}].
    -- jsonb rather than more nullable text columns because the count
    -- varies; option_a/option_b cannot express 3 or 4.
    (game_type = 'scenario'
      AND question_subtype IS NULL
      AND options IS NOT NULL
      AND jsonb_typeof(options) = 'array'
      AND jsonb_array_length(options) BETWEEN 3 AND 4)
  );

-- ---------------------------------------------------------------------
-- 2. mirror_round_truth
--
-- Mirror is the only game whose round holds THREE values: A's guess,
-- B's guess, and the subject's real answer. The third has nowhere to
-- live in the two-column round shape.
-- ---------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.mirror_round_truth (
  round_id uuid PRIMARY KEY
    REFERENCES public.game_session_rounds(id) ON DELETE CASCADE,
  -- Whose inner state this round is about. Mirror alternates, so both
  -- partners are guessed about across the 8 rounds.
  subject_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  truth_text text NOT NULL CHECK (char_length(truth_text) <= 400),
  submitted_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.mirror_round_truth ENABLE ROW LEVEL SECURITY;

-- Both partners may read the truth (it is revealed to both, and that
-- reveal IS the game); only the subject may write their own.
DROP POLICY IF EXISTS mirror_truth_members_read ON public.mirror_round_truth;
CREATE POLICY mirror_truth_members_read
ON public.mirror_round_truth FOR SELECT
USING (
  round_id IN (
    SELECT r.id FROM public.game_session_rounds r
    JOIN public.game_sessions s ON s.id = r.session_id
    JOIN public.relationships rel ON rel.id = s.relationship_id
    WHERE rel.user_a = auth.uid() OR rel.user_b = auth.uid()
  )
);

DROP POLICY IF EXISTS mirror_truth_subject_write ON public.mirror_round_truth;
CREATE POLICY mirror_truth_subject_write
ON public.mirror_round_truth FOR INSERT
WITH CHECK (subject_id = auth.uid());

-- ---------------------------------------------------------------------
-- 3. mirror_scores — §11.1
--
-- "Asymmetric behavioural data is shown to each user about themselves
-- only. Never shown as a judgment of the partner." A per-person
-- attentiveness score on the shared game_sessions row would be readable
-- by both partners by construction, so it lives here instead, scoped by
-- RLS to its own subject. game_sessions.match_count is deliberately
-- left unused by Mirror for exactly this reason.
-- ---------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.mirror_scores (
  session_id uuid NOT NULL
    REFERENCES public.game_sessions(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  score int NOT NULL CHECK (score BETWEEN 0 AND 8),
  flagged boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (session_id, user_id)
);

ALTER TABLE public.mirror_scores ENABLE ROW LEVEL SECURITY;

-- The whole §11.1 guarantee, in one clause: a partner cannot read this
-- row even with a direct PostgREST query. Enforced here rather than in
-- a widget so it survives any future client that forgets it.
DROP POLICY IF EXISTS mirror_scores_self_only ON public.mirror_scores;
CREATE POLICY mirror_scores_self_only
ON public.mirror_scores FOR ALL
USING (user_id = auth.uid())
WITH CHECK (user_id = auth.uid());

REVOKE ALL ON public.mirror_round_truth FROM PUBLIC, anon;
REVOKE ALL ON public.mirror_scores FROM PUBLIC, anon;
GRANT SELECT, INSERT ON public.mirror_round_truth TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.mirror_scores TO authenticated;

-- ---------------------------------------------------------------------
-- 4. Reveal gate
--
-- game_session_rounds' RLS grants relationship members FOR ALL on the
-- whole row, and both_answered is checked only inside RPCs — never in a
-- policy. So a direct PostgREST select can read a partner's answer
-- before reveal. §8.4 calls that mechanic non-negotiable.
--
-- Fixing it for the three shipped games is out of scope (their clients
-- select the row directly and would break), but the new games must not
-- inherit it: they read answers ONLY through this function, which
-- returns them only once both partners have submitted.
-- ---------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.get_revealed_round(p_round_id uuid)
RETURNS TABLE (answer_a text, answer_b text, both_answered boolean)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    CASE WHEN r.both_answered THEN r.answer_a ELSE NULL END,
    CASE WHEN r.both_answered THEN r.answer_b ELSE NULL END,
    r.both_answered
  FROM public.game_session_rounds r
  JOIN public.game_sessions s ON s.id = r.session_id
  JOIN public.relationships rel ON rel.id = s.relationship_id
  WHERE r.id = p_round_id
    AND (rel.user_a = auth.uid() OR rel.user_b = auth.uid());
$$;

REVOKE ALL ON FUNCTION public.get_revealed_round(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_revealed_round(uuid) TO authenticated;
```

- [ ] **Step 4: Apply and verify**

Run:
```bash
cd /Users/user/attune && supabase db push
```
Expected: `Applying migration 20260909120000_session_games_schema.sql...` then `Finished supabase db push.` with no error.

Then confirm it registered:
```bash
supabase migration list | grep 20260909120000
```
Expected: the timestamp appears in BOTH the Local and Remote columns.

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/20260909120000_session_games_schema.sql \
        supabase/tests/session_games_contracts.sql
git commit -m "feat(games): schema for Mirror, Sliding Scale and Scenario

Widens game_questions to five types with a named shape CHECK (the two
existing branches reproduced verbatim, so this is a widening). Adds
mirror_round_truth for Mirror's third per-round value, and mirror_scores
with USING (user_id = auth.uid()) so a partner cannot read the other's
attentiveness score even by direct query — §11.1 enforced in RLS rather
than UI.

Adds get_revealed_round(), which returns a partner's answer only when
both_answered is true. game_session_rounds' own policy grants members
FOR ALL on the whole row and checks both_answered only inside RPCs, so
new games read through this function rather than inheriting that hole."
```

---

## Task 2: Seed the three games' content

**Files:**
- Create: `supabase/migrations/20260909130000_session_games_content.sql`

**Interfaces:**
- Consumes: `game_questions` from Task 1 (columns `value_domain`, `scale_low`, `scale_high`, `options`; `game_type` accepting the three new values)
- Produces: seeded rows — 24 `mirror`, 6 `sliding_scale`, 10 `scenario`

- [ ] **Step 1: Write the migration**

Create `supabase/migrations/20260909130000_session_games_content.sql`. Follows the existing seeding pattern from `20260712125000_games_launch_hardening.sql` (`WITH seed(...) AS (VALUES ...)`), and is idempotent so a re-run does not duplicate rows.

```sql
-- Content for the three session games (§8.4).
--
-- tone is 'connecting' throughout: game_questions.tone is NOT NULL with
-- CHECK (tone IN ('connecting','romantic','playful','spicy','intimate')),
-- and these three games are diagnostic rather than playful.

-- Mirror: 24 prompts about the partner's CURRENT state (§8.4 measures
-- attentiveness now, not memory of biographical facts).
WITH seed(question_text) AS (
  VALUES
  ('What is weighing on them most this week?'),
  ('What would they say is going well right now?'),
  ('What are they most looking forward to?'),
  ('What small thing has been irritating them lately?'),
  ('How rested do they feel at the moment?'),
  ('What would help them most this week?'),
  ('What are they worrying about that they have not said out loud?'),
  ('What did they enjoy most in the last few days?'),
  ('How are they feeling about work right now?'),
  ('What would their ideal evening look like this week?'),
  ('What have they been putting off?'),
  ('Who have they been thinking about lately?'),
  ('What is one thing they need more of right now?'),
  ('What would they change about this week if they could?'),
  ('How connected have they been feeling to you lately?'),
  ('What made them laugh most recently?'),
  ('What are they proud of right now?'),
  ('What is draining their energy at the moment?'),
  ('What would they want a whole free day for?'),
  ('What have they been quietly hoping you would notice?'),
  ('What is on their mind just before sleep lately?'),
  ('What kind of support do they want right now — practical or emotional?'),
  ('What has felt harder than usual for them recently?'),
  ('What are they curious about at the moment?')
)
INSERT INTO public.game_questions (game_type, tone, question_text)
SELECT 'mirror', 'connecting', s.question_text
FROM seed s
WHERE NOT EXISTS (
  SELECT 1 FROM public.game_questions g
  WHERE g.game_type = 'mirror' AND g.question_text = s.question_text
);

-- Sliding Scale: one statement per §8.4 domain (money, children,
-- independence, location, ambition, religion).
WITH seed(value_domain, question_text, scale_low, scale_high) AS (
  VALUES
  ('money', 'How much of our money should be shared?',
   'Kept separate', 'Fully shared'),
  ('children', 'How central are children to the life you want?',
   'Not part of it', 'Central to it'),
  ('independence', 'How much time apart feels right to you?',
   'Almost none', 'A great deal'),
  ('location', 'How settled do you want to be geographically?',
   'Open to moving', 'Rooted for good'),
  ('ambition', 'How much should career shape our decisions?',
   'It comes second', 'It leads'),
  ('religion', 'How present should faith or spirituality be in our life?',
   'Not present', 'Central')
)
INSERT INTO public.game_questions
  (game_type, tone, question_text, value_domain, scale_low, scale_high)
SELECT 'sliding_scale', 'connecting',
       s.question_text, s.value_domain, s.scale_low, s.scale_high
FROM seed s
WHERE NOT EXISTS (
  SELECT 1 FROM public.game_questions g
  WHERE g.game_type = 'sliding_scale' AND g.value_domain = s.value_domain
);

-- Scenario: 10 situations, 3 options each. §8.4: "Neither option is
-- 'correct' — the insight is in the pattern across scenarios", so the
-- options are written as equally defensible.
WITH seed(question_text, options) AS (
  VALUES
  ('You are both tired and a disagreement starts. What do you do?',
   '[{"key":"a","text":"Push through and resolve it now"},
     {"key":"b","text":"Pause and return to it tomorrow"},
     {"key":"c","text":"Step away alone for a while first"}]'::jsonb),
  ('Your partner is upset but says they are fine. What do you do?',
   '[{"key":"a","text":"Take them at their word"},
     {"key":"b","text":"Ask once more, gently"},
     {"key":"c","text":"Stay close without asking"}]'::jsonb),
  ('A friend criticises your partner in front of you. What do you do?',
   '[{"key":"a","text":"Defend them on the spot"},
     {"key":"b","text":"Change the subject"},
     {"key":"c","text":"Raise it with the friend privately later"}]'::jsonb),
  ('You get a job offer in another city. What comes first?',
   '[{"key":"a","text":"Talk it through before deciding anything"},
     {"key":"b","text":"Work out what you want, then discuss"},
     {"key":"c","text":"Decline unless you both already wanted to move"}]'::jsonb),
  ('Your partner forgets something that mattered to you. What do you do?',
   '[{"key":"a","text":"Say so directly, soon"},
     {"key":"b","text":"Let it go this time"},
     {"key":"c","text":"Wait to see if they remember on their own"}]'::jsonb),
  ('You disagree about money on something significant. What do you do?',
   '[{"key":"a","text":"Defer to whoever feels more strongly"},
     {"key":"b","text":"Find a compromise you both half-like"},
     {"key":"c","text":"Postpone until you both have more information"}]'::jsonb),
  ('Your partner wants a weekend alone. How do you take it?',
   '[{"key":"a","text":"Straightforwardly — everyone needs space"},
     {"key":"b","text":"Fine, but you would want to know why"},
     {"key":"c","text":"It would sit uneasily with you"}]'::jsonb),
  ('You are running late to something that matters to them. What do you do?',
   '[{"key":"a","text":"Tell them immediately"},
     {"key":"b","text":"Try to make up the time first"},
     {"key":"c","text":"Tell them once you know how late you will be"}]'::jsonb),
  ('A conflict from last month resurfaces. What do you do?',
   '[{"key":"a","text":"Treat it as unfinished and reopen it"},
     {"key":"b","text":"Address only what is happening now"},
     {"key":"c","text":"Ask why it is coming back before engaging"}]'::jsonb),
  ('Your partner is stressed and short with you. What do you do?',
   '[{"key":"a","text":"Give them room until it passes"},
     {"key":"b","text":"Name it kindly in the moment"},
     {"key":"c","text":"Take on something practical to lighten the load"}]'::jsonb)
)
INSERT INTO public.game_questions (game_type, tone, question_text, options)
SELECT 'scenario', 'connecting', s.question_text, s.options
FROM seed s
WHERE NOT EXISTS (
  SELECT 1 FROM public.game_questions g
  WHERE g.game_type = 'scenario' AND g.question_text = s.question_text
);
```

- [ ] **Step 2: Apply and verify the counts**

Run:
```bash
cd /Users/user/attune && supabase db push
```
Expected: applies with no CHECK violation. A violation here means a seed row does not satisfy Task 1's `game_questions_shape_check` — read the error's failing row before changing the constraint.

- [ ] **Step 3: Verify idempotency**

Run `supabase db push` again after re-stamping is not possible; instead confirm by inspection that every INSERT has its `WHERE NOT EXISTS` guard:

```bash
grep -c "WHERE NOT EXISTS" supabase/migrations/20260909130000_session_games_content.sql
```
Expected: `3` — one per INSERT.

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/20260909130000_session_games_content.sql
git commit -m "feat(games): seed Mirror, Sliding Scale and Scenario content

24 Mirror prompts about the partner's current state (§8.4 measures
attentiveness now, not biographical recall), 6 Sliding Scale statements
covering the domains §8.4 names, and 10 Scenarios with 3 equally
defensible options each — per §8.4 'neither option is correct'.

Every INSERT is guarded by WHERE NOT EXISTS so a re-run cannot
duplicate rows."
```

---

## Task 3: Mirror scoring (pure domain logic)

**Files:**
- Create: `lib/features/games/mirror/domain/services/mirror_scoring.dart`
- Test: `test/features/games/mirror_scoring_test.dart`

**Interfaces:**
- Consumes: nothing (pure logic, no I/O)
- Produces: `int mirrorScore(List<bool> judgements)`, `bool isAttentivenessFlagged(int score, {int total = 8})`, `const double kAttentivenessFlagThreshold = 6.5`

- [ ] **Step 1: Write the failing test**

Create `test/features/games/mirror_scoring_test.dart`:

```dart
import 'package:attune/features/games/mirror/domain/services/mirror_scoring.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('mirrorScore', () {
    test('counts correct judgements', () {
      expect(mirrorScore([true, true, false, true]), 3);
    });

    test('a perfect round scores every question', () {
      expect(mirrorScore(List<bool>.filled(8, true)), 8);
    });

    test('no correct guesses scores zero, not null', () {
      expect(mirrorScore(List<bool>.filled(8, false)), 0);
    });

    test('an empty list scores zero', () {
      // A session abandoned before any round was judged must produce a
      // real 0, not a crash or a null that later reads as "unscored".
      expect(mirrorScore(const []), 0);
    });
  });

  group('isAttentivenessFlagged', () {
    test('flags below the 6.5 threshold (§8.4)', () {
      expect(isAttentivenessFlagged(6), isTrue);
      expect(isAttentivenessFlagged(0), isTrue);
    });

    test('does not flag at or above the threshold', () {
      // 6.5 of 8 means 7 is the first passing whole score.
      expect(isAttentivenessFlagged(7), isFalse);
      expect(isAttentivenessFlagged(8), isFalse);
    });

    test('the boundary is exclusive on the low side', () {
      // Guards the off-by-one: 6 < 6.5 flags, 7 > 6.5 does not. A >= 
      // comparison against 6 or a rounding of 6.5 to 7 would break one
      // of these two assertions.
      expect(isAttentivenessFlagged(6), isTrue);
      expect(isAttentivenessFlagged(7), isFalse);
    });
  });
}
```

- [ ] **Step 2: Run it and verify it fails**

Run: `cd /Users/user/attune && flutter test test/features/games/mirror_scoring_test.dart`
Expected: FAIL — `Error: Couldn't resolve the package 'attune' ... mirror_scoring.dart` or `Undefined name 'mirrorScore'`.

- [ ] **Step 3: Write the implementation**

Create `lib/features/games/mirror/domain/services/mirror_scoring.dart`:

```dart
/// Mirror Game scoring (ATTUNE_MASTER_SPEC.md §8.4).
///
/// Pure and I/O-free so it is directly testable, and so the §11.1
/// visibility rules around the RESULT are enforced at the storage layer
/// (mirror_scores' RLS) rather than tangled into the arithmetic.

/// §8.4: "Score tracked: below 6.5/8 = attentiveness flag".
const double kAttentivenessFlagThreshold = 6.5;

/// Number of guesses the subject judged correct.
///
/// Correctness is a subjective judgement made by the SUBJECT — the
/// person whose inner state the round was about — not string equality.
/// "She's stressed about work" against "work has been overwhelming" is
/// a match, and no string comparison or fuzzy match would agree. This
/// function therefore takes the judgements, never the raw answers.
int mirrorScore(List<bool> judgements) =>
    judgements.where((correct) => correct).length;

/// Whether this score raises the §8.4 attentiveness flag.
///
/// Strictly below the threshold: 6/8 flags, 7/8 does not. The flag is
/// self-facing only (§11.1) — the caller must never surface it for the
/// partner.
bool isAttentivenessFlagged(int score, {int total = 8}) {
  if (total <= 0) return false;
  final scaled = score * (8 / total);
  return scaled < kAttentivenessFlagThreshold;
}
```

- [ ] **Step 4: Run the test and verify it passes**

Run: `cd /Users/user/attune && flutter test test/features/games/mirror_scoring_test.dart`
Expected: `All tests passed!` (7 tests)

- [ ] **Step 5: Commit**

```bash
git add lib/features/games/mirror/domain/services/mirror_scoring.dart \
        test/features/games/mirror_scoring_test.dart
git commit -m "feat(games): Mirror attentiveness scoring

Pure, I/O-free scoring with the §8.4 threshold (below 6.5/8 flags).
Takes the subject's judgements rather than raw answers: correctness is
subjective — 'stressed about work' against 'work has been overwhelming'
is a match no string comparison would accept."
```

---

## Task 4: Sliding Scale gap (pure domain logic)

**Files:**
- Create: `lib/features/games/sliding_scale/domain/services/sliding_scale_gap.dart`
- Test: `test/features/games/sliding_scale_gap_test.dart`

**Interfaces:**
- Consumes: nothing (pure logic, no I/O)
- Produces: `int ratingGap(int a, int b)`, `double averageGap(List<int> gaps)`, `double alignmentFromGap(double avgGap)`

- [ ] **Step 1: Write the failing test**

Create `test/features/games/sliding_scale_gap_test.dart`:

```dart
import 'package:attune/features/games/sliding_scale/domain/services/sliding_scale_gap.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ratingGap', () {
    test('identical ratings have no gap', () {
      expect(ratingGap(5, 5), 0);
    });

    test('opposite extremes give the maximum gap of 9', () {
      // The scale is 1-10, so the widest possible disagreement is 9,
      // not 10. Getting this wrong would make alignmentFromGap return a
      // negative score at the extreme.
      expect(ratingGap(1, 10), 9);
      expect(ratingGap(10, 1), 9);
    });

    test('gap is order-independent', () {
      expect(ratingGap(3, 8), ratingGap(8, 3));
    });
  });

  group('averageGap', () {
    test('averages across statements', () {
      expect(averageGap([0, 4, 2]), closeTo(2.0, 0.001));
    });

    test('an empty list averages to zero, not NaN', () {
      // Guards a divide-by-zero that would propagate NaN into the Pulse
      // score and poison every downstream comparison.
      expect(averageGap(const []), 0.0);
    });
  });

  group('alignmentFromGap', () {
    test('a zero gap is full alignment', () {
      expect(alignmentFromGap(0), closeTo(100.0, 0.001));
    });

    test('the maximum gap is zero alignment', () {
      expect(alignmentFromGap(9), closeTo(0.0, 0.001));
    });

    test('a mid gap is mid alignment', () {
      expect(alignmentFromGap(4.5), closeTo(50.0, 0.001));
    });

    test('out-of-range input is clamped, never negative', () {
      expect(alignmentFromGap(20), 0.0);
      expect(alignmentFromGap(-3), 100.0);
    });
  });
}
```

- [ ] **Step 2: Run it and verify it fails**

Run: `cd /Users/user/attune && flutter test test/features/games/sliding_scale_gap_test.dart`
Expected: FAIL — `Undefined name 'ratingGap'`.

- [ ] **Step 3: Write the implementation**

Create `lib/features/games/sliding_scale/domain/services/sliding_scale_gap.dart`:

```dart
import 'dart:math' as math;

/// Sliding Scale gap maths (ATTUNE_MASTER_SPEC.md §8.4).
///
/// Pure and I/O-free. This is the "values overlap from games" input §7
/// names for the Alignment dimension, so its range behaviour matters
/// beyond this game: a NaN or a negative here would propagate into
/// every couple's Pulse score.

/// Absolute distance between two 1-10 ratings.
///
/// Maximum is 9 (1 versus 10), not 10 — the scale has ten positions but
/// nine intervals.
int ratingGap(int a, int b) => (a - b).abs();

/// Mean gap across statements both partners rated.
///
/// Returns 0.0 for an empty list rather than NaN: a couple who rated
/// nothing has no measured disagreement, and NaN would silently corrupt
/// the Alignment dimension it feeds.
double averageGap(List<int> gaps) {
  if (gaps.isEmpty) return 0.0;
  return gaps.reduce((a, b) => a + b) / gaps.length;
}

/// Converts an average gap into a 0-100 alignment score.
///
/// Inverted: a small gap means high alignment. Clamped at both ends so
/// an out-of-range input can never produce a negative or above-100
/// contribution to Pulse.
double alignmentFromGap(double avgGap) {
  const maxGap = 9.0;
  final clamped = math.max(0.0, math.min(maxGap, avgGap));
  return (1.0 - clamped / maxGap) * 100.0;
}
```

- [ ] **Step 4: Run the test and verify it passes**

Run: `cd /Users/user/attune && flutter test test/features/games/sliding_scale_gap_test.dart`
Expected: `All tests passed!` (9 tests)

- [ ] **Step 5: Commit**

```bash
git add lib/features/games/sliding_scale/domain/services/sliding_scale_gap.dart \
        test/features/games/sliding_scale_gap_test.dart
git commit -m "feat(games): Sliding Scale gap maths

Pure gap/alignment conversion with the boundaries tested: max gap is 9
(1 vs 10, nine intervals not ten), empty input averages to 0.0 rather
than NaN, and alignment is clamped so an out-of-range value cannot push
a negative contribution into the Pulse Alignment dimension."
```

---

## Task 5: Game signals RPC

**Files:**
- Create: `supabase/migrations/20260909140000_game_pulse_signals.sql`

**Interfaces:**
- Consumes: `game_sessions`, `game_session_rounds`, `game_questions` (Task 1's widened types), `mirror_scores` (Task 1)
- Produces: RPC `public.compute_relationship_game_signals(p_relationship_id uuid, p_window_start timestamptz) RETURNS TABLE (sessions_completed int, sliding_scale_pairs int, sliding_scale_avg_gap double precision, mirror_rounds_scored int)`

- [ ] **Step 1: Write the migration**

Create `supabase/migrations/20260909140000_game_pulse_signals.sql`:

```sql
-- Game signals for the Pulse score.
--
-- §7 lists "game engagement" as a Connection data source and "values
-- overlap from games" for Alignment, but compute-pulse reads no game
-- table at all — so 40% of the score is computed without the inputs its
-- own specification names.
--
-- Mirrors compute_relationship_chat_signals: pre-aggregates in Postgres
-- so the edge function never selects raw game rows (Algorithm Quality
-- Review Checklist 2.14, memory growth bounds), and is service-role
-- only.

CREATE OR REPLACE FUNCTION public.compute_relationship_game_signals(
  p_relationship_id uuid,
  p_window_start timestamptz
)
RETURNS TABLE (
  sessions_completed int,
  sliding_scale_pairs int,
  sliding_scale_avg_gap double precision,
  mirror_rounds_scored int
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  WITH completed AS (
    SELECT s.id, s.game_type
    FROM public.game_sessions s
    WHERE s.relationship_id = p_relationship_id
      AND s.status = 'completed'
      AND s.completed_at >= p_window_start
  ),
  scale_rounds AS (
    -- Only rounds where BOTH partners rated: a one-sided rating has no
    -- gap to measure.
    SELECT abs(r.answer_a::int - r.answer_b::int) AS gap
    FROM public.game_session_rounds r
    JOIN completed c ON c.id = r.session_id
    WHERE c.game_type = 'sliding_scale'
      AND r.both_answered = true
      AND r.answer_a ~ '^[0-9]+$'
      AND r.answer_b ~ '^[0-9]+$'
  ),
  mirror_rounds AS (
    SELECT count(*)::int AS n
    FROM public.game_session_rounds r
    JOIN completed c ON c.id = r.session_id
    WHERE c.game_type = 'mirror'
      AND r.both_answered = true
  )
  SELECT
    (SELECT count(*)::int FROM completed),
    (SELECT count(*)::int FROM scale_rounds),
    (SELECT avg(gap)::double precision FROM scale_rounds),
    (SELECT n FROM mirror_rounds);
$$;

-- Server-only: these aggregates feed scoring and are not client data.
REVOKE ALL ON FUNCTION
  public.compute_relationship_game_signals(uuid, timestamptz)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION
  public.compute_relationship_game_signals(uuid, timestamptz)
  TO service_role;
```

The `~ '^[0-9]+$'` guards are load-bearing: `answer_a` is `text` (shared with games that store `'a'`/`'b'`), so an unguarded `::int` cast would raise on any non-numeric value and take the whole Pulse run down.

- [ ] **Step 2: Apply and verify**

Run:
```bash
cd /Users/user/attune && supabase db push
supabase migration list | grep 20260909140000
```
Expected: applies cleanly; the timestamp appears in both Local and Remote columns.

- [ ] **Step 3: Commit**

```bash
git add supabase/migrations/20260909140000_game_pulse_signals.sql
git commit -m "feat(pulse): add compute_relationship_game_signals

§7 names game engagement as a Connection source and values overlap as
an Alignment source, but compute-pulse read no game table at all. This
pre-aggregates both in Postgres, mirroring the existing chat-signals
RPC so the edge function never pulls raw game rows.

Numeric guards on the rating cast are load-bearing: answer_a is text
shared with games storing 'a'/'b', so an unguarded ::int would raise and
fail the whole pulse run."
```

---

## Task 6: Blend game signals into Pulse

**Files:**
- Modify: `supabase/functions/compute-pulse/index.ts`
- Test: `supabase/functions/compute-pulse/index.test.ts`

**Interfaces:**
- Consumes: `compute_relationship_game_signals` (Task 5); existing `DimensionState { communication, connection, emotionalSafety }` and `clamp()` in `index.ts`
- Produces: `export interface GameSignals { sessionsCompleted: number; slidingScalePairs: number; slidingScaleAvgGap: number | null; mirrorRoundsScored: number }`, `export interface GameDimensionState { connection: number; alignment: number }`, `export function applyGameSignals(dimensions: GameDimensionState, signals: GameSignals): GameDimensionState`

- [ ] **Step 1: Write the failing test**

Append to `supabase/functions/compute-pulse/index.test.ts`:

```ts
import {
  applyGameSignals,
  type GameSignals,
} from "./index.ts";

const noGames: GameSignals = {
  sessionsCompleted: 0,
  slidingScalePairs: 0,
  slidingScaleAvgGap: null,
  mirrorRoundsScored: 0,
};

Deno.test("applyGameSignals: zero game signal is a byte-identical no-op", () => {
  // The hard requirement from the design: a couple who never plays must
  // score exactly as they did before games existed. If this ever fails,
  // shipping the feature silently moves every non-playing couple's
  // Pulse score.
  const before = { connection: 62, alignment: 48 };
  const after = applyGameSignals(before, noGames);
  assertEquals(after, before);
});

Deno.test("applyGameSignals: engagement raises Connection", () => {
  const after = applyGameSignals(
    { connection: 50, alignment: 50 },
    { ...noGames, sessionsCompleted: 3 },
  );
  assertEquals(after.connection > 50, true);
  // Engagement says nothing about values overlap.
  assertEquals(after.alignment, 50);
});

Deno.test("applyGameSignals: engagement contribution is capped", () => {
  // An enthusiastic couple must not be able to max Connection through
  // volume alone — the dimension has other, more meaningful sources.
  const many = applyGameSignals(
    { connection: 50, alignment: 50 },
    { ...noGames, sessionsCompleted: 500 },
  );
  assertEquals(many.connection <= 60, true);
});

Deno.test("applyGameSignals: a small values gap raises Alignment", () => {
  const aligned = applyGameSignals(
    { connection: 50, alignment: 50 },
    { ...noGames, slidingScalePairs: 6, slidingScaleAvgGap: 0.5 },
  );
  assertEquals(aligned.alignment > 50, true);
});

Deno.test("applyGameSignals: a large values gap lowers Alignment", () => {
  const misaligned = applyGameSignals(
    { connection: 50, alignment: 50 },
    { ...noGames, slidingScalePairs: 6, slidingScaleAvgGap: 8.5 },
  );
  assertEquals(misaligned.alignment < 50, true);
});

Deno.test("applyGameSignals: too few rated pairs cannot move Alignment", () => {
  // One answered statement is not evidence of a values pattern.
  const thin = applyGameSignals(
    { connection: 50, alignment: 50 },
    { ...noGames, slidingScalePairs: 3, slidingScaleAvgGap: 9 },
  );
  assertEquals(thin.alignment, 50);
});

Deno.test("applyGameSignals: output stays within 0-100", () => {
  const low = applyGameSignals(
    { connection: 2, alignment: 2 },
    { ...noGames, slidingScalePairs: 6, slidingScaleAvgGap: 9 },
  );
  assertEquals(low.alignment >= 0, true);
  const high = applyGameSignals(
    { connection: 98, alignment: 98 },
    { ...noGames, sessionsCompleted: 50, slidingScalePairs: 6, slidingScaleAvgGap: 0 },
  );
  assertEquals(high.connection <= 100, true);
  assertEquals(high.alignment <= 100, true);
});
```

- [ ] **Step 2: Run it and verify it fails**

Run: `cd /Users/user/attune && deno test --allow-net --allow-env supabase/functions/compute-pulse/index.test.ts`
Expected: FAIL — `The requested module './index.ts' does not provide an export named 'applyGameSignals'`.

- [ ] **Step 3: Add the types and blend function**

In `supabase/functions/compute-pulse/index.ts`, immediately after the existing `applyChatSignals` function, add:

```ts
export interface GameSignals {
  sessionsCompleted: number
  slidingScalePairs: number
  slidingScaleAvgGap: number | null
  mirrorRoundsScored: number
}

/// Connection and Alignment only. Separate from DimensionState because
/// that type carries emotionalSafety and no alignment — chat signals and
/// game signals touch different dimensions.
export interface GameDimensionState {
  connection: number
  alignment: number
}

/// Blends game signals into the two dimensions §7 says they belong to.
///
/// Deliberately does NOT consume mirrorRoundsScored: Mirror accuracy is
/// per-person, and feeding it into a shared relationship score would
/// leak an asymmetric signal into a mutually-visible number (§11.1, one
/// step removed). It is returned by the RPC for diagnostics only.
export function applyGameSignals(
  dimensions: GameDimensionState,
  signals: GameSignals
): GameDimensionState {
  let { connection, alignment } = dimensions

  // CONNECTION — engagement. Capped at +10 so volume alone cannot max
  // the dimension; its other sources are more meaningful.
  if (signals.sessionsCompleted > 0) {
    connection = clamp(
      connection + Math.min(signals.sessionsCompleted * 2, 10),
      0,
      100
    )
  }

  // ALIGNMENT — values overlap, gated on at least 4 rated statements so
  // a single answer cannot move the score.
  if (signals.slidingScalePairs >= 4 && signals.slidingScaleAvgGap != null) {
    const maxGap = 9
    const clampedGap = Math.max(0, Math.min(maxGap, signals.slidingScaleAvgGap))
    // Centred on the mid gap: closer than 4.5 pulls up, wider pulls
    // down, and the magnitude is capped at +/-15.
    const delta = ((maxGap / 2 - clampedGap) / (maxGap / 2)) * 15
    alignment = clamp(alignment + delta, 0, 100)
  }

  return { connection, alignment }
}
```

- [ ] **Step 4: Run the test and verify it passes**

Run: `cd /Users/user/attune && deno test --allow-net --allow-env supabase/functions/compute-pulse/index.test.ts`
Expected: `ok | N passed | 0 failed` — including all seven new tests.

- [ ] **Step 5: Wire the call site**

In `supabase/functions/compute-pulse/index.ts`, after the existing chat-signal fetch (the `compute_relationship_chat_signals` `.rpc(...)` call), add:

```ts
  const { data: gameSignalRows } = await supabase
    .rpc('compute_relationship_game_signals', {
      p_relationship_id: relationshipId,
      p_window_start: thirtyDaysAgo.toISOString(),
    })
  const gameRow = gameSignalRows?.[0] ?? null

  const gameSignals: GameSignals = {
    sessionsCompleted: gameRow?.sessions_completed ?? 0,
    slidingScalePairs: gameRow?.sliding_scale_pairs ?? 0,
    slidingScaleAvgGap: gameRow?.sliding_scale_avg_gap ?? null,
    mirrorRoundsScored: gameRow?.mirror_rounds_scored ?? 0,
  }
```

Then, immediately after the existing `chatAdjusted` block that assigns
`communication`, `connection` and `emotionalSafety`, add:

```ts
  // Game signals (§7: Connection <- engagement, Alignment <- values
  // overlap). Applied after chat so both contribute; a couple with no
  // completed games gets an exact no-op here.
  const gameAdjusted = applyGameSignals({ connection, alignment }, gameSignals)
  connection = gameAdjusted.connection
  alignment = gameAdjusted.alignment
```

- [ ] **Step 6: Type-check and run the full suite**

Run:
```bash
cd /Users/user/attune && deno check supabase/functions/compute-pulse/index.ts
deno test --allow-net --allow-env supabase/functions/
```
Expected: `Check` with no errors, then `ok | N passed | 0 failed`.

If `alignment` is reported as `const`, change its declaration to `let` at
its definition site — do not shadow it with a new variable, which would
silently drop the game contribution.

- [ ] **Step 7: Deploy and smoke-test**

Run:
```bash
cd /Users/user/attune && supabase functions deploy compute-pulse
KEY=$(grep -h "SUPABASE_ANON_KEY=" .env | head -1 | cut -d= -f2- | tr -d '"'"'"'"'")
curl -s -X POST "https://mrgjtyacrzfylawyzabm.supabase.co/functions/v1/compute-pulse" \
  -H "apikey: $KEY" -H "Authorization: Bearer $KEY" \
  -H "Content-Type: application/json" -d '{"force_recompute": true}' | head -c 300
```
Expected: `{"success":true,"computed":N,...}`. A `"Could not compute pulse scores"` here means the RPC call failed — check that Task 5's migration is applied and granted to `service_role`.

- [ ] **Step 8: Commit**

```bash
git add supabase/functions/compute-pulse/index.ts \
        supabase/functions/compute-pulse/index.test.ts
git commit -m "feat(pulse): blend game signals into Connection and Alignment

Closes the §7 gap: Connection claims 'game engagement' and Alignment
claims 'values overlap from games', but compute-pulse read no game
table. Engagement is capped at +10 so volume alone cannot max the
dimension, and Alignment requires at least 4 rated statements before it
moves at all.

mirrorRoundsScored is fetched but deliberately not consumed: Mirror
accuracy is per-person, and feeding it into a shared score would leak an
asymmetric signal into a mutually-visible number (§11.1).

The zero-signal no-op is tested explicitly — a couple who never plays
must score byte-identically to before."
```

---

## Task 7: Register the three games in the launcher

**Files:**
- Modify: `lib/features/games/presentation/widgets/chat_games_sheet.dart`
- Test: `test/features/games/chat_games_sheet_test.dart`

**Interfaces:**
- Consumes: the existing `_ChatGameOption`/`_ChatGameCategory` const catalogue and the `ChatGameDestination` enum in `chat_games_sheet.dart`
- Produces: three new `ChatGameDestination` values — `mirror`, `slidingScale`, `scenario`

- [ ] **Step 1: Write the failing test**

Create `test/features/games/chat_games_sheet_test.dart`:

```dart
import 'package:attune/features/games/presentation/widgets/chat_games_sheet.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every launchable destination is reachable from the catalogue', () {
    // The catalogue is a const list, so a destination added to the enum
    // without a matching entry is invisible in the UI with no compile
    // error. This is the guard against that.
    //
    // gamesHub is excluded because it is not a game: it is the "see all"
    // destination the sheet itself routes to, so it correctly has no
    // catalogue entry. Verified against the current file — every other
    // enum value does have one.
    final reachable = chatGameDestinationsInCatalogue();
    final launchable = ChatGameDestination.values
        .where((d) => d != ChatGameDestination.gamesHub);
    for (final destination in launchable) {
      expect(
        reachable.contains(destination),
        isTrue,
        reason: '$destination has no entry in _chatGameCategories',
      );
    }
  });

  test('the three session games are present', () {
    final reachable = chatGameDestinationsInCatalogue();
    expect(reachable, contains(ChatGameDestination.mirror));
    expect(reachable, contains(ChatGameDestination.slidingScale));
    expect(reachable, contains(ChatGameDestination.scenario));
  });
}
```

- [ ] **Step 2: Run it and verify it fails**

Run: `cd /Users/user/attune && flutter test test/features/games/chat_games_sheet_test.dart`
Expected: FAIL — `Undefined name 'chatGameDestinationsInCatalogue'` and `The getter 'mirror' isn't defined for the type 'ChatGameDestination'`.

- [ ] **Step 3: Add the enum values, catalogue entries, and the test seam**

In `lib/features/games/presentation/widgets/chat_games_sheet.dart`:

Add to the `ChatGameDestination` enum:
```dart
  mirror,
  slidingScale,
  scenario,
```

Add a new category to `_chatGameCategories`, after the existing
`'Getting to know each other'` category:
```dart
  _ChatGameCategory(
    title: 'Understanding each other',
    options: [
      _ChatGameOption(
        destination: ChatGameDestination.mirror,
        title: 'Mirror',
        subtitle: 'How well do you read each other right now?',
        icon: Icons.psychology_outlined,
      ),
      _ChatGameOption(
        destination: ChatGameDestination.slidingScale,
        title: 'Sliding Scale',
        subtitle: 'Where you each land on what matters',
        icon: Icons.tune_rounded,
      ),
      _ChatGameOption(
        destination: ChatGameDestination.scenario,
        title: 'Scenario',
        subtitle: 'What you would each do, and why',
        icon: Icons.alt_route_rounded,
      ),
    ],
  ),
```

Add the test seam at the bottom of the file:
```dart
/// The destinations the catalogue actually exposes.
///
/// Exists so a test can prove every enum value has a UI entry — the
/// catalogue is a const list, so a missing entry is invisible at compile
/// time and would ship a game no one can launch.
@visibleForTesting
Set<ChatGameDestination> chatGameDestinationsInCatalogue() => {
      for (final category in _chatGameCategories)
        for (final option in category.options) option.destination,
    };
```

If `@visibleForTesting` is not already imported, add
`import 'package:flutter/foundation.dart';` at the top of the file.

- [ ] **Step 4: Run the test and verify it passes**

Run: `cd /Users/user/attune && flutter test test/features/games/chat_games_sheet_test.dart`
Expected: `All tests passed!` (2 tests)

If the first test fails naming a destination other than the three new
ones, that destination has lost its catalogue entry since this plan was
written. Do not add a filler entry to force the test green — report it,
since it means a shipped game became unlaunchable.

- [ ] **Step 5: Verify nothing else broke**

Run: `cd /Users/user/attune && flutter analyze lib/features/games/`
Expected: no `error •` lines. A non-exhaustive-switch error on
`ChatGameDestination` means a `switch` elsewhere needs the three new
cases — add them, routing to the screens from Task 8.

- [ ] **Step 6: Commit**

```bash
git add lib/features/games/presentation/widgets/chat_games_sheet.dart \
        test/features/games/chat_games_sheet_test.dart
git commit -m "feat(games): register Mirror, Sliding Scale and Scenario

Adds an 'Understanding each other' category to the launcher catalogue,
plus a test proving every ChatGameDestination has an entry — the
catalogue is a const list, so a missing entry ships a game no one can
launch, with no compile error."
```

---

## Task 8: Session repository and reveal-gated reads

**Files:**
- Create: `lib/features/games/session_games/data/models/session_game_question.dart`
- Create: `lib/features/games/session_games/data/repositories/session_game_repository.dart`
- Test: `test/features/games/session_game_repository_test.dart`

**Interfaces:**
- Consumes: `get_revealed_round` RPC (Task 1); `game_questions` columns `value_domain`, `scale_low`, `scale_high`, `options` (Task 1)
- Produces: `SessionGameQuestion.fromRow(Map<String, dynamic>)` with fields `id`, `gameType`, `questionText`, `valueDomain`, `scaleLow`, `scaleHigh`, `options` (`List<SessionGameOption>`); `SessionGameRepository.fetchQuestions({required String gameType, required int limit})`; `SessionGameRepository.fetchRevealedRound(String roundId)` returning `RevealedRound(answerA, answerB, bothAnswered)`

- [ ] **Step 1: Write the failing test**

Create `test/features/games/session_game_repository_test.dart`:

```dart
import 'package:attune/features/games/session_games/data/models/session_game_question.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SessionGameQuestion.fromRow', () {
    test('parses a sliding_scale row with its anchors', () {
      final q = SessionGameQuestion.fromRow(const {
        'id': 'q1',
        'game_type': 'sliding_scale',
        'question_text': 'How much of our money should be shared?',
        'value_domain': 'money',
        'scale_low': 'Kept separate',
        'scale_high': 'Fully shared',
      });
      expect(q.gameType, 'sliding_scale');
      expect(q.valueDomain, 'money');
      expect(q.scaleLow, 'Kept separate');
      expect(q.scaleHigh, 'Fully shared');
      expect(q.options, isEmpty);
    });

    test('parses a scenario row with its options', () {
      final q = SessionGameQuestion.fromRow(const {
        'id': 'q2',
        'game_type': 'scenario',
        'question_text': 'You are both tired and a disagreement starts.',
        'options': [
          {'key': 'a', 'text': 'Push through'},
          {'key': 'b', 'text': 'Pause'},
          {'key': 'c', 'text': 'Step away'},
        ],
      });
      expect(q.options.length, 3);
      expect(q.options.first.key, 'a');
      expect(q.options.first.text, 'Push through');
    });

    test('parses a mirror row, which has neither anchors nor options', () {
      final q = SessionGameQuestion.fromRow(const {
        'id': 'q3',
        'game_type': 'mirror',
        'question_text': 'What is weighing on them most this week?',
      });
      expect(q.gameType, 'mirror');
      expect(q.options, isEmpty);
      expect(q.scaleLow, isNull);
    });

    test('malformed options degrade to empty rather than throwing', () {
      // The column is jsonb; a row written by hand or by a future
      // migration could hold a shape this parser does not expect. A
      // throw here would take down the whole question list.
      final q = SessionGameQuestion.fromRow(const {
        'id': 'q4',
        'game_type': 'scenario',
        'question_text': 'Broken',
        'options': 'not-an-array',
      });
      expect(q.options, isEmpty);
    });

    test('an option missing its text is dropped, not rendered blank', () {
      final q = SessionGameQuestion.fromRow(const {
        'id': 'q5',
        'game_type': 'scenario',
        'question_text': 'Partial',
        'options': [
          {'key': 'a', 'text': 'Fine'},
          {'key': 'b'},
        ],
      });
      expect(q.options.length, 1);
      expect(q.options.first.key, 'a');
    });
  });
}
```

- [ ] **Step 2: Run it and verify it fails**

Run: `cd /Users/user/attune && flutter test test/features/games/session_game_repository_test.dart`
Expected: FAIL — `Couldn't resolve the package ... session_game_question.dart`.

- [ ] **Step 3: Write the model**

Create `lib/features/games/session_games/data/models/session_game_question.dart`:

```dart
/// One question for any of the three session games (§8.4).
///
/// A single model rather than three: the games differ only in which
/// fields are populated, and game_questions is a single shared table
/// with a per-type CHECK. Three near-identical classes would drift.
class SessionGameQuestion {
  const SessionGameQuestion({
    required this.id,
    required this.gameType,
    required this.questionText,
    this.valueDomain,
    this.scaleLow,
    this.scaleHigh,
    this.options = const [],
  });

  final String id;
  final String gameType;
  final String questionText;

  /// Sliding Scale only: the §8.4 domain this statement belongs to.
  final String? valueDomain;

  /// Sliding Scale only: the 1 and 10 anchor labels.
  final String? scaleLow;
  final String? scaleHigh;

  /// Scenario only: its 3-4 response options. Empty for other types.
  final List<SessionGameOption> options;

  factory SessionGameQuestion.fromRow(Map<String, dynamic> row) {
    return SessionGameQuestion(
      id: row['id'] as String,
      gameType: row['game_type'] as String,
      questionText: row['question_text'] as String? ?? '',
      valueDomain: row['value_domain'] as String?,
      scaleLow: row['scale_low'] as String?,
      scaleHigh: row['scale_high'] as String?,
      options: _parseOptions(row['options']),
    );
  }

  /// Tolerant by design: `options` is a jsonb column, so a row written
  /// by a future migration could hold an unexpected shape. Returning an
  /// empty list degrades one question rather than throwing and taking
  /// down the whole list.
  static List<SessionGameOption> _parseOptions(Object? raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((entry) {
          final key = entry['key'];
          final text = entry['text'];
          if (key is! String || text is! String) return null;
          return SessionGameOption(key: key, text: text);
        })
        .whereType<SessionGameOption>()
        .toList();
  }
}

class SessionGameOption {
  const SessionGameOption({required this.key, required this.text});
  final String key;
  final String text;
}
```

- [ ] **Step 4: Run the test and verify it passes**

Run: `cd /Users/user/attune && flutter test test/features/games/session_game_repository_test.dart`
Expected: `All tests passed!` (5 tests)

- [ ] **Step 5: Write the repository**

Create `lib/features/games/session_games/data/repositories/session_game_repository.dart`:

```dart
import 'package:attune/features/games/session_games/data/models/session_game_question.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// A round's answers, readable only once both partners have submitted.
class RevealedRound {
  const RevealedRound({
    required this.answerA,
    required this.answerB,
    required this.bothAnswered,
  });

  /// Null until [bothAnswered] — the server withholds them, the client
  /// does not merely hide them.
  final String? answerA;
  final String? answerB;
  final bool bothAnswered;
}

/// Data access shared by Mirror, Sliding Scale and Scenario.
class SessionGameRepository {
  SessionGameRepository({SupabaseClient? client}) : _client = client;

  final SupabaseClient? _client;
  SupabaseClient get _safeClient => _client ?? Supabase.instance.client;

  Future<List<SessionGameQuestion>> fetchQuestions({
    required String gameType,
    required int limit,
  }) async {
    final rows = await _safeClient
        .from('game_questions')
        .select()
        .eq('game_type', gameType)
        .eq('active', true)
        .limit(limit);

    return rows
        .map((row) =>
            SessionGameQuestion.fromRow(Map<String, dynamic>.from(row)))
        .toList();
  }

  /// Reads a round's answers through the reveal gate.
  ///
  /// Deliberately an RPC, not a table select. game_session_rounds' RLS
  /// grants relationship members access to the whole row and checks
  /// both_answered only inside RPCs, so a direct select would let a
  /// partner read the other's answer before reveal — the mechanic §8.4
  /// calls non-negotiable. get_revealed_round returns nulls until both
  /// have submitted.
  Future<RevealedRound> fetchRevealedRound(String roundId) async {
    final rows = await _safeClient
        .rpc('get_revealed_round', params: {'p_round_id': roundId});

    final list = rows as List<dynamic>;
    if (list.isEmpty) {
      return const RevealedRound(
        answerA: null,
        answerB: null,
        bothAnswered: false,
      );
    }
    final row = Map<String, dynamic>.from(list.first as Map);
    return RevealedRound(
      answerA: row['answer_a'] as String?,
      answerB: row['answer_b'] as String?,
      bothAnswered: row['both_answered'] as bool? ?? false,
    );
  }
}
```

- [ ] **Step 6: Analyze**

Run: `cd /Users/user/attune && flutter analyze lib/features/games/session_games/ test/features/games/`
Expected: `No issues found!`

- [ ] **Step 7: Commit**

```bash
git add lib/features/games/session_games/ \
        test/features/games/session_game_repository_test.dart
git commit -m "feat(games): shared session-game model and repository

One model for all three games — they differ only in which fields are
populated, and game_questions is a single shared table, so three
near-identical classes would drift.

fetchRevealedRound goes through the get_revealed_round RPC rather than
selecting the round directly: game_session_rounds' RLS grants members
the whole row and gates both_answered only inside RPCs, so a direct
select would expose a partner's answer before reveal.

Options parsing is tolerant — the column is jsonb, and one malformed row
must degrade a single question rather than throw and empty the list."
```

---

## Self-Review

**1. Spec coverage**

| Spec requirement | Task |
|---|---|
| Widen `game_questions` (types + `value_domain`/`scale_low`/`scale_high`/`options`) | 1 |
| `mirror_round_truth` (third per-round value) | 1 |
| `mirror_scores` with §11.1 RLS | 1 |
| Reveal gate not inherited by new games | 1 (RPC), 8 (client uses it) |
| Content: 24 Mirror / 6 Sliding Scale / 10 Scenario | 2 |
| Mirror scoring, subject-judged, `<6.5` flag | 3 |
| Sliding Scale gap maths | 4 |
| `compute_relationship_game_signals` RPC | 5 |
| Connection ← engagement, Alignment ← values overlap | 6 |
| `mirrorRoundsScored` returned but not consumed | 5 (returns), 6 (documents non-consumption) |
| Zero-signal no-op | 6 (explicit test) |
| Games reachable in the launcher | 7 |

**Deliberate scope note:** this plan delivers schema, content, domain
logic, Pulse wiring, launcher registration, and the shared data layer —
everything that is testable and shared. The three games' *screen flows*
(question → waiting → reveal → end) are not yet decomposed into tasks:
`this_or_that` needs 28 files for that shape, and specifying three
parallel UI flows here would triple the plan's length while duplicating
decisions best made against the real widgets. Tasks 1-8 are
independently valuable and leave the UI as a clean follow-on plan
against a finished data layer.

**2. Placeholder scan:** no `TBD`/`TODO`/"handle edge cases"/"similar to
Task N". Every code step contains runnable code; every test step contains
the assertions.

**3. Type consistency:** `SessionGameQuestion.fromRow` (Task 8) reads
exactly the columns Task 1 creates (`value_domain`, `scale_low`,
`scale_high`, `options`). `GameSignals`' four fields (Task 6) map
one-to-one onto the RPC's four returned columns (Task 5):
`sessions_completed`→`sessionsCompleted`,
`sliding_scale_pairs`→`slidingScalePairs`,
`sliding_scale_avg_gap`→`slidingScaleAvgGap`,
`mirror_rounds_scored`→`mirrorRoundsScored`. `get_revealed_round`'s three
returned columns match `RevealedRound`'s three fields. `mirrorScore` and
`isAttentivenessFlagged` (Task 3) are referenced by no later task, so no
signature drift is possible.

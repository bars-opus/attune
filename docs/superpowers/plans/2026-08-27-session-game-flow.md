# Session Game Flow Controller and Mirror Truth Path — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Mirror, Sliding Scale and Scenario playable — give Mirror somewhere to store the subject's truth and a way to judge a guess, then build the controller that drives a session from question to reveal to end.

**Architecture:** Mirror's round gains a second writer. The never-populated `game_session_rounds.active_partner_id` becomes the subject; `submit_session_game_answer` derives from `auth.uid()` whether your text is a truth (→ `mirror_round_truth`) or a guess (→ `answer_a`/`answer_b`), so the client never chooses. `both_answered` still flips only when both have written, leaving the reveal gate and its `FOR UPDATE OF r` race fix untouched. A Riverpod `AsyncNotifier` then owns one session's progression and supplies the `SessionGameQuestion` the routes read as `extra`.

**Tech Stack:** Supabase Postgres (`SECURITY DEFINER` RPCs, RLS), Flutter + Riverpod, GoRouter.

**Spec:** `docs/superpowers/specs/2026-08-27-session-game-flow-design.md`

**Predecessor plans:** `2026-08-27-session-games.md` (data layer, merged), `2026-08-27-session-games-ui.md` (screens, merged at `eb8ec647`)

## Global Constraints

- **Hidden reveal is non-negotiable (§8.4):** neither partner may see the other's answer before both submit. Answers are read ONLY through `get_revealed_round`. Never `.select()` and never `.stream()` `game_session_rounds` for answer data — its RLS is `FOR ALL` for relationship members, so both bypass the gate.
- **The client never decides where a Mirror write lands.** The RPC derives it from `auth.uid() = active_partner_id`. Do NOT add a `p_is_truth` parameter — that would move the decision to the client and make the guarantee a convention instead of a constraint.
- **§11.1 asymmetric data is self-facing only.** Two UI rules, both binding: the judging screen shows ONE round at a time with no counter, progress bar or running tally; the end screen takes only the viewer's own score and must not gain a partner-score parameter.
- **§11.2 no couple report:** no combined view, no "you matched N times together" framing.
- **Only the round's subject may judge it**, and only after `both_answered`.
- **`mirror_scores` is DERIVED, never incremented** — computed from `SUM(was_correct)` at completion so it is re-derivable and retry-safe.
- **RPC grant convention** (copy verbatim): `REVOKE ALL ON FUNCTION public.<name>(<args>) FROM PUBLIC, anon;` then `GRANT EXECUTE ON FUNCTION public.<name>(<args>) TO authenticated;`
- **Migration timestamps** must sort after `20260910130000` (the latest applied).
- **Never DROP an existing column or table.** All schema changes are additive.
- **Round count:** 8 rounds, subject alternating, so each partner guesses 4 times. Copy reads "You read them N of 4 times". `mirror_scores.score`'s `CHECK (score BETWEEN 0 AND 8)` is unchanged and still satisfied.

---

## File Structure

**New migration**
- `supabase/migrations/20260911120000_mirror_truth_and_judgement.sql` — `was_correct`/`judged_at` columns, the mirror branch in `submit_session_game_answer`, `judge_mirror_round`, and `finalise_mirror_scores`

**Modified repository**
- `lib/features/games/session_games/data/repositories/session_game_repository.dart` — fix `createSession`'s two defects, add `judgeRound`, `fetchMirrorTruth`, `completeSession`

**New Flutter**
- `lib/features/games/session_games/domain/session_game_flow_state.dart` — the state machine's states, pure and I/O-free
- `lib/features/games/session_games/presentation/providers/session_game_flow_provider.dart` — the `AsyncNotifier`
- `lib/features/games/mirror/presentation/screens/mirror_judge_screen.dart` — the Mirror-only judging step

**Modified Flutter**
- `lib/app/routing/app_router.dart` — routes build from the controller rather than `state.extra`
- `lib/features/chat/presentation/screens/chat_screen.dart` — restore the three cases to their own routes (LAST step, once there is something behind them)

The state machine is a separate I/O-free file from the notifier so its transitions are unit-testable without Supabase, mirroring how `mirror_scoring.dart` and `sliding_scale_gap.dart` were split in the predecessor plan.

---

## Task 1: Mirror truth, judgement, and derived score

**Files:**
- Create: `supabase/migrations/20260911120000_mirror_truth_and_judgement.sql`

**Interfaces:**
- Consumes: `game_session_rounds` (incl. the unused `active_partner_id`), `mirror_round_truth`, `mirror_scores`, `submit_session_game_answer` — all live
- Produces: `mirror_round_truth.was_correct boolean` / `.judged_at timestamptz`; RPC `public.judge_mirror_round(p_round_id uuid, p_was_correct boolean) RETURNS void`; RPC `public.finalise_mirror_scores(p_session_id uuid) RETURNS void`; `submit_session_game_answer` routing mirror writes by subject

- [ ] **Step 1: Write the migration**

Create `supabase/migrations/20260911120000_mirror_truth_and_judgement.sql`:

```sql
-- Mirror's third value, its judgement, and a derived score.
--
-- §8.4 gives Mirror three values per round: each partner's guess and the
-- subject's real answer. submit_session_game_answer writes only
-- answer_a/answer_b, and mirror_round_truth has no client write path at
-- all — so both_answered could flip on two guesses with no truth
-- recorded, and mirror_scores stayed empty. Mirror could never produce a
-- scoreable round.

-- ---------------------------------------------------------------------
-- 1. The judgement lives on the row that already exists per round
-- ---------------------------------------------------------------------

-- Nullable: NULL means "not yet judged". Keeping the judgement on
-- mirror_round_truth means one Mirror round is one row, with no second
-- table keyed on the same round_id and no second RLS policy to keep in
-- step.
ALTER TABLE public.mirror_round_truth
  ADD COLUMN IF NOT EXISTS was_correct boolean,
  ADD COLUMN IF NOT EXISTS judged_at timestamptz;

-- ---------------------------------------------------------------------
-- 2. submit_session_game_answer routes mirror writes by subject
--
-- The signature does NOT change. The function already looks up the round
-- and joins to relationships, so it can compare auth.uid() against
-- active_partner_id and derive the destination itself. That is the whole
-- point: the client keeps calling submitAnswer(roundId, answer) and
-- cannot write a truth row for a round it is not the subject of. A
-- p_is_truth parameter would move that decision to the client and turn a
-- constraint into a convention.
-- ---------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.submit_session_game_answer(
  p_round_id uuid,
  p_answer text
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_game_type text;
  v_user_a uuid;
  v_user_b uuid;
  v_is_a boolean;
  v_answer_a text;
  v_answer_b text;
  v_option_keys text[];
  v_subject_id uuid;
  v_truth_exists boolean;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  -- FOR UPDATE OF r locks the round row for the rest of this
  -- transaction. A concurrent caller blocks here and, under READ
  -- COMMITTED, re-reads the row once the lock is granted — so it sees
  -- the partner's committed answer rather than a stale NULL. Without it,
  -- two partners submitting at the same moment each read the other's
  -- slot as NULL, neither flips both_answered, and the round is stuck
  -- un-revealed forever.
  SELECT s.game_type, rel.user_a, rel.user_b, r.answer_a, r.answer_b,
         r.active_partner_id
    INTO v_game_type, v_user_a, v_user_b, v_answer_a, v_answer_b,
         v_subject_id
  FROM public.game_session_rounds r
  JOIN public.game_sessions s ON s.id = r.session_id
  JOIN public.relationships rel ON rel.id = s.relationship_id
  WHERE r.id = p_round_id
    AND (rel.user_a = v_user_id OR rel.user_b = v_user_id)
  FOR UPDATE OF r;

  IF v_game_type IS NULL THEN
    RAISE EXCEPTION 'Round not found';
  END IF;

  IF v_game_type NOT IN ('mirror', 'sliding_scale', 'scenario') THEN
    RAISE EXCEPTION 'Unsupported game type';
  END IF;

  IF v_game_type = 'sliding_scale' THEN
    IF p_answer !~ '^([1-9]|10)$' THEN
      RAISE EXCEPTION 'Rating must be an integer from 1 to 10';
    END IF;
  ELSIF v_game_type = 'scenario' THEN
    SELECT array_agg(opt->>'key')
      INTO v_option_keys
    FROM public.game_session_rounds r
    JOIN public.game_questions q ON q.id = r.question_id
    CROSS JOIN LATERAL jsonb_array_elements(q.options) AS opt
    WHERE r.id = p_round_id;

    IF v_option_keys IS NULL OR NOT (p_answer = ANY(v_option_keys)) THEN
      RAISE EXCEPTION 'Answer is not one of this question''s options';
    END IF;
  ELSE
    IF p_answer IS NULL OR char_length(trim(p_answer)) = 0 THEN
      RAISE EXCEPTION 'Answer cannot be empty';
    END IF;
    IF char_length(p_answer) > 400 THEN
      RAISE EXCEPTION 'Answer is too long';
    END IF;
  END IF;

  v_is_a := (v_user_a = v_user_id);

  -- Mirror, and this caller is the round's subject: their text is the
  -- TRUTH about themselves, not a guess, so it goes to
  -- mirror_round_truth rather than an answer slot.
  IF v_game_type = 'mirror' AND v_subject_id = v_user_id THEN
    IF EXISTS (
      SELECT 1 FROM public.mirror_round_truth WHERE round_id = p_round_id
    ) THEN
      RAISE EXCEPTION 'Answer already submitted';
    END IF;

    INSERT INTO public.mirror_round_truth (round_id, subject_id, truth_text)
    VALUES (p_round_id, v_user_id, p_answer);

    v_truth_exists := true;
  ELSE
    -- Everyone else — both partners in the other two games, and the
    -- guesser in Mirror — writes their own answer slot.
    IF v_is_a AND v_answer_a IS NOT NULL THEN
      RAISE EXCEPTION 'Answer already submitted';
    END IF;
    IF NOT v_is_a AND v_answer_b IS NOT NULL THEN
      RAISE EXCEPTION 'Answer already submitted';
    END IF;

    IF v_is_a THEN
      UPDATE public.game_session_rounds
         SET answer_a = p_answer,
             answer_a_submitted_at = now()
       WHERE id = p_round_id;
      v_answer_a := p_answer;
    ELSE
      UPDATE public.game_session_rounds
         SET answer_b = p_answer,
             answer_b_submitted_at = now()
       WHERE id = p_round_id;
      v_answer_b := p_answer;
    END IF;

    SELECT EXISTS (
      SELECT 1 FROM public.mirror_round_truth WHERE round_id = p_round_id
    ) INTO v_truth_exists;
  END IF;

  -- both_answered is derived here and nowhere else. For mirror the two
  -- writers are the truth row and the guesser's slot; for the other
  -- games they are the two answer slots. Either way the client has no
  -- path to this flag and cannot force an early reveal.
  IF v_game_type = 'mirror' THEN
    IF v_truth_exists AND (v_answer_a IS NOT NULL OR v_answer_b IS NOT NULL) THEN
      UPDATE public.game_session_rounds
         SET both_answered = true,
             reveal_triggered_at = COALESCE(reveal_triggered_at, now())
       WHERE id = p_round_id
         AND both_answered = false;
      RETURN true;
    END IF;
  ELSIF v_answer_a IS NOT NULL AND v_answer_b IS NOT NULL THEN
    UPDATE public.game_session_rounds
       SET both_answered = true,
           reveal_triggered_at = COALESCE(reveal_triggered_at, now())
     WHERE id = p_round_id
       AND both_answered = false;
    RETURN true;
  END IF;

  RETURN false;
END;
$$;

-- CREATE OR REPLACE resets privileges to the default, so the original
-- grants must be reapplied or this becomes a privilege regression.
REVOKE ALL ON FUNCTION public.submit_session_game_answer(uuid, text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.submit_session_game_answer(uuid, text)
  TO authenticated;

-- ---------------------------------------------------------------------
-- 3. Judging a revealed guess
--
-- §8.4: the subject marks whether their partner read them accurately.
-- Correctness is a subjective judgement and the subject is the only
-- authority on it — no string match or AI could stand in, since
-- "she's stressed about work" and "work has been overwhelming" are the
-- same answer.
-- ---------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.judge_mirror_round(
  p_round_id uuid,
  p_was_correct boolean
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_subject_id uuid;
  v_both_answered boolean;
  v_already_judged boolean;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  SELECT t.subject_id, r.both_answered, (t.was_correct IS NOT NULL)
    INTO v_subject_id, v_both_answered, v_already_judged
  FROM public.mirror_round_truth t
  JOIN public.game_session_rounds r ON r.id = t.round_id
  WHERE t.round_id = p_round_id
  FOR UPDATE OF t;

  IF v_subject_id IS NULL THEN
    RAISE EXCEPTION 'Round not found';
  END IF;

  -- Only the subject may judge: it is their own inner state that was
  -- being guessed at.
  IF v_subject_id <> v_user_id THEN
    RAISE EXCEPTION 'Only this round''s subject may judge it';
  END IF;

  -- Judging before the reveal would mean judging a guess you have not
  -- seen.
  IF NOT v_both_answered THEN
    RAISE EXCEPTION 'Round is not revealed yet';
  END IF;

  IF v_already_judged THEN
    RAISE EXCEPTION 'Round already judged';
  END IF;

  UPDATE public.mirror_round_truth
     SET was_correct = p_was_correct,
         judged_at = now()
   WHERE round_id = p_round_id;
END;
$$;

REVOKE ALL ON FUNCTION public.judge_mirror_round(uuid, boolean)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.judge_mirror_round(uuid, boolean)
  TO authenticated;

-- ---------------------------------------------------------------------
-- 4. mirror_scores is derived, never incremented
--
-- Computed from SUM(was_correct) so it is re-derivable and retry-safe.
-- An incrementing counter would be neither: a double-submit or a retry
-- would silently corrupt the total, and nothing could rebuild it.
--
-- The score belongs to the GUESSER — the partner who was not the
-- subject — since it measures how well they read the other person.
-- ---------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.finalise_mirror_scores(
  p_session_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_user_a uuid;
  v_user_b uuid;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  SELECT rel.user_a, rel.user_b
    INTO v_user_a, v_user_b
  FROM public.game_sessions s
  JOIN public.relationships rel ON rel.id = s.relationship_id
  WHERE s.id = p_session_id
    AND s.game_type = 'mirror'
    AND (rel.user_a = v_user_id OR rel.user_b = v_user_id);

  IF v_user_a IS NULL THEN
    RAISE EXCEPTION 'Session not found';
  END IF;

  -- One row per guesser. A round's guesser is whichever partner is NOT
  -- its subject, so the score counts the rounds where that person read
  -- their partner correctly.
  INSERT INTO public.mirror_scores (session_id, user_id, score, flagged)
  SELECT
    p_session_id,
    guesser.id,
    count(*) FILTER (WHERE t.was_correct)::int,
    -- §8.4: "below 6.5/8 = attentiveness flag". With the subject
    -- alternating across 8 rounds each partner guesses 4 times, so the
    -- proportional threshold is 6.5/8 of their own round count.
    (count(*) FILTER (WHERE t.was_correct)::numeric
       / NULLIF(count(*), 0)) < (6.5 / 8.0)
  FROM public.mirror_round_truth t
  JOIN public.game_session_rounds r ON r.id = t.round_id
  CROSS JOIN LATERAL (
    SELECT CASE WHEN t.subject_id = v_user_a THEN v_user_b
                ELSE v_user_a END AS id
  ) AS guesser
  WHERE r.session_id = p_session_id
    AND t.was_correct IS NOT NULL
  GROUP BY guesser.id
  ON CONFLICT (session_id, user_id) DO UPDATE
    SET score = EXCLUDED.score,
        flagged = EXCLUDED.flagged;
END;
$$;

REVOKE ALL ON FUNCTION public.finalise_mirror_scores(uuid)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.finalise_mirror_scores(uuid)
  TO authenticated;
```

- [ ] **Step 2: Apply and verify**

Run:
```bash
cd /Users/user/attune && supabase db push
supabase migration list | grep 20260911120000
```
Expected: applies cleanly; the timestamp appears in BOTH the Local and Remote columns. A clean apply proves the SQL parses and every referenced table, column and function exists.

Note: there is no local database and no psql in this environment. `supabase db reset` and `supabase db execute` do not work.

- [ ] **Step 3: Verify the grants and the derivation by reading back**

Run:
```bash
grep -c "GRANT EXECUTE ON FUNCTION" supabase/migrations/20260911120000_mirror_truth_and_judgement.sql
grep -c "p_is_truth" supabase/migrations/20260911120000_mirror_truth_and_judgement.sql
```
Expected: `3` grants (one per function, including the replaced one), and `0` occurrences of `p_is_truth` — the client must not be able to choose the destination.

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/20260911120000_mirror_truth_and_judgement.sql
git commit -m "feat(games): Mirror truth write path, judgement, and derived score

§8.4 gives Mirror three values per round, but the write path stored two
and mirror_round_truth had no client writer at all — so both_answered
could flip on two guesses with no truth recorded and Mirror could never
be scored.

submit_session_game_answer now DERIVES the destination from
auth.uid() = active_partner_id rather than taking a parameter, so the
client cannot write a truth row for a round it is not the subject of.
both_answered still needs two writers; for mirror those are the truth
row and the guesser's slot, so the reveal gate and its FOR UPDATE race
fix are unchanged.

judge_mirror_round is callable only by the round's subject, only after
reveal, and only once. finalise_mirror_scores DERIVES mirror_scores from
SUM(was_correct) rather than incrementing, so it is re-derivable and
retry-safe, and attributes each score to the guesser."
```

---

## Task 2: Repository — fix createSession, add the new calls

**Files:**
- Modify: `lib/features/games/session_games/data/repositories/session_game_repository.dart`
- Test: `test/features/games/session_game_flow_repository_test.dart`

**Interfaces:**
- Consumes: `judge_mirror_round`, `finalise_mirror_scores` (Task 1); existing `submitAnswer`, `fetchQuestions`, `fetchRounds`, `fetchRevealedRound`
- Produces: `SessionGameRepository.judgeRound({required String roundId, required bool wasCorrect})` → `Future<void>`; `.completeSession(String sessionId, {required String gameType})` → `Future<void>`; `.fetchMirrorTruth(String roundId)` → `Future<String?>`; `createSession` now takes `{required String relationshipId, required String initiatorId, required String gameType, required String partnerId}` with no `totalRounds`

- [ ] **Step 1: Write the failing test**

Create `test/features/games/session_game_flow_repository_test.dart`:

```dart
import 'package:attune/features/games/session_games/data/models/session_game_round.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SessionGameRound.subjectId', () {
    test('parses the round subject when present', () {
      // Mirror alternates whose inner state each round is about. The
      // controller needs that to decide whether this user writes a truth
      // or a guess, and whether they are the one who judges.
      final round = SessionGameRound.fromRow(const {
        'id': 'r1',
        'round_number': 1,
        'question_id': 'q1',
        'both_answered': false,
        'active_partner_id': 'user-a',
      });
      expect(round.subjectId, 'user-a');
    });

    test('subjectId is null for the non-Mirror games', () {
      // Sliding Scale and Scenario have no subject: both partners answer
      // the same prompt about the same thing.
      final round = SessionGameRound.fromRow(const {
        'id': 'r2',
        'round_number': 2,
        'question_id': 'q2',
        'both_answered': false,
      });
      expect(round.subjectId, isNull);
    });

    test('still carries no answer fields', () {
      // Regression guard on the reveal gate: a round model that could
      // hold answers would invite a direct table select, which RLS
      // permits and the gate never sees.
      final round = SessionGameRound.fromRow(const {
        'id': 'r3',
        'round_number': 3,
        'question_id': 'q3',
        'both_answered': false,
        'active_partner_id': 'user-a',
        'answer_a': 'leaked',
        'answer_b': 'leaked',
      });
      expect(round.toString(), isNot(contains('leaked')));
    });
  });
}
```

- [ ] **Step 2: Run it and verify it fails**

Run: `cd /Users/user/attune && flutter test test/features/games/session_game_flow_repository_test.dart`
Expected: FAIL — `The getter 'subjectId' isn't defined for the type 'SessionGameRound'`.

- [ ] **Step 3: Add subjectId to the round model**

In `lib/features/games/session_games/data/models/session_game_round.dart`, add the field to the class, the constructor, and `fromRow`:

```dart
  /// Whose inner state this round is about — Mirror only, null for the
  /// other two games. Mirror alternates it across the session, so the
  /// controller reads it to decide whether this user submits a truth or
  /// a guess, and who may judge the round afterwards.
  final String? subjectId;
```

Add `this.subjectId,` to the constructor's parameter list, and to `fromRow`:

```dart
      subjectId: row['active_partner_id'] as String?,
```

- [ ] **Step 4: Run the test and verify it passes**

Run: `cd /Users/user/attune && flutter test test/features/games/session_game_flow_repository_test.dart`
Expected: `All tests passed!` (3 tests)

- [ ] **Step 5: Fix createSession's two defects**

Replace the whole `createSession` method. Two changes: fetch questions BEFORE inserting the session, and derive `total_rounds` from what actually came back.

```dart
  /// Creates a session and its rounds.
  ///
  /// Questions are fetched BEFORE the session row is inserted. The old
  /// order committed a session, then fetched, then threw if nothing came
  /// back — stranding a zero-round session the user could neither play
  /// nor clear.
  ///
  /// total_rounds is derived from the questions actually returned, never
  /// from a caller's argument. Sliding Scale has only 6 seeded
  /// questions, so a caller asking for 8 would have written
  /// total_rounds = 8 against 6 real rounds and stranded the controller
  /// on round 7.
  Future<String> createSession({
    required String relationshipId,
    required String initiatorId,
    required String gameType,
    required String partnerId,
  }) async {
    const requestedRounds = 8;

    final questions = await fetchQuestions(
      gameType: gameType,
      limit: requestedRounds,
    );

    if (questions.isEmpty) {
      throw StateError('No questions available for $gameType');
    }

    final session = await _safeClient
        .from('game_sessions')
        .insert({
          'relationship_id': relationshipId,
          'initiator_id': initiatorId,
          'game_type': gameType,
          'tone': 'connecting',
          'status': 'active',
          'total_rounds': questions.length,
        })
        .select('id')
        .single();

    final sessionId = session['id'] as String;

    await _safeClient.from('game_session_rounds').insert([
      for (var i = 0; i < questions.length; i++)
        {
          'session_id': sessionId,
          'round_number': i + 1,
          'question_id': questions[i].id,
          // Mirror alternates the subject so each partner is guessed
          // about half the time. Null for the other games, which have
          // no subject.
          if (gameType == 'mirror')
            'active_partner_id': i.isEven ? initiatorId : partnerId,
        },
    ]);

    return sessionId;
  }
```

- [ ] **Step 6: Add the three new methods**

Append inside the same class:

```dart
  /// Records the subject's judgement of their partner's guess.
  ///
  /// Goes through judge_mirror_round, which enforces that only the
  /// round's subject may judge, only after the reveal, and only once.
  Future<void> judgeRound({
    required String roundId,
    required bool wasCorrect,
  }) async {
    await _safeClient.rpc(
      'judge_mirror_round',
      params: {'p_round_id': roundId, 'p_was_correct': wasCorrect},
    );
  }

  /// Marks a session complete and, for Mirror, derives its scores.
  ///
  /// finalise_mirror_scores recomputes from SUM(was_correct) rather than
  /// incrementing, so calling this twice is safe.
  Future<void> completeSession(
    String sessionId, {
    required String gameType,
  }) async {
    await _safeClient
        .from('game_sessions')
        .update({
          'status': 'completed',
          'completed_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', sessionId);

    if (gameType == 'mirror') {
      await _safeClient.rpc(
        'finalise_mirror_scores',
        params: {'p_session_id': sessionId},
      );
    }
  }

  /// The subject's own answer for a Mirror round, or null if not yet
  /// submitted.
  ///
  /// Safe to read directly: mirror_round_truth's RLS lets both partners
  /// SELECT it, which is deliberate — the truth is what the guess is
  /// revealed against, so both must see it at reveal. The reveal gate
  /// lives on the GUESS (get_revealed_round), and the caller must not
  /// display this before both_answered.
  Future<String?> fetchMirrorTruth(String roundId) async {
    final row = await _safeClient
        .from('mirror_round_truth')
        .select('truth_text')
        .eq('round_id', roundId)
        .maybeSingle();
    return row?['truth_text'] as String?;
  }
```

- [ ] **Step 7: Verify**

Run:
```bash
cd /Users/user/attune && flutter test test/features/games/
flutter analyze lib/features/games/session_games/
```
Expected: all tests pass; `No issues found!`

If a call site of `createSession` fails to compile because `totalRounds` is gone, that is expected — it has no production caller yet. Fix any test that constructs it.

- [ ] **Step 8: Commit**

```bash
git add lib/features/games/session_games/ test/features/games/session_game_flow_repository_test.dart
git commit -m "feat(games): repository support for the session-game flow

createSession now fetches questions BEFORE inserting the session and
derives total_rounds from what came back. The old order committed a
session then threw if no questions existed, stranding a zero-round
session; and a caller asking for 8 rounds of Sliding Scale (which has 6
seeded questions) would have written total_rounds = 8 against 6 real
rounds. It also assigns Mirror's alternating subject.

Adds judgeRound, completeSession and fetchMirrorTruth. SessionGameRound
gains subjectId from active_partner_id and still carries no answer
fields — a model that could hold answers would invite a direct table
select, which RLS permits and the reveal gate never sees."
```

---

## Task 3: The flow state machine (pure)

**Files:**
- Create: `lib/features/games/session_games/domain/session_game_flow_state.dart`
- Test: `test/features/games/session_game_flow_state_test.dart`

**Interfaces:**
- Consumes: nothing (pure, no I/O)
- Produces: `enum SessionGameStage { question, waiting, reveal, judge, end }`; `class SessionGameFlowState` with fields `stage`, `roundIndex`, `totalRounds`, `gameType`, `isSubject`, and methods `SessionGameStage stageAfterSubmit()`, `SessionGameStage stageAfterReveal()`, `bool get isLastRound`

- [ ] **Step 1: Write the failing test**

Create `test/features/games/session_game_flow_state_test.dart`:

```dart
import 'package:attune/features/games/session_games/domain/session_game_flow_state.dart';
import 'package:flutter_test/flutter_test.dart';

SessionGameFlowState stateFor({
  required String gameType,
  bool isSubject = false,
  int roundIndex = 0,
  int totalRounds = 8,
  SessionGameStage stage = SessionGameStage.question,
}) {
  return SessionGameFlowState(
    stage: stage,
    roundIndex: roundIndex,
    totalRounds: totalRounds,
    gameType: gameType,
    isSubject: isSubject,
  );
}

void main() {
  group('stageAfterSubmit', () {
    test('submitting always waits for the partner', () {
      for (final type in ['mirror', 'sliding_scale', 'scenario']) {
        expect(
          stateFor(gameType: type).stageAfterSubmit(),
          SessionGameStage.waiting,
          reason: type,
        );
      }
    });
  });

  group('stageAfterReveal', () {
    test('Mirror sends the SUBJECT to judge', () {
      // The subject is the only authority on whether their partner read
      // them accurately (§8.4), so only they get the judge step.
      expect(
        stateFor(gameType: 'mirror', isSubject: true).stageAfterReveal(),
        SessionGameStage.judge,
      );
    });

    test('Mirror does NOT send the guesser to judge', () {
      // The guesser must never judge their own guess — that would let a
      // user score themselves.
      expect(
        stateFor(gameType: 'mirror', isSubject: false).stageAfterReveal(),
        SessionGameStage.question,
      );
    });

    test('the other two games skip judging entirely', () {
      for (final type in ['sliding_scale', 'scenario']) {
        expect(
          stateFor(gameType: type, isSubject: true).stageAfterReveal(),
          SessionGameStage.question,
          reason: '$type has no subject and no judgement',
        );
      }
    });

    test('the last round ends instead of advancing', () {
      expect(
        stateFor(
          gameType: 'scenario',
          roundIndex: 7,
          totalRounds: 8,
        ).stageAfterReveal(),
        SessionGameStage.end,
      );
    });

    test('Mirror still judges on the last round before ending', () {
      // Dropping the final judgement would silently lose one mark from
      // the score.
      expect(
        stateFor(
          gameType: 'mirror',
          isSubject: true,
          roundIndex: 7,
          totalRounds: 8,
        ).stageAfterReveal(),
        SessionGameStage.judge,
      );
    });
  });

  group('isLastRound', () {
    test('true only on the final index', () {
      expect(stateFor(gameType: 'mirror', roundIndex: 6).isLastRound, isFalse);
      expect(stateFor(gameType: 'mirror', roundIndex: 7).isLastRound, isTrue);
    });

    test('handles a short session, not just the nominal 8', () {
      // Sliding Scale has only 6 seeded questions, so totalRounds is 6.
      expect(
        stateFor(gameType: 'sliding_scale', roundIndex: 5, totalRounds: 6)
            .isLastRound,
        isTrue,
      );
    });
  });
}
```

- [ ] **Step 2: Run it and verify it fails**

Run: `cd /Users/user/attune && flutter test test/features/games/session_game_flow_state_test.dart`
Expected: FAIL — `Couldn't resolve the package ... session_game_flow_state.dart`.

- [ ] **Step 3: Write the state machine**

Create `lib/features/games/session_games/domain/session_game_flow_state.dart`:

```dart
/// Where a session-game round currently is.
///
/// [judge] is Mirror-only and reached only by the round's subject —
/// §8.4 makes them the sole authority on whether their partner read them
/// accurately.
enum SessionGameStage { question, waiting, reveal, judge, end }

/// One session's progression, as pure data.
///
/// I/O-free and separate from the notifier so the transitions can be
/// unit-tested without Supabase, matching how mirror_scoring.dart and
/// sliding_scale_gap.dart were split out.
class SessionGameFlowState {
  const SessionGameFlowState({
    required this.stage,
    required this.roundIndex,
    required this.totalRounds,
    required this.gameType,
    required this.isSubject,
  });

  final SessionGameStage stage;

  /// Zero-based index of the current round.
  final int roundIndex;

  /// Derived from the questions actually fetched, never assumed to be 8 —
  /// Sliding Scale has only 6 seeded questions.
  final int totalRounds;

  final String gameType;

  /// Whether the viewer is this round's subject. Always false outside
  /// Mirror.
  final bool isSubject;

  bool get isLastRound => roundIndex >= totalRounds - 1;

  /// After submitting, you always wait: the partner has not answered yet,
  /// and the reveal gate will not open until they do.
  SessionGameStage stageAfterSubmit() => SessionGameStage.waiting;

  /// After the reveal, Mirror's subject judges the guess; everyone else
  /// moves on. The judge step comes BEFORE the end check so the final
  /// round's judgement is not silently dropped from the score.
  SessionGameStage stageAfterReveal() {
    if (gameType == 'mirror' && isSubject) return SessionGameStage.judge;
    if (isLastRound) return SessionGameStage.end;
    return SessionGameStage.question;
  }

  SessionGameFlowState copyWith({
    SessionGameStage? stage,
    int? roundIndex,
  }) {
    return SessionGameFlowState(
      stage: stage ?? this.stage,
      roundIndex: roundIndex ?? this.roundIndex,
      totalRounds: totalRounds,
      gameType: gameType,
      isSubject: isSubject,
    );
  }
}
```

- [ ] **Step 4: Run the test and verify it passes**

Run: `cd /Users/user/attune && flutter test test/features/games/session_game_flow_state_test.dart`
Expected: `All tests passed!` (7 tests)

- [ ] **Step 5: Commit**

```bash
git add lib/features/games/session_games/domain/session_game_flow_state.dart \
        test/features/games/session_game_flow_state_test.dart
git commit -m "feat(games): pure state machine for the session-game flow

I/O-free so the transitions are testable without Supabase. The judge
stage is Mirror-only and reached only by the round's subject — the
guesser must never judge their own guess. The judge check precedes the
end check so the final round's judgement is not dropped, and isLastRound
reads totalRounds rather than assuming 8, since Sliding Scale has only 6
seeded questions."
```

---

## Task 4: The judging screen

**Files:**
- Create: `lib/features/games/mirror/presentation/screens/mirror_judge_screen.dart`
- Test: `test/features/games/mirror_judge_screen_test.dart`

**Interfaces:**
- Consumes: nothing (presentational)
- Produces: `MirrorJudgeScreen({required String yourTruth, required String theirGuess, required ValueChanged<bool> onJudge})`

- [ ] **Step 1: Write the failing test**

Create `test/features/games/mirror_judge_screen_test.dart`:

```dart
import 'package:attune/features/games/mirror/presentation/screens/mirror_judge_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('shows your own answer beside their guess', (tester) async {
    await tester.pumpWidget(
      wrap(
        MirrorJudgeScreen(
          yourTruth: 'Work has been overwhelming',
          theirGuess: 'She is stressed about work',
          onJudge: (_) {},
        ),
      ),
    );
    expect(find.text('Work has been overwhelming'), findsOneWidget);
    expect(find.text('She is stressed about work'), findsOneWidget);
  });

  testWidgets('both verdicts report their value', (tester) async {
    final judgements = <bool>[];
    await tester.pumpWidget(
      wrap(
        MirrorJudgeScreen(
          yourTruth: 'truth',
          theirGuess: 'guess',
          onJudge: judgements.add,
        ),
      ),
    );

    await tester.tap(find.text('Yes'));
    await tester.pump();
    expect(judgements, [true]);

    await tester.tap(find.text('Not quite'));
    await tester.pump();
    expect(judgements, [true, false]);
  });

  testWidgets('renders no tally, counter or progress indicator', (
    tester,
  ) async {
    // §11.1 rule 1. The subject produces every mark that composes their
    // partner's score, so showing them a running total would hand them
    // the partner's score outright — the exact thing §11.1 forbids. A
    // later contributor would add a progress bar as an obvious
    // improvement; this test is what stops that.
    await tester.pumpWidget(
      wrap(
        MirrorJudgeScreen(
          yourTruth: 'truth',
          theirGuess: 'guess',
          onJudge: (_) {},
        ),
      ),
    );

    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.textContaining('of 4'), findsNothing);
    expect(find.textContaining('of 8'), findsNothing);
    expect(find.textContaining('correct'), findsNothing);
    expect(find.textContaining('score'), findsNothing);
  });
}
```

- [ ] **Step 2: Run it and verify it fails**

Run: `cd /Users/user/attune && flutter test test/features/games/mirror_judge_screen_test.dart`
Expected: FAIL — `Couldn't resolve the package ... mirror_judge_screen.dart`.

- [ ] **Step 3: Write the screen**

Create `lib/features/games/mirror/presentation/screens/mirror_judge_screen.dart`:

```dart
import 'package:flutter/material.dart';

/// Asks the subject whether their partner read them accurately (§8.4).
///
/// Deliberately shows ONE round and nothing else: no counter, no
/// progress bar, no running tally. The subject produces every mark that
/// composes their partner's score, so a running total would hand them
/// that score outright — precisely what §11.1 forbids ("never shown as a
/// judgment of the partner"). RLS hides the stored score from them; this
/// screen must not give it back.
class MirrorJudgeScreen extends StatelessWidget {
  const MirrorJudgeScreen({
    super.key,
    required this.yourTruth,
    required this.theirGuess,
    required this.onJudge,
  });

  /// What the subject said about themselves.
  final String yourTruth;

  /// What their partner guessed.
  final String theirGuess;

  /// true = read accurately.
  final ValueChanged<bool> onJudge;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('You said', style: textTheme.labelLarge),
          const SizedBox(height: 8),
          Text(yourTruth, textAlign: TextAlign.center),
          const SizedBox(height: 32),
          Text('They guessed', style: textTheme.labelLarge),
          const SizedBox(height: 8),
          Text(theirGuess, textAlign: TextAlign.center),
          const SizedBox(height: 40),
          Text('Did they read you right?', style: textTheme.titleMedium),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              OutlinedButton(
                onPressed: () => onJudge(false),
                child: const Text('Not quite'),
              ),
              const SizedBox(width: 16),
              FilledButton(
                onPressed: () => onJudge(true),
                child: const Text('Yes'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Run the test and verify it passes**

Run: `cd /Users/user/attune && flutter test test/features/games/mirror_judge_screen_test.dart`
Expected: `All tests passed!` (3 tests)

- [ ] **Step 5: Commit**

```bash
git add lib/features/games/mirror/presentation/screens/mirror_judge_screen.dart \
        test/features/games/mirror_judge_screen_test.dart
git commit -m "feat(games): Mirror judging screen

Shows the subject their own answer beside their partner's guess and asks
whether they were read right.

Deliberately renders one round and nothing else — no counter, no
progress bar, no running tally — with a test asserting their absence.
The subject produces every mark composing their partner's score, so a
running total would hand them that score outright, which §11.1 forbids.
RLS hides the stored score; this screen must not give it back."
```

---

## Task 5: The flow controller

**Files:**
- Create: `lib/features/games/session_games/presentation/providers/session_game_flow_provider.dart`
- Test: `test/features/games/session_game_flow_provider_test.dart`

**Interfaces:**
- Consumes: `SessionGameFlowState`/`SessionGameStage` (Task 3); `SessionGameRepository.createSession`, `.fetchRounds`, `.fetchQuestions`, `.submitAnswer`, `.judgeRound`, `.completeSession`, `.fetchMirrorTruth` (Task 2)
- Produces: `sessionGameFlowProvider` — an `AsyncNotifierProvider<SessionGameFlowNotifier, SessionGameFlowState>`; `class SessionGameFlowNotifier` with `Future<void> start({required String gameType, required String relationshipId, required String userId, required String partnerId})`, `Future<void> submit(String answer)`, `Future<void> judge(bool wasCorrect)`, `Future<void> advance()`

- [ ] **Step 1: Write the failing test**

Create `test/features/games/session_game_flow_provider_test.dart`:

```dart
import 'package:attune/features/games/session_games/domain/session_game_flow_state.dart';
import 'package:attune/features/games/session_games/presentation/providers/session_game_flow_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('isAlreadySubmitted', () {
    test('recognises the server\'s resubmission message', () {
      // "Answer already submitted" is NOT a failure: it is the normal
      // state of a user returning to a round they answered before
      // backgrounding the app or losing signal. Surfacing it as an error
      // would show a scary message on a round that is perfectly fine.
      expect(
        isAlreadySubmitted(Exception('Answer already submitted')),
        isTrue,
      );
    });

    test('does not swallow other failures', () {
      // A genuine failure must still surface — treating everything as
      // "already submitted" would hide real breakage.
      expect(isAlreadySubmitted(Exception('Round not found')), isFalse);
      expect(
        isAlreadySubmitted(Exception('Rating must be an integer from 1 to 10')),
        isFalse,
      );
      expect(isAlreadySubmitted(Exception('network unreachable')), isFalse);
    });
  });

  group('subjectOf', () {
    test('the viewer is the subject when the round names them', () {
      expect(subjectOf(subjectId: 'me', userId: 'me'), isTrue);
    });

    test('the viewer is not the subject when the round names the partner', () {
      expect(subjectOf(subjectId: 'them', userId: 'me'), isFalse);
    });

    test('a round with no subject makes nobody the subject', () {
      // Sliding Scale and Scenario have no subject at all; treating a
      // null as "you" would give both partners a judge step that should
      // not exist.
      expect(subjectOf(subjectId: null, userId: 'me'), isFalse);
    });
  });
}
```

- [ ] **Step 2: Run it and verify it fails**

Run: `cd /Users/user/attune && flutter test test/features/games/session_game_flow_provider_test.dart`
Expected: FAIL — `Couldn't resolve the package ... session_game_flow_provider.dart`.

- [ ] **Step 3: Write the notifier**

Create `lib/features/games/session_games/presentation/providers/session_game_flow_provider.dart`:

```dart
import 'package:attune/features/games/session_games/data/models/session_game_question.dart';
import 'package:attune/features/games/session_games/data/models/session_game_round.dart';
import 'package:attune/features/games/session_games/data/repositories/session_game_repository.dart';
import 'package:attune/features/games/session_games/domain/session_game_flow_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether a failure is the server's resubmission guard rather than a
/// real error.
///
/// The RPC raises for validation, membership and resubmission alike, and
/// they all arrive as one undifferentiated exception. "Answer already
/// submitted" is not a failure at all — it is what a user hits when they
/// return to a round they already answered after backgrounding the app,
/// navigating back, or retrying on a flaky connection. Treated as an
/// error it shows a scary message on a round that is perfectly fine.
bool isAlreadySubmitted(Object error) =>
    error.toString().contains('Answer already submitted');

/// Whether the viewer is this round's subject.
///
/// A null subjectId means the game has no subject (Sliding Scale,
/// Scenario), so nobody is — returning true there would give both
/// partners a judge step that should not exist.
bool subjectOf({required String? subjectId, required String userId}) =>
    subjectId != null && subjectId == userId;

final sessionGameRepositoryProvider = Provider<SessionGameRepository>(
  (ref) => SessionGameRepository(),
);

final sessionGameFlowProvider =
    AsyncNotifierProvider<SessionGameFlowNotifier, SessionGameFlowState>(
  SessionGameFlowNotifier.new,
);

/// Drives one session: question -> waiting -> reveal -> [judge] -> end.
///
/// Owns the session id, its rounds, and the fetched questions, and
/// supplies the SessionGameQuestion each screen renders. Nothing did
/// that before, which is why the routes read a null `extra` and every
/// game rendered "Question unavailable."
class SessionGameFlowNotifier extends AsyncNotifier<SessionGameFlowState> {
  late String _sessionId;
  late String _gameType;
  late String _userId;
  List<SessionGameRound> _rounds = const [];
  List<SessionGameQuestion> _questions = const [];

  SessionGameRepository get _repository =>
      ref.read(sessionGameRepositoryProvider);

  @override
  Future<SessionGameFlowState> build() async {
    // No session until start() is called. The routes render their own
    // empty state while this is the case.
    return const SessionGameFlowState(
      stage: SessionGameStage.question,
      roundIndex: 0,
      totalRounds: 0,
      gameType: '',
      isSubject: false,
    );
  }

  /// The question for the current round, or null before start().
  SessionGameQuestion? get currentQuestion {
    final current = state.value;
    if (current == null || _questions.isEmpty) return null;
    if (current.roundIndex >= _questions.length) return null;
    return _questions[current.roundIndex];
  }

  String? get currentRoundId {
    final current = state.value;
    if (current == null || _rounds.isEmpty) return null;
    if (current.roundIndex >= _rounds.length) return null;
    return _rounds[current.roundIndex].id;
  }

  Future<void> start({
    required String gameType,
    required String relationshipId,
    required String userId,
    required String partnerId,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      _gameType = gameType;
      _userId = userId;

      _sessionId = await _repository.createSession(
        relationshipId: relationshipId,
        initiatorId: userId,
        gameType: gameType,
        partnerId: partnerId,
      );

      _rounds = await _repository.fetchRounds(_sessionId);
      _questions = await _repository.fetchQuestions(
        gameType: gameType,
        limit: _rounds.length,
      );

      return SessionGameFlowState(
        stage: SessionGameStage.question,
        roundIndex: 0,
        // From the rounds actually created, never assumed — Sliding
        // Scale has only 6 seeded questions.
        totalRounds: _rounds.length,
        gameType: gameType,
        isSubject: subjectOf(
          subjectId: _rounds.isEmpty ? null : _rounds.first.subjectId,
          userId: userId,
        ),
      );
    });
  }

  Future<void> submit(String answer) async {
    final current = state.value;
    final roundId = currentRoundId;
    if (current == null || roundId == null) return;

    try {
      await _repository.submitAnswer(roundId: roundId, answer: answer);
    } catch (error) {
      // A returning user has already answered this round; that is the
      // normal path, not a failure. Anything else is real.
      if (!isAlreadySubmitted(error)) rethrow;
    }

    state = AsyncData(current.copyWith(stage: current.stageAfterSubmit()));
  }

  /// Called by the waiting screen once the reveal gate opens.
  void onRevealed() {
    final current = state.value;
    if (current == null) return;
    state = AsyncData(current.copyWith(stage: SessionGameStage.reveal));
  }

  Future<void> judge(bool wasCorrect) async {
    final current = state.value;
    final roundId = currentRoundId;
    if (current == null || roundId == null) return;

    await _repository.judgeRound(roundId: roundId, wasCorrect: wasCorrect);
    await advance();
  }

  /// Moves past the current round, ending the session on the last one.
  Future<void> advance() async {
    final current = state.value;
    if (current == null) return;

    if (current.isLastRound) {
      await _repository.completeSession(_sessionId, gameType: _gameType);
      state = AsyncData(current.copyWith(stage: SessionGameStage.end));
      return;
    }

    final nextIndex = current.roundIndex + 1;
    state = AsyncData(
      SessionGameFlowState(
        stage: SessionGameStage.question,
        roundIndex: nextIndex,
        totalRounds: current.totalRounds,
        gameType: current.gameType,
        // Mirror alternates the subject, so this is recomputed each
        // round rather than carried forward.
        isSubject: subjectOf(
          subjectId: _rounds[nextIndex].subjectId,
          userId: _userId,
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run the test and verify it passes**

Run: `cd /Users/user/attune && flutter test test/features/games/session_game_flow_provider_test.dart`
Expected: `All tests passed!` (5 tests)

- [ ] **Step 5: Verify the whole games suite and analyze**

Run:
```bash
cd /Users/user/attune && flutter test test/features/games/
flutter analyze lib/features/games/
```
Expected: all pass; no `error •` lines.

- [ ] **Step 6: Commit**

```bash
git add lib/features/games/session_games/presentation/providers/session_game_flow_provider.dart \
        test/features/games/session_game_flow_provider_test.dart
git commit -m "feat(games): session-game flow controller

An AsyncNotifier owning one session's progression and supplying the
SessionGameQuestion each screen renders — the gap that made the routes
read a null extra and every game render 'Question unavailable.'

totalRounds comes from the rounds actually created, and isSubject is
recomputed each round since Mirror alternates it. 'Answer already
submitted' is treated as the normal returning-user path rather than an
error, while every other failure still surfaces."
```

---

## Task 6: Wire the routes and the launcher

**Files:**
- Modify: `lib/app/routing/app_router.dart`
- Modify: `lib/features/chat/presentation/screens/chat_screen.dart`
- Test: `test/features/games/session_game_routing_test.dart`

**Interfaces:**
- Consumes: `sessionGameFlowProvider`, `SessionGameFlowNotifier` (Task 5); `MirrorJudgeScreen` (Task 4); the existing router, waiting, reveal and end screens
- Produces: the three games reachable and playable from the chat launcher

- [ ] **Step 1: Write the failing test**

Append to `test/features/games/session_game_routing_test.dart`:

```dart
  test('no session-game route depends on GoRouter extra', () async {
    // The previous branch shipped routes that read
    // `state.extra as SessionGameQuestion?` while every caller passed
    // nothing, so all three games rendered "Question unavailable." The
    // controller now supplies the question, so no route should read
    // extra at all — this asserts the regression cannot come back.
    final source = await File('lib/app/routing/app_router.dart').readAsString();

    // Scoped to the three game routes only: state.extra is used
    // legitimately by ~60 other routes in this file, so an unscoped
    // search would be permanently red. The window runs from the first
    // game route to the end of the last one — located by the next
    // GoRoute after it rather than a fixed character count, so the
    // assertion cannot silently under-scope if that route grows.
    final start = source.indexOf("name: 'mirrorGame'");
    final lastRoute = source.indexOf("name: 'scenarioGame'");
    final afterLast = source.indexOf('GoRoute(', lastRoute);
    final gameRouteBlock = source.substring(
      start,
      afterLast == -1 ? source.length : afterLast,
    );

    expect(start, isNot(-1), reason: 'mirrorGame route not found');
    expect(lastRoute, isNot(-1), reason: 'scenarioGame route not found');
    expect(gameRouteBlock.contains('state.extra'), isFalse);
    expect(gameRouteBlock.contains('Question unavailable'), isFalse);
  });
```

Add `import 'dart:io';` to that file's imports.

- [ ] **Step 2: Run it and verify it fails**

Run: `cd /Users/user/attune && flutter test test/features/games/session_game_routing_test.dart`
Expected: FAIL — the assertions find `state.extra` and `Question unavailable` still present.

- [ ] **Step 3: Rewrite the three route builders**

In `lib/app/routing/app_router.dart`, replace each of the three game route builders so it renders from the controller instead of `state.extra`. Each becomes a `Consumer` reading `sessionGameFlowProvider` and switching on the stage. Use this for `mirrorGame`, and the same shape with `'sliding_scale'` and `'scenario'` for the other two:

```dart
      GoRoute(
        path: RouteNames.mirrorGame,
        name: 'mirrorGame',
        builder: (context, state) =>
            const SessionGameFlowScaffold(gameType: 'mirror'),
      ),
```

Then delete the now-unused `_acknowledgeSessionGameAnswer` helper — the games are real now, so the placeholder acknowledgment it showed is obsolete.

- [ ] **Step 4: Create the scaffold that renders the current stage**

Create `lib/features/games/session_games/presentation/screens/session_game_flow_scaffold.dart`:

```dart
import 'package:attune/features/games/mirror/presentation/screens/mirror_judge_screen.dart';
import 'package:attune/features/games/session_games/domain/session_game_flow_state.dart';
import 'package:attune/features/games/session_games/presentation/providers/session_game_flow_provider.dart';
import 'package:attune/features/games/session_games/presentation/screens/session_game_end_screen.dart';
import 'package:attune/features/games/session_games/presentation/screens/session_game_reveal_screen.dart';
import 'package:attune/features/games/session_games/presentation/screens/session_game_router_screen.dart';
import 'package:attune/features/games/session_games/presentation/screens/session_game_waiting_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Renders whichever stage the flow controller is in.
///
/// One scaffold for all three games: they share waiting, reveal and end,
/// and differ only in how an answer is captured (handled by
/// SessionGameRouterScreen) and whether a judge step exists (Mirror
/// only).
class SessionGameFlowScaffold extends ConsumerWidget {
  const SessionGameFlowScaffold({super.key, required this.gameType});

  final String gameType;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(sessionGameFlowProvider);
    final notifier = ref.read(sessionGameFlowProvider.notifier);

    return Scaffold(
      appBar: AppBar(),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          // Never render the raw error: it can carry row contents.
          child: Text('Could not start this game. Please try again.'),
        ),
        data: (flow) {
          final question = notifier.currentQuestion;
          if (question == null) {
            return const Center(child: CircularProgressIndicator());
          }

          switch (flow.stage) {
            case SessionGameStage.question:
              return SessionGameRouterScreen(
                question: question,
                onSubmit: notifier.submit,
              );
            case SessionGameStage.waiting:
              return SessionGameWaitingScreen(
                roundId: notifier.currentRoundId!,
                onRevealed: notifier.onRevealed,
              );
            case SessionGameStage.reveal:
              return _RevealStage(notifier: notifier, flow: flow);
            case SessionGameStage.judge:
              return _JudgeStage(notifier: notifier);
            case SessionGameStage.end:
              return SessionGameEndScreen(
                onDone: () => Navigator.of(context).pop(),
              );
          }
        },
      ),
    );
  }
}
```

The two private stage widgets fetch what they need (`fetchRevealedRound`, and `fetchMirrorTruth` for the judge stage) and hand it to the existing screens. Write them in the same file, following the `FutureBuilder` shape already used elsewhere in this codebase, rendering a `CircularProgressIndicator` while loading and the same generic message on error.

- [ ] **Step 5: Restore the launcher**

In `lib/features/chat/presentation/screens/chat_screen.dart`, split the three games back out of the `gamesHub` fallthrough group and route them to their own routes. The result:

```dart
      case ChatGameDestination.gamesHub:
      case ChatGameDestination.thirtySixQuestions:
      case ChatGameDestination.neverHaveIEver:
        await context.pushNamed('gamesHub');
      case ChatGameDestination.mirror:
        await context.pushNamed('mirrorGame');
      case ChatGameDestination.slidingScale:
        await context.pushNamed('slidingScaleGame');
      case ChatGameDestination.scenario:
        await context.pushNamed('scenarioGame');
```

Remove the comment above them explaining why they pointed at the hub — it is no longer true.

- [ ] **Step 6: Verify**

Run:
```bash
cd /Users/user/attune && flutter test test/features/games/
flutter analyze lib/features/games/ lib/app/routing/app_router.dart \
  lib/features/chat/presentation/screens/chat_screen.dart
```
Expected: all tests pass; no `error •` lines.

A non-exhaustive-switch error on `ChatGameDestination` means a case was dropped — restore it. Do NOT add a `default:` clause.

- [ ] **Step 7: Commit**

```bash
git add lib/app/routing/app_router.dart \
        lib/features/chat/presentation/screens/chat_screen.dart \
        lib/features/games/session_games/presentation/screens/session_game_flow_scaffold.dart \
        test/features/games/session_game_routing_test.dart
git commit -m "feat(games): make the three session games playable

The routes render from the flow controller instead of GoRouter's extra,
which every caller left null — the reason all three games rendered
'Question unavailable' and the launcher was reverted to the games hub.
A test now asserts no game route reads extra, so that regression cannot
return.

The chat launcher points at the real games again, and the placeholder
'coming soon' acknowledgment is gone."
```

---

## Self-Review

**1. Spec coverage**

| Spec requirement | Task |
|---|---|
| `active_partner_id` becomes the subject; alternates | 1 (schema semantics), 2 (assignment in createSession) |
| RPC derives truth-vs-guess from `auth.uid()`, no client parameter | 1 |
| `both_answered` needs two writers, gate unchanged | 1 |
| `was_correct` / `judged_at` on `mirror_round_truth` | 1 |
| `judge_mirror_round` — subject only, post-reveal, once | 1 |
| `mirror_scores` derived from `SUM(was_correct)` | 1 |
| §11.1 rule 1: no tally on the judging screen | 4 (asserted by test) |
| §11.1 rule 2: end screen takes only the viewer's score | already true; Task 6 passes no partner score |
| `total_rounds` from questions fetched | 2 |
| `createSession` must not strand a session | 2 |
| "Answer already submitted" is a normal state | 5 |
| Flow controller supplies the question | 5, 6 |
| Launcher restored last | 6 |

**2. Placeholder scan:** no `TBD`/`TODO`/"handle edge cases"/"similar to Task N". Every code step carries runnable code; every test step carries its assertions. Task 6 Step 4 describes the two private stage widgets in prose rather than full code, because they must match the `FutureBuilder` shape of the surrounding file — the widgets they wrap, the loading state and the error copy are all specified.

**3. Type consistency:** `SessionGameRound.subjectId` (Task 2) is what `subjectOf` consumes (Task 5). `SessionGameFlowState`'s five constructor fields (Task 3) are exactly what the notifier constructs (Task 5). `MirrorJudgeScreen`'s three parameters (Task 4) match what the judge stage passes (Task 6). `judgeRound({roundId, wasCorrect})` (Task 2) matches `judge_mirror_round(p_round_id, p_was_correct)` (Task 1) and the notifier's call (Task 5). `completeSession(sessionId, {gameType})` (Task 2) matches Task 5's call.

**Known scope boundary:** the round count is 8 with the subject alternating, so each partner guesses 4 times and their score reads "N of 4". `mirror_scores.score`'s `CHECK (score BETWEEN 0 AND 8)` is unchanged and still satisfied. The spec records this as an open product question with three options; this plan implements option 1.

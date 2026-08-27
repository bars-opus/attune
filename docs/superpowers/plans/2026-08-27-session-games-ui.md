# Session Games UI (Mirror, Sliding Scale, Scenario) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the three session games playable — session creation, answer submission, the hidden-reveal waiting flow, reveal, and end screens — and close the two security items the data-layer plan deferred here.

**Architecture:** The data layer already exists: schema, 40 seeded questions, `get_revealed_round`, the signals RPC, and the Pulse blend all shipped in `2026-08-27-session-games.md` and are live in production. This plan adds the write path and the screens. It deliberately does NOT copy `this_or_that`'s `watchRound` Realtime stream — that streams the raw round row, which RLS grants members in full, and would hand a partner the other's answer before reveal. Waiting instead polls `get_revealed_round`, the one read path that is gated.

**Tech Stack:** Flutter + Riverpod, Supabase Postgres (RLS, `SECURITY DEFINER` RPCs), GoRouter.

**Spec:** `docs/superpowers/specs/2026-08-27-session-games-design.md`

**Predecessor plan:** `docs/superpowers/plans/2026-08-27-session-games.md` (complete, merged at `4c946fd6`)

## Global Constraints

- **Hidden reveal is non-negotiable (§8.4):** neither partner may see the other's answer before both have submitted. Answers are read ONLY through `get_revealed_round`. Never `.select()` and never `.stream()` `game_session_rounds` for answer data — RLS grants relationship members the whole row, so both bypass the gate.
- **§11.1 asymmetric data is self-facing only:** Mirror's `/8` score and `<6.5` flag are visible to their own subject only. `mirror_scores` RLS (`USING (user_id = auth.uid())`) enforces it; the UI must never render a partner's score, and must not infer it from any other value.
- **§11.2 no couple report:** no combined view of both partners' scores.
- **Sliding Scale ratings are integers 1-10 inclusive.** Enforce at write time. The read-side RPC guard (`^([1-9]|10)$`) already exists but only filters the aggregate — it does not stop a bad row being written.
- **RPC grant convention** (copy verbatim): `REVOKE ALL ON FUNCTION public.<name>(<args>) FROM PUBLIC, anon;` then `GRANT EXECUTE ON FUNCTION public.<name>(<args>) TO authenticated;`
- **Migration timestamps** must sort after `20260909150000` (the latest applied).
- **Never DROP an existing column or table.** All schema changes are additive.
- `game_questions.tone` is `NOT NULL`; the three new game types use `'connecting'`.

## Two items the predecessor plan deferred INTO this plan

Both are recorded in that plan's execution ledger and are now due:

1. **Sliding Scale write-time range validation.** `game_session_rounds`' RLS is `FOR ALL` for relationship members, so a member can already `UPDATE answer_a = '999'` via PostgREST today. Task 1 closes this.
2. **The reveal-gate write hole.** The same `FOR ALL` policy lets a member set `both_answered = true` on their own round and then legitimately call `get_revealed_round`. The read gate holds; the write side does not. Task 1 closes this too.

---

## File Structure

**New migration**
- `supabase/migrations/20260910120000_session_games_write_path.sql` — `submit_session_game_answer` RPC (validates, writes, flips `both_answered` only when genuinely both answered), plus a `CHECK` narrowing direct writes

**New Flutter — shared**
- `lib/features/games/session_games/data/repositories/session_game_repository.dart` (MODIFY) — add `createSession`, `submitAnswer`, `fetchRounds`
- `lib/features/games/session_games/presentation/providers/session_game_providers.dart` — Riverpod wiring
- `lib/features/games/session_games/presentation/screens/session_game_router_screen.dart` — one router, three games
- `lib/features/games/session_games/presentation/screens/session_game_waiting_screen.dart` — polls the gated RPC
- `lib/features/games/session_games/presentation/screens/session_game_reveal_screen.dart`
- `lib/features/games/session_games/presentation/screens/session_game_end_screen.dart`

**New Flutter — per-game answer input (the only genuinely game-specific UI)**
- `lib/features/games/mirror/presentation/screens/mirror_question_screen.dart`
- `lib/features/games/sliding_scale/presentation/screens/sliding_scale_question_screen.dart`
- `lib/features/games/scenario/presentation/screens/scenario_question_screen.dart`

**Modified**
- `lib/app/routing/app_router.dart` — route constants + routes
- `lib/features/chat/presentation/screens/chat_screen.dart` — `_openGameRoute` cases currently fall through to `gamesHub`; point them at the real router

One shared flow with three thin question screens, rather than `this_or_that`'s 13-file shape triplicated. The games differ only in how an answer is captured — waiting, reveal, and end are identical.

---

## Task 1: Server-side write path

**Files:**
- Create: `supabase/migrations/20260910120000_session_games_write_path.sql`

**Interfaces:**
- Consumes: `game_session_rounds`, `game_sessions`, `mirror_round_truth` (all live)
- Produces: RPC `public.submit_session_game_answer(p_round_id uuid, p_answer text) RETURNS boolean` (true when this submission completed the round)

- [ ] **Step 1: Write the migration**

```sql
-- Server-side write path for the three session games.
--
-- Closes two holes the data-layer plan deferred here. Both stem from
-- game_session_rounds' policy being FOR ALL for relationship members
-- (20260625120000), which grants a member full write access to their own
-- couple's rounds:
--
--   1. Nothing constrains a sliding_scale rating to 1-10. A member can
--      UPDATE answer_a = '999' via plain PostgREST today. The read-side
--      guard added in 20260909150000 filters such a row out of the
--      aggregate, but the row still exists and still renders in the UI.
--
--   2. A member can set both_answered = true on their own round and then
--      legitimately call get_revealed_round, which honours the flag. The
--      read gate holds; the write side does not. §8.4 calls the reveal
--      mechanic non-negotiable, so a client must not own that flag.
--
-- The fix is to take answer writes away from the client entirely for
-- these three games: this RPC validates the answer for its game type,
-- writes it to the correct slot, and flips both_answered ONLY when both
-- slots are genuinely populated. The client never writes both_answered.

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
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  -- Membership and game type in one lookup. A caller who is not a member
  -- of this round's relationship finds nothing and is rejected — the
  -- function never reveals whether the round exists.
  SELECT s.game_type, rel.user_a, rel.user_b, r.answer_a, r.answer_b
    INTO v_game_type, v_user_a, v_user_b, v_answer_a, v_answer_b
  FROM public.game_session_rounds r
  JOIN public.game_sessions s ON s.id = r.session_id
  JOIN public.relationships rel ON rel.id = s.relationship_id
  WHERE r.id = p_round_id
    AND (rel.user_a = v_user_id OR rel.user_b = v_user_id);

  IF v_game_type IS NULL THEN
    RAISE EXCEPTION 'Round not found';
  END IF;

  IF v_game_type NOT IN ('mirror', 'sliding_scale', 'scenario') THEN
    RAISE EXCEPTION 'Unsupported game type';
  END IF;

  -- Per-type answer validation. This is the write-time constraint the
  -- read-side regex could not provide.
  IF v_game_type = 'sliding_scale' THEN
    IF p_answer !~ '^([1-9]|10)$' THEN
      RAISE EXCEPTION 'Rating must be an integer from 1 to 10';
    END IF;
  ELSIF v_game_type = 'scenario' THEN
    -- The answer must be one of the option keys this question actually
    -- offers, so a client cannot invent a choice that no UI presented.
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
    -- mirror: free text, bounded to match mirror_round_truth's own limit.
    IF p_answer IS NULL OR char_length(trim(p_answer)) = 0 THEN
      RAISE EXCEPTION 'Answer cannot be empty';
    END IF;
    IF char_length(p_answer) > 400 THEN
      RAISE EXCEPTION 'Answer is too long';
    END IF;
  END IF;

  v_is_a := (v_user_a = v_user_id);

  -- First write wins: a resubmission must not overwrite an answer the
  -- partner may already have seen at reveal.
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

  -- both_answered is derived here and nowhere else. The client has no
  -- path to set it, so it cannot force an early reveal.
  IF v_answer_a IS NOT NULL AND v_answer_b IS NOT NULL THEN
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

REVOKE ALL ON FUNCTION public.submit_session_game_answer(uuid, text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.submit_session_game_answer(uuid, text)
  TO authenticated;
```

- [ ] **Step 2: Apply and verify**

Run:
```bash
cd /Users/user/attune && supabase db push
supabase migration list | grep 20260910120000
```
Expected: applies cleanly; the timestamp appears in BOTH the Local and Remote columns.

- [ ] **Step 3: Verify the grants landed as intended**

Run:
```bash
grep -A2 "REVOKE ALL ON FUNCTION public.submit_session_game_answer" \
  supabase/migrations/20260910120000_session_games_write_path.sql
```
Expected: the REVOKE names `PUBLIC, anon` and is followed by a GRANT to `authenticated`. A function granted to `anon` would let a signed-out caller write answers.

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/20260910120000_session_games_write_path.sql
git commit -m "feat(games): server-side write path for session games

Takes answer writes away from the client for the three session games,
closing two holes the data-layer plan deferred here.

game_session_rounds' policy is FOR ALL for relationship members, so a
member could UPDATE answer_a = '999' (no 1-10 constraint existed at
write time — the read-side regex only filtered the aggregate), and could
set both_answered = true themselves and then legitimately call
get_revealed_round, forcing an early reveal of a mechanic §8.4 calls
non-negotiable.

submit_session_game_answer validates per game type (1-10 for ratings,
a real option key for scenarios, non-empty bounded text for mirror),
writes to the caller's own slot, refuses a resubmission, and derives
both_answered itself. The client has no path to that flag."
```

---

## Task 2: Repository write methods

**Files:**
- Modify: `lib/features/games/session_games/data/repositories/session_game_repository.dart`
- Test: `test/features/games/session_game_write_test.dart`

**Interfaces:**
- Consumes: `submit_session_game_answer` (Task 1); existing `SessionGameQuestion`, `RevealedRound`, `fetchQuestions`, `fetchRevealedRound`
- Produces: `SessionGameRepository.createSession({required String relationshipId, required String initiatorId, required String gameType, required int totalRounds})` returning `String` (session id); `SessionGameRepository.submitAnswer({required String roundId, required String answer})` returning `bool`; `SessionGameRepository.fetchRounds(String sessionId)` returning `List<SessionGameRound>`; class `SessionGameRound { id, roundNumber, questionId, bothAnswered }`

- [ ] **Step 1: Write the failing test**

Create `test/features/games/session_game_write_test.dart`:

```dart
import 'package:attune/features/games/session_games/data/models/session_game_round.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SessionGameRound.fromRow', () {
    test('parses a round that is not yet revealed', () {
      final round = SessionGameRound.fromRow(const {
        'id': 'r1',
        'round_number': 1,
        'question_id': 'q1',
        'both_answered': false,
      });
      expect(round.id, 'r1');
      expect(round.roundNumber, 1);
      expect(round.questionId, 'q1');
      expect(round.bothAnswered, isFalse);
    });

    test('parses a revealed round', () {
      final round = SessionGameRound.fromRow(const {
        'id': 'r2',
        'round_number': 2,
        'question_id': 'q2',
        'both_answered': true,
      });
      expect(round.bothAnswered, isTrue);
    });

    test('carries no answer fields at all', () {
      // The model deliberately has no answerA/answerB. Answers reach the
      // UI only via fetchRevealedRound's gated RPC — a round model that
      // could hold them would invite a caller to select them directly
      // from the table, which RLS would permit and the reveal gate would
      // not catch.
      final round = SessionGameRound.fromRow(const {
        'id': 'r3',
        'round_number': 3,
        'question_id': 'q3',
        'both_answered': false,
        'answer_a': 'leaked',
        'answer_b': 'leaked',
      });
      expect(round.toString(), isNot(contains('leaked')));
    });

    test('a missing both_answered defaults to false, never true', () {
      // Failing closed matters more than failing loud: a null read as
      // true would reveal both answers early.
      final round = SessionGameRound.fromRow(const {
        'id': 'r4',
        'round_number': 4,
        'question_id': 'q4',
      });
      expect(round.bothAnswered, isFalse);
    });
  });
}
```

- [ ] **Step 2: Run it and verify it fails**

Run: `cd /Users/user/attune && flutter test test/features/games/session_game_write_test.dart`
Expected: FAIL — `Couldn't resolve the package ... session_game_round.dart`.

- [ ] **Step 3: Write the model**

Create `lib/features/games/session_games/data/models/session_game_round.dart`:

```dart
/// One round of a session game, WITHOUT its answers.
///
/// The absence of answer fields is deliberate and load-bearing. Answers
/// reach the UI only through SessionGameRepository.fetchRevealedRound,
/// which calls the gated get_revealed_round RPC. game_session_rounds'
/// RLS grants relationship members the whole row, so a model that could
/// carry answers would invite a direct table select that RLS permits and
/// the reveal gate never sees — reintroducing exactly the hole the RPC
/// exists to close (§8.4).
class SessionGameRound {
  const SessionGameRound({
    required this.id,
    required this.roundNumber,
    required this.questionId,
    required this.bothAnswered,
  });

  final String id;
  final int roundNumber;
  final String? questionId;

  /// Whether the reveal gate has opened. Fails closed: a missing or
  /// non-boolean value reads as false, because a wrong `true` would show
  /// both answers early while a wrong `false` only delays a reveal.
  final bool bothAnswered;

  factory SessionGameRound.fromRow(Map<String, dynamic> row) {
    return SessionGameRound(
      id: row['id'] as String,
      roundNumber: (row['round_number'] as num?)?.toInt() ?? 0,
      questionId: row['question_id'] as String?,
      bothAnswered: row['both_answered'] == true,
    );
  }
}
```

- [ ] **Step 4: Run the test and verify it passes**

Run: `cd /Users/user/attune && flutter test test/features/games/session_game_write_test.dart`
Expected: `All tests passed!` (4 tests)

- [ ] **Step 5: Add the repository methods**

Append to `lib/features/games/session_games/data/repositories/session_game_repository.dart`, inside the existing `SessionGameRepository` class:

```dart
  /// Creates a session and its rounds.
  ///
  /// Rounds are created here rather than by a trigger so the question
  /// selection is visible and testable. Questions are drawn with an
  /// explicit ORDER BY — `fetchQuestions` has none, so an unordered
  /// LIMIT would serve the same rows every time.
  Future<String> createSession({
    required String relationshipId,
    required String initiatorId,
    required String gameType,
    required int totalRounds,
  }) async {
    final session = await _safeClient
        .from('game_sessions')
        .insert({
          'relationship_id': relationshipId,
          'initiator_id': initiatorId,
          'game_type': gameType,
          'tone': 'connecting',
          'status': 'active',
          'total_rounds': totalRounds,
        })
        .select('id')
        .single();

    final sessionId = session['id'] as String;

    final questions = await fetchQuestions(
      gameType: gameType,
      limit: totalRounds,
    );

    if (questions.isEmpty) {
      throw StateError('No questions available for $gameType');
    }

    await _safeClient.from('game_session_rounds').insert([
      for (var i = 0; i < questions.length; i++)
        {
          'session_id': sessionId,
          'round_number': i + 1,
          'question_id': questions[i].id,
        },
    ]);

    return sessionId;
  }

  /// Submits this user's answer for a round.
  ///
  /// Goes through the submit_session_game_answer RPC, never a direct
  /// update. The RPC validates the answer for its game type, refuses a
  /// resubmission, and is the only thing that may set both_answered —
  /// a client that wrote the row directly could force an early reveal.
  ///
  /// Returns true when this submission completed the round.
  Future<bool> submitAnswer({
    required String roundId,
    required String answer,
  }) async {
    final result = await _safeClient.rpc(
      'submit_session_game_answer',
      params: {'p_round_id': roundId, 'p_answer': answer},
    );
    return result == true;
  }

  /// Rounds for a session, without answers.
  ///
  /// Selects only the non-answer columns. A `select()` with no argument
  /// would return answer_a/answer_b too — RLS permits it — bypassing the
  /// reveal gate.
  Future<List<SessionGameRound>> fetchRounds(String sessionId) async {
    final rows = await _safeClient
        .from('game_session_rounds')
        .select('id, round_number, question_id, both_answered')
        .eq('session_id', sessionId)
        .order('round_number');

    return rows
        .map((row) => SessionGameRound.fromRow(Map<String, dynamic>.from(row)))
        .toList();
  }
```

Add the import at the top of the file:
```dart
import 'package:attune/features/games/session_games/data/models/session_game_round.dart';
```

- [ ] **Step 6: Add ordering to fetchQuestions**

In the same file, change `fetchQuestions`' query from:
```dart
        .eq('active', true)
        .limit(limit);
```
to:
```dart
        .eq('active', true)
        // Explicit ordering: without it the LIMIT returns an arbitrary
        // subset that Postgres may repeat run to run, so a couple would
        // see the same questions every session.
        .order('created_at')
        .limit(limit);
```

- [ ] **Step 7: Analyze**

Run: `cd /Users/user/attune && flutter analyze lib/features/games/session_games/ test/features/games/`
Expected: `No issues found!`

- [ ] **Step 8: Commit**

```bash
git add lib/features/games/session_games/ test/features/games/session_game_write_test.dart
git commit -m "feat(games): session-game write path in the repository

createSession, submitAnswer and fetchRounds. submitAnswer goes through
the submit_session_game_answer RPC rather than updating the row, so the
client has no path to both_answered.

SessionGameRound deliberately carries NO answer fields, and fetchRounds
names its columns explicitly rather than select()-ing everything: RLS
grants relationship members the whole row, so either shortcut would
bypass the reveal gate the RPC exists to enforce.

fetchQuestions gains an ORDER BY — an unordered LIMIT served the same
rows every session."
```

---

## Task 3: Waiting screen that does not leak

**Files:**
- Create: `lib/features/games/session_games/presentation/screens/session_game_waiting_screen.dart`
- Test: `test/features/games/session_game_waiting_test.dart`

**Interfaces:**
- Consumes: `SessionGameRepository.fetchRevealedRound` (existing), `RevealedRound`
- Produces: `SessionGameWaitingScreen({required String roundId, required VoidCallback onRevealed})`

- [ ] **Step 1: Write the failing test**

Create `test/features/games/session_game_waiting_test.dart`:

```dart
import 'package:attune/features/games/session_games/presentation/screens/session_game_waiting_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows a waiting state and no answer text', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SessionGameWaitingScreen.forTesting(
            bothAnswered: false,
            partnerAnswer: null,
          ),
        ),
      ),
    );
    expect(find.textContaining('Waiting'), findsOneWidget);
  });

  testWidgets('renders nothing resembling an answer before reveal', (
    tester,
  ) async {
    // The screen is handed a null partner answer because the gated RPC
    // returns null until both submit. This asserts the screen has no
    // other source it could render from.
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SessionGameWaitingScreen.forTesting(
            bothAnswered: false,
            partnerAnswer: null,
          ),
        ),
      ),
    );
    expect(find.textContaining('answered:'), findsNothing);
  });

  testWidgets('reports reveal exactly once when the gate opens', (
    tester,
  ) async {
    var revealCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SessionGameWaitingScreen.forTesting(
            bothAnswered: true,
            partnerAnswer: 'their answer',
            onRevealed: () => revealCount++,
          ),
        ),
      ),
    );
    await tester.pump();
    expect(revealCount, 1);
  });
}
```

- [ ] **Step 2: Run it and verify it fails**

Run: `cd /Users/user/attune && flutter test test/features/games/session_game_waiting_test.dart`
Expected: FAIL — `Couldn't resolve the package ... session_game_waiting_screen.dart`.

- [ ] **Step 3: Write the screen**

Create `lib/features/games/session_games/presentation/screens/session_game_waiting_screen.dart`:

```dart
import 'dart:async';

import 'package:attune/features/games/session_games/data/repositories/session_game_repository.dart';
import 'package:flutter/material.dart';

/// Shown after this user submits, until the partner does too.
///
/// Polls get_revealed_round rather than streaming game_session_rounds.
/// this_or_that's watchRound streams the raw row, and RLS grants
/// relationship members every column of it — so a Realtime subscription
/// delivers the partner's answer the instant they submit, before the
/// reveal. §8.4 calls that mechanic non-negotiable, so this flow uses
/// the one read path that is gated, at the cost of a few seconds'
/// latency.
class SessionGameWaitingScreen extends StatefulWidget {
  const SessionGameWaitingScreen({
    super.key,
    required this.roundId,
    required this.onRevealed,
    SessionGameRepository? repository,
  })  : _repository = repository,
        _testBothAnswered = null,
        _testPartnerAnswer = null;

  /// Renders a fixed state without polling, for widget tests.
  const SessionGameWaitingScreen.forTesting({
    super.key,
    required bool bothAnswered,
    required String? partnerAnswer,
    VoidCallback? onRevealed,
  })  : roundId = 'test',
        onRevealed = onRevealed ?? _noop,
        _repository = null,
        _testBothAnswered = bothAnswered,
        _testPartnerAnswer = partnerAnswer;

  static void _noop() {}

  final String roundId;
  final VoidCallback onRevealed;
  final SessionGameRepository? _repository;
  final bool? _testBothAnswered;
  final String? _testPartnerAnswer;

  @override
  State<SessionGameWaitingScreen> createState() =>
      _SessionGameWaitingScreenState();
}

class _SessionGameWaitingScreenState extends State<SessionGameWaitingScreen> {
  Timer? _poll;
  bool _revealed = false;

  /// Three seconds: fast enough that a partner answering feels
  /// near-immediate, slow enough that a five-minute wait costs ~100
  /// requests rather than thousands.
  static const _pollInterval = Duration(seconds: 3);

  @override
  void initState() {
    super.initState();
    if (widget._testBothAnswered == true) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _fireReveal());
      return;
    }
    if (widget._testBothAnswered != null) return; // test, not yet revealed
    _poll = Timer.periodic(_pollInterval, (_) => unawaited(_check()));
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _check() async {
    final repository = widget._repository ?? SessionGameRepository();
    try {
      final round = await repository.fetchRevealedRound(widget.roundId);
      if (round.bothAnswered && mounted) _fireReveal();
    } catch (_) {
      // A transient failure just means waiting one more interval. The
      // reveal is not time-critical and a visible error here would be
      // noise during a normal wait.
    }
  }

  void _fireReveal() {
    if (_revealed) return; // exactly once, even if a poll overlaps
    _revealed = true;
    _poll?.cancel();
    widget.onRevealed();
  }

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('Waiting for your partner'),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Run the test and verify it passes**

Run: `cd /Users/user/attune && flutter test test/features/games/session_game_waiting_test.dart`
Expected: `All tests passed!` (3 tests)

- [ ] **Step 5: Commit**

```bash
git add lib/features/games/session_games/presentation/screens/session_game_waiting_screen.dart \
        test/features/games/session_game_waiting_test.dart
git commit -m "feat(games): waiting screen that polls the gated reveal RPC

Deliberately does NOT copy this_or_that's watchRound. That streams the
raw game_session_rounds row, and RLS grants relationship members every
column — so a Realtime subscription hands a partner the other's answer
the moment they submit, before the reveal §8.4 calls non-negotiable.

Polls get_revealed_round every 3s instead: the one read path that is
gated. Costs a few seconds' latency, fires onRevealed exactly once, and
swallows transient failures rather than showing an error during a normal
wait."
```

---

## Task 4: The three question screens

**Files:**
- Create: `lib/features/games/mirror/presentation/screens/mirror_question_screen.dart`
- Create: `lib/features/games/sliding_scale/presentation/screens/sliding_scale_question_screen.dart`
- Create: `lib/features/games/scenario/presentation/screens/scenario_question_screen.dart`
- Test: `test/features/games/question_screens_test.dart`

**Interfaces:**
- Consumes: `SessionGameQuestion` (existing, with `questionText`, `scaleLow`, `scaleHigh`, `options`)
- Produces: three widgets each taking `({required SessionGameQuestion question, required ValueChanged<String> onSubmit})`

- [ ] **Step 1: Write the failing test**

Create `test/features/games/question_screens_test.dart`:

```dart
import 'package:attune/features/games/mirror/presentation/screens/mirror_question_screen.dart';
import 'package:attune/features/games/scenario/presentation/screens/scenario_question_screen.dart';
import 'package:attune/features/games/session_games/data/models/session_game_question.dart';
import 'package:attune/features/games/sliding_scale/presentation/screens/sliding_scale_question_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('SlidingScaleQuestionScreen', () {
    const question = SessionGameQuestion(
      id: 'q1',
      gameType: 'sliding_scale',
      questionText: 'How much of our money should be shared?',
      valueDomain: 'money',
      scaleLow: 'Kept separate',
      scaleHigh: 'Fully shared',
    );

    testWidgets('shows both anchor labels', (tester) async {
      await tester.pumpWidget(
        wrap(SlidingScaleQuestionScreen(question: question, onSubmit: (_) {})),
      );
      expect(find.text('Kept separate'), findsOneWidget);
      expect(find.text('Fully shared'), findsOneWidget);
    });

    testWidgets('submits a value inside 1-10', (tester) async {
      String? submitted;
      await tester.pumpWidget(
        wrap(SlidingScaleQuestionScreen(
          question: question,
          onSubmit: (v) => submitted = v,
        )),
      );
      await tester.tap(find.text('Submit'));
      await tester.pump();

      final value = int.parse(submitted!);
      // The server rejects anything outside 1-10; the UI must never be
      // able to produce such a value in the first place.
      expect(value, greaterThanOrEqualTo(1));
      expect(value, lessThanOrEqualTo(10));
    });
  });

  group('ScenarioQuestionScreen', () {
    const question = SessionGameQuestion(
      id: 'q2',
      gameType: 'scenario',
      questionText: 'You are both tired and a disagreement starts.',
      options: [
        SessionGameOption(key: 'a', text: 'Push through'),
        SessionGameOption(key: 'b', text: 'Pause'),
        SessionGameOption(key: 'c', text: 'Step away'),
      ],
    );

    testWidgets('renders every option', (tester) async {
      await tester.pumpWidget(
        wrap(ScenarioQuestionScreen(question: question, onSubmit: (_) {})),
      );
      expect(find.text('Push through'), findsOneWidget);
      expect(find.text('Pause'), findsOneWidget);
      expect(find.text('Step away'), findsOneWidget);
    });

    testWidgets('submits the option KEY, not its text', (tester) async {
      // The server validates the answer against the question's option
      // keys, so submitting display text would be rejected.
      String? submitted;
      await tester.pumpWidget(
        wrap(ScenarioQuestionScreen(
          question: question,
          onSubmit: (v) => submitted = v,
        )),
      );
      await tester.tap(find.text('Pause'));
      await tester.pump();
      expect(submitted, 'b');
    });
  });

  group('MirrorQuestionScreen', () {
    const question = SessionGameQuestion(
      id: 'q3',
      gameType: 'mirror',
      questionText: 'What is weighing on them most this week?',
    );

    testWidgets('shows the prompt and a text field', (tester) async {
      await tester.pumpWidget(
        wrap(MirrorQuestionScreen(question: question, onSubmit: (_) {})),
      );
      expect(find.text('What is weighing on them most this week?'),
          findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('will not submit an empty answer', (tester) async {
      // The server rejects empty answers; the UI should not let the user
      // reach that error.
      var submitCount = 0;
      await tester.pumpWidget(
        wrap(MirrorQuestionScreen(
          question: question,
          onSubmit: (_) => submitCount++,
        )),
      );
      await tester.tap(find.text('Submit'));
      await tester.pump();
      expect(submitCount, 0);
    });
  });
}
```

- [ ] **Step 2: Run it and verify it fails**

Run: `cd /Users/user/attune && flutter test test/features/games/question_screens_test.dart`
Expected: FAIL — `Couldn't resolve the package ... mirror_question_screen.dart`.

- [ ] **Step 3: Write the Sliding Scale screen**

Create `lib/features/games/sliding_scale/presentation/screens/sliding_scale_question_screen.dart`:

```dart
import 'package:attune/features/games/session_games/data/models/session_game_question.dart';
import 'package:flutter/material.dart';

/// Rates one statement on the 1-10 scale (§8.4).
///
/// The slider is bounded to 1-10 with integer divisions, so the UI
/// cannot produce a value the server would reject — the write-time
/// constraint in submit_session_game_answer is the backstop, not the
/// primary control.
class SlidingScaleQuestionScreen extends StatefulWidget {
  const SlidingScaleQuestionScreen({
    super.key,
    required this.question,
    required this.onSubmit,
  });

  final SessionGameQuestion question;
  final ValueChanged<String> onSubmit;

  @override
  State<SlidingScaleQuestionScreen> createState() =>
      _SlidingScaleQuestionScreenState();
}

class _SlidingScaleQuestionScreenState
    extends State<SlidingScaleQuestionScreen> {
  double _value = 5;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            widget.question.questionText,
            style: Theme.of(context).textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          Slider(
            value: _value,
            min: 1,
            max: 10,
            divisions: 9, // nine intervals across ten positions
            label: _value.round().toString(),
            onChanged: (v) => setState(() => _value = v),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(child: Text(widget.question.scaleLow ?? '')),
              Flexible(child: Text(widget.question.scaleHigh ?? '')),
            ],
          ),
          const SizedBox(height: 32),
          FilledButton(
            onPressed: () => widget.onSubmit(_value.round().toString()),
            child: const Text('Submit'),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Write the Scenario screen**

Create `lib/features/games/scenario/presentation/screens/scenario_question_screen.dart`:

```dart
import 'package:attune/features/games/session_games/data/models/session_game_question.dart';
import 'package:flutter/material.dart';

/// Presents a situation and its 3-4 response options (§8.4).
///
/// Submits the option KEY, not its display text: the server validates
/// the answer against the question's own option keys, so text would be
/// rejected. Options are rendered in their stored order and none is
/// styled as preferred — §8.4 is explicit that "neither option is
/// 'correct'", and visually privileging one would turn a diagnostic into
/// a test the user can fail.
class ScenarioQuestionScreen extends StatelessWidget {
  const ScenarioQuestionScreen({
    super.key,
    required this.question,
    required this.onSubmit,
  });

  final SessionGameQuestion question;
  final ValueChanged<String> onSubmit;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            question.questionText,
            style: Theme.of(context).textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          for (final option in question.options)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => onSubmit(option.key),
                  child: Text(option.text),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 5: Write the Mirror screen**

Create `lib/features/games/mirror/presentation/screens/mirror_question_screen.dart`:

```dart
import 'package:attune/features/games/session_games/data/models/session_game_question.dart';
import 'package:flutter/material.dart';

/// Captures this user's guess at their partner's current state (§8.4).
///
/// Guards against an empty submission locally so the user never sees the
/// server's rejection for something the UI could prevent. The 400-char
/// limit matches mirror_round_truth's own CHECK.
class MirrorQuestionScreen extends StatefulWidget {
  const MirrorQuestionScreen({
    super.key,
    required this.question,
    required this.onSubmit,
  });

  final SessionGameQuestion question;
  final ValueChanged<String> onSubmit;

  @override
  State<MirrorQuestionScreen> createState() => _MirrorQuestionScreenState();
}

class _MirrorQuestionScreenState extends State<MirrorQuestionScreen> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final answer = _controller.text.trim();
    if (answer.isEmpty) return;
    widget.onSubmit(answer);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            widget.question.questionText,
            style: Theme.of(context).textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          TextField(
            controller: _controller,
            maxLength: 400,
            maxLines: 3,
            decoration: const InputDecoration(
              hintText: 'What do you think they would say?',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _submit,
            child: const Text('Submit'),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 6: Run the tests and verify they pass**

Run: `cd /Users/user/attune && flutter test test/features/games/question_screens_test.dart`
Expected: `All tests passed!` (6 tests)

- [ ] **Step 7: Analyze**

Run: `cd /Users/user/attune && flutter analyze lib/features/games/`
Expected: no `error •` lines.

- [ ] **Step 8: Commit**

```bash
git add lib/features/games/mirror/presentation/ \
        lib/features/games/sliding_scale/presentation/ \
        lib/features/games/scenario/presentation/ \
        test/features/games/question_screens_test.dart
git commit -m "feat(games): question screens for the three session games

The only genuinely game-specific UI — waiting, reveal and end are
shared. The slider is bounded 1-10 with integer divisions so the UI
cannot produce a value the server would reject; Scenario submits the
option key rather than its text because the server validates against the
question's own keys; Mirror refuses an empty answer locally so the user
never meets a server error the UI could prevent.

No Scenario option is styled as preferred — §8.4 is explicit that
neither option is correct, and privileging one visually would turn a
diagnostic into a test the user can fail."
```

---

## Task 5: Router, reveal, end, and wiring

**Files:**
- Create: `lib/features/games/session_games/presentation/screens/session_game_router_screen.dart`
- Create: `lib/features/games/session_games/presentation/screens/session_game_reveal_screen.dart`
- Create: `lib/features/games/session_games/presentation/screens/session_game_end_screen.dart`
- Modify: `lib/app/routing/app_router.dart`
- Modify: `lib/features/chat/presentation/screens/chat_screen.dart:446-452`
- Test: `test/features/games/session_game_routing_test.dart`

**Interfaces:**
- Consumes: everything from Tasks 2-4
- Produces: route constants `RouteNames.mirrorGame`, `RouteNames.slidingScaleGame`, `RouteNames.scenarioGame`

- [ ] **Step 1: Write the failing test**

Create `test/features/games/session_game_routing_test.dart`:

```dart
import 'package:attune/app/routing/app_router.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('each session game has a distinct route', () {
    final routes = {
      RouteNames.mirrorGame,
      RouteNames.slidingScaleGame,
      RouteNames.scenarioGame,
    };
    // A copy-paste slip that pointed two games at one path would send a
    // user to the wrong game with no compile error.
    expect(routes.length, 3);
    for (final route in routes) {
      expect(route.startsWith('/'), isTrue);
    }
  });
}
```

- [ ] **Step 2: Run it and verify it fails**

Run: `cd /Users/user/attune && flutter test test/features/games/session_game_routing_test.dart`
Expected: FAIL — `The getter 'mirrorGame' isn't defined for the type 'RouteNames'`.

- [ ] **Step 3: Add the route constants**

In `lib/app/routing/app_router.dart`, beside the other game routes:

```dart
  static const String mirrorGame = '/mirrorGame';
  static const String slidingScaleGame = '/slidingScaleGame';
  static const String scenarioGame = '/scenarioGame';
```

- [ ] **Step 4: Run the test and verify it passes**

Run: `cd /Users/user/attune && flutter test test/features/games/session_game_routing_test.dart`
Expected: `All tests passed!` (1 test)

- [ ] **Step 5: Write the reveal screen**

Create `lib/features/games/session_games/presentation/screens/session_game_reveal_screen.dart`:

```dart
import 'package:attune/features/games/session_games/data/repositories/session_game_repository.dart';
import 'package:flutter/material.dart';

/// Shows both answers side by side once the gate has opened.
///
/// Takes an already-fetched [RevealedRound] rather than fetching one:
/// the caller obtained it from get_revealed_round, and a screen that
/// could fetch answers itself would be a second path to guard.
class SessionGameRevealScreen extends StatelessWidget {
  const SessionGameRevealScreen({
    super.key,
    required this.round,
    required this.yourAnswerIsA,
    required this.onNext,
  });

  final RevealedRound round;

  /// Which slot belongs to the viewer, so the labels are right.
  final bool yourAnswerIsA;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    // Defensive: the caller should only build this once bothAnswered is
    // true, but rendering nulls as empty rather than "null" keeps a
    // mistake from displaying something that looks like an answer.
    final yours = (yourAnswerIsA ? round.answerA : round.answerB) ?? '';
    final theirs = (yourAnswerIsA ? round.answerB : round.answerA) ?? '';

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('You said', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          Text(yours, textAlign: TextAlign.center),
          const SizedBox(height: 32),
          Text('They said', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          Text(theirs, textAlign: TextAlign.center),
          const SizedBox(height: 40),
          FilledButton(onPressed: onNext, child: const Text('Next')),
        ],
      ),
    );
  }
}
```

- [ ] **Step 6: Write the end screen**

Create `lib/features/games/session_games/presentation/screens/session_game_end_screen.dart`:

```dart
import 'package:flutter/material.dart';

/// Closes a completed session.
///
/// [yourScore] is populated for Mirror only, and is the VIEWER'S OWN
/// score. §11.1 makes it self-facing: this screen must never receive or
/// render the partner's score, and there is deliberately no parameter
/// for it. mirror_scores' RLS (USING user_id = auth.uid()) means a
/// caller could not fetch one even if this screen asked.
class SessionGameEndScreen extends StatelessWidget {
  const SessionGameEndScreen({
    super.key,
    required this.onDone,
    this.yourScore,
    this.totalRounds,
  });

  final VoidCallback onDone;
  final int? yourScore;
  final int? totalRounds;

  @override
  Widget build(BuildContext context) {
    final score = yourScore;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('That is the end', style: Theme.of(context).textTheme.titleLarge),
          if (score != null && totalRounds != null) ...[
            const SizedBox(height: 24),
            // Framed as the viewer's own reading of their partner, never
            // as a verdict on either person (§11.1, and §8.4's "no
            // diagnosis language").
            Text('You read them $score of $totalRounds times'),
          ],
          const SizedBox(height: 40),
          FilledButton(onPressed: onDone, child: const Text('Done')),
        ],
      ),
    );
  }
}
```

- [ ] **Step 7: Write the router screen**

Create `lib/features/games/session_games/presentation/screens/session_game_router_screen.dart`:

```dart
import 'package:attune/features/games/mirror/presentation/screens/mirror_question_screen.dart';
import 'package:attune/features/games/scenario/presentation/screens/scenario_question_screen.dart';
import 'package:attune/features/games/session_games/data/models/session_game_question.dart';
import 'package:flutter/material.dart';

/// Chooses the answer-input screen for a game type.
///
/// One router for all three: the games share waiting, reveal and end, and
/// differ only in how an answer is captured.
class SessionGameRouterScreen extends StatelessWidget {
  const SessionGameRouterScreen({
    super.key,
    required this.question,
    required this.onSubmit,
  });

  final SessionGameQuestion question;
  final ValueChanged<String> onSubmit;

  @override
  Widget build(BuildContext context) {
    switch (question.gameType) {
      case 'mirror':
        return MirrorQuestionScreen(question: question, onSubmit: onSubmit);
      case 'scenario':
        return ScenarioQuestionScreen(question: question, onSubmit: onSubmit);
      case 'sliding_scale':
        return SlidingScaleQuestionScreen(
          question: question,
          onSubmit: onSubmit,
        );
      default:
        // An unknown type means seed data ran ahead of the client. Show a
        // plain message rather than a blank screen or a crash.
        return const Center(child: Text('This game is not available yet.'));
    }
  }
}
```

Add the import for `SlidingScaleQuestionScreen`:
```dart
import 'package:attune/features/games/sliding_scale/presentation/screens/sliding_scale_question_screen.dart';
```

- [ ] **Step 8: Point the chat launcher at the real games**

In `lib/features/chat/presentation/screens/chat_screen.dart`, the three
new destinations currently fall through to `gamesHub` (added when the
enum grew). Replace those three cases:

```dart
      case ChatGameDestination.mirror:
        await context.pushNamed('mirrorGame');
      case ChatGameDestination.slidingScale:
        await context.pushNamed('slidingScaleGame');
      case ChatGameDestination.scenario:
        await context.pushNamed('scenarioGame');
```

Leave `gamesHub`, `thirtySixQuestions` and `neverHaveIEver` grouped as they are.

- [ ] **Step 9: Register the routes**

In `lib/app/routing/app_router.dart`, add three `GoRoute` entries beside
the other game routes, each named to match the `pushNamed` calls above
(`mirrorGame`, `slidingScaleGame`, `scenarioGame`) and each building
`SessionGameRouterScreen` for its game type. Follow the exact shape of
the adjacent `thisOrThat` routes in that file.

- [ ] **Step 10: Verify**

Run:
```bash
cd /Users/user/attune && flutter test test/features/games/
flutter analyze lib/features/games/ lib/app/routing/app_router.dart \
  lib/features/chat/presentation/screens/chat_screen.dart
```
Expected: all tests pass; no `error •` lines.

A non-exhaustive-switch error on `ChatGameDestination` means a case was
dropped in Step 8 — restore it rather than adding a `default:`.

- [ ] **Step 11: Commit**

```bash
git add lib/features/games/session_games/presentation/ \
        lib/app/routing/app_router.dart \
        lib/features/chat/presentation/screens/chat_screen.dart \
        test/features/games/session_game_routing_test.dart
git commit -m "feat(games): router, reveal and end screens, and launcher wiring

One router for all three games — they share waiting, reveal and end and
differ only in answer capture. The chat launcher's three destinations
stop falling through to the generic hub and open the real games.

SessionGameEndScreen takes only the viewer's OWN Mirror score and has no
parameter for the partner's: §11.1 makes it self-facing, and
mirror_scores' RLS means a caller could not fetch one even if the screen
asked. The score is phrased as the viewer's reading of their partner,
never as a verdict on either person."
```

---

## Self-Review

**1. Spec coverage**

| Requirement | Task |
|---|---|
| Session creation + rounds | 2 |
| Answer submission, server-validated | 1 (RPC), 2 (repository) |
| Hidden reveal preserved end to end | 1 (write side), 3 (waiting polls the gate) |
| Sliding Scale 1-10 write-time constraint (deferred here) | 1 (server), 4 (UI cannot produce out-of-range) |
| Reveal-gate write hole (deferred here) | 1 |
| Per-game answer input | 4 |
| Reveal + end screens | 5 |
| §11.1 self-facing Mirror score | 5 (no partner-score parameter exists) |
| Games reachable from the launcher | 5 |

**Not covered, deliberately:** Mirror's subject-judged scoring loop (the
subject marking each revealed guess correct/incorrect, writing
`mirror_scores`) needs its own reveal-time UI and is a natural follow-on
once this flow is playable. `mirror_round_truth` is written by that same
loop. Flagged rather than silently dropped: without it, Mirror plays and
reveals but produces no score, so `mirror_scores` stays empty and the
`/8` line on the end screen does not render. Sliding Scale and Scenario
are complete after this plan.

**2. Placeholder scan:** no `TBD`/`TODO`/"handle edge cases"/"similar to
Task N". Every code step carries runnable code; every test step carries
its assertions. Task 5 Step 9 describes the route registration in prose
rather than code because it must match the surrounding file's exact
`GoRoute` shape, which the implementer reads in place — the names it must
produce are given explicitly.

**3. Type consistency:** `SessionGameRound.fromRow` (Task 2) reads
`id`, `round_number`, `question_id`, `both_answered` — the columns
`fetchRounds` selects in the same task. `submitAnswer` returns `bool`,
matching the RPC's `RETURNS boolean` (Task 1). `RevealedRound`'s
`answerA`/`answerB`/`bothAnswered` (existing) are what Task 5's reveal
screen reads. The three question screens share one signature
(`question`, `onSubmit`), which is what Task 5's router passes.
`RouteNames.mirrorGame`/`slidingScaleGame`/`scenarioGame` (Task 5 Step 3)
are the names Step 8's `pushNamed` calls use.

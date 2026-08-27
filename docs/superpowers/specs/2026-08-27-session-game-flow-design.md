# Session Game Flow Controller and Mirror Truth Write Path — Design

**Date:** 2026-08-27
**Status:** Approved, ready for implementation planning
**Spec reference:** `ATTUNE_MASTER_SPEC.md` §8.4 (Games & Connection), §11.1 and §11.2 (Permanent Constraints)

## Problem

Mirror, Sliding Scale and Scenario have schema, seeded content, a
server-side write path, a Pulse signal, and five screens — all shipped
and live. None of it is reachable. Two blockers stand between the built
pieces and a playable game.

**1. No flow controller.** Nothing supplies a `SessionGameQuestion`, and
nothing drives a round from question to reveal. The three GoRoutes read
`state.extra as SessionGameQuestion?`, and every caller passed nothing —
so every game rendered "Question unavailable." That regression is why
`2026-08-27-session-games-ui.md` reverted the chat launcher to point at
the games hub. `SessionGameWaitingScreen`, `SessionGameRevealScreen` and
`SessionGameEndScreen` have zero callers today (verified: only comments
in `app_router.dart` reference them).

**2. Mirror cannot be scored.** §8.4 gives Mirror three values per
round — each partner's guess and the subject's real answer — but
`submit_session_game_answer` writes only `answer_a`/`answer_b`.
`mirror_round_truth` exists and has no client write path anywhere in
`lib/` (verified: one doc comment, zero writes), and the RPC has no
parameter for a truth. So `both_answered` can flip on two guesses with
no truth recorded, `mirror_scores` stays empty, and the reveal would
show guess-against-guess rather than guess-against-truth. A flow
controller alone cannot fix this: the server contract itself is missing
half the game.

## Non-Goals

- **Love Map.** The fifth §8.4 game, still unspecced. Ongoing rather
  than session-based; its own spec.
- **Retuning Pulse weights.** `compute_relationship_game_signals`
  already reads completed sessions and Sliding Scale gaps. This design
  makes those signals real rather than changing how they score.
- **Closing the DB-level write hole.** `game_session_rounds`' RLS is
  `FOR ALL` for relationship members, so a partner can still forge
  `both_answered` via raw PostgREST. The app's write path avoids it;
  fixing the policy would break the three shipped games. Out of scope,
  named here so it is not mistaken for an oversight.

## Mirror's round shape

`game_session_rounds.active_partner_id` has existed since the 36Q
schema and is never populated. It becomes **the subject** — whose inner
state the round is about. `createSession` alternates it across the
rounds, so each partner is guessed about half the time.

One round then has two writers, and who you are decides where your
write lands:

| You are | You answer | Stored in |
|---|---|---|
| The subject (`active_partner_id`) | your own real state | `mirror_round_truth.truth_text` |
| The other partner | your guess about them | `answer_a` / `answer_b` |

The load-bearing property: **`both_answered` still flips only when both
partners have written.** The existing gate, the `FOR UPDATE OF r` race
fix, and `get_revealed_round` all work unchanged. Mirror stops being a
special case at the gate and becomes one only at the destination of the
write.

Sliding Scale and Scenario are unaffected — both partners answer the
same prompt, and `active_partner_id` stays null for their rounds.

## Server contract

### `submit_session_game_answer` gains a mirror branch

The signature does **not** change. The RPC already looks up the round
and joins to `relationships`, so it can compare `auth.uid()` against
`active_partner_id` and derive the destination itself.

That is the point: the client keeps calling
`submitAnswer(roundId, answer)` and never decides where the write goes,
so it cannot write a truth row for a round it is not the subject of.
Adding a `p_is_truth` parameter would move that decision to the client
and make the guarantee a convention instead of a constraint.

For `game_type = 'mirror'`:

- if `auth.uid() = active_partner_id` → upsert `mirror_round_truth`
  (`round_id`, `subject_id = auth.uid()`, `truth_text`)
- otherwise → write `answer_a`/`answer_b` as today
- `both_answered` becomes true when the truth row exists **and** the
  guesser's slot is populated — the same two-writer condition, read
  from two places

Validation matches the existing mirror rules: non-empty after trim, at
most 400 characters, which is `mirror_round_truth.truth_text`'s own
CHECK.

### `mirror_round_truth` gains a judgement

```sql
ALTER TABLE public.mirror_round_truth
  ADD COLUMN was_correct boolean,
  ADD COLUMN judged_at timestamptz;
```

Both nullable: null means *not yet judged*. The row already exists
per-round, keyed on `round_id`, and already holds the subject's own
data — so everything about one Mirror round lives in one row, with no
second table and no second RLS policy to keep in step.

### `judge_mirror_round(p_round_id uuid, p_was_correct boolean)`

A new `SECURITY DEFINER` RPC, following the existing grant convention
(`REVOKE ALL ... FROM PUBLIC, anon` then `GRANT EXECUTE ... TO
authenticated`).

- callable **only by that round's subject** — the person whose inner
  state it was is the only authority on whether they were read
  accurately (§8.4)
- refuses a re-judgement, the way answer submission refuses a
  resubmission
- refuses to judge a round that is not yet `both_answered` — judging
  before reveal would mean judging a guess you have not seen

### `mirror_scores` is derived, never incremented

Computed server-side from `SUM(was_correct)` over the session's rounds
when the session completes. Re-derivable, retry-safe, and auditable —
an incrementing counter would be none of those, and a double-submit
would silently corrupt the total.

## §11.1 — the real constraint

In Mirror, A guesses about B, and B judges whether A read them right.
The score therefore belongs to **A**, but **B** produces every mark
that composes it. B knows A's score by construction. No RLS policy can
change that: `mirror_scores`' `USING (user_id = auth.uid())` hides the
stored row from B, but B already watched themselves mark six of eight
wrong.

**This design mitigates rather than guarantees, and says so plainly.**
What it does guarantee is narrower and still worth having: the app
never states, totals, stores-readably, or displays A's score to B.

Two UI rules follow, and both belong here because a later contributor
would otherwise add them innocently as improvements:

1. **The judging screen shows one round at a time.** No counter, no
   progress bar, no "3 of 8 so far". The subject answers "did they read
   you right?" for the round in front of them and nothing else.
2. **The end screen takes only the viewer's own score.**
   `SessionGameEndScreen` already has no partner-score parameter and
   must not gain one. §11.2 also forbids a combined view, so no
   "you matched N times together" framing either.

## Flow controller

An `AsyncNotifierProvider` — 16 existing uses in this codebase, the
dominant idiom for async state — owning one session's progression:

```
question → waiting → reveal → [judge: Mirror only] → next round → end
```

It holds the session id, the ordered rounds, the current index, and the
fetched questions; it supplies the `SessionGameQuestion` the routes read
as `extra`. That is precisely the gap that made every game a dead end.

Sliding Scale and Scenario skip the judge state entirely.

Restoring the three `chat_screen.dart` cases to their own routes is the
**last** step, once there is something real behind them. Until then the
launcher keeps pointing at the games hub, as it does today.

### Two corrections the controller must carry

- **`total_rounds` must come from the questions actually fetched**, not
  from a caller's argument. Sliding Scale has exactly 6 seeded rows
  (verified) — one per §8.4 value domain, and the seed's dedupe is on
  `value_domain`, so it stays 6. A session created with
  `totalRounds: 8` would write `total_rounds = 8` against 6 real rounds
  and strand the controller on round 7.
- **`createSession` must not commit a session it cannot populate.**
  Today it inserts the session row, then fetches questions, then throws
  if none came back — stranding a zero-round session. Fetch first, or
  move both writes into one RPC.

### Error handling

`submitAnswer` returns a bare `bool`, and the RPC's distinct
`RAISE EXCEPTION` paths all arrive as an undifferentiated
`PostgrestException`. The controller must distinguish at least
**"Answer already submitted"**, which is not an error at all but the
normal state of a user returning to a round they already answered —
after backgrounding the app, navigating back, or retrying on a flaky
network. Treated as a failure it shows a scary message on a round that
is perfectly fine; the controller should advance to waiting instead.

## Testing

| Layer | Coverage |
|---|---|
| SQL contract | a non-subject cannot write a truth row; a non-subject cannot judge; judging before `both_answered` is refused; a second judgement is refused |
| SQL contract | `mirror_scores` derives from `SUM(was_correct)` and is re-derivable after a repeat run |
| Flutter unit | the state machine's transitions, including the Mirror-only judge step and the skip for the other two games |
| Flutter widget | §11.1 rule 1: the judging screen renders no tally, counter or progress indicator |
| Flutter widget | §11.1 rule 2: the end screen renders only the viewer's own score |
| Flutter unit | "Answer already submitted" advances to waiting rather than surfacing an error |

The first two rows matter beyond this feature: the spec's own Testing
table already required SQL contract tests for the reveal gate, and none
exist. These are the tests that would catch a future RLS regression.

## Open question for the product owner

**§8.4 says 8 rounds, and `mirror_scores.score` is
`CHECK (score BETWEEN 0 AND 8)` (verified).** But alternating the
subject gives each partner 4 rounds as guesser, so each person's score
is out of 4, not 8.

Three ways out, and this is a product call rather than a technical one:

1. **Run 8 rounds and show `/4`.** No schema change; the CHECK still
   holds since 4 ≤ 8. The copy says "You read them 3 of 4 times."
   *Recommended* — cheapest, and 8 rounds keeps §8.4's stated length.
2. **Run 16 rounds for a true `/8` each.** Doubles the session to
   roughly 20 minutes, against §8.4's "~10 minutes".
3. **Both partners guess every round about the same subject.** Gives
   `/8` each in 8 rounds but changes the game: nobody supplies a truth,
   so there is nothing to judge against.

The implementation plan assumes option 1 unless told otherwise.

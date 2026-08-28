# Love Map — Design

**Date:** 2026-08-28
**Status:** Approved, ready for implementation planning
**Spec reference:** `ATTUNE_MASTER_SPEC.md` §8.4 (Games & Connection),
§11.1 and §11.2 (Permanent Constraints)

## Problem

Love Map is the fifth §8.4 game and the only one with no
implementation of any kind — no schema, no seeded questions, no
screens. It appears in the master spec twice, in five lines:

> **Love Map** (ongoing — builds over time)
> - Tracks partner's evolving inner world: fears, dreams, current stressors
> - Questions refresh based on what the AI has detected in chat
> - Accumulates over months — cannot be completed in one session
> - Ongoing

Every other game is a sitting with a start and an end. Love Map is
not, and that single difference drives most of this design.

## Non-Goals

- **Retuning Pulse weights.** `compute_relationship_game_signals`
  reads completed sessions; Love Map has no sessions. Whether it
  should feed Pulse at all is deferred — see Open Questions.
- **Renaming Mirror's tables.** Love Map reuses
  `mirror_round_truth`, `judge_mirror_round` and `mirror_scores`. The
  names become historical rather than descriptive. Renaming live
  tables that already hold production rows is not worth the deploy
  risk; the mismatch is documented in the table comments instead.
- **AI-generated question text.** See "AI sourcing" — the model
  selects from a seeded bank and never writes a question.

## Cadence: a recurring prompt, not a session

Three questions surface per week per couple, answered whenever either
partner opens the card. The games hub shows coverage, not a session:

```
Love Map                    3 new ●
You know 34 of 60 answers
████████░░░░░░░░
```

This is the only one of the five games without a session. That is
deliberate: §8.4 says it "cannot be completed in one session," and
wrapping it in `game_sessions` would give it a `total_rounds` and a
completion state that contradict the spec. There is no session row,
no waiting screen, and no end screen.

**Why not reuse the session-games flow.** The flow controller built
in `2026-08-27-session-game-flow` owns a session's progression from
question to end. Love Map has no end. Forcing it through that
controller would mean either a permanently-incomplete session or a
weekly session that quietly reintroduces the sitting the spec
excludes.

## Mechanic: guess and truth, as in Mirror

Each question has a **subject** — the partner whose inner world it is
about — and a **guesser**. The subject answers about themselves; that
answer is the truth. The guesser guesses. Both are hidden until both
have answered (§8.4). The subject then judges whether they were read
right.

| You are | You answer | Stored in |
|---|---|---|
| The subject | your own real state | `mirror_round_truth.truth_text` |
| The other partner | your guess about them | `answer_a` / `answer_b` |

This is Mirror's exact shape, and it reuses Mirror's write path
rather than a parallel one — `submit_session_game_answer` already
derives the destination from `active_partner_id` and never lets the
client choose it. Duplicating that logic for Love Map would mean a
second copy of the §8.4 reveal gate to keep in step, which is the
precise shape of the C2 breach found in the session-games review.

The subject alternates question by question, so each partner is known
as often as they are knowing.

"Do you know what they're afraid of?" is the whole premise of a love
map, which is why the guess/truth mechanic is right here and a
mutual-disclosure format is not: two people answering the same
question about themselves measures overlap, not knowledge.

## Rounds without sessions

Love Map rounds are `game_session_rounds` rows whose `session_id` is
null, scoped instead by a new nullable `relationship_id`:

```sql
ALTER TABLE public.game_session_rounds
  ADD COLUMN relationship_id uuid REFERENCES public.relationships(id)
    ON DELETE CASCADE;

ALTER TABLE public.game_session_rounds
  ALTER COLUMN session_id DROP NOT NULL;

-- Exactly one owner: a session round, or a sessionless Love Map round.
ALTER TABLE public.game_session_rounds
  ADD CONSTRAINT game_session_rounds_owner_check
  CHECK (num_nonnulls(session_id, relationship_id) = 1);
```

Keeping Love Map in `game_session_rounds` is what allows the reveal
gate, the `FOR UPDATE OF r` race fix, `get_revealed_round` and the
truth branch to be reused unchanged. A separate table would fork all
four.

**This is the highest-risk part of the design, and it is larger than
it first appears.** `game_session_rounds` is not the session games'
table — it is shared by 36 Questions, this_or_that, paint ball and the
three session games. There are **29 sites** across 11 migrations that
reach a round through `session_id -> game_sessions -> relationship_id`,
and dropping `session_id`'s NOT NULL relaxes an invariant every one of
those callers currently relies on.

Each site must either gain a `relationship_id` branch or be proven
unreachable for Love Map rounds. A policy updated to read the new
column incorrectly widens access; one left unchanged silently excludes
Love Map rounds — and the second failure mode is the quieter of the
two, because it looks like the feature merely not working.

The implementation plan must enumerate all 29 with a per-site
disposition, and the SQL contract tests must cover the shared games
(36 Questions especially) to prove they are unaffected — not only
Love Map itself.

**An alternative worth pricing before committing:** give Love Map its
own rounds table and accept duplicating the reveal gate. This design
rejects that because a second copy of the gate is what produced C2 —
but that judgement was made against a 3-caller table, not a
29-site one shared by five games. If the plan's enumeration shows the
widening cannot be made safely, the duplication becomes the lesser
risk and this decision should be revisited rather than forced.

## Server contract

### `submit_session_game_answer` gains `love_map`

The RPC's allowlist is currently
`('mirror', 'sliding_scale', 'scenario')` and its truth branch is
gated on `v_game_type = 'mirror'`. Both widen:

- add `'love_map'` to the allowlist
- change the truth branch to
  `v_game_type IN ('mirror', 'love_map') AND v_subject_id = v_user_id`
- resolve the round's relationship from `relationship_id` when
  `session_id` is null

The signature does not change, and the client still never decides
where its answer lands.

### `judge_mirror_round` gains `love_map`

Same widening: the subject alone may judge, only after
`both_answered`, only once. Its membership check resolves the
relationship through either owner column.

### No score

Mirror scores because it is diagnostic — §8.4 sets an explicit
attentiveness flag below 6.5/8. Love Map accumulates instead, so
`finalise_mirror_scores` is **not** called for it and no
`mirror_scores` row is ever written with `game_type = 'love_map'`.

Coverage ("34 of 60 answered") is shown. Accuracy is not. A running
"you know them 62%" would turn an intimacy tool into a scoreboard,
and §11.1 already forbids showing one partner a number the other
produced. The per-round judgement still matters — it is what the
subject sees at reveal — it simply never totals.

## AI sourcing: the model selects, never writes

Questions refresh from what chat analysis already detects.
`analysis_sessions` carries `dominant_topic` and
`root_need_detected` per session and is indexed
`(relationship_id, started_at DESC)`.

The weekly refresh job:

1. reads recent `analysis_sessions` for the relationship
2. maps the most frequent `dominant_topic` to a seeded question's
   `value_domain`
3. picks unseen questions in that domain via `game_questions_seen`
4. falls back to ordinary rotation when no topic is detected

**The model never writes question text and no message content ever
reaches a question.** A generated question can quote or paraphrase
something one partner said in confidence and put it in front of the
other — a disclosure the speaker never chose to make. Selecting from
a seeded bank keeps the responsiveness while making that class of
leak structurally impossible rather than merely unlikely.

This also means Love Map degrades safely: with no analysis data, it
is a well-ordered fixed question bank.

### `game_questions` needs a `love_map` branch

`game_questions` carries a per-game-type CHECK: each type declares
which of the shared nullable columns it requires. Love Map needs its
own branch, alongside the existing five:

```sql
-- Love Map: a free-text prompt about the partner's inner world,
-- tagged with the domain the refresh job maps detected topics onto.
(game_type = 'love_map'
  AND question_subtype IS NULL
  AND value_domain IS NOT NULL)
```

`value_domain` is an unconstrained `text` column today (used by
Sliding Scale for its §8.4 domains), so Love Map's four domains need
no schema change beyond this branch — and requiring it NOT NULL is
what makes topic-to-question mapping possible at all.

The `game_type` allowlist on `game_questions` widens to include
`'love_map'` the same way `20260909120000` widened it for the session
games: drop the named constraint, re-add it with every existing branch
reproduced verbatim, so the change is provably a widening rather than
a relaxation.

### `game_questions_seen` must be widened first

Its `game_type` CHECK is still
`('this_or_that', 'truth_or_dare')` — the session games were never
added when they shipped. So rotation is currently unavailable to
Mirror, Sliding Scale and Scenario too, which is why
`fetchQuestions` documents that every couple gets the same top-N
questions forever.

This design widens the constraint to all six types, following the
same drop-and-replace-with-a-named-constraint pattern used for
`game_questions` in `20260909120000`. Rotation for the other three
games is a side effect, not a goal, and is called out here so it is
reviewed rather than discovered.

## §11.1 and §11.2

Love Map is asymmetric in the same way Mirror is: A guesses about B,
and B judges. B therefore knows how well A read them, by
construction, and no RLS policy changes that.

What the app guarantees is narrower and still worth having:

1. **No total is ever computed or displayed.** No score row, no
   percentage, no streak of correct guesses.
2. **Coverage is mutual, not comparative.** "34 of 60 answered"
   counts the couple's shared progress, never "you got 20, they got
   14."
3. **The judging surface shows one round at a time** — no counter, no
   history, no tally, matching the session-games rule.
4. **No combined view** (§11.2): there is no "your love map score
   together."

## Testing

| Layer | Coverage |
|---|---|
| SQL contract | a sessionless round resolves its relationship correctly in every widened policy — and a non-member still cannot read it |
| SQL contract | the owner CHECK rejects a round with both `session_id` and `relationship_id`, and one with neither |
| SQL contract | a non-subject cannot write a Love Map truth row, cannot judge, and cannot judge before `both_answered` |
| SQL contract | the reveal gate withholds a Love Map guess until both have answered |
| SQL contract | no `mirror_scores` row is ever written for `game_type = 'love_map'` |
| SQL contract | a `love_map` question without a `value_domain` is rejected, and the five existing game types' CHECK branches still hold (regression) |
| Flutter widget | the card renders coverage and never an accuracy figure |
| Flutter widget | the subject sees self-facing copy; the guesser sees third-person |
| Flutter unit | refresh falls back to plain rotation when no topic is detected |
| Flutter unit | a question is never selected twice for the same relationship |

The SQL rows are load-bearing rather than routine: this design widens
policies on a table that already enforces the §8.4 reveal gate, and
that gate has been breached once before (C2) by exactly this kind of
change.

**These tests cannot currently be executed** — the machine has no
Postgres and no container runtime, so `scripts/run_sql_contracts.sh`
has nothing to run against. Writing them unverified would repeat the
mistake that produced C2. Implementation of the SQL layer should not
be considered complete until they have actually been run.

## Open questions for the product owner

1. **Does Love Map feed Pulse?** Every other game does, via
   `compute_relationship_game_signals`, which keys on completed
   sessions. Love Map has none. Options: leave it out of Pulse
   entirely (simplest, and defensible — it is a connection tool, not
   a diagnostic); or feed a coverage-growth signal rather than an
   accuracy one. *Recommended: leave it out for now* and revisit once
   there is real usage data. Feeding an accuracy signal would
   contradict the no-score decision above.

2. **How many seeded questions at launch?** The coverage bar needs a
   denominator. 60 across four domains (fears, dreams, stressors,
   history) gives roughly five months at three per week. Fewer makes
   the map feel finishable, which §8.4 explicitly does not want.

3. **What happens at 100% coverage?** With a fixed bank the map
   eventually fills. Either the bank grows over time, or answered
   questions re-surface after some months on the grounds that a
   partner's fears change — which is arguably the entire point of a
   map that "tracks their *evolving* inner world." *Recommended: re-ask
   on a long interval*, which also makes the accumulating design
   genuinely endless rather than merely long.

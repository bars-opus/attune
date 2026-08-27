# Session Games: Mirror, Sliding Scale, Scenario — Design

**Date:** 2026-08-27
**Status:** Approved, ready for implementation planning
**Spec reference:** `ATTUNE_MASTER_SPEC.md` §8.4 (Games & Connection), §7 (Pulse), §11 (Permanent Constraints)

## Problem

§8.4 names five games. Only **36 Questions** is built. Three others —
Mirror Game, Sliding Scale, Scenario — are missing entirely, and the
fifth (Love Map) is deliberately out of scope here (see Non-Goals).

This is not only a feature gap. §7 lists "game engagement" as a data
source for the **Connection** dimension (22% of Pulse) and "values
overlap from games" for **Alignment** (18%). Verified against
`compute-pulse/index.ts`: it reads `psych_profiles`, `timeline_events`,
`weekly_checkins`, `pulse_scores` and the chat-signals RPC — **no game
table at all**. So 40% of the Pulse score is currently computed without
the game inputs its own specification claims. Sliding Scale is precisely
the values-overlap source Alignment is supposed to use.

## Non-Goals

- **Love Map.** §8.4 describes it as "ongoing — builds over time",
  "accumulates over months — cannot be completed in one session", with
  "questions refresh based on what the AI has detected in chat". It has
  no session, no round, and no reveal moment. Designing it alongside
  three round-based games would distort both. It gets its own spec.
- **Localisation of game content.** See Known Limitations.
- **Retuning existing Pulse weights.** Game signals are additive; the
  existing chat/timeline/check-in contributions are untouched.

## Architecture

### The engine already exists

`game_sessions` and `game_session_rounds` (from
`20260625120000_thirty_six_questions_journey.sql`) are already generic:

```
game_sessions        game_type text, status, total_rounds, current_round,
                     match_count, total_rounds_completed, ...
game_session_rounds  session_id, round_number, question_id,
                     answer_a, answer_b,
                     answer_a_submitted_at, answer_b_submitted_at,
                     both_answered, revealed_at, ...
```

All three built games — `this_or_that`, `truth_or_dare`, `paint_ball` —
use these tables with **zero tables of their own**. The hidden-reveal
mechanic §8.4 calls non-negotiable is already infrastructure, not
36Q-specific code.

Therefore all three new games are **additive extensions of the existing
engine**, not new subsystems. This is the central decision of this
design: nothing here rebuilds session, round, reveal, or invite
handling.

### Schema changes

**1. Widen `game_questions`.** It is already a shared content table with
a per-type CHECK (`game_type IN ('this_or_that','truth_or_dare')`) and
type-specific nullable columns. Extend the same way:

| Change | Purpose |
|---|---|
| `game_type` CHECK widened | add `mirror`, `sliding_scale`, `scenario` |
| `value_domain text` | Sliding Scale: money / children / independence / location / ambition / religion (§8.4's named list) |
| `scale_low text`, `scale_high text` | Sliding Scale: the 1 and 10 anchor labels |
| `options jsonb` | Scenario: its 3–4 response options, as `[{key, text}]` |
| New CHECK branch per game_type | mirrors the existing this_or_that / truth_or_dare branches |

`options` is `jsonb` rather than four nullable text columns because
Scenario's option count varies (3–4) and the existing `option_a`/
`option_b` pair cannot express that without adding columns that are
NULL for every other game type.

**2. Reuse `game_session_rounds` as-is.** `answer_a`/`answer_b` are
`text` and hold, per game: a guess (Mirror), a stringified 1–10 rating
(Sliding Scale), or an option key (Scenario). No migration needed.

**3. One new table — `mirror_round_truth`.** Mirror is the only game
where a round has **three** values, not two: A's guess, B's guess, and
the *subject's real answer*. That third value has nowhere to live in the
two-column round shape.

```
mirror_round_truth
  round_id    uuid PK REFERENCES game_session_rounds(id) ON DELETE CASCADE
  subject_id  uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE
  truth_text  text NOT NULL CHECK (char_length(truth_text) <= 400)
  submitted_at timestamptz NOT NULL DEFAULT now()
```

`subject_id` records whose inner state the round is about — Mirror
alternates, so both partners are guessed about across the 8 rounds.

**4. One new table — `mirror_scores`.** See §11.1 below; the score
cannot live on the shared session row.

### Scoring

`game_sessions.match_count` already exists and nothing currently writes
it. It is **deliberately left unused by Mirror**: it sits on the shared
session row, readable by both partners, so writing a per-person
attentiveness score there would leak asymmetric data by construction
(§11.1). Mirror's scores go to `mirror_scores`, which is
per-user and RLS-scoped. `match_count` remains available for a future
symmetric game where a shared "you matched on 6 of 8" figure is exactly
right.

Mirror correctness is a **subjective judgement**, not string equality:
the guess "she's stressed about work" against the truth "work has been
overwhelming" is a match. The subject marks each revealed guess
correct/incorrect — the person whose inner state it is, is the only
authority on whether it was read accurately. No AI, no fuzzy matching;
both would produce confidently wrong scores on exactly the answers that
matter most.

## §11.1: the one real design decision

Mirror produces asymmetric data by construction. §11 constraint 1 is
permanent:

> Asymmetric behavioural data — who pursues, whose NVC rate is higher,
> whose bid-toward rate is lower — is shown to each user about
> themselves only. Never shown as a judgment of the partner.
> **The pattern is shared. The role is private.**

A scoreboard reading "you 7/8, them 4/8" hands one partner evidence
about the other. That is precisely the judgment the constraint forbids.

**Resolution:**

| Visibility | Content |
|---|---|
| **Shared** | Every round's reveal — your guess beside their real answer. This *is* the game and stays fully mutual. |
| **Private (self only)** | Your `/8` tally and your `< 6.5` attentiveness flag. |
| **Never** | Your partner's score or flag, on any surface — including AI-generated insight copy. |

Enforced in **RLS, not UI**:

```
mirror_scores
  session_id uuid REFERENCES game_sessions(id) ON DELETE CASCADE
  user_id    uuid REFERENCES auth.users(id)    ON DELETE CASCADE
  score      int  NOT NULL CHECK (score BETWEEN 0 AND 8)
  flagged    boolean NOT NULL DEFAULT false
  PRIMARY KEY (session_id, user_id)

POLICY: USING (user_id = auth.uid())
```

A partner cannot read the other's row even with a direct PostgREST
query. The constraint survives any future client that forgets it —
which is the point of putting it in the database rather than a widget.

Sliding Scale and Scenario are symmetric (both answer the same prompt
about themselves), so §11.1 does not bind them.

## Pulse wiring

New RPC mirroring `compute_relationship_chat_signals` exactly — same
shape, same pre-aggregation so `compute-pulse` never selects raw game
rows into the edge function (Algorithm Quality Review Checklist 2.14),
same `REVOKE ALL FROM PUBLIC` + `GRANT EXECUTE TO service_role`:

```
compute_relationship_game_signals(p_relationship_id uuid,
                                  p_window_start timestamptz)
RETURNS TABLE (
  sessions_completed      int,     -- engagement, any game type
  sliding_scale_pairs     int,     -- statements both partners rated
  sliding_scale_avg_gap   double precision,  -- 0..9, lower = aligned
  mirror_rounds_scored    int
)
```

Consumed in `applyGameSignals`, following `applyChatSignals`'s existing
shape (weighted blend, minimum-evidence threshold, clamped):

- **Connection** ← `sessions_completed` (engagement)
- **Alignment** ← `sliding_scale_avg_gap`, inverted (small gap = high
  alignment), gated on `sliding_scale_pairs >= 4` so a single answered
  statement cannot move the score

`mirror_rounds_scored` is returned but **not consumed**: Mirror
accuracy is per-person, and feeding it into a shared relationship score
would leak an asymmetric signal into a mutually-visible number — §11.1
again, one step removed. It is returned for diagnostics only.

**Zero-signal no-op is a hard requirement.** A couple who never plays
must score *exactly* as they do today. This gets an explicit test,
mirroring the existing "no-op proof" test already in the compute-pulse
suite.

## Finding: the reveal gate is not enforced server-side

While tracing the reveal mechanic, verified: `game_session_rounds`'
RLS policy (`game_rounds_relationship_members`) grants relationship
members `FOR ALL` access to the whole row. `both_answered` is only ever
set and checked **inside RPCs** — it appears in no RLS policy, and there
is no column-level restriction or gated view.

So today a partner could read the other's `answer_a`/`answer_b` before
reveal with a direct PostgREST query, bypassing the client. §8.4 calls
this mechanic "non-negotiable — never remove it", and it is currently
enforced only by client good behaviour.

This is pre-existing and affects the three shipped games, so fixing it
for them is out of scope here. But **the new games must not inherit
it**: their answer reads go through a `SECURITY DEFINER` RPC that
returns the partner's answer only when `both_answered = true`, rather
than a direct table select. The existing hole is flagged for its own
follow-up.

## Content

Drafted as seed data in the migration, following the existing
`game_questions` seeding pattern (~100 rows already seeded there):

- **Mirror** — 24 prompts (3 sets of 8) about a partner's *current*
  state: stressors, wants, recent mood. Current-state, not trivia:
  §8.4 measures attentiveness now, not memory of facts.
- **Sliding Scale** — 6 statements, one per §8.4 domain (money,
  children, independence, location, ambition, religion), each with 1
  and 10 anchor labels.
- **Scenario** — 10 situations, 3–4 options each. Per §8.4 "neither
  option is 'correct'" — options are written as equally defensible, so
  the signal is the pattern across scenarios, not any single choice.

This is relationship-sensitive copy. It is drafted here for
completeness and flagged for review before merge.

## Testing

| Layer | Coverage |
|---|---|
| SQL contract | reveal gate: partner's answer unreadable before `both_answered`; `mirror_scores` RLS: partner's row unreadable, verified as a direct select, not a UI assertion |
| Deno | `compute_relationship_game_signals` shape and window filtering; `applyGameSignals` blend; **zero-signal no-op** |
| Flutter widget | per game: submit → wait → reveal; Mirror score visible to self and absent for partner |
| Flutter unit | Sliding Scale gap maths at boundaries (identical ratings → 0, 1-vs-10 → 9) |

## Known limitations

**Localisation.** `game_questions` is single-locale (English) while the
app ships 6 locales (en, de, es, fr, it, pt). 36Q solved this with a
`canonical` + `translations` split; `this_or_that` and `truth_or_dare`
did not, and serve English from the DB. This design follows the
`game_questions` precedent rather than introducing a translations layer
for three games while the two existing ones lack it — a partial
migration would leave the table in two shapes at once. Localising all
of `game_questions` is worth its own pass.

## Open questions

None. Both design decisions raised during brainstorming — scope
(Love Map deferred) and Mirror's §11.1 resolution (self-facing scores) —
were settled before this document was written.

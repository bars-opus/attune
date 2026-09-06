# ATTUNE - PAINT BALL GAME SPECIFICATION

**Version:** 2.0 (implementation-ready, aligned to live Games architecture)
**Created:** July 2026
**Last updated:** July 2026
**Status:** Ready for implementation by DeepSeek
**Part of:** Games Module - Game 4
**Builder:** DeepSeek
**Reviewer:** Claude (Opus) + Fable (design reasoning on the anti-cheat / penalty threat model)

**Related documents:**
- `ATTUNE_MASTER_SPEC.md`
- `ATTUNE_SOUL.md`
- `ATTUNE_PRINCIPLES_CHECKLIST.md`
- `ATTUNE_CLINICAL.md`
- `GAMES.md` (**the governing architecture doc — this spec extends it, never replaces it**)
- `TRUTH_OR_DARE.md`
- `../algorithms/algorithm_quality_review_checklist.md`

---

## HOW TO USE THIS DOCUMENT

This spec defines the Attune Paint Ball game end to end. It is a fast, playful,
**asynchronous, turn-based, server-authoritative** couples game inspired by
iMessage-style paintball, with a 3-life rule and a Truth or Dare penalty when a
player is knocked out.

**Read `GAMES.md` Section 5 (Shared Game Architecture) first.** Paint Ball is the
fourth game inside the *existing* shared session model. It does **not** invent its
own session infrastructure. Every rule in `GAMES.md` §5 (idempotency, concurrency,
auth, rate limiting, timeouts, error codes, observability, pagination) applies to
Paint Ball unchanged unless this spec explicitly overrides it. Where this spec and
`GAMES.md` conflict, `GAMES.md` wins and this spec must be reconciled.

Build in the exact order defined in **Section 13 — Build Order**.

---

## TABLE OF CONTENTS

1. Game Overview
2. What This Game Is For
3. Game Flow Overview
4. Session Lifecycle
5. Core Rules
6. Truth or Dare Penalty Layer
7. Screen Designs
8. Content, Tone, and Safety
9. Database Schema
10. Server RPC Contract
11. Auth, Idempotency, Concurrency, Rate Limiting, Errors
12. Edge Cases
13. Build Order
14. Notifications
15. Analytics Events
16. Algorithm Quality Checklist
17. Soul Document Compliance
18. Implementation Defaults

---

## 1. GAME OVERVIEW

### 1.1 What it is

Paint Ball is a quick, turn-based couple game that keeps the energy of
iMessage-style paintball: each player has 3 lives, takes turns firing paint
splashes, and loses a life when hit. When a player loses all 3 lives, the round
ends in a Truth or Dare penalty.

The mechanic is **simultaneous prediction**, not reflexes. Each turn you
choose where to hide on your own side and where to shoot on theirs. Once both
partners have taken their half, the round resolves: each shot is checked
against where the other actually hid *that same round*. You are guessing where
they will go, not where they were.

Then you watch it: both characters step out, aim, and fire at once — the
**replay** (§5.5), which is where the game stops being arithmetic and becomes
a scene. The skill is reading your partner — whether they repeat, and whether
they think you expect them to — which is the only kind of skill this app
should reward.

It is asynchronous: the two partners are on separate devices and do not need
to be online at the same time. Each half-round is a discrete, server-recorded
action, exactly like an answer in This or That — the duel only *looks*
simultaneous, which is the trick that lets a couple in two time zones play
one.

### 1.2 Core characteristics

| Characteristic | Value |
|----------------|-------|
| Duration | ~5 to 10 minutes |
| Players | 2 (asynchronous on separate devices) |
| Tone | Playful (default); Connecting and Romantic allowed |
| Lives | 3 per player |
| Core loop | Take turns firing paint splashes |
| Win condition | Opponent reaches 0 lives |
| Loss penalty | One **declinable** Truth or Dare prompt |
| Penalty source | App random (default) or partner-authored (optional) |
| Shot skill | Predicting where your partner will hide *this round*; **fully server-authoritative** |
| Motion | Reposition (out-across-in), aim tilt, paintball flight, round replay, knockout |
| Sound | Fire, hit, miss, knockout, penalty reveal |
| Visual language | Line schematic on black: arch shields, triangle players |
| Replayability | Reuses the shared Truth or Dare bank + seen tracking |

### 1.3 What makes it work for couples

- It is fast and light.
- It has tension without heavy stakes.
- It creates a clear reveal moment.
- It can end in conversation instead of just a score.
- It reuses the existing Attune Truth or Dare content and moderation system.

---

## 2. WHAT THIS GAME IS FOR

Paint Ball is not meant to feel like a harsh combat game. It should feel like a
playful back-and-forth with a little suspense. The UI stays intentionally minimal:
3 cover nodes per player, a triangle avatar, and short movement between cover and
firing position. Sound and animation do the heavy lifting; the visual language
stays simple.

### 2.1 Emotional job

- Create a burst of energy.
- Give couples a short shared challenge.
- Reward timing, anticipation, and nerve.
- Resolve into a relational prompt when someone loses.

### 2.2 Where it fits in Attune

- **Native tone:** Playful.
- **Allowed with warmth:** Connecting.
- **Allowed with light content only:** Romantic.
- **Off by default:** Spicy, Intimate. (Rationale in §8.1 — combat framing plus
  a forced penalty is the wrong container for high-intimacy content.)

---

## 3. GAME FLOW OVERVIEW

### 3.1 Complete flow diagram

```
Partner A initiates (game_type = 'paint_ball')
    │
    ▼
Selects tone (Playful default)
    │
    ▼
Creates game_sessions row (status: invited) via idempotent RPC
    │
    ▼
Partner B receives invite (push + in-app)
    │
    ├── Decline -> status: abandoned
    │
    └── Accept  -> status: active, both players start with 3 lives
                │
                ▼
         Turn 1: current_turn_user_id fires one paint splash
                │
                ├── Hit  -> defender loses exactly 1 life (server-enforced)
                └── Miss -> no life lost
                │
                ▼
         Turn passes to the other player (server sets current_turn_user_id)
                │
                ▼
         Alternate until one player reaches 0 lives
                │
                ▼
         Losing player receives ONE Truth or Dare penalty prompt
                │
                ├── Complete -> penalty recorded
                └── Decline  -> penalty recorded as declined (no punishment)
                │
                ▼
         status: completed, winner recorded, end screen shown to both
```

### 3.2 Turn structure

> **Revised 2026-09-05 (v3).**

A **round** is one exchange between both players and holds two halves. The
active player (`current_turn_user_id`) takes their half: reposition, aim,
fire. The round resolves only once both halves are in (§5.5).

From a player's seat the loop is:

```
open the game
  -> watch the previous round's replay   (if one completed since you last looked)
  -> reposition   (tap your cover)
  -> aim          (tap their cover)
  -> fire         (tap your triangle)
  -> if you closed the round, watch it resolve immediately
  -> wait
```

Neither player need be present at once. A round completing while you are away
is waiting as a replay when you return.

### 3.3 Game ending

The game ends when a player reaches 0 lives **and** the penalty step is resolved
(completed or declined) **and** the end screen is reachable by both players. The
session moves to `completed` only after the penalty row exists.

---

## 4. SESSION LIFECYCLE

Paint Ball uses the shared `game_sessions` lifecycle from `GAMES.md` §5.1
**unchanged**. It does not define its own states, expiration timers, or abandonment
cron.

### 4.1 States and transitions (inherited)

```
invited -> active     (partner accepts)
invited -> abandoned  (48h no response OR explicit decline)
active  -> completed  (loser reaches 0 lives AND penalty resolved)
active  -> abandoned  (24h inactivity OR partner unlinks relationship)
```

### 4.2 Expiration (inherited)

- Invitation expires after 48 hours with no response.
- Active session expires after 24 hours of inactivity on the current turn.
- Completed sessions remain readable in history and are hideable per-user via the
  existing `game_sessions.hidden_by_user_ids` array (soft delete, partner
  unaffected — same as This or That).
- Abandonment is handled by `public.expire_paint_ball_sessions()` (created in the
  Paint Ball migration). **Note:** there is no pre-existing *shared* cron — the
  only game expiry that existed was `expire-thirty-six-chapters`, hardcoded to
  36 Questions with a 7-day window measured from `started_at`. Paint Ball needs a
  24h inactivity window measured from **last activity** (latest round), not game
  age, so it has its own correct sweep. The `pg_cron` schedule is an operator
  deploy step (see the migration's scheduling note).

---

## 5. CORE RULES

### 5.1 Lives

- Each player starts with 3 lives (`lives_a = 3`, `lives_b = 3`).
- Every hit removes exactly 1 life from the defender.
- A player can never go below 0. The decrement is server-guarded:
  `... SET lives_x = lives_x - 1 WHERE lives_x > 0 ...` (see §10).
- The UI must always show current lives clearly and legibly.

### 5.2 Shots

- One shot per turn.
- A shot resolves to `hit` or `miss`.
- A hit removes one life from the opponent; a miss changes no life state.
- Either way, the turn advances to the other player.

### 5.3 Turn advance (server-authoritative)

- After a shot resolves, the server sets `current_turn_user_id` to the other
  player as part of the same transaction that records the round. The client never
  sets whose turn it is.
- A turn is taken via `paint_ball_take_turn` (§10). The RPC is idempotent on
  `(session_id, round_number)`: a duplicate call for a round that already resolved
  returns the existing result and does not double-advance or double-decrement.
- The RPC rejects a turn from anyone who is not the current `current_turn_user_id`
  (error `NOT_YOUR_TURN`).

### 5.4 Result reveal

- The client calls `paint_ball_take_turn` with its two chosen positions; the
  server returns the verdict. The flight animation plays *alongside* the
  request rather than before it, so the animation costs no waiting and never
  implies an outcome the server has not yet confirmed.
- The **life counter in `game_sessions` is the single source of truth.** Both
  clients render lives from the server row, never from local optimistic state that
  isn't reconciled.
- **State delivery (locked): both.** Subscribe to the `game_sessions` row via
  Supabase Realtime for live updates while the partner is present (same pattern
  This or That uses for reveal sync), **and** fetch the latest row on every
  open/reopen as the authoritative source. Realtime is the nicety; fetch-on-open is
  the guarantee — never rely on realtime alone, because a dropped subscription must
  not strand a player on stale state.

### 5.5 Shot resolution mechanic (simultaneous prediction)

> **Rewritten 2026-09-05 (v3).** Supersedes the v2 "hidden information"
> resolution, which itself replaced a v1 timing-tap. See the end of this
> section for what changed and why each version was retired.

Paint Ball is an **asynchronous simultaneous duel**. Neither player needs to
be online at the same time, yet each round resolves as though both fired at
once.

#### The round

A **round** is one exchange between *both* players — not one player's turn.
It has two halves, taken whenever each player next opens the app:

1. The **round opener** picks a hiding place and a target, then fires.
   Nothing resolves. The turn passes.
2. The **round closer** picks a hiding place and a target, then fires.
   **Now the round resolves.**

#### Resolution (symmetric)

Both shots are compared against the hide the *other* player chose **in that
same round**:

```
A hides LEFT,   shoots MIDDLE
B hides MIDDLE, shoots LEFT
  -> A's shot vs B's round hide (MIDDLE) = HIT
  -> B's shot vs A's round hide (LEFT)   = HIT
  Both lose a life.
```

Every outcome is possible: both hit, one hits, neither hits.

**Why same-round and not previous-round.** You are predicting where your
partner *will be this turn*, not where they were last turn. Resolving against
a stale position rewards pattern-matching a record; resolving against the
current one rewards reading the person. It also means round one can be a real
hit — if you call middle and they choose middle, that is a read, and the game
should honour it.

**Symmetry.** The opener's shot is locked before the closer chooses their
hide — but equally, the opener's *hide* is locked before the closer's shot.
Each player commits both decisions without sight of the other's. Neither
seat has an information advantage.

#### The opening round

Round one still resolves normally: both players choose a hide and a target,
and either may hit. `shot_result = 'opening'` is retired — it existed only
because v2 resolved against a previous hide that did not yet exist. There is
no longer a turn that cannot hit.

#### The replay

Because the round resolves only when both halves are in, neither player sees
the exchange live. The **replay** is where it is paid off, and it is the
centre of the game's feel.

When a round completes, both players see it animated in full: both triangles
emerge from their covers, step forward, tilt toward whatever each targeted,
and fire. Both paintballs travel simultaneously. Hits land, lives update.

**Both positions are revealed during the replay.** This is a deliberate
reversal of v2's rule that `hide_position` never reaches a client. It is safe
*and better* here because the round is already resolved — the information is
history, not a live secret. Learning that your partner broke left when they
were cornered is exactly the read this game exists to produce.

**After the replay ends, both triangles return to hiding.** Only your own
stays visible. The reveal is a moment, not a state.

**When each player sees it.** Each player sees a round's replay the first
time they open the game after that round completed:

- The **closer** sees it immediately after firing — they completed the round,
  so it resolves in front of them. They then open the next round.
- The **opener** sees it when they next open the game, *before* taking their
  half of the next round.

So the loop from a player's seat is: watch the previous round resolve →
reposition → aim → fire → wait.

#### Trust model — server-authoritative

Unchanged and non-negotiable. The server holds both hides, computes both
verdicts, and applies both life changes. A client cannot report a hit.

`get_paint_ball_session_state` returns `hide_position` **only for rounds that
have already resolved**. For a round with one half outstanding, the opener's
hide is withheld — otherwise the closer could read it and the prediction would
stop being one. The contract test asserts exactly this boundary: resolved
rounds expose both hides; unresolved rounds expose neither.

#### Version history

- **v1 — timing tap.** A target swept the screen; a tap inside a window
  scored a hit, computed on the client and trusted by the server. Retired
  because a reaction test measures reflexes, which say nothing about the
  person you are playing, and because it played thinly.
- **v2 — hidden information, previous-round resolution.** Introduced hiding
  and prediction, moved resolution to the server, and never revealed a hide.
  Retired because resolving against a *stale* position made the read a matter
  of recalling a record rather than anticipating a person, and because
  withholding every hide forever meant the game never showed you what
  happened — there was no scene, only arithmetic.
- **v3 — simultaneous, with replay.** Current.

The v2 argument for never revealing a hide was sound while a revealed hide
would leak a *live* secret. It stopped applying once resolution became
simultaneous: after both halves are in, a hide is a completed fact, and
showing it is what turns a turn into a moment.

## 6. TRUTH OR DARE PENALTY LAYER

When a player loses all 3 lives, the game resolves into one Truth or Dare prompt
for the loser. This is what makes Paint Ball feel like Attune rather than a generic
arcade toy — and it is where the entire safety model lives.

### 6.1 Penalty rule

- The losing player is shown **one** Truth or Dare prompt immediately after the
  knockout animation.
- **On a draw (double knockout, §10.3) both players get a prompt** — each
  their own, drawn independently. The framing is mutual, never "you both
  lost": copy reads "You got each other." Both prompts are declinable on the
  same terms, and one player declining says nothing about the other.
- The prompt step must be **resolved** (completed or declined) by every player
  who has one before the session becomes `completed`.
- **The prompt is always declinable.** Declining is a first-class outcome, not a
  failure: no punishment, no re-prompt loop, no streak, no "you owe me" ledger, no
  nag. Declining records `penalty_status = 'declined'` and proceeds to the end
  screen. (This is the core anti-coercion control — see §8.2.)

### 6.2 Prompt type selection

The app randomly selects `truth` or `dare`. There is no player choice at selection
time. (The original v1 draft mentioned an optional "winner chooses the type" mode;
it is **cut for launch** — it added a configuration flag that existed nowhere else
in the design and it hands the winner a lever over the loser, which is the wrong
direction for this app. It may return in a future version only with an explicit
consent design.)

### 6.3 Prompt source

| Source | Description |
|--------|-------------|
| App random (default) | Server selects a preset prompt from the shared Truth or Dare bank at the session tone |
| Partner-authored (optional) | The winning partner's own shared custom Truth-or-Dare prompt is used, subject to the same moderation as everywhere else |

### 6.4 Reuse of the existing Truth or Dare content system (mandatory)

Paint Ball prompts **must reuse the live Truth or Dare content tables and RPCs.
Do not create any new prompt, custom-prompt, or report tables.**

- **Preset prompts:** read from `public.game_questions` where
  `game_type = 'truth_or_dare'`, `question_subtype IN ('truth','dare')`, and
  `tone` = the session tone, `active = true`. (Paint Ball does **not** add a
  `'paint_ball'` value to the `game_questions.game_type` CHECK constraint — it
  borrows the Truth-or-Dare bank as-is.)
- **Seen tracking:** reuse `public.game_questions_seen` (keyed by
  `relationship_id`, `question_id`, `game_type = 'truth_or_dare'`) so penalty
  prompts don't repeat across sessions before the bank is exhausted.
- **Partner-authored prompts:** read from `public.custom_truth_or_dare_questions`
  using the existing `custom_tod_partner_read` RLS policy (owner + non-private
  active partner rows + community). Do not add a Paint Ball custom table.
- **Reporting/moderation:** reuse `public.report_custom_question(question_id,
  reason)` and the `custom_question_reports` ledger verbatim. A reported prompt is
  hidden by the existing 2-distinct-reporter threshold and falls back to preset.
- **Usage counters:** reuse `increment_custom_question_usage` /
  `increment_community_usage`.

### 6.5 Recommended default behavior

- App randomly selects `truth` or `dare`.
- App-random preset source is used **unless** the session explicitly enabled
  partner-authored prompts at creation (`penalty_allow_partner_authored = true`)
  and a valid, non-hidden partner prompt exists.
- If partner-authored is enabled but no eligible prompt is available (none exist,
  or the selected one was hidden by moderation), **fall back to app random**. The
  loser must never be shown a broken/empty prompt.

---

## 7. SCREEN DESIGNS

### 7.1 Game lobby

```
┌─────────────────────────────────────┐
│ Paint Ball                          │
│ Playful pressure · 3 lives each     │
│                                     │
│ [Start game]                        │
└─────────────────────────────────────┘
```

### 7.2 Active battle layout

> **Rewritten 2026-09-05 (v3).** The bottom "left / middle / right" cover
> buttons are **removed**. Every action is a tap on the field itself. A
> control strip that duplicates the board teaches the player that the board
> is a picture; making the board the controller teaches them it is a place.

The field is a line diagram on plain black. Three arch-shaped shields per
side, drawn as strokes rather than filled shapes.

```
┌─────────────────────────────────────┐
│ Paint Ball   Round 2                │
│  ♥♥♥                          ♥♥·   │
│                                     │
│    ╭─╮      ╭─╮      ╭─╮            │  THEIR row (red)
│    │ │      │ │      │ │            │  never occupied, except in replay
│                                     │
│  ─────────────────────────────────  │
│                                     │
│    ╭─╮      ╭─╮      ╭─╮            │  YOUR row (green)
│    │ │      │▲│      │ │            │  your triangle is always visible
│                                     │
└─────────────────────────────────────┘
```

**Your row is always the bottom one**, whichever player you are.

**Colours are fixed, not theme-derived.** Green (`#5EEAD4`) is your side, red
(`#FF4D6A`) theirs, yellow (`#FFC94D`) a player and the paint in flight, on
plain black.

### 7.3 Controls — three taps, all on the field

| Tap | Effect |
|---|---|
| **Your cover** | Reposition. Your triangle moves to that cover. |
| **Their cover** | Aim. Your triangle emerges and tilts toward it. |
| **Your triangle** | Fire. |

**Repositioning stays open.** You may change your hiding place at any point
before firing, including after aiming. Aiming does not lock the hide — a
player who has committed to a target should still be free to reconsider where
they are standing, since the two decisions are independent.

**Re-aiming is free.** Tapping a different enemy cover swings the triangle to
the new angle. Tapping the currently-aimed cover again does nothing (it is
not a fire shortcut — firing is always the triangle, so the fire action is
never something you trigger by accident while choosing).

**Firing requires an aim.** Tapping your triangle with no target selected
does nothing and shows a quiet hint.

### 7.4 Turn animation rules

All motion is state-driven, so a dropped frame or a backgrounded app can
never leave a triangle stranded mid-move.

**Reposition** — the triangle leaves cover, travels, and re-enters:
1. Step **back** out of the current cover.
2. Travel **laterally** to the new cover's column.
3. Step **forward** into the new cover.

The three-beat path is what makes repositioning read as *moving through the
world* rather than teleporting between slots.

**Aim** — the triangle steps **forward** clear of its own cover, then
**rotates** to point at the targeted cover. Re-aiming rotates from the
current angle to the new one; it does not snap.

**Fire** — a yellow circle leaves the **tip of the triangle** and travels to
the targeted cover.

**Replay (§5.5)** — the full exchange, both sides at once:
1. Both triangles step forward from their true covers. *This is the reveal.*
2. Both rotate to their respective targets.
3. Both paintballs travel simultaneously.
4. Impacts resolve: a hit plays a recoil-and-flash on the struck triangle;
   a miss splatters on the cover.
5. Lives update.
6. Both triangles return to cover; the opponent's disappears.

The replay is **skippable** — a tap anywhere jumps to the end state. It must
never gate the player from acting, and a player who has seen it should not
be made to sit through it again on reopen.

**Reduce-motion.** The skill is a choice, not a reaction, so reduce-motion
costs nothing. Every animation above collapses to its end state, and the
replay becomes a static summary showing both positions, both shots, and the
outcome. Identical information, identical odds.

### 7.5 Hit reveal

Folded into the replay (§7.4 step 4) rather than a separate screen. The
outcome is shown *on the field*, where the positions are, because "they were
behind the left cover" means more when you can see the left cover.

A short line of text accompanies it, naming the read rather than the maths:
"You called it." / "They moved." / "You got each other."

### 7.6 Loss penalty (declinable)

```
┌─────────────────────────────────────┐
│ Knocked out                         │
│ You lost all 3 lives                │
│                                     │
│ TRUTH or DARE                       │
│ [Prompt content]                    │
│                                     │
│ [Complete]        [Skip this one]   │
└─────────────────────────────────────┘
```

The **[Skip this one]** action is always present and always free. Copy avoids any
implication of losing/owing.

### 7.7 End screen

```
┌─────────────────────────────────────┐
│ Game over                           │
│ Winner: Jordan                      │
│                                     │
│ Hits landed: 3 / 2                  │
│ Penalty: Truth (completed)          │
│                                     │
│ [Play again] [Try another game]     │
└─────────────────────────────────────┘
```

**Stats shown (symmetric, this-session-only):** both players' hits landed (the
`3 / 2` line), and the penalty outcome (`completed` or `skipped`). Symmetric
per-session stats are fine — they are the recap of the game just played. The hard
line is **no cross-session persistence**: no running win/loss record, no tally, no
"you've lost N times." Each end screen describes only its own session.

---

## 8. CONTENT, TONE, AND SAFETY

### 8.1 Tone guidance

- Playful is the native tone.
- Connecting should feel warm, not competitive.
- Romantic content stays light.
- **Spicy and Intimate are off by default.** A combat frame plus a *forced-by-losing*
  penalty is the wrong container for high-intimacy content; combining "you lost" with
  an intimate dare risks pressure. If ever enabled, it requires the same Intimate
  consent gate the other games use, and heavily curated content.

### 8.2 Safety rules (the real threat model)

Attune is used by couples, some of whom have power imbalances. The design assumption
is that a partner *could* try to weaponize a "you have to do this" game. The
mitigations are structural, not cosmetic:

- **The penalty is always declinable with zero consequence** (§6.1). This is the
  single most important safety property in the game.
- **No coercive persistence:** no cross-session score, no "penalties owed" counter,
  no streak, no leaderboard, no completion-rate visible to the partner.
- Prompts come only from the vetted shared Truth-or-Dare bank at the couple's tone;
  partner-authored prompts pass the same moderation as everywhere else.
- No humiliating, aggressive, or mean-spirited prompts.
- No prompts that pressure disclosure beyond the tone.
- No dares requiring unsafe or public behavior.
- No prompts targeting sensitive mental-health or trauma content.
- Safety Resources and quick exit remain available (inherited from the Games shell).

### 8.3 Partner-authored prompt controls (inherited)

- Must be explicitly shared (`is_private = false`) to be selectable.
- Removable by the author at any time.
- Reportable; hidden by the existing 2-reporter threshold; falls back to preset.
- Tone-bound to the session tone.

### 8.4 Motion, sound, and feedback

- Every shot has a short animation; a hit has a stronger feedback beat than a miss;
  a knockout feels distinct from a normal hit.
- Sound reinforces action without becoming noisy; a global mute is respected.
- Haptics used sparingly for key beats (fire, hit, knockout) and respect the OS
  haptic setting.
- **Reduce-motion (locked):** the skill is a *choice*, not a reaction, so
  reduce-motion costs the player nothing. Disable the reposition slide, the
  shield step-aside and the paintball flight; keep the state changes they
  convey (which shield is targeted, where the shot landed) as immediate
  static changes. Reduce-motion users play exactly the same game with exactly
  the same odds.

  > This is a strict improvement on the previous timing-tap design, which had
  > to choose between a fair-but-motion-heavy sweep and a fixed-probability
  > fallback that stripped the skill out. A game of prediction has no such
  > trade-off.
- Accessibility: shields and the fire control are real focusable, labelled
  targets. Lives are conveyed with text + shape, never colour alone — and the
  same applies to the two sides: the field is green vs red, so which row is
  yours must also be conveyed by position (yours is always the bottom) and by
  label, never by colour alone.

---

## 9. DATABASE SCHEMA

Paint Ball is a `game_type = 'paint_ball'` game **inside the shared session
tables.** It does **not** create `paint_ball_sessions` or `paint_ball_rounds`.
Reuse `public.game_sessions` and `public.game_session_rounds` exactly as This or
That, Truth or Dare, and 36 Questions do, and add only the columns Paint Ball needs
via `ALTER TABLE ... ADD COLUMN IF NOT EXISTS` (the same additive pattern the 36
Questions migration used).

### 9.1 Columns to add to `public.game_sessions`

```sql
ALTER TABLE IF EXISTS public.game_sessions
  ADD COLUMN IF NOT EXISTS current_turn_user_id uuid REFERENCES auth.users(id),
  ADD COLUMN IF NOT EXISTS lives_a smallint NOT NULL DEFAULT 3 CHECK (lives_a BETWEEN 0 AND 3),
  ADD COLUMN IF NOT EXISTS lives_b smallint NOT NULL DEFAULT 3 CHECK (lives_b BETWEEN 0 AND 3),
  ADD COLUMN IF NOT EXISTS winner_user_id uuid REFERENCES auth.users(id),
  ADD COLUMN IF NOT EXISTS penalty_type text CHECK (penalty_type IN ('truth', 'dare')),
  ADD COLUMN IF NOT EXISTS penalty_source text CHECK (penalty_source IN ('app_random', 'partner_authored')),
  ADD COLUMN IF NOT EXISTS penalty_status text CHECK (penalty_status IN ('pending', 'completed', 'declined')),
  ADD COLUMN IF NOT EXISTS penalty_allow_partner_authored boolean NOT NULL DEFAULT false;
```

Notes:
- `lives_a`/`lives_b` follow the existing `_a`/`_b` convention (player A = the
  relationship's `user_a`, player B = `user_b`), matching `skips_used_a`/`_b`.
- `current_turn_user_id` is the whose-turn source of truth. Set server-side only.
- Existing shared columns are reused as-is: `relationship_id`, `initiator_id`,
  `game_type`, `tone`, `status`, `current_round`, `total_rounds_completed`,
  `started_at`, `completed_at`, `abandoned_at`, `hidden_by_user_ids`.

### 9.2 Reuse `public.game_session_rounds` for turns

> **Revised 2026-09-05 (v3).** A round is now an exchange between *both*
> players, so it holds **two** rows — one per player — sharing a
> `round_number`. The old UNIQUE on `(session_id, round_number)` becomes
> `(session_id, round_number, active_partner_id)`.

```sql
ALTER TABLE IF EXISTS public.game_session_rounds
  ADD COLUMN IF NOT EXISTS shot_result text
    CHECK (shot_result IN ('hit', 'miss')),
  ADD COLUMN IF NOT EXISTS life_lost boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS hide_position smallint,
  ADD COLUMN IF NOT EXISTS shot_position smallint,
  -- Null until the round's other half arrives and both are resolved
  -- together. Its nullness IS the "round half-complete" state, so there is
  -- no separate status column to drift out of sync with reality.
  ADD COLUMN IF NOT EXISTS resolved_at timestamptz;

ALTER TABLE public.game_session_rounds
  ADD CONSTRAINT game_session_rounds_positions_range
  CHECK (
    (hide_position IS NULL OR hide_position BETWEEN 0 AND 2)
    AND (shot_position IS NULL OR shot_position BETWEEN 0 AND 2)
  );
```

`shot_result` no longer includes `'opening'` — v3 has no turn that cannot
hit (§5.5).

**`hide_position` is the game's secret, and its exposure is time-boxed.** It
is written when a player takes their half, and may be read by a client
**only once `resolved_at` is set on that round**. Before then it is live
information; after, it is history. See §10.3.

**Idempotency anchor** is now `(session_id, round_number, active_partner_id)`
— a player retrying their own half must not create a second row, and must not
be mistaken for their partner's half.

### 9.3 Penalty record

> **Revised 2026-09-05 (v3).** A double knockout (§10.3) produces **two**
> penalties in one session, so the single set of columns on `game_sessions`
> no longer suffices.

Penalties move to a child table keyed on `(session_id, user_id)`. There is at
most one penalty per player per session, and a draw writes two rows.

```sql
CREATE TABLE IF NOT EXISTS public.paint_ball_penalties (
  session_id uuid NOT NULL REFERENCES public.game_sessions(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  penalty_type text NOT NULL CHECK (penalty_type IN ('truth', 'dare')),
  penalty_source text NOT NULL CHECK (penalty_source IN ('app_random', 'partner_authored')),
  penalty_status text NOT NULL DEFAULT 'pending'
    CHECK (penalty_status IN ('pending', 'completed', 'declined')),
  penalty_prompt_id uuid,
  penalty_prompt_snapshot text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  resolved_at timestamptz,
  PRIMARY KEY (session_id, user_id)
);
```

The existing `game_sessions` penalty columns are retained and backfilled for
sessions created before this change, so old sessions stay readable. New
sessions write only to the child table.

`winner_user_id` stays NULL on a draw. Nothing in the UI may present a draw as
a loss for either player.

Store the resolved prompt reference for history:

```sql
ALTER TABLE IF EXISTS public.game_sessions
  ADD COLUMN IF NOT EXISTS penalty_prompt_id uuid,   -- refs game_questions.id OR custom_truth_or_dare_questions.id
  ADD COLUMN IF NOT EXISTS penalty_prompt_snapshot text; -- denormalized text so history survives prompt deletion
```

`penalty_prompt_id` is intentionally not a hard FK (it may point at either the
preset bank or a custom table, and custom prompts can be deleted); the snapshot
guarantees history remains readable — the same pattern 36 Questions uses with
`question_text_snapshot`.

### 9.4 Indexes

```sql
CREATE INDEX IF NOT EXISTS idx_paint_ball_sessions_relationship
  ON public.game_sessions(relationship_id, game_type, status)
  WHERE game_type = 'paint_ball';
CREATE INDEX IF NOT EXISTS idx_paint_ball_turn
  ON public.game_sessions(current_turn_user_id)
  WHERE game_type = 'paint_ball' AND status = 'active';
```

### 9.5 RLS

**No new RLS policies are needed.** `game_sessions`, `game_session_rounds`,
`session_idempotency_keys`, `game_questions`, `game_questions_seen`,
`custom_truth_or_dare_questions`, and `custom_question_reports` already have
relationship-scoped / owner-scoped RLS (see the 36 Questions and games-hardening
migrations). Paint Ball rows are covered automatically because they live in those
same tables. **Do not disable, widen, or duplicate the existing policies.**

---

## 10. SERVER RPC CONTRACT

All state mutation goes through `SECURITY DEFINER` Postgres RPCs with
`SET search_path = public`, `REVOKE ALL ... FROM PUBLIC, anon` and
`GRANT EXECUTE ... TO authenticated`, exactly like the existing games RPCs. Every
RPC verifies `auth.uid()` is a member of the session's relationship and raises the
standard error codes.

### 10.1 `paint_ball_create_session`

- Inputs: `p_relationship_id uuid`, `p_tone text`, `p_idempotency_key text`,
  `p_allow_partner_authored boolean`.
- Reuses `session_idempotency_keys`: if the key exists, returns the existing
  session (no new row). Otherwise inserts `game_sessions` with
  `game_type = 'paint_ball'`, `status = 'invited'`, `lives_a = 3`, `lives_b = 3`,
  `initiator_id = auth.uid()`, and records the key.
- Enforces the shared init rate limit (max 5 game initiations/hour/couple).

### 10.2 `paint_ball_accept_session` / `paint_ball_decline_session`

- Accept: `invited -> active`, set `started_at`, set `current_turn_user_id` to the
  **initiator** (initiator fires first). Only the non-initiator member may accept.
- Decline: `invited -> abandoned`, set `abandoned_at`.

### 10.3 `paint_ball_take_turn` (the core RPC)

> **Revised 2026-09-05 (v3).** One call still submits one player's half of a
> round, but resolution now happens only when the round's **second** half
> arrives. The first half records and returns without a verdict.
>
> Historical note: v1's `paint_ball_fire_shot(uuid, int, boolean, text)` took
> the hit verdict as a client-supplied boolean and has been **dropped** from
> the database — it was reachable with `EXECUTE` granted to `authenticated`,
> letting a partner drain the other's lives without aiming. Do not
> reintroduce it.

```
Inputs:  p_session_id uuid, p_round_number int,
         p_hide_position smallint, p_shot_position smallint
```

In one transaction, with `SELECT ... FOR UPDATE` on the `game_sessions` row:

1. **Auth:** caller is a member of the session's relationship, else `FORBIDDEN`.
2. **Range check:** both positions in `0..2`, else `INVALID_INPUT`.
3. **Idempotency:** if a row exists for
   `(session_id, round_number, active_partner_id = auth.uid())`, return its
   stored state. Runs *before* the status check, so a retry of the turn that
   ended the game returns its result rather than `SESSION_EXPIRED`.
4. **State check:** `status = 'active'`, else `SESSION_EXPIRED`.
5. **Turn check:** `current_turn_user_id = auth.uid()`, else `NOT_YOUR_TURN`.
6. **Record this half:** insert the row with both positions, `shot_result`
   and `resolved_at` left NULL.
7. **Is the round complete?** Look for the partner's row at the same
   `round_number`.

   **If absent — this is the opener's half.** Set
   `current_turn_user_id` to the partner. Return
   `{ round_state: 'awaiting_partner' }` with no verdict, no lives change,
   and **no positions**. Nothing is revealed.

   **If present — this is the closer's half; resolve the round.** In the
   same transaction:
   - `hit_opener := opener.shot_position = closer.hide_position`
   - `hit_closer := closer.shot_position = opener.hide_position`
   - Apply each hit to the *other* player's lives, each guarded by
     `... AND lives_x > 0` so a below-zero life is structurally impossible.
   - Stamp `resolved_at = now()` on **both** rows and write each
     `shot_result`.
   - Set `current_turn_user_id` to the opener (they open the next round),
     unless a knockout occurred.

8. **Knockout.** If either player reached 0 lives, select their penalty
   (§10.4), set `penalty_status = 'pending'`, and clear
   `current_turn_user_id`. **Leave `status = 'active'`** — the game is
   entering the penalty phase, not finishing, and `paint_ball_resolve_penalty`
   returns early on a completed session, which would lock the loser out of
   the forfeit they just earned.

   **Double knockout.** Both players may reach 0 in the same round. This is a
   **draw**: both take a penalty, neither is the winner. `winner_user_id`
   stays NULL and both penalty slots are populated (§9.3). A mutual forfeit
   is a shared moment; declaring a winner on turn order would be arbitrary
   and would make the ending feel like a technicality.

9. Return, for a resolved round:
   `{ round_state: 'resolved', lives_a, lives_b, round_number,
      opener: { user_id, hide_position, shot_position, shot_result },
      closer: { user_id, hide_position, shot_position, shot_result },
      current_turn_user_id, knockout, double_knockout,
      penalties: [ { user_id, penalty_type, penalty_source,
                     penalty_prompt_snapshot } ] }`

The `opener`/`closer` block is what the replay animates. It is returned
**only** on the call that resolves the round; the opener receives the same
data from `get_paint_ball_session_state` when they next open.

**The hidden-information boundary.** `get_paint_ball_session_state` returns
`hide_position` for rounds where `resolved_at IS NOT NULL`, and withholds it
otherwise. A contract test asserts both halves of this: a resolved round
exposes both hides, and a round awaiting its second half exposes neither.
Withholding forever (v2) meant the game could never show what happened;
exposing always would let the closer read the opener's position before
choosing. The boundary is `resolved_at`.

### 10.4 Penalty selection (inside knockout, deterministic once chosen)

- Randomly pick `penalty_type IN ('truth','dare')`.
- If `penalty_allow_partner_authored` and an eligible `custom_truth_or_dare_questions`
  row for the **winner** exists that satisfies **all** of:
  `user_id = winner`, `question_type = penalty_type` (the roll), `tone = session.tone`
  (exact match — tone is the couple's consent boundary; a Playful session must never
  surface a Spicy custom prompt), `is_private = false`, `hidden_for_review = false`
  → `penalty_source = 'partner_authored'`, snapshot its `content`.
  If multiple qualify, pick one at random.
- Else → `penalty_source = 'app_random'`, pick an unseen preset from
  `game_questions` (`game_type='truth_or_dare'`, matching subtype+tone), record it
  in `game_questions_seen`, snapshot its `question_text`.
- Persist `penalty_prompt_id` + `penalty_prompt_snapshot`. **Once chosen, the
  prompt is fixed** — reopening the penalty screen shows the same prompt (no
  reroll), satisfying "deterministic once chosen."

### 10.5 `paint_ball_resolve_penalty`

- Inputs: `p_session_id uuid`, `p_outcome text CHECK (p_outcome IN ('completed','declined'))`.
- Only the **loser** (the member who is not `winner_user_id`) may call it.
- Sets `penalty_status`, then `status = 'completed'`, `completed_at = now()`.
- Idempotent: a second call after `completed` returns success without change.

---

## 11. AUTH, IDEMPOTENCY, CONCURRENCY, RATE LIMITING, ERRORS

These are **inherited from `GAMES.md` §5 and must be honored**. Summarized here so
DeepSeek does not omit them:

### 11.1 Auth (GAMES.md §5.3)
Every RPC verifies the JWT and that `auth.uid()` belongs to the session's
relationship. Non-members get `FORBIDDEN` (403) with a generic message.

### 11.2 Idempotency (GAMES.md §5.2)
- Session creation uses `session_idempotency_keys` (return existing on repeat).
- `paint_ball_take_turn` is idempotent on `(session_id, round_number)`.
- `paint_ball_resolve_penalty` is idempotent once `completed`.

### 11.3 Concurrency (GAMES.md §5.2)
`paint_ball_take_turn` takes `SELECT ... FOR UPDATE` on the `game_sessions` row.
The turn-ownership check (`current_turn_user_id = auth.uid()`) plus the row lock
means two simultaneous fires cannot both resolve — only the current-turn holder's
transaction proceeds; the other sees `NOT_YOUR_TURN` or the already-resolved round.

### 11.4 Rate limiting (GAMES.md §5.4)
- Game initiation: max 5/hour/couple (shared limit).
- Shot firing: max 1 per 2 seconds per user (mirrors the answer-submission limit;
  prevents tap-spam and accidental double fire beyond idempotency).
- Reuse the shared limiter; do not invent a Paint-Ball-specific one.

### 11.5 Error codes (GAMES.md §5.6 — reuse the exact contract)
Return `{ "error": true, "code": "...", "message": "..." }`. Reuse the existing
codes; Paint Ball adds two:

| Code | HTTP | User message | Notes |
|------|------|--------------|-------|
| `NOT_YOUR_TURN` | 409 | "It's not your turn yet." | New for Paint Ball |
| `GAME_OVER` | 409 | "This game has already finished." | New for Paint Ball |
| `FORBIDDEN` | 403 | "You don't have access to this game." | Inherited |
| `NOT_FOUND` | 404 | "Game session not found." | Inherited |
| `SESSION_EXPIRED` | 410 | "This session expired. Start a new game." | Inherited |
| `RATE_LIMITED` | 429 | "Too many attempts. Please wait a moment." | Inherited |
| `INVALID_INPUT` | 400 | "Invalid value provided." | Inherited |
| `INTERNAL_ERROR` | 500 | "Something went wrong. Please try again." | Inherited |

Never expose internal error detail to the client.

### 11.6 Observability (GAMES.md §5.8)
Structured JSON logs with `request_id`, hashed `user_id`, `session_id`, `action`,
`status`, `duration_ms`. **Never log prompt content, penalty answers, or PII.**
Emit the same RED metrics; add Paint-Ball business counters (§15).

---

## 12. EDGE CASES

| Scenario | Expected behavior |
|----------|-------------------|
| Both clients fire "the same turn" | Turn-ownership check + row lock: only the current-turn holder resolves; the other gets `NOT_YOUR_TURN` or the already-recorded round (idempotent). |
| Duplicate fire (retry/network) for a resolved round | Idempotent on `(session_id, round_number)`: returns stored result, no double-decrement, no double-advance. |
| Life would go below 0 | Structurally impossible: guarded `WHERE lives_x > 0` and CHECK constraint. |
| User loses connection mid-turn | On reopen, restore from server: current lives, whose turn, and (if applicable) the pending penalty. No local state trusted over the server row. |
| User closes app after knockout, before penalty | Reopen lands on the penalty screen with the **same** persisted prompt (deterministic). |
| Partner abandons / unlinks mid-game | Session `abandoned` via the shared cron/unlink handler; both hubs update. |
| Penalty prompt fails to load | Prompt is snapshotted at selection time (`penalty_prompt_snapshot`), so it cannot fail to load post-selection; if selection itself found nothing, fall back to app random preset. |
| Partner-authored prompt reported after being shown | Existing moderation hides it for future selection; the already-snapshotted current instance stands (loser can still decline). |
| Loser completes penalty twice | Idempotent: second `paint_ball_resolve_penalty` returns success, no state change. |
| Loser declines penalty | Recorded as `declined`, session completes normally, no punishment. |
| Invite expires (48h) | Shared cron sets `abandoned`. |
| Active session idle 24h | Shared cron sets `abandoned`. |

---

## 13. BUILD ORDER

1. **Migration:** additive `ALTER TABLE` on `game_sessions` and
   `game_session_rounds` (§9) + indexes. No new session/round/custom/report tables.
2. **RPCs:** `paint_ball_create_session`, `accept`/`decline`, `fire_shot`,
   `resolve_penalty` (§10) with SECURITY DEFINER, search_path, REVOKE/GRANT, and
   the shared auth + rate-limit checks.
3. **Turn + life state** proven via RPC unit/integration tests (idempotency,
   turn-ownership, life floor, knockout, deterministic penalty) **before any UI.**
4. **Battlefield UI:** minimal shape-based arena, lives display, fire button.
5. **Round resolution + replay UI:** on-field tap controls (reposition, aim, fire), the three-beat reposition animation, aim tilt, paintball flight, and the both-sides replay,
   reduce-motion fallback.
6. **Penalty flow:** knockout screen, prompt display, **Complete / Skip** (both
   free), reuse of Truth-or-Dare content + moderation.
7. **Realtime + reopen:** subscribe to the session row; state restoration on
   reopen/kill.
8. **Notifications + analytics** (§14, §15) via existing channels.
9. **History + hide:** completed sessions in the Games hub; per-user soft delete
   via `hidden_by_user_ids`.

---

## 14. NOTIFICATIONS

Reuse the existing Games notification channel and throttling. Bodies must never
contain prompt/penalty content.

- Invitation notification when a session is created.
- Turn notification when it becomes the other player's turn.
- Completion notification when the game ends.
- Keep the pace light; no excessive reminders. (Turn reminders respect the same
  remind throttling as other games.)

---

## 15. ANALYTICS EVENTS

Opaque IDs only; no content, no PII (GAMES.md §5.8).

- `paint_ball_session_started`
- `paint_ball_session_accepted`
- `paint_ball_shot_fired`
- `paint_ball_shot_hit`
- `paint_ball_shot_missed`
- `paint_ball_player_eliminated`
- `paint_ball_penalty_completed`
- `paint_ball_penalty_declined`
- `paint_ball_session_completed`

Track: session starts, completion rate, shot hit rate, penalty completion **and
decline** rate, partner-authored prompt usage. (Decline rate is a product-health
signal, not a per-user metric shown to anyone.)

---

## 16. ALGORITHM QUALITY CHECKLIST

- Session creation is idempotent (shared idempotency keys). ✅
- Turn resolution is atomic and row-locked; turn ownership server-enforced. ✅
- Life counts never drift: server is source of truth, single guarded decrement,
  CHECK floor. ✅
- Penalty selection is deterministic once chosen (snapshotted). ✅
- Reported prompts are removed from future selection (existing moderation). ✅
- User-facing errors are generic; internal detail never leaked. ✅
- Auth + relationship-membership verified on every RPC. ✅
- Rate limiting on init and shot firing. ✅
- Structured logs, no content/PII, RED metrics. ✅
- Trust-the-client is scoped to a socially worthless outcome and documented with a
  revisit trigger. ✅
- UI stays simple enough for animation and sound to carry the feel. ✅

---

## 17. SOUL DOCUMENT COMPLIANCE

Paint Ball complies when it stays:
- playful, not cruel;
- relational, not just competitive;
- lightweight, not stressful;
- **consent-aware: the penalty is always declinable, with no punishment or
  persistence** — this is what keeps a "you lost, now do this" mechanic safe in an
  app used by couples with varying power dynamics;
- tone-bound to what Attune wants couples to feel.

If the game starts to feel like punishment instead of playful tension — or if a
losing partner ever feels *obligated* — it no longer fits the Attune soul.

---

## 18. IMPLEMENTATION DEFAULTS

Locked for the first release:

1. Default tone: **Playful**. Allowed: Connecting, Romantic (light). Off by
   default: Spicy, Intimate.
2. Prompt type: app randomly selects truth or dare (no winner-chooses mode at
   launch).
3. Prompt source: app-random preset by default; partner-authored only if explicitly
   enabled at creation **and** an eligible prompt exists, else fall back to preset.
4. **Penalty is always declinable, always free.** No score history, streak, or
   "owed" ledger.
5. Shot mechanic: choose a hiding place and a target each turn; the round
   resolves once *both* players have taken their half, each shot checked
   against the other's same-round hide (§5.5). **Fully server-authoritative**
   — the client cannot report a hit, and `hide_position` reaches a client only
   after that round has resolved.
6. Visual: a line schematic on plain black — arch shields, triangle players,
   green for your row (always the bottom), red for theirs, yellow for a
   player and the paint in flight (§7.2).
7. Data model: **`game_type = 'paint_ball'` inside the shared `game_sessions` /
   `game_session_rounds` tables.** No standalone Paint Ball tables. Reuse the Truth
   or Dare bank, seen tracking, custom-prompt tables, and moderation verbatim.
8. Reduce-motion has a fair, non-animated fire path.

---

*Rewritten 2026-09-04 (Claude Opus 5) to match the shipped hidden-information
game: §1.1, §1.2, §5.3-5.5, §7.2-7.5, §8.4, §9.2, §10.3, §13 and §18. The
spec had drifted badly — it still documented `paint_ball_fire_shot`, a
timing-tap sweep, and a trust-the-client model, all three of which had been
replaced in code.*

*Originally reviewed by Claude (Opus) for codebase alignment and by Fable for
the anti-cheat / penalty threat model. Aligned to the live Games architecture (`GAMES.md` §5 and the
36-Questions + games-hardening migrations). Ready for DeepSeek implementation in the
Section 13 build order. Review against `ATTUNE_SOUL.md` before shipping.*

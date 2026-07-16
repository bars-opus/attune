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

It is asynchronous: the two partners are on separate devices and do not need to be
online at the same time. Each turn is a discrete, server-recorded action, exactly
like an answer in This or That.

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
| Shot skill | Simple timing tap; **trust-the-client result, server-authoritative structure** |
| Motion | Tap, target sweep, hit flash, knockout transition |
| Sound | Fire, hit, miss, knockout, penalty reveal |
| Visual language | Simple shapes: circles as cover, triangle avatar |
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

Turns alternate. The active player (`current_turn_user_id`) fires one shot per
turn. The other player is not required to be present; they see the resolved result
and updated lives when they next open the session (realtime subscription updates it
live if they are present).

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
- A turn is fired via `paint_ball_fire_shot` (§10). The RPC is idempotent on
  `(session_id, round_number)`: a duplicate fire for a round that already resolved
  returns the existing result and does not double-advance or double-decrement.
- The RPC rejects a fire from anyone who is not the current `current_turn_user_id`
  (error `NOT_YOUR_TURN`).

### 5.4 Result reveal

- The shot animation plays locally, then the client calls `paint_ball_fire_shot`
  with its locally-computed `hit` boolean.
- The **life counter in `game_sessions` is the single source of truth.** Both
  clients render lives from the server row, never from local optimistic state that
  isn't reconciled.
- **State delivery (locked): both.** Subscribe to the `game_sessions` row via
  Supabase Realtime for live updates while the partner is present (same pattern
  This or That uses for reveal sync), **and** fetch the latest row on every
  open/reopen as the authoritative source. Realtime is the nicety; fetch-on-open is
  the guarantee — never rely on realtime alone, because a dropped subscription must
  not strand a player on stale state.

### 5.5 Shot resolution mechanic (skill layer)

Paint Ball uses a simple timing tap so it feels active without becoming
complicated:

- Tap to fire.
- A moving target sweeps across the screen.
- A tap while the target is inside the hit window = hit.
- A tap outside the window, or no tap before the sweep ends, = miss.

**Tuning (locked for launch):**
- Hit window is generous (default: target is "inside window" for ~45% of the sweep
  duration). Tune during playtest; keep it forgiving.
- No drag controls, no precision aiming.
- Sweep duration ~1.5s so the game stays fast.
- The result is computed locally at tap time and is final once submitted.

**Trust model (design decision — reasoned with Fable, do not "improve" this into
server-side timing validation):**

The hit/miss result is **trust-the-client**. The client computes `hit` locally and
reports it; the server does **not** re-derive the tap from a server-held timing
schedule. This is deliberate and correct for this game:

- The prize for "winning" is only that your partner completes a **declinable**
  penalty prompt (§6). Because the penalty can always be declined with no
  consequence, a rigged win yields nothing coercive to steal. The safety control
  lives at the penalty layer, not in anti-cheat.
- Every other game in the module is already honor-system (Truth-or-Dare completion
  and 36-Questions answers are self-reported and unverifiable). Server-validating
  this one tap would close a door in a house with no walls.
- Server-side timing would introduce clock-skew/latency false-misses — an honest
  tap sometimes adjudicated as a failure — which is exactly the "unfair" feeling a
  light couples game must avoid.

**What the server IS authoritative for (must not be trusted to the client):** whose
turn it is, that exactly one life is removed on a hit, that lives never go below 0,
turn alternation, and session termination. These prevent the *bugs* that erode
trust (double-fires, skipped turns, negative lives), which matters far more than
tap honesty. See §10.

> **Revisit trigger (spec this as a standing note):** trust-the-client is correct
> only while game outcomes are socially worthless. If Attune later attaches streaks,
> rewards, leaderboards, or cross-user visibility to Paint Ball results, this
> decision must be re-opened and server-authoritative timing reconsidered.

---

## 6. TRUTH OR DARE PENALTY LAYER

When a player loses all 3 lives, the game resolves into one Truth or Dare prompt
for the loser. This is what makes Paint Ball feel like Attune rather than a generic
arcade toy — and it is where the entire safety model lives.

### 6.1 Penalty rule

- The losing player is shown **one** Truth or Dare prompt immediately after the
  knockout animation.
- The prompt step must be **resolved** (completed or declined) before the session
  becomes `completed`.
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

Simple split arena: left = one player, right = the other; each side has 3 cover
nodes (circles, default); each avatar is a triangle hiding behind cover until its
turn.

```
┌─────────────────────────────────────┐
│ Paint Ball   Round 2                │
│ You have 2 lives                    │
│ Partner has 3 lives                 │
│                                     │
│   ▲  ○  ○  ○        ○  ○  ○  ▲      │
│                                     │
│ [Fire paint splash]                 │
└─────────────────────────────────────┘
```

### 7.3 Waiting-for-partner-turn state

When it is the partner's turn, the fire button is disabled and the screen shows a
calm waiting state ("Partner is taking their shot"). No countdown pressure.

### 7.4 Turn animation rules

- On the active turn, the triangle avatar slides slightly out from cover.
- The shot fires from the avatar position; the target sweep is the tap window.
- After the shot, the avatar slides back behind the same cover node.
- Miss: avatar returns with a light snap.
- Hit: the defender avatar briefly recoils/flashes before the life counter updates.
- All motion respects reduce-motion; a reduced-motion path uses a static
  tap-to-fire button with no sweep (see §8.4).

### 7.5 Hit reveal

```
┌─────────────────────────────────────┐
│ Direct hit                          │
│ Partner loses 1 life                │
│                                     │
│ [Next turn]                         │
└─────────────────────────────────────┘
```

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
- **Reduce-motion (locked):** keep the **same tap-to-fire skill**, but use a
  slower, gentler sweep and a wider window — target ~2.5s sweep and ~60%
  inside-window. Reduce-motion users play *the same game*, just more forgivingly;
  do **not** replace the mechanic with a coin-flip fixed probability, which strips
  the skill and turns their game into pure luck. A fixed-probability tap is only a
  last resort if the sweep cannot be made reduce-motion-safe on a given platform.
  Never rely on the sweep animation alone to convey the hit window — the window
  must also be conveyed statically (e.g. a highlighted band the target crosses).
- Accessibility: fire control is a real focusable/labeled button; lives are
  conveyed with text + shape, never color alone.

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

### 9.2 Reuse `public.game_session_rounds` for shots

One row per shot. Reuse existing columns; add two Paint-Ball-specific ones.

```sql
ALTER TABLE IF EXISTS public.game_session_rounds
  ADD COLUMN IF NOT EXISTS shot_result text CHECK (shot_result IN ('hit', 'miss')),
  ADD COLUMN IF NOT EXISTS life_lost boolean NOT NULL DEFAULT false;
```

Mapping to existing columns:
- `session_id`, `round_number` (UNIQUE per session — idempotency anchor for a shot),
  `active_partner_id` (= the attacker/firer), `resolved_at` uses existing
  `revealed_at`/`created_at`. `defender` is derivable (the other member) but may be
  stored in `active_partner_id`'s complement; no new column needed.

### 9.3 Penalty record

Reuse the session row's penalty columns (§9.1) as the authoritative penalty record.
A dedicated child table is unnecessary because there is exactly one penalty per
session. Store the resolved prompt reference for history:

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

### 10.3 `paint_ball_fire_shot` (the core RPC)

```
Inputs:  p_session_id uuid, p_round_number int, p_hit boolean, p_idempotency_key text (optional)
```

In one transaction, with `SELECT ... FOR UPDATE` on the `game_sessions` row:

1. **Auth:** caller is a member of the session's relationship, else `FORBIDDEN`.
2. **Turn check:** `current_turn_user_id = auth.uid()`, else `NOT_YOUR_TURN`.
3. **State check:** `status = 'active'`, else `SESSION_EXPIRED`.
4. **Idempotency:** if a `game_session_rounds` row already exists for
   `(session_id, round_number)`, return its stored result and current lives without
   mutating anything (handles double-fire / retry).
5. **Resolve:** insert the round row with `active_partner_id = auth.uid()`,
   `shot_result = CASE WHEN p_hit THEN 'hit' ELSE 'miss'`, `round_number`.
6. **Apply life (guarded):** if hit, decrement the **defender's** life with a floor:
   `UPDATE game_sessions SET lives_x = lives_x - 1 WHERE id = p_session_id AND lives_x > 0`
   (x chosen by which member is the defender). Set `life_lost = true` on the round.
   The `lives_x > 0` guard makes a below-zero life structurally impossible even
   under a replayed/racing call.
7. **Check knockout:** if the defender now has 0 lives, set `winner_user_id =
   auth.uid()`, select the penalty (§10.4), set `penalty_status = 'pending'`, and
   **do not** advance the turn (game is entering penalty phase).
8. **Else advance turn:** set `current_turn_user_id` to the other member.
9. Return `{ lives_a, lives_b, shot_result, current_turn_user_id, knockout: bool,
   penalty_type, penalty_prompt_snapshot }`.

The client's `p_hit` is trusted (per §5.5), but the *structure* — turn ownership,
single decrement, floor at 0, single winner, single penalty — is fully enforced
here and cannot be spoofed.

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
- `paint_ball_fire_shot` is idempotent on `(session_id, round_number)`.
- `paint_ball_resolve_penalty` is idempotent once `completed`.

### 11.3 Concurrency (GAMES.md §5.2)
`paint_ball_fire_shot` takes `SELECT ... FOR UPDATE` on the `game_sessions` row.
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
5. **Shot resolution + reveal UI:** target sweep, tap window, hit/miss animation,
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
5. Shot mechanic: simple tap-to-fire with a generous timing window;
   **trust-the-client result, server-authoritative structure** (§5.5). Do not
   implement server-side timing validation for launch.
6. Visual cover: circles by default (squares allowed as an alternate skin).
7. Data model: **`game_type = 'paint_ball'` inside the shared `game_sessions` /
   `game_session_rounds` tables.** No standalone Paint Ball tables. Reuse the Truth
   or Dare bank, seen tracking, custom-prompt tables, and moderation verbatim.
8. Reduce-motion has a fair, non-animated fire path.

---

*Reviewed by Claude (Opus) for codebase alignment and by Fable for the anti-cheat /
penalty threat model. Aligned to the live Games architecture (`GAMES.md` §5 and the
36-Questions + games-hardening migrations). Ready for DeepSeek implementation in the
Section 13 build order. Review against `ATTUNE_SOUL.md` before shipping.*

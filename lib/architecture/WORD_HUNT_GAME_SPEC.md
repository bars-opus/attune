# ATTUNE — WORD HUNT SPECIFICATION

**Status:** Draft for review. Not implemented.

**Reads with:** `SNAKES_AND_LADDERS_SPEC.md` (the game this borrows most
from), `PAINT_BALL_GAME_SPEC.md` (§5.5, the disclosure boundary),
`GAMES.md` §5, `algorithms/algorithm_quality_review_checklist.md`.

---

## 1. What it is

One hidden word, one grid, both partners. You drag a finger across
letters — horizontally, vertically or diagonally — and the trail
highlights as you go. Find the word and your time is recorded. When both
have found it, you see who was faster.

Thirty seconds of play, and then it is over. That is the whole game.

### 1.1 Why it exists

The second game in the Arcade slot Snakes and Ladders opened: **fun with
no insight layer**. Same rule, and it is a rule rather than a note — no
reflection prompt, no score across sessions, no analysis of who wins.

Where Snakes is slow and lucky, this is quick and sharp. A couple who
want thirty seconds of competition rather than ten minutes of dice have
somewhere to go.

### 1.2 What it is not

- Not a vocabulary test. The word is found, not spelled or defined.
- Not scored across sessions. Nothing accumulates.
- Not a live race. See §3.

---

## 2. Core characteristics

| Characteristic | Value |
|---|---|
| Duration | ~20 to 60 seconds per player |
| Word | One per session, drawn from a curated list (§6) |
| Grid | 10×10 |
| Skill | Visual search. Nothing about your partner. |
| Turn model | Asynchronous, **simultaneous** — both play the same puzzle independently |
| Win condition | Faster time, once both have finished |
| Penalty | None |
| Visual language | The reference: a white rounded pill over found letters |

---

## 3. The timer, and what it can honestly claim

**The timer starts when a player taps "Start", not when the grid loads
and not when the invite arrives.**

That distinction is the whole fairness model. A player who opens the
game at 9pm and one who opens it at 7am are not racing each other in any
live sense — but each *did* start their own clock deliberately, and the
elapsed seconds mean the same thing for both.

**Server-anchored.** `started_at` is written by the server when the
player taps Start, and the elapsed time is computed server-side on
submit — `now() - started_at`. The client never sends a duration.

A client-supplied time would be the whole game handed to the client, and
this game is nothing but a number.

**What the reveal may say:** "You found it in 24s. Ama took 31s." A
comparison of two honest measurements.

**What it must not say:** anything framing this as a race that was won.
Nobody was present for the other person's attempt.

### 3.1 Abandonment

A player who starts and never submits does not block the other forever.
After **10 minutes** of an unsubmitted attempt the session records it as
unfinished; the reveal then shows one time and says the other person did
not finish. No penalty, no comment.

---

## 4. The grid

### 4.1 Generation

Server-side, at session creation, with the word placed once in one of
eight directions (four axes, either way along each). Remaining cells are
filled with random letters.

**Generated once and stored**, never regenerated per player: both
partners must search the identical grid, or the comparison means
nothing.

### 4.2 The decoy problem

Random fill can accidentally spell the target word a second time, or
spell it backwards where it was not placed. Either makes a "wrong"
answer look right.

So after filling, the generator **scans all eight directions from every
cell** and rejects the grid if the word appears more than once. On
rejection it regenerates, up to a bounded number of attempts.

A contract test asserts the shipped generator produces exactly one
occurrence across many trials.

**Measured before specifying it:** 400 generated grids across five words
of varying length produced an accidental second occurrence **zero
times**. The scan is cheap insurance, not a bottleneck — but it stays,
because the one time it fires is the time a player drags the right
letters in the wrong place and is told they are wrong.

### 4.3 Difficulty

Words are placed diagonally or backwards more often than not: a word
running left-to-right along a row is found in about two seconds and the
game is over before it starts.

Direction weights live in the same versioned config as the word list, so
difficulty is tunable without an app update.

---

## 5. The disclosure boundary

**The client is never told where the word is.**

This is the same rule Paint Ball enforces for a hiding position, and it
matters more here: the client receives the grid and the word, so if it
also received the coordinates, any modified client could draw the answer
on screen.

- The grid and the word are sent.
- The **placement** — start cell, direction, the cell list — is not.
- Submission sends the **cells the player dragged**; the server compares
  them to the stored placement and answers hit or miss.

A contract test greps the state payload for the placement keys and fails
if they appear, exactly as Paint Ball's does.

**Why the server must judge:** a client that decided its own correctness
could submit "found it in 3 seconds" without looking at the grid.

---

## 6. Words

Thirty to fifty words, relationship-flavoured, stored server-side in a
versioned table alongside the direction weights — the same shape as
`snakes_boards`, and immutable once a session has used a version.

Selection rules:

- **4 to 8 letters.** Shorter is trivially found; longer will not place
  diagonally on a 10×10 grid often enough — a 9-letter word has only two
  legal diagonal starts per direction, so it lands in nearly the same
  place every time.

  *(The first draft of this list included AFFECTION at 9 letters and
  TOGETHER at 8, breaking its own rule. The generator validates word
  length on insert so a future edit cannot reintroduce that by hand.)*
- **No word that is unkind to encounter.** This is a cool-off game and
  might be opened after an argument; a grid containing `ALONE` or
  `LEAVING` is a small cruelty at exactly the wrong moment. The list is
  warm or neutral throughout.
- **No word is repeated** within a couple's recent sessions, tracked the
  way the question banks already track seen items.

Starting list (reviewable, not final):

```
LOVE     KISS     LAUGH    HOME     WARM     TRUST
SPARK    HONEY    SMILE    DANCE    SWEET    HEART
CUDDLE   FLIRT    CHARM    ADORE    DEVOTE   TENDER
GIGGLE   PATIENT  LOYAL    GENTLE   PLAYFUL  COMFORT
DESIRE   ROMANCE  EMBRACE  CHERISH  DELIGHT  BELOVED
DARLING  FOREVER  PARTNER  INTIMATE SNUGGLE  BLUSH
```

---

## 7. The interaction

### 7.1 Dragging

A press begins a selection at that cell. Dragging extends it, **snapped
to the eight legal directions** — a finger wandering off-axis holds the
nearest legal line rather than selecting a crooked path, because a
finger on glass is not precise and the game should not punish that.

Release submits the selection.

### 7.2 Feedback

| Moment | Feedback |
|---|---|
| Selection begins | Light haptic |
| Each new letter entered | Light haptic |
| Release on the right word | Success haptic, the pill **stays and locks**, a brief bloom |
| Release on the wrong word | The pill **animates off**; no haptic, no message |

A wrong guess costs nothing and says nothing. Being told "wrong" every
few seconds while hunting is the kind of nagging that makes a small game
feel like a test.

### 7.3 The pill

The reference image: a white rounded capsule behind the letters, drawn
along the drag axis with a radius of half a cell. It follows the finger
live, and letters under it invert.

---

## 8. Screens

**Lobby** — one line of what the game is, a Start button. Tapping Start
is what begins the clock, so it must be unambiguous.

**Grid** — the 10×10, the target word above it, and a running timer.
Nothing else.

**Waiting** — the breathing mark the session games use, your own time
shown, and an exit to the chat. The screen leaves on its own once the
partner finishes, matching Paint Ball and Snakes.

**Reveal** — both times, and the pill drawn on the grid so you see where
it was. `Play again` and `Back to chat`.

---

## 9. Data model

Reuses `game_sessions` with `game_type = 'word_hunt'`.

```sql
ALTER TABLE public.game_sessions
  ADD COLUMN IF NOT EXISTS hunt_word text,
  ADD COLUMN IF NOT EXISTS hunt_grid jsonb,      -- ["ABC...", ...] 10 rows
  ADD COLUMN IF NOT EXISTS hunt_placement jsonb, -- NEVER sent to a client
  ADD COLUMN IF NOT EXISTS hunt_word_list_version text;

CREATE TABLE IF NOT EXISTS public.word_hunt_attempts (
  session_id uuid NOT NULL REFERENCES public.game_sessions(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  started_at timestamptz NOT NULL DEFAULT now(),
  found_at timestamptz,
  -- Server-computed on submit. The client never sends a duration.
  elapsed_ms int,
  gave_up boolean NOT NULL DEFAULT false,
  PRIMARY KEY (session_id, user_id)
);
```

`hunt_placement` sits on the session row deliberately: RLS on
`game_sessions` will be `word_hunt`-excluded from client writes (§11),
and the state RPC omits the column, so it is unreachable from a client
by either path.

---

## 10. Server contract

### `word_hunt_start(p_session_id)`
Writes `started_at` for the caller. Idempotent: a second call returns the
first timestamp rather than restarting the clock — otherwise closing and
reopening the app would reset the timer, which is a cheat and an easy
accident.

### `word_hunt_submit(p_session_id, p_cells jsonb)`
1. Auth, membership, relationship still active.
2. Idempotency **first**, as everywhere: an already-found attempt returns
   its stored result rather than re-timing.
3. Rate limit — a wrong guess every 300ms is a script, not a finger.
4. Compare `p_cells` to the stored placement, order-insensitive (the word
   may be dragged from either end).
5. On a hit: `found_at = now()`, `elapsed_ms = now() - started_at`.
6. Return hit or miss, and — **only once both have finished** — both
   times and the placement.

### `get_word_hunt_state(p_session_id)`
Grid, word, both players' status, and each elapsed time **only after
that player has finished**. Placement only when both are done.

---

## 11. What this borrows

| Borrowed | From |
|---|---|
| Session lifecycle, error envelope, turn guards | Snakes, near-verbatim |
| Disclosure boundary and its contract test | Paint Ball §5.5 |
| Versioned immutable config table | `snakes_boards` |
| RPC-write-only RLS carve-out | The Snakes security fix |
| Auto-pop, live sync, breathing wait | Snakes / session games |
| Sound generation | `tool/generate_*_sounds.dart` |

**Genuinely new:** grid generation with its uniqueness scan, the drag
gesture with axis snapping, the pill, and the two-attempt timing model.

Estimate: **three to four days.** The gesture and the pill are most of
it; the server is a day.

---

## 12. Risks

**The comparison is not a race, and the copy must not pretend it is.**
Framing matters more than usual: two people who did not play at the same
time being told one "beat" the other is a small lie.

**Grid generation can loop.** The uniqueness scan rejects and retries;
without a bound it could spin. Bounded at 20 attempts, with a fallback
to a straight-line placement rather than failing to start a game. In
practice the measurement above suggests it will never retry — the bound
exists for the case the word list changes to something pathological.

**A 10×10 grid of letters is small on a phone**, and this one is
*dragged on*, not just read — so cells must be large enough to hit
reliably. Same risk Snakes has, with a harder target.

**Difficulty is unknowable from here.** Whether a diagonal backwards word
takes 15 seconds or 90 is a device question, and the direction weights
exist so it can be tuned after finding out.

---

## 13. Open questions

1. **Should a player be able to give up?** Currently only the 10-minute
   timeout ends an attempt. A visible "I can't find it" would be kinder,
   but also an obvious way to end a losing round early.
2. **Is one word per session too thin?** It is over in thirty seconds.
   The instruction was explicit, and `Play again` covers it — but worth
   watching whether people play once and leave.
3. **Should the loser see the answer?** Currently the placement is
   revealed only when both finish, so a player who never finds it never
   learns where it was. Kind, or maddening?

---

## Changelog

- **2026-09-07** — Initial draft. Not implemented, not approved.

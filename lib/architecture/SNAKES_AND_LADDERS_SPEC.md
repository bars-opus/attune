# ATTUNE — SNAKES AND LADDERS SPECIFICATION

**Status:** Draft for review. Not implemented.

**Reads with:** `PAINT_BALL_GAME_SPEC.md` (the game this borrows its
architecture from), `GAMES.md` §5 (session contracts), `ATTUNE_SOUL.md`.

---

## 1. Why this game exists

Every other game in Attune asks the couple to reveal something. This one
does not, and that is the point.

> *"Sometimes after a conflict we just want to play games and cool off."*

A couple who have just had a hard conversation should not only be offered
another prompt. They should be able to sit next to each other and roll a
die. Snakes and Ladders is the least demanding game there is — no skill,
no strategy, nothing to disclose — and that emptiness is exactly the
feature. It asks for nothing except that you both keep playing.

**This is the first Attune game with no insight layer, and it must stay
that way.** No reflection prompt at the end, no "what did you notice",
no analysis. Adding one would defeat the purpose: a person using this
game is deliberately not doing that work right now.

### 1.1 What it is not

- Not a compatibility signal. Nothing about the outcome means anything.
- Not scored across sessions. No ladder, no streak, no record.
- Not a race worth winning. See §5.4 on how the ending is framed.

---

## 2. Core characteristics

| Characteristic | Value |
|----------------|-------|
| Duration | ~3 to 6 minutes across as many sittings as they like |
| Players | The two partners |
| Skill | **None.** Deliberately. |
| Win condition | First token to land exactly on 100 |
| Turn model | Asynchronous, alternating, one roll per turn |
| Penalty | **None.** No forfeit, no prompt, no consequence |
| Visual language | Paint Ball's: line schematic on plain black |
| Sound | Die roll, token step, snake slide, ladder climb, finish |

---

## 3. The board

### 3.1 Layout

Ten by ten, numbered 1–100, boustrophedon: row 1 runs left to right, row 2
right to left, and so on, so the path is continuous. `FINISH` sits at 100,
`START` before 1.

Rendered as Paint Ball is rendered — plain black ground, thin strokes,
white cell borders and numerals. Not the primary-colour board of the
reference image: that look belongs to a children's toy, and Attune's
games are for adults sitting together at the end of a difficult evening.

### 3.2 Snakes and ladders

Fixed for every game. A randomised board would mean a player could never
learn the terrain, and knowing "the long snake at 87" is most of the small
pleasure this game has.

The layout is a **versioned server-side configuration**, not a client
constant, so it can be tuned without shipping an app update — and so both
clients cannot possibly disagree about where a snake is.

```
LADDERS (climb):     2→38   4→14   9→31   21→42   28→84
                    36→44  51→67  71→91  80→99
SNAKES  (slide):    16→6   47→26  49→11  56→53   62→19
                    64→60  87→24  93→73  95→75   98→78
```

Invariants the config must satisfy, checked by a contract test:

- no ladder or snake starts or ends on 1 or 100 — a ladder to 100 would
  bypass the exact-finish rule, which is the only tension the game has
- no cell is the head of two features
- every ladder ends above its start; every snake ends below its
- no chaining: a feature's destination is never another feature's head,
  so a single roll can never trigger two slides

  *(The first draft of this table failed two of these — `1→38` and
  `80→100`. They are cheap invariants to write and easy to violate by
  eye, which is why the test exists rather than a careful read.)*

### 3.3 Exact finish

Landing beyond 100 does not win. The token moves to 100 only on an exact
roll; an overshoot **bounces back** by the excess. From 97, a 5 lands on
98 (100 then back 2).

Rationale: without it the last stretch is a formality. With it, the end of
the game has the only tension the game contains — and it is the shared,
harmless kind.

---

## 4. Turn structure

### 4.1 One roll per turn

A player opens the game, taps the die, watches their token move, and the
turn passes. No "roll again on a six" — that rule exists to speed up
four-player games and here it only creates a lopsided turn where one
person does five things and the other waits.

### 4.1a Who goes first

The **invitee**, matching Paint Ball. The person who accepted has the app
open and their attention on it; handing the first move to the initiator
would mean the game's first action happens whenever they next look, which
is the slowest possible start for a game meant to be picked up quickly.

Both tokens start off-board at 0, and there is no roll-to-start: needing
a six to begin is a rule from physical Ludo that exists to stagger four
players, and here it would just make the first minute nothing.

### 4.2 Asynchronous

Identical to Paint Ball: neither player need be present. A turn is a
discrete server-recorded action, the game card in the chat carries whose
move it is, and the screen returns to the chat once the turn passes.

### 4.3 The replay

Borrowed wholesale from Paint Ball, and the reason this game is cheap to
build.

When you open the game after your partner has moved, you watch their turn
before taking yours: their die lands, their token walks, and if they hit a
snake or a ladder you see it happen. Then it is your turn.

Without this the game is a number changing while you were away. With it,
you were there when they hit the snake on 87 — and that is the entire
social content of this game, which is enough.

---

## 5. Rules

### 5.1 Movement

- Both tokens start off-board (position 0).
- A roll of *n* moves the token *n* cells, then applies at most one
  feature (a ladder top that is a snake head is forbidden by §3.2).
- Movement is animated cell by cell, not teleported — the walk is most of
  what makes a good roll feel good.

### 5.2 Both tokens may share a cell

No capture, no sending anyone back. Capture is Ludo's mechanic and it
introduces exactly the small aggression this game exists to avoid.

### 5.3 The die is the server's

`floor(random() * 6) + 1`, computed in the RPC. The client never sends a
face value and cannot; it sends only "I am rolling".

This matters more than it does in most games: the entire content of a turn
IS the die. A client-supplied roll would not be a game.

### 5.4 Ending

First to land exactly on 100. The end screen says who got there, and
nothing else — no winner banner, no confetti, no record. Copy is
deliberately flat: *"Ama got there first."* with a `Play again`.

**No penalty, no forfeit, no prompt.** Paint Ball earns its Truth or Dare
because skill decided it. Here a die did, and attaching a consequence to a
coin flip would be the opposite of cooling off.

---

## 6. Screens

### 6.1 Board (the only real screen)

```
┌─────────────────────────────────────┐
│ Snakes and Ladders        AMA'S TURN│
│                                     │
│  100  99  98  97  96 ... 91         │
│   81  82  83  84  85 ... 90         │
│              ...                    │
│    1   2   3   4   5 ... 10         │
│                                     │
│         ▲ you 34   ● Ama 51         │
│                                     │
│              [ die ]                │
└─────────────────────────────────────┘
```

- Two tokens, distinguished as Paint Ball distinguishes rows: yours in the
  mint green, theirs in red.
- The die is the only control. Tapping it is the whole game.
- Position readouts under the board, because a token on a 10×10 grid on a
  phone is small and "where am I" should never require squinting.

### 6.2 Waiting

Reuses the pattern the session games now have: a breathing mark, not a
spinner, and the screen leaves for the chat on its own once the turn has
passed (Paint Ball's auto-pop).

### 6.3 End

Who arrived, and `Play again`. Nothing else.

---

## 7. Motion and sound

| Beat | Motion | Sound |
|---|---|---|
| Die roll | Tumble, ~700ms, settling on the face | `game_dice` |
| Token walk | Cell by cell, ~90ms per cell | `game_step` per cell |
| Ladder | Token rises along the ladder line | `game_ladder` (rising) |
| Snake | Token slides down the snake's curve | `game_snake` (falling) |
| Exact-finish bounce | Walk to 100, pause, walk back | `game_step` |
| Arrival | Token settles on 100 | `game_complete` (existing) |

Two new sounds, generated the way the others were
(`tool/generate_*_sounds.dart`): a rising arpeggio for a ladder, a falling
one for a snake, so the two events are distinguishable without looking.
Plus a die rattle and a soft step.

**Reduce motion:** the token jumps to its final cell and the replay
becomes a static summary — "Ama rolled 4, climbed the ladder at 28".
Identical information, no movement.

---

## 8. Data model

Reuses `game_sessions` with `game_type = 'snakes_and_ladders'`. Only two
new columns; everything else the shared table already has.

```sql
ALTER TABLE public.game_sessions
  ADD COLUMN IF NOT EXISTS board_position_a smallint NOT NULL DEFAULT 0
    CHECK (board_position_a BETWEEN 0 AND 100),
  ADD COLUMN IF NOT EXISTS board_position_b smallint NOT NULL DEFAULT 0
    CHECK (board_position_b BETWEEN 0 AND 100),
  -- Pinned at creation. §3.2 says the board is tunable without an app
  -- update, which is only true if a session remembers which board it was
  -- played on -- otherwise retuning silently rewrites the history of
  -- every finished game, and a replay would animate a snake that was not
  -- there at the time.
  ADD COLUMN IF NOT EXISTS board_version text NOT NULL DEFAULT 'v1';
```

The board itself lives in its own table, so a version is a row rather
than a deploy:

```sql
CREATE TABLE IF NOT EXISTS public.snakes_boards (
  version text PRIMARY KEY,
  -- {"ladders": {"2": 38, ...}, "snakes": {"16": 6, ...}}
  features jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  retired_at timestamptz
);
```

Turns are rows in `game_session_rounds`, one per roll:

```sql
ALTER TABLE public.game_session_rounds
  ADD COLUMN IF NOT EXISTS die_roll smallint
    CHECK (die_roll BETWEEN 1 AND 6),
  ADD COLUMN IF NOT EXISTS moved_from smallint,
  -- Where the die alone put them, BEFORE any snake or ladder. The replay
  -- has to walk here first and then slide; a client that only knew the
  -- final cell would have to re-derive this from the board, which stops
  -- being possible the moment board_version can differ.
  ADD COLUMN IF NOT EXISTS rolled_to smallint,
  ADD COLUMN IF NOT EXISTS moved_to smallint,
  -- 'normal' | 'bounce' | 'ladder' | 'snake'. One field the animation can
  -- switch on, rather than three booleans it has to combine correctly.
  ADD COLUMN IF NOT EXISTS movement_kind text
    CHECK (movement_kind IS NULL
           OR movement_kind IN ('normal', 'bounce', 'ladder', 'snake'));
```

A bounce and a snake both end below where the die pointed, and they must
animate differently -- one walks up and back, the other slides down a
curve. Storing the outcome rather than inferring it is what keeps the
replay honest across board versions.

`current_turn_user_id`, `status`, `winner_user_id` and the whole
invite/accept/expire lifecycle come free from the shared table.

**Nothing here is secret.** Unlike Paint Ball, both positions are public
at all times — there is no hidden information, so no disclosure boundary
to enforce. That removes the single most delicate part of Paint Ball.

---

## 9. Server contract

### 9.1 `snakes_roll_die(p_session_id uuid, p_round_number int)`

In one transaction, with `SELECT ... FOR UPDATE` on the session row:

1. **Auth** — caller is a relationship member, else `FORBIDDEN`.
2. **Idempotency, FIRST** — a row already existing for
   `(session_id, round_number, active_partner_id)` returns its stored
   result immediately.

   This runs before every other rejection, and the order is the whole
   point. A retry arriving 200ms after the app was killed must return the
   roll that was recorded, not `RATE_LIMITED` (it looks like spam) and not
   `SESSION_EXPIRED` (the roll it is retrying may have been the winning
   one). Either would let a player lose a turn they had already taken —
   or, worse, believe they could reroll it.

   Paint Ball's shipped `paint_ball_take_turn` already does this; the
   first draft of this spec put the rate limit first, which was a
   regression against working code for no reason.
3. **Rate limit** — a second *new* roll within 1s is `RATE_LIMITED`.
4. **State** — `status = 'active'`, else `SESSION_EXPIRED`.
5. **Turn** — `current_turn_user_id = auth.uid()`, else `NOT_YOUR_TURN`.
6. **Roll** — `v_roll := floor(random() * 6) + 1`.
7. **Move** — advance; bounce on overshoot (§3.3); apply at most one
   feature.
8. **Record** — the round row with the full movement payload (§8).
9. **Win or pass** — landing exactly on 100 sets `winner_user_id` and
   `status = 'completed'`; otherwise `current_turn_user_id` becomes the
   partner.
10. Return the whole turn so the client can animate it without a refetch.

### 9.2 What is NOT needed

- No penalty RPC (§5.4)
- No disclosure boundary (§8)
- No consent or tone (the game has no content)
- No question bank

That is roughly half of Paint Ball's server surface simply absent.

---

## 10. What this borrows from Paint Ball

Listed explicitly because it is the argument for building it.

| Borrowed | Where |
|---|---|
| Session lifecycle (invite/accept/decline/expire/hide) | `paint_ball_*_session` — copy with renames |
| Error envelope | `paint_ball_error` pattern |
| Turn guards (auth, turn, rate limit, idempotency) | `paint_ball_take_turn` steps 1–5 |
| The replay model | §4.3, wholesale |
| Auto-pop when the turn passes | `paint_ball_battle_screen` |
| Fixed dark palette | `PaintBallPalette` |
| Chat game card, moving sides | Already generic |
| Sound generation | `tool/generate_*_sounds.dart` |
| Contract-test shape | `paint_ball_v3_test.sql` |

**Genuinely new:** the board widget and its coordinate maths, token walk
animation, the die, and the feature config with its invariants.

Estimate: **three to five days.**

The first draft said one to two, reasoning from the server side where the
reuse is genuine. That was the wrong thing to measure. The board IS the
game, and it is entirely new: a 10×10 responsive grid, snake and ladder
curves drawn over it, a token that walks cell by cell, a die that tumbles,
the bounce, the zoom-on-move, reduce-motion summaries, five new sounds,
chat-card state, history, and the tests for all of it.

The server work is a day. The rest is the estimate.

---

## 11. Risks

**It is 100% luck, and that is the design.** The Paint Ball research
turned up a player calling that game "100% luck, one in three" as a
criticism. Here it is intentional — but it means the game has no
replay value beyond its mood. Accepted: this is a cool-off game, not a
centrepiece.

**Exact-finish can stall.** From 97 with bad rolls a player can bounce for
several turns. That is the classic frustration of the game. Mitigation:
the bounce is *visible* (walk up, pause, walk back), so it reads as the
board being cheeky rather than the app being broken.

**Board legibility on a small screen.** A 10×10 grid with numerals, two
tokens and nineteen features on a 5" phone is genuinely tight, and
"drop some numbers if testing shows it is noisy" was too vague to build
against. The rules, specified now:

- **Numbers are not the board's job.** Snakes and ladders are drawn
  *above* the cell grid, and the grid recedes to a hairline. A player
  reads the shape of the board, not its arithmetic.
- **Below 400dp width, label only every tenth cell** (1, 10, 20 … 100),
  plus the cell each token stands on and every feature head. That is the
  set a player actually looks for.
- **At 400dp and above**, all numerals, at reduced contrast.
- **During a move the path zooms**: the animating cells scale up slightly
  and the rest dims, so a walk is legible without the player hunting for
  a 20px square.
- Position readouts stay under the board (§6.1) as the reliable answer to
  "where am I", independent of whether a numeral is visible.

---

## 12. Open questions

1. ~~**Does an exact finish frustrate more than it delights?**~~
   **Settled: keep the bounce.**

   The alternative — any roll at or above the remaining distance wins —
   turns the final stretch into waiting rather than playing. The bounce
   is the only drama the game contains and it costs a few seconds.

   One softener: within six cells of home, the board says **"needs an
   exact roll"**. The frustration of bouncing is much smaller when it was
   expected, and much larger when it looks like the app is refusing to
   let you finish.
2. ~~**Should a session expire?**~~ **Settled: yes, on the shared
   schedule — 48h for an unaccepted invite, 24h of inactivity for an
   active game.**

   The first draft said Paint Ball expires after seven days and wondered
   whether this game should expire at all. The seven days was wrong:
   `20260715120000_paint_ball_launch.sql` uses 48 hours and 24 hours.

   Leaving these sessions open forever is also the wrong instinct, and
   for a reason specific to this game. It is the one people reach for
   after a conflict — so an abandoned board is *attached to a bad
   evening*, and a game card resurfacing weeks later would drag that
   evening back into the chat unannounced. Expiry is not housekeeping
   here; it is the same care the rest of the app takes about what gets
   raised and when.
3. ~~**Ludo instead, or as well?**~~ **Settled: no, not for this slot.**

   Ludo adds choice, but it also adds capture — sending your partner's
   token back to the start — and that is a small act of aggression aimed
   at the person you are trying to cool off with. It fights the one job
   this game has.

   A strategic board game may be worth building later. It is a different
   game with a different purpose, and it should not be smuggled in as a
   variant of this one.

---

## Changelog

- **2026-09-07** — Initial draft.
- **2026-09-07** — Revised after review. Six changes, five of them
  fixing real defects in the first draft:
  - **Idempotency moved before the rate limit and state checks** (§9.1).
    The draft would have returned `RATE_LIMITED` or `SESSION_EXPIRED` to
    a client retrying a roll the server had already recorded — including,
    possibly, the winning one. Paint Ball's shipped code already gets
    this right; the draft was a regression against it.
  - **`board_version` added** (§8). The draft claimed a tunable
    server-side board but gave a session no way to remember which board
    it was played on, so retuning would have silently rewritten the
    history of every finished game.
  - **Replay payload widened** to `rolled_to` and `movement_kind` (§8).
    A bounce and a snake both land below the die's target and must
    animate differently; the draft's fields could not tell them apart
    without re-deriving the board, which stops working once versions can
    differ.
  - **Expiry corrected and settled** (§12.2). The draft said Paint Ball
    expires after seven days. It does not — 48h invited, 24h inactive.
  - **First-turn rule added** (§4.1a), which the draft never stated.
  - **Legibility rules made concrete** (§11), replacing "drop numbers if
    testing shows it is noisy".

  Also: estimate revised from one-to-two days to three-to-five, and the
  three open questions settled. Still not implemented, not approved.

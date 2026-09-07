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
    CHECK (board_position_b BETWEEN 0 AND 100);
```

Turns are rows in `game_session_rounds`, one per roll:

```sql
ALTER TABLE public.game_session_rounds
  ADD COLUMN IF NOT EXISTS die_roll smallint
    CHECK (die_roll BETWEEN 1 AND 6),
  ADD COLUMN IF NOT EXISTS moved_from smallint,
  ADD COLUMN IF NOT EXISTS moved_to smallint,
  -- 'ladder' | 'snake' | null. What the replay animates.
  ADD COLUMN IF NOT EXISTS feature_kind text
    CHECK (feature_kind IS NULL OR feature_kind IN ('ladder', 'snake'));
```

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
2. **Rate limit** — a second roll within 1s is `RATE_LIMITED`.
3. **Idempotency** — a row already existing for
   `(session_id, round_number, active_partner_id)` returns its stored
   result. Critical here: a retried roll must never re-roll, or a player
   could reroll a bad number by killing the app.
4. **State** — `status = 'active'`, else `SESSION_EXPIRED`.
5. **Turn** — `current_turn_user_id = auth.uid()`, else `NOT_YOUR_TURN`.
6. **Roll** — `v_roll := floor(random() * 6) + 1`.
7. **Move** — advance; bounce on overshoot (§3.3); apply one feature.
8. **Record** — the round row with `die_roll`, `moved_from`, `moved_to`,
   `feature_kind`.
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

Estimate: **one to two days**, most of it the board and the walk.

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

**Board legibility on a small screen.** A 10×10 grid with numerals on a
5" phone is tight. Mitigations: position readouts under the board (§6.1),
tokens sized generously, and the numbers dropping to every-fifth-cell if
testing shows the full set is noise.

---

## 12. Open questions

1. **Does an exact finish frustrate more than it delights?** Alternative:
   any roll ≥ the remaining distance wins. Loses the tension, gains
   kindness. Worth a device test before committing.
2. **Should a session expire?** Paint Ball's games expire after seven
   days. A cool-off game abandoned mid-board is probably fine to leave
   open indefinitely — but an infinite session is a row that never
   closes.
3. **Ludo instead, or as well?** Ludo has real choices (which token to
   move, whether to send someone back) but needs 20–40 minutes and both
   players present, which breaks the asynchronous shape every other
   Attune game has. Recommendation: no, and if the itch is for choice,
   that is what Paint Ball is for.

---

## Changelog

- **2026-09-07** — Initial draft. Not implemented, not approved.

# ATTUNE — DOTS AND BOXES SPECIFICATION

**Status:** Revised after external review. **Not implemented, not
approved, and not recommended as the next build** — see §12 and §15.

**Reads with:** `SNAKES_AND_LADDERS_SPEC.md` (the lifecycle this reuses
wholesale), `WORD_HUNT_GAME_SPEC.md` (§5, what a server can and cannot
prove), `PAINT_BALL_GAME_SPEC.md` (§5.5, the disclosure boundary),
`GAMES.md` §5, `algorithms/algorithm_quality_review_checklist.md`.

---

## 1. What it is

A grid of dots. You take turns drawing one line between two adjacent
dots. Close the fourth side of a box and it is yours — **and you go
again.** When every line is drawn, whoever owns more boxes wins.

That second sentence is the whole game. Everything below follows from it.

### 1.1 Why this one

The third Arcade game, and the first with **skill in it**.

Paint Ball came from something real:

> *"I used to play with one of my exes and it made predicting and
> understanding their choices interesting — like they can choose to stay
> where they were shot consecutively without changing places, and that was
> something intriguing."*

That is the texture this game is for. Every move here is a small, legible
decision, and the endgame is a run of deliberate sacrifices where you can
watch someone choose: take the whole chain, or leave two boxes behind to
keep control. You learn something about how your partner plays without
the game ever asking either of you a question.

**No insight layer, and that is a rule rather than a note.** Same as
Snakes and Word Hunt: no reflection prompt, no score across sessions, no
analysis of who wins. What the game shows, it shows in the playing.

### 1.2 What it is not

- Not a compatibility signal. Nothing about the outcome means anything.
- Not scored across sessions. Nothing accumulates.
- Not luck. See §12 — this is the first Arcade game a person can be
  reliably better at, and that is a real risk rather than a feature.

---

## 2. Core characteristics

| Characteristic | Value |
|---|---|
| Duration | ~24 moves, across as many sittings as they like |
| Board | 3×3 boxes — 24 edges, 9 boxes |
| Skill | **Yes**, and increasing with practice. The first Arcade game like this. |
| Turn model | Asynchronous, alternating, **one edge per turn — unless you close a box** |
| Win condition | Most boxes when all 24 edges are drawn |
| Draws | **Impossible.** 9 is odd. See §3.2 |
| Penalty | None. No forfeit, no prompt, no consequence |
| Visual language | Snakes' and Paint Ball's: thin strokes on plain black |

---

## 3. The board

### 3.1 Geometry, stated exactly

A 3×3 grid of **boxes** means a 4×4 grid of **dots**, and:

- horizontal edges: 4 rows × 3 columns = **12**
- vertical edges: 3 rows × 4 columns = **12**
- total edges: **24**
- boxes: **9**

Counted rather than estimated, because every bound in §10 depends on it:
a game is exactly 24 moves' worth of edges, and the payload, the loop
bounds and the completion check are all sized from that number.

Addressing: an edge is `(orientation, row, col)` where orientation is
`h` or `v`. A horizontal edge `(h, r, c)` runs from dot `(r, c)` to
`(r, c+1)`, with `0 ≤ r ≤ 3` and `0 ≤ c ≤ 2`. A vertical edge `(v, r, c)`
runs from dot `(r, c)` to `(r+1, c)`, with `0 ≤ r ≤ 2` and `0 ≤ c ≤ 3`.
Box `(r, c)` for `0 ≤ r, c ≤ 2` is bounded by `(h,r,c)`, `(h,r+1,c)`,
`(v,r,c)` and `(v,r,c+1)`.

Canonical index: horizontal edges first in row-major order (0–11), then
vertical (12–23).

**One edge touches at most two boxes** — verified by enumeration, not
assumed — so a single move can close at most two. That bound matters for
§5.1's scoring loop and for the animation.

### 3.2 Why 3×3, and why draws are impossible

9 boxes cannot split evenly, so **every game has a winner**. A draw in a
two-person game is the least satisfying possible ending, and 4×4 and 6×6
— both even — would produce them regularly.

**This was 5×5 in the first draft, and the reason it changed is a
correction worth keeping.** That draft rejected 4×4 as "24 edges and
about three minutes, but draws become possible". 4×4 has **40** edges,
not 24. The board with 24 edges is 3×3, and it has 9 boxes — odd, so it
keeps the no-draw property the whole argument rested on. A product
decision was being made on a number nobody had checked.

With the arithmetic right, 3×3 is the better board:

| | edges | boxes | draws | moves per player |
|---|---|---|---|---|
| 3×3 | 24 | 9 | impossible | ~12 |
| 4×4 | 40 | 16 | possible | ~20 |
| 5×5 | 60 | 25 | impossible | ~30 |

**24 moves is the right size for an asynchronous game.** Sixty
server-recorded turns is a game two people play in one sitting, and the
"5 to 10 minutes" the first draft claimed quietly assumed both players
were live — which contradicts §4.2. A couple trading moves across a day
will finish a 3×3 board; they will abandon a 5×5 one.

It also fits one screen at the largest text setting on the smallest
supported device with room to spare, where 5×5 was tight (§12), and it
cuts the tap-target problem from 60 targets to 24.

### 3.3 Rendering

Snakes' visual language, unchanged: plain black ground, thin strokes,
no light mode. Dots are small filled circles in `#6E6E6E`. An undrawn
edge is not drawn at all — only its tap target exists. A drawn edge is a
2px stroke in the owner's colour: `#5EEAD4` for you, `#FF4D6A` for them,
matching every other Arcade game.

A captured box is filled at low alpha in its owner's colour with their
initial centred. **Colour is never the only signal** (§12): the initial
carries the same information, so the board is readable without colour
vision.

---

## 4. Turn structure

### 4.1 One edge, unless you score

You draw one edge. If it closed no box, the turn passes. If it closed one
or two boxes, **you draw again**, and keep drawing until a move closes
nothing.

A player can theoretically take all 9 boxes in a single turn from a
sufficiently bad position. That is a legal outcome, not an error, and
§10.3 is written so nothing in the server assumes a turn is one move.

### 4.2 Asynchronous, like everything else

Neither player need be present. A turn is a move sent to the server; the
partner sees it when they next open the game, or live if they have it
open. There is no clock on a move and no penalty for taking a day.

### 4.3 Who goes first

The **invitee**, matching Snakes §4.1a and for the same reason: they have
the app open and their attention on it. Handing the first move to the
initiator means the game's first action happens whenever they next look.

In this game that matters more than in Snakes, because moving first in
Dots and Boxes is a small but real disadvantage in the endgame at even
board sizes — and at 3×3 the parity works out the other way. Neither
effect is large enough to justify a coin flip that would make the rule
harder to explain.

### 4.4 The replay

On opening, a player sees the moves made since **they** last looked,
drawn in sequence: each edge appearing, each captured box filling.

**"Since they last looked" needs a server-side cursor**, and the first
draft did not say where it lived. Local state is not enough: reinstall,
a second device, or switching phones and the client either replays a
finished game from move one or replays nothing. So
`dots_boxes_state` carries `last_seen_move_a` and `last_seen_move_b`,
advanced by `get_dots_boxes_state` for the calling player only. Two
devices for one person converge on the same cursor, which is the right
answer: the second device shows nothing new because the person has
already seen it.

**Budget, not a move count.** Unseen moves animate individually within
about **1.5 seconds** total; beyond that the remainder snaps to the final
state. A chain of nine captures is a legitimate outcome (§4.1) and
animating each in turn is a cutscene rather than a replay. A `Skip`
control is always available, and `reduceMotionOf(context)` skips the
sequence entirely and renders the final board — the same rule every other
Attune animation follows.

**Summaries name the actor.** "Ama took 4 boxes", not "they took 4",
because during a chain the summary may span moves by one player only and
"they" is ambiguous once both have moved. Live moves — arriving while
the screen is open — always animate individually; there is nothing to
catch up on.

---

## 5. Rules

### 5.1 Scoring a move

Resolution is a **pure function** of the board and the edge:

```
resolve(board, edge, player) -> {
  boxes_closed: [(r, c), ...],   -- 0, 1 or 2 entries
  extra_turn:   boxes_closed is not empty
}
```

Pure and `IMMUTABLE`, the same shape as `snakes_resolve_move`, so it can
be tested without a session, a player or a clock.

**Not "exhaustively", which the first draft claimed.** Edge occupancy
alone is 2^24 states — sixteen million, and that is before considering
which player owns what. What IS enumerable is the thing that decides a
move: the **local configuration around the proposed edge**, which is at
most two boxes and three other edges each. That space is small (a few
hundred cases) and is enumerated in full. Whole games are covered by
property tests instead — play random legal games to completion and assert
the invariants of §8.2 hold at every step, which is a stronger statement
than any hand-written sequence.

### 5.2 An edge is drawn once

Drawing an already-drawn edge is not a move. It is refused as
`EDGE_TAKEN` and the turn does not pass — it was never a turn.

### 5.3 Ending

The game ends when all 24 edges are drawn. Whoever owns more boxes wins;
9 is odd so there is always exactly one winner.

**The ending is stated plainly and once.** "You took 14, they took 11."
No rematch pressure, no streak, no record — `Play again` is one tap and
that is the whole ceremony, matching Snakes §5.4 and Word Hunt §13.3.

### 5.4 Resigning

**A player may resign at any time.** It ends the game, the partner is
recorded as the winner, and the end screen says plainly that the game was
resigned — not that the scores were what they were.

The first draft got this wrong in both halves, and the correction is
worth keeping because the reasoning that produced it was superficially
sound.

**It restricted resignation to a player who was arithmetically
eliminated**, reasoning from Word Hunt's review that ending a game both
players are in is not one person's decision. That transfers the
conclusion without the reason. Word Hunt's decline was dangerous for two
specific reasons: it destroyed a partner's *in-progress* attempt, and it
released the hidden answer early. **Neither exists here.** There is no
secret, and nothing to destroy — the board is finished either way, and
the partner is credited with the win. What the restriction actually
achieved was trapping an unhappy player in a game for seven days with no
exit but silence, which is worse than the thing it was guarding against.

**It also reported a resignation as an ordinary score.** That is the
opposite of Word Hunt's actual lesson. There, a timeout and a surrender
read identically *because the distinction would have shamed someone for
using a kindness*. Here the distinction protects the person who did
**not** resign: telling them they won 6–3 when their partner in fact quit
is a small lie about their own game. Honest and neutral is "they
resigned" — a fact, with no verb suggesting cowardice.

The arithmetic-elimination check is kept, but only as UI copy: past that
point the button reads "concede" rather than "resign", because conceding
a decided game is a different act from quitting a live one.

---

## 6. Screens

**Lobby** — one line of what the game is, a Start button. Same shape as
Snakes' and Word Hunt's.

**Board** — the grid, both scores, whose turn it is by name (not "them" —
Paint Ball's correction). Nothing else.

**Waiting** — the breathing mark the session games use, the current score,
and an exit to chat. The screen leaves on its own when the partner moves,
matching Paint Ball and Snakes.

**End** — final scores, the completed board, `Play again` prominent and
`Back to chat` secondary.

---

## 7. The interaction

### 7.1 Tapping an edge

Edges are thin, and a 60-edge board on a phone means each tap target is
small. Three things make that workable, specified rather than left to
discovery:

- **The tap target is the gap, not the line.** Hit-testing assigns a tap
  to the nearest undrawn edge within a threshold, so the finger does not
  have to land on a 2px stroke.
- **Confirm-on-second-tap.** The first tap previews the edge as a dashed
  ghost; the second commits it. A misdrawn edge is unrecoverable — it is
  the whole move — so this game cannot use the tap-once model that Word
  Hunt's grid can.
- **Already-drawn edges are inert**, not error-flashing. Tapping one does
  nothing at all.

### 7.2 Feedback

| Moment | Feedback |
|---|---|
| Preview tap | Light haptic, dashed ghost edge |
| Commit tap | Medium haptic, the edge strokes in |
| A box closes | Success haptic, the box fills, the score ticks |
| Two boxes at once | One haptic, both fill together |
| Your turn ends | The turn indicator moves, no haptic |

### 7.3 Accessibility

Every edge is a semantics node labelled by position and state
("horizontal edge, row 2, column 3, undrawn"), activated through the
semantics tree rather than a competing gesture recogniser — the exact
mistake Word Hunt's board made twice and had to fix.

**The two-step commit has to exist in the semantics tree too, not only
under the finger.** §7.1's preview-then-confirm is a state machine, and
an assistive-technology user must be able to see and drive both states:

1. First activation previews. The node's label becomes "horizontal edge,
   row 2, column 3, **selected — activate again to draw**", and its
   action hint changes with it.
2. Second activation commits.

**The preview clears** — and announces that it has — when the turn
changes under realtime, when that edge is drawn by the partner first,
when the app backgrounds, or when focus moves to another node. Without
that, a second activation arriving a minute later commits a selection
made against a board that no longer exists, which is the one input error
this game cannot undo.

Score and turn are a live region. Captured boxes carry their owner's
initial so the board never depends on colour alone.

---

## 8. Data model

Reuses `game_sessions` with `game_type = 'dots_and_boxes'`. Nothing here
is secret — **there is no hidden information in this game at all** — so
unlike Word Hunt there is no private table and no disclosure boundary.
That absence is worth stating explicitly, because it is the reason this
spec is shorter than Word Hunt's and the reason its threat model is
smaller.

### 8.1 Board state

```sql
CREATE TABLE IF NOT EXISTS public.dots_boxes_state (
  session_id uuid PRIMARY KEY
    REFERENCES public.game_sessions(id) ON DELETE CASCADE,

  -- 24 entries indexed by the canonical edge ordering in §3.1:
  -- NULL = undrawn, otherwise the user_id who drew it.
  --
  -- OWNERS, NOT BOOLEANS. The first draft stored booleans while §3.3
  -- coloured each edge by who drew it -- and since the state payload
  -- returns only the recent moves, ownership of an older edge was
  -- unrecoverable. The board could not be rendered from the board.
  edge_owners uuid[] NOT NULL,

  -- 9 entries: NULL, or the user_id who closed that box.
  box_owners uuid[] NOT NULL,

  -- Denormalised so the lobby and end screen need not count arrays.
  score_a smallint NOT NULL DEFAULT 0,
  score_b smallint NOT NULL DEFAULT 0,

  moves_played smallint NOT NULL DEFAULT 0,

  -- Per-player replay cursors (§4.4). Server-side, because a local one
  -- breaks on reinstall, on a second device, and on a new phone.
  last_seen_move_a smallint NOT NULL DEFAULT 0,
  last_seen_move_b smallint NOT NULL DEFAULT 0,

  updated_at timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT dots_boxes_edges_len CHECK (cardinality(edge_owners) = 24),
  CONSTRAINT dots_boxes_owners_len CHECK (cardinality(box_owners) = 9),
  CONSTRAINT dots_boxes_scores CHECK (
    score_a BETWEEN 0 AND 9 AND score_b BETWEEN 0 AND 9
    AND score_a + score_b <= 9
  ),
  CONSTRAINT dots_boxes_moves CHECK (moves_played BETWEEN 0 AND 24),
  CONSTRAINT dots_boxes_cursors CHECK (
    last_seen_move_a BETWEEN 0 AND moves_played
    AND last_seen_move_b BETWEEN 0 AND moves_played
  )
);
```

### 8.2 The constraints that make an impossible board impossible

The lengths and ranges above still permit a row that cannot exist: ten
drawn edges with `moves_played = 3`, a score that disagrees with
`box_owners`, a closed box with no owner, an owner who is not in the
relationship. RPC-only access stops a hostile client writing those — it
does not stop an implementation bug or a bad migration writing them, and
a corrupt board is the failure a player would report as "the game broke".

So the following are enforced by a trigger, not left to the RPC:

- `moves_played` equals the count of non-null `edge_owners`
- `score_a + score_b` equals the count of non-null `box_owners`
- every owner in either array is one of the relationship's two members,
  and matches the `score_a`/`score_b` assignment
- a box is owned **iff** all four of its edges are drawn (§3.1's formula)
- a terminal session has 24 drawn edges and 9 owned boxes

The last two are the load-bearing ones: together they mean the score is
derivable from the board, so the denormalised counters can never drift
away from the thing they summarise.

### 8.3 Moves

**A dedicated table, not `game_session_rounds`.**

The first draft said moves would reuse the shared rounds table "matching
Snakes". They cannot, and the claim was asserted rather than checked:
that table has no column for an edge index, for the boxes a move closed,
or for whether the turn passed. It is already thirty-plus columns wide
because four previous games each grafted their own fields onto it —
`hide_position` and `shot_position` from Paint Ball, `die_roll` and
`movement_kind` from Snakes, `chosen_type` and `answer_a` from the
question games. Adding four more would make this the fifth, and every one
of those columns is `NULL` for every other game's rows.

```sql
CREATE TABLE IF NOT EXISTS public.dots_boxes_moves (
  session_id uuid NOT NULL
    REFERENCES public.game_sessions(id) ON DELETE CASCADE,

  -- Assigned by the SERVER, not the client. See §10.3.
  move_number smallint NOT NULL,

  player_id uuid NOT NULL REFERENCES public.users(id),

  -- The client's idempotency key for this action.
  action_id uuid NOT NULL,

  edge_index smallint NOT NULL,
  boxes_closed smallint[] NOT NULL,
  turn_passed boolean NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),

  PRIMARY KEY (session_id, move_number),
  CONSTRAINT dots_boxes_move_edge CHECK (edge_index BETWEEN 0 AND 23),
  CONSTRAINT dots_boxes_move_number CHECK (move_number BETWEEN 1 AND 24),
  CONSTRAINT dots_boxes_move_closed CHECK (
    cardinality(boxes_closed) BETWEEN 0 AND 2
  ),
  -- turn_passed is exactly "closed nothing", so the two cannot disagree.
  CONSTRAINT dots_boxes_move_turn CHECK (
    turn_passed = (cardinality(boxes_closed) = 0)
  )
);

-- One action_id per session: the idempotency key.
CREATE UNIQUE INDEX dots_boxes_moves_action
  ON public.dots_boxes_moves(session_id, action_id);

-- One edge drawn once, enforced by the database rather than by the RPC
-- reading the array and hoping.
CREATE UNIQUE INDEX dots_boxes_moves_edge
  ON public.dots_boxes_moves(session_id, edge_index);
```

### 8.4 Retention

Expiry abandons a session; it does not delete these rows. The board holds
no secret, but the moves are relationship data — who played, when, and
how — so they inherit the shared game-session retention policy rather
than having one of their own, and are deleted when the relationship is
deleted (`ON DELETE CASCADE` from `game_sessions`).

The state RPC returns only what the client draws: the board, the scores,
the turn owner and the replay window. It does not return per-move
timestamps, which the client has no use for and which would turn a game
board into an activity log.

### 8.5 RLS

Read is open to both partners — the board is public by definition.

**Write is RPC-only**, and `dots_and_boxes` must be named in every
`game_type NOT IN (...)` carve-out on `game_sessions` and
`game_session_rounds`, in both `USING` and `WITH CHECK`.

This is not a precaution. It is the same defect Snakes shipped and Word
Hunt reproduced before fixing: **the shared policies are permissive by
default, so a new `game_type` inherits write access unless it opts out.**
Without the carve-out a player can `UPDATE game_sessions SET status =
'completed', winner_user_id = me`, which makes every other control in
this game decorative. A contract test must prove the three writes are
refused, and prove an unrelated legacy game still has its intended
access.

### 8.6 Table grants

`dots_boxes_state` and `dots_boxes_moves` are written only by
`SECURITY DEFINER` RPCs. `authenticated` gets `SELECT` and nothing else,
and the REVOKE is repeated in the file replayed by
`scripts/local_pg_grants.sql` after its blanket grant — otherwise the
local harness silently re-grants write access and the contract test
passes or fails by script ordering rather than by the schema.

---

## 9. What the server proves, and what it does not

Short, because there is little to say: **this game has no hidden
information.** Both players see the whole board. There is nothing to
withhold, nothing to leak, and no equivalent of Word Hunt's problem where
the client is handed both the puzzle and the answer.

What the server enforces:

- the edge is in range and not already drawn
- it is the caller's turn
- boxes closed and the extra-turn rule are computed **server-side** from
  the stored board, never accepted from the client
- the winner is derived from the box counts, never sent

A modified client can compute good moves — it is a perfect-information
game, so of course it can. That is not cheating, it is thinking, and a
player using a solver is a relationship question rather than a security
one. The copy therefore never claims the outcome proves anything.

---

## 10. Server contract

### 10.1 Lock order, and the re-check that the order alone does not give you

Every mutating RPC takes the **session row** `FOR UPDATE` first, then the
state row. One order, everywhere, including the expiry sweep and the
relationship-change trigger.

Stated first because Word Hunt's review found exactly this inverted:
gameplay locked session-then-attempt while expiry wrote
attempts-then-sessions, and it deadlocked.

**A single lock order prevents deadlock. It does not prevent staleness,
and the first draft of this section confused the two.** The sweep selects
the sessions it considers stale, then waits on a lock a live move is
holding. When it gets the lock, the move has committed and the session is
no longer stale — but the sweep is still working from the set it chose
before it waited, and abandons a game somebody is playing.

So every function that closes a session must **re-read the staleness
predicate after acquiring the lock**, and skip the session if it no
longer holds. That is a separate requirement from the lock order, it is
the fix Word Hunt needed *after* its lock order was corrected, and it has
its own contract test (§10.9).

### 10.2 Mutation order

**auth → session lock → membership → idempotency → relationship-active
and lazy expiry → turn check → move validation → mutation.**

The first draft put "relationship active" third, before idempotency, and
that **contradicted the retry guarantee in the same paragraph**: a move
that committed successfully could not be recovered by a retry once the
relationship was archived, because the retry would be rejected before it
reached the idempotency check. A committed action must be readable
afterwards regardless of what has happened to the relationship since.

Membership stays early — a non-member gets `FORBIDDEN` before anything
else — but membership and relationship-*state* are different questions,
and only the first gates the retry path.

`v_now := clock_timestamp()` is captured **after** the lock. `now()` is
transaction-start time and can predate a lock wait, which Word Hunt's
review found producing a `completed_at` earlier than the move that caused
it.

### 10.3 `dots_boxes_draw_edge(p_session_id, p_action_id, p_edge_index)`

One edge, by its canonical index `0..23`.

**The move number is assigned by the server, never sent by the client.**
The first draft took a client-supplied `p_move_number` and never said it
had to equal `moves_played + 1`, be bound to the caller, or be bound to
the edge — so a client could submit move 24 first, and reusing a number
with a different edge had no defined behaviour at all. The client sends
an `action_id` (a UUID it generates once per intended move and reuses on
every retry); the server assigns `move_number = moves_played + 1`.

- **Idempotent on `(session_id, action_id)`**, checked first, before every
  other rejection. A retry returns that move's stored result.
- **A reused `action_id` with a different `p_edge_index` is
  `IDEMPOTENCY_CONFLICT`**, not a silent replay of the first move and not
  a second move. The stored row carries the edge, so the two can be
  compared rather than assumed equal.
- Refuses `NOT_YOUR_TURN`, `EDGE_TAKEN`, `INVALID_INPUT` (index outside
  `0..23`, or not an integer — validated *before* any cast, so a decimal
  or oversized value is a structured error rather than a raw SQL
  exception, which Word Hunt's review found leaking Postgres type names
  to the client).
- Computes boxes closed with the pure resolver, then writes the edge
  owner, the box owners, the scores and `moves_played`.
- **The turn passes only if nothing was closed.** The caller keeps the
  turn otherwise.
- On the 24th edge: sets `status = 'completed'`, `completed_at` from the
  post-lock timestamp, and `winner_user_id` from the box counts.

Returns the move's result and the new board.

### 10.4 `dots_boxes_resign(p_session_id)`

Refused unless the caller is arithmetically eliminated (§5.4). Ends the
session, records the partner as winner, and is idempotent.

### 10.5 `get_dots_boxes_state(p_session_id)`

Board, scores, whose turn, and the last 12 moves for the replay —
bounded, so a finished game is a finite payload rather than 60 rows.

Performs lazy session expiry, so a client arriving from a push
notification without passing the lobby cannot act on a stale session.
Word Hunt shipped that gap: expiry lived only in the lobby lookup, and a
50-hour-old invitation could still be accepted during the cron gap.

### 10.6 Lifecycle

Create, accept, decline, active-session lookup — Snakes' shapes exactly,
with two rules its review taught:

- **Decline means decline an INVITATION.** Once both players are in,
  leaving is not one person's decision. Word Hunt's review found the
  unrestricted version let either partner destroy a live game and be
  handed the answer; here there is no answer to be handed, but destroying
  a partner's in-progress game is the same wrong.
- Accepting activates the session and assigns the first turn to the
  invitee (§4.3).

### 10.7 Expiry

48h for an unaccepted invitation, 7 days of inactivity for an active
game — longer than Snakes' 24h because this game is genuinely played
across days.

Cron **and** lazily on every RPC. And the cron job must actually be
registered: writing Word Hunt's sweep turned up that
`expire_snakes_sessions()` had shipped written, granted and never
scheduled, so abandoned boards blocked every future game between those
two people forever. A contract test asserts the registration exists.

### 10.8 Required contract tests

The backend is not complete until SQL tests prove all of these against
the `authenticated` role, not by inspecting function source:

- direct INSERT, UPDATE and DELETE of a `dots_and_boxes` session row are
  denied, while an unrelated legacy game keeps its intended access
- direct write to `dots_boxes_state` is denied
- unauthenticated and non-member calls to every RPC are denied
- the resolver over **every local configuration** around a proposed edge
  (§5.1) — not "every board state", which is 2^24 — plus property tests
  playing random legal games to completion and asserting §8.2's
  invariants after every move
- a reused `action_id` with the same edge replays; with a **different**
  edge it returns `IDEMPOTENCY_CONFLICT`
- a client cannot influence `move_number`; the server assigns it
- the state trigger refuses every impossible board in §8.2: a score that
  disagrees with `box_owners`, an owned box missing an edge, an owner who
  is not a relationship member, `moves_played` out of step with
  `edge_owners`
- the replay cursor advances per player, and a second device for the same
  player sees nothing new
- an edge cannot be drawn twice, and the failed attempt does not pass the
  turn
- closing a box keeps the turn; closing nothing passes it
- a full chain — one player closing many boxes in one turn — leaves the
  turn with them throughout and the score correct at the end
- the 24th edge completes the session exactly once, with a winner derived
  from the counts
- concurrent draws by both players produce one legal board and one turn
  owner
- a retried move returns its stored result before turn, range and
  terminal-state checks
- resign is permitted at any time, records the partner as winner, is
  idempotent, and the result is reported **as a resignation** rather than
  as a score
- session expiry is enforced by every RPC, not only the lobby
- the expiry sweep is registered with cron
- non-integer, decimal and out-of-range edge indices return
  `INVALID_INPUT` rather than a raw SQL error
- `completed_at` never precedes the move that caused it

### 10.9 Concurrency contracts

Three of the above cannot be written inside the single-transaction SQL
suite, because a lock race needs two connections. They belong in
`scripts/concurrency/`, run by the local harness, exactly as Word Hunt's
do:

- gameplay against the expiry sweep does not deadlock
- **a sweep that selected a session, then waited on a live move's lock,
  does not abandon the now-fresh session** — the under-lock re-check of
  §10.1, which the lock order alone does not give
- a move landing during a sweep does not leave a half-closed session
- a draw racing relationship teardown leaves session and state agreeing
- two simultaneous draws resolve to one board with one turn owner

---

### 10.10 Checklist obligations, answered at design time

The items the Algorithm Quality Review Checklist expects a **design** to
answer, answered here rather than discovered during implementation. Items
that only a built system can evidence — coverage, benchmarks, soak — are
listed in §14 as outstanding rather than claimed.

**1.1 Idempotency.** Every mutation carries a move number or an
idempotency key, and the retry check runs before every other rejection
(§10.2, §10.3).

**1.2 Timeouts.** The client gateway bounds every RPC at **30 seconds**
total, matching Snakes and Word Hunt. The checklist asks for distinct
connect, read and total values; the Supabase Dart client exposes a single
total timeout, so **connect and read are not separately bounded and this
item is partially met, not met.** Carried as a known gap across every
Attune feature rather than claimed here. Without the total bound a
stalled connection leaves a player staring at a board whose turn may
already have passed.

**1.3 Graceful degradation.** There are exactly two dependencies:
Postgres and the realtime channel. If realtime is down the board still
works — every screen refetches on open, on resume and after every move,
and the live channel only removes the need to tap. If Postgres is
unreachable the RPC times out and the UI says so with a retry.

**No move is ever COMMITTED locally.** The first draft said "no move is
ever applied locally", which contradicted §7.1's committed-looking
preview two pages earlier. The preview is a local, reversible drawing
that is explicitly not a move: it renders under the round trip and is
rolled back if the server refuses. What never happens is a move being
treated as *made* before the server says so, because in a turn-based game
that shows the player a board their partner does not have.

**1.9 Consistency model.** Read-your-writes, by construction: every
mutation returns the new board, and the client renders the response
rather than re-fetching. Between players it is eventual, bounded by the
realtime channel or the next open. Nothing is cached beyond the current
screen's state — there is no client-side board cache to invalidate,
which is a decision rather than an omission: a stale board in a
turn-based game is worse than a spinner.

**3.9 / 3.10 Retry policy.** Mutations are **not** retried
automatically. They carry an `action_id` so a *user-initiated* retry is
safe, and the UI offers that retry rather than performing it — because a
silent retry of a move whose response was merely slow shows the player
their move failing and then appearing. Reads retry once on transport
failure. Neither retries a 4xx-equivalent: `NOT_YOUR_TURN`,
`EDGE_TAKEN`, `FORBIDDEN` and `INVALID_INPUT` are permanent and
retrying them is noise.

**5.4 Retry UX.** Because every mutation is idempotent on `action_id`,
the failure copy can say so: "That didn't send. Try again." — with the
retry reusing the same id, so a move that in fact reached the server is
recovered rather than duplicated.

**1.6 Concurrency.** One lock order everywhere (§10.1), and the three
races that need two connections are contract-tested outside the
single-transaction suite (§10.9). This item is written this explicitly
because the equivalent claim in Word Hunt's audit was **false** — it
asserted one lock order on the strength of gameplay-versus-gameplay races
only, and expiry inverted it.

**1.7 Statelessness.** All state is in Postgres. No server-side session
affinity, nothing cached between calls.

**1.8 Complexity.** Every operation is bounded by the board, which is a
constant: 24 edges, 9 boxes. `resolve` is O(1) — at most two boxes to
check, four edges each. A move is O(1) array writes. The state payload is
O(1) plus at most 12 replay rows. Nothing here grows with the number of
games played, users, or time.

**1.10 Rollback.** Each RPC is a single transaction. A partial move
cannot exist: the edge, the box owners, the score and the turn all commit
together or not at all. No saga, no compensating write, no cleanup path
— which is the reason to prefer one transaction here over an
event-sourced design that would need one.

**1.11 Privacy.** No PII in this feature beyond the user ids already on
`game_sessions`. The board is not personal data. Nothing is retained
after session expiry beyond what the shared game tables already keep.

**2.1 / 2.5 Input and limits.** One input: an integer edge index. Range
checked, integer-checked **before any cast** (§10.3). Loops are bounded
by the 24-edge constant. There is no unbounded collection, no
pagination-needing list, and no client-supplied size anywhere.

**2.2 Parameterized queries.** No dynamic SQL. No string interpolation
into a query anywhere in this feature.

**2.4 / 5.5 Error messages.** One shared error function returning a fixed
set of codes and user-facing sentences — never a Postgres message, never
a type name, never a schema detail. Word Hunt leaked exactly that through
an unvalidated cast, which is why §10.3 validates before casting.

**3.1 / 3.3 Queries and indexes.** Two access patterns: by session id
(primary key) and by relationship for the lobby. Both need a partial
index of the shape `(relationship_id, game_type, status) WHERE game_type
= 'dots_and_boxes'`, matching Paint Ball's — and the expiry sweep needs
`(status, created_at)` on the same predicate. `EXPLAIN` output is
attached to the implementation PR, not assumed: Word Hunt shipped a
sequential scan on its sweep because nobody ran it.

**3.8 Rate limiting.** The shared five-games-per-hour initiation limiter
covers session creation.

The first draft said moves need no limiter because "your partner is the
natural rate limit". **That is false in two ways.** During a chain a
player holds the turn for many consecutive moves, so nothing external
paces them; and an invalid request — a taken edge, a wrong turn — is
refused but still costs a round trip, so a client can spam regardless of
whose turn it is. A 300ms floor between accepted moves from one player,
and a shorter one on rejected requests, matching Word Hunt's limiter.
Abuse protection, not an anti-cheat claim.

**4.x Observability.** This feature emits no structured logs, metrics or
alerts, and neither does any other Attune game. That is a **known gap
carried across the whole games surface**, not something this spec solves
alone, and it is listed in §14 as outstanding rather than quietly marked
passing.

**5.1 Error copy.** Each error code maps to a sentence that says what to
do: `NOT_YOUR_TURN` → "It's their move." `EDGE_TAKEN` → "That line is
already drawn." `SESSION_EXPIRED` → "This game expired. Start a new one."

**5.2 Latency.** The interaction target is first feedback within 200ms:
the preview ghost draws on the first tap **locally**, before any network
call, so the round trip happens under a committed-looking edge. The
server round trip itself is not on the 200ms path and must not be
claimed to be.

**6.6 Determinism.** There is no randomness in this game at all — no die,
no generated board, no shuffled content. Every test is deterministic by
construction, which is not true of Snakes or Word Hunt and is worth
having in the suite.

**7.6 CSRF/CORS.** Not applicable: native mobile only, no browser
surface. Documented as skipped per the checklist's instruction.

**2.3 Constant-time comparison.** Not applicable — this feature compares
no secrets. There is no token, signature, password or API key in the
whole game. Documented as skipped rather than left silent, because a
blocking item with no note reads the same as a blocking item nobody
checked.

**2.7 / 2.8 / 2.9 Secrets.** None introduced. No key, no token, no
connection string, no new `.env` entry. The feature reaches Postgres
through the Supabase client the app already holds.

**2.10 Resource release.** Two things to release, both on the client: the
realtime channel and the animation controllers. The channel is disposed
with its provider — Attune already leaked one of these once, which is why
`gameSessionLiveProvider` disposes explicitly — and every controller is
disposed with its widget. Server-side there is nothing to release: each
RPC is one transaction and Postgres owns the connection.

**7.1 / 7.2 / 7.3 / 7.5 Scanning and transport.** Inherited, not solved
here: dependency scanning, SAST, secret scanning and TLS are
repo-and-platform level. This feature adds no dependency and no network
call of its own.

---

## 11. What this borrows

| Borrowed | From |
|---|---|
| Session lifecycle, error envelope, idempotency keys | Snakes |
| RPC-write-only carve-out | The Snakes security fix, via Word Hunt |
| Lock order, post-lock timestamp, lazy expiry at every entry point | Word Hunt's review |
| Pure resolver tested by enumeration | `snakes_resolve_move` |
| Auto-pop, live sync, breathing wait | Snakes / session games |
| Board palette and stroke language | Paint Ball / Snakes |
| Sound generation | `tool/generate_*_sounds.dart` |

**Genuinely new:** the box-closing resolver, the extra-turn rule and
everything it implies for the turn model, the edge hit-testing, and the
chain replay.

Estimate: **seven to ten working days, plus device testing.**

The first draft said four to six, reasoning that the absent things —
hidden state, a private table, a disclosure boundary, a generator — made
this cheaper than Word Hunt. A review pointed out that the argument only
counted what was missing. What is *present* is mostly new: the turn
machinery around the extra-turn rule, two new tables with a
consistency-enforcing trigger, a per-player replay cursor, a two-step
commit that has to exist in the semantics tree as well as under the
finger, and the chain animation with its budget and skip. The lifecycle
reuse from Snakes is real; almost nothing else is.

Four to six days is a happy-path prototype. It is not a build anyone
should trust with a couple's Saturday evening.

---

## 12. Risks

**This is the first Arcade game a person can be reliably better at, and
that may disqualify it from this slot.**

Snakes is pure luck and Word Hunt is near-luck, so nobody loses because
they are worse. Dots and Boxes has a known optimal strategy — chain
parity — and a partner who learns it wins essentially every game against
one who has not. The slot exists because *"after a conflict we just want
to play games and cool off."* Losing ten in a row to your partner is not
cooling off.

The first draft called this "not a reason to cut it" and listed three
mitigations: neutral copy, nothing recorded across sessions, `Play again`
prominent. **A review pushed back on exactly that, and it is right.**
Cosmetic copy does not stop one person repeatedly beating the other. The
mitigations address how the result is *described*, not the fact that the
same person keeps producing it.

Two things follow, and they are the reason this spec is not a
build-it-now recommendation:

- **3×3 is a genuine mitigation, not only a length decision.** A 24-edge
  board has far less room for chain-parity play than a 60-edge one. The
  skill gap is real at 5×5 and small at 3×3, which is a second
  independent argument for the smaller board.
- **It should be prototyped and played by real couples before it ships**
  — specifically after mild conflict, which is the condition the slot is
  for. If one partner wins every time, the honest answer is that this
  game does not belong in this slot, whatever its other qualities.

**And the gap it does not fill remains the more interesting one.** Paint
Ball, Snakes, Word Hunt and this all have a winner or a comparison. The
Arcade has no **co-operative** game — nothing where both players win or
both lose together — and that, not a fourth competition, is what a
cooldown slot is missing. Building this next would be the third
competitive game in a row.

**The Arcade is now entirely competitive.** Paint Ball, Snakes, Word Hunt
and this all have a winner or a comparison. The genuinely missing thing
is a **co-operative** game where both players win or both lose together,
and this spec does not address that gap. Worth naming here so it is not
forgotten.

**24 tap targets on a phone.** At ~340dp of usable width a 3-box board
gives each edge a span of about 113dp and a stroke a few dp wide — so the
*length* is generous and the *thickness* is the whole problem, which is
what nearest-edge hit-testing exists for. Measured rather than guessed:
the first draft of this line said 40dp for a 5×5 board and was wrong
twice over. Mitigated by nearest-edge hit-testing, confirm-on-second-tap,
and the accessible path in §7.3 — and tested on the smallest supported
device at the largest text setting, since both shrink the board.

**A long chain is a long animation.** One player can close twenty boxes
in a turn. The replay is bounded at 12 moves and summarises beyond that
(§4.4), or the partner opens the game to a forty-second cutscene.

**Resign is a partial answer.** §5.4 only offers it once the outcome is
arithmetically decided, which means a player in a losing-but-not-lost
position has no exit except walking away and letting expiry take it.
That is the correct trade — the alternative lets one person end a game
the other is enjoying — but it is a rough edge, not an elegance.

---

## 13. Questions, open

Three, and they are genuinely open rather than rhetorical.

1. ~~**Is 5×5 the right size?**~~ **Settled: 3×3.** The first draft
   compared 5×5 against a 4×4 board it believed had 24 edges. 4×4 has
   40. The 24-edge board is 3×3, it has 9 boxes, and 9 is odd — so it
   keeps the no-draw property the whole argument depended on while
   halving the game. See §3.2.

2. ~~**Should the first move alternate between games?**~~ **Settled:
   yes, on rematch.** The invitee starts the first game (§4.3); each
   rematch flips it. `game_sessions` stores `starting_user_id` and a
   rematch links to the session it followed, so the alternation survives
   a reinstall and does not depend on who taps `Play again` first.

3. ~~**Should a chain be animated move-by-move, or resolved at once?**~~
   **Settled: a time budget, not a move count.** ~1.5 seconds of
   individual animation, then snap, with `Skip` always available and
   reduced-motion skipping entirely (§4.4).

---

## 14. What this spec does NOT claim

Listed so a reviewer spends their pass on what has not been thought about
rather than rediscovering what has. Every item here is a **failure**
against the checklist, not a pass, and none is resolved by writing more
spec — they need a built system, a device, or an ops decision.

**Cannot be evidenced until it is built:**

- branch coverage against the checklist's targets (6.7)
- mutation testing on the resolver and the turn machinery (6.8)
- a performance benchmark for the move path (6.9)
- 24-hour soak and 2× load behaviour (6.10, 6.11)
- chaos testing with Postgres killed mid-move (6.12)
- `EXPLAIN` output for both access patterns (3.3)

**Cannot be evidenced without a device:**

- first-feedback latency actually measured at p95 (5.2)
- the 24-target board at the smallest supported size and largest text
  setting (§12)
- screen-reader navigation of 60 edge nodes, which is the part of §7.3
  most likely to be unpleasant in practice and cannot be judged from code

**Not solved here, and not solvable here:**

- **Observability (4.1–4.14).** No structured logs, no metrics, no
  alerts, no runbook — for this game or any other Attune game. A
  games-wide gap that one spec should not pretend to close.
- **Rollback and smoke tests (8.1, 8.2).** Deployment concerns shared
  with every migration in the project.
- **The Arcade has no co-operative game.** Named in §12 and unaddressed.

**Open by choice:** the three questions in §13.

## 15. Recommendation

**Do not build this next.**

The spec is sound enough to build from — twelve review findings are
folded in and the arithmetic is now checked rather than asserted. That is
not the same as it being the right thing to build.

Three reasons, in order:

1. **The slot's purpose argues against it.** Three of the four Arcade
   games would then have a winner, and the one thing a cooldown slot is
   actually missing is a **co-operative** game. Building a fourth
   competition — and the first skill-dominant one — is moving away from
   what the Arcade is for.

2. **The skill risk is unresolved, not mitigated.** §12 is honest that
   neutral copy does not stop one partner winning every time. 3×3 helps.
   Nothing in this spec proves it helps enough, and that is not a
   question a spec can answer.

3. **It is seven to ten days plus device testing**, which is a real
   fraction of the remaining runway, spent on the least differentiated
   thing in the app. Dots and Boxes is a game anyone can play anywhere.
   Paint Ball came out of something specific to this couple's history;
   this did not.

**What to do instead, in order:**

- **Design a co-operative Arcade game.** The genuine gap. Both players
  win or lose together, so a skill difference stops being a way to lose
  to your partner and becomes a way to help them.
- **If this game is still wanted, prototype 3×3 first** — a throwaway
  build, played by real couples, specifically after mild conflict. If one
  partner wins every time, the answer is that it does not belong here.
- **Only then build it properly**, against this spec.

Written down because the work of specifying something is exactly what
makes it feel inevitable, and it is not.

---

## Changelog

- **2026-09-08** — Revised after an external implementation review of the
  first draft. Twelve findings, all confirmed before being applied:

  - **The board was wrong on arithmetic.** The draft chose 5×5 partly by
    rejecting 4×4 as "24 edges"; 4×4 has 40. The 24-edge board is 3×3,
    with 9 boxes — still odd, so draws stay impossible. Now 3×3, which is
    also a genuine mitigation for the skill risk rather than only a
    length decision.
  - **The stored board could not render itself.** Edges were booleans
    while §3.3 coloured them by owner, and with a bounded replay window
    older ownership was unrecoverable. Now `uuid[24] edge_owners`.
  - **Move identity was undefined.** A client-supplied move number, never
    bound to the caller, the edge, or `moves_played + 1`. Now a
    client `action_id` with a server-assigned move number, and a reused
    id with a different edge is `IDEMPOTENCY_CONFLICT`.
  - **The mutation order contradicted its own retry guarantee** by
    checking relationship-active before idempotency.
  - **One lock order does not close the expiry race.** The sweep can
    select a session, wait on a live move's lock, and then abandon a game
    somebody is playing. The under-lock re-check is a separate
    requirement, and was the fix Word Hunt needed *after* its lock order
    was corrected.
  - **`game_session_rounds` reuse was asserted, not checked.** That table
    has none of the columns this game needs and is already thirty-plus
    columns wide from four previous games. Now a dedicated
    `dots_boxes_moves`.
  - **The state constraints permitted impossible boards** — scores
    disagreeing with owners, owned boxes missing edges. Now a trigger.
  - **Resign over-applied Word Hunt's lesson**, trapping an unhappy
    player for seven days, and then reported a resignation as an ordinary
    score, which is a small lie to the person who did not resign.
  - **Four §10.10 claims were unsupported**: exhaustive enumeration of
    2^24 states, "your partner is the natural rate limit" (false during a
    chain), a single timeout satisfying a three-value requirement, and
    "no move applied locally" contradicting the committed-looking preview
    two sections earlier.
  - **The replay had no durable cursor**, so a reinstall or a second
    device replayed the wrong thing.
  - **The accessible path had no two-step state machine**, so a delayed
    second activation could commit against a board that no longer exists.
  - **Retention was unstated** for per-move relationship data.

  Estimate raised from four-to-six days to seven-to-ten plus device
  testing: the first figure counted what this game does not have rather
  than what it does. §15 added, recommending it is **not** built next.

- **2026-09-08** — Initial draft. Not reviewed, not approved, not
  implemented. Written after Word Hunt's external review, so its ten
  findings are folded in as requirements rather than as things to
  rediscover: the RPC-write-only carve-out (§8.1), one lock order
  everywhere (§10.1), post-lock timestamps (§10.2), lazy session expiry
  at every entry point (§10.5), decline restricted to invitations
  (§10.6), a registered cron sweep (§10.7), coordinate validation before
  casting (§10.3), and concurrency contracts that need two connections
  (§10.9).

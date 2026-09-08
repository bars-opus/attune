# ATTUNE — DOTS AND BOXES SPECIFICATION

**Status:** Revised after two adversarial reviews. **Not implemented, not
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

Another Arcade game, and the first with **skill in it**.

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

9 boxes cannot split evenly, so **every completed game has a winner**.
Even-sized boards permit draws; this spec makes no unsupported claim about
how frequently real players would produce one.

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

**24 moves is the chosen prototype size for an asynchronous game.** Sixty
server-recorded turns is a game two people play in one sitting, and the
"5 to 10 minutes" the first draft claimed quietly assumed both players
were live — which contradicts §4.2. The smaller board reduces remote
handoffs; whether couples actually finish it is a product-test question.

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

Persistence uses relationship slots A/B, not user UUIDs (§8.1). The
client maps those slots to viewer-relative colours and current display
names; if an account has been deleted, the initial falls back to a neutral
person marker rather than exposing or requiring the former identity.

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

That rule applies to the first game only. A rematch gives first move to
the player who did **not** start the previous game (§10.6). The spec makes
no unproved claim about which player 3×3 favours; alternating is cheap,
legible fairness regardless of what optimal play eventually shows.

### 4.4 The replay

On opening, a player sees the moves made since **they** last looked,
drawn in sequence: each edge appearing, each captured box filling.

**"Since they last looked" needs a server-side cursor**, and the first
draft did not say where it lived. Local state is not enough: reinstall,
a second device, or switching phones and the client either replays a
finished game from move one or replays nothing. A private
`dots_boxes_replay_cursors` row stores one monotonic cursor per player.

Fetching does **not** advance it. `get_dots_boxes_state` returns every
move after the cursor (at most 24), with no timestamps, plus the current
board. Only after the client has rendered the final board — whether it
played, skipped or suppressed the animation — does it call
`dots_boxes_ack_replay`. This avoids the lost-response hole where a read
advances the cursor but its payload never reaches the phone. Two devices
converge after acknowledgement: an earlier acknowledgement can never move
the cursor backwards.

This provides **at-least-once**, not exactly-once, replay across devices.
Two devices that fetch before either acknowledges may both animate the
same moves. Avoiding that would require a lease and would make a harmless
duplicate animation capable of blocking replay entirely.

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

**The ending is stated plainly and once.** "You took 5, they took 4."
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
secret, and the partial board remains viewable rather than being disclosed
or erased; the partner is credited with the win. What the restriction actually
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
a decided game is a different act from quitting a live one. Here
`remaining = 9 - score_a - score_b`, and the outcome is decided when
`opponent_score > my_score + remaining`; this does not gate the RPC.

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

Edges are thin, and even a 24-edge board on a phone means each tap target is
small. Three things make that workable, specified rather than left to
discovery:

- **The tap target is the gap, not the line.** Hit-testing finds the
  nearest edge of either state within a logical-dp threshold. If that edge
  is already drawn, it consumes the tap and does nothing; the algorithm
  must not skip it and unexpectedly select a nearby undrawn edge. At an
  exact geometric tie it keeps the current preview, or selects nothing if
  there is no preview.
- **Confirm-on-second-tap.** The first tap previews the edge as a dashed
  ghost; the second commits it. A misdrawn edge is unrecoverable — it is
  the whole move — so this game cannot use the tap-once model that Word
  Hunt's grid can.
- The second tap commits only when it resolves to the **same** previewed
  edge. Tapping a different undrawn edge moves the preview there and still
  requires confirmation. No board hit-test runs while an RPC outcome is
  pending or when it is not the caller's turn.
- **Already-drawn edges are inert**, not error-flashing. Tapping one does
  nothing at all.

### 7.2 Feedback

| Moment | Feedback |
|---|---|
| Preview tap | Light haptic, dashed ghost edge |
| Commit tap | Dashed preview becomes a pulsing pending stroke; input locks |
| Server accepts | Medium haptic, owner stroke becomes permanent |
| A box closes | Success haptic, the box fills, the score ticks |
| Two boxes at once | One haptic, both fill together |
| Your turn ends | The turn indicator moves, no haptic |
| Server refuses definitively | Pending state clears; actionable error appears |
| Transport timeout | Pending state stays; Retry reuses the action ID |

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

Reuses `game_sessions` with `game_type = 'dots_and_boxes'`. There is no
hidden **gameplay** information: both players may know the complete board
and move sequence. Operational metadata is still private. In particular,
a player's replay cursor and exact move timestamps are not disclosed to
their partner. This is a smaller disclosure problem than Word Hunt's
hidden answer, not an absence of privacy boundaries.

### 8.1 Board state

```sql
CREATE TABLE IF NOT EXISTS public.dots_boxes_state (
  session_id uuid PRIMARY KEY
    REFERENCES public.game_sessions(id) ON DELETE CASCADE,

  -- 24 entries indexed by the canonical edge ordering in §3.1:
  -- NULL = undrawn, otherwise relationship slot 1 (A) or 2 (B).
  --
  -- OWNERS, NOT BOOLEANS. The first draft stored booleans while §3.3
  -- coloured each edge by who drew it -- and since the state payload
  -- returns only the recent moves, ownership of an older edge was
  -- unrecoverable. The board could not be rendered from the board.
  edge_owners smallint[] NOT NULL,

  -- 9 entries: NULL, or relationship slot 1 (A) or 2 (B).
  box_owners smallint[] NOT NULL,

  -- Denormalised so the lobby and end screen need not count arrays.
  score_a smallint NOT NULL DEFAULT 0,
  score_b smallint NOT NULL DEFAULT 0,

  moves_played smallint NOT NULL DEFAULT 0,

  -- Set on acceptance. A rematch flips the previous session's starter.
  starting_player_slot smallint
    CHECK (starting_player_slot IN (1, 2)),
  rematch_of_session_id uuid
    REFERENCES public.game_sessions(id) ON DELETE SET NULL,

  -- NULL while live; records why a completed game ended.
  completion_reason text
    CHECK (completion_reason IN ('board_complete', 'resigned')),
  resigned_by_slot smallint CHECK (resigned_by_slot IN (1, 2)),
  winner_slot smallint CHECK (winner_slot IN (1, 2)),

  updated_at timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT dots_boxes_edges_shape CHECK (
    array_ndims(edge_owners) = 1
    AND array_lower(edge_owners, 1) = 1
    AND array_upper(edge_owners, 1) = 24
  ),
  CONSTRAINT dots_boxes_owners_shape CHECK (
    array_ndims(box_owners) = 1
    AND array_lower(box_owners, 1) = 1
    AND array_upper(box_owners, 1) = 9
  ),
  CONSTRAINT dots_boxes_scores CHECK (
    score_a BETWEEN 0 AND 9 AND score_b BETWEEN 0 AND 9
    AND score_a + score_b <= 9
  ),
  CONSTRAINT dots_boxes_moves CHECK (moves_played BETWEEN 0 AND 24),
  CONSTRAINT dots_boxes_completion CHECK (
    (completion_reason = 'resigned' AND resigned_by_slot IS NOT NULL)
    OR (completion_reason IS DISTINCT FROM 'resigned'
        AND resigned_by_slot IS NULL)
  )
);
```

### 8.2 The constraints that make an impossible board impossible

Creation explicitly initializes one-dimensional, one-based arrays with 24
and 9 null smallint entries. Shape checks matter: `cardinality = 24` alone
also accepts a 2×12 array or a one-dimensional array whose lower bound is
zero, either of which breaks canonical indexing.

The shapes and ranges above still permit a row that cannot exist: ten
drawn edges with `moves_played = 3`, a score that disagrees with
`box_owners`, a closed box with no owner, or an owner value outside slots
1 and 2. RPC-only access stops a hostile client writing those — it
does not stop an implementation bug or a bad migration writing them, and
a corrupt board is the failure a player would report as "the game broke".

The deferred validator does not merely compare counters. It replays the
at-most-24 move rows from an empty board through the same pure resolver,
starting with `starting_player_slot`, and compares the derived board, owners,
scores, next turn and completion with the stored state/session. That one
replay enforces all of the following at transaction commit:

- `moves_played` equals the count of non-null `edge_owners`
- `game_sessions.current_round` mirrors `moves_played` (`0` before the
  first draw, then `1..24`) and is notification metadata, not move truth
- shared `total_rounds = 24` and `total_rounds_completed = moves_played`
- `score_a + score_b` equals the count of non-null `box_owners`
- every owner in either array is slot 1 or 2 and matches the
  `score_a`/`score_b` assignment
- a box is owned **iff** all four of its edges are drawn (§3.1's formula)
- move numbers are contiguous `1..moves_played`, with exactly one move per
  drawn edge; each move's player owns that edge and was the legal turn
  owner for that move
- every `boxes_closed` index is distinct and in `0..8`; every owned box is
  named by exactly one move and is owned by that move's player
- an invited session has no starter; acceptance sets slot 1 or 2 as starter
  and seeds `updated_at`; while active, `current_turn_user_id`
  equals the next player derived by replay
- `status = 'completed'` with `completion_reason = 'board_complete'` iff
  the board has 24 drawn edges and 9 owned boxes
- `completion_reason = 'resigned'` names one slot as resigner and the other
  as winner, and may preserve a partial board
- normal completion derives `winner_slot` from scores; active and abandoned
  sessions have no winner slot
- while both identities exist, shared `winner_user_id` maps to
  `winner_slot`; after account anonymisation it may be null and the slot
  remains the canonical historical result
- completed and abandoned sessions have no current turn; a completion
  reason is present exactly when status is `completed`

The trigger is installed on Dots state and move changes and on Dots
session transitions. It is deferred because the move row, state row and
session row must be allowed to change in any order inside one RPC before
being checked as a unit. A normal row trigger would reject the legitimate
intermediate state on the final move. The replay is bounded at 24 rows;
correctness is worth that small commit-time cost, and the benchmark in
§14 must include it. The validator exits cleanly when its session has been
hard-deleted so account/relationship cascade deletion cannot be blocked by
a deferred child-table event. Because a deferred trigger runs at commit,
outside the RPC body's normal JSON error path, invariant failure raises one
fixed generic SQLSTATE/message (`P0001` / `DOTS_STATE_INVALID`) with no
row values, query text or constraint names. The client repository maps it
to "The game couldn't update. Try reopening it." and never displays raw
database text.

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

  -- Relationship slot 1 (A) or 2 (B), not a durable user UUID.
  player_slot smallint NOT NULL CHECK (player_slot IN (1, 2)),

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

`boxes_closed` is additionally validated by that replay: values are unique
and in `0..8`, and they are exactly what the resolver produced for that
move. Array cardinality alone cannot prove any of those facts.

### 8.4 Replay acknowledgement and request throttling

```sql
CREATE TABLE public.dots_boxes_replay_cursors (
  session_id uuid NOT NULL
    REFERENCES public.game_sessions(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  last_seen_move smallint NOT NULL DEFAULT 0
    CHECK (last_seen_move BETWEEN 0 AND 24),
  PRIMARY KEY (session_id, user_id)
);

CREATE TABLE public.dots_boxes_request_limits (
  session_id uuid NOT NULL
    REFERENCES public.game_sessions(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  last_request_at timestamptz NOT NULL,
  PRIMARY KEY (session_id, user_id)
);
```

Both are RPC-write-only. A caller may receive their own cursor through the
state RPC but never their partner's. The request-limit row is internal and
is never returned.

### 8.5 Retention

Expiry abandons a session; it does not delete these rows. The board holds
no secret, but the moves are relationship data — who played, when, and
how. Attune currently has no timed game-session purge to inherit, so the
honest policy is explicit: state, moves and cursors remain while the
relationship's game-session history remains; hiding a card is only a
client-facing soft hide. Hard deletion of a relationship or session
cascades all Dots rows. If one account is deleted while shared relationship
history is retained, that user's cursor/limiter rows cascade but board and
move history survives only as anonymous relationship slots — no Dots
owner UUID remains to block deletion or identify the departed user.
Nothing here builds a cross-session score, ranking or behavioural profile.
A future games-wide retention limit may shorten this period, but this
feature must not claim that limit exists today.

The implementation migration also verifies that the shared
`game_sessions.current_turn_user_id` and `winner_user_id` foreign keys use
`ON DELETE SET NULL` (or that the account-deletion transaction clears them
before deleting auth identity). They currently carry live user UUIDs even
though Dots' durable result does not. This is an integration requirement:
anonymous owner slots are pointless if a shared winner FK still blocks the
same deletion.

The state RPC returns only what the client draws: the board, the scores,
the turn owner and the replay window. It does not return per-move
timestamps, which the client has no use for and which would turn a game
board into an activity log.

### 8.6 RLS

Board information is open to both partners **through the state RPC**; the
underlying state, move, cursor and limiter tables have no direct client
grants. This matters even without a secret board: direct `SELECT` on the
moves table would expose exact activity timestamps, and direct state reads
would bypass the bounded response contract.

RLS is enabled on all four tables with no client-facing policies. The
state RPC performs its own membership check before selecting any of them;
RLS is not bypassed merely by forgetting a grant because the table surface
is intentionally closed.

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

### 8.7 Table grants

All four Dots tables are accessed only by `SECURITY DEFINER` RPCs.
`authenticated` gets no direct table privilege, and the REVOKE is repeated
in the file replayed by
`scripts/local_pg_grants.sql` after its blanket grant — otherwise the
local harness silently re-grants write access and the contract test
passes or fails by script ordering rather than by the schema.

---

## 9. What the server proves, and what it does not

This game has no hidden **gameplay** information. Both players see the
whole board and projected move history. There is no equivalent of Word
Hunt's hidden answer. The server still withholds operational metadata that
is unnecessary to play: exact timestamps, action IDs, limiter state and
the partner's replay cursor (§8.4–§8.6).

What the server enforces:

- the edge is in range and not already drawn
- it is the caller's turn
- boxes closed and the extra-turn rule are computed **server-side** from
  the stored board, never accepted from the client
- the winner is derived from the box counts, never accepted from the client

A modified client can compute good moves — it is a perfect-information
game, so of course it can. That is not cheating, it is thinking, and a
player using a solver is a relationship question rather than a security
one. The copy therefore never claims the outcome proves anything.

---

## 10. Server contract

### 10.1 Lock order, and the re-check that the order alone does not give you

For an existing game, every mutating RPC locks the **session row** first,
then state when it needs state, then an auxiliary cursor or limiter row.
Move rows are append-only and are read for idempotency while the session
lock prevents a competing insert for that session. Batch expiry and the
relationship-change trigger process session IDs in stable UUID order and
take session then state for each one.

Creation has no session row yet. It uses the shared relationship and
idempotency-key advisory locks before inserting, matching Snakes. Gameplay
does not take a blocking relationship-row lock after its session lock, so
that creation/teardown order cannot form a relationship↔session cycle.

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

For draw, the exact order is **auth → session lock → membership →
idempotency read → state lock → request throttle → relationship-active
and lazy expiry → turn check → move validation → mutation.** Operations
that do not touch state omit that lock without changing the relative order
of locks they do take.

The first draft put "relationship active" third, before idempotency, and
that **contradicted the retry guarantee in the same paragraph**: a move
that committed successfully could not be recovered by a retry once the
relationship was archived, because the retry would be rejected before it
reached the idempotency check. A committed action must be readable
afterwards while its session is retained, regardless of whether the
relationship has since been archived. Hard deletion deliberately removes
the session and its idempotency record (§8.5).

Membership stays early — a non-member gets `FORBIDDEN` before anything
else — but membership and relationship-*state* are different questions,
and only the first gates the retry path.

`v_now := clock_timestamp()` is captured **after the operation's final
blocking row lock** (the limiter row for draw, state for expiry/resign).
`now()` is transaction-start time, and capturing before a later lock wait
can still predate the action being recorded. Word Hunt's review found that
producing a `completed_at` earlier than the event that caused it.

### 10.3 `dots_boxes_draw_edge(p_session_id uuid, p_action_id uuid, p_edge_index numeric)`

One edge, by its canonical index `0..23`.

`p_edge_index` is accepted as `numeric` so the function can reject `NULL`,
fractions and values outside `0..23` before casting to `smallint`. Giving
the SQL function an integer parameter would let PostgREST/Postgres reject
a decimal before the fixed error envelope can handle it.

**The move number is assigned by the server, never sent by the client.**
The first draft took a client-supplied `p_move_number` and never said it
had to equal `moves_played + 1`, be bound to the caller, or be bound to
the edge — so a client could submit move 24 first, and reusing a number
with a different edge had no defined behaviour at all. The client sends
an `action_id` (a UUID it generates once per intended move, persists until
the result is known, and reuses on every retry); the server assigns
`move_number = moves_played + 1`.

- **Idempotent on `(session_id, action_id)`**, checked first, before every
  other rejection. A retry returns that move's stored result only when its
  `player_slot` matches the caller's current relationship slot and its edge
  matches.
- **A reused `action_id` with a different `p_edge_index` is
  `IDEMPOTENCY_CONFLICT`**, not a silent replay of the first move and not
  a second move. The stored row carries the edge, so the two can be
  compared rather than assumed equal.
- An existing action owned by the other relationship member is also
  `IDEMPOTENCY_CONFLICT`; action identity is never transferable between
  callers, even though UUID collision is improbable.
- Refuses `NOT_YOUR_TURN`, `EDGE_TAKEN`, `INVALID_INPUT` (index outside
  `0..23`, or not an integer — validated *before* any cast, so a decimal
  or oversized value is a structured error rather than a raw SQL
  exception, which Word Hunt's review found leaking Postgres type names
  to the client).
- Computes boxes closed with the pure resolver; inserts the move; writes
  the edge owner, box owners, scores and `moves_played`; and advances
  `game_sessions.current_round` to the new `moves_played` value so the
  existing session realtime channel emits on **every** move, including an
  extra-turn move where the turn owner does not change. It mirrors the
  same value to `total_rounds_completed`. The move's
  `created_at` and state `updated_at` are explicitly set to the same
  post-lock `v_now`; neither relies on transaction-start column defaults.
- **The turn passes only if nothing was closed.** The caller keeps the
  turn otherwise.
- On the 24th edge: sets `status = 'completed'`, `completed_at` from the
  post-lock timestamp, `winner_slot` from the box counts, and the shared
  `winner_user_id` from that slot while both identities exist. Terminal
  completion wins over the extra-turn rule: `current_turn_user_id` becomes
  null even though the final edge necessarily closes at least one box.

Returns the move's result and the new board.

An unknown transport outcome never unlocks a different draw. The client
keeps the pending action and offers Retry with the same ID, or reconciles
by fetching state after resume. Only a definitive response/refetch may
clear that durable pending action; otherwise a successful box-closing move
whose response was lost could be followed accidentally by a second move.

### 10.4 `dots_boxes_resign(p_session_id)`

Available to either member while the session is active. It ends the
session, stores `completion_reason = 'resigned'` and
`resigned_by_slot = caller's slot`, and records the other slot as winner.
A retry by that caller returns the stored result; a later call by the partner or
against a normally completed game returns `GAME_OVER`. This intrinsic
terminal-state check makes the operation idempotent without an action ID.

### 10.5 `get_dots_boxes_state(p_session_id)`

Board, scores, whose turn, the caller's replay cursor, and every move after
that cursor. The result is bounded by the whole game — at most 24 move
projections — and excludes `created_at`, `action_id` and the partner's
cursor. Each projection contains only move number, player slot, edge,
boxes closed and whether the turn passed. The response also carries
session status and `moves_played`, which together are the client revision.
**Reading does not advance the cursor.**

Performs lazy session expiry, so a client arriving from a push
notification without passing the lobby cannot act on a stale session.
Word Hunt shipped that gap: expiry lived only in the lobby lookup, and a
50-hour-old invitation could still be accepted during the cron gap.

The session row is locked before state and moves are read, producing one
internally consistent snapshot relative to draw, resign and expiry.

### 10.5a `dots_boxes_ack_replay(p_session_id uuid, p_through_move numeric)`

Called only after the final board from a fetch has been rendered, replayed
or deliberately skipped. It validates an integer in `0..moves_played` and
updates only the caller's cursor with
`GREATEST(last_seen_move, p_through_move)`. The monotonic assignment is
naturally idempotent, so retries need no action ID. It takes the session
lock before the cursor row and never updates `dots_boxes_state.updated_at`.
It remains valid after normal completion or abandonment while the member
may still view that session; otherwise a final replay could never be
acknowledged.

### 10.6 Lifecycle

Create, accept, decline, active-session lookup — Snakes' shapes exactly,
with these Dots-specific rules:

- Creation initializes `current_round = 0`, `total_rounds = 24`,
  `total_rounds_completed = 0` and the empty Dots state. Each accepted draw
  mirrors `moves_played` into the two shared progress counters. The state
  row remains the source of gameplay truth.
- **Decline means decline an INVITATION.** Once both players are in,
  `decline` is no longer valid; ending an active game is the distinct,
  honestly reported `resign` operation (§10.4).
- Acceptance creates both replay-cursor rows at zero. Accepting an initial
  game assigns first turn to the invitee (§4.3).
- A rematch must reference a completed Dots session from the same
  relationship. Creation uses the lifecycle's relationship and
  idempotency-key advisory locks, validates the predecessor under lock,
  and stores its id in `rematch_of_session_id`. Acceptance assigns first
  turn to the opposite of the predecessor's `starting_player_slot`.
  Concurrent `Play again` calls converge on one invitation rather than
  creating two.

### 10.7 Expiry

48h for an unaccepted invitation, 7 days of inactivity for an active
game — longer than Snakes' 24h because this game is genuinely played
across days.

Cron **and** lazily on every RPC. And the cron job must actually be
registered: writing Word Hunt's sweep turned up that
`expire_snakes_sessions()` had shipped written, granted and never
scheduled, so abandoned boards blocked every future game between those
two people forever. A contract test asserts the registration exists.

For active games, inactivity is derived from
`dots_boxes_state.updated_at`, seeded when the invitation is accepted and
then changed only on an accepted draw.
Fetching, replay acknowledgement and rejected requests do not keep an
abandoned game alive. Every sweep selects candidates, locks each session,
and recomputes that predicate under the lock before writing.

### 10.8 Required contract tests

The backend is not complete until SQL tests prove all of these against
the `authenticated` role, not by inspecting function source:

- direct INSERT, UPDATE and DELETE of a `dots_and_boxes` session row are
  denied, while an unrelated legacy game keeps its intended access
- direct read or write to every Dots table is denied; the state RPC is the
  only client read surface
- deleting either relationship member is not blocked by a Dots foreign
  key; their cursor/limiter rows disappear and retained move/state rows
  contain only anonymous A/B slots
- unauthenticated and non-member calls to every RPC are denied
- the resolver over **every local configuration** around a proposed edge
  (§5.1) — not "every board state", which is 2^24 — plus property tests
  playing random legal games to completion and asserting §8.2's
  invariants after every move
- a reused `action_id` with the same edge replays; with a **different**
  edge it returns `IDEMPOTENCY_CONFLICT`
- another player cannot claim or replay an existing `action_id`
- a client cannot influence `move_number`; the server assigns it
- the deferred invariant trigger refuses every impossible board in §8.2:
  gapped or duplicated move history, a move that claims the wrong edge or
  box, a score that disagrees with `box_owners`, an owned box missing an
  edge, an owner slot outside `1..2`, or `moves_played` out of step with
  `edge_owners`
- fetching does not advance the replay cursor; acknowledgement advances
  only the caller's cursor, never moves backwards, rejects a value beyond
  `moves_played`, and survives a lost-response retry
- an edge cannot be drawn twice, and the failed attempt does not pass the
  turn
- closing a box keeps the turn; closing nothing passes it
- a full chain — one player closing many boxes in one turn — leaves the
  turn with them throughout and the score correct at the end
- one interior edge can close two boxes, assigns both to the caller and
  increments that caller's score by exactly two
- the 24th edge completes the session exactly once, with a winner derived
  from the counts
- concurrent draws by both players produce one legal board and one turn
  owner
- a retried move returns its stored result before turn, range and
  terminal-state checks
- resign is permitted at any time, records the partner as winner, is
  idempotent, and the result is reported **as a resignation** rather than
  as a score
- initial acceptance starts with the invitee; a valid rematch flips the
  prior starter; cross-relationship or non-completed predecessors are
  refused; concurrent rematch creation yields one invitation
- accepted and rejected non-idempotent requests are throttled, while a
  retry of a committed action bypasses the throttle and returns its result
- session expiry is enforced by every RPC, not only the lobby
- state fetches, replay acknowledgements and rejected requests do not
  refresh active-session inactivity
- the expiry sweep is registered with cron
- non-integer, decimal and out-of-range edge indices return
  `INVALID_INPUT` rather than a raw SQL error
- `completed_at` never precedes the move that caused it
- malformed dimensions or non-one-based bounds on either state array are
  rejected, not merely arrays with the wrong cardinality
- an invariant failure exposes only `P0001` / `DOTS_STATE_INVALID`; client
  error mapping never renders raw database or constraint text

### 10.8a Required client contracts

- a pending action ID is durably stored **before** its RPC is sent; a
  storage failure sends nothing
- timeout keeps the board locked and reuses that ID; app restart refetches
  before deciding whether to retry or clear it
- a definitive domain rejection clears pending state and never changes the
  committed board
- replay acknowledgement is sent only after final-board render, Skip or
  reduced-motion completion; a failed acknowledgement merely permits a
  harmless replay next time
- the touch and semantics paths drive the same preview/confirm state
  machine, and turn change/backgrounding clears preview safely
- every session realtime event refetches authoritative state; duplicate or
  out-of-order events cannot apply a move twice. The reducer accepts a
  higher `moves_played`, or at equal moves only a valid forward status
  transition (`invited → active/abandoned`, `active →
  completed/abandoned`); it never replaces terminal state with live state.
  The caller's cursor merges by `max` independently.

### 10.9 Concurrency contracts

Several of the above cannot be written inside the single-transaction SQL
suite, because a lock race needs two connections. They belong in
`scripts/concurrency/`, run by the local harness, exactly as Word Hunt's
do:

- gameplay against the expiry sweep does not deadlock
- **a sweep that selected a session, then waited on a live move's lock,
  does not abandon the now-fresh session** — the under-lock re-check of
  §10.1, which the lock order alone does not give
- a move landing during a sweep does not leave a half-closed session
- a draw racing relationship teardown leaves session and state agreeing
- draw racing resign has one serial outcome: either the move commits before
  resignation, or resignation wins and the move is refused; a final move
  that completes first cannot then be overwritten by resignation
- two simultaneous draws resolve to one board with one turn owner

---

### 10.10 Checklist applicability and design-time gaps

These notes answer the shared checklist where a design can do so; they are
not a self-issued pass. Items that only a built system can evidence —
authorization behaviour, coverage, benchmarks, soak — remain obligations
and are listed in §14 where relevant. An item not mentioned here is not
implicitly passed or N/A; the implementation review must walk the shared
checklist in full.

**1.1 Idempotency.** Draw carries a client action ID whose retry check runs
before every other rejection (§10.2, §10.3). Resign is idempotent by its
stored terminal reason and actor. Replay acknowledgement is a monotonic
`GREATEST` assignment. Creation uses the shared lifecycle idempotency key.
No mutation relies on a client-supplied sequence number.

**1.2 Timeouts.** The client gateway bounds every RPC at **30 seconds**
total, matching Snakes and Word Hunt. The checklist asks for distinct
connect, read and total values; the Supabase Dart client exposes a single
total timeout, so **connect and read are not separately bounded and this
item is partially met, not met.** Carried as a known gap across every
Attune feature rather than claimed here. Without the total bound a
stalled connection leaves a player staring at a board whose turn may
already have passed.

**1.3 Graceful degradation.** There are three runtime dependencies:
Postgres, the realtime channel and the existing local store used to retain
a pending action ID. If realtime is down the board still works — every
screen refetches on open, on resume and after every move. If the local
pending action cannot be persisted, the draw is not sent; sending first
would make a force-quit retry unsafe. If Postgres is unreachable the RPC
times out and the UI retains the pending action for retry/reconciliation.

**No move is ever COMMITTED locally.** The preview is a local, reversible
dashed drawing. After confirmation it becomes a visibly pending stroke,
not an owner-coloured committed edge, and input remains locked until the
RPC resolves. A definitive refusal clears it; an unknown transport outcome
keeps it for idempotent retry. Only a server response or authoritative
refetch makes it permanent, updates ownership and unlocks the next move.

**1.4 / 1.5 Authorization and authentication.** Every RPC begins with
`auth.uid()`, locks the named Dots session, then verifies that user against
the session's relationship before reading or returning any sub-resource.
All functions are `SECURITY DEFINER SET search_path = public`; execution is
revoked from `PUBLIC` and `anon`; base-table privileges are revoked from
`authenticated`. Supabase Auth owns token validation and rotation. These
are design obligations, not passes, until role-based SQL tests prove them.

**1.9 Consistency model.** Read-your-writes, by construction: every
mutation returns the new board, and the client renders the response
rather than re-fetching. Between players it is eventual, bounded by the
realtime channel or the next open. Nothing is cached beyond the current
screen's state — there is no client-side board cache to invalidate,
which is a decision rather than an omission: a stale board in a
turn-based game is worse than a spinner.

**3.9 / 3.10 Retry policy.** Mutations are **not** retried automatically.
Draw carries an `action_id`; resign and replay acknowledgement have
intrinsically idempotent assignments. The UI offers a user-initiated retry
rather than silently repeating a slow request. Reads retry once on
transport failure. Nothing retries a 4xx-equivalent: `NOT_YOUR_TURN`,
`EDGE_TAKEN`, `FORBIDDEN` and `INVALID_INPUT` are permanent and
retrying them is noise.

**5.4 Retry UX.** An unknown outcome says: "We couldn't confirm that
line. Try again." The board remains locked and Retry reuses the same action
ID, so a move that reached the server is recovered rather than duplicated.
A fixed server rejection uses its actionable error and clears pending
state. The UI never claims a timed-out move definitely failed.

**1.6 Concurrency.** One lock order everywhere (§10.1), and the races that
need two connections are contract-tested outside the
single-transaction suite (§10.9). This item is written this explicitly
because the equivalent claim in Word Hunt's audit was **false** — it
asserted one lock order on the strength of gameplay-versus-gameplay races
only, and expiry inverted it.

**1.7 Statelessness.** All state is in Postgres. No server-side session
affinity, nothing cached between calls.

**1.8 Complexity.** Every operation is bounded by the board: 24 edges and
9 boxes. `resolve` is O(1) — at most two boxes, four edges each. The
mutation itself is O(1), while the deferred consistency validator replays
O(m) moves where `m ≤ 24`. State returns at most 24 replay projections.
Nothing grows with games played, users or time, but the commit-time replay
must be included in the move benchmark rather than described as free.

**1.10 Rollback.** Each RPC is a single transaction. A partial move
cannot exist: the edge, the box owners, the score and the turn all commit
together or not at all. No saga, no compensating write, no cleanup path
— which is the reason to prefer one transaction here over an
event-sourced design that would need one.

**1.11 Privacy.** Move authorship, replay acknowledgement and timestamps
are relationship data even though the puzzle has no secret. Durable board
ownership uses relationship slots rather than UUIDs; the short-lived
cursor/limiter rows still use user IDs and cascade on account deletion.
Their explicit retention is defined in §8.5. Clients get
only the board projection, scores, turn, their own cursor and timestamp-
free replay moves; direct table reads are denied.

**2.1 / 2.5 Input and limits.** The only gameplay-choice input is the edge
index; session and action identifiers are UUIDs. The edge is accepted as
`numeric`, then null/range/integer-checked **before** its `smallint` cast
(§10.3). Repository error mapping prevents gateway-level malformed UUID
errors from reaching UI copy. Loops are bounded by 24; there is no
client-supplied collection or size.

**2.2 Parameterized queries.** No dynamic SQL. No string interpolation
into a query anywhere in this feature.

**2.4 / 5.5 Error messages.** Expected domain failures use one shared
error function with fixed codes and user-facing sentences. Input is
validated before casts (§10.3). A deferred invariant failure cannot return
that JSON envelope because it occurs at commit, so it raises only the
generic `P0001` / `DOTS_STATE_INVALID` signal defined in §8.2. Gateway, transport and
unexpected database failures are sanitised by the repository before they
reach UI; the spec does not falsely claim Postgres can never produce one.

**3.1 / 3.3 Queries and indexes.** Access patterns are: session by primary
key; lobby by relationship; replay by `(session_id, move_number)`; action
recovery by `(session_id, action_id)`; and cursor/limiter by their composite
primary keys. The lobby needs a partial index shaped
`(relationship_id, game_type, status) WHERE game_type =
'dots_and_boxes'`; expiry needs `dots_boxes_state(updated_at, session_id)`
plus a partial active/invited Dots-session index before joining by primary
key.
`EXPLAIN` output for all paths is attached to the implementation PR, not
assumed.

**3.8 Rate limiting.** The shared five-games-per-hour initiation limiter
covers session creation.

The first draft said moves need no limiter because "your partner is the
natural rate limit". **That is false in two ways.** During a chain a
player holds the turn for many consecutive moves, and rejected requests
still cost a round trip. After idempotency recovery but before status,
turn and edge validation, draw locks the caller's request-limit row. A
non-idempotent request within 300ms of the last admitted request returns
`RATE_LIMITED`; otherwise it advances `last_request_at`, including when a
later validation returns a structured error. This bounds accepted,
wrong-turn and invalid-edge traffic while preserving immediate recovery
of a committed action. It is abuse protection, not an anti-cheat claim.

**4.x Observability.** This feature emits no structured logs, metrics or
alerts, and neither does any other Attune game. That is a **known gap
carried across the whole games surface**, not something this spec solves
alone, and it is listed in §14 as outstanding rather than quietly marked
passing.

**5.1 Error copy.** Each error code maps to a sentence that says what to
do: `NOT_YOUR_TURN` → "It's their move." `EDGE_TAKEN` → "That line is
already drawn." `SESSION_EXPIRED` → "This game expired. Start a new one."

**5.2 Latency.** The interaction target is first feedback within 200ms:
the preview ghost draws on the first tap locally, before any network call.
After confirmation a distinct pending stroke remains during the round
trip (§7.2); it must not look owner-confirmed. The server round trip itself
is not on the 200ms path and must not be claimed to be.

**6.6 Determinism.** There is no gameplay randomness — no die, generated
board or shuffled content. Resolver tests are deterministic. Property
tests that generate legal games use a fixed, reported seed and print it on
failure so a failing sequence is exactly reproducible.

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

Estimate: **ten to fourteen working days, plus product/device testing.**

The first draft said four to six, reasoning that the absent things —
hidden state, a private table, a disclosure boundary, a generator — made
this cheaper than Word Hunt. A review pointed out that the argument only
counted what was missing. What is *present* is mostly new: the turn
machinery around the extra-turn rule, two new tables with a
consistency-enforcing trigger, a per-player replay cursor, a two-step
commit that has to exist in the semantics tree as well as under the
finger, and the chain animation with its budget and skip. The lifecycle
reuse from Snakes is real; almost nothing else is.

Four to six days is a happy-path prototype. Seven to ten omitted the
durable pending-action reconciliation, fetch-then-ack replay protocol and
commit-time history replay that the second review made explicit. It is not
a build anyone should trust with a couple's Saturday evening.

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

- **3×3 limits the exposure; it does not prove balance.** A 24-edge board
  gives a stronger player fewer decisions over which to compound an
  advantage, but the spec has no evidence that its skill gap is small.
  That remains a product-test question, not a mathematical claim.
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

**24 tap targets on a phone.** At ~340dp of usable width a 3-box board
gives each edge a span of about 113dp and a stroke a few dp wide — so the
*length* is generous and the *thickness* is the whole problem, which is
what nearest-edge hit-testing exists for. Measured rather than guessed:
the first draft of this line said 40dp for a 5×5 board and was wrong
twice over. Mitigated by nearest-edge hit-testing, confirm-on-second-tap,
and the accessible path in §7.3 — and tested on the smallest supported
device at the largest text setting, since both shrink the board.

**A long chain still needs a time budget.** One player can close all nine
boxes in one turn. The fetch returns every unseen move so the client can
reconstruct honestly, while §4.4 caps animation time rather than dropping
history.

---

## 13. Decisions from review

The first draft left three questions open. They are now decisions:

1. ~~**Is 5×5 the right size?**~~ **Settled: 3×3.** The first draft
   compared 5×5 against a 4×4 board it believed had 24 edges. 4×4 has
   40. The 24-edge board is 3×3, it has 9 boxes, and 9 is odd — so it
   keeps the no-draw property the whole argument depended on while
   halving the game. See §3.2.

2. ~~**Should the first move alternate between games?**~~ **Settled:
   yes, on rematch.** The invitee starts the first game (§4.3); each
   rematch flips it. `dots_boxes_state` stores `starting_player_slot` and
   `rematch_of_session_id`, so the alternation survives a reinstall and
   does not depend on who taps `Play again` first.

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

- role-based authentication, authorization and direct-table denial tests
  for every RPC/table (1.4, 1.5)
- branch coverage against the checklist's targets (6.7)
- mutation testing on the resolver and the turn machinery (6.8)
- a performance benchmark for the move path (6.9)
- 24-hour soak and 2× load behaviour (6.10, 6.11)
- chaos testing with Postgres killed mid-move (6.12)
- `EXPLAIN` output for all access patterns in §10.10 (3.3)

**Known platform gap:**

- the Supabase Dart path currently provides one 30-second total RPC
  timeout, not separately configurable connect/read/total bounds; checklist
  1.2 remains partially met until the shared transport solves that

**Cannot be evidenced without a device:**

- first-feedback latency actually measured at p95 (5.2)
- the 24-target board at the smallest supported size and largest text
  setting (§12)
- screen-reader navigation of 24 edge nodes, which is the part of §7.3
  most likely to be unpleasant in practice and cannot be judged from code

**Not solved here, and not solvable here:**

- **Observability (4.1–4.14).** No structured logs, no metrics, no
  alerts, no runbook — for this game or any other Attune game. A
  games-wide gap that one spec should not pretend to close.
- **Rollback and smoke tests (8.1, 8.2).** Deployment concerns shared
  with every migration in the project.
- **The Arcade has no co-operative game.** Named in §12 and unaddressed.

## 15. Recommendation

**Do not build this next.**

The spec is sound enough to build from — the review findings are folded in
and the arithmetic is now checked rather than asserted. That is
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

3. **It is ten to fourteen days plus product/device testing**, which is a real
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

- **2026-09-08 — Second adversarial pass.** Kept the first-pass fixes that
  were sound and closed the remaining contradictions:
  - replay reads no longer acknowledge themselves; fetch and monotonic ack
    are separate, so a lost response cannot swallow unseen moves
  - replay cursors, timestamps and limiter state are private operational
    metadata; clients have no direct access to any Dots table
  - durable ownership uses anonymous relationship slots rather than UUIDs,
    and account deletion is an explicit integration contract
  - commit-time validation replays the complete bounded history, proving
    turn ownership, extra turns, box claims and denormalised state together
  - array dimensions/lower bounds, rematch metadata, resignation reason,
    current-round signalling and post-lock activity timestamps are explicit
  - unknown draw outcomes retain a durable action ID and lock the board
    until retry or authoritative reconciliation
  - hit-testing now makes drawn edges truly inert and requires the second
    tap to resolve to the same previewed edge
  - stale 5×5, 12-move, twenty-box and arithmetic-only resignation text was
    removed; the checklist section is explicitly an applicability map, not
    a self-awarded pass
  - estimate raised to ten-to-fourteen working days plus product/device
    testing to include these contracts

- **2026-09-08** — Revised after an external implementation review of the
  first draft. Twelve findings, all confirmed before being applied:

  - **The board was wrong on arithmetic.** The draft chose 5×5 partly by
    rejecting 4×4 as "24 edges"; 4×4 has 40. The 24-edge board is 3×3,
    with 9 boxes — still odd, so draws stay impossible. Now 3×3, which is
    also a genuine mitigation for the skill risk rather than only a
    length decision.
  - **The stored board could not render itself.** Edges were booleans
    while §3.3 coloured them by owner, and with a bounded replay window
    older ownership was unrecoverable. Now `smallint[24]` relationship-slot
    owners, which also survive account anonymisation without retaining UUIDs.
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
  rediscover: the RPC-write-only carve-out (§8.6), one lock order
  everywhere (§10.1), post-lock timestamps (§10.2), lazy session expiry
  at every entry point (§10.5), decline restricted to invitations
  (§10.6), a registered cron sweep (§10.7), coordinate validation before
  casting (§10.3), and concurrency contracts that need two connections
  (§10.9).

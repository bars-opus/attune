# ATTUNE — DOTS AND BOXES SPECIFICATION

**Status:** Draft for review. Not implemented. Not approved.

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
| Duration | ~5 to 10 minutes across as many sittings as they like |
| Board | 5×5 boxes — 60 edges, 25 boxes |
| Skill | **Yes**, and increasing with practice. The first Arcade game like this. |
| Turn model | Asynchronous, alternating, **one edge per turn — unless you close a box** |
| Win condition | Most boxes when all 60 edges are drawn |
| Draws | **Impossible.** 25 is odd. See §3.2 |
| Penalty | None. No forfeit, no prompt, no consequence |
| Visual language | Snakes' and Paint Ball's: thin strokes on plain black |

---

## 3. The board

### 3.1 Geometry, stated exactly

A 5×5 grid of **boxes** means a 6×6 grid of **dots**, and:

- horizontal edges: 6 rows × 5 columns = **30**
- vertical edges: 5 rows × 6 columns = **30**
- total edges: **60**
- boxes: **25**

Counted rather than estimated, because every bound in §10 depends on it:
a game is exactly 60 moves' worth of edges, and the payload, the loop
bounds and the completion check are all sized from that number.

Addressing: an edge is `(orientation, row, col)` where orientation is
`h` or `v`. A horizontal edge `(h, r, c)` runs from dot `(r, c)` to
`(r, c+1)`, with `0 ≤ r ≤ 5` and `0 ≤ c ≤ 4`. A vertical edge `(v, r, c)`
runs from dot `(r, c)` to `(r+1, c)`, with `0 ≤ r ≤ 4` and `0 ≤ c ≤ 5`.
Box `(r, c)` for `0 ≤ r, c ≤ 4` is bounded by `(h,r,c)`, `(h,r+1,c)`,
`(v,r,c)` and `(v,r,c+1)`.

**One edge touches at most two boxes** — verified by enumeration, not
assumed — so a single move can close at most two. That bound matters for
§5.1's scoring loop and for the animation.

### 3.2 Why 5×5, and why draws are impossible

25 boxes cannot split evenly, so **every game has a winner**. That is
deliberate. A draw in a two-person game that took ten minutes is the
least satisfying possible ending, and the alternative — 4×4 or 6×6, both
even — would produce them regularly at this board size.

It also keeps the game inside one screen without scrolling on the
smallest supported device (§12), which 6×6 does not.

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

A player can theoretically take all 25 boxes in a single turn from a
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
board sizes — and at 5×5 the parity works out the other way. Neither
effect is large enough to justify a coin flip that would make the rule
harder to explain.

### 4.4 The replay

On opening, a player sees the moves made since they last looked, drawn in
sequence: each edge appearing, each captured box filling. Bounded at the
**last 12 moves** — a long unattended run is summarised as "they took N
boxes" and then shown in its final state, because animating twenty-five
captures is a cutscene rather than a replay.

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
be tested exhaustively without a session, a player or a clock. Every
legal board state and every legal edge is a small enough space to test
by enumeration rather than by sampling.

### 5.2 An edge is drawn once

Drawing an already-drawn edge is not a move. It is refused as
`EDGE_TAKEN` and the turn does not pass — it was never a turn.

### 5.3 Ending

The game ends when all 60 edges are drawn. Whoever owns more boxes wins;
25 is odd so there is always exactly one winner.

**The ending is stated plainly and once.** "You took 14, they took 11."
No rematch pressure, no streak, no record — `Play again` is one tap and
that is the whole ceremony, matching Snakes §5.4 and Word Hunt §13.3.

### 5.4 Resigning

A player may resign. It ends the game immediately, the partner is shown
as having won, and — like Word Hunt's "I can't find it" — **it is
reported as a result, never as a surrender.** The screen says who had
more boxes at that point.

Resigning is one player ending a game **both** players are in, which
Word Hunt's review established is not one person's decision to make
unilaterally. So the rule here is narrower: **resign is only offered once
the outcome is already decided** — when the losing player cannot catch up
even by taking every remaining box. Before that point there is no resign
button, only the ordinary "leave it and come back" that every
asynchronous game has.

That check is arithmetic, not judgement: `their_boxes > mine + remaining`.

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

```sql
CREATE TABLE IF NOT EXISTS public.dots_boxes_state (
  session_id uuid PRIMARY KEY
    REFERENCES public.game_sessions(id) ON DELETE CASCADE,

  -- 60 booleans, indexed by the canonical edge ordering in §3.1:
  -- horizontal edges first (row-major), then vertical.
  edges boolean[] NOT NULL,

  -- 25 entries: NULL, or the user_id who closed that box.
  box_owners uuid[] NOT NULL,

  -- Denormalised so the lobby and the end screen do not count arrays.
  score_a smallint NOT NULL DEFAULT 0,
  score_b smallint NOT NULL DEFAULT 0,

  moves_played smallint NOT NULL DEFAULT 0,

  updated_at timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT dots_boxes_edges_len CHECK (cardinality(edges) = 60),
  CONSTRAINT dots_boxes_owners_len CHECK (cardinality(box_owners) = 25),
  CONSTRAINT dots_boxes_scores CHECK (
    score_a BETWEEN 0 AND 25 AND score_b BETWEEN 0 AND 25
    AND score_a + score_b <= 25
  ),
  CONSTRAINT dots_boxes_moves CHECK (moves_played BETWEEN 0 AND 60)
);
```

Moves are rows in `game_session_rounds`, matching Snakes: one row per
move, carrying the edge drawn, the boxes closed, and whether the turn
passed. That is what the replay reads.

### 8.1 RLS

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

### 8.2 State table grants

`dots_boxes_state` is written only by `SECURITY DEFINER` RPCs.
`authenticated` gets `SELECT` and nothing else, and the REVOKE is
repeated in the file replayed by `scripts/local_pg_grants.sql` after its
blanket grant — otherwise the local harness silently re-grants write
access and the contract test passes or fails by script ordering rather
than by the schema.

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

### 10.1 Lock order

Every mutating RPC takes the **session row** `FOR UPDATE` first, then the
state row. One order, everywhere, including the expiry sweep and the
relationship-change trigger.

Stated first and this bluntly because Word Hunt's review found exactly
this inverted: gameplay locked session-then-attempt while expiry wrote
attempts-then-sessions, and it deadlocked in production shape. Any
function here that closes a session takes the session lock before
touching `dots_boxes_state`.

### 10.2 Mutation order

**auth → membership → relationship active → session lock → idempotency →
lazy session expiry → turn check → move validation → mutation.**

Idempotency precedes expiry and rejection so a retry of a committed move
returns its stored result rather than an error about the state that move
itself produced.

`v_now := clock_timestamp()` is captured **after** the lock. `now()` is
transaction-start time and can predate a lock wait, which Word Hunt's
review found producing a `completed_at` earlier than the move that caused
it.

### 10.3 `dots_boxes_draw_edge(p_session_id, p_move_number, p_edge_index)`

One edge, by its canonical index `0..59`.

- **Idempotent on `p_move_number`.** A retry of a committed move returns
  that move's stored result. Checked first, before every other rejection.
- Refuses `NOT_YOUR_TURN`, `EDGE_TAKEN`, `INVALID_INPUT` (index outside
  `0..59`, or not an integer — validated *before* any cast, so a decimal
  or oversized value is a structured error rather than a raw SQL
  exception, which Word Hunt's review found leaking Postgres type names
  to the client).
- Computes boxes closed with the pure resolver, updates the board, the
  owners, the score and `moves_played` **in one statement each**.
- **The turn passes only if nothing was closed.** The caller keeps the
  turn otherwise.
- On the 60th edge: sets `status = 'completed'`, `completed_at` from the
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
- the resolver, **enumerated exhaustively**: every edge on an empty board
  closes nothing; every edge that completes a box closes exactly it; the
  two edges that can close two boxes at once do
- an edge cannot be drawn twice, and the failed attempt does not pass the
  turn
- closing a box keeps the turn; closing nothing passes it
- a full chain — one player closing many boxes in one turn — leaves the
  turn with them throughout and the score correct at the end
- the 60th edge completes the session exactly once, with a winner derived
  from the counts
- concurrent draws by both players produce one legal board and one turn
  owner
- a retried move returns its stored result before turn, range and
  terminal-state checks
- resign is refused while the caller can still catch up, permitted when
  they cannot, and idempotent
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
- a move landing during a sweep does not leave a half-closed session
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

**1.2 Timeouts.** The client gateway bounds every RPC at **30 seconds**,
matching Snakes and Word Hunt. Without a bound a stalled connection
leaves a player staring at a board whose turn may already have passed.

**1.3 Graceful degradation.** There are exactly two dependencies:
Postgres and the realtime channel. If realtime is down the board still
works — every screen refetches on open, on resume and after every move,
and the live channel only removes the need to tap. If Postgres is
unreachable the RPC times out and the UI says so with a retry; no move is
ever applied locally and reconciled later, because a locally-applied move
in a turn-based game shows the player a board their partner does not
have.

**1.6 Concurrency.** One lock order everywhere (§10.1), and the three
races that need two connections are contract-tested outside the
single-transaction suite (§10.9). This item is written this explicitly
because the equivalent claim in Word Hunt's audit was **false** — it
asserted one lock order on the strength of gameplay-versus-gameplay races
only, and expiry inverted it.

**1.7 Statelessness.** All state is in Postgres. No server-side session
affinity, nothing cached between calls.

**1.8 Complexity.** Every operation is bounded by the board, which is a
constant: 60 edges, 25 boxes. `resolve` is O(1) — at most two boxes to
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
by the 60-edge constant. There is no unbounded collection, no
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
covers session creation. Moves need no limiter of their own: a move is
only legal on your turn, so the natural rate limit is your partner.

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

Estimate: **four to six days.** Lower than Word Hunt's five-to-eight
because there is no hidden state, no private table, no disclosure
boundary and no generator — the three things that made that game
expensive. Higher than a naive reading suggests because the extra-turn
rule touches every part of the turn machinery, and because the review
lessons above are now non-optional work rather than discoveries.

---

## 12. Risks

**This is the first Arcade game a person can be reliably better at.**
Snakes is pure luck and Word Hunt is near-luck. Dots and Boxes has a
known optimal strategy, and a partner who learns chain parity will win
essentially every game against one who has not. That is a genuine
product risk in a slot whose stated purpose is *"after a conflict we just
want to play games and cool off"* — losing ten in a row is not cooling
off.

Not a reason to cut it. It is the reason the copy states results without
ranking language, the reason nothing is recorded across sessions, and the
reason `Play again` is the prominent action. But it should be watched,
and if it turns out one partner always wins, the honest fix is a smaller
board rather than a handicap.

**The Arcade is now entirely competitive.** Paint Ball, Snakes, Word Hunt
and this all have a winner or a comparison. The genuinely missing thing
is a **co-operative** game where both players win or both lose together,
and this spec does not address that gap. Worth naming here so it is not
forgotten.

**60 tap targets on a phone.** At ~340dp of usable width a 5-box board
gives each edge a span of about 68dp and a stroke a few dp wide — so the
*length* is fine and the *thickness* is the problem. Measured rather than
guessed, because the first draft of this line said 40dp and was wrong. Mitigated by nearest-edge hit-testing, confirm-on-second-tap,
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

1. **Is 5×5 the right size?** It makes draws impossible and fits one
   screen, but 60 moves is a long game for the Arcade. 4×4 is 24 edges
   and about three minutes — but draws become possible and common.

2. **Should the first move alternate between games?** §4.3 gives it to
   the invitee always. If the parity advantage turns out to matter at
   5×5, alternating would be fairer and harder to explain.

3. **Should a chain be animated move-by-move, or resolved at once?**
   Move-by-move is honest and shows the decision; at once is faster and
   less of a cutscene. §4.4 currently splits the difference at 12.

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
- the 60-target board at the smallest supported size and largest text
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

## Changelog

- **2026-09-08** — Initial draft. Not reviewed, not approved, not
  implemented. Written after Word Hunt's external review, so its ten
  findings are folded in as requirements rather than as things to
  rediscover: the RPC-write-only carve-out (§8.1), one lock order
  everywhere (§10.1), post-lock timestamps (§10.2), lazy session expiry
  at every entry point (§10.5), decline restricted to invitations
  (§10.6), a registered cron sweep (§10.7), coordinate validation before
  casting (§10.3), and concurrency contracts that need two connections
  (§10.9).

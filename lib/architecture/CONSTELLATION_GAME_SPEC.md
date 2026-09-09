# ATTUNE — CONSTELLATION SPECIFICATION

**Status:** Draft for review. Not implemented, not approved.

**Reads with:** `SNAKES_AND_LADDERS_SPEC.md` (the lifecycle and the
versioned-content table this reuses), `WORD_HUNT_GAME_SPEC.md` (§10, the
hardened server contract), `DOTS_AND_BOXES_SPEC.md` (§12 and §15, the
argument this game answers), `GAMES.md` §5,
`algorithms/algorithm_quality_review_checklist.md`.

---

## 1. What it is

A dark field with scattered stars. On your turn, two or three of them
glow. You tap one. A line draws from the growing edge of the
constellation out to that star, a small region of light reveals, and it
becomes your partner's turn.

Every offered star is valid. None is better, faster, or worth more. What
differs is **which way the pattern grows**.

When the constellation completes, the finished pattern animates once and
the session ends. Nothing carries over.

### 1.1 Why it exists

**Every other Arcade game produces a winner or a comparison.**

| Game | Ending |
|---|---|
| Paint Ball | Someone is knocked out |
| Snakes and Ladders | Someone reaches 100 first |
| Word Hunt | Two times, side by side |
| Dots and Boxes | Someone has more boxes |

The Arcade exists for one stated reason:

> *"Not everything needs to be about learning about each other. Sometimes
> after a conflict we just want to play games and cool off."*

Snakes survives that brief because it is pure luck — nobody loses for
being worse. Word Hunt is near-luck. Dots and Boxes is skill-dominant,
and its own spec (§15) recommends against shipping it into this slot for
exactly that reason: losing ten in a row to your partner is not cooling
off.

So the slot is missing a **co-operative** game, where the game is the
opponent rather than your partner. The structural payoff is not
sentimental. **A skill gap stops being a way to beat your partner**,
because there is nothing here to be better at.

### 1.2 The design rule, stated once

**Choices without wrong answers.**

Each turn offers two or three valid stars. Every one of them advances the
work. No route is optimal, faster, or worth more. What a choice changes
is the shape of the thing you are making together.

That sentence is the whole design, and §4 exists to enforce it. The
question this game asks is *"what will we make?"* — never *"can we solve
this?"* The moment there is a better move, there is a better player, and
the game has become the thing it was built to replace.

### 1.3 What it is not

- **Not a puzzle.** Nothing to solve, no optimal path, no solver role for
  one partner to fall into.
- **Not scored.** No winner, no streak, no record, no comparison.
- **Not an insight layer.** Nothing about the finished pattern means
  anything about the relationship. No reflection prompt, no analysis.
  This is a rule, as it is for Snakes and Word Hunt.
- **Not a progress bar.** See §4.3 — this is the failure this design is
  most at risk of, and it is guarded in the database rather than by
  authorial good intentions.

### 1.4 The honest objection

This is closer to a collaborative toy than a conventional game. There is
no danger, no failure state, and no way to play badly.

That is a strength here, not an embarrassment. "Arcade" in Attune means
**no insight layer**, not *danger* — Snakes has no danger either; you
roll a die and nothing is asked of you. What makes a game belong in this
slot is that it demands nothing at the moment when neither person has
anything to give.

What the design still owes is **agency, anticipation and a satisfying
completion**. A game does not need a failure state; it needs those three.
§4 and §7 are where they are earned or lost.

---

## 2. Core characteristics

| Characteristic | Value |
|---|---|
| Duration | 12–20 taps total, 6–10 each, across as many sittings as they like |
| Board | A hand-authored scene: stars, legal connections, revealed regions |
| Skill | **None.** Structurally, not by mitigation — see §4.2 |
| Turn model | Asynchronous, alternating, one star per turn |
| Failure | **None.** No loss condition exists |
| Winner | **None.** No score exists to hold |
| Art | Abstract patterns of line and light. No depicted object |
| Visual language | Thin strokes on plain black, as the rest of the Arcade |

---

## 3. Why abstract, and what it costs

The finished constellation is **an abstract pattern** — lines, light and
geometry. It does not depict a bear, a ship or a heart.

**What that buys.** Authoring becomes tractable. A recognisable figure
constrains every branch to still resolve into the same object, which
fights the divergence requirement in §4.3 directly: the more the paths
must converge on a ship, the less the choices can matter. Abstract lets a
branch genuinely go anywhere.

**What it costs.** With no object to name, *"we made this"* has to be
carried entirely by the visuals. There is no "it's a ship" moment to fall
back on.

**So the completion is the highest-risk piece of UI in this build**, and
is treated as such rather than as a finishing touch. If the moment the
pattern completes and animates is flat, the game is flat, and no amount
of correct server behaviour will save it. §7.3 specifies it; §14 lists it
as unevidenced until it exists on a device.

---

## 4. The scene, and the property that makes or breaks it

### 4.1 Shape

A scene is a hand-authored directed graph, versioned exactly like
`snakes_boards`:

- **Nodes** are stars, each with a position on a normalised field
- **Edges** are legal connections between them
- Each node names the **region** of the pattern that reveals on arrival
- One node is the **origin**, where the constellation begins

The **frontier** is the set of unreached nodes adjacent to reached ones.
A turn offers two or three of them; tapping one commits that edge,
reveals that node's region, and moves the frontier.

### 4.2 Why there is no skill

Not a mitigation — a structural property, and the reason this game and
not Lantern Relay (§13).

Every offered star advances the work by exactly one node. There is no
resource, no ordering that scores better, no position to be in later.
A player thinking ten moves ahead arrives at the same place as one
tapping whichever star is nearest their thumb. **There is nothing to
optimise, so there is no one to be better at it.**

Compare the alternative that was considered and rejected: a path-laying
puzzle where the light must reach three lanterns. Curated boards and
hidden future choices reduce the *visibility* of the skill gap; they do
not remove it, because an objectively better route still exists. Once
optimisation exists, one partner becomes the solver and the other becomes
an input device. That is the Dots and Boxes failure wearing a
co-operative coat.

### 4.3 Branch divergence, enforced in the database

**The failure this design is most at risk of is becoming a progress bar
disguised as a game.** An author can produce a graph that branches on
paper while every path yields a visually identical pattern. The choices
would then be decoration, and §1.2 would be a lie the spec tells itself.

So it is a validator rule, not a matter of authorial judgement:

**Any two complete playthroughs of a scene must differ by at least `N`
revealed regions.**

The same discipline as Word Hunt's uniqueness scan, which exists because
"the word appears exactly once" was too important to trust to a
generator's good behaviour. Here the equivalent claim is "the choices
matter", and it gets the same treatment.

`N` is stored per scene rather than hard-coded, because the right value
depends on the scene's size. A floor applies: **no scene may declare an
`N` below 3.**

### 4.4 What else the validator proves

A scene is refused storage unless:

1. **Every node is reachable** from the origin — no scene can strand a
   couple mid-pattern
2. **Every path terminates in a complete pattern** — no dead ends, no
   playthrough that ends with the illustration half-drawn
3. **Every frontier state offers at least two choices**, until the last
   move — a scene that funnels into a single legal tap for several turns
   in a row is a progress bar for those turns
4. **Divergence** as in §4.3
5. Node positions are inside the field, edges connect existing nodes, and
   the graph is acyclic in the direction of growth

Rules 1, 2 and 3 are checkable by exhaustive traversal at authoring time,
because a scene is 12–20 nodes and the space of playthroughs is small.
Rule 4 is checked over the same traversal.

**A scene that fails validation is not stored.** It fails at insert, in
the migration, in front of whoever authored it — never in front of a
couple.

### 4.5 Authoring cost, flagged as a risk

An abstract scene should be quick to author, but the divergence rule
makes each one a small construction problem rather than free drawing.
**If a scene takes a day to build, the content cost dwarfs the code**,
and the estimate in §11 is wrong.

The honest mitigation is to author **three scenes before writing any
server code** and measure how long the third takes. If it is hours, the
library is viable. If it is a day, the art direction needs to loosen
before the build proceeds, not after.

### 4.6 The library, and repeats

**A scene is never repeated until the library is exhausted**, tracked the
way Word Hunt tracks recently-seen words.

This makes the library the content budget: twenty scenes is twenty
sessions before anything returns. That is the trade accepted in exchange
for abstract art being cheap enough to author that a real library is
achievable.

When every scene has been played, the exclusion falls back to the full
list rather than failing — a couple who play the library out must never
be told there is no game.

---

## 5. Turn structure

### 5.1 One star, then it is their turn

No extra turns, no chains, no combinations. One tap moves the game
forward by exactly one node and hands it over. The simplest turn model in
the Arcade, deliberately.

### 5.2 Asynchronous, and frozen between turns

Neither player need be present. **The board does not change while nobody
is playing** — no decay, no timer, no state that worsens with absence.

That is a design rule with a reason. A game where absence causes loss
turns leisure into maintenance and needs notifications to function, which
is the opposite of a slot for people with nothing to give. A couple who
open this after four days find exactly what they left, plus whatever
their partner added.

### 5.3 Who goes first

The **invitee**, matching Snakes §4.1a and Word Hunt: they have the app
open and their attention on it. Handing the first move to the initiator
means the game's first action happens whenever they next look.

There is no first-move advantage to alternate away from, because there is
no advantage in this game at all.

### 5.4 The replay

On opening, a player sees the stars added since they last looked, drawn
in sequence. Bounded by a **time budget of about 1.5 seconds** rather
than a move count, then the remainder snaps to current state. `Skip` is
always available, and `reduceMotionOf(context)` skips to the final state
— the rule every Attune animation follows.

The cursor is **server-side and acknowledged by the client after
rendering**, not advanced by the fetch. Word Hunt's review established
why: a cursor advanced on read loses the replay entirely when the
response never reaches the phone. Explicitly at-least-once — two devices
that both fetch before either acknowledges will both animate, which is
harmless, where a lease would make a harmless duplicate capable of
blocking replay for good.

### 5.5 Ending

The session ends when every node is reached. The completed pattern
animates once and holds.

There is no winner to name and no score to report. The end screen says
what was made, offers `Play again` prominently and `Back to chat`
secondarily — matching Snakes §5.4 and Word Hunt §13.

### 5.6 Leaving

There is no resign, because there is nothing to resign from — no loss to
avoid and no opponent to concede to. A couple who stop simply stop, and
the session expires on the shared schedule (§9.7).

Either partner may **abandon an invitation** that has not been accepted.
Once both are in, ending it is not one person's decision — the lesson
Word Hunt's review taught, and it applies here even though there is no
hidden answer to be released early.

---

## 6. Screens

**Lobby** — one line of what the game is, a Start button. Snakes' shape.

**Field** — the constellation, the glowing choices, and whose turn it is
by name. Nothing else. No score, because there is none.

**Waiting** — the breathing mark the session games use, the pattern as it
stands, and an exit to chat. The screen leaves on its own when the
partner plays.

**Completion** — the finished pattern, animated once (§7.3).

---

## 7. Interaction, motion and the moment that matters

### 7.1 Choosing

Offered stars pulse gently. Unreachable stars are drawn faintly or not at
all, so the field never looks like a menu of 40 options.

**Tap-once commits.** This is deliberate and differs from Dots and Boxes,
which needed confirm-on-second-tap because an edge there was an
irreversible move in a game that could be lost. Here **no choice can be
wrong**, so a mis-tap costs nothing but a different pattern — and a
confirmation step for a decision with no downside is friction pretending
to be care.

Hit-testing is by nearest offered star within a threshold, not by the
drawn circle, so a finger need not be precise.

### 7.2 Feedback

| Moment | Feedback |
|---|---|
| A star is offered | Slow pulse, no sound |
| Tap | Light haptic; the line draws out to the star |
| The region reveals | Soft tone, brightness blooming outward |
| Turn passes | The turn indicator moves; no haptic |
| The pattern completes | §7.3 |

### 7.3 The completion

**The highest-risk piece of UI in this build** (§3), specified rather
than left to taste:

The final line draws. A beat of stillness. Then the whole pattern
brightens from the origin outward, in the order it was actually built —
so the animation is a record of the two of you taking turns, not a
generic sweep. It holds at full brightness, and stops.

No confetti, no fanfare, no score tally. The pattern is the reward and
anything layered on top of it competes with the thing it is celebrating.

### 7.4 Accessibility

Every offered star is a semantics node, labelled by position and
availability, activated through the semantics tree rather than a
competing gesture recogniser — the mistake Word Hunt's board made twice
and had to fix.

The turn is a live region. Offered stars are distinguished by pulse and
size as well as brightness, so the field never depends on colour alone.

---

## 8. Data model

Reuses `game_sessions` with `game_type = 'constellation'`.

**There is no hidden gameplay information.** Both players see the whole
field, the whole pattern and every choice made. There is no disclosure
boundary, no private puzzle table, and no equivalent of Word Hunt's
hidden answer. That absence is the reason this is the cheapest game in
the Arcade to build correctly.

Operational metadata is still not disclosed: exact move timestamps and
the partner's replay cursor are withheld, because neither is needed to
play and a game board should not double as an activity log.

### 8.1 Scenes

```sql
CREATE TABLE IF NOT EXISTS public.constellation_scenes (
  version text PRIMARY KEY,

  -- [{"id": 0, "x": 0.14, "y": 0.62, "region": 3}, ...]
  nodes jsonb NOT NULL,

  -- [[0, 3], [0, 4], [3, 7], ...] -- legal growth directions
  edges jsonb NOT NULL,

  origin_node smallint NOT NULL,

  -- §4.3. Minimum revealed regions by which any two complete
  -- playthroughs must differ. Floor of 3, enforced by the validator.
  min_divergence smallint NOT NULL,

  created_at timestamptz NOT NULL DEFAULT now(),
  retired_at timestamptz
);
```

Immutable once played on, exactly as `snakes_boards` is: retuning a scene
would rewrite the history of every pattern already made on it. Tuning
means a new version; retirement metadata may still change.

### 8.2 Session state

```sql
CREATE TABLE IF NOT EXISTS public.constellation_state (
  session_id uuid PRIMARY KEY
    REFERENCES public.game_sessions(id) ON DELETE CASCADE,

  scene_version text NOT NULL
    REFERENCES public.constellation_scenes(version),

  -- Reached nodes in order, each with the slot that chose it.
  -- Slots, not user ids: a finished pattern should not carry an identity
  -- that can be deleted out from under it (the Dots and Boxes lesson).
  reached jsonb NOT NULL,

  moves_played smallint NOT NULL DEFAULT 0,
  updated_at timestamptz NOT NULL DEFAULT now()
);
```

### 8.3 Moves

A dedicated table, **not** `game_session_rounds`. That table is already
thirty-plus columns wide because four previous games each grafted their
own fields onto it, and Dots and Boxes' review established that a fifth
should not.

```sql
CREATE TABLE IF NOT EXISTS public.constellation_moves (
  session_id uuid NOT NULL
    REFERENCES public.game_sessions(id) ON DELETE CASCADE,
  move_number smallint NOT NULL,        -- server-assigned
  player_slot smallint NOT NULL CHECK (player_slot IN (1, 2)),
  action_id uuid NOT NULL,              -- client idempotency key
  node_id smallint NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),

  PRIMARY KEY (session_id, move_number)
);

CREATE UNIQUE INDEX constellation_moves_action
  ON public.constellation_moves(session_id, action_id);

-- A node is reached once.
CREATE UNIQUE INDEX constellation_moves_node
  ON public.constellation_moves(session_id, node_id);
```

### 8.4 Replay cursors

```sql
CREATE TABLE IF NOT EXISTS public.constellation_replay_cursors (
  session_id uuid NOT NULL
    REFERENCES public.game_sessions(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  last_seen_move smallint NOT NULL DEFAULT 0,
  PRIMARY KEY (session_id, user_id)
);
```

A caller receives their own cursor and never their partner's.

### 8.5 RLS and grants

Scenes are readable by `authenticated` — the field must be drawn, and
there is nothing secret in it.

**State, moves and cursors are RPC-only.** `authenticated` gets no direct
privilege, and the REVOKE is repeated in the file replayed by
`scripts/local_pg_grants.sql` after its blanket grant — otherwise the
local harness re-grants write access and the contract test passes or
fails by script ordering rather than by the schema.

`constellation` must be named in every `game_type NOT IN (...)` carve-out
on `game_sessions` and `game_session_rounds`, in both `USING` and
`WITH CHECK`. **Not a precaution:** the shared policies are permissive by
default, so a new `game_type` inherits write access unless it opts out.
Snakes shipped that defect and Word Hunt reproduced it before fixing.

---

## 9. Server contract

### 9.1 Lock order, and the re-check

Every mutating RPC locks the **session row** first, then state, then any
cursor row. One order, everywhere, including expiry and the
relationship-change trigger.

**A single lock order prevents deadlock; it does not prevent staleness.**
Every function that closes a session must re-read the staleness predicate
**after** acquiring the lock and skip the session if it no longer holds.
That is a separate requirement, and it was the fix Word Hunt needed
*after* its lock order was corrected.

### 9.2 Mutation order

**auth → session lock → membership → idempotency → relationship-active
and lazy expiry → turn check → move validation → mutation.**

Membership gates early; relationship *state* does not gate the retry
path, or a committed move becomes unrecoverable once a relationship is
archived.

`v_now := clock_timestamp()` is captured after the final blocking lock.
`now()` is transaction-start time and can predate a lock wait.

### 9.3 `constellation_choose_star(p_session_id, p_action_id, p_node_id)`

`p_node_id` is accepted as `numeric` so the function can reject NULL,
fractions and out-of-range values **inside the error envelope** — an
integer parameter would let Postgres reject a decimal before the envelope
runs, leaking a type name to the client.

- **Idempotent on `(session_id, action_id)`**, checked before every other
  rejection. A retry returns that move's stored result.
- A reused `action_id` with a **different** node is `IDEMPOTENCY_CONFLICT`
  — not a silent replay and not a second move. An action owned by the
  other member is also a conflict; action identity is never transferable.
- Refuses `NOT_YOUR_TURN`, `NODE_NOT_OFFERED` (the node is not on the
  current frontier), `INVALID_INPUT`.
- The frontier is computed **server-side** from the stored scene and
  reached set. The client never asserts what was offered.
- Appends the move, updates `reached` and `moves_played`, and mirrors
  `moves_played` into `game_sessions.current_round` so the shared
  realtime channel emits on every move.
- On the final node: `status = 'completed'`, `completed_at` from the
  post-lock timestamp. **No `winner_user_id` is ever set** — there is no
  winner, and a null there is the honest record.

### 9.4 `get_constellation_state(p_session_id)`

Scene, reached set, whose turn, the caller's cursor, and every move after
it — bounded by the whole game, at most 20 projections. Excludes
`created_at`, `action_id` and the partner's cursor.

**Reading does not advance the cursor.** Performs lazy session expiry:
deep links and resumed screens call this directly without pressing
anything, and Word Hunt shipped with that gap.

### 9.5 `constellation_ack_replay(p_session_id, p_through_move)`

Called after the client has rendered, skipped or suppressed the replay.
Monotonic `GREATEST`, so retries need no action id. Valid after
completion, or a final replay could never be acknowledged.

### 9.6 Lifecycle

Snakes' create / accept / decline / active-lookup, with:

- **Decline is for invitations only.** Once both are in, ending the game
  is not one person's decision.
- Acceptance pins a scene version, seeds both cursors at zero, assigns
  the first turn to the invitee, and seeds `updated_at`.
- Scene selection excludes those the couple has recently played (§4.6),
  falling back to the full library when exhausted.

### 9.7 Expiry

48h for an unaccepted invitation, **7 days** of inactivity for an active
game — longer than Snakes' 24h, because this is explicitly a game played
across days.

Cron **and** lazily on every RPC including the state read. The cron job
must be *registered*: writing Word Hunt's sweep turned up that
`expire_snakes_sessions()` had shipped written, granted, and never
scheduled, so abandoned boards blocked every future game between those
two people. A contract test asserts the registration exists.

### 9.8 Required contract tests

Not complete until SQL tests prove these against the `authenticated`
role, not by inspecting function source:

- direct INSERT/UPDATE/DELETE of a `constellation` session row is denied,
  while an unrelated legacy game keeps its intended access
- direct read or write of state, moves and cursors is denied
- unauthenticated and non-member calls to every RPC are denied
- **the validator refuses**: an unreachable node, a dead-end path, a
  frontier that offers one choice before the last move, a scene whose
  playthroughs diverge by less than its `min_divergence`, and a
  `min_divergence` below the floor of 3
- a node not on the frontier is refused; the frontier is derived
  server-side and a client claim about it is ignored
- a node cannot be reached twice
- a reused `action_id` with the same node replays; with a different node
  it returns `IDEMPOTENCY_CONFLICT`; owned by the other member, likewise
- the client cannot influence `move_number`
- the final node completes the session exactly once, and
  `winner_user_id` **stays null**
- concurrent choices by both players produce one legal state and one turn
  owner
- fetching does not advance the cursor; acknowledgement advances only the
  caller's, never backwards, and rejects a value beyond `moves_played`
- session expiry is enforced by every RPC including the state read
- the expiry sweep is registered with cron
- non-integer, decimal and out-of-range node ids return `INVALID_INPUT`
  rather than a raw SQL error
- `completed_at` never precedes the move that caused it
- a scene played by a couple is not offered again until the library is
  exhausted, and an exhausted library falls back rather than failing

### 9.9 Concurrency contracts

Three need two connections and cannot live in the single-transaction
suite. They belong in `scripts/concurrency/`, as Word Hunt's do:

- gameplay against the expiry sweep does not deadlock
- a sweep that selected a session, then waited on a live move's lock,
  does not abandon the now-fresh session
- two simultaneous choices resolve to one state with one turn owner

---

## 10. What this borrows

| Borrowed | From |
|---|---|
| Session lifecycle, error envelope, idempotency keys | Snakes |
| Versioned immutable content table with a validator | `snakes_boards` |
| RPC-write-only carve-out | The Snakes security fix, via Word Hunt |
| Lock order, under-lock re-check, post-lock timestamps | Word Hunt's review |
| Lazy expiry at every entry point including reads | Word Hunt's review |
| Slot-based ownership, ack-based replay cursor | Dots and Boxes' review |
| Recently-played exclusion as a pure function | Word Hunt's `word_hunt_pool` |
| Auto-pop, live sync, breathing wait | Snakes / session games |

**Genuinely new:** the scene validator and its divergence rule, the
frontier computation, and the completion animation.

---

## 11. Estimate

**Five to eight days**, plus scene authoring measured separately (§4.5).

Cheaper than Word Hunt's five-to-eight-plus because there is **no hidden
information**: no private table, no disclosure boundary, no generator, no
timing model, no rate-limit subtlety. Both players see everything.

Not cheaper than that figure suggests, because the six inherited
hardening requirements — the carve-out, one lock order, the under-lock
re-check, post-lock timestamps, lazy expiry everywhere, a registered
sweep — are real work. Each shipped broken in a previous game and cost a
review cycle. They are not free for being known.

---

## 12. Risks

**It becomes a progress bar.** The failure this design is most at risk
of, and §4.3 puts the guard in the database rather than in good
intentions. Still the thing to watch first in testing: if a couple cannot
tell their pattern from a stranger's, the divergence floor is too low.

**The completion falls flat.** With abstract art there is no object to
name, so the ending carries the whole payoff (§3, §7.3). Untestable
before it exists on a device.

**Authoring costs more than the code.** §4.5 — three scenes before any
server work, and if the third takes a day the art direction is wrong.

**The library runs out.** Twenty scenes is twenty sessions. The fallback
is honest rather than clever: replay a scene, and the choices differ. But
a couple who play often will notice.

**Nobody wants a game with no stakes.** The real product risk, and it
cannot be argued away in a spec. It can only be found out.

---

## 13. What was considered and rejected

Recorded because the reasoning matters more than the conclusion.

**Wall-clock decay** — a garden that dies untended, entropy as the
opponent. **Rejected outright.** It turns absence into failure and
leisure into maintenance, needs notifications to function, and punishes
the couple who had a bad week — precisely the couple this slot is for.

**A growing pile that overflows if you are careless** — shared loss as
the tension. **Rejected.** Shared loss does not prevent blame; it makes
it more direct. "We both lost because of your move" points back at the
partner, which is the exact thing this game exists to avoid.

**Permanent asymmetric abilities** — you move horizontally, they move
vertically. **Rejected.** It reliably produces one solver and one input
device: the stronger player works out the sequence and the partner taps
what they are told. Co-operative in shape only.

**Lantern Relay** — a light routed through a tile network toward three
lanterns. The mechanically strongest conventional game of those
considered, and **the wrong first choice for this slot**. Even with
curated boards and only current-endpoint choices visible, an objectively
better route exists. Hiding future information reduces the *visibility*
of the skill gap without removing it. Worth keeping as a future
co-operative *puzzle*, which is a different category from a cooldown
game.

**Pass the Key** — paired locks where each player's completed action
opens the partner's next one. The warmest concept considered, and
shelved on cost: eight to twelve days if there are only two reusable
puzzle primitives, and the honest risk is that it becomes alternating
solo mini-games with a shared frame painted over them.

---

## 14. What this spec does NOT claim

Every item here is a **failure** against the checklist, not a pass.

**Cannot be evidenced until built:** branch coverage, mutation testing,
a benchmark for the move path, 24-hour soak, 2× load, chaos with
Postgres killed mid-move, `EXPLAIN` for both access patterns.

**Cannot be evidenced without a device:** whether the completion animation
lands (§3, §7.3) — the single highest-risk unknown in the build; first-
feedback latency at p95; screen-reader navigation of the field.

**Not solved here:** observability (4.1–4.14) — no structured logs,
metrics, alerts or runbook, for this game or any Attune game, a
games-wide gap one spec should not pretend to close. Rollback and smoke
tests, shared with every migration.

**Not knowable from a spec:** whether a couple wants a game with no
stakes. §12's last risk.

---

## Changelog

- **2026-09-09** — Initial draft, after a brainstorm that rejected four
  alternative mechanics (§13). Written after Word Hunt's and Dots and
  Boxes' reviews, so their findings are folded in as requirements rather
  than left to be rediscovered: the RPC-write-only carve-out, one lock
  order plus the under-lock re-check, post-lock timestamps, lazy session
  expiry at every entry point *including the state read*, decline
  restricted to invitations, a registered cron sweep, input validated
  before casting, slot-based ownership, an ack-based replay cursor, and
  concurrency contracts that need two connections. Not reviewed, not
  approved, not implemented.

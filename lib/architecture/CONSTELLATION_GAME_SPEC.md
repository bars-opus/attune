# ATTUNE — CONSTELLATION SPECIFICATION

**Status:** Revised after two reviews. Not implemented, not approved.

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

Each turn offers two or three valid choices. Every one advances the work
by exactly one step, and every route is the same length. No choice is
optimal, faster, or worth more. What a choice changes is the shape of the
thing you are making together.

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

### 4.0 What the first draft got wrong

The first draft modelled a scene as **a graph of stars where a
playthrough ends when every node is reached** (§5.5), and then demanded
that any two playthroughs differ by at least three revealed regions
(§4.3).

**Those two rules cannot both hold.** If completion means reaching every
node, and every node names a fixed region, then every playthrough reveals
the identical set of regions and differs only in the *order* they
appeared. Divergence is always exactly zero. A correct validator would
have rejected every scene ever authored; an implementation that accepted
scenes would not have been implementing the spec.

Proven rather than argued, on the smallest case — a diamond `0 → {1,2}`:

```
complete playthroughs: [(0,1,2), (0,2,1)]
distinct region sets:  1
max divergence:        0        (the rule demands >= 3)
```

This is not a rule that was too weak. It was self-contradicting, and it
was the load-bearing claim of the entire design. §4 is therefore rebuilt
around a different model.

### 4.1 Scenes are layered choice states, not a free graph

A scene is an explicit state machine:

```
state  →  2 or 3 choices
choice →  { from_star, to_star, reveal_layers, next_state }
```

- A **state** is a point in the story of the pattern
- Each state offers exactly the choices authored for it — no more
- A **choice** names the line drawn (`from_star` → `to_star`), the
  **layers** of the pattern it reveals, and the state it leads to
- A **terminal state** has no choices, and reaching one completes the
  session

**A playthrough is complete when it reaches a terminal state**, not when
it has reached every star. That single change is what makes divergence
possible: two routes reveal genuinely different material because they
never visited the same choices.

This also fixes three problems the graph model had:

- **The offered set is now exact.** The graph model said "a turn offers
  two or three" of a frontier that could hold more, so the server's legal
  set and the client's visible set were different things and the spec
  never said which 2–3 were offered. A modified client could pick any
  frontier node. Now the state names its choices and both sides read the
  same list.
- **The line to draw is unambiguous.** With a graph, a node reachable
  from two reached predecessors left `node_id` unable to say which edge
  to animate, so two clients could draw different pictures from the same
  history. A choice names both endpoints.
- **Moves store the choice id**, not the node, so replay is exact.

### 4.2 Divergence, proved locally rather than enumerated

**Divergence must be provable without enumerating outcomes.** The second
draft said validation memoises over reachable states, which sounded
bounded and was not: the memo's *value* is a set of outcomes, and that
set grows exponentially even when the state count does not. Measured on
the 13-state chain in §4.2a — 4,096 outcomes either way, memo or no memo.
Twenty ternary turns would be billions.

So divergence is not measured. It is **implied by three local rules**,
each checkable in a single pass:

1. **Every variant layer has exactly one owning choice, scene-wide.** No
   two choices anywhere reveal the same variant layer.
2. **Every choice reveals at least two variant layers.**
3. **Material that appears on every route is not a variant layer at
   all** — it lives in a state's `common_layers`, revealed on entry
   however you arrived, and is excluded from divergence entirely.

Those three give the global property for free. Two routes that diverge at
any choice differ by that choice's layers *and* its sibling's, and since
no other choice can reveal them, they survive to the end. Minimum
symmetric difference is therefore at least `2 × 2 = 4`, above the floor
of 3, **without looking at a single outcome**.

Verified rather than argued: predicted 4, measured 4 by full enumeration
on the same scene.

```
every variant layer uniquely owned: True
min layers per choice:              2
guaranteed minimum difference:      4
empirical minimum difference:       4
```

**What this proves and what it does not.** It proves the *material*
differs, in polynomial time. It does not prove two finished patterns look
different to a person: four changed layers could be four faint sparks
beside an otherwise identical composition, and the database has no
geometry, no visual weight and no rendering with which to judge.

So validation is two-level, and §4.3a states exactly which half does
what — because the second draft asserted this split and then contradicted
it two sections later.

### 4.2a Reconvergence, and why the format needs it

A pure branching tree is unauthorable at the depth this game wants.
Computed rather than assumed:

```
turns   states   choices   outcomes
    3       15        14          8
    6      127       126         64
   12    8,191     8,190      4,096
```

Twelve turns of pure branching is eight thousand hand-authored states.
The library would never exist.

**So routes must reconverge**: different choices may lead to the *same*
next state. A chain of twelve reconverging pairs is 13 states and 24
choices, and still yields 4,096 distinct outcomes — author effort linear
in depth rather than exponential.

That creates one tension, and the spec resolves it rather than leaving it
to be discovered. With reconvergence, the two most similar outcomes
differ only by the layers of a single choice. With one layer per choice
the minimum divergence is 2, below the floor of 3:

```
bundle width 1: min divergence 2   below floor
bundle width 2: min divergence 4   OK
```

**So each choice must reveal at least two layers.** That is an authoring
rule the validator enforces, and the reason it exists is that
reconvergence — the thing that makes authoring possible — is also what
pushes the closest outcomes together.

### 4.2b Reconvergence must not disconnect the drawing

A state records where the story is, not which stars exist — and with
reconvergence, different routes into the same state have reached
different stars. A choice leaving that state names one `from_star`, and
it can be a star that route never drew.

Demonstrated on the smallest case. Two siblings draw `0→3` and `0→4`,
both reconverging on `S1`:

```
stars reached at S1, via a: {0, 3}
stars reached at S1, via b: {0, 4}
intersection:               {0}

from_star = 3 -> disconnected if they came via b
from_star = 4 -> disconnected if they came via a
from_star = 0 -> valid on both
```

The line would float, attached to nothing. §4.2a's "13 states and 24
choices" example is only a valid scene if this is checked, and it was
not.

**So every choice's `from_star` must lie in the intersection of stars
reached along all routes into its state.** Computed by forward dataflow —
propagate the reached-star intersection through the state machine to a
fixed point — which is polynomial and needs no enumeration, the same
discipline as §4.2.

Equivalently an author may give each state a **canonical anchor**: a star
every incoming choice is guaranteed to have drawn. The validator accepts
either, because both produce the same guarantee.

### 4.3 No objective optimisation — the honest version of "no skill"

The first draft claimed "no skill, structurally". That is overstated.
There is no *scoring* to optimise, but choices can still differ in
aesthetic influence, and without further rules one player could
systematically get the consequential turns.

The defensible claim is **no objective optimisation**: no choice is
better, and none is worth more. Three invariants make it true, all
validator-enforced:

1. **Equal, EVEN depth.** Every route has the same number of choices,
   *and* that number is even.

   The second draft required only equal depth and claimed both players
   therefore "always make the same number of decisions". That is false at
   odd depth — with turns alternating, depth 13 gives the invitee seven
   moves and their partner six:

   ```
   depth 11: invitee 6, partner 5   INVITEE +1
   depth 12: invitee 6, partner 6   equal
   depth 13: invitee 7, partner 6   INVITEE +1
   depth 20: invitee 10, partner 10 equal
   ```

   So the depth is even and within 12–20, giving 6–10 decisions each.
2. **Comparable visual weight per turn.** No choice may reveal
   dramatically more of the pattern than its siblings, and the budget is
   balanced across odd and even turns so neither slot systematically gets
   the consequential ones. Without this, an early high-impact choice
   decides half the composition while later turns add accents.

   **Postgres checks bundle cardinality; it cannot check weight** — see
   §4.3a. Rendered area and distribution are measured in authoring/CI.
3. **No choice reduces the partner's future options.** Not merely the
   immediate successor's arity, which the second draft compared and which
   is too shallow — two states can offer the same two choices now and
   very different counts two turns later. All states at a given depth
   must share an arity, so the shape of what remains is the same whichever
   route was taken.

With those three, a player thinking ten moves ahead arrives where one
tapping their nearest thumb does: at a different pattern, not a better
one.

### 4.3a Which validator enforces what

The second draft said Postgres has no geometry and cannot judge visual
weight, and then two sections later listed comparable visual weight among
the database validator's guarantees and demanded a SQL test rejecting a
visually dominant choice. Both cannot be true. The table holds layer
numbers.

| Property | Enforced by | How |
|---|---|---|
| Unique layer ownership | **Postgres** | One pass over the states blob |
| ≥2 variant layers per choice | **Postgres** | Cardinality |
| Equal depth, arity, non-narrowing | **Postgres** | Forward dataflow |
| `from_star` connectivity | **Postgres** | Forward dataflow (§4.2b) |
| Reachability, termination, 2–3 choices | **Postgres** | Traversal over states |
| Format bounds and identifier rules | **Postgres** | §4.4a |
| **Comparable visual weight** | **Authoring/CI** | Renders every terminal outcome, measures illuminated area and spatial distribution |
| **Perceptual difference** | **A person** | Contact-sheet review of rendered outcomes |

The bottom two rows are **not** database guarantees and are not claimed
as such anywhere. A scene passing every Postgres rule can still look
identical whichever way it is played; only a render and a human eye
catch that, and pretending otherwise is how the first draft went wrong.

### 4.4 What else the validator proves

A scene is refused storage unless:

1. **Every state is reachable** from the origin
2. **Every route terminates** — no cycles, no dead ends that are not
   terminal states
3. **Every non-terminal state offers 2 or 3 choices.** A state with one
   choice is not a decision, and rather than asking for a ceremonial tap
   the authoring format forbids it
4. **Equal depth, comparable weight, non-narrowing** (§4.3)
5. **Mutually exclusive sibling bundles and minimum divergence** (§4.2),
   and **at least two layers per choice** (§4.2a) — with reconvergence,
   single-layer choices put the closest outcomes below the floor
6. Stars referenced by choices exist and sit inside the field

**Checked by memoised traversal over reachable STATES, not over
playthroughs.** The first draft claimed exhaustive traversal was safe
"because a scene is 12–20 nodes and the space of playthroughs is small",
which was asserted rather than computed. It is not small:

```
16 nodes: up to 20,922,789,888,000 orderings
16 states: up to 65,536 reachable state sets
```

Orderings are intractable; states are trivial. The layered model is what
makes rule 4 checkable at all.

**A scene that fails validation is not stored.** It fails at insert, in
front of whoever authored it — never in front of a couple.

### 4.4a Format bounds and identity rules

Unstated in the second draft, which then referred to "a scene sized at
the format's maximum" as though one existed.

| Bound | Value |
|---|---|
| States | ≤ 64 |
| Choices per state | 2 or 3 (non-terminal), 0 (terminal) |
| Choices per scene | ≤ 160 |
| Stars | ≤ 64 |
| Variant layers | ≤ 512 |
| Depth | even, 12–20 |
| `states` blob | ≤ 64 KB |
| Identifier length | ≤ 32 characters, `[a-z0-9_]` |

And two identity rules the moves table depends on:

- **Choice ids are unique scene-wide**, not per state. `constellation_moves`
  stores only `choice_id`, so a duplicate would make history ambiguous.
- **A layer may not be revealed twice along any route.** Reconvergence
  makes this possible to author accidentally, and a layer revealed twice
  would break the divergence arithmetic in §4.2, which assumes each
  contributes once.

### 4.5 Authoring cost, flagged as a risk

An abstract scene should be quick to author, but the divergence and
equal-depth rules make each one a small construction problem.
**If a scene takes a day, the content cost dwarfs the code** and the
estimate in §11 is wrong.

So: author **three scenes before any server code** — a simple one, a
median one, and the most complex the format allows. Count rejected
drafts and time spent fixing validator failures, not just the final
draft. Three is a kill test, not an estimate: if they pass, author two
more as a batch to measure real throughput before committing to twenty.

### 4.6 The library, and repeats

**A scene is never repeated until the library is exhausted**, tracked the
way Word Hunt tracks recently-seen words.

The library is therefore the content budget: twenty scenes is twenty
sessions before anything returns. That is the trade accepted in exchange
for abstract art being cheap enough to author that a real library is
achievable.

When every scene has been played the exclusion falls back to the full
list rather than failing — a couple who play the library out must never
be told there is no game.

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

The session ends when a **terminal state** is reached (§4.1) — not when
every star is reached. That distinction is what makes divergence possible
at all; the first draft had it the other way round and the two rules
contradicted each other (§4.0).

The completed pattern animates once and holds.

There is no winner to name and no score to report. The end screen says
what was made, offers `Play again` prominently and `Back to chat`
secondarily — matching Snakes §5.4 and Word Hunt §13.

### 5.6 Leaving

There is no **resign**, because there is nothing to resign from — no loss
to avoid and no opponent to concede to. The word does not belong here.

But there is an **`End activity`** operation, available to either partner
at any time, with a confirmation. It closes the session with a neutral
`ended` reason, names no winner, and keeps the partial pattern viewable.

**The first draft got this wrong by importing a conclusion without its
reason** — the same mistake Dots and Boxes made and had to correct.
Word Hunt restricted unilateral ending because ending a live game there
destroyed a partner's in-progress attempt *and* released the hidden
answer early. **Neither exists here.** There is no secret, no result to
protect, and nothing to destroy — the pattern stays exactly as far as the
two of you took it.

What the restriction actually achieved was stranding a partner. If one
person stops on their turn, the other cannot move, cannot close it, and —
because the lobby allows one live session per couple — cannot start
another for seven days. That is worse than the thing the rule was
guarding against.

An unaccepted invitation may still be declined by either partner, which
is the ordinary lifecycle and not this operation.

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

**Tap-once commits**, but not because the choice is meaningless — the
layered model makes choices visibly consequential, and the second draft's
claim that "a mis-tap costs nothing" stopped being true when §4 was
rebuilt. A mis-tap costs you the pattern you would have made.

It differs from Dots and Boxes, which needed confirm-on-second-tap
because an edge there was irreversible *in a game that could be lost*.
Here there is no loss, so a modal confirmation is too heavy — but a slip
should still not commit.

So: **highlight on pointer-down, commit on pointer-up inside the target,
cancel if the finger moves away.** The rhythm of a single tap, with the
slip protection a consequential choice deserves.

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

**The reward needs an accessible form, not only the field.** A screen
reader user can navigate and activate stars, but this game's entire
payoff is a finished abstract picture — and "upper-left available star"
plus a brightness animation is functionally nothing. Navigation without a
perceivable ending is access to the chore and not to the game.

So two things beyond the usual:

- **Each choice carries a short, non-interpretive description** of what
  it draws — "a long arc to the upper left", not "a hopeful sweep". It
  describes the mark, never what it might mean, because meaning is the
  insight layer this slot does not have.
- **The completion has an audio and haptic form** that follows the actual
  build order: each contribution sounds in the sequence the two of you
  made it, so the record of taking turns survives into a form that does
  not require sight.

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

  -- Stars are positions only. They carry no game meaning; the state
  -- machine below decides what is offered and what it reveals.
  -- [{"id": 0, "x": 0.14, "y": 0.62}, ...]
  stars jsonb NOT NULL,

  -- The state machine (§4.1). Every non-terminal state offers 2 or 3
  -- choices; a terminal state offers none and completes the session.
  --
  --   {"S0": [{"id": "c1", "from": 0, "to": 3,
  --            "layers": [1, 2], "next": "S1"},
  --           {"id": "c2", "from": 0, "to": 4,
  --            "layers": [7, 8], "next": "S2"}],
  --    "S1": [...],
  --    "S3": []}
  --
  -- Sibling choices reveal MUTUALLY EXCLUSIVE layer bundles, which is
  -- what makes two routes produce different material rather than the
  -- same material in a different order (§4.0).
  states jsonb NOT NULL,

  origin_state text NOT NULL,

  -- §4.2. Minimum symmetric difference in revealed layers between any
  -- two terminal outcomes. Floor of 3, though the local rules in §4.2
  -- guarantee 4 without measuring it.
  min_divergence smallint NOT NULL,

  -- THE ARTWORK'S SOURCE OF TRUTH. Layer ids alone are not enough: a
  -- scene inserted today can be selected for an app build that has never
  -- heard of its layers, and the two partners can be on different
  -- builds. That renders missing artwork for one of them, or -- worse --
  -- different pictures from the same history.
  --
  -- Layers ship BUNDLED with the client as SVG groups, not delivered by
  -- the server: they are static art, and a game whose payoff is a
  -- picture should not have that picture arrive over a flaky connection
  -- mid-session.
  --
  -- So the scene pins the asset bundle it was authored against and the
  -- minimum client build that contains it. Scene selection (§9.6) offers
  -- only scenes both partners' builds can render.
  asset_bundle_id text NOT NULL,
  asset_bundle_hash text NOT NULL,
  min_client_build int NOT NULL,

  created_at timestamptz NOT NULL DEFAULT now(),
  retired_at timestamptz
);
```

**The SQL manifest and the Flutter asset manifest are generated from one
authoring source**, so a layer cannot exist in one and not the other. Two
hand-maintained lists of the same 512 ids will drift, and the failure is
invisible until a couple opens a scene with a hole in it.

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

  -- Where in the state machine this session stands.
  current_state text NOT NULL,

  -- The layers revealed so far, accumulated from the choices made.
  -- Slots, not user ids: a finished pattern should not carry an identity
  -- that can be deleted out from under it (the Dots and Boxes lesson).
  revealed_layers smallint[] NOT NULL,

  moves_played smallint NOT NULL DEFAULT 0,

  -- Both completion RPCs write this and the second draft gave it
  -- nowhere to live -- game_sessions has no such column, verified
  -- against the live schema.
  completion_reason text
    CHECK (completion_reason IN ('pattern_complete', 'ended')),

  updated_at timestamptz NOT NULL DEFAULT now()
);
```

**`take_choice` racing `end_activity`:** both take the session lock, so
whichever acquires it first wins. A session already `pattern_complete`
cannot become `ended` — the pattern was finished, and recording it as
abandoned would be a lie about a thing that happened. A session already
`ended` refuses further choices with `GAME_OVER`.

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

  -- The CHOICE, not the star. A star reachable by two different choices
  -- left the replay unable to say which line to draw, so two clients
  -- could render different pictures from the same history.
  choice_id text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),

  PRIMARY KEY (session_id, move_number)
);

CREATE UNIQUE INDEX constellation_moves_action
  ON public.constellation_moves(session_id, action_id);

-- A choice is taken once.
CREATE UNIQUE INDEX constellation_moves_choice
  ON public.constellation_moves(session_id, choice_id);
```

### 8.4 Replay cursors

```sql
CREATE TABLE IF NOT EXISTS public.constellation_replay_cursors (
  session_id uuid NOT NULL
    REFERENCES public.game_sessions(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  last_seen_move smallint NOT NULL DEFAULT 0,

  -- Separate from the cursor: the completion bloom is its own event, and
  -- a crash between the final line and the bloom must not consume it.
  completion_seen boolean NOT NULL DEFAULT false,

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

### 9.3 `constellation_take_choice(p_session_id, p_action_id, p_choice_id)`

Takes a **choice id**, not a star. The first draft took a node, which
left the offered set and the legal set as different things: a turn was
said to offer "two or three" of a frontier that could hold more, the spec
never said which, and the RPC accepted anything on the whole frontier —
so a modified client could take a star it was never shown.

Now the state names its choices, the client renders exactly those, and
the server validates against exactly those. There is no gap to exploit
because there is no arbitrary subset.

- **Idempotent on `(session_id, action_id)`**, checked before every other
  rejection. A retry returns that move's stored result.
- A reused `action_id` with a **different** choice is
  `IDEMPOTENCY_CONFLICT` — not a silent replay, not a second move. An
  action owned by the other member is also a conflict; action identity is
  never transferable.
- Refuses `NOT_YOUR_TURN`, `CHOICE_NOT_AVAILABLE` (the choice does not
  belong to the session's `current_state`), `INVALID_INPUT`.
- The available set is read **server-side** from the pinned scene's
  `current_state`. The client never asserts what it was offered.
- Appends the move, unions the choice's layers into `revealed_layers`,
  advances `current_state` to the choice's `next`, increments
  `moves_played`, and mirrors that into `game_sessions.current_round` so
  the shared realtime channel emits on every move.
- On reaching a **terminal state**: `status = 'completed'`,
  `completed_at` from the post-lock timestamp, `completion_reason =
  'pattern_complete'`. **No `winner_user_id` is ever set** — there is no
  winner, and a null there is the honest record.

`p_choice_id` is text and is validated for length and membership in the
current state's choice list before any use, so a malformed value is a
structured error rather than a raw SQL exception.

### 9.3a `constellation_end_activity(p_session_id)`

Available to either partner while the session is active (§5.6). Closes it
with `completion_reason = 'ended'`, no winner, and the partial pattern
intact. Idempotent by its own terminal state, so it needs no action id: a
second call, by either partner, returns the stored result.

Not resignation, and not reported as one.

### 9.4 `get_constellation_state(p_session_id)`

Scene stars, revealed layers, `current_state` **with its available
choices**, whose turn it is, the caller's cursor, and every move after it
— bounded by the scene's depth. Excludes `created_at`, `action_id` and
the partner's cursor.

The available choices come from the server, so the client renders what
the server will accept and the two cannot disagree.

**Reading does not advance the cursor.** Performs lazy session expiry:
deep links and resumed screens call this directly without pressing
anything, and Word Hunt shipped with that gap.

### 9.5 `constellation_ack_replay(p_session_id, p_through_move, p_completion_seen)`

Called after the client has rendered, skipped or suppressed the replay.
Monotonic `GREATEST`, so retries need no action id. Valid after
completion, or a final replay could never be acknowledged.

**`completion_seen` is tracked separately from the move cursor**, because
the completion bloom (§7.3) is a distinct event from the last move's
line. Acknowledging the final move and then crashing before the bloom
would otherwise mark everything seen and silently eat the one moment this
game exists for — the payoff, gone to a race.

So the cursor advances when a move has been drawn, and `completion_seen`
only when the bloom has finished or been explicitly skipped. A client
that reopens with `moves_played` acknowledged but `completion_seen` false
plays the completion.

**And `completion_seen = true` is refused unless it can be true.** The
second draft left it ungated, so a buggy client could set it during an
active game and permanently suppress the one moment this game exists for.
It is accepted only when the session is `pattern_complete` **and** the
caller's cursor has reached the final move; otherwise `INVALID_INPUT`.
Applied monotonically by boolean OR, so it can never be un-seen and a
retry is harmless.

Note it is gated on `pattern_complete` specifically, not on any terminal
status: a session closed by `end_activity` has no completion bloom to
have seen.

### 9.6 Lifecycle

Snakes' create / accept / decline / active-lookup, with:

- **Decline is for invitations only** — the ordinary lifecycle for an
  invitation nobody accepted. Ending an *active* session is
  `end_activity` (§5.6, §9.3a), available to either partner. The second
  draft kept a sentence here saying active ending "is not one person's
  decision", which directly contradicted the operation it had just added
  two sections earlier.
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
- **the validator refuses**: an unreachable state; a route that does not
  terminate; a non-terminal state offering other than 2 or 3 choices; a
  variant layer owned by two choices; a choice revealing fewer than two
  variant layers; a layer revealed twice along one route; a duplicate
  choice id; routes of unequal depth; an odd depth; states at one depth
  with differing arity; a `from_star` outside the reached-star
  intersection for its state; and every format bound in §4.4a
- **the validator never enumerates outcomes.** Given a scene at the
  format maximum, validation completes in bounded time — the local
  ownership rules of §4.2 imply divergence without measuring it, and
  memoising over states does NOT bound the work because the memo's value
  grows exponentially
- **`min_divergence` below 3 is refused**, and a conforming scene's
  actual minimum is at least 4 by construction
- **the validator does NOT claim to check visual weight or perceptual
  difference** (§4.3a) — those are authoring/CI and human review, and no
  SQL test asserts them
- a choice not belonging to the session's `current_state` is refused; the
  available set is derived server-side and a client claim is ignored
- a choice cannot be taken twice
- a reused `action_id` with the same choice replays; with a different
  choice it returns `IDEMPOTENCY_CONFLICT`; owned by the other member,
  likewise
- the client cannot influence `move_number`
- reaching a terminal state completes the session exactly once, with
  `completion_reason = 'pattern_complete'`, and `winner_user_id`
  **stays null**
- `take_choice` racing `end_activity` produces one terminal state: a
  completed pattern never becomes `ended`, and an ended session refuses
  further choices
- a scene whose `min_client_build` exceeds either partner's build is not
  offered
- `end_activity` is available to either partner while active, closes with
  `completion_reason = 'ended'`, names no winner, keeps the partial
  pattern readable, and is idempotent for both callers
- `completion_seen` advances independently of the move cursor: a client
  that acknowledged the final move but not the completion still gets the
  completion on reopening
- `completion_seen = true` is **refused** while the session is active,
  before the caller's cursor reaches the final move, and for a session
  closed by `end_activity`; it is monotonic and a retry is harmless
- concurrent choices by both players produce one legal state and one turn
  owner
- fetching does not advance the cursor; acknowledgement advances only the
  caller's, never backwards, and rejects a value beyond `moves_played`
- session expiry is enforced by every RPC including the state read
- the expiry sweep is registered with cron
- malformed, over-long and unknown choice ids return `INVALID_INPUT`
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
layered choice-state format and its traversal, and the completion
animation with its accessible form.

---

## 11. Estimate

**Eight to twelve days**, plus scene authoring measured separately
(§4.5) and an authoring/CI rendering pipeline that is not in that figure.

Raised twice. The first draft's scene model was a free graph, which was
both simpler and impossible (§4.0). The layered state machine that
replaces it is more to author and more to validate — and the second
review added forward-dataflow connectivity checks (§4.2b), format bounds
(§4.4a), an asset-compatibility gate (§8.1), and a generated dual
manifest so the SQL and Flutter layer lists cannot drift.

**The rendering pipeline is excluded from this figure** and is real work:
§4.3a puts perceptual difference outside the database, which means
authoring/CI must render every terminal outcome and produce a contact
sheet. Without it the divergence guarantee is structural only.

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
of. §4.2 puts a structural guard in the database — mutually exclusive
sibling bundles and a minimum symmetric difference — but is explicit that
Postgres cannot prove two pictures *look* different, only that the
material differs. The rendered comparison in CI and a human contact-sheet
review are the other half, and neither is optional.

Still the thing to watch first in testing: if a couple cannot tell their
pattern from a stranger's, the floor is too low or the layers too faint.

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

- **2026-09-09** — Second review. Eight findings, one of them a blocker
  again, and all eight confirmed by computation before being applied.

  **Memoising over states did not bound validation.** The first revision
  answered "exhaustive traversal is intractable" with "memoise over
  reachable states", which sounded bounded and was not: the memo's
  *value* is a set of outcomes and grows exponentially regardless. Same
  4,096 outcomes on the 13-state chain, memo or no memo. Divergence is
  now **proved locally** — every variant layer owned by exactly one
  choice scene-wide, at least two per choice, common material excluded —
  which implies a minimum symmetric difference of 4 with no enumeration
  at all. Predicted 4, measured 4.

  **Reconvergence could disconnect the drawing.** Two siblings drawing
  `0→3` and `0→4` reconverge on a state whose next choice has one fixed
  `from_star`, and that star exists on only one of the routes — the line
  would float, attached to nothing. §4.2a's own worked example was
  invalid for this reason. Now every `from_star` must lie in the
  intersection of stars reached along all routes into its state,
  computed by forward dataflow.

  **"Comparable visual weight" was claimed as a database guarantee** two
  sections after the spec correctly said Postgres has no geometry to
  judge it with. §4.3a is now a table naming which of Postgres, CI and a
  human enforces each property, and the contract tests explicitly do not
  assert the last two.

  **The artwork had no source of truth.** Layer ids with no asset
  identifier, hash or client-compatibility constraint: a scene inserted
  today could be selected for a build that has never heard of its layers,
  or render differently for each partner. Scenes now pin an asset bundle
  and minimum client build, selection filters on it, and both manifests
  are generated from one source so 512 ids cannot drift across two
  hand-maintained lists.

  **Equal depth did not mean equal participation.** With alternating
  turns, depth 13 gives the invitee seven moves and their partner six.
  Depth is now even. The non-narrowing rule also compared only immediate
  successor arity, which is too shallow — all states at a depth now share
  an arity.

  **`completion_reason` had nowhere to live** — neither table declared
  it, and `game_sessions` has no such column, verified against the live
  schema. Added, with the `take_choice`/`end_activity` race resolved: a
  completed pattern never becomes `ended`.

  Also: `completion_seen` was ungated, so a buggy client could consume
  the payoff during an active game; a stale lifecycle sentence still said
  active ending "is not one person's decision", contradicting the
  `end_activity` added two sections earlier; format bounds and identifier
  rules were referred to but never stated; and tap-once kept its rhythm
  but lost the claim that "a mis-tap costs nothing", which stopped being
  true when §4 was rebuilt — now highlight on pointer-down, commit on
  pointer-up inside the target.

  Estimate seven-to-ten to eight-to-twelve, with the rendering pipeline
  called out as excluded.

- **2026-09-09** — Revised after an external review. Eight findings, one
  of them fatal to the design as written.

  **§4.3's divergence rule was self-contradicting, not merely weak.** The
  first draft said a playthrough completes when every node is reached
  (§5.5) *and* that any two playthroughs must differ by at least three
  revealed regions (§4.3). If completion means reaching every node, every
  playthrough reveals the identical set and differs only in order —
  divergence is always exactly zero, so a correct validator rejects every
  scene that could ever be authored. Proven on a three-node diamond
  before the rewrite. This was the load-bearing claim of the whole
  design.

  §4 is rebuilt around an explicit **layered choice-state machine**:
  states offer 2–3 named choices, each naming the line drawn, the layers
  it reveals and the next state; completion is reaching a *terminal
  state*, not every star; sibling choices reveal mutually exclusive
  bundles. That makes divergence a real quantity, and fixes two further
  defects the graph model had — the offered set and the legal set were
  different things (so a modified client could take an unshown star), and
  a star reachable two ways left the replay unable to say which line to
  draw.

  **Divergence is now two-level and says so.** Postgres proves the
  material differs; only a rendered comparison in CI plus human review
  can prove two pictures look different. The first draft implied the
  database could do more than it can.

  **"No skill, structurally" was overstated** and is now "no objective
  optimisation", earned by three validator-enforced invariants: equal
  depth on every route, comparable visual weight per turn, and no choice
  that narrows the partner's future options. Without them, an early
  high-impact choice plus unequal route lengths would hand one slot real
  positional advantage.

  **§4.4's "exhaustive traversal is safe" was asserted, not computed** —
  16 nodes is up to 2×10¹³ orderings. Validation is over reachable
  *states* (65k) with memoisation.

  **§5.6 imported Word Hunt's conclusion without its reason** — the same
  mistake Dots and Boxes made. Restricting unilateral ending protected a
  hidden answer there; here there is nothing to protect, and the rule
  stranded a partner for seven days with no way to move, close, or start
  another game. Replaced with a neutral `End activity`.

  Also: `completion_seen` is tracked separately from the replay cursor,
  because a crash between the final line and the completion bloom would
  otherwise consume the one moment this game exists for; and the
  accessible path gains per-choice mark descriptions and an audio/haptic
  completion, since navigation without a perceivable ending is access to
  the chore rather than to the game.

  **One finding of my own, while checking the rewrite was buildable:** a
  pure branching tree at twelve turns is 8,191 hand-authored states, so
  the format needs *reconvergence* — different choices leading to the
  same next state — which makes author effort linear rather than
  exponential. That in turn pushes the two closest outcomes together, so
  each choice must reveal at least two layers to stay above the
  divergence floor. Both computed, not assumed (§4.2a).

  Estimate raised from five-to-eight days to seven-to-ten.

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

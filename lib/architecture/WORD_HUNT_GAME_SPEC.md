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
attempts end, the two results are revealed together.

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
| Result | Times side by side once both finish; differences under 1,000ms are a tie |
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
submit from one captured `clock_timestamp()` value minus `started_at`.
The client never sends a duration.

The running number on screen is only a display estimate. Start and state
responses include `started_at` and a `server_observed_at` captured just
before the response is built. The client seeds the display from their
difference, then advances it with a monotonic stopwatch rather than the
device wall clock. On resume or reconnect it refetches state and reseeds.
The submitted/revealed value always replaces that estimate with the stored
server result.

A client-supplied time would be the whole game handed to the client, and
this game is nothing but a number.

**What the reveal may say:** "You found it in 24s. Ama took 31s." A
comparison of two server-recorded measurements under the honest-client
trust model in §5.

**What it must not say:** anything framing this as a race that was won.
Nobody was present for the other person's attempt.

### 3.1 Giving up, and running out of time

Two ways an attempt ends without a find.

**"I can't find it"** — a visible button on the grid screen. Records
`status = 'gave_up'` with no elapsed time. It releases the reveal once the
partner is also terminal.

There is no cost to giving up: no score, no streak, no record. Staring
at a grid you cannot solve while your partner waits is the harm this
button prevents, and a game with nothing to lose should not make anyone
sit it out.

**The 10-minute timeout** — a started attempt that is never submitted is
swept as unfinished, so one player cannot block the other forever by
walking away mid-hunt.

The reveal says a person **did not find it**. It never says they quit:
the button is a kindness the game offers, and reporting it as a
surrender would turn that into something to be embarrassed about.


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
produced an accidental second occurrence **zero times**. The scan is
cheap insurance, not a bottleneck.

But that measurement shows duplicates are rare -- it does not show the
scanner works. A scanner that always returned 1 would pass it. So the
scanner is tested against grids built to break it:

- a second occurrence planted in each of the eight directions
- occurrences starting at every edge and corner
- a maximum-length diagonal
- two occurrences that overlap
- a reversed occurrence where the word was placed forwards
- a word with a repeated letter (`GIGGLE`)
- a palindrome, where one physical placement reads the same both ways
  and must be counted **once** -- occurrences are canonicalised by the
  lexicographically sorted pair of endpoints
- malformed input: wrong row count, ragged rows, non-letters, and a
  stored placement whose cells do not spell the stored word

### 4.3 Difficulty

Words are placed diagonally or backwards more often than not: a word
running left-to-right along a row is found in about two seconds and the
game is over before it starts.

Direction weights live in the same versioned config as the word list, so
difficulty is tunable without an app update.

---

## 5. What the server can and cannot prove

The first draft of this section claimed the placement was withheld from
the client and called the timing cheat-proof. Both claims were wrong,
and the way they were wrong is worth recording.

### 5.1 The leak, and where it came from

The draft put `hunt_grid`, `hunt_word` and `hunt_placement` on the
`game_sessions` row, and argued they were safe because the state RPC
omitted the placement column.

**RLS is row-level. It does not filter columns.** The existing
`game_sessions_relationship_members_select` policy returns the whole row
to either partner, so:

```sql
select hunt_placement from game_sessions where id = ...;
```

returns the answer. Verified against a local database before rewriting
this section: the client read the placement in full.

Omitting a column from an RPC hides it from the RPC. It does not hide it
from the table.

**The fix:** all puzzle material lives in `word_hunt_puzzles`, a table
with `authenticated` revoked entirely, reachable only through
`SECURITY DEFINER` RPCs. This is the same shape as
`this_or_that_round_answers`, which exists for exactly this reason.

### 5.2 The harder problem: the client holds both halves

Even with the placement withheld, **the client is given the grid and the
word.** Scanning a 10×10 grid in eight directions is trivial, so a
modified client can compute the answer and submit it immediately.

This is genuinely different from Paint Ball, where the hidden choice
cannot be reconstructed from anything the client can see. Here it can.

The word cannot be withheld — the player has to know what to look for.

**So this game is not cheat-proof, and the spec must stop saying it
is.** What the server can prove:

- the clock was started and stopped by the server, not the client
- the submitted cells match the stored placement
- no duration was ever accepted from a client

What it cannot prove is that a human searched the grid.

### 5.3 What that means for the product

**This is an honest-client comparison, not a contest.** That is
acceptable here and would not be elsewhere: there is no score, no
streak, no record, and nothing to win. The only thing a cheat buys is
lying to your partner about a number in a game you chose to play
together for fun — which is a relationship problem, not a security one.

It does mean the copy must never overclaim. No "winner", no ranking, no
leaderboard. Two times, side by side.

**An absolute elapsed difference below 1,000ms is shown as a tie**, because
the measurement includes Start-response latency, render time and Submit latency. A
player on a worse connection should not lose to network noise, and
ranking two numbers that close would be reporting jitter as skill.

If either player does not find the word, there is no speed comparison:
the reveal shows **found** and **did not find it**. A partner whose session
expired before they started is shown as **did not play**. These labels are
results, never wins or losses.

### 5.4 Still enforced

- `started_at`, `finished_at` and `elapsed_ms` are RPC-write-only.
- Submission is validated as a real drag (§10), not a set of cells.
- No partner timing or outcome is disclosed until **both** attempts are
  terminal — otherwise the second player starts knowing the benchmark.


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
it was. Shown to **both** players, including whoever did not find it:
never learning where the word was is maddening rather than kind.
`Play again` and `Back to chat`.

---

## 9. Data model

Reuses `game_sessions` with `game_type = 'word_hunt'`, but **no puzzle
material goes on that row** -- see §5.1. It lives in its own table with
`authenticated` revoked, so there is no column for a client to read and
no policy to get subtly wrong.

```sql
CREATE TABLE IF NOT EXISTS public.word_hunt_configs (
  version text PRIMARY KEY,
  words text[] NOT NULL,
  direction_weights jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  retired_at timestamptz
);

CREATE TABLE IF NOT EXISTS public.word_hunt_puzzles (
  session_id uuid PRIMARY KEY
    REFERENCES public.game_sessions(id) ON DELETE CASCADE,
  word text NOT NULL,
  grid jsonb NOT NULL,       -- ["ABCDEFGHIJ", ...] exactly 10 rows of 10
  placement jsonb NOT NULL,  -- ordered cells; never leaves the server
  word_list_version text NOT NULL
    REFERENCES public.word_hunt_configs(version),
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.word_hunt_configs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.word_hunt_puzzles ENABLE ROW LEVEL SECURITY;
-- No policies at all: nothing reaches these tables except a SECURITY
-- DEFINER function running as owner. A policy would be a door.
REVOKE ALL ON public.word_hunt_configs FROM PUBLIC, anon, authenticated;
REVOKE ALL ON public.word_hunt_puzzles FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE ON public.word_hunt_configs TO service_role;
GRANT SELECT, INSERT ON public.word_hunt_puzzles TO service_role;

CREATE TABLE IF NOT EXISTS public.word_hunt_attempts (
  session_id uuid NOT NULL
    REFERENCES public.game_sessions(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,

  -- A boolean cannot tell a timeout from a choice. The UI may show them
  -- identically; the database must not record one as the other.
  status text NOT NULL DEFAULT 'in_progress'
    CHECK (status IN ('in_progress', 'found', 'gave_up', 'timed_out')),

  started_at timestamptz NOT NULL DEFAULT now(),
  finished_at timestamptz,
  elapsed_ms int,

  -- Rate limiting reads these rather than scanning a log.
  last_submission_at timestamptz,
  submission_count int NOT NULL DEFAULT 0,

  PRIMARY KEY (session_id, user_id),
  CHECK (submission_count >= 0),
  CHECK (finished_at IS NULL OR finished_at >= started_at),
  CHECK (last_submission_at IS NULL OR last_submission_at >= started_at),
  CHECK (
    (status = 'in_progress'
      AND finished_at IS NULL AND elapsed_ms IS NULL)
    OR
    (status = 'found'
      AND finished_at IS NOT NULL
      AND elapsed_ms IS NOT NULL AND elapsed_ms BETWEEN 0 AND 599999)
    OR
    (status IN ('gave_up', 'timed_out')
      AND finished_at IS NOT NULL AND elapsed_ms IS NULL)
  )
);

ALTER TABLE public.word_hunt_attempts ENABLE ROW LEVEL SECURITY;
-- Also closed. A readable attempts table would let a player see their
-- partner's time before starting, and a writable one would let them
-- rewrite their own clock.
REVOKE ALL ON public.word_hunt_attempts FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE ON public.word_hunt_attempts TO service_role;
```

The config table's validator requires a non-empty unique list of uppercase
ASCII words, each 4 to 8 letters, and exactly eight non-negative direction
weights with a positive total. Session creation selects the newest
unretired config by `(created_at, version)` and fails clearly if none exists.
The puzzle table also has a validating trigger. It independently checks
that the grid is exactly 10 rows of 10 ASCII letters, the word belongs to
the referenced config and satisfies
the configured length and alphabet rules, the placement is in bounds and
contiguous, its cells spell the word, and the canonical occurrence scan
finds exactly one physical occurrence. The generator and trigger use the
same scanner implementation, while the adversarial tests call that scanner
directly; creation fails rather than storing a puzzle that does not pass.

Puzzle rows and the words/weights of a versioned config are immutable once
referenced by a session. Tuning creates a new version; it never changes an
active or historical puzzle. Retirement metadata may change without
changing the contents a session pinned.

An attempt transition trigger provides a final invariant beneath the RPCs:
`started_at`, `session_id` and `user_id` never change; `submission_count`
never decreases; `last_submission_at` never moves backwards; and the only
status transitions are `in_progress -> found|gave_up|timed_out`. Every
terminal state is immutable. This catches a future SECURITY DEFINER RPC
that accidentally tries to reopen or retime an attempt.

Closing the private tables is not enough. The migration must also recreate
the shared `game_sessions` INSERT, UPDATE and DELETE policies with
`word_hunt` added to every `game_type NOT IN (...)` carve-out, in both
`USING` and `WITH CHECK`. Otherwise either partner can directly complete or
delete the session and bypass the attempt RPCs, repeating the Snakes defect.
Direct SELECT may remain because the shared row contains no puzzle or raw
attempt data.

Every exposed function revokes execute from `PUBLIC` and `anon`, grants it
only to `authenticated`, validates `auth.uid()`, and uses a fixed safe
`search_path` with fully qualified object names. Internal generator and
validator functions are not executable by authenticated clients.

**None of these private tables joins the realtime publication.** Publishing
attempts would broadcast a partner's raw row -- their time, their status --
straight past every RPC that exists to withhold it. Live updates come
from `game_sessions`, which carries only public lifecycle state. Word Hunt
has no turn owner. The first terminal attempt does **not** touch a public
revision or `updated_at`, because that event alone would reveal that the
partner had finished. The second terminal attempt completes the session,
which gives both clients a row change to observe before refetching sanitized
state.


## 10. Server contract

Every mutating RPC takes `SELECT ... FOR UPDATE` on the **session row**
before touching an attempt. Near-simultaneous finishes are ordinary here,
not an edge case; without the lock each transaction could read the other
as unfinished and neither would close the session. Lock order is always
session first, then attempt, so Start, Submit, Give Up and expiry cannot
deadlock by taking the same rows in different orders.

Mutation order is: **auth, membership, relationship still active, session
lock, action-specific idempotency, lazy expiry, rate limit where applicable,
then state validation and mutation.** Idempotency precedes expiry, rate
limit and status rejection so a retry of a committed terminal action
returns its stored result. An in-progress attempt already beyond its
deadline is then changed to `timed_out` before a new action can affect it.
Read RPCs authenticate and lock only when they need to perform lazy expiry.
For a new action, the RPC captures `v_now := clock_timestamp()` immediately
after acquiring its locks and uses that one value for deadline checks,
rate limiting, `finished_at` and elapsed time. PostgreSQL `now()` is fixed at
transaction start and could predate time spent waiting for the session lock,
so it is not the clock used for resolution.

### Lifecycle RPCs

The Snakes lifecycle is reused through Word Hunt-specific create, accept,
decline, hide and active-session lookup RPCs. It is not inherited merely by
using the same table. Creation validates the relationship and active-session
limit, selects and pins an unretired config, inserts the session, generates
and validates the puzzle, and inserts the private puzzle in one transaction.
A generation failure rolls the whole transaction back, leaving no invite
without a puzzle. Accepting activates the session but does not start either
player's clock. Word Hunt never assigns `current_turn_user_id`.

The migration also adds `word_hunt` to every shared game-type constraint,
resolver and chat-card allowlist used by the lifecycle. The active-session
uniqueness rule covers invited and active Word Hunt sessions for the same
relationship, matching the replay/lobby model used by Snakes.

### `word_hunt_start(p_session_id)`

Creates the attempt and returns the puzzle **in one transaction**. The
grid cannot be fetched before the clock has committed -- otherwise a
client could study the puzzle and start the timer afterwards. A database
transaction cannot guarantee that the response reaches or renders on the
device: if the response is lost, the clock still runs and the retry returns
the original timestamp and puzzle.

```sql
INSERT INTO word_hunt_attempts (session_id, user_id, started_at)
VALUES (..., v_now) ON CONFLICT (session_id, user_id) DO NOTHING;
```

Then read the row back. A concurrent double-tap, a retried request, or a
reopened app all resolve to the first `started_at` and the same puzzle.
Start is permitted only after the invitation is accepted and while the
session is active. If the existing attempt is already terminal, Start
returns that stored state rather than reopening it.

**Time keeps running** through backgrounding, a phone call, a crash or a
dropped connection. There is no pause: a client-controlled pause is a
client-controlled clock.

### `word_hunt_submit(p_session_id, p_cells jsonb)`

Validated as a **drag**, not a set of cells:

- exactly `length(word)` cells
- all in bounds, all distinct
- consecutive cells differ by exactly one step in a single fixed
  direction -- a straight line in one of the eight legal directions
- the sequence equals the stored placement, or its exact reverse (the
  word may be dragged from either end)

A set comparison would accept the right letters selected in a scattered
order, which is not the game.

On a hit: `status = 'found'`, `finished_at = v_now`,
`elapsed_ms = floor(extract(epoch FROM (v_now - started_at)) * 1000)::int`.

Returns hit or miss, and partner data **only when both attempts are
terminal**.

On every structurally valid miss, the same transaction updates
`last_submission_at` and increments `submission_count`; a hit does likewise
before becoming terminal. The 300ms limit is abuse protection, not an
anti-cheat claim -- a modified client can solve locally without guessing.
A duplicated miss caused by transport retry may be rate-limited, but it
cannot change a result or add a player-visible penalty. Successful terminal
submissions are fully idempotent and return the stored elapsed time.

After any transition to a terminal state, the RPC queries both attempts
while still holding the session lock. Exactly two terminal attempts move
the session to `completed` and set `completed_at`; one terminal attempt
leaves it active. This check is shared by Submit, Give Up and lazy/cron
expiry rather than reimplemented three ways.

### `word_hunt_give_up(p_session_id)`

`status = 'gave_up'`, no elapsed time. Refused once the caller has
already found the word: giving up afterwards would rewrite a result.
It also requires an existing in-progress attempt; giving up from the lobby
does not silently start and finish a clock.

First terminal action prevails. A submit and a give-up racing each other are
serialised by the session lock, and the second finds the attempt already
terminal and returns its stored state.

### `get_word_hunt_state(p_session_id)`

- **Before the caller starts:** no grid, no word. They are withheld until
  Start, so a player cannot study the puzzle off the clock.
- **After the caller starts:** grid and word.
- **Partner timing and status:** only once both attempts are terminal.
  The draft leaked each time as that player finished, which let the
  second player start knowing the number to beat.
- **Placement:** only once the session is over -- then shown to both,
  including whoever did not find it (§13.3).

### Expiry

The 10-minute attempt sweep runs on cron, but **every state and mutation
RPC also expires an overdue attempt lazily after authentication, locking
and any applicable idempotent-result lookup**.
Cron is the backstop; a player opening the game after eleven minutes
should see the finished state immediately rather than whenever the job
next runs.

A session where a partner never taps Start at all is covered by the
shared session expiry, not by the attempt timeout -- there is no attempt
to time out. Session expiry is terminal for disclosure purposes: any
in-progress attempt becomes `timed_out`, the absent partner is represented
as **did not play** rather than **did not find it**, and the placement may
then be revealed because nobody can start that expired puzzle. No synthetic
attempt row is created for the absent partner.

The deadline comparison is `v_now >= started_at + interval '10 minutes'`,
using the post-lock timestamp captured for the transaction.
At the boundary, timeout wins. A Submit or Give Up that acquired the session
lock first may commit before the deadline check in a competing transaction;
the first committed terminal transition remains authoritative.

### Required contract tests

The backend is not complete until SQL tests prove all of these against the
authenticated role, not merely by inspecting function source:

- direct SELECT from configs, puzzles and attempts is denied
- direct INSERT, UPDATE and DELETE of a Word Hunt `game_sessions` row is
  denied, while an unrelated legacy game retains its intended policy
- unauthenticated and non-member calls to every RPC are denied
- state before Start contains no grid, word, placement or partner attempt
- two concurrent Starts produce one attempt and one immutable timestamp
- a lost-response Start retry returns that original timestamp and puzzle
- a finished partner remains undisclosed until the caller is also terminal
- concurrent Submit/Submit and Submit/Give Up calls produce one legal final
  state and complete the session exactly once
- a successful Submit retry returns the stored elapsed time before timeout,
  rate-limit and terminal-state checks
- the millisecond before the deadline may finish and the deadline itself
  times out, through a pure internal deadline helper that accepts the
  captured server timestamp; tests do not depend on sleeps
- session expiry with an absent partner reveals **did not play**, closes any
  in-progress attempt and never creates a synthetic attempt
- no private table is in the realtime publication, and the first terminal
  attempt causes no observable `game_sessions` update
- every adversarial scanner case in §4.2 is rejected or canonicalised as
  specified


## 11. What this borrows

| Borrowed | From |
|---|---|
| Session lifecycle and error envelope | Snakes, adapted for simultaneous play |
| Delayed-disclosure RPC pattern and contract test | Paint Ball §5.5; its secrecy claim does not transfer |
| Versioned immutable config table | `snakes_boards` |
| RPC-write-only RLS carve-out | The Snakes security fix |
| Auto-pop, live sync, breathing wait | Snakes / session games |
| Sound generation | `tool/generate_*_sounds.dart` |

**Genuinely new:** grid generation with its uniqueness scan, the drag
gesture with axis snapping, the pill, and the two-attempt timing model.

Estimate: **five to eight days.**

The first draft said three to four, counting the gesture and the pill
and treating the server as a day. That was before the review found the
puzzle needed its own private tables, the concurrency needed real
locking, the generator needed adversarial tests, and the grid needed an
accessible alternative to dragging. None of those are optional and none
were in the original figure.

---

## 12. Risks

**The comparison is not a race, and the copy must not pretend it is.**
Framing matters more than usual: two people who did not play at the same
time being told one "beat" the other is a small lie.

**Grid generation can loop.** The uniqueness scan rejects and retries,
bounded at 20 attempts.

The draft's fallback was "place it in a straight line" -- which is
meaningless, since every legal placement is already a straight line, and
worse, it bypassed the very validation it was falling back from. **A
generator that cannot produce a unique grid in 20 attempts fails the
session creation.** An unstarted game is a minor annoyance; an ambiguous
puzzle tells a player who found the word that they are wrong.

**A 10×10 grid of letters is small on a phone, and this one is dragged
on.** At ~340dp of usable width a cell is about 34px -- under the 44px
touch-target guidance, and this game asks for a *precise path* across
several of them rather than a single tap.

Mitigations, specified rather than left to discovery:

- hit-testing extends beyond the drawn cell, so the finger does not have
  to be centred
- direction locks with hysteresis once a drag establishes an axis: a
  wobbling finger holds its line instead of flickering between diagonals
- **tap-first-letter then tap-last-letter** as a complete alternative to
  dragging, which is also the only path that works with switch control
- selection is shown by the pill's shape and position, never by colour
  alone
- tested on the smallest supported device with the largest text setting,
  since both shrink the grid

**Competition may work against the reason this slot exists.** Snakes is
in the Arcade because a couple after an argument want something with no
stakes. This game has a comparison at the end, and "you were slower"
lands differently at 11pm after a hard conversation than it does on a
Sunday afternoon.

Not a reason to cut it -- a small competitive thing between two people
who are fine is good, and the app should not assume every session
follows a fight. But it is why the copy is neutral, why sub-second
differences are a tie, and why `Play again` is the prominent action at
the end rather than the times themselves.

**Difficulty is unknowable from here.** Whether a diagonal backwards word
takes 15 seconds or 90 is a device question, and the direction weights
exist so it can be tuned after finding out.

---

## 13. Questions, settled

All three are now settled. Kept here with their reasoning rather than
deleted, because the reasoning is what a later reader needs.

1. ~~**Should a player be able to give up?**~~ **Settled: yes — an
   "I can't find it" button, alongside the 10-minute timeout.**

   The objection was that it lets someone bail on a losing round. That
   assumes losing costs something, and here it does not: no score, no
   streak, no record. Staring at a grid you cannot solve while your
   partner waits is the actual harm, and a way out is the kinder design.

   Giving up records `status = 'gave_up'` with no elapsed time.

2. ~~**Is one word per session too thin?**~~ **Settled: one word.**

   It is over in thirty seconds and that is the point — this is the
   quick game beside the slow one. `Play again` is one tap, and a couple
   who want five words can have five sessions.

3. ~~**Should the loser see the answer?**~~ **Settled: yes, everyone
   sees the placement once the session ends.**

   Never learning where it was is maddening rather than kind. The word
   is drawn on the grid at the reveal for whoever did not find it,
   exactly as for whoever did.

---

## Changelog

- **2026-09-07** — Initial draft.
- **2026-09-08** — Reviewed. Two security findings, both confirmed
  against a local database before rewriting:

  - **The puzzle was readable by the client.** The draft put the grid,
    word and placement on `game_sessions` and claimed the placement was
    safe because the state RPC omitted it. RLS is row-level: a partner
    selecting their own session row got every column. Proven, then moved
    to `word_hunt_puzzles` with `authenticated` revoked outright.
  - **The game is not cheat-proof and the spec said it was.** The client
    must be given the grid and the word, and a 10x10 grid is trivially
    scanned in eight directions, so a modified client can compute the
    answer without looking. Unlike Paint Ball, the hidden thing is
    derivable from the visible thing. §5 now says so plainly and frames
    this as an honest-client comparison.

  Also: attempts get their own closed table with a four-state status
  rather than a boolean (a timeout is not a surrender), session-row
  locking for concurrent finishes, submission validated as a contiguous
  drag rather than a set of cells, partner timing withheld until both
  attempts are terminal, lazy expiry alongside cron, adversarial
  generator tests including palindromes and repeated letters, an
  accessible tap-first/tap-last alternative to dragging, and the
  estimate raised from three-to-four days to five-to-eight.

- **2026-09-08** — All three open questions settled. A visible "I can't
  find it" button joins the 10-minute timeout; one word per session
  stands; and the placement is revealed to both players at the end,
  including whoever did not find it. Still not implemented, not
  approved.

- **2026-09-08** — Second review pass. Made the shared `game_sessions`
  RPC-write-only carve-out explicit for Word Hunt; added the versioned config
  foreign key, private-table grants, validators and attempt transition
  invariants; defined lifecycle RPCs, lock order, post-lock timestamp capture,
  terminal completion and session-expiry behaviour; removed the public
  first-finish realtime signal; and corrected stale references to the deleted
  `gave_up` boolean. Added an executable security/concurrency contract-test
  list and clarified that a committed Start may outlive a lost response.

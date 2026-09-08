# Word Hunt — Algorithm Quality Review

Audited against `lib/architecture/algorithms/algorithm_quality_review_checklist.md`.

**Date:** 2026-09-08 · **Scope:** `word_hunt_*` RPCs, puzzle generation, Flutter client
**Tags:** `[SERVICE]` `[MUTATION]` `[UI]` `[MOBILE]` — not `[FIN]`, not `[BATCH]`, not `[ASYNC]` beyond one cron sweep

**Verdict: externally reviewed, ten findings fixed, awaiting device QA.
Still not production-cleared.**

**Revised 2026-09-08 after an external implementation review.** It found
ten defects, three release-blocking. All ten were reproduced against a
live database before being fixed, and all ten now have regression tests
that fail against the unfixed code — verified by reverting each fix in
turn. Two of the ten were claims *in this document* that the code did not
support.

The Snakes audit that preceded this one said "ships", was written by the
author of the code, and was wrong — an external review found a
release-blocking authorization hole plus eight further defects, several
inside items marked as passing. That correction is the reason this
document is shaped the way it is: **a self-audit is evidence of intent,
not of quality**, and every claim below names the artefact that backs it
rather than asserting a conclusion.

Two things were found here by disbelieving my own reasoning, and both are
recorded in full rather than smoothed over.

---

## What the external review found

Three release blockers, none of which any existing test touched — the
tests were written by the same person who decided which paths mattered.

**1. Either partner could kill a live hunt and be handed the answer.**
`word_hunt_decline_session` checked membership and then abandoned the
session at any status. Reproduced:

```
B is hunting: attempt=in_progress
A declines an ACTIVE session -> {"ok": true, "existing": false}
session is now: abandoned   B attempt is now: timed_out
WARNING: A destroyed B's live hunt AND got the answer: [[6,0],...]
```

Worse than the disclosure leak it looks like: because an abandoned
session is terminal for disclosure, A — who never started, and so risked
nothing — ends B's attempt mid-hunt and is handed the placement. A
griefing move with a reward attached. Decline now means *decline an
invitation*; leaving a live game is Give Up, which ends only the caller's
own attempt.

**2. Gameplay and expiry took opposite lock orders.** Gameplay locks
session then attempt; expiry wrote attempts then sessions. Reproduced:
`ERROR: deadlock detected`. This directly disproved item 1.6 below.

**3. Expiry could leave a clock running on a dead game.** The sweep
snapshotted ids, updated attempts, then updated sessions — so a Start
landing in that window survived as `in_progress` under an `abandoned`
session, a state no RPC would ever close. Reproduced:

```
 session  |   attempt
abandoned | in_progress
```

Both are fixed by the same rewrite: iterate session by session, take the
**session** lock first, re-read staleness *under* that lock, then close
attempts and session together.

**Also found:** the session deadline was enforced only from the lobby, so
a client arriving by push notification could accept a 50-hour-old
invitation (4); decimal and oversized coordinates escaped as raw SQL
exceptions instead of `INVALID_INPUT` (7); `completed_at` used
transaction-start time and could precede the finish that caused it (9);
a slow `refresh()` could overwrite a finished submit and make the reveal
vanish (5); the realtime provider never refreshed on reconnect, so a
waiting player could stay waiting indefinitely (6); the reveal said "You
were quicker", which is a winner declaration in a politer register (8);
and this document's "provably undetectable" mutant claim was too
strong (10).

### The concurrency tests that now exist

Three of these could not be expressed in `supabase/tests/`, which runs
inside a single transaction — a lock race needs two connections. They
live in `scripts/concurrency/word_hunt_races.sh`, run by the local
harness, and each was verified to fail against its own reverted fix.

---

## What was wrong before that, found during implementation

**1. The session row was writable straight past every RPC.** The same
defect Snakes shipped. Reproduced against a local database before it was
fixed:

```
ATTACK 3: declare the session complete by writing the table
  WARNING:  EXPLOIT CONFIRMED: player completed the session directly
ATTACK 4: delete the session
  WARNING:  EXPLOIT CONFIRMED: deleted the session
ATTACK 5: insert a word_hunt session directly
  WARNING:  EXPLOIT CONFIRMED: inserted a session with no puzzle behind it
```

Completing the session directly releases the reveal before the partner
has finished — the entire disclosure boundary bypassed by one statement.
It recurs because the shared policies are permissive by default: a new
`game_type` inherits write access unless it opts out. Fixed in
`20260936140000`; all three attacks now blocked and covered by contract
tests.

**2. Two reapers that never ran.** Word Hunt needed an expiry sweep, and
writing it turned up that `expire_snakes_sessions()` — written, granted,
shipped — was **never registered with cron**. Because the lobby allows one
live session per couple, an abandoned Snakes board silently blocked every
future game between those two people. Both are now scheduled, and a
contract test asserts the registration exists.

**3. Four tests that proved nothing.** The "a word is not repeated"
rule was tested four ways and each was measured against a build with the
exclusion deleted:

| Test shape | Caught the deleted exclusion |
|---|---|
| six draws from the 36-word list | 5 of 12 |
| three draws from a three-word list | 8 of 12 |
| two draws from a two-word list | 7 of 15 |
| asserting the whole draw sequence | 4 of 15 |

The reason is structural: with the exclusion gone the draw is random, and
a random draw *agrees* with the rule often enough that any assertion over
draws is a coin flip. The rule was extracted into `word_hunt_pool()`, a
pure function, and asserted where there is exactly one right answer —
**12 of 12** with the exclusion deleted.

---

## 🔴 P0-U — Universal blocking

| # | Item | Evidence |
|---|---|---|
| 1.4 | Authorization at every access | `word_hunt_authorize()` runs before every RPC body. **Crucially also at the table**: `word_hunt_configs`, `word_hunt_puzzles` and `word_hunt_attempts` have `authenticated` revoked and **no RLS policy at all** — a policy would be a door. Contract test proves a member's direct SELECT is denied on all three, and that the shared `game_sessions` row is not writable for `word_hunt`. |
| 1.5 | Authentication verified | `auth.uid()` first in every function; NULL → `UNAUTHORIZED`. Contract test calls all five client RPCs with no claims and asserts `UNAUTHORIZED`. |
| 2.1 | Input sanitisation | `p_cells` is validated as a *drag*: exact length, in bounds, one fixed step held for the whole run. Malformed jsonb, wrong length, out-of-bounds at the correct length, and the right cells in the wrong order are each rejected by name. Grid and word are validated by an anchored `^[A-Z]{10}$` per row. |
| 2.2 | Parameterised queries | No dynamic SQL in the feature. `grep` for `EXECUTE format` / `EXECUTE '` across all nine migrations returns nothing. |
| 2.3 | Constant-time secret comparison | **N/A.** No secrets, tokens or signatures compared anywhere in this feature. |
| 2.4 | Error messages don't leak | `word_hunt_error()` maps a code to a fixed user-facing sentence; no internals reach the client. A widget test asserts the codes, table names and ids never appear on screen. |
| 2.5 | Resource limits | Generation bounded at 20 attempts then **fails rather than storing an ambiguous grid**. Grid fixed at 10×10. Recent-words query `LIMIT 10`. Submissions rate-limited at 300ms. |
| 2.6 | Output sanitisation | Payloads are jsonb built field by field; the client renders letters into `TextPainter`, not markup. |
| 2.7–2.9 | No hardcoded secrets | Nothing secret exists in this feature. |
| 2.10 | Resources released | No connections, files or streams held. The Flutter side disposes its `AnimationController`, `Stopwatch`, `Timer`, `WidgetsBindingObserver` and `WordHuntBoardController`. |
| 5.5 | No internal info in UI | Covered by the widget test above. |
| 7.1–7.3 | Dependency / SAST / secret scans | **Not run for this change.** Inherited from repo-wide CI; not verified by me. Stated as a gap, not a pass. |
| 7.5 | Encryption in transit | Supabase client is TLS-only. Inherited, not re-verified. |
| 7.6 | CSRF/CORS | **Skipped:** native-mobile-only surface, no browser-facing endpoint. |

## 🔴 P0-C — Contextual blocking

Only 2.6 and 7.6 apply; both addressed above.

## 🟡 P1 — High

| # | Item | Evidence |
|---|---|---|
| 1.1 / 2.18 | Idempotency for all mutations | Creation takes a client key and an advisory lock. **Start** returns the original `started_at` and puzzle on retry — a lost response does not restart the clock, because the server genuinely did start. **Submit** checks terminal state *first*, before expiry, rate limit and status, so a retry of a committed result returns that result rather than an error about the state it produced. Give Up on an already-found attempt returns the found result. All four have contract tests. |
| 1.2 | Timeouts on external calls | 30s on every RPC in `WordHuntService`, matching the rest of the app. |
| 1.6 | Concurrency identified and mitigated | **Was FAILING when first audited.** I claimed "one lock order, so nothing here deadlocks against itself" on the strength of races I had run between *gameplay paths* — submit vs submit, submit vs give-up, start vs start. Expiry and the relationship trigger wrote **attempts before sessions**, the inverse, and an external review found it. Reproduced: `ERROR: deadlock detected`. The claim was about the paths I had thought to test, not about the system. Now: every path that closes a session takes the session lock first, iterating session-by-session in id order, and a contract test asserts the ordering in all three closing functions. |
| 1.10 | Rollback for multi-step failures | Session creation, puzzle generation and puzzle insert are one transaction. A generation failure rolls the session back, so there is never an invitation with no puzzle behind it. |
| 1.11 | Privacy | No PII in this feature. The grid, the word and two integers. |
| 2.16 | Shared mutable state protected | The session lock, above. |
| 3.10 | No retry on permanent errors | `WordHuntApiError.isTerminal` marks `SESSION_EXPIRED`, `GAME_OVER`, `NOT_FOUND`; the UI offers a way out rather than a retry. Unit-tested. |
| 6.1 | Edge cases | Deadline boundary asserted exactly (the millisecond before finishes, the deadline itself times out) through a pure `IMMUTABLE` helper — **no sleeps**. Scanner tested against every direction, every corner, the longest diagonal, a repeated letter, a palindrome, overlapping runs, and five malformed inputs. |
| 6.3 | Concurrency tested | The multi-process races above. |
| 6.4 | Negative tests | The five reproduced attacks; "one finished attempt does not complete the session"; "a miss does not end the attempt"; "giving up cannot rewrite a found result"; "expiry does not invent a row for the absent partner". |
| 2.19–2.23 | Financial | **N/A.** No money. |
| 3.12 | Graceful shutdown | **N/A** for a Postgres function; the mobile client has no in-flight server state to drain, and the clock is server-owned by design. |
| 8.1 | Rollback procedure | **Not written.** Tier 3 by the checklist's own definition. Gap. |

## 🟢 P2 — Medium

| # | Item | Evidence |
|---|---|---|
| 1.3 | Graceful degradation | Every RPC failure surfaces a sentence and a way out; the board goes inert rather than accepting drags it cannot submit. |
| 1.7 | Stateless | All state in Postgres. |
| 1.8 | Complexity documented | Scanner is O(rows × cols × 8 × len) = 800·len cell reads, ~15k for an 8-letter word; **measured**: 400 generated grids in 352ms. |
| 1.9 | Consistency model | Strong: every read and write goes through a `SECURITY DEFINER` function against the primary. |
| 3.1 | Pagination | **N/A.** Every payload is one session; nothing here returns a list. |
| 3.2 | No N+1 | Each RPC is a fixed number of statements regardless of history. |
| 3.3 | Indexes, EXPLAIN run | **Was failing.** `EXPLAIN` showed `Seq Scan on game_sessions` for both the lobby lookup and the hourly sweep. Two partial indexes added in `20260936180000`; both plans are now index scans. |
| 3.4 | Cache strategy | **N/A.** Nothing cached. |
| 3.7 | Backpressure | The 300ms limiter, plus the shared five-games-per-hour initiation limiter. |
| 3.8 | Rate limiting tested | Contract test asserts two submissions in the same transaction return `RATE_LIMITED` **and that the limiter cannot change a result**. |
| 4.1 / 4.5 | Structured logs | **Not implemented.** These RPCs emit nothing. Consistent with the other games; a gap for all of them, not just this one. |
| 4.4 | No sensitive data logged | Vacuously true — nothing is logged. |
| 4.6–4.10 | Metrics and alerts | **Not implemented.** Gap, shared with every other game. |
| 4.11 | Configurable thresholds | **Partially failing.** The word list and direction weights are a versioned table, tunable without an app update. But the 10-minute deadline, the 300ms limiter and the 48h/24h expiry windows are literals in the function bodies. Honest status: fail. |
| 4.12–4.13 | Health / readiness | **N/A.** No service to probe. |
| 5.1 | Actionable errors | Each message says what happened and what to do next. |
| 5.2 | p95 ≤ 200ms first feedback | **Not measured on device.** The pill follows the finger locally with no network in the path, and the board goes inert during a submit, so first feedback is a frame — but that is reasoning, not a trace. Gap until device QA. |
| 5.3 | Progressive loading | Spinner on every await. |
| 6.2 | Failure scenarios tested | Malformed grid, missing puzzle, non-member, unauthenticated, expired attempt, expired session, absent partner. |
| 6.7 | Branch coverage | **Line coverage measured, not branch** — the checklist asks for branch and `flutter test --coverage` gives lines. Reported as measured: models 92.0%, selection 92.9%, board 94.3%, reveal 98.6%, game screen 89.5%, lobby 70.2%, provider 58.8%, service 6.7% (eight RPC wrappers need a live client; the one piece of real logic there is extracted and tested). **Total 79.7%.** Core logic clears the ≥90% target; adapters and the provider sit below ≥70%. |
| 6.9 | Performance benchmark | Generation measured (400 grids / 352ms). No benchmark on the RPC round trip. |
| 6.10–6.12 | Soak / load / chaos | **Not run.** Gaps. |
| 6.13 | Documentation | `WORD_HUNT_GAME_SPEC.md`, plus every non-obvious decision commented at the point it is made. |
| 6.14 | Runbook | **Not written.** Gap. |
| 7.4 | Least privilege | `authenticated` gets execute on exactly eight RPCs and nothing else; every helper, validator and generator is revoked, asserted by a contract test that enumerates thirteen of them. Private tables grant only `service_role`. |
| 8.2–8.3 | Smoke tests, 24h metrics | **Not run.** Post-deployment. |

## ⚪ P3 — Nice to have

| # | Item | Evidence |
|---|---|---|
| 6.5 | Property-based tests | The selection sweep: for all 100 target cells, every path the client can produce is a straight line of distinct in-bounds cells in one of the eight legal directions — the same property the server independently enforces, so the two cannot drift into the client submitting what the server rejects. |
| 6.6 | Determinism | Generation is deliberately random; the scanner, the deadline helper and `word_hunt_pool()` are `IMMUTABLE` and tested directly. The flaky-test episode above is recorded because it is the interesting part. |
| 6.8 | Mutation testing | **41 mutants, 40 killed.** The survivor deletes the generator's *own* uniqueness scan. I called this "provably undetectable" and **that was too strong** — a review pointed out the two versions differ in AVAILABILITY, not just correctness: with the scan, generation retries up to 20 times; without it, an ambiguous first candidate reaches the table trigger and aborts session creation outright. Correctness is preserved either way (the trigger refuses the bad grid), so no player is ever told a right answer is wrong — but "equivalent mutant" was the wrong words for it. It is a *correctness*-equivalent mutant with a different failure rate, and the honest reason it survives is that the difference only shows at a frequency my tests do not sample. |
| 5.4 | Retry guidance | Terminal codes offer a way out instead of a retry. |
| 5.6 | Accessibility | Tap-first-letter / tap-last-letter is a complete alternative to dragging and the only path that works with switch control. Every cell carries a label naming its letter, row and column. Selection is shown by the pill's shape and position, never colour alone. `reduceMotionOf` suppresses the breathing mark and the dismissal animation. **Not audited with a real screen reader on a device** — that is device QA. |
| 3.5, 3.6, 3.11, 3.13, 4.2, 4.3, 4.14 | Parallelisation, I/O batching, circuit breaker, bulkheads, correlation IDs, tracing, DLQ | **N/A** at this scale, or not implemented. Not claimed. |

---

## Honest summary

**Passing and evidenced:** authorization at the table as well as the RPC,
the disclosure boundary, idempotency on all four mutations, concurrency
under real races *including gameplay against expiry*, input validation as
a drag rather than a set with integer coordinates checked before any
cast, least privilege, the adversarial scanner suite, and mutation
testing at 40/41.

**What the review changed about how this document should be read.** Two
of its ten findings were claims made here that the code did not support:
item 1.6 asserted one lock order on the strength of races I had run
between gameplay paths only, and item 6.8 called a surviving mutant
"provably undetectable" when the two versions differ in availability.
Both are corrected in place, with the original claim left visible. The
pattern is the same one the Snakes audit taught and this one repeated:
**the dangerous items are not the ones marked failing, they are the ones
marked passing on the strength of evidence I chose myself.**

**Failing or not done, stated as such:**

- 4.11 — three thresholds are literals in function bodies
- 4.1, 4.5, 4.6–4.10 — no structured logs, metrics or alerts (shared with every game)
- 6.7 — line coverage, not branch; provider 58.8% and service 6.7% miss the ≥70% adapter target
- 6.10–6.12 — no soak, load or chaos testing
- 6.14, 8.1 — no runbook, no rollback procedure
- 5.2, 5.6 — first-feedback latency and screen-reader behaviour reasoned about, not measured on a device
- 7.1–7.3 — dependency, SAST and secret scans inherited from CI, not re-run for this change

**What this feature is honest about in its own copy:** it is not
cheat-proof. The client is given both the grid and the word, and a 10×10
grid is trivially scanned in eight directions, so a modified client can
compute the answer without looking. The server can prove the clock was
its own, that the submitted cells match the stored placement, and that no
duration was ever accepted from a client. It cannot prove a human
searched. Because there is no score, no streak and nothing to win, that
is acceptable here — and it is why the reveal says two times side by
side and never a winner.

**Not production-cleared.** It wants an external review pass and device
QA before that claim is made, for the reason at the top of this file.

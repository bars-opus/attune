# Snakes and Ladders — Algorithm Quality Review

Audited against `lib/architecture/algorithms/algorithm_quality_review_checklist.md` v3.1.

**Date:** 2026-09-07 · **Scope:** `snakes_*` RPCs, board config, Flutter client
**Tags:** `[SERVICE]` `[MUTATION]` `[UI]` `[MOBILE]` — not `[FIN]`, not `[BATCH]`

**Verdict: code-complete for device QA, not production-cleared. Revised
2026-09-07 after two external review passes.**

The first version of this audit said "ships". It was written by the same
person who wrote the code, and it was wrong — an external review found a
release-blocking authorization hole plus eight further defects, several
in items I had marked as passing. What follows is the corrected audit,
with the items I over-marked called out as such.

**The lesson worth keeping: a self-audit is evidence of intent, not of
quality.** Every item below that changed from pass to fail was one I had
convinced myself of.

---

## 🔴 P0-U — Universal blocking

| # | Item | Evidence |
|---|---|---|
| 1.4 | Authorization at every access | **Was FAILING when first audited.** The shared RLS policies granted members direct INSERT/UPDATE/DELETE on every non-Paint-Ball game, so a player could set their own position to 100 and name themselves winner without rolling. I audited the RPCs and never checked whether the table could be written around them. Fixed in `20260935130000`; a contract test now proves the write is refused. |
| 1.5 | Authentication verified | `auth.uid()` at the top of every function; NULL → `UNAUTHORIZED` |
| 2.1 | Input sanitisation | **Was incomplete.** The board validator accepted a ladder to 101 (which aborts the turn on landing and silently rerolls) and a board where 100 is unreachable. Both now rejected, with reachability proved by working backwards from 100. |
| 2.2 | Parameterised queries | No dynamic SQL anywhere in the feature |
| 2.3 | Constant-time compare | **N/A** — no secrets compared |
| 2.4 | Errors don't leak | `snakes_error()` returns fixed player-facing strings; the client's `catch (_)` never renders an exception |
| 2.5 | Resource limits | State RPC bounded to 20 rounds; board is a single row; walk animation bounded by board size |
| 2.7–2.9 | Secrets | **N/A** — none introduced |
| 2.10 | Resources released | Animation controllers disposed; no open handles |
| 4.4 | No PII in logs | Nothing logged by this feature |
| 5.5 | No internals in UI | Only `snakes_error` messages reach the screen |
| 7.1–7.3 | Dependency / SAST / secret scan | Existing CI; no new dependencies |
| 7.5 | TLS | Supabase client, TLS 1.2+ |

## 🔴 P0-C — Contextual

| # | Item | Status |
|---|---|---|
| 2.6 | Output sanitisation | **N/A** — no user-authored text in this game at all |
| 7.6 | CSRF/CORS | **Skipped** — native mobile only |

## 🟡 P1

| # | Item | Evidence |
|---|---|---|
| 1.1 / 2.18 | Idempotency | `snakes_create_session` retains one UUID only across a failed attempt and clears it after success; `snakes_roll_die` checks `(session, round, player)` before rate, expiry and status, so even a retry after relationship teardown returns the committed roll. Contract-tested. |
| 1.2 | Timeouts | 30s on all six client calls |
| 1.6 | Concurrency | `FOR UPDATE` serialises turns; relationship and idempotency-key advisory locks serialise creation. A true two-connection race test is still absent. |
| 1.10 | Compensating paths | Single-transaction turns; nothing partial to unwind |
| 1.11 | Data privacy | No PII; positions are not personal data |
| 2.11–2.15 | Pools, cancellation, memory | Supabase pool; animation bounded; no caches. `Future.timeout` bounds the UI wait but does not cancel the underlying HTTP request. |
| 2.16 | Shared state | Server-side, row-locked |
| 3.10 | No retry on permanent errors | Client does not auto-retry |
| 6.1 | Edge cases | Boundary sweep over all 600 (position, roll) pairs asserts nothing leaves the board |
| 6.4 | Negative tests | Outsider refused, out-of-turn refused, finished game refused, retry does not double-move |
| 7.4 | Least privilege | `anon` revoked on all; internal helpers revoked from players; `expire_snakes_sessions` is `service_role` only; shared table writes exclude Snakes. |

## 🟢 P2

| # | Item | Evidence |
|---|---|---|
| 1.3 | Graceful degradation | **Partial.** A malformed board still renders as an empty board rather than saying so. Acceptable only because the board is server-owned and validated on write; a client-facing "this game is unavailable" state is still missing. |
| 1.7 | Stateless | All state in Postgres |
| 1.8 | Complexity | Movement is O(1); walk is O(cells) ≤ 100 |
| 1.9 | Consistency | Strong — single row, single transaction |
| 2.17 | Pure logic testable | `snakes_resolve_move` is `IMMUTABLE` and tested with no session |
| 3.1 | Pagination | State RPC caps rounds at 20 |
| 3.2 | No N+1 | One row read per turn |
| 3.3 | Indexes | Partial unique on `(session, round, player)`; turn lookup index |
| 3.8 | Rate limiting | 1s per roll; 5 sessions/hour per couple |
| 4.11 | Configurable | **Partial.** The board is a versioned table row, but the rate limits, history cap, round cap and every animation duration are hardcoded. |
| 5.1 | Actionable errors | Each code has a player-facing next step |
| 5.2 | p95 ≤ 200ms | **Unmeasured, not passed.** The die tumbles on tap so first feedback is immediate, but no trace has been taken. |
| 5.6 | Accessibility | Die is a labelled button; the board now describes itself and its token positions; reduce-motion honoured. **Was failing** — the painted board had no semantics at all. |
| 6.2 | Failure scenarios | Malformed board, unknown movement kind, absent board version, initial-load failure, stale async load, expired invite/active session, relationship teardown and retry after teardown |
| 6.7 | Coverage | **Not measured.** Branch coverage was never run. The service, provider and screen paths are largely untested; what exists covers the model, geometry, board parsing and wiring. |
| 6.8 | Mutation testing | 8 mutants now, all caught — but hand-picked by the author, which is not evidence of a <5% survival rate. Two of them only became effective after a review pointed at what I had not thought to break. |

---

## Observability (4.1–4.10)

**Absent, and omitted from the first audit entirely.** This feature emits
no logs, no metrics, and has no alerts or runbook. For a game with no
money and no personal data the risk is low, but the items are not passed
and should not have been left out.

## Mutation testing

| Mutant | Result |
|---|---|
| Idempotency moved after the rate limit | **caught** |
| Overshoot wins instead of bouncing | **caught** |
| Board pin removed at creation | **caught** |
| Board rows all left-to-right | **caught** |
| Client sends a die face | **caught** |
| Sheet routes to the wrong game | **caught** |
| Direct table write declaring a winner | **caught** (after the fix) |
| Bounce read from `movement` instead of `didBounce` | **caught** (the first version of that test checked only the model and missed it) |

One of these is worth recording: the die-face mutant *appeared* to survive
on the first run. The mutation script had failed to apply, because
`dart format` had collapsed the lines its anchor matched. The test was
nonetheless genuinely weak — its regex anchored on a leading quote and
would have missed `'p_die_roll'`. Found only by disbelieving a green run.

---

## Open — require production

These cannot be satisfied before deployment and are not claimed:

| # | Item |
|---|---|
| 6.9 | Performance benchmark on the critical path |
| 6.10 | 24h soak |
| 6.11 | Load test at 2× peak |
| 6.12 | Chaos test in staging |
| 8.2 | Production smoke test |
| 8.3 | 24h metric verification |

**Also not done:** no device testing and no Snakes golden suite. Everything
above is verified by contract, unit, and widget tests. Whether the walk animation *feels* right, and
whether a 10×10 board is legible on a real phone, are judgements a test
cannot make.

## Rollback (8.1, Tier 2)

Seven migrations. Reverting means:

- `DROP FUNCTION` on the `snakes_*` set and `get_active_snakes_session`
- `DROP TABLE public.snakes_boards` and its two triggers
- Dropping the added columns on `game_sessions` and
  `game_session_rounds`, and their `CHECK` constraints and indexes
- **Restoring the previous RLS policies on both shared tables** — the
  security fix widened the paint_ball exclusion, so a revert must put
  those back rather than leave them half-changed
- `cron.unschedule('expire-snakes-sessions')`
- Removing the Arcade entry and both routes
- Existing `snakes_and_ladders` game cards in chat would need hiding

Not the trivial revert the first audit described. No data migration to
undo, but the RLS change makes this a considered rollback rather than a
drop.

## Still open

Unchanged from the first audit, and still true: 6.9 benchmark, 6.10
soak, 6.11 load, 6.12 chaos, 8.2 production smoke, 8.3 metric
verification. **And nothing has run on a device.**

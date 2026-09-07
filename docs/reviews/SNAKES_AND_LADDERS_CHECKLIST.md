# Snakes and Ladders — Algorithm Quality Review

Audited against `lib/architecture/algorithms/algorithm_quality_review_checklist.md` v3.1.

**Date:** 2026-09-07 · **Scope:** `snakes_*` RPCs, board config, Flutter client
**Tags:** `[SERVICE]` `[MUTATION]` `[UI]` `[MOBILE]` — not `[FIN]`, not `[BATCH]`

**Verdict: ships, with four items open that require production and are listed as such.**

---

## 🔴 P0-U — Universal blocking

| # | Item | Evidence |
|---|---|---|
| 1.4 | Authorization at every access | Every RPC re-reads the relationship and checks membership; `get_active_snakes_session` checks before revealing a session exists |
| 1.5 | Authentication verified | `auth.uid()` at the top of every function; NULL → `UNAUTHORIZED` |
| 2.1 | Input sanitisation | Round number range-checked and capped at 1000; idempotency key length-bounded; positions and `movement_kind` constrained by `CHECK` |
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
| 1.1 / 2.18 | Idempotency | `snakes_create_session` on key; `snakes_roll_die` on `(session, round, player)` — **checked first, before rate limit and status**, so a retry never re-rolls. Mutation-tested. |
| 1.2 | Timeouts | 30s on all five client calls |
| 1.6 | Concurrency | `FOR UPDATE` on the session row; `pg_advisory_xact_lock` on create |
| 1.10 | Compensating paths | Single-transaction turns; nothing partial to unwind |
| 1.11 | Data privacy | No PII; positions are not personal data |
| 2.11–2.15 | Pools, cancellation, memory | Supabase pool; animation bounded; no caches |
| 2.16 | Shared state | Server-side, row-locked |
| 3.10 | No retry on permanent errors | Client does not auto-retry |
| 6.1 | Edge cases | Boundary sweep over all 600 (position, roll) pairs asserts nothing leaves the board |
| 6.4 | Negative tests | Outsider refused, out-of-turn refused, finished game refused, retry does not double-move |
| 7.4 | Least privilege | `anon` revoked on all; `expire_snakes_sessions` is `service_role` only |

## 🟢 P2

| # | Item | Evidence |
|---|---|---|
| 1.3 | Graceful degradation | Board load failure → `NOT_FOUND`, not a crash; malformed board parses empty |
| 1.7 | Stateless | All state in Postgres |
| 1.8 | Complexity | Movement is O(1); walk is O(cells) ≤ 100 |
| 1.9 | Consistency | Strong — single row, single transaction |
| 2.17 | Pure logic testable | `snakes_resolve_move` is `IMMUTABLE` and tested with no session |
| 3.1 | Pagination | State RPC caps rounds at 20 |
| 3.2 | No N+1 | One row read per turn |
| 3.3 | Indexes | Partial unique on `(session, round, player)`; turn lookup index |
| 3.8 | Rate limiting | 1s per roll; 5 sessions/hour per couple |
| 4.11 | Configurable | Board is a table row, versioned per session |
| 5.1 | Actionable errors | Each code has a player-facing next step |
| 5.2 | p95 ≤ 200ms | Tap → die tumbles immediately; the roll resolves behind it |
| 5.6 | Accessibility | Die is a labelled `Semantics` button; reduce-motion honoured throughout; position readout means no numeral is load-bearing |
| 6.2 | Failure scenarios | Malformed board, unknown movement kind, absent board version |
| 6.7 | Coverage | Movement, geometry, parsing, errors, die, wiring |
| 6.8 | Mutation testing | 6 mutants, all caught — see below |

---

## Mutation testing

| Mutant | Result |
|---|---|
| Idempotency moved after the rate limit | **caught** |
| Overshoot wins instead of bouncing | **caught** |
| Board pin removed at creation | **caught** |
| Board rows all left-to-right | **caught** |
| Client sends a die face | **caught** |
| Sheet routes to the wrong game | **caught** |

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

**Also not done:** no device testing. Everything above is verified by
tests and golden renders. Whether the walk animation *feels* right, and
whether a 10×10 board is legible on a real phone, are judgements a test
cannot make.

## Rollback (8.1, Tier 2)

Three migrations, all additive — new table, new columns, new functions.
Reverting is `DROP FUNCTION` on the `snakes_*` set plus removing the
Arcade entry; no existing game reads any of it. No data migration to
undo.

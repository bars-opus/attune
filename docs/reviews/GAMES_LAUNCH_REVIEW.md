# Games — launch-hardening review (2026-07-12)

Audit of the Games module (This or That, Truth or Dare, 36 Questions) against
[GAMES.md v2.0](../../lib/architecture/GAMES.md), focused on the security /
correctness contract (§5.2–5.4 idempotency, authz, input validation; RLS). The
in-flight `20260712120000_games_launch_hardening.sql` was strong on session
lifecycle, membership-scoped RLS, the concurrency win-condition for round
completion (`both_answered=false` compare-and-swap), and the atomic skip counter
(`skips_used_a < 1`). Three findings were fixed.

## GAMES-1 (High) — Report griefing / arbitrary content hide — **FIXED**

`report_custom_question(id)` → `increment_custom_question_report_count` set
`hidden_for_review=true` on **any** custom question by id, with no
membership/ownership check and **no report threshold** — a single (even anon,
see GAMES-3) actor could instantly suppress anyone's partner/community question.
The function name said "report_count" but no count existed; it hard-hid on the
first call. Separately, This or That's client report path inserted into a
`forum_reports` table that **no games migration creates** (runtime failure) and
called the now-removed `increment_custom_question_report_count`.

**Fix:** new `custom_question_reports` ledger (RLS: reporters read/write only
their own rows) with `UNIQUE(question_id, reporter_user_id)` so a report is
one-per-reporter. Rewrote `report_custom_question(p_question_id, p_reason)` to
record the caller's report idempotently and flip `hidden_for_review` only once
**≥ 2 distinct reporters** have flagged it. Existence is opaque (no error reveals
whether an id exists). Both game clients now call this single RPC; the phantom
`forum_reports` insert and dead RPC are removed.

## GAMES-2 (Medium) — Ungated counter writes — **FIXED**

`increment_custom_question_usage` and `increment_community_usage` incremented
counters on an arbitrary id with no authz. Added an `auth.uid() IS NULL` guard so
an unauthenticated caller is rejected.

## GAMES-3 (High) — RPCs executable by anon (no REVOKE/GRANT) — **FIXED**

The migration created SECURITY DEFINER RPCs with **no** grant statements, so all
defaulted to `EXECUTE TO PUBLIC` (incl. `anon`). Added
`REVOKE ALL … FROM PUBLIC, anon` + `GRANT EXECUTE … TO authenticated` for every
Games RPC (`mark_this_or_that_round_complete`, `mark_round_complete`,
`increment_skip_count`, `increment_custom_question_usage`,
`report_custom_question`, `increment_community_usage`).

## Contract test

`supabase/tests/games_contracts.sql` (four accounts A+B couple, C outsider, D
owner/second-reporter) proves: (1) RPCs revoked from anon, granted authenticated;
(2) one reporter cannot hide a question, a second distinct reporter does, and a
repeat report from the same reporter is idempotent; (3) counter RPC rejects an
unauthenticated caller; (4) an outsider cannot complete an A/B round or forge a
skip for another user. Auto-discovered by `scripts/run_sql_contracts.sh`.

## Not changed (correct as built / deferred)

- Session lifecycle, idempotency (`session_idempotency_keys`), round-complete
  concurrency, atomic skips, membership RLS — verified correct against §5.2–5.4.
- Rate limits (§5.4), observability/metrics (§5.8), cursor pagination (§5.9) —
  product/ops gates, not code defects for the flag-off launch.
- In-flight repo cleanups folded in: `Random.secure()` for the truth/dare pick
  (was `millisecondsSinceEpoch % 2` — predictable), dead-code removal,
  `withOpacity`→`withValues` on touched lines.

## Motion

Applied the universal `lib/core/ui` toolkit to This or That's reveal: a match now
fires a `HapticFeedback.mediumImpact()` and the `MatchIndicator` settles into a
`GlowPulse` — the game's warmest beat — while a non-match stays quiet. Consistent
with the Dating match-reveal treatment.

## Remaining launch blockers (human/ops, not code)

Run `games_contracts.sql` green in CI; wire rate limits + observability;
product-review the community question-sharing moderation policy (threshold value).

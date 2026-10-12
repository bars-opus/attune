# Planning v2 P1 — Algorithm Quality Review Checklist v3.1 evidence

Spec: docs/superpowers/specs/2026-10-12-planning-v2-design.md §12. This file records what P1 actually proved, measured on branch `feat/planning-advance` on 2026-10-12.

| Check | Evidence |
|---|---|
| 1.4 Authorization at every access | Every RPC resolves the row, then calls `planning_v2_actor`. Each of the five v2 SQL contract files has "stranger" contracts. A mutant with the actor check removed from `get_planning_entry` was caught by planning_v2_entry_contracts Contract 4 ("stranger read entry"). |
| 1.6 / 2.16 / 6.3 Concurrency | planning_v2_concurrency.sh covers three races: simultaneous first open (6 categories, both sessions succeed); disjoint ticks (both persist); same-block save (exactly one `stale_version`). A mutant with the seed lock removed was caught ("partner A's first open errored"). Runs: 3/3 PASS, plus 3/3 during Task 5. |
| 1.1 / 2.18 Idempotency | Client UUIDs plus version checks. The `op_replay` contract shows a replayed tick op is a no-op. The outbox test "replay is idempotent" shows every retry reuses its op id. |
| 1.10 Compensations | Template copy, duplicate, reset and category delete each run as a single transaction. |
| 2.1 Input validation | `planning_v2_validate_block`, `planning_v2_validate_item` and `planning_validate_delta`; helpers contracts 7–12 (embeds, unknown/hex attributes, `javascript:` links and forbidden list types rejected; characters counted, not bytes). |
| 2.2 No dynamic SQL | `grep -rn "EXECUTE format" supabase/migrations/202610122*` returns no hits. |
| 2.4 / 5.5 No leakage | `not_found` is returned for forbidden rows. A test asserts that no `planningV2ErrorMessage` contains `planning:` or underscores. |
| 2.5 / 2.14 Limits | `planning_limits()` is mirrored in Dart; the limits test parses the migration literal. Contracts cover the category, block and item limits. The outbox is capped at 200 (tested). |
| 2.19 No float money | The grep for `double` and `/ 100` / `* 100` in `lib/features/planning/v2` has one hit: `width: double.infinity` (layout, not money). P1 stores no money. |
| 3.1 Pagination | `list_planning_entries` uses keyset pagination; entry contracts 6 (35 entries → 30 + 5, limit clamped to 100). |
| 3.3 Indexes | `idx_planning_*` in 20261012200000. |
| 3.9 / 3.10 Retry | PlanningOutbox: 6 attempts, 500ms base, 30s cap, full jitter (bounds tested). Permanent errors are dropped and never retried (tested). |
| 5.1 Actionable errors | `planningV2ErrorMessage`, shown through the app's `ErrorStateWidget`. |
| 5.6 Accessibility | `androidTapTargetGuideline` passes on the home and entry screens. Tick, assignee and the new dot each have their own semantics node. Blocks can be reordered without dragging (Move up/down menu). Text at 200% scale renders without overflow (tested). |
| 6.4 Negative tests | A permanent tick failure reverts the tick and queues nothing. A template is never listed as an entry. An edited template is never overwritten by an upgrade. A failed save keeps the draft. |
| 6.5 Property tests | Sort-key property over 1000 random insertions (helpers Contract 4). |
| 6.7 Coverage | **Line** coverage (`flutter test --coverage`), not branch coverage: `domain/` 99.0% (102/103; the uncovered line is a private constructor), `data/` 85.7%, `presentation/` 78.3%, v2 overall 81.3%. Branch coverage was not measured. |
| 6.8 Mutation | 5 mutants caught: actor check, version check, seed lock, corrupt-storage guard, and (pre-execution) the concurrency exit-code check. |
| 7.1 Dependency scan | `gh api /advisories?ecosystem=pub&affects=flutter_quill` returned 0 advisories (flutter_quill 11.5.0). |
| 7.4 Least privilege | No table grants: schema Contract 11 runs under the real harness grant order (`scripts/local_pg_grants.sql` re-applies `20261012200010` and `20261012200210`). |
| 8.1 Rollback | P1 is additive and unreachable without `--dart-define=PLANNING_V2_PREVIEW=true`. Rollback means not shipping the define. |

Regression evidence: the full Flutter suite passes (2328 tests; baseline 2243). `flutter analyze` reports 0 errors. The SQL harness applies 289 migrations with 0 failures; 67 contract files pass and 1 fails (the pre-existing `settings_accessor_test.sql`, which needs a local Vault). The v1 Planning contracts and `ai_assist_planning_conversion_contracts.sql` pass.

Out of scope for P1, owned by later sub-projects: 2.22 audit log (P3), link-preview SSRF (P3), notifications (P4), storage bucket (P3).
Partial across the repo: 4.6–4.10 metrics/alerting and 6.10–6.12 soak/load/chaos (the repo has no infrastructure for them).

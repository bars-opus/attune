# SDD ledger — plan: docs/superpowers/plans/2026-10-12-planning-p2-replace-v1.md

Spec: §16 (user-approved 2026-10-12: no data copy, no shim, delete v1, no v2 naming). Executor: inline. User constraint: must not affect the chat system beyond the Planning card and Add-to-Planning.
Task 1: complete (4bea127c; tests: full SQL harness 292 migrations, 65 PASS / 1 pre-existing FAIL settings_accessor; concurrency PASS; chat_system + message_edit_delete + all ai_assist contracts PASS)
Task 1: Ruling: added 20261012200710_planning_change_signals_grants.sql — the v1 grants file also re-applied planning_change_signals' SELECT-only grant; unregistering it would have left the harness granting writes — cost if wrong: none
Task 2/3-6: Ruling: execute consumer rewiring (Tasks 3-6) before deleting v1 + renaming (Task 2) — keeps every commit compiling — cost if wrong: none
Task 4: complete (93f5ca34; tests: flutter test test/features/timeline test/features/planning/v2 -> 168 pass)
Task 5: complete (30f54c40; tests: planning_v2_ui_test + chat planning_entry_row_wiring_test pass)
Task 6: complete (5eac19ed; tests: flutter test test/features/ai_assistant -> 420 pass)
Task 2+3: complete (501b8d1a; tests: flutter test full suite 2316 pass, analyze 0 errors, no v1/V2 leftovers in Dart)
Final review (opus): 0 Critical, 0 Important. Migration replayed against real v1 data incl. link rows; chat impact additive only.
Final: fixed minor 1 (re-graded: user-visible dead end) — conversion Contract 8 RED (returned deleted plan; then link outlived plan) -> GREEN; link-cleanup trigger + liveness check. Note: Undo of a plan delete does not restore its link (the reply offers Add again).
Final: minor (deferred): 2 AI-created plans are USD (invisible until money blocks exist)
Final: minor (deferred): 3 ensure_starters locks templates before the Everyday category (only partner is pinning a template, which the UI cannot do)
Final: minor (deferred): 4 summary 'recent' can show a done/archived plan (spec silent)
Final: minor (deferred): 5 lib/architecture/PLANNING.md still describes v1; ai_session_sheet.dart:227 comment cites a deleted file
Final: action for user: 6 back up the four v1 tables + ai_assist_planning_links before db push (irreversible)

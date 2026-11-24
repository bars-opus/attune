# Spec 3 W3 (Forum removal: drop the retired forum schema) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Summary (one paragraph).** W3 is **one batch, three tasks** and six migrations, plus one Dart tidy-up and four doc edits. **Task 1** → `20261125100000_forum_drop_views.sql` (a preflight that stops the push before anything is dropped unless the database is the one W3 was built on, then the two forum views), `…100010_forum_drop_functions.sql` (the 29 forum-only functions) and `…100020_forum_drop_tables.sql` (forum rows in kept tables, the three foreign keys into the forum tables, the forum push index, the 8 tables), proven by a **rehearsal** on a pre-W3 snapshot that holds forum data, rolled back every time. **Task 2** → `…100030_forum_kept_table_columns.sql` (`get_post_poll` and `create_poll_for_post` without topics, in the same transaction that drops `post_polls.topic_id` and the forum columns of `forum_reports`), `…100040_forum_shared_function_branches.sql` (`assert_can_post`, `admin_confirm_content_removal` and Spec 1 W9d's `opinion_stamp_backfill` without their forum branches) and `…100050_forum_retirement_health_v2.sql` (two more health checks), with contract section F and the two contracts that pinned the forum schema. **Task 3**: `PollRepository.getPollIdsForTopics` goes, the architecture test loses its last allowance, `FORUM.md` and the design spec get their W3 lines, every mutant again and the W3 gate. No feature flag, no grants twin, no edge function, no new app string. Opinions behaves exactly as before.

**Replayed.** Every task below was built in a scratch copy of the repo at `9bac1bdb` (`git archive`) on a clone of `attune_spec3a`, then replayed from this text on a fresh copy and a fresh clone (Replay record, end of plan).

**Goal:** Drop the forum schema cleanly (Spec 3 §1 Goal, §6.3): no forum table, view, function, column, index, cron or push left, no dangling reference in SQL, crons or app code, and Opinions (polls for guests and voters, tags, reports, the ban ladder and its two notices, notifications, the console's Opinions queue) unchanged; and refuse to run at all on a database that differs from the one this was built on.

**Architecture:** Six idempotent migrations in the spec's order, each its own `BEGIN; … COMMIT;` with `SET LOCAL lock_timeout = '5s'`, every DROP `RESTRICT`. Migration 1's preflight turns the spec's owner checklist steps 3 and 4 (the inventory and the body check) into code: an unknown forum function, a shared body that is not the one W3 was built from (md5 of `prosrc`, before or after), any dependency on a forum relation other than the three expected foreign keys, or W2 not holding stops the push before anything is dropped. Every re-created function is its LIVE body with only lines marked `-- Spec 3 W3` changed (`marked_diff.py`), `SET search_path = ''`. Data cleaning is proven where contracts can't see it: `rehearse.py` seeds every forum table on a pre-W3 snapshot, applies the migrations inside one transaction, checks every forum row is gone and every Opinions row stays, and rolls back.

**Tech Stack:** Supabase Postgres 17 (RLS, `SECURITY DEFINER`, pg_cron), psql, Python 3 (the rehearsal, edit and mutation scripts), Flutter 3.29.1 / Dart 3.7 (one repository file and one architecture test). No new package.

**Spec:** `docs/superpowers/specs/2026-10-24-forum-removal-design.md` — §6.3 (W3: gate, three tasks, coordination with Spec 1 W9, the six migrations, "Also in W3", rollback, owner checklist); §2 V3, V6, V7, V8, V11; §3.5 (the `security_lockdown_contracts.sql` row), §3.9 (database objects, shared functions, kept-table columns), §3.10, §4 (keep list), §7.1, §7.3 (section F, "Also re-run in W3"), §7.4 (W3 addition), §8 R8, R9, R13–R17, R19, R22, §9 (the `FORUM.md`, shared-function and migrations rows), §10 D7, D8, D10. Format reference: `docs/superpowers/plans/2026-11-22-spec2-w8-device.md`. Earlier waves: `docs/superpowers/plans/2026-10-25-spec3-forum-removal-w1-w2.md` (W1, W2; its D-1 and D-2). Since the spec was written: Spec 1 W9b (`20261104120000`, the two moderation notices and the OPN-BAN-42702 fix), W9d (`20261107100000`, `opinion_stamp_backfill`, the latest `admin_confirm_content_removal` and `prepare_account_deletion` bodies), Spec 2 W7b (`20261121110000`, `moderation_opinions_remove`), W8 (`dating_v2_device_contracts.sql` §A's exemption), W9 (`20261123100000`, the latest `prepare_account_deletion`), W10 (`20261124100000/100010`, the newest migrations).

## Global Constraints

- **Where and how.** Work in the main working tree on `main` (`/Users/user/attune`). HEAD is `9bac1bdb` (Spec 2 W1–W10 committed). The owner may have uncommitted edits (`supabase/.temp/cli-latest`, `backup-before-planning-p2.sql`): never revert, stash, stage, checkout, reformat or read them into anything. Every edit to an existing file is an exact replacement made by a script that asserts each anchor occurs once (`$D/anchor.py`). If an anchor moved because the live code changed after this plan was written, make the same change to the current text and say so in the task report (live code is the truth).
- **NO commits.** No `git add`, `git commit`, `git stash`, `git checkout`, `git reset`, `git rm` (delete files with `rm`). Where a skill says "commit", instead: **do not commit; record the tree in the report** with `T=$(mktemp -u); GIT_INDEX_FILE=$T git read-tree HEAD && GIT_INDEX_FILE=$T git add -A && GIT_INDEX_FILE=$T git write-tree; rm -f $T` (a private index; the real index is untouched). The controller commits after the batch's final review, **on a branch, not `main`** (Owner question 1: any `supabase db push` from `main` after W3 lands applies the drop).
- **Formatting.** Never `dart format` a pre-existing file (the repo uses an older formatter). W3 creates no Dart file; its two Dart edits are anchor scripts already in the files' style.
- **SQL target.** Contracts run on `attune_spec3a`, from the repo root. A file with a top-level `BEGIN;` runs as `psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f F`; one without runs wrapped (`suite.sh` does both). Confirm the target first (`psql -X -d attune_spec3a -Atc 'select current_database()'` prints `attune_spec3a`). **NEVER `attune_test`. NEVER run `scripts/local_pg_setup.sh` or `scripts/local_pg_grants.sql`** (W3 has no grants twin; Task 2 fix round 1 edits `local_pg_grants.sql`, never runs it: see the table below). W3 is irreversible: Task 1 Step 1 takes the pre-W3 snapshot `attune_spec3a_w3pre` (`createdb -T`, only if absent) **before** anything is applied; the six migrations are applied to `attune_spec3a` only in Task 2 Step 5, all six together. The rehearsal and every SQL mutant run on the snapshot inside a transaction that is rolled back (it never changes); the snapshot is kept until the owner commits the wave, then dropped (Owner checklist 9). Every negative assertion checks the specific error (its SQLSTATE class and message or constraint), never `WHEN OTHERS`.
- **Migrations.** `20261125100000_forum_drop_views.sql`, `…100010_forum_drop_functions.sql`, `…100020_forum_drop_tables.sql`, `…100030_forum_kept_table_columns.sql`, `…100040_forum_shared_function_branches.sql`, `…100050_forum_retirement_health_v2.sql`: later than every file in `supabase/migrations/` (the newest is `20261124100010_dating_v2_launch_guards_grants.sql`), strictly increasing in the spec's order (House rules, R19). If `ls supabase/migrations | sort | tail -1` shows anything at or after `20261125100000` when Task 1 starts, shift all six to the next free hour keeping their order, and change every name in `combine.py`, the headers and the commands. Each is idempotent (applied twice, `exit=0` both times), its own `BEGIN; … COMMIT;` with `SET LOCAL lock_timeout = '5s'`; no `CREATE INDEX CONCURRENTLY`; every DROP is `RESTRICT`. Re-created functions start from their LIVE body (saved to `$D/before_w3/`) with only lines marked `-- Spec 3 W3` changed, `SECURITY DEFINER SET search_path = ''`, and their grants re-asserted as they are. **Migration 1's after-md5s are the md5 of the `prosrc` migrations 4 and 5 write:** if any body in 4 or 5 changes, recompute them (Task 2 Step 6 checks).
- **Opinions stays exactly as it is** (Spec 3 binding decision; owner rule). Kept, unrenamed: `forum_reports` (its opinion and comment columns, dedup indexes, RLS, grants), `private.enqueue_forum_notification` (signature unchanged), `private.assert_can_post`, `public.admin_confirm_content_removal`, `private.opinion_stamp_backfill`, `post_polls` / `poll_options` / `poll_votes` and every poll RPC, **`public.get_post_poll(uuid, uuid)` with its anon grant** (V3), tags, `forum_content_removed` / `forum_posting_banned`. Only forum branches, columns and objects go. Spec 1 W9b's notices and the W9d stamp are unchanged (V8, R16).
- **Off limits.** Games (`test/architecture/games_untouched_test.dart` stays green), every Opinions file but `lib/core/polls/data/repositories/poll_repository.dart` (spec §6.3: `poll_providers.dart` is not touched), `ATTUNE_SOUL.md`, `ATTUNE_THESIS.md`, `lib/home/home_screen.dart` and its latch (`shasum -c .superpowers/sdd/2026-11-07-spec2-w3/latch.sha`), `lib/main.dart`, `lib/app/**`, every applied migration, every edge function (the dispatcher's `forum_post_id` / `topic_id` allowlist keys stay, §1 non-goals), `dating_v2_device_contracts.sql` (its exemption names two kept functions: unchanged, re-run), `backup-before-planning-p2.sql`, `supabase/.temp`. **No deploys** (`supabase db push`, app builds are the owner's; Owner checklist). No `.env*`, credentials or keychain. Opus for every implementer and reviewer.
- **Fixture ids.** Contract F's people are `9f3a0000-0000-0000-0000-0000000000f1`–`f3` with phones `+15550940011`–`13`; the rehearsal's `…00d1`–`d2` with `+15550940021`–`22` (the W2 contract's `9f3a0000-` prefix and `+1555094xxxx` range, spec §7.1; swept: no other file uses them).
- **Gates (Task 3; `$D/gate.sh`).** (1) The wrapped SQL suite on `attune_spec3a`: no new FAIL against `$D/sql-baseline.txt` (baseline **165 PASS / 14 FAIL** by day; `quiet_hours_contracts.sql` reads the real clock and fails 22:00–08:00 UTC, **164 / 15**); W3 adds no SQL file, so the count stays. (2) `forum_retirement_contracts.sql`, `opinion_moderation_notice_contracts.sql`, `opinion_enforcement_records_contracts.sql`, `dating_v2_device_contracts.sql`, `dating_rls_canary.sql`: `all held`. (3) `forum_retirement_health()` on `attune_spec3a`: **7 of 7 ok**; the snapshot still pre-W3 (`true, 5 health rows`); the rehearsal `REHEARSAL all held`. (4) The Deno CI line (`.github/workflows/tests.yml` job `deno-w9`, frozen lock): **285** passed, and its `deno check` line clean (W3 touches no edge function). (5) `flutter analyze --no-pub lib test`: **571 issues, 0 new**. (6) `shasum -c` of the W10 and W9 sha lists: every line `OK`; the latch `OK`; the Games guard passes. (7) The feature flags: **46 rows, 6 on** (unchanged). (8) `scripts/concurrency/dating_kill_switch_races.sh` on an **idle** scratch database (load under about 4; wait, or note the load) built from `pg_dump -s attune_spec3a` plus the config tables' data, dropped after: **62 PASS, 0 FAIL**. (9) Full `flutter test`: no failure beyond the known three (`healing_journal_large_text` goldens) and the known flakes (`chat_controller_test:259`, `chat_screen_list_anchor` D<0, `reflection_journal` at a date boundary, `planning_recent`, `story_outbox_notices_test`, `chat_upload_progress_cancel_test`, `story_review_test`; re-run a failing file alone before calling it a flake); **+9728 −3** at `9bac1bdb` plus W3 (the replay's; W3 adds and removes no test, so it is HEAD's count; the `+9726` in the W9/W10 notes was measured on an earlier tree). (10) Every named mutant RED (`CONTRACT VIOLATED` or `KILLED`), the RED line quoted in the report: SQL 21/21 (17 + Task 2 fix round 1's 4), rehearsal 23/23 (9 + Task 1 fix round 1's 14), Dart 2/2. A `mutant anchor missing`, a `COMPILE` or a migration that merely errors is a broken mutant to fix, never a kill.

## Review Focus

Five things a real person will meet that this wave must survive. Each is pinned to tests that fail if it regresses.

1. **Production is not quite the database W3 was built on** (a moderation function hand-edited in the SQL editor, a hand-made view or function on a forum table, the hand-registered `mark-quiet-forums` cron still there because W2's push was skipped). Expect: the push stops at migration 1 with a message naming the difference, before any view, function, row or table is dropped. Tests: Task 1 rehearsal refusals "a hand-edited shared body" (and one per checked body), "an unknown forum function", "an upper-case forum reference", "a forum function in another schema", "a view on a forum table", "a function on a forum row type", "a forum cron job still scheduled", "a hand-made cron job on a forum table", "the guest poll grant gone" (mutants `body_guard_off`, `body_row_*`, `inventory_off`, `inventory_case_sensitive`, `other_schemas_unscanned`, `dependency_check_off`, `rowtype_deps_off`, `w2_check_off`, `cron_scan_off`, `opinions_arm_off`).
2. **Production holds forum data** (topics with a poll and votes, posts with replies and likes, reports on a forum post and on a topic, a report naming an opinion and a forum post at once, forum pushes pending, sent and cancelled). Expect: every forum row and the topic poll's options and votes go; every opinion, comment, opinion poll (options, votes), tag, opinion report, comment report (the mixed one too) and Opinions push stays. An account whose unstamped Opinions strikes include a removed forum post (Spec 1 W9d) is stamped before `forum_posts` goes, and without the exclusion key the push stops at migration 1 (fix round 1, review I-1). Tests: Task 1 rehearsal "data" (mutants `forum_pushes_kept`, `opinion_notice_deleted`, `opinion_poll_deleted`, `opinion_reports_deleted`, `mixed_report_deleted`, `backfill_call_removed`) and refusal "strikes waiting for a removed forum post without the key" (`stamp_key_check_off`, `stamp_refusals_off`).
3. **A guest opens an opinion with a poll, from a new build or an old one that still asks for a topic's poll.** Expect: the guest sees the options with counts hidden, a voter sees counts, a topic id answers no rows (never an error), and nothing can create a topic poll. Tests: Task 2 contract F4, D (mutants `guest_polls_closed`, `topic_poll_allowed`, `poll_parent_optional`).
4. **A moderator confirms Opinions removals after the drop** (the console's Opinions queue or the SQL editor), and someone tries the old `forum_post` type. Expect: strikes 1, 2, 3, the 7-day ban, "Post removed" three times and "Posting paused" once, the ban gate for every kind; `forum_post` refused as an unknown type; a report with no opinion or comment refused. Tests: Task 2 contract F3, F5, `opinion_moderation_notice_contracts.sql`, `dating_v2_moderation_contracts.sql` (mutants `forum_post_branch_silent`, `removal_notice_lost`, `ban_notice_lost`, `topic_still_limited`, `report_target_unchecked`).
5. **The owner runs Spec 1 W9d's stamp backfill after the drop** (its body read `forum_posts` until W3), or anything else still names a forum table. Expect: it runs; the health check names any function, view or cron job that still names one. Tests: Task 2 contract F1, F6, `opinion_enforcement_records_contracts.sql` (mutants `backfill_reads_forum_posts`, `code_check_blind_functions`, `code_check_blind_views`, `code_check_blind_cron`).

## Pre-flight (read before Task 1)

`D=.superpowers/sdd/2026-11-24-spec3-w3` throughout. Task 1 Step 0 copies W10's tools from `.superpowers/sdd/2026-11-23-spec2-w10/`: `anchor.py`, `suite.sh`, `mirror.py`, `marked_diff.py`, `replay.py` (unchanged), `mutate.py` (`W3_DB`) and `dmut.py` (temporary folder prefix `w3dmut-`).

### Shared files and interfaces between tasks

| File or interface | Tasks | Rule |
|---|---|---|
| `supabase/migrations/20261125100000_forum_drop_views.sql` | 1 | its after-md5s are the `prosrc` of the five bodies migrations 4–5 write (Task 2); a change to one of those bodies means recomputing them (Task 2 Step 6) |
| `$D/w3_all.sql` (built by `combine.py`) | 1 (migrations 1–3), 2 (all six) | rebuilt after any migration edit; never hand-edited |
| `supabase/tests/forum_retirement_contracts.sql` | 2 (section F spliced above its last line) | sections A–E unchanged (spec §7.3: E re-runs unchanged) |
| `supabase/tests/opinion_moderation_notice_contracts.sql`, `security_lockdown_contracts.sql` | 2 | one pin each; nothing loosened |
| `lib/core/polls/data/repositories/poll_repository.dart`, `test/architecture/no_forum_references_test.dart` | 3 | shared Opinions code: only the dead method and the docs (flag: polls are the Opinions surface; the Dart mutants pin it) |
| `lib/architecture/FORUM.md`, `docs/superpowers/specs/2026-10-24-forum-removal-design.md` | 3 | two lines; four amendment notes |

### What changed since the spec was written (all accounted for)

| Item (grep of `supabase/migrations`, `supabase/tests`, `lib`, `scripts`, `.github` at `9bac1bdb`) | Where W3 handles it |
|---|---|
| `private.opinion_stamp_backfill()` (Spec 1 W9d, `20261107100000:157`) reads `public.forum_posts` in a `UNION ALL`; `opinion_enforcement_records_contracts.sql` calls it nine times, `dating_rls_canary.sql:192` pins its grants (no service role) | Ruling R-W3-2: migration 5 re-creates it without that branch; F6; mutant `backfill_reads_forum_posts` |
| `admin_confirm_content_removal`'s live body is W9d's (`20261107100000:342`, with W9b's notices and the OPN-BAN-42702 fix); `moderation_opinions_remove` (W7b) calls it but refuses any type but `opinion` / `comment` itself | migration 5 from that live body; F5 now runs strike 3 (W1–W2 plan D-2 is fixed); `dating_v2_moderation_contracts.sql:1923` (`forum_post` → `invalid`) unchanged and re-run |
| `opinion_moderation_notice_contracts.sql:214` pins "the kept forum branch": `forum_post` returns `violation_count 0` | Task 2 edits that one pin to "`forum_post` raises `invalid_content_type`" (spec §3.9 makes the branch go) |
| `dating_v2_device_contracts.sql` §A exempts the walk `moderation_opinions_remove` → `enqueue_forum_notification` | **No edit** (Ruling R-W3-5): both functions are kept with their names, the walk still goes through `admin_confirm_content_removal`, and the build checked the exemption is still needed (without it the contract fails "a Dating push is not neutral"); re-run in the gate |
| `security_lockdown_contracts.sql:17` names `public.forum_topic_tags` | Task 2 (spec §3.5) |
| `scripts/local_pg_grants.sql:164` `\i`s the applied `20261017195000_security_lockdown.sql`, whose line 16 revokes on `public.forum_topic_tags` (the first scan missed this transitive include; Task 2 review I-1): after W3 the local from-zero harness stops there (`ON_ERROR_STOP`) and skips every later grant | Task 2 fix round 1: the `\i` becomes an inline copy of that migration's statements without `public.forum_topic_tags` (marked `-- Spec 3 W3`; the applied migration is not edited); proven on a post-W3 clone with psql, never by running the script. CI (`supabase start`) applies migrations only and is unaffected |
| `prepare_account_deletion` (latest in `20261123100000`), the export functions, `build-data-exports`, `service_role_grants_test.sql`, `dating_rls_canary.sql`, `scripts/local_pg_setup.sh`, `scripts/run_sql_contracts.sh`, `.github/workflows/tests.yml` | none name a forum relation, column or function (scanned): **no edit**; `account_deletion_contracts.sql`, `data_export_contracts.sql`, the canary and `service_role_grants_test.sql` (one table fewer to check) re-run in the suite |
| `public.forum_retirement_health()` names the forum relations in its own body | Ruling R-W3-4: migration 6's code scan leaves it out |
| The production inventory (spec owner checklist step 3) now lists 36 functions: the 32, `opinion_stamp_backfill`, `forum_retirement_health`, and (by `topic_id`) `get_post_poll` and `create_poll_for_post` | migration 1's preflight (a) |

### Rulings (the spec wins over this plan; each records its cost if wrong)

- **Ruling R-W3-1 ⚑ (the preflight).** Migration 1 checks, before it drops anything: (a) every function named for forums or topics, or whose body names a forum relation, `topic_id` or `forum_post_id`, is one of the 36 W3 knows; (a) is case-blind (unquoted names fold to lower case), and also: no function in another schema (but system schemas and extension members) names a forum relation in its body; (b) the five re-created bodies are the ones W3 was built from (md5 of `prosrc`) or already W3's, and the kept `private.enqueue_forum_notification` has its own (fix round 1, review I-2); (c) nothing outside the 10 forum relations depends on them or their row and array types but the three foreign keys and the 29 functions migration 2 drops, and nothing but those 29 depends on the 29 (final review M-5); (d) `forum_retirement_health()`'s cron and Opinions checks hold, and no cron job's command names a forum relation or one of the 29; (e) no account with a removed forum post holds strikes or a live ban no stamp covers while `dating_exclusion_key` is missing (migration 3 then runs `private.opinion_stamp_backfill()` before `forum_posts` goes; review I-1). It automates the spec's owner checklist steps 3–4, and because migration 1 is the first file, a refusal leaves production untouched. Cost if wrong: a refusal on a harmless difference; the owner re-plans migrations 4–5 from the live body (Owner checklist 5).
- **Ruling R-W3-2 (the stamp backfill).** `private.opinion_stamp_backfill()` (written after the spec) loses its `forum_posts` branch in migration 5. With no forum post left the branch reads nothing, but removed forum posts also drop out of its count (`v_removed`): an account whose strikes include forum-post removals and that W9d's apply-time backfill did not stamp is now skipped as unverified (fails closed: "not shown"; Owner checklist 2, the keys before the push). Cost if wrong: such an account's strikes are never carried into Dating (the function would fail at its next run otherwise).
- **Ruling R-W3-3 (where W3 is applied locally).** Tasks 1–2 prove the migrations on the pre-W3 snapshot inside rolled-back transactions; `attune_spec3a` gets all six together in Task 2 Step 5, never a half state other agents could meet. Cost if wrong: none.
- **Ruling R-W3-4 (the health check's own body).** `no_code_references_forum_schema` scans every function in `public` and `private` but `forum_retirement_health()` itself, which names the relations to look for them; `forum_schema_dropped` also checks `idx_scheduled_notifications_forum_activity`. Cost if wrong: none.
- **Ruling R-W3-5 (the W8 push audit).** `dating_v2_device_contracts.sql` is not edited: its exemption (`moderation_opinions_remove` → `enqueue_forum_notification`) names two functions W3 keeps, and stays needed. Cost if wrong: one line.
- **Ruling R-W3-6 (search_path).** `assert_can_post`, `create_poll_for_post` and `get_post_poll` move from `search_path 'public', 'private'` to `''` (spec House rules, R17); every relation in them was already qualified, built-ins resolve in `pg_catalog`. Cost if wrong: none (F exercises every branch).
- **Ruling R-W3-7 (contract E).** Section E stays byte for byte (spec §7.3: "re-runs unchanged"), its strike-2 stop and its comment about 42702 included; F runs the whole ladder. Cost if wrong: one comment.

## File map

**Task 1** creates `$D/{anchor.py, suite.sh, mirror.py, marked_diff.py, replay.py, mutate.py, dmut.py}` (copied), `$D/{sql-baseline.txt, analyze-baseline.txt, before_w3/, combine.py, rehearse.py, mut_reh.py, w3_all.sql}`, `supabase/migrations/20261125100000_forum_drop_views.sql`, `…100010_forum_drop_functions.sql`, `…100020_forum_drop_tables.sql`; the database `attune_spec3a_w3pre`. **Task 2** creates `$D/{contract_F.sql, edit_tests.py, mut_sql.py}`, `supabase/migrations/20261125100030_forum_kept_table_columns.sql`, `…100040_forum_shared_function_branches.sql`, `…100050_forum_retirement_health_v2.sql`; modifies `supabase/tests/forum_retirement_contracts.sql` (section F), `opinion_moderation_notice_contracts.sql`, `security_lockdown_contracts.sql`, and (fix round 1, review I-1) `scripts/local_pg_grants.sql`; applies the six to `attune_spec3a`. **Task 3** creates `$D/{edit_arch_test.py, edit_app.py, mut_dart.py, edit_docs.py, gate.sh}`; modifies `test/architecture/no_forum_references_test.dart`, `lib/core/polls/data/repositories/poll_repository.dart`, `lib/architecture/FORUM.md`, `docs/superpowers/specs/2026-10-24-forum-removal-design.md`.

**Not edited:** `lib/core/polls/presentation/providers/poll_providers.dart`, `poll_model.dart`, every other `lib/**` file, `supabase/functions/**` (the dispatcher allowlist included), `dating_v2_device_contracts.sql`, `dating_v2_moderation_contracts.sql`, `account_deletion_contracts.sql`, `data_export_contracts.sql`, `service_role_grants_test.sql`, `dating_rls_canary.sql`, `scripts/local_pg_setup.sh`, every applied migration, `ATTUNE_SOUL.md`, `ATTUNE_THESIS.md`.

---

## Batch W3 — drop the forum schema

### Task 1: The preflight, the views, the 29 functions and the 8 tables, proven on forum data (spec §6.3 migrations 1–3; V6, V11; R13, R14; R-W3-1, R-W3-3)

**Files:**
- Create: `$D/` tools (copied), `$D/{sql-baseline.txt, analyze-baseline.txt, before_w3/, combine.py, rehearse.py, mut_reh.py}`, `supabase/migrations/20261125100000_forum_drop_views.sql`, `supabase/migrations/20261125100010_forum_drop_functions.sql`, `supabase/migrations/20261125100020_forum_drop_tables.sql`
- Test: `$D/rehearse.py` (two data runs and eighteen refusals) on `attune_spec3a_w3pre`

**Interfaces:**
- Consumes: `public.forum_retirement_health()` (W2, five checks), the five live bodies (saved in Step 1), `cron.schedule` / `cron.unschedule` (the local stub supports both), `private.opinion_stamp_backfill()` (Spec 1 W9d, its pre-W3 body) and `public.dating_phone_hmac`.
- Produces: `$D/combine.py` → `$D/w3_all.sql` (the W3 migrations so far, BEGIN/COMMIT removed); `$D/rehearse.py <pre-db> [mutants.py [name …]]`; the snapshot `attune_spec3a_w3pre`; the preflight's refusal texts `unexpected forum function`, `is not the body this wave was built from`, `depend(s) on the forum schema`, `Spec 3 W2 does not hold`, `name the forum schema`, `wait for their Opinions stamps`.

- [ ] **Step 0: The tool folder**

```bash
D=.superpowers/sdd/2026-11-24-spec3-w3; W=.superpowers/sdd/2026-11-23-spec2-w10
mkdir -p $D && cp $W/{anchor.py,suite.sh,mirror.py,marked_diff.py,replay.py} $D/
sed 's/Spec 2 W10 mutation runner/Spec 3 W3 mutation runner/; s/W10_DB/W3_DB/g' $W/mutate.py > $D/mutate.py
sed "s/w10dmut-/w3dmut-/; s/Spec 2 W10 Dart mutation runner (W8's)/Spec 3 W3 Dart mutation runner (W10's)/" $W/dmut.py > $D/dmut.py
chmod +x $D/suite.sh
ls $D | tr '\n' ' '; echo; grep -c W3_DB $D/mutate.py
ls supabase/migrations | sort | tail -1
```

Expected: `anchor.py dmut.py marked_diff.py mirror.py mutate.py replay.py suite.sh`; `2`; `20261124100010_dating_v2_launch_guards_grants.sql`.

- [ ] **Step 1: The pre-W3 snapshot, the live bodies and the baselines (before anything of W3)**

```bash
D=.superpowers/sdd/2026-11-24-spec3-w3
psql -X -d attune_spec3a -Atc 'select current_database()'
psql -X -d attune_spec3a -Atc "select (to_regclass('public.forum_topics') is not null)::text || ', ' || count(*) || ' health rows' from public.forum_retirement_health()"
# The snapshot: only if absent (never re-made from a database W3 has touched).
psql -X -lqt | cut -d'|' -f1 | tr -d ' ' | grep -qx attune_spec3a_w3pre || createdb -T attune_spec3a attune_spec3a_w3pre
psql -X -d attune_spec3a_w3pre -Atc "select (to_regclass('public.forum_topics') is not null)::text || ', ' || count(*) || ' health rows' from public.forum_retirement_health()"
mkdir -p $D/before_w3
for s in 'private.assert_can_post(uuid,text)' 'public.admin_confirm_content_removal(text,uuid)' 'private.opinion_stamp_backfill()' 'private.create_poll_for_post(uuid,uuid,uuid,text[])' 'public.get_post_poll(uuid,uuid)'; do
  psql -X -d attune_spec3a_w3pre -Atc "select pg_get_functiondef('$s'::regprocedure)" > "$D/before_w3/$s.sql"
  psql -X -d attune_spec3a_w3pre -Atc "select '$s ' || md5(prosrc) from pg_proc where oid = '$s'::regprocedure"
done
bash $D/suite.sh attune_spec3a > $D/sql-baseline.txt; echo "SQL $(grep -c '^PASS' $D/sql-baseline.txt) PASS / $(grep -c '^FAIL' $D/sql-baseline.txt) FAIL"
flutter analyze --no-pub lib test > $D/analyze-baseline.txt 2>&1; tail -1 $D/analyze-baseline.txt | sed 's/ (ran in.*//'
psql -X -d attune_spec3a -Atc "select count(*) || ' rows, ' || count(*) filter (where enabled) || ' on' from public.feature_flags"
```

Expected: `attune_spec3a`; `true, 5 health rows` twice (if `createdb` says the source is being accessed by other users, wait for them and run the block again); the five md5s **exactly** as migration 1 holds them (if one differs, the live body moved: stop and rebuild that function in migration 4 or 5 from `$D/before_w3/`, then its two md5s in migration 1):

```text
private.assert_can_post(uuid,text) 920660396b7d4e331db2948838f98333
public.admin_confirm_content_removal(text,uuid) b50fef071e4ef2503f14b16376edb0ea
private.opinion_stamp_backfill() 118a2ca9d86ef932e0342867d616ef5c
private.create_poll_for_post(uuid,uuid,uuid,text[]) 6154f307c3afdb76c0249c2db2ec44f6
public.get_post_poll(uuid,uuid) dd3f4fc152767cd7b054c8324a46020e
```

then `SQL 165 PASS / 14 FAIL` by day (`164 PASS / 15 FAIL` between 22:00 and 08:00 UTC: `quiet_hours_contracts.sql`); `571 issues found.`; `46 rows, 6 on`.

- [ ] **Step 2: Write the rehearsal (the failing test)**

Create `.superpowers/sdd/2026-11-24-spec3-w3/combine.py` with exactly:

````python
#!/usr/bin/env python3
"""Spec 3 W3: w3_all.sql = the W3 migrations written so far (1-3 after Task
1, all six after Task 2), in order, each with its own BEGIN; and COMMIT;
removed (each must hold exactly one of each), so the rehearsal and the
mutants run them inside one transaction that is rolled back.
usage (repo root): combine.py"""
import pathlib, sys
D = pathlib.Path('.superpowers/sdd/2026-11-24-spec3-w3')
SIX = ['20261125100000_forum_drop_views.sql', '20261125100010_forum_drop_functions.sql',
       '20261125100020_forum_drop_tables.sql', '20261125100030_forum_kept_table_columns.sql',
       '20261125100040_forum_shared_function_branches.sql', '20261125100050_forum_retirement_health_v2.sql']
have = sorted(f.name for f in pathlib.Path('supabase/migrations').glob('20261125*.sql'))
if not have or have != SIX[:len(have)]:
    sys.exit(f'combine.py: the W3 migrations are not a prefix of the six: {have}')
out = []
for name in have:
    t = (pathlib.Path('supabase/migrations') / name).read_text()
    assert t.count('\nBEGIN;\n') == 1 and t.count('\nCOMMIT;\n') == 1, name
    out.append(f'-- ==== {name}\n' + t.replace('\nBEGIN;\n', '\n').replace('\nCOMMIT;\n', '\n'))
(D / 'w3_all.sql').write_text('\n'.join(out))
print(f'w3_all.sql: {len(have)} of 6 migrations')
````

Create `.superpowers/sdd/2026-11-24-spec3-w3/rehearse.py` with exactly:

````python
#!/usr/bin/env python3
"""Spec 3 W3 rehearsal (R13, R14): the six migrations (w3_all.sql, from
combine.py) on a PRE-W3 database, each run inside one transaction that is
rolled back, so the database never changes.
usage (repo root): rehearse.py <pre-W3 db> [<mutants.py> [name ...]]
  data:     every forum table holds rows (forum_posts also in the realtime
            publication), with a topic poll (options, a vote), an opinion
            poll (options, a vote), forum and Opinions reports and pushes,
            an account with 3 unstamped strikes (2 removed opinions, 1
            removed forum post) and a live ban, and one whose strike is
            stamped but whose live ban is not (its one removal a forum
            post), with the exclusion key set; after the migrations every
            forum row is gone, every Opinions row stays, and both accounts'
            strikes and bans are stamped.
  refusals: the preflight (migration 1) stops the whole run before anything
            is dropped when the database differs from the one W3 was built
            on: a hand-edited body (each of the six it checks), an unknown
            forum function (in public, in upper case, or in another schema),
            a view on a forum table, a function on a forum row type, a
            forum cron job still scheduled (W2's, or a hand-made one), the
            guest poll grant gone, strikes or a ban waiting for a removed
            forum post without the key, a view (or a policy on a forum
            table) calling one of the 29. A second data run holds only the
            ban-only account.
Without mutants: one line per part, then 'REHEARSAL all held' (exit 0) or
the failures (exit 1). With mutants.py (MUTS = {name: (old, new)} or
{name: ('MULTI', [(old, new), ...])}, each old occurring exactly once in
w3_all.sql): every part per mutant; KILLED when a part prints CONTRACT
VIOLATED, SURVIVED otherwise."""
import pathlib, re, runpy, subprocess, sys

D = pathlib.Path('.superpowers/sdd/2026-11-24-spec3-w3')
db = sys.argv[1]
ALL = (D / 'w3_all.sql').read_text()

SEED = r"""
INSERT INTO auth.users (id) VALUES
  ('9f3a0000-0000-0000-0000-0000000000d1'), ('9f3a0000-0000-0000-0000-0000000000d2')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.users (id, phone, display_name) VALUES
  ('9f3a0000-0000-0000-0000-0000000000d1', '+15550940021', 'Spec3 D1'),
  ('9f3a0000-0000-0000-0000-0000000000d2', '+15550940022', 'Spec3 D2')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.profiles (id) VALUES
  ('9f3a0000-0000-0000-0000-0000000000d1'), ('9f3a0000-0000-0000-0000-0000000000d2')
ON CONFLICT (id) DO NOTHING;
CREATE TEMP TABLE w3r (k text PRIMARY KEY, id uuid NOT NULL);
-- A forum table in the realtime publication (a dashboard toggle in a hosted
-- project) never blocks the drop: membership goes with the table.
ALTER PUBLICATION supabase_realtime ADD TABLE public.forum_posts;
DO $$
DECLARE
  v_a constant uuid := '9f3a0000-0000-0000-0000-0000000000d1';
  v_b constant uuid := '9f3a0000-0000-0000-0000-0000000000d2';
  v_topic uuid; v_post uuid; v_op uuid; v_com uuid; v_tag uuid;
  v_tpoll uuid; v_topt uuid; v_opoll uuid; v_oopt uuid; v_id uuid;
BEGIN
  INSERT INTO public.tags (slug) VALUES ('spec3-w3-rehearsal') RETURNING id INTO v_tag;
  INSERT INTO public.forum_topics (submitted_by, content, status) VALUES (v_a, 'Spec 3 W3 rehearsal topic', 'active')
    RETURNING id INTO v_topic;
  INSERT INTO public.forum_posts (topic_id, user_id, side, content) VALUES (v_topic, v_a, 'for', 'Rehearsal post')
    RETURNING id INTO v_post;
  INSERT INTO public.forum_posts (topic_id, user_id, side, content, reply_to_post_id)
    VALUES (v_topic, v_b, 'against', 'Rehearsal reply', v_post);
  INSERT INTO public.forum_post_likes (forum_post_id, user_id) VALUES (v_post, v_b);
  INSERT INTO public.topic_votes (topic_id, user_id, vote_type) VALUES (v_topic, v_b, 'up');
  INSERT INTO public.topic_impressions (topic_id, user_id) VALUES (v_topic, v_b);
  INSERT INTO public.user_forum_sides (user_id, topic_id, side) VALUES (v_b, v_topic, 'against');
  INSERT INTO public.forum_topic_visits (topic_id, user_id) VALUES (v_topic, v_b);
  INSERT INTO public.forum_topic_tags (topic_id, tag_id) VALUES (v_topic, v_tag);
  INSERT INTO public.opinions (user_id, content) VALUES (v_a, 'Rehearsal opinion') RETURNING id INTO v_op;
  INSERT INTO public.opinion_tags (opinion_id, tag_id) VALUES (v_op, v_tag);
  INSERT INTO public.opinion_comments (opinion_id, user_id, content) VALUES (v_op, v_b, 'Rehearsal comment')
    RETURNING id INTO v_com;
  -- A topic poll and an opinion poll, each with two options and one vote.
  INSERT INTO public.post_polls (topic_id, created_by) VALUES (v_topic, v_a) RETURNING id INTO v_tpoll;
  INSERT INTO public.poll_options (poll_id, option_position, label) VALUES (v_tpoll, 0, 'For') RETURNING id INTO v_topt;
  INSERT INTO public.poll_options (poll_id, option_position, label) VALUES (v_tpoll, 1, 'Against');
  INSERT INTO public.poll_votes (poll_id, option_id, user_id) VALUES (v_tpoll, v_topt, v_b);
  INSERT INTO public.post_polls (opinion_id, created_by) VALUES (v_op, v_a) RETURNING id INTO v_opoll;
  INSERT INTO public.poll_options (poll_id, option_position, label) VALUES (v_opoll, 0, 'Yes') RETURNING id INTO v_oopt;
  INSERT INTO public.poll_options (poll_id, option_position, label) VALUES (v_opoll, 1, 'No');
  INSERT INTO public.poll_votes (poll_id, option_id, user_id) VALUES (v_opoll, v_oopt, v_b);
  INSERT INTO w3r VALUES ('topic', v_topic), ('tag', v_tag), ('opinion', v_op), ('comment', v_com),
                         ('topic_poll', v_tpoll), ('opinion_poll', v_opoll);
  -- Reports: on a forum post, on a topic, on an opinion, on a comment, and
  -- one naming an opinion and a forum post at once.
  INSERT INTO public.forum_reports (reported_by, forum_post_id, reason) VALUES (v_b, v_post, 'Spam') RETURNING id INTO v_id;
  INSERT INTO w3r VALUES ('report_post', v_id);
  INSERT INTO public.forum_reports (reported_by, topic_id, reason) VALUES (v_b, v_topic, 'Spam') RETURNING id INTO v_id;
  INSERT INTO w3r VALUES ('report_topic', v_id);
  INSERT INTO public.forum_reports (reported_by, opinion_id, reason) VALUES (v_b, v_op, 'Spam') RETURNING id INTO v_id;
  INSERT INTO w3r VALUES ('report_opinion', v_id);
  INSERT INTO public.forum_reports (reported_by, comment_id, reason) VALUES (v_a, v_com, 'Spam') RETURNING id INTO v_id;
  INSERT INTO w3r VALUES ('report_comment', v_id);
  INSERT INTO public.forum_reports (reported_by, opinion_id, forum_post_id, reason) VALUES (v_a, v_op, v_post, 'Other')
    RETURNING id INTO v_id;
  INSERT INTO w3r VALUES ('report_mixed', v_id);
  -- Pushes: the three retired types (pending, sent, cancelled) and two
  -- Opinions ones that stay.
  INSERT INTO public.scheduled_notifications (user_id, notification_type, scheduled_for, status, metadata) VALUES
    (v_b, 'immediate', now(), 'pending', jsonb_build_object('type', 'forum_activity', 'title', 't', 'body', 'b', 'topic_id', v_topic::text)),
    (v_b, 'immediate', now(), 'sent', jsonb_build_object('type', 'forum_quiet', 'title', 't', 'body', 'b', 'topic_id', v_topic::text)),
    (v_b, 'immediate', now(), 'cancelled', jsonb_build_object('type', 'forum_topic_activated', 'title', 't', 'body', 'b'));
  INSERT INTO public.scheduled_notifications (user_id, notification_type, scheduled_for, status, metadata)
    VALUES (v_a, 'immediate', now(), 'pending', jsonb_build_object('type', 'opinion_liked', 'title', 't', 'body', 'b', 'opinion_id', v_op::text))
    RETURNING id INTO v_id;
  INSERT INTO w3r VALUES ('push_opinion', v_id);
  INSERT INTO public.scheduled_notifications (user_id, notification_type, scheduled_for, status, metadata)
    VALUES (v_a, 'immediate', now(), 'pending', jsonb_build_object('type', 'forum_content_removed', 'title', 'Post removed', 'body', 'b'))
    RETURNING id INTO v_id;
  INSERT INTO w3r VALUES ('push_removed', v_id);
END $$;
"""

# Spec 1 W9d: strikes only a removed forum post can stamp (fixture d3).
KEY = """SELECT set_config('app.settings.dating_exclusion_key', 'spec3-w3-rehearsal-exclusion-key', true);
"""
NO_KEY = """SELECT set_config('app.settings.dating_exclusion_key', '', true);
"""
STRIKER = r"""
INSERT INTO auth.users (id, phone, phone_confirmed_at, created_at)
VALUES ('9f3a0000-0000-0000-0000-0000000000d3', '15550940023', now() - interval '400 days', now() - interval '400 days')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.users (id, phone, display_name, created_at, updated_at)
VALUES ('9f3a0000-0000-0000-0000-0000000000d3', '15550940023', 'Spec3 D3', now() - interval '400 days', now() - interval '400 days')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.profiles (id) VALUES ('9f3a0000-0000-0000-0000-0000000000d3') ON CONFLICT (id) DO NOTHING;
DO $$
DECLARE
  v_c constant uuid := '9f3a0000-0000-0000-0000-0000000000d3';
  v_topic uuid;
BEGIN
  -- Three strikes placed before W9d (no stamp), a live ban; two of the
  -- removals are opinions, one is a forum post.
  UPDATE public.profiles SET confirmed_violation_count = 3, banned_until = now() + interval '7 days' WHERE id = v_c;
  DELETE FROM private.opinion_enforcement_stamps WHERE user_id = v_c;
  INSERT INTO public.opinions (user_id, content, removed_at) VALUES
    (v_c, 'Rehearsal removed opinion 1', now() - interval '10 days'),
    (v_c, 'Rehearsal removed opinion 2', now() - interval '5 days');
  INSERT INTO public.forum_topics (submitted_by, content, status) VALUES (v_c, 'Spec 3 W3 rehearsal striker topic', 'active')
    RETURNING id INTO v_topic;
  INSERT INTO public.forum_posts (topic_id, user_id, side, content, removed_at)
    VALUES (v_topic, v_c, 'for', 'Rehearsal removed forum post', now() - interval '20 days');
END $$;
"""

# A strike already stamped, a live ban not (fixture d4): the stamp row
# carries a placeholder hmac, so the seed needs no key.
BAN_ONLY = r"""
INSERT INTO auth.users (id, phone, phone_confirmed_at, created_at)
VALUES ('9f3a0000-0000-0000-0000-0000000000d4', '15550940024', now() - interval '400 days', now() - interval '400 days')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.users (id, phone, display_name, created_at, updated_at)
VALUES ('9f3a0000-0000-0000-0000-0000000000d4', '15550940024', 'Spec3 D4', now() - interval '400 days', now() - interval '400 days')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.profiles (id) VALUES ('9f3a0000-0000-0000-0000-0000000000d4') ON CONFLICT (id) DO NOTHING;
DO $$
DECLARE
  v_c constant uuid := '9f3a0000-0000-0000-0000-0000000000d4';
  v_topic uuid;
BEGIN
  UPDATE public.profiles SET confirmed_violation_count = 1, banned_until = now() + interval '7 days' WHERE id = v_c;
  DELETE FROM private.opinion_enforcement_stamps WHERE user_id = v_c;
  INSERT INTO private.opinion_enforcement_stamps (user_id, phone_hmac, strikes, ban_until)
    VALUES (v_c, repeat('d4', 32), 1, NULL);
  INSERT INTO public.forum_topics (submitted_by, content, status) VALUES (v_c, 'Spec 3 W3 rehearsal ban-only topic', 'active')
    RETURNING id INTO v_topic;
  INSERT INTO public.forum_posts (topic_id, user_id, side, content, removed_at)
    VALUES (v_topic, v_c, 'for', 'Rehearsal removed forum post (ban only)', now() - interval '3 days');
END $$;
"""

CHECK = r"""
DO $$
DECLARE
  v_bad text := '';
  v_n int;
  v_k text;
BEGIN
  SELECT count(*) INTO v_n FROM pg_class AS c JOIN pg_namespace AS n ON n.oid = c.relnamespace
   WHERE n.nspname = 'public' AND c.relname IN ('forum_topics', 'topic_votes', 'topic_impressions', 'forum_posts',
     'forum_post_likes', 'user_forum_sides', 'forum_topic_tags', 'forum_topic_visits', 'public_forum_topics', 'public_forum_posts');
  IF v_n <> 0 THEN v_bad := v_bad || format('; %s forum relation(s) left', v_n); END IF;
  -- The topic poll went with its options and votes.
  IF EXISTS (SELECT 1 FROM public.post_polls WHERE id = (SELECT id FROM w3r WHERE k = 'topic_poll'))
     OR EXISTS (SELECT 1 FROM public.poll_options WHERE poll_id = (SELECT id FROM w3r WHERE k = 'topic_poll'))
     OR EXISTS (SELECT 1 FROM public.poll_votes WHERE poll_id = (SELECT id FROM w3r WHERE k = 'topic_poll')) THEN
    v_bad := v_bad || '; the topic poll (or its options or votes) is left';
  END IF;
  -- The opinion poll stays whole.
  IF (SELECT count(*) FROM public.post_polls WHERE id = (SELECT id FROM w3r WHERE k = 'opinion_poll')
        AND opinion_id = (SELECT id FROM w3r WHERE k = 'opinion')) <> 1
     OR (SELECT count(*) FROM public.poll_options WHERE poll_id = (SELECT id FROM w3r WHERE k = 'opinion_poll')) <> 2
     OR (SELECT count(*) FROM public.poll_votes WHERE poll_id = (SELECT id FROM w3r WHERE k = 'opinion_poll')) <> 1 THEN
    v_bad := v_bad || '; the opinion poll lost its row, options or vote';
  END IF;
  -- Reports: forum-only ones gone, every Opinions one (the mixed one too) kept.
  FOREACH v_k IN ARRAY ARRAY['report_post', 'report_topic'] LOOP
    IF EXISTS (SELECT 1 FROM public.forum_reports WHERE id = (SELECT id FROM w3r WHERE k = v_k)) THEN
      v_bad := v_bad || format('; %s is left', v_k);
    END IF;
  END LOOP;
  FOREACH v_k IN ARRAY ARRAY['report_opinion', 'report_comment', 'report_mixed'] LOOP
    IF NOT EXISTS (SELECT 1 FROM public.forum_reports WHERE id = (SELECT id FROM w3r WHERE k = v_k)) THEN
      v_bad := v_bad || format('; %s was deleted', v_k);
    END IF;
  END LOOP;
  -- Pushes: no retired type in any status; the Opinions ones kept.
  SELECT count(*) INTO v_n FROM public.scheduled_notifications
   WHERE metadata->>'type' IN ('forum_topic_activated', 'forum_activity', 'forum_quiet');
  IF v_n <> 0 THEN v_bad := v_bad || format('; %s retired forum push(es) left', v_n); END IF;
  FOREACH v_k IN ARRAY ARRAY['push_opinion', 'push_removed'] LOOP
    IF NOT EXISTS (SELECT 1 FROM public.scheduled_notifications WHERE id = (SELECT id FROM w3r WHERE k = v_k)) THEN
      v_bad := v_bad || format('; %s was deleted', v_k);
    END IF;
  END LOOP;
  -- The Opinions content and the tag stay.
  IF NOT EXISTS (SELECT 1 FROM public.opinions WHERE id = (SELECT id FROM w3r WHERE k = 'opinion'))
     OR NOT EXISTS (SELECT 1 FROM public.opinion_comments WHERE id = (SELECT id FROM w3r WHERE k = 'comment'))
     OR NOT EXISTS (SELECT 1 FROM public.tags WHERE id = (SELECT id FROM w3r WHERE k = 'tag'))
     OR NOT EXISTS (SELECT 1 FROM public.opinion_tags WHERE opinion_id = (SELECT id FROM w3r WHERE k = 'opinion')) THEN
    v_bad := v_bad || '; an opinion, comment, tag or opinion tag was deleted';
  END IF;
  -- The striker's three strikes and live ban are stamped (the removed forum
  -- post counted before it went).
  IF (SELECT coalesce(sum(s.strikes), 0) FROM private.opinion_enforcement_stamps AS s
       WHERE s.user_id = '9f3a0000-0000-0000-0000-0000000000d3') <> 3
     OR NOT coalesce((SELECT max(s.ban_until) FROM private.opinion_enforcement_stamps AS s
                       WHERE s.user_id = '9f3a0000-0000-0000-0000-0000000000d3')
                     >= (SELECT p.banned_until FROM public.profiles AS p
                          WHERE p.id = '9f3a0000-0000-0000-0000-0000000000d3'), false) THEN
    v_bad := v_bad || '; the strikes from a removed forum post were never stamped';
  END IF;
  IF NOT coalesce((SELECT max(s.ban_until) FROM private.opinion_enforcement_stamps AS s
                    WHERE s.user_id = '9f3a0000-0000-0000-0000-0000000000d4')
                  >= (SELECT p.banned_until FROM public.profiles AS p
                       WHERE p.id = '9f3a0000-0000-0000-0000-0000000000d4'), false) THEN
    v_bad := v_bad || '; a live ban only a removed forum post could stamp was never stamped';
  END IF;
  IF v_bad <> '' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the drop with forum data%', v_bad;
  END IF;
  RAISE NOTICE 'REHEARSAL data: all held';
END $$;
"""

def hand_edit(sig):
    """A comment added at the end of a function's body (its md5 moves)."""
    return (f"DO $t$ BEGIN EXECUTE regexp_replace(pg_get_functiondef('{sig}'::regprocedure), "
            r"""'\$function\$\s*$', E'-- edited by hand\n$function$'); END $t$;""")


# The ban-only account alone, so nothing else sets the backfill off.
BAN_CHECK = r"""
DO $$
BEGIN
  IF NOT coalesce((SELECT max(s.ban_until) FROM private.opinion_enforcement_stamps AS s
                    WHERE s.user_id = '9f3a0000-0000-0000-0000-0000000000d4')
                  >= (SELECT p.banned_until FROM public.profiles AS p
                       WHERE p.id = '9f3a0000-0000-0000-0000-0000000000d4'), false) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the drop with forum data; a live ban only a removed forum post could stamp was never stamped';
  END IF;
  RAISE NOTICE 'REHEARSAL ban-only data: all held';
END $$;
"""

# (name, SQL run first, the preflight's refusal text)
REFUSALS = [
    ('a hand-edited shared body',
     """DO $t$ BEGIN EXECUTE replace(pg_get_functiondef('private.assert_can_post(uuid,text)'::regprocedure),
          '-- Ban gate', '-- Ban gate (edited by hand)'); END $t$;""",
     'is not the body this wave was built from'),
    ('an unknown forum function',
     """CREATE FUNCTION public.spec3_rehearsal_extra() RETURNS bigint LANGUAGE plpgsql
          AS $t$ BEGIN RETURN (SELECT count(*) FROM public.forum_topics); END $t$;""",
     'unexpected forum function'),
    ('a view on a forum table',
     """CREATE VIEW public.spec3_rehearsal_v AS SELECT id FROM public.forum_posts;""",
     'depend(s) on the forum schema'),
    ('a forum cron job still scheduled',
     """SELECT cron.schedule('mark-quiet-forums', '0 1 * * *', 'select 1');""",
     'Spec 3 W2 does not hold'),
] + [
    (f'a hand-edited {sig}', hand_edit(sig), 'is not the body this wave was built from')
    for sig in ['public.admin_confirm_content_removal(text,uuid)', 'private.opinion_stamp_backfill()',
                'private.create_poll_for_post(uuid,uuid,uuid,text[])', 'public.get_post_poll(uuid,uuid)',
                'private.enqueue_forum_notification(uuid,text,text,text,uuid,uuid,uuid)']
] + [
    ('an upper-case forum reference',
     """CREATE FUNCTION public.spec3_rehearsal_upper() RETURNS void LANGUAGE plpgsql
          AS $t$ BEGIN PERFORM 1 FROM PUBLIC.FORUM_TOPICS; END $t$;""",
     'unexpected forum function'),
    ('a forum function in another schema',
     """CREATE FUNCTION extensions.spec3_rehearsal_count() RETURNS bigint LANGUAGE sql
          AS $t$ SELECT count(*) FROM public.forum_posts $t$;""",
     'unexpected forum function'),
    ('a function on a forum row type',
     """CREATE FUNCTION public.spec3_rehearsal_row(p public.forum_posts) RETURNS integer LANGUAGE sql
          AS $t$ SELECT 1 $t$;""",
     'depend(s) on the forum schema'),
    ('a hand-made cron job on a forum table',
     """SELECT cron.schedule('prune-topic-impressions', '0 3 * * *', 'DELETE FROM public.topic_impressions');""",
     'name the forum schema'),
    ('the guest poll grant gone',
     """REVOKE EXECUTE ON FUNCTION public.get_post_poll(uuid, uuid) FROM anon;""",
     'Spec 3 W2 does not hold'),
    ('strikes waiting for a removed forum post without the key',
     NO_KEY + STRIKER,
     'wait for their Opinions stamps'),
    ('a live ban waiting for a removed forum post without the key',
     NO_KEY + BAN_ONLY,
     'wait for their Opinions stamps'),
    ('a view calling one of the 29',
     """CREATE VIEW public.spec3_rehearsal_fv AS SELECT * FROM public.get_forum_topic_tags(NULL::uuid);""",
     'depend(s) on the forum schema'),
    ('a policy on a forum table calling one of the 29',
     """CREATE POLICY spec3_rehearsal_p ON public.forum_topics FOR SELECT
          USING ((SELECT count(*) FROM public.get_forum_topic_tags(id)) >= 0);""",
     'depend(s) on the forum schema'),
]


def run(sql):
    r = subprocess.run(['psql', '-X', '-q', '-v', 'ON_ERROR_STOP=1', '-d', db],
                       input=sql, capture_output=True, text=True)
    lines = (r.stdout + r.stderr).splitlines()
    err = next((l for l in lines if 'ERROR' in l), None)
    return err, lines


def parts(all_sql):
    out = []
    err, lines = run('BEGIN;\n' + KEY + SEED + STRIKER + BAN_ONLY + all_sql + CHECK + 'ROLLBACK;\n')
    out.append('data: all held' if err is None and any('REHEARSAL data: all held' in l for l in lines)
               else f'data: {err or "no result"}')
    err, lines = run('BEGIN;\n' + KEY + BAN_ONLY + all_sql + BAN_CHECK + 'ROLLBACK;\n')
    out.append('data (ban only): all held' if err is None and any('REHEARSAL ban-only data: all held' in l for l in lines)
               else f'data (ban only): {err or "no result"}')
    for name, tamper, expect in REFUSALS:
        err, _ = run('BEGIN;\n' + tamper + '\n' + all_sql + '\nROLLBACK;\n')
        if err is None:
            out.append(f'refusal: CONTRACT VIOLATED: the preflight let {name} through')
        elif expect in err:
            out.append(f'refusal: refused {name}')
        else:
            out.append(f'refusal: CONTRACT VIOLATED: the preflight let {name} through (it failed later: {err[:120]})')
    return out


if len(sys.argv) == 2:
    res = parts(ALL)
    print('\n'.join(res))
    ok = (res[0] == 'data: all held' and res[1] == 'data (ban only): all held'
          and all(l.startswith('refusal: refused') for l in res[2:]))
    print('REHEARSAL all held' if ok else 'REHEARSAL FAILED')
    sys.exit(0 if ok else 1)

muts = runpy.run_path(sys.argv[2])['MUTS']
only = set(sys.argv[3:])
killed = 0
chosen = {n: m for n, m in muts.items() if not only or n in only}
for name, (a, b) in chosen.items():
    edits = b if a == 'MULTI' else [(a, b)]
    text = ALL
    for o, n in edits:
        assert text.count(o) == 1, (name, o[:60], text.count(o))
        text = text.replace(o, n)
    res = parts(text)
    hit = next((l for l in res if 'CONTRACT VIOLATED' in l), None)
    killed += hit is not None
    print(f'{name}: {"KILLED  " + hit[:160] if hit else "SURVIVED  " + " | ".join(res)[:160]}', flush=True)
print(f'{killed}/{len(chosen)} killed')
````

Create `.superpowers/sdd/2026-11-24-spec3-w3/mut_reh.py` with exactly:

````python
# Spec 3 W3 rehearsal mutants (rehearse.py on w3_all.sql, on the PRE-W3
# database). Each must print a CONTRACT VIOLATED line.
MUTS = {
    # Migration 3: which rows go.
    'forum_pushes_kept': ("""  DELETE FROM public.scheduled_notifications
   WHERE metadata->>'type' IN ('forum_topic_activated', 'forum_activity', 'forum_quiet');""",
                          """  DELETE FROM public.scheduled_notifications
   WHERE metadata->>'type' IN ('forum_topic_activated', 'forum_activity') AND status = 'pending';"""),
    'opinion_notice_deleted': ("""   WHERE metadata->>'type' IN ('forum_topic_activated', 'forum_activity', 'forum_quiet');""",
                               """   WHERE metadata->>'type' IN ('forum_topic_activated', 'forum_activity', 'forum_quiet', 'forum_content_removed');"""),
    'opinion_poll_deleted': ("""    EXECUTE 'DELETE FROM public.post_polls WHERE topic_id IS NOT NULL';""",
                             """    EXECUTE 'DELETE FROM public.post_polls WHERE topic_id IS NOT NULL OR opinion_id IS NOT NULL';"""),
    'opinion_reports_deleted': ("""  DELETE FROM public.forum_reports WHERE opinion_id IS NULL AND comment_id IS NULL;""",
                                """  DELETE FROM public.forum_reports WHERE opinion_id IS NULL OR comment_id IS NULL;"""),
    'mixed_report_deleted': ("""  DELETE FROM public.forum_reports WHERE opinion_id IS NULL AND comment_id IS NULL;""",
                             """  DELETE FROM public.forum_reports WHERE (opinion_id IS NULL AND comment_id IS NULL) OR forum_post_id IS NOT NULL;"""),
    # Migration 1: each preflight check.
    'body_guard_off': ("""    IF v_md5 <> r.before_md5 AND v_md5 <> r.after_md5 THEN""", """    IF false THEN"""),
    'inventory_off': ("""  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'forum_drop preflight: unexpected forum function(s) %""", """  IF false THEN
    RAISE EXCEPTION 'forum_drop preflight: unexpected forum function(s) %"""),
    'dependency_check_off': ("""  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'forum_drop preflight: % depend(s) on the forum schema""", """  IF false THEN
    RAISE EXCEPTION 'forum_drop preflight: % depend(s) on the forum schema"""),
    'w2_check_off': ("""   WHERE h.check_name IN ('forum_cron_unscheduled', 'opinions_shared_objects_present') AND NOT h.ok;""",
                     """   WHERE false;"""),
    # Fix round 1 (Task 1 review I-1, I-2, minors 1-3 and 6).
    'opinions_arm_off': ("""   WHERE h.check_name IN ('forum_cron_unscheduled', 'opinions_shared_objects_present') AND NOT h.ok;""",
                         """   WHERE h.check_name IN ('forum_cron_unscheduled') AND NOT h.ok;"""),
    'backfill_call_removed': ("""      v_n := private.opinion_stamp_backfill();""", """      v_n := 0;"""),
    'stamp_key_check_off': ("""    IF v_n > 0 AND public.dating_phone_hmac('attune:dating_exclusion_key:fingerprint:v1') IS NULL THEN""",
                            """    IF false THEN"""),
    'stamp_refusals_off': ('MULTI', [
        ("""    IF v_n > 0 AND public.dating_phone_hmac('attune:dating_exclusion_key:fingerprint:v1') IS NULL THEN""",
         """    IF false THEN"""),
        ("""      IF v_n < 0 THEN""", """      IF false THEN""")]),
    'cron_scan_off': ("""    IF v_bad IS NOT NULL THEN
      RAISE EXCEPTION 'forum_drop preflight: cron job(s)""", """    IF false THEN
      RAISE EXCEPTION 'forum_drop preflight: cron job(s)"""),
    'other_schemas_unscanned': ("""   WHERE n.nspname NOT IN ('public', 'private', 'pg_catalog', 'information_schema')""",
                                """   WHERE false AND n.nspname NOT IN ('public', 'private', 'pg_catalog', 'information_schema')"""),
    'rowtype_deps_off': ("""              OR (d.refclassid = 'pg_catalog.pg_type'::pg_catalog.regclass AND d.refobjid = ANY (v_types))""",
                         """              OR false"""),
    'inventory_case_sensitive': ("""          OR p.prosrc ~* '(forum_topics|""", """          OR p.prosrc ~ '(forum_topics|"""),
    # Final fix round (final review M-4, M-5).
    'ban_deficit_ignored': ("""                       -- a live ban no stamp covers (the backfill stamps it too)
                       OR (p.banned_until > now()""",
                            """                       -- a live ban no stamp covers (the backfill stamps it too)
                       OR (false"""),
    'ban_deficit_ignored_preflight': ("""            -- a live ban no stamp covers (the backfill stamps it too)
            OR (p.banned_until > now()""",
                                      """            -- a live ban no stamp covers (the backfill stamps it too)
            OR (false"""),
    'function_deps_off': ("""              OR (d.refclassid = 'pg_catalog.pg_proc'::pg_catalog.regclass AND d.refobjid = ANY (v_dropped_oids)))""",
                          """              OR false)"""),
    'function_deps_owner_exempt': ("""     AND (x.on_function OR x.owner_rel IS NULL OR x.owner_rel <> ALL (v_rels));""",
                                   """     AND (x.owner_rel IS NULL OR x.owner_rel <> ALL (v_rels));"""),
    # Each body the guard checks, left out of its list.
    'body_row_assert_can_post': ("""      ('private.assert_can_post(uuid,text)',
       '920660396b7d4e331db2948838f98333', '3cf33d5a02460a23c6ed90160eadaf8e'),
""", ''),
    'body_row_admin_confirm': ("""      ('public.admin_confirm_content_removal(text,uuid)',
       'b50fef071e4ef2503f14b16376edb0ea', '86567c9277f9f36ac2377437e986db0d'),
""", ''),
    'body_row_stamp_backfill': ("""      ('private.opinion_stamp_backfill()',
       '118a2ca9d86ef932e0342867d616ef5c', '936f500d8639e59da292ef061744d796'),
""", ''),
    'body_row_create_poll': ("""      ('private.create_poll_for_post(uuid,uuid,uuid,text[])',
       '6154f307c3afdb76c0249c2db2ec44f6', '332f6851a5edd7f409ed77fcf4a6a69a'),
""", ''),
    'body_row_get_post_poll': ("""      ('public.get_post_poll(uuid,uuid)',
       'dd3f4fc152767cd7b054c8324a46020e', 'b0f239e72b6a09681140d928b1a03cba'),
""", ''),
    'body_row_enqueue': ("""),
      ('private.enqueue_forum_notification(uuid,text,text,text,uuid,uuid,uuid)',
       '3d57c8b5ca75d1edbe87192d5af837e1', '3d57c8b5ca75d1edbe87192d5af837e1')
""", """)
"""),
}
````

- [ ] **Step 3: Run it to see it fail**

```bash
D=.superpowers/sdd/2026-11-24-spec3-w3
python3 -I $D/combine.py; echo "exit=$?"
```

Expected: `combine.py: the W3 migrations are not a prefix of the six: []`, `exit=1`.

- [ ] **Step 4: The three migrations**

Create `supabase/migrations/20261125100000_forum_drop_views.sql` with exactly:

````sql
-- Spec 3 (forum removal) W3, migration 1 of 6: the preflight, then the two
-- forum views. Spec 3 §6.3, §3.9; risks R13-R15. Nothing is dropped unless
-- every check below holds, so a production database that differs from the
-- one this wave was built on stops here, before any data or schema goes:
--   (a) Inventory: every function in public or private that is named for
--       forums or topics, or whose body names a forum relation, topic_id or
--       forum_post_id, is one of the 36 this wave knows (the 29 forum-only
--       functions migration 2 drops, the 3 shared ones migration 5 rewrites
--       or keeps, private.opinion_stamp_backfill (Spec 1 W9d, rewritten in
--       migration 5), the 2 poll functions migration 4 rewrites, and
--       forum_retirement_health (migration 6)); and no function in any other
--       schema (but the system ones and extension members) names a forum
--       relation in its body. Anything extra: stop.
--   (b) Bodies: the five functions this wave re-creates still have the
--       body it was built from (md5 of prosrc), or already the new one (a
--       re-run), and the kept private.enqueue_forum_notification (every
--       Opinions push goes through it; W3 does not re-create it) has its
--       own. Otherwise stop: rebuild migrations 4-5 from
--       pg_get_functiondef on that database (Spec 3 §6.3 "from the live
--       definition").
--   (c) Dependencies: nothing outside the 10 forum relations depends on
--       them or on their row and array types (a view, a policy, a trigger, a
--       key, a column, a function signature) except the three foreign keys
--       migration 3 drops (post_polls_topic_id_fkey,
--       forum_reports_forum_post_id_fkey, forum_reports_topic_id_fkey) and
--       the 29 functions migration 2 drops; and nothing but those 29
--       depends on the 29 functions themselves (a view, a default, a
--       trigger, even one on a forum table: migration 2 drops them first).
--       Everything is dropped RESTRICT anyway.
--   (d) W2 holds: public.forum_retirement_health() reports no forum cron and
--       every Opinions object present (gate (c)); the kept
--       private.enqueue_forum_notification keeps its signature; and no cron
--       job's command names a forum relation or one of the 29 functions
--       (W2's check knows only the crons it retired).
--   (e) Opinions stamps (Spec 1 W9d): an account whose strikes or live ban
--       no stamp covers yet, with a removed forum post, needs that post counted by
--       private.opinion_stamp_backfill() before forum_posts goes (migration
--       3 runs it). That needs dating_exclusion_key: without it, stop.
-- Then: DROP VIEW ... RESTRICT for public_forum_posts and public_forum_topics.
-- Idempotent: a re-run passes (a)-(e) on the dropped schema and drops nothing.
BEGIN;
SET LOCAL lock_timeout = '5s';

DO $$
DECLARE
  -- the 29 forum-only functions (migration 2)
  v_dropped constant text[] := ARRAY[
    'public.activate_pending_topics()',
    'public.expire_old_topics()',
    'public.mark_quiet_topics()',
    'public.notify_quiet_topic(uuid)',
    'private.queue_forum_activity_notifications(uuid,uuid)',
    'public.record_forum_topic_visit(uuid)',
    'public.create_forum_post(uuid,text,text,uuid,text)',
    'public.create_forum_topic(text)',
    'public.create_forum_topic_with_poll(text,text[])',
    'public.edit_forum_post(uuid,text)',
    'public.attach_forum_topic_tags(uuid,text[])',
    'public.get_forum_topic_tags(uuid)',
    'public.get_forum_topics_by_tag(text,integer,integer)',
    'public.get_tags_for_forum_topics(uuid[])',
    'public.get_polls_for_topics(uuid[])',
    'public.get_active_forums_filtered(text[])',
    'public.get_quiet_forums_filtered(text[])',
    'public.get_voting_topics_filtered(text[])',
    'public.increment_topic_upvote_count(uuid)',
    'public.decrement_topic_upvote_count(uuid)',
    'public.increment_topic_downvote_count(uuid)',
    'public.decrement_topic_downvote_count(uuid)',
    'public.increment_topic_post_count(uuid,text)',
    'public.decrement_topic_post_count(uuid,text)',
    'public.increment_topic_seen_count(uuid)',
    'public.increment_forum_post_like_count(uuid)',
    'public.decrement_forum_post_like_count(uuid)',
    'public.report_forum_post(uuid,text)',
    'public.report_forum_topic(uuid,text)'
  ];
  v_known constant text[] := v_dropped || ARRAY[
    -- shared, kept (migrations 4-6 rewrite all but the notification helper)
    'private.assert_can_post(uuid,text)',
    'public.admin_confirm_content_removal(text,uuid)',
    'private.enqueue_forum_notification(uuid,text,text,text,uuid,uuid,uuid)',
    'private.opinion_stamp_backfill()',
    'private.create_poll_for_post(uuid,uuid,uuid,text[])',
    'public.get_post_poll(uuid,uuid)',
    'public.forum_retirement_health()'
  ];
  v_forum_relations constant text[] := ARRAY[
    'public.forum_topics', 'public.topic_votes', 'public.topic_impressions',
    'public.forum_posts', 'public.forum_post_likes', 'public.user_forum_sides',
    'public.forum_topic_tags', 'public.forum_topic_visits',
    'public.public_forum_topics', 'public.public_forum_posts'
  ];
  v_bad text[];
  v_rels oid[];
  v_types oid[];
  v_dropped_oids oid[];
  r record;
  v_md5 text;
  v_n bigint;
BEGIN
  -- (a) The inventory. Case-blind (~*): unquoted names fold to lower case,
  -- so PUBLIC.FORUM_TOPICS in a body reads the same table.
  SELECT pg_catalog.array_agg(p.oid::pg_catalog.regprocedure::text ORDER BY p.oid::pg_catalog.regprocedure::text)
    INTO v_bad
    FROM pg_catalog.pg_proc AS p
    JOIN pg_catalog.pg_namespace AS n ON n.oid = p.pronamespace
   WHERE n.nspname IN ('public', 'private') AND p.prokind IN ('f', 'p')
     AND (p.proname ~* 'forum|topic'
          OR p.prosrc ~* '(forum_topics|forum_posts|topic_votes|topic_impressions|user_forum_sides|forum_post_likes|forum_topic_tags|forum_topic_visits|public_forum|\mtopic_id\M|\mforum_post_id\M)')
     AND p.oid <> ALL (ARRAY(SELECT pg_catalog.to_regprocedure(k) FROM pg_catalog.unnest(v_known) AS k
                              WHERE pg_catalog.to_regprocedure(k) IS NOT NULL));
  -- Any other schema: only a body that names a forum relation (Supabase's
  -- own realtime.topic() and its kin are named for realtime topics), never
  -- the system schemas, temporary ones or an extension's own functions.
  SELECT pg_catalog.array_cat(v_bad, pg_catalog.array_agg(p.oid::pg_catalog.regprocedure::text
                                                          ORDER BY p.oid::pg_catalog.regprocedure::text))
    INTO v_bad
    FROM pg_catalog.pg_proc AS p
    JOIN pg_catalog.pg_namespace AS n ON n.oid = p.pronamespace
   WHERE n.nspname NOT IN ('public', 'private', 'pg_catalog', 'information_schema')
     AND n.nspname !~ '^pg_(temp|toast)'
     AND p.prosrc ~* '(forum_topics|forum_posts|topic_votes|topic_impressions|user_forum_sides|forum_post_likes|forum_topic_tags|forum_topic_visits|public_forum)'
     AND NOT EXISTS (SELECT 1 FROM pg_catalog.pg_depend AS e
                      WHERE e.classid = 'pg_catalog.pg_proc'::pg_catalog.regclass
                        AND e.objid = p.oid AND e.deptype = 'e');
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'forum_drop preflight: unexpected forum function(s) %; add them to the drop or the rewrite first', v_bad;
  END IF;

  -- (b) The bodies this wave was built from (before) or wrote (after); the
  -- kept notification helper's is both.
  FOR r IN SELECT * FROM (VALUES
      ('private.assert_can_post(uuid,text)',
       '920660396b7d4e331db2948838f98333', '3cf33d5a02460a23c6ed90160eadaf8e'),
      ('public.admin_confirm_content_removal(text,uuid)',
       'b50fef071e4ef2503f14b16376edb0ea', '86567c9277f9f36ac2377437e986db0d'),
      ('private.opinion_stamp_backfill()',
       '118a2ca9d86ef932e0342867d616ef5c', '936f500d8639e59da292ef061744d796'),
      ('private.create_poll_for_post(uuid,uuid,uuid,text[])',
       '6154f307c3afdb76c0249c2db2ec44f6', '332f6851a5edd7f409ed77fcf4a6a69a'),
      ('public.get_post_poll(uuid,uuid)',
       'dd3f4fc152767cd7b054c8324a46020e', 'b0f239e72b6a09681140d928b1a03cba'),
      ('private.enqueue_forum_notification(uuid,text,text,text,uuid,uuid,uuid)',
       '3d57c8b5ca75d1edbe87192d5af837e1', '3d57c8b5ca75d1edbe87192d5af837e1')
    ) AS t(sig, before_md5, after_md5)
  LOOP
    SELECT pg_catalog.md5(p.prosrc) INTO v_md5
      FROM pg_catalog.pg_proc AS p WHERE p.oid = pg_catalog.to_regprocedure(r.sig);
    IF v_md5 IS NULL THEN
      RAISE EXCEPTION 'forum_drop preflight: % is missing', r.sig;
    END IF;
    IF v_md5 <> r.before_md5 AND v_md5 <> r.after_md5 THEN
      RAISE EXCEPTION 'forum_drop preflight: % is not the body this wave was built from (md5 %); rebuild migrations 4-5 from its live definition', r.sig, v_md5;
    END IF;
  END LOOP;

  -- (c) Nothing outside the forum relations depends on them or on their row
  -- and array types, but the three foreign keys migration 3 drops and the
  -- 29 functions migration 2 drops first; and nothing at all but those 29
  -- depends on the 29 (a view, a default, a trigger, a policy).
  v_rels := ARRAY(SELECT pg_catalog.to_regclass(x)::oid FROM pg_catalog.unnest(v_forum_relations) AS x
                   WHERE pg_catalog.to_regclass(x) IS NOT NULL);
  v_types := ARRAY(SELECT t.oid FROM pg_catalog.pg_type AS t WHERE t.typrelid = ANY (v_rels)
                   UNION ALL
                   SELECT t.typarray FROM pg_catalog.pg_type AS t
                    WHERE t.typrelid = ANY (v_rels) AND t.typarray <> 0);
  v_dropped_oids := ARRAY(SELECT pg_catalog.to_regprocedure(k)::oid FROM pg_catalog.unnest(v_dropped) AS k
                           WHERE pg_catalog.to_regprocedure(k) IS NOT NULL);
  SELECT pg_catalog.array_agg(DISTINCT x.what ORDER BY x.what) INTO v_bad
    FROM (
      SELECT CASE d.classid
               WHEN 'pg_catalog.pg_class'::pg_catalog.regclass THEN
                 (SELECT coalesce(i.indrelid, c.oid) FROM pg_catalog.pg_class AS c
                    LEFT JOIN pg_catalog.pg_index AS i ON i.indexrelid = c.oid WHERE c.oid = d.objid)
               WHEN 'pg_catalog.pg_constraint'::pg_catalog.regclass THEN
                 (SELECT c.conrelid FROM pg_catalog.pg_constraint AS c WHERE c.oid = d.objid)
               WHEN 'pg_catalog.pg_rewrite'::pg_catalog.regclass THEN
                 (SELECT w.ev_class FROM pg_catalog.pg_rewrite AS w WHERE w.oid = d.objid)
               WHEN 'pg_catalog.pg_trigger'::pg_catalog.regclass THEN
                 (SELECT t.tgrelid FROM pg_catalog.pg_trigger AS t WHERE t.oid = d.objid)
               WHEN 'pg_catalog.pg_policy'::pg_catalog.regclass THEN
                 (SELECT y.polrelid FROM pg_catalog.pg_policy AS y WHERE y.oid = d.objid)
               WHEN 'pg_catalog.pg_attrdef'::pg_catalog.regclass THEN
                 (SELECT a.adrelid FROM pg_catalog.pg_attrdef AS a WHERE a.oid = d.objid)
             END AS owner_rel,
             pg_catalog.pg_describe_object(d.classid, d.objid, d.objsubid) AS what,
             (d.classid = 'pg_catalog.pg_constraint'::pg_catalog.regclass
              AND (SELECT c.conname FROM pg_catalog.pg_constraint AS c WHERE c.oid = d.objid)
                  IN ('post_polls_topic_id_fkey', 'forum_reports_forum_post_id_fkey', 'forum_reports_topic_id_fkey')) AS expected_fk,
             (d.refclassid = 'pg_catalog.pg_proc'::pg_catalog.regclass) AS on_function
        FROM pg_catalog.pg_depend AS d
       WHERE ((d.refclassid = 'pg_catalog.pg_class'::pg_catalog.regclass AND d.refobjid = ANY (v_rels))
              OR (d.refclassid = 'pg_catalog.pg_type'::pg_catalog.regclass AND d.refobjid = ANY (v_types))
              -- Migration 2 drops the 29 before any forum table goes, so even
              -- a trigger on a forum table that calls one would stop it.
              OR (d.refclassid = 'pg_catalog.pg_proc'::pg_catalog.regclass AND d.refobjid = ANY (v_dropped_oids)))
         AND NOT (d.classid = 'pg_catalog.pg_proc'::pg_catalog.regclass AND d.objid = ANY (v_dropped_oids))
         -- Normal dependencies only: auto ones (indexes, the table's own
         -- constraints, owned sequences, realtime publication membership)
         -- go with the table and never block a RESTRICT drop.
         AND d.deptype = 'n'
    ) AS x
   WHERE NOT x.expected_fk
     AND (x.on_function OR x.owner_rel IS NULL OR x.owner_rel <> ALL (v_rels));
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'forum_drop preflight: % depend(s) on the forum schema; remove that dependency first', v_bad;
  END IF;

  -- (d) W2 holds, and the kept helper is where Opinions expects it.
  IF pg_catalog.to_regprocedure('public.forum_retirement_health()') IS NULL THEN
    RAISE EXCEPTION 'forum_drop preflight: Spec 3 W2 is not applied (no forum_retirement_health)';
  END IF;
  SELECT pg_catalog.array_agg(h.check_name || ': ' || h.detail) INTO v_bad
    FROM public.forum_retirement_health() AS h
   WHERE h.check_name IN ('forum_cron_unscheduled', 'opinions_shared_objects_present') AND NOT h.ok;
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'forum_drop preflight: Spec 3 W2 does not hold: %', v_bad;
  END IF;
  -- Any cron job, by what it runs (a hand-made one W2's check cannot know).
  IF pg_catalog.to_regclass('cron.job') IS NOT NULL THEN
    SELECT pg_catalog.array_agg(coalesce(j.jobname, '<unnamed>') || ' (jobid ' || j.jobid || ')' ORDER BY j.jobid)
      INTO v_bad
      FROM cron.job AS j
     WHERE j.command ~* ('(forum_topics|forum_posts|topic_votes|topic_impressions|user_forum_sides|forum_post_likes|forum_topic_tags|forum_topic_visits|public_forum|'
                         || (SELECT pg_catalog.string_agg(pg_catalog.split_part(pg_catalog.split_part(k, '(', 1), '.', 2), '|')
                               FROM pg_catalog.unnest(v_dropped) AS k)
                         || ')');
    IF v_bad IS NOT NULL THEN
      RAISE EXCEPTION 'forum_drop preflight: cron job(s) % name the forum schema; unschedule them first', v_bad;
    END IF;
  END IF;

  -- (e) Strikes (or a ban) only a removed forum post can stamp wait for the key.
  IF pg_catalog.to_regclass('public.forum_posts') IS NOT NULL THEN
    SELECT pg_catalog.count(*) INTO v_n
      FROM public.profiles AS p
     WHERE (p.confirmed_violation_count
              > coalesce((SELECT sum(s.strikes) FROM private.opinion_enforcement_stamps AS s
                           WHERE s.user_id = p.id), 0)
            -- a live ban no stamp covers (the backfill stamps it too)
            OR (p.banned_until > now()
                AND coalesce((SELECT max(s.ban_until) FROM private.opinion_enforcement_stamps AS s
                               WHERE s.user_id = p.id), '-infinity') < p.banned_until))
       AND EXISTS (SELECT 1 FROM public.forum_posts AS f WHERE f.user_id = p.id AND f.removed_at IS NOT NULL);
    IF v_n > 0 AND public.dating_phone_hmac('attune:dating_exclusion_key:fingerprint:v1') IS NULL THEN
      RAISE EXCEPTION 'forum_drop preflight: % account(s) with a removed forum post wait for their Opinions stamps, and dating_exclusion_key is not set; set it (Vault) and push again (migration 3 runs private.opinion_stamp_backfill() before forum_posts goes)', v_n;
    END IF;
  END IF;
END
$$;

DROP VIEW IF EXISTS public.public_forum_posts RESTRICT;
DROP VIEW IF EXISTS public.public_forum_topics RESTRICT;

COMMIT;
````

Create `supabase/migrations/20261125100010_forum_drop_functions.sql` with exactly:

````sql
-- Spec 3 (forum removal) W3, migration 2 of 6: the 29 forum-only functions
-- (Spec 3 §3.9), closed to every role since W2 (20261025090100). This also
-- removes the realtime senders of topic-counts:<id> and post-counts:<id>.
-- RESTRICT: an unexpected dependency fails loudly instead of cascading.
-- Kept (Spec 3 §4): private.enqueue_forum_notification, private.assert_can_post,
-- public.admin_confirm_content_removal, public.get_post_poll (and its anon
-- grant), private.create_poll_for_post, every poll, tag and Opinions RPC.
-- Idempotent: IF EXISTS.
BEGIN;
SET LOCAL lock_timeout = '5s';

DROP FUNCTION IF EXISTS public.activate_pending_topics() RESTRICT;
DROP FUNCTION IF EXISTS public.expire_old_topics() RESTRICT;
DROP FUNCTION IF EXISTS public.mark_quiet_topics() RESTRICT;
DROP FUNCTION IF EXISTS public.notify_quiet_topic(uuid) RESTRICT;
DROP FUNCTION IF EXISTS private.queue_forum_activity_notifications(uuid, uuid) RESTRICT;
DROP FUNCTION IF EXISTS public.record_forum_topic_visit(uuid) RESTRICT;
DROP FUNCTION IF EXISTS public.create_forum_post(uuid, text, text, uuid, text) RESTRICT;
DROP FUNCTION IF EXISTS public.create_forum_topic(text) RESTRICT;
DROP FUNCTION IF EXISTS public.create_forum_topic_with_poll(text, text[]) RESTRICT;
DROP FUNCTION IF EXISTS public.edit_forum_post(uuid, text) RESTRICT;
DROP FUNCTION IF EXISTS public.attach_forum_topic_tags(uuid, text[]) RESTRICT;
DROP FUNCTION IF EXISTS public.get_forum_topic_tags(uuid) RESTRICT;
DROP FUNCTION IF EXISTS public.get_forum_topics_by_tag(text, integer, integer) RESTRICT;
DROP FUNCTION IF EXISTS public.get_tags_for_forum_topics(uuid[]) RESTRICT;
DROP FUNCTION IF EXISTS public.get_polls_for_topics(uuid[]) RESTRICT;
DROP FUNCTION IF EXISTS public.get_active_forums_filtered(text[]) RESTRICT;
DROP FUNCTION IF EXISTS public.get_quiet_forums_filtered(text[]) RESTRICT;
DROP FUNCTION IF EXISTS public.get_voting_topics_filtered(text[]) RESTRICT;
DROP FUNCTION IF EXISTS public.increment_topic_upvote_count(uuid) RESTRICT;
DROP FUNCTION IF EXISTS public.decrement_topic_upvote_count(uuid) RESTRICT;
DROP FUNCTION IF EXISTS public.increment_topic_downvote_count(uuid) RESTRICT;
DROP FUNCTION IF EXISTS public.decrement_topic_downvote_count(uuid) RESTRICT;
DROP FUNCTION IF EXISTS public.increment_topic_post_count(uuid, text) RESTRICT;
DROP FUNCTION IF EXISTS public.decrement_topic_post_count(uuid, text) RESTRICT;
DROP FUNCTION IF EXISTS public.increment_topic_seen_count(uuid) RESTRICT;
DROP FUNCTION IF EXISTS public.increment_forum_post_like_count(uuid) RESTRICT;
DROP FUNCTION IF EXISTS public.decrement_forum_post_like_count(uuid) RESTRICT;
DROP FUNCTION IF EXISTS public.report_forum_post(uuid, text) RESTRICT;
DROP FUNCTION IF EXISTS public.report_forum_topic(uuid, text) RESTRICT;

COMMIT;
````

Create `supabase/migrations/20261125100020_forum_drop_tables.sql` with exactly:

````sql
-- Spec 3 (forum removal) W3, migration 3 of 6: the forum rows in kept
-- tables, the three foreign keys into the forum tables, the forum push
-- index, then the 8 forum tables (Spec 3 §6.3 step 3; V6; R14). One
-- transaction. Irreversible: the owner backs up first (W3 Owner checklist).
--   (o)   Opinions stamps first (Spec 1 W9d): while forum_posts exists and
--         an account with a removed forum post holds strikes, or a live
--         ban, no stamp covers, private.opinion_stamp_backfill() (still its pre-W3 body,
--         which counts removed forum posts; migration 5 rewrites it) runs
--         now, or those strikes could never be stamped after the drop. It
--         refuses the migration if the backfill cannot run (-1: no
--         dating_exclusion_key; the preflight's (e) stops earlier);
--   (i)   topic polls (their options and votes cascade); opinion polls stay;
--   (ii)  reports that name only a forum post or topic; every report on an
--         opinion or a comment stays;
--   (iii) every queued, sent or cancelled push of the three retired types
--         (forum_topic_activated, forum_activity, forum_quiet); the two
--         Opinions moderation notices (forum_content_removed,
--         forum_posting_banned) are not these types and stay;
--   (iv)  every foreign key on a kept table that points into a forum table,
--         found in pg_constraint; exactly the three the preflight allows;
--   (v)   idx_scheduled_notifications_forum_activity;
--   (vi)  the tables, RESTRICT, children first.
-- Idempotent: (o) runs only while forum_posts exists, (i) only while
-- post_polls.topic_id exists (migration 4 drops it); everything else is IF
-- EXISTS or finds nothing.
BEGIN;
SET LOCAL lock_timeout = '5s';

DO $$
DECLARE
  v_n bigint;
  r record;
BEGIN
  -- Nested: the inner query names forum_posts, so it runs only while it exists.
  IF pg_catalog.to_regclass('public.forum_posts') IS NOT NULL THEN
    IF EXISTS (SELECT 1 FROM public.profiles AS p
                WHERE EXISTS (SELECT 1 FROM public.forum_posts AS f
                               WHERE f.user_id = p.id AND f.removed_at IS NOT NULL)
                  AND (p.confirmed_violation_count
                         > coalesce((SELECT sum(s.strikes) FROM private.opinion_enforcement_stamps AS s
                                      WHERE s.user_id = p.id), 0)
                       -- a live ban no stamp covers (the backfill stamps it too)
                       OR (p.banned_until > now()
                           AND coalesce((SELECT max(s.ban_until) FROM private.opinion_enforcement_stamps AS s
                                          WHERE s.user_id = p.id), '-infinity') < p.banned_until))) THEN
      v_n := private.opinion_stamp_backfill();
      IF v_n < 0 THEN
        RAISE EXCEPTION 'forum_drop_tables: opinion_stamp_backfill() returned -1 (dating_exclusion_key is not set); set it and push again, or strikes from removed forum posts are lost';
      END IF;
      RAISE NOTICE 'forum_drop_tables: % account(s) stamped before forum_posts goes', v_n;
    END IF;
  END IF;

  IF EXISTS (SELECT 1 FROM pg_catalog.pg_attribute
              WHERE attrelid = 'public.post_polls'::pg_catalog.regclass
                AND attname = 'topic_id' AND NOT attisdropped) THEN
    EXECUTE 'DELETE FROM public.post_polls WHERE topic_id IS NOT NULL';
    GET DIAGNOSTICS v_n = ROW_COUNT;
    RAISE NOTICE 'forum_drop_tables: % topic poll(s) deleted', v_n;
  END IF;

  DELETE FROM public.forum_reports WHERE opinion_id IS NULL AND comment_id IS NULL;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RAISE NOTICE 'forum_drop_tables: % forum-only report(s) deleted', v_n;

  DELETE FROM public.scheduled_notifications
   WHERE metadata->>'type' IN ('forum_topic_activated', 'forum_activity', 'forum_quiet');
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RAISE NOTICE 'forum_drop_tables: % retired forum push(es) deleted', v_n;

  FOR r IN
    SELECT c.conname, c.conrelid::pg_catalog.regclass AS on_table
      FROM pg_catalog.pg_constraint AS c
     WHERE c.contype = 'f'
       AND c.confrelid IN (SELECT pg_catalog.to_regclass(x) FROM pg_catalog.unnest(ARRAY[
             'public.forum_topics', 'public.topic_votes', 'public.topic_impressions',
             'public.forum_posts', 'public.forum_post_likes', 'public.user_forum_sides',
             'public.forum_topic_tags', 'public.forum_topic_visits']) AS x)
       AND c.conrelid NOT IN (SELECT pg_catalog.to_regclass(x) FROM pg_catalog.unnest(ARRAY[
             'public.forum_topics', 'public.topic_votes', 'public.topic_impressions',
             'public.forum_posts', 'public.forum_post_likes', 'public.user_forum_sides',
             'public.forum_topic_tags', 'public.forum_topic_visits']) AS x
             WHERE pg_catalog.to_regclass(x) IS NOT NULL)
  LOOP
    IF r.conname NOT IN ('post_polls_topic_id_fkey', 'forum_reports_forum_post_id_fkey',
                         'forum_reports_topic_id_fkey') THEN
      RAISE EXCEPTION 'forum_drop_tables: unexpected foreign key % on % into the forum schema', r.conname, r.on_table;
    END IF;
    EXECUTE pg_catalog.format('ALTER TABLE %s DROP CONSTRAINT %I', r.on_table, r.conname);
    RAISE NOTICE 'forum_drop_tables: dropped % on %', r.conname, r.on_table;
  END LOOP;
END
$$;

DROP INDEX IF EXISTS public.idx_scheduled_notifications_forum_activity;

DROP TABLE IF EXISTS public.forum_post_likes RESTRICT;
DROP TABLE IF EXISTS public.forum_topic_tags RESTRICT;
DROP TABLE IF EXISTS public.forum_topic_visits RESTRICT;
DROP TABLE IF EXISTS public.topic_votes RESTRICT;
DROP TABLE IF EXISTS public.topic_impressions RESTRICT;
DROP TABLE IF EXISTS public.user_forum_sides RESTRICT;
DROP TABLE IF EXISTS public.forum_posts RESTRICT;
DROP TABLE IF EXISTS public.forum_topics RESTRICT;

COMMIT;
````

- [ ] **Step 5: Run the rehearsal to see it pass**

```bash
D=.superpowers/sdd/2026-11-24-spec3-w3
python3 -I $D/combine.py
python3 -I $D/rehearse.py attune_spec3a_w3pre
psql -X -d attune_spec3a_w3pre -Atc "select (to_regclass('public.forum_topics') is not null)::text || ', ' || count(*) || ' health rows' from public.forum_retirement_health()"
```

Expected:

```text
w3_all.sql: 3 of 6 migrations
data: all held
data (ban only): all held
refusal: refused a hand-edited shared body
refusal: refused an unknown forum function
refusal: refused a view on a forum table
refusal: refused a forum cron job still scheduled
refusal: refused a hand-edited public.admin_confirm_content_removal(text,uuid)
refusal: refused a hand-edited private.opinion_stamp_backfill()
refusal: refused a hand-edited private.create_poll_for_post(uuid,uuid,uuid,text[])
refusal: refused a hand-edited public.get_post_poll(uuid,uuid)
refusal: refused a hand-edited private.enqueue_forum_notification(uuid,text,text,text,uuid,uuid,uuid)
refusal: refused an upper-case forum reference
refusal: refused a forum function in another schema
refusal: refused a function on a forum row type
refusal: refused a hand-made cron job on a forum table
refusal: refused the guest poll grant gone
refusal: refused strikes waiting for a removed forum post without the key
refusal: refused a live ban waiting for a removed forum post without the key
refusal: refused a view calling one of the 29
refusal: refused a policy on a forum table calling one of the 29
REHEARSAL all held
true, 5 health rows
```

(the last line: the snapshot is untouched).

- [ ] **Step 6: The rehearsal mutants**

```bash
D=.superpowers/sdd/2026-11-24-spec3-w3
python3 -I $D/rehearse.py attune_spec3a_w3pre $D/mut_reh.py | tee $D/mut_reh.txt | tail -1
```

Expected: `27/27 killed` (each line `KILLED  data: … CONTRACT VIOLATED: the drop with forum data; …` or `KILLED  refusal: CONTRACT VIOLATED: the preflight let … through`; `dependency_check_off`, `rowtype_deps_off`, `function_deps_off` and `function_deps_owner_exempt` show the second line of defence: `it failed later: … cannot drop table forum_posts because other objects depend on it`; `stamp_key_check_off` shows migration 3's: `it failed later: … forum_drop_tables: opinion_stamp_backfill() returned -1`).

- [ ] **Step 7: Record the tree (do not commit).**

---

### Task 2: The kept columns, the shared branches, health v2, contract F; W3 applied (spec §6.3 migrations 4–6, §7.3 F, §3.5; V3, V7, V8; R8, R9, R15–R17; R-W3-2, R-W3-4–R-W3-7)

**Files:**
- Create: `$D/{contract_F.sql, edit_tests.py, mut_sql.py}`, `supabase/migrations/20261125100030_forum_kept_table_columns.sql`, `supabase/migrations/20261125100040_forum_shared_function_branches.sql`, `supabase/migrations/20261125100050_forum_retirement_health_v2.sql`
- Modify: `supabase/tests/forum_retirement_contracts.sql` (section F), `supabase/tests/opinion_moderation_notice_contracts.sql` (one pin), `supabase/tests/security_lockdown_contracts.sql` (one array)
- Test: `forum_retirement_contracts.sql` A–F; the suite; the rehearsal again

**Interfaces:**
- Consumes: Task 1's migrations, `combine.py`, `rehearse.py`, the snapshot, `$D/before_w3/`.
- Produces: `public.forum_retirement_health()` with seven rows (`forum_cron_unscheduled`, `forum_pushes_not_queued`, `forum_rpcs_closed_to_clients`, `forum_tables_closed_to_clients`, `opinions_shared_objects_present`, `forum_schema_dropped`, `no_code_references_forum_schema`); `private.create_poll_for_post(uuid, uuid, uuid, text[])` raising `topic_polls_retired` (22023) for a topic; `public.get_post_poll(uuid, uuid)` matching opinions only; `public.admin_confirm_content_removal('forum_post', …)` raising `invalid_content_type` (22023); `post_polls.opinion_id NOT NULL`; `forum_reports_target_check`.

- [ ] **Step 1: Write contract F and the two pins**

Create `.superpowers/sdd/2026-11-24-spec3-w3/contract_F.sql` with exactly:

````sql
-- =====================================================================
-- F (W3). The forum schema is gone, and Opinions works on what is left:
-- polls without topics, reports without forum targets, the whole ban
-- ladder with both notices, the shared functions without their forum
-- branches, and a health check that really looks. F1 is removed three
-- times; F2 posts a poll; F3 votes.
-- =====================================================================
INSERT INTO auth.users (id) VALUES
  ('9f3a0000-0000-0000-0000-0000000000f1'),
  ('9f3a0000-0000-0000-0000-0000000000f2'),
  ('9f3a0000-0000-0000-0000-0000000000f3')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.users (id, phone, display_name) VALUES
  ('9f3a0000-0000-0000-0000-0000000000f1', '+15550940011', 'Spec3 F1'),
  ('9f3a0000-0000-0000-0000-0000000000f2', '+15550940012', 'Spec3 F2'),
  ('9f3a0000-0000-0000-0000-0000000000f3', '+15550940013', 'Spec3 F3')
ON CONFLICT (id) DO NOTHING;
INSERT INTO public.profiles (id) VALUES
  ('9f3a0000-0000-0000-0000-0000000000f1'),
  ('9f3a0000-0000-0000-0000-0000000000f2'),
  ('9f3a0000-0000-0000-0000-0000000000f3')
ON CONFLICT (id) DO NOTHING;

-- F1. Health: all seven checks hold, and the two W3 checks really look.
DO $$
DECLARE
  v_bad text;
  v_job bigint;
BEGIN
  SELECT string_agg(check_name || ': ' || detail, '; ') INTO v_bad
    FROM public.forum_retirement_health() WHERE NOT ok;
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: forum_retirement_health not ok after W3: %', v_bad;
  END IF;
  IF (SELECT count(*) FROM public.forum_retirement_health()
       WHERE check_name IN ('forum_schema_dropped', 'no_code_references_forum_schema')) <> 2 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a W3 forum_retirement_health check is missing';
  END IF;

  -- A forum table back, or a forum column on a kept table, is seen.
  CREATE TABLE public.forum_topics (id int);
  IF (SELECT ok FROM public.forum_retirement_health() WHERE check_name = 'forum_schema_dropped') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the health check missed a forum table';
  END IF;
  DROP TABLE public.forum_topics;
  ALTER TABLE public.forum_reports ADD COLUMN topic_id uuid;
  IF (SELECT ok FROM public.forum_retirement_health() WHERE check_name = 'forum_schema_dropped') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the health check missed forum_reports.topic_id';
  END IF;
  ALTER TABLE public.forum_reports DROP COLUMN topic_id;

  -- A function, a view or a cron job that still names a forum table is seen.
  CREATE FUNCTION public.spec3_w3_probe() RETURNS void LANGUAGE plpgsql
    AS $f$ BEGIN PERFORM 1 FROM public.forum_posts; END $f$;
  IF (SELECT ok FROM public.forum_retirement_health() WHERE check_name = 'no_code_references_forum_schema') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the health check missed a function naming forum_posts';
  END IF;
  DROP FUNCTION public.spec3_w3_probe();
  -- Unquoted names fold to lower case, so an upper-case reference runs too.
  CREATE FUNCTION public.spec3_w3_probe() RETURNS void LANGUAGE plpgsql
    AS $f$ BEGIN PERFORM 1 FROM PUBLIC.FORUM_TOPICS; END $f$;
  IF (SELECT ok FROM public.forum_retirement_health() WHERE check_name = 'no_code_references_forum_schema') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the health check missed a function naming FORUM_TOPICS';
  END IF;
  DROP FUNCTION public.spec3_w3_probe();
  CREATE VIEW public.spec3_w3_probe_v AS SELECT 'topic_votes'::text AS t;
  IF (SELECT ok FROM public.forum_retirement_health() WHERE check_name = 'no_code_references_forum_schema') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the health check missed a view naming topic_votes';
  END IF;
  DROP VIEW public.spec3_w3_probe_v;
  v_job := cron.schedule('spec3-w3-probe', '0 3 * * *', 'select count(*) from PUBLIC.FORUM_POST_LIKES');
  IF (SELECT ok FROM public.forum_retirement_health() WHERE check_name = 'no_code_references_forum_schema') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the health check missed a cron job naming forum_post_likes';
  END IF;
  PERFORM cron.unschedule(v_job);

  SELECT string_agg(check_name, ', ') INTO v_bad FROM public.forum_retirement_health() WHERE NOT ok;
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: % stayed red after the probes were removed', v_bad;
  END IF;
END $$;

-- F2. The schema itself, read from the catalog (not through the health check).
DO $$
DECLARE
  v_bad text;
BEGIN
  SELECT string_agg(x, ', ') INTO v_bad FROM unnest(ARRAY[
    'public.forum_topics', 'public.topic_votes', 'public.topic_impressions',
    'public.forum_posts', 'public.forum_post_likes', 'public.user_forum_sides',
    'public.forum_topic_tags', 'public.forum_topic_visits',
    'public.public_forum_topics', 'public.public_forum_posts',
    'public.idx_scheduled_notifications_forum_activity', 'public.idx_post_polls_topic',
    'public.forum_reports_unique_reporter_forum_post', 'public.forum_reports_unique_reporter_topic',
    'public.idx_forum_reports_forum_post_id', 'public.idx_forum_reports_topic_id']) AS x
   WHERE to_regclass(x) IS NOT NULL;
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: still there after W3: %', v_bad;
  END IF;
  SELECT string_agg(p.proname, ', ') INTO v_bad
    FROM pg_proc AS p JOIN pg_namespace AS n ON n.oid = p.pronamespace
   WHERE n.nspname IN ('public', 'private')
     AND p.proname = ANY (ARRAY[
       'activate_pending_topics', 'expire_old_topics', 'mark_quiet_topics', 'notify_quiet_topic',
       'queue_forum_activity_notifications', 'record_forum_topic_visit', 'create_forum_post',
       'create_forum_topic', 'create_forum_topic_with_poll', 'edit_forum_post',
       'attach_forum_topic_tags', 'get_forum_topic_tags', 'get_forum_topics_by_tag',
       'get_tags_for_forum_topics', 'get_polls_for_topics', 'get_active_forums_filtered',
       'get_quiet_forums_filtered', 'get_voting_topics_filtered', 'increment_topic_upvote_count',
       'decrement_topic_upvote_count', 'increment_topic_downvote_count',
       'decrement_topic_downvote_count', 'increment_topic_post_count', 'decrement_topic_post_count',
       'increment_topic_seen_count', 'increment_forum_post_like_count',
       'decrement_forum_post_like_count', 'report_forum_post', 'report_forum_topic']);
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: forum functions still there after W3: %', v_bad;
  END IF;
  SELECT string_agg(attrelid::regclass || '.' || attname, ', ') INTO v_bad
    FROM pg_attribute
   WHERE NOT attisdropped
     AND ((attrelid = 'public.post_polls'::regclass AND attname = 'topic_id')
          OR (attrelid = 'public.forum_reports'::regclass AND attname IN ('forum_post_id', 'topic_id')));
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: forum columns still on kept tables: %', v_bad;
  END IF;
  -- What Opinions' polls and reports rest on is still there.
  SELECT string_agg(c, ', ') INTO v_bad FROM unnest(ARRAY[
    'post_polls_unique_opinion', 'post_polls_opinion_id_fkey', 'forum_reports_target_check',
    'forum_reports_opinion_id_fkey', 'forum_reports_comment_id_fkey', 'forum_reports_status_check']) AS c
   WHERE NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = c);
  IF v_bad IS NOT NULL
     OR to_regclass('public.forum_reports_unique_reporter_opinion') IS NULL
     OR to_regclass('public.forum_reports_unique_reporter_comment') IS NULL
     OR NOT (SELECT attnotnull FROM pg_attribute
              WHERE attrelid = 'public.post_polls'::regclass AND attname = 'opinion_id') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a poll or report rule Opinions needs is gone: %',
      coalesce(v_bad, 'a dedup index, or post_polls.opinion_id NOT NULL');
  END IF;
END $$;

-- F3. The kept tables refuse a row with no Opinions parent.
DO $$
DECLARE
  v_f1 constant uuid := '9f3a0000-0000-0000-0000-0000000000f1';
  v_con text;
BEGIN
  BEGIN
    INSERT INTO public.post_polls (opinion_id, created_by) VALUES (NULL, v_f1);
    RAISE EXCEPTION 'CONTRACT VIOLATED: a poll with no opinion was accepted';
  EXCEPTION WHEN not_null_violation THEN
    NULL;
  END;
  BEGIN
    INSERT INTO public.forum_reports (reported_by, reason) VALUES (v_f1, 'Spam');
    RAISE EXCEPTION 'CONTRACT VIOLATED: a report naming neither an opinion nor a comment was accepted';
  EXCEPTION WHEN check_violation THEN
    GET STACKED DIAGNOSTICS v_con = CONSTRAINT_NAME;
    IF v_con IS DISTINCT FROM 'forum_reports_target_check' THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: the report was refused by %, expected forum_reports_target_check', v_con;
    END IF;
  END;
END $$;

-- F4. Polls: a guest still reads an opinion's poll (counts hidden), a voter
-- sees counts, a topic id matches nothing, and the writer refuses a topic.
DO $$
DECLARE
  v_f2 constant uuid := '9f3a0000-0000-0000-0000-0000000000f2';
  v_f3 constant uuid := '9f3a0000-0000-0000-0000-0000000000f3';
  v_o uuid;
  v_yes uuid;
  v_n int;
  v_visible int;
  v_msg text;
  r record;
BEGIN
  PERFORM pg_temp.as_user(v_f2);
  v_o := public.create_opinion_with_poll('Spec 3 W3 contract: a poll with no topic.', ARRAY['Yes', 'No']);
  RESET ROLE;

  PERFORM pg_temp.as_anon();
  SELECT count(*), count(vote_count) INTO v_n, v_visible
    FROM public.get_post_poll(p_opinion_id => v_o, p_topic_id => gen_random_uuid());
  RESET ROLE;
  IF v_n <> 2 OR v_visible <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a guest read % options, % visible counts (expected 2, 0)', v_n, v_visible;
  END IF;
  PERFORM pg_temp.as_anon();
  SELECT count(*) INTO v_n FROM public.get_post_poll(p_topic_id => gen_random_uuid());
  RESET ROLE;
  IF v_n <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a topic id read % poll rows', v_n;
  END IF;

  SELECT o.id INTO v_yes FROM public.poll_options AS o JOIN public.post_polls AS p ON p.id = o.poll_id
   WHERE p.opinion_id = v_o AND o.label = 'Yes';
  PERFORM pg_temp.as_user(v_f3);
  PERFORM public.cast_poll_vote(v_yes);
  SELECT * INTO r FROM public.get_post_poll(p_opinion_id => v_o) WHERE option_id = v_yes;
  RESET ROLE;
  IF r.vote_count IS DISTINCT FROM 1 OR r.has_voted IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: after voting F3 saw vote_count %, has_voted %', r.vote_count, r.has_voted;
  END IF;

  -- A topic is refused, with or without an opinion beside it.
  FOR r IN SELECT * FROM (VALUES (NULL::uuid), (v_o)) AS t(opinion) LOOP
    BEGIN
      PERFORM private.create_poll_for_post(v_f2, r.opinion, gen_random_uuid(), ARRAY['a', 'b']);
      RAISE EXCEPTION 'CONTRACT VIOLATED: a topic poll was accepted (opinion %)', r.opinion;
    EXCEPTION
      WHEN invalid_parameter_value THEN
        GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
        IF v_msg <> 'topic_polls_retired' THEN
          RAISE EXCEPTION 'CONTRACT VIOLATED: a topic poll raised %, expected topic_polls_retired', v_msg;
        END IF;
      WHEN not_null_violation OR unique_violation THEN
        RAISE EXCEPTION 'CONTRACT VIOLATED: a topic poll reached the insert (%)', SQLERRM;
    END;
  END LOOP;
  IF (SELECT count(*) FROM public.post_polls WHERE opinion_id = v_o) <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a refused topic poll left a poll behind';
  END IF;
END $$;

-- F5. Moderation: 'forum_post' is an unknown type now; three confirmed
-- removals still give strikes 1, 2, 3, the 7-day ban and both notices
-- (Spec 1 W9b); the ban gate holds for every kind, 'topic' included.
DO $$
DECLARE
  v_f1 constant uuid := '9f3a0000-0000-0000-0000-0000000000f1';
  v_f2 constant uuid := '9f3a0000-0000-0000-0000-0000000000f2';
  v_o uuid[];
  v_msg text;
  v_i int;
  r record;
BEGIN
  WITH ins AS (
    INSERT INTO public.opinions (user_id, content)
    SELECT v_f1, 'Spec 3 W3 contract: removal ' || g FROM generate_series(1, 3) AS g
    RETURNING id)
  SELECT array_agg(id ORDER BY id) INTO v_o FROM ins;

  PERFORM pg_temp.as_service();
  BEGIN
    PERFORM public.admin_confirm_content_removal('forum_post', gen_random_uuid());
    RAISE EXCEPTION 'CONTRACT VIOLATED: forum_post is still a content type after W3';
  EXCEPTION WHEN invalid_parameter_value THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    IF v_msg <> 'invalid_content_type' THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: forum_post raised %, expected invalid_content_type', v_msg;
    END IF;
  END;
  FOR v_i IN 1 .. 3 LOOP
    SELECT * INTO r FROM public.admin_confirm_content_removal('opinion', v_o[v_i]);
    IF r.violation_count IS DISTINCT FROM v_i
       OR (v_i < 3 AND r.banned_until IS NOT NULL)
       OR (v_i = 3 AND r.banned_until IS DISTINCT FROM now() + interval '7 days') THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: removal % gave (%, %)', v_i, r.violation_count, r.banned_until;
    END IF;
  END LOOP;
  RESET ROLE;
  IF (SELECT banned_until FROM public.profiles WHERE id = v_f1) IS DISTINCT FROM now() + interval '7 days' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the third strike did not ban F1 for 7 days';
  END IF;
  IF (SELECT count(*) FROM public.scheduled_notifications
       WHERE user_id = v_f1 AND status = 'pending' AND metadata->>'type' = 'forum_content_removed'
         AND (metadata->>'opinion_id')::uuid = ANY (v_o)) <> 3
     OR (SELECT count(*) FROM public.scheduled_notifications
          WHERE user_id = v_f1 AND status = 'pending' AND metadata->>'type' = 'forum_posting_banned'
            AND metadata->>'body' = 'You can''t post in Opinions for 7 days.') <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the removal and ban notices did not survive W3';
  END IF;

  -- The ban gate, for an opinion and for the retired 'topic' kind alike.
  PERFORM pg_temp.as_user(v_f1);
  BEGIN
    PERFORM public.create_opinion('Spec 3 W3 contract: posting while banned.');
    RAISE EXCEPTION 'CONTRACT VIOLATED: a banned author posted';
  EXCEPTION WHEN insufficient_privilege THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    IF v_msg <> 'posting_banned' THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: expected posting_banned, got %', v_msg;
    END IF;
  END;
  RESET ROLE;
  BEGIN
    PERFORM private.assert_can_post(v_f1, 'topic');
    RAISE EXCEPTION 'CONTRACT VIOLATED: the ban gate let a banned author through as topic';
  EXCEPTION WHEN insufficient_privilege THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    IF v_msg <> 'posting_banned' THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: topic while banned raised %, expected posting_banned', v_msg;
    END IF;
  END;
  -- Not banned: 'topic' meets only the ban gate (no forum table is read).
  BEGIN
    PERFORM private.assert_can_post(v_f2, 'topic');
  EXCEPTION WHEN SQLSTATE '53400' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the retired topic kind still has a limit (%)', SQLERRM;
  END;
END $$;

-- F6. The re-created functions: search_path '', their grants as before, and
-- the owner-run stamp backfill still runs its keyed path (the removal query
-- read forum_posts until W3): with the key ready it walks F1 (three strikes
-- F5 could not stamp, no confirmed phone) and skips F1 as unverified.
DO $$
DECLARE
  v_sig text;
  v_n int;
  v_before bigint;
BEGIN
  FOREACH v_sig IN ARRAY ARRAY[
    'private.assert_can_post(uuid,text)',
    'public.admin_confirm_content_removal(text,uuid)',
    'private.opinion_stamp_backfill()',
    'private.create_poll_for_post(uuid,uuid,uuid,text[])',
    'public.get_post_poll(uuid,uuid)',
    'public.forum_retirement_health()'
  ] LOOP
    IF NOT (SELECT coalesce(p.proconfig, '{}') @> ARRAY['search_path=""'] AND p.prosecdef
              FROM pg_proc AS p WHERE p.oid = v_sig::regprocedure) THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: % is not SECURITY DEFINER with search_path ''''', v_sig;
    END IF;
    IF EXISTS (SELECT 1 FROM pg_proc AS p, aclexplode(p.proacl) AS a
                WHERE p.oid = v_sig::regprocedure AND a.grantee = 0) THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: PUBLIC can execute %', v_sig;
    END IF;
  END LOOP;
  IF NOT has_function_privilege('anon', 'public.get_post_poll(uuid,uuid)', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.get_post_poll(uuid,uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: get_post_poll lost a client grant (guest polls, V3)';
  END IF;
  FOREACH v_sig IN ARRAY ARRAY[
    'private.assert_can_post(uuid,text)',
    'public.admin_confirm_content_removal(text,uuid)',
    'private.opinion_stamp_backfill()',
    'private.create_poll_for_post(uuid,uuid,uuid,text[])'
  ] LOOP
    IF has_function_privilege('anon', v_sig, 'EXECUTE')
       OR has_function_privilege('authenticated', v_sig, 'EXECUTE') THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: a client can execute %', v_sig;
    END IF;
  END LOOP;
  IF NOT has_function_privilege('service_role', 'public.admin_confirm_content_removal(text,uuid)', 'EXECUTE')
     OR has_function_privilege('service_role', 'private.opinion_stamp_backfill()', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the service role''s grants on the moderation functions changed';
  END IF;
  PERFORM set_config('app.settings.dating_exclusion_key', 'spec3-w3-contract-exclusion-key', true);
  DELETE FROM private.dating_key_fingerprints WHERE name = 'dating_exclusion_key';
  IF private.seed_dating_exclusion_key_fingerprint() IS DISTINCT FROM 'ready' THEN
    RAISE EXCEPTION 'CONTRACT SETUP: the contract key could not be made ready';
  END IF;
  IF (SELECT p.confirmed_violation_count FROM public.profiles AS p WHERE p.id = '9f3a0000-0000-0000-0000-0000000000f1')
     <= coalesce((SELECT sum(s.strikes) FROM private.opinion_enforcement_stamps AS s
                   WHERE s.user_id = '9f3a0000-0000-0000-0000-0000000000f1'), 0) THEN
    RAISE EXCEPTION 'CONTRACT SETUP: F1 has no unstamped strike for the backfill to walk';
  END IF;
  SELECT coalesce(sum(count), 0) INTO v_before FROM public.metric_counters
   WHERE key = 'opinions.enforcement.backfill_phone_unverified';
  v_n := private.opinion_stamp_backfill();
  IF v_n IS NULL OR v_n < 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: opinion_stamp_backfill returned % with the key ready', v_n;
  END IF;
  IF (SELECT coalesce(sum(count), 0) FROM public.metric_counters
       WHERE key = 'opinions.enforcement.backfill_phone_unverified') < v_before + 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the stamp backfill did not walk F1''s removals';
  END IF;
END $$;
RESET ROLE;

````

Create `.superpowers/sdd/2026-11-24-spec3-w3/edit_tests.py` with exactly:

````python
#!/usr/bin/env python3
# Spec 3 W3 Task 1: the contracts that pinned the forum schema. Section F
# joins forum_retirement_contracts.sql (Spec 3 §7.3); the moderation notice
# contract's "kept forum branch" pin becomes "forum_post is refused"
# (§3.9: the branch goes); security_lockdown's array loses the dropped
# forum_topic_tags (§3.5). Exact edits; nothing else changes.
import pathlib, runpy
D = '.superpowers/sdd/2026-11-24-spec3-w3'
edit = runpy.run_path(f'{D}/anchor.py')['edit']
F = pathlib.Path(f'{D}/contract_F.sql').read_text()
edit('supabase/tests/forum_retirement_contracts.sql', [
    ("""DO $$ BEGIN RAISE NOTICE 'forum_retirement_contracts: all held'; END $$;
""", F + """DO $$ BEGIN RAISE NOTICE 'forum_retirement_contracts: all held'; END $$;
"""),
], 'W3 contract F')
edit('supabase/tests/opinion_moderation_notice_contracts.sql', [
    ("""  -- The kept forum branch and the type check are unchanged.
  SELECT * INTO r FROM public.admin_confirm_content_removal('forum_post', gen_random_uuid());
  IF r.violation_count IS DISTINCT FROM 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the forum_post branch changed';
  END IF;
  BEGIN
""", """  -- Spec 3 W3: the forum_post branch went with its table; it is refused
  -- like any unknown type, and the type check is unchanged.
  BEGIN
    PERFORM public.admin_confirm_content_removal('forum_post', gen_random_uuid());
    RAISE EXCEPTION 'CONTRACT VIOLATED: forum_post is still a content type';
  EXCEPTION WHEN invalid_parameter_value THEN
    IF SQLERRM <> 'invalid_content_type' THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: forum_post raised %, expected invalid_content_type', SQLERRM;
    END IF;
  END;
  BEGIN
"""),
], 'W3 notice contract')
edit('supabase/tests/security_lockdown_contracts.sql', [
    ("""  FOREACH v_fn IN ARRAY ARRAY['public.forum_topic_tags', 'public.opinion_tags', 'public.tags'] LOOP
""", """  FOREACH v_fn IN ARRAY ARRAY['public.opinion_tags', 'public.tags'] LOOP -- Spec 3 W3: forum_topic_tags is dropped
"""),
], 'W3 lockdown contract')
````

```bash
D=.superpowers/sdd/2026-11-24-spec3-w3
python3 -I $D/edit_tests.py
```

Expected: `supabase/tests/forum_retirement_contracts.sql: 1 edit(s) (W3 contract F)`, `supabase/tests/opinion_moderation_notice_contracts.sql: 1 edit(s) (W3 notice contract)`, `supabase/tests/security_lockdown_contracts.sql: 1 edit(s) (W3 lockdown contract)`.

- [ ] **Step 2: Run them to see F and the notice pin fail (attune_spec3a is still pre-W3)**

```bash
for t in forum_retirement_contracts opinion_moderation_notice_contracts security_lockdown_contracts; do
  echo "$t: $(psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/$t.sql 2>&1 | grep -oE 'all held|CONTRACT VIOLATED.*' | head -1)"
done
```

Expected:

```text
forum_retirement_contracts: CONTRACT VIOLATED: a W3 forum_retirement_health check is missing
opinion_moderation_notice_contracts: CONTRACT VIOLATED: forum_post is still a content type
security_lockdown_contracts: all held
```

- [ ] **Step 3: The three migrations**

Create `supabase/migrations/20261125100030_forum_kept_table_columns.sql` with exactly:

````sql
-- Spec 3 (forum removal) W3, migration 4 of 6: the kept poll and report
-- tables lose their forum columns (Spec 3 §3.9, §6.3 step 4; V6, V7; D7,
-- D8). One transaction with the two poll functions that read or wrote
-- post_polls.topic_id, so no moment exists where a live function names a
-- dropped column.
--   * private.create_poll_for_post and public.get_post_poll: their live
--     bodies (20260726120000_polls_on_opinions_and_topics.sql; md5 checked
--     by migration 1) with only the topic handling changed. Signatures and
--     defaults unchanged, so get_post_poll keeps its anon grant (V3: guest
--     Opinions polls) and an old client passing p_topic_id gets no rows;
--     create_poll_for_post refuses a topic (topic_polls_retired, 22023).
--     search_path '' (house rule; every relation was already qualified).
--     Removed, verbatim: in create_poll_for_post
--       INSERT INTO public.post_polls (opinion_id, topic_id, created_by)
--       VALUES (p_opinion_id, p_topic_id, p_user_id)
--     and in get_post_poll
--          OR (p_topic_id IS NOT NULL AND p.topic_id = p_topic_id)
--   * post_polls: post_polls_one_parent, post_polls_unique_topic and
--     idx_post_polls_topic, then topic_id; opinion_id NOT NULL keeps "every
--     poll has its one parent" (topic polls were deleted by migration 3).
--   * forum_reports: forum_reports_check, the two forum dedup indexes and
--     the two forum indexes, then forum_post_id and topic_id;
--     forum_reports_target_check keeps "every report names an opinion or a
--     comment" (forum-only reports were deleted by migration 3). The
--     opinion and comment columns, their dedup indexes (report_opinion's
--     ON CONFLICT target), RLS and grants are unchanged.
-- Idempotent: CREATE OR REPLACE, IF EXISTS, the CHECK added once.
BEGIN;
SET LOCAL lock_timeout = '5s';

CREATE OR REPLACE FUNCTION private.create_poll_for_post(p_user_id uuid, p_opinion_id uuid, p_topic_id uuid, p_options text[])
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = ''
AS $function$
DECLARE
  v_poll_id uuid;
  v_label text;
  v_position int := 0;
  v_clean text[];
BEGIN
  -- Spec 3 W3: topic polls are retired with the forums. p_topic_id stays in
  -- the signature, so the one caller (create_opinion_with_poll, which passes
  -- NULL) is unchanged; a topic is refused.
  IF p_topic_id IS NOT NULL THEN
    RAISE EXCEPTION 'topic_polls_retired' USING ERRCODE = '22023';
  END IF;
  -- 2-4 options (§8.11). Reject anything else rather than silently truncating.
  IF p_options IS NULL OR array_length(p_options, 1) IS NULL THEN
    RAISE EXCEPTION 'poll_requires_options' USING ERRCODE = '22023';
  END IF;

  SELECT array_agg(btrim(opt))
  INTO v_clean
  FROM unnest(p_options) AS opt
  WHERE btrim(opt) <> '';

  IF v_clean IS NULL OR array_length(v_clean, 1) < 2 OR array_length(v_clean, 1) > 4 THEN
    RAISE EXCEPTION 'poll_option_count' USING ERRCODE = '22023';
  END IF;

  FOREACH v_label IN ARRAY v_clean LOOP
    IF char_length(v_label) > 60 THEN
      RAISE EXCEPTION 'poll_option_too_long' USING ERRCODE = '22023';
    END IF;
  END LOOP;

  INSERT INTO public.post_polls (opinion_id, created_by) -- Spec 3 W3: no topic_id
  VALUES (p_opinion_id, p_user_id) -- Spec 3 W3
  RETURNING id INTO v_poll_id;

  FOREACH v_label IN ARRAY v_clean LOOP
    INSERT INTO public.poll_options (poll_id, option_position, label)
    VALUES (v_poll_id, v_position, v_label);
    v_position := v_position + 1;
  END LOOP;

  RETURN v_poll_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_post_poll(p_opinion_id uuid DEFAULT NULL::uuid, p_topic_id uuid DEFAULT NULL::uuid)
 RETURNS TABLE(poll_id uuid, option_id uuid, option_position integer, label text, vote_count integer, total_votes integer, my_option_id uuid, has_voted boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path = ''
AS $function$
  -- Spec 3 W3: topic polls are retired. The second parameter stays so the
  -- signature, and the anon grant guest Opinions polls need, never change;
  -- it matches nothing.
  WITH target AS (
    SELECT p.id
    FROM public.post_polls p
    WHERE p_opinion_id IS NOT NULL AND p.opinion_id = p_opinion_id -- Spec 3 W3
    LIMIT 1
  ),
  mine AS (
    SELECT v.option_id
    FROM public.poll_votes v
    JOIN target t ON t.id = v.poll_id
    WHERE v.user_id = auth.uid()
  ),
  totals AS (
    SELECT COALESCE(sum(o.vote_count), 0)::int AS total
    FROM public.poll_options o
    JOIN target t ON t.id = o.poll_id
  )
  SELECT
    o.poll_id,
    o.id AS option_id,
    o.option_position,
    o.label,
    -- Masked until the caller has voted.
    CASE WHEN (SELECT option_id FROM mine) IS NOT NULL
         THEN o.vote_count END AS vote_count,
    CASE WHEN (SELECT option_id FROM mine) IS NOT NULL
         THEN (SELECT total FROM totals) END AS total_votes,
    (SELECT option_id FROM mine) AS my_option_id,
    ((SELECT option_id FROM mine) IS NOT NULL) AS has_voted
  FROM public.poll_options o
  JOIN target t ON t.id = o.poll_id
  ORDER BY o.option_position;
$function$;

-- The ACLs as they are (re-asserted): the poll writer is the database's own;
-- the poll read is for guests and signed-in people (V3).
REVOKE ALL ON FUNCTION private.create_poll_for_post(uuid, uuid, uuid, text[]) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.get_post_poll(uuid, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_post_poll(uuid, uuid) TO anon, authenticated;

ALTER TABLE public.post_polls DROP CONSTRAINT IF EXISTS post_polls_one_parent;
ALTER TABLE public.post_polls DROP CONSTRAINT IF EXISTS post_polls_unique_topic;
DROP INDEX IF EXISTS public.idx_post_polls_topic;
ALTER TABLE public.post_polls DROP COLUMN IF EXISTS topic_id RESTRICT;
ALTER TABLE public.post_polls ALTER COLUMN opinion_id SET NOT NULL;

ALTER TABLE public.forum_reports DROP CONSTRAINT IF EXISTS forum_reports_check;
DROP INDEX IF EXISTS public.forum_reports_unique_reporter_forum_post;
DROP INDEX IF EXISTS public.forum_reports_unique_reporter_topic;
DROP INDEX IF EXISTS public.idx_forum_reports_forum_post_id;
DROP INDEX IF EXISTS public.idx_forum_reports_topic_id;
ALTER TABLE public.forum_reports
  DROP COLUMN IF EXISTS forum_post_id RESTRICT,
  DROP COLUMN IF EXISTS topic_id RESTRICT;
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_constraint
                  WHERE conrelid = 'public.forum_reports'::pg_catalog.regclass
                    AND conname = 'forum_reports_target_check') THEN
    ALTER TABLE public.forum_reports
      ADD CONSTRAINT forum_reports_target_check CHECK (opinion_id IS NOT NULL OR comment_id IS NOT NULL);
  END IF;
END
$$;

COMMIT;
````

Create `supabase/migrations/20261125100040_forum_shared_function_branches.sql` with exactly:

````sql
-- Spec 3 (forum removal) W3, migration 5 of 6: the shared functions lose
-- their forum branches (Spec 3 §6.3 step 5, §3.9; V8, V11; R15-R17). Each is
-- its LIVE body (pg_get_functiondef on attune_spec3a at 9bac1bdb; migration
-- 1 refuses to run unless the database holds exactly that body, md5 of
-- prosrc) with only the lines below changed; review is a pure diff against
-- the source named. Opinions limits, bans, strikes, stamps and the two
-- moderation notices Spec 1 W9b restored are unchanged.
--   * private.assert_can_post(uuid, text) (live: 20260716140000): removed,
--     verbatim:
--         ELSIF p_kind = 'topic' THEN
--           -- 3 submissions per 7 days.
--           SELECT count(*) INTO v_count
--           FROM public.forum_topics
--           WHERE submitted_by = p_user_id AND created_at > now() - interval '7 days';
--           IF v_count >= 3 THEN RAISE EXCEPTION 'daily_limit' USING ERRCODE = '53400'; END IF;
--         -- forum_post per-forum limits are enforced in create_forum_post (needs topic_id).
--     and search_path 'public', 'private' becomes '' (every relation was
--     already qualified). 'topic' now meets only the ban gate.
--   * public.admin_confirm_content_removal(text, uuid) (live: 20261107100000):
--     removed, verbatim:
--         ELSIF p_content_type = 'forum_post' THEN
--           UPDATE public.forum_posts SET removed_at = now()
--           WHERE id = p_content_id AND removed_at IS NULL
--           RETURNING user_id INTO v_author_id;
--     so 'forum_post' raises invalid_content_type (22023) like any unknown
--     type. Spec 1 W9b's notices and W9d's stamp are untouched.
--   * private.opinion_stamp_backfill() (Spec 1 W9d, live: 20261107100000;
--     added after Spec 3 was written, found by migration 1's inventory):
--     removed, verbatim:
--                     UNION ALL
--                     SELECT f.removed_at FROM public.forum_posts AS f WHERE f.user_id = r.id AND f.removed_at IS NOT NULL
--     With no forum post left the branch reads nothing. Removed forum posts
--     no longer count, from v_removed as well as from the earliest date: an
--     account whose strikes include forum-post removals now fails
--     v_removed >= strikes and is skipped as unverified (fails closed: "not
--     shown"). W9d's own apply-time backfill, run with the keys set before
--     this wave, stamps such accounts while forum_posts still exists (owner
--     checklist).
-- ACLs re-asserted as they are: assert_can_post and the backfill are the
-- database's own (the backfill is owner-run; dating_rls_canary.sql pins no
-- service_role); admin_confirm_content_removal is the service role's.
-- private.enqueue_forum_notification is not touched (every Opinions caller
-- uses named arguments; p_forum_post_id stays in its signature).
-- Idempotent: CREATE OR REPLACE.
BEGIN;
SET LOCAL lock_timeout = '5s';

CREATE OR REPLACE FUNCTION private.assert_can_post(p_user_id uuid, p_kind text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = ''
AS $function$
DECLARE
  v_banned_until timestamptz;
  v_count int;
  v_last timestamptz;
BEGIN
  -- Ban gate: banned users may read but not post.
  SELECT banned_until INTO v_banned_until FROM public.profiles WHERE id = p_user_id;
  IF v_banned_until IS NOT NULL AND v_banned_until > now() THEN
    RAISE EXCEPTION 'posting_banned' USING ERRCODE = '42501';
  END IF;

  IF p_kind = 'opinion' THEN
    -- 5 per 24h, 60s cooldown.
    SELECT count(*), max(created_at) INTO v_count, v_last
    FROM public.opinions
    WHERE user_id = p_user_id AND created_at > now() - interval '24 hours';
    IF v_count >= 5 THEN RAISE EXCEPTION 'daily_limit' USING ERRCODE = '53400'; END IF;
    IF v_last IS NOT NULL AND v_last > now() - interval '60 seconds' THEN
      RAISE EXCEPTION 'cooldown' USING ERRCODE = '53400';
    END IF;

  ELSIF p_kind = 'comment' THEN
    -- 20 per 24h.
    SELECT count(*) INTO v_count
    FROM public.opinion_comments
    WHERE user_id = p_user_id AND created_at > now() - interval '24 hours';
    IF v_count >= 20 THEN RAISE EXCEPTION 'daily_limit' USING ERRCODE = '53400'; END IF;
  END IF;
  -- Spec 3 W3: any other kind (the retired 'topic' among them) has no limit
  -- beyond the ban gate above.
END;
$function$;

CREATE OR REPLACE FUNCTION public.admin_confirm_content_removal(p_content_type text, p_content_id uuid)
 RETURNS TABLE(violation_count integer, banned_until timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = ''
AS $function$
DECLARE
  v_author_id uuid;
  v_new_count int;
  v_ban_until timestamptz;
  v_prev_ban timestamptz; -- Spec 1 W9b
BEGIN
  IF auth.role() <> 'service_role' THEN
    RAISE EXCEPTION 'forbidden' USING ERRCODE = '42501';
  END IF;

  IF p_content_type = 'opinion' THEN
    UPDATE public.opinions SET removed_at = now()
    WHERE id = p_content_id AND removed_at IS NULL
    RETURNING user_id INTO v_author_id;
  ELSIF p_content_type = 'comment' THEN
    UPDATE public.opinion_comments SET removed_at = now()
    WHERE id = p_content_id AND removed_at IS NULL
    RETURNING user_id INTO v_author_id;
  ELSE
    -- Spec 3 W3: 'forum_post' is refused here too; its table is gone.
    RAISE EXCEPTION 'invalid_content_type' USING ERRCODE = '22023';
  END IF;

  IF v_author_id IS NULL THEN
    RETURN QUERY SELECT 0, NULL::timestamptz;
    RETURN;
  END IF;

  UPDATE public.profiles
  SET confirmed_violation_count = confirmed_violation_count + 1
  WHERE id = v_author_id
  RETURNING confirmed_violation_count INTO v_new_count;

  -- Spec 1 W9b (D17): the removal notice, to the author only.
  PERFORM private.enqueue_forum_notification(
    p_user_id    => v_author_id,
    p_title      => 'Post removed',
    p_body       => 'One of your posts was removed for breaking the Opinions guidelines.',
    p_type       => 'forum_content_removed',
    p_opinion_id => CASE WHEN p_content_type = 'opinion' THEN p_content_id END,
    p_comment_id => CASE WHEN p_content_type = 'comment' THEN p_content_id END
  );

  IF v_new_count >= 3 THEN
    -- Never move the ban backward: a moderator confirming several
    -- violations in one sitting extends the ban past whichever is later
    -- (now, or an existing future banned_until), and never re-shortens or
    -- re-applies a ban that already ran its course before this confirmation.
    SELECT GREATEST(COALESCE(p.banned_until, now()), now()) + interval '7 days', p.banned_until -- Spec 1 W9b: OPN-BAN-42702
    INTO v_ban_until, v_prev_ban
    FROM public.profiles AS p WHERE p.id = v_author_id;

    UPDATE public.profiles
    SET banned_until = v_ban_until
    WHERE id = v_author_id;

    -- Spec 1 W9b (D17): the ban notice, new or extended.
    PERFORM private.enqueue_forum_notification(
      p_user_id => v_author_id,
      p_title   => 'Posting paused',
      p_body    => CASE WHEN v_prev_ban > now()
                        THEN 'Your pause on posting in Opinions has been extended.'
                        ELSE 'You can''t post in Opinions for 7 days.' END,
      p_type    => 'forum_posting_banned'
    );
  END IF;

  -- Spec 1 W9d (O4; S2 W1 B3 I-1): this strike, and the ban it set, are
  -- Spec 1 W9d stamped with the number the author holds now; never raises.
  IF v_new_count IS NOT NULL THEN -- Spec 1 W9d
    PERFORM private.opinion_stamp_enforcement(v_author_id, 1, v_ban_until); -- Spec 1 W9d
  END IF; -- Spec 1 W9d
  RETURN QUERY SELECT v_new_count, v_ban_until;
END;
$function$;

CREATE OR REPLACE FUNCTION private.opinion_stamp_backfill()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = ''
AS $function$
-- Owner-run (owner checklist): strikes and live bans no stamp covers, under
-- the number each account holds now, only when that number provably hasn't
-- changed since the account's earliest removed post (M-1 ruling). -1 while
-- the key is missing.
DECLARE
  r record;
  v_n integer := 0;
  v_first timestamptz;
  v_removed integer;
BEGIN
  IF public.dating_phone_hmac('attune:dating_exclusion_key:fingerprint:v1') IS NULL THEN
    RAISE NOTICE 'dating_exclusion_key is not set: no Opinions strike stamped';
    RETURN -1;
  END IF;
  FOR r IN
    SELECT p.id, p.confirmed_violation_count AS strikes,
           CASE WHEN p.banned_until > now() THEN p.banned_until END AS ban,
           coalesce((SELECT sum(s.strikes) FROM private.opinion_enforcement_stamps AS s
                      WHERE s.user_id = p.id), 0)::integer AS stamped,
           (SELECT max(s.ban_until) FROM private.opinion_enforcement_stamps AS s
             WHERE s.user_id = p.id) AS stamped_ban,
           (SELECT a.phone_confirmed_at FROM auth.users AS a WHERE a.id = p.id) AS confirmed_at,
           (SELECT (to_jsonb(a) ->> 'phone_change_sent_at')::timestamptz FROM auth.users AS a
             WHERE a.id = p.id) AS change_sent_at
      FROM public.profiles AS p
     WHERE p.confirmed_violation_count > 0 OR p.banned_until > now()
  LOOP
    IF r.strikes > r.stamped OR (r.ban IS NOT NULL AND (r.stamped_ban IS NULL OR r.stamped_ban < r.ban)) THEN
      SELECT min(x.removed_at), count(*)::integer INTO v_first, v_removed
        FROM (SELECT o.removed_at FROM public.opinions AS o WHERE o.user_id = r.id AND o.removed_at IS NOT NULL
              UNION ALL
              SELECT c.removed_at FROM public.opinion_comments AS c WHERE c.user_id = r.id AND c.removed_at IS NOT NULL) AS x; -- Spec 3 W3: forum posts are gone
      -- The number held now provably held since the earliest removal, or
      -- nothing is stamped (a NULL anywhere is "not shown").
      IF NOT coalesce(v_removed >= r.strikes
                      AND r.confirmed_at <= v_first
                      AND (r.change_sent_at IS NULL OR r.change_sent_at <= v_first), false) THEN
        PERFORM private.bump_metric_internal('opinions.enforcement.backfill_phone_unverified');
        CONTINUE;
      END IF;
      IF private.opinion_stamp_enforcement(r.id, greatest(r.strikes - r.stamped, 0), r.ban) THEN
        v_n := v_n + 1;
      END IF;
    END IF;
  END LOOP;
  RETURN v_n;
END;
$function$;

REVOKE ALL ON FUNCTION private.assert_can_post(uuid, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.admin_confirm_content_removal(text, uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_confirm_content_removal(text, uuid) TO service_role;
REVOKE ALL ON FUNCTION private.opinion_stamp_backfill() FROM PUBLIC, anon, authenticated, service_role;

COMMIT;
````

Create `supabase/migrations/20261125100050_forum_retirement_health_v2.sql` with exactly:

````sql
-- Spec 3 (forum removal) W3, migration 6 of 6: forum_retirement_health()
-- gains its two W3 checks (Spec 3 §6.2 step 4, §6.3 step 6; D9):
--   forum_schema_dropped: none of the 10 forum relations or 29 forum
--     functions exists, nor post_polls.topic_id, forum_reports.forum_post_id,
--     forum_reports.topic_id or idx_scheduled_notifications_forum_activity;
--   no_code_references_forum_schema: no function body in public or private
--     (this function aside), no view and no cron job names a forum relation,
--     in any letter case (unquoted names fold to lower case; views are
--     stored deparsed, in lower case).
-- The five W2 checks are unchanged (20261025090300, copied verbatim). Same
-- posture: STABLE SECURITY DEFINER, search_path '', service role only.
-- Idempotent: CREATE OR REPLACE.
BEGIN;
SET LOCAL lock_timeout = '5s';

CREATE OR REPLACE FUNCTION public.forum_retirement_health()
RETURNS TABLE (check_name text, ok boolean, detail text)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_forum_rpcs constant text[] := ARRAY[
    'public.activate_pending_topics()',
    'public.expire_old_topics()',
    'public.mark_quiet_topics()',
    'public.notify_quiet_topic(uuid)',
    'private.queue_forum_activity_notifications(uuid,uuid)',
    'public.record_forum_topic_visit(uuid)',
    'public.create_forum_post(uuid,text,text,uuid,text)',
    'public.create_forum_topic(text)',
    'public.create_forum_topic_with_poll(text,text[])',
    'public.edit_forum_post(uuid,text)',
    'public.attach_forum_topic_tags(uuid,text[])',
    'public.get_forum_topic_tags(uuid)',
    'public.get_forum_topics_by_tag(text,integer,integer)',
    'public.get_tags_for_forum_topics(uuid[])',
    'public.get_polls_for_topics(uuid[])',
    'public.get_active_forums_filtered(text[])',
    'public.get_quiet_forums_filtered(text[])',
    'public.get_voting_topics_filtered(text[])',
    'public.increment_topic_upvote_count(uuid)',
    'public.decrement_topic_upvote_count(uuid)',
    'public.increment_topic_downvote_count(uuid)',
    'public.decrement_topic_downvote_count(uuid)',
    'public.increment_topic_post_count(uuid,text)',
    'public.decrement_topic_post_count(uuid,text)',
    'public.increment_topic_seen_count(uuid)',
    'public.increment_forum_post_like_count(uuid)',
    'public.decrement_forum_post_like_count(uuid)',
    'public.report_forum_post(uuid,text)',
    'public.report_forum_topic(uuid,text)'
  ];
  v_forum_relations constant text[] := ARRAY[
    'public.forum_topics',
    'public.topic_votes',
    'public.topic_impressions',
    'public.forum_posts',
    'public.forum_post_likes',
    'public.user_forum_sides',
    'public.forum_topic_tags',
    'public.forum_topic_visits',
    'public.public_forum_topics',
    'public.public_forum_posts'
  ];
  v_kept_relations constant text[] := ARRAY[
    'public.forum_reports',
    'public.post_polls',
    'public.poll_options',
    'public.poll_votes',
    'public.tags',
    'public.opinion_tags',
    'public.tag_follows'
  ];
  v_kept_functions constant text[] := ARRAY[
    'private.enqueue_forum_notification(uuid,text,text,text,uuid,uuid,uuid)',
    'private.assert_can_post(uuid,text)',
    'public.admin_confirm_content_removal(text,uuid)'
  ];
  -- Spec 3 W3: the columns that pointed into the forum tables.
  v_forum_columns constant text[][] := ARRAY[
    ARRAY['public.post_polls', 'topic_id'],
    ARRAY['public.forum_reports', 'forum_post_id'],
    ARRAY['public.forum_reports', 'topic_id']
  ];
  v_forum_names constant text :=
    '\m(forum_topics|forum_posts|topic_votes|topic_impressions|user_forum_sides|forum_post_likes|forum_topic_tags|forum_topic_visits|public_forum_topics|public_forum_posts)\M';
  v_i int;
  v_name text;
  v_fn regprocedure;
  v_rel regclass;
  v_bad text[];
BEGIN
  -- 1. No forum cron, by name or by what it runs.
  SELECT pg_catalog.array_agg(
           coalesce(j.jobname, '<unnamed>') || ' (jobid ' || j.jobid || ')'
           ORDER BY j.jobid)
    INTO v_bad
    FROM cron.job j
   WHERE j.jobname IN ('activate-topics-sweep', 'forum-quiet-check', 'mark-quiet-forums')
      OR j.command ~* '(activate-topics|forum-quiet-check|forum_topics|mark_quiet_topics|activate_pending_topics|expire_old_topics|notify_quiet_topic)';
  check_name := 'forum_cron_unscheduled';
  ok := v_bad IS NULL;
  detail := coalesce(pg_catalog.array_to_string(v_bad, ', '), 'none');
  RETURN NEXT;

  -- 2. No retired forum push waiting to go out or going out.
  SELECT pg_catalog.array_agg(DISTINCT (s.metadata->>'type') || ' ' || s.status)
    INTO v_bad
    FROM public.scheduled_notifications s
   WHERE s.status IN ('pending', 'processing')
     AND s.metadata->>'type' IN ('forum_topic_activated', 'forum_activity', 'forum_quiet');
  check_name := 'forum_pushes_not_queued';
  ok := v_bad IS NULL;
  detail := coalesce(pg_catalog.array_to_string(v_bad, ', '), 'none');
  RETURN NEXT;

  -- 3. No forum RPC a client can execute (a dropped one passes).
  v_bad := NULL;
  FOREACH v_name IN ARRAY v_forum_rpcs LOOP
    v_fn := pg_catalog.to_regprocedure(v_name);
    IF v_fn IS NOT NULL
       AND (pg_catalog.has_function_privilege('anon', v_fn, 'EXECUTE')
            OR pg_catalog.has_function_privilege('authenticated', v_fn, 'EXECUTE')) THEN
      v_bad := pg_catalog.array_append(v_bad, v_name);
    END IF;
  END LOOP;
  check_name := 'forum_rpcs_closed_to_clients';
  ok := v_bad IS NULL;
  detail := coalesce(pg_catalog.array_to_string(v_bad, ', '), 'none');
  RETURN NEXT;

  -- 4. No forum table or view a client can read or write (a dropped one passes).
  v_bad := NULL;
  FOREACH v_name IN ARRAY v_forum_relations LOOP
    v_rel := pg_catalog.to_regclass(v_name);
    IF v_rel IS NOT NULL
       AND (pg_catalog.has_table_privilege('anon', v_rel, 'SELECT, INSERT, UPDATE, DELETE')
            OR pg_catalog.has_table_privilege('authenticated', v_rel, 'SELECT, INSERT, UPDATE, DELETE')) THEN
      v_bad := pg_catalog.array_append(v_bad, v_name);
    END IF;
  END LOOP;
  check_name := 'forum_tables_closed_to_clients';
  ok := v_bad IS NULL;
  detail := coalesce(pg_catalog.array_to_string(v_bad, ', '), 'none');
  RETURN NEXT;

  -- 5. Everything Opinions shares with the old forum schema is still there,
  -- including guest polls.
  v_bad := NULL;
  FOREACH v_name IN ARRAY v_kept_relations LOOP
    IF pg_catalog.to_regclass(v_name) IS NULL THEN
      v_bad := pg_catalog.array_append(v_bad, v_name || ' missing');
    END IF;
  END LOOP;
  FOREACH v_name IN ARRAY v_kept_functions LOOP
    IF pg_catalog.to_regprocedure(v_name) IS NULL THEN
      v_bad := pg_catalog.array_append(v_bad, v_name || ' missing');
    END IF;
  END LOOP;
  v_fn := pg_catalog.to_regprocedure('public.get_post_poll(uuid,uuid)');
  IF v_fn IS NULL
     OR NOT pg_catalog.has_function_privilege('anon', v_fn, 'EXECUTE')
     OR NOT pg_catalog.has_function_privilege('authenticated', v_fn, 'EXECUTE') THEN
    v_bad := pg_catalog.array_append(v_bad, 'get_post_poll(uuid,uuid) not executable by anon and authenticated');
  END IF;
  v_fn := pg_catalog.to_regprocedure('public.create_opinion_with_poll(text,text[])');
  IF v_fn IS NULL
     OR NOT pg_catalog.has_function_privilege('authenticated', v_fn, 'EXECUTE') THEN
    v_bad := pg_catalog.array_append(v_bad, 'create_opinion_with_poll(text,text[]) not executable by authenticated');
  END IF;
  check_name := 'opinions_shared_objects_present';
  ok := v_bad IS NULL;
  detail := coalesce(pg_catalog.array_to_string(v_bad, ', '), 'none');
  RETURN NEXT;

  -- 6. Spec 3 W3: the forum schema is gone: no forum relation, function,
  -- forum column on a kept table, or forum push index.
  v_bad := NULL;
  FOREACH v_name IN ARRAY v_forum_relations LOOP
    IF pg_catalog.to_regclass(v_name) IS NOT NULL THEN
      v_bad := pg_catalog.array_append(v_bad, v_name);
    END IF;
  END LOOP;
  FOREACH v_name IN ARRAY v_forum_rpcs LOOP
    IF pg_catalog.to_regprocedure(v_name) IS NOT NULL THEN
      v_bad := pg_catalog.array_append(v_bad, v_name);
    END IF;
  END LOOP;
  FOR v_i IN 1 .. pg_catalog.array_length(v_forum_columns, 1) LOOP
    IF EXISTS (SELECT 1 FROM pg_catalog.pg_attribute AS a
                WHERE a.attrelid = pg_catalog.to_regclass(v_forum_columns[v_i][1])
                  AND a.attname = v_forum_columns[v_i][2] AND NOT a.attisdropped) THEN
      v_bad := pg_catalog.array_append(v_bad, v_forum_columns[v_i][1] || '.' || v_forum_columns[v_i][2]);
    END IF;
  END LOOP;
  IF pg_catalog.to_regclass('public.idx_scheduled_notifications_forum_activity') IS NOT NULL THEN
    v_bad := pg_catalog.array_append(v_bad, 'public.idx_scheduled_notifications_forum_activity');
  END IF;
  check_name := 'forum_schema_dropped';
  ok := v_bad IS NULL;
  detail := coalesce(pg_catalog.array_to_string(v_bad, ', '), 'none');
  RETURN NEXT;

  -- 7. Spec 3 W3: no function body (this one aside: it names them to look
  -- for them), view or cron job still names a forum relation.
  SELECT pg_catalog.array_agg(x.what ORDER BY x.what) INTO v_bad
    FROM (
      SELECT 'function ' || n.nspname || '.' || p.proname AS what
        FROM pg_catalog.pg_proc AS p
        JOIN pg_catalog.pg_namespace AS n ON n.oid = p.pronamespace
       WHERE n.nspname IN ('public', 'private')
         AND p.oid <> 'public.forum_retirement_health()'::pg_catalog.regprocedure
         AND p.prosrc ~* v_forum_names -- any case: FROM FORUM_POSTS runs too
      UNION ALL
      SELECT 'view ' || v.schemaname || '.' || v.viewname
        FROM pg_catalog.pg_views AS v
       WHERE v.schemaname NOT IN ('pg_catalog', 'information_schema')
         AND v.definition ~ v_forum_names
      UNION ALL
      SELECT 'cron job ' || coalesce(j.jobname, '<unnamed>') || ' (jobid ' || j.jobid || ')'
        FROM cron.job AS j
       WHERE j.command ~* v_forum_names -- any case
    ) AS x;
  check_name := 'no_code_references_forum_schema';
  ok := v_bad IS NULL;
  detail := coalesce(pg_catalog.array_to_string(v_bad, ', '), 'none');
  RETURN NEXT;
END;
$$;

-- Service role only: it names the system's jobs and queue state.
REVOKE ALL ON FUNCTION public.forum_retirement_health() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.forum_retirement_health() TO service_role;

COMMIT;
````

- [ ] **Step 4: The rehearsal with all six, and contract F on the snapshot (rolled back)**

```bash
D=.superpowers/sdd/2026-11-24-spec3-w3
python3 -I $D/combine.py
python3 -I $D/rehearse.py attune_spec3a_w3pre | tail -1
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a_w3pre -c BEGIN -f $D/w3_all.sql -f supabase/tests/forum_retirement_contracts.sql 2>&1 | grep -oE 'all held|CONTRACT VIOLATED.*|ERROR.*' | head -1
```

Expected: `w3_all.sql: 6 of 6 migrations`; `REHEARSAL all held`; `all held` (the mutation harness's own baseline: the six and the contract in one rolled-back transaction).

- [ ] **Step 5: Apply W3 to attune_spec3a, twice**

```bash
psql -X -d attune_spec3a -Atc 'select current_database()'
for pass in 1 2; do
  for f in supabase/migrations/20261125100000_forum_drop_views.sql supabase/migrations/20261125100010_forum_drop_functions.sql supabase/migrations/20261125100020_forum_drop_tables.sql supabase/migrations/20261125100030_forum_kept_table_columns.sql supabase/migrations/20261125100040_forum_shared_function_branches.sql supabase/migrations/20261125100050_forum_retirement_health_v2.sql; do
    psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f $f > /dev/null 2>&1; echo "$pass $(basename $f .sql | cut -c16-) exit=$?"
  done
done
psql -X -d attune_spec3a -Atc "select check_name || ' ' || ok from public.forum_retirement_health()"
```

Expected: `attune_spec3a`; twelve lines, each `exit=0` (`1 forum_drop_views exit=0` … `2 forum_retirement_health_v2 exit=0`); seven lines, each ending ` true`.

- [ ] **Step 6: The contracts, the diff against the live bodies, migration 1's md5s, the suite**

```bash
D=.superpowers/sdd/2026-11-24-spec3-w3
for t in forum_retirement_contracts opinion_moderation_notice_contracts security_lockdown_contracts opinion_enforcement_records_contracts dating_v2_device_contracts dating_v2_moderation_contracts dating_rls_canary account_deletion_contracts data_export_contracts; do
  echo "$t: $(psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/$t.sql 2>&1 | grep -oE 'all held|CONTRACT VIOLATED.*|ERROR.*' | head -1)"
done
python3 -I $D/marked_diff.py $D/before_w3 attune_spec3a 'Spec 3 W3' | sed 's/; header:.*//'
for s in 'private.assert_can_post(uuid,text)' 'public.admin_confirm_content_removal(text,uuid)' 'private.opinion_stamp_backfill()' 'private.create_poll_for_post(uuid,uuid,uuid,text[])' 'public.get_post_poll(uuid,uuid)'; do
  m=$(psql -X -d attune_spec3a -Atc "select md5(prosrc) from pg_proc where oid = '$s'::regprocedure"); echo "$s after $(grep -c "'$m'" supabase/migrations/20261125100000_forum_drop_views.sql)"
done
bash $D/suite.sh attune_spec3a > $D/sql-T2.txt; echo "SQL $(grep -c '^PASS' $D/sql-T2.txt) PASS / $(grep -c '^FAIL' $D/sql-T2.txt) FAIL; new: $(comm -13 <(grep FAIL $D/sql-baseline.txt | sort) <(grep FAIL $D/sql-T2.txt | sort) | tr '\n' ' ')"
```

Expected:

```text
forum_retirement_contracts: all held
opinion_moderation_notice_contracts: all held
security_lockdown_contracts: all held
opinion_enforcement_records_contracts: all held
dating_v2_device_contracts: all held
dating_v2_moderation_contracts: all held
dating_rls_canary: all held
account_deletion_contracts: all held
data_export_contracts: all held
private.assert_can_post(uuid,text): 2 added line(s), 8 removed OK
private.create_poll_for_post(uuid,uuid,uuid,text[]): 8 added line(s), 2 removed OK
private.opinion_stamp_backfill(): 1 added line(s), 3 removed OK
public.admin_confirm_content_removal(text,uuid): 1 added line(s), 4 removed OK
public.get_post_poll(uuid,uuid): 4 added line(s), 2 removed OK
private.assert_can_post(uuid,text) after 1
public.admin_confirm_content_removal(text,uuid) after 1
private.opinion_stamp_backfill() after 1
private.create_poll_for_post(uuid,uuid,uuid,text[]) after 1
public.get_post_poll(uuid,uuid) after 1
```

and the suite at the baseline's count with `new: ` empty (a `quiet_hours_contracts.sql` line only when the baseline and this run fall on different sides of 22:00/08:00 UTC).

- [ ] **Step 7: The SQL mutants and the rehearsal mutants (on the snapshot)**

Create `.superpowers/sdd/2026-11-24-spec3-w3/mut_sql.py` with exactly:

````python
# Spec 3 W3 contract mutants (mutate.py on w3_all.sql, against
# forum_retirement_contracts.sql, on the PRE-W3 database). Each must print a
# CONTRACT VIOLATED line.
MUTS = {
    # Migration 5: the shared functions.
    'forum_post_branch_silent': (
        """  ELSE
    -- Spec 3 W3: 'forum_post' is refused here too; its table is gone.
""", """  ELSIF p_content_type = 'forum_post' THEN
    NULL;
  ELSE
"""),
    'removal_notice_lost': ("""    p_type       => 'forum_content_removed',""",
                            """    p_type       => 'opinion_removed',"""),
    'ban_notice_lost': ("""      p_type    => 'forum_posting_banned'""", """      p_type    => 'posting_paused'"""),
    'topic_still_limited': (
        """  -- Spec 3 W3: any other kind (the retired 'topic' among them) has no limit
  -- beyond the ban gate above.
""", """  IF p_kind = 'topic' THEN RAISE EXCEPTION 'daily_limit' USING ERRCODE = '53400'; END IF;
"""),
    'assert_path_public': (
        """ SET search_path = ''
AS $function$
DECLARE
  v_banned_until timestamptz;""", """ SET search_path TO 'public', 'private'
AS $function$
DECLARE
  v_banned_until timestamptz;"""),
    'backfill_reads_forum_posts': (
        """WHERE c.user_id = r.id AND c.removed_at IS NOT NULL) AS x; -- Spec 3 W3: forum posts are gone""",
        """WHERE c.user_id = r.id AND c.removed_at IS NOT NULL
              UNION ALL
              SELECT f.removed_at FROM public.forum_posts AS f WHERE f.user_id = r.id AND f.removed_at IS NOT NULL) AS x;"""),
    'backfill_granted': (
        """REVOKE ALL ON FUNCTION private.opinion_stamp_backfill() FROM PUBLIC, anon, authenticated, service_role;
""", """REVOKE ALL ON FUNCTION private.opinion_stamp_backfill() FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION private.opinion_stamp_backfill() TO service_role;
"""),
    # Migration 4: polls and reports.
    'topic_poll_allowed': ("""  IF p_topic_id IS NOT NULL THEN
    RAISE EXCEPTION 'topic_polls_retired' USING ERRCODE = '22023';""", """  IF false THEN
    RAISE EXCEPTION 'topic_polls_retired' USING ERRCODE = '22023';"""),
    'guest_polls_closed': ('MULTI', [
        ("""REVOKE ALL ON FUNCTION public.get_post_poll(uuid, uuid) FROM PUBLIC;""",
         """REVOKE ALL ON FUNCTION public.get_post_poll(uuid, uuid) FROM PUBLIC, anon;"""),
        ("""GRANT EXECUTE ON FUNCTION public.get_post_poll(uuid, uuid) TO anon, authenticated;""",
         """GRANT EXECUTE ON FUNCTION public.get_post_poll(uuid, uuid) TO authenticated;"""),
    ]),
    'poll_parent_optional': ("""ALTER TABLE public.post_polls ALTER COLUMN opinion_id SET NOT NULL;
""", """
"""),
    'report_target_unchecked': ("""      ADD CONSTRAINT forum_reports_target_check CHECK (opinion_id IS NOT NULL OR comment_id IS NOT NULL);""",
                                """      ADD CONSTRAINT forum_reports_target_check CHECK (true);"""),
    # Migration 2: a kept object dropped with the forum ones.
    'notification_helper_dropped': ("""DROP FUNCTION IF EXISTS public.report_forum_topic(uuid, text) RESTRICT;
""", """DROP FUNCTION IF EXISTS public.report_forum_topic(uuid, text) RESTRICT;
DROP FUNCTION IF EXISTS private.enqueue_forum_notification(uuid, text, text, text, uuid, uuid, uuid) RESTRICT;
"""),
    # Migration 6: the health check's two W3 checks.
    'schema_check_blind_tables': ("""    IF pg_catalog.to_regclass(v_name) IS NOT NULL THEN""", """    IF false THEN"""),
    'schema_check_blind_columns': ("""                  AND a.attname = v_forum_columns[v_i][2] AND NOT a.attisdropped) THEN""",
                                   """                  AND false) THEN"""),
    'code_check_blind_functions': ("""         AND p.prosrc ~* v_forum_names""", """         AND false"""),
    'code_check_blind_views': ("""         AND v.definition ~ v_forum_names""", """         AND false"""),
    'code_check_blind_cron': ("""       WHERE j.command ~* v_forum_names""", """       WHERE false"""),
    # Fix round 1 (Task 2 review M-2, M-1).
    'code_check_case_functions': ("""         AND p.prosrc ~* v_forum_names""", """         AND p.prosrc ~ v_forum_names"""),
    'code_check_case_cron': ("""       WHERE j.command ~* v_forum_names""", """       WHERE j.command ~ v_forum_names"""),
    'backfill_never_keyed': ("""  IF public.dating_phone_hmac('attune:dating_exclusion_key:fingerprint:v1') IS NULL THEN
    RAISE NOTICE 'dating_exclusion_key is not set: no Opinions strike stamped';""", """  IF true THEN
    RAISE NOTICE 'dating_exclusion_key is not set: no Opinions strike stamped';"""),
    'backfill_skips_walk': ("""        PERFORM private.bump_metric_internal('opinions.enforcement.backfill_phone_unverified');
        CONTINUE;""", """        CONTINUE;"""),
}
````

```bash
D=.superpowers/sdd/2026-11-24-spec3-w3
W3_DB=attune_spec3a_w3pre python3 -I $D/mutate.py $D/w3_all.sql supabase/tests/forum_retirement_contracts.sql $D/mut_sql.py $D/mut > $D/mut_sql.txt
echo "SQL $(grep -c 'CONTRACT VIOLATED' $D/mut_sql.txt) of $(wc -l < $D/mut_sql.txt | tr -d ' ')"
python3 -I $D/rehearse.py attune_spec3a_w3pre $D/mut_reh.py | tail -1
```

Expected: `SQL 21 of 21`; `27/27 killed`. The SQL lines, as built (the last four are Task 2 fix round 1's):

```text
forum_post_branch_silent: ERROR:  CONTRACT VIOLATED: forum_post is still a content type after W3
removal_notice_lost: ERROR:  CONTRACT VIOLATED: the removal and ban notices did not survive W3
ban_notice_lost: ERROR:  CONTRACT VIOLATED: the removal and ban notices did not survive W3
topic_still_limited: ERROR:  CONTRACT VIOLATED: the retired topic kind still has a limit (daily_limit)
assert_path_public: ERROR:  CONTRACT VIOLATED: private.assert_can_post(uuid,text) is not SECURITY DEFINER with search_path ''
backfill_reads_forum_posts: ERROR:  CONTRACT VIOLATED: forum_retirement_health not ok: no_code_references_forum_schema: function private.opinion_stamp_backfill
backfill_granted: ERROR:  CONTRACT VIOLATED: the service role's grants on the moderation functions changed
topic_poll_allowed: ERROR:  CONTRACT VIOLATED: a topic poll reached the insert (null value in column "opinion_id" of relation "post_polls" violates not-null constraint)
guest_polls_closed: ERROR:  CONTRACT VIOLATED: forum_retirement_health not ok: opinions_shared_objects_present: get_post_poll(uuid,uuid) not executable by anon and authenticated
poll_parent_optional: ERROR:  CONTRACT VIOLATED: a poll or report rule Opinions needs is gone: a dedup index, or post_polls.opinion_id NOT NULL
report_target_unchecked: ERROR:  CONTRACT VIOLATED: a report naming neither an opinion nor a comment was accepted
notification_helper_dropped: ERROR:  CONTRACT VIOLATED: forum_retirement_health not ok: opinions_shared_objects_present: private.enqueue_forum_notification(uuid,text,text,text,uuid,uuid,uuid) missing
schema_check_blind_tables: ERROR:  CONTRACT VIOLATED: the health check missed a forum table
schema_check_blind_columns: ERROR:  CONTRACT VIOLATED: the health check missed forum_reports.topic_id
code_check_blind_functions: ERROR:  CONTRACT VIOLATED: the health check missed a function naming forum_posts
code_check_blind_views: ERROR:  CONTRACT VIOLATED: the health check missed a view naming topic_votes
code_check_blind_cron: ERROR:  CONTRACT VIOLATED: the health check missed a cron job naming forum_post_likes
code_check_case_functions: ERROR:  CONTRACT VIOLATED: the health check missed a function naming FORUM_TOPICS
code_check_case_cron: ERROR:  CONTRACT VIOLATED: the health check missed a cron job naming forum_post_likes
backfill_never_keyed: ERROR:  CONTRACT VIOLATED: opinion_stamp_backfill returned -1 with the key ready
backfill_skips_walk: ERROR:  CONTRACT VIOLATED: the stamp backfill did not walk F1's removals
```

- [ ] **Step 8: Record the tree (do not commit).**

---

### Task 3: The dead topic-poll lookup, the docs, every mutant again and the W3 gate (spec §6.3 "Also in W3", §7.4 W3 addition, §9; D10)

**Files:**
- Create: `$D/{edit_arch_test.py, edit_app.py, mut_dart.py, edit_docs.py, gate.sh}`
- Modify: `test/architecture/no_forum_references_test.dart` (the allowance goes), `lib/core/polls/data/repositories/poll_repository.dart` (`getPollIdsForTopics` goes; two docs), `lib/architecture/FORUM.md` (two lines), `docs/superpowers/specs/2026-10-24-forum-removal-design.md` (four `amended Spec 3 W3 build` notes)
- Test: `test/architecture/no_forum_references_test.dart`; the gate

**Interfaces:**
- Consumes: Tasks 1–2.
- Produces: `PollRepository` without `getPollIdsForTopics`; `getPollForTopic(String) → Future<PollModel?>` unchanged (always `null` now: the server matches nothing); `$D/gate.sh [db] [pre-db]`.

- [ ] **Step 1: The architecture test loses its allowance (the failing test)**

Create `.superpowers/sdd/2026-11-24-spec3-w3/edit_arch_test.py` with exactly:

````python
#!/usr/bin/env python3
# Spec 3 W3 Task 3 (§6.3 "Also in W3", §7.4 W3 addition): the architecture
# test drops its get_polls_for_topics allowance, so no Dart file may name an
# RPC W3 dropped. Exact edit (W1's file, never formatted).
import runpy
edit = runpy.run_path('.superpowers/sdd/2026-11-24-spec3-w3/anchor.py')['edit']
edit('test/architecture/no_forum_references_test.dart', [
    ("""    final hits = _hits(
      _dartFiles(['lib', 'test']),
      [
        RegExp(r'package:attune/features/forums/'),
        RegExp('\\\\b(${[...classes, ...providers].join('|')})\\\\b'),
        // A named push to a removed route compiles and then throws.
        RegExp(r'''['"](debateRoom|sideSelection|forumInsight)['"]'''),
        RegExp('[\\'"][^\\'"]*\\\\b($names)\\\\b[^\\'"]*[\\'"]'),
      ],
      // The dead topic-poll lookup goes with its RPC in W3 (§6.3).
      allow:
          (path, line) =>
              path.endsWith(
                'core/polls/data/repositories/poll_repository.dart',
              ) &&
              line.contains("'get_polls_for_topics'"),
    );
""", """    // Spec 3 W3: no allowance is left; every forum RPC is dropped.
    final hits = _hits(_dartFiles(['lib', 'test']), [
      RegExp(r'package:attune/features/forums/'),
      RegExp('\\\\b(${[...classes, ...providers].join('|')})\\\\b'),
      // A named push to a removed route compiles and then throws.
      RegExp(r'''['"](debateRoom|sideSelection|forumInsight)['"]'''),
      RegExp('[\\'"][^\\'"]*\\\\b($names)\\\\b[^\\'"]*[\\'"]'),
    ]);
"""),
], 'W3 arch test')
````

```bash
D=.superpowers/sdd/2026-11-24-spec3-w3
python3 -I $D/edit_arch_test.py
flutter test --no-pub test/architecture/no_forum_references_test.dart 2>&1 | tr '\r' '\n' | grep -oE '^ *lib/core/polls/data/repositories/poll_repository.dart:[0-9]+|Some tests failed\.' | sed 's/^ *//' | sort -u
```

Expected: `test/architecture/no_forum_references_test.dart: 1 edit(s) (W3 arch test)`; `Some tests failed.` and `lib/core/polls/data/repositories/poll_repository.dart:62` (the `'get_polls_for_topics'` call).

- [ ] **Step 2: The repository tidy-up**

Create `.superpowers/sdd/2026-11-24-spec3-w3/edit_app.py` with exactly:

````python
#!/usr/bin/env python3
# Spec 3 W3 Task 3 (§6.3 "Also in W3", D10): PollRepository loses
# getPollIdsForTopics (zero callers; its RPC get_polls_for_topics is
# dropped), and its docs say topic polls are retired. getPollForTopic stays
# (PollTarget never changes; poll_providers.dart is not touched): the
# server now answers it with no rows, so it returns null. Exact edits
# (an existing file, never formatted).
import runpy
edit = runpy.run_path('.superpowers/sdd/2026-11-24-spec3-w3/anchor.py')['edit']
edit('lib/core/polls/data/repositories/poll_repository.dart', [
    ("""/// Polls on opinions and forum topics (ATTUNE_MASTER_SPEC.md §8.11).
///
/// One repository serves both surfaces: a poll behaves identically whether it
/// hangs off an opinion or a topic, so the vote path exists once rather than
/// being duplicated per feature.
""", """/// Polls on opinions (ATTUNE_MASTER_SPEC.md §8.11).
///
/// Topic polls were retired with the forums (Spec 3): only opinions carry
/// polls now. [getPollForTopic] stays so `PollTarget` never changes; it always
/// returns null.
"""),
    ("""  /// Fetches the poll attached to a forum topic, or null if it has none.
  Future<PollModel?> getPollForTopic(String topicId) async {
""", """  /// Topic polls retired (Spec 3); always returns null. Kept so `PollTarget`
  /// never changes: the server matches nothing for a topic id.
  Future<PollModel?> getPollForTopic(String topicId) async {
"""),
    ("""  /// Which of these topics carry a poll.
  Future<Map<String, String>> getPollIdsForTopics(List<String> topicIds) async {
    if (topicIds.isEmpty) return const {};
    final rows = await _supabase.rpc(
      'get_polls_for_topics',
      params: {'p_topic_ids': topicIds},
    );
    return {
      for (final row in (rows as List).cast<Map<String, dynamic>>())
        row['topic_id'] as String: row['poll_id'] as String,
    };
  }

""", ""),
], 'W3 poll repository')
````

```bash
D=.superpowers/sdd/2026-11-24-spec3-w3
python3 -I $D/edit_app.py
flutter test --no-pub test/architecture/no_forum_references_test.dart test/core/polls 2>&1 | tr '\r' '\n' | grep -oE '\+[0-9]+( -[0-9]+)?: (All tests passed!|Some tests failed\.)' | tail -1
flutter analyze --no-pub lib/core/polls test/architecture/no_forum_references_test.dart 2>&1 | tail -1 | sed 's/ (ran in.*//'
grep -rn "getPollIdsForTopics\|get_polls_for_topics" lib | wc -l | tr -d ' '
```

Expected: `lib/core/polls/data/repositories/poll_repository.dart: 3 edit(s) (W3 poll repository)`; `+24: All tests passed!`; `No issues found!`; `0`.

- [ ] **Step 3: The Dart mutants**

Create `.superpowers/sdd/2026-11-24-spec3-w3/mut_dart.py` with exactly:

````python
# Spec 3 W3 Task 3 Dart mutants (dmut.py): each must be KILLED.
P = 'lib/core/polls/data/repositories/poll_repository.dart'
T = ['test/architecture/no_forum_references_test.dart']
MUTS = {
    'topic_rpc_back': (P, """  /// Casts a vote, or moves an existing one to a different option.
""", """  Future<void> pollIdsForTopics(List<String> ids) =>
      _supabase.rpc('get_polls_for_topics', params: {'p_topic_ids': ids});

  /// Casts a vote, or moves an existing one to a different option.
""", T),
    'forum_table_read': (P, """  /// Casts a vote, or moves an existing one to a different option.
""", """  Future<void> topicRows() => _supabase.from('forum_topics').select();

  /// Casts a vote, or moves an existing one to a different option.
""", T),
}
````

```bash
D=.superpowers/sdd/2026-11-24-spec3-w3
python3 -I $D/dmut.py $D/mut_dart.py | tail -1
```

Expected: `2/2 killed`.

- [ ] **Step 4: FORUM.md and the design spec**

Create `.superpowers/sdd/2026-11-24-spec3-w3/edit_docs.py` with exactly:

````python
#!/usr/bin/env python3
# Spec 3 W3 Task 3 (§6.3 "Also in W3"; the §1.5 amendment pattern):
# FORUM.md gets its two W3 lines (Spec 3 owns the file, §9), and the design
# spec says what W3 built where it differs (four amendment notes). Exact
# edits; nothing else in either file changes.
import runpy
edit = runpy.run_path('.superpowers/sdd/2026-11-24-spec3-w3/anchor.py')['edit']
edit('lib/architecture/FORUM.md', [
    ("""> **Forums retired 2026-10 (Spec 3):** screens and pushes removed in W1, producers stopped in W2, tables dropped in W3. §4, §7 and §8 still describe Opinions.
""", """> **Forums retired 2026-10 (Spec 3):** screens and pushes removed in W1, producers stopped in W2, tables dropped in W3. §4, §7 and §8 still describe Opinions.
>
> **Schema dropped, Spec 3 W3 (2026-11):** the 8 forum tables, 2 views and 29 functions are gone, and so are `post_polls.topic_id` and the forum columns of `forum_reports`. `forum_reports`, `enqueue_forum_notification` and the `forum_content_removed` / `forum_posting_banned` notices keep their names (they are Opinions').
"""),
    ("""## 4. FEATURE 1 — OPINIONS

""", """## 4. FEATURE 1 — OPINIONS

> **Since Spec 1 W9 (2026-11):** the six Opinions writers pass a content filter, reports have the "Someone may be at risk" reason (it reaches a person, never auto-hides), and confirmed removals queue the "Post removed" and "Posting paused" notices again.

"""),
], 'W3 FORUM.md')
S = 'docs/superpowers/specs/2026-10-24-forum-removal-design.md'
edit(S, [
    ("""RESTRICT everywhere in W3, so an unexpected dependency fails loudly instead of cascading. No function returns a view rowtype (checked).
""", """RESTRICT everywhere in W3, so an unexpected dependency fails loudly instead of cascading. No function returns a view rowtype (checked). *(amended Spec 3 W3 build: the migration opens with a preflight that stops the push before anything is dropped unless the database is the one W3 was built on: the 36-function inventory of checklist step 3, the five re-created bodies and the kept notification helper by md5 (step 4), no dependency on a forum relation or its row type but the three foreign keys, no cron job naming the forum schema, W2's health, and no Opinions strike waiting on a removed forum post without the exclusion key (migration 3 stamps those first). The six files are `20261125100000`–`20261125100050`.)*
"""),
    ("""5. **`forum_shared_function_branches.sql`**: `CREATE OR REPLACE` `private.assert_can_post` and `public.admin_confirm_content_removal`.
""", """5. **`forum_shared_function_branches.sql`**: `CREATE OR REPLACE` `private.assert_can_post` and `public.admin_confirm_content_removal`. *(amended Spec 3 W3 build: and `private.opinion_stamp_backfill()`, Spec 1 W9d's owner-run backfill, written after this spec, whose body read `forum_posts`; only that `UNION ALL` branch goes.)*
"""),
    ("""   - `no_code_references_forum_schema`: no `pg_proc.prosrc` in `public` or `private`, no `pg_views.definition` and no `cron.job.command` matches `\\m(forum_topics|forum_posts|topic_votes|topic_impressions|user_forum_sides|forum_post_likes|forum_topic_tags|forum_topic_visits|public_forum_topics|public_forum_posts)\\M`.
""", """   - `no_code_references_forum_schema`: no `pg_proc.prosrc` in `public` or `private`, no `pg_views.definition` and no `cron.job.command` matches `\\m(forum_topics|forum_posts|topic_votes|topic_impressions|user_forum_sides|forum_post_likes|forum_topic_tags|forum_topic_visits|public_forum_topics|public_forum_posts)\\M`. *(amended Spec 3 W3 build: `forum_retirement_health()` itself is left out of the scan, since it names the relations to look for them; `forum_schema_dropped` also checks `idx_scheduled_notifications_forum_activity`.)*
"""),
    ("""- **Also re-run in W3:** `account_deletion_contracts.sql`, `data_export_contracts.sql`, Spec 1 W9's `opinion_moderation_notice_contracts.sql` and `security_lockdown_contracts.sql` (edited).
""", """- **Also re-run in W3:** `account_deletion_contracts.sql`, `data_export_contracts.sql`, Spec 1 W9's `opinion_moderation_notice_contracts.sql` and `security_lockdown_contracts.sql` (edited). *(amended Spec 3 W3 build: `opinion_moderation_notice_contracts.sql` is edited too: its "kept forum branch" pin becomes "`forum_post` raises `invalid_content_type`". `dating_v2_device_contracts.sql`'s exemption (`moderation_opinions_remove` → `enqueue_forum_notification`) names two kept functions and is unchanged. Section F runs the full three-strike ladder, which Spec 1 W9b's OPN-BAN-42702 fix made possible. A rehearsal on a pre-W3 copy proves the drop with forum data present.)*
"""),
], 'W3 design spec')
````

```bash
D=.superpowers/sdd/2026-11-24-spec3-w3
python3 -I $D/edit_docs.py
grep -c 'amended Spec 3 W3 build' docs/superpowers/specs/2026-10-24-forum-removal-design.md
grep -c 'Schema dropped, Spec 3 W3\|Since Spec 1 W9 (2026-11)' lib/architecture/FORUM.md
```

Expected: `lib/architecture/FORUM.md: 2 edit(s) (W3 FORUM.md)`, `docs/superpowers/specs/2026-10-24-forum-removal-design.md: 4 edit(s) (W3 design spec)`; `4`; `2`.

- [ ] **Step 5: Every W3 mutant again, on the finished tree**

```bash
D=.superpowers/sdd/2026-11-24-spec3-w3
python3 -I $D/combine.py
W3_DB=attune_spec3a_w3pre python3 -I $D/mutate.py $D/w3_all.sql supabase/tests/forum_retirement_contracts.sql $D/mut_sql.py $D/mut | grep -c 'CONTRACT VIOLATED'
python3 -I $D/rehearse.py attune_spec3a_w3pre $D/mut_reh.py | tail -1
python3 -I $D/dmut.py $D/mut_dart.py | tail -1
```

Expected: `w3_all.sql: 6 of 6 migrations`; `21`; `27/27 killed`; `2/2 killed`.

- [ ] **Step 6: The W3 gate (wait for an idle machine for the race script)**

Create `.superpowers/sdd/2026-11-24-spec3-w3/gate.sh` with exactly:

````bash
#!/bin/bash
# Spec 3 W3 gate (W10's gate.sh, for W3). usage (repo root): gate.sh [db] [pre-db]
# db (post-W3) defaults to attune_spec3a, pre-db (the pre-W3 snapshot) to
# attune_spec3a_w3pre (the replay passes its clones). Writes $D/gate-W3.txt,
# one line per check. The race script runs on an idle scratch database built
# from <db> (dropped after).
DB=${1:-attune_spec3a}
PRE=${2:-attune_spec3a_w3pre}
D=.superpowers/sdd/2026-11-24-spec3-w3
O=$D/gate-W3.txt; : > $O
[ "$(psql -X -d "$DB" -Atc 'select current_database()')" = "$DB" ] || { echo "no database $DB" >> $O; exit 1; }
[ "$(psql -X -d "$PRE" -Atc "select to_regclass('public.forum_topics') is not null")" = "t" ] || { echo "$PRE is not a pre-W3 snapshot" >> $O; exit 1; }
H=$(date -u +%H)
$D/suite.sh "$DB" > $D/sql-W3.txt
echo "SQL $(grep -c '^PASS' $D/sql-W3.txt) PASS, $(grep -c '^FAIL' $D/sql-W3.txt) FAIL" >> $O
echo "SQL-NEW-FAILS: $(comm -13 <(grep FAIL $D/sql-baseline.txt | sort) <(grep FAIL $D/sql-W3.txt | sort) | tr '\n' ' ')" >> $O
if (( 10#$H >= 22 || 10#$H < 8 )); then
  echo "SQL-NOTE: suite run at ${H}h UTC (22:00-08:00): a quiet_hours_contracts.sql FAIL is the real clock (W8 R-T3-5); re-run it by day" >> $O
fi
for c in forum_retirement_contracts opinion_moderation_notice_contracts opinion_enforcement_records_contracts dating_v2_device_contracts dating_rls_canary; do
  echo "$c $(psql -X -q -v ON_ERROR_STOP=1 -d "$DB" -f supabase/tests/$c.sql 2>&1 | grep -oE 'all held|CONTRACT VIOLATED.*|ERROR.*' | head -1)" >> $O
done
echo "HEALTH $(psql -X -d "$DB" -Atc "select count(*) filter (where ok) || ' of ' || count(*) || ' ok' from public.forum_retirement_health()")" >> $O
echo "PRE $(psql -X -d "$PRE" -Atc "select (to_regclass('public.forum_topics') is not null)::text || ', ' || count(*) || ' health rows' from public.forum_retirement_health()")" >> $O
echo "REHEARSAL $(python3 -I $D/rehearse.py "$PRE" | tail -1 | sed 's/^REHEARSAL //')" >> $O
(cd supabase/functions && eval "$(grep -m1 -oE 'deno test --allow-read [^"]*' ../../.github/workflows/tests.yml)" 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | grep -E '^ok \||^FAILED' | tail -1) | sed 's/^/DENO /' >> $O
(cd supabase/functions && eval "$(grep -m1 -oE 'deno check --lock[^"]*' ../../.github/workflows/tests.yml)" > /dev/null 2>&1; echo "DENO-CHECK exit=$?") >> $O
flutter analyze --no-pub lib test > $D/analyze-W3.txt 2>&1; echo "ANALYZE $(tail -1 $D/analyze-W3.txt)" >> $O
echo "W10SHA $(shasum -c .superpowers/sdd/2026-11-04-spec1-w10-accessibility-docs/w10-1.0.sha | grep -vc ': OK$')" >> $O
echo "W9SHA $(shasum -c .superpowers/sdd/2026-11-04-spec1-w9/flag_off.sha | grep -vc ': OK$')" >> $O
echo "LATCH $(shasum -c .superpowers/sdd/2026-11-07-spec2-w3/latch.sha)" >> $O
flutter test --no-pub test/architecture/games_untouched_test.dart 2>&1 | tr '\r' '\n' | grep -oE 'All tests passed!|Some tests failed\.' | tail -1 | sed 's/^/GAMES /' >> $O
echo "FLAGS $(psql -X -d "$DB" -Atc "select count(*) || ' rows, ' || count(*) filter (where enabled) || ' on' from public.feature_flags")" >> $O
R=w3race_$$
dropdb --if-exists $R 2>/dev/null; createdb $R
pg_dump -s "$DB" | psql -X -q -d $R > /dev/null 2>&1
pg_dump -a -t public.metric_key_prefixes -t public.feature_flags -t public.country_safety_config -t private.dating_calling_codes \
  -t private.dating_phone_trunk_rules -t private.flag_production_gates -t public.dating_algorithm_configs \
  -t public.dating_safety_configs "$DB" | psql -X -q -d $R > /dev/null 2>&1
echo "LOAD-BEFORE-RACES $(uptime | sed 's/.*load averages*: //')" >> $O
bash scripts/concurrency/dating_kill_switch_races.sh $R > $D/race-W3.txt 2>&1
echo "RACES $(grep -c '^PASS' $D/race-W3.txt) PASS, $(grep -c '^FAIL' $D/race-W3.txt) FAIL" >> $O
dropdb $R
flutter test --no-pub --reporter compact > $D/flutter-W3.txt 2>&1
echo "FLUTTER $(tr '\r' '\n' < $D/flutter-W3.txt | grep -E '^[0-9:]+ \+[0-9]+' | tail -1 | grep -oE '\+[0-9]+( ~[0-9]+)?( -[0-9]+)?: (All tests passed!|Some tests failed\.)')" >> $O
echo "FLUTTER-FAILS:" >> $O
tr '\r' '\n' < $D/flutter-W3.txt | grep -E '\[E\][[:space:]]*$' | sed -E 's/^[0-9:]+ \+[0-9]+( ~[0-9]+)?( -[0-9]+)?: //; s#.*/test/#test/#; s/ \[E\][[:space:]]*$//' | sort -u | sed 's/^/  /' >> $O
echo DONE >> $O
cat $O
````

```bash
D=.superpowers/sdd/2026-11-24-spec3-w3
chmod +x $D/gate.sh
uptime
bash $D/gate.sh attune_spec3a attune_spec3a_w3pre
```

Expected (the replay's, run at night, so the baseline and the run both carry `quiet_hours_contracts.sql`; by day `165 PASS, 14 FAIL` and no SQL-NOTE):

```text
SQL 164 PASS, 15 FAIL
SQL-NEW-FAILS: 
SQL-NOTE: suite run at 02h UTC (22:00-08:00): a quiet_hours_contracts.sql FAIL is the real clock (W8 R-T3-5); re-run it by day
forum_retirement_contracts all held
opinion_moderation_notice_contracts all held
opinion_enforcement_records_contracts all held
dating_v2_device_contracts all held
dating_rls_canary all held
HEALTH 7 of 7 ok
PRE true, 5 health rows
REHEARSAL all held
DENO ok | 285 passed | 0 failed
DENO-CHECK exit=0
ANALYZE 571 issues found.
W10SHA 0
W9SHA 0
LATCH lib/home/home_screen.dart: OK
GAMES All tests passed!
FLAGS 46 rows, 6 on
LOAD-BEFORE-RACES 4.46 6.36 8.90
RACES 62 PASS, 0 FAIL
FLUTTER +9728 -3: Some tests failed.
FLUTTER-FAILS:
  test/accessibility/w10/healing_journal_large_text_test.dart: journal list and entry, 390 wide, text 1.0
  test/accessibility/w10/healing_journal_large_text_test.dart: journal list and entry, 390 wide, text 1.3
  test/accessibility/w10/healing_journal_large_text_test.dart: journal list and entry, 390 wide, text 2.0
DONE
```

- [ ] **Step 7: Record the tree (do not commit).**

---

## Owner checklist (nothing here is done by an implementer)

**W3 is irreversible: it deletes data and schema, and has no rollback in place (spec §6.3).** Production here means the linked Supabase project (dev/testing until the launch switch; spec House rules).

1. **⚑ Hold W3 off `main` until the go/no-go below passes (Owner question 1).** The six files sort after every migration, so the first `supabase db push` from a checkout that holds them applies the drop, whatever that push was meant for. Commit W3 on a branch (`spec3-w3-forum-drop`); merge it only for step 4.
2. **Before W3 can be pushed (the spec's gate (a)–(d), in production):**
   - (d) every earlier migration is pushed, Spec 3 W2's four (`20261025090000`–`090300`) included, with the W2 owner checklist done (`activate-topics` and `forum-quiet-check` deleted; `supabase functions list` names neither; `select * from public.forum_retirement_health();` all five `ok`). The Spec 1 and Spec 2 waves are still undeployed (their status notes): their pushes come first.
   - (c) **W2 live and quiet for 7 days (Owner question 2):** `forum_retirement_health()` all `ok` on day 0 and day 7. *(Owner 2026-11-24: no quiet-period wait, the owner is the only tester; (c) and (b) are waived, and W3 may go in the same push as the W2 migrations, its files sorting last.)*
   - (b) Supabase API logs for those 7 days: **zero** requests to `/rest/v1/rpc/` for any of the 29 names, to `/rest/v1/public_forum_*`, `/rest/v1/forum_*` (except `forum_reports`) or `/rest/v1/topic_*`.
   - (a) every test device runs a build ≥ the W1 build number recorded in the W1 checklist.
   - (e) **The Opinions strike stamps before the drop (R-W3-2; Task 2 review M-3):** the Dating keys are set before the push (hosted deploy step 1), so W9d's apply-time `opinion_stamp_backfill()` runs while `forum_posts` still exists; or `select count(*) from public.forum_posts where removed_at is not null;` is `0` in production. Otherwise an account whose strikes include forum-post removals is skipped by the backfill after W3 (fails closed).
3. **Back up, and don't commit the files (they hold data):** `supabase db dump -f backup-before-spec3-w3-schema.sql` and `supabase db dump --data-only -f backup-before-spec3-w3-data.sql`.
4. **The push.** Merge the branch, then `supabase db push`. Owner 2026-11-24: W3 goes in the same hosted deploy as the pending waves (Spec 1, Spec 2 W1–W10, Spec 3 W2); its six files sort after every other, so they apply last, after the W2 migrations. Set the Vault keys first (deploy checklist step 1, `dating_exclusion_key` included): migration 3 runs `private.opinion_stamp_backfill()` before `forum_posts` goes, so an account whose strikes include a removed forum post is stamped. The deploy script's pending count (`EXPECTED_PENDING` in `scripts/deploy/hosted_deploy.sh`) grows by 6 with W3: the owner approves that edit with the merge. Migration 1 checks first and refuses, with its reason, before anything is dropped:
   - `unexpected forum function(s) …`: production has a function W3 doesn't know; stop and add it to migration 2 (forum-only) or 5 (shared);
   - `… is not the body this wave was built from (md5 …)`: a shared function differs from the one W3 was built on (a hand edit, or a later wave); stop and rebuild migrations 4–5 from `select pg_get_functiondef('<sig>'::regprocedure);`, then migration 1's md5s (spec §6.3 "from the live definition");
   - `… depend(s) on the forum schema`: a view, policy, trigger or key outside the forum tables uses them; remove it first;
   - `Spec 3 W2 does not hold`: a forum cron is scheduled again, or an Opinions object is missing (the guest poll grant included); run the W2 checklist;
   - `cron job(s) … name the forum schema`: a hand-made cron job runs something on a forum table or one of the 29 functions; unschedule it first;
   - `… wait for their Opinions stamps, and dating_exclusion_key is not set`: set the key (deploy checklist step 1) and push again.
   In the single hosted push these refusals would come only after the 121 earlier files: the deploy script's step 0.9b (`deploy-w3.patch`, final review I-1) runs the body md5s and the inventory read-only before the push and stops there instead. Migration 3 also drops 7 tables with foreign keys to `auth.users` (a SHARE ROW EXCLUSIVE lock on it, 5 s `lock_timeout`): push at a quiet time.
   A refusal leaves W3 unapplied (earlier waves in the same push stay applied). If a later file (2–6) fails (for example `lock_timeout` on a busy `scheduled_notifications`), the earlier ones stay applied (each file is its own transaction); every state in between is safe for clients (the closed forum tables simply remain, and the forum branches fail only for the retired types nobody can call); push again at a quiet hour, each file is idempotent. **If it stops after migration 3 and before 5** (Task 2 review M-4), `admin_confirm_content_removal('forum_post', …)` and `assert_can_post(…, 'topic')` raise 42P01, and `opinion_stamp_backfill()` raises when it reaches an account it would stamp (opinion and comment paths are unaffected): re-push until all six are applied **before** running the hosted deploy's `select private.opinion_stamp_backfill();` (`docs/deploy/2026-11-24-hosted-deploy.md:393`).
5. **Verify:** `select * from public.forum_retirement_health();` → **7 rows, all `ok`**; `select * from public.scheduled_jobs_health();` → no forum job.
6. **Opinions smoke test** (on the W3 app build, which only drops a dead method and is safe with any server): post an opinion with a poll; vote from a second account (results after voting); as a guest the poll shows with hidden counts; report an opinion and a comment (a second report of the same item is quietly deduplicated); edit within 15 minutes; mute an author; open a tag page; the moderation console's Opinions queue opens.
7. **Moderation check** in the SQL editor, as the service role, on a test opinion: `select * from public.admin_confirm_content_removal('opinion', '<test opinion id>');` returns `violation_count = 1` and queues one `forum_content_removed` row for its author; `select * from public.admin_confirm_content_removal('forum_post', gen_random_uuid());` raises `invalid_content_type`.
8. **Recovery, if ever needed:** restore the two dumps into a scratch database and re-create objects by hand (spec §6.3). There is no down migration.
9. **Local databases:** `attune_spec3a` holds W3 after Task 2; the pre-W3 snapshot `attune_spec3a_w3pre` is kept for the reviewers' mutant runs; once the wave is committed, `dropdb attune_spec3a_w3pre`.
10. **CI:** the branch's `sql-contracts` job (a from-zero `supabase start`, W2 and W3 applied in order; W2's health holds there, so the preflight passes) and `Flutter analyze + tests` must be green before the merge.
11. **Stale notes elsewhere** (not W3's to edit): `docs/reviews/2026-10-24-stories-handoff.md` still names the two deleted forum functions in its deploy command (W2 step 0); the W1–W2 plan's D-2 (strike 3 failing with 42702) was fixed by Spec 1 W9b, and contract E's comment still says so (R-W3-7).

## Owner questions (each with this plan's recommended default)

1. **Branch:** keep W3 on a branch until the production go/no-go passes? — **Default: yes** (`spec3-w3-forum-drop`; any push from `main` with W3 in it drops the schema).
2. **Quiet period:** how long must W2 be live in production, with zero forum API requests, before W3 is pushed? — **Default: 7 days** (the spec's log window, gate (b)).
3. **Preflight (R-W3-1):** refuse to run when a shared body differs from the one W3 was built on, rather than overwrite it? — **Default: refuse** (re-plan migrations 4–5 from the live body).
4. **Stamp backfill (R-W3-2):** remove the `forum_posts` branch from Spec 1 W9d's `opinion_stamp_backfill()`, which the spec predates? — **Default: yes** (it fails at its next run otherwise; its result is the same without forum posts).
5. **Local application (R-W3-3):** apply W3 to `attune_spec3a` in Task 2 and keep a pre-W3 snapshot until the commit? — **Default: yes.**
6. **Contract E (R-W3-7):** leave section E byte for byte, its stale 42702 comment included? — **Default: yes** (spec: E re-runs unchanged; F runs the whole ladder).

## Spec coverage (self-review)

| Spec | Where |
|---|---|
| §6.3 gate (a)–(d) | Owner checklist 2; (c) and (d) also in migration 1's preflight (d) |
| §6.3 migration 1 `forum_drop_views.sql` (RESTRICT) | Task 1 (with the preflight, R-W3-1) |
| §6.3 migration 2 `forum_drop_functions.sql` (29, RESTRICT; the broadcast senders) | Task 1 |
| §6.3 migration 3 (i)–(vi) | Task 1 (the rehearsal: data) |
| §6.3 migration 4 (i)–(iii); V3, V7; D7, D8 | Task 2 (F2–F4, F6) |
| §6.3 migration 5; V8; R15–R17; the "before" body in the header | Task 2 (removed lines quoted verbatim; `marked_diff.py`; md5 in migration 1; F5, F6); plus `opinion_stamp_backfill` (R-W3-2) |
| §6.3 migration 6 (two checks) | Task 2 (F1; R-W3-4) |
| §6.3 "Also in W3": `security_lockdown_contracts.sql`, section F, `FORUM.md` two lines, `poll_repository.dart`, the architecture test | Tasks 2, 3 |
| §7.3 F (every bullet) and "Also re-run in W3" | Task 2 (F1–F6; the re-run list in Step 6; the gate) |
| §7.4 W3 addition | Task 3 Step 1 |
| §6.3 owner checklist 1–8 | Owner checklist 2–7 (steps 3–4 also automated, R-W3-1) |
| §8 R13, R14 (irreversible; drop order with data) | Owner checklist 1–4, 8; Task 1 rehearsal and refusals |
| §8 R8, R9 (guest polls; kept forum-named objects) | F4, F6, D; health check 5; mutants `guest_polls_closed`, `notification_helper_dropped` |
| §8 R19 (migration order) | Global Constraints (Migrations) |
| §8 R22 (the wrong local database) | Global Constraints (SQL target); R-W3-3 |
| Everything added since the spec (W9b, W9d, W7b, W8, W9, W10) | Pre-flight table "What changed since the spec was written" |

## Replay record (2026-11-24)

The plan was built in a scratch copy of the repo at `9bac1bdb` (`git archive`, so no checkout of the main tree; W10's tool folder, the W10 and W9 sha lists and the latch copied in) on a clone of `attune_spec3a` (`w3plan_build`, `createdb -T`), with a second clone kept pre-W3 as the snapshot (`w3plan_pre`). The build found and fixed six things this text now carries:

1. **A function the spec predates reads a forum table.** The production-inventory scan of the spec's owner checklist step 3, run on the clone, listed 34 functions, not 32: Spec 1 W9d's `private.opinion_stamp_backfill()` reads `forum_posts`, and `forum_retirement_health()` matches by name. After a first drop without it, `opinion_enforcement_records_contracts.sql` would fail at its first backfill call. Migration 5 now rewrites it (R-W3-2), and the preflight's inventory knows all 36 (with `get_post_poll` and `create_poll_for_post`, matched by `topic_id`).
2. **Two kept contracts pinned the forum schema:** after the drop the suite read `opinion_moderation_notice_contracts.sql` (its "kept forum branch" pin) and `security_lockdown_contracts.sql` (`forum_topic_tags`) as new FAILs; Task 2 edits one pin in each.
3. **The health check's code scan matched its own body** (it names the relations to look for them): it now leaves itself out (R-W3-4).
4. **The dependency preflight must ignore auto dependencies** (indexes, the table's own constraints, owned sequences, realtime publication membership: they go with the table); the rehearsal now puts `forum_posts` in `supabase_realtime` to prove it.
5. **`marked_diff.py` found two unmarked changed lines** in `create_poll_for_post` and `get_post_poll` (and a blank line inside a marked block); they now carry the tag, and migration 1's after-md5s were recomputed from the final bodies.
6. **The W8 push audit needs no edit:** with its exemption removed the device contract fails ("a Dating push is not neutral"), so the exemption is still needed, and both functions it names are kept (R-W3-5).

The full gate ran on the build at load 4–16 while other agents ran Flutter: everything matched except the race script (`58 PASS, 4 FAIL`, each a "(no race)" timing case none of which touches forums) and four Games test files that timed out loading (12 minutes each); those four files alone then read `+56: All tests passed!`, and the replay's gate (below) read 62/0 and only the three journal goldens.

Then the plan was **replayed from this text**: a fresh scratch copy at `9bac1bdb` (the same files copied in), a fresh clone of `attune_spec3a` (`w3replay`; Step 1 made its snapshot `w3replay_w3pre`), and W10's `replay.py`, which wrote every "Create … with exactly" block (17 files) and ran every `bash` block in order (17, the gate included), with the database name swapped for the clone's. Every Expected line matched except one, fixed here: Task 3 Step 2's last count was `1`, because the architecture test itself lists `get_polls_for_topics` among the names it forbids; the command now counts `lib` only (`0`, checked on the replayed tree). The replayed tree equals the built tree file for file (`diff -rq`; tool logs and the copied tools' docstrings aside).

| Check | Build (`w3plan_build`, `w3plan_pre`) | Replay (`w3replay`, `w3replay_w3pre`) |
|---|---|---|
| Rehearsal after Task 1 (3 migrations) | data held, 4 refusals | same |
| Rehearsal mutants | 9 / 9 killed | 9 / 9 (twice: Tasks 1, 3; and Task 2) |
| Contracts before W3 (Task 2 Step 2) | F and the notice pin red, lockdown green | same |
| Six migrations applied twice | `exit=0` ×12 | `exit=0` ×12 |
| `forum_retirement_health()` | 7 of 7 ok | 7 of 7 ok |
| `marked_diff.py` | 5 functions `OK` | 5 `OK` |
| Migration 1's after-md5s | 5 found | 5 found |
| SQL suite (wrapped, at night) | 164 / 15 → 164 / 15, no new fail | 164 / 15 → 164 / 15 |
| Named contracts (forum, notice, lockdown, enforcement, device, moderation, canary, deletion, export) | `all held` | `all held` |
| SQL mutants | 17 / 17 RED | 17 / 17 (twice) |
| Dart mutants | 2 / 2 killed | 2 / 2 (twice) |
| Deno (CI line, frozen lock) | 285 passed; `deno check` clean | same |
| `flutter analyze --no-pub lib test` | 571 | 571 |
| Races (idle scratch DB) | 58 / 4 at load 3.7–11 (timing; see above) | 62 / 0 at load 4.5 |
| Full `flutter test` | +9672 −7 at load 16 (4 Games files timed out loading; alone `+56` passed) | +9728 −3 (the three journal goldens) |
| W10 / W9 golden shas, latch, Games guard | 0 / 0 / OK / passed | same |
| Feature flags | 46 rows, 6 on | 46 rows, 6 on |

The clones (`w3plan_build`, `w3plan_pre`, `w3replay`, `w3replay_w3pre`) and the gates' race databases were dropped afterwards, and the scratch copies removed; `attune_spec3a` holds no W3 object (it was only cloned); the main tree changed only by this file.

**After the build (Tasks 1–2 fix round 1, synced in Task 3):** the table above is the pre-review replay. The reviews' fix rounds changed migrations 1, 3, 5, 6, contract F, `rehearse.py`, `mut_reh.py` and `mut_sql.py`; every "Create … with exactly" block in this plan now equals its file on disk, and the counts in the Steps are the as-built ones: rehearsal mutants 23/23 (16 refusals), SQL mutants 21/21, Dart 2/2.

**Final fix round (whole-wave review, 2026-11-24):** migration 3's pre-drop stamp trigger and the preflight (e) also fire on a live ban no stamp covers (M-4); the preflight (c) also refuses anything but the 29 that depends on the 29 (M-5). The blocks above hold both; the rehearsal has two data runs and eighteen refusals, mutants 27 / 27. Three comments that named dropped objects were reworded (M-7; comments only, exact replacements, not formatted): `lib/core/widgets/tag_picker.dart` (`attach_opinion_tags / attach_forum_topic_tags, which raise` → `attach_opinion_tags, which raises`), `lib/features/opinions/data/models/opinion_model.dart` (`opinions, comments and forum posts` → `opinions and comments`; `/ edit_forum_post` dropped), `lib/core/realtime/count_broadcast_channel.dart` (`the base tables (opinions, forum_topics, forum_posts) aren't` → `the base table (opinions) isn't`); `supabase/functions/process-scheduled-notifications/index.ts` keeps its allowlist comment (edge functions are off limits; its keys are a §1 non-goal). The deploy-script and deploy-doc edits, with a read-only pre-push probe (step 0.9b, I-1), are a ready-to-apply patch for the owner: `.superpowers/sdd/2026-11-24-spec3-w3-forum-drop/deploy-w3.patch`.

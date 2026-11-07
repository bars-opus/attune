# Spec 2 W2 (Eligibility and the gentle wait) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Healing gate with the gentle wait everywhere it occurs: gate 5 of `dating_eligibility` (the 30-day ending window of a relationship that ended on Attune, for candidates only), the Healing gate gone from its last four SQL call sites and dropped, `get_dating_eligibility()` kept as a same-shape shim until W3a, Healing no longer granting Dating (server and app), the `users.path` trigger that pauses Dating → Just for me with `path_change` (one writer per reason, D18), `get_dating_home()` v1, and D0 (the gentle-wait screen) with its private reflection and its two counters.

**Architecture:** Two batches, seven tasks, three migrations (each with its `…10` grants twin). **Batch A, server (Tasks 1-4).** Task 1 records the baselines and the "before" bodies and creates the W2 tool folder. Task 2 is migration 1 (`dating_v2_gentle_wait`: gate 5, the open date, `begin_dating_enrollment`, the candidate check and the gate cron moved onto `dating_eligibility` with the shared lock order, the bounded retry and W1's carried M-6 reason, the shim, Healing's status and message, `dating_healing_gates_hold` dropped). Task 3 is migration 2 (`dating_v2_path_pause`: the `users.path` trigger, health counters) with the race case. Task 4 is migration 3 (`dating_v2_home`: `get_dating_home` v1, the reflection table and its two RPCs, the §6.9 counters) and the Batch A gate. **Batch B, app and docs (Tasks 5-7).** Task 5 removes Dating from Healing's client and rewrites the manual's Healing, About and Dating sentences. Task 6 builds D0 (repository, providers, screen, strings, goldens). Task 7 applies the `DATING_MODE_SPEC.md` §2, §2.1, §3.1, §3.2 amendments, records the gentle-wait note in the clinical packet, and runs the W2 gate. Every SQL block below was run while writing this plan on a scratch copy of `attune_spec3a` (`createdb -T`), task by task in this order: each contract red before its migration with the message quoted, each migration and twin applied twice (`exit=0` both times), each re-created function diffed against `pg_get_functiondef` (only the lines marked `Spec 2 W2` differ), each contract green after, every mutant red with the message quoted, the race script 8/8 on a throwaway copy, and the whole contract suite with no new FAIL. Every Dart file was written and its tests (14 + 3 + the edited readiness test + the manual and Healing suites) run green in a scratch copy of the app.

**Tech Stack:** Supabase Postgres 17 (RLS; `SECURITY DEFINER` with `SET search_path = ''`; pg_cron untouched), psql, Python 3 (edit, section and mutation scripts), Flutter 3.29.1 / Riverpod 2.6 / GoRouter, `connectivity_plus` (already a dependency). Deno 2 is not touched. No new package.

**Spec:** `docs/superpowers/specs/2026-10-24-dating-mode-design.md` — §8 W2 (contents, dependencies, tests, mutants 24 and 29, the production gate); §1.3 Q12; §1.5 (the `DATING_MODE_SPEC.md` §2, §2.1, §3.1, §3.2 amendments; the clinical packet note); §2.1 (gate 5, the A-9 window predicate, "Which gates apply where", "Where the Healing predicates go", I-4); §3.0 (motion, accessibility, no local persistence, offline, errors); §3.1 (the section's states); §3.2 D0; §3.15 D0 row; §4.3 (`pause_reason`, `dating_gentle_wait_reflections`); §4.4 (Home, Gentle wait, the W2 → W3a shim, `dating_pause_on_path_change`, `dating_gentle_wait_opens_at`); §4.8 (the reflection deleted at exit); §4.9 W2; §4.10 (every row tagged W2); §6.9 (gentle-wait keys); §7.1 (`dating_v2_eligibility_contracts.sql` W2 rows); §7.5 (mutants 24, 29); §9 R7, R13, R21; §10 item 3. `docs/superpowers/specs/2026-10-24-cross-spec-review.md` I-4, I-5, A-9, A-10. Spec 1 (`docs/superpowers/specs/2026-10-24-app-flow-identity-design.md`) D18 and its `flow_paths_v2` gate. `docs/superpowers/research/2026-10-24-flow-dating-research/11-synthesis-decisions.md` T4, §2.10, Q12 (accepted as written in §12), §11 metrics (the gentle-wait evasion proxy). `lib/architecture/DATING_MODE_SPEC.md`, `lib/architecture/DATING_MODE_CLINICAL_REVIEW_PACKET.md`. Carried items from `.superpowers/sdd/2026-11-06-spec2-w1-dating-foundation/progress.md` (B10 M-6, B5 M-8, the shared lock order). Format reference: `docs/superpowers/plans/2026-11-06-spec2-w1-dating-foundation.md`.

## Global Constraints

- **Where and how.** Work in the main working tree on `main` (`/Users/user/attune`). HEAD is `23f94df5` (Spec 1, S2 W1 and S1 W9d committed). The owner may have uncommitted edits (`supabase/.temp/cli-latest`, `backup-before-planning-p2.sql` at the time of writing): never revert, stash, stage, checkout or reformat them. Every edit to an existing file is an exact replacement made by a script that asserts each anchor occurs once; if an anchor has moved because a later fix changed it, apply the same change to the current text and say so in the task report.
- **NO commits.** No `git add`, `git commit`, `git stash`, `git checkout`, `git reset`, `git rm`. Tasks end with "Run tests", not "Commit".
- **Formatting.** Never `dart format` a pre-existing file. `dart format` only the files this plan creates (Task 6's three `lib/` files and its test; Task 5's new test).
- **SQL target.** Contracts run only on `attune_spec3a`, only from the repo root, as `psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f <file>`. A contract with no top-level `BEGIN;` runs as `psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -c 'BEGIN' -f <file> -c 'ROLLBACK'` (Task 1's suite runner does this for the 22 files that need it). Confirm the target first (`psql -X -d attune_spec3a -Atc 'select current_database()'` prints `attune_spec3a`). NEVER `attune_test`. NEVER run `scripts/local_pg_setup.sh` or `scripts/local_pg_grants.sql` (tasks **edit** `scripts/local_pg_grants.sql`, never run it). The only writes to `attune_spec3a` are this plan's migration files; mutants run inside one transaction that the contract's own `ROLLBACK` ends. Scratch databases are allowed only if the task creates and drops them (`createdb -T attune_spec3a <name>` … `dropdb <name>`); the race script runs only on such a copy (it refuses `attune_spec3a` and sets database-level keys).
- **Migrations.** `20261107120000_dating_v2_gentle_wait.sql`, `20261107130000_dating_v2_path_pause.sql`, `20261107140000_dating_v2_home.sql`, each with its `…10` grants twin (P-1), later than every migration in the tree (the newest is S1 W9d's `20261107110010_opinion_enforcement_restore_grants.sql`). If `ls supabase/migrations | sort | tail -1` shows anything at or after `20261107120000` when Task 2 starts, shift all six to the next free hours, keeping their order, and change every header, `\i` line and command below to match. Each file is one `BEGIN; … COMMIT;`, idempotent (applied twice, `exit=0` both times), with `SET LOCAL lock_timeout = '5s'`. Grants are explicit: nothing reaches `anon`; `service_role` is revoked on every new function and on the new table (as S2 W1 did; health keeps its service grant); the three client RPCs are granted to `authenticated` in their twin only; server-only objects are revoked in the migration and again in the twin; `dating_rls_canary.sql` gains a row for every new object. Every re-created function starts from its LIVE body (saved from `pg_get_functiondef` in Task 1) and changes only the lines marked `-- Spec 2 W2` (plus the deletions each task names); each task diffs them. No `CREATE INDEX CONCURRENTLY`. No function names a table a later wave creates.
- **Fail-closed and safety.** Every fail-closed branch has a mutant. Comparisons are NULL-safe (`IS DISTINCT FROM`, `IS NOT TRUE`, `IS NOT FALSE`, `coalesce`; never a bare `NOT f()` or `<>` on a value that can be NULL). Inputs are pre-validated and answered (`{ok:false, reason:'invalid', field}`), never echoed by a raw constraint error. Exposure-reducing changes are never gated (clearing one's reflection needs no device or eligibility; the path pause never raises). D8 shared phones: D0's providers are keyed to the signed-in account and reset on a change; its tests hold the new account's read open and assert every frame. D20: nothing Dating is written to `SharedPreferences` or disk (no key or value contains "dating"; D0's answers live in memory until saved on the server). Nothing tells a reported or blocked person anything (`get_dating_home` reads only the person's own standing; a report or a block changes nothing it returns). Quick exit works everywhere: D0 adds no route in W2 (P-14), so the global gesture is unchanged.
- **Off limits.** In-chat Games (`test/architecture/games_untouched_test.dart` stays green), `ATTUNE_SOUL.md`, `ATTUNE_THESIS.md`, Opinions (no Opinions object, migration or contract changes), `lib/home/home_screen.dart`'s latch (byte-identical: Task 1 saves its hash, every gate compares), `set_user_path_internal` (R13: not edited), `get_public_app_config()`, `quick_exit_service.dart`, `auth_provider.dart` (read through `currentUserProvider` only), `lib/main.dart`, `app_router.dart` (P-14), Spec 1's Me files (`dating_slot.dart` and the rest, until W3a), `healing_readiness_screen.dart` (P-8), every applied migration, every edge function, the dev scripts (W2 adds no flag, so `supabase/sql/dev_enable_spec2_dating_flags.sql` is unchanged). Existing contracts are edited only where W2 changes what they pin (P-17).
- **Copy and UI.** New strings go into `lib/i10n/app_en.arb` under `dating_` through `arb_append.py` (`.superpowers/sdd/2026-10-26-spec1-w3/arb_append.py`), then `flutter gen-l10n --arb-dir=lib/i10n --template-arb-file=app_en.arb --output-dir=lib/i10n/generated --output-localization-file=app_localizations.dart --no-synthetic-package`; never S1 W2 P-9's perl fix. Never "they" for the partner (D0 says "you both"). Displayed dates go through `MyDateFormat` (`toDate`, full words). §2.3 accessibility: every new screen is under `AllowLargeText` (through `FlowFrame`), goldens at 1.0, 1.3, 2.0 and RTL (`expectFlowGoldens`), the three guidelines (`expectFlowGuidelines`); no per-caller text scaling (`InfoRowWidget` and `BottomSheetUtils` already scale above 1.0; D0 uses neither). The light error colour is `#C62828` (`AppColors.error`; D0's errors are `FlowErrorLine`, icon plus text, never colour alone). Taps in tests use `tapInReach` (`test/helpers/tap_in_reach.dart`); a missed tap is a failure (the large-text audit counts it). Any `\u` escape is written by a script (W2's strings need none: straight apostrophes only, as the rest of `app_en.arb`).
- **No deploys.** `supabase db push`, the app build, the clinician's note and the domestic-violence reviewer's read are the owner's ("Owner deploy checklist"). Don't read `.env*`, credentials or the keychain.
- **Lessons baked in.** A write and the read that checks it are separate statements (one statement sees one snapshot; Task 4's contract learned it); a subtransaction's GUC writes roll back with it, so retry stand-ins count with a temp sequence; DO blocks that contain `$f$$s$` use a named delimiter (`DO $shim$`), never `$$`; a new `ProviderScope` in the same widget test keeps the first scope's overrides, so each golden set with different overrides is its own test.
- **Regression gate at the end of each batch (Tasks 4 and 7):** every SQL contract on `attune_spec3a` shows no new FAIL against Task 1's two baseline runs (157 PASS / 14 FAIL on the scratch copy: `ai_assist_draft_share`, `ai_assistant_quota`, `ai_assistant_quota_evasion_regression`, `ai_assistant_schema`, `ai_processing_consent`, `ai_session_admit`, `ai_session_approve_activate`, `ai_session_dispatch_claim`, `ai_session_prepare`, `ai_session_purge`, `couple_map_presence`, `reminder_delivery`, `together_events`, `together_rituals`); `dating_v2_home_contracts.sql` is new and PASS; the Games test passes; the latch is unchanged; after Task 7, `flutter test` shows no new failure against Task 1's baseline and `flutter analyze` no new issue.

## Review Focus

1. **The sweep is late (A-9).** A relationship ended 30 days and an hour ago, still `ended` because `close_relationship_windows()` hasn't run. Expect introductions to be possible now (the gate reads `ended_at`, not the status), and D0 never to say "opens on" a date already past. Tests: Task 2 contract E (`after the open date, before the sweep, the reason is …`), mutants `m29_status_only` (spec mutant 29), `wait_31_days`.
2. **Two endings inside one window.** Someone's relationship ends, a second one (with someone else) starts and ends within 30 days. Expect the later ending to set the open date, and D0 to show it. Tests: Task 2 contract E (`the open date is not the latest ending + 30 days`), mutant `opens_earliest`.
3. **A long paste or emoji in a reflection answer.** Flutter counts graphemes, the server counts code points. Expect the field to stop at 500 code points (a family emoji counts as five), the counter to say so, and the server to answer `invalid` (never raise) for anything longer. Tests: Task 6 (`an answer holds at most 500 code points …`), Task 4 contract E (`repeat('é', 501)` → `{"field": "q2", "reason": "invalid"}`), mutants `save_no_length`, `save_bytes`.
4. **Another account signs in on the same phone while D0 is open with typed text.** Expect no frame to show the first account's typed or saved answers, also when the next account's read fails. Tests: Task 6 (`D8: the next account never sees …`, `D8: the next account's read fails …`).
5. **Leaving the Dating path while a country's same-gender switch runs.** Expect no deadlock to reach anyone, the path change to go through and the pause to hold (`path_change`), because the trigger takes the shared lock order. Tests: Task 3 race case `path change (Dating to Just for me) vs the country switch` (fails with 3 deadlocks when the trigger skips `dating_lock_setup`), contract I2 retries, mutants `no_lock`, `no_retry`.

## Decisions found while verifying the code (read before Task 1)

Each is a verified fact about today's code (HEAD `23f94df5`), the database or the platform, with the smallest change that keeps the spec's intent. *Changes spec intent* marks the ones the owner should see.

**Batch A (server)**

- **P-1 (three files).** §4.9 lists one W2 migration; it is three files, one per task (as W1's P-21): `20261107120000_dating_v2_gentle_wait` (gate 5, the Healing gate's call sites, the shim, Healing's server functions), `20261107130000_dating_v2_path_pause` (the `users.path` trigger, health), `20261107140000_dating_v2_home` (`get_dating_home` v1, the reflection). Each with its `…10` twin and an `\i` line in `scripts/local_pg_grants.sql`.
- **P-2 (four call sites, not five).** §2.1 names five callers of `dating_healing_gates_hold`; W1d's `activate_dating_profile` v2 already calls `dating_eligibility(…, 'setup')` instead (live body), so four remain: `get_dating_eligibility`, `begin_dating_enrollment`, `dating_candidate_is_current`, `enforce_dating_lifecycle_gates`. After Task 2 no function body names it and it is dropped (`DROP FUNCTION IF EXISTS`).
- **P-3 (gate 5 and the open date).** `private.dating_gentle_wait_opens_at(p_user)` = the latest `ended_at` + 30 days over the person's relationships (either member) that are `ended` with `ended_at > now() - 30 days`, else NULL. That is exactly Spec 3a's own window predicate (`20261018100000`, the shared space's read-only window, and Spec 1's `get_my_home_state` `ended_window`), so "you don't date while your former partner can still read your shared space" holds to the second. An `archived` space (both sealed, or either started a new relationship, or the sweep ran) is no wait. A row `ended` with a NULL `ended_at` is no wait, as for Spec 3a's window (no writer leaves it NULL: `relationship_end_internal` always sets it). Gate 5 sits between gates 4 and 6 and applies to the `candidate` scope only (`IF p_scope = 'candidate' AND … IS NOT NULL`), so setup and activation go ahead during the wait (§2.1 "Which gates apply where").
- **P-4 (`begin_dating_enrollment`).** Re-created from its live body: its four-condition gate becomes `dating_eligibility(me, 'setup') IS DISTINCT FROM 'eligible'` (so standing now includes W1's enforcement records and Spec 1's holds, and gate 2's DOB, phone and EULA); it gains the shared lock order first (`private.dating_lock_setup`), the trusted-device check (§4.4; W1c's pass-through until W4b) and the bounded 40P01/55P03/40001 retry around its one write (the W1 final ruling: every Dating writer takes the shared lock order and the retry). Its v1 consent checks, rate limit, idempotency and return shape are unchanged (W3 replaces its callers).
- **P-5 (the candidate check; B5 M-8 assessed).** `dating_candidate_is_current` = `coalesce(dating_eligibility(p) = 'eligible', false)` (default scope: gates 1-6, the gentle wait included) AND the age gate AND an active enrolment AND readiness, each NULL-safe. M-8 measured on the scratch copy: one `dating_eligibility` call ≈ 0.85 ms (2,000 calls 1.69 s), one candidate check ≈ 1.04 ms. The per-request readers that call the check (`get_my_dating_introductions`, `get_my_dating_matches`, `act_on_dating_introduction`) are bounded by their row limits. The only O(N²) caller is v1 generation (`dating_pair_passes_hard_filters` checks both members per pair), which runs weekly, only in development, and is replaced by W5a. Carried to W5a with the number: evaluate each person once per run (a temp table keyed by user), never per pair.
- **P-6 (the gate cron; W1 B10 M-6).** `enforce_dating_lifecycle_gates` (every 15 minutes) pauses an active enrolment only for the person's own state: the age gate, standing, gates 2-4 through `dating_eligibility(…, 'setup') IN ('account_unavailable', 'relationship_active')`, the relationship guard, readiness. It never pauses for the gentle wait, a closed country, the feature switch or an exclusion key that isn't ready (those already keep everyone out of generation and reads, and a mass pause would not undo itself). Every check is NULL-safe. Per person it takes the shared lock order and the bounded retry; a person whose lock conflicts three times is skipped, counted (`dating.gates.busy`, shown in health) and retried at the next run, so one person never stops the run. Each pause writes `pause_reason = coalesce(pause_reason, 'gates')`, and the `pause_reason` CHECK gains `gates` (§4.3 lists six values; *changes spec intent*: one value added, owner nod). The age trigger (`enforce_dating_age_verification_change`) still writes no reason; W4a re-creates it (carried).
- **P-7 (the shim, I-4).** `get_dating_eligibility()` keeps its exact shape and messages: `not_authenticated`, `feature_unavailable` and `relationship_active` as before, every other failure (and a NULL reason) `account_unavailable`, eligible with `age_verification_complete` (NULL-safe). It reads the `setup` scope, so a person in the gentle wait reads eligible (they may set up), and it can never answer `healing_not_complete`. W3a drops it after its `lib/` grep test.
- **P-8 (Healing's server functions; R7).** `_healing_refresh_status` makes a ready journey `completed` whatever the score and clears `eligible_for_dating_opt_in_at`; its two Dating-only reads (latest attempt, open relationship) go. `submit_healing_readiness` keeps the key `is_eligible` for the app's result screen (`healing_readiness_screen.dart`, unchanged), which now means "this check-in completed the journey" (`v_updated.status = 'completed'`, NULL-safe), and its message is `Your check-in is complete. Healing stays here whenever you want it.` (score 71+) or the unchanged below-71 words; no Dating date. The migration rewrites any `eligible_for_dating_opt_in` row to `completed` and clears every `eligible_for_dating_opt_in_at`; the CHECK keeps the value (R7). *Changes spec intent* (small): the meaning of `is_eligible` and the new message words; both go to the clinician with D0 (owner checklist 5).
- **P-9 (the path trigger; I-5, D18, R13).** `dating_pause_on_path_change()`, `AFTER UPDATE OF path ON public.users FOR EACH ROW WHEN (OLD.path IS DISTINCT FROM NEW.path)`; the body acts only when the path leaves `dating` for anything but `relationship` (Spec 1's `set_user_path_internal` pauses that one itself with `relationship`; it is not edited). It takes the shared lock order (`dating_lock_setup`, then the enrolment row before the profile row, as W1d's parked trigger), pauses an `active` or `profile_draft` enrolment with `path_change` (an enrolment already paused or suspended keeps its first reason), pauses the profile, invalidates the person's introductions, retries a lock conflict twice, and never raises: a failure is counted (`dating.path_pause.failed`, shown in health's `safety_counters_7d`) and the path change goes through. Spec 1's `identity_foundation_contracts.sql` G6 pinned "Just for me doesn't pause"; Task 3 amends it to the D18 end state (`paused/path_change`). Spec 1's `flow_paths_v2` production gate row (`Spec 2 W2 path trigger live …`) is satisfied once this is deployed (owner checklist 4).
- **P-10 (`get_dating_home` v1).** Signed in (else 42501 `not_authenticated`), STABLE, reads only the person's own rows. Order: `feature_unavailable {country}` (gate 1, including an exclusion key that isn't ready; `country` = the profile's Dating country, else the phone's calling-code country, else null) → `reverify_device` (W1c pass-through; W4b's real check) → `account_unavailable` mapped by the person's own standing to `restricted` (a live suspension, a live enforcement record for their number, an Auth ban), `hold` (a live `moderation_hold`/`under_review` restriction or an unresolved `safety_review` hold), `age_review` (an `age_review` restriction or hold), else `unavailable` → `country_closed {country}` → `region_closed {country, region, open_regions}` → `relationship_active` as `paused {pause_reason}` when enrolled-and-paused, else `unavailable` → any other or NULL reason `unavailable` (fail closed) → a `suspended` enrolment with no live restriction `unavailable` (W7a routes it) → `paused {pause_reason}` → `active` enrolment: `cool_off {first_drop_at}` while the later of the open date and `users.created_at + 72 h` is in the future, else `active` → in the wait (not active, not paused): `gentle_wait {ended_at, opens_at, next_step}` → `not_started` → `setup_in_progress {next_step}`. `first_drop_at` is the first drop at or after that moment at the person's `drop_time` (default 19:00) in the Dating country's `reference_tz` (UTC without one). *Changes spec intent:* §3.1's state list gains `unavailable` (gate-2 failures, a relationship with nothing enrolled, an unknown reason): showing "restricted" to someone whose only problem is, say, a missing EULA v2 would be false and alarming. `verifying` (W4), `ready` and Today (W5b), the restriction's category (W7a) and `away` (W8b) come with their waves, each re-creating it from its live body.
- **P-11 (the resume step).** `private.dating_next_step(p_user)` returns §3.14's step name of the first step not done: `how` (nothing started), `looking-for` (intention or attestation missing), `where` (country or region missing), `privacy` (no `profile_draft`/`active`/`paused` enrolment, or one of the three D4 consents not standing), `you`, `meet`, `children`, `photos` (< 2 approved), `prompts` (< 2 approved), `verify` (not verified, or the age gate not holding), else `preview`. Faith (D8) is optional and never blocks a resume (nothing records a skipped D8; it stays editable in Dating settings). The photo-reader tripwire in `dating_v2_setup_contracts.sql` gains this function (P-17).
- **P-12 (the reflection).** `dating_gentle_wait_reflections (user_id PK → users ON DELETE CASCADE, answers jsonb, saved_at, seen_at)`, RLS on, no API role (the service role included); a CHECK refuses any key but `q1`-`q3`, a non-string value or more than 500 characters (defence in depth). *Changes spec intent* (small): §4.3's columns gain `seen_at` (when D0 was last opened during a wait), which the two §6.9 counters need. `save_gentle_wait_reflection(p_answers)` pre-validates (an object; only `q1`-`q3`; a string or null; ≤ 500 code points) and answers `{ok:false, reason:'invalid', field}`; trims, drops blanks; saving answers goes through W1c's `private.dating_setup_guard()` (the setup lock, the trusted device, setup eligibility: `not_eligible` with Dating off or a failing gate); clearing (all blank) takes only the lock and is never gated. No idempotency key: the save is a whole-row overwrite (§4.4 gives it none). `get_my_gentle_wait_reflection()` returns `{ok, answers, saved_at, ended_at, opens_at}` (*extends spec*: the dates, so D0 needs one call) and, while the person is in the wait with Dating open to them (setup scope eligible), records `seen_at` once per ending and counts `dating.gentle_wait.seen`. The account-deletion trigger W1a created (`private.dating_carry_on_auth_user_delete`, re-created from its live body) counts `dating.gentle_wait.account_deleted_7d` when the person opened D0 in the last 7 days; it never blocks the deletion. Exit already deletes the row (W1d's `dating_exit_internal` names this table behind `to_regclass`); account deletion cascades. The row otherwise stays until exit or account deletion (owner question 2).

**Batch B (app and docs)**

- **P-13 (the manual).** §4.10 rewrites `healing_docs.dart`'s Dating topics and `about_attune_docs.dart:74` in W2. `dating_mode_docs.dart` is W3c's to replace, but two of its sentences ("only becomes available once you're eligible through Healing Mode …") become false the moment Task 2 lands and the topic is shown to everyone, so Task 5 corrects just those two sentences now (*changes spec intent*: timing only).
- **P-14 (D0 has no route in W2).** §3.14 puts every `/dating/*` route in W3a's route group with the Dating-lock redirect; a W2 route outside it would skip the lock. So D0 is `GentleWaitScreen({required VoidCallback onSetUp, VoidCallback? onBack})`, built and tested here; W3a routes it at `/dating/setup/wait` behind the lock, registers it with `TextScalePolicy` (large text) and passes `onSetUp` (the saved next step). Quick exit is the app's global gesture and needs nothing here. Device checks of D0 move to W3a (owner checklist 7).
- **P-15 (D0's client).** RPC-only `GentleWaitRepository` (`get_my_gentle_wait_reflection`, `save_gentle_wait_reflection`) on today's Supabase client (the Dating-scoped client arrives with W4b's device header), with W1's carried item 11 applied here: one silent retry when the server answers `dating:busy`. Providers: `gentleWaitAccountProvider` (the signed-in id), `gentleWaitGatewayProvider`, `gentleWaitProvider` (`autoDispose`, re-read on an account change), `datingOnlineProvider` (its own `connectivity_plus` stream: Dating imports nothing from `lib/features/chat/**`, §7.4). The screen shows data only from an `AsyncData` (a loading or failed frame never shows the last account's answers), clears its fields on an account change, and seeds them once per account. It reuses Spec 1's `FlowFrame`, `FlowPrimaryButton`, `FlowSecondaryButton` and `FlowErrorLine` (no entry animation, labels that wrap, `AllowLargeText`), as six other features already do. Each answer is a multi-line field labelled by its question (`Semantics(label: …)`, the visible question excluded so it is read once), cut at 500 code points by a formatter, with a "{count} of {max} characters" line.
- **P-16 (a second contract file).** §7.1 lists only `dating_v2_eligibility_contracts.sql` for W2; `get_dating_home` and the reflection get their own `supabase/tests/dating_v2_home_contracts.sql` (fixtures `5e2f0000-…-0000000000NN`, phones `15558705NN`, unused by every other contract). The eligibility file gains sections E-I (fixtures `5e2c…40`-`76`, as its existing scheme).
- **P-17 (shared contracts edited).** Each pins something W2 changes: `dating_mode_contracts.sql` (its candidates must now pass `dating_eligibility`: a ready exclusion key, Spec 1 DOBs, EULA v2, Ghana open, D in an open region; Task 2); `dating_rls_canary.sql` (the rows for every new object; the dropped Healing gate's row; Tasks 2-4); `identity_foundation_contracts.sql` G6 (P-9; Task 3); `service_role_grants_test.sql` (the reflection table is no API role's, like the S-5 tables; Task 4); `dating_v2_setup_contracts.sql` (the photo-reader tripwire, P-11; Task 4). `scripts/concurrency/dating_kill_switch_races.sh` gains the path-change case (Task 3).
- **P-18 (Healing's client; R7).** `ReadinessScoringService` keeps `calculateScore`, `getNextRetakeDate`, `scoringVersion` and `minimumScore` (now only the result message's threshold) and loses `isEligibleForDating`, `getEligibilityDate`, `minimumWeeks` and the date helpers; `getResultMessage(int score)` returns the server's two messages. `HealingJourney` loses `eligibleForDatingOptInAt` and `isEligibleForDating`. The repository's status list drops `eligible_for_dating_opt_in` (the migration rewrote those rows; push the migration before the build, owner checklist 1). `healing_journey_screen.dart` loses only the Dating card; W9e's support card, AI pause and D8 resets and W10's large-text and RTL work are untouched.

**Fixtures.** `dating_v2_eligibility_contracts.sql`: `5e2c0000-0000-0000-0000-0000000000NN` with NN 40-76 for W2, phones `15558702NN`; `dating_v2_home_contracts.sql`: `5e2f…`, `15558705NN`. The race script's own ids (`5e2f…`, `15558709NN`) live only on its throwaway database.

## Carried items

From S2 W1 (`.superpowers/sdd/2026-11-06-spec2-w1-dating-foundation/progress.md`):

1. **B10 M-6 (W2 part) → built, Task 2.** The gate cron writes `pause_reason = 'gates'`; the CHECK gains it; contract G pins that the cron leaves no reasonless pause. **W4a part, carried:** `enforce_dating_age_verification_change` still pauses with no reason; W4a re-creates it (with `coalesce(pause_reason, 'age_review')` and the value added to the CHECK).
2. **B5 M-8 → assessed, Task 2 (P-5); carried to W5a** with the measured cost (≈ 0.85 ms a call): generation v2 evaluates each person's eligibility once per run, set-based or into a temp table keyed by user, never per pair or inside the pair predicate.
3. **The shared lock order → built (Tasks 2-4).** The `users.path` trigger, `begin_dating_enrollment`, the gate cron and both reflection writers start with `private.dating_lock_setup`; every write that can meet the switch retries 40P01/55P03/40001 three times; the race script proves the trigger (Task 3).
4. **Carried item 11 (`dating:busy` retried once by the client) → built for D0's two RPCs (P-15); W3a applies it to the rest of the repository.**

Found here, for later batches:

5. **W3a.** Route D0 at `/dating/setup/wait` inside the Dating route group with the lock redirect, add it to `TextScalePolicy`'s audited routes, and pass `onSetUp`; move `dating_feature_flags.dart` and `dating_repository.dart` off the shim before dropping it (I-4, R21). Spec 1's Me slot shows its own gentle-wait card from `get_my_home_state().link = 'ended_window'`, which counts an `archived` space inside 30 days (both sealed) as still waiting, while gate 5 opens Dating at once; W3a's `DatingSection` reads `get_dating_home` and ends that mismatch (W2 doesn't touch Spec 1's Me files). `resume_dating_mode` and `activate_dating_profile` accept a paused enrolment whatever `users.path` is; the client shows Dating only on the Dating path.
6. **W4a.** Item 1's age trigger. **W4b.** `get_dating_home`'s `reverify_device` and both reflection RPCs' device checks become real with the trusted-device function; D0's repository moves to the Dating-scoped client.
7. **W5a/W5b.** Item 2; `get_dating_home` gains `ready` and Today (re-created from its live body) and may compute the first drop from generation's own schedule.
8. **W7a.** `get_dating_home`'s `restricted`/`hold`/`age_review` gain the category from `get_my_dating_restriction`, and the `suspended`-with-no-restriction state its route out (W1 B10 M-8).
9. **W9.** `dating_export_for_job` includes the person's own gentle-wait reflection (their own Dating data, Q17).

## Owner questions (each with a recommendation)

1. **`unavailable` as a home state (P-10).** *Recommendation:* accept. Gate-2 failures (no EULA v2, a missing DOB) and a relationship with nothing enrolled need an honest neutral state; W3a gives it the copy "Dating isn't available on this account right now." Mapping them to `restricted` would tell people they were restricted when they were not.
2. **How long a reflection is kept for someone who never sets up Dating (P-12).** Built: until they leave Dating or delete their account; they can clear it any time by saving blank answers. *Recommendation:* keep it so (it is the author's own private text, deleted at exit and with the account), and record the line in `lib/architecture/DATING_MODE_DPIA.md` §3; the alternative is a purge 90 days after the wait ends, one more cron.
3. **Owner nods.** P-6's `gates` pause reason; P-8's `is_eligible` meaning and Healing's new message (to the clinician too); P-12's `seen_at` column and the dates in `get_my_gentle_wait_reflection`; P-13's two early sentences in `dating_mode_docs.dart`.


## Interfaces this plan consumes (read from the current code; adjust here if a later fix renames one)

- **Spec 1:** `public.users (id, path IN ('relationship','dating','just_me') or NULL, path_previous, path_chosen_at, created_at, eula_accepted_at, eula_version, phone_released_at)`; `public.set_user_path_internal(p_user uuid, p_path text)` (the one path writer: `UPDATE public.users SET path …` with the row locked `FOR UPDATE`, then, on a change to `relationship` with an enrolment, `public.pause_dating_for_relationship_user(p_user)`); `public.set_my_path(p_path text, p_confirmed boolean DEFAULT false) → jsonb` (the app's; `path:confirm_pause_dating` for an unconfirmed Dating → Relationship); `public.get_my_home_state()` (its `dating` key is `private.dating_home_summary`; its `link.window_ends_at` is Spec 1's `ended_window`); `public.account_age(uuid)`, `public.account_holds (user_id, kind, resolved_at)`, `public.place_account_hold(p_user, p_kind, p_ref)`; `private.bump_metric_internal(text)` (never raises); `public.metric_counters (day, key, count)`; `private.flag_production_gates` (row `flow_paths_v2`: "Spec 2 W2 path trigger live, so Dating -> Just for me pauses Dating (D18)").
- **Spec 3a:** `public.relationships (id, user_a, user_b, status IN ('pending','active','paused','ended','archived'), ended_at, chat_archived_at, chat_archived_reason)`; `relationship_end_internal` sets `ended_at = now()`; the trigger `relationship_archive_on_new_chapter` (`AFTER UPDATE OF status … WHEN pending → active`) archives the other member's `ended` spaces; `close_relationship_windows()` archives `ended` rows past 30 days.
- **S2 W1 (live bodies saved in Task 1):** `public.dating_eligibility(p_user uuid, p_scope text DEFAULT 'candidate') → text` (`feature_unavailable` incl. the exclusion key not ready, `account_unavailable`, `relationship_active`, `country_closed`, `region_closed`, `eligible`; `eligibility:invalid_scope` 22023); `private.dating_home_summary(uuid) → jsonb {enabled, enrolled}` (not changed by W2: no enrolment state changes); `private.dating_lock_setup(uuid)` and `(uuid, text[])` (the setup advisory lock, then the person's same-gender country locks shared, before any row); `private.dating_setup_guard() → text` (signed in, the lock, `reverify_device`, `not_eligible`, else NULL); `private.dating_invalid(text) → jsonb` (`{ok:false, reason:'invalid', field}`); `public.dating_require_trusted_device() → boolean` (W1c pass-through, `true`); `private.dating_consent_granted(uuid, text)`; `public.dating_profile_complete(uuid)`, `public.dating_profile_ready(uuid)` v2; `public.dating_age_gate_holds(uuid)`; `public.dating_account_in_good_standing(uuid)`; `public.dating_has_relationship(uuid)` (pending, active, paused); `public.dating_phone_hmac_for_user(uuid)`; `public.dating_country_config(text) → country_safety_config` (`dating_enabled`, `open_regions`, `reference_tz`); `public.publish_country_config(text, jsonb)`; `private.dating_phone_country(text)`; `public.invalidate_dating_for_user(uuid, text)` (its own bounded retry); `private.dating_exit_internal(uuid, boolean)` (already deletes `dating_gentle_wait_reflections` behind `to_regclass`); `private.dating_carry_on_auth_user_delete()` (`BEFORE DELETE ON auth.users`); `public.get_dating_operational_health()` (`safety_counters_7d` key list); `private.seed_dating_exclusion_key_fingerprint()`; tables `dating_enrollments (state, pause_reason CHECK user/relationship/path_change/same_gender_switch/away/account_parked, paused_at, activated_at, exited_at)`, `dating_profiles (country_code, region_code, intention, not_married_attested_at, children_have, children_want, verification_state, profile_state)`, `dating_profile_sensitive (identity_enc, seeking_enc)`, `dating_prompts`, `dating_profile_photos`, `dating_settings (drop_time, 07:00-22:00 on the half hour)`, `dating_account_restrictions (restriction_type suspended/under_review/age_review/moderation_hold, starts_at, ends_at, lifted_at)`, `enforcement_records`, `dating_consent_events`, `dating_age_verifications` (v1 shape until W4a).
- **Today's v1 functions W2 re-creates (live bodies saved in Task 1):** `begin_dating_enrollment(text, text) → dating_enrollments`, `dating_candidate_is_current(uuid)`, `enforce_dating_lifecycle_gates() → bigint` (cron `revalidate-dating-lifecycle-gates`, `*/15 * * * *`), `get_dating_eligibility() → jsonb`, `dating_healing_gates_hold(uuid)` (dropped), `_healing_refresh_status(uuid) → healing_journeys`, `submit_healing_readiness(uuid, jsonb) → jsonb`.
- **App:** `currentUserProvider` (`lib/features/auth/providers/auth_provider.dart`); `FlowFrame`, `FlowPrimaryButton`, `FlowSecondaryButton` (`lib/features/auth/sign_up/presentation/widgets/flow_frame.dart`, `flow_buttons.dart`), `FlowErrorLine` (`flow_text_field.dart`); `MyDateFormat.toDate` (`lib/core/utils/date_formatter.dart`); `RouteNames.healingJourney` (`/healingJourney`); `BorderRadiusTokens`, `Spacing` (`lib/app/theme/design_tokens.dart`); test helpers `pumpFlowScreen`, `expectFlowGoldens`, `expectFlowGuidelines` (`test/helpers/flow_harness.dart`), `tapInReach`, `bringIntoReach` (`test/helpers/tap_in_reach.dart`), `FakeHealingRepository` (`test/features/healing/w9e/support/healing_fakes.dart`).

## Interfaces this plan produces (for W3 onward)

- **Migration 1:** `private.dating_gentle_wait_opens_at(p_user uuid) → timestamptz` (NULL = no wait); `dating_eligibility` gate 5 → `'gentle_wait'` (candidate scope only); `get_dating_eligibility()` shim (W3a drops it); `pause_reason` value `'gates'`; `dating_healing_gates_hold` gone.
- **Migration 2:** trigger `dating_pause_on_path_change` on `public.users` (function `public.dating_pause_on_path_change()`); health keys `dating.path_pause.failed`, `dating.gates.busy`.
- **Migration 3:** `public.get_dating_home() → jsonb {state, …}` with the states and data of P-10; `private.dating_next_step(uuid) → text` (§3.14 step names), `private.dating_unavailable_state(uuid) → text`, `private.dating_first_drop_at(uuid, timestamptz) → timestamptz`; table `public.dating_gentle_wait_reflections (user_id, answers, saved_at, seen_at)`; `public.save_gentle_wait_reflection(p_answers jsonb) → jsonb` (`{ok:true, saved_at}` | `{ok:false, reason:'invalid', field}` | `{ok:false, reason:'not_eligible'|'reverify_device'}`); `public.get_my_gentle_wait_reflection() → jsonb {ok, answers, saved_at, ended_at, opens_at}` (or `{ok:false, reason:'reverify_device'}`); metric keys `dating.gentle_wait.seen`, `dating.gentle_wait.account_deleted_7d`.
- **App:** `lib/features/dating/gentle_wait/gentle_wait_repository.dart` (`GentleWait`, `GentleWaitSave`, `GentleWaitUnavailable`, `GentleWaitGateway`, `GentleWaitRepository`, `gentleWaitQuestionKeys`, `gentleWaitAnswerMax`), `gentle_wait_providers.dart` (`gentleWaitAccountProvider`, `gentleWaitGatewayProvider`, `gentleWaitProvider`, `datingOnlineProvider`), `gentle_wait_screen.dart` (`GentleWaitScreen({required VoidCallback onSetUp, VoidCallback? onBack})`); ARB keys `dating_gentleWait*`, `dating_offline`, `dating_connectToSave`, `dating_errorGeneric`, `dating_retry`; `ReadinessScoringService.getResultMessage(int score)`.

## File map

**Batch A (Tasks 1-4)**
- Create `.superpowers/sdd/2026-11-07-spec2-w2/{suite.sh, mutate.py, section.py, grants_line.py, before/*.sql, sql-baseline-1.txt, sql-baseline-2.txt, latch.sha, flutter-baseline.txt}` (Task 1).
- Create `supabase/migrations/20261107120000_dating_v2_gentle_wait.sql`, `…120010_…_grants.sql`; modify `supabase/tests/dating_v2_eligibility_contracts.sql` (header; sections E-H), `supabase/tests/dating_mode_contracts.sql` (fixture), `supabase/tests/dating_rls_canary.sql`, `scripts/local_pg_grants.sql` (Task 2).
- Create `…130000_dating_v2_path_pause.sql`, `…130010_…_grants.sql`; modify `dating_v2_eligibility_contracts.sql` (sections I, I2), `supabase/tests/identity_foundation_contracts.sql` (G6), `dating_rls_canary.sql`, `scripts/concurrency/dating_kill_switch_races.sh`, `scripts/local_pg_grants.sql` (Task 3).
- Create `…140000_dating_v2_home.sql`, `…140010_…_grants.sql`, `supabase/tests/dating_v2_home_contracts.sql`; modify `dating_rls_canary.sql`, `supabase/tests/service_role_grants_test.sql`, `supabase/tests/dating_v2_setup_contracts.sql`, `scripts/local_pg_grants.sql` (Task 4).

**Batch B (Tasks 5-7)**
- Modify `lib/features/healing/domain/services/readiness_scoring_service.dart`, `lib/features/healing/data/models/healing_journey.dart`, `lib/features/healing/data/repositories/healing_repository.dart`, `lib/features/healing/presentation/screens/healing_journey_screen.dart`, `lib/app/documentations/user_manual/data/{healing_docs,about_attune_docs,dating_mode_docs}.dart`, `test/features/healing/readiness_scoring_service_test.dart`; create `test/features/healing/healing_never_gates_dating_test.dart` (Task 5).
- Create `lib/features/dating/gentle_wait/{gentle_wait_repository,gentle_wait_providers,gentle_wait_screen}.dart`, `test/features/dating/gentle_wait/gentle_wait_screen_test.dart` and its eight goldens; modify `lib/i10n/app_en.arb` and the generated `lib/i10n/generated/*` (Task 6).
- Modify `lib/architecture/DATING_MODE_SPEC.md`, `lib/architecture/DATING_MODE_CLINICAL_REVIEW_PACKET.md`, `lib/architecture/DATING_MODE_DPIA.md` (one retention line) (Task 7).

**Not edited:** `set_user_path_internal` and every other Spec 1 function, `lib/features/me/**`, `lib/app/routing/app_router.dart`, `lib/main.dart`, `quick_exit_service.dart`, `auth_provider.dart`, `healing_readiness_screen.dart`, `dating_repository.dart`, `dating_feature_flags.dart`, every other `lib/features/dating/**` file, `supabase/functions/**`, every applied migration, `supabase/sql/*`, `scripts/local_pg_setup.sh`, `scripts/local_pg_bootstrap.sql`, every contract not named above, Games, Opinions, `ATTUNE_SOUL.md`, `ATTUNE_THESIS.md`.

---

## Batch A — the server

### Task 1: Baselines, the "before" bodies, the W2 tool folder

**Files:**
- Create: `.superpowers/sdd/2026-11-07-spec2-w2/{suite.sh, mutate.py, section.py, grants_line.py, before/*.sql, sql-baseline-1.txt, sql-baseline-2.txt, latch.sha, flutter-baseline.txt}`

**Interfaces:**
- Consumes: S2 W1's `mutate.py` and `section.py` (`.superpowers/sdd/2026-11-06-spec2-w1/`), unchanged.
- Produces: `D=.superpowers/sdd/2026-11-07-spec2-w2` (every later task's `$D`); `$D/suite.sh` (the whole contract suite, wrapping the 22 files that have no top-level `BEGIN;`); the baselines every gate compares against.

- [ ] **Step 1: Confirm the target and the tree**

```bash
psql -X -d attune_spec3a -Atc "select current_database(), to_regprocedure('public.dating_healing_gates_hold(uuid)') is not null"
ls supabase/migrations | sort | tail -1
git log --oneline -1
git status --short -- lib test supabase scripts
```

Expected: `attune_spec3a|t`; `20261107110010_opinion_enforcement_restore_grants.sql`; `23f94df5 …`; at most the owner's `supabase/.temp/cli-latest`.

- [ ] **Step 2: The W2 tool folder**

```bash
D=.superpowers/sdd/2026-11-07-spec2-w2; mkdir -p $D/before
cp .superpowers/sdd/2026-11-06-spec2-w1/mutate.py .superpowers/sdd/2026-11-06-spec2-w1/section.py $D/
```

Create `$D/suite.sh` with exactly:

```bash
#!/bin/bash
# usage: suite.sh <db> ; run from repo root
db=$1
for f in supabase/tests/*.sql; do
  if grep -q -E '^BEGIN;' "$f"; then
    psql -X -q -v ON_ERROR_STOP=1 -d "$db" -f "$f" >/dev/null 2>&1 && echo "PASS $(basename "$f")" || echo "FAIL $(basename "$f")"
  else
    psql -X -q -v ON_ERROR_STOP=1 -d "$db" -c 'BEGIN' -f "$f" -c 'ROLLBACK' >/dev/null 2>&1 && echo "PASS $(basename "$f")" || echo "FAIL $(basename "$f")"
  fi
done
```

Create `$D/grants_line.py` with exactly:

```python
# usage: grants_line.py <previous last \i path> <comment> <new \i path>
import pathlib, sys
prev, comment, new = sys.argv[1], sys.argv[2], sys.argv[3]
p = pathlib.Path('scripts/local_pg_grants.sql')
s = p.read_text()
assert s.endswith('\\i ' + prev + '\n'), 'the harness does not end with ' + prev
p.write_text(s + '\n-- ' + comment + '\n\\i ' + new + '\n')
print('local_pg_grants.sql: one \\i block added')
```

```bash
chmod +x .superpowers/sdd/2026-11-07-spec2-w2/suite.sh
```

- [ ] **Step 3: Two baseline runs of the whole SQL suite**

```bash
D=.superpowers/sdd/2026-11-07-spec2-w2
for run in 1 2; do
  $D/suite.sh attune_spec3a > $D/sql-baseline-$run.txt
  echo "run $run: $(grep -c '^PASS' $D/sql-baseline-$run.txt) PASS, $(grep -c '^FAIL' $D/sql-baseline-$run.txt) FAIL"
done
diff $D/sql-baseline-1.txt $D/sql-baseline-2.txt && echo stable
```

Expected on the scratch copy (record whatever the real database prints): `run 1: 157 PASS, 14 FAIL`, `run 2: 157 PASS, 14 FAIL`, `stable` (the FAILs are the 14 of Global Constraints; every Dating contract, `identity_foundation_contracts.sql`, `account_deletion_contracts.sql`, `dormancy_contracts.sql`, `service_role_grants_test.sql` PASS).

- [ ] **Step 4: Save the live bodies W2 re-creates, the latch hash, the Flutter baseline**

```bash
D=.superpowers/sdd/2026-11-07-spec2-w2
for sig in 'public.dating_eligibility(uuid,text)' 'public.begin_dating_enrollment(text,text)' \
           'public.dating_candidate_is_current(uuid)' 'public.enforce_dating_lifecycle_gates()' \
           'public.get_dating_eligibility()' 'public._healing_refresh_status(uuid)' \
           'public.submit_healing_readiness(uuid,jsonb)' 'public.get_dating_operational_health()' \
           'private.dating_carry_on_auth_user_delete()'; do
  psql -X -d attune_spec3a -Atc "select pg_get_functiondef('$sig'::regprocedure)" > "$D/before/$sig.sql"
done
ls $D/before | wc -l
shasum -a 256 lib/home/home_screen.dart > $D/latch.sha; cat $D/latch.sha
flutter test test/architecture/games_untouched_test.dart 2>&1 | tail -1
flutter test --reporter compact > $D/flutter-baseline.txt 2>&1; tail -c 120 $D/flutter-baseline.txt
flutter analyze 2>&1 | tail -1
```

Expected: `9`; `a84bef1cd6e99cf759bcf2e7243516d34fe7c6b8d9192e5b4022702c594e3def  lib/home/home_screen.dart`; the Games test `All tests passed!`; the Flutter and analyzer totals recorded as the Task 7 baseline (S2 W1's final run: about +7232 with the two clock-dependent owner items of W1's checklist 20, and 571 analyzer issues).

### Task 2: Migration 1: gate 5, the Healing gate gone, the shim, the gate cron, Healing's server functions (§4.9 W2, §2.1, §4.10, I-4, A-9, R7; mutant 29; P-2-P-8)

**Files:**
- Create: `supabase/migrations/20261107120000_dating_v2_gentle_wait.sql`, `supabase/migrations/20261107120010_dating_v2_gentle_wait_grants.sql`, `$D/{elig_W2a.sql, edit_elig_header_T2.py, seed_T2.sql, edit_mode_contracts.py, edit_canary_T2.py, canary_T2.sql, mut_T2.py}`
- Modify: `supabase/tests/dating_v2_eligibility_contracts.sql`, `supabase/tests/dating_mode_contracts.sql`, `supabase/tests/dating_rls_canary.sql`, `scripts/local_pg_grants.sql`

**Interfaces:**
- Consumes: Task 1's `$D/before/*`; the live W1 functions of "Interfaces consumed".
- Produces: `private.dating_gentle_wait_opens_at(uuid) → timestamptz`; `dating_eligibility` gate 5 (`'gentle_wait'`, candidate scope only); `begin_dating_enrollment` (setup-scope eligibility, lock order, device check, retry); `dating_candidate_is_current` (default scope, NULL-safe); `enforce_dating_lifecycle_gates` (person's own gates, `pause_reason 'gates'`, `dating.gates.busy`); `get_dating_eligibility()` shim; `_healing_refresh_status`, `submit_healing_readiness` without Dating; `dating_healing_gates_hold` dropped.

- [ ] **Step 1: Write the failing contract sections (E, E2, F, G, H)**

Create `$D/edit_elig_header_T2.py` with exactly:

```python
import pathlib
p = pathlib.Path('supabase/tests/dating_v2_eligibility_contracts.sql')
s = p.read_text()
old = "-- W2 adds the gentle wait, the shim and the path trigger.\n"
new = ("-- W2 adds the gentle wait (E), begin and the candidate check (E2), the\n"
       "-- shim (F), the gate cron (G), Healing (H) and the path trigger (I).\n")
assert s.count(old) == 1
p.write_text(s.replace(old, new))
print('dating_v2_eligibility_contracts.sql: header names the W2 sections')
```

Create `$D/elig_W2a.sql` with exactly:

```sql
-- =====================================================================
-- E. (W2, §2.1 gate 5, A-9) The gentle wait: inside the 30-day ending
--    window of a relationship of theirs that ended here, for candidates
--    only; the window, not the status alone; both members; an archived
--    space is no wait; Healing gates nothing.
-- =====================================================================
CREATE FUNCTION pg_temp.metric(p_key text) RETURNS bigint LANGUAGE sql AS $$
  SELECT coalesce((SELECT sum(c.count) FROM public.metric_counters AS c
                    WHERE c.day = (now() AT TIME ZONE 'utc')::date AND c.key = p_key), 0)::bigint;
$$;
CREATE FUNCTION pg_temp.as_person(p uuid) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claim.sub', p::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', p, 'role', 'authenticated')::text, true);
END $$;
CREATE FUNCTION pg_temp.as_db() RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  RESET ROLE;
  PERFORM set_config('request.jwt.claim.sub', '', true);
  PERFORM set_config('request.jwt.claims', '', true);
END $$;

-- The error [p_sql] raises ('no error' when none).
CREATE FUNCTION pg_temp.error_of(p_sql text) RETURNS text LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE p_sql;
  RETURN 'no error';
EXCEPTION WHEN OTHERS THEN
  RETURN SQLERRM;
END $$;

-- [p_user] begins enrolment under key [p_key]: the error (or 'no error'),
-- then the enrolment's state, read afterwards.
CREATE FUNCTION pg_temp.begin_as(p_user uuid, p_key text) RETURNS text LANGUAGE plpgsql AS $$
DECLARE
  v text;
BEGIN
  PERFORM pg_temp.as_person(p_user);
  v := pg_temp.error_of(format('SELECT public.begin_dating_enrollment(%L, %L)', '1', p_key));
  PERFORM pg_temp.as_db();
  RETURN v || '/' || coalesce((SELECT e.state FROM public.dating_enrollments AS e WHERE e.user_id = p_user), 'none');
END $$;

CREATE FUNCTION pg_temp.enrolled(p_n text, p_state text, p_reason text DEFAULT NULL) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE
  v constant uuid := pg_temp.person(p_n);
BEGIN
  INSERT INTO public.dating_enrollments (user_id, state, pause_reason, paused_at)
  VALUES (v, p_state, p_reason, CASE WHEN p_state = 'paused' THEN now() - interval '1 day' END);
  INSERT INTO public.dating_profiles (user_id, display_name, profile_state)
  VALUES (v, 'Enrolled ' || p_n, CASE p_state WHEN 'active' THEN 'active' WHEN 'paused' THEN 'paused' ELSE 'draft' END);
  RETURN v;
END $$;

-- The enrolment's state/reason and the profile's state for [p].
CREATE FUNCTION pg_temp.pause_of(p uuid) RETURNS text LANGUAGE sql AS $$
  SELECT coalesce((SELECT e.state || '/' || coalesce(e.pause_reason, '-') FROM public.dating_enrollments AS e WHERE e.user_id = p), 'none')
         || '/' || coalesce((SELECT d.profile_state FROM public.dating_profiles AS d WHERE d.user_id = p), 'none');
$$;


DO $$
DECLARE
  v_wait constant uuid := pg_temp.person('40');
  v_wait_b constant uuid := pg_temp.person('41');
  v_past constant uuid := pg_temp.person('42');
  v_past_b constant uuid := pg_temp.person('43');
  v_sealed constant uuid := pg_temp.person('44');
  v_sealed_b constant uuid := pg_temp.person('45');
  v_solo constant uuid := pg_temp.person('46');
  v_edge constant uuid := pg_temp.person('47');
  v_edge_b constant uuid := pg_temp.person('48');
  v_two constant uuid := pg_temp.person('49');
  v_two_b constant uuid := pg_temp.person('50');
  v_two_c constant uuid := pg_temp.person('51');
  v_left constant uuid := pg_temp.person('52');
  v_moved_on constant uuid := pg_temp.person('53');
  v_new constant uuid := pg_temp.person('54');
  v_ended timestamptz;
  v_journey uuid;
  v_rel uuid;
BEGIN
  INSERT INTO public.relationships (user_a, user_b, status, ended_at) VALUES
    (v_wait, v_wait_b, 'ended', now() - interval '10 days'),
    (v_past, v_past_b, 'ended', now() - interval '30 days' - interval '1 hour'),
    (v_edge, v_edge_b, 'ended', now() - interval '30 days' + interval '1 hour'),
    (v_two, v_two_b, 'ended', now() - interval '20 days'),
    (v_two, v_two_c, 'ended', now() - interval '5 days'),
    (v_left, v_moved_on, 'ended', now() - interval '3 days');
  INSERT INTO public.relationships (user_a, user_b, status, ended_at, chat_archived_at, chat_archived_reason)
  VALUES (v_sealed, v_sealed_b, 'archived', now() - interval '2 days', now() - interval '1 day', 'both_sealed');

  -- Setup goes ahead during the wait; a candidate waits (and gate 5 comes
  -- before gate 6: with no Dating country yet the candidate's first reason
  -- is the wait).
  IF pg_temp.both(v_wait) IS DISTINCT FROM 'eligible/gentle_wait'
     OR pg_temp.both(v_wait_b) IS DISTINCT FROM 'eligible/gentle_wait' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: inside the ending window the reasons are % and % (expected eligible/gentle_wait for both members)',
      pg_temp.both(v_wait), pg_temp.both(v_wait_b);
  END IF;
  IF pg_temp.both(v_edge) IS DISTINCT FROM 'eligible/gentle_wait' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an hour before the open date the reason is % (expected eligible/gentle_wait)', pg_temp.both(v_edge);
  END IF;
  -- A-9: past ended_at + 30 days it is open, though the sweep hasn't
  -- archived the space yet (status still 'ended').
  IF pg_temp.both(v_past) IS DISTINCT FROM 'eligible/country_closed'
     OR (SELECT r.status FROM public.relationships AS r WHERE r.user_a = v_past) IS DISTINCT FROM 'ended' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: after the open date, before the sweep, the reason is % (the gate read the status, not the window)', pg_temp.both(v_past);
  END IF;
  -- Archived by both seals: open at once.
  IF pg_temp.both(v_sealed) IS DISTINCT FROM 'eligible/country_closed' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a space both sealed still holds the wait (%)', pg_temp.both(v_sealed);
  END IF;
  -- The latest ending in its window decides the open date.
  SELECT max(r.ended_at) INTO v_ended FROM public.relationships AS r WHERE r.user_a = v_two;
  IF private.dating_gentle_wait_opens_at(v_two) IS DISTINCT FROM v_ended + interval '30 days'
     OR private.dating_gentle_wait_opens_at(v_wait) IS DISTINCT FROM
        (SELECT r.ended_at FROM public.relationships AS r WHERE r.user_a = v_wait) + interval '30 days' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the open date is not the latest ending + 30 days (%, %)',
      private.dating_gentle_wait_opens_at(v_two), private.dating_gentle_wait_opens_at(v_wait);
  END IF;
  IF private.dating_gentle_wait_opens_at(v_past) IS NOT NULL OR private.dating_gentle_wait_opens_at(v_solo) IS NOT NULL
     OR private.dating_gentle_wait_opens_at(NULL) IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an open date exists with no ending in its window';
  END IF;
  -- The other member starts a new relationship: the space is archived and
  -- the wait ends for the one left behind (A-9).
  INSERT INTO public.relationships (user_a, user_b, status, invite_code, invite_expires_at)
  VALUES (v_moved_on, NULL, 'pending', 'W2GWAIT1', now() + interval '1 day') RETURNING id INTO v_rel;
  UPDATE public.relationships SET user_b = v_new, status = 'active', invite_code = NULL, invite_accepted_at = now()
   WHERE id = v_rel;
  IF (SELECT r.status FROM public.relationships AS r WHERE r.user_a = v_left) IS DISTINCT FROM 'archived'
     OR pg_temp.both(v_left) IS DISTINCT FROM 'eligible/country_closed' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: after the other member''s new relationship the reason is % (expected the wait to end)', pg_temp.both(v_left);
  END IF;
  -- An open country: the wait is the only reason; after it, eligible.
  PERFORM public.publish_country_config('GH', '{"dating_enabled": true}');
  INSERT INTO public.dating_profiles (user_id, display_name, country_code, region_code) VALUES
    (v_wait, 'Waits', 'GH', 'AA'), (v_past, 'Open', 'GH', 'AA'), (v_wait_b, 'Lagos', 'NG', NULL);
  IF pg_temp.both(v_wait) IS DISTINCT FROM 'eligible/gentle_wait' OR pg_temp.both(v_past) IS DISTINCT FROM 'eligible/eligible' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: in an open country the reasons are % and % (expected eligible/gentle_wait, eligible/eligible)',
      pg_temp.both(v_wait), pg_temp.both(v_past);
  END IF;
  IF pg_temp.both(v_wait_b) IS DISTINCT FROM 'country_closed/gentle_wait' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a closed country during the wait is % (expected country_closed/gentle_wait: gate 5 before 6)', pg_temp.both(v_wait_b);
  END IF;
  -- Healing gates nothing (§2.1): a journey with a readiness score of 10.
  INSERT INTO public.healing_journeys (user_id, breakup_at, breakup_at_source, status)
  VALUES (v_solo, now() - interval '1 day', 'user_reported', 'active') RETURNING id INTO v_journey;
  INSERT INTO public.healing_readiness_attempts (journey_id, user_id, answers, score, scoring_version)
  VALUES (v_journey, v_solo, '{}'::jsonb, 10, 'healing_readiness_v1_1');
  INSERT INTO public.dating_profiles (user_id, display_name, country_code, region_code) VALUES (v_solo, 'Solo', 'GH', 'AH');
  IF pg_temp.both(v_solo) IS DISTINCT FROM 'eligible/eligible' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a Healing readiness score of 10 gates Dating (%)', pg_temp.both(v_solo);
  END IF;
  IF to_regprocedure('public.dating_healing_gates_hold(uuid)') IS NOT NULL
     OR EXISTS (SELECT 1 FROM pg_proc AS p JOIN pg_namespace AS n ON n.oid = p.pronamespace
                 WHERE n.nspname IN ('public', 'private')
                   AND (p.prosrc LIKE '%dating_healing_gates_hold%' OR p.prosrc LIKE '%''eligible_for_dating_opt_in''%')) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the Healing gate (or a Healing Dating status writer) is still there';
  END IF;
  IF has_function_privilege('authenticated', 'private.dating_gentle_wait_opens_at(uuid)', 'EXECUTE')
     OR has_function_privilege('anon', 'private.dating_gentle_wait_opens_at(uuid)', 'EXECUTE')
     OR has_function_privilege('service_role', 'private.dating_gentle_wait_opens_at(uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the open date is callable outside the database';
  END IF;
END $$;


-- E2. (W2, §4.10) begin_dating_enrollment and the candidate check go
--     through dating_eligibility: setup begins during the wait, a candidate
--     waits, NULL never passes, and begin takes the shared lock order first
--     and retries a lock conflict.
DO $e2$
DECLARE
  v_wait constant uuid := pg_temp.id('40');
  v_past constant uuid := pg_temp.id('42');
  v_young constant uuid := pg_temp.id('02');
  v_retry constant uuid := pg_temp.person('56');
  v_device constant uuid := pg_temp.person('57');
  v_ready constant text[] := ARRAY[
    $s$CREATE OR REPLACE FUNCTION public.dating_profile_ready(p_user_id uuid) RETURNS boolean LANGUAGE sql STABLE AS $f$ SELECT true $f$$s$,
    $s$CREATE OR REPLACE FUNCTION public.dating_age_gate_holds(p_user_id uuid) RETURNS boolean LANGUAGE sql STABLE AS $f$ SELECT true $f$$s$];
  v_src text;
  v text;
BEGIN
  INSERT INTO public.dating_consent_events (user_id, idempotency_key, purpose, action, policy_version, occurred_at)
  SELECT u, 'w2-begin-' || p || '-' || right(u::text, 2), p, 'granted', '1', clock_timestamp()
    FROM unnest(ARRAY[v_wait, v_young, v_retry, v_device]) AS u, unnest(ARRAY['dating_terms', 'dating_opt_in']) AS p;
  v := pg_temp.begin_as(v_wait, 'spec2-w2-begin-0040');
  IF v IS DISTINCT FROM 'no error/profile_draft' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: during the gentle wait setup could not begin (%)', v;
  END IF;
  v := pg_temp.begin_as(v_young, 'spec2-w2-begin-0002');
  IF v IS DISTINCT FROM 'not_eligible/exited' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an under-18 account began enrolment (%)', v;
  END IF;
  v := pg_temp.probe(ARRAY[
    $s$CREATE OR REPLACE FUNCTION public.dating_require_trusted_device() RETURNS boolean LANGUAGE sql STABLE AS $f$ SELECT false $f$$s$],
    format($q$SELECT pg_temp.begin_as(%L, 'spec2-w2-begin-0057')$q$, v_device));
  IF v IS DISTINCT FROM 'reverify_device/none' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an untrusted device began enrolment (%)', v;
  END IF;
  -- Two lock conflicts on the write are retried (a sequence outlives each
  -- rolled-back savepoint).
  CREATE TEMP SEQUENCE w2_begin_calls;
  v := pg_temp.probe(ARRAY[
    $s$CREATE FUNCTION public.w2_flaky_enrolment() RETURNS trigger LANGUAGE plpgsql AS $f$
       BEGIN
         IF nextval('pg_temp.w2_begin_calls') <= 2 THEN RAISE EXCEPTION 'deadlock stand-in' USING ERRCODE = '40P01'; END IF;
         RETURN NEW;
       END $f$$s$,
    $s$CREATE TRIGGER w2_flaky BEFORE INSERT ON public.dating_enrollments FOR EACH ROW EXECUTE FUNCTION public.w2_flaky_enrolment()$s$,
    $s$SELECT 1$s$],
    format($s$SELECT pg_temp.begin_as(%L, 'spec2-w2-begin-0056') || '/' || currval('pg_temp.w2_begin_calls')$s$, v_retry));
  IF v IS DISTINCT FROM 'no error/profile_draft/3' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: two lock conflicts were not retried into an enrolment (%; expected no error/profile_draft/3)', v;
  END IF;
  v_src := (SELECT p.prosrc FROM pg_proc AS p WHERE p.oid = 'public.begin_dating_enrollment(text,text)'::regprocedure);
  IF position('private.dating_lock_setup(v_user_id)' IN v_src) = 0
     OR position('private.dating_lock_setup(v_user_id)' IN v_src) > position('dating_exclusion_key_mismatch' IN v_src) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: begin_dating_enrollment does not take the shared lock order first';
  END IF;
  -- The candidate check: the wait keeps an active, ready person out; NULL
  -- never passes.
  UPDATE public.dating_enrollments SET state = 'active' WHERE user_id = v_wait;
  INSERT INTO public.dating_enrollments (user_id, state) VALUES (v_past, 'active');
  v := pg_temp.probe(v_ready, format($q$SELECT (public.dating_candidate_is_current(%L) IS FALSE) || '/' || (public.dating_candidate_is_current(%L) IS TRUE)$q$, v_wait, v_past));
  IF v IS DISTINCT FROM 'true/true' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the candidate check ignores the gentle wait (in the wait not current, after it current: %)', v;
  END IF;
  v := pg_temp.probe(v_ready || ARRAY[
    $s$CREATE OR REPLACE FUNCTION public.dating_eligibility(p_user uuid, p_scope text DEFAULT 'candidate') RETURNS text LANGUAGE sql STABLE AS $f$ SELECT NULL::text $f$$s$],
    format($q$SELECT (public.dating_candidate_is_current(%L) IS FALSE)::text$q$, v_past));
  IF v IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a NULL eligibility made a current candidate (or a NULL answer)';
  END IF;
  v := pg_temp.probe(ARRAY[
    $s$CREATE OR REPLACE FUNCTION public.dating_profile_ready(p_user_id uuid) RETURNS boolean LANGUAGE sql STABLE AS $f$ SELECT NULL::boolean $f$$s$,
    $s$CREATE OR REPLACE FUNCTION public.dating_age_gate_holds(p_user_id uuid) RETURNS boolean LANGUAGE sql STABLE AS $f$ SELECT true $f$$s$],
    format($q$SELECT (public.dating_candidate_is_current(%L) IS FALSE)::text$q$, v_past));
  IF v IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a NULL readiness answer made a current candidate (or a NULL answer)';
  END IF;
  v := pg_temp.probe(ARRAY[
    $s$CREATE OR REPLACE FUNCTION public.dating_profile_ready(p_user_id uuid) RETURNS boolean LANGUAGE sql STABLE AS $f$ SELECT true $f$$s$,
    $s$CREATE OR REPLACE FUNCTION public.dating_age_gate_holds(p_user_id uuid) RETURNS boolean LANGUAGE sql STABLE AS $f$ SELECT NULL::boolean $f$$s$],
    format($q$SELECT (public.dating_candidate_is_current(%L) IS FALSE)::text$q$, v_past));
  IF v IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a NULL age answer made a current candidate (or a NULL answer)';
  END IF;
  UPDATE public.dating_enrollments SET state = 'profile_draft' WHERE user_id = v_wait;
  DELETE FROM public.dating_enrollments WHERE user_id = v_past;
END $e2$;

-- =====================================================================
-- F. (W2, I-4) get_dating_eligibility() is a same-shape shim over the
--    setup scope until W3a: feature_unavailable and relationship_active
--    as before, every other failure account_unavailable, never
--    healing_not_complete.
-- =====================================================================
DO $shim$
DECLARE
  v_wait constant uuid := pg_temp.id('40');
  v_solo constant uuid := pg_temp.id('46');
  v_young constant uuid := pg_temp.id('02');
  v_inviter constant uuid := pg_temp.person('55');
  v jsonb;
  v_reason text;
BEGIN
  INSERT INTO public.relationships (user_a, user_b, status, invite_code, invite_expires_at)
  VALUES (v_inviter, NULL, 'pending', 'W2SHIM01', now() + interval '1 day');
  PERFORM pg_temp.as_person(v_wait);
  v := public.get_dating_eligibility();
  PERFORM pg_temp.as_db();
  IF v IS DISTINCT FROM jsonb_build_object('is_eligible', true, 'age_verification_complete', false, 'reason', NULL,
                                           'message', 'You can opt in to Dating Mode when you are ready.') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the shim for a person in the wait (setup scope) is %', v;
  END IF;
  PERFORM pg_temp.as_person(v_solo);
  v := public.get_dating_eligibility();
  PERFORM pg_temp.as_db();
  IF v ->> 'is_eligible' IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the shim still reads Healing (%)', v;
  END IF;
  PERFORM pg_temp.as_person(v_inviter);
  v := public.get_dating_eligibility();
  PERFORM pg_temp.as_db();
  IF v IS DISTINCT FROM jsonb_build_object('is_eligible', false, 'reason', 'relationship_active',
       'message', 'Dating Mode stays unavailable while a relationship is pending or active.') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the shim with a pending relationship is %', v;
  END IF;
  PERFORM pg_temp.as_person(v_young);
  v := public.get_dating_eligibility();
  PERFORM pg_temp.as_db();
  IF v IS DISTINCT FROM jsonb_build_object('is_eligible', false, 'reason', 'account_unavailable',
       'message', 'Dating Mode is not available for this account.') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the shim for an under-18 account is %', v;
  END IF;
  UPDATE public.feature_flags SET enabled = false WHERE key = 'dating_mode_enabled';
  PERFORM pg_temp.as_person(v_wait);
  v := public.get_dating_eligibility();
  PERFORM pg_temp.as_db();
  UPDATE public.feature_flags SET enabled = true WHERE key = 'dating_mode_enabled';
  IF v IS DISTINCT FROM jsonb_build_object('is_eligible', false, 'reason', 'feature_unavailable',
       'message', 'Dating Mode is not available yet.') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the shim with the flag off is %', v;
  END IF;
  v_reason := pg_temp.probe(ARRAY[
    $s$CREATE OR REPLACE FUNCTION public.dating_eligibility(p_user uuid, p_scope text DEFAULT 'candidate') RETURNS text LANGUAGE sql STABLE AS $f$ SELECT NULL::text $f$$s$,
    format($s$SELECT pg_temp.as_person(%L)$s$, v_wait)],
    $q$SELECT public.get_dating_eligibility() ->> 'reason'$q$);
  PERFORM pg_temp.as_db();
  IF v_reason IS DISTINCT FROM 'account_unavailable' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: with a NULL eligibility the shim answered %', v_reason;
  END IF;
  IF NOT has_function_privilege('authenticated', 'public.get_dating_eligibility()', 'EXECUTE')
     OR has_function_privilege('anon', 'public.get_dating_eligibility()', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the shim''s grants changed';
  END IF;
END $shim$;

-- =====================================================================
-- G. (W2, W1 B10 M-6) The 15-minute gate cron pauses only on the person's
--    own gates (2-4, age, readiness), never on the gentle wait, a closed
--    country or the feature switch; every pause has a reason; one person's
--    lock conflict is counted and the run goes on.
-- =====================================================================
-- Runs the cron, then: how many enrolments it paused without a reason
-- (any person, M-6), and [p_people]'s states in order.
CREATE FUNCTION pg_temp.cron_states(p_people uuid[]) RETURNS text LANGUAGE plpgsql AS $$
BEGIN
  BEGIN
    PERFORM public.enforce_dating_lifecycle_gates();
  EXCEPTION WHEN OTHERS THEN
    RETURN 'raised ' || SQLSTATE || ' ' || SQLERRM;
  END;
  RETURN (SELECT count(*) FROM public.dating_enrollments AS e
           WHERE e.state = 'paused' AND e.pause_reason IS NULL AND e.updated_at = now()) || ':'
         || (SELECT string_agg(pg_temp.pause_of(x), ',' ORDER BY o) FROM unnest(p_people) WITH ORDINALITY AS t(x, o));
END $$;

DO $h$
DECLARE
  v_wait constant uuid := pg_temp.enrolled('70', 'active');
  v_held constant uuid := pg_temp.enrolled('71', 'active');
  v_closed constant uuid := pg_temp.enrolled('72', 'active');
  v_partner constant uuid := pg_temp.person('73');
  v_people uuid[];
  v_ready constant text[] := ARRAY[
    $s$CREATE OR REPLACE FUNCTION public.dating_profile_ready(p_user_id uuid) RETURNS boolean LANGUAGE sql STABLE AS $f$ SELECT true $f$$s$,
    $s$CREATE OR REPLACE FUNCTION public.dating_age_gate_holds(p_user_id uuid) RETURNS boolean LANGUAGE sql STABLE AS $f$ SELECT true $f$$s$];
  v_before bigint;
  v text;
BEGIN
  v_people := ARRAY[v_wait, v_held, v_closed];
  INSERT INTO public.relationships (user_a, user_b, status, ended_at) VALUES (v_wait, v_partner, 'ended', now() - interval '3 days');
  UPDATE public.dating_profiles SET country_code = 'GH', region_code = 'AA' WHERE user_id IN (v_wait, v_held);
  UPDATE public.dating_profiles SET country_code = 'NG' WHERE user_id = v_closed;
  PERFORM public.place_account_hold(v_held, 'safety_review', 'spec2-w2-cron');
  v := pg_temp.probe(v_ready, format('SELECT pg_temp.cron_states(%L)', v_people));
  IF v IS DISTINCT FROM '0:active/-/active,paused/gates/paused,active/-/active' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the gate cron gave % (expected only the held person paused, with the reason gates)', v;
  END IF;
  v := pg_temp.probe(v_ready || ARRAY[$s$UPDATE public.feature_flags SET enabled = false WHERE key = 'dating_mode_enabled'$s$],
                     format('SELECT pg_temp.cron_states(%L)', v_people));
  IF v IS DISTINCT FROM '0:active/-/active,paused/gates/paused,active/-/active' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: with the flag off the gate cron gave % (the switch pauses nobody; standing still does)', v;
  END IF;
  -- A NULL readiness answer never counts as ready.
  v := pg_temp.probe(ARRAY[
    $s$CREATE OR REPLACE FUNCTION public.dating_profile_ready(p_user_id uuid) RETURNS boolean LANGUAGE sql STABLE AS $f$ SELECT NULL::boolean $f$$s$,
    $s$CREATE OR REPLACE FUNCTION public.dating_age_gate_holds(p_user_id uuid) RETURNS boolean LANGUAGE sql STABLE AS $f$ SELECT true $f$$s$],
    format('SELECT pg_temp.cron_states(%L)', v_people));
  IF v IS DISTINCT FROM '0:paused/gates/paused,paused/gates/paused,paused/gates/paused' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a NULL readiness answer kept a person active (%)', v;
  END IF;
  -- Without the readiness stand-ins, an incomplete v1 profile is paused too, with a reason.
  v := pg_temp.probe(ARRAY[]::text[], format('SELECT pg_temp.cron_states(%L)', v_people));
  IF v IS DISTINCT FROM '0:paused/gates/paused,paused/gates/paused,paused/gates/paused' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: incomplete profiles gave % (expected all three paused, each with a reason)', v;
  END IF;
  -- One person's lock conflicts: counted, the run goes on.
  v_before := pg_temp.metric('dating.gates.busy');
  v := pg_temp.probe(v_ready || ARRAY[
    format($s$CREATE OR REPLACE FUNCTION public.invalidate_dating_for_user(p_user_id uuid, p_reason text DEFAULT NULL) RETURNS void
       LANGUAGE plpgsql AS $f$ BEGIN IF p_user_id = %L THEN RAISE EXCEPTION 'deadlock stand-in' USING ERRCODE = '40P01'; END IF; END $f$$s$, v_held),
    $s$UPDATE public.dating_profiles SET country_code = 'GH', region_code = 'AA' WHERE user_id = '5e2c0000-0000-0000-0000-000000000072'$s$,
    $s$SELECT public.place_account_hold('5e2c0000-0000-0000-0000-000000000072', 'age_review', 'spec2-w2-cron')$s$],
    format($s$SELECT pg_temp.cron_states(%L) || '/' || (pg_temp.metric('dating.gates.busy') - %s)$s$, v_people, v_before));
  IF v IS DISTINCT FROM '0:active/-/active,active/-/active,paused/gates/paused/1' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a lock conflict stopped the gate cron or went uncounted (%)', v;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_proc AS p WHERE p.oid = 'public.enforce_dating_lifecycle_gates()'::regprocedure
              AND (position('private.dating_lock_setup(v_user_id)' IN p.prosrc) = 0
                   OR position('private.dating_lock_setup(v_user_id)' IN p.prosrc) > position('UPDATE public.dating_enrollments' IN p.prosrc))) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the gate cron writes before the shared lock';
  END IF;
END $h$;

-- =====================================================================
-- H. (W2, R7) Healing never grants Dating: a ready journey is completed
--    whatever the score; the readiness answer names no Dating date; no row
--    keeps the old status.
-- =====================================================================
DO $i$
DECLARE
  v_high constant uuid := pg_temp.person('75');
  v_low constant uuid := pg_temp.person('76');
  v_journey uuid;
  v_low_journey uuid;
  v jsonb;
  v_low_answer jsonb;
BEGIN
  INSERT INTO public.healing_journeys (user_id, breakup_at, breakup_at_source, status, reflection_completed_at,
                                       post_mortem_status, post_mortem_completed_at, pattern_awareness_completed_at,
                                       portrait_status, portrait_completed_at)
  VALUES (v_high, now() - interval '12 weeks', 'user_reported', 'active', now(), 'completed', now(), now(), 'completed', now())
  RETURNING id INTO v_journey;
  INSERT INTO public.healing_journeys (user_id, breakup_at, breakup_at_source, status, reflection_completed_at,
                                       post_mortem_status, post_mortem_completed_at, pattern_awareness_completed_at,
                                       portrait_status, portrait_completed_at)
  VALUES (v_low, now() - interval '2 weeks', 'user_reported', 'active', now(), 'completed', now(), now(), 'completed', now())
  RETURNING id INTO v_low_journey;
  UPDATE public.healing_journeys SET eligible_for_dating_opt_in_at = now() - interval '1 day' WHERE id = v_journey;
  PERFORM pg_temp.as_person(v_high);
  v := public.submit_healing_readiness(v_journey, '{"q1":5,"q2":5,"q3":5,"q4":5,"q5":5,"q6":5,"q7":5}');
  PERFORM pg_temp.as_person(v_low);
  v_low_answer := public.submit_healing_readiness(v_low_journey, '{"q1":1,"q2":1,"q3":1,"q4":1,"q5":1,"q6":1,"q7":1}');
  PERFORM pg_temp.as_db();
  IF (SELECT j.status || '/' || (j.eligible_for_dating_opt_in_at IS NULL) FROM public.healing_journeys AS j WHERE j.id = v_journey)
     IS DISTINCT FROM 'completed/true' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a ready journey with a score of 100 is not simply completed';
  END IF;
  IF v ->> 'score' IS DISTINCT FROM '100' OR v ->> 'is_eligible' IS DISTINCT FROM 'true'
     OR v ->> 'message' IS DISTINCT FROM 'Your check-in is complete. Healing stays here whenever you want it.'
     OR v_low_answer ->> 'message' IS DISTINCT FROM 'Your answers suggest there may be more you want to explore. Go at your own pace.'
     OR (v::text || v_low_answer::text) ILIKE '%dating%' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the readiness answer still speaks of Dating (%, %)', v, v_low_answer;
  END IF;
  IF v_low_answer ->> 'is_eligible' IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: is_eligible follows the score, not the completed journey (%)', v_low_answer;
  END IF;
  IF EXISTS (SELECT 1 FROM public.healing_journeys WHERE status = 'eligible_for_dating_opt_in' OR eligible_for_dating_opt_in_at IS NOT NULL) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a journey still holds a Dating outcome';
  END IF;
END $i$;
```

```bash
D=.superpowers/sdd/2026-11-07-spec2-w2
python3 -I $D/edit_elig_header_T2.py
python3 -I $D/section.py supabase/tests/dating_v2_eligibility_contracts.sql $D/elig_W2a.sql --end
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/dating_v2_eligibility_contracts.sql 2>&1 | grep -E 'ERROR|all held' | head -1 | sed -E 's/^psql:[^ ]* //'
```

Expected: `dating_v2_eligibility_contracts.sql: header names the W2 sections`, `dating_v2_eligibility_contracts.sql: elig_W2a.sql end`, then `ERROR:  CONTRACT VIOLATED: inside the ending window the reasons are eligible/country_closed and eligible/country_closed (expected eligible/gentle_wait for both members)`.

- [ ] **Step 2: Write migration 1 and its twin**

Create `supabase/migrations/20261107120000_dating_v2_gentle_wait.sql` with exactly:

```sql
-- Spec 2 W2, migration 1 (spec §4.9 W2 #1, §2.1 gate 5 and "Where the
-- Healing predicates go", §4.10; I-4, I-14, A-9; R7; W1 B10 M-6):
--   * private.dating_gentle_wait_opens_at(p_user): the open date, the latest
--     ended_at + 30 days of a relationship of theirs that is 'ended' and
--     still inside its 30-day ending window (Spec 3a's own window predicate,
--     20261018100000); NULL when there is none (an archived space, by both
--     seals or a new relationship, is no wait). The window, not the status
--     alone, so the gate opens on the D0 date before the archive sweep runs.
--   * dating_eligibility re-created from its live body (20261106140000 with
--     its fix rounds) adding gate 5, 'gentle_wait', for the candidate scope
--     only (setup and activation go ahead during the wait).
--   * The Healing gate leaves its four remaining call sites (W1d already
--     moved activate_dating_profile): begin_dating_enrollment and the
--     candidate check go through dating_eligibility; the 15-minute gate cron
--     pauses on the person's own gates (2-4), never on the gentle wait, a
--     closed country or the feature switch, takes the shared lock order and
--     the bounded retry, and writes pause_reason 'gates' (W1 B10 M-6);
--     get_dating_eligibility() becomes the compatible shim (I-4) until W3a.
--     Then dating_healing_gates_hold is dropped.
--   * Healing no longer grants Dating (R7): a ready journey becomes
--     'completed'; submit_healing_readiness's message names no Dating date
--     and its is_eligible key now means "this check-in completed the
--     journey"; old 'eligible_for_dating_opt_in' rows become 'completed'
--     (the CHECK keeps the value) and eligible_for_dating_opt_in_at is
--     cleared.
-- Grants in 20261107120010_dating_v2_gentle_wait_grants.sql.
BEGIN;
SET LOCAL lock_timeout = '5s';

CREATE OR REPLACE FUNCTION private.dating_gentle_wait_opens_at(p_user uuid)
RETURNS timestamptz
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $fn$
  SELECT max(r.ended_at) + interval '30 days'
    FROM public.relationships AS r
   WHERE p_user IN (r.user_a, r.user_b)
     AND r.status = 'ended'
     AND r.ended_at > now() - interval '30 days';
$fn$;

CREATE OR REPLACE FUNCTION public.dating_eligibility(p_user uuid, p_scope text DEFAULT 'candidate'::text)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_profile jsonb;
  v_country text;
  v_region text;
  v_config public.country_safety_config;
BEGIN
  IF p_scope IS NULL OR p_scope NOT IN ('setup', 'candidate') THEN
    RAISE EXCEPTION 'eligibility:invalid_scope' USING ERRCODE = '22023';
  END IF;
  -- 1. Feature.
  IF public.dating_flag_enabled('dating_mode_enabled') IS NOT TRUE THEN
    RETURN 'feature_unavailable';
  END IF;
  -- 1b. (Fix round 1, I-1) Carried restrictions are readable only under a
  -- set exclusion key whose stored fingerprint matches. Otherwise nobody is
  -- eligible, under the generic system reason (never a personal one),
  -- counted best-effort (a read-only caller can't write; the refusal stands).
  IF private.dating_exclusion_key_ready() IS NOT TRUE THEN
    BEGIN
      PERFORM private.bump_metric_internal('dating.eligibility.key_not_ready');
    EXCEPTION WHEN OTHERS THEN
      NULL;
    END;
    RETURN 'feature_unavailable';
  END IF;
  -- 2. Account: an adult by Spec 1's DOB, a confirmed phone, EULA v2.
  IF p_user IS NULL
     OR coalesce(public.account_age(p_user), 0) < 18
     OR NOT EXISTS (SELECT 1 FROM auth.users AS a WHERE a.id = p_user AND a.phone_confirmed_at IS NOT NULL)
     OR NOT EXISTS (SELECT 1 FROM public.users AS u
                     WHERE u.id = p_user AND u.eula_accepted_at IS NOT NULL
                       AND coalesce(substring(u.eula_version FROM '^[0-9]{1,3}$')::integer, 0) >= 2) THEN
    RETURN 'account_unavailable';
  END IF;
  -- 3. Standing. (Fix round 1, I-1) A person whose own HMAC can't be
  -- computed under the set key can't be checked against carried records.
  IF public.dating_account_in_good_standing(p_user) IS NOT TRUE
     OR public.dating_phone_hmac_for_user(p_user) IS NULL THEN
    RETURN 'account_unavailable';
  END IF;
  -- 4. Relationship guard.
  IF public.dating_has_relationship(p_user) IS NOT FALSE THEN
    RETURN 'relationship_active';
  END IF;
  -- 5. Gentle wait (Spec 2 W2, A-9): candidates only; setup goes ahead.
  IF p_scope = 'candidate' AND private.dating_gentle_wait_opens_at(p_user) IS NOT NULL THEN -- Spec 2 W2
    RETURN 'gentle_wait'; -- Spec 2 W2
  END IF; -- Spec 2 W2
  -- 6. Country and region.
  SELECT to_jsonb(p) INTO v_profile FROM public.dating_profiles AS p WHERE p.user_id = p_user;
  v_country := v_profile ->> 'country_code';
  v_region := v_profile ->> 'region_code';
  IF v_country IS NULL THEN
    RETURN CASE WHEN p_scope = 'setup' THEN 'eligible' ELSE 'country_closed' END;
  END IF;
  v_config := public.dating_country_config(v_country);
  IF v_config IS NULL OR v_config.dating_enabled IS NOT TRUE THEN
    RETURN 'country_closed';
  END IF;
  IF v_config.open_regions IS NOT NULL
     AND (v_region IS NULL OR (v_region = ANY (v_config.open_regions)) IS NOT TRUE) THEN
    RETURN CASE WHEN v_region IS NULL AND p_scope = 'setup' THEN 'eligible' ELSE 'region_closed' END;
  END IF;
  RETURN 'eligible';
END;
$function$;

CREATE OR REPLACE FUNCTION public.begin_dating_enrollment(p_terms_version text, p_idempotency_key text)
 RETURNS dating_enrollments
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id uuid := auth.uid();
  v_enrollment public.dating_enrollments%ROWTYPE;
  v_try integer; -- Spec 2 W2
BEGIN
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'not_authenticated' USING ERRCODE='42501'; END IF;
  PERFORM private.dating_lock_setup(v_user_id); -- Spec 2 W2: the shared lock order (setup, then same-gender) before any row
  IF private.dating_exclusion_key_mismatch() THEN -- Spec 2 W1a (I-5): a different exclusion key refuses quietly, counted
    PERFORM private.bump_metric_internal('dating.exclusion_key.mismatch'); -- Spec 2 W1a
    SELECT * INTO v_enrollment FROM public.dating_enrollments WHERE user_id=v_user_id; -- Spec 2 W1a
    RETURN v_enrollment; -- Spec 2 W1a
  END IF; -- Spec 2 W1a
  IF public.dating_require_trusted_device() IS NOT TRUE THEN RAISE EXCEPTION 'reverify_device' USING ERRCODE='22023'; END IF; -- Spec 2 W2
  PERFORM public.check_dating_rate_limit('begin_enrollment',5,interval '1 day');
  IF public.dating_eligibility(v_user_id, 'setup') IS DISTINCT FROM 'eligible' THEN -- Spec 2 W2: gates 1-4 and 6 (no Healing gate; the gentle wait never blocks setup; NULL refuses)
    RAISE EXCEPTION 'not_eligible' USING ERRCODE='22023';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.dating_consent_events dce
    WHERE dce.user_id=v_user_id AND dce.purpose='dating_terms'
      AND dce.action='granted' AND dce.policy_version=p_terms_version
      AND NOT EXISTS (
        SELECT 1 FROM public.dating_consent_events later
        WHERE later.user_id=dce.user_id AND later.purpose=dce.purpose
          AND later.occurred_at>dce.occurred_at AND later.action='withdrawn'
      )
  ) THEN RAISE EXCEPTION 'terms_consent_required' USING ERRCODE='22023'; END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.dating_consent_events dce
    WHERE dce.user_id=v_user_id AND dce.purpose='dating_opt_in'
      AND dce.action='granted' AND dce.policy_version=p_terms_version
      AND NOT EXISTS (
        SELECT 1 FROM public.dating_consent_events later
        WHERE later.user_id=dce.user_id AND later.purpose=dce.purpose
          AND later.occurred_at>dce.occurred_at AND later.action='withdrawn'
      )
  ) THEN RAISE EXCEPTION 'dating_opt_in_required' USING ERRCODE='22023'; END IF;
  IF NOT public.claim_dating_idempotency('begin_dating_enrollment',p_idempotency_key) THEN
    SELECT * INTO v_enrollment FROM public.dating_enrollments WHERE user_id=v_user_id;
    RETURN v_enrollment;
  END IF;
  FOR v_try IN 1..3 LOOP -- Spec 2 W2: a lock conflict is retried (each attempt its own savepoint)
    BEGIN -- Spec 2 W2
      INSERT INTO public.dating_enrollments(user_id,state,terms_version,opted_in_at)
      VALUES(v_user_id,'profile_draft',p_terms_version,now())
      ON CONFLICT(user_id) DO UPDATE SET
        state=CASE WHEN public.dating_enrollments.state='suspended' THEN 'suspended' ELSE 'profile_draft' END,
        terms_version=EXCLUDED.terms_version,opted_in_at=now(),exited_at=NULL,updated_at=now()
      RETURNING * INTO v_enrollment;
      EXIT; -- Spec 2 W2
    EXCEPTION WHEN deadlock_detected OR lock_not_available OR serialization_failure THEN -- Spec 2 W2
      IF v_try = 3 OR SQLERRM = 'dating:busy' THEN RAISE EXCEPTION 'dating:busy' USING ERRCODE = SQLSTATE; END IF; -- Spec 2 W2
    END; -- Spec 2 W2
  END LOOP; -- Spec 2 W2
  RETURN v_enrollment;
END;
$function$;

CREATE OR REPLACE FUNCTION public.dating_candidate_is_current(p_user_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT coalesce(public.dating_eligibility(p_user_id) = 'eligible', false) -- Spec 2 W2: gates 1-6 (flag, standing, relationship, gentle wait, country) replace the flag, Healing, standing and relationship lines
    AND coalesce(public.dating_age_gate_holds(p_user_id), false) -- Spec 2 W2: NULL-safe
    AND EXISTS (
      SELECT 1 FROM public.dating_enrollments de
      WHERE de.user_id = p_user_id AND de.state = 'active'
    )
    AND coalesce(public.dating_profile_ready(p_user_id), false); -- Spec 2 W2: NULL-safe
$function$;

CREATE OR REPLACE FUNCTION public.enforce_dating_lifecycle_gates()
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_user_id uuid; v_count bigint := 0;
  v_try integer; -- Spec 2 W2
BEGIN
  FOR v_user_id IN
    SELECT de.user_id FROM public.dating_enrollments de
    WHERE de.state='active' AND (
      public.dating_age_gate_holds(de.user_id) IS NOT TRUE -- Spec 2 W2: NULL-safe
      OR public.dating_account_in_good_standing(de.user_id) IS NOT TRUE -- Spec 2 W2: NULL-safe
      OR public.dating_eligibility(de.user_id, 'setup') IN ('account_unavailable', 'relationship_active') -- Spec 2 W2: the person's own gates 2-4 replace the Healing gate; the gentle wait, a closed country and the feature switch never pause
      OR public.dating_has_relationship(de.user_id) IS NOT FALSE -- Spec 2 W2: NULL-safe
      OR public.dating_profile_ready(de.user_id) IS NOT TRUE -- Spec 2 W2: NULL-safe
    )
  LOOP
    BEGIN -- Spec 2 W2: one person's lock conflict never stops the run
      PERFORM private.dating_lock_setup(v_user_id); -- Spec 2 W2: the shared lock order (setup, then same-gender)
      FOR v_try IN 1..3 LOOP -- Spec 2 W2: a lock conflict is retried (each attempt its own savepoint)
        BEGIN -- Spec 2 W2
          UPDATE public.dating_enrollments SET state='paused',paused_at=COALESCE(paused_at,now()),
            pause_reason=COALESCE(pause_reason,'gates'),updated_at=now() -- Spec 2 W2 (W1 B10 M-6): a reason for every pause
            WHERE user_id=v_user_id AND state='active';
          IF FOUND THEN -- Spec 2 W2: counted and invalidated only when it paused
            UPDATE public.dating_profiles SET profile_state='paused',updated_at=now()
              WHERE user_id=v_user_id AND profile_state='active';
            PERFORM public.invalidate_dating_for_user(v_user_id,'scheduled_gate_revalidation');
            v_count := v_count + 1;
          END IF; -- Spec 2 W2
          EXIT; -- Spec 2 W2
        EXCEPTION WHEN deadlock_detected OR lock_not_available OR serialization_failure THEN -- Spec 2 W2
          IF v_try = 3 OR SQLERRM = 'dating:busy' THEN RAISE EXCEPTION 'dating:busy' USING ERRCODE = SQLSTATE; END IF; -- Spec 2 W2
        END; -- Spec 2 W2
      END LOOP; -- Spec 2 W2
    EXCEPTION WHEN deadlock_detected OR lock_not_available OR serialization_failure THEN -- Spec 2 W2
      PERFORM private.bump_metric_internal('dating.gates.busy'); -- Spec 2 W2: left for the next run, counted
    END; -- Spec 2 W2
  END LOOP;
  RETURN v_count;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_dating_eligibility()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_user_id uuid := auth.uid();
  v_reason text; -- Spec 2 W2
BEGIN
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('is_eligible',false,'reason','not_authenticated','message','Sign in to continue.');
  END IF;
  -- Spec 2 W2 (I-4): a compatible shim over dating_eligibility's setup scope
  -- Spec 2 W2 until W3a moves its two callers to get_dating_home and drops it.
  v_reason := public.dating_eligibility(v_user_id, 'setup'); -- Spec 2 W2
  IF v_reason IS NOT DISTINCT FROM 'feature_unavailable' THEN -- Spec 2 W2
    RETURN jsonb_build_object('is_eligible',false,'reason','feature_unavailable','message','Dating Mode is not available yet.');
  END IF;
  IF v_reason IS NOT DISTINCT FROM 'relationship_active' THEN -- Spec 2 W2
    RETURN jsonb_build_object('is_eligible',false,'reason','relationship_active','message','Dating Mode stays unavailable while a relationship is pending or active.');
  END IF;
  IF v_reason IS DISTINCT FROM 'eligible' THEN -- Spec 2 W2: every other reason, and NULL
    RETURN jsonb_build_object('is_eligible',false,'reason','account_unavailable','message','Dating Mode is not available for this account.');
  END IF;
  RETURN jsonb_build_object(
    'is_eligible',true,
    'age_verification_complete',coalesce(public.dating_age_gate_holds(v_user_id), false), -- Spec 2 W2: NULL-safe
    'reason',NULL,
    'message','You can opt in to Dating Mode when you are ready.'
  );
END;
$function$;

DROP FUNCTION IF EXISTS public.dating_healing_gates_hold(uuid);

-- W1 B10 M-6: the gate cron's pauses carry a reason.
ALTER TABLE public.dating_enrollments DROP CONSTRAINT IF EXISTS dating_enrollments_pause_reason_check;
ALTER TABLE public.dating_enrollments ADD CONSTRAINT dating_enrollments_pause_reason_check
  CHECK (pause_reason IS NULL OR pause_reason IN ('user', 'relationship', 'path_change', 'same_gender_switch',
                                                  'away', 'account_parked', 'gates'));

CREATE OR REPLACE FUNCTION public._healing_refresh_status(p_journey_id uuid)
 RETURNS healing_journeys
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_journey public.healing_journeys%ROWTYPE;
  v_ready boolean;
BEGIN
  SELECT * INTO v_journey
  FROM public.healing_journeys
  WHERE id = p_journey_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'journey_not_found' USING ERRCODE = '22023';
  END IF;

  v_ready := v_journey.reflection_completed_at IS NOT NULL
    AND v_journey.post_mortem_completed_at IS NOT NULL
    AND v_journey.pattern_awareness_completed_at IS NOT NULL
    AND v_journey.portrait_completed_at IS NOT NULL
    AND v_journey.readiness_stage_completed_at IS NOT NULL;

  IF v_ready THEN
    -- Spec 2 W2 (§2.1, R7): Healing never grants Dating; a ready journey is
    -- Spec 2 W2 complete, whatever the check-in score.
    UPDATE public.healing_journeys
    SET status = 'completed', -- Spec 2 W2
        completed_at = COALESCE(completed_at, now()),
        eligible_for_dating_opt_in_at = NULL -- Spec 2 W2
    WHERE id = p_journey_id
    RETURNING * INTO v_journey;
  END IF;

  RETURN v_journey;
END;
$function$;

CREATE OR REPLACE FUNCTION public.submit_healing_readiness(p_journey_id uuid, p_answers jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_user_id uuid := auth.uid();
  v_journey public.healing_journeys%ROWTYPE;
  v_latest public.healing_readiness_attempts%ROWTYPE;
  v_score integer;
  v_attempt_id uuid;
  v_updated public.healing_journeys%ROWTYPE;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'authentication_required' USING ERRCODE = '28000';
  END IF;

  SELECT * INTO v_journey
  FROM public.healing_journeys
  WHERE id = p_journey_id
    AND user_id = v_user_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'journey_not_found' USING ERRCODE = '22023';
  END IF;
  IF v_journey.portrait_completed_at IS NULL THEN
    RAISE EXCEPTION 'portrait_not_complete' USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_latest
  FROM public.healing_readiness_attempts
  WHERE journey_id = p_journey_id
  ORDER BY submitted_at DESC
  LIMIT 1;

  IF FOUND AND now() < (v_latest.submitted_at + interval '7 days') THEN
    RAISE EXCEPTION 'readiness_cooldown_active' USING ERRCODE = '22023';
  END IF;

  v_score := public._healing_score_from_answers(p_answers);

  INSERT INTO public.healing_readiness_attempts (
    journey_id,
    user_id,
    answers,
    score,
    scoring_version
  ) VALUES (
    p_journey_id,
    v_user_id,
    p_answers,
    v_score,
    'healing_readiness_v1_1'
  )
  RETURNING id INTO v_attempt_id;

  UPDATE public.healing_journeys
  SET readiness_stage_completed_at = COALESCE(readiness_stage_completed_at, now()),
      current_stage = 5
  WHERE id = p_journey_id;

  v_updated := public._healing_refresh_status(p_journey_id);

  RETURN jsonb_build_object(
    'score', v_score,
    'is_eligible', coalesce(v_updated.status = 'completed', false), -- Spec 2 W2: kept for the app's result screen; it now means the journey is complete (no Dating outcome)
    'attempt_id', v_attempt_id,
    'message', CASE
      WHEN v_score <= 70 THEN 'Your answers suggest there may be more you want to explore. Go at your own pace.'
      ELSE 'Your check-in is complete. Healing stays here whenever you want it.' -- Spec 2 W2: no Dating date
    END
  );
END;
$function$;

-- R7: no journey keeps a Dating outcome.
UPDATE public.healing_journeys
   SET status = CASE WHEN status = 'eligible_for_dating_opt_in' THEN 'completed' ELSE status END,
       eligible_for_dating_opt_in_at = NULL
 WHERE status = 'eligible_for_dating_opt_in' OR eligible_for_dating_opt_in_at IS NOT NULL;

REVOKE ALL ON FUNCTION private.dating_gentle_wait_opens_at(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.dating_eligibility(uuid, text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.dating_candidate_is_current(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.enforce_dating_lifecycle_gates() FROM PUBLIC, anon, authenticated, service_role;

COMMIT;
```

Create `supabase/migrations/20261107120010_dating_v2_gentle_wait_grants.sql` with exactly:

```sql
-- Spec 2 W2: grants for 20261107120000_dating_v2_gentle_wait.sql.
-- The open date, the eligibility, the candidate check and the gate cron are
-- the database's own (no API role, the service role included); the two app
-- RPCs keep exactly their W1 grants (authenticated only); Healing's two
-- functions keep theirs (the app's readiness submit; the internal refresh).
BEGIN;
SET LOCAL lock_timeout = '5s';
REVOKE ALL ON FUNCTION private.dating_gentle_wait_opens_at(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.dating_eligibility(uuid, text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.dating_candidate_is_current(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.enforce_dating_lifecycle_gates() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.begin_dating_enrollment(text, text) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.begin_dating_enrollment(text, text) TO authenticated;
REVOKE ALL ON FUNCTION public.get_dating_eligibility() FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.get_dating_eligibility() TO authenticated;
COMMIT;
```

- [ ] **Step 3: Apply each file twice; diff the re-created bodies; run the contract**

```bash
for i in 1 2; do
  for f in 20261107120000_dating_v2_gentle_wait 20261107120010_dating_v2_gentle_wait_grants; do
    psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/migrations/$f.sql > /dev/null 2>&1; echo "$f exit=$?"
  done
done
D=.superpowers/sdd/2026-11-07-spec2-w2
for sig in 'public.dating_eligibility(uuid,text)' 'public.begin_dating_enrollment(text,text)' 'public.dating_candidate_is_current(uuid)' \
           'public.enforce_dating_lifecycle_gates()' 'public.get_dating_eligibility()' 'public._healing_refresh_status(uuid)' \
           'public.submit_healing_readiness(uuid,jsonb)'; do
  echo "== $sig"; diff "$D/before/$sig.sql" <(psql -X -d attune_spec3a -Atc "select pg_get_functiondef('$sig'::regprocedure)") | grep '^[<>]'
done
psql -X -d attune_spec3a -Atc "select to_regprocedure('public.dating_healing_gates_hold(uuid)')"
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/dating_v2_eligibility_contracts.sql 2>&1 | grep -E 'ERROR|all held' | head -1 | sed -E 's/^psql:[^ ]* //'
```

Expected: four `exit=0` lines (the second apply also prints `NOTICE: function public.dating_healing_gates_hold(uuid) does not exist, skipping`, hidden here); then exactly this diff (each `>` line carries `Spec 2 W2`; each `<` line is a replaced or removed Dating-only line):

```text
== public.dating_eligibility(uuid,text)
>   -- 5. Gentle wait (Spec 2 W2, A-9): candidates only; setup goes ahead.
>   IF p_scope = 'candidate' AND private.dating_gentle_wait_opens_at(p_user) IS NOT NULL THEN -- Spec 2 W2
>     RETURN 'gentle_wait'; -- Spec 2 W2
>   END IF; -- Spec 2 W2
== public.begin_dating_enrollment(text,text)
>   v_try integer; -- Spec 2 W2
>   PERFORM private.dating_lock_setup(v_user_id); -- Spec 2 W2: the shared lock order (setup, then same-gender) before any row
>   IF public.dating_require_trusted_device() IS NOT TRUE THEN RAISE EXCEPTION 'reverify_device' USING ERRCODE='22023'; END IF; -- Spec 2 W2
<   IF NOT public.dating_flag_enabled('dating_mode_enabled')
<      OR NOT public.dating_healing_gates_hold(v_user_id)
<      OR public.dating_has_relationship(v_user_id)
<      OR NOT public.dating_account_in_good_standing(v_user_id) THEN
>   IF public.dating_eligibility(v_user_id, 'setup') IS DISTINCT FROM 'eligible' THEN -- Spec 2 W2: gates 1-4 and 6 (no Healing gate; the gentle wait never blocks setup; NULL refuses)
<   INSERT INTO public.dating_enrollments(user_id,state,terms_version,opted_in_at)
<   VALUES(v_user_id,'profile_draft',p_terms_version,now())
<   ON CONFLICT(user_id) DO UPDATE SET
<     state=CASE WHEN public.dating_enrollments.state='suspended' THEN 'suspended' ELSE 'profile_draft' END,
<     terms_version=EXCLUDED.terms_version,opted_in_at=now(),exited_at=NULL,updated_at=now()
<   RETURNING * INTO v_enrollment;
>   FOR v_try IN 1..3 LOOP -- Spec 2 W2: a lock conflict is retried (each attempt its own savepoint)
>     BEGIN -- Spec 2 W2
>       INSERT INTO public.dating_enrollments(user_id,state,terms_version,opted_in_at)
>       VALUES(v_user_id,'profile_draft',p_terms_version,now())
>       ON CONFLICT(user_id) DO UPDATE SET
>         state=CASE WHEN public.dating_enrollments.state='suspended' THEN 'suspended' ELSE 'profile_draft' END,
>         terms_version=EXCLUDED.terms_version,opted_in_at=now(),exited_at=NULL,updated_at=now()
>       RETURNING * INTO v_enrollment;
>       EXIT; -- Spec 2 W2
>     EXCEPTION WHEN deadlock_detected OR lock_not_available OR serialization_failure THEN -- Spec 2 W2
>       IF v_try = 3 OR SQLERRM = 'dating:busy' THEN RAISE EXCEPTION 'dating:busy' USING ERRCODE = SQLSTATE; END IF; -- Spec 2 W2
>     END; -- Spec 2 W2
>   END LOOP; -- Spec 2 W2
== public.dating_candidate_is_current(uuid)
<   SELECT public.dating_flag_enabled('dating_mode_enabled')
<     AND public.dating_healing_gates_hold(p_user_id)
<     AND public.dating_age_gate_holds(p_user_id)
<     AND public.dating_account_in_good_standing(p_user_id)
<     AND NOT public.dating_has_relationship(p_user_id)
>   SELECT coalesce(public.dating_eligibility(p_user_id) = 'eligible', false) -- Spec 2 W2: gates 1-6 (flag, standing, relationship, gentle wait, country) replace the flag, Healing, standing and relationship lines
>     AND coalesce(public.dating_age_gate_holds(p_user_id), false) -- Spec 2 W2: NULL-safe
<     AND public.dating_profile_ready(p_user_id);
>     AND coalesce(public.dating_profile_ready(p_user_id), false); -- Spec 2 W2: NULL-safe
== public.enforce_dating_lifecycle_gates()
>   v_try integer; -- Spec 2 W2
<       NOT public.dating_age_gate_holds(de.user_id)
<       OR NOT public.dating_account_in_good_standing(de.user_id)
<       OR NOT public.dating_healing_gates_hold(de.user_id)
<       OR public.dating_has_relationship(de.user_id)
<       OR NOT public.dating_profile_ready(de.user_id)
>       public.dating_age_gate_holds(de.user_id) IS NOT TRUE -- Spec 2 W2: NULL-safe
>       OR public.dating_account_in_good_standing(de.user_id) IS NOT TRUE -- Spec 2 W2: NULL-safe
>       OR public.dating_eligibility(de.user_id, 'setup') IN ('account_unavailable', 'relationship_active') -- Spec 2 W2: the person's own gates 2-4 replace the Healing gate; the gentle wait, a closed country and the feature switch never pause
>       OR public.dating_has_relationship(de.user_id) IS NOT FALSE -- Spec 2 W2: NULL-safe
>       OR public.dating_profile_ready(de.user_id) IS NOT TRUE -- Spec 2 W2: NULL-safe
<     UPDATE public.dating_enrollments SET state='paused',paused_at=COALESCE(paused_at,now()),updated_at=now()
<       WHERE user_id=v_user_id AND state='active';
<     UPDATE public.dating_profiles SET profile_state='paused',updated_at=now()
<       WHERE user_id=v_user_id AND profile_state='active';
<     PERFORM public.invalidate_dating_for_user(v_user_id,'scheduled_gate_revalidation');
<     v_count := v_count + 1;
>     BEGIN -- Spec 2 W2: one person's lock conflict never stops the run
>       PERFORM private.dating_lock_setup(v_user_id); -- Spec 2 W2: the shared lock order (setup, then same-gender)
>       FOR v_try IN 1..3 LOOP -- Spec 2 W2: a lock conflict is retried (each attempt its own savepoint)
>         BEGIN -- Spec 2 W2
>           UPDATE public.dating_enrollments SET state='paused',paused_at=COALESCE(paused_at,now()),
>             pause_reason=COALESCE(pause_reason,'gates'),updated_at=now() -- Spec 2 W2 (W1 B10 M-6): a reason for every pause
>             WHERE user_id=v_user_id AND state='active';
>           IF FOUND THEN -- Spec 2 W2: counted and invalidated only when it paused
>             UPDATE public.dating_profiles SET profile_state='paused',updated_at=now()
>               WHERE user_id=v_user_id AND profile_state='active';
>             PERFORM public.invalidate_dating_for_user(v_user_id,'scheduled_gate_revalidation');
>             v_count := v_count + 1;
>           END IF; -- Spec 2 W2
>           EXIT; -- Spec 2 W2
>         EXCEPTION WHEN deadlock_detected OR lock_not_available OR serialization_failure THEN -- Spec 2 W2
>           IF v_try = 3 OR SQLERRM = 'dating:busy' THEN RAISE EXCEPTION 'dating:busy' USING ERRCODE = SQLSTATE; END IF; -- Spec 2 W2
>         END; -- Spec 2 W2
>       END LOOP; -- Spec 2 W2
>     EXCEPTION WHEN deadlock_detected OR lock_not_available OR serialization_failure THEN -- Spec 2 W2
>       PERFORM private.bump_metric_internal('dating.gates.busy'); -- Spec 2 W2: left for the next run, counted
>     END; -- Spec 2 W2
== public.get_dating_eligibility()
>   v_reason text; -- Spec 2 W2
<   IF NOT public.dating_flag_enabled('dating_mode_enabled') THEN
>   -- Spec 2 W2 (I-4): a compatible shim over dating_eligibility's setup scope
>   -- Spec 2 W2 until W3a moves its two callers to get_dating_home and drops it.
>   v_reason := public.dating_eligibility(v_user_id, 'setup'); -- Spec 2 W2
>   IF v_reason IS NOT DISTINCT FROM 'feature_unavailable' THEN -- Spec 2 W2
<   IF NOT public.dating_account_in_good_standing(v_user_id) THEN
<     RETURN jsonb_build_object('is_eligible',false,'reason','account_unavailable','message','Dating Mode is not available for this account.');
<   END IF;
<   IF public.dating_has_relationship(v_user_id) THEN
>   IF v_reason IS NOT DISTINCT FROM 'relationship_active' THEN -- Spec 2 W2
<   IF NOT public.dating_healing_gates_hold(v_user_id) THEN
<     RETURN jsonb_build_object('is_eligible',false,'reason','healing_not_complete','message','Dating Mode unlocks only after the Healing eligibility transition.');
>   IF v_reason IS DISTINCT FROM 'eligible' THEN -- Spec 2 W2: every other reason, and NULL
>     RETURN jsonb_build_object('is_eligible',false,'reason','account_unavailable','message','Dating Mode is not available for this account.');
<     'age_verification_complete',public.dating_age_gate_holds(v_user_id),
>     'age_verification_complete',coalesce(public.dating_age_gate_holds(v_user_id), false), -- Spec 2 W2: NULL-safe
== public._healing_refresh_status(uuid)
<   v_latest_attempt public.healing_readiness_attempts%ROWTYPE;
<   v_has_relationship boolean;
<   SELECT * INTO v_latest_attempt
<   FROM public.healing_readiness_attempts
<   WHERE journey_id = p_journey_id
<   ORDER BY submitted_at DESC
<   LIMIT 1;
< 
<   SELECT EXISTS (
<     SELECT 1
<     FROM public.relationships r
<     WHERE (r.user_a = v_journey.user_id OR r.user_b = v_journey.user_id)
<       AND r.status IN ('pending', 'active')
<   ) INTO v_has_relationship;
< 
>     -- Spec 2 W2 (§2.1, R7): Healing never grants Dating; a ready journey is
>     -- Spec 2 W2 complete, whatever the check-in score.
<     SET status = CASE
<           WHEN v_latest_attempt.id IS NOT NULL
<             AND v_latest_attempt.score > 70
<             AND now() >= (breakup_at + interval '8 weeks')
<             AND NOT v_has_relationship
<           THEN 'eligible_for_dating_opt_in'
<           ELSE 'completed'
<         END,
>     SET status = 'completed', -- Spec 2 W2
<         eligible_for_dating_opt_in_at = CASE
<           WHEN v_latest_attempt.id IS NOT NULL
<             AND v_latest_attempt.score > 70
<             AND now() >= (breakup_at + interval '8 weeks')
<             AND NOT v_has_relationship
<           THEN COALESCE(eligible_for_dating_opt_in_at, now())
<           ELSE NULL
<         END
>         eligible_for_dating_opt_in_at = NULL -- Spec 2 W2
== public.submit_healing_readiness(uuid,jsonb)
<     'is_eligible', v_updated.status = 'eligible_for_dating_opt_in',
>     'is_eligible', coalesce(v_updated.status = 'completed', false), -- Spec 2 W2: kept for the app's result screen; it now means the journey is complete (no Dating outcome)
<       WHEN now() < (v_journey.breakup_at + interval '8 weeks') THEN
<         'Your check-in is complete. Dating Mode remains unavailable until '
<         || to_char((v_journey.breakup_at + interval '8 weeks') AT TIME ZONE 'UTC', 'DD Mon YYYY')
<         || '.'
<       ELSE 'You can choose whether to explore Dating Mode when it becomes available.'
>       ELSE 'Your check-in is complete. Healing stays here whenever you want it.' -- Spec 2 W2: no Dating date
```

then an empty line (the Healing gate is gone), then `NOTICE:  dating_v2_eligibility_contracts: all held`.

- [ ] **Step 4: The data rewrite (R7), checked on a seeded row**

The `UPDATE` of `healing_journeys` runs once per apply; no contract fixture exists before the migration, so check it in one rolled-back transaction, with the migration's own `BEGIN;`/`COMMIT;` lines removed (an inner `COMMIT` would commit the seed into `attune_spec3a`).

Create `$D/seed_T2.sql` with exactly:

```sql
INSERT INTO auth.users (id, phone, phone_confirmed_at) VALUES ('5e2c0000-0000-0000-0000-000000000099', '1555870299', now());
INSERT INTO public.users (id, phone, display_name) VALUES ('5e2c0000-0000-0000-0000-000000000099', '1555870299', 'Legacy');
INSERT INTO public.healing_journeys (user_id, breakup_at, breakup_at_source, status, eligible_for_dating_opt_in_at)
VALUES ('5e2c0000-0000-0000-0000-000000000099', now() - interval '12 weeks', 'user_reported', 'eligible_for_dating_opt_in', now());
```

```bash
D=.superpowers/sdd/2026-11-07-spec2-w2
psql -X -q -At -v ON_ERROR_STOP=1 -d attune_spec3a -c 'BEGIN' -f $D/seed_T2.sql \
  -f <(sed -e '/^BEGIN;$/d' -e '/^COMMIT;$/d' supabase/migrations/20261107120000_dating_v2_gentle_wait.sql) \
  -c "SELECT status || '/' || (eligible_for_dating_opt_in_at IS NULL) FROM public.healing_journeys WHERE user_id = '5e2c0000-0000-0000-0000-000000000099'" \
  -c 'ROLLBACK' 2>&1 | grep -v NOTICE
psql -X -d attune_spec3a -Atc "select count(*) from public.users where id = '5e2c0000-0000-0000-0000-000000000099'"
```

Expected: `completed/true`, then `0` (nothing outlived the transaction).

- [ ] **Step 5: `dating_mode_contracts.sql`'s candidates pass the new candidate check**

```bash
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/dating_mode_contracts.sql 2>&1 | grep -m1 ERROR | sed -E 's/^psql:[^ ]* //'
```

Expected (red): `ERROR:  introduction_unavailable` (its A, B and D now need gates 1-6). Create `$D/edit_mode_contracts.py` with exactly:

```python
import pathlib, sys
p = pathlib.Path(sys.argv[1])
s = p.read_text()
def rep(old, new):
    global s
    assert s.count(old) == 1, (old[:60], s.count(old))
    s = s.replace(old, new)
rep("""SET LOCAL app.settings.dating_field_key = 'dating-mode-contracts-field-key-0123456789abcdef';
""", """SET LOCAL app.settings.dating_field_key = 'dating-mode-contracts-field-key-0123456789abcdef';
-- Spec 2 W2: the candidate check is dating_eligibility now (gates 1-6), so
-- the fixture holds what its gates read: a ready exclusion key, adults by
-- Spec 1's DOB with EULA v2, and Ghana open in each candidate's region.
SET LOCAL app.settings.dating_exclusion_key = 'dating-mode-contracts-exclusion-key';
SELECT private.seed_dating_exclusion_key_fingerprint() AS seeded \\gset
""")
rep("""  INSERT INTO public.users(id, phone, display_name, mode) VALUES
    (a, '+233200000001', 'Dating A','dating'),
    (b, '+233200000002', 'Dating B','dating'),
    (c, '+233200000003', 'Dating C','dating'),
    (d, '+233200000004', 'Dating D','dating')
  ON CONFLICT (id) DO UPDATE SET phone=EXCLUDED.phone, display_name=EXCLUDED.display_name;
""", """  INSERT INTO public.users(id, phone, display_name, mode) VALUES
    (a, '+233200000001', 'Dating A','dating'),
    (b, '+233200000002', 'Dating B','dating'),
    (c, '+233200000003', 'Dating C','dating'),
    (d, '+233200000004', 'Dating D','dating')
  ON CONFLICT (id) DO UPDATE SET phone=EXCLUDED.phone, display_name=EXCLUDED.display_name;
  -- Spec 2 W2: gate 2 (Spec 1's DOB, EULA v2) and gate 6 (Ghana open).
  UPDATE public.users SET eula_accepted_at = now(), eula_version = '2' WHERE id IN (a, b, c, d);
  INSERT INTO public.account_birthdates (user_id, birth_date)
  SELECT u, current_date - interval '30 years' FROM (VALUES (a), (b), (c), (d)) AS x(u)
  ON CONFLICT (user_id) DO NOTHING;
  PERFORM public.publish_country_config('GH', '{"dating_enabled": true}');
""")
rep("""    (d, 'Dating D','Takoradi','Intentional dating',NULL,'active','approved','verified','GH','WP','committed',now(),'2026-10-v1',false,'yes'),""",
    """    (d, 'Dating D','Takoradi','Intentional dating',NULL,'active','approved','verified','GH','AA','committed',now(),'2026-10-v1',false,'yes'), -- Spec 2 W2: an open region (gate 6)""")
p.write_text(s)
print(p.name + ': W2 fixture lines added')
```

```bash
D=.superpowers/sdd/2026-11-07-spec2-w2
python3 -I $D/edit_mode_contracts.py supabase/tests/dating_mode_contracts.sql
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/dating_mode_contracts.sql > /dev/null 2>&1; echo "dating_mode_contracts exit=$?"
```

Expected: `dating_mode_contracts.sql: W2 fixture lines added`, `dating_mode_contracts exit=0` (the edited file also passes before the migration: the added fixture rows are only more complete).

- [ ] **Step 6: The canary's rows**

```bash
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/dating_rls_canary.sql 2>&1 | grep -A2 -m1 ERROR | sed -E 's/^psql:[^ ]* //'
```

Expected (red): `ERROR:  CONTRACT VIOLATED: Dating grants differ from the allow-list:` / `  private.dating_gentle_wait_opens_at(uuid): not in the canary's allow-list`. Create `$D/edit_canary_T2.py` with exactly:

```python
import pathlib
p = pathlib.Path('supabase/tests/dating_rls_canary.sql')
s = p.read_text()
old = "  ('dating_healing_gates_hold(uuid)', ''),\n"
assert s.count(old) == 1, s.count(old)
p.write_text(s.replace(old, ''))
print('dating_rls_canary.sql: the dropped Healing gate row removed')
```

Create `$D/canary_T2.sql` with exactly:

```sql
-- ---------------------------------------------------------------------
-- W2 (migration 1): the gentle wait's open date is the database's own.
-- ---------------------------------------------------------------------
INSERT INTO allowed_fn (sig, clients, service) VALUES
  ('private.dating_gentle_wait_opens_at(uuid)', '', '');
```

```bash
D=.superpowers/sdd/2026-11-07-spec2-w2
python3 -I $D/edit_canary_T2.py
python3 -I $D/section.py supabase/tests/dating_rls_canary.sql $D/canary_T2.sql --before '-- Checks (every batch adds its rows above this line).'
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/dating_rls_canary.sql 2>&1 | grep -E 'ERROR|all held' | head -1 | sed -E 's/^psql:[^ ]* //'
```

Expected: `dating_rls_canary.sql: the dropped Healing gate row removed`, `dating_rls_canary.sql: canary_T2.sql before`, `NOTICE:  dating_rls_canary: all held`.

- [ ] **Step 7: Mutation checks**

Create `$D/mut_T2.py` with exactly:

```python
MUTS = {
 'm29_status_only': ("""     AND r.status = 'ended'
     AND r.ended_at > now() - interval '30 days';""", """     AND r.status = 'ended';"""),
 'wait_31_days': ("""     AND r.ended_at > now() - interval '30 days';""", """     AND r.ended_at > now() - interval '31 days';"""),
 'wait_archived_counts': ("""     AND r.status = 'ended'
""", """     AND r.status IN ('ended', 'archived')
"""),
 'wait_one_member': ("""   WHERE p_user IN (r.user_a, r.user_b)""", """   WHERE p_user = r.user_a"""),
 'opens_earliest': ("""  SELECT max(r.ended_at) + interval '30 days'""", """  SELECT min(r.ended_at) + interval '30 days'"""),
 'wait_in_setup': ("""  IF p_scope = 'candidate' AND private.dating_gentle_wait_opens_at(p_user) IS NOT NULL THEN -- Spec 2 W2""",
                   """  IF private.dating_gentle_wait_opens_at(p_user) IS NOT NULL THEN -- Spec 2 W2"""),
 'no_wait_gate': ("""    RETURN 'gentle_wait'; -- Spec 2 W2""", """    NULL; -- Spec 2 W2"""),
 'wait_after_country': ('MULTI', [
   ("""  -- 5. Gentle wait (Spec 2 W2, A-9): candidates only; setup goes ahead.
  IF p_scope = 'candidate' AND private.dating_gentle_wait_opens_at(p_user) IS NOT NULL THEN -- Spec 2 W2
    RETURN 'gentle_wait'; -- Spec 2 W2
  END IF; -- Spec 2 W2
""", ""),
   ("""    RETURN CASE WHEN v_region IS NULL AND p_scope = 'setup' THEN 'eligible' ELSE 'region_closed' END;
  END IF;
  RETURN 'eligible';""", """    RETURN CASE WHEN v_region IS NULL AND p_scope = 'setup' THEN 'eligible' ELSE 'region_closed' END;
  END IF;
  IF p_scope = 'candidate' AND private.dating_gentle_wait_opens_at(p_user) IS NOT NULL THEN
    RETURN 'gentle_wait';
  END IF;
  RETURN 'eligible';""")]),
 'begin_no_lock': ("""  PERFORM private.dating_lock_setup(v_user_id); -- Spec 2 W2: the shared lock order (setup, then same-gender) before any row
""", ""),
 'begin_no_device': ("""  IF public.dating_require_trusted_device() IS NOT TRUE THEN RAISE EXCEPTION 'reverify_device' USING ERRCODE='22023'; END IF; -- Spec 2 W2
""", ""),
 'begin_skips_eligibility': ("""  IF public.dating_eligibility(v_user_id, 'setup') IS DISTINCT FROM 'eligible' THEN -- Spec 2 W2""",
                             """  IF false THEN -- Spec 2 W2"""),
 'begin_candidate_scope': ("""  IF public.dating_eligibility(v_user_id, 'setup') IS DISTINCT FROM 'eligible' THEN -- Spec 2 W2""",
                           """  IF public.dating_eligibility(v_user_id, 'candidate') IS DISTINCT FROM 'eligible' AND public.dating_eligibility(v_user_id, 'candidate') <> 'country_closed' THEN -- Spec 2 W2"""),
 'begin_no_retry': ("""      IF v_try = 3 OR SQLERRM = 'dating:busy' THEN RAISE EXCEPTION 'dating:busy' USING ERRCODE = SQLSTATE; END IF; -- Spec 2 W2
    END; -- Spec 2 W2
  END LOOP; -- Spec 2 W2
  RETURN v_enrollment;""", """      RAISE;
    END; -- Spec 2 W2
  END LOOP; -- Spec 2 W2
  RETURN v_enrollment;"""),
 'candidate_setup_scope': ("""  SELECT coalesce(public.dating_eligibility(p_user_id) = 'eligible', false)""",
                           """  SELECT coalesce(public.dating_eligibility(p_user_id, 'setup') = 'eligible', false)"""),
 'candidate_null_eligible': ("""  SELECT coalesce(public.dating_eligibility(p_user_id) = 'eligible', false)""",
                             """  SELECT public.dating_eligibility(p_user_id) IS DISTINCT FROM 'feature_unavailable'"""),
 'candidate_null_ready': ("""    AND coalesce(public.dating_profile_ready(p_user_id), false); -- Spec 2 W2: NULL-safe""",
                          """    AND public.dating_profile_ready(p_user_id); -- Spec 2 W2: NULL-safe"""),
 'candidate_null_age': ("""    AND coalesce(public.dating_age_gate_holds(p_user_id), false) -- Spec 2 W2: NULL-safe""",
                        """    AND coalesce(public.dating_age_gate_holds(p_user_id), true) -- Spec 2 W2: NULL-safe"""),
 'cron_pauses_wait': ("""      OR public.dating_eligibility(de.user_id, 'setup') IN ('account_unavailable', 'relationship_active')""",
                      """      OR public.dating_eligibility(de.user_id) NOT IN ('eligible', 'country_closed')"""),
 'cron_pauses_on_switch': ("""      OR public.dating_eligibility(de.user_id, 'setup') IN ('account_unavailable', 'relationship_active')""",
                           """      OR public.dating_eligibility(de.user_id, 'setup') <> 'eligible'"""),
 'cron_no_reason': ("""            pause_reason=COALESCE(pause_reason,'gates'),updated_at=now() -- Spec 2 W2 (W1 B10 M-6): a reason for every pause""",
                    """            updated_at=now() -- Spec 2 W2 (W1 B10 M-6): a reason for every pause"""),
 'cron_null_ready': ("""      OR public.dating_profile_ready(de.user_id) IS NOT TRUE -- Spec 2 W2: NULL-safe""",
                     """      OR NOT public.dating_profile_ready(de.user_id) -- Spec 2 W2: NULL-safe"""),
 'cron_no_lock': ("""      PERFORM private.dating_lock_setup(v_user_id); -- Spec 2 W2: the shared lock order (setup, then same-gender)
""", ""),
 'cron_busy_aborts': ("""    EXCEPTION WHEN deadlock_detected OR lock_not_available OR serialization_failure THEN -- Spec 2 W2
      PERFORM private.bump_metric_internal('dating.gates.busy'); -- Spec 2 W2: left for the next run, counted""",
                      """    EXCEPTION WHEN deadlock_detected OR lock_not_available OR serialization_failure THEN -- Spec 2 W2
      RAISE; -- Spec 2 W2: left for the next run, counted"""),
 'cron_busy_uncounted': ("""      PERFORM private.bump_metric_internal('dating.gates.busy'); -- Spec 2 W2: left for the next run, counted""",
                         """      NULL; -- Spec 2 W2: left for the next run, counted"""),
 'shim_null_eligible': ("""  IF v_reason IS DISTINCT FROM 'eligible' THEN -- Spec 2 W2: every other reason, and NULL""",
                        """  IF v_reason <> 'eligible' THEN -- Spec 2 W2: every other reason, and NULL"""),
 'shim_candidate_scope': ("""  v_reason := public.dating_eligibility(v_user_id, 'setup'); -- Spec 2 W2""",
                          """  v_reason := public.dating_eligibility(v_user_id); -- Spec 2 W2"""),
 'shim_relationship_generic': ("""  IF v_reason IS NOT DISTINCT FROM 'relationship_active' THEN -- Spec 2 W2""",
                               """  IF false THEN -- Spec 2 W2"""),
 'healing_still_grants': ("""    SET status = 'completed', -- Spec 2 W2""",
                          """    SET status = CASE WHEN breakup_at <= now() - interval '8 weeks' THEN 'eligible_for_dating_opt_in' ELSE 'completed' END, -- Spec 2 W2"""),
 'healing_keeps_eligible_at': ("""        eligible_for_dating_opt_in_at = NULL -- Spec 2 W2""", """        eligible_for_dating_opt_in_at = eligible_for_dating_opt_in_at -- Spec 2 W2"""),
 'readiness_dating_message': ("""      ELSE 'Your check-in is complete. Healing stays here whenever you want it.' -- Spec 2 W2: no Dating date""",
                              """      ELSE 'You can choose whether to explore Dating Mode when it becomes available.' -- Spec 2 W2: no Dating date"""),
 'readiness_eligible_by_score': ("""    'is_eligible', coalesce(v_updated.status = 'completed', false),""",
                                 """    'is_eligible', v_score > 70,"""),
 'opens_granted': ('RAW', "GRANT EXECUTE ON FUNCTION private.dating_gentle_wait_opens_at(uuid) TO authenticated;"),
}
```

```bash
D=.superpowers/sdd/2026-11-07-spec2-w2
python3 -I $D/mutate.py supabase/migrations/20261107120000_dating_v2_gentle_wait.sql supabase/tests/dating_v2_eligibility_contracts.sql $D/mut_T2.py $D | tee $D/mut_T2.txt
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/dating_v2_eligibility_contracts.sql 2>&1 | grep -E 'ERROR|all held' | head -1 | sed -E 's/^psql:[^ ]* //'
```

Expected: 32 lines, every one a `CONTRACT VIOLATED` (times shown as `<time>`; `m29_status_only` is the spec's mutant 29):

```text
m29_status_only: ERROR:  CONTRACT VIOLATED: after the open date, before the sweep, the reason is eligible/gentle_wait (the gate read the status, not the window)
wait_31_days: ERROR:  CONTRACT VIOLATED: after the open date, before the sweep, the reason is eligible/gentle_wait (the gate read the status, not the window)
wait_archived_counts: ERROR:  CONTRACT VIOLATED: a space both sealed still holds the wait (eligible/gentle_wait)
wait_one_member: ERROR:  CONTRACT VIOLATED: inside the ending window the reasons are eligible/gentle_wait and eligible/country_closed (expected eligible/gentle_wait for both members)
opens_earliest: ERROR:  CONTRACT VIOLATED: the open date is not the latest ending + 30 days (<time>, <time>)
wait_in_setup: ERROR:  CONTRACT VIOLATED: inside the ending window the reasons are gentle_wait/gentle_wait and gentle_wait/gentle_wait (expected eligible/gentle_wait for both members)
no_wait_gate: ERROR:  CONTRACT VIOLATED: inside the ending window the reasons are eligible/country_closed and eligible/country_closed (expected eligible/gentle_wait for both members)
wait_after_country: ERROR:  CONTRACT VIOLATED: inside the ending window the reasons are eligible/country_closed and eligible/country_closed (expected eligible/gentle_wait for both members)
begin_no_lock: ERROR:  CONTRACT VIOLATED: begin_dating_enrollment does not take the shared lock order first
begin_no_device: ERROR:  CONTRACT VIOLATED: an untrusted device began enrolment (no error/profile_draft)
begin_skips_eligibility: ERROR:  CONTRACT VIOLATED: an under-18 account began enrolment (no error/profile_draft)
begin_candidate_scope: ERROR:  CONTRACT VIOLATED: during the gentle wait setup could not begin (not_eligible/none)
begin_no_retry: ERROR:  CONTRACT VIOLATED: two lock conflicts were not retried into an enrolment (deadlock stand-in/none/1; expected no error/profile_draft/3)
candidate_setup_scope: ERROR:  CONTRACT VIOLATED: the candidate check ignores the gentle wait (in the wait not current, after it current: false/true)
candidate_null_eligible: ERROR:  CONTRACT VIOLATED: the candidate check ignores the gentle wait (in the wait not current, after it current: false/true)
candidate_null_ready: ERROR:  CONTRACT VIOLATED: a NULL readiness answer made a current candidate (or a NULL answer)
candidate_null_age: ERROR:  CONTRACT VIOLATED: a NULL age answer made a current candidate (or a NULL answer)
cron_pauses_wait: ERROR:  CONTRACT VIOLATED: the gate cron gave 0:paused/gates/paused,paused/gates/paused,active/-/active (expected only the held person paused, with the reason gates)
cron_pauses_on_switch: ERROR:  CONTRACT VIOLATED: the gate cron gave 0:active/-/active,paused/gates/paused,paused/gates/paused (expected only the held person paused, with the reason gates)
cron_no_reason: ERROR:  CONTRACT VIOLATED: the gate cron gave 1:active/-/active,paused/-/paused,active/-/active (expected only the held person paused, with the reason gates)
cron_null_ready: ERROR:  CONTRACT VIOLATED: a NULL readiness answer kept a person active (0:active/-/active,paused/gates/paused,active/-/active)
cron_no_lock: ERROR:  CONTRACT VIOLATED: the gate cron writes before the shared lock
cron_busy_aborts: ERROR:  CONTRACT VIOLATED: a lock conflict stopped the gate cron or went uncounted (raised 40P01 dating:busy/0)
cron_busy_uncounted: ERROR:  CONTRACT VIOLATED: a lock conflict stopped the gate cron or went uncounted (0:active/-/active,active/-/active,paused/gates/paused/0)
shim_null_eligible: ERROR:  CONTRACT VIOLATED: with a NULL eligibility the shim answered <NULL>
shim_candidate_scope: ERROR:  CONTRACT VIOLATED: the shim for a person in the wait (setup scope) is {"reason": "account_unavailable", "message": "Dating Mode is not available for this account.
shim_relationship_generic: ERROR:  CONTRACT VIOLATED: the shim with a pending relationship is {"reason": "account_unavailable", "message": "Dating Mode is not available for this account.", "is_elig
healing_still_grants: ERROR:  CONTRACT VIOLATED: the Healing gate (or a Healing Dating status writer) is still there
healing_keeps_eligible_at: ERROR:  CONTRACT VIOLATED: a ready journey with a score of 100 is not simply completed
readiness_dating_message: ERROR:  CONTRACT VIOLATED: the readiness answer still speaks of Dating ({"score": 100, "message": "You can choose whether to explore Dating Mode when it becomes available
readiness_eligible_by_score: ERROR:  CONTRACT VIOLATED: is_eligible follows the score, not the completed journey ({"score": 0, "message": "Your answers suggest there may be more you want to explore. 
opens_granted: ERROR:  CONTRACT VIOLATED: the open date is callable outside the database
```

then `NOTICE:  dating_v2_eligibility_contracts: all held` (the database is unchanged).

- [ ] **Step 8: The local harness (edit only, never run); the neighbours**

```bash
D=.superpowers/sdd/2026-11-07-spec2-w2
python3 -I $D/grants_line.py supabase/migrations/20261107110010_opinion_enforcement_restore_grants.sql \
  "Spec 2 W2: the open date, eligibility, the candidate check and the gate cron are the database's own; the shim and begin stay the app's." \
  supabase/migrations/20261107120010_dating_v2_gentle_wait_grants.sql
for t in identity_foundation_contracts dating_v2_identity_contracts dating_v2_setup_contracts country_safety_config_contracts \
         account_deletion_contracts dormancy_contracts dating_exclusion_wiring_test service_role_grants_test \
         healing_ai_pause_contracts relationship_lifecycle_contracts dating_alignment_contracts; do
  psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/$t.sql > /dev/null 2>&1 && echo "PASS $t" || echo "FAIL $t"
done
```

Expected: `local_pg_grants.sql: one \i block added`, then eleven `PASS` lines.

### Task 3: Migration 2: the `users.path` trigger, one writer per pause reason (§4.9 W2, §4.10 users triggers, R13, I-5, Spec 1 D18; mutant 24; P-9)

**Files:**
- Create: `supabase/migrations/20261107130000_dating_v2_path_pause.sql`, `…130010_dating_v2_path_pause_grants.sql`, `$D/{elig_W2b.sql, edit_identity_T3.py, canary_T3.sql, mut_T3.py, edit_races_T3.py}`
- Modify: `supabase/tests/dating_v2_eligibility_contracts.sql`, `supabase/tests/identity_foundation_contracts.sql`, `supabase/tests/dating_rls_canary.sql`, `scripts/concurrency/dating_kill_switch_races.sh`, `scripts/local_pg_grants.sql`

**Interfaces:**
- Consumes: Task 2's contract helpers (`pg_temp.enrolled`, `pg_temp.pause_of`, `pg_temp.as_person`, `pg_temp.as_db`, `pg_temp.error_of`, `pg_temp.metric`, `pg_temp.probe`); `set_my_path`, `set_user_path_internal`; `private.dating_lock_setup`; `public.invalidate_dating_for_user`.
- Produces: trigger `dating_pause_on_path_change` (`public.dating_pause_on_path_change()`); health keys `dating.path_pause.failed`, `dating.gates.busy`.

- [ ] **Step 1: Write the failing sections (I, I2)**

Create `$D/elig_W2b.sql` with exactly:

```sql
-- =====================================================================
-- I. (W2, I-5, Spec 1 D18, R13) One writer per pause reason: Dating ->
--    Just for me is paused by the path trigger with path_change; Dating ->
--    Relationship by Spec 1's set_user_path_internal with relationship,
--    and the trigger does nothing; a paused enrolment keeps its first
--    reason; the trigger takes the shared lock order, retries a lock
--    conflict and never raises.
-- =====================================================================
DO $$
DECLARE
  v_just constant uuid := pg_temp.enrolled('60', 'active');
  v_rel constant uuid := pg_temp.enrolled('61', 'active');
  v_user_paused constant uuid := pg_temp.enrolled('62', 'paused', 'user');
  v_draft constant uuid := pg_temp.enrolled('63', 'profile_draft');
  v_none constant uuid := pg_temp.person('64');
  v_back constant uuid := pg_temp.person('65');
  v_paused_at timestamptz;
  v_src text;
BEGIN
  PERFORM pg_temp.as_person(v_just);
  PERFORM public.set_my_path('just_me');
  PERFORM pg_temp.as_db();
  IF pg_temp.pause_of(v_just) IS DISTINCT FROM 'paused/path_change/paused' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: Dating -> Just for me left %, expected paused/path_change/paused', pg_temp.pause_of(v_just);
  END IF;
  PERFORM pg_temp.as_person(v_rel);
  PERFORM public.set_my_path('relationship', true);
  PERFORM pg_temp.as_db();
  IF pg_temp.pause_of(v_rel) IS DISTINCT FROM 'paused/relationship/paused' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: Dating -> Relationship left %, expected paused/relationship/paused (Spec 1''s one pause, D18)', pg_temp.pause_of(v_rel);
  END IF;
  SELECT e.paused_at INTO v_paused_at FROM public.dating_enrollments AS e WHERE e.user_id = v_user_paused;
  PERFORM pg_temp.as_person(v_user_paused);
  PERFORM public.set_my_path('just_me');
  PERFORM pg_temp.as_db();
  IF pg_temp.pause_of(v_user_paused) IS DISTINCT FROM 'paused/user/paused'
     OR (SELECT e.paused_at FROM public.dating_enrollments AS e WHERE e.user_id = v_user_paused) IS DISTINCT FROM v_paused_at THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an enrolment already paused by the person lost its first reason (%)', pg_temp.pause_of(v_user_paused);
  END IF;
  PERFORM pg_temp.as_person(v_draft);
  PERFORM public.set_my_path('just_me');
  PERFORM pg_temp.as_db();
  IF pg_temp.pause_of(v_draft) IS DISTINCT FROM 'paused/path_change/draft' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a draft left on Dating -> Just for me is %', pg_temp.pause_of(v_draft);
  END IF;
  PERFORM pg_temp.as_person(v_none);
  PERFORM public.set_my_path('just_me');
  PERFORM pg_temp.as_db();
  IF pg_temp.pause_of(v_none) IS DISTINCT FROM 'none/none' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the path trigger wrote Dating rows for someone never enrolled (%)', pg_temp.pause_of(v_none);
  END IF;
  -- A move to Dating (here from Just for me, with an active enrolment) changes nothing.
  UPDATE public.users SET path = 'just_me' WHERE id = v_back;
  INSERT INTO public.dating_enrollments (user_id, state) VALUES (v_back, 'active');
  INSERT INTO public.dating_profiles (user_id, display_name, profile_state) VALUES (v_back, 'Back', 'active');
  UPDATE public.users SET path = 'dating' WHERE id = v_back;
  IF pg_temp.pause_of(v_back) IS DISTINCT FROM 'active/-/active' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a move to Dating paused it (%)', pg_temp.pause_of(v_back);
  END IF;
  -- One writer per reason, by body: only the guard trigger and Spec 1's
  -- path setter call the relationship pause, and only the path trigger
  -- writes path_change.
  IF (SELECT string_agg(p.proname, ',' ORDER BY p.proname) FROM pg_proc AS p JOIN pg_namespace AS n ON n.oid = p.pronamespace
       WHERE n.nspname IN ('public', 'private') AND p.prosrc LIKE '%pause_dating_for_relationship_user(%'
         AND p.proname <> 'pause_dating_for_relationship_user')
     IS DISTINCT FROM 'set_user_path_internal,sync_dating_pause_on_relationship'
     OR (SELECT string_agg(p.proname, ',' ORDER BY p.proname) FROM pg_proc AS p JOIN pg_namespace AS n ON n.oid = p.pronamespace
          WHERE n.nspname IN ('public', 'private') AND p.prosrc LIKE '%''path_change''%')
     IS DISTINCT FROM 'dating_pause_on_path_change' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: another function pauses Dating for a path change';
  END IF;
  -- The shared lock order: the setup lock before the first row.
  v_src := (SELECT p.prosrc FROM pg_proc AS p WHERE p.oid = 'public.dating_pause_on_path_change()'::regprocedure);
  IF position('private.dating_lock_setup(NEW.id)' IN v_src) = 0
     OR position('private.dating_lock_setup(NEW.id)' IN v_src) > position('UPDATE public.dating_enrollments' IN v_src)
     OR position('FOR UPDATE' IN v_src) > position('UPDATE public.dating_profiles' IN v_src) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the path trigger does not take the shared lock order';
  END IF;
  IF has_function_privilege('authenticated', 'public.dating_pause_on_path_change()', 'EXECUTE')
     OR has_function_privilege('service_role', 'public.dating_pause_on_path_change()', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the path trigger function is callable by an API role';
  END IF;
END $$;

-- I2. The trigger never raises: a failing pause is counted and the path
--     change still goes through; a lock conflict is retried (two failures
--     then success pauses; three are counted).
-- [p] moves to Just for me: the error (or 'no error'), then the path, the
-- Dating states and how many path-pause failures were counted since [p_before].
CREATE FUNCTION pg_temp.leave_dating(p uuid, p_before bigint) RETURNS text LANGUAGE plpgsql AS $$
DECLARE
  v text;
BEGIN
  PERFORM pg_temp.as_person(p);
  v := pg_temp.error_of($q$SELECT public.set_my_path('just_me')$q$);
  PERFORM pg_temp.as_db();
  RETURN v || '/' || (SELECT u.path FROM public.users AS u WHERE u.id = p) || '/' || pg_temp.pause_of(p)
         || '/' || (pg_temp.metric('dating.path_pause.failed') - p_before);
END $$;

DO $i2$
DECLARE
  v_fail constant uuid := pg_temp.enrolled('66', 'active');
  v_retry constant uuid := pg_temp.enrolled('67', 'active');
  v_busy constant uuid := pg_temp.enrolled('68', 'active');
  v text;
BEGIN
  -- Each stand-in lives inside a probe, which undoes it.
  v := pg_temp.probe(ARRAY[
    $s$CREATE OR REPLACE FUNCTION public.invalidate_dating_for_user(p_user_id uuid, p_reason text DEFAULT NULL) RETURNS void
       LANGUAGE plpgsql AS $f$ BEGIN RAISE EXCEPTION 'boom'; END $f$$s$],
    format('SELECT pg_temp.leave_dating(%L, %s)', v_fail, pg_temp.metric('dating.path_pause.failed')));
  IF v IS DISTINCT FROM 'no error/just_me/active/-/active/1' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a failing pause raised, or went uncounted, or half-paused (%; expected no error/just_me/active/-/active/1)', v;
  END IF;
  -- A sequence counts the calls: it outlives each retry's rolled-back savepoint.
  CREATE TEMP SEQUENCE w2_calls;
  v := pg_temp.probe(ARRAY[
    $s$CREATE OR REPLACE FUNCTION public.invalidate_dating_for_user(p_user_id uuid, p_reason text DEFAULT NULL) RETURNS void
       LANGUAGE plpgsql AS $f$
       BEGIN
         IF nextval('pg_temp.w2_calls') <= 2 THEN RAISE EXCEPTION 'deadlock stand-in' USING ERRCODE = '40P01'; END IF;
       END $f$$s$],
    format($s$SELECT pg_temp.leave_dating(%L, %s) || '/' || currval('pg_temp.w2_calls')$s$, v_retry, pg_temp.metric('dating.path_pause.failed')));
  -- Calls: two failed attempts, then the profile trigger's and the pause's own.
  IF v IS DISTINCT FROM 'no error/just_me/paused/path_change/paused/0/4' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: two lock conflicts were not retried into a pause (%; expected no error/just_me/paused/path_change/paused/0/4)', v;
  END IF;
  v := pg_temp.probe(ARRAY[
    $s$CREATE OR REPLACE FUNCTION public.invalidate_dating_for_user(p_user_id uuid, p_reason text DEFAULT NULL) RETURNS void
       LANGUAGE plpgsql AS $f$ BEGIN RAISE EXCEPTION 'deadlock stand-in' USING ERRCODE = '40P01'; END $f$$s$],
    format('SELECT pg_temp.leave_dating(%L, %s)', v_busy, pg_temp.metric('dating.path_pause.failed')));
  IF v IS DISTINCT FROM 'no error/just_me/active/-/active/1' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: three lock conflicts raised or went uncounted (%; expected no error/just_me/active/-/active/1)', v;
  END IF;
  IF (SELECT pg_get_functiondef('public.get_dating_operational_health()'::regprocedure)) NOT LIKE '%''dating.path_pause.failed''%'
     OR (SELECT pg_get_functiondef('public.get_dating_operational_health()'::regprocedure)) NOT LIKE '%''dating.gates.busy''%' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: health does not show the path-pause failures and the busy gate runs';
  END IF;
END $i2$;
```

```bash
D=.superpowers/sdd/2026-11-07-spec2-w2
python3 -I $D/section.py supabase/tests/dating_v2_eligibility_contracts.sql $D/elig_W2b.sql --end
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/dating_v2_eligibility_contracts.sql 2>&1 | grep -E 'ERROR|all held' | head -1 | sed -E 's/^psql:[^ ]* //'
```

Expected: `dating_v2_eligibility_contracts.sql: elig_W2b.sql end`, then `ERROR:  CONTRACT VIOLATED: Dating -> Just for me left active/-/active, expected paused/path_change/paused`.

- [ ] **Step 2: Write migration 2 and its twin**

Create `supabase/migrations/20261107130000_dating_v2_path_pause.sql` with exactly:

```sql
-- Spec 2 W2, migration 2 (spec §4.9 W2 #1, §4.10 users triggers, R13;
-- Spec 1 D18; I-5): the users.path trigger dating_pause_on_path_change.
--   * AFTER UPDATE OF path: a change from Dating to anything but
--     Relationship pauses an active or draft enrolment with pause_reason
--     'path_change'. A change to Relationship is left to Spec 1's
--     set_user_path_internal, which pauses with 'relationship' (one writer
--     per reason); an enrolment already paused keeps its first reason.
--   * It takes the shared lock order (private.dating_lock_setup: setup,
--     then same-gender, then the enrolment row before the profile row) and
--     the bounded retry on 40P01/55P03/40001, like the parked trigger, and
--     never raises (R13): a failure is counted (dating.path_pause.failed),
--     shown in health, and the path change still goes through.
--   * get_dating_operational_health() re-created from its live body
--     (20261106200000 with the W1 final fixes) with two keys added to
--     safety_counters_7d: dating.path_pause.failed and dating.gates.busy
--     (migration 1's gate cron).
-- set_user_path_internal is not edited (R13).
-- Grants in 20261107130010_dating_v2_path_pause_grants.sql.
BEGIN;
SET LOCAL lock_timeout = '5s';

CREATE OR REPLACE FUNCTION public.dating_pause_on_path_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_try integer;
BEGIN
  -- Only a change away from Dating, and never to Relationship (D18, I-5):
  -- Spec 1's set_user_path_internal pauses that change itself.
  IF OLD.path IS DISTINCT FROM 'dating'
     OR NEW.path IS NOT DISTINCT FROM 'dating'
     OR NEW.path IS NOT DISTINCT FROM 'relationship' THEN
    RETURN NULL;
  END IF;
  FOR v_try IN 1..3 LOOP
    BEGIN
      PERFORM private.dating_lock_setup(NEW.id);
      PERFORM 1 FROM public.dating_enrollments AS e WHERE e.user_id = NEW.id FOR UPDATE; -- the enrolment row before the profile row
      UPDATE public.dating_enrollments AS e
         SET state = 'paused', pause_reason = 'path_change', paused_at = coalesce(e.paused_at, now()),
             updated_at = now()
       WHERE e.user_id = NEW.id AND e.state IN ('active', 'profile_draft');
      IF FOUND THEN
        UPDATE public.dating_profiles AS p SET profile_state = 'paused', updated_at = now()
         WHERE p.user_id = NEW.id AND p.profile_state = 'active';
        PERFORM public.invalidate_dating_for_user(NEW.id, 'path_change');
      END IF;
      EXIT;
    EXCEPTION WHEN OTHERS THEN
      CONTINUE WHEN v_try < 3 AND SQLSTATE IN ('40P01', '55P03', '40001') AND SQLERRM IS DISTINCT FROM 'dating:busy';
      -- Never raises (R13): the path change goes through; the failure is
      -- counted for health.
      PERFORM private.bump_metric_internal('dating.path_pause.failed');
      RAISE WARNING 'dating_pause_on_path_change:%', SQLSTATE;
      EXIT;
    END;
  END LOOP;
  RETURN NULL;
END;
$fn$;

CREATE OR REPLACE TRIGGER dating_pause_on_path_change
  AFTER UPDATE OF path ON public.users
  FOR EACH ROW
  WHEN (OLD.path IS DISTINCT FROM NEW.path)
  EXECUTE FUNCTION public.dating_pause_on_path_change();

CREATE OR REPLACE FUNCTION public.get_dating_operational_health()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT jsonb_build_object(
    'dating_enabled',public.dating_flag_enabled('dating_mode_enabled'),
    'candidate_generation_enabled',public.dating_flag_enabled('dating_candidate_generation'),
    'exclusion_key_present',public.app_setting('dating_exclusion_key') IS NOT NULL,
    'relationships_ended_without_exclusion_24h',(
      SELECT count(*) FROM public.relationships r
      WHERE r.status = 'ended'
        AND r.ended_at >= now() - interval '24 hours'
        AND NOT EXISTS (
          SELECT 1 FROM public.dating_former_partner_exclusions e
          WHERE e.relationship_id = r.id
        )
    ),
    'active_algorithm_versions',(SELECT count(*) FROM public.dating_algorithm_configs WHERE state='active'),
    'stuck_generation_runs',(SELECT count(*) FROM public.dating_generation_runs WHERE state='processing' AND started_at < now()-interval '30 minutes'),
    'failed_generation_runs_24h',(SELECT count(*) FROM public.dating_generation_runs WHERE state IN ('failed','dead_letter') AND created_at >= now()-interval '24 hours'),
    'expired_open_introductions',(SELECT count(*) FROM public.dating_introductions WHERE state IN ('generated','presented','interested') AND expires_at <= now()),
    'pending_bio_moderation',(SELECT count(*) FROM public.dating_profiles WHERE moderation_state='pending'),
    'pending_photo_moderation',(SELECT count(*) FROM public.dating_profile_photos WHERE moderation_state='pending'),
    'environment',private.attune_environment(), -- Spec 2 W1d
    'field_key_present',private.dating_field_key_present(), -- Spec 2 W1d
    -- Spec 2 W1d (§2.4): nothing can write an RPC's parameters to the log.
    'log_settings_safe',coalesce(current_setting('log_statement', true) IN ('none', 'ddl')
      AND (current_setting('log_min_duration_statement', true) = '-1'
           OR current_setting('log_parameter_max_length', true) = '0')
      AND current_setting('log_parameter_max_length_on_error', true) = '0', false),
    'enabled_countries',to_jsonb(private.dating_open_countries()), -- Spec 2 W1d
    -- Spec 2 W1d (B2 I-5, B5 M-4, B6 M-5): each key set and its stored
    -- Spec 2 W1d fingerprint equal (read only; never the counting mismatch()).
    'exclusion_key_fingerprint_ok',private.dating_exclusion_key_ready(), -- Spec 2 W1d
    'field_key_fingerprint_ok',private.dating_field_key_ready(), -- Spec 2 W1d
    'safety_counters_7d',(SELECT jsonb_object_agg(k.key, coalesce((SELECT sum(c.count) FROM public.metric_counters c -- Spec 2 W1d
                            WHERE c.key = k.key AND c.day >= (now() AT TIME ZONE 'utc')::date - 6), 0)) -- Spec 2 W1d
      FROM unnest(ARRAY['dating.deletion.uncarried', 'dating.exclusion_key.mismatch', 'dating.exclusion_key.unseeded', -- Spec 2 W1d
                        'dating.eligibility.key_not_ready', 'dating.field_key.mismatch', 'dating.field_key.missing', -- Spec 2 W1d
                        'dating.parked_pause.failed', -- Spec 2 W1d (fix round 1, M-5)
                        'dating.path_pause.failed', 'dating.gates.busy', -- Spec 2 W2
                        'dating.kill_switch.pending', 'dating.kill_switch.unreadable', -- Spec 2 W1d (migration 11)
                        'dating.deletion.prepare_carry_failed', 'dating.deletion.late_carry_failed']) AS k(key)), -- W1 final fix (M-4)
    -- W1 final fix (M-4): app deletions refused for a missing exclusion key
    -- W1 final fix (delete-account records prepare's message) in 7 days.
    'deletions_refused_key_missing_7d',(SELECT count(*) FROM public.account_deletion_requests AS r -- W1 final fix (M-4)
                                         WHERE r.completed_at IS NULL AND r.requested_at >= now() - interval '7 days' -- W1 final fix (M-4)
                                           AND r.failure_reason LIKE '%deletion:enforcement_key_missing%'), -- W1 final fix (M-4)
    -- Spec 2 W1d (fix round 1, I-1): every purge still pending, until a switch clears it.
    'kill_switch_pending',(SELECT coalesce(jsonb_agg(jsonb_build_object('scope', k.scope, 'since', k.first_failed_at, -- Spec 2 W1d
                             'sqlstate', k.last_sqlstate, 'attempts', k.attempts) ORDER BY k.scope), '[]'::jsonb) -- Spec 2 W1d
                           FROM private.dating_kill_switch_pending k) -- Spec 2 W1d
  );
$function$;

REVOKE ALL ON FUNCTION public.dating_pause_on_path_change() FROM PUBLIC, anon, authenticated, service_role;

COMMIT;
```

Create `supabase/migrations/20261107130010_dating_v2_path_pause_grants.sql` with exactly:

```sql
-- Spec 2 W2: grants for 20261107130000_dating_v2_path_pause.sql.
-- The trigger function is no API role's (the service role included);
-- health keeps its W1 grant (the service role's, for the edge health check).
BEGIN;
SET LOCAL lock_timeout = '5s';
REVOKE ALL ON FUNCTION public.dating_pause_on_path_change() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.get_dating_operational_health() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_dating_operational_health() TO service_role;
COMMIT;
```

- [ ] **Step 3: Apply twice; diff health; run the contract**

```bash
for i in 1 2; do
  for f in 20261107130000_dating_v2_path_pause 20261107130010_dating_v2_path_pause_grants; do
    psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/migrations/$f.sql > /dev/null 2>&1; echo "$f exit=$?"
  done
done
D=.superpowers/sdd/2026-11-07-spec2-w2
diff "$D/before/public.get_dating_operational_health().sql" <(psql -X -d attune_spec3a -Atc "select pg_get_functiondef('public.get_dating_operational_health()'::regprocedure)") | grep '^[<>]'
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/dating_v2_eligibility_contracts.sql 2>&1 | grep -E 'ERROR|all held' | head -1 | sed -E 's/^psql:[^ ]* //'
```

Expected: four `exit=0`; exactly `>                         'dating.path_pause.failed', 'dating.gates.busy', -- Spec 2 W2`; `NOTICE:  dating_v2_eligibility_contracts: all held`.

- [ ] **Step 4: Spec 1's D18 contract follows the end state (P-9)**

```bash
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/identity_foundation_contracts.sql 2>&1 | grep -m1 ERROR | sed -E 's/^psql:[^ ]* //'
```

Expected (red): `ERROR:  CONTRACT VIOLATED: the D18 pause rule is wrong with the real pause function`. Create `$D/edit_identity_T3.py` with exactly:

```python
# Spec 2 W2 Task 3: Spec 1's D18 contract pinned that Dating -> Just for me
# leaves Dating active; W2's path trigger now pauses it (D18's end state).
import pathlib

def edit(path, pairs):
    p = pathlib.Path(path)
    s = p.read_text()
    for old, new in pairs:
        assert s.count(old) == 1, (path, old[:60], s.count(old))
        s = s.replace(old, new)
    p.write_text(s)
    print(f'{path}: {len(pairs)} edit(s)')

# Spec 1's D18 contract: Just for me is now paused, by Spec 2 W2's trigger.
edit('supabase/tests/identity_foundation_contracts.sql', [(
"""-- G6. D18 with the real pause: Relationship pauses Dating; Just for me doesn't.
DO $$
BEGIN
  PERFORM pg_temp.as_user('5f1a0000-0000-0000-0000-000000000036');
  PERFORM public.set_my_path('relationship', true);
  RESET ROLE;
  PERFORM pg_temp.as_user('5f1a0000-0000-0000-0000-000000000037');
  PERFORM public.set_my_path('just_me');
  RESET ROLE;
  IF (SELECT state FROM public.dating_enrollments WHERE user_id = '5f1a0000-0000-0000-0000-000000000036') <> 'paused'
     OR (SELECT state FROM public.dating_enrollments WHERE user_id = '5f1a0000-0000-0000-0000-000000000037') <> 'active' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the D18 pause rule is wrong with the real pause function';
  END IF;
END $$;""",
"""-- G6. D18 with the real pause: Relationship pauses Dating with Spec 1's
--     'relationship'; Just for me is paused by Spec 2 W2's path trigger with
--     'path_change' (amended by Spec 2 W2: until then nothing paused it).
DO $$
BEGIN
  PERFORM pg_temp.as_user('5f1a0000-0000-0000-0000-000000000036');
  PERFORM public.set_my_path('relationship', true);
  RESET ROLE;
  PERFORM pg_temp.as_user('5f1a0000-0000-0000-0000-000000000037');
  PERFORM public.set_my_path('just_me');
  RESET ROLE;
  IF (SELECT state || '/' || coalesce(pause_reason, '-') FROM public.dating_enrollments
       WHERE user_id = '5f1a0000-0000-0000-0000-000000000036') IS DISTINCT FROM 'paused/relationship'
     OR (SELECT state || '/' || coalesce(pause_reason, '-') FROM public.dating_enrollments
          WHERE user_id = '5f1a0000-0000-0000-0000-000000000037') IS DISTINCT FROM 'paused/path_change' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the D18 pause rule is wrong with the real pause function';
  END IF;
END $$;""")])
```

```bash
D=.superpowers/sdd/2026-11-07-spec2-w2
python3 -I $D/edit_identity_T3.py
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/identity_foundation_contracts.sql > /dev/null 2>&1; echo "identity_foundation exit=$?"
```

Expected: `supabase/tests/identity_foundation_contracts.sql: 1 edit(s)`, `identity_foundation exit=0` (G5, the spy, still sees zero pause calls on Dating → Just for me: the trigger pauses by itself).

- [ ] **Step 5: The canary's row**

Create `$D/canary_T3.sql` with exactly:

```sql
-- ---------------------------------------------------------------------
-- W2 (migration 2): the users.path trigger function is no API role's.
-- ---------------------------------------------------------------------
INSERT INTO allowed_fn (sig, clients, service) VALUES
  ('dating_pause_on_path_change()', '', '');
```

```bash
D=.superpowers/sdd/2026-11-07-spec2-w2
python3 -I $D/section.py supabase/tests/dating_rls_canary.sql $D/canary_T3.sql --before '-- Checks (every batch adds its rows above this line).'
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/dating_rls_canary.sql 2>&1 | grep -E 'ERROR|all held' | head -1 | sed -E 's/^psql:[^ ]* //'
```

Expected: `dating_rls_canary.sql: canary_T3.sql before`, `NOTICE:  dating_rls_canary: all held` (before this step the canary named `dating_pause_on_path_change(): not in the canary's allow-list`).

- [ ] **Step 6: Mutation checks**

Create `$D/mut_T3.py` with exactly:

```python
MUTS = {
 'm24_pauses_to_relationship': ("""     OR NEW.path IS NOT DISTINCT FROM 'dating'
     OR NEW.path IS NOT DISTINCT FROM 'relationship' THEN""", """     OR NEW.path IS NOT DISTINCT FROM 'dating' THEN"""),
 'm24_relationship_reason': ("""         SET state = 'paused', pause_reason = 'path_change', paused_at = coalesce(e.paused_at, now()),""",
                             """         SET state = 'paused', pause_reason = 'relationship', paused_at = coalesce(e.paused_at, now()),"""),
 'overwrites_first_reason': ("""       WHERE e.user_id = NEW.id AND e.state IN ('active', 'profile_draft');""",
                             """       WHERE e.user_id = NEW.id AND e.state IN ('active', 'profile_draft', 'paused');"""),
 'skips_drafts': ("""       WHERE e.user_id = NEW.id AND e.state IN ('active', 'profile_draft');""",
                  """       WHERE e.user_id = NEW.id AND e.state IN ('active');"""),
 'pauses_into_dating': ("""  IF OLD.path IS DISTINCT FROM 'dating'
     OR NEW.path IS NOT DISTINCT FROM 'dating'""", """  IF NEW.path IS NOT DISTINCT FROM 'dating'
     AND OLD.path IS NOT DISTINCT FROM 'dating'"""),
 'profile_stays_active': ("""        UPDATE public.dating_profiles AS p SET profile_state = 'paused', updated_at = now()
         WHERE p.user_id = NEW.id AND p.profile_state = 'active';
""", ""),
 'no_lock': ("""      PERFORM private.dating_lock_setup(NEW.id);
""", ""),
 'no_retry': ("""      CONTINUE WHEN v_try < 3 AND SQLSTATE IN ('40P01', '55P03', '40001') AND SQLERRM IS DISTINCT FROM 'dating:busy';
""", ""),
 'raises': ("""      RAISE WARNING 'dating_pause_on_path_change:%', SQLSTATE;""", """      RAISE;"""),
 'uncounted': ("""      PERFORM private.bump_metric_internal('dating.path_pause.failed');
""", ""),
 'health_misses_counter': ("""                        'dating.path_pause.failed', 'dating.gates.busy', -- Spec 2 W2
""", ""),
 'trigger_granted': ('RAW', "GRANT EXECUTE ON FUNCTION public.dating_pause_on_path_change() TO authenticated;"),
}
```

```bash
D=.superpowers/sdd/2026-11-07-spec2-w2
python3 -I $D/mutate.py supabase/migrations/20261107130000_dating_v2_path_pause.sql supabase/tests/dating_v2_eligibility_contracts.sql $D/mut_T3.py $D | tee $D/mut_T3.txt
```

Expected (the two `m24_*` are the spec's mutant 24, both directions):

```text
m24_pauses_to_relationship: ERROR:  CONTRACT VIOLATED: Dating -> Relationship left paused/path_change/paused, expected paused/relationship/paused (Spec 1's one pause, D18)
m24_relationship_reason: ERROR:  CONTRACT VIOLATED: Dating -> Just for me left paused/relationship/paused, expected paused/path_change/paused
overwrites_first_reason: ERROR:  CONTRACT VIOLATED: an enrolment already paused by the person lost its first reason (paused/path_change/paused)
skips_drafts: ERROR:  CONTRACT VIOLATED: a draft left on Dating -> Just for me is profile_draft/-/draft
pauses_into_dating: ERROR:  CONTRACT VIOLATED: a move to Dating paused it (paused/path_change/paused)
profile_stays_active: ERROR:  CONTRACT VIOLATED: Dating -> Just for me left paused/path_change/active, expected paused/path_change/paused
no_lock: ERROR:  CONTRACT VIOLATED: the path trigger does not take the shared lock order
no_retry: ERROR:  CONTRACT VIOLATED: two lock conflicts were not retried into a pause (no error/just_me/active/-/active/1/1; expected no error/just_me/paused/path_change/paused/0/4
raises: ERROR:  CONTRACT VIOLATED: a failing pause raised, or went uncounted, or half-paused (boom/dating/active/-/active/0; expected no error/just_me/active/-/active/1)
uncounted: ERROR:  CONTRACT VIOLATED: a failing pause raised, or went uncounted, or half-paused (no error/just_me/active/-/active/0; expected no error/just_me/active/-/active/1)
health_misses_counter: ERROR:  CONTRACT VIOLATED: health does not show the path-pause failures and the busy gate runs
trigger_granted: ERROR:  CONTRACT VIOLATED: the path trigger function is callable by an API role
```

- [ ] **Step 7: The race (a throwaway copy, never `attune_spec3a`)**

Create `$D/edit_races_T3.py` with exactly:

```python
import pathlib
p = pathlib.Path('scripts/concurrency/dating_kill_switch_races.sh')
s = p.read_text()
anchor = """run "country change (GB to GH) vs the global flag off" \\\n"""
assert s.count(anchor) == 1
case = '''# Spec 2 W2: the users.path trigger (Dating -> Just for me) takes the same
# lock order, so a path change and the switch serialise and the pause holds.
run "path change (Dating to Just for me) vs the country switch" "$FX_GH" \\
  "SET race.sleep_dating_profiles_update = '2:race.s1';
   SELECT race.call(race.id('03'), 'SELECT public.set_my_path(''just_me'')') ->> 'tab';" \\
  "$SWITCH_GH" \\
  "SELECT CASE WHEN NOT ($SWITCH_RAN) THEN 'the switch did not run'
               WHEN race.enrol(race.id('03')) = 'paused/path_change'
                    AND (SELECT path FROM public.users WHERE id = race.id('03')) = 'just_me'
               THEN 'ok' ELSE 'path pause lost: ' || coalesce(race.enrol(race.id('03')), 'none') END;" serialised

'''
s = s.replace(anchor, case + anchor)
old_head = """#   same-country (pause, plain pause, withdrawal, country change, exit):"""
new_head = """#   same-country (pause, plain pause, withdrawal, country change, exit,
#   and Spec 2 W2's path change):"""
assert s.count(old_head) == 1
s = s.replace(old_head, new_head)
p.write_text(s)
print('dating_kill_switch_races.sh: the W2 path-change case added')
```

```bash
D=.superpowers/sdd/2026-11-07-spec2-w2
python3 -I $D/edit_races_T3.py
createdb -T attune_spec3a w2_race
bash scripts/concurrency/dating_kill_switch_races.sh w2_race | tail -18
dropdb w2_race
```

Expected: `dating_kill_switch_races.sh: the W2 path-change case added`, then **eighteen** `PASS` lines (the count today: this step expected eight when the plan was written; Task 2's fix round 1 made it 10, this step 11, Task 3's fix round 14 and Task 4's fix round 18, and every later gate expects 18; batch 6 ran 18/18 on a scratch copy). The cross-border cases may show 1-2 deadlocks "detected and retried"; the same-country ones, the path change among them, 0. The eight lines as Task 3 first wrote them:

```text
PASS  pause (not plain) vs the country switch (deadlocks detected and retried: 0)
PASS  pause (plain man) vs the country switch (deadlocks detected and retried: 0)
PASS  consent withdrawal (leaving) vs the country switch (deadlocks detected and retried: 0)
PASS  exit vs the country switch (deadlocks detected and retried: 0)
PASS  path change (Dating to Just for me) vs the country switch (deadlocks detected and retried: 0)
PASS  country change (GB to GH) vs the global flag off (deadlocks detected and retried: 0)
PASS  pause across the border vs the country switch (deadlocks detected and retried: 2)
PASS  withdrawal across the border vs the country switch (deadlocks detected and retried: 0)
```

(`createdb -T` needs no other session on `attune_spec3a`; close any open `psql` first. The race mutant was checked while writing this plan: with the trigger's `PERFORM private.dating_lock_setup(NEW.id);` removed, the path-change case fails with `3 deadlock(s): the shared lock order did not serialise it`.)

- [ ] **Step 8: The local harness (edit only, never run)**

```bash
D=.superpowers/sdd/2026-11-07-spec2-w2
python3 -I $D/grants_line.py supabase/migrations/20261107120010_dating_v2_gentle_wait_grants.sql \
  "Spec 2 W2: the users.path trigger function is no API role's." \
  supabase/migrations/20261107130010_dating_v2_path_pause_grants.sql
```

Expected: `local_pg_grants.sql: one \i block added`.

### Task 4: Migration 3: `get_dating_home` v1, the reflection, the gentle-wait counters; the Batch A gate (§3.1, §3.2 D0, §4.3, §4.4, §6.9, A-10; P-10-P-12, P-16, P-17)

**Files:**
- Create: `supabase/migrations/20261107140000_dating_v2_home.sql`, `…140010_dating_v2_home_grants.sql`, `supabase/tests/dating_v2_home_contracts.sql`, `$D/{canary_T4.sql, edit_shared_contracts_T4.py, mut_T4.py}`
- Modify: `supabase/tests/dating_rls_canary.sql`, `supabase/tests/service_role_grants_test.sql`, `supabase/tests/dating_v2_setup_contracts.sql`, `scripts/local_pg_grants.sql`

**Interfaces:**
- Consumes: Task 2's `private.dating_gentle_wait_opens_at`, `dating_eligibility` gate 5; W1's `private.dating_setup_guard`, `private.dating_invalid`, `private.dating_lock_setup`, `private.dating_consent_granted`, `dating_country_config`, `private.dating_phone_country`, `private.dating_exit_internal`.
- Produces: everything listed under "Migration 3" in "Interfaces this plan produces".

- [ ] **Step 1: Write the failing contract**

Create `supabase/tests/dating_v2_home_contracts.sql` with exactly:

```sql
-- supabase/tests/dating_v2_home_contracts.sql
-- Spec 2 W2 (§3.1, §3.2 D0, §4.3, §4.4, §6.9; I-4, A-10): get_dating_home
-- v1 names every state the person is in from their own data only (A), the
-- setup resume step (B), the cool-off and the first drop (C), never a
-- report or a block (D); the gentle-wait reflection is the author's alone,
-- pre-validated, never gated to clear (E), and its two counters (F).
-- One BEGIN ... ROLLBACK. Run only on attune_spec3a:
--   psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/dating_v2_home_contracts.sql
-- Fixture ids 5e2f0000-0000-0000-0000-0000000000NN; phones 15558705NN.
BEGIN;

DO $$
BEGIN
  PERFORM set_config('app.settings.dating_exclusion_key', 'spec2-w2-home-key', true);
END $$;
SELECT private.seed_dating_exclusion_key_fingerprint() AS seeded \gset
INSERT INTO public.feature_flags (key, enabled) VALUES ('dating_mode_enabled', true)
ON CONFLICT (key) DO UPDATE SET enabled = true;
SELECT public.publish_country_config('GH', '{"dating_enabled": true}') AS gh \gset
SELECT public.publish_country_config('GB', '{"dating_enabled": true}') AS gb \gset

CREATE FUNCTION pg_temp.id(p_n text) RETURNS uuid LANGUAGE sql IMMUTABLE AS $$
  SELECT ('5e2f0000-0000-0000-0000-0000000000' || p_n)::uuid;
$$;
-- An adult [p_n] on the Dating path whose account is [p_age] old.
CREATE FUNCTION pg_temp.person(p_n text, p_age interval DEFAULT interval '40 days') RETURNS uuid LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO auth.users (id, phone, phone_confirmed_at, created_at)
  VALUES (pg_temp.id(p_n), '15558705' || p_n, now(), now() - p_age);
  INSERT INTO public.users (id, phone, display_name, path, created_at, eula_accepted_at, eula_version)
  VALUES (pg_temp.id(p_n), '15558705' || p_n, 'Home ' || p_n, 'dating', now() - p_age, now(), '2');
  INSERT INTO public.account_birthdates (user_id, birth_date) VALUES (pg_temp.id(p_n), current_date - interval '30 years');
  RETURN pg_temp.id(p_n);
END $$;
CREATE FUNCTION pg_temp.as_person(p uuid) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claim.sub', p::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', p, 'role', 'authenticated')::text, true);
END $$;
CREATE FUNCTION pg_temp.as_db() RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  RESET ROLE;
  PERFORM set_config('request.jwt.claim.sub', '', true);
  PERFORM set_config('request.jwt.claims', '', true);
END $$;
CREATE FUNCTION pg_temp.home(p uuid) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
  v jsonb;
BEGIN
  PERFORM pg_temp.as_person(p);
  v := public.get_dating_home();
  PERFORM pg_temp.as_db();
  RETURN v;
END $$;
CREATE FUNCTION pg_temp.state(p uuid) RETURNS text LANGUAGE sql AS $$
  SELECT pg_temp.home(p) ->> 'state';
$$;
CREATE FUNCTION pg_temp.save(p uuid, p_answers jsonb) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
  v jsonb;
BEGIN
  PERFORM pg_temp.as_person(p);
  v := public.save_gentle_wait_reflection(p_answers);
  PERFORM pg_temp.as_db();
  RETURN v;
END $$;
CREATE FUNCTION pg_temp.reflection(p uuid) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
  v jsonb;
BEGIN
  PERFORM pg_temp.as_person(p);
  v := public.get_my_gentle_wait_reflection();
  PERFORM pg_temp.as_db();
  RETURN v;
END $$;
CREATE FUNCTION pg_temp.metric(p_key text) RETURNS bigint LANGUAGE sql AS $$
  SELECT coalesce((SELECT sum(c.count) FROM public.metric_counters AS c
                    WHERE c.day = (now() AT TIME ZONE 'utc')::date AND c.key = p_key), 0)::bigint;
$$;
-- Runs [p_setup] then returns [p_probe]'s value, undoing both.
CREATE FUNCTION pg_temp.probe(p_setup text[], p_probe text) RETURNS text LANGUAGE plpgsql AS $$
DECLARE
  v text;
  v_sql text;
BEGIN
  BEGIN
    FOREACH v_sql IN ARRAY p_setup LOOP
      EXECUTE v_sql;
    END LOOP;
    EXECUTE p_probe INTO v;
    RAISE EXCEPTION 'w2:probe_undo';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM IS DISTINCT FROM 'w2:probe_undo' THEN
      RAISE;
    END IF;
  END;
  RETURN coalesce(v, '<NULL>');
END $$;

-- =====================================================================
-- A. Every state, with exactly the data that state needs.
-- =====================================================================
DO $a$
DECLARE
  v_new constant uuid := pg_temp.person('01');
  v_young constant uuid := pg_temp.person('02');
  v_eula1 constant uuid := pg_temp.person('03');
  v_suspended constant uuid := pg_temp.person('04');
  v_held constant uuid := pg_temp.person('05');
  v_safety constant uuid := pg_temp.person('06');
  v_age constant uuid := pg_temp.person('07');
  v_lagos constant uuid := pg_temp.person('08');
  v_volta constant uuid := pg_temp.person('09');
  v_inviter constant uuid := pg_temp.person('10');
  v_coupled constant uuid := pg_temp.person('11');
  v_partner constant uuid := pg_temp.person('12');
  v_wait constant uuid := pg_temp.person('13');
  v_ex constant uuid := pg_temp.person('14');
  v_paused constant uuid := pg_temp.person('15');
  v_lifted constant uuid := pg_temp.person('16');
  v_left constant uuid := pg_temp.person('17');
  v_ended timestamptz;
  v jsonb;
  v_msg text;
BEGIN
  IF has_function_privilege('anon', 'public.get_dating_home()', 'EXECUTE')
     OR has_function_privilege('service_role', 'public.get_dating_home()', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.get_dating_home()', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: get_dating_home is not the app''s alone';
  END IF;
  BEGIN
    PERFORM public.get_dating_home();
    RAISE EXCEPTION 'CONTRACT VIOLATED: get_dating_home answered without a signed-in person';
  EXCEPTION WHEN insufficient_privilege THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    IF v_msg IS DISTINCT FROM 'not_authenticated' THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: signed out, get_dating_home raised %', v_msg;
    END IF;
  END;

  IF pg_temp.home(v_new) IS DISTINCT FROM '{"state": "not_started"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: nothing set up is %', pg_temp.home(v_new);
  END IF;
  UPDATE public.feature_flags SET enabled = false WHERE key = 'dating_mode_enabled';
  IF pg_temp.home(v_new) IS DISTINCT FROM '{"state": "feature_unavailable", "country": null}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: with Dating off the home is %', pg_temp.home(v_new);
  END IF;
  UPDATE public.feature_flags SET enabled = true WHERE key = 'dating_mode_enabled';

  -- The person's own standing (gates 2 and 3), most serious first.
  UPDATE public.account_birthdates SET birth_date = current_date - interval '17 years' WHERE user_id = v_young;
  UPDATE public.users SET eula_version = '1' WHERE id = v_eula1;
  INSERT INTO public.dating_account_restrictions (user_id, restriction_type) VALUES (v_suspended, 'suspended');
  INSERT INTO public.dating_account_restrictions (user_id, restriction_type) VALUES (v_held, 'moderation_hold');
  PERFORM public.place_account_hold(v_safety, 'safety_review', 'spec2-w2-home');
  PERFORM public.place_account_hold(v_age, 'age_review', 'spec2-w2-home');
  IF pg_temp.home(v_young) IS DISTINCT FROM '{"state": "unavailable"}'::jsonb
     OR pg_temp.home(v_eula1) IS DISTINCT FROM '{"state": "unavailable"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an under-18 or EULA v1 account is % / %', pg_temp.home(v_young), pg_temp.home(v_eula1);
  END IF;
  IF pg_temp.home(v_suspended) IS DISTINCT FROM '{"state": "restricted"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a suspended account is %', pg_temp.home(v_suspended);
  END IF;
  IF pg_temp.home(v_held) IS DISTINCT FROM '{"state": "hold"}'::jsonb OR pg_temp.home(v_safety) IS DISTINCT FROM '{"state": "hold"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an interim or safety hold is % / %', pg_temp.home(v_held), pg_temp.home(v_safety);
  END IF;
  IF pg_temp.home(v_age) IS DISTINCT FROM '{"state": "age_review"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an age review is %', pg_temp.home(v_age);
  END IF;
  -- A lifted suspension is no restriction: the age review shows.
  INSERT INTO public.dating_account_restrictions (user_id, restriction_type, lifted_at) VALUES (v_age, 'suspended', now());
  IF pg_temp.state(v_age) IS DISTINCT FROM 'age_review' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a lifted suspension still reads as %', pg_temp.state(v_age);
  END IF;
  -- A suspension outranks a hold.
  INSERT INTO public.dating_account_restrictions (user_id, restriction_type) VALUES (v_held, 'suspended');
  IF pg_temp.state(v_held) IS DISTINCT FROM 'restricted' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a suspension and a hold read as %', pg_temp.state(v_held);
  END IF;

  -- The country and region (gate 6).
  INSERT INTO public.dating_profiles (user_id, display_name, country_code, region_code) VALUES
    (v_lagos, 'Lagos', 'NG', NULL), (v_volta, 'Volta', 'GH', 'TV');
  IF pg_temp.home(v_lagos) IS DISTINCT FROM '{"state": "country_closed", "country": "NG"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a closed country is %', pg_temp.home(v_lagos);
  END IF;
  IF pg_temp.home(v_volta) IS DISTINCT FROM '{"state": "region_closed", "country": "GH", "region": "TV", "open_regions": ["AA", "AH"]}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a closed region is %', pg_temp.home(v_volta);
  END IF;
  UPDATE public.feature_flags SET enabled = false WHERE key = 'dating_mode_enabled';
  IF pg_temp.home(v_lagos) IS DISTINCT FROM '{"state": "feature_unavailable", "country": "NG"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: with Dating off a person with a Dating country sees %', pg_temp.home(v_lagos);
  END IF;
  UPDATE public.feature_flags SET enabled = true WHERE key = 'dating_mode_enabled';

  -- The relationship guard (gate 4): paused if enrolled, else unavailable.
  INSERT INTO public.relationships (user_a, user_b, status, invite_code, invite_expires_at)
  VALUES (v_inviter, NULL, 'pending', 'W2HOME01', now() + interval '1 day');
  INSERT INTO public.dating_enrollments (user_id, state) VALUES (v_coupled, 'active');
  INSERT INTO public.relationships (user_a, user_b, status) VALUES (v_coupled, v_partner, 'active');
  IF pg_temp.home(v_inviter) IS DISTINCT FROM '{"state": "unavailable"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an inviter never enrolled is %', pg_temp.home(v_inviter);
  END IF;
  IF pg_temp.home(v_coupled) IS DISTINCT FROM '{"state": "paused", "pause_reason": "relationship"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an enrolled person who entered a relationship is %', pg_temp.home(v_coupled);
  END IF;

  -- The gentle wait: the dates and where setup would resume.
  INSERT INTO public.relationships (user_a, user_b, status, ended_at) VALUES (v_wait, v_ex, 'ended', now() - interval '10 days')
  RETURNING ended_at INTO v_ended;
  IF pg_temp.home(v_wait) IS DISTINCT FROM jsonb_build_object('state', 'gentle_wait', 'ended_at', v_ended,
                                                             'opens_at', v_ended + interval '30 days', 'next_step', 'how') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the gentle wait is %', pg_temp.home(v_wait);
  END IF;
  INSERT INTO public.dating_profiles (user_id, display_name, intention, not_married_attested_at, attestation_version)
  VALUES (v_wait, 'Waits', 'marriage', now(), '2026-10-v1');
  IF pg_temp.home(v_wait) ->> 'state' IS DISTINCT FROM 'gentle_wait' OR pg_temp.home(v_wait) ->> 'next_step' IS DISTINCT FROM 'where' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: setting up during the wait is %', pg_temp.home(v_wait);
  END IF;
  -- Paused (own reason), and exited, and suspended without a live restriction.
  INSERT INTO public.dating_enrollments (user_id, state, pause_reason, paused_at) VALUES (v_paused, 'paused', 'user', now());
  INSERT INTO public.dating_enrollments (user_id, state) VALUES (v_left, 'exited');
  INSERT INTO public.dating_enrollments (user_id, state) VALUES (v_lifted, 'suspended');
  IF pg_temp.home(v_paused) IS DISTINCT FROM '{"state": "paused", "pause_reason": "user"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a paused person is %', pg_temp.home(v_paused);
  END IF;
  IF pg_temp.home(v_left) IS DISTINCT FROM '{"state": "not_started"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a person who left Dating is %', pg_temp.home(v_left);
  END IF;
  IF pg_temp.home(v_lifted) IS DISTINCT FROM '{"state": "unavailable"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a suspended enrolment with no live restriction is %', pg_temp.home(v_lifted);
  END IF;
END $a$;

-- A2. Fail closed: an untrusted device, a key that isn't ready, an
--     unknown or NULL eligibility reason.
DO $a2$
DECLARE
  v_new constant uuid := pg_temp.id('01');
  v text;
BEGIN
  v := pg_temp.probe(ARRAY[
    $s$CREATE OR REPLACE FUNCTION public.dating_require_trusted_device() RETURNS boolean LANGUAGE sql STABLE AS $f$ SELECT NULL::boolean $f$$s$],
    format('SELECT pg_temp.home(%L)::text', v_new));
  IF v IS DISTINCT FROM '{"state": "reverify_device"}' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an untrusted device (NULL) saw %', v;
  END IF;
  v := pg_temp.probe(ARRAY[
    $s$CREATE OR REPLACE FUNCTION private.dating_exclusion_key_ready() RETURNS boolean LANGUAGE sql STABLE AS $f$ SELECT false $f$$s$],
    format('SELECT pg_temp.home(%L)::text', v_new));
  IF v IS DISTINCT FROM '{"state": "feature_unavailable", "country": null}' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: without a ready exclusion key the home is %', v;
  END IF;
  v := pg_temp.probe(ARRAY[
    $s$CREATE OR REPLACE FUNCTION public.dating_eligibility(p_user uuid, p_scope text DEFAULT 'candidate') RETURNS text LANGUAGE sql STABLE AS $f$ SELECT 'some_new_gate'::text $f$$s$],
    format('SELECT pg_temp.home(%L)::text', v_new));
  IF v IS DISTINCT FROM '{"state": "unavailable"}' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an unknown eligibility reason gave %', v;
  END IF;
  v := pg_temp.probe(ARRAY[
    $s$CREATE OR REPLACE FUNCTION public.dating_eligibility(p_user uuid, p_scope text DEFAULT 'candidate') RETURNS text LANGUAGE sql STABLE AS $f$ SELECT NULL::text $f$$s$],
    format('SELECT pg_temp.home(%L)::text', v_new));
  IF v IS DISTINCT FROM '{"state": "unavailable"}' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a NULL eligibility reason gave %', v;
  END IF;
END $a2$;

-- =====================================================================
-- B. Setup resumes at the first step not done (§3.2, §3.14 step names);
--    faith (D8) is optional.
-- =====================================================================
DO $b$
DECLARE
  v constant uuid := pg_temp.person('20');
  v_step text;
BEGIN
  INSERT INTO public.dating_profiles (user_id, display_name) VALUES (v, 'Steps');
  IF pg_temp.home(v) IS DISTINCT FROM '{"state": "setup_in_progress", "next_step": "looking-for"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a bare profile resumes at %', pg_temp.home(v);
  END IF;
  UPDATE public.dating_profiles SET intention = 'committed' WHERE user_id = v;
  v_step := pg_temp.home(v) ->> 'next_step';
  IF v_step IS DISTINCT FROM 'looking-for' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an intention without the attestation resumes at %', v_step;
  END IF;
  UPDATE public.dating_profiles SET not_married_attested_at = now(), attestation_version = '2026-10-v1' WHERE user_id = v;
  v_step := pg_temp.home(v) ->> 'next_step';
  IF v_step IS DISTINCT FROM 'where' THEN RAISE EXCEPTION 'CONTRACT VIOLATED: after D2 setup resumes at %', v_step; END IF;
  UPDATE public.dating_profiles SET country_code = 'GH' WHERE user_id = v;
  v_step := pg_temp.home(v) ->> 'next_step';
  IF v_step IS DISTINCT FROM 'where' THEN RAISE EXCEPTION 'CONTRACT VIOLATED: a country without a region resumes at %', v_step; END IF;
  UPDATE public.dating_profiles SET region_code = 'AA' WHERE user_id = v;
  v_step := pg_temp.home(v) ->> 'next_step';
  IF v_step IS DISTINCT FROM 'privacy' THEN RAISE EXCEPTION 'CONTRACT VIOLATED: after D3 setup resumes at %', v_step; END IF;
  INSERT INTO public.dating_enrollments (user_id, state) VALUES (v, 'profile_draft');
  INSERT INTO public.dating_consent_events (user_id, idempotency_key, purpose, action, policy_version, occurred_at)
  SELECT v, 'w2-home-' || p, p, 'granted', 'dating-2.0', clock_timestamp()
    FROM unnest(ARRAY['dating_terms', 'dating_opt_in']) AS p;
  v_step := pg_temp.home(v) ->> 'next_step';
  IF v_step IS DISTINCT FROM 'privacy' THEN RAISE EXCEPTION 'CONTRACT VIOLATED: without the special-category consent setup resumes at %', v_step; END IF;
  INSERT INTO public.dating_consent_events (user_id, idempotency_key, purpose, action, policy_version, occurred_at)
  VALUES (v, 'w2-home-special', 'special_category_profile', 'granted', 'dating-2.0', clock_timestamp());
  v_step := pg_temp.home(v) ->> 'next_step';
  IF v_step IS DISTINCT FROM 'you' THEN RAISE EXCEPTION 'CONTRACT VIOLATED: after D4 setup resumes at %', v_step; END IF;
  INSERT INTO public.dating_profile_sensitive (user_id, identity_enc) VALUES (v, '\x01'::bytea);
  v_step := pg_temp.home(v) ->> 'next_step';
  IF v_step IS DISTINCT FROM 'meet' THEN RAISE EXCEPTION 'CONTRACT VIOLATED: after D5 setup resumes at %', v_step; END IF;
  UPDATE public.dating_profile_sensitive SET seeking_enc = '\x01'::bytea WHERE user_id = v;
  v_step := pg_temp.home(v) ->> 'next_step';
  IF v_step IS DISTINCT FROM 'children' THEN RAISE EXCEPTION 'CONTRACT VIOLATED: after D6 setup resumes at %', v_step; END IF;
  UPDATE public.dating_profiles SET children_have = false, children_want = 'open' WHERE user_id = v;
  v_step := pg_temp.home(v) ->> 'next_step';
  IF v_step IS DISTINCT FROM 'photos' THEN RAISE EXCEPTION 'CONTRACT VIOLATED: after D7 (faith optional) setup resumes at %', v_step; END IF;
  INSERT INTO public.dating_profile_photos (user_id, storage_key, position, moderation_state) VALUES
    (v, 'w2-home/' || v || '-1.jpg', 1, 'approved'), (v, 'w2-home/' || v || '-2.jpg', 2, 'pending');
  v_step := pg_temp.home(v) ->> 'next_step';
  IF v_step IS DISTINCT FROM 'photos' THEN RAISE EXCEPTION 'CONTRACT VIOLATED: one approved photo resumes at %', v_step; END IF;
  UPDATE public.dating_profile_photos SET moderation_state = 'approved' WHERE user_id = v;
  v_step := pg_temp.home(v) ->> 'next_step';
  IF v_step IS DISTINCT FROM 'prompts' THEN RAISE EXCEPTION 'CONTRACT VIOLATED: after D9 setup resumes at %', v_step; END IF;
  INSERT INTO public.dating_prompts (user_id, position, prompt_id, answer) VALUES
    (v, 1, 'perfect_sunday', 'A long walk and jollof.'), (v, 2, 'ask_me_about', 'The best chalet in Kumasi.');
  v_step := pg_temp.home(v) ->> 'next_step';
  IF v_step IS DISTINCT FROM 'verify' THEN RAISE EXCEPTION 'CONTRACT VIOLATED: after D10 setup resumes at %', v_step; END IF;
  UPDATE public.dating_profiles SET verification_state = 'verified' WHERE user_id = v;
  v_step := pg_temp.home(v) ->> 'next_step';
  IF v_step IS DISTINCT FROM 'verify' THEN RAISE EXCEPTION 'CONTRACT VIOLATED: verified without the age check resumes at %', v_step; END IF;
  INSERT INTO public.dating_age_verifications (user_id, birth_date, verification_method, verified_at)
  VALUES (v, current_date - interval '30 years', 'test', now());
  v_step := pg_temp.home(v) ->> 'next_step';
  IF v_step IS DISTINCT FROM 'preview' THEN RAISE EXCEPTION 'CONTRACT VIOLATED: after D11 setup resumes at %', v_step; END IF;
  -- Each helper is the database's own.
  IF has_function_privilege('authenticated', 'private.dating_next_step(uuid)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'private.dating_unavailable_state(uuid)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'private.dating_first_drop_at(uuid,timestamptz)', 'EXECUTE')
     OR has_function_privilege('service_role', 'private.dating_next_step(uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a home helper is callable by an API role';
  END IF;
END $b$;

-- =====================================================================
-- C. Active: the first drop is the later of the open date and 72 h from
--    account creation, at the person's drop time in the country's zone.
-- =====================================================================
DO $c$
DECLARE
  v_fresh constant uuid := pg_temp.person('30', interval '1 day');
  v_london constant uuid := pg_temp.person('31', interval '2 days');
  v_waiting constant uuid := pg_temp.person('32');
  v_ex constant uuid := pg_temp.person('33');
  v_open constant uuid := pg_temp.person('34');
  v_lagos constant uuid := pg_temp.person('36');
  v_after timestamptz;
  v jsonb;
  v_at timestamptz;
BEGIN
  INSERT INTO public.dating_enrollments (user_id, state, activated_at) VALUES
    (v_fresh, 'active', now()), (v_london, 'active', now()), (v_waiting, 'active', now()), (v_open, 'active', now());
  INSERT INTO public.dating_profiles (user_id, display_name, profile_state, country_code, region_code) VALUES
    (v_fresh, 'Fresh', 'active', 'GH', 'AA'), (v_london, 'London', 'active', 'GB', 'TLI'),
    (v_waiting, 'Waiting', 'active', 'GH', 'AH'), (v_open, 'Open', 'active', 'GH', 'AA');
  INSERT INTO public.dating_settings (user_id, drop_time) VALUES (v_fresh, '22:00'), (v_london, '07:30');
  -- 72 h from creation, Accra, 22:00.
  v := pg_temp.home(v_fresh);
  v_after := (SELECT u.created_at FROM public.users AS u WHERE u.id = v_fresh) + interval '72 hours';
  v_at := (v ->> 'first_drop_at')::timestamptz;
  IF v ->> 'state' IS DISTINCT FROM 'cool_off' OR (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(v) AS k) IS DISTINCT FROM ARRAY['first_drop_at', 'state']
     OR v_at < v_after OR v_at >= v_after + interval '1 day'
     OR (v_at AT TIME ZONE 'Africa/Accra')::time IS DISTINCT FROM time '22:00' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the cool-off from account creation reads % (72 h after creation: %)', v, v_after;
  END IF;
  -- London's own clock (summer or winter time), 07:30.
  v := pg_temp.home(v_london);
  v_after := (SELECT u.created_at FROM public.users AS u WHERE u.id = v_london) + interval '72 hours';
  v_at := (v ->> 'first_drop_at')::timestamptz;
  IF v ->> 'state' IS DISTINCT FROM 'cool_off' OR v_at < v_after OR v_at >= v_after + interval '1 day'
     OR (v_at AT TIME ZONE 'Europe/London')::time IS DISTINCT FROM time '07:30' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a London first drop reads % (after %)', v, v_after;
  END IF;
  -- Activated during the wait: the open date decides, at the default 19:00.
  INSERT INTO public.relationships (user_a, user_b, status, ended_at) VALUES (v_waiting, v_ex, 'ended', now() - interval '20 days');
  v_after := private.dating_gentle_wait_opens_at(v_waiting);
  v := pg_temp.home(v_waiting);
  v_at := (v ->> 'first_drop_at')::timestamptz;
  IF v ->> 'state' IS DISTINCT FROM 'cool_off' OR v_at < v_after OR v_at >= v_after + interval '1 day'
     OR (v_at AT TIME ZONE 'Africa/Accra')::time IS DISTINCT FROM time '19:00' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: activated during the wait the home reads % (open date %)', v, v_after;
  END IF;
  IF pg_temp.home(v_open) IS DISTINCT FROM '{"state": "active"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: past both dates the home is %', pg_temp.home(v_open);
  END IF;
  -- A zone away from UTC: Lagos (UTC+1), the default 19:00 (the helper).
  PERFORM public.publish_country_config('NG', '{"reference_tz": "Africa/Lagos"}');
  INSERT INTO public.dating_profiles (user_id, display_name, country_code) VALUES (v_lagos, 'Lagos', 'NG');
  v_at := private.dating_first_drop_at(v_lagos, timestamptz '2026-11-10 17:30:00+00');
  IF v_at IS DISTINCT FROM timestamptz '2026-11-10 18:00:00+00'
     OR private.dating_first_drop_at(v_lagos, timestamptz '2026-11-10 18:30:00+00') IS DISTINCT FROM timestamptz '2026-11-11 18:00:00+00' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the first drop ignores the country''s zone (%)', v_at;
  END IF;
END $c$;

-- =====================================================================
-- D. Nothing tells a reported or blocked person anything: a report about
--    the person and a block of them change nothing in their home.
-- =====================================================================
DO $d$
DECLARE
  v_target constant uuid := pg_temp.id('34');
  v_reporter constant uuid := pg_temp.person('35');
  v_before jsonb;
BEGIN
  v_before := pg_temp.home(v_target);
  INSERT INTO public.dating_reports (reporter_user_id, target_user_id, category) VALUES (v_reporter, v_target, 'harassment');
  INSERT INTO public.dating_blocks (blocker_user_id, blocked_user_id, pair_key)
  VALUES (v_reporter, v_target, public.dating_pair_key(v_reporter, v_target));
  IF pg_temp.home(v_target) IS DISTINCT FROM v_before OR v_before IS DISTINCT FROM '{"state": "active"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a report or a block showed in the person''s home (% -> %)', v_before, pg_temp.home(v_target);
  END IF;
END $d$;

-- =====================================================================
-- E. The reflection: the author's alone, pre-validated, never gated to
--    clear; trimmed; blank answers dropped.
-- =====================================================================
DO $e$
DECLARE
  v_wait constant uuid := pg_temp.id('13');
  v_other constant uuid := pg_temp.id('01');
  v_young constant uuid := pg_temp.id('02');
  v jsonb;
  v_msg text;
BEGIN
  IF has_table_privilege('authenticated', 'public.dating_gentle_wait_reflections', 'SELECT')
     OR has_table_privilege('anon', 'public.dating_gentle_wait_reflections', 'SELECT')
     OR has_table_privilege('service_role', 'public.dating_gentle_wait_reflections', 'SELECT')
     OR NOT (SELECT c.relrowsecurity FROM pg_class AS c WHERE c.oid = 'public.dating_gentle_wait_reflections'::regclass) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the reflections table is readable by an API role, or RLS is off';
  END IF;
  -- Invalid input is answered, never raised, and nothing is stored. (Each
  -- write and the read that checks it are separate statements.)
  v := jsonb_build_array(pg_temp.save(v_wait, NULL), pg_temp.save(v_wait, '["a"]'), pg_temp.save(v_wait, '{"q4": "x"}'),
                         pg_temp.save(v_wait, '{"q1": 7}'), pg_temp.save(v_wait, jsonb_build_object('q2', repeat('é', 501))));
  IF v IS DISTINCT FROM '[{"ok": false, "field": "answers", "reason": "invalid"}, {"ok": false, "field": "answers", "reason": "invalid"},
                          {"ok": false, "field": "answers", "reason": "invalid"}, {"ok": false, "field": "q1", "reason": "invalid"},
                          {"ok": false, "field": "q2", "reason": "invalid"}]'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: invalid reflections were answered %', v;
  END IF;
  IF EXISTS (SELECT 1 FROM public.dating_gentle_wait_reflections WHERE user_id = v_wait) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an invalid reflection was stored';
  END IF;
  v := pg_temp.save(v_wait, jsonb_build_object('q1', '  To listen first.  ', 'q2', '', 'q3', repeat('é', 500)));
  IF v ->> 'ok' IS DISTINCT FROM 'true' OR v ->> 'saved_at' IS NULL
     OR (SELECT g.answers FROM public.dating_gentle_wait_reflections AS g WHERE g.user_id = v_wait)
        IS DISTINCT FROM jsonb_build_object('q1', 'To listen first.', 'q3', repeat('é', 500)) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a valid reflection saved as % / %', v,
      (SELECT g.answers FROM public.dating_gentle_wait_reflections AS g WHERE g.user_id = v_wait);
  END IF;
  v := pg_temp.reflection(v_wait);
  IF v -> 'answers' IS DISTINCT FROM jsonb_build_object('q1', 'To listen first.', 'q3', repeat('é', 500))
     OR v ->> 'ok' IS DISTINCT FROM 'true' OR v -> 'saved_at' = 'null'::jsonb
     OR (v ->> 'opens_at')::timestamptz IS DISTINCT FROM private.dating_gentle_wait_opens_at(v_wait)
     OR (v ->> 'ended_at')::timestamptz IS DISTINCT FROM private.dating_gentle_wait_opens_at(v_wait) - interval '30 days' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the author reads %', v;
  END IF;
  -- Someone else reads only their own (nothing).
  v := pg_temp.reflection(v_other);
  IF v IS DISTINCT FROM '{"ok": true, "answers": {}, "ended_at": null, "opens_at": null, "saved_at": null}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: another person read %', v;
  END IF;
  -- Saving needs setup eligibility (an under-18 account, Dating off).
  v := pg_temp.save(v_young, '{"q1": "Something"}');
  IF v IS DISTINCT FROM '{"ok": false, "reason": "not_eligible"}'::jsonb
     OR EXISTS (SELECT 1 FROM public.dating_gentle_wait_reflections WHERE user_id = v_young) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an under-18 account saved a reflection (%)', v;
  END IF;
  UPDATE public.feature_flags SET enabled = false WHERE key = 'dating_mode_enabled';
  v := pg_temp.save(v_wait, '{"q1": "Changed"}');
  IF v IS DISTINCT FROM '{"ok": false, "reason": "not_eligible"}'::jsonb
     OR (SELECT g.answers ->> 'q1' FROM public.dating_gentle_wait_reflections AS g WHERE g.user_id = v_wait) IS DISTINCT FROM 'To listen first.' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a reflection was saved with Dating off (%)', v;
  END IF;
  -- Clearing one's own answers is never gated (exposure-reducing).
  v := pg_temp.save(v_wait, '{"q1": " ", "q2": null}');
  IF v IS DISTINCT FROM '{"ok": true, "saved_at": null}'::jsonb
     OR (SELECT g.answers FROM public.dating_gentle_wait_reflections AS g WHERE g.user_id = v_wait) IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: clearing a reflection with Dating off did not clear it (%)', v;
  END IF;
  UPDATE public.feature_flags SET enabled = true WHERE key = 'dating_mode_enabled';
  -- The table refuses a malformed row even from a definer (defence in depth).
  BEGIN
    INSERT INTO public.dating_gentle_wait_reflections (user_id, answers) VALUES (v_other, '{"q9": "x"}');
    RAISE EXCEPTION 'CONTRACT VIOLATED: the table took a malformed reflection';
  EXCEPTION WHEN check_violation THEN
    NULL;
  END;
END $e$;

-- E2. An untrusted device can't save or read answers, but can clear them;
--     both RPCs take the setup lock before writing.
DO $e2$
DECLARE
  v_wait constant uuid := pg_temp.id('13');
  v text;
  v_src text;
BEGIN
  PERFORM pg_temp.save(v_wait, '{"q2": "Kindness"}');
  v := pg_temp.probe(ARRAY[
    $s$CREATE OR REPLACE FUNCTION public.dating_require_trusted_device() RETURNS boolean LANGUAGE sql STABLE AS $f$ SELECT false $f$$s$],
    format($q$SELECT pg_temp.save(%L, '{"q1": "New"}')::text || ' ' || pg_temp.reflection(%L)::text$q$, v_wait, v_wait)); -- both refuse: nothing to see
  IF v IS DISTINCT FROM '{"ok": false, "reason": "reverify_device"} {"ok": false, "reason": "reverify_device"}' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an untrusted device saved or read a reflection (%)', v;
  END IF;
  v := pg_temp.probe(ARRAY[
    $s$CREATE OR REPLACE FUNCTION public.dating_require_trusted_device() RETURNS boolean LANGUAGE sql STABLE AS $f$ SELECT false $f$$s$],
    format($q$SELECT pg_temp.save(%L, '{}')::text$q$, v_wait));
  IF v IS DISTINCT FROM '{"ok": true, "saved_at": null}' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an untrusted device could not clear its own reflection (%)', v;
  END IF;
  v_src := (SELECT p.prosrc FROM pg_proc AS p WHERE p.oid = 'public.save_gentle_wait_reflection(jsonb)'::regprocedure);
  IF position('private.dating_lock_setup(v_user)' IN v_src) = 0 OR position('private.dating_setup_guard()' IN v_src) = 0
     OR position('private.dating_lock_setup(v_user)' IN v_src) > position('INSERT INTO public.dating_gentle_wait_reflections' IN v_src) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: saving a reflection does not take the setup lock first';
  END IF;
  v_src := (SELECT p.prosrc FROM pg_proc AS p WHERE p.oid = 'public.get_my_gentle_wait_reflection()'::regprocedure);
  IF position('private.dating_lock_setup(v_user)' IN v_src) = 0
     OR position('private.dating_lock_setup(v_user)' IN v_src) > position('INSERT INTO public.dating_gentle_wait_reflections' IN v_src) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: opening D0 writes before the setup lock';
  END IF;
  IF has_function_privilege('anon', 'public.save_gentle_wait_reflection(jsonb)', 'EXECUTE')
     OR has_function_privilege('service_role', 'public.save_gentle_wait_reflection(jsonb)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.get_my_gentle_wait_reflection()', 'EXECUTE')
     OR has_function_privilege('service_role', 'public.get_my_gentle_wait_reflection()', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.save_gentle_wait_reflection(jsonb)', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.get_my_gentle_wait_reflection()', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the reflection RPCs are not the app''s alone';
  END IF;
END $e2$;

-- =====================================================================
-- F. The two §6.9 counters: D0 opened during a wait (once per ending, not
--    outside a wait, not with Dating off), and an account deleted within
--    7 days of that. Exit deletes the reflection.
-- =====================================================================
DO $f$
DECLARE
  v_seer constant uuid := pg_temp.person('40');
  v_ex constant uuid := pg_temp.person('41');
  v_ex2 constant uuid := pg_temp.person('42');
  v_outside constant uuid := pg_temp.id('01');
  v_gone constant uuid := pg_temp.person('43');
  v_old constant uuid := pg_temp.person('44');
  v_ex3 constant uuid := pg_temp.person('45');
  v_leaver constant uuid := pg_temp.id('13');
  v_seen bigint := pg_temp.metric('dating.gentle_wait.seen');
  v_deleted bigint := pg_temp.metric('dating.gentle_wait.account_deleted_7d');
BEGIN
  INSERT INTO public.relationships (user_a, user_b, status, ended_at) VALUES
    (v_seer, v_ex, 'ended', now() - interval '25 days'),
    (v_gone, v_ex3, 'ended', now() - interval '3 days'),
    (v_old, v_ex3, 'ended', now() - interval '12 days');
  PERFORM pg_temp.reflection(v_seer);
  PERFORM pg_temp.reflection(v_seer);
  PERFORM pg_temp.reflection(v_outside);
  IF pg_temp.metric('dating.gentle_wait.seen') IS DISTINCT FROM v_seen + 1
     OR (SELECT g.seen_at FROM public.dating_gentle_wait_reflections AS g WHERE g.user_id = v_seer) IS NULL
     OR EXISTS (SELECT 1 FROM public.dating_gentle_wait_reflections WHERE user_id = v_outside) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: D0 seen counted % times (expected once, and never outside a wait)',
      pg_temp.metric('dating.gentle_wait.seen') - v_seen;
  END IF;
  -- A later ending (another relationship) counts again.
  UPDATE public.dating_gentle_wait_reflections SET seen_at = now() - interval '24 days' WHERE user_id = v_seer;
  INSERT INTO public.relationships (user_a, user_b, status, ended_at) VALUES (v_seer, v_ex2, 'ended', now() - interval '1 day');
  PERFORM pg_temp.reflection(v_seer);
  IF pg_temp.metric('dating.gentle_wait.seen') IS DISTINCT FROM v_seen + 2 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a new ending was not counted as a new view';
  END IF;
  UPDATE public.feature_flags SET enabled = false WHERE key = 'dating_mode_enabled';
  PERFORM pg_temp.reflection(v_gone);
  UPDATE public.feature_flags SET enabled = true WHERE key = 'dating_mode_enabled';
  IF pg_temp.metric('dating.gentle_wait.seen') IS DISTINCT FROM v_seen + 2
     OR EXISTS (SELECT 1 FROM public.dating_gentle_wait_reflections WHERE user_id = v_gone) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: D0 was counted as seen with Dating off';
  END IF;
  -- Deleted 2 days after D0: counted. Deleted 8 days after: not.
  PERFORM pg_temp.reflection(v_gone);
  UPDATE public.dating_gentle_wait_reflections SET seen_at = now() - interval '2 days' WHERE user_id = v_gone;
  PERFORM pg_temp.reflection(v_old);
  UPDATE public.dating_gentle_wait_reflections SET seen_at = now() - interval '8 days' WHERE user_id = v_old;
  DELETE FROM auth.users WHERE id IN (v_gone, v_old);
  IF pg_temp.metric('dating.gentle_wait.account_deleted_7d') IS DISTINCT FROM v_deleted + 1
     OR EXISTS (SELECT 1 FROM public.dating_gentle_wait_reflections WHERE user_id IN (v_gone, v_old)) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: deletions after D0 counted % (expected 1: within 7 days only), or a reflection outlived its account',
      pg_temp.metric('dating.gentle_wait.account_deleted_7d') - v_deleted;
  END IF;
  -- Exit deletes it (W1d's exit names this table).
  PERFORM pg_temp.save(v_leaver, '{"q1": "Leaving"}');
  PERFORM private.dating_exit_internal(v_leaver, false);
  IF EXISTS (SELECT 1 FROM public.dating_gentle_wait_reflections WHERE user_id = v_leaver) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: exit kept the gentle-wait reflection';
  END IF;
END $f$;

-- =====================================================================
-- G. (A-10) Spec 1's seam is unchanged by W2: exactly {enabled, enrolled}.
-- =====================================================================
DO $g$
DECLARE
  v jsonb := private.dating_home_summary(pg_temp.id('15'));
BEGIN
  IF v IS DISTINCT FROM '{"enabled": true, "enrolled": true}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: dating_home_summary is %', v;
  END IF;
END $g$;

DO $$ BEGIN RAISE NOTICE 'dating_v2_home_contracts: all held'; END $$;
ROLLBACK;
```

```bash
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/dating_v2_home_contracts.sql 2>&1 | grep -E 'ERROR|all held' | head -1 | sed -E 's/^psql:[^ ]* //'
```

Expected: `ERROR:  function "public.get_dating_home()" does not exist`.

- [ ] **Step 2: Write migration 3 and its twin**

Create `supabase/migrations/20261107140000_dating_v2_home.sql` with exactly:

```sql
-- Spec 2 W2, migration 3 (spec §3.1, §3.2 D0, §4.3, §4.4 Home and Gentle
-- wait, §6.9 gentle-wait keys; I-4, A-10):
--   * dating_gentle_wait_reflections: the person's own three answers (each
--     at most 500 characters, optional), saved_at, and seen_at (when D0 was
--     last opened during a wait, for the two §6.9 counters). RLS on, no API
--     role (the service role included); exit deletes the row (W1d's
--     dating_exit_internal already names this table), account deletion
--     cascades.
--   * save_gentle_wait_reflection(p_answers): pre-validated (an object with
--     only q1-q3, each a string or null, at most 500 characters; anything
--     else is {ok:false, reason:'invalid', field}); saving answers needs the
--     setup guard (lock, trusted device, setup eligibility); clearing them
--     (all blank) needs only the lock (exposure-reducing, never gated).
--   * get_my_gentle_wait_reflection(): own answers plus the wait's dates;
--     while the person is in the wait it records seen_at once per ending
--     and counts dating.gentle_wait.seen.
--   * get_dating_home() v1: the Dating section's one read, {state, ...only
--     what that state needs}: feature_unavailable / country_closed
--     {country}, region_closed {country, region, open_regions},
--     reverify_device, restricted / hold / age_review / unavailable (the
--     person's own standing, never a report or a block), gentle_wait
--     {ended_at, opens_at, next_step}, not_started, setup_in_progress
--     {next_step}, paused {pause_reason}, cool_off {first_drop_at}, active.
--     W4, W5, W7 and W8 re-create it from its live body to add verifying,
--     ready and Today, the restriction's category and away.
--   * Spec 2 W1a's private.dating_carry_on_auth_user_delete() re-created
--     from its live body: an account deleted within 7 days of opening D0
--     counts dating.gentle_wait.account_deleted_7d (the evasion proxy).
-- Grants in 20261107140010_dating_v2_home_grants.sql.
BEGIN;
SET LOCAL lock_timeout = '5s';

CREATE TABLE IF NOT EXISTS public.dating_gentle_wait_reflections (
  user_id uuid PRIMARY KEY REFERENCES public.users(id) ON DELETE CASCADE,
  answers jsonb,
  saved_at timestamptz,
  seen_at timestamptz,
  CONSTRAINT dating_gentle_wait_reflections_answers_check CHECK (
    answers IS NULL OR (
      jsonb_typeof(answers) = 'object'
      AND answers - ARRAY['q1', 'q2', 'q3'] = '{}'::jsonb
      AND coalesce(jsonb_typeof(answers -> 'q1'), 'string') = 'string'
      AND coalesce(jsonb_typeof(answers -> 'q2'), 'string') = 'string'
      AND coalesce(jsonb_typeof(answers -> 'q3'), 'string') = 'string'
      AND coalesce(char_length(answers ->> 'q1'), 0) <= 500
      AND coalesce(char_length(answers ->> 'q2'), 0) <= 500
      AND coalesce(char_length(answers ->> 'q3'), 0) <= 500))
);
ALTER TABLE public.dating_gentle_wait_reflections ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.dating_gentle_wait_reflections FROM PUBLIC, anon, authenticated, service_role;

-- The first setup step not yet done, in §3.14's step names ('how' when
-- nothing is started). Faith (D8) is optional and never blocks a resume.
CREATE OR REPLACE FUNCTION private.dating_next_step(p_user uuid)
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $fn$
  SELECT CASE
    WHEN p.user_id IS NULL
         AND (e.state IS NULL OR e.state IN ('ineligible', 'eligible_to_opt_in', 'exited')) THEN 'how'
    WHEN p.intention IS NULL OR p.not_married_attested_at IS NULL THEN 'looking-for'
    WHEN p.country_code IS NULL OR p.region_code IS NULL THEN 'where'
    WHEN e.state IS NULL OR e.state NOT IN ('profile_draft', 'active', 'paused')
         OR NOT (private.dating_consent_granted(p_user, 'dating_terms')
                 AND private.dating_consent_granted(p_user, 'dating_opt_in')
                 AND private.dating_consent_granted(p_user, 'special_category_profile')) THEN 'privacy'
    WHEN s.identity_enc IS NULL THEN 'you'
    WHEN s.seeking_enc IS NULL THEN 'meet'
    WHEN p.children_have IS NULL OR p.children_want IS NULL THEN 'children'
    WHEN (SELECT count(*) FROM public.dating_profile_photos AS f
           WHERE f.user_id = p_user AND f.moderation_state = 'approved') < 2 THEN 'photos'
    WHEN (SELECT count(*) FROM public.dating_prompts AS q
           WHERE q.user_id = p_user AND q.moderation_state = 'approved') < 2 THEN 'prompts'
    WHEN p.verification_state IS DISTINCT FROM 'verified'
         OR coalesce(public.dating_age_gate_holds(p_user), false) IS NOT TRUE THEN 'verify'
    ELSE 'preview'
  END
    FROM (SELECT p_user AS id) AS me
    LEFT JOIN public.dating_profiles AS p ON p.user_id = me.id
    LEFT JOIN public.dating_enrollments AS e ON e.user_id = me.id
    LEFT JOIN public.dating_profile_sensitive AS s ON s.user_id = me.id;
$fn$;

-- The person's own standing, for an account_unavailable answer: never a
-- report or a block (nothing tells a reported or blocked person anything).
CREATE OR REPLACE FUNCTION private.dating_unavailable_state(p_user uuid)
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $fn$
  SELECT CASE
    WHEN EXISTS (SELECT 1 FROM public.dating_account_restrictions AS r
                  WHERE r.user_id = p_user AND r.restriction_type = 'suspended' AND r.lifted_at IS NULL
                    AND r.starts_at <= now() AND (r.ends_at IS NULL OR r.ends_at > now()))
      OR EXISTS (SELECT 1 FROM public.enforcement_records AS er
                  WHERE er.scope = 'dating' AND er.phone_hmac = public.dating_phone_hmac_for_user(p_user)
                    AND (er.effect_until IS NULL OR er.effect_until > now()) AND er.purge_after > now())
      OR EXISTS (SELECT 1 FROM auth.users AS a
                  WHERE a.id = p_user AND a.banned_until > now()) THEN 'restricted'
    WHEN EXISTS (SELECT 1 FROM public.dating_account_restrictions AS r
                  WHERE r.user_id = p_user AND r.restriction_type IN ('moderation_hold', 'under_review')
                    AND r.lifted_at IS NULL AND r.starts_at <= now() AND (r.ends_at IS NULL OR r.ends_at > now()))
      OR EXISTS (SELECT 1 FROM public.account_holds AS h
                  WHERE h.user_id = p_user AND h.kind = 'safety_review' AND h.resolved_at IS NULL) THEN 'hold'
    WHEN EXISTS (SELECT 1 FROM public.dating_account_restrictions AS r
                  WHERE r.user_id = p_user AND r.restriction_type = 'age_review' AND r.lifted_at IS NULL
                    AND r.starts_at <= now() AND (r.ends_at IS NULL OR r.ends_at > now()))
      OR EXISTS (SELECT 1 FROM public.account_holds AS h
                  WHERE h.user_id = p_user AND h.kind = 'age_review' AND h.resolved_at IS NULL) THEN 'age_review'
    ELSE 'unavailable'
  END;
$fn$;

-- The first drop at or after p_after: the person's drop time (default
-- 19:00) in their Dating country's reference time zone (UTC without one).
CREATE OR REPLACE FUNCTION private.dating_first_drop_at(p_user uuid, p_after timestamptz)
RETURNS timestamptz
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_tz text;
  v_drop time;
  v_at timestamptz;
BEGIN
  SELECT coalesce((public.dating_country_config(p.country_code::text)).reference_tz, 'UTC')
    INTO v_tz FROM public.dating_profiles AS p WHERE p.user_id = p_user;
  v_tz := coalesce(v_tz, 'UTC');
  SELECT t.drop_time INTO v_drop FROM public.dating_settings AS t WHERE t.user_id = p_user;
  v_drop := coalesce(v_drop, time '19:00');
  v_at := ((p_after AT TIME ZONE v_tz)::date + v_drop) AT TIME ZONE v_tz;
  IF v_at < p_after THEN
    v_at := (((p_after AT TIME ZONE v_tz)::date + 1) + v_drop) AT TIME ZONE v_tz;
  END IF;
  RETURN v_at;
END;
$fn$;

CREATE OR REPLACE FUNCTION public.get_dating_home()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_user constant uuid := auth.uid();
  v_reason text;
  v_country text;
  v_region text;
  v_config public.country_safety_config;
  v_enrol public.dating_enrollments;
  v_opens timestamptz;
  v_after timestamptz;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;
  v_reason := public.dating_eligibility(v_user, 'setup');
  SELECT p.country_code::text, p.region_code INTO v_country, v_region
    FROM public.dating_profiles AS p WHERE p.user_id = v_user;
  IF v_reason IS NOT DISTINCT FROM 'feature_unavailable' THEN
    RETURN jsonb_build_object('state', 'feature_unavailable', 'country',
      coalesce(v_country, private.dating_phone_country((SELECT a.phone FROM auth.users AS a WHERE a.id = v_user))));
  END IF;
  IF public.dating_require_trusted_device() IS NOT TRUE THEN
    RETURN jsonb_build_object('state', 'reverify_device');
  END IF;
  IF v_reason IS NOT DISTINCT FROM 'account_unavailable' THEN
    RETURN jsonb_build_object('state', private.dating_unavailable_state(v_user));
  END IF;
  IF v_reason IS NOT DISTINCT FROM 'country_closed' THEN
    RETURN jsonb_build_object('state', 'country_closed', 'country', v_country);
  END IF;
  IF v_reason IS NOT DISTINCT FROM 'region_closed' THEN
    v_config := public.dating_country_config(v_country);
    RETURN jsonb_build_object('state', 'region_closed', 'country', v_country, 'region', v_region,
      'open_regions', to_jsonb(coalesce(v_config.open_regions, ARRAY[]::text[])));
  END IF;
  SELECT * INTO v_enrol FROM public.dating_enrollments AS e WHERE e.user_id = v_user;
  IF v_reason IS NOT DISTINCT FROM 'relationship_active' THEN
    RETURN CASE WHEN v_enrol.state = 'paused'
                THEN jsonb_build_object('state', 'paused', 'pause_reason', v_enrol.pause_reason)
                ELSE jsonb_build_object('state', 'unavailable') END;
  END IF;
  IF v_reason IS DISTINCT FROM 'eligible' THEN
    RETURN jsonb_build_object('state', 'unavailable'); -- an unknown or NULL reason fails closed
  END IF;
  IF v_enrol.state = 'suspended' THEN
    RETURN jsonb_build_object('state', 'unavailable'); -- suspended without a live restriction (W7a routes it)
  END IF;
  IF v_enrol.state = 'paused' THEN
    RETURN jsonb_build_object('state', 'paused', 'pause_reason', v_enrol.pause_reason);
  END IF;
  v_opens := private.dating_gentle_wait_opens_at(v_user);
  IF v_enrol.state = 'active' THEN
    -- The first drop is the later of the open date and the 72 h cool-off
    -- from account creation (§2.1, §2.8).
    v_after := greatest(coalesce(v_opens, '-infinity'::timestamptz),
                        (SELECT u.created_at FROM public.users AS u WHERE u.id = v_user) + interval '72 hours');
    IF v_after > now() THEN
      RETURN jsonb_build_object('state', 'cool_off', 'first_drop_at', private.dating_first_drop_at(v_user, v_after));
    END IF;
    RETURN jsonb_build_object('state', 'active');
  END IF;
  IF v_opens IS NOT NULL THEN
    RETURN jsonb_build_object('state', 'gentle_wait', 'ended_at', v_opens - interval '30 days', 'opens_at', v_opens,
                              'next_step', private.dating_next_step(v_user));
  END IF;
  IF private.dating_next_step(v_user) IS NOT DISTINCT FROM 'how' THEN
    RETURN jsonb_build_object('state', 'not_started');
  END IF;
  RETURN jsonb_build_object('state', 'setup_in_progress', 'next_step', private.dating_next_step(v_user));
END;
$fn$;

CREATE OR REPLACE FUNCTION public.save_gentle_wait_reflection(p_answers jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_user constant uuid := auth.uid();
  v_key text;
  v_value jsonb;
  v_clean jsonb;
  v_reason text;
  v_at timestamptz;
  v_try integer;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;
  -- Pre-validated: no raw constraint error ever reaches the app.
  IF p_answers IS NULL OR jsonb_typeof(p_answers) IS DISTINCT FROM 'object' THEN
    RETURN private.dating_invalid('answers');
  END IF;
  FOR v_key, v_value IN SELECT k, v FROM jsonb_each(p_answers) AS j(k, v) LOOP
    IF v_key NOT IN ('q1', 'q2', 'q3') THEN
      RETURN private.dating_invalid('answers');
    END IF;
    IF jsonb_typeof(v_value) NOT IN ('string', 'null') OR coalesce(char_length(v_value #>> '{}'), 0) > 500 THEN
      RETURN private.dating_invalid(v_key);
    END IF;
  END LOOP;
  v_clean := jsonb_strip_nulls(jsonb_build_object(
    'q1', nullif(btrim(p_answers ->> 'q1'), ''),
    'q2', nullif(btrim(p_answers ->> 'q2'), ''),
    'q3', nullif(btrim(p_answers ->> 'q3'), '')));
  IF v_clean = '{}'::jsonb THEN
    -- Clearing one's own answers is never gated (exposure-reducing).
    PERFORM private.dating_lock_setup(v_user);
  ELSE
    v_reason := private.dating_setup_guard(); -- the lock, the trusted device, setup eligibility
    IF v_reason IS NOT NULL THEN
      RETURN jsonb_build_object('ok', false, 'reason', v_reason);
    END IF;
  END IF;
  v_at := now();
  FOR v_try IN 1..3 LOOP -- a lock conflict is retried (each attempt its own savepoint)
    BEGIN
      IF v_clean = '{}'::jsonb THEN
        UPDATE public.dating_gentle_wait_reflections AS g SET answers = NULL, saved_at = NULL WHERE g.user_id = v_user;
      ELSE
        INSERT INTO public.dating_gentle_wait_reflections AS g (user_id, answers, saved_at)
        VALUES (v_user, v_clean, v_at)
        ON CONFLICT (user_id) DO UPDATE SET answers = EXCLUDED.answers, saved_at = EXCLUDED.saved_at;
      END IF;
      EXIT;
    EXCEPTION WHEN deadlock_detected OR lock_not_available OR serialization_failure THEN
      IF v_try = 3 OR SQLERRM = 'dating:busy' THEN RAISE EXCEPTION 'dating:busy' USING ERRCODE = SQLSTATE; END IF;
    END;
  END LOOP;
  RETURN jsonb_build_object('ok', true, 'saved_at', CASE WHEN v_clean = '{}'::jsonb THEN NULL ELSE v_at END);
END;
$fn$;

CREATE OR REPLACE FUNCTION public.get_my_gentle_wait_reflection()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_user constant uuid := auth.uid();
  v_opens timestamptz;
  v_row public.dating_gentle_wait_reflections;
  v_marked boolean := false;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;
  IF public.dating_require_trusted_device() IS NOT TRUE THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'reverify_device');
  END IF;
  v_opens := private.dating_gentle_wait_opens_at(v_user);
  -- D0 opened during a wait: seen once per ending (§6.9), never while
  -- Dating is closed to the person.
  IF v_opens IS NOT NULL
     AND public.dating_eligibility(v_user, 'setup') IS NOT DISTINCT FROM 'eligible' THEN
    PERFORM private.dating_lock_setup(v_user);
    INSERT INTO public.dating_gentle_wait_reflections AS g (user_id, seen_at)
    VALUES (v_user, now())
    ON CONFLICT (user_id) DO UPDATE SET seen_at = now()
     WHERE g.seen_at IS NULL OR g.seen_at < v_opens - interval '30 days';
    v_marked := FOUND;
    IF v_marked THEN
      PERFORM private.bump_metric_internal('dating.gentle_wait.seen');
    END IF;
  END IF;
  SELECT * INTO v_row FROM public.dating_gentle_wait_reflections AS g WHERE g.user_id = v_user;
  RETURN jsonb_build_object(
    'ok', true,
    'answers', coalesce(v_row.answers, '{}'::jsonb),
    'saved_at', v_row.saved_at,
    'ended_at', v_opens - interval '30 days',
    'opens_at', v_opens);
END;
$fn$;

CREATE OR REPLACE FUNCTION private.dating_carry_on_auth_user_delete()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
BEGIN
  BEGIN -- W1 final fix (I-1)
    PERFORM private.dating_lock_setup(OLD.id); -- W1 final fix (I-1)
  EXCEPTION WHEN OTHERS THEN -- W1 final fix (I-1): never blocks the deletion
    RAISE WARNING 'dating_carry_on_auth_user_delete:lock:%', SQLSTATE; -- W1 final fix (I-1)
  END; -- W1 final fix (I-1)
  BEGIN
    IF private.dating_deletion_carry(OLD.id, true) > 0 THEN
      PERFORM private.bump_metric_internal('dating.deletion.late_carry');
    END IF;
  EXCEPTION WHEN OTHERS THEN
    PERFORM private.bump_metric_internal('dating.deletion.late_carry_failed');
  END;
  BEGIN -- Spec 2 W2 (§6.9): an account deleted within 7 days of opening D0 (the evasion proxy)
    IF EXISTS (SELECT 1 FROM public.dating_gentle_wait_reflections AS g -- Spec 2 W2
                WHERE g.user_id = OLD.id AND g.seen_at > now() - interval '7 days') THEN -- Spec 2 W2
      PERFORM private.bump_metric_internal('dating.gentle_wait.account_deleted_7d'); -- Spec 2 W2
    END IF; -- Spec 2 W2
  EXCEPTION WHEN OTHERS THEN -- Spec 2 W2: never blocks the deletion
    NULL; -- Spec 2 W2
  END; -- Spec 2 W2
  RETURN OLD;
END;
$function$;

REVOKE ALL ON FUNCTION private.dating_next_step(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_unavailable_state(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_first_drop_at(uuid, timestamptz) FROM PUBLIC, anon, authenticated, service_role;

COMMIT;
```

Create `supabase/migrations/20261107140010_dating_v2_home_grants.sql` with exactly:

```sql
-- Spec 2 W2: grants for 20261107140000_dating_v2_home.sql.
-- The reflections table is no API role's (the service role included): the
-- person reaches it through the two definer RPCs only. The three RPCs are
-- the app's (authenticated only); the helpers and the deletion trigger are
-- no API role's.
BEGIN;
SET LOCAL lock_timeout = '5s';
REVOKE ALL ON TABLE public.dating_gentle_wait_reflections FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_next_step(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_unavailable_state(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_first_drop_at(uuid, timestamptz) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_carry_on_auth_user_delete() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.get_dating_home() FROM PUBLIC, anon, service_role;
REVOKE ALL ON FUNCTION public.save_gentle_wait_reflection(jsonb) FROM PUBLIC, anon, service_role;
REVOKE ALL ON FUNCTION public.get_my_gentle_wait_reflection() FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.get_dating_home() TO authenticated;
GRANT EXECUTE ON FUNCTION public.save_gentle_wait_reflection(jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_my_gentle_wait_reflection() TO authenticated;
COMMIT;
```

- [ ] **Step 3: Apply twice; diff the deletion trigger; run the contract**

```bash
for i in 1 2; do
  for f in 20261107140000_dating_v2_home 20261107140010_dating_v2_home_grants; do
    psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/migrations/$f.sql > /dev/null 2>&1; echo "$f exit=$?"
  done
done
D=.superpowers/sdd/2026-11-07-spec2-w2
diff "$D/before/private.dating_carry_on_auth_user_delete().sql" <(psql -X -d attune_spec3a -Atc "select pg_get_functiondef('private.dating_carry_on_auth_user_delete()'::regprocedure)") | grep '^[<>]'
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/dating_v2_home_contracts.sql 2>&1 | grep -E 'ERROR|all held' | head -1 | sed -E 's/^psql:[^ ]* //'
```

Expected: four `exit=0` (the second apply prints `NOTICE: relation "dating_gentle_wait_reflections" already exists, skipping`, hidden); then exactly:

```text
>   BEGIN -- Spec 2 W2 (§6.9): an account deleted within 7 days of opening D0 (the evasion proxy)
>     IF EXISTS (SELECT 1 FROM public.dating_gentle_wait_reflections AS g -- Spec 2 W2
>                 WHERE g.user_id = OLD.id AND g.seen_at > now() - interval '7 days') THEN -- Spec 2 W2
>       PERFORM private.bump_metric_internal('dating.gentle_wait.account_deleted_7d'); -- Spec 2 W2
>     END IF; -- Spec 2 W2
>   EXCEPTION WHEN OTHERS THEN -- Spec 2 W2: never blocks the deletion
>     NULL; -- Spec 2 W2
>   END; -- Spec 2 W2
```

then `NOTICE:  dating_v2_home_contracts: all held`.

- [ ] **Step 4: The canary, Spec 1's service-role test, the photo-reader tripwire**

```bash
for t in dating_rls_canary service_role_grants_test dating_v2_setup_contracts; do
  psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/$t.sql 2>&1 | grep -m1 ERROR | sed -E 's/^psql:[^ ]* //' | cut -c1-160
done
```

Expected (red, one line each): `ERROR:  CONTRACT VIOLATED: Dating grants differ from the allow-list:` (the table and six functions are not listed); `ERROR:  1 table(s) unreadable by service_role -- their workers will read empty queues with no error: dating_gentle_wait_reflections`; `ERROR:  CONTRACT VIOLATED: the functions reading Dating photos changed (review photos after mutual interest): private.dating_exit_internal(uuid, boolean):; private.dating_next_step(uuid):; …`.

Create `$D/canary_T4.sql` with exactly:

```sql
-- ---------------------------------------------------------------------
-- W2 (migration 3): the reflection table is no API role's (the service
-- role included); the home and the two reflection RPCs are the app's; the
-- helpers are the database's own.
-- ---------------------------------------------------------------------
INSERT INTO allowed_rel (name, authenticated, service_dml) VALUES
  ('dating_gentle_wait_reflections', '', '');
INSERT INTO allowed_fn (sig, clients, service) VALUES
  ('get_dating_home()', 'authenticated', ''),
  ('get_my_gentle_wait_reflection()', 'authenticated', ''),
  ('private.dating_first_drop_at(uuid,timestamp with time zone)', '', ''),
  ('private.dating_next_step(uuid)', '', ''),
  ('private.dating_unavailable_state(uuid)', '', ''),
  ('save_gentle_wait_reflection(jsonb)', 'authenticated', '');
```

Create `$D/edit_shared_contracts_T4.py` with exactly:

```python
# Spec 2 W2 Task 4: the two existing contracts that pin what migration 3 changes.
import pathlib

def edit(path, pairs):
    p = pathlib.Path(path)
    s = p.read_text()
    for old, new in pairs:
        assert s.count(old) == 1, (path, old[:60], s.count(old))
        s = s.replace(old, new)
    p.write_text(s)
    print(f'{path}: {len(pairs)} edit(s)')

# 1. Spec 1's service-role test: the reflections table is no API role's.
old_list = """                          -- Spec 2 W1d (batch-9 fix round 1, M-5): the never-introduce
                          -- list is no API role's either; definer functions reach it.
                          'dating_never_introduce')"""
new_list = """                          -- Spec 2 W1d (batch-9 fix round 1, M-5): the never-introduce
                          -- list is no API role's either; definer functions reach it.
                          'dating_never_introduce',
                          -- Spec 2 W2: the gentle-wait reflections are the author's alone,
                          -- read and written through two definer RPCs.
                          'dating_gentle_wait_reflections')"""
p = pathlib.Path('supabase/tests/service_role_grants_test.sql')
s = p.read_text()
assert s.count(old_list) == 2, s.count(old_list)
p.write_text(s.replace(old_list, new_list))
print('supabase/tests/service_role_grants_test.sql: 2 edit(s)')

# 2. The setup contract's photo-reader tripwire: the resume step counts
#    the person's own approved photos (no API role).
edit('supabase/tests/dating_v2_setup_contracts.sql', [(
    "  IF v_got IS DISTINCT FROM 'private.dating_exit_internal(uuid, boolean):; public.create_dating_photo_upload_intent(text):;",
    "  -- Spec 2 W2: get_dating_home's resume step counts the person's own\n"
    "  -- approved photos (private.dating_next_step, no API role).\n"
    "  IF v_got IS DISTINCT FROM 'private.dating_exit_internal(uuid, boolean):; private.dating_next_step(uuid):; public.create_dating_photo_upload_intent(text):;")])
```

```bash
D=.superpowers/sdd/2026-11-07-spec2-w2
python3 -I $D/section.py supabase/tests/dating_rls_canary.sql $D/canary_T4.sql --before '-- Checks (every batch adds its rows above this line).'
python3 -I $D/edit_shared_contracts_T4.py
for t in dating_rls_canary service_role_grants_test dating_v2_setup_contracts; do
  psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/$t.sql > /dev/null 2>&1; echo "$t exit=$?"
done
```

Expected: `dating_rls_canary.sql: canary_T4.sql before`, `supabase/tests/service_role_grants_test.sql: 2 edit(s)`, `supabase/tests/dating_v2_setup_contracts.sql: 1 edit(s)`, three `exit=0`.

- [ ] **Step 5: Mutation checks**

Create `$D/mut_T4.py` with exactly:

```python
MUTS = {
 'home_no_auth': ("""  IF v_user IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;
  v_reason := public.dating_eligibility(v_user, 'setup');""", """  v_reason := public.dating_eligibility(v_user, 'setup');"""),
 'home_device_null_passes': ("""  IF public.dating_require_trusted_device() IS NOT TRUE THEN
    RETURN jsonb_build_object('state', 'reverify_device');""", """  IF public.dating_require_trusted_device() IS FALSE THEN
    RETURN jsonb_build_object('state', 'reverify_device');"""),
 'home_unknown_reason_eligible': ("""    RETURN jsonb_build_object('state', 'unavailable'); -- an unknown or NULL reason fails closed""",
                                  """    NULL; -- an unknown or NULL reason fails closed"""),
 'home_null_reason_eligible': ("""  IF v_reason IS DISTINCT FROM 'eligible' THEN
    RETURN jsonb_build_object('state', 'unavailable'); -- an unknown or NULL reason fails closed""",
                               """  IF v_reason <> 'eligible' THEN
    RETURN jsonb_build_object('state', 'unavailable'); -- an unknown or NULL reason fails closed"""),
 'home_account_generic': ("""    RETURN jsonb_build_object('state', private.dating_unavailable_state(v_user));""",
                          """    RETURN jsonb_build_object('state', 'unavailable');"""),
 'home_hold_over_suspension': ('MULTI', [
   ("""                    AND r.starts_at <= now() AND (r.ends_at IS NULL OR r.ends_at > now()))
      OR EXISTS (SELECT 1 FROM public.enforcement_records AS er""", """                    AND r.starts_at <= now() AND (r.ends_at IS NULL OR r.ends_at > now()) AND false)
      OR EXISTS (SELECT 1 FROM public.enforcement_records AS er""")]),
 'home_lifted_counts': ("""                  WHERE r.user_id = p_user AND r.restriction_type = 'suspended' AND r.lifted_at IS NULL""",
                        """                  WHERE r.user_id = p_user AND r.restriction_type = 'suspended'"""),
 'home_wait_for_active': ("""  v_opens := private.dating_gentle_wait_opens_at(v_user);
  IF v_enrol.state = 'active' THEN""", """  v_opens := private.dating_gentle_wait_opens_at(v_user);
  IF v_opens IS NOT NULL THEN
    RETURN jsonb_build_object('state', 'gentle_wait', 'ended_at', v_opens - interval '30 days', 'opens_at', v_opens, 'next_step', 'how');
  END IF;
  IF v_enrol.state = 'active' THEN"""),
 'cool_off_from_activation': ("""                        (SELECT u.created_at FROM public.users AS u WHERE u.id = v_user) + interval '72 hours');""",
                              """                        coalesce(v_enrol.activated_at, now()) + interval '72 hours');"""),
 'cool_off_ignores_wait': ("""    v_after := greatest(coalesce(v_opens, '-infinity'::timestamptz),""", """    v_after := greatest('-infinity'::timestamptz,"""),
 'drop_in_utc': ("""  v_tz := coalesce(v_tz, 'UTC');""", """  v_tz := 'UTC';"""),
 'drop_earlier_kept': ("""  IF v_at < p_after THEN""", """  IF false THEN"""),
 'drop_default_time': ("""  v_drop := coalesce(v_drop, time '19:00');""", """  v_drop := time '19:00';"""),
 'suspended_shows_paused': ("""  IF v_enrol.state = 'suspended' THEN
    RETURN jsonb_build_object('state', 'unavailable'); -- suspended without a live restriction (W7a routes it)
  END IF;
""", ""),
 'step_skips_consent': ("""         OR NOT (private.dating_consent_granted(p_user, 'dating_terms')
                 AND private.dating_consent_granted(p_user, 'dating_opt_in')
                 AND private.dating_consent_granted(p_user, 'special_category_profile')) THEN 'privacy'""",
                        """         THEN 'privacy'"""),
 'step_pending_photo_counts': ("""           WHERE f.user_id = p_user AND f.moderation_state = 'approved') < 2 THEN 'photos'""",
                               """           WHERE f.user_id = p_user) < 2 THEN 'photos'"""),
 'step_no_age_check': ("""         OR coalesce(public.dating_age_gate_holds(p_user), false) IS NOT TRUE THEN 'verify'""", """         THEN 'verify'"""),
 'step_region_optional': ("""    WHEN p.country_code IS NULL OR p.region_code IS NULL THEN 'where'""", """    WHEN p.country_code IS NULL THEN 'where'"""),
 'step_attestation_optional': ("""    WHEN p.intention IS NULL OR p.not_married_attested_at IS NULL THEN 'looking-for'""", """    WHEN p.intention IS NULL THEN 'looking-for'"""),
 'save_raises_on_null': ("""  IF p_answers IS NULL OR jsonb_typeof(p_answers) IS DISTINCT FROM 'object' THEN""", """  IF jsonb_typeof(p_answers) <> 'object' THEN"""),
 'save_no_length': ("""    IF jsonb_typeof(v_value) NOT IN ('string', 'null') OR coalesce(char_length(v_value #>> '{}'), 0) > 500 THEN""",
                    """    IF jsonb_typeof(v_value) NOT IN ('string', 'null') THEN"""),
 'save_bytes': ("""    IF jsonb_typeof(v_value) NOT IN ('string', 'null') OR coalesce(char_length(v_value #>> '{}'), 0) > 500 THEN""",
                """    IF jsonb_typeof(v_value) NOT IN ('string', 'null') OR coalesce(octet_length(v_value #>> '{}'), 0) > 500 THEN"""),
 'save_any_key': ("""    IF v_key NOT IN ('q1', 'q2', 'q3') THEN
      RETURN private.dating_invalid('answers');
    END IF;
""", ""),
 'save_ungated': ("""    v_reason := private.dating_setup_guard(); -- the lock, the trusted device, setup eligibility""",
                  """    PERFORM private.dating_lock_setup(v_user); v_reason := NULL; -- the lock, the trusted device, setup eligibility"""),
 'clear_gated': ("""  IF v_clean = '{}'::jsonb THEN
    -- Clearing one's own answers is never gated (exposure-reducing).
    PERFORM private.dating_lock_setup(v_user);
  ELSE""", """  IF false THEN
    PERFORM private.dating_lock_setup(v_user);
  ELSE"""),
 'save_untrimmed': ("""    'q1', nullif(btrim(p_answers ->> 'q1'), ''),""", """    'q1', p_answers ->> 'q1',"""),
 'get_no_device': ("""  IF public.dating_require_trusted_device() IS NOT TRUE THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'reverify_device');
  END IF;
  v_opens := private.dating_gentle_wait_opens_at(v_user);""", """  v_opens := private.dating_gentle_wait_opens_at(v_user);"""),
 'seen_every_time': ("""     WHERE g.seen_at IS NULL OR g.seen_at < v_opens - interval '30 days';""", """     WHERE true;"""),
 'seen_once_ever': ("""     WHERE g.seen_at IS NULL OR g.seen_at < v_opens - interval '30 days';""", """     WHERE g.seen_at IS NULL;"""),
 'seen_with_dating_off': ("""  IF v_opens IS NOT NULL
     AND public.dating_eligibility(v_user, 'setup') IS NOT DISTINCT FROM 'eligible' THEN""", """  IF v_opens IS NOT NULL THEN"""),
 'seen_outside_wait': ("""  IF v_opens IS NOT NULL
     AND public.dating_eligibility(v_user, 'setup') IS NOT DISTINCT FROM 'eligible' THEN""",
                       """  IF public.dating_eligibility(v_user, 'setup') IS NOT DISTINCT FROM 'eligible' THEN"""),
 'deleted_any_time': ("""                WHERE g.user_id = OLD.id AND g.seen_at > now() - interval '7 days') THEN -- Spec 2 W2""",
                      """                WHERE g.user_id = OLD.id AND g.seen_at IS NOT NULL) THEN -- Spec 2 W2"""),
 'deleted_uncounted': ("""      PERFORM private.bump_metric_internal('dating.gentle_wait.account_deleted_7d'); -- Spec 2 W2""", """      NULL; -- Spec 2 W2"""),
 'table_readable': ('RAW', "GRANT SELECT ON public.dating_gentle_wait_reflections TO authenticated;"),
 'home_for_anon': ('RAW', "GRANT EXECUTE ON FUNCTION public.get_dating_home() TO anon;"),
}
```

```bash
D=.superpowers/sdd/2026-11-07-spec2-w2
python3 -I $D/mutate.py supabase/migrations/20261107140000_dating_v2_home.sql supabase/tests/dating_v2_home_contracts.sql $D/mut_T4.py $D | tee $D/mut_T4.txt
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/dating_v2_home_contracts.sql 2>&1 | grep -E 'ERROR|all held' | head -1 | sed -E 's/^psql:[^ ]* //'
```

Expected: 35 lines, all killed (`save_no_length` by the table's own CHECK, the defence in depth P-12 adds; the rest by a `CONTRACT VIOLATED`):

```text
home_no_auth: ERROR:  CONTRACT VIOLATED: get_dating_home answered without a signed-in person
home_device_null_passes: ERROR:  CONTRACT VIOLATED: an untrusted device (NULL) saw {"state": "not_started"}
home_unknown_reason_eligible: ERROR:  CONTRACT VIOLATED: an unknown eligibility reason gave {"state": "not_started"}
home_null_reason_eligible: ERROR:  CONTRACT VIOLATED: a NULL eligibility reason gave {"state": "not_started"}
home_account_generic: ERROR:  CONTRACT VIOLATED: a suspended account is {"state": "unavailable"}
home_hold_over_suspension: ERROR:  CONTRACT VIOLATED: a suspended account is {"state": "unavailable"}
home_lifted_counts: ERROR:  CONTRACT VIOLATED: a lifted suspension still reads as restricted
home_wait_for_active: ERROR:  CONTRACT VIOLATED: setting up during the wait is {"state": "gentle_wait", "ended_at": "<time>", "opens_at": "<time>
cool_off_from_activation: ERROR:  CONTRACT VIOLATED: the cool-off from account creation reads {"state": "cool_off", "first_drop_at": "<time>"} (72 h after creation: 2026-11-09 1
cool_off_ignores_wait: ERROR:  CONTRACT VIOLATED: activated during the wait the home reads {"state": "active"} (open date <time>)
drop_in_utc: ERROR:  CONTRACT VIOLATED: the first drop ignores the country's zone (<time>)
drop_earlier_kept: ERROR:  CONTRACT VIOLATED: a London first drop reads {"state": "cool_off", "first_drop_at": "<time>"} (after <time>)
drop_default_time: ERROR:  CONTRACT VIOLATED: the cool-off from account creation reads {"state": "cool_off", "first_drop_at": "<time>"} (72 h after creation: 2026-11-09 1
suspended_shows_paused: ERROR:  CONTRACT VIOLATED: a suspended enrolment with no live restriction is {"state": "setup_in_progress", "next_step": "looking-for"}
step_skips_consent: ERROR:  CONTRACT VIOLATED: without the special-category consent setup resumes at you
step_pending_photo_counts: ERROR:  CONTRACT VIOLATED: one approved photo resumes at prompts
step_no_age_check: ERROR:  CONTRACT VIOLATED: verified without the age check resumes at preview
step_region_optional: ERROR:  CONTRACT VIOLATED: a country without a region resumes at privacy
step_attestation_optional: ERROR:  CONTRACT VIOLATED: an intention without the attestation resumes at where
save_raises_on_null: ERROR:  CONTRACT VIOLATED: invalid reflections were answered [{"ok": true, "saved_at": null}, {"ok": false, "field": "answers", "reason": "invalid"}, {"ok": false, "field
save_no_length: ERROR:  new row for relation "dating_gentle_wait_reflections" violates check constraint "dating_gentle_wait_reflections_answers_check"
save_bytes: ERROR:  CONTRACT VIOLATED: a valid reflection saved as {"ok": false, "field": "q3", "reason": "invalid"} / <NULL>
save_any_key: ERROR:  CONTRACT VIOLATED: invalid reflections were answered [{"ok": false, "field": "answers", "reason": "invalid"}, {"ok": false, "field": "answers", "reason": "invalid
save_ungated: ERROR:  CONTRACT VIOLATED: an under-18 account saved a reflection ({"ok": true, "saved_at": "<time>"})
clear_gated: ERROR:  CONTRACT VIOLATED: clearing a reflection with Dating off did not clear it ({"ok": false, "reason": "not_eligible"})
save_untrimmed: ERROR:  CONTRACT VIOLATED: a valid reflection saved as {"ok": true, "saved_at": "<time>"} / {"q1": "  To listen first.  ", "q3": "éééééééééééééé
get_no_device: ERROR:  CONTRACT VIOLATED: an untrusted device saved or read a reflection ({"ok": false, "reason": "reverify_device"} {"ok": true, "answers": {"q2": "Kindness"}, "ended_a
seen_every_time: ERROR:  CONTRACT VIOLATED: D0 seen counted 2 times (expected once, and never outside a wait)
seen_once_ever: ERROR:  CONTRACT VIOLATED: a new ending was not counted as a new view
seen_with_dating_off: ERROR:  CONTRACT VIOLATED: D0 was counted as seen with Dating off
seen_outside_wait: ERROR:  CONTRACT VIOLATED: D0 seen counted 1 times (expected once, and never outside a wait)
deleted_any_time: ERROR:  CONTRACT VIOLATED: deletions after D0 counted 2 (expected 1: within 7 days only), or a reflection outlived its account
deleted_uncounted: ERROR:  CONTRACT VIOLATED: deletions after D0 counted 0 (expected 1: within 7 days only), or a reflection outlived its account
table_readable: ERROR:  CONTRACT VIOLATED: the reflections table is readable by an API role, or RLS is off
home_for_anon: ERROR:  CONTRACT VIOLATED: get_dating_home is not the app's alone
```

then `NOTICE:  dating_v2_home_contracts: all held`. (The table CHECK itself is pinned by contract E's direct insert, not by a mutant: `CREATE TABLE IF NOT EXISTS` doesn't re-create an existing table, so a mutated CHECK never applies.)

- [ ] **Step 6: The local harness (edit only, never run)**

```bash
D=.superpowers/sdd/2026-11-07-spec2-w2
python3 -I $D/grants_line.py supabase/migrations/20261107130010_dating_v2_path_pause_grants.sql \
  "Spec 2 W2: the reflection table is no API role's; the home and the two reflection RPCs are the app's." \
  supabase/migrations/20261107140010_dating_v2_home_grants.sql
```

Expected: `local_pg_grants.sql: one \i block added`.

- [ ] **Step 7: The Batch A gate**

```bash
D=.superpowers/sdd/2026-11-07-spec2-w2
$D/suite.sh attune_spec3a > $D/sql-after-A.txt
diff $D/sql-baseline-1.txt $D/sql-after-A.txt
echo "$(grep -c '^PASS' $D/sql-after-A.txt) PASS, $(grep -c '^FAIL' $D/sql-after-A.txt) FAIL"
shasum -a 256 lib/home/home_screen.dart | diff - $D/latch.sha && echo latch unchanged
flutter test test/architecture/games_untouched_test.dart 2>&1 | tail -1
git status --short -- lib test
```

Expected: exactly `> PASS dating_v2_home_contracts.sql` (inserted after `dating_v2_eligibility_contracts.sql`); `158 PASS, 14 FAIL`; `latch unchanged`; the Games test `All tests passed!`; no `lib/` or `test/` change yet. (Under heavy machine load `story_hardening_contracts.sql` was once slow enough to fail while writing this plan and passed on its own; re-run any single new FAIL alone before reporting it.)

---

## Batch B — the app and the docs

### Task 5: Healing stops granting Dating on the phone; the manual (§2.1, §4.10, R7; P-13, P-18)

**Files:**
- Modify: `lib/features/healing/domain/services/readiness_scoring_service.dart`, `lib/features/healing/data/models/healing_journey.dart`, `lib/features/healing/data/repositories/healing_repository.dart`, `lib/features/healing/presentation/screens/healing_journey_screen.dart`, `lib/app/documentations/user_manual/data/healing_docs.dart`, `lib/app/documentations/user_manual/data/about_attune_docs.dart`, `lib/app/documentations/user_manual/data/dating_mode_docs.dart`, `test/features/healing/readiness_scoring_service_test.dart`
- Create: `test/features/healing/healing_never_gates_dating_test.dart`, `$D/{edit_healing_T5.py, edit_docs_T5.py, edit_readiness_test_T5.py}`

**Interfaces:**
- Consumes: Task 2's server (a ready journey is `completed`; the message has no Dating date).
- Produces: `ReadinessScoringService.getResultMessage(int score) → String`; `HealingJourney` without `eligibleForDatingOptInAt` / `isEligibleForDating`.

- [ ] **Step 1: Write the failing test**

Create `test/features/healing/healing_never_gates_dating_test.dart` with exactly:

```dart
// Spec 2 W2 (§2.1, §4.10, R7): Healing never decides when someone can
// date. A finished journey shows no Dating outcome, the repository and the
// model know no Dating status, and the manual says the same.
import 'dart:io';

import 'package:attune/app/documentations/user_manual/data/about_attune_docs.dart';
import 'package:attune/app/documentations/user_manual/data/dating_mode_docs.dart';
import 'package:attune/app/documentations/user_manual/data/healing_docs.dart';
import 'package:attune/app/documentations/user_manual/models/documentation_model.dart'
    show DocumentationModule;
import 'package:attune/features/healing/data/models/healing_journey.dart';
import 'package:attune/features/healing/presentation/providers/healing_providers.dart';
import 'package:attune/features/healing/presentation/screens/healing_journey_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/flow_harness.dart';
import 'w9e/support/healing_fakes.dart';

HealingJourney _finished({String status = 'completed'}) =>
    HealingJourney.fromJson({
      'id': 'j9',
      'user_id': 'ama',
      'relationship_id': 'r1',
      'breakup_at': '2026-08-01T00:00:00Z',
      'breakup_at_source': 'relationship',
      'status': status,
      'current_stage': 5,
      'reflection_answers': <String, dynamic>{},
      'reflection_completed_at': '2026-08-02T00:00:00Z',
      'post_mortem_status': 'completed',
      'post_mortem_completed_at': '2026-08-03T00:00:00Z',
      'pattern_awareness_completed_at': '2026-08-04T00:00:00Z',
      'portrait_status': 'completed',
      'portrait_completed_at': '2026-08-05T00:00:00Z',
      'readiness_stage_completed_at': '2026-08-06T00:00:00Z',
      'completed_at': '2026-08-06T00:00:00Z',
      // A column the app no longer reads.
      'eligible_for_dating_opt_in_at': '2026-08-06T00:00:00Z',
      'created_at': '2026-08-02T00:00:00Z',
      'updated_at': '2026-08-06T00:00:00Z',
    });

List<String> _texts(BuildContext context, DocumentationModule m) => [
  m.getTitle(context),
  m.getSubtitle(context),
  for (final s in m.getSections(context)) ...[
    s.title,
    s.subtitle ?? '',
    for (final c in s.contents) ...[c.title, c.content, ...?c.bulletPoints],
  ],
  for (final f in m.getFAQs(context)) ...[f.question, f.answer],
];

void main() {
  testWidgets('a finished journey offers no Dating outcome (even a row '
      'read before the migration rewrote its old status)', (t) async {
    final repo =
        FakeHealingRepository()
          ..latest['ama'] = _finished(status: 'eligible_for_dating_opt_in');
    await pumpFlowScreen(
      t,
      () => const HealingJourneyScreen(),
      size: const Size(900, 1200),
      overrides: [
        healingRepositoryProvider.overrideWithValue(repo),
        healingAccountProvider.overrideWith((ref) => 'ama'),
      ],
    );
    expect(find.textContaining('Dating'), findsNothing);
  });

  test('the repository and the model know no Dating status', () {
    final repo =
        File(
          'lib/features/healing/data/repositories/healing_repository.dart',
        ).readAsStringSync();
    final model =
        File(
          'lib/features/healing/data/models/healing_journey.dart',
        ).readAsStringSync();
    expect(repo, isNot(contains('eligible_for_dating_opt_in')));
    expect(model, isNot(contains('isEligibleForDating')));
    expect(model, isNot(contains('eligibleForDatingOptInAt')));
    expect(_finished().isCompleted, isTrue);
  });

  testWidgets('the manual never says Healing gates Dating', (t) async {
    late BuildContext context;
    await t.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (c) {
            context = c;
            return const SizedBox();
          },
        ),
      ),
    );
    final all = [
      for (final m in <DocumentationModule>[
        HealingDocs(),
        AboutAttuneDocs(),
        DatingModeDocs(),
      ])
        ..._texts(context, m),
    ].join('\n');
    for (final stale in [
      'eligible through Healing',
      '8 weeks',
      'potentially eligible',
      'matched on who you actually are',
      'readiness score that needs to reflect',
    ]) {
      expect(all, isNot(contains(stale)), reason: stale);
    }
    expect(all, contains('Healing never decides when you can date'));
    expect(all, contains('introduced on what you both say you want'));
  });
}
```

```bash
dart format test/features/healing/healing_never_gates_dating_test.dart
flutter test -r expanded test/features/healing/healing_never_gates_dating_test.dart 2>&1 | grep -E '\[E\]|All tests passed|Some tests failed'
```

Expected: `Formatted 1 file (0 changed)`, then all three tests `[E]` and `Some tests failed.`: the legacy journey still shows "You can choose whether to explore Dating Mode when it becomes available."; the repository and model still name the Dating status; the manual still says "eligible through Healing".

- [ ] **Step 2: The edits**

Create `$D/edit_healing_T5.py` with exactly:

```python
# Spec 2 W2 Task 5: Healing stops granting Dating on the client (§2.1, §4.10, R7).
# Exact replacements, each anchor asserted once; nothing else in these files moves.
import pathlib

def edit(path, pairs):
    p = pathlib.Path(path)
    s = p.read_text()
    for old, new in pairs:
        assert s.count(old) == 1, (path, old[:70], s.count(old))
        s = s.replace(old, new)
    p.write_text(s)
    print(f'{path}: {len(pairs)} edit(s)')

edit('lib/features/healing/domain/services/readiness_scoring_service.dart', [
("""// lib/features/healing/domain/services/readiness_scoring_service.dart

class ReadinessScoringService {
  static const String scoringVersion = 'healing_readiness_v1_1';
  static const int minimumScore = 71;
  static const int minimumWeeks = 8;
""", """// lib/features/healing/domain/services/readiness_scoring_service.dart

/// Healing's readiness check-in: Healing's own private reflection. Spec 2
/// W2 (§2.1): it never decides anything about Dating.
class ReadinessScoringService {
  static const String scoringVersion = 'healing_readiness_v1_1';

  /// From this score the result says the check-in is complete; below it,
  /// that there may be more to explore (the same words as the server's
  /// submit_healing_readiness).
  static const int minimumScore = 71;
"""),
("""  /// Check if the user is eligible for Dating Mode
  static bool isEligibleForDating({
    required int score,
    required DateTime breakupAt,
  }) {
    if (score < minimumScore) return false;

    final now = DateTime.now();
    final weeksSinceBreakup = now.difference(breakupAt).inDays / 7;
    if (weeksSinceBreakup < minimumWeeks) return false;

    return true;
  }

  /// Get the date when 8 weeks have passed
  static DateTime getEligibilityDate(DateTime breakupAt) {
    return breakupAt.add(Duration(days: minimumWeeks * 7));
  }

""", ""),
("""  /// Get result message based on score
  static String getResultMessage(int score, DateTime breakupAt) {
    if (score < minimumScore) {
      return 'Your answers suggest there may be more you want to explore. Go at your own pace.';
    }

    if (!isEligibleForDating(score: score, breakupAt: breakupAt)) {
      final eligibilityDate = getEligibilityDate(breakupAt);
      return 'Your check-in is complete. Dating Mode remains unavailable until ${_formatDate(eligibilityDate)}.';
    }

    return 'You can choose whether to explore Dating Mode when it becomes available.';
  }

  static String _formatDate(DateTime date) {
    return '${date.day} ${_getMonth(date.month)} ${date.year}';
  }

  static String _getMonth(int month) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return months[month - 1];
  }
}""", """  /// The words after a check-in: never a Dating date (Spec 2 W2).
  static String getResultMessage(int score) {
    if (score < minimumScore) {
      return 'Your answers suggest there may be more you want to explore. Go at your own pace.';
    }

    return 'Your check-in is complete. Healing stays here whenever you want it.';
  }
}"""),
])

edit('lib/features/healing/data/models/healing_journey.dart', [
("""  status; // 'active', 'paused', 'completed', 'eligible_for_dating_opt_in', 'archived'""",
 """  status; // 'active', 'paused', 'completed', 'archived' (Spec 2 W2: no Dating outcome)"""),
("""  final DateTime? completedAt;
  final DateTime? eligibleForDatingOptInAt;
  final DateTime createdAt;""", """  final DateTime? completedAt;
  final DateTime createdAt;"""),
("""    this.completedAt,
    this.eligibleForDatingOptInAt,
    required this.createdAt,""", """    this.completedAt,
    required this.createdAt,"""),
("""      eligibleForDatingOptInAt:
          json['eligible_for_dating_opt_in_at'] != null
              ? DateTime.parse(json['eligible_for_dating_opt_in_at'])
              : null,
""", ""),
("""  bool get isEligibleForDating => status == 'eligible_for_dating_opt_in';
""", ""),
("""    completedAt,
    eligibleForDatingOptInAt,
  ];""", """    completedAt,
  ];"""),
])

edit('lib/features/healing/data/repositories/healing_repository.dart', [
("""        .inFilter('status', [
          'active',
          'paused',
          'completed',
          'eligible_for_dating_opt_in',
        ])""", """        // Spec 2 W2: no journey has a Dating outcome any more (the
        // migration made each one 'completed').
        .inFilter('status', ['active', 'paused', 'completed'])"""),
])

edit('lib/features/healing/presentation/screens/healing_journey_screen.dart', [
("""                if (journey.isFullyComplete) ...[
                  if (journey.isEligibleForDating)
                    Container(
                      padding: EdgeInsets.all(Spacing.md.w),
                      decoration: BoxDecoration(
                        color: colorScheme.primary.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(
                          BorderRadiusTokens.md.r,
                        ),
                        border: Border.all(
                          color: colorScheme.primary.withValues(alpha: 0.2),
                        ),
                      ),
                      child: Column(
                        children: [
                          Text(
                            'You can choose whether to explore Dating Mode when it becomes available.',
                            style: textTheme.bodyMedium,
                            textAlign: TextAlign.center,
                          ),
                          Gap(Spacing.md.h),
                          Text(
                            'Dating Mode is coming soon.',
                            style: textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurface.withValues(
                                alpha: 0.6,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  Gap(Spacing.md.h),""", """                // Spec 2 W2 (§2.1): a finished journey offers no Dating
                // outcome; Healing never decides when someone can date.
                if (journey.isFullyComplete) ...[
                  Gap(Spacing.md.h),"""),
])
```

Create `$D/edit_docs_T5.py` with exactly:

```python
# Spec 2 W2 Task 5: the manual says what W2 built (§4.10 healing_docs.dart,
# about_attune_docs.dart:74; the two Healing-gate sentences in
# dating_mode_docs.dart, P-12). Exact replacements, each anchor once.
import pathlib

def edit(path, pairs):
    p = pathlib.Path(path)
    s = p.read_text()
    for old, new in pairs:
        assert s.count(old) == 1, (path, old[:70], s.count(old))
        s = s.replace(old, new)
    p.write_text(s)
    print(f'{path}: {len(pairs)} edit(s)')

D = 'lib/app/documentations/user_manual/data/'
edit(D + 'healing_docs.dart', [
("""    ManualSection(
      id: 'healing_dating_readiness',
      title: 'When Dating Mode becomes available',
      subtitle: 'A gate, not a race',
      icon: Icons.hourglass_bottom,
      category: 'Healing Mode',
      order: 4,
      contents: [
        ManualContent(
          id: 'healing_gate_explained',
          title: 'Why there\\'s a waiting period',
          content:
              'Completing the journey doesn\\'t automatically unlock Dating Mode. There\\'s a minimum waiting period after your relationship ended (around 8 weeks) and a readiness score that needs to reflect genuine readiness, not just finishing the steps quickly. This exists because rushing back into dating right after a breakup carries real, well-documented risk — the gate exists to protect you, not to slow you down for its own sake.',
          numberPrefix: '1',
          type: ManualContentType.text,
        ),
        ManualContent(
          id: 'healing_score_not_verdict',
          title: '',
          content:
              'Your readiness score reflects how you answered today — it\\'s not a permanent verdict on you, and it can change as you do.',
          type: ManualContentType.tip,
        ),
        ManualContent(
          id: 'healing_dating_consent_separate',
          title: 'Dating Mode still requires its own consent',
          content:
              'Becoming eligible for Dating Mode is not the same as joining it. If and when Dating Mode is available to you, you\\'ll be asked for a separate, explicit opt-in — and your former partner\\'s data is never used for matching, no matter what.',
          numberPrefix: '2',
          type: ManualContentType.text,
        ),
      ],
    ),""", """    // Spec 2 W2 (§2.1): Healing no longer decides anything about Dating.
    ManualSection(
      id: 'healing_and_dating',
      title: 'Healing and Dating',
      subtitle: 'Healing is there for you; it never decides when you can date',
      icon: Icons.self_improvement_outlined,
      category: 'Healing Mode',
      order: 4,
      contents: [
        ManualContent(
          id: 'healing_never_decides',
          title: 'Healing never decides when you can date',
          content:
              'Healing is there to help, at your own pace, and it\\'s never required. Finishing the journey, or your readiness check-in, doesn\\'t decide when you can date, and nothing from Healing is used to introduce you to anyone.',
          numberPrefix: '1',
          type: ManualContentType.text,
        ),
        ManualContent(
          id: 'healing_score_not_verdict',
          title: '',
          content:
              'Your readiness score reflects how you answered today — it\\'s not a permanent verdict on you, and it can change as you do.',
          type: ManualContentType.tip,
        ),
      ],
    ),"""),
("""      FAQModel(
        id: 'faq_healing_dating_automatic',
        question: 'Does finishing the journey put me straight into Dating Mode?',
        answer:
            'No. Completing all five stages makes you potentially eligible, but entering Dating Mode always requires a separate, explicit opt-in and its own consent — nothing happens automatically.',""",
"""      FAQModel(
        id: 'faq_healing_and_dating',
        question: 'Does finishing the journey decide when I can date?',
        answer:
            'No. Healing never decides that, and nothing from it is used to introduce you. Dating has its own steps and its own consent, and nothing happens automatically.',"""),
])
edit(D + 'about_attune_docs.dart', [
("""And when you\\'re genuinely ready (never rushed, never based on loneliness), Dating Mode can introduce you to people matched on who you actually are in relationships — not a photo, not a swipe.""",
 """And when you\\'re genuinely ready (never rushed, never based on loneliness), Dating Mode can introduce you to a few people, introduced on what you both say you want — not a photo, not a swipe."""),
])
edit(D + 'dating_mode_docs.dart', [
("""              'Dating Mode only becomes available once you\\'re eligible through Healing Mode — a genuine waiting period and readiness check-in, not something you can skip. Being eligible still requires a separate, explicit opt-in of its own before anything activates.',""",
 """              'Dating Mode is for adults whose account is in good standing and who aren\\'t in a relationship. Healing never decides when you can date. If your relationship ended on Attune, Dating opens for you when your shared space closes, 30 days after it ended, or sooner if you both close it. You still opt in, separately, before anything activates.',"""),
("""            'Only after you\\'re eligible through Healing Mode — which requires a genuine waiting period after a breakup and a readiness check-in reflecting real readiness, not just finishing steps quickly. Eligibility alone doesn\\'t enroll you either; you\\'ll still need to explicitly opt in.',""",
 """            'When you choose, as an adult whose account is in good standing and who isn\\'t in a relationship. Healing never decides it. If your relationship ended on Attune, Dating opens for you when your shared space closes, 30 days after it ended, or sooner if you both close it; you can set up Dating in the meantime. You still need to opt in explicitly.',"""),
])
```

Create `$D/edit_readiness_test_T5.py` with exactly:

```python
# Spec 2 W2 Task 5 (R7): the readiness test keeps the score tests and
# drops only the Dating eligibility ones; the message test follows the
# new signature, and two tests pin that no message names Dating or a date.
import pathlib
p = pathlib.Path('test/features/healing/readiness_scoring_service_test.dart')
s = p.read_text()
cut_start = s.index("    test('does not allow score 70 to qualify', () {")
cut_end = s.index("    test('rejects an incomplete answer set rather than scoring it', () {")
s = s[:cut_start] + s[cut_end:]
cut_start = s.index("    test('a high score still fails inside the eight-week window', () {")
cut_end = s.index("    test('the retake date is a week after the attempt', () {")
s = s[:cut_start] + s[cut_end:]
old = """      final message = ReadinessScoringService.getResultMessage(
        40,
        DateTime.now().subtract(const Duration(days: 400)),
      );
      expect(message, isNot(contains('until')));
    });
  });
}"""
new = """      final message = ReadinessScoringService.getResultMessage(40);
      expect(message, isNot(contains('until')));
    });

    // Spec 2 W2 (§2.1, R7): Healing never decides anything about Dating.
    test('no result message names Dating or a date', () {
      for (final score in [0, 40, 70, 71, 100]) {
        final message = ReadinessScoringService.getResultMessage(score);
        expect(message.toLowerCase(), isNot(contains('dating')));
        expect(message, isNot(contains('until')));
      }
      expect(
        ReadinessScoringService.getResultMessage(71),
        'Your check-in is complete. Healing stays here whenever you want it.',
      );
      expect(
        ReadinessScoringService.getResultMessage(70),
        'Your answers suggest there may be more you want to explore. Go at your own pace.',
      );
    });

    test('the service has no Dating eligibility left', () {
      final source =
          File(
            'lib/features/healing/domain/services/readiness_scoring_service.dart',
          ).readAsStringSync();
      expect(source, isNot(contains('isEligibleForDating')));
      expect(source, isNot(contains('getEligibilityDate')));
      expect(source, isNot(contains('minimumWeeks')));
    });
  });
}"""
assert s.count(old) == 1
s = s.replace(old, new)
old_imp = """import 'package:attune/features/healing/domain/services/readiness_scoring_service.dart';
"""
assert s.count(old_imp) == 1
s = s.replace(old_imp, """import 'dart:io';

""" + old_imp)
p.write_text(s)
print('readiness_scoring_service_test.dart: eligibility tests dropped, 2 added')
```

```bash
D=.superpowers/sdd/2026-11-07-spec2-w2
python3 -I $D/edit_healing_T5.py
python3 -I $D/edit_docs_T5.py
python3 -I $D/edit_readiness_test_T5.py
```

Expected:

```text
lib/features/healing/domain/services/readiness_scoring_service.dart: 3 edit(s)
lib/features/healing/data/models/healing_journey.dart: 6 edit(s)
lib/features/healing/data/repositories/healing_repository.dart: 1 edit(s)
lib/features/healing/presentation/screens/healing_journey_screen.dart: 1 edit(s)
lib/app/documentations/user_manual/data/healing_docs.dart: 2 edit(s)
lib/app/documentations/user_manual/data/about_attune_docs.dart: 1 edit(s)
lib/app/documentations/user_manual/data/dating_mode_docs.dart: 2 edit(s)
readiness_scoring_service_test.dart: eligibility tests dropped, 2 added
```

- [ ] **Step 3: Run the tests; analyze (no pre-existing file is formatted)**

```bash
flutter test test/features/healing test/app/documentations 2>&1 | tail -1
flutter analyze lib/features/healing lib/app/documentations test/features/healing 2>&1 | tail -1
grep -rn "isEligibleForDating\|getEligibilityDate\|eligible_for_dating_opt_in" lib test | grep -v '/generated/'
```

Expected: `… All tests passed!` (81 tests in these two folders while writing this plan); `21 issues found.` (the same 21 as before the edits: none new); no `grep` output.

### Task 6: D0, the gentle wait (§3.2 D0, §3.0, §3.15, §4.4; D8, D20; P-14, P-15)

**Files:**
- Create: `lib/features/dating/gentle_wait/gentle_wait_repository.dart`, `lib/features/dating/gentle_wait/gentle_wait_providers.dart`, `lib/features/dating/gentle_wait/gentle_wait_screen.dart`, `test/features/dating/gentle_wait/gentle_wait_screen_test.dart`, `test/features/dating/gentle_wait/goldens/{gentle_wait,gentle_wait_offline}.{scale1.0,scale1.3,scale2.0,rtl}.png`, `$D/arb_fragment_T6.txt`
- Modify: `lib/i10n/app_en.arb`, `lib/i10n/generated/*` (generated)

**Interfaces:**
- Consumes: Task 4's two reflection RPCs; `currentUserProvider`; Spec 1's flow widgets; `MyDateFormat.toDate`; `RouteNames.healingJourney`.
- Produces: the App interfaces of "Interfaces this plan produces"; W3a routes `GentleWaitScreen` (P-14).

- [ ] **Step 1: The strings**

Create `$D/arb_fragment_T6.txt` with exactly:

```json
  "dating_gentleWaitTitle": "Before you begin",
  "@dating_gentleWaitTitle": {
    "description": "Spec 2 D0 (the gentle wait): the title. Clinician-reviewed copy (W2 gate)."
  },
  "dating_gentleWaitBody": "Your relationship on Attune ended on {endDate}. Dating opens for you on {openDate}, when your shared space closes. If you both close it sooner, Dating opens then.",
  "@dating_gentleWaitBody": {
    "description": "Spec 2 D0: when the relationship ended and when Dating opens. Both dates in full words (MyDateFormat.toDate). Clinician-reviewed copy (W2 gate).",
    "placeholders": {
      "endDate": {
        "type": "String",
        "example": "Sunday, November 1, 2026"
      },
      "openDate": {
        "type": "String",
        "example": "Tuesday, December 1, 2026"
      }
    }
  },
  "dating_gentleWaitNotJudgement": "This pause is because your relationship ended here. It isn't a judgement about you.",
  "@dating_gentleWaitNotJudgement": {
    "description": "Spec 2 D0: why there is a wait. Clinician-reviewed copy (W2 gate)."
  },
  "dating_gentleWaitQuestionsTitle": "Three questions, just for you",
  "@dating_gentleWaitQuestionsTitle": {
    "description": "Spec 2 D0: the heading above the private reflection."
  },
  "dating_gentleWaitQuestionsHint": "Only you can see these, and nothing is scored.",
  "@dating_gentleWaitQuestionsHint": {
    "description": "Spec 2 D0: under the reflection heading."
  },
  "dating_gentleWaitQuestion1": "What do you want to carry into your next relationship?",
  "@dating_gentleWaitQuestion1": {
    "description": "Spec 2 D0: reflection question 1 (optional answer, up to 500 characters)."
  },
  "dating_gentleWaitQuestion2": "What are you hoping for now?",
  "@dating_gentleWaitQuestion2": {
    "description": "Spec 2 D0: reflection question 2 (optional answer, up to 500 characters)."
  },
  "dating_gentleWaitQuestion3": "How will you know if you need more time?",
  "@dating_gentleWaitQuestion3": {
    "description": "Spec 2 D0: reflection question 3 (optional answer, up to 500 characters)."
  },
  "dating_gentleWaitAnswerCount": "{count} of {max} characters",
  "@dating_gentleWaitAnswerCount": {
    "description": "Spec 2 D0: under each answer, how many characters it holds.",
    "placeholders": {
      "count": {
        "type": "int"
      },
      "max": {
        "type": "int"
      }
    }
  },
  "dating_gentleWaitSave": "Save my answers",
  "@dating_gentleWaitSave": {
    "description": "Spec 2 D0: the secondary button that saves the three answers."
  },
  "dating_gentleWaitSaved": "Your answers are saved.",
  "@dating_gentleWaitSaved": {
    "description": "Spec 2 D0: read out after the answers are saved."
  },
  "dating_gentleWaitHealing": "Healing is here if you want it. It's there to help, and it's never required.",
  "@dating_gentleWaitHealing": {
    "description": "Spec 2 D0: the card that opens Healing. Clinician-reviewed copy (W2 gate)."
  },
  "dating_gentleWaitSetUp": "Set up Dating now",
  "@dating_gentleWaitSetUp": {
    "description": "Spec 2 D0: the primary button; setup runs as usual and introductions start on the open date."
  },
  "dating_offline": "You're offline. Dating needs a connection.",
  "@dating_offline": {
    "description": "Spec 2 §3.0: the banner on a Dating screen while the phone is offline."
  },
  "dating_connectToSave": "Connect to save this answer.",
  "@dating_connectToSave": {
    "description": "Spec 2 §3.0: under a save button that is off while the phone is offline."
  },
  "dating_errorGeneric": "Something went wrong. Try again.",
  "@dating_errorGeneric": {
    "description": "Spec 2 §3.0: a server failure on a Dating screen."
  },
  "dating_retry": "Retry",
  "@dating_retry": {
    "description": "Spec 2 §3.0: the button that tries a failed Dating read again."
  }
```

```bash
D=.superpowers/sdd/2026-11-07-spec2-w2
python3 -I .superpowers/sdd/2026-10-26-spec1-w3/arb_append.py $D/arb_fragment_T6.txt
flutter gen-l10n --arb-dir=lib/i10n --template-arb-file=app_en.arb --output-dir=lib/i10n/generated --output-localization-file=app_localizations.dart --no-synthetic-package
grep -c 'dating_gentleWait' lib/i10n/generated/app_localizations.dart
```

Expected: `added 17 keys`; gen-l10n lists the new keys as untranslated in the other locales (they fall back to English, as the spec says); `13`.

- [ ] **Step 2: Write the failing test**

Create `test/features/dating/gentle_wait/gentle_wait_screen_test.dart` with exactly:

```dart
// Spec 2 W2: D0, the gentle wait (§3.2 D0, §3.0, §3.15; D8, D20).
// The copy with both dates in full words, three labelled answers kept in
// memory and saved only when asked, the offline rule, Healing offered,
// setup going ahead, another account on the same phone never seeing the
// last one's answers, nothing on disk, and the goldens at 1.0, 1.3, 2.0
// and right-to-left.
//   flutter test --update-goldens test/features/dating/gentle_wait/gentle_wait_screen_test.dart
import 'dart:async';

import 'package:attune/features/dating/gentle_wait/gentle_wait_providers.dart';
import 'package:attune/features/dating/gentle_wait/gentle_wait_repository.dart';
import 'package:attune/features/dating/gentle_wait/gentle_wait_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../helpers/flow_harness.dart';
import '../../../helpers/tap_in_reach.dart';

const _body =
    'Your relationship on Attune ended on Sunday, November 1, 2026. Dating opens for you on Tuesday, December 1, 2026, when your shared space closes. If you both close it sooner, Dating opens then.';
const _q1 = 'What do you want to carry into your next relationship?';
const _q2 = 'What are you hoping for now?';
const _q3 = 'How will you know if you need more time?';

// Noon UTC, so the dates are the same day in any test machine's zone.
final _ama = GentleWait(
  endedAt: DateTime.utc(2026, 11, 1, 12),
  opensAt: DateTime.utc(2026, 12, 1, 12),
  answers: const {'q1': 'Patience with myself'},
);
final _kofi = GentleWait(
  endedAt: DateTime.utc(2026, 11, 1, 12),
  opensAt: DateTime.utc(2026, 12, 1, 12),
  answers: const {'q2': 'Someone kind'},
);

/// Answers each account's read from [data]; [hold] keeps the next
/// account's read open; [saves] records what was sent.
class _FakeGateway implements GentleWaitGateway {
  _FakeGateway(this.signedIn);

  final StateController<String?> Function() signedIn;
  final data = <String, GentleWait>{'ama': _ama, 'kofi': _kofi};
  final saves = <Map<String, String>>[];
  Completer<void>? hold;
  Object? readError;
  GentleWaitSave saveResult = GentleWaitSave.saved;
  int reads = 0;

  @override
  Future<GentleWait> read() async {
    reads++;
    final who = signedIn().state;
    if (who != 'ama') await hold?.future;
    final error = readError;
    if (error != null) throw error;
    return data[who]!;
  }

  @override
  Future<GentleWaitSave> save(Map<String, String> answers) async {
    saves.add(answers);
    return saveResult;
  }
}

final _signedIn = StateProvider<String?>((ref) => 'ama');

class _Pumped {
  _Pumped(this.harness, this.gateway, this.setUps);

  final FlowHarness harness;
  final _FakeGateway gateway;
  final List<int> setUps;
}

ProviderContainer _container(WidgetTester t) =>
    ProviderScope.containerOf(t.element(find.byType(GentleWaitScreen)));

Future<_Pumped> _open(WidgetTester t, {bool online = true}) async {
  late _FakeGateway gateway;
  final setUps = <int>[];
  final harness = await pumpFlowScreen(
    t,
    () => GentleWaitScreen(onSetUp: () => setUps.add(1)),
    overrides: [
      gentleWaitAccountProvider.overrideWith((ref) => ref.watch(_signedIn)),
      gentleWaitGatewayProvider.overrideWith((ref) {
        return gateway = _FakeGateway(() => ref.read(_signedIn.notifier));
      }),
      datingOnlineProvider.overrideWith((ref) => Stream.value(online)),
    ],
  );
  await t.pumpAndSettle();
  return _Pumped(harness, gateway, setUps);
}

void main() {
  testWidgets('D0 reads the wait in full words, with three labelled answers', (
    t,
  ) async {
    await _open(t);
    expect(find.text('Before you begin'), findsOneWidget);
    expect(find.text(_body), findsOneWidget);
    expect(
      find.text(
        "This pause is because your relationship ended here. It isn't a judgement about you.",
      ),
      findsOneWidget,
    );
    expect(find.text('Three questions, just for you'), findsOneWidget);
    expect(
      find.text('Only you can see these, and nothing is scored.'),
      findsOneWidget,
    );
    for (final question in [_q1, _q2, _q3]) {
      expect(find.bySemanticsLabel(question), findsOneWidget);
    }
    // Saved answers are back in their fields.
    expect(find.text('Patience with myself'), findsOneWidget);
    expect(find.text('Save my answers'), findsOneWidget);
    expect(find.text('Set up Dating now'), findsOneWidget);
    expect(
      find.text(
        "Healing is here if you want it. It's there to help, and it's never required.",
      ),
      findsOneWidget,
    );
    expect(
      find.text("You're offline. Dating needs a connection."),
      findsNothing,
    );
  });

  testWidgets('Save sends what was typed, says so, and writes nothing to the '
      'phone (D20)', (t) async {
    final p = await _open(t);
    await t.enterText(
      find.byKey(const ValueKey('gentle_wait_q3')),
      'When I feel rushed',
    );
    await tapInReach(t, find.text('Save my answers'));
    await t.pumpAndSettle();
    expect(p.gateway.saves, [
      {'q1': 'Patience with myself', 'q2': '', 'q3': 'When I feel rushed'},
    ]);
    expect(find.text('Your answers are saved.'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getKeys().where((k) => k.toLowerCase().contains('dating')),
      isEmpty,
    );
    expect(
      prefs
          .getKeys()
          .map((k) => '${prefs.get(k)}')
          .where((v) => v.contains('rushed')),
      isEmpty,
    );
  });

  testWidgets('a failed save says so and keeps the answers on screen', (
    t,
  ) async {
    final p = await _open(t);
    p.gateway.saveResult = GentleWaitSave.failed;
    await t.enterText(find.byKey(const ValueKey('gentle_wait_q2')), 'Kindness');
    await tapInReach(t, find.text('Save my answers'));
    await t.pumpAndSettle();
    expect(find.text('Something went wrong. Try again.'), findsOneWidget);
    expect(find.text('Your answers are saved.'), findsNothing);
    expect(find.text('Kindness'), findsOneWidget);
  });

  testWidgets('offline: the banner, Save off with its hint, typed text kept', (
    t,
  ) async {
    final p = await _open(t, online: false);
    expect(
      find.text("You're offline. Dating needs a connection."),
      findsOneWidget,
    );
    expect(find.text('Connect to save this answer.'), findsOneWidget);
    await t.enterText(
      find.byKey(const ValueKey('gentle_wait_q1')),
      'Still here',
    );
    await bringIntoReach(t, find.text('Save my answers'));
    await t.tap(find.text('Save my answers'), warnIfMissed: false);
    await t.pumpAndSettle();
    expect(p.gateway.saves, isEmpty);
    expect(find.text('Still here'), findsOneWidget);
  });

  testWidgets('Healing is offered: the card opens Healing', (t) async {
    final p = await _open(t);
    await tapInReach(
      t,
      find.text(
        "Healing is here if you want it. It's there to help, and it's never required.",
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('at /healingJourney'), findsOneWidget);
  });

  testWidgets('Set up Dating now goes ahead with setup', (t) async {
    final p = await _open(t);
    await tapInReach(t, find.text('Set up Dating now'));
    await t.pumpAndSettle();
    expect(p.setUps, [1]);
  });

  testWidgets('after the wait (no dates) D0 shows no date sentence', (t) async {
    final p = await _open(t);
    p.gateway.data['ama'] = const GentleWait(
      answers: {'q1': 'Patience with myself'},
    );
    _container(t).invalidate(gentleWaitProvider);
    await t.pumpAndSettle();
    expect(find.textContaining('Dating opens for you on'), findsNothing);
    expect(find.bySemanticsLabel(_q1), findsOneWidget);
  });

  testWidgets('a failed read says so, and Retry reads again', (t) async {
    final p = await _open(t);
    p.gateway.readError = Exception('offline');
    _container(t).invalidate(gentleWaitProvider);
    await t.pumpAndSettle();
    expect(find.text('Something went wrong. Try again.'), findsOneWidget);
    expect(find.text('Patience with myself'), findsNothing);
    p.gateway.readError = null;
    final before = p.gateway.reads;
    await tapInReach(t, find.text('Retry'));
    await t.pumpAndSettle();
    expect(p.gateway.reads, before + 1);
    expect(find.text('Patience with myself'), findsOneWidget);
  });

  testWidgets('an answer holds at most 500 code points (the server counts '
      'code points, so a family emoji counts as several)', (t) async {
    await _open(t);
    final field = find.byKey(const ValueKey('gentle_wait_q2'));
    await t.enterText(field, 'é' * 501);
    await t.pump();
    final text =
        t
            .widget<TextField>(
              find.descendant(of: field, matching: find.byType(TextField)),
            )
            .controller!
            .text;
    expect(text.runes.length, 500);
    expect(find.text('500 of 500 characters'), findsOneWidget);
    final family = '\u{1F468}‍\u{1F469}‍\u{1F467}'; // 5 code points
    await t.enterText(field, family * 101);
    await t.pump();
    expect(
      t
          .widget<TextField>(
            find.descendant(of: field, matching: find.byType(TextField)),
          )
          .controller!
          .text
          .runes
          .length,
      lessThanOrEqualTo(500),
    );
  });

  testWidgets('D8: the next account never sees the last one\'s answers or '
      'typing, not even while its read is out', (t) async {
    final p = await _open(t);
    await t.enterText(
      find.byKey(const ValueKey('gentle_wait_q3')),
      'Ama typed this',
    );
    p.gateway.hold = Completer<void>();
    _container(t).read(_signedIn.notifier).state = 'kofi';
    for (var i = 0; i < 5; i++) {
      await t.pump(const Duration(milliseconds: 100));
      expect(
        find.text('Patience with myself'),
        findsNothing,
        reason: 'frame $i',
      );
      expect(find.text('Ama typed this'), findsNothing, reason: 'frame $i');
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    }
    p.gateway.hold!.complete();
    await t.pumpAndSettle();
    expect(find.text('Someone kind'), findsOneWidget);
    expect(find.text('Patience with myself'), findsNothing);
    expect(find.text('Ama typed this'), findsNothing);
  });

  testWidgets('D8: the next account\'s read fails: an error, never the last '
      'account\'s answers', (t) async {
    final p = await _open(t);
    p.gateway
      ..hold = Completer<void>()
      ..readError = Exception('offline');
    _container(t).read(_signedIn.notifier).state = 'kofi';
    await t.pump();
    p.gateway.hold!.complete();
    await t.pumpAndSettle();
    expect(find.text('Something went wrong. Try again.'), findsOneWidget);
    expect(find.text('Patience with myself'), findsNothing);
  });

  testWidgets('accessibility: tap targets, labels, contrast', (t) async {
    await _open(t);
    await expectFlowGuidelines(t);
  });

  testWidgets('goldens: D0', (t) async {
    await expectFlowGoldens(
      t,
      'gentle_wait',
      () => GentleWaitScreen(onSetUp: () {}),
      overrides: [
        gentleWaitAccountProvider.overrideWith((ref) => ref.watch(_signedIn)),
        gentleWaitGatewayProvider.overrideWith(
          (ref) => _FakeGateway(() => ref.read(_signedIn.notifier)),
        ),
        datingOnlineProvider.overrideWith((ref) => Stream.value(true)),
      ],
    );
  });

  // Its own test: a new ProviderScope in the same test keeps the first
  // scope's connection.
  testWidgets('goldens: D0 offline', (t) async {
    await expectFlowGoldens(
      t,
      'gentle_wait_offline',
      () => GentleWaitScreen(onSetUp: () {}),
      overrides: [
        gentleWaitAccountProvider.overrideWith((ref) => ref.watch(_signedIn)),
        gentleWaitGatewayProvider.overrideWith(
          (ref) => _FakeGateway(() => ref.read(_signedIn.notifier)),
        ),
        datingOnlineProvider.overrideWith((ref) => Stream.value(false)),
      ],
      // The connection is known a frame after the first read.
      before: (t) async {
        await t.pumpAndSettle();
        expect(
          find.text("You're offline. Dating needs a connection."),
          findsOneWidget,
        );
      },
    );
  });
}
```

```bash
flutter test test/features/dating/gentle_wait/gentle_wait_screen_test.dart 2>&1 | grep -m1 -E "Error: |error"
```

Expected: a compile error naming `package:attune/features/dating/gentle_wait/gentle_wait_providers.dart` (the files don't exist yet).

- [ ] **Step 3: Write the repository, the providers and the screen**

Create `lib/features/dating/gentle_wait/gentle_wait_repository.dart` with exactly:

```dart
// Spec 2 W2 (§3.2 D0, §4.4 Gentle wait): the gentle wait's two RPCs.
// RPC-only, like every Dating read (§4.1); nothing is kept on the phone
// (§3.0, C-5): the answers live in memory while D0 is open.
import 'package:supabase_flutter/supabase_flutter.dart';

/// The three questions' keys, in the order D0 asks them.
const gentleWaitQuestionKeys = ['q1', 'q2', 'q3'];

/// The longest answer, in Unicode code points (the server counts with
/// char_length, so a family emoji counts as several).
const gentleWaitAnswerMax = 500;

/// What D0 shows: the wait's two dates (both null once the wait is over)
/// and the person's own saved answers.
class GentleWait {
  const GentleWait({this.endedAt, this.opensAt, this.answers = const {}});

  final DateTime? endedAt;
  final DateTime? opensAt;
  final Map<String, String> answers;

  factory GentleWait.fromJson(Map<String, dynamic> json) {
    final raw = json['answers'];
    final answers = <String, String>{};
    if (raw is Map) {
      for (final key in gentleWaitQuestionKeys) {
        final value = raw[key];
        if (value is String) answers[key] = value;
      }
    }
    DateTime? at(String key) {
      final value = json[key];
      return value is String ? DateTime.tryParse(value) : null;
    }

    return GentleWait(
      endedAt: at('ended_at'),
      opensAt: at('opens_at'),
      answers: answers,
    );
  }
}

/// How saving the answers went.
enum GentleWaitSave { saved, notEligible, reverifyDevice, failed }

/// The server would not show D0's data (W4b: on an untrusted phone).
class GentleWaitUnavailable implements Exception {
  const GentleWaitUnavailable(this.reason);

  final String reason;

  @override
  String toString() => 'GentleWaitUnavailable($reason)';
}

/// D0's reads and writes, behind an interface so the screen can be tested
/// without Supabase.
abstract class GentleWaitGateway {
  Future<GentleWait> read();

  Future<GentleWaitSave> save(Map<String, String> answers);
}

class GentleWaitRepository implements GentleWaitGateway {
  GentleWaitRepository(this._client);

  final SupabaseClient _client;

  /// Every call is bounded, as the other repositories' (checklist 1.2).
  static const _timeout = Duration(seconds: 30);

  /// One silent retry when the server answers `dating:busy`: it has
  /// already retried three times itself (Spec 2 W1 carried item 11).
  Future<dynamic> _rpc(String fn, [Map<String, dynamic>? params]) async {
    for (var attempt = 1; ; attempt++) {
      try {
        return await _client.rpc(fn, params: params).timeout(_timeout);
      } on PostgrestException catch (e) {
        if (e.message == 'dating:busy' && attempt == 1) continue;
        rethrow;
      }
    }
  }

  @override
  Future<GentleWait> read() async {
    final json = Map<String, dynamic>.from(
      await _rpc('get_my_gentle_wait_reflection') as Map,
    );
    if (json['ok'] != true) {
      throw GentleWaitUnavailable('${json['reason']}');
    }
    return GentleWait.fromJson(json);
  }

  @override
  Future<GentleWaitSave> save(Map<String, String> answers) async {
    final json = Map<String, dynamic>.from(
      await _rpc('save_gentle_wait_reflection', {'p_answers': answers}) as Map,
    );
    if (json['ok'] == true) return GentleWaitSave.saved;
    return switch (json['reason']) {
      'not_eligible' => GentleWaitSave.notEligible,
      'reverify_device' => GentleWaitSave.reverifyDevice,
      _ => GentleWaitSave.failed,
    };
  }
}
```

Create `lib/features/dating/gentle_wait/gentle_wait_providers.dart` with exactly:

```dart
// Spec 2 W2 (D0; D8 shared phones): everything here belongs to the
// signed-in account, lives in memory only, and is read again when the
// account changes (another account on the same phone never sees it).
import 'package:attune/features/auth/providers/auth_provider.dart'
    show currentUserProvider;
import 'package:attune/features/dating/gentle_wait/gentle_wait_repository.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The signed-in account's id (null when signed out).
final gentleWaitAccountProvider = Provider<String?>(
  (ref) => ref.watch(currentUserProvider.select((u) => u?.id)),
);

final gentleWaitGatewayProvider = Provider<GentleWaitGateway>(
  (ref) => GentleWaitRepository(Supabase.instance.client),
);

/// D0's data for the signed-in account; disposed when D0 closes.
final gentleWaitProvider = FutureProvider.autoDispose<GentleWait>((ref) {
  ref.watch(gentleWaitAccountProvider);
  return ref.read(gentleWaitGatewayProvider).read();
});

/// Whether the phone has a connection (§3.0 offline rule). Dating keeps
/// its own: it imports nothing from the chat feature (§7.4).
final datingOnlineProvider = StreamProvider.autoDispose<bool>((ref) async* {
  final connectivity = Connectivity();
  yield await connectivity.checkConnectivity() != ConnectivityResult.none;
  await for (final result in connectivity.onConnectivityChanged) {
    yield result != ConnectivityResult.none;
  }
});
```

Create `lib/features/dating/gentle_wait/gentle_wait_screen.dart` with exactly:

```dart
// Spec 2 W2: D0, the gentle wait (§3.2 D0, §3.0, §3.15). Shown only while
// get_dating_home() answers `gentle_wait`; W3a gives it its route
// (/dating/setup/wait, behind the Dating lock) and the next step.
// Never animated; large text let through (FlowFrame's AllowLargeText);
// the dates read in full words; the three answers are typed into memory
// only and saved on the server when the person asks.
import 'package:attune/app/routing/app_router.dart' show RouteNames;
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/utils/date_formatter.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_buttons.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_frame.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_text_field.dart'
    show FlowErrorLine;
import 'package:attune/features/dating/gentle_wait/gentle_wait_providers.dart';
import 'package:attune/features/dating/gentle_wait/gentle_wait_repository.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class GentleWaitScreen extends ConsumerStatefulWidget {
  const GentleWaitScreen({super.key, required this.onSetUp, this.onBack});

  /// "Set up Dating now": setup runs as usual (W3a opens the next step).
  final VoidCallback onSetUp;

  /// The back button; none when null.
  final VoidCallback? onBack;

  @override
  ConsumerState<GentleWaitScreen> createState() => _GentleWaitScreenState();
}

enum _Status { none, saved, failed }

class _GentleWaitScreenState extends ConsumerState<GentleWaitScreen> {
  final _answers = {
    for (final key in gentleWaitQuestionKeys) key: TextEditingController(),
  };

  /// The account whose saved answers are in the fields (D8).
  String? _seededFor;
  bool _saving = false;
  _Status _status = _Status.none;

  @override
  void initState() {
    super.initState();
    // D8: another account on this phone starts from empty fields, never
    // from what the last one typed or saved.
    ref.listenManual<String?>(gentleWaitAccountProvider, (previous, next) {
      if (previous == next) return;
      for (final controller in _answers.values) {
        controller.clear();
      }
      setState(() {
        _seededFor = null;
        _status = _Status.none;
      });
    });
    ref.listenManual<AsyncValue<GentleWait>>(gentleWaitProvider, (_, next) {
      final data = next.valueOrNull;
      final account = ref.read(gentleWaitAccountProvider);
      if (data == null || next.isLoading || _seededFor == account) return;
      for (final key in gentleWaitQuestionKeys) {
        _answers[key]!.text = data.answers[key] ?? '';
      }
      _seededFor = account;
    }, fireImmediately: true);
  }

  @override
  void dispose() {
    for (final controller in _answers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _status = _Status.none;
    });
    var result = GentleWaitSave.failed;
    try {
      result = await ref.read(gentleWaitGatewayProvider).save({
        for (final entry in _answers.entries) entry.key: entry.value.text,
      });
    } catch (_) {
      result = GentleWaitSave.failed;
    }
    if (!mounted) return;
    setState(() {
      _saving = false;
      _status = result == GentleWaitSave.saved ? _Status.saved : _Status.failed;
    });
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final wait = ref.watch(gentleWaitProvider);
    final online = ref.watch(datingOnlineProvider).valueOrNull ?? true;
    // Only a finished read is shown: a loading or failed frame (a first
    // read, or the next account's) never shows the last data (D8).
    final data = wait is AsyncData<GentleWait> ? wait.value : null;
    return FlowFrame(
      title: loc.dating_gentleWaitTitle,
      onBack: widget.onBack,
      actions: [
        FlowPrimaryButton(
          label: loc.dating_gentleWaitSetUp,
          onPressed: widget.onSetUp,
        ),
      ],
      body:
          data != null
              ? _body(context, loc, data, online)
              : wait is AsyncError<GentleWait>
              ? _readFailed(loc)
              : const Center(child: CircularProgressIndicator()),
    );
  }

  Widget _readFailed(AppLocalizations loc) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      FlowErrorLine(text: loc.dating_errorGeneric, liveRegion: true),
      const SizedBox(height: Spacing.md),
      FlowSecondaryButton(
        label: loc.dating_retry,
        onPressed: () => ref.invalidate(gentleWaitProvider),
      ),
    ],
  );

  Widget _body(
    BuildContext context,
    AppLocalizations loc,
    GentleWait data,
    bool online,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final endedAt = data.endedAt;
    final opensAt = data.opensAt;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!online) ...[
          _OfflineBanner(text: loc.dating_offline),
          const SizedBox(height: Spacing.md),
        ],
        if (endedAt != null && opensAt != null) ...[
          Text(
            loc.dating_gentleWaitBody(
              MyDateFormat.toDate(endedAt.toLocal()),
              MyDateFormat.toDate(opensAt.toLocal()),
            ),
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: Spacing.sm),
        ],
        Text(
          loc.dating_gentleWaitNotJudgement,
          style: theme.textTheme.bodyLarge,
        ),
        const SizedBox(height: Spacing.lg),
        Semantics(
          header: true,
          child: Text(
            loc.dating_gentleWaitQuestionsTitle,
            style: theme.textTheme.titleMedium?.copyWith(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(height: Spacing.xs),
        Text(
          loc.dating_gentleWaitQuestionsHint,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        for (final (key, question) in [
          ('q1', loc.dating_gentleWaitQuestion1),
          ('q2', loc.dating_gentleWaitQuestion2),
          ('q3', loc.dating_gentleWaitQuestion3),
        ]) ...[
          const SizedBox(height: Spacing.md),
          _ReflectionField(
            key: ValueKey('gentle_wait_$key'),
            controller: _answers[key]!,
            label: question,
            countLabel: loc.dating_gentleWaitAnswerCount,
          ),
        ],
        const SizedBox(height: Spacing.md),
        FlowSecondaryButton(
          label: loc.dating_gentleWaitSave,
          busy: _saving,
          onPressed: online ? _save : null,
        ),
        if (!online) ...[
          const SizedBox(height: Spacing.xs),
          Text(
            loc.dating_connectToSave,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        if (_status == _Status.saved) ...[
          const SizedBox(height: Spacing.sm),
          Semantics(
            liveRegion: true,
            child: Text(
              loc.dating_gentleWaitSaved,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurface,
              ),
            ),
          ),
        ],
        if (_status == _Status.failed) ...[
          const SizedBox(height: Spacing.sm),
          FlowErrorLine(text: loc.dating_errorGeneric, liveRegion: true),
        ],
        const SizedBox(height: Spacing.lg),
        _HealingCard(
          text: loc.dating_gentleWaitHealing,
          onTap: () => context.push(RouteNames.healingJourney),
        ),
      ],
    );
  }
}

/// Keeps an answer within [gentleWaitAnswerMax] code points (the server's
/// count), so a long paste is cut here rather than refused there.
class _CodePointLimit extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.runes.length <= gentleWaitAnswerMax) return newValue;
    final kept = String.fromCharCodes(
      newValue.text.runes.take(gentleWaitAnswerMax),
    );
    return TextEditingValue(
      text: kept,
      selection: TextSelection.collapsed(offset: kept.length),
    );
  }
}

/// One question: its text above a multi-line field, read as the field's
/// name (§3.15 D0: "three labelled fields"), with a character count.
class _ReflectionField extends StatelessWidget {
  const _ReflectionField({
    super.key,
    required this.controller,
    required this.label,
    required this.countLabel,
  });

  final TextEditingController controller;
  final String label;
  final String Function(int count, int max) countLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ExcludeSemantics(
          child: Text(
            label,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: colorScheme.onSurface,
            ),
          ),
        ),
        const SizedBox(height: Spacing.xs),
        Semantics(
          label: label,
          child: TextField(
            controller: controller,
            minLines: 3,
            maxLines: 8,
            keyboardType: TextInputType.multiline,
            textCapitalization: TextCapitalization.sentences,
            inputFormatters: [_CodePointLimit()],
            decoration: InputDecoration(
              border: const OutlineInputBorder(
                borderRadius: BorderRadiusTokens.mdAll,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadiusTokens.mdAll,
                borderSide: BorderSide(color: colorScheme.primary, width: 2),
              ),
            ),
          ),
        ),
        const SizedBox(height: Spacing.xs),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          builder:
              (context, value, _) => Text(
                countLabel(value.text.runes.length, gentleWaitAnswerMax),
                textAlign: TextAlign.end,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
        ),
      ],
    );
  }
}

/// §3.0: "You're offline. Dating needs a connection." Read out when it
/// appears; never animated.
class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Semantics(
      liveRegion: true,
      container: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadiusTokens.mdAll,
        ),
        child: Padding(
          padding: const EdgeInsets.all(Spacing.smMd),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.cloud_off_outlined,
                size: 20,
                color: colorScheme.onSurface,
              ),
              const SizedBox(width: Spacing.sm),
              Expanded(
                child: Text(
                  text,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Healing is here if you want it…" → Healing (offered, never required).
class _HealingCard extends StatelessWidget {
  const _HealingCard({required this.text, required this.onTap});

  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Material(
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadiusTokens.mdAll,
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.all(Spacing.md),
            child: Row(
              children: [
                Icon(
                  Icons.self_improvement_outlined,
                  color: colorScheme.onSurface,
                ),
                const SizedBox(width: Spacing.smMd),
                Expanded(
                  child: Text(
                    text,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurface,
                    ),
                  ),
                ),
                const SizedBox(width: Spacing.sm),
                Icon(Icons.chevron_right, color: colorScheme.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Format the new files; create the goldens; run the tests**

```bash
dart format lib/features/dating/gentle_wait test/features/dating/gentle_wait
flutter analyze lib/features/dating/gentle_wait test/features/dating/gentle_wait 2>&1 | tail -1
flutter test --update-goldens test/features/dating/gentle_wait/gentle_wait_screen_test.dart 2>&1 | tail -1
flutter test -r expanded test/features/dating/gentle_wait/gentle_wait_screen_test.dart 2>&1 | grep -E '\[E\]|All tests passed|Some tests failed'
ls test/features/dating/gentle_wait/goldens
python3 scripts/large_text_audit.py --scale 2.0 test/features/dating/gentle_wait 2>&1 | tail -1
```

Expected: `Formatted 4 files (0 changed)` (the files above are already in `dart format` style; any change is whitespace only); `No issues found!`; `All tests passed!` twice (14 tests); the eight PNGs (`gentle_wait.{rtl,scale1.0,scale1.3,scale2.0}.png`, `gentle_wait_offline.{…}.png`); `SCALE 2.0: 0 site(s) to fix, 0 listed apart`. Open `gentle_wait.scale2.0.png` and `gentle_wait_offline.scale2.0.png` and check by eye: nothing clipped, the offline banner first in the body, "Set up Dating now" pinned at the bottom.

- [ ] **Step 5: No Dating on the phone's disk, no chat or Games import**

```bash
grep -rn "SharedPreferences\|FlutterSecureStorage\|path_provider" lib/features/dating/gentle_wait
grep -rn "features/chat\|features/games" lib/features/dating/gentle_wait
flutter test test/architecture 2>&1 | tail -1
```

Expected: no output from either `grep`; `All tests passed!`.

### Task 7: The `DATING_MODE_SPEC.md` amendments, the clinician's note, the DPIA line; the W2 gate (§1.5, §8 W2 gate, §10 item 3)

**Files:**
- Modify: `lib/architecture/DATING_MODE_SPEC.md`, `lib/architecture/DATING_MODE_CLINICAL_REVIEW_PACKET.md`, `lib/architecture/DATING_MODE_DPIA.md`
- Create: `$D/{edit_spec_docs_T7.py, edit_dpia_T7.py}`

- [ ] **Step 1: The amendments**

Create `$D/edit_spec_docs_T7.py` with exactly:

```python
# Spec 2 W2 Task 7: the DATING_MODE_SPEC.md amendments W2 owns (§1.5:
# §2 eligibility, launch gate and profile rows; §2.1; §3.1; §3.2) and the
# gentle-wait note for the clinician. Exact replacements, each anchor once.
import pathlib

def edit(path, pairs):
    p = pathlib.Path(path)
    s = p.read_text()
    for old, new in pairs:
        assert s.count(old) == 1, (path, old[:70], s.count(old))
        s = s.replace(old, new)
    p.write_text(s)
    print(f'{path}: {len(pairs)} edit(s)')

SPEC = 'docs/superpowers/specs/2026-10-24-dating-mode-design.md'
edit('lib/architecture/DATING_MODE_SPEC.md', [
("""**Version:** 1.3  
**Created:** July 2026  
**Updated:** July 2026  """,
 """**Version:** 1.4 (Spec 2 W2 amended §2, §2.1, §3.1 and §3.2; the rest of the Spec 2 §1.5 amendments follow in W3–W7, then 2.0)  
**Created:** July 2026  
**Updated:** November 2026  """),
("""| Launch gate | Month 6+ and sufficient eligible local pool; target 2,000 active couples is a planning signal, not an authorization bypass |
| Eligibility | Server-authoritative Healing v1.3 eligibility; score greater than 70, all stages complete, path-specific time gate met (3.1), no active/pending relationship, account in good standing |""",
 """| Launch gate | Per country, behind the gates of `""" + SPEC + """` §8 and production mode (Ghana: Greater Accra and Ashanti first, men–women; the UK); a thin pool is never a reason to open early (2.1) |
| Eligibility | Server-authoritative `dating_eligibility` (3.1): an adult by the account's date of birth, a confirmed phone, EULA v2, an account in good standing, no pending, active or paused relationship, Dating open in the person's Dating country and region; to be introduced, also outside the gentle wait. Healing never gates Dating |"""),
("""| Profile | User verifies identity-facing fields and preferences before activation; no silent public profile creation |""",
 """| Profile | The fields of the Spec 2 design §3.2 (D2–D13), one question per screen, special-category answers encrypted; activated only after age assurance and the identity check; no silent public profile creation |"""),
("""**Legitimate levers under pool pressure:** grow the solo-journey supply
(Healing Mode marketed standalone), regional staged enablement, marketing,
extending the pilot, and patience.

**Never legitimate without fresh recorded clinical sign-off:** lowering the
readiness threshold (>70), shortening the eight-week gate, removing Healing
stages, weakening moderation SLAs, widening a user's stated preferences, or
softening any Section 5 hard filter. A thin pool is a growth problem;
re-labelling it an eligibility problem is the failure mode this section exists
to prevent.""",
 """**Legitimate levers under pool pressure:** regional staged enablement,
marketing, extending the pilot, and patience.

**Never legitimate without fresh recorded clinical sign-off:** shortening or
removing the gentle wait (3.1: the 30-day ending window after a relationship
ended on Attune, shorter only when both close the shared space), weakening the
trust friction (the 72-hour cool-off from account creation, the daily and
waiting caps, same country by default, other countries only for verified
accounts 14 or more days old), weakening moderation SLAs, widening a user's
stated preferences, or softening any Section 5 hard filter. A thin pool is a
growth problem; re-labelling it an eligibility problem is the failure mode
this section exists to prevent. The gentle wait's clinical note is
`DATING_MODE_CLINICAL_REVIEW_PACKET.md` §7."""),
("""The Dating backend reads eligibility from the trusted Healing transition defined in `HEALING_MODE_SPEC.md`. It must revalidate all gates transactionally when the user opts in and whenever their account or relationship state changes. A stale `eligible_for_dating_opt_in_at` timestamp is not sufficient by itself.

There are three approved eligibility paths, all of them server-authoritative and all of them ending in the same `eligible_for_dating_opt_in` state (HEALING_MODE_SPEC v1.3 Sections 2.1 and 7):

| Path | `breakup_at_source` | Who it is for | Time gate |
| --- | --- | --- | --- |
| Ended Attune relationship | `relationship` | A relationship that ended on Attune | Eight weeks from trusted `ended_at` |
| Solo journey | `user_reported` | A breakup that happened off Attune | Eight weeks from the reported date **and** four weeks of observed journey |
| Readiness journey | `no_prior_relationship` | Never-partnered users, and users not processing any breakup | Four weeks of observed journey |

The solo journey's tightened clock exists because a user-reported breakup date is self-attested and cannot be trusted the way `relationships.ended_at` can. The readiness journey carries no breakup clock at all, because there is no loss to recover from; its four-week observed-journey floor is the same anti-speed-run control, measured from server-set `journey_created_at`.

Do not fabricate a breakup date, bypass the journey in the client, or route a never-partnered user through the solo path to make the numbers work. Before v1.3 that user had no eligible path, and the tempting workaround — self-reporting a breakup that did not happen — is exactly the fabricated provenance this section forbids.""",
 """Eligibility is one server predicate, `dating_eligibility(user, scope)` (Spec 2 design §2.1), which returns the first failing reason: the feature switch, the account (an adult by the account's date of birth, a confirmed phone, EULA v2), standing, the relationship guard, the gentle wait, the Dating country and region (then, from later waves, the trusted device and where the person is). Every RPC that gates Dating calls it, transactionally, each time; nothing is cached.

**The gentle wait** applies only after a relationship ended on Attune: while any relationship of the person's is ended and its `ended_at` is within the last 30 days (the shared space's read-only window). It ends early when both partners close the space or either starts a new relationship (the space is then archived). The predicate reads the window, not the status alone, so it ends on the open date even before the archive sweep runs. During the wait a person can set up and activate Dating; introductions start on the open date (or after the 72-hour cool-off, whichever is later). The wait screen (D0) offers a private three-question reflection and Healing; neither is required, and nothing is scored.

**Healing never gates Dating.** No readiness score, Healing stage, journey or self-reported breakup date opens or delays Dating, and nothing from Healing is read by Dating. A breakup that happened off Attune, or none, means no wait. The former-partner exclusion stays mandatory whatever the wait says (Section 5.1)."""),
("""Enrollment requires four affirmative, independently recorded decisions:

1. accept the current Dating Mode terms and privacy notice;
2. opt in to Dating Mode;
3. confirm that the user is at least 18 using a server-trusted date of birth or approved age-verification result;
4. activate the reviewed dating profile.

Historical-data consent is a fifth, optional decision. Refusing it must not block Dating Mode. Without it, matching uses current self-reported quiz dimensions and explicit dating preferences only.""",
 """Enrollment requires these affirmative, independently recorded decisions and results:

1. accept the current Dating terms and privacy notice (`dating_terms`);
2. opt in to Dating (`dating_opt_in`);
3. consent to the special-category profile answers (`special_category_profile`; faith separately, `special_category_faith`, only if the person answers it);
4. pass age assurance and the identity check (Spec 2 design §3.3, recorded as results, never as a stored date of birth). The typed date of birth never unlocks Dating, and there is no age checkbox;
5. activate the reviewed dating profile.

There is no historical-data consent: Dating reads no historical Attune data (quiz results, journal, Healing, messages). Section 3.3 no longer applies (Spec 2 design §1.5)."""),
])

edit('lib/architecture/DATING_MODE_CLINICAL_REVIEW_PACKET.md', [
("""Decision:  
Required changes before production:  
""",
 """Decision:  
Required changes before production:  

## 7. The gentle wait (Spec 2 W2; a production gate)

The owner's ruling (Q12) replaces the Healing gate (a readiness score above 70, every Healing stage, eight weeks) with a gentle wait. The clinician is asked to record a note on its length and its copy, under `DATING_MODE_SPEC.md` §2.1's gate-erosion clause.

**What is built.** The wait applies only when a relationship ended on Attune. It lasts while the shared space's 30-day read-only window is open: from the ending, 30 days; sooner when both partners close the space or either starts a new relationship. During the wait the person can set up Dating; introductions start on the open date. A private three-question reflection is offered (each answer optional, up to 500 characters, never scored, seen by nobody else, deleted when the person leaves Dating), and Healing is offered, never required. No wait for a breakup off Attune, or none. The former-partner exclusion is mandatory regardless. Two counts are kept, aggregate only: people who open the wait screen, and accounts deleted within 7 days of opening it (a proxy for people re-registering to escape the wait).

**Why not a longer or scored wait (research 03 §2.8, 09 P15).** No study supports an imposed wait after a breakup; a hard eight-week timer pushed a test persona to re-register on another SIM, which defeats the ex-exclusion. The 30-day window gives a reason ("you don't date while your former partner can still read your shared space") instead of an arbitrary number.

**The screen's copy (D0), exactly as built:**

- Title: "Before you begin"
- "Your relationship on Attune ended on {end date}. Dating opens for you on {open date}, when your shared space closes. If you both close it sooner, Dating opens then."
- "This pause is because your relationship ended here. It isn't a judgement about you."
- "Three questions, just for you" — "Only you can see these, and nothing is scored."
- "What do you want to carry into your next relationship?"
- "What are you hoping for now?"
- "How will you know if you need more time?"
- "Save my answers" — "Your answers are saved."
- "Healing is here if you want it. It's there to help, and it's never required."
- "Set up Dating now"

Healing's own readiness result now reads "Your check-in is complete. Healing stays here whenever you want it." (or, below 71, "Your answers suggest there may be more you want to explore. Go at your own pace.") and names no Dating date.

**Questions requiring explicit clinical sign-off** (record `approve`, `approve with changes` or `reject`):

- [ ] The length: the 30-day ending window, shorter when both close the space or either starts a new relationship.
- [ ] Setup during the wait, with introductions only from the open date.
- [ ] The three reflection questions, optional and unscored.
- [ ] The D0 copy above, including "It isn't a judgement about you."
- [ ] Healing offered, never required, and Healing's new result message.
- [ ] No wait after a breakup off Attune.

Reviewer name:  
Credentials:  
Date:  
Decision:  
Required changes before production:  

A domestic-violence specialist also reads the D0 copy (the same W2 gate) and records their read here:

DV reviewer name:  
Date:  
Decision:  
"""),
])
```

Create `$D/edit_dpia_T7.py` with exactly:

```python
# Spec 2 W2 Task 7: the DPIA's retention table names the gentle-wait
# reflection (P-12; owner question 2). One row added after the first.
import pathlib
p = pathlib.Path('lib/architecture/DATING_MODE_DPIA.md')
s = p.read_text()
anchor = """| Conversations (matches now; messages from W6) |"""
assert s.count(anchor) == 1
row = ("| Gentle-wait reflection (`dating_gentle_wait_reflections`, W2: the person's own three answers, each at most 500 characters, "
       "and when they last opened D0 during a wait; read and written only by the author through two definer RPCs, no API role) "
       "| answers until the person clears them (a clear works at any time, inside or outside the wait); the row (with when they last "
       "opened D0 during a wait) until they leave Dating or delete the account, whether or not they ever set Dating up "
       "| hard-deleted at exit or account deletion — **owner ruling 2026-11-07 (kept as built); open for counsel** |\n")
s = s.replace(anchor, row + anchor)
pair = """| Pair data | `dating_introductions`, `dating_interest_actions` and `dating_matches` are revoked from `service_role` too (W1a); no edge function reads them. |"""
assert s.count(pair) == 1
s = s.replace(pair, pair[:-2] + " The gentle-wait reflections (`dating_gentle_wait_reflections`, W2) are revoked from every API role, `service_role` included, column by column; only the author's two definer RPCs, exit and the account-deletion trigger reach them (the home contract's H9 pins exactly those four). |")
p.write_text(s)
print('lib/architecture/DATING_MODE_DPIA.md: 2 edit(s)')
```

```bash
D=.superpowers/sdd/2026-11-07-spec2-w2
python3 -I $D/edit_spec_docs_T7.py
python3 -I $D/edit_dpia_T7.py
grep -n "Healing v1.3 eligibility\|shortening the eight-week gate\|readiness threshold (>70)\|Historical-data consent is a fifth" lib/architecture/DATING_MODE_SPEC.md
```

Expected: `lib/architecture/DATING_MODE_SPEC.md: 6 edit(s)`, `lib/architecture/DATING_MODE_CLINICAL_REVIEW_PACKET.md: 1 edit(s)`, `lib/architecture/DATING_MODE_DPIA.md: 2 edit(s)`; no `grep` output.

- [ ] **Step 2: The W2 gate**

```bash
D=.superpowers/sdd/2026-11-07-spec2-w2
$D/suite.sh attune_spec3a > $D/sql-after-W2.txt
diff $D/sql-after-A.txt $D/sql-after-W2.txt && echo "SQL unchanged since Batch A"
flutter test --reporter compact > $D/flutter-after-W2.txt 2>&1; tail -c 120 $D/flutter-after-W2.txt
flutter analyze 2>&1 | tail -1
shasum -a 256 lib/home/home_screen.dart | diff - $D/latch.sha && echo latch unchanged
flutter test test/architecture/games_untouched_test.dart 2>&1 | tail -1
git status --short
```

Expected: `SQL unchanged since Batch A` (158 PASS / 14 FAIL); Flutter: Task 1's baseline plus 15 tests (14 D0, 3 Healing, 2 readiness added, 4 readiness removed), no new failure (while writing this plan, a copy of the app without `android/`, `ios/` and `docs/` ran +7226 with only the 21 platform-file tests that need those folders failing); analyzer: Task 1's total, nothing new; `latch unchanged`; the Games test passes; `git status` shows only this plan's files (and the owner's two).


## Owner deploy checklist (the plan never runs any of this)

1. **Order.** S2 W1 and Spec 1 W9d are deployed first. Then, in one `supabase db push`: the six files `20261107120000` … `20261107140010` in order, **then** the app build with Batch B (the build's Healing repository no longer lists `eligible_for_dating_opt_in`; migration 1 has already rewritten those rows to `completed`, so no journey disappears). The build carries D0's code but no route to it (P-14), so nothing new is reachable until W3a.
2. **Right after the push (SQL editor), each project:**
   - `select to_regprocedure('public.dating_healing_gates_hold(uuid)'), count(*) filter (where status = 'eligible_for_dating_opt_in') from public.healing_journeys;` → `NULL | 0`.
   - `select tgname from pg_trigger where tgrelid = 'public.users'::regclass and tgname = 'dating_pause_on_path_change';` → one row.
   - `select has_function_privilege('anon','public.get_dating_home()','EXECUTE'), has_function_privilege('authenticated','public.get_dating_home()','EXECUTE'), has_table_privilege('service_role','public.dating_gentle_wait_reflections','SELECT'), has_function_privilege('authenticated','public.get_dating_eligibility()','EXECUTE');` → `f | t | f | t`.
   - `select public.get_dating_operational_health() -> 'safety_counters_7d';` → includes the ten W2 keys, all 0 (D0 is unrouted until W3a): `dating.path_pause.failed`, `dating.path_pause.swept`, `dating.gates.busy`, `dating.gates.failed`, `dating.gentle_wait.undated`, `dating.gentle_wait.seen`, `dating.gentle_wait.account_deleted_7d`, `dating.gentle_wait.clear_busy`, `dating.gentle_wait.seen_skipped`, `dating.home.unreadable_field`.
   - **Development only:** nothing to re-run (W2 adds no flag and changes no country); `dev_enable_spec2_dating_flags.sql` stays as it is.
3. **Watch for a week after the push.** `dating.gates.busy` (a person's gate check met a running switch three times; harmless, retried in 15 minutes) and `dating.path_pause.failed` (someone left the Dating path but stayed visible until the next gate run; investigate any non-zero day). The first gate-cron run after the push pauses, with `pause_reason = 'gates'`, every v1-active development profile that isn't complete under readiness v2 (expected, W1 P-2). From W3a, read `dating.gentle_wait.account_deleted_7d` as a floor: someone who leaves Dating and then deletes the account within 7 days is not counted, because leaving deletes the reflection row with its `seen_at` (B3 M-4; the spec's "deleted on exit" is kept). A non-zero `dating.gentle_wait.undated` is an ended relationship without `ended_at`; that person is refused Dating (`account_unavailable`), so investigate it. Development only (final review M-8): migration 1 relabels `both_sealed` rows whose second member is already gone, inside their window, as `last_member_sealed`, so someone who was free can be back in a wait until the window ends; Dating is off in production, so nothing to do there.
4. **Spec 1's `flow_paths_v2` production gate.** Its gate row reads "Spec 2 W2 path trigger live, so Dating -> Just for me pauses Dating (D18)". Once item 2 shows the trigger on the production project, record the evidence in `private.flag_production_gates` (`review_ref`) for `flow_paths_v2`.
5. **W2's production gate (§8 W2): the clinician and the domestic-violence reviewer.** Send `lib/architecture/DATING_MODE_CLINICAL_REVIEW_PACKET.md` §7 (built in Task 7: the length, setup during the wait, the three questions, the D0 copy, Healing offered and Healing's new result message, no wait after a breakup off Attune). The clinician records a note on the length and the copy under `DATING_MODE_SPEC.md` §2.1's gate-erosion clause (now amended to name the gentle wait); the DV reviewer reads the D0 copy and signs in the same section. Copy changes come back as an edit to `lib/i10n/app_en.arb` (through `arb_append.py`'s pattern: an exact replacement script) and to the server's two Healing messages (a new migration that re-creates `submit_healing_readiness` from its live body). Dating stays off in production until W10 regardless.
   - **The clinician's note also records** (packet §7, batch 6): the deleted-former-partner rule (a lone close after the other account was deleted still waits); the second-account closure, alone and with both closing (whoever moved on keeps the first ending's wait); the 30-day window, shorter only when both close the space with both accounts present or the former partner starts a new relationship; the gate-erosion clause (§2.1: shortening the wait or weakening either rule needs a fresh recorded sign-off); and the optional question whether D0 shows Spec 1's static "Need support now?" link.
   - **The clinician and the DV reviewer rule on D0's no-shortcut variant together** (final review M-4; packet §7's new box): the line drops "If you both close it sooner" when that can no longer happen, and the manual's general "or sooner if you both close it" is put to them unchanged. Also in packet §7: a low readiness score never gets the success styling (final review I-1).
   - **The DV reviewer reads every string W2 adds** (Task 4 adds none a person sees). D0 (Task 6): "Before you begin"; "Your relationship on Attune ended on {end date}. Dating opens for you on {open date}, when your shared space closes. If you both close it sooner, Dating opens then."; "This pause is because your relationship ended here. It isn't a judgement about you."; "Three questions, just for you"; "Only you can see these, and nothing is scored."; the three questions; "{count} of {max} characters"; "Save my answers"; "Your answers are saved."; "Healing is here if you want it. It's there to help, and it's never required."; "Set up Dating now"; "You're offline. Dating needs a connection."; "Connect to save this answer."; "Something went wrong. Try again."; "Retry". D0's fix-round strings (the 4 of batch 5 and the busy-clear string): "Clear my answers"; "Your answers are cleared."; "This is taking a little longer than usual. Your answers are still here, so try again in a moment."; "This is taking a little longer than usual. Try again in a moment."; "This is taking a little longer than usual. Try clearing again in a moment." Task 5: the dashboard fallback "You always opt in separately, and nothing starts until you do."; Healing's result "Your check-in is complete. Healing stays here whenever you want it."; the final fix wave's D0 no-shortcut sentence (`dating_gentleWaitBodyNoShortcut`) "Your relationship on Attune ended on {end date}. Dating opens for you on {open date}." (shown when closing the space together can no longer end the wait: the former partner deleted their account, or the person moved on); the manual's rewritten Healing, About and Dating sentences (`healing_docs.dart`, `about_attune_docs.dart`, `dating_mode_docs.dart`).
   - `lib/architecture/HEALING_MODE_SPEC.md` is amended to match (the `eligible_for_dating_opt_in` state and the eight-week gate retired, each edit tagged "(amended S2 W2)"); nothing to sign beyond this item.
6. **Owner decisions** (Owner questions above): 1, the `unavailable` home state; 2, how long a never-used reflection is kept: **ruled 2026-11-07, kept as built** (until exit or account deletion, clearable at any time); the DPIA §3 row says so and is marked **open for counsel**, so counsel confirms it (cost if counsel disagrees: a 90-day purge later); 3, the nods on P-6, P-8, P-12, P-13.
7. **Device checks move to W3a** (P-14): D0 at 1.0, 1.3 and 2.0 text and right-to-left on a small Android and an iPhone, VoiceOver and TalkBack reading each question as its field's name and both dates in full words, the offline banner, the Dating lock in front of it, quick exit from it, and a second account on the same phone (D8). W2's widget tests and goldens cover each in the meantime.
8. **Spec amendments to sign (owner-visible).** None is in `docs/superpowers/specs/2026-10-24-dating-mode-design.md` yet; once the owner signs, the controller applies each. Each line names its cost:
   - **§3.1 state list (P-10):** `unavailable` added. *Cost:* W3a writes one more line of copy.
   - **§4.3 `pause_reason` (P-6):** `gates` added. *Cost:* none for people; W3a's paused copy covers it.
   - **§4.3 `dating_gentle_wait_reflections` (P-12):** `seen_at` added; **§4.4** `get_my_gentle_wait_reflection()` also returns the wait's two dates. *Cost:* one timestamp a person, deleted with the row.
   - **§2.1 "Where the Healing predicates go" (P-2, P-8):** four call sites (W1d moved the fifth); `submit_healing_readiness` keeps `is_eligible` meaning "this check-in completed the journey". *Cost:* an old app build reads the key as before (emphasis on a completed check-in), which is now accurate.
   - **§4.10 `dating_mode_docs.dart` (P-13):** two sentences corrected in W2 rather than W3c. *Cost:* none.
   - **§2.1 / §3.2 D0 (B1 I-1 ruling):** the wait shortens only when both close the space with both accounts present, or the former partner starts a new relationship; the one who moved on keeps the first ending's wait. D0's body names only the first. *Cost:* none in W2; the clinician may ask for a sentence.
9. **W3a carries from W2** (W3a's plan picks each up; none is reachable before W3a routes D0):
   - map `path_not_dating` (resume or activation off the Dating path) to "choose Dating to resume";
   - a "Clear my answers" route for the reflection outside the wait (the server's clear already works anytime, ungated);
   - Spec 1's Me slot still shows a wait after both partners close the space, while the gate opens Dating at once: W3a's Dating section fixes it;
   - D0's quick-exit wipe if W3a keeps it mounted (a shell branch or `IndexedStack`): keep D0's answers in the route's `State`, `gentleWaitProvider` `autoDispose`, and register any kept-alive Dating state in `registerDatingDeviceWipes()` for `quickExit` and `signOut`;
   - harden the server's `btrim` to strip all whitespace (`btrim(x, E' \t\r\n')`) before the clear;
   - map a save's `notEligible` and `reverifyDevice`, and an `unavailable` read, to their own D0 states (still offering "Clear my answers" when the read is unavailable);
   - an ending with no `ended_at` shows an active person as `active` on the home while the candidate check refuses them: show it as `unavailable`;
   - the home's `gentle_wait` state carries no `can_shorten` yet (only D0's read does, final review M-4): W3a's Dating section adds it if it shows the shortcut line;
   - map begin's new `path_not_dating` (final review M-1) with resume's and activation's.
10. **Carries to named waves (final review):**
   - **W5a:** the 72-hour cool-off is computed only by `get_dating_home`; add `dating_cool_off_ends_at(uuid)` and check it in generation and in the candidate scope (final review M-5; development only until then, Dating is off in production).
   - **W3 (W3c):** delete `ReadinessScoringService.getResultMessage` and its test if it still has no caller after W3 (batch-4 M-5). Batch-4 M-3 (the result screen's success styling) is closed by the final fix wave's I-1 on the server.

## Spec coverage (self-review)

| Spec item | Where |
|---|---|
| §8 W2 contents: gate 5 with the window predicate | Task 2 (migration 1; contract E; mutants `m29_status_only`, `wait_31_days`, `wait_archived_counts`, `wait_one_member`, `opens_earliest`, `wait_in_setup`, `no_wait_gate`, `wait_after_country`) |
| The Healing gate removed from its call sites and dropped | Task 2 (P-2; contract E's `pg_proc` scan and `to_regprocedure`; mutants `begin_*`, `candidate_*`, `cron_*`, `healing_still_grants`) |
| `get_dating_eligibility()` shim until W3a (I-4, R21) | Task 2 (P-7; contract F; mutants `shim_*`); carried item 5 (W3a's grep test and drop) |
| Healing's status and message no longer mention Dating (R7) | Task 2 (P-8; contract H; Step 4's data rewrite; mutants `healing_*`, `readiness_*`); Task 5 (client) |
| `get_dating_home` (first version) | Task 4 (P-10, P-11; home contract A-D, G; mutants `home_*`, `cool_off_*`, `drop_*`, `step_*`, `suspended_shows_paused`) |
| The `users.path` trigger, one writer per reason (Spec 1 D18, I-5, R13) | Task 3 (P-9; contract I, I2; identity_foundation G6; mutants `m24_*` (spec mutant 24) and 10 more; the race case) |
| Client changes in Healing (`ReadinessScoringService`, `HealingJourney`, `healing_journey_screen.dart`, `healing_repository.dart`) and docs (`healing_docs.dart`, `about_attune_docs.dart:74`) | Task 5 (P-13, P-18) |
| D0 screen and its reflection | Task 4 (table, RPCs, counters; home contract E, F); Task 6 (screen, strings, 14 tests, 8 goldens) |
| `DATING_MODE_SPEC.md` §2, §2.1, §3.1, §3.2 amendments; the clinical note recorded in the packet | Task 7 Step 1; owner checklist 5 |
| §8 W2 tests: `dating_v2_eligibility_contracts`, `readiness_scoring_service_test.dart` updated, D0 widget and golden tests, mutants 24 and 29 | Tasks 2-3 (E-I), Task 5 Step 2, Task 6, Task 2 Step 7 (29), Task 3 Step 6 (24) |
| §8 W2 gate: the clinician's note, the DV reviewer's read | Owner checklist 5; packet §7 (Task 7) |
| §7.1 W2 rows: Healing score 10 still eligible; `gentle_wait` inside the window; open past it before the sweep (A-9); open once both sealed; the shim's shape; one writer per pause reason with the `pg_proc` scan; A-10 keys; no wait for an ending outside Attune or long ago; the 72 h cool-off from `users.created_at`; leaving the Dating path pauses; the Healing gate gone | Contract E (score 10, window, A-9, seals, archived by a new relationship), F, I (incl. the scan), home contract G (A-10 keys) and C (cool-off), E (no wait without an Attune ending: `v_solo`) |
| §2.1 "Which gates apply where": setup and activation during the wait; candidates wait | Contract E2 (begin during the wait; the candidate check), P-3 |
| §3.0 rules on D0: no motion; `AllowLargeText` and goldens at 1.0/1.3/2.0 (+ RTL); labels; contrast; offline banner and hint; nothing on disk; errors with Retry | Task 6 (FlowFrame, `expectFlowGoldens`, `expectFlowGuidelines`, the offline, D20, error and Retry tests) |
| §3.2 D0 copy, fields (three optional, 0-500), validation (length only), storage (own row, author only, deleted on exit), open date | Task 6 (strings, the 500 code-point test); Task 4 (P-12; home contract E, F's exit check) |
| §3.15 D0 row (dates in full words; three labelled fields; Save disabled offline; typed text kept in memory) | Task 6 tests 1, 4 |
| §4.4 internal functions `dating_pause_on_path_change`, `dating_gentle_wait_opens_at` | Tasks 3, 2 |
| §4.8 the reflection hard-deleted at exit or account deletion | Home contract F (exit; the account deletion cascade) |
| §6.9 `dating.gentle_wait.seen`, `dating.gentle_wait.account_deleted_7d` | Task 4 (P-12; home contract F; mutants `seen_*`, `deleted_*`) |
| §9 R7, R13, R21 | Tasks 2/5, 3, carried item 5 |
| §10 item 3 (the clinician's ruling) | Owner checklist 5 |
| Cross-spec I-4, I-5, A-9, A-10 | Tasks 2, 3, 2, 4 |
| Carried: B10 M-6 (W2 part), B5 M-8, the shared lock order, carried item 11 | Carried items 1-4; Tasks 2-4, 6 |
| Global constraints: D8, D20, nothing tells a reported or blocked person anything, quick exit, exposure-reducing never gated, NULL-safety, pre-validation | Task 6 (D8 ×2, D20), home contract D (report and block), P-14 (quick exit), home contract E (clearing ungated), every NULL probe, contract E's invalid inputs |

Placeholder scan: no "TBD", "TODO", "later" without a wave, "similar to" or undefined name; every code step has its full text; `<time>` in the mutant outputs stands for a timestamp that differs per run. Type consistency: every SQL signature is used as created and every Dart name as declared (each migration was applied, each contract run and each mutant executed while writing this plan, in task order, on a scratch copy of `attune_spec3a`; every Dart file compiled, analyzed clean and passed its tests in a scratch copy of the app).

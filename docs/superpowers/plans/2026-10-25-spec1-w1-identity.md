# Spec 1 W1 (Identity Foundation: W1a, W1b, W1c) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build Spec 1's identity foundation: `users.phone` and the Opinions moderation columns can no longer be rewritten from the phone; `users.mode` loses every writer; the server gains the path, date-of-birth, hold, home-state and metric primitives; and the environment helper, Spec 1's eleven flags (all off), the production flag gate, the public config with the Dating open-country seam, identity health, the unfinished sign-up purge, the Journal insight pause and the scoped invite key are in place. Nothing a person sees changes, except that Journal insights stop wherever `journal_ai_insights` is off.

**Architecture:** Six migrations, each with its `_grants` twin, in spec §4.7 order. W1a hardens `users` (column grants, a phone mirror from `auth.users`, retired `mode`) and `profiles` (a `current_user` guard trigger on the two moderation columns and on deletes), and re-creates the five dating functions without their `users.mode` write. W1b adds metric storage with an exact-key client surface, write-once birth dates, account holds, the single path writer and `get_my_home_state()`. W1c adds `private.attune_environment()`, the production flag gate, `get_public_app_config()` and identity health. One SQL contract file, `supabase/tests/identity_foundation_contracts.sql`, grows one section per task; every security change has a mutant that turns it red. The client changes are narrow: the legacy onboarding submission stops writing `phone`/`mode`, both invite functions stop writing `mode`, and four new, unwired foundation files (`HomeState`, `HomeStateStore`, the public config client, the metric counter) wait for W2/W3. Every SQL block in this plan was run while writing it, inside rolled-back transactions on `attune_spec3a` (all six migrations applied twice, the full contract green, every mutant red with the message quoted below); every Dart and Deno block was run in a scratch copy of the tree.

**Tech Stack:** Flutter 3.29.1 (Dart 3.7), Riverpod 2.6, GoRouter, Supabase Postgres 17 (pg_cron, Vault), Supabase CLI 2.75, Deno 2 for edge-function tests, psql.

**Spec:** `docs/superpowers/specs/2026-10-24-app-flow-identity-design.md` (§1.3–1.5, §2.5, §4, §5.3, §5.5, §5.6, §6, §7, §8 W1a–W1c, §9, §11, "Owner approval"), plus the "Controller rulings for the fix pass" at the end of `docs/superpowers/specs/2026-10-24-cross-spec-review.md`. Spec 2 (`docs/superpowers/specs/2026-10-24-dating-mode-design.md`, header "Depends on Spec 1") consumes these W1 objects by name: the `users` column grants and `phone` from `auth.users`; `users.path`, `path_previous`, `path_chosen_at`, `phone_released_at`; `metric_counters`, `metric_key_prefixes` (it inserts `dating.`), `metric_client_keys`, `private.bump_metric_internal`, `bump_metric_server`; `account_birthdates`, `set_my_birth_date`, `get_my_age()`, `account_age(uuid)`; `account_holds`, `place_account_hold(uuid, text, text DEFAULT NULL)`; `set_user_path_internal(uuid, text)`; `get_my_home_state()` with `dating {enabled, enrolled}` from `private.dating_home_summary(uuid)`; `private.attune_environment()`, `get_attune_environment()`, `private.assert_development_project()`; `app_public_config`, `private.dating_open_countries()`, `get_public_app_config()`. Those names and signatures are fixed by this plan.

## Global Constraints

- Work in the main working tree on `main` (`/Users/user/attune`). The owner may have uncommitted edits (today: `supabase/.temp/cli-latest`, `backup-before-planning-p2.sql`): never revert, stash, stage, checkout or reformat them. If a file this plan edits is already modified, edit on top of the owner's version; every edit below is an exact-string replacement, so an edit elsewhere in the file doesn't move it.
- **NO commits.** No `git add`, `git commit`, `git stash`, `git checkout`, `git reset`, `git rm`. Every task ends with "Run tests", not "Commit".
- Never `dart format` a pre-existing file (the repo's files predate the 3.7 formatter; formatting one reflows it). Format only the eleven Dart files this plan creates: `lib/features/onboarding/domain/home_state.dart`, `lib/features/onboarding/data/home_state_store.dart`, `lib/core/flags/public_app_config.dart`, `lib/core/metrics/metric_counter.dart`, `test/features/onboarding/onboarding_submission_service_test.dart`, `test/features/onboarding/home_state_test.dart`, `test/features/onboarding/home_state_store_test.dart`, `test/features/onboarding/scoped_invite_code_test.dart`, `test/core/flags/public_app_config_test.dart`, `test/core/metrics/metric_counter_test.dart`, `test/features/reflection_journal/journal_analysis_paused_test.dart` (the code below is already formatter output, so formatting them changes nothing).
- **SQL:** contracts run only on the local scratch database `attune_spec3a`, only as `psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f <file>`, inside the file's own `BEGIN … ROLLBACK`. Confirm the target first (`psql -X -d attune_spec3a -Atc 'select current_database()'` prints `attune_spec3a`). NEVER `attune_test`. NEVER run `scripts/local_pg_setup.sh` (it runs `dropdb`/`createdb`) or `scripts/local_pg_grants.sql` (its blanket grants undo deliberate revokes). This plan **edits** `scripts/local_pg_grants.sql` (one `\i` line per grants twin, the repo pattern, for the from-scratch harness) and never executes it.
- **Migrations**, in spec §4.7 order with the timestamps below (later than every applied migration; the newest applied is `20261025090300_forum_retirement_health.sql`). If `ls supabase/migrations | sort | tail -1` shows anything at or after `20261025100000` when Task 1 starts, shift all twelve to the next free hour, keeping the steps and the order. Don't use `supabase migration new`: it stamps today's date (2026-10-24), which sorts before the applied `20261025…` files.
  - `20261025100000_identity_users_lockdown.sql` + `20261025100010_identity_users_lockdown_grants.sql` (W1a)
  - `20261025100100_metric_counters.sql` + `20261025100110_metric_counters_grants.sql` (W1b)
  - `20261025100200_account_birthdates_and_holds.sql` + `20261025100210_account_birthdates_and_holds_grants.sql` (W1b)
  - `20261025100300_paths_and_home_state.sql` + `20261025100310_paths_and_home_state_grants.sql` (W1b)
  - `20261025100400_spec1_flags_and_public_config.sql` + `20261025100410_spec1_flags_and_public_config_grants.sql` (W1c)
  - `20261025100500_identity_health.sql` + `20261025100510_identity_health_grants.sql` (W1c)
- Supabase CLI 2.75 doesn't wrap a file in a transaction: every migration and twin here carries its own `BEGIN; … COMMIT;`. Every migration is idempotent and is applied to `attune_spec3a`, then applied again to prove it (`exit=0` both times). Every `SECURITY DEFINER` function has `SET search_path = ''` and schema-qualifies every name. Grants are explicit, in the twin; nothing reaches `anon` except `bump_metric` and `get_public_app_config` (both spec'd). No `CREATE INDEX CONCURRENTLY`. `SET LOCAL lock_timeout = '5s'` wherever a table is altered.
- **Feature flags** are inserted `false` by the W1c migration (`ON CONFLICT (key) DO NOTHING`). `supabase/sql/dev_enable_spec1_flags.sql` (not a migration) turns them on, starting with `SELECT private.assert_development_project();`. Nothing in this plan sets `attune_environment`.
- **Security fixes are never behind a flag** (spec §2.5): the `users` column grants with `phone` copied from `auth.users`, and the `profiles` guard on `banned_until` and `confirmed_violation_count` (including a client DELETE). Each has a contract section and a mutant.
- **Never touch:** `lib/features/games/**`, `ChatScreen` game entry points, `UniversalBubble` / `ChatTextField` parameters, `lib/features/auth/utility/auth_exports.dart`, `supabase/tests/games_contracts.sql`; `lib/home/home_screen.dart` (W1 doesn't edit it at all, so its redirect latch at `:340-365` is untouched); the "profiles readable by authenticated" SELECT policy on `profiles.display_name`; the `relationships` grants; `ATTUNE_SOUL.md`, `ATTUNE_THESIS.md`. Keep the `users.mode` column (and its default and CHECK); only its writers go. No SQL fixture is edited.
- **Regression gate at the end of each sub-wave** (Task 4, Task 8, Task 12): every SQL contract on `attune_spec3a` shows no new FAIL against the baseline captured in Task 1 (16 files fail today from known fixture leftovers; use the number you record), and `identity_foundation_contracts.sql` is PASS; the full `flutter test` passes; `flutter analyze --no-pub lib test` shows no new `error` line.
- No deploys. `supabase db push`, `supabase functions deploy …`, the dev flag script on the development project and the `.env.json` key are the owner's, from the "Owner deploy checklist" at the end. Don't read `.env*` or credentials. No new packages.

## Review Focus

1. **A sign-up on the person's 18th birthday, by the UTC date** (and one whose DOB is a day later): a person turning 18 today expects to get in, and someone turning 18 tomorrow must be refused with nothing written. Test: Task 6, Step 1, contract section F part 6 (`an 18th-birthday sign-up` / `someone turning 18 tomorrow was let in`).
2. **A name in a non-Latin script or with West African letters** ("Ɛsi  Ɔbɛng", "عائشة"): the person expects it kept exactly as typed (inner spaces collapsed), while digits-and-punctuation-only names are refused. Test: Task 6, Step 1, section F parts 4–5 (`a non-Latin or West African name was not kept as typed`).
3. **A legacy couple, linked before paths existed (no `users.path`)**: they expect to keep their Chat tab, not be moved onto Me before they answer A6. Test: Task 7, Step 1, section G4 (`linked (legacy, no path)` expects `tab: chat`).
4. **Cancelling an invite "back to where I came from" when Relationship was the first path ever chosen**: the person expects to stay on Relationship (state `none`), never a cleared or null path. Test: Task 7, Step 1, section G3 (`cancelling with no previous path left …`).
5. **A legacy onboarding name longer than 40 characters** (the old name step has no limit) after the new `users_display_name_length` CHECK: the person expects onboarding to save, not to fail and replay forever. Test: Task 4, Step 1 (`a name over 40 characters is clamped to 40 code points, emoji whole`).

## Decisions found while verifying the code (read before Task 1)

Each is a verified fact about today's code or database, with the smallest change that keeps the spec's intent.

- **P-1 (environment source).** On the managed project `ALTER DATABASE … SET app.settings.*` fails with 42501 (`supabase/migrations/20260931120000_vault_backed_settings.sql:1-5`), which is why the repo reads settings through `public.app_setting(name)`: Vault first, then the `app.settings.<name>` GUC. `private.attune_environment()` reads `public.app_setting('attune_environment')` and `private.assert_development_project()` reads `public.app_setting('supabase_url')`. Unset still means development; `set_config('app.settings.attune_environment', …, true)` still drives the contracts (local Vault is empty: `select count(*) from vault.decrypted_secrets` = 0); the owner flips production at launch with `select vault.create_secret('production', 'attune_environment');` (or the spec's `ALTER DATABASE` where it is permitted).
- **P-2 (`withdraw_my_pending_invites`).** Spec §4.3 drops the no-argument function and re-creates it with `p_return_to_previous_path boolean DEFAULT false`. Dropping it turns `supabase/tests/invite_age_contracts.sql:35,37` red (they name `'public.withdraw_my_pending_invites()'`) and breaks the `\i supabase/migrations/20261018130610_invite_age_grants.sql` replay in `scripts/local_pg_grants.sql`. So the no-argument function stays exactly as it is (the app's no-argument call in `relationship_invite_service.dart:142` keeps resolving to it), and the return-to-previous variant is a new overload `withdraw_my_pending_invites(p_return_to_previous_path boolean)` with no default, which calls the original and then restores `path_previous`.
- **P-3 (home tab for a legacy couple).** `get_my_home_state().tab` is `chat` on the Relationship path, and also for an account with no path yet whose latest relationship is pending, linked or paused (Review Focus 3). Otherwise `me`.
- **P-4 / P-5 (home-state shape).** The answer adds `has_account` (A4 needs "no account → A5" apart from a legacy account with `needs`), and `hold` is a boolean (H1 shows no reason).
- **P-6 (40-character names).** A `NOT VALID` CHECK still binds every later UPDATE of an old row (a path write, a phone sync), so migration 1 first trims any existing `users.display_name` longer than 40 characters (none on `attune_spec3a`: `max(char_length(display_name))` = 13), and the legacy client clamps the name it sends to 40 code points (Review Focus 5).
- **P-7 (the five dating functions).** Re-created from their live bodies (`pg_get_functiondef` on `attune_spec3a`, which match `20260705210000` for `activate_dating_profile` and `20260703203000` for the other four) minus the `UPDATE public.users SET mode …` statement, with two binding-constraint changes: `SET search_path = ''` (was `public`) and `RETURNS public.dating_enrollments`. Every name in the bodies is already schema-qualified; every callee sets its own `search_path` (`check_dating_rate_limit`, `dating_flag_enabled`, `dating_healing_gates_hold`, `dating_age_gate_holds`, `dating_has_relationship`, `claim_dating_idempotency`, `invalidate_dating_for_user` = `{search_path=public}`, `dating_account_in_good_standing` = `{"search_path=public, auth"}`), and the trigger functions on the tables they write (`set_updated_at`, `bump_dating_*_version`) name no relation. No test reads their `proconfig`.
- **P-8 (`recorded_by`).** Inside a `SECURITY DEFINER` function `current_user` is the owner, so `record_flag_gate_evidence` records the JWT role, else `session_user`.
- **P-9 (service_role on new tables).** `supabase/tests/service_role_grants_test.sql` requires `service_role` SELECT and UPDATE on every `public` table, so each new public table gets explicit service_role DML; the spec's "no grants" means no client grants.
- **P-10 (`anon` on users).** The hosted project's default privileges give `anon` table DML on new public tables; the W1a twin also revokes `INSERT, UPDATE, DELETE` on `users` from `anon` (RLS already refuses it), so the "no client inserts a users row" contract holds under CI's real Supabase too.
- **P-11 (`healing_ai_insights`).** Owner approval O2 puts the Healing pause in S1 W9 behind `healing_ai_insights`; W9 inserts that flag and its gate row. W1c inserts the eleven flags spec §2.5 lists.
- **P-12 (one capped metric writer).** The exact client keys are not under any server prefix, so both `private.bump_metric_internal` (prefix rule) and `bump_metric` (exact keys) call one internal writer, `private.metric_increment(text)`, which applies the pattern and the daily cap.
- **P-13 (`verified_phone`).** Returns NULL for an unconfirmed phone; `complete_sign_up` uses it for `signup:phone_required`.
- **P-14 (local roles).** On `attune_spec3a` the connecting role is the superuser `user`; there is no `postgres` or `supabase_auth_admin` role. Definer functions are owned by `user` locally and by `postgres` in CI, so the `profiles` guard's `current_user IN ('authenticated', 'anon')` test behaves the same in both.
- **P-15 (W1c client scope).** `PublicAppConfig` parses all four public flags, but W1c adds only the providers a next wave reads: `publicAppConfigProvider`, `flowSignInV2Provider` and `datingOpenCountriesProvider` (W2a). `platformAgeSignalsProvider`, `supportResourcesV2Provider`, `textScaleCapProvider` and the signed-in `flowPathsV2Provider` / `flowCouplesV2Provider` / `coupleProfileEnabledProvider` (spec §5.3) arrive with the waves that read them. Nothing in the app reads the new providers yet, so W1 changes no screen.

## File map

**W1a (Tasks 1–4): users and profiles lockdown**
- Create `supabase/migrations/20261025100000_identity_users_lockdown.sql` (Task 1; extended in Tasks 2, 3): `users` path columns, the 40-character CHECK, the `mode` comment, the `auth.users` phone mirror, `verified_phone`, the `profiles` moderation guard, the five dating functions without `users.mode`.
- Create `supabase/migrations/20261025100010_identity_users_lockdown_grants.sql` (Task 1; extended in Tasks 2, 3): the `users` column grants and every function grant of migration 1.
- Create `supabase/tests/identity_foundation_contracts.sql` (Task 1; one section added per SQL task): the whole W1 contract.
- Modify `scripts/local_pg_grants.sql` (append after line 241; Tasks 1, 5, 6, 7, 9, 10): one `\i` line per twin. Edited, never run.
- Modify `lib/features/onboarding/data/onboarding_submission_service.dart:36-49, 58, 80` (Task 4; lines `:36` and `:68` of the original in Task 7): `users` becomes an update of the name only, clamped to 40 code points; then `onboarding_profiles.mode` goes.
- Create `test/features/onboarding/onboarding_submission_service_test.dart` (Task 4; one test added in Task 7).
- Modify `supabase/functions/accept-invite/index.ts:145-168` and `supabase/functions/create-relationship-invite/index.ts:141-164` (Task 4): `ensureUserRow` writes no `mode` and no phone as a name.
- Modify `supabase/functions/accept-invite/index.test.ts` (append after line 21; Task 4).

**W1b (Tasks 5–8): metrics, birth dates, holds, paths, home state**
- Create `supabase/migrations/20261025100100_metric_counters.sql` + `…100110_metric_counters_grants.sql` (Task 5).
- Create `supabase/migrations/20261025100200_account_birthdates_and_holds.sql` + `…100210_account_birthdates_and_holds_grants.sql` (Task 6).
- Create `supabase/migrations/20261025100300_paths_and_home_state.sql` + `…100310_paths_and_home_state_grants.sql` (Task 7).
- Create `lib/features/onboarding/domain/home_state.dart`, `lib/features/onboarding/data/home_state_store.dart`, `test/features/onboarding/home_state_test.dart`, `test/features/onboarding/home_state_store_test.dart` (Task 8).

**W1c (Tasks 9–12): environment, flags, public config, health, Journal pause, scoped invite**
- Create `supabase/migrations/20261025100400_spec1_flags_and_public_config.sql` + `…100410_spec1_flags_and_public_config_grants.sql`, `supabase/sql/dev_enable_spec1_flags.sql` (Task 9).
- Create `supabase/migrations/20261025100500_identity_health.sql` + `…100510_identity_health_grants.sql`, `supabase/functions/purge-unfinished-signups/{handler.ts,index.ts,handler.test.ts}` (Task 10).
- Create `supabase/functions/analyse-journal-entry/journal_pause.ts` + `journal_pause.test.ts`; modify `supabase/functions/analyse-journal-entry/index.ts:4, 59-60`; modify `lib/features/reflection_journal/data/models/journal_analysis.dart:4, 27`; create `test/features/reflection_journal/journal_analysis_paused_test.dart` (Task 11).
- Create `lib/core/flags/public_app_config.dart`, `lib/core/metrics/metric_counter.dart`, `test/core/flags/public_app_config_test.dart`, `test/core/metrics/metric_counter_test.dart`, `test/features/onboarding/scoped_invite_code_test.dart`; modify `lib/core/config/env.dart:66-68`, `lib/app/feature_flag_refresher.dart:1, 25-26`, `lib/features/onboarding/data/onboarding_store.dart:1, 56-70, 167-175, 206-212`, `lib/main.dart:182-187` (Task 12).

**Not edited:** `lib/home/home_screen.dart`, `lib/features/onboarding/presentation/screens/onboarding_gate.dart` (both keep calling `store.pendingInviteCode`, which now claims the scoped slot), `lib/features/relationships/data/relationship_invite_service.dart`, every games file, every existing SQL contract, every applied migration.

---

### Task 1: Baselines, and `users` locked down (W1a)

**Files:**
- Create: `supabase/migrations/20261025100000_identity_users_lockdown.sql`
- Create: `supabase/migrations/20261025100010_identity_users_lockdown_grants.sql`
- Create: `supabase/tests/identity_foundation_contracts.sql`
- Modify: `scripts/local_pg_grants.sql` (append after the last line, 241)

**Interfaces:**
- Consumes: nothing from this plan. Existing: `public.users` (`phone text NOT NULL UNIQUE`, `display_name text NOT NULL`, `mode text NOT NULL DEFAULT 'personal'`), `auth.users (phone, phone_confirmed_at)`, `public.record_eula_acceptance(text)` (creates the users row with the phone from `auth.users`, unchanged).
- Produces: columns `public.users.path text` (`relationship|dating|just_me`), `path_previous text`, `path_chosen_at timestamptz`, `phone_released_at timestamptz`; constraint `users_display_name_length` (≤ 40); trigger `auth_users_phone_sync` on `auth.users` → `private.sync_users_phone_from_auth()`; `public.verified_phone(p_user uuid) RETURNS text` (no client grant; NULL when unconfirmed); `authenticated` may UPDATE only `users.display_name`, `avatar_url`, `timezone` and may not INSERT. Contract helpers in the test file: `pg_temp.as_user(uuid)`, `pg_temp.as_anon()`, `pg_temp.make_account(uuid, text phone, text name_or_null)`, `pg_temp.error_of(text sql) RETURNS text` (the refusal's message or NULL).

- [ ] **Step 1: Confirm the target and the newest migration**

```bash
cd /Users/user/attune
psql -X -d attune_spec3a -Atc 'select current_database()'
ls supabase/migrations | sort | tail -1
mkdir -p .superpowers/sdd/2026-10-25-spec1-w1
git status --short > .superpowers/sdd/2026-10-25-spec1-w1/git-status-before.txt
```
Expected: `attune_spec3a`, then `20261025090300_forum_retirement_health.sql` (if newer, shift the timestamps as Global Constraints says). `.superpowers/` is gitignored; the status snapshot lets Task 12 prove no protected file moved.

- [ ] **Step 2: Record the SQL contract baseline**

```bash
cd /Users/user/attune
for f in supabase/tests/*.sql; do
  if psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f "$f" >/dev/null 2>&1; then echo "PASS $(basename "$f")"; else echo "FAIL $(basename "$f")"; fi
done > .superpowers/sdd/2026-10-25-spec1-w1/sql-baseline.txt
grep -c '^FAIL' .superpowers/sdd/2026-10-25-spec1-w1/sql-baseline.txt
```
Expected: a count (16 when this plan was written). Keep the file: every gate compares against it.

- [ ] **Step 3: Record the Flutter baselines**

```bash
cd /Users/user/attune
flutter test --no-pub 2>&1 | tr '\r' '\n' | grep -E 'All tests passed!|Some tests failed' | tail -1
flutter analyze --no-pub lib test > .superpowers/sdd/2026-10-25-spec1-w1/analyze-baseline.txt 2>&1
grep -E '^\s*error ' .superpowers/sdd/2026-10-25-spec1-w1/analyze-baseline.txt | sed -E 's/:[0-9]+:[0-9]+//' | sort -u > .superpowers/sdd/2026-10-25-spec1-w1/analyze-errors-baseline.txt
wc -l < .superpowers/sdd/2026-10-25-spec1-w1/analyze-errors-baseline.txt
```
Expected: a line ending `All tests passed!`, then `0` (no analyzer errors under `lib` and `test`). If either differs, stop and report: the gate needs a green start.

- [ ] **Step 4: Write the failing contract (sections A and B)**

Create `supabase/tests/identity_foundation_contracts.sql` with exactly:

```sql
-- supabase/tests/identity_foundation_contracts.sql
-- Spec 1 W1 (identity foundation) §7.1: users and profiles lockdown (W1a),
-- metrics, birth dates, holds, paths and home state (W1b), environment,
-- flags, public config and identity health (W1c). One BEGIN ... ROLLBACK.
-- Run only on attune_spec3a:
--   psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/identity_foundation_contracts.sql
-- Fixture ids 5f1a0000-0000-0000-0000-0000000000NN (relationships ...00000001NN);
-- phones +15558100NN, set on auth.users and public.users. Plain INSERTs, so a
-- leftover fixture fails loudly instead of being skipped. Every refusal is
-- checked by its exact message.
BEGIN;

CREATE FUNCTION pg_temp.as_user(p uuid) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claim.sub', p::text, true);
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', p, 'role', 'authenticated')::text, true);
END $$;

CREATE FUNCTION pg_temp.as_anon() RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE 'SET LOCAL ROLE anon';
  PERFORM set_config('request.jwt.claim.sub', '', true);
  PERFORM set_config('request.jwt.claims', json_build_object('role', 'anon')::text, true);
END $$;

-- An Auth user with a verified phone; with a name, also its users row.
CREATE FUNCTION pg_temp.make_account(p_id uuid, p_phone text, p_name text) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO auth.users (id, phone, phone_confirmed_at) VALUES (p_id, p_phone, now());
  IF p_name IS NOT NULL THEN
    INSERT INTO public.users (id, phone, display_name) VALUES (p_id, p_phone, p_name);
  END IF;
END $$;

-- Runs p_sql as the current role and returns the refusal's message, or NULL
-- when it succeeded. Only the refusals these contracts expect are caught.
CREATE FUNCTION pg_temp.error_of(p_sql text) RETURNS text LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE p_sql;
  RETURN NULL;
EXCEPTION WHEN raise_exception OR insufficient_privilege OR check_violation THEN
  RETURN SQLERRM;
END $$;

-- =====================================================================
-- A. users (W1a; Q5, research 10 F-1): the client changes only its name,
--    avatar and time zone; it never inserts its own row; phone is copied
--    from auth.users. Fixtures 01-03.
-- =====================================================================
DO $$
BEGIN
  IF to_regprocedure('public.verified_phone(uuid)') IS NULL
     OR NOT EXISTS (SELECT 1 FROM information_schema.columns
                     WHERE table_schema = 'public' AND table_name = 'users' AND column_name = 'path') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: W1a objects are missing (users.path, public.verified_phone)';
  END IF;
END $$;

DO $$
BEGIN
  PERFORM pg_temp.make_account('5f1a0000-0000-0000-0000-000000000001', '+15558100001', 'Ama W1');
  PERFORM pg_temp.make_account('5f1a0000-0000-0000-0000-000000000002', '+15558100002', NULL);
  PERFORM pg_temp.make_account('5f1a0000-0000-0000-0000-000000000003', '+15558100003', 'Kofi W1');
END $$;

DO $$
DECLARE
  v_me constant uuid := '5f1a0000-0000-0000-0000-000000000001';
  v_new constant uuid := '5f1a0000-0000-0000-0000-000000000002';
  v_col text;
  v_bad text;
  v_msg text;
  v_n int;
BEGIN
  -- Grants: UPDATE on exactly three columns; INSERT on none; SELECT kept.
  SELECT string_agg(a.attname, ', ' ORDER BY a.attname) INTO v_bad
    FROM pg_attribute a
   WHERE a.attrelid = 'public.users'::regclass AND a.attnum > 0 AND NOT a.attisdropped
     AND a.attname NOT IN ('display_name', 'avatar_url', 'timezone')
     AND has_column_privilege('authenticated', 'public.users', a.attname, 'UPDATE');
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: authenticated may UPDATE users.%', v_bad;
  END IF;
  SELECT string_agg(a.attname, ', ' ORDER BY a.attname) INTO v_bad
    FROM pg_attribute a
   WHERE a.attrelid = 'public.users'::regclass AND a.attnum > 0 AND NOT a.attisdropped
     AND (has_column_privilege('authenticated', 'public.users', a.attname, 'INSERT')
          OR has_column_privilege('anon', 'public.users', a.attname, 'INSERT'));
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a client may INSERT users.%', v_bad;
  END IF;
  IF NOT has_column_privilege('authenticated', 'public.users', 'display_name', 'UPDATE')
     OR NOT has_column_privilege('authenticated', 'public.users', 'avatar_url', 'UPDATE')
     OR NOT has_column_privilege('authenticated', 'public.users', 'timezone', 'UPDATE')
     OR NOT has_table_privilege('authenticated', 'public.users', 'SELECT') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the client lost a users grant it still needs';
  END IF;

  -- Behaviour: each server-owned column is refused by the grant itself.
  FOREACH v_col IN ARRAY ARRAY['phone', 'mode', 'path', 'path_previous', 'path_chosen_at',
                               'phone_released_at', 'eula_version', 'eula_accepted_at'] LOOP
    PERFORM pg_temp.as_user(v_me);
    v_msg := pg_temp.error_of(format('UPDATE public.users SET %I = %s WHERE id = %L', v_col,
      CASE v_col
        WHEN 'phone' THEN quote_literal('+15558100099')
        WHEN 'mode' THEN quote_literal('dating')
        WHEN 'path' THEN quote_literal('dating')
        WHEN 'path_previous' THEN quote_literal('dating')
        WHEN 'eula_version' THEN quote_literal('2')
        ELSE 'now()'
      END, v_me));
    RESET ROLE;
    IF v_msg IS DISTINCT FROM 'permission denied for table users' THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: a client wrote users.% directly (got %)', v_col, coalesce(v_msg, 'no error');
    END IF;
  END LOOP;

  -- The three self-service columns still work for the owner of the row.
  PERFORM pg_temp.as_user(v_me);
  UPDATE public.users
     SET display_name = 'Ama Renamed', avatar_url = 'https://example.invalid/a.png', timezone = 'Africa/Accra'
   WHERE id = v_me;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RESET ROLE;
  IF v_n <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the owner could not update name, avatar and time zone (% rows)', v_n;
  END IF;

  -- No client creates its own users row.
  PERFORM pg_temp.as_user(v_new);
  v_msg := pg_temp.error_of(format(
    'INSERT INTO public.users (id, phone, display_name) VALUES (%L, %L, %L)', v_new, '+15558100002', 'Kwame W1'));
  RESET ROLE;
  IF v_msg IS DISTINCT FROM 'permission denied for table users' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a client inserted its own users row (got %)', coalesce(v_msg, 'no error');
  END IF;

  -- display_name: 40 characters at most for every new write.
  v_msg := pg_temp.error_of(format('UPDATE public.users SET display_name = repeat(%L, 41) WHERE id = %L', 'a', v_me));
  IF v_msg IS DISTINCT FROM 'new row for relation "users" violates check constraint "users_display_name_length"' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a 41-character users.display_name was not refused (got %)', coalesce(v_msg, 'no error');
  END IF;

  -- users.mode is retired, and says so.
  IF coalesce(col_description('public.users'::regclass,
       (SELECT attnum FROM pg_attribute WHERE attrelid = 'public.users'::regclass AND attname = 'mode')::int), '')
     NOT LIKE 'Retired (Spec 1 W1).%' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: users.mode is not marked retired';
  END IF;
END $$;

-- =====================================================================
-- B. The phone is Auth's (W1a): the mirror follows auth.users, a NULL Auth
--    phone never blanks it, and verified_phone reads only a confirmed phone.
-- =====================================================================
DO $$
DECLARE
  v_me constant uuid := '5f1a0000-0000-0000-0000-000000000003';
BEGIN
  UPDATE auth.users SET phone = '+15558100093' WHERE id = v_me;
  IF (SELECT phone FROM public.users WHERE id = v_me) IS DISTINCT FROM '+15558100093' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an Auth phone change did not reach public.users';
  END IF;
  UPDATE auth.users SET phone = NULL WHERE id = v_me;
  IF (SELECT phone FROM public.users WHERE id = v_me) IS DISTINCT FROM '+15558100093' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a NULL Auth phone overwrote public.users.phone';
  END IF;

  UPDATE auth.users SET phone = '+15558100093', phone_confirmed_at = now() WHERE id = v_me;
  IF public.verified_phone(v_me) IS DISTINCT FROM '+15558100093' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: verified_phone did not return the confirmed Auth phone';
  END IF;
  UPDATE auth.users SET phone_confirmed_at = NULL WHERE id = v_me;
  IF public.verified_phone(v_me) IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: verified_phone returned an unconfirmed phone';
  END IF;

  IF has_function_privilege('authenticated', 'public.verified_phone(uuid)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.verified_phone(uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a client can run verified_phone';
  END IF;
END $$;

ROLLBACK;
```

- [ ] **Step 5: Run it to verify it fails**

```bash
cd /Users/user/attune
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/identity_foundation_contracts.sql; echo "exit=$?"
```
Expected: `ERROR:  CONTRACT VIOLATED: W1a objects are missing (users.path, public.verified_phone)` and `exit=3`.

- [ ] **Step 6: Write the migration**

Create `supabase/migrations/20261025100000_identity_users_lockdown.sql` with exactly:

```sql
-- Spec 1 (app flow and identity) W1a, migration 1 of 6 (spec §4.7 #1):
-- identity_users_lockdown. Security hardening, never behind a flag (§2.5).
--   * users gains path, path_previous, path_chosen_at and phone_released_at;
--     their writers arrive in W1b (set_user_path_internal) and W6a.
--   * users.mode is retired (D3): the five dating functions below stop
--     writing it, as do the client upsert and both invite functions in the
--     same release. The column stays: SQL fixtures still insert it.
--   * users.phone is copied from auth.users (Q5, research 10 F-1): the client
--     loses the column grant (20261025100010) and a trigger mirrors Auth.
--   * profiles.banned_until and confirmed_violation_count are server-only,
--     and a profile with strikes or a live ban can't be deleted (D5, S-1).
-- Grants in 20261025100010_identity_users_lockdown_grants.sql.
BEGIN;
SET LOCAL lock_timeout = '5s';

-- 1. users: the path columns ------------------------------------------------
ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS path text
    CONSTRAINT users_path_check CHECK (path IN ('relationship', 'dating', 'just_me')),
  ADD COLUMN IF NOT EXISTS path_previous text
    CONSTRAINT users_path_previous_check CHECK (path_previous IN ('relationship', 'dating', 'just_me')),
  ADD COLUMN IF NOT EXISTS path_chosen_at timestamptz,
  ADD COLUMN IF NOT EXISTS phone_released_at timestamptz;

COMMENT ON COLUMN public.users.path IS
  'Spec 1: relationship | dating | just_me. Written only by set_user_path_internal (W1b).';
COMMENT ON COLUMN public.users.phone_released_at IS
  'Spec 1 W6a: set when the account is parked for a fresh start.';
COMMENT ON COLUMN public.users.mode IS
  'Retired (Spec 1 W1). Not written by the app, edge functions or SQL functions; not granted to clients. Kept so SQL fixtures still insert it.';

-- A NOT VALID check still binds every later UPDATE of an old row (a path
-- write, a phone sync), so a legacy name over 40 characters is trimmed
-- first; nothing else about the row changes.
UPDATE public.users SET display_name = left(display_name, 40)
 WHERE char_length(display_name) > 40;
ALTER TABLE public.users DROP CONSTRAINT IF EXISTS users_display_name_length;
ALTER TABLE public.users
  ADD CONSTRAINT users_display_name_length CHECK (char_length(display_name) <= 40) NOT VALID;

-- 2. users.phone mirrors auth.users ----------------------------------------
-- AFTER UPDATE only: fixtures that insert public.users directly keep
-- working. A NULL Auth phone never blanks the mirror (users.phone is NOT NULL).
CREATE OR REPLACE FUNCTION private.sync_users_phone_from_auth()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  UPDATE public.users
     SET phone = NEW.phone
   WHERE id = NEW.id
     AND phone IS DISTINCT FROM NEW.phone;
  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS auth_users_phone_sync ON auth.users;
CREATE TRIGGER auth_users_phone_sync
  AFTER UPDATE OF phone ON auth.users
  FOR EACH ROW
  WHEN (NEW.phone IS NOT NULL AND NEW.phone IS DISTINCT FROM OLD.phone)
  EXECUTE FUNCTION private.sync_users_phone_from_auth();

-- 3. The verified phone, for definer callers (Spec 2 builds its HMAC on it).
CREATE OR REPLACE FUNCTION public.verified_phone(p_user uuid)
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT nullif(btrim(u.phone), '')
    FROM auth.users u
   WHERE u.id = p_user
     AND u.phone_confirmed_at IS NOT NULL;
$$;

COMMIT;
```

- [ ] **Step 7: Write the grants twin**

Create `supabase/migrations/20261025100010_identity_users_lockdown_grants.sql` with exactly:

```sql
-- Spec 1 W1a: grants for 20261025100000_identity_users_lockdown.sql.
-- users: SELECT stays (own-row RLS). INSERT goes: a users row is written by
-- record_eula_acceptance, complete_sign_up (W1b) and the invite functions'
-- service role, always with the phone from auth.users. UPDATE is limited to
-- the three self-service columns (timezone stays: set_my_timezone is the
-- app's path and user_timezone_contracts.sql:133 relies on a direct write).
-- The policy "users insert own profile" stays; it is inert without INSERT.
-- anon never writes users (RLS refuses it anyway); the hosted project's
-- default privileges grant it table DML, so that goes too.
BEGIN;
REVOKE INSERT, UPDATE ON public.users FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.users FROM anon;
GRANT UPDATE (display_name, avatar_url, timezone) ON public.users TO authenticated;

REVOKE ALL ON FUNCTION public.verified_phone(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.sync_users_phone_from_auth() FROM PUBLIC, anon, authenticated;
COMMIT;
```

- [ ] **Step 8: Apply both, then apply both again (idempotency)**

```bash
cd /Users/user/attune
for i in 1 2; do
  psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/migrations/20261025100000_identity_users_lockdown.sql; echo "migration exit=$?"
  psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/migrations/20261025100010_identity_users_lockdown_grants.sql; echo "grants exit=$?"
done
```
Expected: four lines `… exit=0`; the second pass may print `NOTICE: column "path" of relation "users" already exists, skipping` and similar.

- [ ] **Step 9: Run the contract to verify it passes**

```bash
cd /Users/user/attune
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/identity_foundation_contracts.sql; echo "exit=$?"
```
Expected: no `ERROR` line, `exit=0`.

- [ ] **Step 10: Mutation check (spec §7.4 `GRANT UPDATE (phone)`)**

```bash
cd /Users/user/attune
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a <<'SQL'; echo "exit=$?"
BEGIN;
GRANT UPDATE (phone) ON public.users TO authenticated;
\i supabase/tests/identity_foundation_contracts.sql
SQL
```
Expected: `ERROR:  CONTRACT VIOLATED: authenticated may UPDATE users.phone`, `exit=3`. The mutant dies with the session (nothing persists). Confirm: `psql -X -d attune_spec3a -Atc "select has_column_privilege('authenticated','public.users','phone','UPDATE')"` prints `f`.

- [ ] **Step 11: Add the twin to the local harness (edit only, never run)**

Append to the end of `scripts/local_pg_grants.sql`:

```sql

-- Spec 1 W1a: users column grants (no client INSERT; UPDATE of name, avatar
-- and time zone only) and migration 1's function grants.
\i supabase/migrations/20261025100010_identity_users_lockdown_grants.sql
```

- [ ] **Step 12: Run tests**

```bash
cd /Users/user/attune
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/identity_foundation_contracts.sql; echo "identity exit=$?"
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/user_timezone_contracts.sql; echo "timezone exit=$?"
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/invite_age_contracts.sql; echo "invite_age exit=$?"
```
Expected: `identity exit=0`, and `timezone`/`invite_age` exit as in the baseline file (`grep -E 'user_timezone|invite_age' .superpowers/sdd/2026-10-25-spec1-w1/sql-baseline.txt`).

---

### Task 2: The `profiles` moderation guard (W1a; D5, review S-1)

**Files:**
- Modify: `supabase/migrations/20261025100000_identity_users_lockdown.sql` (insert section 4 before the final `COMMIT;`)
- Modify: `supabase/migrations/20261025100010_identity_users_lockdown_grants.sql` (insert one line before the final `COMMIT;`)
- Modify: `supabase/tests/identity_foundation_contracts.sql` (insert section C before the final `ROLLBACK;`)

**Interfaces:**
- Consumes: Task 1's contract helpers (`pg_temp.as_user`, `pg_temp.make_account`, `pg_temp.error_of`).
- Produces: trigger `profiles_guard_moderation_columns` (BEFORE INSERT OR UPDATE OR DELETE on `public.profiles`) → `private.guard_profile_moderation_columns()` (not SECURITY DEFINER; acts only when `current_user IN ('authenticated','anon')`). Client UPDATE that changes `banned_until` or `confirmed_violation_count` raises `profile:moderation_column`; client INSERT forces them to `NULL` / `0`; client DELETE of a profile with strikes or a future ban raises `profile:moderation_locked`. Definer functions and `service_role` write both columns unchanged (W9b's `admin_confirm_content_removal` relies on that).

- [ ] **Step 1: Write the failing contract section**

In `supabase/tests/identity_foundation_contracts.sql`, insert immediately before the final line `ROLLBACK;`:

```sql
-- =====================================================================
-- C. profiles moderation guard (W1a; D5, review S-1). A client can't clear
--    a ban, reset or change its strike count, arrive pre-banned, or delete
--    and re-create a profile with strikes or a live ban. Everything else a
--    client writes still works, and the server still writes both columns.
--    Fixtures 04-07.
-- =====================================================================
DO $$
BEGIN
  IF to_regprocedure('private.guard_profile_moderation_columns()') IS NULL
     OR NOT EXISTS (SELECT 1 FROM pg_trigger
                     WHERE tgrelid = 'public.profiles'::regclass
                       AND tgname = 'profiles_guard_moderation_columns' AND NOT tgisinternal) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the profiles moderation guard is missing (D5, S-1)';
  END IF;
END $$;

DO $$
BEGIN
  PERFORM pg_temp.make_account('5f1a0000-0000-0000-0000-000000000004', '+15558100004', 'Kofi W1');
  PERFORM pg_temp.make_account('5f1a0000-0000-0000-0000-000000000005', '+15558100005', 'Esi W1');
  PERFORM pg_temp.make_account('5f1a0000-0000-0000-0000-000000000006', '+15558100006', 'Yaw W1');
  PERFORM pg_temp.make_account('5f1a0000-0000-0000-0000-000000000007', '+15558100007', 'Abena W1');
END $$;

-- Stands in for a SECURITY DEFINER server function (complete_sign_up,
-- set_user_path_internal, admin_confirm_content_removal's callers).
CREATE FUNCTION pg_temp.definer_clear_ban(p uuid) RETURNS void
LANGUAGE sql SECURITY DEFINER AS $$
  UPDATE public.profiles SET banned_until = NULL WHERE id = p;
$$;

DO $$
DECLARE
  v_struck constant uuid := '5f1a0000-0000-0000-0000-000000000004';
  v_banned constant uuid := '5f1a0000-0000-0000-0000-000000000005';
  v_clean constant uuid := '5f1a0000-0000-0000-0000-000000000006';
  v_new constant uuid := '5f1a0000-0000-0000-0000-000000000007';
  v_msg text;
  v_n int;
  v_count int;
  v_ban timestamptz;
  v_name text;
BEGIN
  -- Seeded by the owner, the way the service-role moderation function writes them.
  INSERT INTO public.profiles (id, display_name, confirmed_violation_count, banned_until) VALUES
    (v_struck, 'Kofi', 2, NULL),
    (v_banned, 'Esi', 0, now() + interval '3 days'),
    (v_clean, 'Yaw', 0, NULL);

  -- 1. No client write to either column.
  PERFORM pg_temp.as_user(v_banned);
  v_msg := pg_temp.error_of(format('UPDATE public.profiles SET banned_until = NULL WHERE id = %L', v_banned));
  RESET ROLE;
  IF v_msg IS DISTINCT FROM 'profile:moderation_column' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a client cleared its own Opinions ban (got %)', coalesce(v_msg, 'no error');
  END IF;

  PERFORM pg_temp.as_user(v_struck);
  v_msg := pg_temp.error_of(format('UPDATE public.profiles SET confirmed_violation_count = 0 WHERE id = %L', v_struck));
  RESET ROLE;
  IF v_msg IS DISTINCT FROM 'profile:moderation_column' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a client reset its own strike count (got %)', coalesce(v_msg, 'no error');
  END IF;

  PERFORM pg_temp.as_user(v_struck);
  v_msg := pg_temp.error_of(format('UPDATE public.profiles SET confirmed_violation_count = 7 WHERE id = %L', v_struck));
  RESET ROLE;
  IF v_msg IS DISTINCT FROM 'profile:moderation_column' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a client changed its own strike count (got %)', coalesce(v_msg, 'no error');
  END IF;

  PERFORM pg_temp.as_user(v_clean);
  v_msg := pg_temp.error_of(format(
    'UPDATE public.profiles SET banned_until = now() + interval %L WHERE id = %L', '1 day', v_clean));
  RESET ROLE;
  IF v_msg IS DISTINCT FROM 'profile:moderation_column' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a client set a ban on itself (got %)', coalesce(v_msg, 'no error');
  END IF;

  -- An upsert that names banned_until is an update of it.
  PERFORM pg_temp.as_user(v_banned);
  v_msg := pg_temp.error_of(format(
    'INSERT INTO public.profiles (id, banned_until) VALUES (%L, NULL) '
    'ON CONFLICT (id) DO UPDATE SET banned_until = EXCLUDED.banned_until', v_banned));
  RESET ROLE;
  IF v_msg IS DISTINCT FROM 'profile:moderation_column' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an upsert cleared a ban (got %)', coalesce(v_msg, 'no error');
  END IF;

  -- 2. Everything else still works, for a struck author too (R6).
  PERFORM pg_temp.as_user(v_struck);
  UPDATE public.profiles SET preferred_location = 'Accra', last_location_update = now() WHERE id = v_struck;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  INSERT INTO public.profiles (id, display_name, relationship_status, updated_at)
  VALUES (v_struck, 'Kofi A.', 'taken', now())
  ON CONFLICT (id) DO UPDATE
    SET display_name = EXCLUDED.display_name,
        relationship_status = EXCLUDED.relationship_status,
        updated_at = EXCLUDED.updated_at;
  RESET ROLE;
  SELECT confirmed_violation_count, display_name INTO v_count, v_name FROM public.profiles WHERE id = v_struck;
  IF v_n <> 1 OR v_count <> 2 OR v_name <> 'Kofi A.' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an ordinary profile write broke (location rows %, strikes %, name %)',
      v_n, v_count, v_name;
  END IF;

  -- 3. A client INSERT can't arrive pre-banned or pre-struck.
  PERFORM pg_temp.as_user(v_new);
  INSERT INTO public.profiles (id, display_name, banned_until, confirmed_violation_count)
  VALUES (v_new, 'Abena', now() + interval '9 days', 5);
  RESET ROLE;
  SELECT banned_until, confirmed_violation_count INTO v_ban, v_count FROM public.profiles WHERE id = v_new;
  IF v_ban IS NOT NULL OR v_count <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a client insert stored banned_until %, strikes %', v_ban, v_count;
  END IF;

  -- 4. Delete-and-re-create can't reset strikes or a live ban; a clean profile can go.
  PERFORM pg_temp.as_user(v_struck);
  v_msg := pg_temp.error_of(format('DELETE FROM public.profiles WHERE id = %L', v_struck));
  RESET ROLE;
  IF v_msg IS DISTINCT FROM 'profile:moderation_locked' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a client deleted a profile with strikes (got %)', coalesce(v_msg, 'no error');
  END IF;
  PERFORM pg_temp.as_user(v_banned);
  v_msg := pg_temp.error_of(format('DELETE FROM public.profiles WHERE id = %L', v_banned));
  RESET ROLE;
  IF v_msg IS DISTINCT FROM 'profile:moderation_locked' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a client deleted a profile with a live ban (got %)', coalesce(v_msg, 'no error');
  END IF;
  PERFORM pg_temp.as_user(v_clean);
  DELETE FROM public.profiles WHERE id = v_clean;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RESET ROLE;
  IF v_n <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the owner could not delete a clean profile';
  END IF;

  -- 5. The server still writes both: the service role, and a definer function
  --    called by a client.
  SET LOCAL ROLE service_role;
  UPDATE public.profiles SET confirmed_violation_count = 3, banned_until = now() + interval '7 days'
   WHERE id = v_struck;
  RESET ROLE;
  SELECT confirmed_violation_count, banned_until INTO v_count, v_ban FROM public.profiles WHERE id = v_struck;
  IF v_count <> 3 OR v_ban IS NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the service role could not record a strike and a ban';
  END IF;
  PERFORM pg_temp.as_user(v_banned);
  PERFORM pg_temp.definer_clear_ban(v_banned);
  RESET ROLE;
  IF (SELECT banned_until FROM public.profiles WHERE id = v_banned) IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a definer function could not clear a ban';
  END IF;
END $$;
```

- [ ] **Step 2: Run it to verify it fails**

```bash
cd /Users/user/attune
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/identity_foundation_contracts.sql; echo "exit=$?"
```
Expected: `ERROR:  CONTRACT VIOLATED: the profiles moderation guard is missing (D5, S-1)`, `exit=3`.

- [ ] **Step 3: Add the guard to migration 1**

In `supabase/migrations/20261025100000_identity_users_lockdown.sql`, insert immediately before the final line `COMMIT;`:

```sql
-- 4. profiles: the moderation columns are server-only (D5, S-1) ------------
-- Deliberately NOT SECURITY DEFINER: the whole check is "who is
-- current_user", which a definer function would rewrite to its owner
-- (precedent 20261019110300_system_notice_server_only.sql:19-31). Definer
-- functions and the service role pass; only a direct client write is
-- inspected, and only these two columns and deletes.
CREATE OR REPLACE FUNCTION private.guard_profile_moderation_columns()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
  IF current_user NOT IN ('authenticated', 'anon') THEN
    IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
    RETURN NEW;
  END IF;
  IF TG_OP = 'INSERT' THEN
    NEW.banned_until := NULL;
    NEW.confirmed_violation_count := 0;
    RETURN NEW;
  END IF;
  IF TG_OP = 'UPDATE' THEN
    IF NEW.banned_until IS DISTINCT FROM OLD.banned_until OR NEW.confirmed_violation_count IS DISTINCT FROM OLD.confirmed_violation_count THEN
      RAISE EXCEPTION 'profile:moderation_column';
    END IF;
    RETURN NEW;
  END IF;
  IF OLD.confirmed_violation_count > 0 OR OLD.banned_until > now() THEN
    RAISE EXCEPTION 'profile:moderation_locked';
  END IF;
  RETURN OLD;
END;
$$;

DROP TRIGGER IF EXISTS profiles_guard_moderation_columns ON public.profiles;
CREATE TRIGGER profiles_guard_moderation_columns
  BEFORE INSERT OR UPDATE OR DELETE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION private.guard_profile_moderation_columns();
```

- [ ] **Step 4: Add its grant line to the twin**

In `supabase/migrations/20261025100010_identity_users_lockdown_grants.sql`, insert immediately before the final line `COMMIT;`:

```sql
REVOKE ALL ON FUNCTION private.guard_profile_moderation_columns() FROM PUBLIC, anon, authenticated;
```

- [ ] **Step 5: Apply both twice, then run the contract**

```bash
cd /Users/user/attune
for i in 1 2; do
  psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/migrations/20261025100000_identity_users_lockdown.sql; echo "migration exit=$?"
  psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/migrations/20261025100010_identity_users_lockdown_grants.sql; echo "grants exit=$?"
done
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/identity_foundation_contracts.sql; echo "exit=$?"
```
Expected: four `… exit=0`, then `exit=0` with no `ERROR`.

- [ ] **Step 6: Mutation checks (spec §7.4 S-1: drop the count from the guard; let a client delete a profile with strikes)**

```bash
cd /Users/user/attune
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a <<'SQL'; echo "exit=$?"
BEGIN;
SELECT replace(pg_get_functiondef('private.guard_profile_moderation_columns()'::regprocedure),
  ' OR NEW.confirmed_violation_count IS DISTINCT FROM OLD.confirmed_violation_count', '') \gexec
DO $$ BEGIN
  IF position('NEW.confirmed_violation_count IS DISTINCT' IN pg_get_functiondef('private.guard_profile_moderation_columns()'::regprocedure)) > 0 THEN
    RAISE EXCEPTION 'MUTANT NOT APPLIED';
  END IF;
END $$;
\i supabase/tests/identity_foundation_contracts.sql
SQL
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a <<'SQL'; echo "exit=$?"
BEGIN;
SELECT replace(pg_get_functiondef('private.guard_profile_moderation_columns()'::regprocedure),
  'OLD.confirmed_violation_count > 0 OR ', '') \gexec
DO $$ BEGIN
  IF position('OLD.confirmed_violation_count > 0' IN pg_get_functiondef('private.guard_profile_moderation_columns()'::regprocedure)) > 0 THEN
    RAISE EXCEPTION 'MUTANT NOT APPLIED';
  END IF;
END $$;
\i supabase/tests/identity_foundation_contracts.sql
SQL
```
Expected: first `ERROR:  CONTRACT VIOLATED: a client reset its own strike count (got no error)`, `exit=3`; then `ERROR:  CONTRACT VIOLATED: a client deleted a profile with strikes (got no error)`, `exit=3`. Never `MUTANT NOT APPLIED`.

- [ ] **Step 7: Run tests**

```bash
cd /Users/user/attune
for t in identity_foundation_contracts forum_retirement_contracts account_deletion_contracts security_lockdown_contracts; do
  psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/$t.sql >/dev/null 2>&1; echo "$t exit=$?"
done
grep -E 'forum_retirement|account_deletion|security_lockdown' .superpowers/sdd/2026-10-25-spec1-w1/sql-baseline.txt
```
Expected: `identity_foundation_contracts exit=0`; each of the other three `exit=0` exactly where the baseline says PASS (the moderation function's strikes 1 and 2 in `forum_retirement_contracts` still pass with the guard in place).

---

### Task 3: The five dating functions stop writing `users.mode` (W1a; D3)

**Files:**
- Modify: `supabase/migrations/20261025100000_identity_users_lockdown.sql` (insert section 5 before the final `COMMIT;`)
- Modify: `supabase/migrations/20261025100010_identity_users_lockdown_grants.sql` (insert the dating grants before the final `COMMIT;`)
- Modify: `supabase/tests/identity_foundation_contracts.sql` (insert section D before the final `ROLLBACK;`)

**Interfaces:**
- Consumes: Task 1's helpers.
- Produces: `public.activate_dating_profile(text)`, `public.pause_dating_mode(text)`, `public.exit_dating_mode(text)` (all `RETURNS public.dating_enrollments`), `public.pause_dating_for_relationship_user(uuid) RETURNS void`, `public.delete_dating_profile(text) RETURNS void`: same signatures, same grants (the four RPCs to `authenticated`; `pause_dating_for_relationship_user` to nobody), same behaviour, no `users.mode` write, `search_path = ''`. W1b's `set_user_path_internal` calls `pause_dating_for_relationship_user(uuid)`.

- [ ] **Step 1: Write the failing contract section**

In `supabase/tests/identity_foundation_contracts.sql`, insert immediately before the final line `ROLLBACK;`:

```sql
-- =====================================================================
-- D. users.mode has no writer left (W1a; D3), and the five dating functions
--    still do everything else they did. Fixtures 08-09.
-- =====================================================================
DO $$
DECLARE
  v_bad text;
BEGIN
  SELECT string_agg(p.oid::regprocedure::text, ', ' ORDER BY p.oid::regprocedure::text) INTO v_bad
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname IN ('public', 'private')
     AND (p.prosrc ~* 'update\s+(public\.)?users\M[^;]*\mmode\M\s*='
          OR p.prosrc ~* 'insert\s+into\s+(public\.)?users\s*\([^)]*\mmode\M');
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: functions still write users.mode: %', v_bad;
  END IF;

  SELECT string_agg(p.oid::regprocedure::text, ', ' ORDER BY p.oid::regprocedure::text) INTO v_bad
    FROM pg_proc p
   WHERE p.oid IN ('public.activate_dating_profile(text)'::regprocedure,
                   'public.pause_dating_mode(text)'::regprocedure,
                   'public.exit_dating_mode(text)'::regprocedure,
                   'public.pause_dating_for_relationship_user(uuid)'::regprocedure,
                   'public.delete_dating_profile(text)'::regprocedure)
     AND p.proconfig IS DISTINCT FROM ARRAY['search_path=""'];
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: dating functions without search_path = '''': %', v_bad;
  END IF;
  IF has_function_privilege('authenticated', 'public.pause_dating_for_relationship_user(uuid)', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.pause_dating_mode(text)', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.exit_dating_mode(text)', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.activate_dating_profile(text)', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.delete_dating_profile(text)', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a dating function''s grants changed';
  END IF;
END $$;

DO $$
BEGIN
  PERFORM pg_temp.make_account('5f1a0000-0000-0000-0000-000000000008', '+15558100008', 'Dating W1 A');
  PERFORM pg_temp.make_account('5f1a0000-0000-0000-0000-000000000009', '+15558100009', 'Dating W1 B');
END $$;

DO $$
DECLARE
  v_a constant uuid := '5f1a0000-0000-0000-0000-000000000008';
  v_b constant uuid := '5f1a0000-0000-0000-0000-000000000009';
  v_state text;
  v_mode text;
BEGIN
  UPDATE public.users SET mode = 'dating' WHERE id IN (v_a, v_b);
  INSERT INTO public.dating_enrollments (user_id, state) VALUES (v_a, 'active'), (v_b, 'active');

  PERFORM public.pause_dating_for_relationship_user(v_a);
  SELECT e.state, u.mode INTO v_state, v_mode
    FROM public.dating_enrollments e JOIN public.users u ON u.id = e.user_id WHERE e.user_id = v_a;
  IF v_state <> 'paused' OR v_mode <> 'dating' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: pause_dating_for_relationship_user left state %, mode %', v_state, v_mode;
  END IF;

  PERFORM pg_temp.as_user(v_b);
  PERFORM public.pause_dating_mode('w1-contract-pause-0001');
  RESET ROLE;
  SELECT e.state, u.mode INTO v_state, v_mode
    FROM public.dating_enrollments e JOIN public.users u ON u.id = e.user_id WHERE e.user_id = v_b;
  IF v_state <> 'paused' OR v_mode <> 'dating' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: pause_dating_mode left state %, mode %', v_state, v_mode;
  END IF;

  PERFORM pg_temp.as_user(v_b);
  PERFORM public.exit_dating_mode('w1-contract-exit-0001');
  RESET ROLE;
  SELECT e.state, u.mode INTO v_state, v_mode
    FROM public.dating_enrollments e JOIN public.users u ON u.id = e.user_id WHERE e.user_id = v_b;
  IF v_state <> 'exited' OR v_mode <> 'dating' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: exit_dating_mode left state %, mode %', v_state, v_mode;
  END IF;
END $$;
```

- [ ] **Step 2: Run it to verify it fails**

```bash
cd /Users/user/attune
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/identity_foundation_contracts.sql; echo "exit=$?"
```
Expected: `ERROR:  CONTRACT VIOLATED: functions still write users.mode: activate_dating_profile(text), delete_dating_profile(text), exit_dating_mode(text), pause_dating_for_relationship_user(uuid), pause_dating_mode(text)`, `exit=3`.

- [ ] **Step 3: Confirm the live bodies are the ones copied below**

```bash
cd /Users/user/attune
for f in 'activate_dating_profile(text)' 'pause_dating_mode(text)' 'exit_dating_mode(text)' 'pause_dating_for_relationship_user(uuid)' 'delete_dating_profile(text)'; do
  psql -X -d attune_spec3a -Atc "select '$f', md5(prosrc) from pg_proc where oid = 'public.$f'::regprocedure"
done
```
Expected (bodies as they are before this task's re-apply; if a hash differs, someone changed a dating function since this plan was written: rebuild section 5 from `pg_get_functiondef` minus the `UPDATE public.users` statement instead of using the text below):
```
activate_dating_profile(text)|789e533cfb7eb99130af0d82004bd2c3
pause_dating_mode(text)|c6b3c1bdf0fc8695b8c2f5833a5b1821
exit_dating_mode(text)|8220354d87f0b7e8b5c6f55ce520eea5
pause_dating_for_relationship_user(uuid)|f615774adcca07424adf5124f30e1f91
delete_dating_profile(text)|8fa50be2e43bbc41ac16789f6ba42849
```

- [ ] **Step 4: Add the re-created functions to migration 1**

In `supabase/migrations/20261025100000_identity_users_lockdown.sql`, insert immediately before the final line `COMMIT;`:

```sql
-- 5. The five dating functions, from their live bodies minus the users.mode
-- write (D3). Otherwise verbatim, except SET search_path = '' and the
-- schema-qualified return type: every name in the bodies is already
-- qualified, and every callee sets its own search_path.
CREATE OR REPLACE FUNCTION public.activate_dating_profile(p_idempotency_key text)
 RETURNS public.dating_enrollments
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = ''
AS $function$
DECLARE
  v_user_id uuid := auth.uid();
  v_enrollment public.dating_enrollments%ROWTYPE;
BEGIN
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'not_authenticated' USING ERRCODE='42501'; END IF;
  PERFORM public.check_dating_rate_limit('profile_activation',10,interval '1 day');
  IF NOT public.dating_flag_enabled('dating_mode_enabled')
     OR NOT public.dating_healing_gates_hold(v_user_id)
     OR NOT public.dating_age_gate_holds(v_user_id)
     OR NOT public.dating_account_in_good_standing(v_user_id)
     OR public.dating_has_relationship(v_user_id) THEN
    RAISE EXCEPTION 'activation_gates_not_met' USING ERRCODE='22023';
  END IF;
  SELECT * INTO v_enrollment FROM public.dating_enrollments WHERE user_id=v_user_id FOR UPDATE;
  IF NOT FOUND OR v_enrollment.state NOT IN ('profile_draft','paused','active')
     OR v_enrollment.adults_only_confirmed_at IS NULL THEN
    RAISE EXCEPTION 'enrollment_incomplete' USING ERRCODE='22023';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.dating_profiles dp
    JOIN public.dating_preferences pref ON pref.user_id=dp.user_id
    WHERE dp.user_id=v_user_id AND dp.moderation_state='approved'
      AND jsonb_array_length(pref.gender_preferences)>0
      AND jsonb_array_length(pref.region_preferences)>0
      AND jsonb_array_length(pref.intention_preferences)>0
  ) THEN RAISE EXCEPTION 'profile_or_preferences_incomplete' USING ERRCODE='22023'; END IF;
  IF NOT public.claim_dating_idempotency('activate_dating_profile',p_idempotency_key) THEN RETURN v_enrollment; END IF;
  UPDATE public.dating_profiles SET profile_state='active',updated_at=now() WHERE user_id=v_user_id;
  UPDATE public.dating_enrollments SET state='active',activated_at=COALESCE(activated_at,now()),
    paused_at=NULL,exited_at=NULL,updated_at=now() WHERE user_id=v_user_id RETURNING * INTO v_enrollment;
  RETURN v_enrollment;
END;
$function$;

CREATE OR REPLACE FUNCTION public.pause_dating_mode(p_idempotency_key text)
 RETURNS public.dating_enrollments
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = ''
AS $function$
DECLARE
  v_user_id uuid := auth.uid();
  v_enrollment public.dating_enrollments%ROWTYPE;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;

  IF NOT public.claim_dating_idempotency('pause_dating_mode', p_idempotency_key) THEN
    SELECT * INTO v_enrollment
    FROM public.dating_enrollments
    WHERE user_id = v_user_id;
    RETURN v_enrollment;
  END IF;

  UPDATE public.dating_profiles
  SET profile_state = 'paused',
      updated_at = now()
  WHERE user_id = v_user_id;

  UPDATE public.dating_enrollments
  SET state = 'paused',
      paused_at = now(),
      updated_at = now()
  WHERE user_id = v_user_id
  RETURNING * INTO v_enrollment;

  RETURN v_enrollment;
END;
$function$;

CREATE OR REPLACE FUNCTION public.exit_dating_mode(p_idempotency_key text)
 RETURNS public.dating_enrollments
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = ''
AS $function$
DECLARE
  v_user_id uuid := auth.uid();
  v_enrollment public.dating_enrollments%ROWTYPE;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;

  IF NOT public.claim_dating_idempotency('exit_dating_mode', p_idempotency_key) THEN
    SELECT * INTO v_enrollment
    FROM public.dating_enrollments
    WHERE user_id = v_user_id;
    RETURN v_enrollment;
  END IF;

  UPDATE public.dating_profiles
  SET profile_state = 'exited',
      updated_at = now()
  WHERE user_id = v_user_id;

  UPDATE public.dating_enrollments
  SET state = 'exited',
      exited_at = now(),
      updated_at = now()
  WHERE user_id = v_user_id
  RETURNING * INTO v_enrollment;

  PERFORM public.invalidate_dating_for_user(v_user_id, 'exit');

  RETURN v_enrollment;
END;
$function$;

CREATE OR REPLACE FUNCTION public.pause_dating_for_relationship_user(p_user_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = ''
AS $function$
BEGIN
  UPDATE public.dating_profiles
  SET profile_state = 'paused',
      updated_at = now()
  WHERE user_id = p_user_id
    AND profile_state = 'active';

  UPDATE public.dating_enrollments
  SET state = CASE
        WHEN state = 'suspended' THEN state
        ELSE 'paused'
      END,
      paused_at = COALESCE(paused_at, now()),
      updated_at = now()
  WHERE user_id = p_user_id
    AND state IN ('active', 'profile_draft', 'eligible_to_opt_in');

  PERFORM public.invalidate_dating_for_user(p_user_id, 'relationship_guard');
END;
$function$;

CREATE OR REPLACE FUNCTION public.delete_dating_profile(p_idempotency_key text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = ''
AS $function$
DECLARE
  v_user_id uuid := auth.uid();
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;

  IF NOT public.claim_dating_idempotency('delete_dating_profile', p_idempotency_key) THEN
    RETURN;
  END IF;

  DELETE FROM public.dating_profile_photos
  WHERE user_id = v_user_id;

  DELETE FROM public.dating_preferences
  WHERE user_id = v_user_id;

  DELETE FROM public.dating_profiles
  WHERE user_id = v_user_id;

  UPDATE public.dating_enrollments
  SET state = CASE
        WHEN state = 'suspended' THEN state
        ELSE 'profile_draft'
      END,
      updated_at = now()
  WHERE user_id = v_user_id;

  PERFORM public.invalidate_dating_for_user(v_user_id, 'profile_deleted');
END;
$function$;
```

- [ ] **Step 5: Add their grants to the twin**

In `supabase/migrations/20261025100010_identity_users_lockdown_grants.sql`, insert immediately before the final line `COMMIT;`:

```sql
-- The five dating functions keep exactly the grants they had (CREATE OR
-- REPLACE keeps an ACL); re-asserted so the twin states them.
REVOKE ALL ON FUNCTION public.activate_dating_profile(text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.pause_dating_mode(text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.exit_dating_mode(text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.delete_dating_profile(text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.pause_dating_for_relationship_user(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.activate_dating_profile(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.pause_dating_mode(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.exit_dating_mode(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.delete_dating_profile(text) TO authenticated;
```

- [ ] **Step 6: Apply both twice, then run the contract**

```bash
cd /Users/user/attune
for i in 1 2; do
  psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/migrations/20261025100000_identity_users_lockdown.sql; echo "migration exit=$?"
  psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/migrations/20261025100010_identity_users_lockdown_grants.sql; echo "grants exit=$?"
done
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/identity_foundation_contracts.sql; echo "exit=$?"
```
Expected: four `… exit=0`, then `exit=0` with no `ERROR`.

- [ ] **Step 7: Mutation check (a `users.mode` writer comes back)**

```bash
cd /Users/user/attune
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a <<'SQL'; echo "exit=$?"
BEGIN;
CREATE FUNCTION public.w1_mutant_mode_writer() RETURNS void LANGUAGE sql AS $$ UPDATE public.users SET mode = 'dating' WHERE false $$;
\i supabase/tests/identity_foundation_contracts.sql
SQL
```
Expected: `ERROR:  CONTRACT VIOLATED: functions still write users.mode: w1_mutant_mode_writer()`, `exit=3`.

- [ ] **Step 8: Run tests (the dating contracts stay as they were)**

```bash
cd /Users/user/attune
for t in identity_foundation_contracts dating_mode_contracts dating_exclusion_wiring_test dating_alignment_contracts relationship_lifecycle_hardening_contracts sync_fixes_contracts; do
  psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/$t.sql >/dev/null 2>&1; echo "$t exit=$?"
done
grep -E 'dating_|relationship_lifecycle_hardening|sync_fixes' .superpowers/sdd/2026-10-25-spec1-w1/sql-baseline.txt
```
Expected: `identity_foundation_contracts exit=0`; every other file `exit=0` exactly where the baseline says PASS.

---

### Task 4: The client and both invite functions stop writing `phone`/`mode`; W1a gate

**Files:**
- Create: `test/features/onboarding/onboarding_submission_service_test.dart`
- Modify: `lib/features/onboarding/data/onboarding_submission_service.dart:36-49, 58, 80`
- Modify: `supabase/functions/accept-invite/index.ts:145-168`
- Modify: `supabase/functions/create-relationship-invite/index.ts:141-164`
- Modify: `supabase/functions/accept-invite/index.test.ts` (append after line 21)

**Interfaces:**
- Consumes: Task 1's grants (`authenticated` may UPDATE `users.display_name`, may not INSERT or write `phone`/`mode`).
- Produces: `OnboardingSubmissionService.clampDisplayName(String) → String` (static, `@visibleForTesting`; at most 40 code points). `submit(...)` keeps its signature; it now sends `PATCH /rest/v1/users?id=eq.<uid>` with `{"display_name": <clamped>}` and the same clamped name to `profiles`. Both `ensureUserRow` functions upsert `{id, phone, display_name: ""}` with `ignoreDuplicates: true`.

- [ ] **Step 1: Write the failing Dart test**

Create `test/features/onboarding/onboarding_submission_service_test.dart` with exactly:

```dart
// Spec 1 W1a (§5.2, regression note R5): the legacy onboarding submission
// no longer sends users.phone or users.mode (the client lost both grants)
// and never inserts a users row; W1b also drops onboarding_profiles.mode.
// Pinned on the requests it actually sends.
import 'dart:convert';

import 'package:attune/features/onboarding/data/onboarding_submission_service.dart';
import 'package:attune/features/onboarding/domain/onboarding_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _me = '5f1a0000-0000-0000-0000-0000000000aa';

String _fakeJwt() {
  String part(Map<String, Object> json) =>
      base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '');
  final exp =
      DateTime.now().add(const Duration(days: 1)).millisecondsSinceEpoch ~/
      1000;
  return '${part({'alg': 'HS256', 'typ': 'JWT'})}.'
      '${part({'sub': _me, 'exp': exp, 'role': 'authenticated'})}.sig';
}

Future<(SupabaseClient, List<http.Request>)> _client() async {
  final requests = <http.Request>[];
  final client = SupabaseClient(
    'http://localhost:54321',
    'test-anon-key',
    httpClient: MockClient((request) async {
      if (request.url.path.startsWith('/rest/v1/')) {
        requests.add(request);
        return http.Response('', 204, request: request);
      }
      return http.Response('not found', 404, request: request);
    }),
    authOptions: const AuthClientOptions(autoRefreshToken: false),
  );
  final exp = DateTime.now().add(const Duration(days: 1));
  await client.auth.recoverSession(
    jsonEncode({
      'access_token': _fakeJwt(),
      'token_type': 'bearer',
      'expires_in': 86400,
      'expires_at': exp.millisecondsSinceEpoch ~/ 1000,
      'refresh_token': 'refresh',
      'user': {
        'id': _me,
        'aud': 'authenticated',
        'phone': '233241234567',
        'app_metadata': <String, Object>{},
        'user_metadata': <String, Object>{},
        'created_at': '2026-07-01T00:00:00Z',
      },
    }),
  );
  return (client, requests);
}

http.Request _to(List<http.Request> requests, String table) =>
    requests.singleWhere((r) => r.url.path == '/rest/v1/$table');

Map<String, dynamic> _body(http.Request request) =>
    Map<String, dynamic>.from(jsonDecode(request.body) as Map);

void main() {
  test(
    'users gets an update of the name only: no insert, no phone, no mode',
    () async {
      final (client, requests) = await _client();
      addTearDown(client.dispose);

      await OnboardingSubmissionService(client: client).submit(
        mode: OnboardingMode.couples,
        displayName: 'Ama',
        attachmentAnswers: const [1, 2],
        anchors: const ['time'],
      );

      final users = _to(requests, 'users');
      expect(users.method, 'PATCH');
      expect(users.url.queryParameters['id'], 'eq.$_me');
      expect(_body(users), {'display_name': 'Ama'});
    },
  );

  // Review Focus 5: a legacy name longer than users' 40-character CHECK.
  test(
    'a name over 40 characters is clamped to 40 code points, emoji whole',
    () async {
      final (client, requests) = await _client();
      addTearDown(client.dispose);
      final long = '${'A' * 39}😀😀😀';

      await OnboardingSubmissionService(client: client).submit(
        mode: OnboardingMode.personal,
        displayName: long,
        attachmentAnswers: const [],
        anchors: const [],
      );

      final sent = _body(_to(requests, 'users'))['display_name'] as String;
      expect(sent.runes.length, 40);
      expect(sent, '${'A' * 39}😀');
      expect(_body(_to(requests, 'profiles'))['display_name'], sent);
      expect(OnboardingSubmissionService.clampDisplayName('Ama'), 'Ama');
    },
  );
}
```

- [ ] **Step 2: Run it to verify it fails**

```bash
cd /Users/user/attune
flutter test --no-pub test/features/onboarding/onboarding_submission_service_test.dart 2>&1 | tr '\r' '\n' | grep -E "Error:|error:|All tests passed|Some tests failed" | head -3
```
Expected: `Error: Member not found: 'OnboardingSubmissionService.clampDisplayName'.` and `Some tests failed.`

- [ ] **Step 3: Change the users write**

In `lib/features/onboarding/data/onboarding_submission_service.dart`, replace exactly:

```dart
    final modeName = mode.remoteModeName;
    final relationshipStatus = _relationshipStatusForMode(mode);
    final now = DateTime.now().toUtc().toIso8601String();

    try {
      await client
          .from('users')
          .upsert({
            'id': user.id,
            'phone': phone,
            'display_name': displayName,
            'mode': modeName,
          }, onConflict: 'id')
          .timeout(timeout);
```

with:

```dart
    final modeName = mode.remoteModeName;
    final relationshipStatus = _relationshipStatusForMode(mode);
    final now = DateTime.now().toUtc().toIso8601String();
    final name = clampDisplayName(displayName);

    try {
      // Spec 1 W1a: the client may update only its name (users.phone is
      // copied from auth.users, users.mode is retired, and the row itself is
      // created by record_eula_acceptance, which the EULA gate runs first).
      await client
          .from('users')
          .update({'display_name': name})
          .eq('id', user.id)
          .timeout(timeout);
```

Then replace exactly:

```dart
            'id': user.id,
            'display_name': displayName,
            'relationship_status': relationshipStatus,
```

with:

```dart
            'id': user.id,
            'display_name': name,
            'relationship_status': relationshipStatus,
```

Then replace exactly:

```dart
  String _relationshipStatusForMode(OnboardingMode mode) {
```

with:

```dart
  /// users.display_name holds at most 40 characters (the CHECK
  /// users_display_name_length, counted in code points like Postgres'
  /// char_length). The legacy name step has no limit, so the name is clamped
  /// here rather than failing the write and replaying it forever. Whole code
  /// points only: an emoji is never split.
  @visibleForTesting
  static String clampDisplayName(String value) {
    final runes = value.runes;
    if (runes.length <= 40) return value;
    return String.fromCharCodes(runes.take(40));
  }

  String _relationshipStatusForMode(OnboardingMode mode) {
```

- [ ] **Step 4: Run the Dart test to verify it passes**

```bash
cd /Users/user/attune
flutter test --no-pub test/features/onboarding/onboarding_submission_service_test.dart test/features/onboarding/onboarding_pending_sync_test.dart 2>&1 | tr '\r' '\n' | grep -E "All tests passed|Some tests failed" | tail -1
dart format test/features/onboarding/onboarding_submission_service_test.dart
```
Expected: `… All tests passed!`, then `Formatted 1 file (0 changed)`.

- [ ] **Step 5: Write the failing Deno test**

Append to `supabase/functions/accept-invite/index.test.ts` (after line 21):

```ts
// Spec 1 W1a (D3, §4.5): the service-role safety net that creates a missing
// users row never writes the retired users.mode and never uses a phone
// number as a display name.
Deno.test("ensureUserRow writes no users.mode and no phone as a name", () => {
  for (const [name, source] of [["accept-invite", accept], ["create-relationship-invite", create]]) {
    const start = source.indexOf("async function ensureUserRow(");
    if (start < 0) throw new Error(`${name}: ensureUserRow is missing`);
    const body = source.slice(start, source.indexOf("\n}\n", start));
    if (/\bmode\s*:/.test(body)) throw new Error(`${name}: ensureUserRow still writes users.mode`);
    if (!/display_name:\s*""/.test(body)) throw new Error(`${name}: ensureUserRow must write an empty display_name`);
    if (/user\.phone\s*\?\?|displayName/.test(body)) throw new Error(`${name}: ensureUserRow still derives a name from the phone`);
    if (!body.includes("ignoreDuplicates: true")) throw new Error(`${name}: ensureUserRow must only insert a missing row`);
  }
});
```

```bash
cd /Users/user/attune/supabase/functions
deno test --allow-read accept-invite/index.test.ts 2>&1 | grep -E "ensureUserRow|passed|failed" | tail -3
```
Expected: `error: Error: accept-invite: ensureUserRow still writes users.mode` and `2 passed | 1 failed`.

- [ ] **Step 6: Change both `ensureUserRow` functions**

In `supabase/functions/accept-invite/index.ts`, replace exactly:

```ts
async function ensureUserRow(
  supabase: ReturnType<typeof serviceRoleClient>,
  user: { id: string; email: string | null; phone: string | null },
) {
  const displayName = user.phone ?? user.email?.split("@")[0] ??
    `user-${user.id.slice(0, 8)}`;

  // public.users has no `email` column (20260606133000_phone_only_auth.sql
  // dropped it — launch auth is phone OTP only). ignoreDuplicates so this
  // only ever INSERTs a missing row; it must never overwrite an existing
  // user's `mode` on every invite acceptance.
  const { error } = await supabase
    .from("users")
    .upsert(
      {
        id: user.id,
        phone: user.phone,
        display_name: displayName,
        mode: "couples",
      },
      { onConflict: "id", ignoreDuplicates: true },
    );
  if (error) throw error;
}
```

with:

```ts
async function ensureUserRow(
  supabase: ReturnType<typeof serviceRoleClient>,
  user: { id: string; email: string | null; phone: string | null },
) {
  // Spec 1 W1a: users.mode is retired, so it is never written, and the name
  // is left empty for onboarding to fill: a phone number is never a display
  // name. ignoreDuplicates so this only ever INSERTs a missing row (the
  // phone is the verified one from the JWT).
  const { error } = await supabase
    .from("users")
    .upsert(
      {
        id: user.id,
        phone: user.phone,
        display_name: "",
      },
      { onConflict: "id", ignoreDuplicates: true },
    );
  if (error) throw error;
}
```

In `supabase/functions/create-relationship-invite/index.ts`, replace exactly:

```ts
async function ensureUserRow(
  supabase: ReturnType<typeof serviceRoleClient>,
  user: { id: string; email: string | null; phone: string | null },
) {
  const displayName = user.phone ?? user.email?.split("@")[0] ??
    `user-${user.id.slice(0, 8)}`;

  // public.users has no `email` column (20260606133000_phone_only_auth.sql
  // dropped it — launch auth is phone OTP only). ignoreDuplicates so this
  // only ever INSERTs a missing row; it must never overwrite an existing
  // user's `mode` on every invite creation.
  const { error } = await supabase
    .from("users")
    .upsert(
      {
        id: user.id,
        phone: user.phone,
        display_name: displayName,
        mode: "couples",
      },
      { onConflict: "id", ignoreDuplicates: true },
    );
  if (error) throw error;
}
```

with the same new function:

```ts
async function ensureUserRow(
  supabase: ReturnType<typeof serviceRoleClient>,
  user: { id: string; email: string | null; phone: string | null },
) {
  // Spec 1 W1a: users.mode is retired, so it is never written, and the name
  // is left empty for onboarding to fill: a phone number is never a display
  // name. ignoreDuplicates so this only ever INSERTs a missing row (the
  // phone is the verified one from the JWT).
  const { error } = await supabase
    .from("users")
    .upsert(
      {
        id: user.id,
        phone: user.phone,
        display_name: "",
      },
      { onConflict: "id", ignoreDuplicates: true },
    );
  if (error) throw error;
}
```

- [ ] **Step 7: Run the Deno test to verify it passes**

```bash
cd /Users/user/attune/supabase/functions
deno test --allow-read accept-invite/index.test.ts 2>&1 | grep -E "passed|failed" | tail -1
deno check accept-invite/index.ts create-relationship-invite/index.ts 2>&1 | grep -E "error|Check" | head -3
```
Expected: `ok | 3 passed | 0 failed`, then two `Check …` lines and no `error`.

- [ ] **Step 8: W1a regression gate — SQL**

```bash
cd /Users/user/attune
for f in supabase/tests/*.sql; do
  if psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f "$f" >/dev/null 2>&1; then echo "PASS $(basename "$f")"; else echo "FAIL $(basename "$f")"; fi
done > .superpowers/sdd/2026-10-25-spec1-w1/sql-after-w1a.txt
comm -13 <(grep '^FAIL' .superpowers/sdd/2026-10-25-spec1-w1/sql-baseline.txt | sort) <(grep '^FAIL' .superpowers/sdd/2026-10-25-spec1-w1/sql-after-w1a.txt | sort)
grep identity_foundation .superpowers/sdd/2026-10-25-spec1-w1/sql-after-w1a.txt
```
Expected: the `comm` prints nothing (no new FAIL), then `PASS identity_foundation_contracts.sql`.

- [ ] **Step 9: W1a regression gate — Flutter**

```bash
cd /Users/user/attune
flutter test --no-pub 2>&1 | tr '\r' '\n' | grep -E 'All tests passed!|Some tests failed' | tail -1
flutter analyze --no-pub lib test > .superpowers/sdd/2026-10-25-spec1-w1/analyze-w1a.txt 2>&1
comm -13 .superpowers/sdd/2026-10-25-spec1-w1/analyze-errors-baseline.txt <(grep -E '^\s*error ' .superpowers/sdd/2026-10-25-spec1-w1/analyze-w1a.txt | sed -E 's/:[0-9]+:[0-9]+//' | sort -u)
```
Expected: `… All tests passed!`, then the `comm` prints nothing.

- [ ] **Step 10: Run tests**

W1a ships as one release (grants, client and both invite functions together; Owner checklist item 1). Nothing else to run: Steps 8–9 are this task's tests.

---

### Task 5: Metric storage with an exact-key client surface (W1b; review S-2)

**Files:**
- Create: `supabase/migrations/20261025100100_metric_counters.sql`
- Create: `supabase/migrations/20261025100110_metric_counters_grants.sql`
- Modify: `supabase/tests/identity_foundation_contracts.sql` (insert section E before the final `ROLLBACK;`)
- Modify: `scripts/local_pg_grants.sql` (append)

**Interfaces:**
- Consumes: Task 1's helpers.
- Produces: tables `public.metric_counters (day date, key text, count bigint, PK (day, key))`, `public.metric_key_prefixes (prefix text PK, owner_spec text)`, `public.metric_client_keys (key text PK, anon_ok boolean, owner_spec text)` (key pattern `^[a-z0-9_:>.-]{1,80}$`; no client grant); view `public.metric_counters_report (day, key, count)` (NULL under 50; service role only); `private.metric_increment(p_key text) RETURNS void` (pattern + 5,000-keys-a-day cap, never raises); `private.bump_metric_internal(p_key text) RETURNS void` (definer callers; key must start with a server prefix); `public.bump_metric_server(p_key text) RETURNS void` (service_role); `public.bump_metric(p_key text) RETURNS void` (anon, authenticated; exact `metric_client_keys` rows only, anon only `anon_ok`); cron job `metric-counters-retention` (`12 4 * * *`). Seeds: 10 server prefixes and 26 client keys (9 `anon_ok`), all `owner_spec = 'spec1'`; Task 12's `ClientMetricKey` must equal the client-key seed. Spec 2 inserts the prefix `('dating.', 'spec2')`. Section E also defines `pg_temp.metric(text) RETURNS bigint` (today's count), used by sections F and G.

- [ ] **Step 1: Write the failing contract section**

In `supabase/tests/identity_foundation_contracts.sql`, insert immediately before the final line `ROLLBACK;`:

```sql
-- =====================================================================
-- E. Metrics (W1b; review S-2): exact client keys, anon only for the
--    pre-auth funnel, server prefixes only for definer callers and the
--    service role, blanked report cells, a daily row cap. Fixture 10.
-- =====================================================================
DO $$
BEGIN
  IF to_regclass('public.metric_counters') IS NULL
     OR to_regprocedure('public.bump_metric(text)') IS NULL
     OR to_regprocedure('private.bump_metric_internal(text)') IS NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: W1b metric objects are missing (metric_counters, bump_metric, bump_metric_internal)';
  END IF;
END $$;

DO $$
BEGIN
  PERFORM pg_temp.make_account('5f1a0000-0000-0000-0000-000000000010', '+15558100010', 'Metric W1');
END $$;

CREATE FUNCTION pg_temp.metric(p_key text) RETURNS bigint LANGUAGE sql AS $$
  SELECT coalesce((SELECT count FROM public.metric_counters
                    WHERE day = (now() AT TIME ZONE 'utc')::date AND key = p_key), 0);
$$;

DO $$
DECLARE
  v_me constant uuid := '5f1a0000-0000-0000-0000-000000000010';
  v_day constant date := (now() AT TIME ZONE 'utc')::date;
  v_key text;
  v_before bigint;
  v_rows int;
BEGIN
  -- Privileges.
  IF has_function_privilege('anon', 'public.bump_metric_server(text)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.bump_metric_server(text)', 'EXECUTE')
     OR has_function_privilege('anon', 'private.bump_metric_internal(text)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'private.bump_metric_internal(text)', 'EXECUTE')
     OR has_function_privilege('anon', 'private.metric_increment(text)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'private.metric_increment(text)', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a client can run a server metric writer';
  END IF;
  IF NOT has_function_privilege('anon', 'public.bump_metric(text)', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.bump_metric(text)', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'public.bump_metric_server(text)', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a metric entry point lost its grant';
  END IF;
  FOREACH v_key IN ARRAY ARRAY['public.metric_counters', 'public.metric_key_prefixes',
                               'public.metric_client_keys', 'public.metric_counters_report'] LOOP
    IF has_table_privilege('anon', v_key, 'SELECT') OR has_table_privilege('authenticated', v_key, 'SELECT')
       OR has_table_privilege('authenticated', v_key, 'INSERT') OR has_table_privilege('authenticated', v_key, 'UPDATE') THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: a client can read or write %', v_key;
    END IF;
  END LOOP;
  IF NOT has_table_privilege('service_role', 'public.metric_counters_report', 'SELECT') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the service role cannot read the metric report';
  END IF;

  -- Seeds: 26 exact client keys (9 pre-auth), 10 server prefixes.
  IF (SELECT count(*) FROM public.metric_client_keys WHERE owner_spec = 'spec1') <> 26
     OR (SELECT count(*) FROM public.metric_client_keys WHERE owner_spec = 'spec1' AND anon_ok) <> 9
     OR (SELECT count(*) FROM public.metric_key_prefixes WHERE owner_spec = 'spec1') <> 10 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the Spec 1 metric seeds are wrong';
  END IF;

  -- anon: a signed-in-only key and unlisted keys write nothing; a pre-auth key counts.
  v_before := pg_temp.metric('signup_started');
  PERFORM pg_temp.as_anon();
  PERFORM public.bump_metric('invite_shared:whatsapp');
  PERFORM public.bump_metric('signup_completed');
  PERFORM public.bump_metric('invite_accepted');
  PERFORM public.bump_metric('x_y');
  PERFORM public.bump_metric('signup_started');
  RESET ROLE;
  IF pg_temp.metric('invite_shared:whatsapp') + pg_temp.metric('signup_completed')
     + pg_temp.metric('invite_accepted') + pg_temp.metric('x_y') <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: anon bumped a signed-in-only or unlisted key';
  END IF;
  IF pg_temp.metric('signup_started') <> v_before + 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a listed pre-auth key did not count once';
  END IF;

  -- authenticated: unlisted keys, including a server prefix, write nothing.
  PERFORM pg_temp.as_user(v_me);
  PERFORM public.bump_metric('signup_completed');
  PERFORM public.bump_metric('invite_accepted');
  PERFORM public.bump_metric('x_y');
  PERFORM public.bump_metric('path_chosen:dating');
  PERFORM public.bump_metric('invite_shared:whatsapp');
  RESET ROLE;
  IF pg_temp.metric('signup_completed') + pg_temp.metric('invite_accepted')
     + pg_temp.metric('x_y') + pg_temp.metric('path_chosen:dating') <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: authenticated bumped an unlisted key';
  END IF;
  IF pg_temp.metric('invite_shared:whatsapp') <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a listed signed-in key did not count once';
  END IF;

  -- Server side: a prefix counts, anything else is ignored, nothing raises.
  PERFORM private.bump_metric_internal('invite_accepted_24h');
  PERFORM private.bump_metric_internal('x_y');
  PERFORM private.bump_metric_internal('Not A Key');
  PERFORM private.bump_metric_internal(NULL);
  SET LOCAL ROLE service_role;
  PERFORM public.bump_metric_server('otp_sent:gh:sms:ghana_direct');
  RESET ROLE;
  IF pg_temp.metric('invite_accepted_24h') <> 1 OR pg_temp.metric('x_y') <> 0
     OR pg_temp.metric('otp_sent:gh:sms:ghana_direct') <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the server prefix rule is wrong';
  END IF;

  -- The report blanks every cell under 50.
  INSERT INTO public.metric_counters (day, key, count) VALUES
    (v_day - 1, 'path_chosen:just_me', 49), (v_day - 1, 'path_chosen:dating', 50);
  IF (SELECT count FROM public.metric_counters_report WHERE day = v_day - 1 AND key = 'path_chosen:just_me') IS NOT NULL
     OR (SELECT count FROM public.metric_counters_report WHERE day = v_day - 1 AND key = 'path_chosen:dating') IS DISTINCT FROM 50 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the report shows a cell under 50 or hides one at 50';
  END IF;

  -- The daily row cap: past 5,000 keys a new key isn't created; existing keys keep counting.
  SELECT count(*) INTO v_rows FROM public.metric_counters WHERE day = v_day AND key <> 'metric_cap_reached';
  INSERT INTO public.metric_counters (day, key, count)
  SELECT v_day, 'path_chosen:cap' || g, 1 FROM generate_series(1, 5000 - v_rows) AS g;
  v_before := pg_temp.metric('metric_cap_reached');
  PERFORM private.bump_metric_internal('signup_completed');
  IF EXISTS (SELECT 1 FROM public.metric_counters WHERE day = v_day AND key = 'signup_completed') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a new key was created past the daily cap';
  END IF;
  IF pg_temp.metric('metric_cap_reached') <> v_before + 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: metric_cap_reached did not move past the cap';
  END IF;
  PERFORM private.bump_metric_internal('invite_accepted_24h');
  IF pg_temp.metric('invite_accepted_24h') <> 2 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an existing key stopped counting at the cap';
  END IF;
  DELETE FROM public.metric_counters WHERE day = v_day AND key LIKE 'path_chosen:cap%';

  -- Retention runs as its own job.
  IF NOT EXISTS (SELECT 1 FROM cron.job
                  WHERE jobname = 'metric-counters-retention' AND schedule = '12 4 * * *'
                    AND command LIKE '%DELETE FROM public.metric_counters WHERE day < current_date - 400%') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: metric-counters-retention is not scheduled';
  END IF;
END $$;
```

- [ ] **Step 2: Run it to verify it fails**

```bash
cd /Users/user/attune
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/identity_foundation_contracts.sql; echo "exit=$?"
```
Expected: `ERROR:  CONTRACT VIOLATED: W1b metric objects are missing (metric_counters, bump_metric, bump_metric_internal)`, `exit=3`.

- [ ] **Step 3: Write the migration**

Create `supabase/migrations/20261025100100_metric_counters.sql` with exactly:

```sql
-- Spec 1 W1b, migration 2 of 6 (spec §4.7 #2): metric storage (§4.2, §4.3
-- W1b; cross-spec review S-2). Aggregates only: a day, a key, a count; never
-- a user id, an answer, a gender, a preference, a faith or an age signal.
--   * server prefixes (metric_key_prefixes) are bumped only by definer
--     functions (private.bump_metric_internal) and service-role edge
--     functions (bump_metric_server);
--   * a client (bump_metric) may bump only an exact listed key
--     (metric_client_keys), and anon only an anon_ok pre-auth key;
--   * at most 5,000 distinct keys per UTC day: past the cap a new key is not
--     created and metric_cap_reached moves instead;
--   * a metric never fails its caller.
-- First in W1b because the next two migrations bump metrics.
-- Grants in 20261025100110_metric_counters_grants.sql.
BEGIN;

CREATE TABLE IF NOT EXISTS public.metric_counters (
  day date NOT NULL,
  key text NOT NULL CONSTRAINT metric_counters_key_check CHECK (key ~ '^[a-z0-9_:>.-]{1,80}$'),
  count bigint NOT NULL DEFAULT 0,
  PRIMARY KEY (day, key)
);
CREATE TABLE IF NOT EXISTS public.metric_key_prefixes (
  prefix text PRIMARY KEY CONSTRAINT metric_key_prefixes_prefix_check CHECK (prefix ~ '^[a-z0-9_:>.-]{1,80}$'),
  owner_spec text NOT NULL
);
CREATE TABLE IF NOT EXISTS public.metric_client_keys (
  key text PRIMARY KEY CONSTRAINT metric_client_keys_key_check CHECK (key ~ '^[a-z0-9_:>.-]{1,80}$'),
  anon_ok boolean NOT NULL DEFAULT false,
  owner_spec text NOT NULL
);
ALTER TABLE public.metric_counters ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.metric_key_prefixes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.metric_client_keys ENABLE ROW LEVEL SECURITY;

-- Server prefixes (spec §4.3 W1b seeds). Spec 2 adds 'dating.'.
INSERT INTO public.metric_key_prefixes (prefix, owner_spec) VALUES
  ('signup_completed', 'spec1'),
  ('path_chosen:', 'spec1'),
  ('path_switch_7d:', 'spec1'),
  ('path_switch_30d:', 'spec1'),
  ('invite_accepted', 'spec1'),
  ('otp_sent:', 'spec1'),
  ('otp_refused:', 'spec1'),
  ('dormancy_', 'spec1'),
  ('support_card_shown:journal', 'spec1'),
  ('auth_hook_fail_open', 'spec1')
ON CONFLICT (prefix) DO NOTHING;

-- Exact client keys; anon_ok only for the pre-auth funnel. Kept in step with
-- lib/core/metrics/metric_counter.dart (test/core/metrics/metric_counter_test.dart).
INSERT INTO public.metric_client_keys (key, anon_ok, owner_spec) VALUES
  ('welcome_preview:relationship', true, 'spec1'),
  ('welcome_preview:dating', true, 'spec1'),
  ('welcome_preview:just_me', true, 'spec1'),
  ('guest_age_ok', true, 'spec1'),
  ('signup_started', true, 'spec1'),
  ('signup_step:name', true, 'spec1'),
  ('signup_step:dob', true, 'spec1'),
  ('signup_step:phone', true, 'spec1'),
  ('signup_age_stop', true, 'spec1'),
  ('push_ask_shown:r2', false, 'spec1'),
  ('push_ask_shown:r4', false, 'spec1'),
  ('push_ask_shown:j3', false, 'spec1'),
  ('push_ask_granted:r2', false, 'spec1'),
  ('push_ask_granted:r4', false, 'spec1'),
  ('push_ask_granted:j3', false, 'spec1'),
  ('invite_shared:whatsapp', false, 'spec1'),
  ('invite_shared:share', false, 'spec1'),
  ('invite_shared:qr', false, 'spec1'),
  ('invite_shared:copy', false, 'spec1'),
  ('invite_new_day7', false, 'spec1'),
  ('invite_day30_shown', false, 'spec1'),
  ('opinion_blocked:contact_info', false, 'spec1'),
  ('opinion_blocked:slur', false, 'spec1'),
  ('opinion_blocked:explicit', false, 'spec1'),
  ('support_link_opened:opinions', false, 'spec1'),
  ('support_link_opened:journal', false, 'spec1')
ON CONFLICT (key) DO NOTHING;

-- The one capped writer. Callers decide whether a key may be bumped; this
-- only checks the pattern and the daily row cap. Never raises.
CREATE OR REPLACE FUNCTION private.metric_increment(p_key text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_day constant date := (now() AT TIME ZONE 'utc')::date;
BEGIN
  IF p_key IS NULL OR p_key !~ '^[a-z0-9_:>.-]{1,80}$' THEN
    RETURN;
  END IF;
  UPDATE public.metric_counters AS c SET count = c.count + 1
   WHERE c.day = v_day AND c.key = p_key;
  IF FOUND THEN
    RETURN;
  END IF;
  IF p_key <> 'metric_cap_reached'
     AND (SELECT count(*) FROM public.metric_counters AS c
           WHERE c.day = v_day AND c.key <> 'metric_cap_reached') >= 5000 THEN
    INSERT INTO public.metric_counters AS c (day, key, count)
    VALUES (v_day, 'metric_cap_reached', 1)
    ON CONFLICT (day, key) DO UPDATE SET count = c.count + 1;
    RETURN;
  END IF;
  INSERT INTO public.metric_counters AS c (day, key, count)
  VALUES (v_day, p_key, 1)
  ON CONFLICT (day, key) DO UPDATE SET count = c.count + 1;
EXCEPTION WHEN OTHERS THEN
  -- A metric never fails its caller (spec §4.3 W1b).
  RETURN;
END;
$$;

-- Definer callers: the key must start with a server prefix.
CREATE OR REPLACE FUNCTION private.bump_metric_internal(p_key text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF p_key IS NULL OR p_key !~ '^[a-z0-9_:>.-]{1,80}$' THEN
    RETURN;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.metric_key_prefixes AS k
                  WHERE left(p_key, char_length(k.prefix)) = k.prefix) THEN
    RETURN;
  END IF;
  PERFORM private.metric_increment(p_key);
EXCEPTION WHEN OTHERS THEN
  RETURN;
END;
$$;

-- Edge functions (service role): the same rule.
CREATE OR REPLACE FUNCTION public.bump_metric_server(p_key text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  PERFORM private.bump_metric_internal(p_key);
END;
$$;

-- Clients: exact listed keys only; anon only anon_ok ones. Anything else is
-- ignored silently. Client counts are advisory: nothing decides on them.
CREATE OR REPLACE FUNCTION public.bump_metric(p_key text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_anon_ok boolean;
BEGIN
  SELECT k.anon_ok INTO v_anon_ok FROM public.metric_client_keys AS k WHERE k.key = p_key;
  IF NOT FOUND THEN
    RETURN;
  END IF;
  IF auth.uid() IS NULL AND NOT v_anon_ok THEN
    RETURN;
  END IF;
  PERFORM private.metric_increment(p_key);
EXCEPTION WHEN OTHERS THEN
  RETURN;
END;
$$;

-- Service role only; a cell under 50 is blank (spec §4.1 rule 4).
CREATE OR REPLACE VIEW public.metric_counters_report AS
  SELECT c.day, c.key, CASE WHEN c.count >= 50 THEN c.count END AS count
    FROM public.metric_counters AS c;

-- Retention: 400 days, its own job (spec §4.6).
DO $$
BEGIN
  PERFORM cron.unschedule('metric-counters-retention');
EXCEPTION WHEN OTHERS THEN
  NULL;
END $$;
SELECT cron.schedule(
  'metric-counters-retention',
  '12 4 * * *',
  $cron$DELETE FROM public.metric_counters WHERE day < current_date - 400$cron$
);

COMMIT;
```

- [ ] **Step 4: Write the grants twin**

Create `supabase/migrations/20261025100110_metric_counters_grants.sql` with exactly:

```sql
-- Spec 1 W1b: grants for 20261025100100_metric_counters.sql. No client reads
-- or writes a metric table; service_role keeps DML (service_role_grants_test).
BEGIN;
REVOKE ALL ON public.metric_counters, public.metric_key_prefixes, public.metric_client_keys
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON public.metric_counters_report FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE
  ON public.metric_counters, public.metric_key_prefixes, public.metric_client_keys TO service_role;
GRANT SELECT ON public.metric_counters_report TO service_role;

REVOKE ALL ON FUNCTION private.metric_increment(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.bump_metric_internal(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.bump_metric_server(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.bump_metric(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.bump_metric_server(text) TO service_role;
GRANT EXECUTE ON FUNCTION public.bump_metric(text) TO anon, authenticated;
COMMIT;
```

- [ ] **Step 5: Apply both twice, then run the contract**

```bash
cd /Users/user/attune
for i in 1 2; do
  psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/migrations/20261025100100_metric_counters.sql; echo "migration exit=$?"
  psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/migrations/20261025100110_metric_counters_grants.sql; echo "grants exit=$?"
done
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/identity_foundation_contracts.sql; echo "exit=$?"
```
Expected: each migration run prints the `cron.schedule` job id (a one-row `schedule` table); four `… exit=0`; then `exit=0` with no `ERROR`.

- [ ] **Step 6: Mutation checks (spec §7.4 S-2)**

```bash
cd /Users/user/attune
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a <<'SQL'; echo "exit=$?"
BEGIN;
GRANT EXECUTE ON FUNCTION public.bump_metric_server(text) TO anon;
\i supabase/tests/identity_foundation_contracts.sql
SQL
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a <<'SQL'; echo "exit=$?"
BEGIN;
SELECT replace(pg_get_functiondef('public.bump_metric(text)'::regprocedure),
  'PERFORM private.metric_increment(p_key);', 'PERFORM private.bump_metric_internal(p_key);') \gexec
SELECT replace(pg_get_functiondef('public.bump_metric(text)'::regprocedure),
  E'  IF NOT FOUND THEN\n    RETURN;\n  END IF;\n  IF auth.uid()', E'  IF auth.uid()') \gexec
DO $$ BEGIN
  IF position('IF NOT FOUND' IN pg_get_functiondef('public.bump_metric(text)'::regprocedure)) > 0 THEN
    RAISE EXCEPTION 'MUTANT NOT APPLIED';
  END IF;
END $$;
\i supabase/tests/identity_foundation_contracts.sql
SQL
```
Expected: first `ERROR:  CONTRACT VIOLATED: a client can run a server metric writer`, `exit=3`; then (bump_metric accepts any key under a server prefix) `ERROR:  CONTRACT VIOLATED: anon bumped a signed-in-only or unlisted key`, `exit=3`.

- [ ] **Step 7: Add the twin to the local harness (edit only)**

Append to the end of `scripts/local_pg_grants.sql`:

```sql

-- Spec 1 W1b: metric tables and the report are closed to clients.
\i supabase/migrations/20261025100110_metric_counters_grants.sql
```

- [ ] **Step 8: Run tests**

```bash
cd /Users/user/attune
for t in identity_foundation_contracts service_role_grants_test; do
  psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/$t.sql >/dev/null 2>&1; echo "$t exit=$?"
done
grep service_role_grants .superpowers/sdd/2026-10-25-spec1-w1/sql-baseline.txt
```
Expected: `identity_foundation_contracts exit=0`; `service_role_grants_test` exits `0` if the baseline says PASS (the three new tables carry service_role DML).

---

### Task 6: Birth dates, holds and the atomic sign-up (W1b; D8, Q4, I-7)

**Files:**
- Create: `supabase/migrations/20261025100200_account_birthdates_and_holds.sql`
- Create: `supabase/migrations/20261025100210_account_birthdates_and_holds_grants.sql`
- Modify: `supabase/tests/identity_foundation_contracts.sql` (insert section F before the final `ROLLBACK;`)
- Modify: `scripts/local_pg_grants.sql` (append)

**Interfaces:**
- Consumes: `public.verified_phone(uuid)` (Task 1), `private.bump_metric_internal(text)` (Task 5), `pg_temp.metric(text)` (section E).
- Produces: tables `public.account_birthdates (user_id uuid PK → users ON DELETE CASCADE, birth_date date ≥ 1900-01-01, source 'self_declared'|'support_corrected', declared_at, corrected_at, self_corrections 0..1)` and `public.account_holds (user_id → users ON DELETE CASCADE, kind 'age_review'|'recovery_hold'|'safety_review', reason_ref, created_at, expires_at, resolved_at, resolved_by; PK (user_id, kind))`, neither readable by a client; `private.age_on_utc_today(date) RETURNS integer`; `public.account_age(p_user uuid) RETURNS integer` (no client grant; NULL without a DOB); `public.get_my_age() RETURNS integer` (authenticated); `public.place_account_hold(p_user uuid, p_kind text, p_ref text DEFAULT NULL) RETURNS void` (no client grant; re-opens a resolved hold; `recovery_hold` expires in 180 days); `public.complete_sign_up(p_display_name text, p_birth_date date, p_eula_version text) RETURNS jsonb` → `{age, created}` (authenticated; errors `signup:not_signed_in|phone_required|invalid_name|eula_required|invalid_birth_date|not_eligible`); `public.set_my_birth_date(p_birth_date date) RETURNS jsonb` → `{status:'ok', age}` or `{status:'not_eligible'}` (authenticated; errors `birth_date:not_signed_in|no_account|invalid|already_set`).

- [ ] **Step 1: Write the failing contract section**

In `supabase/tests/identity_foundation_contracts.sql`, insert immediately before the final line `ROLLBACK;`:

```sql
-- =====================================================================
-- F. Sign-up, birth dates and holds (W1b; D8, Q4, I-7). Under 18 writes
--    nothing; the phone is Auth's; a replay is idempotent; a DOB is
--    write-once; a legacy minor gets a hold that commits. Fixtures 11-19.
-- =====================================================================
DO $$
BEGIN
  IF to_regclass('public.account_birthdates') IS NULL OR to_regclass('public.account_holds') IS NULL
     OR to_regprocedure('public.complete_sign_up(text,date,text)') IS NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: W1b birth-date objects are missing (account_birthdates, account_holds, complete_sign_up)';
  END IF;
END $$;

DO $$
BEGIN
  PERFORM pg_temp.make_account('5f1a0000-0000-0000-0000-000000000011', '+15558100011', NULL);
  PERFORM pg_temp.make_account('5f1a0000-0000-0000-0000-000000000012', '+15558100012', NULL);
  PERFORM pg_temp.make_account('5f1a0000-0000-0000-0000-000000000013', '+15558100013', 'Legacy W1');
  PERFORM pg_temp.make_account('5f1a0000-0000-0000-0000-000000000014', '+15558100014', 'Legacy Minor W1');
  PERFORM pg_temp.make_account('5f1a0000-0000-0000-0000-000000000015', '+15558100015', NULL);
  PERFORM pg_temp.make_account('5f1a0000-0000-0000-0000-000000000016', '+15558100016', NULL);
  PERFORM pg_temp.make_account('5f1a0000-0000-0000-0000-000000000017', '+15558100017', NULL);
  PERFORM pg_temp.make_account('5f1a0000-0000-0000-0000-000000000018', '+15558100018', NULL);
  PERFORM pg_temp.make_account('5f1a0000-0000-0000-0000-000000000019', '+15558100019', NULL);
END $$;
UPDATE auth.users SET phone_confirmed_at = NULL WHERE id = '5f1a0000-0000-0000-0000-000000000015';

DO $$
DECLARE
  v_adult constant uuid := '5f1a0000-0000-0000-0000-000000000011';
  v_minor constant uuid := '5f1a0000-0000-0000-0000-000000000012';
  v_legacy constant uuid := '5f1a0000-0000-0000-0000-000000000013';
  v_legacy_minor constant uuid := '5f1a0000-0000-0000-0000-000000000014';
  v_unverified constant uuid := '5f1a0000-0000-0000-0000-000000000015';
  v_birthday constant uuid := '5f1a0000-0000-0000-0000-000000000016';
  v_tomorrow constant uuid := '5f1a0000-0000-0000-0000-000000000017';
  v_twi constant uuid := '5f1a0000-0000-0000-0000-000000000018';
  v_arabic constant uuid := '5f1a0000-0000-0000-0000-000000000019';
  v_today constant date := (now() AT TIME ZONE 'utc')::date;
  v_eighteen constant date := ((now() AT TIME ZONE 'utc')::date - interval '18 years')::date;
  v_res jsonb;
  v_msg text;
  v_n int;
  v_before bigint;
BEGIN
  -- Privileges: a DOB and a hold are never reachable from a client.
  IF has_function_privilege('authenticated', 'public.account_age(uuid)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.account_age(uuid)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.place_account_hold(uuid,text,text)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.complete_sign_up(text,date,text)', 'EXECUTE')
     OR has_table_privilege('authenticated', 'public.account_birthdates', 'SELECT')
     OR has_table_privilege('authenticated', 'public.account_holds', 'SELECT')
     OR has_table_privilege('anon', 'public.account_birthdates', 'SELECT') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a client can reach a birth date or a hold directly';
  END IF;
  IF NOT has_function_privilege('authenticated', 'public.complete_sign_up(text,date,text)', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.set_my_birth_date(date)', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.get_my_age()', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a sign-up RPC lost its grant';
  END IF;

  -- 1. Under 18: refused, and nothing at all is written (D8).
  PERFORM pg_temp.as_user(v_minor);
  v_msg := pg_temp.error_of(format('SELECT public.complete_sign_up(%L, %L::date, %L)',
    'Kwame', (v_today - interval '17 years')::date, '2'));
  RESET ROLE;
  IF v_msg IS DISTINCT FROM 'signup:not_eligible' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an under-18 sign-up was not refused (got %)', coalesce(v_msg, 'no error');
  END IF;
  SELECT (SELECT count(*) FROM public.users WHERE id = v_minor)
       + (SELECT count(*) FROM public.profiles WHERE id = v_minor)
       + (SELECT count(*) FROM public.account_birthdates WHERE user_id = v_minor) INTO v_n;
  IF v_n <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an under-18 sign-up wrote % row(s)', v_n;
  END IF;

  -- 2. An adult: one transaction; phone from auth.users; name collapsed.
  v_before := pg_temp.metric('signup_completed');
  PERFORM pg_temp.as_user(v_adult);
  v_res := public.complete_sign_up('  Ama   Mensah ', DATE '1996-03-27', '2');
  RESET ROLE;
  IF v_res IS DISTINCT FROM jsonb_build_object('age', extract(year FROM age(v_today, DATE '1996-03-27'))::int, 'created', true) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the first sign-up returned %', v_res;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.users u JOIN auth.users a ON a.id = u.id
                  WHERE u.id = v_adult AND u.phone = a.phone AND u.display_name = 'Ama Mensah'
                    AND u.eula_version = '2' AND u.eula_accepted_at IS NOT NULL) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the users row is not (Auth phone, collapsed name, EULA 2)';
  END IF;
  IF (SELECT display_name FROM public.profiles WHERE id = v_adult) IS DISTINCT FROM 'Ama Mensah'
     OR (SELECT birth_date FROM public.account_birthdates WHERE user_id = v_adult AND source = 'self_declared')
        IS DISTINCT FROM DATE '1996-03-27' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the profile name or the DOB was not written';
  END IF;
  IF pg_temp.metric('signup_completed') <> v_before + 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: signup_completed did not count once';
  END IF;

  -- 3. The offline replay: idempotent; the stored DOB and name win.
  PERFORM pg_temp.as_user(v_adult);
  v_res := public.complete_sign_up('Someone Else', DATE '1980-01-01', '2');
  RESET ROLE;
  IF v_res ->> 'created' IS DISTINCT FROM 'false'
     OR (v_res ->> 'age')::int <> extract(year FROM age(v_today, DATE '1996-03-27'))::int
     OR (SELECT birth_date FROM public.account_birthdates WHERE user_id = v_adult) <> DATE '1996-03-27'
     OR (SELECT display_name FROM public.users WHERE id = v_adult) <> 'Ama Mensah'
     OR pg_temp.metric('signup_completed') <> v_before + 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a replayed sign-up overwrote or recounted (%)', v_res;
  END IF;

  -- 4. Refusals that name the problem.
  PERFORM pg_temp.as_user(v_unverified);
  v_msg := pg_temp.error_of($q$SELECT public.complete_sign_up('Efua', DATE '1990-05-05', '2')$q$);
  RESET ROLE;
  IF v_msg IS DISTINCT FROM 'signup:phone_required' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an unverified phone was not refused (got %)', coalesce(v_msg, 'no error');
  END IF;
  PERFORM pg_temp.as_user(v_twi);
  FOREACH v_msg IN ARRAY ARRAY[
    pg_temp.error_of($q$SELECT public.complete_sign_up('12 !! --', DATE '1990-05-05', '2')$q$),
    pg_temp.error_of($q$SELECT public.complete_sign_up('   ', DATE '1990-05-05', '2')$q$),
    pg_temp.error_of(format('SELECT public.complete_sign_up(%L, %L::date, %L)', repeat('a', 41), DATE '1990-05-05', '2'))] LOOP
    IF v_msg IS DISTINCT FROM 'signup:invalid_name' THEN
      RESET ROLE;
      RAISE EXCEPTION 'CONTRACT VIOLATED: a bad name was not refused (got %)', coalesce(v_msg, 'no error');
    END IF;
  END LOOP;
  FOREACH v_msg IN ARRAY ARRAY[
    pg_temp.error_of(format('SELECT public.complete_sign_up(%L, %L::date, %L)', 'Efua', v_today + 1, '2')),
    pg_temp.error_of($q$SELECT public.complete_sign_up('Efua', DATE '1899-12-31', '2')$q$)] LOOP
    IF v_msg IS DISTINCT FROM 'signup:invalid_birth_date' THEN
      RESET ROLE;
      RAISE EXCEPTION 'CONTRACT VIOLATED: a bad DOB was not refused (got %)', coalesce(v_msg, 'no error');
    END IF;
  END LOOP;
  v_msg := pg_temp.error_of($q$SELECT public.complete_sign_up('Efua', DATE '1990-05-05', NULL)$q$);
  RESET ROLE;
  IF v_msg IS DISTINCT FROM 'signup:eula_required' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a sign-up without consent was not refused (got %)', coalesce(v_msg, 'no error');
  END IF;

  -- 5. Review Focus 2: a name in any script is a name.
  PERFORM pg_temp.as_user(v_twi);
  PERFORM public.complete_sign_up('Ɛsi  Ɔbɛng', DATE '1990-05-05', '2');
  RESET ROLE;
  PERFORM pg_temp.as_user(v_arabic);
  PERFORM public.complete_sign_up('عائشة', DATE '1990-05-05', '2');
  RESET ROLE;
  IF (SELECT display_name FROM public.users WHERE id = v_twi) IS DISTINCT FROM 'Ɛsi Ɔbɛng'
     OR (SELECT display_name FROM public.users WHERE id = v_arabic) IS DISTINCT FROM 'عائشة' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a non-Latin or West African name was not kept as typed';
  END IF;

  -- 6. Review Focus 1: the 18th birthday (UTC date) is in; the day after that DOB is not.
  PERFORM pg_temp.as_user(v_birthday);
  v_res := public.complete_sign_up('Kojo', v_eighteen, '2');
  RESET ROLE;
  IF (v_res ->> 'age')::int IS DISTINCT FROM 18 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an 18th-birthday sign-up gave %', v_res;
  END IF;
  PERFORM pg_temp.as_user(v_tomorrow);
  v_msg := pg_temp.error_of(format('SELECT public.complete_sign_up(%L, %L::date, %L)', 'Akua', v_eighteen + 1, '2'));
  RESET ROLE;
  IF v_msg IS DISTINCT FROM 'signup:not_eligible' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: someone turning 18 tomorrow was let in (got %)', coalesce(v_msg, 'no error');
  END IF;

  -- 7. Legacy accounts: a DOB once; under 18 places a hold that commits.
  PERFORM pg_temp.as_user(v_legacy);
  v_res := public.set_my_birth_date(DATE '1990-01-01');
  v_msg := pg_temp.error_of($q$SELECT public.set_my_birth_date(DATE '1991-01-01')$q$);
  v_n := public.get_my_age();
  RESET ROLE;
  IF v_res IS DISTINCT FROM jsonb_build_object('status', 'ok', 'age', extract(year FROM age(v_today, DATE '1990-01-01'))::int)
     OR v_msg IS DISTINCT FROM 'birth_date:already_set'
     OR v_n IS DISTINCT FROM extract(year FROM age(v_today, DATE '1990-01-01'))::int THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: legacy DOB: first %, second %, age %', v_res, v_msg, v_n;
  END IF;
  PERFORM pg_temp.as_user(v_legacy_minor);
  v_res := public.set_my_birth_date((v_today - interval '16 years')::date);
  RESET ROLE;
  IF v_res IS DISTINCT FROM '{"status": "not_eligible"}'::jsonb
     OR NOT EXISTS (SELECT 1 FROM public.account_holds
                     WHERE user_id = v_legacy_minor AND kind = 'age_review' AND resolved_at IS NULL)
     OR NOT EXISTS (SELECT 1 FROM public.account_birthdates WHERE user_id = v_legacy_minor) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a legacy minor got % without a kept hold and DOB', v_res;
  END IF;
  PERFORM pg_temp.as_user(v_unverified);
  IF public.get_my_age() IS NOT NULL THEN
    RESET ROLE;
    RAISE EXCEPTION 'CONTRACT VIOLATED: get_my_age returned an age with no DOB';
  END IF;
  RESET ROLE;

  -- 8. Holds: the two-argument call (I-7); a resolved hold re-opens; recovery expires in 180 days.
  PERFORM public.place_account_hold(v_legacy, 'safety_review');
  UPDATE public.account_holds SET resolved_at = now(), resolved_by = 'contract'
   WHERE user_id = v_legacy AND kind = 'safety_review';
  PERFORM public.place_account_hold(v_legacy, 'safety_review', 'case-1');
  IF NOT EXISTS (SELECT 1 FROM public.account_holds
                  WHERE user_id = v_legacy AND kind = 'safety_review'
                    AND resolved_at IS NULL AND resolved_by IS NULL AND reason_ref = 'case-1') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a resolved hold did not re-open';
  END IF;
  PERFORM public.place_account_hold(v_legacy, 'recovery_hold');
  IF (SELECT expires_at FROM public.account_holds WHERE user_id = v_legacy AND kind = 'recovery_hold')
     NOT BETWEEN now() + interval '179 days' AND now() + interval '181 days' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a recovery hold does not expire in 180 days';
  END IF;
  v_msg := pg_temp.error_of(format('SELECT public.place_account_hold(%L, %L)', v_legacy, 'banned'));
  IF v_msg IS DISTINCT FROM 'new row for relation "account_holds" violates check constraint "account_holds_kind_check"' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an unknown hold kind was not refused (got %)', coalesce(v_msg, 'no error');
  END IF;
END $$;
```

- [ ] **Step 2: Run it to verify it fails**

```bash
cd /Users/user/attune
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/identity_foundation_contracts.sql; echo "exit=$?"
```
Expected: `ERROR:  CONTRACT VIOLATED: W1b birth-date objects are missing (account_birthdates, account_holds, complete_sign_up)`, `exit=3`.

- [ ] **Step 3: Write the migration**

Create `supabase/migrations/20261025100200_account_birthdates_and_holds.sql` with exactly:

```sql
-- Spec 1 W1b, migration 3 of 6 (spec §4.7 #3): account_birthdates_and_holds.
--   * account_birthdates: the declared date of birth, write-once, never
--     shown (only an age is), never readable by a client;
--   * account_holds: whole-account holds (age_review, recovery_hold,
--     safety_review). Created here because set_my_birth_date and
--     get_my_home_state use them; the access-token hook that enforces them
--     lands in W6a;
--   * complete_sign_up writes users, profiles.display_name, the DOB and the
--     consent in one transaction, and an under-18 DOB writes nothing (D8).
-- Grants in 20261025100210_account_birthdates_and_holds_grants.sql.
BEGIN;

CREATE TABLE IF NOT EXISTS public.account_birthdates (
  user_id uuid PRIMARY KEY REFERENCES public.users(id) ON DELETE CASCADE,
  birth_date date NOT NULL CONSTRAINT account_birthdates_birth_date_check CHECK (birth_date >= DATE '1900-01-01'),
  source text NOT NULL DEFAULT 'self_declared'
    CONSTRAINT account_birthdates_source_check CHECK (source IN ('self_declared', 'support_corrected')),
  declared_at timestamptz NOT NULL DEFAULT now(),
  corrected_at timestamptz,
  self_corrections smallint NOT NULL DEFAULT 0
    CONSTRAINT account_birthdates_self_corrections_check CHECK (self_corrections >= 0 AND self_corrections <= 1)
);
ALTER TABLE public.account_birthdates ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.account_holds (
  user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  kind text NOT NULL CONSTRAINT account_holds_kind_check CHECK (kind IN ('age_review', 'recovery_hold', 'safety_review')),
  reason_ref text,
  created_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz,
  resolved_at timestamptz,
  resolved_by text,
  PRIMARY KEY (user_id, kind)
);
ALTER TABLE public.account_holds ENABLE ROW LEVEL SECURITY;

-- Whole years on today's UTC date: the stricter side of the day line, the
-- same rule the app's A2 screen uses.
CREATE OR REPLACE FUNCTION private.age_on_utc_today(p_birth_date date)
RETURNS integer
LANGUAGE sql
STABLE
SET search_path = ''
AS $$
  SELECT extract(year FROM age((now() AT TIME ZONE 'utc')::date, p_birth_date))::integer;
$$;

CREATE OR REPLACE FUNCTION public.account_age(p_user uuid)
RETURNS integer
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT private.age_on_utc_today(b.birth_date)
    FROM public.account_birthdates AS b
   WHERE b.user_id = p_user;
$$;

CREATE OR REPLACE FUNCTION public.get_my_age()
RETURNS integer
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT public.account_age(auth.uid());
$$;

-- Upsert an active hold. p_ref defaults to NULL so Spec 2's two-argument
-- call works (review I-7). A resolved hold of the same kind re-opens.
CREATE OR REPLACE FUNCTION public.place_account_hold(p_user uuid, p_kind text, p_ref text DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF p_user IS NULL OR p_kind IS NULL THEN
    RAISE EXCEPTION 'hold:invalid';
  END IF;
  INSERT INTO public.account_holds AS h (user_id, kind, reason_ref, created_at, expires_at)
  VALUES (p_user, p_kind, p_ref, now(),
          CASE WHEN p_kind = 'recovery_hold' THEN now() + interval '180 days' END)
  ON CONFLICT (user_id, kind) DO UPDATE
    SET reason_ref = coalesce(EXCLUDED.reason_ref, h.reason_ref),
        created_at = CASE WHEN h.resolved_at IS NULL THEN h.created_at ELSE EXCLUDED.created_at END,
        expires_at = CASE WHEN h.resolved_at IS NULL THEN h.expires_at ELSE EXCLUDED.expires_at END,
        resolved_at = NULL,
        resolved_by = NULL;
END;
$$;

-- A5 (spec §3.3): the account, in one transaction. The phone comes from
-- auth.users, never from the caller. Idempotent for the offline replay
-- (PendingSignUp): a replay returns {age, created:false} and overwrites
-- nothing (a stored DOB wins; a non-empty name stays).
CREATE OR REPLACE FUNCTION public.complete_sign_up(p_display_name text, p_birth_date date, p_eula_version text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid constant uuid := auth.uid();
  v_today constant date := (now() AT TIME ZONE 'utc')::date;
  v_name constant text := regexp_replace(btrim(coalesce(p_display_name, '')), '\s+', ' ', 'g');
  v_phone text;
  v_stored date;
  v_age integer;
  v_created boolean;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'signup:not_signed_in';
  END IF;
  v_phone := public.verified_phone(v_uid);
  IF v_phone IS NULL THEN
    RAISE EXCEPTION 'signup:phone_required';
  END IF;
  IF char_length(v_name) NOT BETWEEN 1 AND 40 OR v_name !~ '[^[:space:][:punct:][:digit:]]' THEN
    RAISE EXCEPTION 'signup:invalid_name';
  END IF;
  IF p_eula_version IS NULL OR p_eula_version !~ '^[0-9]{1,3}$' THEN
    RAISE EXCEPTION 'signup:eula_required';
  END IF;

  SELECT b.birth_date INTO v_stored FROM public.account_birthdates AS b WHERE b.user_id = v_uid;
  IF v_stored IS NULL THEN
    IF p_birth_date IS NULL OR p_birth_date < DATE '1900-01-01' OR p_birth_date > v_today THEN
      RAISE EXCEPTION 'signup:invalid_birth_date';
    END IF;
    v_age := private.age_on_utc_today(p_birth_date);
  ELSE
    v_age := private.age_on_utc_today(v_stored);
  END IF;

  -- Under 18: refused before anything at all is written (D8).
  IF v_age < 18 THEN RAISE EXCEPTION 'signup:not_eligible'; END IF;

  v_created := NOT EXISTS (SELECT 1 FROM public.users AS u WHERE u.id = v_uid);

  INSERT INTO public.users AS u (id, phone, display_name, eula_accepted_at, eula_version)
  VALUES (v_uid, v_phone, v_name, now(), p_eula_version)
  ON CONFLICT (id) DO UPDATE
    SET phone = EXCLUDED.phone,
        display_name = CASE WHEN btrim(u.display_name) ~ '^\+?[0-9 ()-]*$'
                            THEN EXCLUDED.display_name ELSE u.display_name END,
        eula_accepted_at = CASE WHEN u.eula_version IS DISTINCT FROM EXCLUDED.eula_version
                                THEN EXCLUDED.eula_accepted_at ELSE u.eula_accepted_at END,
        eula_version = EXCLUDED.eula_version;

  INSERT INTO public.profiles AS p (id, display_name)
  VALUES (v_uid, v_name)
  ON CONFLICT (id) DO UPDATE
    SET display_name = EXCLUDED.display_name
  WHERE coalesce(btrim(p.display_name), '') ~ '^\+?[0-9 ()-]*$';

  INSERT INTO public.account_birthdates (user_id, birth_date)
  VALUES (v_uid, coalesce(v_stored, p_birth_date))
  ON CONFLICT (user_id) DO NOTHING;

  IF v_created THEN
    PERFORM private.bump_metric_internal('signup_completed');
  END IF;
  RETURN jsonb_build_object('age', v_age, 'created', v_created);
END;
$$;

-- A2 interstitial for legacy accounts (spec §3.15): once. Under 18 places an
-- age_review hold and returns not_eligible WITHOUT raising, so the hold and
-- the DOB commit.
CREATE OR REPLACE FUNCTION public.set_my_birth_date(p_birth_date date)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid constant uuid := auth.uid();
  v_age integer;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'birth_date:not_signed_in';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.users AS u WHERE u.id = v_uid) THEN
    RAISE EXCEPTION 'birth_date:no_account';
  END IF;
  IF p_birth_date IS NULL OR p_birth_date < DATE '1900-01-01'
     OR p_birth_date > (now() AT TIME ZONE 'utc')::date THEN
    RAISE EXCEPTION 'birth_date:invalid';
  END IF;
  INSERT INTO public.account_birthdates (user_id, birth_date)
  VALUES (v_uid, p_birth_date)
  ON CONFLICT (user_id) DO NOTHING;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'birth_date:already_set';
  END IF;
  v_age := private.age_on_utc_today(p_birth_date);
  IF v_age < 18 THEN
    PERFORM public.place_account_hold(v_uid, 'age_review', 'self_declared_birth_date');
    RETURN jsonb_build_object('status', 'not_eligible');
  END IF;
  RETURN jsonb_build_object('status', 'ok', 'age', v_age);
END;
$$;

COMMIT;
```

- [ ] **Step 4: Write the grants twin**

Create `supabase/migrations/20261025100210_account_birthdates_and_holds_grants.sql` with exactly:

```sql
-- Spec 1 W1b: grants for 20261025100200_account_birthdates_and_holds.sql.
-- No client grant on either table (a DOB is never readable from the phone);
-- service_role keeps DML (service_role_grants_test).
BEGIN;
REVOKE ALL ON public.account_birthdates, public.account_holds FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.account_birthdates, public.account_holds TO service_role;

REVOKE ALL ON FUNCTION private.age_on_utc_today(date) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.account_age(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.place_account_hold(uuid, text, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.complete_sign_up(text, date, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.set_my_birth_date(date) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_my_age() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.complete_sign_up(text, date, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_my_birth_date(date) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_my_age() TO authenticated;
COMMIT;
```

- [ ] **Step 5: Apply both twice, then run the contract**

```bash
cd /Users/user/attune
for i in 1 2; do
  psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/migrations/20261025100200_account_birthdates_and_holds.sql; echo "migration exit=$?"
  psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/migrations/20261025100210_account_birthdates_and_holds_grants.sql; echo "grants exit=$?"
done
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/identity_foundation_contracts.sql; echo "exit=$?"
```
Expected: four `… exit=0`; then `exit=0` with no `ERROR`.

- [ ] **Step 6: Mutation check (spec §7.4: remove the age check in `complete_sign_up`)**

```bash
cd /Users/user/attune
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a <<'SQL'; echo "exit=$?"
BEGIN;
SELECT replace(pg_get_functiondef('public.complete_sign_up(text,date,text)'::regprocedure),
  'IF v_age < 18 THEN RAISE EXCEPTION ''signup:not_eligible''; END IF;', '') \gexec
DO $$ BEGIN
  IF position('signup:not_eligible' IN pg_get_functiondef('public.complete_sign_up(text,date,text)'::regprocedure)) > 0 THEN
    RAISE EXCEPTION 'MUTANT NOT APPLIED';
  END IF;
END $$;
\i supabase/tests/identity_foundation_contracts.sql
SQL
```
Expected: `ERROR:  CONTRACT VIOLATED: an under-18 sign-up was not refused (got no error)`, `exit=3`.

- [ ] **Step 7: Add the twin to the local harness (edit only)**

Append to the end of `scripts/local_pg_grants.sql`:

```sql

-- Spec 1 W1b: birth dates and holds are server-only; the sign-up RPCs.
\i supabase/migrations/20261025100210_account_birthdates_and_holds_grants.sql
```

- [ ] **Step 8: Run tests**

```bash
cd /Users/user/attune
for t in identity_foundation_contracts service_role_grants_test account_deletion_contracts data_export_contracts; do
  psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/$t.sql >/dev/null 2>&1; echo "$t exit=$?"
done
grep -E 'service_role_grants|account_deletion|data_export' .superpowers/sdd/2026-10-25-spec1-w1/sql-baseline.txt
```
Expected: `identity_foundation_contracts exit=0`; the other three as in the baseline (the new tables cascade with `users`).

---

### Task 7: Paths, home state and the `onboarding_profiles.mode` drop (W1b; Q6, Q7, D14, D18, I-6)

**Files:**
- Create: `supabase/migrations/20261025100300_paths_and_home_state.sql`
- Create: `supabase/migrations/20261025100310_paths_and_home_state_grants.sql`
- Modify: `supabase/tests/identity_foundation_contracts.sql` (insert section G before the final `ROLLBACK;`)
- Modify: `lib/features/onboarding/data/onboarding_submission_service.dart` (the two `mode` lines of the `onboarding_profiles` upsert)
- Modify: `test/features/onboarding/onboarding_submission_service_test.dart` (append one test)
- Modify: `scripts/local_pg_grants.sql` (append)

**Interfaces:**
- Consumes: `public.account_age(uuid)`, `public.place_account_hold(uuid, text, text)` (Task 6); `private.bump_metric_internal(text)`, `pg_temp.metric(text)` (Task 5); `public.pause_dating_for_relationship_user(uuid)` (Task 3); existing `public.dating_flag_enabled(text)`, `public.relationship_chat_open_for(uuid, uuid)`, `public.withdraw_my_pending_invites()` (unchanged).
- Produces: `private.spec1_flag_on(p_key text) RETURNS boolean` (effective flag: `flow_paths_v2` needs `flow_signin_v2`, `flow_couples_v2` needs `flow_paths_v2`, `couple_profile` needs `flow_couples_v2`; missing row = off); `private.dating_home_summary(p_user uuid) RETURNS jsonb` → `{enabled, enrolled}` (Spec 2 W1b re-creates it, same shape); `public.set_user_path_internal(p_user uuid, p_path text) RETURNS void` (no client grant; the single path writer; pauses Dating only on a change to `relationship`; W5 re-creates it from this live body); `public.set_my_path(p_path text, p_confirmed boolean DEFAULT false) RETURNS jsonb` (authenticated; errors `path:not_signed_in|invalid|needs_signup|relationship_open|confirm_withdraw|confirm_pause_dating`; returns `get_my_home_state()`); `public.get_my_home_state() RETURNS jsonb` → `{has_account, path, tab, path_previous, needs, hold, eula_version, dating:{enabled, enrolled}, link:{state, relationship_id, partner_first_name, invite_expires_at, window_ends_at}}` with `tab` `chat|me`, `needs` ⊆ `["consent","birth_date","name","path"]` in that order, `link.state` `none|pending|linked|paused|ended_window|after_ending` (authenticated); `public.withdraw_my_pending_invites(p_return_to_previous_path boolean) RETURNS integer` (authenticated; no default). `onboarding_profiles.mode` no longer exists.

- [ ] **Step 1: Write the failing contract section**

In `supabase/tests/identity_foundation_contracts.sql`, insert immediately before the final line `ROLLBACK;`:

```sql
-- =====================================================================
-- G. Paths and home state (W1b; Q6, Q7, D14, D18, I-6). Fixtures 20-39,
--    relationships 5f1a0000-0000-0000-0000-0000000001NN.
-- =====================================================================
DO $$
DECLARE
  v_bad text;
BEGIN
  IF to_regprocedure('public.set_my_path(text,boolean)') IS NULL
     OR to_regprocedure('public.get_my_home_state()') IS NULL
     OR to_regprocedure('public.set_user_path_internal(uuid,text)') IS NULL
     OR to_regprocedure('public.withdraw_my_pending_invites(boolean)') IS NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: W1b path objects are missing (set_my_path, get_my_home_state, set_user_path_internal)';
  END IF;

  -- I-6: no W1 function names a table or column that a later wave creates.
  SELECT string_agg(p.oid::regprocedure::text, ', ' ORDER BY p.oid::regprocedure::text) INTO v_bad
    FROM pg_proc p
   WHERE p.oid IN ('public.verified_phone(uuid)'::regprocedure,
                   'private.metric_increment(text)'::regprocedure,
                   'private.bump_metric_internal(text)'::regprocedure,
                   'public.bump_metric(text)'::regprocedure,
                   'public.bump_metric_server(text)'::regprocedure,
                   'public.complete_sign_up(text,date,text)'::regprocedure,
                   'public.set_my_birth_date(date)'::regprocedure,
                   'public.account_age(uuid)'::regprocedure,
                   'public.place_account_hold(uuid,text,text)'::regprocedure,
                   'private.spec1_flag_on(text)'::regprocedure,
                   'private.dating_home_summary(uuid)'::regprocedure,
                   'public.set_user_path_internal(uuid,text)'::regprocedure,
                   'public.set_my_path(text,boolean)'::regprocedure,
                   'public.get_my_home_state()'::regprocedure,
                   'public.withdraw_my_pending_invites(boolean)'::regprocedure)
     AND p.prosrc ~* '(couple_profiles|couple_profile_drafts|journal_reminder_settings|otp_delivery_intents|invite_preview_attempts|account_activity|fresh_start_challenges|auth_hook_failures|parked_phone_hmac|child_safety_reports)';
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a W1 function names a later wave''s table (I-6): %', v_bad;
  END IF;

  -- Privileges.
  IF has_function_privilege('authenticated', 'public.set_user_path_internal(uuid,text)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'private.spec1_flag_on(text)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'private.dating_home_summary(uuid)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.get_my_home_state()', 'EXECUTE')
     OR has_function_privilege('anon', 'public.set_my_path(text,boolean)', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.get_my_home_state()', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.set_my_path(text,boolean)', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.withdraw_my_pending_invites(boolean)', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.withdraw_my_pending_invites()', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: path function grants are wrong';
  END IF;

  -- onboarding_profiles.mode is gone (W1b; its client writer goes in the same release).
  IF EXISTS (SELECT 1 FROM information_schema.columns
              WHERE table_schema = 'public' AND table_name = 'onboarding_profiles' AND column_name = 'mode') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: onboarding_profiles.mode still exists';
  END IF;
END $$;

-- An adult with a DOB, a v2 consent and (optionally) a path.
CREATE FUNCTION pg_temp.adult(p_id uuid, p_phone text, p_name text, p_eula text, p_path text) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  PERFORM pg_temp.make_account(p_id, p_phone, p_name);
  UPDATE public.users SET eula_version = p_eula, eula_accepted_at = now(), path = p_path,
                          path_chosen_at = CASE WHEN p_path IS NULL THEN NULL ELSE now() - interval '1 day' END
   WHERE id = p_id;
  INSERT INTO public.account_birthdates (user_id, birth_date) VALUES (p_id, DATE '1990-01-01');
END $$;

DO $$
BEGIN
  PERFORM pg_temp.adult('5f1a0000-0000-0000-0000-000000000020', '+15558100020', 'Esi Path', '2', NULL);
  PERFORM pg_temp.make_account('5f1a0000-0000-0000-0000-000000000021', '+15558100021', 'No DOB W1');
  PERFORM pg_temp.make_account('5f1a0000-0000-0000-0000-000000000022', '+15558100022', NULL);
  PERFORM pg_temp.adult('5f1a0000-0000-0000-0000-000000000023', '+15558100023', 'Adwoa Linked', '2', NULL);
  PERFORM pg_temp.adult('5f1a0000-0000-0000-0000-000000000024', '+15558100024', 'Kojo Asante', '2', 'relationship');
  PERFORM pg_temp.adult('5f1a0000-0000-0000-0000-000000000025', '+15558100025', 'Akosua Paused', '2', 'relationship');
  PERFORM pg_temp.adult('5f1a0000-0000-0000-0000-000000000026', '+15558100026', '+15558100026', '2', 'relationship');
  PERFORM pg_temp.adult('5f1a0000-0000-0000-0000-000000000027', '+15558100027', 'Efua Ended', '2', 'relationship');
  PERFORM pg_temp.adult('5f1a0000-0000-0000-0000-000000000028', '+15558100028', 'Kwabena Ended', '2', 'relationship');
  PERFORM pg_temp.adult('5f1a0000-0000-0000-0000-000000000029', '+15558100029', 'Ama Long Ago', '2', 'relationship');
  PERFORM pg_temp.adult('5f1a0000-0000-0000-0000-000000000030', '+15558100030', 'Yaw Long Ago', '2', 'relationship');
  PERFORM pg_temp.adult('5f1a0000-0000-0000-0000-000000000031', '+15558100031', 'Abena First', '2', 'relationship');
  PERFORM pg_temp.adult('5f1a0000-0000-0000-0000-000000000032', '+15558100032', 'Dating Spy', '2', 'dating');
  PERFORM pg_temp.adult('5f1a0000-0000-0000-0000-000000000033', '+15558100033', 'Just Me', '2', 'just_me');
  PERFORM pg_temp.adult('5f1a0000-0000-0000-0000-000000000034', '+15558100034', 'Held W1', '2', 'just_me');
  PERFORM pg_temp.adult('5f1a0000-0000-0000-0000-000000000035', '+15558100035', 'Old Consent', '1', NULL);
  PERFORM pg_temp.adult('5f1a0000-0000-0000-0000-000000000036', '+15558100036', 'Dating To Couple', '2', 'dating');
  PERFORM pg_temp.adult('5f1a0000-0000-0000-0000-000000000037', '+15558100037', 'Dating To Me', '2', 'dating');
  PERFORM pg_temp.adult('5f1a0000-0000-0000-0000-000000000038', '+15558100038', 'Pending Invite', '2', 'relationship');
END $$;

INSERT INTO public.relationships (id, user_a, user_b, status, started_at, invite_accepted_at, created_at) VALUES
  ('5f1a0000-0000-0000-0000-000000000101', '5f1a0000-0000-0000-0000-000000000023',
   '5f1a0000-0000-0000-0000-000000000024', 'active', current_date, now() - interval '10 days', now() - interval '10 days');
INSERT INTO public.relationships (id, user_a, user_b, status, created_at, paused_at, paused_by) VALUES
  ('5f1a0000-0000-0000-0000-000000000102', '5f1a0000-0000-0000-0000-000000000025',
   '5f1a0000-0000-0000-0000-000000000026', 'paused', now() - interval '20 days', now() - interval '1 day',
   '5f1a0000-0000-0000-0000-000000000025');
INSERT INTO public.relationships (id, user_a, user_b, status, created_at, ended_at, ended_by) VALUES
  ('5f1a0000-0000-0000-0000-000000000103', '5f1a0000-0000-0000-0000-000000000027',
   '5f1a0000-0000-0000-0000-000000000028', 'ended', now() - interval '60 days', now() - interval '2 days',
   '5f1a0000-0000-0000-0000-000000000027'),
  ('5f1a0000-0000-0000-0000-000000000104', '5f1a0000-0000-0000-0000-000000000029',
   '5f1a0000-0000-0000-0000-000000000030', 'ended', now() - interval '90 days', now() - interval '40 days',
   '5f1a0000-0000-0000-0000-000000000029');
INSERT INTO public.relationships (id, user_a, status, invite_code, invite_expires_at, created_at) VALUES
  ('5f1a0000-0000-0000-0000-000000000105', '5f1a0000-0000-0000-0000-000000000031', 'pending', 'W1PND5',
   now() + interval '6 days', now() - interval '1 day'),
  ('5f1a0000-0000-0000-0000-000000000106', '5f1a0000-0000-0000-0000-000000000038', 'pending', 'W1PND6',
   now() + interval '5 days', now() - interval '2 days');
INSERT INTO public.dating_enrollments (user_id, state) VALUES
  ('5f1a0000-0000-0000-0000-000000000032', 'active'),
  ('5f1a0000-0000-0000-0000-000000000036', 'active'),
  ('5f1a0000-0000-0000-0000-000000000037', 'active');
DO $$
BEGIN
  PERFORM public.place_account_hold('5f1a0000-0000-0000-0000-000000000034', 'safety_review');
END $$;

CREATE FUNCTION pg_temp.home_of(p uuid) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v jsonb;
BEGIN
  PERFORM pg_temp.as_user(p);
  v := public.get_my_home_state();
  RESET ROLE;
  RETURN v;
END $$;

-- G1. Who may choose a path, and the refusals by name.
DO $$
DECLARE
  v_msg text;
BEGIN
  PERFORM pg_temp.as_user('5f1a0000-0000-0000-0000-000000000021');
  v_msg := pg_temp.error_of($q$SELECT public.set_my_path('just_me')$q$);
  RESET ROLE;
  IF v_msg IS DISTINCT FROM 'path:needs_signup' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a path without a DOB was not refused (got %)', coalesce(v_msg, 'no error');
  END IF;
  PERFORM pg_temp.as_user('5f1a0000-0000-0000-0000-000000000022');
  v_msg := pg_temp.error_of($q$SELECT public.set_my_path('just_me')$q$);
  RESET ROLE;
  IF v_msg IS DISTINCT FROM 'path:needs_signup' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a path without an account was not refused (got %)', coalesce(v_msg, 'no error');
  END IF;

  -- With flow_signin_v2 effectively on, EULA 2 is required.
  INSERT INTO public.feature_flags (key, enabled) VALUES ('flow_signin_v2', true)
  ON CONFLICT (key) DO UPDATE SET enabled = true;
  PERFORM pg_temp.as_user('5f1a0000-0000-0000-0000-000000000035');
  v_msg := pg_temp.error_of($q$SELECT public.set_my_path('just_me')$q$);
  RESET ROLE;
  UPDATE public.feature_flags SET enabled = false WHERE key = 'flow_signin_v2';
  IF v_msg IS DISTINCT FROM 'path:needs_signup' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a v1 consent chose a path under flow_signin_v2 (got %)', coalesce(v_msg, 'no error');
  END IF;

  PERFORM pg_temp.as_user('5f1a0000-0000-0000-0000-000000000020');
  v_msg := pg_temp.error_of($q$SELECT public.set_my_path('couples')$q$);
  RESET ROLE;
  IF v_msg IS DISTINCT FROM 'path:invalid' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an unknown path was not refused (got %)', coalesce(v_msg, 'no error');
  END IF;

  PERFORM pg_temp.as_user('5f1a0000-0000-0000-0000-000000000023');
  v_msg := pg_temp.error_of($q$SELECT public.set_my_path('just_me')$q$);
  RESET ROLE;
  IF v_msg IS DISTINCT FROM 'path:relationship_open' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a linked member left Relationship (got %)', coalesce(v_msg, 'no error');
  END IF;
  PERFORM pg_temp.as_user('5f1a0000-0000-0000-0000-000000000025');
  v_msg := pg_temp.error_of($q$SELECT public.set_my_path('dating')$q$);
  RESET ROLE;
  IF v_msg IS DISTINCT FROM 'path:relationship_open' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a paused member left Relationship (got %)', coalesce(v_msg, 'no error');
  END IF;

  -- A pending invite: confirm first, then the invite goes in the same call.
  PERFORM pg_temp.as_user('5f1a0000-0000-0000-0000-000000000038');
  v_msg := pg_temp.error_of($q$SELECT public.set_my_path('just_me')$q$);
  RESET ROLE;
  IF v_msg IS DISTINCT FROM 'path:confirm_withdraw' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: leaving with a pending invite did not ask first (got %)', coalesce(v_msg, 'no error');
  END IF;
  PERFORM pg_temp.as_user('5f1a0000-0000-0000-0000-000000000038');
  PERFORM public.set_my_path('just_me', true);
  RESET ROLE;
  IF EXISTS (SELECT 1 FROM public.relationships WHERE id = '5f1a0000-0000-0000-0000-000000000106')
     OR (SELECT path FROM public.users WHERE id = '5f1a0000-0000-0000-0000-000000000038') <> 'just_me' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a confirmed switch kept the invite or the old path';
  END IF;
END $$;

-- G2. The first choice, then a switch: path_previous, relationship_status
--     once (D14), onboarding_profiles, metrics, tab.
DO $$
DECLARE
  v_me constant uuid := '5f1a0000-0000-0000-0000-000000000020';
  v_res jsonb;
  v_chosen_before bigint := pg_temp.metric('path_chosen:just_me');
  v_switch_before bigint := pg_temp.metric('path_switch_7d:just_me>relationship');
BEGIN
  IF pg_temp.home_of(v_me) -> 'needs' IS DISTINCT FROM '["path"]'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an account with no path did not need one: %', pg_temp.home_of(v_me);
  END IF;
  PERFORM pg_temp.as_user(v_me);
  v_res := public.set_my_path('just_me');
  RESET ROLE;
  IF v_res ->> 'path' IS DISTINCT FROM 'just_me' OR v_res ->> 'tab' IS DISTINCT FROM 'me'
     OR v_res -> 'needs' IS DISTINCT FROM '[]'::jsonb OR v_res -> 'path_previous' IS DISTINCT FROM 'null'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: set_my_path did not return the new home state: %', v_res;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.onboarding_profiles WHERE user_id = v_me)
     OR (SELECT relationship_status FROM public.profiles WHERE id = v_me) IS DISTINCT FROM 'figuring_it_out'
     OR (SELECT path_chosen_at FROM public.users WHERE id = v_me) IS NULL
     OR pg_temp.metric('path_chosen:just_me') <> v_chosen_before + 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the first path choice did not record onboarding, status, time and metric';
  END IF;

  PERFORM pg_temp.as_user(v_me);
  v_res := public.set_my_path('relationship');
  RESET ROLE;
  IF v_res ->> 'path' IS DISTINCT FROM 'relationship' OR v_res ->> 'path_previous' IS DISTINCT FROM 'just_me'
     OR v_res ->> 'tab' IS DISTINCT FROM 'chat' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a switch did not keep path_previous or map Relationship to Chat: %', v_res;
  END IF;
  IF (SELECT relationship_status FROM public.profiles WHERE id = v_me) IS DISTINCT FROM 'figuring_it_out' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: relationship_status was re-synced on a switch (D14)';
  END IF;
  IF pg_temp.metric('path_switch_7d:just_me>relationship') <> v_switch_before + 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a switch within 7 days was not counted';
  END IF;

  -- Cancel the invite and go back where they came from (Q7).
  INSERT INTO public.relationships (id, user_a, status, invite_code, invite_expires_at)
  VALUES ('5f1a0000-0000-0000-0000-000000000107', v_me, 'pending', 'W1PND7', now() + interval '7 days');
  PERFORM pg_temp.as_user(v_me);
  IF public.withdraw_my_pending_invites(true) <> 1 THEN
    RESET ROLE;
    RAISE EXCEPTION 'CONTRACT VIOLATED: withdraw did not remove the pending invite';
  END IF;
  RESET ROLE;
  IF (SELECT path FROM public.users WHERE id = v_me) IS DISTINCT FROM 'just_me'
     OR (SELECT path_previous FROM public.users WHERE id = v_me) IS DISTINCT FROM 'relationship' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: withdraw-with-return did not restore the previous path';
  END IF;
END $$;

-- G3. Review Focus 4: cancelling with no previous path keeps Relationship.
DO $$
DECLARE
  v_me constant uuid := '5f1a0000-0000-0000-0000-000000000031';
  v_home jsonb;
BEGIN
  PERFORM pg_temp.as_user(v_me);
  IF public.withdraw_my_pending_invites(true) <> 1 THEN
    RESET ROLE;
    RAISE EXCEPTION 'CONTRACT VIOLATED: withdraw did not remove the first-time inviter''s invite';
  END IF;
  RESET ROLE;
  v_home := pg_temp.home_of(v_me);
  IF v_home ->> 'path' IS DISTINCT FROM 'relationship' OR v_home -> 'link' ->> 'state' IS DISTINCT FROM 'none'
     OR v_home ->> 'tab' IS DISTINCT FROM 'chat' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: cancelling with no previous path left %', v_home;
  END IF;
END $$;

-- G4. get_my_home_state: link states, partner names, tab, needs, hold, dating.
DO $$
DECLARE
  v jsonb;
BEGIN
  -- Review Focus 3: a legacy linked member with no path keeps Chat.
  v := pg_temp.home_of('5f1a0000-0000-0000-0000-000000000023');
  IF v -> 'link' ->> 'state' IS DISTINCT FROM 'linked' OR v -> 'link' ->> 'partner_first_name' IS DISTINCT FROM 'Kojo'
     OR v ->> 'tab' IS DISTINCT FROM 'chat' OR v -> 'needs' IS DISTINCT FROM '["path"]'::jsonb
     OR v -> 'link' ->> 'relationship_id' IS DISTINCT FROM '5f1a0000-0000-0000-0000-000000000101' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: linked (legacy, no path): %', v;
  END IF;
  v := pg_temp.home_of('5f1a0000-0000-0000-0000-000000000024');
  IF v -> 'link' ->> 'state' IS DISTINCT FROM 'linked' OR v ->> 'tab' IS DISTINCT FROM 'chat'
     OR v -> 'link' ->> 'partner_first_name' IS DISTINCT FROM 'Adwoa' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: linked: %', v;
  END IF;
  -- A phone stored as a name is never shown.
  v := pg_temp.home_of('5f1a0000-0000-0000-0000-000000000025');
  IF v -> 'link' ->> 'state' IS DISTINCT FROM 'paused' OR v -> 'link' -> 'partner_first_name' IS DISTINCT FROM 'null'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: paused: %', v;
  END IF;
  v := pg_temp.home_of('5f1a0000-0000-0000-0000-000000000026');
  IF v -> 'needs' IS DISTINCT FROM '["name"]'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a phone stored as a name did not need a name: %', v;
  END IF;
  v := pg_temp.home_of('5f1a0000-0000-0000-0000-000000000027');
  IF v -> 'link' ->> 'state' IS DISTINCT FROM 'ended_window'
     OR (v -> 'link' ->> 'window_ends_at')::timestamptz
        IS DISTINCT FROM (SELECT ended_at + interval '30 days' FROM public.relationships
                           WHERE id = '5f1a0000-0000-0000-0000-000000000103') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: ended inside the window: %', v;
  END IF;
  v := pg_temp.home_of('5f1a0000-0000-0000-0000-000000000029');
  IF v -> 'link' ->> 'state' IS DISTINCT FROM 'after_ending' OR v -> 'link' -> 'window_ends_at' IS DISTINCT FROM 'null'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: ended after the window: %', v;
  END IF;
  INSERT INTO public.relationships (id, user_a, status, invite_code, invite_expires_at)
  VALUES ('5f1a0000-0000-0000-0000-000000000108', '5f1a0000-0000-0000-0000-000000000033', 'pending', 'W1PND8',
          now() + interval '7 days');
  v := pg_temp.home_of('5f1a0000-0000-0000-0000-000000000033');
  IF v -> 'link' ->> 'state' IS DISTINCT FROM 'pending' OR v -> 'link' -> 'invite_expires_at' = 'null'::jsonb
     OR v -> 'link' -> 'partner_first_name' IS DISTINCT FROM 'null'::jsonb OR v ->> 'tab' IS DISTINCT FROM 'me' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: pending (on Just for me): %', v;
  END IF;
  DELETE FROM public.relationships WHERE id = '5f1a0000-0000-0000-0000-000000000108';
  v := pg_temp.home_of('5f1a0000-0000-0000-0000-000000000033');
  IF v -> 'link' ->> 'state' IS DISTINCT FROM 'none' OR v -> 'link' -> 'relationship_id' IS DISTINCT FROM 'null'::jsonb
     OR v ->> 'tab' IS DISTINCT FROM 'me' OR (v ->> 'hold')::boolean
     OR v -> 'dating' IS DISTINCT FROM jsonb_build_object('enabled', public.dating_flag_enabled('dating_mode_enabled'), 'enrolled', false) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: none: %', v;
  END IF;
  v := pg_temp.home_of('5f1a0000-0000-0000-0000-000000000034');
  IF NOT (v ->> 'hold')::boolean THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an unresolved hold was not reported: %', v;
  END IF;
  v := pg_temp.home_of('5f1a0000-0000-0000-0000-000000000036');
  IF NOT (v -> 'dating' ->> 'enrolled')::boolean OR v ->> 'tab' IS DISTINCT FROM 'me' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a Dating enrollment was not summarised: %', v;
  END IF;
  v := pg_temp.home_of('5f1a0000-0000-0000-0000-000000000035');
  IF v -> 'needs' IS DISTINCT FROM '["consent", "path"]'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a v1 consent did not need consent: %', v;
  END IF;
  v := pg_temp.home_of('5f1a0000-0000-0000-0000-000000000022');
  IF (v ->> 'has_account')::boolean OR v -> 'needs' IS DISTINCT FROM '["consent", "birth_date", "name", "path"]'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: no account: %', v;
  END IF;
END $$;

-- G5. D18: Spec 1 pauses Dating only on a change to Relationship, exactly once.
DO $$
DECLARE
  v_dating constant uuid := '5f1a0000-0000-0000-0000-000000000032';
  v_def constant text := pg_get_functiondef('public.pause_dating_for_relationship_user(uuid)'::regprocedure);
  v_msg text;
BEGIN
  PERFORM set_config('w1.pause_calls', '0', true);
  EXECUTE $spy$
    CREATE OR REPLACE FUNCTION public.pause_dating_for_relationship_user(p_user_id uuid)
    RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $body$
    BEGIN
      PERFORM set_config('w1.pause_calls',
        (coalesce(nullif(current_setting('w1.pause_calls', true), ''), '0')::int + 1)::text, true);
    END
    $body$
  $spy$;

  PERFORM pg_temp.as_user(v_dating);
  PERFORM public.set_my_path('just_me');
  RESET ROLE;
  IF current_setting('w1.pause_calls') <> '0' THEN
    EXECUTE v_def;
    RAISE EXCEPTION 'CONTRACT VIOLATED: Dating -> Just for me called the Dating pause (Spec 2 W2 owns that, D18)';
  END IF;

  UPDATE public.users SET path = 'dating' WHERE id = v_dating;
  PERFORM pg_temp.as_user(v_dating);
  v_msg := pg_temp.error_of($q$SELECT public.set_my_path('relationship')$q$);
  RESET ROLE;
  IF v_msg IS DISTINCT FROM 'path:confirm_pause_dating' OR current_setting('w1.pause_calls') <> '0' THEN
    EXECUTE v_def;
    RAISE EXCEPTION 'CONTRACT VIOLATED: an unconfirmed Dating -> Relationship gave % with % pause call(s)',
      coalesce(v_msg, 'no error'), current_setting('w1.pause_calls');
  END IF;

  PERFORM pg_temp.as_user(v_dating);
  PERFORM public.set_my_path('relationship', true);
  RESET ROLE;
  IF current_setting('w1.pause_calls') <> '1' THEN
    EXECUTE v_def;
    RAISE EXCEPTION 'CONTRACT VIOLATED: Dating -> Relationship made % pause call(s), expected exactly 1',
      current_setting('w1.pause_calls');
  END IF;
  EXECUTE v_def;
END $$;

-- G6. D18 with the real pause: Relationship pauses Dating; Just for me doesn't.
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
END $$;

-- G7. Effective flags (§2.5): a flag is on only with everything it needs.
DO $$
BEGIN
  INSERT INTO public.feature_flags (key, enabled) VALUES
    ('flow_signin_v2', false), ('flow_paths_v2', true), ('flow_couples_v2', true), ('couple_profile', true)
  ON CONFLICT (key) DO UPDATE SET enabled = EXCLUDED.enabled;
  IF private.spec1_flag_on('flow_paths_v2') OR private.spec1_flag_on('flow_couples_v2')
     OR private.spec1_flag_on('couple_profile') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a flag was effective without flow_signin_v2';
  END IF;
  UPDATE public.feature_flags SET enabled = true WHERE key = 'flow_signin_v2';
  IF NOT (private.spec1_flag_on('flow_paths_v2') AND private.spec1_flag_on('flow_couples_v2')
          AND private.spec1_flag_on('couple_profile')) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the whole chain on did not read on';
  END IF;
  UPDATE public.feature_flags SET enabled = false WHERE key = 'flow_paths_v2';
  IF private.spec1_flag_on('flow_couples_v2') OR private.spec1_flag_on('couple_profile')
     OR NOT private.spec1_flag_on('flow_signin_v2') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a flag stayed effective after what it needs went off';
  END IF;
  IF private.spec1_flag_on('no_such_spec1_flag') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a missing flag read as on';
  END IF;
  UPDATE public.feature_flags SET enabled = false
   WHERE key IN ('flow_signin_v2', 'flow_paths_v2', 'flow_couples_v2', 'couple_profile');
END $$;
```

- [ ] **Step 2: Run it to verify it fails**

```bash
cd /Users/user/attune
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/identity_foundation_contracts.sql; echo "exit=$?"
```
Expected: `ERROR:  CONTRACT VIOLATED: W1b path objects are missing (set_my_path, get_my_home_state, set_user_path_internal)`, `exit=3`.

- [ ] **Step 3: Write the failing Dart test for the dropped column**

In `test/features/onboarding/onboarding_submission_service_test.dart`, insert this test immediately before the file's last line `}` (leave one blank line after the previous test's `);`):

```dart
  test(
    'onboarding_profiles is sent without the dropped mode column (W1b)',
    () async {
      final (client, requests) = await _client();
      addTearDown(client.dispose);

      await OnboardingSubmissionService(client: client).submit(
        mode: OnboardingMode.couples,
        displayName: 'Ama',
        attachmentAnswers: const [3, 4],
        anchors: const ['rest'],
      );

      final body = _body(_to(requests, 'onboarding_profiles'));
      expect(body.containsKey('mode'), isFalse);
      expect(body['user_id'], _me);
      expect(body['attachment_answers'], [3, 4]);
      expect(body['anchors'], ['rest']);
      expect(body['completed_at'], isA<String>());
    },
  );
```

```bash
cd /Users/user/attune
flutter test --no-pub test/features/onboarding/onboarding_submission_service_test.dart 2>&1 | tr '\r' '\n' | grep -E "Expected: false|All tests passed|Some tests failed" | tail -2
```
Expected: `Expected: false` (the body still has `mode`) and `Some tests failed.`

- [ ] **Step 4: Write the migration**

Create `supabase/migrations/20261025100300_paths_and_home_state.sql` with exactly (no function body in it may mention a later wave's table, even in a comment: the I-6 scan reads `prosrc`):

```sql
-- Spec 1 W1b, migration 4 of 6 (spec §4.7 #4): paths_and_home_state.
--   * private.spec1_flag_on: the effective Spec 1 flag (§2.5 dependencies);
--     a missing row is off. W1c inserts the rows.
--   * private.dating_home_summary: {enabled, enrolled}, the seam Spec 2 W1b
--     re-creates; no client reads a Dating table for this (I-4, A-10).
--   * set_user_path_internal: the single path writer. It pauses Dating only
--     on a change to relationship (D18); any other change away from Dating
--     is paused by Spec 2 W2's users.path trigger. It names no table a later
--     wave creates (I-6): W5 re-creates it from this live body.
--   * set_my_path, get_my_home_state, and withdraw_my_pending_invites with a
--     return-to-previous-path variant.
--   * onboarding_profiles.mode is dropped: no SQL reader, no fixture; the
--     legacy client stops writing it in the same release.
-- Grants in 20261025100310_paths_and_home_state_grants.sql.
BEGIN;
SET LOCAL lock_timeout = '5s';

ALTER TABLE public.onboarding_profiles DROP COLUMN IF EXISTS mode;

CREATE OR REPLACE FUNCTION private.spec1_flag_on(p_key text)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_on boolean;
  v_needs text;
BEGIN
  SELECT f.enabled INTO v_on FROM public.feature_flags AS f WHERE f.key = p_key;
  IF NOT coalesce(v_on, false) THEN
    RETURN false;
  END IF;
  v_needs := CASE p_key
               WHEN 'flow_paths_v2' THEN 'flow_signin_v2'
               WHEN 'flow_couples_v2' THEN 'flow_paths_v2'
               WHEN 'couple_profile' THEN 'flow_couples_v2'
             END;
  RETURN v_needs IS NULL OR private.spec1_flag_on(v_needs);
END;
$$;

CREATE OR REPLACE FUNCTION private.dating_home_summary(p_user uuid)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT jsonb_build_object(
    'enabled', public.dating_flag_enabled('dating_mode_enabled'),
    'enrolled', EXISTS (
      SELECT 1 FROM public.dating_enrollments AS e
       WHERE e.user_id = p_user
         AND e.state IN ('profile_draft', 'active', 'paused', 'suspended')));
$$;

CREATE OR REPLACE FUNCTION public.set_user_path_internal(p_user uuid, p_path text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_old text;
  v_chosen_at timestamptz;
  v_elapsed interval;
BEGIN
  IF p_path IS NULL OR p_path NOT IN ('relationship', 'dating', 'just_me') THEN
    RAISE EXCEPTION 'path:invalid';
  END IF;
  SELECT u.path, u.path_chosen_at INTO v_old, v_chosen_at
    FROM public.users AS u WHERE u.id = p_user FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'path:no_account';
  END IF;
  IF v_old IS NOT DISTINCT FROM p_path THEN RETURN; END IF;

  UPDATE public.users
     SET path_previous = v_old,
         path = p_path,
         path_chosen_at = now()
   WHERE id = p_user;

  IF v_old IS NULL THEN
    INSERT INTO public.onboarding_profiles (user_id) VALUES (p_user)
    ON CONFLICT (user_id) DO NOTHING;
    -- Written once, at the first choice, and never re-synced (D14).
    INSERT INTO public.profiles AS p (id, relationship_status)
    VALUES (p_user, CASE p_path WHEN 'relationship' THEN 'taken'
                                WHEN 'dating' THEN 'single'
                                ELSE 'figuring_it_out' END)
    ON CONFLICT (id) DO UPDATE SET relationship_status = EXCLUDED.relationship_status;
    PERFORM private.bump_metric_internal('path_chosen:' || p_path);
  ELSE
    v_elapsed := now() - coalesce(v_chosen_at, now());
    IF v_elapsed <= interval '7 days' THEN
      PERFORM private.bump_metric_internal('path_switch_7d:' || v_old || '>' || p_path);
    ELSIF v_elapsed <= interval '30 days' THEN
      PERFORM private.bump_metric_internal('path_switch_30d:' || v_old || '>' || p_path);
    END IF;
  END IF;

  -- The one Dating pause Spec 1 makes (D18).
  IF p_path = 'relationship'
     AND (private.dating_home_summary(p_user) ->> 'enrolled')::boolean THEN
    PERFORM public.pause_dating_for_relationship_user(p_user);
  END IF;
END;
$$;

-- The home's one read (spec §3.11, §3.15, §5.3).
CREATE OR REPLACE FUNCTION public.get_my_home_state()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid constant uuid := auth.uid();
  v_user public.users%ROWTYPE;
  v_has_account boolean;
  v_needs text[] := ARRAY[]::text[];
  v_rel public.relationships%ROWTYPE;
  v_state text := 'none';
  v_partner_name text;
  v_tab text;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'home:not_signed_in';
  END IF;
  SELECT * INTO v_user FROM public.users AS u WHERE u.id = v_uid;
  v_has_account := FOUND;

  IF NOT v_has_account
     OR coalesce(nullif(regexp_replace(coalesce(v_user.eula_version, ''), '[^0-9]', '', 'g'), '')::integer, 0) < 2 THEN
    v_needs := array_append(v_needs, 'consent');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.account_birthdates AS b WHERE b.user_id = v_uid) THEN
    v_needs := array_append(v_needs, 'birth_date');
  END IF;
  IF NOT v_has_account OR coalesce(btrim(v_user.display_name), '') ~ '^\+?[0-9 ()-]*$' THEN
    v_needs := array_append(v_needs, 'name');
  END IF;
  IF v_user.path IS NULL THEN
    v_needs := array_append(v_needs, 'path');
  END IF;

  SELECT * INTO v_rel FROM public.relationships AS r
   WHERE v_uid IN (r.user_a, r.user_b)
   ORDER BY r.created_at DESC, r.id DESC
   LIMIT 1;
  IF FOUND THEN
    v_state := CASE
      WHEN v_rel.status = 'pending' THEN 'pending'
      WHEN v_rel.status = 'active' THEN 'linked'
      WHEN v_rel.status = 'paused' THEN 'paused'
      WHEN v_rel.status = 'ended' AND public.relationship_chat_open_for(v_rel.id, v_uid) THEN 'ended_window'
      ELSE 'after_ending'
    END;
    IF v_state <> 'pending' THEN
      -- A name, never a phone number (the lifecycle RPC's guard).
      SELECT CASE WHEN split_part(btrim(p.display_name), ' ', 1) ~ '^\+?[0-9 ()-]*$' THEN NULL
                  ELSE split_part(btrim(p.display_name), ' ', 1) END
        INTO v_partner_name
        FROM public.users AS p
       WHERE p.id = CASE WHEN v_rel.user_a = v_uid THEN v_rel.user_b ELSE v_rel.user_a END;
    END IF;
  END IF;

  -- Chat on the Relationship path. A legacy account that has not chosen a
  -- path yet keeps Chat while its latest relationship is pending, linked or
  -- paused, so the v2 shell never moves a couple onto Me before A6.
  v_tab := CASE
    WHEN v_user.path = 'relationship' THEN 'chat'
    WHEN v_user.path IS NULL AND v_state IN ('pending', 'linked', 'paused') THEN 'chat'
    ELSE 'me'
  END;

  RETURN jsonb_build_object(
    'has_account', v_has_account,
    'path', v_user.path,
    'tab', v_tab,
    'path_previous', v_user.path_previous,
    'needs', to_jsonb(v_needs),
    'hold', EXISTS (SELECT 1 FROM public.account_holds AS h
                     WHERE h.user_id = v_uid AND h.resolved_at IS NULL),
    'eula_version', v_user.eula_version,
    'dating', private.dating_home_summary(v_uid),
    'link', jsonb_build_object(
      'state', v_state,
      'relationship_id', CASE WHEN v_state = 'none' THEN NULL ELSE v_rel.id END,
      'partner_first_name', v_partner_name,
      'invite_expires_at', CASE WHEN v_state = 'pending' THEN v_rel.invite_expires_at END,
      'window_ends_at', CASE WHEN v_state = 'ended_window' THEN v_rel.ended_at + interval '30 days' END));
END;
$$;

-- The return-to-previous variant (spec §4.3 W1b). The zero-argument
-- withdraw_my_pending_invites() stays exactly as it is: the app calls it,
-- invite_age_contracts.sql names it, and scripts/local_pg_grants.sql replays
-- its grants. This overload has no default, so a call without arguments
-- still resolves to the original.
CREATE OR REPLACE FUNCTION public.withdraw_my_pending_invites(p_return_to_previous_path boolean)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid constant uuid := auth.uid();
  v_n integer;
  v_path text;
  v_previous text;
BEGIN
  v_n := public.withdraw_my_pending_invites();
  IF p_return_to_previous_path AND v_n > 0 THEN
    SELECT u.path, u.path_previous INTO v_path, v_previous
      FROM public.users AS u WHERE u.id = v_uid;
    IF v_path = 'relationship' AND v_previous IS NOT NULL AND v_previous <> 'relationship' THEN
      PERFORM public.set_user_path_internal(v_uid, v_previous);
    END IF;
  END IF;
  RETURN v_n;
END;
$$;

-- A6 and Settings -> How you use Attune (spec §3.7, §3.12).
CREATE OR REPLACE FUNCTION public.set_my_path(p_path text, p_confirmed boolean DEFAULT false)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid constant uuid := auth.uid();
  v_current text;
  v_eula text;
  v_age integer;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'path:not_signed_in';
  END IF;
  IF p_path IS NULL OR p_path NOT IN ('relationship', 'dating', 'just_me') THEN
    RAISE EXCEPTION 'path:invalid';
  END IF;
  SELECT u.path, u.eula_version INTO v_current, v_eula FROM public.users AS u WHERE u.id = v_uid;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'path:needs_signup';
  END IF;
  v_age := public.account_age(v_uid);
  IF v_age IS NULL OR v_age < 18 THEN
    RAISE EXCEPTION 'path:needs_signup';
  END IF;
  IF private.spec1_flag_on('flow_signin_v2') AND v_eula IS DISTINCT FROM '2' THEN
    RAISE EXCEPTION 'path:needs_signup';
  END IF;

  IF p_path <> 'relationship' THEN
    IF EXISTS (SELECT 1 FROM public.relationships AS r
                WHERE v_uid IN (r.user_a, r.user_b) AND r.status IN ('active', 'paused')) THEN
      RAISE EXCEPTION 'path:relationship_open';
    END IF;
    IF EXISTS (SELECT 1 FROM public.relationships AS r
                WHERE r.user_a = v_uid AND r.status = 'pending' AND r.user_b IS NULL) THEN
      IF NOT p_confirmed THEN
        RAISE EXCEPTION 'path:confirm_withdraw';
      END IF;
      PERFORM public.withdraw_my_pending_invites();
    END IF;
  ELSIF v_current IS DISTINCT FROM 'relationship'
        AND (private.dating_home_summary(v_uid) ->> 'enrolled')::boolean
        AND NOT p_confirmed THEN
    RAISE EXCEPTION 'path:confirm_pause_dating';
  END IF;

  PERFORM public.set_user_path_internal(v_uid, p_path);
  RETURN public.get_my_home_state();
END;
$$;

COMMIT;
```

- [ ] **Step 5: Write the grants twin**

Create `supabase/migrations/20261025100310_paths_and_home_state_grants.sql` with exactly:

```sql
-- Spec 1 W1b: grants for 20261025100300_paths_and_home_state.sql. The path
-- writer and both seams are server-only; the three RPCs are the app's.
BEGIN;
REVOKE ALL ON FUNCTION private.spec1_flag_on(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.dating_home_summary(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.set_user_path_internal(uuid, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.get_my_home_state() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.set_my_path(text, boolean) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.withdraw_my_pending_invites(boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_my_home_state() TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_my_path(text, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.withdraw_my_pending_invites(boolean) TO authenticated;
COMMIT;
```

- [ ] **Step 6: Stop the client writing `onboarding_profiles.mode` (same release as the drop)**

In `lib/features/onboarding/data/onboarding_submission_service.dart`, replace exactly:

```dart
    final modeName = mode.remoteModeName;
    final relationshipStatus = _relationshipStatusForMode(mode);
```

with:

```dart
    final relationshipStatus = _relationshipStatusForMode(mode);
```

Then replace exactly:

```dart
            'user_id': user.id,
            'mode': modeName,
            'attachment_answers': attachmentAnswers,
```

with:

```dart
            // Spec 1 W1b: onboarding_profiles.mode is dropped with this release.
            'user_id': user.id,
            'attachment_answers': attachmentAnswers,
```

- [ ] **Step 7: Apply both twice, then run the contract and the Dart test**

```bash
cd /Users/user/attune
for i in 1 2; do
  psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/migrations/20261025100300_paths_and_home_state.sql; echo "migration exit=$?"
  psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/migrations/20261025100310_paths_and_home_state_grants.sql; echo "grants exit=$?"
done
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/identity_foundation_contracts.sql; echo "exit=$?"
flutter test --no-pub test/features/onboarding/onboarding_submission_service_test.dart 2>&1 | tr '\r' '\n' | grep -E "All tests passed|Some tests failed" | tail -1
dart format test/features/onboarding/onboarding_submission_service_test.dart
```
Expected: four `… exit=0` (the second pass prints `NOTICE: column "mode" of relation "onboarding_profiles" does not exist, skipping`); `exit=0` with no `ERROR`; `… All tests passed!`; `Formatted 1 file (0 changed)`.

- [ ] **Step 8: Mutation check (spec §7.4 I-6: the W5 draft delete in the W1 body)**

```bash
cd /Users/user/attune
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a <<'SQL'; echo "exit=$?"
BEGIN;
SELECT replace(pg_get_functiondef('public.set_user_path_internal(uuid,text)'::regprocedure),
  'IF v_old IS NOT DISTINCT FROM p_path THEN RETURN; END IF;',
  'IF v_old IS NOT DISTINCT FROM p_path THEN RETURN; END IF; IF p_path = ''dating'' THEN DELETE FROM public.couple_profile_drafts AS d WHERE d.user_id = p_user; END IF;') \gexec
DO $$ BEGIN
  IF position('couple_profile_drafts' IN pg_get_functiondef('public.set_user_path_internal(uuid,text)'::regprocedure)) = 0 THEN
    RAISE EXCEPTION 'MUTANT NOT APPLIED';
  END IF;
END $$;
\i supabase/tests/identity_foundation_contracts.sql
SQL
```
Expected: `ERROR:  CONTRACT VIOLATED: a W1 function names a later wave's table (I-6): set_user_path_internal(uuid,text)`, `exit=3`.

- [ ] **Step 9: Add the twin to the local harness (edit only)**

Append to the end of `scripts/local_pg_grants.sql`:

```sql

-- Spec 1 W1b: the path writer and both seams are server-only; the home RPCs.
\i supabase/migrations/20261025100310_paths_and_home_state_grants.sql
```

- [ ] **Step 10: Run tests**

```bash
cd /Users/user/attune
for t in identity_foundation_contracts invite_age_contracts relationship_lifecycle_contracts dating_mode_contracts ask2_state_test ask2_eligibility_test data_export_contracts; do
  psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/$t.sql >/dev/null 2>&1; echo "$t exit=$?"
done
grep -E 'invite_age|relationship_lifecycle_contracts|dating_mode|ask2_|data_export' .superpowers/sdd/2026-10-25-spec1-w1/sql-baseline.txt
flutter test --no-pub test/features/onboarding 2>&1 | tr '\r' '\n' | grep -E "All tests passed|Some tests failed" | tail -1
```
Expected: `identity_foundation_contracts exit=0`; the others exactly as in the baseline (`invite_age_contracts` still finds `withdraw_my_pending_invites()`; `ask2_*` and `data_export` read `onboarding_profiles` without `mode`); `… All tests passed!`.

---

### Task 8: The `HomeState` model and its tab-layout-only cache (W1b; D20, C-5); W1b gate

**Files:**
- Create: `lib/features/onboarding/domain/home_state.dart`
- Create: `lib/features/onboarding/data/home_state_store.dart`
- Create: `test/features/onboarding/home_state_test.dart`
- Create: `test/features/onboarding/home_state_store_test.dart`

**Interfaces:**
- Consumes: the `get_my_home_state()` JSON shape (Task 7).
- Produces (W3a's `homeStateProvider` builds on these): `enum AppPath { relationship, dating, justMe }` (`wire`, `fromWire(Object?) → AppPath?`); `enum AppTab { chat, me }` (`fromWire(Object?) → AppTab`, unknown → `me`; `forPath(AppPath) → AppTab`); `enum LinkState { none, pending, linked, paused, endedWindow, afterEnding }` (`fromWire`, unknown → `none`); `enum HomeNeed { consent, birthDate, name, path }` (`fromWire`, `listFromWire(Object?) → List<HomeNeed>`); `class HomeLink { state, relationshipId, partnerFirstName, inviteExpiresAt, windowEndsAt; static none; HomeLink.fromJson(Object?) }`; `class DatingSummary { enabled, enrolled; static off; DatingSummary.fromJson(Object?) }`; `class HomeState { hasAccount, path, tab, pathPrevious, needs, hold, eulaVersion, dating, link; bool get isComplete; HomeState.fromJson(Map<String, dynamic>) }`; `class CachedHomeState { tab, link, needs, hold, at; isComplete }`; `class HomeStateStore(SharedPreferences, {required String userId, DateTime Function()? now})` with `static String keyFor(String userId)` = `attune.home.<uid>.state`, `CachedHomeState? read()`, `Future<void> write(HomeState)`, `Future<void> clear()`. The cache never holds the path or the Dating summary.

- [ ] **Step 1: Write the failing tests**

Create `test/features/onboarding/home_state_test.dart` with exactly:

```dart
// Spec 1 W1b (§5.1, §7.3): the HomeState model parses get_my_home_state()
// exactly as the SQL contract pins it, and maps paths and link states.
import 'package:attune/features/onboarding/domain/home_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses a full server answer', () {
    final state = HomeState.fromJson({
      'has_account': true,
      'path': 'relationship',
      'tab': 'chat',
      'path_previous': 'just_me',
      'needs': <String>[],
      'hold': false,
      'eula_version': '2',
      'dating': {'enabled': true, 'enrolled': false},
      'link': {
        'state': 'ended_window',
        'relationship_id': '5f1a0000-0000-0000-0000-000000000103',
        'partner_first_name': 'Kwabena',
        'invite_expires_at': null,
        'window_ends_at': '2026-11-22T09:00:00+00:00',
      },
    });
    expect(state.path, AppPath.relationship);
    expect(state.pathPrevious, AppPath.justMe);
    expect(state.tab, AppTab.chat);
    expect(state.isComplete, isTrue);
    expect(state.dating.enabled, isTrue);
    expect(state.dating.enrolled, isFalse);
    expect(state.link.state, LinkState.endedWindow);
    expect(state.link.partnerFirstName, 'Kwabena');
    expect(state.link.windowEndsAt, DateTime.utc(2026, 11, 22, 9));
    expect(state.link.inviteExpiresAt, isNull);
  });

  test('every link state and need round-trips its wire value', () {
    for (final state in LinkState.values) {
      expect(LinkState.fromWire(state.wire), state);
    }
    expect(
      HomeNeed.listFromWire(['consent', 'birth_date', 'name', 'path']),
      HomeNeed.values,
    );
    expect(AppPath.fromWire('just_me'), AppPath.justMe);
  });

  test('unknown or missing values fall to the safe side', () {
    final state = HomeState.fromJson({
      'tab': 'dating',
      'needs': ['consent', 'telepathy'],
      'link': {'state': 'married'},
    });
    expect(state.hasAccount, isFalse);
    expect(state.isComplete, isFalse);
    expect(state.path, isNull);
    expect(state.tab, AppTab.me);
    expect(state.needs, [HomeNeed.consent]);
    expect(state.hold, isFalse);
    expect(state.dating, same(DatingSummary.off));
    expect(state.link.state, LinkState.none);
  });

  test('path to tab: Relationship is Chat, Dating and Just for me are Me', () {
    expect(AppTab.forPath(AppPath.relationship), AppTab.chat);
    expect(AppTab.forPath(AppPath.dating), AppTab.me);
    expect(AppTab.forPath(AppPath.justMe), AppTab.me);
  });
}
```

Create `test/features/onboarding/home_state_store_test.dart` with exactly:

```dart
// Spec 1 W1b (§5.5, D20, controller ruling C-5): the home-state cache keeps
// the tab layout, link state, needs and hold only. Never the path, never
// anything about Dating, so Spec 2's S19 "no Dating data on disk" holds.
import 'dart:convert';

import 'package:attune/features/onboarding/data/home_state_store.dart';
import 'package:attune/features/onboarding/domain/home_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

HomeState _datingAnswer() => HomeState.fromJson({
  'has_account': true,
  'path': 'dating',
  'tab': 'me',
  'path_previous': 'just_me',
  'needs': ['birth_date'],
  'hold': true,
  'eula_version': '2',
  'dating': {'enabled': true, 'enrolled': true},
  'link': {'state': 'none'},
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  test('a Dating account caches me, and nothing that says dating', () async {
    final store = HomeStateStore(
      prefs,
      userId: 'u1',
      now: () => DateTime.utc(2026, 10, 25, 9),
    );
    await store.write(_datingAnswer());

    final raw = prefs.getString('attune.home.u1.state')!;
    expect(raw.toLowerCase(), isNot(contains('dating')));
    expect(raw, isNot(contains('just_me')));
    expect((jsonDecode(raw) as Map).keys.toSet(), {
      'tab',
      'link',
      'needs',
      'hold',
      'at',
    });

    final cached = store.read()!;
    expect(cached.tab, AppTab.me);
    expect(cached.link, LinkState.none);
    expect(cached.needs, [HomeNeed.birthDate]);
    expect(cached.hold, isTrue);
    expect(cached.isComplete, isFalse);
    expect(cached.at, DateTime.utc(2026, 10, 25, 9));
  });

  test(
    'scoped per account, cleared on demand, corrupt values dropped',
    () async {
      await HomeStateStore(prefs, userId: 'u1').write(_datingAnswer());
      expect(HomeStateStore(prefs, userId: 'u2').read(), isNull);

      await HomeStateStore(prefs, userId: 'u1').clear();
      expect(prefs.containsKey(HomeStateStore.keyFor('u1')), isFalse);

      await prefs.setString(HomeStateStore.keyFor('u3'), '{not json');
      expect(HomeStateStore(prefs, userId: 'u3').read(), isNull);
    },
  );
}
```

- [ ] **Step 2: Run them to verify they fail**

```bash
cd /Users/user/attune
flutter test --no-pub test/features/onboarding/home_state_test.dart test/features/onboarding/home_state_store_test.dart 2>&1 | tr '\r' '\n' | grep -E "Error: |Some tests failed" | head -2
```
Expected: `Error: Error when reading 'lib/features/onboarding/domain/home_state.dart': No such file or directory` (or the store's file).

- [ ] **Step 3: Write the model**

Create `lib/features/onboarding/domain/home_state.dart` with exactly:

```dart
import 'package:flutter/foundation.dart';

/// The three ways to use Attune (Spec 1 §1.1), as `users.path` stores them.
enum AppPath {
  relationship('relationship'),
  dating('dating'),
  justMe('just_me');

  const AppPath(this.wire);

  final String wire;

  static AppPath? fromWire(Object? value) {
    for (final path in values) {
      if (path.wire == value) return path;
    }
    return null;
  }
}

/// Tab 2's layout: Chat on the Relationship path, Me on Dating and Just for
/// me (Q6). The only path-derived value the phone may keep (D20).
enum AppTab {
  chat('chat'),
  me('me');

  const AppTab(this.wire);

  final String wire;

  /// Anything but `chat` is Me: an unknown value never opens Chat.
  static AppTab fromWire(Object? value) => value == 'chat' ? chat : me;

  /// The layout a path implies, for a locally made choice before the server
  /// answers (W3a). The server's `tab` always wins once it arrives.
  static AppTab forPath(AppPath path) =>
      path == AppPath.relationship ? chat : me;
}

/// The latest relationship, as get_my_home_state() reads it (spec §4.3).
enum LinkState {
  none('none'),
  pending('pending'),
  linked('linked'),
  paused('paused'),
  endedWindow('ended_window'),
  afterEnding('after_ending');

  const LinkState(this.wire);

  final String wire;

  static LinkState fromWire(Object? value) {
    for (final state in values) {
      if (state.wire == value) return state;
    }
    return none;
  }
}

/// What an account still lacks, in the order the gate asks (spec §3.15).
enum HomeNeed {
  consent('consent'),
  birthDate('birth_date'),
  name('name'),
  path('path');

  const HomeNeed(this.wire);

  final String wire;

  static HomeNeed? fromWire(Object? value) {
    for (final need in values) {
      if (need.wire == value) return need;
    }
    return null;
  }

  /// Known needs in server order; unknown ones are skipped.
  static List<HomeNeed> listFromWire(Object? value) => [
    if (value is List)
      for (final item in value)
        if (fromWire(item) case final need?) need,
  ];
}

@immutable
class HomeLink {
  const HomeLink({
    required this.state,
    this.relationshipId,
    this.partnerFirstName,
    this.inviteExpiresAt,
    this.windowEndsAt,
  });

  static const none = HomeLink(state: LinkState.none);

  final LinkState state;
  final String? relationshipId;

  /// A first name only, never a phone number (the server guards this).
  final String? partnerFirstName;
  final DateTime? inviteExpiresAt;
  final DateTime? windowEndsAt;

  factory HomeLink.fromJson(Object? json) {
    if (json is! Map) return none;
    DateTime? at(Object? value) =>
        value is String ? DateTime.tryParse(value) : null;
    return HomeLink(
      state: LinkState.fromWire(json['state']),
      relationshipId: json['relationship_id'] as String?,
      partnerFirstName: json['partner_first_name'] as String?,
      inviteExpiresAt: at(json['invite_expires_at']),
      windowEndsAt: at(json['window_ends_at']),
    );
  }
}

/// The Dating summary from the server seam private.dating_home_summary.
/// Held in memory only, never cached on the phone (D20).
@immutable
class DatingSummary {
  const DatingSummary({required this.enabled, required this.enrolled});

  static const off = DatingSummary(enabled: false, enrolled: false);

  final bool enabled;
  final bool enrolled;

  factory DatingSummary.fromJson(Object? json) =>
      json is Map
          ? DatingSummary(
            enabled: json['enabled'] == true,
            enrolled: json['enrolled'] == true,
          )
          : off;
}

/// One answer from get_my_home_state() (spec §4.3 W1b).
@immutable
class HomeState {
  const HomeState({
    required this.hasAccount,
    required this.path,
    required this.tab,
    required this.pathPrevious,
    required this.needs,
    required this.hold,
    required this.eulaVersion,
    required this.dating,
    required this.link,
  });

  final bool hasAccount;
  final AppPath? path;
  final AppTab tab;
  final AppPath? pathPrevious;
  final List<HomeNeed> needs;

  /// An unresolved account hold: the app shows H1 and nothing else.
  final bool hold;
  final String? eulaVersion;
  final DatingSummary dating;
  final HomeLink link;

  /// Onboarding is complete when nothing is missing (W3a's v2 gate).
  bool get isComplete => hasAccount && needs.isEmpty;

  factory HomeState.fromJson(Map<String, dynamic> json) => HomeState(
    hasAccount: json['has_account'] == true,
    path: AppPath.fromWire(json['path']),
    tab: AppTab.fromWire(json['tab']),
    pathPrevious: AppPath.fromWire(json['path_previous']),
    needs: HomeNeed.listFromWire(json['needs']),
    hold: json['hold'] == true,
    eulaVersion: json['eula_version'] as String?,
    dating: DatingSummary.fromJson(json['dating']),
    link: HomeLink.fromJson(json['link']),
  );
}
```

- [ ] **Step 4: Write the store**

Create `lib/features/onboarding/data/home_state_store.dart` with exactly:

```dart
import 'dart:convert';

import 'package:attune/features/onboarding/domain/home_state.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The last server home state, as the phone may keep it (spec §5.5, D20):
/// the tab layout, the link state, the needs and whether a hold is on.
/// Never the path, never anything about Dating: Dating and Just for me both
/// cache `me`.
@immutable
class CachedHomeState {
  const CachedHomeState({
    required this.tab,
    required this.link,
    required this.needs,
    required this.hold,
    required this.at,
  });

  final AppTab tab;
  final LinkState link;
  final List<HomeNeed> needs;
  final bool hold;
  final DateTime at;

  bool get isComplete => needs.isEmpty;
}

/// User-scoped cache under `attune.home.<uid>.state`, written only from a
/// server answer so a local value is never invented. Its sign-out wipe
/// entry (`spec1.home_state_cache`) is registered in W3a.
class HomeStateStore {
  HomeStateStore(
    this._prefs, {
    required String userId,
    DateTime Function()? now,
  }) : _userId = userId,
       _now = now ?? DateTime.now;

  final SharedPreferences _prefs;
  final String _userId;
  final DateTime Function() _now;

  static String keyFor(String userId) => 'attune.home.$userId.state';

  String get _key => keyFor(_userId);

  CachedHomeState? read() {
    final raw = _prefs.getString(_key);
    if (raw == null || raw.isEmpty) return null;
    try {
      final json = jsonDecode(raw);
      if (json is! Map<String, dynamic>) return null;
      final at = DateTime.tryParse(json['at'] as String? ?? '');
      if (at == null) return null;
      return CachedHomeState(
        tab: AppTab.fromWire(json['tab']),
        link: LinkState.fromWire(json['link']),
        needs: HomeNeed.listFromWire(json['needs']),
        hold: json['hold'] == true,
        at: at,
      );
    } catch (_) {
      // A corrupt cache is dropped; the next server answer rewrites it.
      return null;
    }
  }

  Future<void> write(HomeState state) => _prefs.setString(
    _key,
    jsonEncode({
      'tab': state.tab.wire,
      'link': state.link.state.wire,
      'needs': [for (final need in state.needs) need.wire],
      'hold': state.hold,
      'at': _now().toUtc().toIso8601String(),
    }),
  );

  Future<void> clear() => _prefs.remove(_key);
}
```

- [ ] **Step 5: Run the tests to verify they pass, and format the new files**

```bash
cd /Users/user/attune
flutter test --no-pub test/features/onboarding/home_state_test.dart test/features/onboarding/home_state_store_test.dart 2>&1 | tr '\r' '\n' | grep -E "All tests passed|Some tests failed" | tail -1
dart format lib/features/onboarding/domain/home_state.dart lib/features/onboarding/data/home_state_store.dart test/features/onboarding/home_state_test.dart test/features/onboarding/home_state_store_test.dart
flutter analyze --no-pub lib/features/onboarding test/features/onboarding 2>&1 | grep -E "^\s*(error|warning) " | head
```
Expected: `… All tests passed!`; `Formatted 4 files (0 changed)`; no `error`/`warning` line.

- [ ] **Step 6: W1b regression gate — SQL**

```bash
cd /Users/user/attune
for f in supabase/tests/*.sql; do
  if psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f "$f" >/dev/null 2>&1; then echo "PASS $(basename "$f")"; else echo "FAIL $(basename "$f")"; fi
done > .superpowers/sdd/2026-10-25-spec1-w1/sql-after-w1b.txt
comm -13 <(grep '^FAIL' .superpowers/sdd/2026-10-25-spec1-w1/sql-baseline.txt | sort) <(grep '^FAIL' .superpowers/sdd/2026-10-25-spec1-w1/sql-after-w1b.txt | sort)
grep identity_foundation .superpowers/sdd/2026-10-25-spec1-w1/sql-after-w1b.txt
```
Expected: the `comm` prints nothing; `PASS identity_foundation_contracts.sql`.

- [ ] **Step 7: W1b regression gate — Flutter**

```bash
cd /Users/user/attune
flutter test --no-pub 2>&1 | tr '\r' '\n' | grep -E 'All tests passed!|Some tests failed' | tail -1
flutter analyze --no-pub lib test > .superpowers/sdd/2026-10-25-spec1-w1/analyze-w1b.txt 2>&1
comm -13 .superpowers/sdd/2026-10-25-spec1-w1/analyze-errors-baseline.txt <(grep -E '^\s*error ' .superpowers/sdd/2026-10-25-spec1-w1/analyze-w1b.txt | sed -E 's/:[0-9]+:[0-9]+//' | sort -u)
```
Expected: `… All tests passed!`; the `comm` prints nothing.

- [ ] **Step 8: Run tests**

Steps 6–7 are this task's tests. W1b ships the `onboarding_profiles.mode` drop and the client that stops writing it together (Owner checklist item 1).

---

### Task 9: Environment, the production flag gate, flags and public config (W1c; R-6, R-7, A-6, D15)

**Files:**
- Create: `supabase/migrations/20261025100400_spec1_flags_and_public_config.sql`
- Create: `supabase/migrations/20261025100410_spec1_flags_and_public_config_grants.sql`
- Create: `supabase/sql/dev_enable_spec1_flags.sql`
- Modify: `supabase/tests/identity_foundation_contracts.sql` (insert section H before the final `ROLLBACK;`)
- Modify: `scripts/local_pg_grants.sql` (append)

**Interfaces:**
- Consumes: `private.spec1_flag_on(text)` (Task 7); existing `public.app_setting(text)` (Vault first, then the `app.settings.*` GUC; owner-only EXECUTE).
- Produces: `private.attune_environment() RETURNS text` (`development` when unset, empty or `development`; otherwise `production`); `public.get_attune_environment() RETURNS text` (service_role); `private.assert_development_project() RETURNS void` (raises `env:not_development` unless development and, when `supabase_url` is configured, it names `mrgjtyacrzfylawyzabm`); table `private.flag_production_gates (flag_key PK, gate, review_ref, recorded_by, recorded_at)` with ten gated rows (all Spec 1 flags but `flow_couples_v2`); trigger `feature_flags_production_gate` (BEFORE INSERT OR UPDATE on `public.feature_flags`) → `private.guard_flag_production_gate()` raising `flag:gate_evidence_required`; `public.record_flag_gate_evidence(p_flag text, p_review_ref text) RETURNS void` (service_role; `flag:review_ref_required`, `flag:not_gated`); `public.production_flag_violations() RETURNS SETOF text` (service_role); the eleven flag rows `flow_signin_v2, flow_paths_v2, flow_couples_v2, couple_profile, dormancy_rule, platform_age_signals, support_resources_v2, csam_hash_matching, opinions_safety_v1, journal_ai_insights, text_scale_v2` (false); table `public.app_public_config (key 'age_signal_storefronts'|'dating_open_countries', value jsonb array, updated_at)` seeded `["USA","BRA"]` and `["GH","GB"]`; `private.dating_open_countries() RETURNS text[]` (sorted; Spec 2 W1b re-creates it); `public.get_public_app_config() RETURNS jsonb` → `{flags:{flow_signin_v2, platform_age_signals, support_resources_v2, text_scale_v2}, config:{age_signal_storefronts, dating_open_countries}}` (anon, authenticated; effective flags). Task 12's `PublicAppConfig.fromJson` reads exactly this shape.

- [ ] **Step 1: Write the failing contract section**

In `supabase/tests/identity_foundation_contracts.sql`, insert immediately before the final line `ROLLBACK;`:

```sql
-- =====================================================================
-- H. Environment, production flag gate, public config (W1c; reviews R-6,
--    R-7, A-6, D15). The setting is changed only with set_config inside
--    this transaction; nothing here persists it.
-- =====================================================================
DO $$
BEGIN
  IF to_regprocedure('private.attune_environment()') IS NULL
     OR to_regprocedure('private.assert_development_project()') IS NULL
     OR to_regprocedure('public.get_public_app_config()') IS NULL
     OR to_regclass('private.flag_production_gates') IS NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: W1c environment objects are missing (attune_environment, assert_development_project, get_public_app_config)';
  END IF;
END $$;

DO $$
DECLARE
  v_bad text;
  v_msg text;
  v_cfg jsonb;
BEGIN
  -- I-6 for the W1c functions.
  SELECT string_agg(p.oid::regprocedure::text, ', ' ORDER BY p.oid::regprocedure::text) INTO v_bad
    FROM pg_proc p
   WHERE p.oid IN ('private.attune_environment()'::regprocedure,
                   'private.assert_development_project()'::regprocedure,
                   'private.guard_flag_production_gate()'::regprocedure,
                   'private.dating_open_countries()'::regprocedure,
                   'public.get_public_app_config()'::regprocedure,
                   'public.record_flag_gate_evidence(text,text)'::regprocedure,
                   'public.production_flag_violations()'::regprocedure)
     AND p.prosrc ~* '(couple_profiles|couple_profile_drafts|journal_reminder_settings|otp_delivery_intents|invite_preview_attempts|account_activity|fresh_start_challenges|auth_hook_failures|parked_phone_hmac|child_safety_reports|country_safety_config)';
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a W1 function names a later wave''s table (I-6): %', v_bad;
  END IF;

  -- Privileges: only get_public_app_config reaches anon.
  IF has_function_privilege('anon', 'public.get_attune_environment()', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.get_attune_environment()', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.record_flag_gate_evidence(text,text)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.production_flag_violations()', 'EXECUTE')
     OR has_function_privilege('authenticated', 'private.attune_environment()', 'EXECUTE')
     OR has_function_privilege('authenticated', 'private.assert_development_project()', 'EXECUTE')
     OR has_table_privilege('anon', 'public.app_public_config', 'SELECT')
     OR has_table_privilege('authenticated', 'public.app_public_config', 'SELECT')
     OR NOT has_function_privilege('anon', 'public.get_public_app_config()', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.get_public_app_config()', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'public.get_attune_environment()', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: environment and config grants are wrong';
  END IF;

  -- private.attune_environment(): unset or development -> development; a typo fails closed.
  PERFORM set_config('app.settings.attune_environment', '', true);
  IF private.attune_environment() <> 'development' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an unset environment did not read development';
  END IF;
  PERFORM set_config('app.settings.attune_environment', 'production', true);
  IF private.attune_environment() <> 'production' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: production did not read production';
  END IF;
  PERFORM set_config('app.settings.attune_environment', 'prodution', true);
  IF private.attune_environment() <> 'production' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a typo did not fail closed to production';
  END IF;
  PERFORM set_config('app.settings.attune_environment', 'development', true);
  IF private.attune_environment() <> 'development' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: development did not read development';
  END IF;

  -- The dev-script guard.
  PERFORM set_config('app.settings.attune_environment', 'production', true);
  v_msg := pg_temp.error_of('SELECT private.assert_development_project()');
  IF v_msg IS DISTINCT FROM 'env:not_development' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the dev guard passed in production (got %)', coalesce(v_msg, 'no error');
  END IF;
  PERFORM set_config('app.settings.attune_environment', '', true);
  PERFORM set_config('app.settings.supabase_url', 'https://abcdefghijklmnopqrst.supabase.co', true);
  v_msg := pg_temp.error_of('SELECT private.assert_development_project()');
  IF v_msg IS DISTINCT FROM 'env:not_development' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the dev guard passed on another project (got %)', coalesce(v_msg, 'no error');
  END IF;
  PERFORM set_config('app.settings.supabase_url', 'https://mrgjtyacrzfylawyzabm.supabase.co', true);
  PERFORM private.assert_development_project();
  PERFORM set_config('app.settings.supabase_url', '', true);
  PERFORM private.assert_development_project();

  -- The eleven flags exist, off; ten carry a gate (flow_couples_v2 has none).
  IF (SELECT count(*) FROM public.feature_flags
       WHERE key IN ('flow_signin_v2', 'flow_paths_v2', 'flow_couples_v2', 'couple_profile', 'dormancy_rule',
                     'platform_age_signals', 'support_resources_v2', 'csam_hash_matching',
                     'opinions_safety_v1', 'journal_ai_insights', 'text_scale_v2')
         AND NOT enabled) <> 11 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the eleven Spec 1 flags are not all present and off';
  END IF;
  IF (SELECT count(*) FROM private.flag_production_gates WHERE review_ref IS NULL) < 10
     OR EXISTS (SELECT 1 FROM private.flag_production_gates WHERE flag_key = 'flow_couples_v2')
     OR NOT EXISTS (SELECT 1 FROM private.flag_production_gates WHERE flag_key = 'journal_ai_insights') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the production gate rows are wrong';
  END IF;

  -- The gate: nothing in development; a gated enable needs evidence in production.
  UPDATE public.feature_flags SET enabled = true WHERE key = 'journal_ai_insights';
  PERFORM set_config('app.settings.attune_environment', 'production', true);
  IF NOT EXISTS (SELECT 1 FROM public.production_flag_violations() AS v WHERE v = 'journal_ai_insights') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: production_flag_violations missed a gated flag that is on';
  END IF;
  UPDATE public.feature_flags SET enabled = false WHERE key = 'journal_ai_insights';
  v_msg := pg_temp.error_of($q$UPDATE public.feature_flags SET enabled = true WHERE key = 'journal_ai_insights'$q$);
  IF v_msg IS DISTINCT FROM 'flag:gate_evidence_required' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a gated flag was enabled in production without evidence (got %)', coalesce(v_msg, 'no error');
  END IF;
  DELETE FROM public.feature_flags WHERE key = 'text_scale_v2';
  v_msg := pg_temp.error_of($q$INSERT INTO public.feature_flags (key, enabled) VALUES ('text_scale_v2', true)$q$);
  IF v_msg IS DISTINCT FROM 'flag:gate_evidence_required' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a gated flag was inserted on in production (got %)', coalesce(v_msg, 'no error');
  END IF;
  INSERT INTO public.feature_flags (key, enabled) VALUES ('text_scale_v2', false)
  ON CONFLICT (key) DO UPDATE SET enabled = false;
  UPDATE public.feature_flags SET enabled = true WHERE key = 'flow_couples_v2';
  UPDATE public.feature_flags SET enabled = false WHERE key = 'flow_couples_v2';

  SET LOCAL ROLE service_role;
  v_msg := pg_temp.error_of($q$SELECT public.record_flag_gate_evidence('flow_couples_v2', 'REF-1')$q$);
  IF v_msg IS DISTINCT FROM 'flag:not_gated' THEN
    RESET ROLE;
    RAISE EXCEPTION 'CONTRACT VIOLATED: evidence for an ungated flag was not refused (got %)', coalesce(v_msg, 'no error');
  END IF;
  v_msg := pg_temp.error_of($q$SELECT public.record_flag_gate_evidence('journal_ai_insights', '  ')$q$);
  IF v_msg IS DISTINCT FROM 'flag:review_ref_required' THEN
    RESET ROLE;
    RAISE EXCEPTION 'CONTRACT VIOLATED: blank evidence was not refused (got %)', coalesce(v_msg, 'no error');
  END IF;
  PERFORM public.record_flag_gate_evidence('journal_ai_insights', 'W9C-CLINICIAN-2026-11');
  RESET ROLE;
  UPDATE public.feature_flags SET enabled = true WHERE key = 'journal_ai_insights';
  IF EXISTS (SELECT 1 FROM public.production_flag_violations() AS v WHERE v = 'journal_ai_insights')
     OR (SELECT recorded_at FROM private.flag_production_gates WHERE flag_key = 'journal_ai_insights') IS NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: recorded evidence did not clear the gate';
  END IF;
  UPDATE public.feature_flags SET enabled = false WHERE key = 'journal_ai_insights';
  PERFORM set_config('app.settings.attune_environment', '', true);

  -- get_public_app_config: anon gets the listed keys only, effective flags,
  -- and the open countries through the seam.
  UPDATE public.feature_flags SET enabled = true WHERE key = 'support_resources_v2';
  PERFORM pg_temp.as_anon();
  v_cfg := public.get_public_app_config();
  RESET ROLE;
  IF (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(v_cfg) AS k) <> ARRAY['config', 'flags']
     OR (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(v_cfg -> 'flags') AS k)
        <> ARRAY['flow_signin_v2', 'platform_age_signals', 'support_resources_v2', 'text_scale_v2']
     OR (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(v_cfg -> 'config') AS k)
        <> ARRAY['age_signal_storefronts', 'dating_open_countries'] THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: get_public_app_config returned other keys: %', v_cfg;
  END IF;
  IF v_cfg -> 'config' -> 'dating_open_countries' IS DISTINCT FROM '["GB", "GH"]'::jsonb
     OR v_cfg -> 'config' -> 'age_signal_storefronts' IS DISTINCT FROM '["USA", "BRA"]'::jsonb
     OR v_cfg -> 'flags' -> 'support_resources_v2' IS DISTINCT FROM 'true'::jsonb
     OR v_cfg -> 'flags' -> 'flow_signin_v2' IS DISTINCT FROM 'false'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: get_public_app_config values are wrong: %', v_cfg;
  END IF;
  UPDATE public.feature_flags SET enabled = false WHERE key = 'support_resources_v2';
  UPDATE public.app_public_config SET value = '["GH"]' WHERE key = 'dating_open_countries';
  IF public.get_public_app_config() -> 'config' -> 'dating_open_countries' IS DISTINCT FROM '["GH"]'::jsonb
     OR private.dating_open_countries() IS DISTINCT FROM ARRAY['GH'] THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the open-country list does not come through the one seam';
  END IF;
END $$;
```

- [ ] **Step 2: Run it to verify it fails**

```bash
cd /Users/user/attune
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/identity_foundation_contracts.sql; echo "exit=$?"
```
Expected: `ERROR:  CONTRACT VIOLATED: W1c environment objects are missing (attune_environment, assert_development_project, get_public_app_config)`, `exit=3`.

- [ ] **Step 3: Write the migration**

Create `supabase/migrations/20261025100400_spec1_flags_and_public_config.sql` with exactly:

```sql
-- Spec 1 W1c, migration 5 of 6 (spec §4.7 #5): spec1_flags_and_public_config.
--   * private.attune_environment(): 'development' while the setting is unset
--     or empty, 'production' for 'production' and for any other value (a
--     typo fails closed). Read through public.app_setting, Vault first and
--     then the app.settings.attune_environment GUC: on the managed project
--     ALTER DATABASE ... SET app.settings.* fails with 42501
--     (20260931120000_vault_backed_settings.sql:1-5). Nothing here sets it;
--     only the owner does, at launch.
--   * private.assert_development_project(): the dev-script guard.
--   * the eleven Spec 1 flags, inserted false (migrations never turn a flag on);
--   * the production flag gate (review R-7): private.flag_production_gates,
--     a feature_flags trigger, record_flag_gate_evidence and
--     production_flag_violations;
--   * app_public_config and the one Dating open-country seam (D15),
--     read by anon through get_public_app_config().
-- Grants in 20261025100410_spec1_flags_and_public_config_grants.sql.
BEGIN;

CREATE OR REPLACE FUNCTION private.attune_environment()
RETURNS text
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_raw constant text := btrim(coalesce(public.app_setting('attune_environment'), ''));
BEGIN
  IF v_raw = '' OR v_raw = 'development' THEN
    RETURN 'development';
  END IF;
  RETURN 'production';
END;
$$;

CREATE OR REPLACE FUNCTION public.get_attune_environment()
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT private.attune_environment();
$$;

-- Development project ref: mrgjtyacrzfylawyzabm (spec §1.3 Q19b).
CREATE OR REPLACE FUNCTION private.assert_development_project()
RETURNS void
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_url constant text := public.app_setting('supabase_url');
BEGIN
  IF private.attune_environment() <> 'development' OR (v_url IS NOT NULL AND position('mrgjtyacrzfylawyzabm' IN v_url) = 0) THEN
    RAISE EXCEPTION 'env:not_development';
  END IF;
END;
$$;

-- The production flag gate (spec §2.5). One row per gated flag;
-- flow_couples_v2 has no gate. Spec 2 may add rows.
CREATE TABLE IF NOT EXISTS private.flag_production_gates (
  flag_key text PRIMARY KEY,
  gate text NOT NULL,
  review_ref text,
  recorded_by text,
  recorded_at timestamptz
);
INSERT INTO private.flag_production_gates (flag_key, gate) VALUES
  ('flow_signin_v2', 'W2 group gate (W2c): SMS, voice and WhatsApp providers contracted; MTN sender ID; Meta template; real-carrier tests in GH, UK, US, CA; A5 AI line and EULA v2 approved by counsel; webcredentials; store listing'),
  ('flow_paths_v2', 'Spec 2 W2 path trigger live, so Dating -> Just for me pauses Dating (D18)'),
  ('couple_profile', 'W5 gate: the Ghanaian cultural reviewer confirms the stage options and helper text'),
  ('dormancy_rule', 'W6a gate: DV specialist reviewed DM1, DM2 and H1; both auth hooks pass on the development project first'),
  ('platform_age_signals', 'W6b gate: Play Restrict Minor Access on, 18+ ratings in both stores, Declared Age Range entitlement granted'),
  ('support_resources_v2', 'W7a gate: resource entries verified per country by the DV professional and the cultural reviewer; clinician reviewed the grief copy'),
  ('csam_hash_matching', 'W7b gate: hash-vendor contract, escalation runbook approved by counsel, named child-safety contact'),
  ('opinions_safety_v1', 'W9a and W9b gates: reviewed slur and explicit lists signed; a named daily reviewer works review queue v0'),
  ('journal_ai_insights', 'W9c gate: the clinician and the suicide-prevention reviewer sign the journal card and the self-harm corpus'),
  ('text_scale_v2', 'W10 group gate (W10c): the device matrix passes on the chosen cap')
ON CONFLICT (flag_key) DO NOTHING;

CREATE OR REPLACE FUNCTION private.guard_flag_production_gate()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF NEW.enabled
     AND private.attune_environment() = 'production'
     AND EXISTS (SELECT 1 FROM private.flag_production_gates AS g
                  WHERE g.flag_key = NEW.key AND g.review_ref IS NULL) THEN
    RAISE EXCEPTION 'flag:gate_evidence_required';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS feature_flags_production_gate ON public.feature_flags;
CREATE TRIGGER feature_flags_production_gate
  BEFORE INSERT OR UPDATE ON public.feature_flags
  FOR EACH ROW EXECUTE FUNCTION private.guard_flag_production_gate();

-- The eleven Spec 1 flags, off (spec §2.5). The dev script turns them on.
INSERT INTO public.feature_flags (key, enabled) VALUES
  ('flow_signin_v2', false),
  ('flow_paths_v2', false),
  ('flow_couples_v2', false),
  ('couple_profile', false),
  ('dormancy_rule', false),
  ('platform_age_signals', false),
  ('support_resources_v2', false),
  ('csam_hash_matching', false),
  ('opinions_safety_v1', false),
  ('journal_ai_insights', false),
  ('text_scale_v2', false)
ON CONFLICT (key) DO NOTHING;

-- Owner-only in practice (SQL editor, service role). recorded_by is the JWT
-- role, else the session user: inside a SECURITY DEFINER function
-- current_user is the owner.
CREATE OR REPLACE FUNCTION public.record_flag_gate_evidence(p_flag text, p_review_ref text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF p_review_ref IS NULL OR btrim(p_review_ref) = '' THEN
    RAISE EXCEPTION 'flag:review_ref_required';
  END IF;
  UPDATE private.flag_production_gates AS g
     SET review_ref = btrim(p_review_ref),
         recorded_by = coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role',
                                session_user::text),
         recorded_at = now()
   WHERE g.flag_key = p_flag;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'flag:not_gated';
  END IF;
END;
$$;

-- Run right after the environment flip: the trigger only sees later writes.
CREATE OR REPLACE FUNCTION public.production_flag_violations()
RETURNS SETOF text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT g.flag_key
    FROM private.flag_production_gates AS g
    JOIN public.feature_flags AS f ON f.key = g.flag_key
   WHERE f.enabled AND g.review_ref IS NULL
   ORDER BY g.flag_key;
$$;

-- Public, pre-auth configuration (spec §4.2). Service-role writes only.
CREATE TABLE IF NOT EXISTS public.app_public_config (
  key text PRIMARY KEY
    CONSTRAINT app_public_config_key_check CHECK (key IN ('age_signal_storefronts', 'dating_open_countries')),
  value jsonb NOT NULL CONSTRAINT app_public_config_value_check CHECK (jsonb_typeof(value) = 'array'),
  updated_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.app_public_config ENABLE ROW LEVEL SECURITY;
INSERT INTO public.app_public_config (key, value) VALUES
  ('age_signal_storefronts', '["USA", "BRA"]'::jsonb),
  ('dating_open_countries', '["GH", "GB"]'::jsonb)
ON CONFLICT (key) DO NOTHING;

-- The one reader of the Dating open-country list (D15): ISO 3166-1 alpha-2
-- codes, sorted. Spec 2 W1b re-creates this over country_safety_config with
-- the same shape, then deletes the row.
CREATE OR REPLACE FUNCTION private.dating_open_countries()
RETURNS text[]
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT coalesce(array_agg(c ORDER BY c), ARRAY[]::text[])
    FROM public.app_public_config AS k,
         jsonb_array_elements_text(k.value) AS c
   WHERE k.key = 'dating_open_countries';
$$;

-- Anon and signed in: effective flag values and the two config lists, nothing else.
CREATE OR REPLACE FUNCTION public.get_public_app_config()
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT jsonb_build_object(
    'flags', jsonb_build_object(
      'flow_signin_v2', private.spec1_flag_on('flow_signin_v2'),
      'platform_age_signals', private.spec1_flag_on('platform_age_signals'),
      'support_resources_v2', private.spec1_flag_on('support_resources_v2'),
      'text_scale_v2', private.spec1_flag_on('text_scale_v2')),
    'config', jsonb_build_object(
      'age_signal_storefronts', coalesce(
        (SELECT k.value FROM public.app_public_config AS k WHERE k.key = 'age_signal_storefronts'),
        '[]'::jsonb),
      'dating_open_countries', to_jsonb(private.dating_open_countries())));
$$;

COMMIT;
```

- [ ] **Step 4: Write the grants twin**

Create `supabase/migrations/20261025100410_spec1_flags_and_public_config_grants.sql` with exactly:

```sql
-- Spec 1 W1c: grants for 20261025100400_spec1_flags_and_public_config.sql.
-- Nothing reaches anon except get_public_app_config (spec §4.3 W1c).
BEGIN;
REVOKE ALL ON public.app_public_config FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.app_public_config TO service_role;
REVOKE ALL ON private.flag_production_gates FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION private.attune_environment() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.assert_development_project() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.guard_flag_production_gate() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.dating_open_countries() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.get_attune_environment() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.record_flag_gate_evidence(text, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.production_flag_violations() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.get_public_app_config() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_attune_environment() TO service_role;
GRANT EXECUTE ON FUNCTION public.record_flag_gate_evidence(text, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.production_flag_violations() TO service_role;
GRANT EXECUTE ON FUNCTION public.get_public_app_config() TO anon, authenticated;
COMMIT;
```

- [ ] **Step 5: Write the development switch-on script (not a migration)**

Create `supabase/sql/dev_enable_spec1_flags.sql` with exactly:

```sql
-- DEV / MANUAL TESTING ONLY. Never a migration (spec §2.5, Q19b). Turns every
-- Spec 1 flag on, on the development project only: the first statement
-- raises env:not_development (and so stops the script) unless the project
-- reads 'development' and, when supabase_url is configured, names the
-- development ref. It never sets attune_environment. Safe to re-run; undo
-- by setting a flag false.
SELECT private.assert_development_project();

INSERT INTO public.feature_flags (key, enabled) VALUES
  ('flow_signin_v2', true),
  ('flow_paths_v2', true),
  ('flow_couples_v2', true),
  ('couple_profile', true),
  ('dormancy_rule', true),
  ('platform_age_signals', true),
  ('support_resources_v2', true),
  ('csam_hash_matching', true),
  ('opinions_safety_v1', true),
  ('journal_ai_insights', true),
  ('text_scale_v2', true)
ON CONFLICT (key) DO UPDATE SET enabled = EXCLUDED.enabled, updated_at = now();
```

- [ ] **Step 6: Apply both twice, then run the contract**

```bash
cd /Users/user/attune
for i in 1 2; do
  psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/migrations/20261025100400_spec1_flags_and_public_config.sql; echo "migration exit=$?"
  psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/migrations/20261025100410_spec1_flags_and_public_config_grants.sql; echo "grants exit=$?"
done
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/identity_foundation_contracts.sql; echo "exit=$?"
psql -X -d attune_spec3a -Atc "select count(*) from public.feature_flags where key in ('flow_signin_v2','flow_paths_v2','flow_couples_v2','couple_profile','dormancy_rule','platform_age_signals','support_resources_v2','csam_hash_matching','opinions_safety_v1','journal_ai_insights','text_scale_v2') and not enabled"
```
Expected: four `… exit=0`; `exit=0` with no `ERROR`; `11`.

- [ ] **Step 7: Prove the dev script, without persisting it**

```bash
cd /Users/user/attune
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -c 'BEGIN;' -f supabase/sql/dev_enable_spec1_flags.sql -f supabase/sql/dev_enable_spec1_flags.sql -c "SELECT count(*) FILTER (WHERE enabled) AS spec1_on FROM public.feature_flags WHERE key IN ('flow_signin_v2','flow_paths_v2','flow_couples_v2','couple_profile','dormancy_rule','platform_age_signals','support_resources_v2','csam_hash_matching','opinions_safety_v1','journal_ai_insights','text_scale_v2');" -c 'ROLLBACK;'; echo "exit=$?"
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -c 'BEGIN;' -c "SELECT set_config('app.settings.attune_environment', 'production', true);" -f supabase/sql/dev_enable_spec1_flags.sql; echo "exit=$?"
psql -X -d attune_spec3a -Atc "select count(*) from public.feature_flags where key = 'journal_ai_insights' and enabled"
```
Expected: the first run (twice in a row: safe to re-run) shows `spec1_on` = `11` and `exit=0`; the second prints `ERROR:  env:not_development` and `exit=3`; the last prints `0` (nothing persisted).

- [ ] **Step 8: Mutation check (spec §7.4 R-6: the dev guard passes in production)**

```bash
cd /Users/user/attune
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a <<'SQL'; echo "exit=$?"
BEGIN;
SELECT replace(pg_get_functiondef('private.assert_development_project()'::regprocedure),
  'private.attune_environment() <> ''development'' OR ', '') \gexec
DO $$ BEGIN
  IF position('attune_environment()' IN pg_get_functiondef('private.assert_development_project()'::regprocedure)) > 0 THEN
    RAISE EXCEPTION 'MUTANT NOT APPLIED';
  END IF;
END $$;
\i supabase/tests/identity_foundation_contracts.sql
SQL
```
Expected: `ERROR:  CONTRACT VIOLATED: the dev guard passed in production (got no error)`, `exit=3`.

- [ ] **Step 9: Add the twin to the local harness (edit only)**

Append to the end of `scripts/local_pg_grants.sql`:

```sql

-- Spec 1 W1c: the environment helpers and the flag gate are server-only;
-- get_public_app_config is the one anon read.
\i supabase/migrations/20261025100410_spec1_flags_and_public_config_grants.sql
```

- [ ] **Step 10: Run tests**

```bash
cd /Users/user/attune
for t in identity_foundation_contracts dating_mode_contracts ai_capability_flag_contracts safety_self_check_contracts pause_messages_contracts service_role_grants_test; do
  psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/$t.sql >/dev/null 2>&1; echo "$t exit=$?"
done
grep -E 'dating_mode|ai_capability_flag|safety_self_check|pause_messages|service_role_grants' .superpowers/sdd/2026-10-25-spec1-w1/sql-baseline.txt
```
Expected: `identity_foundation_contracts exit=0`; the flag-writing contracts exactly as in the baseline (the gate does nothing in development).

---

### Task 10: Identity health and the unfinished sign-up purge (W1c; §4.3, §4.5, §4.6, §4.8)

**Files:**
- Create: `supabase/migrations/20261025100500_identity_health.sql`
- Create: `supabase/migrations/20261025100510_identity_health_grants.sql`
- Create: `supabase/functions/purge-unfinished-signups/handler.ts`
- Create: `supabase/functions/purge-unfinished-signups/index.ts`
- Create: `supabase/functions/purge-unfinished-signups/handler.test.ts`
- Modify: `supabase/tests/identity_foundation_contracts.sql` (insert section I before the final `ROLLBACK;`)
- Modify: `scripts/local_pg_grants.sql` (append)

**Interfaces:**
- Consumes: `public.account_birthdates`, `public.account_holds` (Task 6), `users.path` (Task 1); existing `public.invoke_edge_function(text)` (Vault-backed) and `_shared/attune_auth.ts` (`requireServiceRole`, `serviceRoleClient`, `jsonResponse`, `HttpError`).
- Produces: `public.unfinished_signup_candidates() RETURNS SETOF uuid` (service_role; Auth users with no `public.users` row created more than 24 h ago, oldest first, 500 a run); `public.get_identity_health() RETURNS jsonb` → `{accounts_without_birth_date, accounts_without_path, holds:{age_review, recovery_hold, safety_review}, unfinished_signups_awaiting_purge}` (service_role; W6a re-creates it from this live body); cron job `purge-unfinished-signups` (`41 3 * * *`) calling the edge function `purge-unfinished-signups`; `handler.ts` exports `interface PurgeClient`, `interface PurgeResult { candidates, deleted, failed }`, `candidateIds(data: unknown): string[]`, `purgeUnfinishedSignups(client: PurgeClient): Promise<PurgeResult>`.

- [ ] **Step 1: Write the failing contract section**

In `supabase/tests/identity_foundation_contracts.sql`, insert immediately before the final line `ROLLBACK;`:

```sql
-- =====================================================================
-- I. Identity health and unfinished sign-ups (W1c; §4.3, §4.6, §4.8).
--    Fixtures 40-42.
-- =====================================================================
DO $$
BEGIN
  IF to_regprocedure('public.get_identity_health()') IS NULL
     OR to_regprocedure('public.unfinished_signup_candidates()') IS NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: W1c health objects are missing (get_identity_health, unfinished_signup_candidates)';
  END IF;
END $$;

DO $$
DECLARE
  v_old_unfinished constant uuid := '5f1a0000-0000-0000-0000-000000000040';
  v_new_unfinished constant uuid := '5f1a0000-0000-0000-0000-000000000041';
  v_finished constant uuid := '5f1a0000-0000-0000-0000-000000000042';
  v_before jsonb;
  v_after jsonb;
BEGIN
  IF has_function_privilege('authenticated', 'public.get_identity_health()', 'EXECUTE')
     OR has_function_privilege('anon', 'public.get_identity_health()', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.unfinished_signup_candidates()', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'public.get_identity_health()', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'public.unfinished_signup_candidates()', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: identity health grants are wrong';
  END IF;

  SET LOCAL ROLE service_role;
  v_before := public.get_identity_health();
  RESET ROLE;

  INSERT INTO auth.users (id, phone, created_at) VALUES
    (v_old_unfinished, '+15558100040', timestamptz '2001-01-01 00:00+00'),
    (v_new_unfinished, '+15558100041', now()),
    (v_finished, '+15558100042', now() - interval '30 hours');
  INSERT INTO public.users (id, phone, display_name) VALUES (v_finished, '+15558100042', 'Finished W1');
  PERFORM public.place_account_hold(v_finished, 'age_review');

  SET LOCAL ROLE service_role;
  v_after := public.get_identity_health();
  IF NOT EXISTS (SELECT 1 FROM public.unfinished_signup_candidates() AS c WHERE c = v_old_unfinished)
     OR EXISTS (SELECT 1 FROM public.unfinished_signup_candidates() AS c WHERE c IN (v_new_unfinished, v_finished)) THEN
    RESET ROLE;
    RAISE EXCEPTION 'CONTRACT VIOLATED: unfinished_signup_candidates picked the wrong accounts';
  END IF;
  RESET ROLE;

  IF (v_after ->> 'accounts_without_birth_date')::int <> (v_before ->> 'accounts_without_birth_date')::int + 1
     OR (v_after ->> 'accounts_without_path')::int <> (v_before ->> 'accounts_without_path')::int + 1
     OR (v_after -> 'holds' ->> 'age_review')::int <> (v_before -> 'holds' ->> 'age_review')::int + 1
     OR (v_after ->> 'unfinished_signups_awaiting_purge')::int <> (v_before ->> 'unfinished_signups_awaiting_purge')::int + 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: identity health counts did not move: % -> %', v_before, v_after;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM cron.job
                  WHERE jobname = 'purge-unfinished-signups' AND schedule = '41 3 * * *'
                    AND command LIKE '%invoke_edge_function(''purge-unfinished-signups'')%') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: purge-unfinished-signups is not scheduled';
  END IF;
END $$;
```

- [ ] **Step 2: Run it to verify it fails**

```bash
cd /Users/user/attune
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/identity_foundation_contracts.sql; echo "exit=$?"
```
Expected: `ERROR:  CONTRACT VIOLATED: W1c health objects are missing (get_identity_health, unfinished_signup_candidates)`, `exit=3`.

- [ ] **Step 3: Write the migration and its twin**

Create `supabase/migrations/20261025100500_identity_health.sql` with exactly:

```sql
-- Spec 1 W1c, migration 6 of 6 (spec §4.7 #6): identity_health.
--   * get_identity_health(): W1 counts only (W6a re-creates it from this live
--     body to add dormancy, parked accounts and hook fail-opens);
--   * unfinished_signup_candidates(): auth users with no public.users row,
--     created more than 24 hours ago (oldest first, 500 a run);
--   * the purge-unfinished-signups job (its own cron, spec §4.6).
-- Grants in 20261025100510_identity_health_grants.sql.
BEGIN;

CREATE OR REPLACE FUNCTION public.unfinished_signup_candidates()
RETURNS SETOF uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT a.id
    FROM auth.users AS a
   WHERE a.created_at < now() - interval '24 hours'
     AND NOT EXISTS (SELECT 1 FROM public.users AS u WHERE u.id = a.id)
   ORDER BY a.created_at, a.id
   LIMIT 500;
$$;

CREATE OR REPLACE FUNCTION public.get_identity_health()
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT jsonb_build_object(
    'accounts_without_birth_date', (
      SELECT count(*) FROM public.users AS u
       WHERE NOT EXISTS (SELECT 1 FROM public.account_birthdates AS b WHERE b.user_id = u.id)),
    'accounts_without_path', (SELECT count(*) FROM public.users AS u WHERE u.path IS NULL),
    'holds', jsonb_build_object(
      'age_review', (SELECT count(*) FROM public.account_holds AS h
                      WHERE h.kind = 'age_review' AND h.resolved_at IS NULL),
      'recovery_hold', (SELECT count(*) FROM public.account_holds AS h
                         WHERE h.kind = 'recovery_hold' AND h.resolved_at IS NULL),
      'safety_review', (SELECT count(*) FROM public.account_holds AS h
                         WHERE h.kind = 'safety_review' AND h.resolved_at IS NULL)),
    'unfinished_signups_awaiting_purge', (
      SELECT count(*) FROM auth.users AS a
       WHERE a.created_at < now() - interval '24 hours'
         AND NOT EXISTS (SELECT 1 FROM public.users AS u WHERE u.id = a.id)));
$$;

DO $$
BEGIN
  PERFORM cron.unschedule('purge-unfinished-signups');
EXCEPTION WHEN OTHERS THEN
  NULL;
END $$;
SELECT cron.schedule(
  'purge-unfinished-signups',
  '41 3 * * *',
  $cron$SELECT public.invoke_edge_function('purge-unfinished-signups')$cron$
);

COMMIT;
```

Create `supabase/migrations/20261025100510_identity_health_grants.sql` with exactly:

```sql
-- Spec 1 W1c: grants for 20261025100500_identity_health.sql. Service role only.
BEGIN;
REVOKE ALL ON FUNCTION public.unfinished_signup_candidates() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.get_identity_health() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.unfinished_signup_candidates() TO service_role;
GRANT EXECUTE ON FUNCTION public.get_identity_health() TO service_role;
COMMIT;
```

- [ ] **Step 4: Apply both twice, then run the contract**

```bash
cd /Users/user/attune
for i in 1 2; do
  psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/migrations/20261025100500_identity_health.sql; echo "migration exit=$?"
  psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/migrations/20261025100510_identity_health_grants.sql; echo "grants exit=$?"
done
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/identity_foundation_contracts.sql; echo "exit=$?"
```
Expected: four `… exit=0`; then `exit=0` with no `ERROR`.

- [ ] **Step 5: Write the failing Deno test**

Create `supabase/functions/purge-unfinished-signups/handler.test.ts` with exactly:

```ts
// Spec 1 W1c: the unfinished sign-up purge, against a fake client.
import { candidateIds, type PurgeClient, purgeUnfinishedSignups } from "./handler.ts";

const A = "5f1a0000-0000-0000-0000-0000000000a1";
const B = "5f1a0000-0000-0000-0000-0000000000b2";
const C = "5f1a0000-0000-0000-0000-0000000000c3";

function fakeClient(rows: unknown, failFor: string[] = [], rpcError = false) {
  const deleted: string[] = [];
  const client: PurgeClient = {
    rpc(fn) {
      if (fn !== "unfinished_signup_candidates") throw new Error(`unexpected rpc ${fn}`);
      return Promise.resolve(rpcError ? { data: null, error: { message: "boom" } } : { data: rows, error: null });
    },
    auth: {
      admin: {
        deleteUser(id) {
          if (failFor.includes(id)) return Promise.resolve({ error: { message: "nope" } });
          if (id === C) return Promise.reject(new Error("network"));
          deleted.push(id);
          return Promise.resolve({ error: null });
        },
      },
    },
  };
  return { client, deleted };
}

Deno.test("every candidate is deleted once; failures are counted, never thrown", async () => {
  const { client, deleted } = fakeClient([A, B, C], [B]);
  const result = await purgeUnfinishedSignups(client);
  if (JSON.stringify(result) !== JSON.stringify({ candidates: 3, deleted: 1, failed: 2 })) {
    throw new Error(`unexpected result ${JSON.stringify(result)}`);
  }
  if (deleted.join(",") !== A) throw new Error(`deleted ${deleted.join(",")}`);
});

Deno.test("both PostgREST shapes are read; anything that is not a uuid is skipped", () => {
  const ids = candidateIds([A, { unfinished_signup_candidates: B }, 42, null, "not-a-uuid", { x: 1 }]);
  if (ids.join(",") !== `${A},${B}`) throw new Error(`read ${ids.join(",")}`);
  if (candidateIds(null).length !== 0 || candidateIds({}).length !== 0) throw new Error("non-arrays must read as empty");
});

Deno.test("a failed candidate read stops the run without deleting anything", async () => {
  const { client, deleted } = fakeClient([A], [], true);
  let message = "";
  try {
    await purgeUnfinishedSignups(client);
  } catch (error) {
    message = error instanceof Error ? error.message : String(error);
  }
  if (message !== "unfinished_signup_candidates_failed") throw new Error(`threw "${message}"`);
  if (deleted.length !== 0) throw new Error("deleted after a failed read");
});

Deno.test("the endpoint is service-role only and logs counts, never ids", async () => {
  const index = await Deno.readTextFile(new URL("./index.ts", import.meta.url));
  const handler = await Deno.readTextFile(new URL("./handler.ts", import.meta.url));
  const guard = index.indexOf("requireServiceRole(req);");
  if (guard < 0 || guard > index.indexOf("purgeUnfinishedSignups(")) {
    throw new Error("requireServiceRole must run before the purge");
  }
  if (/console\.(log|error|warn)\([^)]*\bid\b/.test(index + handler)) throw new Error("an id is logged");
  if (/console\./.test(handler)) throw new Error("the handler must not log");
});
```

```bash
cd /Users/user/attune/supabase/functions
deno test --allow-read purge-unfinished-signups/handler.test.ts 2>&1 | grep -E "Cannot find module|Type checking failed" | head -2
```
Expected: `TS2307 [ERROR]: Cannot find module 'file:///…/purge-unfinished-signups/handler.ts'.` and `error: Type checking failed.`

- [ ] **Step 6: Write the handler and the endpoint**

Create `supabase/functions/purge-unfinished-signups/handler.ts` with exactly:

```ts
// supabase/functions/purge-unfinished-signups/handler.ts
//
// Spec 1 W1c (§4.5, §4.8): an Auth user that never finished sign-up (no
// public.users row) is deleted once it is more than 24 hours old. "Not now"
// at consent and an abandoned code both leave one behind; signInWithOtp
// creates the Auth user before anything else.
//
// Logs and returns counts only, never an id or a phone (spec §4.1 rule 5).

export interface PurgeClient {
  rpc(fn: "unfinished_signup_candidates"): PromiseLike<{ data: unknown; error: { message: string } | null }>;
  auth: {
    admin: {
      deleteUser(id: string): PromiseLike<{ error: { message: string } | null }>;
    };
  };
}

export interface PurgeResult {
  candidates: number;
  deleted: number;
  failed: number;
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/// A SETOF uuid comes back as bare values or as one-key rows depending on
/// the PostgREST version; both are read, anything else is skipped.
export function candidateIds(data: unknown): string[] {
  if (!Array.isArray(data)) return [];
  const ids: string[] = [];
  for (const row of data) {
    const value = typeof row === "string"
      ? row
      : row !== null && typeof row === "object"
      ? Object.values(row as Record<string, unknown>)[0]
      : null;
    if (typeof value === "string" && UUID.test(value)) ids.push(value);
  }
  return ids;
}

export async function purgeUnfinishedSignups(client: PurgeClient): Promise<PurgeResult> {
  const { data, error } = await client.rpc("unfinished_signup_candidates");
  if (error) throw new Error("unfinished_signup_candidates_failed");
  const ids = candidateIds(data);
  let deleted = 0;
  let failed = 0;
  for (const id of ids) {
    try {
      const { error: deleteError } = await client.auth.admin.deleteUser(id);
      if (deleteError) {
        failed++;
      } else {
        deleted++;
      }
    } catch {
      failed++;
    }
  }
  return { candidates: ids.length, deleted, failed };
}
```

Create `supabase/functions/purge-unfinished-signups/index.ts` with exactly:

```ts
// supabase/functions/purge-unfinished-signups/index.ts — see handler.ts.
// Run daily by the purge-unfinished-signups cron (20261025100500) with the
// service-role key; any other caller gets 403.
import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import {
  HttpError,
  jsonResponse,
  requireServiceRole,
  serviceRoleClient,
} from "../_shared/attune_auth.ts";
import { type PurgeClient, purgeUnfinishedSignups } from "./handler.ts";

serve(async (req) => {
  if (req.method === "OPTIONS") return jsonResponse({ ok: true });
  try {
    requireServiceRole(req);
    const result = await purgeUnfinishedSignups(serviceRoleClient() as unknown as PurgeClient);
    console.log("purge-unfinished-signups", JSON.stringify(result));
    return jsonResponse({ success: true, ...result });
  } catch (error) {
    if (error instanceof HttpError) {
      return jsonResponse({ error: error.message }, error.status);
    }
    console.error(
      "purge-unfinished-signups failed:",
      error instanceof Error ? error.name : typeof error,
    );
    return jsonResponse({ error: "purge_failed" }, 500);
  }
});
```

- [ ] **Step 7: Run the Deno tests to verify they pass**

```bash
cd /Users/user/attune/supabase/functions
deno test --allow-read purge-unfinished-signups/handler.test.ts 2>&1 | grep -E "passed|failed" | tail -1
deno check purge-unfinished-signups/index.ts 2>&1 | grep -E "error|Check" | head -2
```
Expected: `ok | 4 passed | 0 failed`; `Check …purge-unfinished-signups/index.ts` and no `error`.

- [ ] **Step 8: Add the twin to the local harness (edit only)**

Append to the end of `scripts/local_pg_grants.sql`:

```sql

-- Spec 1 W1c: identity health and the unfinished sign-up list, service role only.
\i supabase/migrations/20261025100510_identity_health_grants.sql
```

- [ ] **Step 9: Run tests**

```bash
cd /Users/user/attune
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/identity_foundation_contracts.sql; echo "identity exit=$?"
psql -X -d attune_spec3a -Atc "select jobname, schedule from cron.job where jobname in ('metric-counters-retention', 'purge-unfinished-signups') order by 1"
```
Expected: `identity exit=0`; `metric-counters-retention|12 4 * * *` and `purge-unfinished-signups|41 3 * * *`.

---

### Task 11: The Journal insight pause (W1c; D12, A-5)

**Files:**
- Create: `supabase/functions/analyse-journal-entry/journal_pause.ts`
- Create: `supabase/functions/analyse-journal-entry/journal_pause.test.ts`
- Modify: `supabase/functions/analyse-journal-entry/index.ts:4, 59-60`
- Modify: `lib/features/reflection_journal/data/models/journal_analysis.dart:4, 27`
- Create: `test/features/reflection_journal/journal_analysis_paused_test.dart`

**Interfaces:**
- Consumes: the `journal_ai_insights` flag row (Task 9); `_shared/feature_flag.ts` `featureFlagEnabled(client, key)` (any doubt is off).
- Produces: `JOURNAL_AI_FLAG = "journal_ai_insights"`, `PAUSED_BODY = { status: "paused" }`, `journalInsightsPaused(adminClient): Promise<boolean>`; `analyse-journal-entry` answers `{"status":"paused"}` to both `analyse_entry` and `get_patterns` while the flag is off, before any read, write or provider call. `JournalAnalysis.isPaused` (Dart). W9c adds the `self_disclosure`-first check after this pause and may switch the flag on in production at its gate.

- [ ] **Step 1: Write the failing Deno test**

Create `supabase/functions/analyse-journal-entry/journal_pause.test.ts` with exactly:

```ts
// Spec 1 W1c (D12): the Journal pause. featureFlagEnabled is exercised
// through a fake client shaped like the supabase-js query chain it calls.
import { JOURNAL_AI_FLAG, journalInsightsPaused, PAUSED_BODY } from "./journal_pause.ts";

function flagClient(result: { data: unknown; error: unknown } | Error) {
  const reads: string[] = [];
  const chain = {
    select(_columns: string) {
      return chain;
    },
    eq(_column: string, value: string) {
      reads.push(value);
      return chain;
    },
    maybeSingle() {
      return result instanceof Error ? Promise.reject(result) : Promise.resolve(result);
    },
  };
  return {
    reads,
    client: {
      from(table: string) {
        reads.push(table);
        return chain;
      },
    },
  };
}

Deno.test("journal insights are paused unless journal_ai_insights is on", async () => {
  if (JOURNAL_AI_FLAG !== "journal_ai_insights") throw new Error(`wrong flag key ${JOURNAL_AI_FLAG}`);
  if (PAUSED_BODY.status !== "paused") throw new Error("the paused answer must be {status: 'paused'}");

  const off = flagClient({ data: { enabled: false }, error: null });
  if (!(await journalInsightsPaused(off.client))) throw new Error("flag off must pause");
  if (off.reads.join(",") !== "feature_flags,journal_ai_insights") {
    throw new Error(`read the wrong flag: ${off.reads.join(",")}`);
  }
  for (const [label, result] of [
    ["a missing row", { data: null, error: null }],
    ["a read error", { data: null, error: { message: "permission denied" } }],
    ["a thrown read", new Error("network")],
  ] as const) {
    if (!(await journalInsightsPaused(flagClient(result).client))) throw new Error(`${label} must pause`);
  }

  const on = flagClient({ data: { enabled: true }, error: null });
  if (await journalInsightsPaused(on.client)) throw new Error("flag on must not pause");
});

Deno.test("the pause is checked before either action can reach a provider", async () => {
  const index = await Deno.readTextFile(new URL("./index.ts", import.meta.url));
  const pause = index.indexOf("if (await journalInsightsPaused(adminClient))");
  if (pause < 0) throw new Error("index.ts does not check the pause");
  for (const dispatch of ['body.action === "get_patterns"', 'body.action === "analyse_entry"']) {
    const at = index.indexOf(dispatch);
    if (at < 0 || at < pause) throw new Error(`${dispatch} is reached before the pause`);
  }
  if (!index.includes("return json(PAUSED_BODY);")) throw new Error("the pause must answer PAUSED_BODY");
});
```

```bash
cd /Users/user/attune/supabase/functions
deno test --allow-read analyse-journal-entry/journal_pause.test.ts 2>&1 | grep -E "Cannot find module|Type checking failed" | head -2
```
Expected: `TS2307 [ERROR]: Cannot find module 'file:///…/analyse-journal-entry/journal_pause.ts'.` and `error: Type checking failed.`

- [ ] **Step 2: Write the pause module**

Create `supabase/functions/analyse-journal-entry/journal_pause.ts` with exactly:

```ts
// supabase/functions/analyse-journal-entry/journal_pause.ts
//
// Spec 1 W1c (D12; research 10 F-7): Journal insights are paused until the
// hard-coded self_disclosure check runs before any provider call (S1 W9c).
// The flag journal_ai_insights is off by default; off, unreadable or missing
// all mean paused, for both actions: no Gemini call, nothing read from or
// written to reflection_journal_analysis.
import { featureFlagEnabled } from "../_shared/feature_flag.ts";

export const JOURNAL_AI_FLAG = "journal_ai_insights";

export const PAUSED_BODY = { status: "paused" } as const;

// deno-lint-ignore no-explicit-any
export async function journalInsightsPaused(adminClient: any): Promise<boolean> {
  return !(await featureFlagEnabled(adminClient, JOURNAL_AI_FLAG));
}
```

- [ ] **Step 3: Run it: the first test passes, the order test still fails**

```bash
cd /Users/user/attune/supabase/functions
deno test --allow-read analyse-journal-entry/journal_pause.test.ts 2>&1 | grep -E "index.ts does not check|passed|failed" | tail -2
```
Expected: `error: Error: index.ts does not check the pause` and `1 passed | 1 failed`.

- [ ] **Step 4: Check the pause first in the handler**

In `supabase/functions/analyse-journal-entry/index.ts`, replace exactly:

```ts
import { callGeminiJson, STATIC_PROHIBITED_PATTERNS } from "../_shared/gemini_json.ts";
```

with:

```ts
import { callGeminiJson, STATIC_PROHIBITED_PATTERNS } from "../_shared/gemini_json.ts";
import { journalInsightsPaused, PAUSED_BODY } from "./journal_pause.ts";
```

Then replace exactly:

```ts
    const body = await req.json();
    if (body.action === "get_patterns") {
```

with:

```ts
    const body = await req.json();
    // Spec 1 W1c (D12): paused until the self_disclosure check runs first
    // (W9c). Off means no provider call for either action.
    if (await journalInsightsPaused(adminClient)) {
      return json(PAUSED_BODY);
    }
    if (body.action === "get_patterns") {
```

- [ ] **Step 5: Run the Deno tests to verify they pass**

```bash
cd /Users/user/attune/supabase/functions
deno test --allow-read analyse-journal-entry/ 2>&1 | grep -E "passed|failed" | tail -1
deno check analyse-journal-entry/index.ts 2>&1 | grep -E "error|Check" | head -2
```
Expected: `ok | 6 passed | 0 failed` (the 2 new tests and the 4 in `runtime_patterns.test.ts`); `Check …analyse-journal-entry/index.ts` and no `error`.

- [ ] **Step 6: Write the failing Dart test**

Create `test/features/reflection_journal/journal_analysis_paused_test.dart` with exactly:

```dart
// Spec 1 W1c (D12): analyse-journal-entry answers {status: 'paused'} while
// journal_ai_insights is off; the model reads it and nothing reads as an
// insight.
import 'package:attune/features/reflection_journal/data/models/journal_analysis.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a paused answer parses, is paused, and is not an insight', () {
    final analysis = JournalAnalysis.fromJson(const {'status': 'paused'});
    expect(analysis.isPaused, isTrue);
    expect(analysis.isComplete, isFalse);
    expect(analysis.observation, isNull);
    expect(analysis.tone, isNull);
  });

  test('a completed answer is not paused', () {
    final analysis = JournalAnalysis.fromJson(const {
      'status': 'completed',
      'tone': 'settled',
      'observation': 'You wrote about rest.',
      'confidence': 'medium',
    });
    expect(analysis.isPaused, isFalse);
    expect(analysis.isComplete, isTrue);
  });
}
```

```bash
cd /Users/user/attune
flutter test --no-pub test/features/reflection_journal/journal_analysis_paused_test.dart 2>&1 | tr '\r' '\n' | grep -E "isPaused|All tests passed|Some tests failed" | head -2
```
Expected: `Error: The getter 'isPaused' isn't defined for the class 'JournalAnalysis'.`

- [ ] **Step 7: Add the getter**

In `lib/features/reflection_journal/data/models/journal_analysis.dart`, replace exactly:

```dart
  final String status; // 'pending' | 'completed' | 'insufficient_evidence' | 'failed'
```

with:

```dart
  // 'pending' | 'completed' | 'insufficient_evidence' | 'failed' | 'paused'
  final String status;
```

Then replace exactly:

```dart
  bool get isInsufficientEvidence => status == 'insufficient_evidence';
```

with:

```dart
  bool get isInsufficientEvidence => status == 'insufficient_evidence';

  /// Spec 1 W1c (D12): insights are paused (journal_ai_insights off). The
  /// entry screen shows a reflection only when [isComplete], so a paused
  /// answer shows nothing.
  bool get isPaused => status == 'paused';
```

- [ ] **Step 8: Run tests**

```bash
cd /Users/user/attune
flutter test --no-pub test/features/reflection_journal 2>&1 | tr '\r' '\n' | grep -E "All tests passed|Some tests failed" | tail -1
dart format test/features/reflection_journal/journal_analysis_paused_test.dart
```
Expected: `… All tests passed!` (the entry screen's `a.status == 'completed'` guard at `journal_entry_screen.dart:283` already hides a paused answer); `Formatted 1 file (0 changed)`.

---

### Task 12: The public config and metric clients, the scoped invite key; W1c gate

**Files:**
- Create: `lib/core/flags/public_app_config.dart`
- Create: `lib/core/metrics/metric_counter.dart`
- Create: `test/core/flags/public_app_config_test.dart`
- Create: `test/core/metrics/metric_counter_test.dart`
- Create: `test/features/onboarding/scoped_invite_code_test.dart`
- Modify: `lib/core/config/env.dart:66-68`
- Modify: `lib/app/feature_flag_refresher.dart:1, 25-26`
- Modify: `lib/features/onboarding/data/onboarding_store.dart:1, 56-70, 167-175, 206-212`
- Modify: `lib/main.dart:182-187`

**Interfaces:**
- Consumes: `get_public_app_config()` (Task 9) and `bump_metric(text)` with the 26 seeded keys (Task 5); `sharedPreferencesProvider` (`lib/core/providers/shared_prefs_provider.dart`).
- Produces: `Environment.flowV2Default` (`bool.fromEnvironment('FLOW_V2_DEFAULT')`); `class PublicAppConfig { flowSignInV2, platformAgeSignals, supportResourcesV2, textScaleV2, ageSignalStorefronts, datingOpenCountries; static off; fromJson; toJson }`; `abstract class PublicAppConfigGateway { Future<Map<String, dynamic>> fetch(); }`; `SupabasePublicAppConfigGateway`; `PublicAppConfigCache(SharedPreferences)` (key `attune.public_config.v1`); providers `publicAppConfigGatewayProvider`, `cachedPublicAppConfigProvider`, `publicAppConfigProvider` (FutureProvider, in `refreshedFlagProviders`), `flowSignInV2Provider` (bool), `datingOpenCountriesProvider` (`List<String>`); `enum ClientMetricKey` (26 values, `key`, `anonOk`); `typedef MetricSender`; `class MetricCounter { void bump(ClientMetricKey) }`; `metricCounterProvider`. `OnboardingStore(prefs, {required String scope, DateTime Function() now})`, `OnboardingStore.inviteClaimWindow` (24 h), `static Future<void> OnboardingStore.storeInviteFromLink(SharedPreferences, String code, {String? userId, DateTime Function() now})`; `pendingInviteCode` / `storePendingInviteCode` / `clearPendingInviteCode` now act on `attune.onboarding.<scope>.pending_invite` (`{code, stored_at}`), with the claim from the anonymous slot and the one-time legacy move inside the getter. W2a reads `flowSignInV2Provider` and `datingOpenCountriesProvider`; W2–W4 call `metricCounterProvider`.

- [ ] **Step 1: Write the failing tests**

Create `test/core/flags/public_app_config_test.dart` with exactly:

```dart
// Spec 1 W1c (§2.5, §5.3, D15): the public config client. Effective flags
// come from the server; the first frame uses the cached copy, else the
// build default; an unreadable config is everything off.
import 'dart:async';

import 'package:attune/core/config/env.dart';
import 'package:attune/core/flags/public_app_config.dart';
import 'package:attune/core/providers/shared_prefs_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Gateway implements PublicAppConfigGateway {
  _Gateway(this._answer);

  final Future<Map<String, dynamic>> Function() _answer;
  int calls = 0;

  @override
  Future<Map<String, dynamic>> fetch() {
    calls++;
    return _answer();
  }
}

const _server = <String, dynamic>{
  'flags': {
    'flow_signin_v2': true,
    'platform_age_signals': false,
    'support_resources_v2': true,
    'text_scale_v2': false,
  },
  'config': {
    'age_signal_storefronts': ['USA', 'BRA'],
    'dating_open_countries': ['GB', 'GH'],
  },
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  ProviderContainer container(PublicAppConfigGateway gateway) {
    final c = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        publicAppConfigGatewayProvider.overrideWithValue(gateway),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  test(
    'reads the server shape and caches it for the next first frame',
    () async {
      final c = container(_Gateway(() async => _server));
      final config = await c.read(publicAppConfigProvider.future);

      expect(config.flowSignInV2, isTrue);
      expect(config.supportResourcesV2, isTrue);
      expect(config.platformAgeSignals, isFalse);
      expect(config.textScaleV2, isFalse);
      expect(config.ageSignalStorefronts, ['USA', 'BRA']);
      expect(c.read(flowSignInV2Provider), isTrue);
      expect(c.read(datingOpenCountriesProvider), ['GB', 'GH']);
      expect(PublicAppConfigCache(prefs).read()?.datingOpenCountries, [
        'GB',
        'GH',
      ]);
    },
  );

  test(
    'before the first answer: the cached copy, else the build default',
    () async {
      final first = container(
        _Gateway(() => Completer<Map<String, dynamic>>().future),
      );
      expect(first.read(flowSignInV2Provider), Environment.flowV2Default);
      expect(first.read(datingOpenCountriesProvider), isEmpty);

      await PublicAppConfigCache(
        prefs,
      ).write(PublicAppConfig.fromJson(_server));
      final second = container(
        _Gateway(() => Completer<Map<String, dynamic>>().future),
      );
      expect(second.read(flowSignInV2Provider), isTrue);
      expect(second.read(datingOpenCountriesProvider), ['GB', 'GH']);
    },
  );

  test('a failed read keeps the cached copy, else everything is off', () async {
    final none = container(_Gateway(() async => throw Exception('offline')));
    final off = await none.read(publicAppConfigProvider.future);
    expect(off.flowSignInV2, isFalse);
    expect(off.datingOpenCountries, isEmpty);
    expect(none.read(flowSignInV2Provider), isFalse);

    await PublicAppConfigCache(prefs).write(PublicAppConfig.fromJson(_server));
    final cached = container(_Gateway(() async => throw Exception('offline')));
    expect(
      (await cached.read(publicAppConfigProvider.future)).flowSignInV2,
      isTrue,
    );
  });

  test('only a literal true is on, and only strings are kept', () {
    final config = PublicAppConfig.fromJson({
      'flags': {'flow_signin_v2': 'yes', 'text_scale_v2': 1},
      'config': {
        'dating_open_countries': [1, 'GH', null],
      },
    });
    expect(config.flowSignInV2, isFalse);
    expect(config.textScaleV2, isFalse);
    expect(config.datingOpenCountries, ['GH']);
    expect(PublicAppConfig.fromJson(const {}).ageSignalStorefronts, isEmpty);
  });

  test('a corrupt cache reads as no cache', () async {
    await prefs.setString(PublicAppConfigCache.key, '{not json');
    expect(PublicAppConfigCache(prefs).read(), isNull);
  });
}
```

Create `test/core/metrics/metric_counter_test.dart` with exactly:

```dart
// Spec 1 W1c (§4.3 W1b, review S-2): the app can pass only the exact client
// keys the server seeded, with the same pre-auth flag, and a bump never
// waits or throws.
import 'dart:io';

import 'package:attune/core/metrics/metric_counter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the client keys are exactly the metric_client_keys seed', () {
    final migration = Directory('supabase/migrations')
        .listSync()
        .whereType<File>()
        .singleWhere((f) => f.path.endsWith('_metric_counters.sql'));
    final sql = migration.readAsStringSync();
    final start = sql.indexOf('INSERT INTO public.metric_client_keys');
    final seed = sql.substring(start, sql.indexOf('ON CONFLICT', start));
    final rows = RegExp(
      r"\('([a-z0-9_:>.-]+)', (true|false), 'spec1'\)",
    ).allMatches(seed);
    final seeded = {for (final m in rows) m.group(1)!: m.group(2) == 'true'};

    expect(seeded, hasLength(26));
    expect({for (final k in ClientMetricKey.values) k.key: k.anonOk}, seeded);
  });

  test('bump sends the exact key, without waiting', () async {
    final sent = <String>[];
    MetricCounter(
      (key) async => sent.add(key),
    ).bump(ClientMetricKey.inviteSharedWhatsapp);
    await Future<void>.delayed(Duration.zero);
    expect(sent, ['invite_shared:whatsapp']);
  });

  test('a failing or throwing sender never surfaces an error', () async {
    MetricCounter(
      (key) async => throw Exception('offline'),
    ).bump(ClientMetricKey.signupStarted);
    MetricCounter(
      (key) => throw StateError('no client'),
    ).bump(ClientMetricKey.signupStarted);
    await Future<void>.delayed(Duration.zero);
  });
}
```

Create `test/features/onboarding/scoped_invite_code_test.dart` with exactly:

```dart
// Spec 1 W1c (§5.5, research 10 S17): invite codes are scoped. A code opened
// while signed out is claimed by the next sign-in within 24 hours, once; a
// second account on the same phone never inherits it; the legacy unscoped
// key is moved once.
import 'dart:convert';

import 'package:attune/features/onboarding/data/onboarding_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DateTime now;
  DateTime clock() => now;

  setUp(() => now = DateTime.utc(2026, 10, 25, 9));

  Future<SharedPreferences> prefsWith(Map<String, Object> values) async {
    SharedPreferences.setMockInitialValues(values);
    return SharedPreferences.getInstance();
  }

  OnboardingStore user(SharedPreferences prefs, String uid) => OnboardingStore(
    prefs,
    scope: '${OnboardingStore.userScopePrefix}.$uid',
    now: clock,
  );

  test('signed out: the next sign-in within 24 h claims it, once', () async {
    final prefs = await prefsWith({});
    await OnboardingStore.storeInviteFromLink(prefs, 'K7P2QM', now: clock);
    expect(
      OnboardingStore(
        prefs,
        scope: OnboardingStore.anonymousScope,
      ).pendingInviteCode,
      'K7P2QM',
    );

    now = now.add(const Duration(hours: 23));
    expect(user(prefs, 'ama').pendingInviteCode, 'K7P2QM');
    expect(
      prefs.getString('attune.onboarding.anonymous.pending_invite'),
      isNull,
    );
    expect(user(prefs, 'kofi').pendingInviteCode, isNull);
    expect(user(prefs, 'ama').pendingInviteCode, 'K7P2QM');
  });

  test('a signed-out code older than 24 h is dropped, never claimed', () async {
    final prefs = await prefsWith({});
    await OnboardingStore.storeInviteFromLink(prefs, 'K7P2QM', now: clock);
    now = now.add(const Duration(hours: 24));
    expect(user(prefs, 'ama').pendingInviteCode, isNull);
    expect(
      prefs.getString('attune.onboarding.anonymous.pending_invite'),
      isNull,
    );
  });

  test(
    'signed in: straight to that account, invisible to anyone else',
    () async {
      final prefs = await prefsWith({});
      await OnboardingStore.storeInviteFromLink(
        prefs,
        'W7XK2P',
        userId: 'ama',
        now: clock,
      );
      final stored =
          jsonDecode(
                prefs.getString('attune.onboarding.user.ama.pending_invite')!,
              )
              as Map;
      expect(stored['code'], 'W7XK2P');
      expect(user(prefs, 'kofi').pendingInviteCode, isNull);
      expect(user(prefs, 'ama').pendingInviteCode, 'W7XK2P');

      await user(prefs, 'ama').clearPendingInviteCode();
      expect(user(prefs, 'ama').pendingInviteCode, isNull);
    },
  );

  test('the legacy unscoped key is moved once, then deleted', () async {
    final prefs = await prefsWith({
      OnboardingStore.pendingInviteCodeKey: 'LEG4CY',
    });
    expect(user(prefs, 'ama').pendingInviteCode, 'LEG4CY');
    expect(prefs.containsKey(OnboardingStore.pendingInviteCodeKey), isFalse);
    expect(user(prefs, 'kofi').pendingInviteCode, isNull);
  });

  test('reset clears the scope\'s code', () async {
    final prefs = await prefsWith({});
    await OnboardingStore.storeInviteFromLink(
      prefs,
      'W7XK2P',
      userId: 'ama',
      now: clock,
    );
    await user(prefs, 'ama').reset();
    expect(user(prefs, 'ama').pendingInviteCode, isNull);
  });
}
```

- [ ] **Step 2: Run them to verify they fail**

```bash
cd /Users/user/attune
flutter test --no-pub test/core/flags/public_app_config_test.dart test/core/metrics/metric_counter_test.dart test/features/onboarding/scoped_invite_code_test.dart 2>&1 | tr '\r' '\n' | grep -E "Error: |Some tests failed" | head -3
```
Expected: compile errors and no test run, for example `Error: Error when reading 'lib/core/flags/public_app_config.dart': No such file or directory` and `Error: Undefined name 'publicAppConfigProvider'.`

- [ ] **Step 3: Add the first-frame default to `Environment`**

In `lib/core/config/env.dart`, replace exactly:

```dart
  static const bool isDebug =
      String.fromEnvironment('DEBUG', defaultValue: 'false') == 'true';
}
```

with:

```dart
  static const bool isDebug =
      String.fromEnvironment('DEBUG', defaultValue: 'false') == 'true';

  /// Spec 1 §5.3: the value of flow_signin_v2 for the first frame, until
  /// get_public_app_config has answered once (or its cached copy is read).
  /// `FLOW_V2_DEFAULT` is true in development builds and unset (false) in
  /// production builds.
  static const bool flowV2Default = bool.fromEnvironment('FLOW_V2_DEFAULT');
}
```

- [ ] **Step 4: Write the public config client**

Create `lib/core/flags/public_app_config.dart` with exactly:

```dart
import 'dart:convert';

import 'package:attune/core/config/env.dart';
import 'package:attune/core/providers/shared_prefs_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The public, pre-auth configuration (Spec 1 §2.5, §4.3 W1c, D15): the
/// effective values of the four flags a signed-out phone needs, the App
/// Store storefronts that read Declared Age Range, and the Dating
/// open-country list (ISO 3166-1 alpha-2, sorted), which comes only through
/// the server seam private.dating_open_countries().
@immutable
class PublicAppConfig {
  const PublicAppConfig({
    required this.flowSignInV2,
    required this.platformAgeSignals,
    required this.supportResourcesV2,
    required this.textScaleV2,
    required this.ageSignalStorefronts,
    required this.datingOpenCountries,
  });

  /// Everything off, nothing listed: what an unreadable config means.
  static const off = PublicAppConfig(
    flowSignInV2: false,
    platformAgeSignals: false,
    supportResourcesV2: false,
    textScaleV2: false,
    ageSignalStorefronts: [],
    datingOpenCountries: [],
  );

  final bool flowSignInV2;
  final bool platformAgeSignals;
  final bool supportResourcesV2;
  final bool textScaleV2;
  final List<String> ageSignalStorefronts;
  final List<String> datingOpenCountries;

  /// Reads get_public_app_config(). Only a literal `true` is on; only
  /// strings are kept from the lists.
  factory PublicAppConfig.fromJson(Map<String, dynamic> json) {
    final flags = json['flags'] is Map ? json['flags'] as Map : const {};
    final config = json['config'] is Map ? json['config'] as Map : const {};
    List<String> strings(Object? value) => [
      if (value is List)
        for (final item in value)
          if (item is String) item,
    ];
    return PublicAppConfig(
      flowSignInV2: flags['flow_signin_v2'] == true,
      platformAgeSignals: flags['platform_age_signals'] == true,
      supportResourcesV2: flags['support_resources_v2'] == true,
      textScaleV2: flags['text_scale_v2'] == true,
      ageSignalStorefronts: strings(config['age_signal_storefronts']),
      datingOpenCountries: strings(config['dating_open_countries']),
    );
  }

  Map<String, dynamic> toJson() => {
    'flags': {
      'flow_signin_v2': flowSignInV2,
      'platform_age_signals': platformAgeSignals,
      'support_resources_v2': supportResourcesV2,
      'text_scale_v2': textScaleV2,
    },
    'config': {
      'age_signal_storefronts': ageSignalStorefronts,
      'dating_open_countries': datingOpenCountries,
    },
  };
}

/// The one network read, so tests can replace it.
abstract class PublicAppConfigGateway {
  Future<Map<String, dynamic>> fetch();
}

class SupabasePublicAppConfigGateway implements PublicAppConfigGateway {
  SupabasePublicAppConfigGateway(this._client);

  final SupabaseClient _client;

  static const timeout = Duration(seconds: 10);

  @override
  Future<Map<String, dynamic>> fetch() async {
    final data = await _client.rpc('get_public_app_config').timeout(timeout);
    return Map<String, dynamic>.from(data as Map);
  }
}

/// The last answer, for the first frame of the next launch (no network).
class PublicAppConfigCache {
  const PublicAppConfigCache(this._prefs);

  final SharedPreferences _prefs;

  static const key = 'attune.public_config.v1';

  PublicAppConfig? read() {
    final raw = _prefs.getString(key);
    if (raw == null || raw.isEmpty) return null;
    try {
      final json = jsonDecode(raw);
      return json is Map<String, dynamic>
          ? PublicAppConfig.fromJson(json)
          : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> write(PublicAppConfig config) =>
      _prefs.setString(key, jsonEncode(config.toJson()));
}

final publicAppConfigGatewayProvider = Provider<PublicAppConfigGateway>(
  (ref) => SupabasePublicAppConfigGateway(Supabase.instance.client),
);

/// The cached copy, read synchronously at first use.
final cachedPublicAppConfigProvider = Provider<PublicAppConfig?>(
  (ref) => PublicAppConfigCache(ref.watch(sharedPreferencesProvider)).read(),
);

/// The live config. A failed read keeps the cached copy, else everything is
/// off. Re-read on resume and on a change of user (FeatureFlagRefresher).
final publicAppConfigProvider = FutureProvider<PublicAppConfig>((ref) async {
  final cache = PublicAppConfigCache(ref.read(sharedPreferencesProvider));
  try {
    final config = PublicAppConfig.fromJson(
      await ref.read(publicAppConfigGatewayProvider).fetch(),
    );
    await cache.write(config);
    return config;
  } catch (error) {
    debugPrint('[public-config] read failed: ${error.runtimeType}');
    return cache.read() ?? PublicAppConfig.off;
  }
});

/// flow_signin_v2, effective (the server applies the flag dependencies).
/// Before the first answer: the cached copy, else [Environment.flowV2Default].
final flowSignInV2Provider = Provider<bool>((ref) {
  final live = ref.watch(publicAppConfigProvider).valueOrNull;
  if (live != null) return live.flowSignInV2;
  return ref.watch(cachedPublicAppConfigProvider)?.flowSignInV2 ??
      Environment.flowV2Default;
});

/// The Dating open-country list (D15): the Welcome preview, A6 and the Me
/// slot read it here and nowhere else. Empty until the config has been read.
final datingOpenCountriesProvider = Provider<List<String>>((ref) {
  final live = ref.watch(publicAppConfigProvider).valueOrNull;
  if (live != null) return live.datingOpenCountries;
  return ref.watch(cachedPublicAppConfigProvider)?.datingOpenCountries ??
      const [];
});
```

- [ ] **Step 5: Write the metric counter**

Create `lib/core/metrics/metric_counter.dart` with exactly:

```dart
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The exact keys a client may count (Spec 1 §4.3 W1b, review S-2): the
/// rows of public.metric_client_keys. Anything else is ignored by the
/// server, so only these can be passed. `anonOk` marks the pre-auth funnel.
/// Kept in step with the seed in supabase/migrations/*_metric_counters.sql by
/// test/core/metrics/metric_counter_test.dart.
enum ClientMetricKey {
  welcomePreviewRelationship('welcome_preview:relationship', anonOk: true),
  welcomePreviewDating('welcome_preview:dating', anonOk: true),
  welcomePreviewJustMe('welcome_preview:just_me', anonOk: true),
  guestAgeOk('guest_age_ok', anonOk: true),
  signupStarted('signup_started', anonOk: true),
  signupStepName('signup_step:name', anonOk: true),
  signupStepDob('signup_step:dob', anonOk: true),
  signupStepPhone('signup_step:phone', anonOk: true),
  signupAgeStop('signup_age_stop', anonOk: true),
  pushAskShownR2('push_ask_shown:r2'),
  pushAskShownR4('push_ask_shown:r4'),
  pushAskShownJ3('push_ask_shown:j3'),
  pushAskGrantedR2('push_ask_granted:r2'),
  pushAskGrantedR4('push_ask_granted:r4'),
  pushAskGrantedJ3('push_ask_granted:j3'),
  inviteSharedWhatsapp('invite_shared:whatsapp'),
  inviteSharedShare('invite_shared:share'),
  inviteSharedQr('invite_shared:qr'),
  inviteSharedCopy('invite_shared:copy'),
  inviteNewDay7('invite_new_day7'),
  inviteDay30Shown('invite_day30_shown'),
  opinionBlockedContactInfo('opinion_blocked:contact_info'),
  opinionBlockedSlur('opinion_blocked:slur'),
  opinionBlockedExplicit('opinion_blocked:explicit'),
  supportLinkOpenedOpinions('support_link_opened:opinions'),
  supportLinkOpenedJournal('support_link_opened:journal');

  const ClientMetricKey(this.key, {this.anonOk = false});

  final String key;
  final bool anonOk;
}

typedef MetricSender = Future<void> Function(String key);

/// Fire-and-forget counting: a metric never waits, blocks or throws.
/// Counts are advisory; nothing in the app or on the server decides on them.
class MetricCounter {
  MetricCounter(this._send);

  final MetricSender _send;

  void bump(ClientMetricKey key) {
    unawaited(
      Future<void>.sync(() => _send(key.key)).catchError((Object _) {}),
    );
  }
}

final metricCounterProvider = Provider<MetricCounter>(
  (ref) => MetricCounter(
    (key) => Supabase.instance.client
        .rpc('bump_metric', params: {'p_key': key})
        .timeout(const Duration(seconds: 10)),
  ),
);
```

- [ ] **Step 6: Re-read the public config on resume and on a change of user**

In `lib/app/feature_flag_refresher.dart`, replace exactly:

```dart
import 'package:attune/app/documentations/user_manual/data/documentation_flags.dart';
```

with:

```dart
import 'package:attune/app/documentations/user_manual/data/documentation_flags.dart';
import 'package:attune/core/flags/public_app_config.dart';
```

Then replace exactly:

```dart
  documentationFlagsProvider,
];
```

with:

```dart
  documentationFlagsProvider,
  publicAppConfigProvider,
];
```

- [ ] **Step 7: Scope the invite code**

In `lib/features/onboarding/data/onboarding_store.dart`, make these five exact replacements (the fifth is in `reset()`).

Replace:

```dart
import 'dart:convert';
```

with:

```dart
import 'dart:async';
import 'dart:convert';
```

Replace:

```dart
class OnboardingStore {
  const OnboardingStore(this._prefs, {required String scope}) : _scope = scope;

  final SharedPreferences _prefs;
  final String _scope;
```

with:

```dart
DateTime _systemNow() => DateTime.now();

class OnboardingStore {
  const OnboardingStore(
    this._prefs, {
    required String scope,
    DateTime Function() now = _systemNow,
  }) : _scope = scope,
       _now = now;

  final SharedPreferences _prefs;
  final String _scope;
  final DateTime Function() _now;
```

Replace:

```dart
  static const _pendingSubmissionKey = 'pending_submission';
  static const pendingInviteCodeKey = 'attune.onboarding.pending_invite_code';
```

with:

```dart
  static const _pendingSubmissionKey = 'pending_submission';

  /// The legacy unscoped invite key: read once, moved to the anonymous slot,
  /// deleted (Spec 1 §5.5, W1c).
  static const pendingInviteCodeKey = 'attune.onboarding.pending_invite_code';
  static const _pendingInviteKey = 'pending_invite';

  /// How long a code opened while signed out may be claimed by the next
  /// account that signs in on this phone (spec §5.5).
  static const inviteClaimWindow = Duration(hours: 24);
```

Replace:

```dart
  String? get pendingInviteCode => _prefs.getString(pendingInviteCodeKey);

  Future<void> storePendingInviteCode(String code) {
    return _prefs.setString(pendingInviteCodeKey, code);
  }

  Future<void> clearPendingInviteCode() {
    return _prefs.remove(pendingInviteCodeKey);
  }
```

with:

```dart
  /// The invite code waiting for THIS scope (Spec 1 §5.5, W1c, unconditional).
  ///
  /// A link opened while signed out lands in the anonymous slot as
  /// `{code, stored_at}`; the first signed-in read claims it into this
  /// account's slot only while it is under 24 hours old, and the anonymous
  /// slot is cleared either way, so a second account on the same phone never
  /// inherits it. SharedPreferences updates its cache synchronously, so the
  /// claim is visible at once; the writes persist in the background.
  String? get pendingInviteCode {
    _moveLegacyInviteCode();
    _claimAnonymousInvite();
    return _readInvite(_key(_pendingInviteKey))?.code;
  }

  Future<void> storePendingInviteCode(String code) =>
      _prefs.setString(_key(_pendingInviteKey), _encodeInvite(code, _now()));

  Future<void> clearPendingInviteCode() async {
    await _prefs.remove(_key(_pendingInviteKey));
    await _prefs.remove(pendingInviteCodeKey);
  }

  /// main.dart's deep-link handler: signed out → the anonymous slot;
  /// signed in → straight to that account's slot.
  static Future<void> storeInviteFromLink(
    SharedPreferences prefs,
    String code, {
    String? userId,
    DateTime Function() now = _systemNow,
  }) {
    final scope = userId == null || userId.isEmpty
        ? anonymousScope
        : '$userScopePrefix.$userId';
    return OnboardingStore(prefs, scope: scope, now: now)
        .storePendingInviteCode(code);
  }

  String get _anonymousInviteKey =>
      'attune.onboarding.$anonymousScope.$_pendingInviteKey';

  void _moveLegacyInviteCode() {
    final legacy = _prefs.getString(pendingInviteCodeKey);
    if (legacy == null) return;
    if (_readInvite(_anonymousInviteKey) == null && legacy.isNotEmpty) {
      unawaited(_prefs.setString(_anonymousInviteKey, _encodeInvite(legacy, _now())));
    }
    unawaited(_prefs.remove(pendingInviteCodeKey));
  }

  void _claimAnonymousInvite() {
    if (!_scope.startsWith('$userScopePrefix.')) return;
    if (!_prefs.containsKey(_anonymousInviteKey)) return;
    final anonymous = _readInvite(_anonymousInviteKey);
    unawaited(_prefs.remove(_anonymousInviteKey));
    if (anonymous == null) return;
    if (_now().difference(anonymous.storedAt) >= inviteClaimWindow) return;
    unawaited(
      _prefs.setString(
        _key(_pendingInviteKey),
        _encodeInvite(anonymous.code, anonymous.storedAt),
      ),
    );
  }

  ({String code, DateTime storedAt})? _readInvite(String key) {
    final raw = _prefs.getString(key);
    if (raw == null || raw.isEmpty) return null;
    try {
      final json = jsonDecode(raw);
      if (json is! Map) return null;
      final code = json['code'];
      final storedAt = DateTime.tryParse(json['stored_at'] as String? ?? '');
      if (code is! String || code.isEmpty || storedAt == null) return null;
      return (code: code, storedAt: storedAt);
    } catch (_) {
      return null;
    }
  }

  static String _encodeInvite(String code, DateTime storedAt) => jsonEncode({
    'code': code,
    'stored_at': storedAt.toUtc().toIso8601String(),
  });
```

Fifth, add the slot to `reset()`: replace exactly:

```dart
    await _prefs.remove(_key(_pendingSubmissionKey));
    await _prefs.remove(pendingInviteCodeKey);
  }
```

with:

```dart
    await _prefs.remove(_key(_pendingSubmissionKey));
    await _prefs.remove(_key(_pendingInviteKey));
    await _prefs.remove(pendingInviteCodeKey);
  }
```

- [ ] **Step 8: Store a link's code in the right slot**

In `lib/main.dart`, replace exactly:

```dart
Future<void> _storePendingInviteCode(String code) async {
  final prefs = await SharedPreferences.getInstance();
  await OnboardingStore(
    prefs,
    scope: OnboardingStore.anonymousScope,
  ).storePendingInviteCode(code);
```

with:

```dart
Future<void> _storePendingInviteCode(String code) async {
  final prefs = await SharedPreferences.getInstance();
  // Spec 1 §5.5 (W1c): signed out, the code waits in the anonymous slot and
  // the next sign-in claims it within 24 h; signed in, it goes straight to
  // this account's slot.
  String? userId;
  try {
    userId = Supabase.instance.client.auth.currentUser?.id;
  } catch (_) {
    userId = null;
  }
  await OnboardingStore.storeInviteFromLink(prefs, code, userId: userId);
```

(The rest of `_storePendingInviteCode` — the comment and `unawaited(_navigateToOnboardingWhenReady());` — is unchanged; `waitForRouterSettled` and the first-launch clear stay exactly as they are, regression note R3.)

- [ ] **Step 9: Run the tests to verify they pass, and format the new files**

```bash
cd /Users/user/attune
flutter test --no-pub test/core/flags test/core/metrics test/features/onboarding test/app 2>&1 | tr '\r' '\n' | grep -E "All tests passed|Some tests failed" | tail -1
dart format lib/core/flags/public_app_config.dart lib/core/metrics/metric_counter.dart test/core/flags/public_app_config_test.dart test/core/metrics/metric_counter_test.dart test/features/onboarding/scoped_invite_code_test.dart
flutter analyze --no-pub lib/core/flags lib/core/metrics lib/core/config/env.dart lib/app/feature_flag_refresher.dart lib/features/onboarding lib/main.dart test/core/flags test/core/metrics test/features/onboarding 2>&1 | grep -E "^\s*(error|warning) " | head
```
Expected: `… All tests passed!` (including the existing `onboarding_pending_sync_test.dart`, `relationship_mode_sync_test.dart` and `feature_flag_refresher_test.dart`); `Formatted 5 files (0 changed)`; no `error`/`warning` line.

- [ ] **Step 10: W1c regression gate — SQL**

```bash
cd /Users/user/attune
for f in supabase/tests/*.sql; do
  if psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f "$f" >/dev/null 2>&1; then echo "PASS $(basename "$f")"; else echo "FAIL $(basename "$f")"; fi
done > .superpowers/sdd/2026-10-25-spec1-w1/sql-after-w1c.txt
comm -13 <(grep '^FAIL' .superpowers/sdd/2026-10-25-spec1-w1/sql-baseline.txt | sort) <(grep '^FAIL' .superpowers/sdd/2026-10-25-spec1-w1/sql-after-w1c.txt | sort)
grep identity_foundation .superpowers/sdd/2026-10-25-spec1-w1/sql-after-w1c.txt
```
Expected: the `comm` prints nothing; `PASS identity_foundation_contracts.sql`.

- [ ] **Step 11: W1c regression gate — Deno and Flutter**

```bash
cd /Users/user/attune/supabase/functions
deno test --allow-read accept-invite/ analyse-journal-entry/ purge-unfinished-signups/ 2>&1 | grep -E "passed|failed" | tail -1
cd /Users/user/attune
flutter test --no-pub 2>&1 | tr '\r' '\n' | grep -E 'All tests passed!|Some tests failed' | tail -1
flutter analyze --no-pub lib test > .superpowers/sdd/2026-10-25-spec1-w1/analyze-w1c.txt 2>&1
comm -13 .superpowers/sdd/2026-10-25-spec1-w1/analyze-errors-baseline.txt <(grep -E '^\s*error ' .superpowers/sdd/2026-10-25-spec1-w1/analyze-w1c.txt | sed -E 's/:[0-9]+:[0-9]+//' | sort -u)
diff <(grep -E 'lib/features/games/|auth_exports\.dart|lib/home/home_screen\.dart|games_contracts\.sql' .superpowers/sdd/2026-10-25-spec1-w1/git-status-before.txt) <(git status --short | grep -E 'lib/features/games/|auth_exports\.dart|lib/home/home_screen\.dart|games_contracts\.sql')
```
Expected: `ok | 13 passed | 0 failed`; `… All tests passed!`; the `comm` prints nothing; the `diff` prints nothing (no Games file, barrel, home screen or Games contract changed since Task 1).

- [ ] **Step 12: Run tests**

Steps 10–11 are the final gate. Hand the owner the checklist below.

---

## Owner deploy checklist (the plan never runs any of this)

0. **Before the push, on each project** (SQL editor, which can read `auth.users`; final review M-4: these give the pre-push baseline, so run them first).
   - **Optional:** `select count(*) from public.users where char_length(display_name) > 40;`. Migration 1 trims any such name to 40 characters (P-6); the count says how many.
   - **Drift count:** how many `users` rows hold a phone that differs from their `auth.users.phone`, and what migration 1's one-time pass will do with them. `users.phone` ends as the verified Auth phone or NULL. `will_be_restored + will_be_nulled` is what the pass changes; `will_be_nulled` also counts a row whose phone equals an *unconfirmed* Auth phone, so it is not a subset of `drift_rows`. A `format_drift` row (`+233…` against Auth's `233…`) is rewritten without the `+` when its Auth phone is confirmed (otherwise it is nulled), which changes its Dating exclusion HMAC.
   ```sql
   select count(*) filter (where u.phone is distinct from a.phone) as drift_rows,
          count(*) filter (where u.phone is distinct from a.phone
                             and a.phone_confirmed_at is not null
                             and nullif(btrim(a.phone), '') is not null) as will_be_restored,
          count(*) filter (where u.phone is not null
                             and (a.id is null or a.phone_confirmed_at is null
                                  or nullif(btrim(a.phone), '') is null)) as will_be_nulled,
          count(*) filter (where u.phone = '+' || a.phone) as format_drift
     from public.users u
     left join auth.users a on a.id = u.id;
   ```
1. **One release: one push, then one client build** (final review M-4). `supabase db push` applies every pending file in order and can't hold any back, so the thirteen W1 files go together; the single client build carries every client change (Task 4's onboarding write, Task 7's `onboarding_profiles` without `mode`, Task 11's paused Journal state and Task 12's foundation files).
   - **Order:** push the thirteen files; deploy the three edge functions in step 2 (not the purge until its go/no-go); install the new build; run the dev script (step 3).
   - **Testers still on an old build** (installed before W1), until they update:
     - sign-up (OTP, then the EULA) still works: `record_eula_acceptance` still creates the `users` row, and the insert guard sets the phone;
     - onboarding a **new** account can't save: the `users` upsert is refused (42501), and after `20261025100300` the `onboarding_profiles` upsert is refused too (`mode` is gone). The old flow then says "Saved locally" and lets them in with an empty `display_name` and no `profiles` name, **so their partner sees a blank name**. It self-heals: `OnboardingSyncService` keeps the payload, and after the update it replays through the new `submit()`;
     - already-onboarded accounts are unaffected (the app's only other `users` access is a SELECT of `id, display_name, avatar_url`), and invite accept and create run server-side;
     - the old Journal Patterns tab shows a blank padded page for `{status: 'paused'}` until the new build is installed.
   - **A new build against a database not yet pushed:** the `users` PATCH works; the `onboarding_profiles` upsert without `mode` fails (23502) until `20261025100020` or `20261025100300` lands, and is queued and replayed.
   Migration 1 itself revokes the client's `users` INSERT and UPDATE(`phone`) before its one-time phone pass (batch 2 review M3), so there is no window between its commit and the twin's, and a failed twin push still leaves `users.phone` closed; the twin re-asserts the same grants. **After the push:** `select has_column_privilege('authenticated', 'public.users', 'phone', 'UPDATE'), has_table_privilege('authenticated', 'public.users', 'INSERT');` must return `f | f`, and step 5's check must hold.
2. **Edge functions:** `supabase functions deploy accept-invite`, `supabase functions deploy create-relationship-invite`, `supabase functions deploy analyse-journal-entry`. Then `purge-unfinished-signups`, **only after its go/no-go** (batch 5 review #3). Migration `20261025100500` arms the hourly cron at push, so deploying the function is the only latch: until then the cron's call is a harmless 404.
   - **Pre-check, on each project** (SQL editor, which can read `auth.users`; it works before or after migration 6). Every table and column it names was checked on `attune_spec3a`. `candidates` is the old "created more than 24 hours ago, no `users` row" set; `active_24h` counts those with any activity (created, signed in or updated) in the last 24 hours, which the purge skips under the inactivity rule (review #1); `will_purge` is what the first runs delete (500 a run, hourly); `with_data` counts candidates that still own rows in the `auth.users`-cascade tables most likely to hold a person's data.
     ```sql
     with c as (
       select a.id, a.created_at, a.last_sign_in_at, a.updated_at, a.phone_confirmed_at
         from auth.users a
        where a.created_at < now() - interval '24 hours'
          and not exists (select 1 from public.users u where u.id = a.id))
     select count(*) as candidates,
            count(*) filter (where phone_confirmed_at is not null) as verified,
            count(*) filter (where greatest(created_at, last_sign_in_at, updated_at) >= now() - interval '24 hours') as active_24h,
            count(*) filter (where greatest(created_at, last_sign_in_at, updated_at) < now() - interval '24 hours') as will_purge,
            count(*) filter (where exists (select 1 from public.profiles p where p.id = c.id)
                                or exists (select 1 from public.opinions o where o.user_id = c.id)
                                or exists (select 1 from public.quiz_responses q where q.user_id = c.id)
                                or exists (select 1 from public.psych_profiles s where s.user_id = c.id)) as with_data,
            min(created_at) as oldest
       from c;
     ```
     To review the ids themselves: `select a.id, a.created_at, a.last_sign_in_at, a.updated_at, a.phone_confirmed_at is not null as verified from auth.users a where a.created_at < now() - interval '24 hours' and not exists (select 1 from public.users u where u.id = a.id) order by a.created_at;`
   - **GO:** `with_data = 0` **and** `active_24h = 0`, or the owner has reviewed every listed id. Then `supabase functions deploy purge-unfinished-signups`.
   - **NO-GO:** don't deploy the function. If migration `20261025100500` is already pushed, also run `select cron.unschedule('purge-unfinished-signups');` `db push` never re-runs an applied migration, so once the owner says go, re-arm it by hand in the SQL editor: `select cron.schedule('purge-unfinished-signups', '41 * * * *', $cron$SELECT public.invoke_edge_function('purge-unfinished-signups')$cron$);`.

   The purge cron (`41 * * * *`, hourly; review #8) reaches the function through the Vault `supabase_url` / `service_role_key` secrets that `20260931120000` already requires; its bearer is the service-role JWT, so the default `verify_jwt = true` holds and `supabase/config.toml` needs no entry.
3. **Turn Spec 1 on in development:** run `supabase/sql/dev_enable_spec1_flags.sql` in the SQL editor of `mrgjtyacrzfylawyzabm`. It refuses to run unless the project reads development, and the refusal and the switch-on are one statement, so a refusal turns nothing on (review #5). Without it, `journal_ai_insights` is off and **Journal insights stop on the development project too** (spec W1c gate, review A-5); with it they continue. Put this line in the release note: "Journal insights are paused wherever `journal_ai_insights` is off (all production projects until the W9c clinician gate)."
4. **Add `"FLOW_V2_DEFAULT": true` to the development `.env.json`** (production builds leave it unset). Nothing reads it before W2a; this plan didn't open `.env*`.
5. **After the push, the drift check again:** step 0's drift query, read against the invariant, must show `will_be_restored = 0` and `will_be_nulled = 0`; `drift_rows` can stay above 0 by design (an account whose Auth phone is unconfirmed keeps `users.phone` NULL, which still differs from `auth.users.phone`).
6. **At launch only (not now):** set production with `select vault.create_secret('production', 'attune_environment');` (P-1; if a secret of that name already exists, `create_secret` fails on the unique name, so update it instead: `select vault.update_secret(id, 'production') from vault.secrets where name = 'attune_environment';`; or `ALTER DATABASE postgres SET app.settings.attune_environment = 'production'` where the platform allows it). **Then confirm the flip took** (final review I-1): `select public.get_attune_environment();` must return `production`. It reads development only when every source that is set (the Vault secret and the GUC) says development, so a stray `development` in either one can't hide the flip, but check anyway before going on. Then immediately `select * from public.production_flag_violations();` and turn each listed flag off, or record its evidence with `select public.record_flag_gate_evidence('<flag>', '<review ref>');` as the service role. Then list the evidence already on record, since for an in-place flip evidence recorded during development survives into production (review #11): `select flag_key, review_ref, recorded_by, recorded_at from private.flag_production_gates where review_ref is not null;`, and confirm each row is a real sign-off for this project, or clear it (`update private.flag_production_gates set review_ref = null, recorded_by = null, recorded_at = null where flag_key = '<flag>';`) and turn that flag off.
7. **CI:** the `sql-contracts` job runs `identity_foundation_contracts.sql` against a from-scratch `supabase start`; no workflow change is needed.
8. **`dating_mode_enabled` stays false in production until Spec 2 W1a (the ex-exclusion keys on phones).**


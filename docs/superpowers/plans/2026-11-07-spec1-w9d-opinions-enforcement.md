# Spec 1 W9d (Opinions enforcement records) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make an Opinions strike count or live ban survive account deletion and re-registration (owner approval O4): `prepare_account_deletion` writes `enforcement_records` rows with scope `opinions` (count and ban end, only for a live ban or a count above 0), and `complete_sign_up`, re-created from its live body, restores them for the same phone HMAC.

**Architecture:** Three tasks, two migrations (each with a grants twin), one new contract, server-only. **Task 1 (migration 21, `20261107100000`)** adds `private.opinion_enforcement_stamps`, which records each strike under the phone HMAC the author holds *when the strike is placed* (the S2 W1 B3 I-1 ruling on the phone-change attack). It does this through one stamp line in `admin_confirm_content_removal`, re-created from its live W9b body. It also adds an owner-run backfill for older strikes, and a carry. The carry runs in `prepare_account_deletion`, re-created from its live S2 W1 body, and again from a `BEFORE DELETE` trigger on `auth.users`. It writes one `opinions` record per stamped number and never refuses (PF-F6). **Task 2 (migration 22, `20261107110000`)** re-creates `complete_sign_up` from its live body. The call that creates an account takes the records under the account's HMAC that are still inside their window, puts their count and live ban back on the profile and stamps them again, so a second deletion never double-counts. **Task 3** is the regression gate, the as-built spec amendments and the owner checklist. Everything is proven by `opinion_enforcement_records_contracts.sql` (sections A–D) and 32 mutants, all verified on a scratch copy of `attune_spec3a` while this plan was written.

**Tech Stack:** Supabase Postgres 17 (`SECURITY DEFINER` with `search_path = ''`, RLS, Vault through `public.app_setting`), psql, Python 3 (the build, edit and mutation scripts). No Dart, Deno or client change.

**Spec:** `docs/superpowers/specs/2026-10-24-app-flow-identity-design.md`: §10 O4, the owner approval (O4), §11 I-16, §8 W9a–W9e (the Opinions rules W9d must not disturb), §4.4 (the `profiles_guard_moderation_columns` guard; `complete_sign_up`'s place in sign-up), §4.7, §4.8. Also `docs/superpowers/specs/2026-10-24-dating-mode-design.md`: §4.2 `enforcement_records` (including `scope`), §6.3 (deletion and carry-over, parked accounts), §10 item 9. Rulings to mirror are in the S2 W1 ledger `.superpowers/sdd/2026-11-06-spec2-w1-dating-foundation/progress.md`: B3 I-1 (stamp at restriction time), B3 I-2 (the `auth.users` trigger), B2 (a key mismatch carries under the live key, is counted and never blocks), PF-F6 and final M-4 (never block a deletion forever), B2 O3/M-4 (no parking-time write), and B3 N-M1 (a backfill uses the number held when it runs).

## Global Constraints

- **Where:** work in the main working tree on `main` (`/Users/user/attune`, HEAD `66ac523c`, S2 W1 committed). The owner's uncommitted files (`supabase/.temp/cli-latest` and `backup-before-planning-p2.sql` at the time of writing) are never reverted, stashed, staged or reformatted. Every edit to an existing file is an exact replacement made by a script that asserts each anchor occurs exactly once. If an anchor has moved, stop and report it; do not improvise.
- **NO commits.** No `git add`, `commit`, `stash`, `checkout`, `reset` or `rm`. Tasks end with "Run tests", not "Commit".
- **No app change.** No file under `lib/` or `test/` changes (`git status --short -- lib test` stays empty at every gate). Never `dart format` a pre-existing file; W9d formats nothing. The W9 flag-off goldens (`test/features/opinions/w9/opinions_flag_off_test.dart`) must pass unchanged.
- **SQL:** contracts run only on `attune_spec3a`, from the repo root, as `psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f <file>`. A file with no top-level `BEGIN;` is wrapped as `psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -c 'BEGIN' -f <file> -c 'ROLLBACK'` (PF-F5). Before the first run, confirm the target: `psql -X -d attune_spec3a -Atc 'select current_database()'` must print `attune_spec3a`. NEVER use `attune_test`. NEVER run `scripts/local_pg_setup.sh`, `scripts/local_pg_grants.sql` or `scripts/local_pg_bootstrap.sql`; Tasks 1 and 2 only **edit** `scripts/local_pg_grants.sql`. The only lasting writes to `attune_spec3a` are applying this plan's four migration files. Mutants run inside one transaction that the contract's own `ROLLBACK` ends. A scratch database is allowed only if it is created (`createdb -T attune_spec3a <name>`) and dropped in the same task.
- **Migrations:** the newest file in the tree is `20261106200010_dating_v2_kill_switch_grants.sql` (S2 W1). W9d's files are `20261107100000_opinion_enforcement_records.sql`, `20261107100010_opinion_enforcement_records_grants.sql`, `20261107110000_opinion_enforcement_restore.sql` and `20261107110010_opinion_enforcement_restore_grants.sql`. If `ls supabase/migrations | sort | tail -1` shows anything at or after `20261107100000` when Task 1 starts, shift all four to the next free hours, keeping their order, and change every header, `\i` line and command below to match. Each file:
  - is one `BEGIN; … COMMIT;`;
  - is idempotent (applied twice, `exit=0` both times);
  - starts with `SET LOCAL lock_timeout = '5s'`;
  - has explicit grants. Nothing reaches `anon`. Every new private object is revoked from `PUBLIC, anon, authenticated, service_role`, in the migration and again in its twin (the S2 W1 batch-2 carry: hosted projects grant `service_role` every new function). The entry points keep exactly their current grants: `admin_confirm_content_removal` and `prepare_account_deletion` belong to the service role only, and `complete_sign_up` to `authenticated` only. `enforcement_records`' grants are not touched.
- **Re-created functions** start from their LIVE bodies, saved from `pg_get_functiondef` on `attune_spec3a` in Task 1, Step 2. The build scripts insert only lines marked `-- Spec 1 W9d`. After applying, the body is diffed against `pg_get_functiondef` and every changed line must carry that mark. W9d re-creates exactly three: `admin_confirm_content_removal(text,uuid)` (live body: Spec 1 W9b, `20261104120000`), `prepare_account_deletion(uuid)` (live: S2 W1 final fix, `20261106120000`) and `complete_sign_up(text,date,text)` (live: Spec 1 W1b, `20261025100200`). **No Dating function is re-created.**
- **Never refuse (PF-F6).** Nothing in W9d may refuse a removal, a deletion or a sign-up. Every path that carries or restores nothing is counted under the `opinions.` metric prefix (owner `spec1`).
- **Every fail-closed branch has a mutant** that turns its contract red with the expected message. Contract comparisons use `IS DISTINCT FROM`, never `<>`. A write and the read that checks it are separate statements.
- **Opinions owner rule:** only what W9d names changes in Opinions. That is `admin_confirm_content_removal`'s stamp lines; nothing else in Opinions (no RPC, policy, notice, copy or client file). The removal's return values and notices stay exactly as they are (contract B pins `1/false 2/false 3/true`).
- **Never touch:** in-chat Games (`test/architecture/games_untouched_test.dart` stays green); `ATTUNE_SOUL.md`; `ATTUNE_THESIS.md`; `lib/home/home_screen.dart`'s latch (byte-identical: Task 1 saves its hash and Task 3 compares it); every applied migration; every edge function. Existing contracts are edited only where W9d changes what they pin: `dating_rls_canary.sql` (new allow-list rows) and `identity_foundation_contracts.sql` (Spec 1's server-prefix seed count 10 → 11).
- **No deploys.** `supabase db push`, the backfill run and the owner decisions belong to the owner (see "Owner deploy checklist"). Don't read `.env*`, credentials or the keychain.
- **Regression set** (Task 3, and the end of Tasks 1–2 where named). Every contract that touches `prepare_account_deletion` or `complete_sign_up` is PASS:
  - `account_deletion_contracts`, `dormancy_contracts` (fresh start, parking, the purge), `identity_foundation_contracts` (sign-up), `otp_delivery_contracts` and `invite_age_contracts` (sign-in);
  - the S2 W1 identity contracts: `dating_v2_identity_contracts`, `dating_v2_eligibility_contracts`, `dating_v2_setup_contracts` and `dating_rls_canary`;
  - the W9 Opinions contracts: `opinion_moderation_notice_contracts`, `opinion_filter_contracts`, `opinion_filter_parity_contracts`, `opinion_remove_own_contracts` and `forum_retirement_contracts`;
  - `service_role_grants_test` and the new `opinion_enforcement_records_contracts`.

  Across the whole suite, no FAIL may appear that isn't in Task 1's two baseline runs, outside the AI-session group (`ai_session_*`, `ai_assist*`, `ai_processing_*`: these read rows their own earlier runs leave behind). For any new FAIL inside that group, its first ERROR must name no Opinions or deletion object.

## Review Focus

1. **A banned person moves their account to someone else's number and deletes it** (the phone-change attack, S2 W1 B3 I-1). Expect the ban to stay with the number it was earned on, and the victim to sign up clean. Tests: Task 1 contract C (`a ban landed on the number the account moved to`), Task 2 contract D (`the number an attacker moved to inherited their strikes`); mutant `carry_deletion_time_number`.
2. **A stranger gets the number long after the deletion** (a recycled number, Spec 1 O3). Expect nothing restored once the record's window has passed, and the record removed. Tests: Task 2 contract D (`a record past its window restored, or was kept`); mutants `restore_ignores_window`, `window_two_years_in_carry`, `window_value`.
3. **A person deletes and re-registers twice.** Expect the count to keep growing correctly (4, never 7). Tests: Task 2 contract D (`did not give back exactly 4 strikes`); mutants `restore_keeps_records`, `restore_not_restamped`.
4. **A removal is confirmed in the seconds between `prepare_account_deletion` and Auth's delete, or someone deletes the account from the dashboard without prepare.** Expect the strike to carry anyway. Tests: Task 1 contract C (`a strike placed after prepare did not carry`, `a deletion without prepare did not carry`); mutants `no_auth_trigger`, `late_pass_lowers`.
5. **The exclusion key is missing, or has been replaced, at strike, deletion or sign-up time.** Expect every action to complete: no stamp or restore without a key, live-key behaviour under a replaced key, each case counted. Tests: Task 1 contract B and C, Task 2 contract D (each `… was not counted` line); mutants `unstamped_not_counted`, `stamp_key_not_ready_not_counted`, `carry_key_not_ready_not_counted`, `uncarried_not_counted`, `key_missing_not_counted`, `key_not_ready_not_counted`.

## Decisions found while verifying the code (read before Task 1)

All of these were verified on a scratch copy of `attune_spec3a` at HEAD `66ac523c`: four migrations applied twice, the contract passing, 32/32 mutants killed, and the whole suite at 156 PASS / 14 FAIL before and after.

- **P-1 (files).** Two migrations, each with a twin (spec §4.7 rows 21 and 22, added by Task 3). Task 1 builds migration 21 and Task 2 builds migration 22, each from the saved live bodies, using a build script that asserts its anchors.
- **P-2 (stamps per number, not per account).** `private.opinion_enforcement_stamps (id, user_id → auth.users ON DELETE CASCADE, phone_hmac, strikes, ban_until, stamped_at, UNIQUE (user_id, phone_hmac))`. Each confirmed removal adds 1 to the row for the HMAC the author holds at that moment, and raises `ban_until` to the ban it set. The FK targets `auth.users` (as `profiles.id` does), because an author can have a profile without a `public.users` row. The deletion carries one `enforcement_records` row per stamp: `source_restriction_id` is the stamp's id, which makes the write idempotent. The spec's "the count and the ban end" is therefore held per number the strikes were earned on. A person who changed number between strikes keeps the strikes on each number, which is the B3 I-1 trade-off ("not followed onto the new number"). The spec's intent is unchanged.
- **P-3 (record shape).** For scope `opinions`, rows use `restriction_type 'opinions_standing'`, `category NULL`, `confirmed_report_count` = strikes and `effect_until` = the ban end while live. For this scope NULL means *no ban*, never "permanent". The CHECK only gains the value. There is no scope/type pairing CHECK, because `dating_v2_identity_contracts.sql` section B moves a `'suspended'` row to scope `opinions` to prove that Opinions records never close Dating, and a pairing CHECK would break that S2 W1 contract. Dating's only reader (`dating_account_in_good_standing`) filters `scope = 'dating'`, and contract C re-proves this.
- **P-4 (the recycled-number rule; OWNER DECISION W9d-1; narrows "like Dating's").** A Dating record is kept 2 years. An Opinions record's `purge_after` is the deletion + `private.opinion_carry_window()` (**30 days**), or the live ban's end if that is later, capped at 2 years. A restore takes only records still inside it; records past it are removed at that sign-up and restore nothing. The reasoning: a person dodging a 7-day pause re-registers within days, and a carrier recycles a number only after months of inactivity plus quarantine, so a short window separates the same person from a stranger. It also matches O3's presumption that a new holder is a new person, and it keeps the least data. The window lives in one function; a different ruling is a one-line migration. Neither the spec nor this plan can tell the same person from a stranger by any other signal (the HMAC is all that survives).
- **P-5 (parked accounts; OWNER DECISION W9d-2; narrows the spec's "writes an opinions record").** A parked account (`users.phone_released_at` set: Spec 1's fresh start presumed its number now belongs to someone else) carries nothing at its 180-day purge, counted `opinions.deletion.parked_not_carried`. This follows Spec 1 O3 and the S2 W1 B2 O3/M-4 ruling (no parking-time write). Dating's own carry at the purge is unchanged.
- **P-6 (restore takes the records).** The restore deletes the records it reads, in the same statement (`DELETE … RETURNING`), and stamps the restored count and ban under the new account. A later deletion then carries them once, and the old records are never summed again (contract D: 4, never 7). A failed restore rolls back inside its own block, so the records stay.
- **P-7 (only the creating call restores).** The restore runs inside `IF v_created` (the call that stored the DOB). A repeated `complete_sign_up`, or an account that already existed, never takes a record (contract D).
- **P-8 (the `auth.users` trigger).** `opinions_carry_on_auth_user_delete` (`BEFORE DELETE ON auth.users`, never raises) runs the carry again as the final pass. A strike placed between prepare and `deleteUser`, or a delete that skips prepare, still carries; this mirrors Dating's B3 I-2 trigger and its `SECURITY DEFINER` pattern. Only the final pass counts `uncarried` and `key_not_ready`, so each deletion counts once.
- **P-9 (no key-missing refusal).** Unlike Dating (which refuses a deletion while the key is missing and a live restriction exists), Opinions never refuses. Its stamps need no key at deletion, and an unstamped strike is counted `opinions.deletion.uncarried`. This follows the brief's PF-F6 line ("a missing key carries nothing and is counted").
- **P-10 (key fingerprint).** A key whose fingerprint isn't ready (`private.dating_exclusion_key_ready()` false: mismatch or unseeded) still lets stamps, carries and restores run under the live key, each counted `…key_not_ready`. W1 final I-3 means the key is never rotated, so a mismatch is a misconfigured secret that the owner puts back.
- **P-11 (locks).** No shared Dating lock applies: W9d never touches `dating_*` rows, and the Dating lock order is unaffected. The carry takes only the profile row (`FOR UPDATE`), so a removal confirmed during the deletion is either seen or waits for it. A deadlock with a concurrent removal surfaces as `40P01`: at the trigger it is caught and counted; elsewhere it is an error that the caller already retries (delete-account, the moderator). No bounded retry is added.
- **P-12 (counters, no health change).** The new server prefix is `opinions.` (owner `spec1`), so `identity_foundation_contracts.sql`'s seed count goes from 10 to 11. W9d adds no health function. The owner reads the counters (checklist item 3).
- **P-13 (no notice, no client change).** A restored ban sends no notice; the existing Opinions ban UI applies. Nothing in the app changes.
- **P-14 (backfill).** `private.opinion_stamp_backfill()` stamps strikes and live bans that no stamp covers. These are strikes from before W9d, or strikes placed while the key was missing. It stamps them under the number each account holds when it runs (B3 N-M1). It returns -1 without the key. Migration 21 runs it; with no key, it is the owner's step (checklist item 1).

## Owner decisions (genuine; each has a recommendation)

1. **W9d-1, the recycled-number restore rule.** **Recommendation: restore only within 30 days of the deletion** (or while a carried ban is still live, if later), as built. Alternatives: 90 days, or the spec-literal 2 years "like Dating's". The longer the window, the more likely it is that a stranger who gets a recycled number inherits a stranger's strikes.
2. **W9d-2, parked accounts carry nothing.** **Recommendation: yes**, as built (Spec 1 O3).

## Interfaces this plan consumes (read from the current code)

- `public.dating_phone_hmac_for_user(uuid) → text`: the HMAC of the Auth number (`'+' || digits`), or `parked_phone_hmac` for a parked account; NULL without the key.
- `public.dating_phone_hmac(text) → text` and the fingerprint label `'attune:dating_exclusion_key:fingerprint:v1'`: NULL means no key.
- `private.dating_exclusion_key_ready() → boolean`; `private.seed_dating_exclusion_key_fingerprint() → text` (`'ready' | 'mismatch' | 'missing_key'`).
- `private.bump_metric_internal(text)`: counts only keys under a registered `public.metric_key_prefixes` prefix.
- `public.enforcement_records`: columns as in Spec 2 §4.2; `UNIQUE (source_restriction_id)`; `purge_after <= created_at + 2 years 1 day`; the service role keeps DML, and the canary pins it.
- `profiles.confirmed_violation_count int`, `profiles.banned_until timestamptz`. The guard `private.guard_profile_moderation_columns` acts only for `authenticated`/`anon`, so definer functions write both.
- `users.phone_released_at` (parked).

## Interfaces this plan produces

- `private.opinion_enforcement_stamps` (P-2).
- `private.opinion_carry_window() → interval` (`'30 days'`).
- `private.opinion_stamp_enforcement(p_user uuid, p_strikes integer, p_ban_until timestamptz) → boolean` (true when stamped; never raises).
- `private.opinion_stamp_backfill() → integer` (accounts stamped; -1 without the key).
- `private.opinion_deletion_carry(p_user uuid, p_final boolean) → integer` (rows written or raised).
- `private.opinion_carry_on_auth_user_delete()`: the trigger function; trigger `opinions_carry_on_auth_user_delete` on `auth.users`.
- `private.opinion_restore_on_sign_up(p_user uuid) → integer` (records restored).
- Metric keys: `opinions.enforcement.{unstamped,key_not_ready,stamp_failed}`, `opinions.deletion.{uncarried,key_not_ready,parked_not_carried,prepare_carry_failed,late_carry_failed}`, `opinions.restore.{applied,failed,key_missing,key_not_ready}`.

## File map

- Create: `supabase/migrations/20261107100000_opinion_enforcement_records.sql`, `…100010_opinion_enforcement_records_grants.sql` (Task 1); `supabase/migrations/20261107110000_opinion_enforcement_restore.sql`, `…110010_opinion_enforcement_restore_grants.sql` (Task 2).
- Create: `supabase/tests/opinion_enforcement_records_contracts.sql` (A–C in Task 1, D in Task 2).
- Modify: `supabase/tests/dating_rls_canary.sql` (allow-list rows, Tasks 1–2); `supabase/tests/identity_foundation_contracts.sql` (seed count, Task 1); `scripts/local_pg_grants.sql` (two `\i` lines, Tasks 1–2; never run).
- Modify (Task 3): `docs/superpowers/specs/2026-10-24-app-flow-identity-design.md` (§4.7 rows 21–22, §4.8 two rows, §8 W9d, the O4 approval line); `docs/superpowers/specs/2026-10-24-dating-mode-design.md` (§4.2 `enforcement_records` row, §10 item 9).
- Plan helpers (git-ignored): `.superpowers/sdd/2026-11-07-spec1-w9d/{before/*.sql, build_m1.py, build_m2.py, edit_t1.py, edit_t2.py, edit_docs.py, m1_muts.py, m2_muts.py, sectionD.sql, mutate.py, section.py, sql-baseline-1.txt, sql-baseline-2.txt, sql-after.txt, latch.sha}`.

---

### Task 1: Baselines; migration 21: stamps at strike time and the deletion carry (O4, I-16; S2 W1 B3 I-1, I-2, PF-F6, B2; Spec 1 O3)

**Files:**
- Create: `supabase/migrations/20261107100000_opinion_enforcement_records.sql`, `supabase/migrations/20261107100010_opinion_enforcement_records_grants.sql`, `supabase/tests/opinion_enforcement_records_contracts.sql`
- Modify: `supabase/tests/dating_rls_canary.sql`, `supabase/tests/identity_foundation_contracts.sql`, `scripts/local_pg_grants.sql`
- Helpers: `.superpowers/sdd/2026-11-07-spec1-w9d/*`

**Interfaces:**
- Consumes: the "Interfaces this plan consumes" list.
- Produces: everything in "Interfaces this plan produces" except `private.opinion_restore_on_sign_up` and the `opinions.restore.*` keys; the contract helpers `pg_temp.id/h/person/strike/delete_account/records/metric`, which Task 2's section D uses.

- [ ] **Step 1: Confirm the target and the newest migration; save the latch; record two baselines**

```bash
psql -X -d attune_spec3a -Atc "select current_database(), to_regclass('public.enforcement_records') is not null, to_regclass('private.opinion_enforcement_stamps') is null"
ls supabase/migrations | sort | tail -1
git status --short -- lib test supabase scripts docs
D=.superpowers/sdd/2026-11-07-spec1-w9d; mkdir -p $D/before $D/mut
cp .superpowers/sdd/2026-11-06-spec2-w1/mutate.py .superpowers/sdd/2026-11-06-spec2-w1/section.py $D/
sed -n '/if (isAuthenticated \&\& !_gateData.isComplete) {/,/_redirectingToOnboarding = false;/p' lib/home/home_screen.dart | shasum > $D/latch.sha; cat $D/latch.sha
for run in 1 2; do
  for f in supabase/tests/*.sql; do
    if grep -qE '^BEGIN;' "$f"; then a=(-f "$f"); else a=(-c 'BEGIN' -f "$f" -c 'ROLLBACK'); fi
    if psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a "${a[@]}" >/dev/null 2>&1; then echo "PASS $(basename "$f")"; else echo "FAIL $(basename "$f")"; fi
  done > $D/sql-baseline-$run.txt
  echo "run $run: $(grep -c '^PASS' $D/sql-baseline-$run.txt) PASS, $(grep -c '^FAIL' $D/sql-baseline-$run.txt) FAIL"
done
```

Expected: `attune_spec3a|t|t`; `20261106200010_dating_v2_kill_switch_grants.sql`; only the owner's ` M supabase/.temp/cli-latest`; `8fe95dbcc4e4e825401daaf612409114e5bed421  -`. Two baseline lines, recorded as printed (the scratch copy printed `156 PASS, 14 FAIL`); every regression-set file is PASS in both.

- [ ] **Step 2: Save the three live bodies W9d re-creates**

```bash
D=.superpowers/sdd/2026-11-07-spec1-w9d
for sig in 'public.admin_confirm_content_removal(text,uuid)' 'public.prepare_account_deletion(uuid)' 'public.complete_sign_up(text,date,text)'; do
  psql -X -d attune_spec3a -Atc "select pg_get_functiondef('$sig'::regprocedure)" > "$D/before/$sig.sql"
done
grep -c 'Spec 1 W9b: OPN-BAN-42702' "$D/before/public.admin_confirm_content_removal(text,uuid).sql"
grep -c "PERFORM private.dating_deletion_carry(p_user_id, false);" "$D/before/public.prepare_account_deletion(uuid).sql"
grep -c "PERFORM private.bump_metric_internal('signup_completed');" "$D/before/public.complete_sign_up(text,date,text).sql"
```

Expected: `1`, `1`, `1` (the W9b body, the S2 W1 body with the Dating carry, and the W1b sign-up).

- [ ] **Step 3: Write the contract (sections A–C) and see it fail**

Create `supabase/tests/opinion_enforcement_records_contracts.sql` with exactly:

```sql
-- supabase/tests/opinion_enforcement_records_contracts.sql
-- Spec 1 W9d (§10 O4, owner approval O4; review I-16; Spec 2 §4.2
-- enforcement_records, §6.3; S2 W1 rulings B3 I-1, B3 I-2, B2 key
-- mismatch, PF-F6; Spec 1 O3): an Opinions strike count or live ban
-- survives account deletion under the phone HMAC stamped when it was
-- placed, never the number held at deletion; nothing ever refuses a
-- deletion or a sign-up; a parked account carries nothing; every path that
-- carries nothing is counted.
-- One BEGIN ... ROLLBACK. Run only on attune_spec3a:
--   psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/opinion_enforcement_records_contracts.sql
-- Fixture ids 5f9d0000-0000-0000-0000-0000000000NN; phones 155586040NN on
-- auth.users (Auth's form, no '+'), copied to public.users.
BEGIN;

DO $$
BEGIN
  PERFORM set_config('app.settings.dating_exclusion_key', 'spec1-w9d-contract-exclusion-key', true);
  -- The key is "ready": its fingerprint is the stored one (rolled back).
  DELETE FROM private.dating_key_fingerprints WHERE name = 'dating_exclusion_key';
  IF private.seed_dating_exclusion_key_fingerprint() IS DISTINCT FROM 'ready' THEN
    RAISE EXCEPTION 'CONTRACT SETUP: the contract key could not be made ready';
  END IF;
END $$;

CREATE FUNCTION pg_temp.id(p_n text) RETURNS uuid LANGUAGE sql IMMUTABLE AS $$
  SELECT ('5f9d0000-0000-0000-0000-0000000000' || p_n)::uuid;
$$;

-- The HMAC of fixture number 155586040<p_n>, as dating_phone_hmac_for_user computes it.
CREATE FUNCTION pg_temp.h(p_n text) RETURNS text LANGUAGE sql AS $$
  SELECT public.dating_phone_hmac('+155586040' || p_n);
$$;

-- An adult account [p_n] with a profile, phone 155586040<p_n>.
CREATE FUNCTION pg_temp.person(p_n text) RETURNS uuid LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO auth.users (id, phone, phone_confirmed_at, created_at)
  VALUES (pg_temp.id(p_n), '155586040' || p_n, now() - interval '400 days', now() - interval '400 days');
  INSERT INTO public.users (id, phone, display_name, created_at, eula_accepted_at, eula_version)
  VALUES (pg_temp.id(p_n), '155586040' || p_n, 'W9d person ' || p_n, now() - interval '400 days', now(), '2');
  INSERT INTO public.profiles (id) VALUES (pg_temp.id(p_n));
  RETURN pg_temp.id(p_n);
END $$;

-- One confirmed removal of a new post by [p_user], as the service role
-- (how the SQL editor and edge functions reach it): 'count/banned'.
CREATE FUNCTION pg_temp.strike(p_user uuid) RETURNS text LANGUAGE plpgsql AS $$
DECLARE
  v_id uuid;
  v_r record;
BEGIN
  INSERT INTO public.opinions (user_id, content) VALUES (p_user, 'W9d contract: a post') RETURNING id INTO v_id;
  PERFORM set_config('request.jwt.claims', json_build_object('role', 'service_role')::text, true);
  SELECT * INTO v_r FROM public.admin_confirm_content_removal('opinion', v_id);
  PERFORM set_config('request.jwt.claims', '', true);
  RETURN v_r.violation_count || '/' || (v_r.banned_until IS NOT NULL);
END $$;

-- The full deletion path: prepare twice (delete-account retries), then
-- Auth's delete (the BEFORE DELETE triggers, then the cascade).
CREATE FUNCTION pg_temp.delete_account(p_user uuid) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM public.prepare_account_deletion(p_user);
  PERFORM public.prepare_account_deletion(p_user);
  DELETE FROM auth.users WHERE id = p_user;
END $$;

-- The Opinions records under [p_hmac]: 'count/ban?' per row, by count.
CREATE FUNCTION pg_temp.records(p_hmac text) RETURNS text LANGUAGE sql AS $$
  SELECT coalesce(string_agg(e.confirmed_report_count || '/' || (e.effect_until IS NOT NULL), ' '
                             ORDER BY e.confirmed_report_count), '')
    FROM public.enforcement_records AS e WHERE e.scope = 'opinions' AND e.phone_hmac = p_hmac;
$$;

CREATE FUNCTION pg_temp.metric(p_key text) RETURNS bigint LANGUAGE sql AS $$
  SELECT coalesce(sum(count), 0)::bigint FROM public.metric_counters WHERE key = p_key;
$$;

-- =====================================================================
-- A. Grants and shape: the stamps and every helper are no API role's;
--    the two entry points stay the service role's; the trigger is on
--    auth.users; the reserved scope takes the new type.
-- =====================================================================
DO $$
DECLARE
  v_role text;
  v_fn text;
BEGIN
  FOREACH v_role IN ARRAY ARRAY['anon', 'authenticated', 'service_role'] LOOP
    IF has_table_privilege(v_role, 'private.opinion_enforcement_stamps', 'SELECT')
       OR has_table_privilege(v_role, 'private.opinion_enforcement_stamps', 'INSERT')
       OR has_table_privilege(v_role, 'private.opinion_enforcement_stamps', 'UPDATE')
       OR has_table_privilege(v_role, 'private.opinion_enforcement_stamps', 'DELETE') THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: % can reach the Opinions stamps', v_role;
    END IF;
    FOREACH v_fn IN ARRAY ARRAY['private.opinion_carry_window()',
                                'private.opinion_stamp_enforcement(uuid,integer,timestamptz)',
                                'private.opinion_stamp_backfill()',
                                'private.opinion_deletion_carry(uuid,boolean)',
                                'private.opinion_carry_on_auth_user_delete()'] LOOP
      IF has_function_privilege(v_role, v_fn, 'EXECUTE') THEN
        RAISE EXCEPTION 'CONTRACT VIOLATED: % can execute %', v_role, v_fn;
      END IF;
    END LOOP;
  END LOOP;
  FOREACH v_fn IN ARRAY ARRAY['public.admin_confirm_content_removal(text,uuid)',
                              'public.prepare_account_deletion(uuid)'] LOOP
    IF has_function_privilege('anon', v_fn, 'EXECUTE') OR has_function_privilege('authenticated', v_fn, 'EXECUTE')
       OR NOT has_function_privilege('service_role', v_fn, 'EXECUTE') THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: % must be the service role''s only', v_fn;
    END IF;
  END LOOP;
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid = 'auth.users'::regclass
                  AND tgname = 'opinions_carry_on_auth_user_delete' AND NOT tgisinternal) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: no Opinions carry trigger on auth.users';
  END IF;
  IF private.opinion_carry_window() IS DISTINCT FROM interval '30 days' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the carry window is %, not the ruled 30 days', private.opinion_carry_window();
  END IF;
  INSERT INTO public.enforcement_records (phone_hmac, scope, restriction_type, purge_after)
  VALUES (repeat('a', 64), 'opinions', 'opinions_standing', now() + interval '1 day'),
         (repeat('b', 64), 'dating', 'suspended', now() + interval '1 day');
  DELETE FROM public.enforcement_records WHERE phone_hmac IN (repeat('a', 64), repeat('b', 64));
END $$;

-- =====================================================================
-- B. Stamps at strike time: each confirmed removal stamps the author's
--    number at that moment (and the ban it set); no HMAC means no stamp,
--    counted; a not-ready key stamps anyway, counted; a stamp failure
--    never fails the removal; the backfill stamps what no stamp covers.
-- =====================================================================
DO $$
DECLARE
  v_a uuid := pg_temp.person('01');
  v_b uuid := pg_temp.person('02');
  v_c uuid := pg_temp.person('03');
  v_d uuid := pg_temp.person('04');
  v_got text;
  v_before bigint;
  v_ban timestamptz;
BEGIN
  -- Strikes 1-3: the removal returns exactly what it did before W9d.
  v_got := pg_temp.strike(v_a) || ' ' || pg_temp.strike(v_a) || ' ' || pg_temp.strike(v_a);
  IF v_got IS DISTINCT FROM '1/false 2/false 3/true' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the removal''s result changed: %', v_got;
  END IF;
  SELECT p.banned_until INTO v_ban FROM public.profiles AS p WHERE p.id = v_a;
  IF (SELECT s.strikes || '/' || (s.ban_until = v_ban) FROM private.opinion_enforcement_stamps AS s
       WHERE s.user_id = v_a AND s.phone_hmac = pg_temp.h('01')) IS DISTINCT FROM '3/true'
     OR (SELECT count(*) FROM private.opinion_enforcement_stamps AS s WHERE s.user_id = v_a) IS DISTINCT FROM 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: three strikes and the ban were not stamped under the author''s number';
  END IF;

  -- A strike, a number change, a strike: one stamp per number.
  PERFORM pg_temp.strike(v_b);
  UPDATE auth.users SET phone = '15558604099' WHERE id = v_b;
  PERFORM pg_temp.strike(v_b);
  IF (SELECT string_agg(s.strikes::text, ',' ORDER BY s.phone_hmac = pg_temp.h('02') DESC)
        FROM private.opinion_enforcement_stamps AS s WHERE s.user_id = v_b) IS DISTINCT FROM '1,1'
     OR NOT EXISTS (SELECT 1 FROM private.opinion_enforcement_stamps AS s
                     WHERE s.user_id = v_b AND s.phone_hmac = pg_temp.h('99')) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a strike was not stamped under the number held when it was placed';
  END IF;

  -- No key: the removal still counts, nothing is stamped, counted.
  v_before := pg_temp.metric('opinions.enforcement.unstamped');
  PERFORM set_config('app.settings.dating_exclusion_key', '', true);
  v_got := pg_temp.strike(v_c);
  PERFORM set_config('app.settings.dating_exclusion_key', 'spec1-w9d-contract-exclusion-key', true);
  IF v_got IS DISTINCT FROM '1/false'
     OR EXISTS (SELECT 1 FROM private.opinion_enforcement_stamps AS s WHERE s.user_id = v_c)
     OR pg_temp.metric('opinions.enforcement.unstamped') IS DISTINCT FROM v_before + 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a strike without the key was lost, stamped or not counted (%)', v_got;
  END IF;

  -- A replaced key (fingerprint not ready): stamped under the live key, counted.
  v_before := pg_temp.metric('opinions.enforcement.key_not_ready');
  PERFORM set_config('app.settings.dating_exclusion_key', 'spec1-w9d-contract-other-key', true);
  PERFORM pg_temp.strike(v_c);
  IF NOT EXISTS (SELECT 1 FROM private.opinion_enforcement_stamps AS s
                  WHERE s.user_id = v_c AND s.phone_hmac = public.dating_phone_hmac('+15558604003'))
     OR pg_temp.metric('opinions.enforcement.key_not_ready') IS DISTINCT FROM v_before + 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: under a replaced key the strike was not stamped under the live key and counted';
  END IF;
  DELETE FROM private.opinion_enforcement_stamps WHERE user_id = v_c; -- that stamp is under a key the rest of the file doesn't use
  PERFORM set_config('app.settings.dating_exclusion_key', 'spec1-w9d-contract-exclusion-key', true);

  -- A stamp that fails never fails the removal; counted.
  v_before := pg_temp.metric('opinions.enforcement.stamp_failed');
  ALTER TABLE private.opinion_enforcement_stamps ADD CONSTRAINT w9d_contract_refuse CHECK (strikes < 0) NOT VALID;
  v_got := pg_temp.strike(v_d);
  ALTER TABLE private.opinion_enforcement_stamps DROP CONSTRAINT w9d_contract_refuse;
  IF v_got IS DISTINCT FROM '1/false'
     OR pg_temp.metric('opinions.enforcement.stamp_failed') IS DISTINCT FROM v_before + 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a failing stamp failed the removal or was not counted (%)', v_got;
  END IF;

  -- The backfill: person 03 (2 strikes, none stamped) and 04 (1 strike,
  -- none stamped, plus a live ban set directly) are stamped once.
  UPDATE public.profiles SET banned_until = now() + interval '3 days' WHERE id = v_d;
  IF private.opinion_stamp_backfill() < 2 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the backfill stamped fewer than the two uncovered accounts';
  END IF;
  IF (SELECT s.strikes FROM private.opinion_enforcement_stamps AS s
       WHERE s.user_id = v_c AND s.phone_hmac = pg_temp.h('03')) IS DISTINCT FROM 2
     OR (SELECT s.strikes || '/' || (s.ban_until > now() + interval '2 days') FROM private.opinion_enforcement_stamps AS s
          WHERE s.user_id = v_d AND s.phone_hmac = pg_temp.h('04')) IS DISTINCT FROM '1/true' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the backfill did not stamp the uncovered strikes and the live ban';
  END IF;
  IF private.opinion_stamp_backfill() IS DISTINCT FROM 0
     OR (SELECT sum(s.strikes) FROM private.opinion_enforcement_stamps AS s WHERE s.user_id IN (v_a, v_b, v_c, v_d))
        IS DISTINCT FROM 8 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a second backfill stamped again';
  END IF;
  PERFORM set_config('app.settings.dating_exclusion_key', '', true);
  IF private.opinion_stamp_backfill() IS DISTINCT FROM -1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the backfill ran without the key';
  END IF;
  PERFORM set_config('app.settings.dating_exclusion_key', 'spec1-w9d-contract-exclusion-key', true);
END $$;

-- =====================================================================
-- C. Carry at deletion: one record per stamp, under the stamped number;
--    only a live ban or a count above 0; the 30-day window; never the
--    deletion-time number (the phone-change attack); a parked account
--    carries nothing; a strike between prepare and the delete, or a
--    delete without prepare, still carries; nothing ever refuses; each
--    gap is counted once.
-- =====================================================================
DO $$
DECLARE
  v_a uuid := pg_temp.id('01');   -- 3 strikes, live ban, number 01
  v_b uuid := pg_temp.id('02');   -- 1 strike on 02, 1 on 99
  v_c uuid := pg_temp.id('03');   -- 2 strikes stamped by the backfill + 1 unstamped below
  v_e uuid := pg_temp.person('05');
  v_f uuid := pg_temp.person('06');
  v_g uuid := pg_temp.person('07');
  v_i uuid := pg_temp.person('08');
  v_j uuid := pg_temp.person('09');
  v_k uuid := pg_temp.person('10');
  v_l uuid := pg_temp.person('12');
  v_ban timestamptz;
  v_before bigint;
  v_before2 bigint;
BEGIN
  -- The whole path, twice prepared: exactly one record, the ban, 30 days.
  SELECT p.banned_until INTO v_ban FROM public.profiles AS p WHERE p.id = v_a;
  PERFORM pg_temp.delete_account(v_a);
  IF pg_temp.records(pg_temp.h('01')) IS DISTINCT FROM '3/true'
     OR NOT EXISTS (SELECT 1 FROM public.enforcement_records AS e
                     WHERE e.phone_hmac = pg_temp.h('01') AND e.scope = 'opinions'
                       AND e.restriction_type = 'opinions_standing' AND e.category IS NULL
                       AND e.effect_until = v_ban
                       AND e.purge_after BETWEEN now() + interval '29 days' AND now() + interval '31 days') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the strikes and live ban did not carry as one 30-day opinions record: %',
      pg_temp.records(pg_temp.h('01'));
  END IF;
  IF EXISTS (SELECT 1 FROM private.opinion_enforcement_stamps WHERE user_id = v_a) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the stamps outlived the account';
  END IF;

  -- One record per number the strikes were placed under.
  PERFORM pg_temp.delete_account(v_b);
  IF pg_temp.records(pg_temp.h('02')) IS DISTINCT FROM '1/false'
     OR pg_temp.records(pg_temp.h('99')) IS DISTINCT FROM '1/false' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: strikes on two numbers did not carry under each: % / %',
      pg_temp.records(pg_temp.h('02')), pg_temp.records(pg_temp.h('99'));
  END IF;

  -- The phone-change attack (S2 W1 B3 I-1): three strikes and a ban on 05,
  -- then the account moves to a victim's number 98 and deletes.
  PERFORM pg_temp.strike(v_e); PERFORM pg_temp.strike(v_e); PERFORM pg_temp.strike(v_e);
  UPDATE auth.users SET phone = '15558604098' WHERE id = v_e;
  PERFORM pg_temp.delete_account(v_e);
  IF pg_temp.records(pg_temp.h('98')) IS DISTINCT FROM '' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a ban landed on the number the account moved to: %', pg_temp.records(pg_temp.h('98'));
  END IF;
  IF pg_temp.records(pg_temp.h('05')) IS DISTINCT FROM '3/true' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the ban did not stay with the number it was earned on: %', pg_temp.records(pg_temp.h('05'));
  END IF;

  -- Nothing to carry: count 0 and no ban; a stamped strike the owner has
  -- since pardoned (count 0, ban over); an expired ban on a stamp carries
  -- the count only.
  PERFORM pg_temp.strike(v_j);
  UPDATE public.profiles SET confirmed_violation_count = 0, banned_until = now() - interval '1 day' WHERE id = v_j;
  PERFORM pg_temp.delete_account(v_f);
  PERFORM pg_temp.delete_account(v_j);
  IF pg_temp.records(pg_temp.h('06')) IS DISTINCT FROM '' OR pg_temp.records(pg_temp.h('09')) IS DISTINCT FROM '' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an account with no strike and no live ban carried a record';
  END IF;
  PERFORM pg_temp.strike(v_k); PERFORM pg_temp.strike(v_k); PERFORM pg_temp.strike(v_k);
  UPDATE private.opinion_enforcement_stamps SET ban_until = now() - interval '1 hour' WHERE user_id = v_k;
  UPDATE public.profiles SET banned_until = now() - interval '1 hour' WHERE id = v_k;
  PERFORM pg_temp.delete_account(v_k);
  IF pg_temp.records(pg_temp.h('10')) IS DISTINCT FROM '3/false' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an expired ban carried, or its count did not: %', pg_temp.records(pg_temp.h('10'));
  END IF;

  -- No key at deletion: the stamps still carry (they need no key); a
  -- strike that was never stamped is counted once, and the deletion ends.
  PERFORM set_config('app.settings.dating_exclusion_key', '', true);
  PERFORM pg_temp.strike(v_c); -- unstamped
  v_before := pg_temp.metric('opinions.deletion.uncarried');
  PERFORM pg_temp.delete_account(v_c);
  PERFORM set_config('app.settings.dating_exclusion_key', 'spec1-w9d-contract-exclusion-key', true);
  IF EXISTS (SELECT 1 FROM auth.users WHERE id = v_c) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a deletion without the key did not complete';
  END IF;
  IF pg_temp.records(pg_temp.h('03')) IS DISTINCT FROM '2/false'
     OR pg_temp.metric('opinions.deletion.uncarried') IS DISTINCT FROM v_before + 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: without the key the stamped strikes did not carry, or the gap was not counted once (%)',
      pg_temp.records(pg_temp.h('03'));
  END IF;

  -- A replaced key at deletion: carried under the stamps, counted, completed.
  PERFORM pg_temp.strike(v_l);
  v_before := pg_temp.metric('opinions.deletion.key_not_ready');
  PERFORM set_config('app.settings.dating_exclusion_key', 'spec1-w9d-contract-other-key', true);
  PERFORM pg_temp.delete_account(v_l);
  PERFORM set_config('app.settings.dating_exclusion_key', 'spec1-w9d-contract-exclusion-key', true);
  IF pg_temp.records(pg_temp.h('12')) IS DISTINCT FROM '1/false'
     OR pg_temp.metric('opinions.deletion.key_not_ready') IS DISTINCT FROM v_before + 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: under a replaced key the deletion did not carry its stamps and count it (%)',
      pg_temp.records(pg_temp.h('12'));
  END IF;

  -- Parked (Spec 1 O3): nothing carries; counted once.
  v_f := pg_temp.person('13');
  PERFORM pg_temp.strike(v_f);
  UPDATE public.users SET phone_released_at = now(), parked_phone_hmac = pg_temp.h('13') WHERE id = v_f;
  v_before := pg_temp.metric('opinions.deletion.parked_not_carried');
  PERFORM pg_temp.delete_account(v_f);
  IF pg_temp.records(pg_temp.h('13')) IS DISTINCT FROM ''
     OR pg_temp.metric('opinions.deletion.parked_not_carried') IS DISTINCT FROM v_before + 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a parked account carried its strikes onto the number, or was not counted';
  END IF;

  -- A strike between prepare and Auth's delete still carries (I-2).
  PERFORM pg_temp.strike(v_g);
  PERFORM public.prepare_account_deletion(v_g);
  PERFORM pg_temp.strike(v_g);
  DELETE FROM auth.users WHERE id = v_g;
  IF pg_temp.records(pg_temp.h('07')) IS DISTINCT FROM '2/false' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a strike placed after prepare did not carry: %', pg_temp.records(pg_temp.h('07'));
  END IF;

  -- A delete that skips prepare still carries.
  PERFORM pg_temp.strike(v_i);
  DELETE FROM auth.users WHERE id = v_i;
  IF pg_temp.records(pg_temp.h('08')) IS DISTINCT FROM '1/false' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a deletion without prepare did not carry: %', pg_temp.records(pg_temp.h('08'));
  END IF;

  -- A carry that fails never refuses the deletion; counted at both passes.
  v_i := pg_temp.person('14');
  PERFORM pg_temp.strike(v_i);
  v_before := pg_temp.metric('opinions.deletion.prepare_carry_failed');
  v_before2 := pg_temp.metric('opinions.deletion.late_carry_failed');
  ALTER TABLE public.enforcement_records ADD CONSTRAINT w9d_contract_refuse CHECK (scope <> 'opinions') NOT VALID;
  PERFORM pg_temp.delete_account(v_i);
  ALTER TABLE public.enforcement_records DROP CONSTRAINT w9d_contract_refuse;
  IF EXISTS (SELECT 1 FROM auth.users WHERE id = v_i)
     OR pg_temp.metric('opinions.deletion.prepare_carry_failed') IS DISTINCT FROM v_before + 2
     OR pg_temp.metric('opinions.deletion.late_carry_failed') IS DISTINCT FROM v_before2 + 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a failing carry blocked the deletion or was not counted';
  END IF;

  -- Dating is untouched: an opinions record never closes Dating standing.
  v_i := pg_temp.person('01');
  IF NOT public.dating_account_in_good_standing(v_i) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an Opinions record closed Dating for the number';
  END IF;
  DELETE FROM auth.users WHERE id = v_i;
END $$;

DO $$ BEGIN RAISE NOTICE 'opinion_enforcement_records_contracts: all held'; END $$;
ROLLBACK;
```

Run: `psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/opinion_enforcement_records_contracts.sql 2>&1 | grep -m1 ERROR`
Expected: `ERROR:  relation "private.opinion_enforcement_stamps" does not exist`.

- [ ] **Step 4: Write the migration's build script and build migration 21**

Create `.superpowers/sdd/2026-11-07-spec1-w9d/build_m1.py` with exactly:

```python
#!/usr/bin/env python3
"""Spec 1 W9d Task 1: writes migration 1 from the LIVE bodies in before/.
usage: build_m1.py <before-dir> <out.sql>
Each insertion anchors on text that must occur exactly once in its body."""
import pathlib, sys

before, out = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])

def body(sig):
    s = (before / f'{sig}.sql').read_text().rstrip('\n')
    assert s.startswith('CREATE OR REPLACE FUNCTION ') and s.endswith('$function$'), sig
    return s + ';\n'

def insert_before(s, anchor, add, name):
    assert s.count(anchor) == 1, (name, anchor[:60], s.count(anchor))
    return s.replace(anchor, add + anchor)

def insert_after(s, anchor, add, name):
    assert s.count(anchor) == 1, (name, anchor[:60], s.count(anchor))
    return s.replace(anchor, anchor + add)

acr = body('public.admin_confirm_content_removal(text,uuid)')
acr = insert_before(acr, '  RETURN QUERY SELECT v_new_count, v_ban_until;\nEND;', (
    "  -- Spec 1 W9d (O4; S2 W1 B3 I-1): this strike, and the ban it set, are\n"
    "  -- Spec 1 W9d stamped with the number the author holds now; never raises.\n"
    "  IF v_new_count IS NOT NULL THEN -- Spec 1 W9d\n"
    "    PERFORM private.opinion_stamp_enforcement(v_author_id, 1, v_ban_until); -- Spec 1 W9d\n"
    "  END IF; -- Spec 1 W9d\n"), 'acr')

pad = body('public.prepare_account_deletion(uuid)')
pad = insert_after(pad, (
    "    PERFORM private.bump_metric_internal('dating.deletion.prepare_carry_failed'); -- Spec 2 W1 final fix (M-4)\n"
    "  END; -- Spec 2 W1 final fix (M-4)\n"), (
    "  -- Spec 1 W9d (O4): the Opinions strike count and live ban carry under\n"
    "  -- Spec 1 W9d the HMACs stamped when they were placed. Never refuses\n"
    "  -- Spec 1 W9d (PF-F6); the auth.users trigger carries again at the delete.\n"
    "  BEGIN -- Spec 1 W9d\n"
    "    PERFORM private.opinion_deletion_carry(p_user_id, false); -- Spec 1 W9d\n"
    "  EXCEPTION WHEN OTHERS THEN -- Spec 1 W9d\n"
    "    RAISE WARNING 'opinion_deletion:carry:%', SQLSTATE; -- Spec 1 W9d\n"
    "    PERFORM private.bump_metric_internal('opinions.deletion.prepare_carry_failed'); -- Spec 1 W9d\n"
    "  END; -- Spec 1 W9d\n"), 'pad')

HEADER = """-- Spec 1 W9d, migration 1 (spec §10 O4, owner approval O4; review I-16;
-- Spec 2 §4.2 enforcement_records, §6.3): an Opinions strike count or live
-- ban survives account deletion, carried in enforcement_records (scope
-- 'opinions'), keyed by phone HMAC. Restored at sign-up by migration 2.
--   * private.opinion_enforcement_stamps: per account and phone HMAC, the
--     strikes and the latest ban placed while the account held that number.
--     admin_confirm_content_removal stamps each confirmed removal with
--     dating_phone_hmac_for_user at that moment, so a deletion carries a
--     strike under the number it was earned on, never a number the account
--     changes to later (S2 W1 B3 I-1, the phone-change attack). No HMAC
--     (key missing, no phone): no stamp, counted
--     opinions.enforcement.unstamped. A key whose fingerprint isn't ready
--     still stamps under the live key, counted
--     opinions.enforcement.key_not_ready. A stamp never fails the removal.
--   * private.opinion_stamp_backfill(): owner-run (and run here when the
--     key is set): stamps strikes and live bans no stamp covers (placed
--     before W9d or while the key was missing) under the number each
--     account holds when it runs (S2 W1 B3 N-M1). Idempotent.
--   * private.opinion_deletion_carry(user, final): only a live ban or a
--     count above 0 carries (O4). One enforcement_records row per stamp
--     (source_restriction_id = the stamp's id: idempotent; a later pass
--     raises the count and ban, never lowers them); restriction_type
--     'opinions_standing', category NULL, confirmed_report_count = the
--     stamp's strikes, effect_until = its ban end while live (NULL: no
--     ban; for scope 'opinions' NULL never means permanent), purge_after =
--     now() + private.opinion_carry_window() (30 days; owner decision W9d-1),
--     or the ban end if later, capped at 2 years. A parked account (Spec 1
--     O3: its number is presumed someone else's; owner decision W9d-2)
--     carries nothing, counted
--     opinions.deletion.parked_not_carried. The final pass counts
--     opinions.deletion.uncarried when the stamps don't cover the count or
--     the live ban (PF-F6: nothing refuses, ever), and
--     opinions.deletion.key_not_ready when the key is set but its
--     fingerprint isn't ready (carried under the stamps anyway). It locks
--     the profile row only (no Dating lock), so a removal confirmed during
--     the deletion is either seen or waits.
--   * opinions_carry_on_auth_user_delete: BEFORE DELETE ON auth.users runs
--     the carry again (final), so a strike placed between prepare and
--     deleteUser, or a deletion that skips prepare, still carries (as
--     Dating's S2 W1 B3 I-2). It never raises.
--   * enforcement_records.restriction_type also allows 'opinions_standing';
--     Dating's readers filter scope = 'dating' and are unchanged.
--   * admin_confirm_content_removal re-created from its LIVE body (Spec 1
--     W9b, 20261104120000; pg_get_functiondef on attune_spec3a) and
--     prepare_account_deletion from its LIVE body (Spec 2 W1 final fix,
--     20261106120000), changing only the lines marked "Spec 1 W9d".
--   * The server metric prefix 'opinions.' (owner spec1); no client key.
-- Grants in 20261107100010_opinion_enforcement_records_grants.sql.
BEGIN;
SET LOCAL lock_timeout = '5s';

INSERT INTO public.metric_key_prefixes (prefix, owner_spec) VALUES ('opinions.', 'spec1')
ON CONFLICT (prefix) DO NOTHING;

ALTER TABLE public.enforcement_records DROP CONSTRAINT IF EXISTS enforcement_records_restriction_type_check;
ALTER TABLE public.enforcement_records ADD CONSTRAINT enforcement_records_restriction_type_check
  CHECK (restriction_type IN ('suspended', 'under_review', 'age_review', 'moderation_hold', 'opinions_standing'));
COMMENT ON TABLE public.enforcement_records IS
  'Spec 2 W1a (Q5, §6.3): a Dating restriction carried past account deletion, keyed by the number''s HMAC (dating_phone_hmac_for_user), kept 2 years. Spec 1 W9d (O4): scope opinions rows carry an Opinions strike count (confirmed_report_count) and live ban end (effect_until; NULL = no ban) under the HMAC stamped at the strike, restriction_type opinions_standing, kept private.opinion_carry_window(); complete_sign_up restores and removes them.';

CREATE TABLE IF NOT EXISTS private.opinion_enforcement_stamps (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  phone_hmac text NOT NULL CHECK (phone_hmac ~ '^[0-9a-f]{64}$'),
  strikes integer NOT NULL DEFAULT 0 CHECK (strikes >= 0),
  ban_until timestamptz,
  stamped_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, phone_hmac)
);
ALTER TABLE private.opinion_enforcement_stamps ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE private.opinion_enforcement_stamps FROM PUBLIC, anon, authenticated, service_role;
COMMENT ON TABLE private.opinion_enforcement_stamps IS
  'Spec 1 W9d (O4, S2 W1 B3 I-1): the Opinions strikes and latest ban an account received while holding each phone HMAC. Read only by the deletion carry; goes with the account.';

-- Owner decision W9d-1 (the recycled-number rule): how long a carried
-- Opinions record can be restored. One place to change it.
CREATE OR REPLACE FUNCTION private.opinion_carry_window()
 RETURNS interval
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
  SELECT interval '30 days';
$function$;

CREATE OR REPLACE FUNCTION private.opinion_stamp_enforcement(p_user uuid, p_strikes integer, p_ban_until timestamptz)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_hmac text;
BEGIN
  IF p_user IS NULL OR (coalesce(p_strikes, 0) <= 0 AND p_ban_until IS NULL) THEN
    RETURN false;
  END IF;
  BEGIN
    v_hmac := public.dating_phone_hmac_for_user(p_user);
    IF v_hmac IS NULL THEN
      PERFORM private.bump_metric_internal('opinions.enforcement.unstamped');
      RETURN false;
    END IF;
    IF NOT private.dating_exclusion_key_ready() THEN
      -- Stamped under the live key anyway (S2 W1 B2: never block, count).
      PERFORM private.bump_metric_internal('opinions.enforcement.key_not_ready');
    END IF;
    INSERT INTO private.opinion_enforcement_stamps AS s (user_id, phone_hmac, strikes, ban_until)
    VALUES (p_user, v_hmac, greatest(coalesce(p_strikes, 0), 0), p_ban_until)
    ON CONFLICT (user_id, phone_hmac) DO UPDATE
      SET strikes = s.strikes + EXCLUDED.strikes,
          ban_until = greatest(s.ban_until, EXCLUDED.ban_until),
          stamped_at = now();
    RETURN true;
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'opinion_stamp:%', SQLSTATE;
    PERFORM private.bump_metric_internal('opinions.enforcement.stamp_failed');
    RETURN false;
  END;
END;
$function$;

CREATE OR REPLACE FUNCTION private.opinion_stamp_backfill()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
-- Owner-run (owner checklist): strikes and live bans no stamp covers, under
-- the number each account holds now. -1 while the key is missing.
DECLARE
  r record;
  v_n integer := 0;
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
             WHERE s.user_id = p.id) AS stamped_ban
      FROM public.profiles AS p
     WHERE p.confirmed_violation_count > 0 OR p.banned_until > now()
  LOOP
    IF r.strikes > r.stamped OR (r.ban IS NOT NULL AND (r.stamped_ban IS NULL OR r.stamped_ban < r.ban)) THEN
      IF private.opinion_stamp_enforcement(r.id, greatest(r.strikes - r.stamped, 0), r.ban) THEN
        v_n := v_n + 1;
      END IF;
    END IF;
  END LOOP;
  RETURN v_n;
END;
$function$;

CREATE OR REPLACE FUNCTION private.opinion_deletion_carry(p_user uuid, p_final boolean)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_count integer;
  v_ban timestamptz;
  v_released timestamptz;
  v_n integer := 0;
  v_stamped integer;
  v_stamped_ban timestamptz;
BEGIN
  IF p_user IS NULL THEN
    RETURN 0;
  END IF;
  SELECT p.confirmed_violation_count, CASE WHEN p.banned_until > now() THEN p.banned_until END
    INTO v_count, v_ban
    FROM public.profiles AS p WHERE p.id = p_user
    FOR UPDATE;
  -- Only a live ban or a count above 0 carries (O4).
  IF coalesce(v_count, 0) <= 0 AND v_ban IS NULL THEN
    RETURN 0;
  END IF;
  SELECT u.phone_released_at INTO v_released FROM public.users AS u WHERE u.id = p_user;
  IF v_released IS NOT NULL THEN
    -- Parked (Spec 1 O3): the number is presumed someone else's now.
    IF p_final THEN
      PERFORM private.bump_metric_internal('opinions.deletion.parked_not_carried');
    END IF;
    RETURN 0;
  END IF;
  INSERT INTO public.enforcement_records AS er (phone_hmac, scope, source_restriction_id, restriction_type,
                                                category, confirmed_report_count, effect_until, purge_after)
  SELECT s.phone_hmac, 'opinions', s.id, 'opinions_standing', NULL, s.strikes,
         CASE WHEN s.ban_until > now() THEN s.ban_until END,
         least(greatest(now() + private.opinion_carry_window(), coalesce(s.ban_until, now())),
               now() + interval '2 years')
    FROM private.opinion_enforcement_stamps AS s
   WHERE s.user_id = p_user AND (s.strikes > 0 OR s.ban_until > now())
  ON CONFLICT (source_restriction_id) DO UPDATE
    SET confirmed_report_count = greatest(er.confirmed_report_count, EXCLUDED.confirmed_report_count),
        effect_until = greatest(er.effect_until, EXCLUDED.effect_until),
        purge_after = least(greatest(er.purge_after, EXCLUDED.purge_after), er.created_at + interval '2 years')
    WHERE er.scope = 'opinions';
  GET DIAGNOSTICS v_n = ROW_COUNT;
  IF p_final THEN
    SELECT coalesce(sum(s.strikes), 0)::integer, max(s.ban_until) INTO v_stamped, v_stamped_ban
      FROM private.opinion_enforcement_stamps AS s WHERE s.user_id = p_user;
    IF coalesce(v_count, 0) > v_stamped OR (v_ban IS NOT NULL AND (v_stamped_ban IS NULL OR v_stamped_ban < v_ban)) THEN
      PERFORM private.bump_metric_internal('opinions.deletion.uncarried');
    END IF;
    IF v_n > 0 AND NOT private.dating_exclusion_key_ready() THEN
      PERFORM private.bump_metric_internal('opinions.deletion.key_not_ready');
    END IF;
  END IF;
  RETURN v_n;
END;
$function$;

CREATE OR REPLACE FUNCTION private.opinion_carry_on_auth_user_delete()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
BEGIN
  BEGIN
    PERFORM private.opinion_deletion_carry(OLD.id, true);
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'opinion_carry_on_auth_user_delete:%', SQLSTATE;
    PERFORM private.bump_metric_internal('opinions.deletion.late_carry_failed');
  END;
  RETURN OLD;
END;
$function$;

DROP TRIGGER IF EXISTS opinions_carry_on_auth_user_delete ON auth.users;
CREATE TRIGGER opinions_carry_on_auth_user_delete
  BEFORE DELETE ON auth.users
  FOR EACH ROW EXECUTE FUNCTION private.opinion_carry_on_auth_user_delete();

"""

FOOTER = """
REVOKE ALL ON FUNCTION private.opinion_carry_window() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.opinion_stamp_enforcement(uuid, integer, timestamptz) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.opinion_stamp_backfill() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.opinion_deletion_carry(uuid, boolean) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.opinion_carry_on_auth_user_delete() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.admin_confirm_content_removal(text, uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_confirm_content_removal(text, uuid) TO service_role;
REVOKE ALL ON FUNCTION public.prepare_account_deletion(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.prepare_account_deletion(uuid) TO service_role;

-- Strikes and bans placed before this migration, when the key is set now
-- (else the owner runs it after setting the key: checklist item 1).
DO $$
BEGIN
  PERFORM private.opinion_stamp_backfill();
END $$;

COMMIT;
"""

out.write_text(HEADER + acr + '\n' + pad + FOOTER)
print(f'{out}: {out.read_text().count(chr(10))} lines')
```

```bash
D=.superpowers/sdd/2026-11-07-spec1-w9d
python3 $D/build_m1.py $D/before supabase/migrations/20261107100000_opinion_enforcement_records.sql
```

Expected: `supabase/migrations/20261107100000_opinion_enforcement_records.sql: 470 lines` (a different count only if the live bodies differ, in which case Step 7's diff decides).

- [ ] **Step 5: Write the grants twin**

Create `supabase/migrations/20261107100010_opinion_enforcement_records_grants.sql` with exactly:

```sql
-- Spec 1 W9d: grants for 20261107100000_opinion_enforcement_records.sql.
-- admin_confirm_content_removal and prepare_account_deletion stay the
-- service role's only; the stamps table and every carry helper are no API
-- role's, the service role included (hosted projects grant it every new
-- function; S2 W1 batch-2 carry). enforcement_records keeps Spec 2 W1's
-- grants (unchanged here).
BEGIN;
SET LOCAL lock_timeout = '5s';
REVOKE ALL ON FUNCTION public.admin_confirm_content_removal(text, uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_confirm_content_removal(text, uuid) TO service_role;
REVOKE ALL ON FUNCTION public.prepare_account_deletion(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.prepare_account_deletion(uuid) TO service_role;
REVOKE ALL ON TABLE private.opinion_enforcement_stamps FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.opinion_carry_window() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.opinion_stamp_enforcement(uuid, integer, timestamptz) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.opinion_stamp_backfill() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.opinion_deletion_carry(uuid, boolean) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.opinion_carry_on_auth_user_delete() FROM PUBLIC, anon, authenticated, service_role;
COMMIT;
```

- [ ] **Step 6: The existing-file edits (canary rows, the seed count, the local grants line)**

Create `.superpowers/sdd/2026-11-07-spec1-w9d/edit_t1.py` with exactly:

```python
#!/usr/bin/env python3
"""Spec 1 W9d Task 1: the three existing-file edits (each anchor exactly once).
usage: edit_t1.py <repo-root>"""
import pathlib, sys
root = pathlib.Path(sys.argv[1])

def edit(rel, old, new):
    p = root / rel
    s = p.read_text()
    assert s.count(old) == 1, (rel, old[:60], s.count(old))
    p.write_text(s.replace(old, new))
    print(f'{rel}: edited')

a = "  ('private.dating_restriction_user_immutable()', '', ''); -- W1 final fix (M-8)\n"
edit('supabase/tests/dating_rls_canary.sql', a, a + """
-- Spec 1 W9d (O4): the Opinions carry-over's helpers name enforcement_records
-- and the Dating HMAC helpers; no API role's, the service role included.
INSERT INTO allowed_fn (sig, clients, service) VALUES
  ('private.opinion_carry_on_auth_user_delete()', '', ''),
  ('private.opinion_carry_window()', '', ''),
  ('private.opinion_deletion_carry(uuid,boolean)', '', ''),
  ('private.opinion_stamp_backfill()', '', ''),
  ('private.opinion_stamp_enforcement(uuid,integer,timestamp with time zone)', '', '');
""")
edit('supabase/tests/identity_foundation_contracts.sql',
     "  -- Seeds: 26 exact client keys (9 pre-auth), 10 server prefixes.\n",
     "  -- Seeds: 26 exact client keys (9 pre-auth), 11 server prefixes (Spec 1 W9d: 'opinions.').\n")
edit('supabase/tests/identity_foundation_contracts.sql',
     "     OR (SELECT count(*) FROM public.metric_key_prefixes WHERE owner_spec = 'spec1') <> 10 THEN\n",
     "     OR (SELECT count(*) FROM public.metric_key_prefixes WHERE owner_spec = 'spec1') <> 11 THEN\n")
b = "\\i supabase/migrations/20261106200010_dating_v2_kill_switch_grants.sql\n"
edit('scripts/local_pg_grants.sql', b, b + """
-- Spec 1 W9d: admin_confirm_content_removal and prepare_account_deletion stay
-- the service role's; the Opinions carry-over's stamps and helpers are no API
-- role's.
\\i supabase/migrations/20261107100010_opinion_enforcement_records_grants.sql
""")
```

Run: `python3 .superpowers/sdd/2026-11-07-spec1-w9d/edit_t1.py .`
Expected: four `edited` lines (canary, identity twice, local grants).

- [ ] **Step 7: Apply twice, diff the re-created bodies, run the contract**

```bash
D=.superpowers/sdd/2026-11-07-spec1-w9d
for f in supabase/migrations/20261107100000_opinion_enforcement_records.sql supabase/migrations/20261107100010_opinion_enforcement_records_grants.sql; do
  for i in 1 2; do psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f $f >/dev/null 2>&1; echo "$(basename $f) exit=$?"; done
done
for sig in 'public.admin_confirm_content_removal(text,uuid)' 'public.prepare_account_deletion(uuid)'; do
  diff "$D/before/$sig.sql" <(psql -X -d attune_spec3a -Atc "select pg_get_functiondef('$sig'::regprocedure)") | grep '^[<>]' | grep -v 'Spec 1 W9d'
done; echo bodies-checked
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/opinion_enforcement_records_contracts.sql 2>&1 | grep -E 'ERROR|all held'
```

Expected: four `exit=0` lines; `bodies-checked` with no line above it; `NOTICE:  opinion_enforcement_records_contracts: all held`.

- [ ] **Step 8: The mutants (every fail-closed branch and every counter)**

Create `.superpowers/sdd/2026-11-07-spec1-w9d/m1_muts.py` with exactly:

```python
MUTS = {
    'carry_deletion_time_number': (
        "  SELECT s.phone_hmac, 'opinions', s.id, 'opinions_standing', NULL, s.strikes,",
        "  SELECT public.dating_phone_hmac_for_user(p_user), 'opinions', s.id, 'opinions_standing', NULL, s.strikes,"),
    'removal_not_stamped': (
        "    PERFORM private.opinion_stamp_enforcement(v_author_id, 1, v_ban_until); -- Spec 1 W9d\n", ""),
    'parked_carries': (
        "    RETURN 0;\n  END IF;\n  INSERT INTO public.enforcement_records AS er",
        "  END IF;\n  INSERT INTO public.enforcement_records AS er"),
    'carry_gate_dropped': (
        "  IF coalesce(v_count, 0) <= 0 AND v_ban IS NULL THEN\n    RETURN 0;\n  END IF;\n", ""),
    'expired_ban_carried': (
        "         CASE WHEN s.ban_until > now() THEN s.ban_until END,\n         least(",
        "         s.ban_until,\n         least("),
    'window_two_years_in_carry': (
        "greatest(now() + private.opinion_carry_window(), coalesce(s.ban_until, now()))",
        "greatest(now() + interval '2 years', coalesce(s.ban_until, now()))"),
    'window_value': ("  SELECT interval '30 days';", "  SELECT interval '2 years';"),
    'no_auth_trigger': ('RAW', 'DROP TRIGGER opinions_carry_on_auth_user_delete ON auth.users;'),
    'trigger_pass_not_final': (
        "    PERFORM private.opinion_deletion_carry(OLD.id, true);",
        "    PERFORM private.opinion_deletion_carry(OLD.id, false);"),
    'prepare_carry_unwrapped': ('MULTI', [
        ("  BEGIN -- Spec 1 W9d\n    PERFORM private.opinion_deletion_carry(p_user_id, false); -- Spec 1 W9d\n",
         "    PERFORM private.opinion_deletion_carry(p_user_id, false); -- Spec 1 W9d\n"),
        ("  EXCEPTION WHEN OTHERS THEN -- Spec 1 W9d\n    RAISE WARNING 'opinion_deletion:carry:%', SQLSTATE; -- Spec 1 W9d\n"
         "    PERFORM private.bump_metric_internal('opinions.deletion.prepare_carry_failed'); -- Spec 1 W9d\n  END; -- Spec 1 W9d\n", "")]),
    'trigger_unwrapped': (
        "  BEGIN\n    PERFORM private.opinion_deletion_carry(OLD.id, true);\n  EXCEPTION WHEN OTHERS THEN\n"
        "    RAISE WARNING 'opinion_carry_on_auth_user_delete:%', SQLSTATE;\n"
        "    PERFORM private.bump_metric_internal('opinions.deletion.late_carry_failed');\n  END;\n",
        "  PERFORM private.opinion_deletion_carry(OLD.id, true);\n"),
    'stamp_unwrapped': ('MULTI', [
        ("  EXCEPTION WHEN OTHERS THEN\n    RAISE WARNING 'opinion_stamp:%', SQLSTATE;\n"
         "    PERFORM private.bump_metric_internal('opinions.enforcement.stamp_failed');\n    RETURN false;\n  END;\nEND;",
         "  END;\nEND;")]),
    'unstamped_not_counted': (
        "      PERFORM private.bump_metric_internal('opinions.enforcement.unstamped');\n", ""),
    'stamp_key_not_ready_not_counted': (
        "      PERFORM private.bump_metric_internal('opinions.enforcement.key_not_ready');\n", ""),
    'carry_key_not_ready_not_counted': (
        "      PERFORM private.bump_metric_internal('opinions.deletion.key_not_ready');\n", ""),
    'uncarried_not_counted': (
        "      PERFORM private.bump_metric_internal('opinions.deletion.uncarried');\n", ""),
    'parked_not_counted': (
        "      PERFORM private.bump_metric_internal('opinions.deletion.parked_not_carried');\n", ""),
    'backfill_without_key': (
        "    RAISE NOTICE 'dating_exclusion_key is not set: no Opinions strike stamped';\n    RETURN -1;\n", ""),
    'backfill_restamps': (
        "    IF r.strikes > r.stamped OR (r.ban IS NOT NULL",
        "    IF r.strikes > 0 OR (r.ban IS NOT NULL"),
    'stamp_overwrites': (
        "      SET strikes = s.strikes + EXCLUDED.strikes,", "      SET strikes = EXCLUDED.strikes,"),
    'late_pass_lowers': (
        "    SET confirmed_report_count = greatest(er.confirmed_report_count, EXCLUDED.confirmed_report_count),",
        "    SET confirmed_report_count = er.confirmed_report_count,"),
}
```

Run: `D=.superpowers/sdd/2026-11-07-spec1-w9d; python3 $D/mutate.py supabase/migrations/20261107100000_opinion_enforcement_records.sql supabase/tests/opinion_enforcement_records_contracts.sql $D/m1_muts.py $D/mut`

Expected (21/21 killed; none prints `NO ERROR (mutant survived)`):

```text
carry_deletion_time_number: ERROR:  CONTRACT VIOLATED: strikes on two numbers did not carry under each:  / 1/false 1/false
removal_not_stamped: ERROR:  CONTRACT VIOLATED: three strikes and the ban were not stamped under the author's number
parked_carries: ERROR:  CONTRACT VIOLATED: a parked account carried its strikes onto the number, or was not counted
carry_gate_dropped: ERROR:  CONTRACT VIOLATED: an account with no strike and no live ban carried a record
expired_ban_carried: ERROR:  CONTRACT VIOLATED: an expired ban carried, or its count did not: 3/true
window_two_years_in_carry: ERROR:  CONTRACT VIOLATED: the strikes and live ban did not carry as one 30-day opinions record: 3/true
window_value: ERROR:  CONTRACT VIOLATED: the carry window is 2 years, not the ruled 30 days
no_auth_trigger: ERROR:  CONTRACT VIOLATED: no Opinions carry trigger on auth.users
trigger_pass_not_final: ERROR:  CONTRACT VIOLATED: without the key the stamped strikes did not carry, or the gap was not counted once (2/false)
prepare_carry_unwrapped: ERROR:  new row for relation "enforcement_records" violates check constraint "w9d_contract_refuse"
trigger_unwrapped: ERROR:  new row for relation "enforcement_records" violates check constraint "w9d_contract_refuse"
stamp_unwrapped: ERROR:  new row for relation "opinion_enforcement_stamps" violates check constraint "w9d_contract_refuse"
unstamped_not_counted: ERROR:  CONTRACT VIOLATED: a strike without the key was lost, stamped or not counted (1/false)
stamp_key_not_ready_not_counted: ERROR:  CONTRACT VIOLATED: under a replaced key the strike was not stamped under the live key and counted
carry_key_not_ready_not_counted: ERROR:  CONTRACT VIOLATED: under a replaced key the deletion did not carry its stamps and count it (1/false)
uncarried_not_counted: ERROR:  CONTRACT VIOLATED: without the key the stamped strikes did not carry, or the gap was not counted once (2/false)
parked_not_counted: ERROR:  CONTRACT VIOLATED: a parked account carried its strikes onto the number, or was not counted
backfill_without_key: ERROR:  CONTRACT VIOLATED: the backfill ran without the key
backfill_restamps: ERROR:  CONTRACT VIOLATED: a second backfill stamped again
stamp_overwrites: ERROR:  CONTRACT VIOLATED: three strikes and the ban were not stamped under the author's number
late_pass_lowers: ERROR:  CONTRACT VIOLATED: a strike placed after prepare did not carry: 1/false
```

The three `…unwrapped` mutants die on the contract's own refusing CHECK, which is the raw error that the wrapper is there to catch.

- [ ] **Step 9: Run tests (the Task 1 regression subset)**

```bash
for f in opinion_enforcement_records_contracts dating_rls_canary identity_foundation_contracts account_deletion_contracts dormancy_contracts \
         dating_v2_identity_contracts opinion_moderation_notice_contracts forum_retirement_contracts service_role_grants_test; do
  g=supabase/tests/$f.sql
  if grep -qE '^BEGIN;' "$g"; then a=(-f "$g"); else a=(-c 'BEGIN' -f "$g" -c 'ROLLBACK'); fi
  psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a "${a[@]}" >/dev/null 2>&1 && echo "PASS $f" || echo "FAIL $f"
done
git status --short -- lib test
```

Expected: nine `PASS` lines; no `git status` line.

### Task 2: Migration 22: the restore in `complete_sign_up` (O4; P-4, P-6, P-7)

**Files:**
- Create: `supabase/migrations/20261107110000_opinion_enforcement_restore.sql`, `supabase/migrations/20261107110010_opinion_enforcement_restore_grants.sql`
- Modify: `supabase/tests/opinion_enforcement_records_contracts.sql` (section D), `supabase/tests/dating_rls_canary.sql`, `scripts/local_pg_grants.sql`

**Interfaces:**
- Consumes: Task 1's `private.opinion_stamp_enforcement(uuid,integer,timestamptz)`, `private.opinion_carry_window()`, the `opinions` records Task 1's carry writes (`purge_after` = the window), and the contract helpers `pg_temp.id/h/person/strike/delete_account/records/metric` and the C-section fixtures (records under numbers 01, 02, 05, 07, 08, 10, 12 and 99).
- Produces: `private.opinion_restore_on_sign_up(uuid) → integer`; the `opinions.restore.*` keys.

- [ ] **Step 1: Add section D and see it fail**

Create `.superpowers/sdd/2026-11-07-spec1-w9d/sectionD.sql` with exactly:

```sql
-- =====================================================================
-- D. Restore at sign-up (complete_sign_up, migration 2): the same number
--    within the window gets the count and live ban back, once, at the
--    call that creates the account; the records are taken, so a second
--    round trip never counts twice; past the window, another number, or
--    an account that already existed restores nothing; no key restores
--    nothing (counted); a replaced key restores under the live key
--    (counted); a failing restore never refuses the sign-up.
-- =====================================================================
-- A new account [p_n] on number 155586040<p_phone> completes A1-A5.
CREATE FUNCTION pg_temp.sign_up(p_n text, p_phone text) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
  v jsonb;
BEGIN
  INSERT INTO auth.users (id, phone, phone_confirmed_at, created_at)
  VALUES (pg_temp.id(p_n), '155586040' || p_phone, now(), now());
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claim.sub', pg_temp.id(p_n)::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', pg_temp.id(p_n), 'role', 'authenticated')::text, true);
  v := public.complete_sign_up('W9d returner', DATE '1990-01-01', '2');
  RESET ROLE;
  PERFORM set_config('request.jwt.claim.sub', '', true);
  PERFORM set_config('request.jwt.claims', '', true);
  RETURN v;
END $$;

-- [p_user]'s Opinions standing: 'count/banned'.
CREATE FUNCTION pg_temp.standing(p_user uuid) RETURNS text LANGUAGE sql AS $$
  SELECT p.confirmed_violation_count || '/' || coalesce(p.banned_until > now(), false)
    FROM public.profiles AS p WHERE p.id = p_user;
$$;

DO $$
DECLARE
  v_ban timestamptz := (SELECT e.effect_until FROM public.enforcement_records AS e
                         WHERE e.scope = 'opinions' AND e.phone_hmac = pg_temp.h('01'));
  v_res jsonb;
  v_before bigint;
  v_u uuid;
BEGIN
  -- The same number, the next day: count and ban back, record taken, one
  -- stamp under the number; the sign-up answers exactly as before.
  v_before := pg_temp.metric('opinions.restore.applied');
  v_res := pg_temp.sign_up('21', '01');
  IF v_res IS DISTINCT FROM jsonb_build_object('age', private.age_on_utc_today(DATE '1990-01-01'), 'created', true) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the sign-up''s answer changed: %', v_res;
  END IF;
  IF pg_temp.standing(pg_temp.id('21')) IS DISTINCT FROM '3/true'
     OR (SELECT p.banned_until FROM public.profiles AS p WHERE p.id = pg_temp.id('21')) IS DISTINCT FROM v_ban THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the same number did not get its strikes and live ban back: %', pg_temp.standing(pg_temp.id('21'));
  END IF;
  IF pg_temp.records(pg_temp.h('01')) IS DISTINCT FROM ''
     OR (SELECT s.strikes || '/' || (s.ban_until = v_ban) FROM private.opinion_enforcement_stamps AS s
          WHERE s.user_id = pg_temp.id('21') AND s.phone_hmac = pg_temp.h('01')) IS DISTINCT FROM '3/true'
     OR pg_temp.metric('opinions.restore.applied') IS DISTINCT FROM v_before + 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the restored record was not taken, re-stamped and counted';
  END IF;

  -- A second call (the account exists): nothing more.
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', pg_temp.id('21'), 'role', 'authenticated')::text, true);
  v_res := public.complete_sign_up('W9d returner', DATE '1990-01-01', '2');
  RESET ROLE;
  PERFORM set_config('request.jwt.claims', '', true);
  IF v_res ->> 'created' IS DISTINCT FROM 'false' OR pg_temp.standing(pg_temp.id('21')) IS DISTINCT FROM '3/true'
     OR pg_temp.metric('opinions.restore.applied') IS DISTINCT FROM v_before + 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a repeated sign-up call restored again';
  END IF;

  -- The round trip again: one more strike, delete, sign up: 4, never 7.
  PERFORM pg_temp.strike(pg_temp.id('21'));
  PERFORM pg_temp.delete_account(pg_temp.id('21'));
  PERFORM pg_temp.sign_up('31', '01');
  IF pg_temp.standing(pg_temp.id('31')) IS DISTINCT FROM '4/true' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a second deletion and sign-up did not give back exactly 4 strikes: %',
      pg_temp.standing(pg_temp.id('31'));
  END IF;

  -- Past the window (owner decision W9d-1): nothing back, the record removed.
  UPDATE public.enforcement_records SET purge_after = now() - interval '1 minute'
   WHERE scope = 'opinions' AND phone_hmac = pg_temp.h('10');
  PERFORM pg_temp.sign_up('22', '10');
  IF pg_temp.standing(pg_temp.id('22')) IS DISTINCT FROM '0/false' OR pg_temp.records(pg_temp.h('10')) IS DISTINCT FROM '' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a record past its window restored, or was kept: %', pg_temp.standing(pg_temp.id('22'));
  END IF;

  -- The victim of the phone-change attack signs up on their own number;
  -- a Dating record on it is never taken by the Opinions restore.
  INSERT INTO public.enforcement_records (phone_hmac, scope, restriction_type, confirmed_report_count, purge_after)
  VALUES (pg_temp.h('98'), 'dating', 'suspended', 5, now() + interval '1 year');
  PERFORM pg_temp.sign_up('23', '98');
  IF pg_temp.standing(pg_temp.id('23')) IS DISTINCT FROM '0/false' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the number an attacker moved to inherited their strikes';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.enforcement_records AS e WHERE e.phone_hmac = pg_temp.h('98') AND e.scope = 'dating') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an Opinions restore took a Dating record';
  END IF;

  -- A carried ban that has since ended restores the count only.
  UPDATE public.enforcement_records SET effect_until = now() - interval '1 hour'
   WHERE scope = 'opinions' AND phone_hmac = pg_temp.h('12');
  PERFORM pg_temp.sign_up('27', '12');
  IF pg_temp.standing(pg_temp.id('27')) IS DISTINCT FROM '1/false'
     OR (SELECT p.banned_until FROM public.profiles AS p WHERE p.id = pg_temp.id('27')) IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a carried ban that had ended came back: %', pg_temp.standing(pg_temp.id('27'));
  END IF;

  -- No key: nothing restored, counted, the record kept, the sign-up done.
  v_before := pg_temp.metric('opinions.restore.key_missing');
  PERFORM set_config('app.settings.dating_exclusion_key', '', true);
  v_res := pg_temp.sign_up('24', '02');
  PERFORM set_config('app.settings.dating_exclusion_key', 'spec1-w9d-contract-exclusion-key', true);
  IF v_res ->> 'created' IS DISTINCT FROM 'true' OR pg_temp.standing(pg_temp.id('24')) IS DISTINCT FROM '0/false'
     OR pg_temp.records(pg_temp.h('02')) IS DISTINCT FROM '1/false'
     OR pg_temp.metric('opinions.restore.key_missing') IS DISTINCT FROM v_before + 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a sign-up without the key restored, failed, dropped the record or was not counted';
  END IF;

  -- A fingerprint that isn't ready: restored under the live key, counted;
  -- a count-only record leaves the ban empty.
  v_before := pg_temp.metric('opinions.restore.key_not_ready');
  UPDATE private.dating_key_fingerprints SET fingerprint = repeat('c', 64) WHERE name = 'dating_exclusion_key';
  PERFORM pg_temp.sign_up('25', '99');
  DELETE FROM private.dating_key_fingerprints WHERE name = 'dating_exclusion_key';
  PERFORM private.seed_dating_exclusion_key_fingerprint();
  IF pg_temp.standing(pg_temp.id('25')) IS DISTINCT FROM '1/false'
     OR (SELECT p.banned_until FROM public.profiles AS p WHERE p.id = pg_temp.id('25')) IS NOT NULL
     OR pg_temp.metric('opinions.restore.key_not_ready') IS DISTINCT FROM v_before + 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: under a fingerprint that isn''t ready the count was not restored and counted: %',
      pg_temp.standing(pg_temp.id('25'));
  END IF;

  -- A restore that fails never refuses the sign-up; the record stays.
  v_before := pg_temp.metric('opinions.restore.failed');
  ALTER TABLE public.profiles ADD CONSTRAINT w9d_contract_refuse CHECK (confirmed_violation_count < 1) NOT VALID;
  v_res := pg_temp.sign_up('26', '05');
  ALTER TABLE public.profiles DROP CONSTRAINT w9d_contract_refuse;
  IF v_res ->> 'created' IS DISTINCT FROM 'true' OR pg_temp.standing(pg_temp.id('26')) IS DISTINCT FROM '0/false'
     OR pg_temp.records(pg_temp.h('05')) IS DISTINCT FROM '3/true'
     OR pg_temp.metric('opinions.restore.failed') IS DISTINCT FROM v_before + 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a failing restore refused the sign-up, took the record or was not counted';
  END IF;

  -- An account that already existed (its DOB stored) never restores.
  v_u := pg_temp.person('08');
  INSERT INTO public.account_birthdates (user_id, birth_date) VALUES (v_u, DATE '1990-01-01');
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_u, 'role', 'authenticated')::text, true);
  v_res := public.complete_sign_up('W9d existing', DATE '1990-01-01', '2');
  RESET ROLE;
  PERFORM set_config('request.jwt.claims', '', true);
  IF pg_temp.standing(v_u) IS DISTINCT FROM '0/false' OR pg_temp.records(pg_temp.h('08')) IS DISTINCT FROM '1/false' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an existing account''s sign-up call took a carried record: %', pg_temp.standing(v_u);
  END IF;

  -- Dating is untouched by a restore.
  IF NOT public.dating_account_in_good_standing(pg_temp.id('31')) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a restored Opinions record closed Dating';
  END IF;
END $$;
```

```bash
D=.superpowers/sdd/2026-11-07-spec1-w9d
python3 $D/section.py supabase/tests/opinion_enforcement_records_contracts.sql $D/sectionD.sql --end
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/opinion_enforcement_records_contracts.sql 2>&1 | grep -m1 ERROR
```

Expected: `opinion_enforcement_records_contracts.sql: sectionD.sql end`, then `ERROR:  CONTRACT VIOLATED: the same number did not get its strikes and live ban back: 0/false`.

- [ ] **Step 2: Build migration 22 from the live `complete_sign_up` body**

Create `.superpowers/sdd/2026-11-07-spec1-w9d/build_m2.py` with exactly:

```python
#!/usr/bin/env python3
"""Spec 1 W9d Task 2: writes migration 2 from the LIVE complete_sign_up body.
usage: build_m2.py <before-dir> <out.sql>"""
import pathlib, sys

before, out = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
s = (before / 'public.complete_sign_up(text,date,text).sql').read_text().rstrip('\n')
assert s.startswith('CREATE OR REPLACE FUNCTION ') and s.endswith('$function$')
csu = s + ';\n'
anchor = "  IF v_created THEN\n    PERFORM private.bump_metric_internal('signup_completed');\n"
assert csu.count(anchor) == 1
csu = csu.replace(anchor, (
    "  IF v_created THEN\n"
    "    -- Spec 1 W9d (O4): an Opinions strike count or live ban carried under\n"
    "    -- Spec 1 W9d this number's HMAC within the window comes back, once, at\n"
    "    -- Spec 1 W9d the first sign-up; a failure never refuses the sign-up.\n"
    "    BEGIN -- Spec 1 W9d\n"
    "      PERFORM private.opinion_restore_on_sign_up(v_uid); -- Spec 1 W9d\n"
    "    EXCEPTION WHEN OTHERS THEN -- Spec 1 W9d\n"
    "      RAISE WARNING 'opinion_restore:%', SQLSTATE; -- Spec 1 W9d\n"
    "      PERFORM private.bump_metric_internal('opinions.restore.failed'); -- Spec 1 W9d\n"
    "    END; -- Spec 1 W9d\n"
    "    PERFORM private.bump_metric_internal('signup_completed');\n"))

HEADER = """-- Spec 1 W9d, migration 2 (spec §10 O4, owner approval O4; §4.3
-- complete_sign_up): a carried Opinions record comes back at sign-up.
--   * private.opinion_restore_on_sign_up(user): the Opinions records under
--     the new account's phone HMAC (dating_phone_hmac_for_user) are taken
--     (deleted) in one statement; those still inside their window
--     (purge_after > now(), private.opinion_carry_window() from the
--     deletion: owner decision W9d-1, the recycled-number rule) give the
--     profile their summed count and their latest live ban end (never
--     lowering either), and the account gets one stamp of them under this
--     number, so a later deletion carries them again instead of the
--     taken records being counted twice. Records past their window are
--     removed and restore nothing. No key: nothing restored, counted
--     opinions.restore.key_missing. A key whose fingerprint isn't ready
--     restores under the live key, counted opinions.restore.key_not_ready.
--     Restored: opinions.restore.applied. No notice is sent (the existing
--     Opinions ban UI applies; nothing else in Opinions changes).
--   * complete_sign_up re-created from its LIVE body (Spec 1 W2,
--     20261025100200; pg_get_functiondef on attune_spec3a), changing only
--     the lines marked "Spec 1 W9d": the restore runs once, at the call
--     that created the account (v_created), inside its own block; any
--     failure warns, counts opinions.restore.failed and the sign-up
--     completes (PF-F6: nothing in W9d ever refuses).
-- Grants in 20261107110010_opinion_enforcement_restore_grants.sql.
BEGIN;
SET LOCAL lock_timeout = '5s';

CREATE OR REPLACE FUNCTION private.opinion_restore_on_sign_up(p_user uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_hmac text;
  v_count integer;
  v_ban timestamptz;
  v_rows integer;
BEGIN
  IF p_user IS NULL THEN
    RETURN 0;
  END IF;
  v_hmac := public.dating_phone_hmac_for_user(p_user);
  IF v_hmac IS NULL THEN
    IF public.dating_phone_hmac('attune:dating_exclusion_key:fingerprint:v1') IS NULL THEN
      PERFORM private.bump_metric_internal('opinions.restore.key_missing');
    END IF;
    RETURN 0;
  END IF;
  IF NOT private.dating_exclusion_key_ready() THEN
    PERFORM private.bump_metric_internal('opinions.restore.key_not_ready');
  END IF;
  WITH taken AS (
    DELETE FROM public.enforcement_records AS er
     WHERE er.scope = 'opinions' AND er.phone_hmac = v_hmac
    RETURNING er.confirmed_report_count, er.effect_until, er.purge_after
  )
  SELECT coalesce(sum(t.confirmed_report_count) FILTER (WHERE t.purge_after > now()), 0)::integer,
         max(t.effect_until) FILTER (WHERE t.purge_after > now() AND t.effect_until > now()),
         (count(*) FILTER (WHERE t.purge_after > now()))::integer
    INTO v_count, v_ban, v_rows
    FROM taken AS t;
  IF v_count <= 0 AND v_ban IS NULL THEN
    RETURN 0;
  END IF;
  UPDATE public.profiles AS p
     SET confirmed_violation_count = greatest(p.confirmed_violation_count, v_count),
         banned_until = CASE WHEN v_ban IS NULL THEN p.banned_until ELSE greatest(p.banned_until, v_ban) END
   WHERE p.id = p_user;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'opinion_restore:no_profile';
  END IF;
  PERFORM private.opinion_stamp_enforcement(p_user, v_count, v_ban);
  PERFORM private.bump_metric_internal('opinions.restore.applied');
  RETURN v_rows;
END;
$function$;

"""

FOOTER = """
REVOKE ALL ON FUNCTION private.opinion_restore_on_sign_up(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.complete_sign_up(text, date, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.complete_sign_up(text, date, text) TO authenticated;

COMMIT;
"""

out.write_text(HEADER + csu + FOOTER)
print(f'{out}: {out.read_text().count(chr(10))} lines')
```

```bash
D=.superpowers/sdd/2026-11-07-spec1-w9d
python3 $D/build_m2.py $D/before supabase/migrations/20261107110000_opinion_enforcement_restore.sql
```

Expected: `supabase/migrations/20261107110000_opinion_enforcement_restore.sql: 179 lines`.

- [ ] **Step 3: Write the grants twin and the two existing-file edits**

Create `supabase/migrations/20261107110010_opinion_enforcement_restore_grants.sql` with exactly:

```sql
-- Spec 1 W9d: grants for 20261107110000_opinion_enforcement_restore.sql.
-- complete_sign_up keeps its grants (signed-in only, as 20261025100210 left
-- them); the restore helper is no API role's, the service role included.
BEGIN;
SET LOCAL lock_timeout = '5s';
REVOKE ALL ON FUNCTION public.complete_sign_up(text, date, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.complete_sign_up(text, date, text) TO authenticated;
REVOKE ALL ON FUNCTION private.opinion_restore_on_sign_up(uuid) FROM PUBLIC, anon, authenticated, service_role;
COMMIT;
```

Create `.superpowers/sdd/2026-11-07-spec1-w9d/edit_t2.py` with exactly:

```python
#!/usr/bin/env python3
"""Spec 1 W9d Task 2: the two existing-file edits (each anchor exactly once).
usage: edit_t2.py <repo-root>"""
import pathlib, sys
root = pathlib.Path(sys.argv[1])

def edit(rel, old, new):
    p = root / rel
    s = p.read_text()
    assert s.count(old) == 1, (rel, old[:60], s.count(old))
    p.write_text(s.replace(old, new))
    print(f'{rel}: edited')

a = "  ('private.opinion_stamp_enforcement(uuid,integer,timestamp with time zone)', '', '');\n"
edit('supabase/tests/dating_rls_canary.sql', a, a + """-- Spec 1 W9d (O4): the sign-up restore helper, the same.
INSERT INTO allowed_fn (sig, clients, service) VALUES
  ('private.opinion_restore_on_sign_up(uuid)', '', '');
""")
b = "\\i supabase/migrations/20261107100010_opinion_enforcement_records_grants.sql\n"
edit('scripts/local_pg_grants.sql', b, b + """
-- Spec 1 W9d: complete_sign_up stays the signed-in app's; the restore helper
-- is no API role's.
\\i supabase/migrations/20261107110010_opinion_enforcement_restore_grants.sql
""")
```

Run: `python3 .superpowers/sdd/2026-11-07-spec1-w9d/edit_t2.py .`
Expected: two `edited` lines.

- [ ] **Step 4: Apply twice, diff the body, run the contract**

```bash
D=.superpowers/sdd/2026-11-07-spec1-w9d
for f in supabase/migrations/20261107110000_opinion_enforcement_restore.sql supabase/migrations/20261107110010_opinion_enforcement_restore_grants.sql; do
  for i in 1 2; do psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f $f >/dev/null 2>&1; echo "$(basename $f) exit=$?"; done
done
diff "$D/before/public.complete_sign_up(text,date,text).sql" \
  <(psql -X -d attune_spec3a -Atc "select pg_get_functiondef('public.complete_sign_up(text,date,text)'::regprocedure)") | grep '^[<>]' | grep -v 'Spec 1 W9d'; echo body-checked
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/opinion_enforcement_records_contracts.sql 2>&1 | grep -E 'ERROR|all held'
```

Expected: four `exit=0` lines; `body-checked` alone; `NOTICE:  opinion_enforcement_records_contracts: all held`.

- [ ] **Step 5: The mutants**

Create `.superpowers/sdd/2026-11-07-spec1-w9d/m2_muts.py` with exactly:

```python
MUTS = {
    'restore_ignores_window': (
        "  SELECT coalesce(sum(t.confirmed_report_count) FILTER (WHERE t.purge_after > now()), 0)::integer,",
        "  SELECT coalesce(sum(t.confirmed_report_count), 0)::integer,"),
    'restore_keeps_records': (
        "    DELETE FROM public.enforcement_records AS er\n     WHERE er.scope = 'opinions' AND er.phone_hmac = v_hmac\n"
        "    RETURNING er.confirmed_report_count, er.effect_until, er.purge_after\n",
        "    SELECT er.confirmed_report_count, er.effect_until, er.purge_after FROM public.enforcement_records AS er\n"
        "     WHERE er.scope = 'opinions' AND er.phone_hmac = v_hmac\n"),
    'restore_takes_any_scope': (
        "     WHERE er.scope = 'opinions' AND er.phone_hmac = v_hmac\n", "     WHERE er.phone_hmac = v_hmac\n"),
    'restore_not_restamped': (
        "  PERFORM private.opinion_stamp_enforcement(p_user, v_count, v_ban);\n", ""),
    'ended_ban_restored': (
        "         max(t.effect_until) FILTER (WHERE t.purge_after > now() AND t.effect_until > now()),",
        "         max(t.effect_until) FILTER (WHERE t.purge_after > now()),"),
    'restore_every_call': (
        "  IF v_created THEN\n    -- Spec 1 W9d (O4)", "  IF true THEN\n    -- Spec 1 W9d (O4)"),
    'restore_unwrapped': ('MULTI', [
        ("    BEGIN -- Spec 1 W9d\n      PERFORM private.opinion_restore_on_sign_up(v_uid); -- Spec 1 W9d\n",
         "      PERFORM private.opinion_restore_on_sign_up(v_uid); -- Spec 1 W9d\n"),
        ("    EXCEPTION WHEN OTHERS THEN -- Spec 1 W9d\n      RAISE WARNING 'opinion_restore:%', SQLSTATE; -- Spec 1 W9d\n"
         "      PERFORM private.bump_metric_internal('opinions.restore.failed'); -- Spec 1 W9d\n    END; -- Spec 1 W9d\n", "")]),
    'restore_failed_not_counted': (
        "      PERFORM private.bump_metric_internal('opinions.restore.failed'); -- Spec 1 W9d\n", ""),
    'key_missing_not_counted': (
        "      PERFORM private.bump_metric_internal('opinions.restore.key_missing');\n", ""),
    'key_not_ready_not_counted': (
        "    PERFORM private.bump_metric_internal('opinions.restore.key_not_ready');\n", ""),
    'applied_not_counted': (
        "  PERFORM private.bump_metric_internal('opinions.restore.applied');\n", ""),
}
```

Run: `D=.superpowers/sdd/2026-11-07-spec1-w9d; python3 $D/mutate.py supabase/migrations/20261107110000_opinion_enforcement_restore.sql supabase/tests/opinion_enforcement_records_contracts.sql $D/m2_muts.py $D/mut`

Expected (11/11 killed):

```text
restore_ignores_window: ERROR:  CONTRACT VIOLATED: a record past its window restored, or was kept: 3/false
restore_keeps_records: ERROR:  CONTRACT VIOLATED: the restored record was not taken, re-stamped and counted
restore_takes_any_scope: ERROR:  CONTRACT VIOLATED: the number an attacker moved to inherited their strikes
restore_not_restamped: ERROR:  CONTRACT VIOLATED: the restored record was not taken, re-stamped and counted
ended_ban_restored: ERROR:  CONTRACT VIOLATED: a carried ban that had ended came back: 1/false
restore_every_call: ERROR:  CONTRACT VIOLATED: an existing account's sign-up call took a carried record: 1/false
restore_unwrapped: ERROR:  new row for relation "profiles" violates check constraint "w9d_contract_refuse"
restore_failed_not_counted: ERROR:  CONTRACT VIOLATED: a failing restore refused the sign-up, took the record or was not counted
key_missing_not_counted: ERROR:  CONTRACT VIOLATED: a sign-up without the key restored, failed, dropped the record or was not counted
key_not_ready_not_counted: ERROR:  CONTRACT VIOLATED: under a fingerprint that isn't ready the count was not restored and counted: 1/false
applied_not_counted: ERROR:  CONTRACT VIOLATED: the restored record was not taken, re-stamped and counted
```

Then re-run Task 1's mutants against the full contract: `python3 $D/mutate.py supabase/migrations/20261107100000_opinion_enforcement_records.sql supabase/tests/opinion_enforcement_records_contracts.sql $D/m1_muts.py $D/mut | grep -c 'mutant survived'`. Expected: `0`.

- [ ] **Step 6: Run tests (the sign-up subset)**

```bash
for f in opinion_enforcement_records_contracts identity_foundation_contracts otp_delivery_contracts invite_age_contracts dormancy_contracts \
         dating_v2_identity_contracts dating_rls_canary; do
  g=supabase/tests/$f.sql
  if grep -qE '^BEGIN;' "$g"; then a=(-f "$g"); else a=(-c 'BEGIN' -f "$g" -c 'ROLLBACK'); fi
  psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a "${a[@]}" >/dev/null 2>&1 && echo "PASS $f" || echo "FAIL $f"
done
```

Expected: seven `PASS` lines.

### Task 3: The W9d gate: whole-suite regression, flag-off goldens, latch, Games; the as-built amendments

**Files:**
- Modify: `docs/superpowers/specs/2026-10-24-app-flow-identity-design.md`, `docs/superpowers/specs/2026-10-24-dating-mode-design.md`
- Helpers: `.superpowers/sdd/2026-11-07-spec1-w9d/{edit_docs.py, sql-after.txt}`

**Interfaces:**
- Consumes: Tasks 1–2 applied on `attune_spec3a`; Task 1's baselines and latch hash.
- Produces: the gate evidence; the spec text W10 and later waves read.

- [ ] **Step 1: The whole SQL suite against Task 1's baselines**

```bash
D=.superpowers/sdd/2026-11-07-spec1-w9d
for f in supabase/tests/*.sql; do
  if grep -qE '^BEGIN;' "$f"; then a=(-f "$f"); else a=(-c 'BEGIN' -f "$f" -c 'ROLLBACK'); fi
  if psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a "${a[@]}" >/dev/null 2>&1; then echo "PASS $(basename "$f")"; else echo "FAIL $(basename "$f")"; fi
done > $D/sql-after.txt
echo "after: $(grep -c '^PASS' $D/sql-after.txt) PASS, $(grep -c '^FAIL' $D/sql-after.txt) FAIL"
grep '^FAIL' $D/sql-after.txt | while read -r _ f; do
  grep -qx "FAIL $f" $D/sql-baseline-1.txt || grep -qx "FAIL $f" $D/sql-baseline-2.txt || echo "NEW FAIL $f"
done
for f in account_deletion_contracts dormancy_contracts identity_foundation_contracts otp_delivery_contracts invite_age_contracts \
         dating_v2_identity_contracts dating_v2_eligibility_contracts dating_v2_setup_contracts dating_rls_canary service_role_grants_test \
         opinion_moderation_notice_contracts opinion_filter_contracts opinion_filter_parity_contracts opinion_remove_own_contracts \
         forum_retirement_contracts opinion_enforcement_records_contracts; do
  grep -qx "PASS $f.sql" $D/sql-after.txt || echo "NOT PASS $f"
done; echo regression-checked
```

Expected: `after:` with one more PASS than the baseline: the new contract (on the scratch copy the existing files were 156 PASS / 14 FAIL before and after, and the new contract passed); no `NEW FAIL` line outside the AI-session group (for one inside it, show that its first ERROR names no Opinions or deletion object); `regression-checked` with no `NOT PASS` line above it.

- [ ] **Step 2: The Deno deletion tests, the flag-off goldens, Games, the latch, no app change**

```bash
D=.superpowers/sdd/2026-11-07-spec1-w9d
(cd supabase/functions && deno test --allow-read --allow-env delete-account/ purge-recovery-holds/ 2>&1 | grep -E 'passed|failed' | tail -1)
flutter test test/features/opinions/w9/opinions_flag_off_test.dart 2>&1 | tail -1
flutter test test/architecture/games_untouched_test.dart 2>&1 | tail -1
sed -n '/if (isAuthenticated \&\& !_gateData.isComplete) {/,/_redirectingToOnboarding = false;/p' lib/home/home_screen.dart | shasum | diff - $D/latch.sha && echo latch-unchanged
git status --short -- lib test ATTUNE_SOUL.md ATTUNE_THESIS.md supabase/functions
```

Expected: `ok | N passed | 0 failed` (N as the files print); `All tests passed!` twice; `latch-unchanged`; no `git status` line.

- [ ] **Step 3: The as-built amendments**

Create `.superpowers/sdd/2026-11-07-spec1-w9d/edit_docs.py` with exactly:

```python
#!/usr/bin/env python3
"""Spec 1 W9d Task 3: the as-built amendments (each anchor exactly once).
usage: edit_docs.py <repo-root>"""
import pathlib, sys
root = pathlib.Path(sys.argv[1])
S1 = 'docs/superpowers/specs/2026-10-24-app-flow-identity-design.md'
S2 = 'docs/superpowers/specs/2026-10-24-dating-mode-design.md'

def edit(rel, old, new):
    p = root / rel
    s = p.read_text()
    assert s.count(old) == 1, (rel, old[:60], s.count(old))
    p.write_text(s.replace(old, new))
    print(f'{rel}: edited')

a = "| 20 | `healing_ai_insights_flag` | W9e | the `healing_ai_insights` flag row (false) and its production gate row; no new object *(amended W9e)* |\n"
edit(S1, a, a +
     "| 21 | `opinion_enforcement_records` | W9d | `private.opinion_enforcement_stamps` and the stamp in `admin_confirm_content_removal` (re-created from its live body); `private.opinion_stamp_backfill()`; the carry in `prepare_account_deletion` (re-created from its live body) and the `opinions_carry_on_auth_user_delete` trigger; `restriction_type` `'opinions_standing'`; the `opinions.` metric prefix *(amended W9d)* |\n"
     "| 22 | `opinion_enforcement_restore` | W9d | `private.opinion_restore_on_sign_up` and the `opinions_restore_on_auth_user` trigger on `auth.users` (the restore point); the restore log `private.opinion_restores` and the owner's `private.undo_opinion_restore`; `complete_sign_up` re-created unchanged from its live body (no restore of its own) *(amended W9d)* |\n")
a = "| Journal crisis-check matches | not stored | only `support_card_shown:journal` counts |\n"
edit(S1, a, a +
     "| Opinions strikes and bans by number (`private.opinion_enforcement_stamps`) | server | account deletion (cascade, after the carry) *(amended W9d)* |\n"
     "| Carried Opinions records (`enforcement_records`, scope `opinions`: phone HMAC, strike count, live ban end) | server | taken when an account becomes the confirmed holder of that number (Auth's phone confirmation); otherwise 30 days after the deletion, or the ban end if later (owner decision W9d-1) *(amended W9d)* |\n"
     "| Opinions restores (`private.opinion_restores`: what a restore added, its source record ids, when; no phone, no HMAC) | server | 90 days after the restore (the daily `opinion-enforcement-purge` job), or account deletion if sooner *(amended W9d)* |\n")
a = "**W10a · Large text**\n"
edit(S1, a, """**W9d · Opinions enforcement records** *(amended W9d; owner approval O4)*
- Contents: migrations 21 and 22 (§4.7). Each confirmed removal stamps the author's number at that moment (S2 W1 B3 I-1: never the number held at deletion); `prepare_account_deletion` and a `BEFORE DELETE` trigger on `auth.users` carry a count above 0 or a live ban into `enforcement_records` (scope `opinions`), one row per number the strikes were placed on; when an account becomes the confirmed holder of that number within the window (a trigger on `auth.users` at Auth's phone confirmation: a new account on every sign-up path, v1 or v2, `flow_signin_v2` on or off, a crafted client, or a confirmed change of number; never a sign-in's re-confirmation, the fresh-start placeholder or a parked account), they come back into `profiles` before the account can post (never lowering its own standing; the profile row is made if missing; the trigger is the only restore path, and it never blocks Auth: any error or cancel inside it is caught and counted), stamps what that added under the account, so a second round trip never counts twice, and logs it in `private.opinion_restores`; the owner's `private.undo_opinion_restore` takes back exactly what a restore added.
- Depends on: S2 W1 (`enforcement_records`, `dating_phone_hmac_for_user`, the exclusion key and its fingerprint); W9b (`admin_confirm_content_removal`).
- Tests: `opinion_enforcement_records_contracts.sql`; the regression set in the W9d plan.
- **As built:** nothing ever refuses a deletion, a removal or a sign-up (PF-F6): no key means no stamp and no restore, counted; a key whose fingerprint isn't ready stamps, carries and restores under the live key, counted; every failure is caught and counted under `opinions.`. A parked account (O3) carries nothing. A restore sends no notice and changes nothing else in Opinions. The window is 30 days from the deletion, or the ban end if later (owner decision W9d-1); parked accounts carrying nothing is owner decision W9d-2.
- Gate: none of its own (no flag); it deploys with S2 W1, after the exclusion key is set and seeded, and the owner runs `private.opinion_stamp_backfill()` then.

""" + a)
a = "This is built as **S1 W9d**, after S2 W1 creates `enforcement_records`.\n"
edit(S1, a, a.rstrip('\n') + " *(amended W9d: as built in §8 W9d; owner decisions W9d-1 (the 30-day window) and W9d-2 (parked accounts carry nothing) pending)*\n")
a = "the next Dating migration drops the value from the CHECK (§10 item 9) |"
edit(S2, a, "the next Dating migration drops the value from the CHECK (§10 item 9). *(amended S1 W9d: ruled yes and built; `restriction_type` also allows `'opinions_standing'` for scope `opinions`, where `confirmed_report_count` is the strike count, `effect_until` the live ban end and NULL means no ban, and `purge_after` is the restore window; Dating's readers filter `scope = 'dating'`)* |")
a = "a yes is built as Spec 1 W9d after this spec's W1a, a no drops the reserved value in the next Dating migration."
edit(S2, a, a + " *(amended S1 W9d: ruled yes, built as S1 W9d)*")
```

Run: `python3 .superpowers/sdd/2026-11-07-spec1-w9d/edit_docs.py .`
Expected: six `edited` lines (four in Spec 1, two in Spec 2).

- [ ] **Step 4: The W9d file list**

Run: `git status --short`
Expected, besides the owner's own files: `?? supabase/migrations/20261107100000_opinion_enforcement_records.sql`, `?? …20261107100010_opinion_enforcement_records_grants.sql`, `?? …20261107110000_opinion_enforcement_restore.sql`, `?? …20261107110010_opinion_enforcement_restore_grants.sql`, `?? supabase/tests/opinion_enforcement_records_contracts.sql`, ` M supabase/tests/dating_rls_canary.sql`, ` M supabase/tests/identity_foundation_contracts.sql`, ` M scripts/local_pg_grants.sql`, ` M docs/superpowers/specs/2026-10-24-app-flow-identity-design.md`, ` M docs/superpowers/specs/2026-10-24-dating-mode-design.md`, and this plan. Nothing else.

---

## Owner deploy checklist (the plan never runs any of this)

1. **Deploy after S2 W1.** One `supabase db push` carries S2 W1's 22 files and W9d's four, in timestamp order, because `enforcement_records` and the HMAC helpers are S2 W1's. Migration 21 creates a trigger on `auth.users`, as S2 W1's `20261106120000` already does, so if that one applies, this one does too.
2. **Run the backfill after every deploy of migration 21, and again after the exclusion key is set and seeded** (S2 W1 checklist items 2 and 11: `dating_exclusion_key` in Vault, then `SELECT private.seed_dating_exclusion_key_fingerprint();` → `ready`): `SELECT private.opinion_stamp_backfill();` from the SQL editor (idempotent; batch-1 review M-4: a removal confirmed by the old body while the migration ran is stamped by the next run). It returns the number of accounts stamped; `-1` means the key is still missing. Strikes and bans placed before this carry nothing until it runs. Run it right after S2 W1's `SELECT private.dating_stamp_restriction_hmacs();`. It stamps a pre-W9d strike only when the account's number provably hasn't changed since its earliest removed post (`auth.users.phone_confirmed_at` no later than it, and no number change requested since: `phone_change_sent_at`; final review M-2: never `public.users.updated_at`, which W1's reconcile in the same push rewrites); every other account is counted `opinions.enforcement.backfill_phone_unverified` and its older strikes carry nothing (the coordinator's M-1 ruling: a victim's number never inherits them). An admin change of an author's number made without confirming it leaves no Auth evidence, so don't make one before the backfill. Afterwards, compare the backfill's return value with the number of struck accounts and with `backfill_phone_unverified`, to see how many older strikes were stamped.
2a. **Confirm the purge cron** (batch-1 review I-2): `SELECT jobname, schedule, command FROM cron.job WHERE jobname = 'opinion-enforcement-purge';` → `19 3 * * *`, `SELECT private.opinion_enforcement_purge()`. It deletes `scope = 'opinions'` records past `purge_after` (30 days after the deletion, or the ban end if later), counted `opinions.enforcement.purged`; Dating's 2-year records are never touched (their own purge stays an S2 W1 owner item). The same job removes restore-log rows (`private.opinion_restores`) 90 days after their restore, counted `opinions.restore.log_purged`.
3. **Watch the counters** (none of them should move in normal use): `SELECT key, sum(count) FROM public.metric_counters WHERE key LIKE 'opinions.%' GROUP BY key ORDER BY key;`. Act on these: `opinions.deletion.uncarried` (run item 2), `opinions.enforcement.unstamped` and `opinions.restore.key_missing` (key missing), `…key_not_ready` (put the original key back; never rotate it, W1 final I-3), and `…stamp_failed`, `…prepare_carry_failed`, `…late_carry_failed`, `opinions.restore.failed` (read the Postgres warnings `opinion_*`), `opinions.restore.unstamped` (a restored standing with no stamp: the next deletion won't carry it), `opinions.enforcement.backfill_phone_unverified`, `opinions.enforcement.parked_unstamped`; for information: `opinions.enforcement.purged`, `opinions.restore.applied`, `…undone`, `…undo_noop`, `…log_purged`, `…parked_skipped`, `opinions.deletion.parked_not_carried` (W9d-2 at work). Each restore runs once, from the `auth.users` trigger (the only restore path), so each counter moves once per confirmation.
4. **Owner decisions W9d-1 and W9d-2: approved 2026-11-07, built as approved.** W9d-1: a carried record restores within 30 days of the deletion, or until a carried ban ends if later; past that it restores nothing and the daily job removes it. W9d-2: a parked account (Spec 1 O3) carries nothing, and a strike on a parked account is never stamped. A different window is a new migration that changes only `private.opinion_carry_window()`.
5. **Support script** (batch-2 review I-1). If someone says they inherited an Opinions pause or count on a new number, the owner checks from the SQL editor: `SELECT restored_count, restored_ban, restored_at - deleted_at AS gap, undone_at FROM private.opinion_restores WHERE user_id = '<user id>';`.
   - No row: nothing was restored, so the standing is the account's own; decline.
   - A gap of hours or a few days: almost certainly the same person re-registering (O4); decline.
   - Otherwise (a recycled number): `SELECT private.undo_opinion_restore('<user id>');`. It takes back exactly what the account's restores added: the restored counts, and a ban only when it came from a restore: still a ban a restore set, or a strike's ban placed after the restore that the account's own remaining strikes (fewer than 3) would never have earned. A ban the owner set directly stays, and so does one the account's own 3 or more strikes earned; clear those by hand if they should go. It never takes the account's own strikes; a second call changes nothing (`false`). The row stays as the record (`undone_at`) until the 90-day log purge.
6. **Counsel:** the privacy notice gains one retention line: Opinions strikes and an active posting pause are kept by a one-way code of the phone number for 30 days after deletion (or until an active pause ends, if later), and when they are restored to a new account on that number, a record of what was restored (no phone number) is kept for 90 days for support (Spec 1 §4.8, amended by Task 3; the DPIA's retention entry the same).
7. **Owner carry for the next Opinions wave (batch-2 review M-4; not changed in W9d).** `public.profiles.confirmed_violation_count` and `banned_until` are readable by every signed-in user (policy `USING (true)`, column SELECT granted to `anon` and `authenticated`). Since W9d, a brand-new account can show an inherited count or pause, which hints that its number belonged to a struck, deleted account within the last 30 days. Fix there: revoke column SELECT on both from `anon` and `authenticated`, and add `public.get_my_opinion_standing()` (own row only) for the client.

## Spec coverage (self-review)

| Requirement | Where |
|---|---|
| O4: `prepare_account_deletion` writes an `opinions` record (count and ban end) | Task 1 migration 21; contract C |
| O4: only for a live ban or a count above 0 | Task 1 carry gate; contract C (`no strike and no live ban`, `an expired ban carried`); mutants `carry_gate_dropped`, `expired_ban_carried` |
| O4: `complete_sign_up` re-created from its live body restores for the same HMAC | Task 2 migration 22; body diff; contract D |
| Phone-change attack (W1 B3 I-1): stamp at strike time in `admin_confirm_content_removal` | Task 1 (live W9b body + stamp lines); contracts B, C, D; mutants `removal_not_stamped`, `carry_deletion_time_number` |
| One-off stamp backfill (an owner step if the key is missing) | Task 1 `private.opinion_stamp_backfill()` (run by migration 21 when the key is set); contract B; checklist item 2 |
| PF-F6: never block; a missing key carries nothing and is counted | P-9; contracts B, C, D; the `…unwrapped` and counter mutants |
| Key-fingerprint mismatch: live key, counted, never blocks | P-10; contracts B, C, D (`…key_not_ready`) |
| Recycled numbers (Spec 1 O3) | P-4 (W9d-1), P-5 (W9d-2); contracts C (parked), D (window, victim) |
| Lock order and bounded retry if Dating locks apply | P-11 (none apply; profile row only) |
| Only what W9d names changes in Opinions; flag-off goldens unchanged | Global Constraints; contract B (return values); Task 3 Step 2 |
| Regression of every contract touching `prepare_account_deletion` / `complete_sign_up` | Task 1 Step 9, Task 2 Step 6, Task 3 Step 1 |
| Spec 2 §4.2: the reserved `opinions` scope used | P-3; Task 3 amendment |
| Games, SOUL, THESIS, latch untouched; no deploys | Global Constraints; Task 3 Step 2; owner checklist |

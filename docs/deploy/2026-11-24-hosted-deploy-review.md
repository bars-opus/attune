# Review: 2026-11-24 hosted deploy checklist and script

Reviewed: `docs/deploy/2026-11-24-hosted-deploy.md` (the doc) and `scripts/deploy/hosted_deploy.sh` (the script), at HEAD `9bac1bdb`. Nothing here contacted the hosted project. The local checks ran against a throwaway clone of `attune_spec3a`, which was dropped afterwards.

**Result: 2 Critical, 7 Important, 11 Minor.** The two Criticals depend on one fact that neither file states: whether anyone outside the test group uses the App Store or Play build against this project. If nobody does, both become release notes. Answer that at the top of the doc, before step 0.

## What was verified and holds

- **Migration set and order.** `ls supabase/migrations` after `20261024100800` gives exactly the 121 files in Appendix A, in the same order. `git diff ed7bfddd HEAD` adds those 121 files and modifies none, so the Stories deploy point is consistent. There are 58 twin pairs and 5 singles, as stated.
- **Apply-time keys.** No pending migration fails when a Vault key is missing. Every backfill that runs at apply time (`dating_recompute_former_partner_exclusions`, both fingerprint seeds, `opinion_stamp_backfill`, `dating_backfill_pair_markers`) returns a NOTICE, `missing_key` or `-1` instead. Setting the keys in step 1, before the push, is the right order, and the script refuses to continue in step 1 without the 4 keys, `supabase_url` and `service_role_key`.
- **verify_jwt.** The doc and the script match `supabase/config.toml`: `false` for `otp-delivery-intent`, `send-sms-hook`, `start-fresh-account` and `dating-moderation`; `true` (explicit, or by default) for the rest.
- **Function list.** 12 new and 8 changed function directories since `ed7bfddd`: exactly the 20 deploys. The only modified `_shared` modules (`aws_rekognition.ts`, `google_vision.ts`) are imported only by `process-dating-photo`, which is redeployed. None of the 13 SQL functions dropped without being re-created is referenced in `lib/` or `supabase/functions`.
- **The 4 deletes.** Nothing in `lib/`, `supabase/functions`, `supabase/sql` or the migrations still calls them. The only caller is the old store build's Dating v1 (`dating_repository.dart:427` at `ed7bfddd`, `verify-dating-profile`), and its v1 RPCs (`get_dating_eligibility` and others) are dropped by the push anyway.
- **Order constraints.** `build-data-exports` is deployed after the W9 migration. The old version only calls RPCs, so it keeps working in the gap. `dating-moderation` is held until `DATING_CONSOLE_ORIGIN` exists. `dating-device-check` is held until the bin exists and is at most 20 MB.
- **Crons.** On the clone, the step 4 query returned all 23 jobs with the schedules in the doc's table, and `enqueue-new-storage-objects` correctly absent on the trigger path. Every job unschedules by name before it schedules, so a replay doesn't double-schedule. `dating-candidate-generation` replaces the v1 job of the same name.
- **Post-push checks.** On the clone, every expected value in the step 2.3 block matched, except the one bucket column the local storage stub lacks. The 2.4 seeds and the catalogue load (`{"loaded": 4, ...}`) also matched.
- **Flag scripts.** In one transaction on the clone, the six scripts gave `demo_on = 27`, `["GB", "GH"]` and `explicit 5 / slur 4`. With `app.settings.attune_environment = 'production'`, the Spec 1 and Spec 2 scripts raise `env:not_development` and change nothing. Spec 5, 7 and 8 have no guard, but the script runs Spec 1 first with `ON_ERROR_STOP`, so a production project stops before them. The table holds 46 flags, 19 of them outside the demo set.
- **Script mechanics.** `bash -n` passes under bash 5 and under macOS `/bin/bash` 3.2.
  - A dry run with failing shims for `supabase`, `psql`, `curl`, `deno`, `flutter`, `gunzip` and `docker` called none of them and wrote no state. It does read `catalogue.json` with python3 and greps one migration, both local.
  - `read -p` at EOF answers "no", and every gate fails safe on "no".
  - `set -Eeuo pipefail` is set, and every `$(sql_value …)` is assigned separately from `local`.
  - `ATTUNE_DB_URL` and `ATTUNE_ANON_KEY` are printed only as variable names.
  - Nothing sets `attune_environment`.
- **Demo notes.**
  - Debug/profile builds only: `dating_capture.dart:82` gates the fake capture on `!kReleaseMode`.
  - Two console accounts: `dating_moderators.user_id` is the primary key and references `public.users`.
  - Introductions at 03:17 UTC: `generation_hour_utc` defaults to 3 and the tick runs at :17.

  All three are correct, but see I-4.
- **Purge stop placement.** 0.10 is in step 0, before anything irreversible: step 0 is read-only apart from the optional dumps. The decision is recorded, an undecided or missing state counts as NO-GO, and the function is deployed only on GO (but see I-1 and I-2).

---

## Critical

### C-1. Step 8 turns on `flow_signin_v2` for every account: no store-build user can create or accept a couple invite

- **Where:** doc §8.2 (lines 610–615) and Summary line 13; script `step8`, line 686 (`dev_enable_spec1_flags.sql`). Code: `20261102100000_accept_invite_v2.sql:160-173` (`relationship_invite_eligibility`), `20261102110100_couple_profiles_links.sql:103-120`, and `_shared/sign_up_guard.ts` (`requireInviterAge`).
- **What goes wrong:**
  - With `flow_signin_v2` on, `relationship_invite_eligibility` returns `age_required` for any account with no date of birth. `account_age` reads the new W1 birth-date table, so that is every existing account.
  - `create-relationship-invite` then answers 428 `invite:age_required`. The accept refuses with `invite:age_required` for the acceptor, and with `invite:not_possible` for an inviter without a date of birth, including invites that are already pending.
  - The store build can't collect a date of birth and doesn't know these codes, so every not-yet-linked couple on the store build is stuck.
  - `flow_paths_v2`, `flow_couples_v2` and `couple_profile` depend on `flow_signin_v2` (`spec1_flag_on`), so the demo needs it on. That is a real conflict, and it is the owner's to decide.
  - The doc only ever talks about "every test device" (lines 129, 185) and never names the public store build.
- **Fix:** add a STOP before 8.2: "Does anyone outside the test group use the App Store/Play build on this project?" If yes, pick one:
  - (a) ship the W10 build to the stores first and wait for adoption; or
  - (b) skip `dev_enable_spec1_flags.sql`, accept no new-flow and Dating demos, and still turn on `journal_ai_insights` and `healing_ai_insights` by hand. Otherwise Journal insights and Healing AI stay `paused` for everyone, because the new functions deployed in step 3 read those flags.

  Put this in the Summary, in bold.

### C-2. The push itself breaks parts of the app for current store-build users until a new store release, and nothing in the plan schedules one

- **Where:** doc §0.8 (line 129) and §0.11 "Old app builds" (lines 181–185), framed for test devices; Summary. Code: `20261025100000` (revokes users INSERT/UPDATE), `20261025100300:18` (`DROP COLUMN onboarding_profiles.mode`), `20261025090100` (forum access revoked), `20261107150000:687` (`DROP FUNCTION get_dating_eligibility`).
- **What goes wrong on the live project, from the moment of the push:**
  - A new account that onboards on the store build can't save its name. The old `onboarding_submission_service.dart` upserts `users` with `phone` and `mode`, and that upsert is now refused (42501). Its `onboarding_profiles` upsert with `mode` fails too, because the column is gone. The app says "Saved locally", and the partner sees a blank name until the user updates.
  - The Forums tab is in an error state for every store-build user.
  - Dating v1 disappears.
  - The Journal Patterns tab shows a blank page while `journal_ai_insights` is off (from step 3 until step 8, or for good under C-1(b)).
  - The W1 plan's own rule (owner checklist item 1, "one push, then one client build"; and `20261025100020`'s header, "the W1b build is installed next") assumes a client release follows the push. This deploy has none.
  - The `onboarding_profiles.mode` drop can only be undone by a restore.
- **Fix:** put a bold "Real users on the store build" box in the Summary listing these effects. Make 0.8 and 0.11 gates ask about the store build, not only test devices. If real users exist, schedule the store release with the deploy, or say plainly that they accept the degradation.

---

## Important

### I-1. The purge GO probe checks 4 tables, but the purge deletes Auth accounts and cascades through about 99 tables

- **Where:** doc §0.10 lines 165–173; script lines 353–371. Code: `purge-unfinished-signups/handler.ts` calls `auth.admin.deleteUser`. `private.unfinished_signups` has no data check at all.
- **What goes wrong:** `with_data` looks only at `profiles`, `opinions`, `quiz_responses` and `psych_profiles`. On the schema, 99 foreign keys outside `auth` and `storage` reference `auth.users`, most of them `ON DELETE CASCADE`. GO also allows "or you have reviewed every listed id", which lets data-bearing accounts be deleted for good. The purge runs every hour from then on, not once.
- **Fix:** replace `with_data` with a probe across every foreign key. It ran clean on the clone, against `private.unfinished_signups`. This is the version to run before the push:
  ```sql
  do $$ declare r record; n bigint; total bigint := 0; begin
    for r in select c.conrelid::regclass as tbl, a.attname as col
               from pg_constraint c join pg_attribute a on a.attrelid = c.conrelid and a.attnum = c.conkey[1]
              where c.contype = 'f' and c.confrelid = 'auth.users'::regclass
                and c.connamespace not in ('auth'::regnamespace, 'storage'::regnamespace) loop
      execute format('select count(*) from %s t where t.%I in (select a.id from auth.users a
        where greatest(a.created_at, a.last_sign_in_at, a.updated_at) < now() - interval ''24 hours''
          and not exists (select 1 from public.users u where u.id = a.id))', r.tbl, r.col) into n;
      total := total + n; if n > 0 then raise notice '%.%: %', r.tbl, r.col, n; end if;
    end loop; raise notice 'rows tied to purge candidates: %', total; end $$;
  ```
  GO only when the total is 0, or when every listed id is confirmed to be a throwaway account.

### I-2. Nothing checks that `purge-unfinished-signups` isn't already deployed before the push arms its cron

- **Where:** doc §0.10 line 153 ("deploying the function is the only latch"); script `step0` (no `functions list` before step 2).
- **What goes wrong:** `20261025100500` schedules the hourly `:41` call at push time. If the function already exists, the purge goes live at the first `:41` after the push, before 2.5 can unschedule it on a NO-GO. It could exist from an earlier no-names `supabase functions deploy`, which the doc itself warns re-creates functions, or from another worktree. The cost is irreversible deletion of Auth accounts.
- **Fix:** in step 0, run `load_function_list`. If `purge-unfinished-signups` is present and the decision is not GO, `supabase functions delete` it before step 2, or stop.

### I-3. Every database step uses `--linked`, but the ref guard only checks an environment variable, and `--from 1..9` never re-links

- **Where:** script lines 270, 283–288, 428–430; `basic_checks` lines 237–257.
- **What goes wrong:** `supabase db push --linked`, `db dump` and `migration list` use whatever `supabase/.temp/project-ref` points to. `supabase link` runs only in step 0. A resume with `--from 2` after the folder was re-linked would push 121 migrations to that other project, while psql checks and seeds the intended one. Re-linking can come from local development, another worktree, or `supabase link` for another project. `SUPABASE_PROJECT_REF` and `ATTUNE_DB_URL` would still pass the guard.
- **Fix:** in `basic_checks` (real runs), either run `supabase link --project-ref "$REF"` unconditionally, or compare the linked ref with `$REF` and stop on a mismatch. Better still, push with `supabase db push --db-url "$ATTUNE_DB_URL"`, so psql and the push provably reach the same database.

### I-4. Demo blocker: the first generation tick after step 8 uses up the day's cohort before any demo profile exists, and the suggested "force" doesn't help

- **Where:** doc §9 "Today" row (line 669); script `step8` (expects all 27 flags on). Code: `20261119120000_dating_v2_signals.sql:556-640` (`run_dating_generation_tick`), and the `dating_generation_runs` claim, which re-runs only `pending` or `failed` partitions.
- **What goes wrong:** once `dating_candidate_generation` is on, the next `:17` tick finds no runs for today's cohort and runs the full partition. That is almost certainly before testers have finished D1–D13, so the partition is marked done with nobody in it. Later ticks, and the manual `select public.run_dating_generation_tick();` the doc suggests, only retry pending or failed partitions. The demo profiles then get nothing until 03:17 UTC the next day.
- **Fix:** in step 8, leave `dating_candidate_generation` off, or turn it off again before the next `:17`. When both demo enrolments show `active`, turn it on and run `select public.run_dating_generation_tick();` once. The script's 27-flag check needs a matching exception. Reword the Today row: "forcing a tick only works if today's partition hasn't run yet".

### I-5. Secrets end up in shell history, SQL-editor history and possibly in Postgres statement logs

- **Where:**
  - doc line 29 says `vault.create_secret(...)` in the SQL editor "is fine";
  - doc line 42 (`export ATTUNE_DB_URL='…'` typed in the shell);
  - doc line 344 (`SUPABASE_SERVICE_ROLE_KEY=<key> scripts/load_support_resources.sh`);
  - `log_settings_safe` is first checked in 2.3, after the keys were created in step 1.
- **What goes wrong:**
  - The DB password (full power) and the service-role key land in `~/.zsh_history`.
  - `dating_field_key` and `dating_exclusion_key` stay in the SQL editor's query history.
  - If `log_statement` is `all` or `mod`, they also land in the Postgres logs before the check that would have caught it. Leaking `dating_field_key` defeats the encryption of Dating answers, and the key must never be rotated.
- **Fix:**
  - Create the Vault keys in Dashboard → Vault, or from psql with `\set` read from a file.
  - Read the URL with `read -rs ATTUNE_DB_URL; export ATTUNE_DB_URL`, or use `~/.pgpass` with a password-free URL, which also keeps the password out of `ps`.
  - Drop option 1 in 2.6.
  - Move the `log_statement` / `log_parameter_max_length_on_error` check into step 0.

### I-6. The script deploys whatever is in the working tree; it never checks that the tree is clean or which commit it is

- **Where:** script `basic_checks`, which has no `git` check; doc Summary.
- **What goes wrong:** `supabase functions deploy` and `db push` ship files from disk, not from a commit. The owner often edits `main` directly (memory: work on main when the user is editing). An uncommitted edit under `supabase/functions`, `lib/console` or `assets/support_resources` would go to the live project unreviewed. The 121-file count catches an extra migration, but not an edited function.
- **Fix:** in `basic_checks`, stop if `git status --porcelain -- supabase lib/console assets/support_resources | grep -v 'supabase/.temp/'` prints anything. Print `git rev-parse --short HEAD` and require it to be `9bac1bdb` or a descendant: `git merge-base --is-ancestor 9bac1bdb HEAD`.

### I-7. `opinions_safety_v1` turns on server-side filtering with the [DRAFT] terms for every Opinions writer, store build included

- **Where:** doc §8.2 (`load_content_filter_terms.sql`); code `20261104100000_opinion_content_filter.sql:555-640`.
- **What goes wrong:** with the flag on, every Opinions post and comment from any client is checked against the developer-written, unreviewed [DRAFT] lists and the contact-info rule (phone numbers). Refused posts get `content:*` codes the store build can't explain. Confirmed removals now count toward the real 7-day ban (0.11). Real users are moderated by an unreviewed list.
- **Fix:** list this under C-2's "real users" box. If real users are present, consider leaving `opinions_safety_v1` off, or accept it explicitly in 0.11.

---

## Minor

- **M-1** (script lines 63–67, 251; 371–376, 504–507):
  - A dry run with a wrong `SUPABASE_PROJECT_REF` passes silently. Compare it with the dev ref when it is set.
  - In a dry run, 0.10 "would record go", but steps 2 and 3 then print the NO-GO path.
- **M-2** (script lines 690–697): `out="$(psql … 2>&1)"` under `set -e` exits on a psql error before `printf "$out"`, so `env:not_development` (or any other error) is swallowed. Use `if ! out=$(…); then printf '%s\n' "$out"; die …; fi`. Also, when it stops on a WARNING the flags are already committed on; say so in the message.
- **M-3** (doc lines 53, 56, 193; script line 273): "migration 16 (`20261104100000`)" is file 44 in Appendix A, and "migrations 10–11 and 21" don't map to Appendix numbers. Use the version numbers.
- **M-4** (doc line 296; script line 462): the quarantine query also returns an `avatars` row (probably `public = t`), but the expected value lists one row. State both rows.
- **M-5** (doc line 245): the 1.2 Verify says the list "must" include `DATING_CONSOLE_ORIGIN`, but its value is only known at step 6. The script treats it as optional; align the doc.
- **M-6** (doc §0.6d, line 110): the push also deletes every v1 `dating_age_verifications` row (`20261109100000:54-61`) and `dating_consent_events` with purposes `historical_data` and `age_gate` (`20261106190000:95`, consent records). It also drops `dating_feature_snapshots` and `onboarding_profiles.mode`. Add counts for these to the baseline, so the owner knows what is discarded under the "never ran in production" assumption.
- **M-7** (doc §0.7): there is no stop rule. Every `format_drift` row (`+233…` against Auth's `233…`) is rewritten without the `+`, and every `will_be_nulled` row loses `users.phone`. Say what count should make the owner stop and look.
- **M-8** (doc §2.1): 207 `SET LOCAL lock_timeout = '5s'` statements. On a live project, a busy `users` or `relationships` table can fail a file on its lock. Add "re-run at a quiet time" to "If it fails".
- **M-9** (doc §8.5): N is counted before the push, but `20261119100000:39` deletes `dating_alignment_algorithm_v1`. If that flag was on, the total reads 27 + N − 1. Mention it next to the "total differs" note.
- **M-10** (script lines 188–194, 609): the doc's fallbacks (`--use-api` without Docker, last month's DB-IP CSV early in a month) need edits to the script. Add `ATTUNE_DEPLOY_USE_API=1` and `DBIP_MONTH=YYYY-MM` overrides.
- **M-11** (script line 84): with `set -E`, a failing `$(sql_value …)` runs the ERR trap in the subshell and again in the parent, so the failure message prints twice. Cosmetic.

## Not changed by this review

Nothing in the doc, the script, the migrations or the functions was edited. The only new file is this review. Local scratch files went to the session scratchpad, and the temporary database `attune_review_deploy_tmp` was dropped.

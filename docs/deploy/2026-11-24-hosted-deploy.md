# Hosted deploy, 2026-11-24: Spec 1 W1–W10 + Spec 2 W1–W10 in demo mode

The script for this checklist is `scripts/deploy/hosted_deploy.sh`. It follows the same order. Run it with `--dry-run` first: that only prints and calls no tool. Every step is the owner's to run. Nothing here was run against the hosted project while it was being written. Revised after the review in `docs/deploy/2026-11-24-hosted-deploy-review.md` (C-1, C-2, I-1–I-7, M-1–M-11).

## Testers, read first

**Who uses this project:** only the owner and the testers use the current App Store / Play build against this project (owner, 2026-11-24). The script asks you to confirm that by typing `yes` before anything else. If anyone else uses the store build here, stop: this deploy breaks it for them.

**What breaks on the current store build, from the push onwards:**
- **No name on sign-up.** A new account that onboards on the store build can't save its name. The `users` upsert is refused, and the `onboarding_profiles` upsert fails because `mode` is dropped (`20261025100000`, `20261025100300`). The app says "Saved locally", and the partner sees a blank name. It self-heals once that phone installs the new build and the saved payload replays.
- **Invites need a birth date once `flow_signin_v2` is on** (step 8). Every existing account has no birth date in the new table, so:
  - creating an invite answers `invite:age_required`;
  - accepting answers `invite:age_required`, or `invite:not_possible` when the inviter has no birth date;
  - this includes invites that are already pending.

  The store build can't ask for a birth date and doesn't know these codes, so unlinked couples on it are stuck until they update.
- **Forums show an error state** (`20261025090100` revokes client access; the forum-free build hides the tab).
- **Dating v1 is gone.** Its RPCs and `verify-dating-profile` are removed.
- **Journal Patterns is blank** while `journal_ai_insights` is off (from step 3 until step 8). Healing AI answers `paused` over the same gap.
- **Opinions:**
  - with `opinions_safety_v1` on, every post and comment is filtered server-side by the unreviewed `[DRAFT]` term list and the contact-detail rule, and the store build shows the refusal codes as a generic error;
  - confirmed removals now count toward a real 7-day ban.
- **Undo:** the `onboarding_profiles.mode` drop can only be undone by a restore.

**Every tester installs the new (W10) build** right after the push. Use a **debug or profile** build for Dating demos: the fake verification capture is refused in release builds. Every flag stays on as planned.

## Summary

| What | Count | Notes |
|---|---|---|
| Migrations | **127** | `20261025090000` → `20261125100050`, in one `supabase db push --db-url "$ATTUNE_DB_URL"`. They are 58 migration + `_grants` twin pairs plus 11 singles (the last six are the Spec 3 W3 forum drop). Assumption: the last applied file is `20261024100800_my_closed_story_items.sql` (Stories, deployed 2026-10-24). Step 0.5 checks this. |
| Edge functions | **20 deploys, 4 deletes** | 12 new and 8 changed. `verify_jwt = false` on `otp-delivery-intent`, `send-sms-hook`, `start-fresh-account` and `dating-moderation`. Delete `upload-dating-photo`, `verify-dating-profile`, `activate-topics` and `forum-quiet-check`. Everything ships from a clean tree at `9bac1bdb` or later. |
| Cron jobs | **23** (+1 conditional) | The migrations create every one of them. `enqueue-new-storage-objects` exists only if the media scan takes the sweep path. Three forum jobs are removed. |
| Secrets | **6 Vault keys to create, 4 edge secrets to set, 3 existing to confirm** | The script asks for each value with a hidden prompt. Plus 23 vendor secrets that are set only when a vendor is contracted. `attune_environment` is never set. |
| Feature flags on | **27** set by the dev scripts | 12 Spec 1, 8 Dating (traveller included), 2 Spec 5, 3 Spec 7, 2 Spec 8. `dating_candidate_generation` is held off from step 8 until both demo enrolments are active (step 9.1), so 26 are on in between. The total is 27 + N, where N is the number of the other flags already on (step 0.7). |
| Expected time | **about 4–5 hours** on the day, plus 15 minutes the next day | Pre-flight 30 min, secrets 20, push 15, functions 40, crons 20 (waiting for ticks), IP table 15, console 30, moderators/MFA/hooks 20, flags 10, app smoke 60–90. The next-day check covers the daily jobs (02:47, 03:17, 04:41 UTC). |

**Owner decisions this deploy implements** (memory `hosted_deploy_plan.md`, 2026-11-23, and 2026-11-24):
- There is one hosted project and no separate production project.
- Everything is deployed now.
- The project stays in **development mode**: `attune_environment` is never set.
- Every Dating and traveller flag is on, for demos.
- Only the owner and testers use the store build.
- The owner sets every secret and runs every command.
- The forum table drop (Spec 3 W3) is part of this deploy (owner, 2026-11-24; branch `spec3-w3-forum-drop` merged): its six migrations (`20261125100000`–`100050`) sort last, so they apply in the same push right after everything else, the W2 forum-retirement migrations included. W3 is irreversible. The Vault keys (step 1, `dating_exclusion_key` included) must be set before the push: W3's migration 3 stamps Opinions strikes from removed forum posts before dropping them, and its preflight refuses without the key. Step 0.9b probes, before the push, what W3's preflight would refuse. See the W3 plan's Owner checklist 4 for its refusals.

**Placeholders and secrets hygiene:**
- `$SUPABASE_PROJECT_REF` is the project's ref. It is not a secret.
- `ATTUNE_DB_URL` is a Postgres connection string for the `postgres` role (Dashboard → Connect).
  - **Don't type it into an `export` line.** Leave it unset and the script asks for it with a hidden prompt.
  - If you do set it in the shell, start the line with a space after `setopt HIST_IGNORE_SPACE` (zsh) or `HISTCONTROL=ignorespace` (bash).
  - Better: a password-free URL plus `~/.pgpass` (mode 600). That also keeps the password out of `ps`. psql and `supabase db push --db-url` both pass the URL on their command line.
- `ATTUNE_ANON_KEY` (the publishable key, step 6) is also asked for with a hidden prompt.
- Vault keys and edge secrets are asked for with hidden prompts and never typed on a command line:
  - Vault values reach psql on stdin, never in the SQL editor's history.
  - Edge values go through a mode-600 temp file that is deleted at once.
  - Step 0.3 first checks that the database logs can't keep statement values.
- `<…>` is a value only you have.
- Never paste a secret into this file, into the script, or into the SQL editor. If you used the editor for one anyway, delete that query from its history.

**Before a real run:** commit (and push) these two files and the review. The script refuses a working tree with any change other than `backup-before-planning-p2.sql` and `supabase/.temp/`, because migrations and functions deploy from the files on disk. It prints `HEAD` and requires `9bac1bdb` or a descendant, on `origin/main` after a `git fetch` (it asks before using an unpushed commit). It re-checks the tree before the push and before every deploy batch.

**Which ref:** the development guards refuse every dev script unless the project URL names the development ref that is hard-coded in `supabase/migrations/20261025100400_spec1_flags_and_public_config.sql` (`private.assert_development_project`). The stub CSAM matcher and the fake verification do the same (`_shared/csam_matcher.ts` `DEVELOPMENT_PROJECT_REF`). The script refuses any other `SUPABASE_PROJECT_REF`, in dry runs too when one is set.

**Same database for the CLI and psql (every run, every resume):**
- Every database command uses `--db-url "$ATTUNE_DB_URL"`: `db push`, `migration list` and `db dump`. Nothing relies on `supabase link`.
- The script refuses a URL that doesn't name the ref.
- It also checks that the database's Vault `supabase_url` names the ref, reading only a count.

---

## 0. Pre-flight (stop-and-decide steps are marked STOP)

### 0.0 STOP: testers only
- **What:** the section above. The script asks you to type `yes` to: "Only the owner and testers use the store build on this project".
- **If not:** stop. Ship the W10 build to the stores first.

### 0.1 Confirm the target
- **Command:** `supabase projects list`. The script also runs `select current_database(), current_user;` and the ref and Vault checks above.
- **Verify:** `postgres|postgres`, and the Vault `supabase_url` names the ref.
- **If it fails:** stop. Never push against an unconfirmed target.

### 0.2 Postgres 17 (S1 W9 checklist item 1)
- **What:** `20261104100000_opinion_content_filter.sql` needs the `pg_c_utf8` collation.
- **Command:** `select current_setting('server_version_num')::int >= 170000;`
- **Verify:** `t`.
- **If not:** STOP. Upgrade the project (Dashboard → Settings → Infrastructure) first. Otherwise the push stops at `20261104100000`, with the 43 files before it applied.

### 0.3 STOP: the database logs keep no statement values (before any key is created)
- **What:** `vault.create_secret` sends the key in the statement. If `log_statement` is `all` or `mod`, the key lands in the Postgres logs, and `dating_field_key` and `dating_exclusion_key` can never be rotated.
- **Command:**
  ```sql
  select name, setting from pg_settings
   where name in ('log_statement','log_min_duration_statement','log_parameter_max_length','log_parameter_max_length_on_error') order by 1;
  select coalesce(current_setting('log_statement', true) in ('none','ddl')
         and (current_setting('log_min_duration_statement', true) = '-1' or current_setting('log_parameter_max_length', true) = '0')
         and current_setting('log_parameter_max_length_on_error', true) = '0', false);
  ```
  This is the same rule as `get_dating_operational_health() -> 'log_settings_safe'`.
- **Verify:** `t`.
- **If not:** set `log_statement` to `none` or `ddl`, `log_parameter_max_length_on_error` to `0`, and either `log_min_duration_statement` to `-1` or `log_parameter_max_length` to `0` (Dashboard → Database → Settings, or ask support), then re-check. If pgaudit is on, make sure it doesn't log these statements. The script refuses to go on until the check reads `t`.

### 0.4 Backup / PITR
- **What:** the only real rollback for a 127-file push (the forum drop in it has no down migration).
- **Commands:**
  - Dashboard → Database → Backups: note the latest daily backup time. If PITR is enabled, note the exact UTC time just before the push. That time is your restore point.
  - Optional local dumps, kept **outside the repo** (they hold personal data; never commit them):
    ```bash
    mkdir -p "$HOME/attune-backups" && chmod 700 "$HOME/attune-backups"
    supabase db dump --db-url "$ATTUNE_DB_URL" -f "$HOME/attune-backups/2026-11-24-schema.sql"
    supabase db dump --db-url "$ATTUNE_DB_URL" --data-only -f "$HOME/attune-backups/2026-11-24-data.sql"
    ```
- **Verify:** both files are non-empty (`wc -c`).
- **If it fails:** don't push without at least the dashboard backup time noted.

### 0.5 What is already applied (`supabase migration list`)
- **What:** confirms the assumption that nothing after `20261024100800` is live.
  - The memory index says "nothing since 2026-11-01". The wave memories say Spec 1 W1–W3 and the four forum files (dated 2026-10-25/26) are undeployed too, so the expected pending set is 127 files (121 plus the six Spec 3 W3 files).
  - Spec 2 W1's plan (item 21) once called `20261025100010` "already applied on hosted projects". Trust the list, not the memory.
- **Command:**
  ```bash
  supabase migration list --db-url "$ATTUNE_DB_URL"
  supabase db push --db-url "$ATTUNE_DB_URL" --dry-run
  ```
  The URL must be percent-encoded.
- **Verify:**
  - The script compares the local files with `supabase_migrations.schema_migrations`: 127 pending, first `20261025090000`, last `20261125100050` (Appendix A).
  - SQL cross-check: `select max(version) from supabase_migrations.schema_migrations;` → `20261024100800`.
- **If it differs:**
  - **Fewer files pending:** fine if the missing ones are the earliest ones and the remote has them. Note which are gone, and skip the matching baselines (for example 0.8 if W1 is already live).
  - **The CLI says "Found local migration files to be inserted before the last migration on remote":** STOP. Don't add `--include-all` blindly.
  - **Any other file listed:** STOP.

### 0.6 Production mode must not be set
- **Command:** `select count(*) from vault.secrets where name = 'attune_environment';`
- **Verify:** `0`. After the push, `select public.get_attune_environment();` must read `development`.
- **If it is 1:** STOP. In production mode the dev scripts refuse, the stub and fake vendors are refused, and the Dating flags are blocked.

### 0.7 Baselines (read-only; keep the output)
```sql
-- a) flags now, and N = enabled flags the dev scripts do NOT set (dating_alignment_algorithm_v1 is
--    left out: 20261119100000 deletes it, so it never counts after the push)
select key, enabled from public.feature_flags order by key;
select count(*) filter (where enabled) as n_other_on
  from public.feature_flags
 where key <> all (array['flow_signin_v2','flow_paths_v2','flow_couples_v2','couple_profile','dormancy_rule',
   'platform_age_signals','support_resources_v2','csam_hash_matching','opinions_safety_v1','journal_ai_insights',
   'healing_ai_insights','text_scale_v2','dating_mode_enabled','dating_candidate_generation','dating_match_messaging',
   'dating_profile_photos','dating_same_gender_matching','dating_age_assurance','dating_traveller_detection',
   'dating_couple_link','quiz_clinical_signoff','couple_map_enabled','appreciation_notes','share_a_win',
   'quiet_states','private_safety_check','conflict_toolkit'])
   and key <> 'dating_alignment_algorithm_v1';
-- b) S1 W1: names that 20261025100000 trims to 40 characters (P-6)
select count(*) from public.users where char_length(display_name) > 40;
-- c) S1 W9: accounts whose NEXT confirmed removal bans at once (release note)
select count(*) from public.profiles where confirmed_violation_count >= 2;
-- d) S2 W5: v1 Dating rows 20261119100000 collapses (newest per pair kept)
select (select count(*) from public.dating_introductions) as intros, (select count(*) from public.dating_matches) as matches;
-- e) what the push discards outright (v1 data that "never ran in production")
select (select count(*) from public.dating_age_verifications) as v1_age_verifications_deleted,          -- 20261109100000
       (select count(*) from public.dating_consent_events where purpose in ('historical_data', 'age_gate'))
                                                               as consent_events_deleted,             -- 20261106190000
       (select count(*) from public.dating_feature_snapshots)  as feature_snapshots_dropped,          -- 20261119100000
       (select count(*) from public.onboarding_profiles where mode is not null) as onboarding_mode_values_dropped; -- 20261025100300
-- f) cron snapshot (forum W2 step 1)
select jobid, jobname, username, schedule, active, left(command, 120) from cron.job order by jobname;
```
Rows in (e) belong to testers on this project. Non-zero counts are expected, and the data is gone after the push (restore only).

### 0.8 STOP: Spec 1 W1 phone drift (W1 checklist item 0)
```sql
select count(*) filter (where u.phone is distinct from a.phone) as drift_rows,
       count(*) filter (where u.phone is distinct from a.phone and a.phone_confirmed_at is not null
                          and nullif(btrim(a.phone), '') is not null) as will_be_restored,
       count(*) filter (where u.phone is not null and (a.id is null or a.phone_confirmed_at is null
                          or nullif(btrim(a.phone), '') is null)) as will_be_nulled,
       count(*) filter (where u.phone = '+' || a.phone) as format_drift
  from public.users u left join auth.users a on a.id = u.id;
-- the rows themselves
select u.id, u.phone is not null as has_phone, a.phone_confirmed_at is not null as auth_confirmed,
       u.phone = '+' || a.phone as format_drift
  from public.users u left join auth.users a on a.id = u.id
 where u.phone is distinct from a.phone order by 4 desc, 3, 1;
```
- **Stop rule:** if `will_be_nulled > 0` or `format_drift > 0`, look at each row before going on.
  - A `will_be_nulled` row loses `users.phone`.
  - A `format_drift` row is rewritten without its `+`, which changes its Dating exclusion HMAC.
  - Continue only when every such row is a known test account, or you accept it.
- Step 2.3 re-runs the counts and expects `will_be_restored = 0` and `will_be_nulled = 0`.

### 0.9 Forum retirement pre-checks (Spec 3 W2 checklist step 1b)
- **Store build:** only testers use it (0.0). They see Forums in an error state until they install the new build.
- **Cron ownership (read-only):**
  ```sql
  select current_user, (select rolbypassrls from pg_roles where rolname = current_user) as sees_all_jobs,
         has_table_privilege('cron.job', 'DELETE') as can_unschedule_others;
  select jobid, jobname, username, username = current_user as owned_by_me, active, schedule
    from cron.job
   where jobname in ('activate-topics-sweep', 'forum-quiet-check', 'mark-quiet-forums')
      or command ~* '(activate-topics|forum-quiet-check|forum_topics|mark_quiet_topics|activate_pending_topics|expire_old_topics|notify_quiet_topic)';
  ```
- **Go:** every listed job has `owned_by_me = t`. If a job is owned by another role and `can_unschedule_others = f`, unschedule it from Dashboard → Integrations → Cron first.

### 0.9b STOP: Spec 3 W3 pre-push probe (read-only; W3 final review I-1)
- **What:** W3's migration 1 refuses the push if a function it checks was hand-edited in production, or production has a forum function W3 doesn't know. In this push that refusal comes only after the 121 earlier files are applied, mid-deploy. This probe finds it before the push. The script runs it here and again at the start of step 2, and stops on any difference.
- Four of the six bodies W3 checks are live now and nothing in the pending set re-creates them; the other two (`admin_confirm_content_removal`, `opinion_stamp_backfill`) are re-created by `20261107100000` in the same push and cannot drift.
  ```sql
  select p.oid::regprocedure, md5(p.prosrc) from pg_proc p where p.oid in (
    'private.assert_can_post(uuid,text)'::regprocedure,
    'private.create_poll_for_post(uuid,uuid,uuid,text[])'::regprocedure,
    'public.get_post_poll(uuid,uuid)'::regprocedure,
    'private.enqueue_forum_notification(uuid,text,text,text,uuid,uuid,uuid)'::regprocedure);
  -- expect: 920660396b7d4e331db2948838f98333, 6154f307c3afdb76c0249c2db2ec44f6,
  --         dd3f4fc152767cd7b054c8324a46020e, 3d57c8b5ca75d1edbe87192d5af837e1
  ```
  The script also runs migration 1's inventory (a) (`w3_probe` in `scripts/deploy/hosted_deploy.sh`); it must list nothing.
- **Go:** all four match and the inventory is empty.
- **No-go:** deploy from a commit without the W3 merge (121 files), or re-plan W3's migrations 4–5 and migration 1's md5s from `select pg_get_functiondef('<sig>'::regprocedure);` first.

### 0.10 No dashboard Database Webhooks on sensitive tables (S2 W9 owner list 1.4)
- **Command:**
  ```sql
  select event_object_schema, event_object_table, trigger_name
    from information_schema.triggers
   where action_statement ilike '%supabase_functions.http_request%' order by 2;
  ```
- **Verify:** no row for `relationships`, `users`, `couple_profiles`, `couple_how_we_met`, `together_change_signals`, `relationship_invite_acceptances` or any `dating_*` table. Also check Dashboard → Database → Webhooks.
- **If one exists:** STOP. Delete it in the dashboard first.

### 0.11 STOP: Spec 1 W1 purge go/no-go (W1 checklist item 2; review I-1)
- **What:** `20261025100500` arms the hourly `purge-unfinished-signups` cron at push time.
  - The function calls `auth.admin.deleteUser` on accounts with no `users` row and no activity in the last 24 hours, 500 per run.
  - The deletion cascades through every table with a foreign key to `auth.users` (about 99 outside `auth` and `storage`). It runs every hour from then on.
- **The probe:** rows in every such table that belong to an account with no `users` row.
  - It covers every account with no `users` row, not just today's idle ones. Each of them becomes a candidate once it is idle for 24 hours.
  - It is read-only: one count per foreign key.
  ```sql
  do $$ declare r record; n bigint; total bigint := 0; begin
    for r in select c.conrelid::regclass as tbl, a.attname as col
               from pg_constraint c join pg_attribute a on a.attrelid = c.conrelid and a.attnum = c.conkey[1]
              where c.contype = 'f' and c.confrelid = 'auth.users'::regclass
                and c.connamespace not in ('auth'::regnamespace, 'storage'::regnamespace) loop
      execute format('select count(*) from %s t where t.%I in (select a.id from auth.users a
        where not exists (select 1 from public.users u where u.id = a.id))', r.tbl, r.col) into n;
      total := total + n; if n > 0 then raise notice '%.%: %', r.tbl, r.col, n; end if;
    end loop; raise notice 'rows tied to accounts without a users row: %', total; end $$;
  ```
  The script runs the same probe as one `select` (via `query_to_xml`), so it can read the total. Run the `do` block above in the SQL editor to see which tables hold rows.
- **GO only when the total is 0.** There is no "I reviewed the ids" exception. Then `purge-unfinished-signups` is deployed in step 3.
- **NO-GO** (total above 0): the function is not deployed, step 2.5 unschedules its cron, and step 11 says how to re-arm it later.
- **The forum tables count here** (W3 final review M-6): seven of them (`forum_topics`, `topic_votes`, `topic_impressions`, `forum_posts`, `forum_post_likes`, `user_forum_sides`, `forum_topic_visits`) have foreign keys to `auth.users`, and W3 deletes them in this push. If the only non-zero tables were forum ones, re-run the `do` block after step 2: it then reads 0, and the purge can be re-armed per step 11.
- An undecided or missing decision counts as NO-GO.

### 0.12 The purge must not already be live (review I-2)
- **What:** if `purge-unfinished-signups` is already deployed (from an earlier no-names deploy or another worktree), the push arms it, and it deletes accounts at the first `:41`, before 2.5 can stop it.
- **Commands:**
  - `supabase functions list --project-ref "$SUPABASE_PROJECT_REF"` must not list `purge-unfinished-signups`.
  - `select count(*) from cron.job where jobname = 'purge-unfinished-signups';` → `0` (it is `1` only if W1 is already applied).
- **If either is there and the decision is NO-GO:** the script deletes the function (`supabase functions delete purge-unfinished-signups --project-ref "$SUPABASE_PROJECT_REF"`) and unschedules the cron before the push. On GO, both may stay.

### 0.13 Acknowledge what goes live whatever the flags
- [ ] **W9c/W9e support card copy ships unsigned.** The journal and Healing crisis cards, "Need support now?" and the manual passages go live with `analyse-journal-entry` and the two Healing functions. The clinician hasn't signed them.
- [ ] **Opinions:** the third confirmed removal now really bans for 7 days, and the 0.7c accounts are banned at their next removal.
- [ ] **The store-build effects** in "Testers, read first".
- [ ] **Local only, skip here:** the stray empty local database (W10 owner list §5) is on your local Postgres cluster, not the hosted project. `dropdb '/private/tmp/claude-501/-Users-user-attune/ae9d44ca-41d8-47c2-b'` locally whenever you like.

---

## 1. Secrets and Vault keys (hidden prompts; you hold every value)

Set the Vault keys **before** the push. Then the backfills and fingerprint seeds that run at apply time (`20261106100000`, `20261106140000`, `20261106190000`, `20261107100000`, and `20261125100020`, which runs `opinion_stamp_backfill()` before the forum drop and refuses without `dating_exclusion_key`) use them. Step 2.4 re-runs them anyway; they are idempotent.

### 1.1 Vault keys (the script asks for each one, hidden, and sends it to psql on stdin)

| Name | Value shape (the script checks it) | Used by | Required now? |
|---|---|---|---|
| `dating_exclusion_key` | 48+ characters, no spaces or quotes | Every exclusion, block pair, never-introduce entry, restriction stamp, report HMAC, Opinions stamp (W9d) and fresh-start park (W6) | **Yes.** **Never rotate, replace or delete it.** Keep an offline copy. |
| `dating_field_key` | base64 of 32 random bytes (44 characters ending in `=`) | Encrypted Dating answers and report evidence | **Yes.** Keep an offline copy: losing it makes every encrypted answer unreadable. Never replace it in place. |
| `dating_push_key` | 64 lowercase hex characters | Every Dating push | **Yes.** |
| `fresh_start_key` | 48+ characters | `start-fresh-account` (W6) | **Yes.** |
| `moderation_alert_webhook` | an `https://` URL | The SLA alerts | Recommended (empty = skip). |
| `age_assurance_mode` | `fake` / `sandbox` | `dating-verification` | Step 8.1. |
| `supabase_url`, `service_role_key` | (existing since `20260931120000`) | Every cron that calls a function | Confirm they exist. |
| `attune_environment` | — | — | **Never set it in this deploy.** |

- **Generating:** use a password manager, or for example `openssl rand -base64 48 | tr -d '\n/+='` (exclusion and fresh-start), `openssl rand -base64 32` (field key) and `openssl rand -hex 32` (push key). Paste the value into the script's hidden prompt.
- **How the script writes them:** it never replaces an existing key. It sends `\set v '<value>'` and `select vault.create_secret(:'v', '<name>');` to psql on stdin, so the value is never on a command line or in the SQL editor's history.
- **Doing it by hand instead:** use psql the same way, or Dashboard → Vault. Never the SQL editor's query window.

**Verify (names only):**
```sql
select name from vault.secrets
 where name in ('dating_exclusion_key','dating_field_key','dating_push_key','fresh_start_key',
                'moderation_alert_webhook','age_assurance_mode','supabase_url','service_role_key','attune_environment')
 order by name;
```
Expected: the first four plus `supabase_url` and `service_role_key`, and the recommended ones if you set them. `attune_environment` must be absent. The script refuses to go on without the six required names.

### 1.2 Edge function secrets (hidden prompts, sent with `supabase secrets set --env-file <600 temp file>`)

| Name | Used by | When |
|---|---|---|
| `CSAM_MATCHER` = `stub` | `scan-media`, `process-dating-photo` | **Step 1, before the push** (S1 W7 PF-L8). The stub works only in development, on the dev ref. Not a secret: the script asks yes/no. |
| `OTP_HMAC_KEY` | `otp-delivery-intent`, `send-sms-hook`, `start-fresh-account` | **Step 1.** 32+ random bytes (`openssl rand -base64 48`). |
| `SAFETY_ALERT_WEBHOOK` | `identity-health-alert`, `scan-media` | Step 1, recommended (empty = skip). |
| `DATING_CONSOLE_ORIGIN` | `dating-moderation` (CORS) | **Step 6**, once the console's address is known. The script asks for it there. `dating-moderation` is deployed only after it exists. |
| `GOOGLE_VISION_API_KEY` | `process-dating-photo` | **Confirm it exists** (from Dating v1), with `LABEL_DETECTION` enabled. Without it photos stay pending. |
| `DATING_PHOTO_VISION` = `stub` | `process-dating-photo` | **Only while there is no `GOOGLE_VISION_API_KEY`** (owner 2026-11-25: no Google billing yet). Every JPEG photo that passes the CSAM scan reads as one clear adult face and is approved (the app sends JPEG; a PNG goes to a person). Photos approved this way stay approved: see the release checklist's real-photo-checks line. Works only in development on the dev ref; a real key always wins. Not a secret: the script asks yes/no. **Before launch:** set the real key, then `supabase secrets unset DATING_PHOTO_VISION`. |
| `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, `SUPABASE_ANON_KEY` | all | Provided by the platform. Never set them. |

**Vendor secrets: set only once the vendor is contracted.** The demo works without them, as follows:
- **SMS, voice and WhatsApp** (only if you switch on the Send SMS hook, step 7.4):
  - `SEND_SMS_HOOK_SECRET`
  - `TWILIO_ACCOUNT_SID`, `TWILIO_AUTH_TOKEN`, `TWILIO_MESSAGING_SERVICE_SID` (or `TWILIO_SMS_FROM`), `TWILIO_VOICE_FROM`
  - `ARKESEL_API_KEY`, `ARKESEL_SENDER_ID`
  - `WHATSAPP_ACCESS_TOKEN`, `WHATSAPP_PHONE_NUMBER_ID`, and optionally `WHATSAPP_TEMPLATE_NAME` and `WHATSAPP_TEMPLATE_LANGUAGE`
  - `ANDROID_SMS_APP_HASHES`
- **Real CSAM matching:** `PHOTODNA_SUBSCRIPTION_KEY` and optionally `PHOTODNA_URL`, or `SAFER_API_KEY` and `SAFER_MATCH_URL`. `CSAM_STUB_MATCH_SHA256` is optional.
- **Verification vendors** (needed for `sandbox`/`live`; `fake` needs none):
  - `AWS_REKOGNITION_ACCESS_KEY_ID`, `AWS_REKOGNITION_SECRET_ACCESS_KEY`, `AWS_REKOGNITION_REGION` (EU/UK)
  - `SMILE_ID_PARTNER_ID`, `SMILE_ID_API_KEY`

  Set these with `supabase secrets set --env-file <600 file outside the repo> --project-ref "$SUPABASE_PROJECT_REF"`, then delete the file.

**Verify:** `supabase secrets list --project-ref "$SUPABASE_PROJECT_REF"` prints names and digests, never values. After step 1 it must list `CSAM_MATCHER`, `OTP_HMAC_KEY`, and `GOOGLE_VISION_API_KEY` or `DATING_PHOTO_VISION`. `DATING_CONSOLE_ORIGIN` follows in step 6.

**If it fails:** fix it and re-check. Nothing is deployed yet.

---

## 2. Migrations (one `supabase db push --db-url "$ATTUNE_DB_URL"`)

### 2.1 The push
- **What:** applies the 127 files in Appendix A, in order, each in its own transaction.
  - Every `_grants` twin re-asserts its migration's grants.
  - `20261025100000` and the Spec 2 W6–W10 files (`20261120*`–`20261124*`) revoke what they create until their twin runs. A push that stops between a file and its twin **fails closed**: re-run it.
  - The script re-checks that the tree is clean first.
- **Command:**
  ```bash
  supabase db push --db-url "$ATTUNE_DB_URL" --dry-run   # the list again: 127 files
  supabase db push --db-url "$ATTUNE_DB_URL"             # answer the prompt with Y
  ```
- **Watch the output for:**
  - `NOTICE: media_scan: new uploads reach the scan queue by …` Record whether it says trigger or sweep.
  - Any NOTICE about a missing `dating_exclusion_key`. There should be none after step 1.
  - The forum unschedule NOTICEs.
- **If it fails:**
  - The CLI stops at the failing file, and everything before it stays applied.
  - **A lock timeout:** 207 statements use `SET LOCAL lock_timeout = '5s'`, so a busy `users` or `relationships` table can fail a file on its lock. Re-run at a quiet time, with testers' apps closed.
  - **Otherwise:** fix the cause and run `supabase db push --db-url "$ATTUNE_DB_URL"` again. An applied migration is never re-run.
  - Never `db reset`. Never edit an applied file.

### 2.2 Right after the push: every migration landed
```sql
select count(*) from supabase_migrations.schema_migrations where version >= '20261025090000';  -- 127
select public.get_attune_environment();                                                        -- development
```

### 2.3 Post-push checks (each expected value is from that wave's owner list)
```sql
-- S1 W1: users.phone closed to the client                                   → f | f
select has_column_privilege('authenticated','public.users','phone','UPDATE'), has_table_privilege('authenticated','public.users','INSERT');
-- S1 W1: re-run the 0.8 counts                                              → will_be_restored = 0, will_be_nulled = 0 (drift_rows may stay > 0)
-- S1 W4: no client insert on relationships                                  → f
select has_table_privilege('authenticated','public.relationships','INSERT');
-- S1 W5: About us is not in Realtime                                        → 0 rows
select tablename from pg_publication_tables where tablename like 'couple_profile%';
-- S1 W6: access-token hook callable by Auth only                            → t | f | f
select has_function_privilege('supabase_auth_admin','public.attune_access_token_hook(jsonb)','EXECUTE'),
       has_function_privilege('authenticated','public.attune_access_token_hook(jsonb)','EXECUTE'),
       has_function_privilege('service_role','public.attune_access_token_hook(jsonb)','EXECUTE');
-- S1 W6: activity seeded                                                    → about the number of public.users rows
select (select count(*) from public.account_activity) as activity, (select count(*) from public.users) as users;
-- S1 W6/W7: identity health                                                 → fresh_start_key_present true; media_scan_enqueue_path trigger|sweep; *_failures 0
select public.get_identity_health();
-- S1 W7: buckets                                                            → two rows: avatars | t, safety-quarantine | f
select id, public from storage.buckets where id in ('safety-quarantine', 'avatars') order by id;
-- S1 W7: no storage policy reaches the quarantine                           → 0 rows
select policyname from pg_policies where schemaname = 'storage' and tablename = 'objects'
   and ((coalesce(qual,'') || coalesce(with_check,'')) ~ 'safety-quarantine' or (coalesce(qual,'') || coalesce(with_check,'')) !~ 'bucket_id = ');
-- S1 W9: the normaliser                                                     → kokoo bastard | contact_info | (null)
select private.match_form('K' || chr(596) || 'k' || chr(596) || chr(596) || ' B@st4rd'),
       private.content_filter_verdict('call me on 024 412 3456', null),
       private.content_filter_verdict('We met in 1999 and married in 2004.', null);
-- Spec 3 W2 + W3: forum retirement and drop                                 → 7 rows, all ok = true
select * from public.forum_retirement_health();
-- S2 W1: keys and logging                                                   → true | true | true | development
select h ->> 'field_key_present', h ->> 'field_key_fingerprint_ok', h -> 'log_settings_safe', h ->> 'environment'
  from (select public.get_dating_operational_health() as h) s;
select private.dating_exclusion_key_ready();                                -- t
-- S2 W1: gate rows for the Dating flags                                     → 8
select count(*) from private.flag_production_gates where flag_key like 'dating%';
-- S2 W2: the path trigger (D18)                                             → 1 row
select tgname from pg_trigger where tgrelid = 'public.users'::regclass and tgname = 'dating_pause_on_path_change';
-- S2 W3: photo bucket limits                                                → 2097152 | {image/jpeg,image/png,image/webp}
select file_size_limit, allowed_mime_types from storage.buckets where id = 'dating-profile-photos';
-- S2 W6: every closed match has an evidence window                          → 0
select count(*) from public.dating_matches where state <> 'active' and evidence_until is null;
-- S2 W9: the service role can't write export jobs (C-1)                     → f | t
select has_table_privilege('service_role','public.data_export_jobs','INSERT'), has_table_privilege('service_role','public.data_export_jobs','SELECT');
```
- `media_scan_enqueue_path = sweep` because `lock_not_available` (PF-M4): at a quiet time, run `select private.install_media_scan_enqueue();` and re-check.
- **Any other mismatch:** stop before step 3.

### 2.4 Key seeding and backfills (idempotent; run in this order)
```sql
select public.backfill_dating_former_partner_exclusions();
select private.seed_dating_exclusion_key_fingerprint();      -- ready
select private.seed_dating_field_key_fingerprint();          -- ready (missing_key = the Vault key isn't readable)
select private.dating_stamp_restriction_hmacs();             -- a count; -1 = key still missing
select private.opinion_stamp_backfill();                     -- a count; -1 = key still missing (W9d item 2)
```
The script stops unless both seeds answer `ready` and neither backfill answers `-1`.

### 2.5 NO-GO only: unschedule the purge
`select cron.unschedule(jobid) from cron.job where jobname = 'purge-unfinished-signups';`. Then `select count(*) from cron.job where jobname = 'purge-unfinished-signups';` → `0`.

### 2.6 Load the support catalogue (S1 W7a item 3)
- **What:** loads `assets/support_resources/catalogue.json` through `public.load_support_resources` as the service role, all or nothing. It runs over psql (`BEGIN; SET LOCAL ROLE service_role; SELECT public.load_support_resources(:'catalogue'::jsonb); COMMIT;`), so no service-role key is typed anywhere.
- **Verify:** `{"loaded": 4, "deactivated": 0, "catalogue_version": "2026-11-03.1"}`. Then `select public.get_support_resources('GH');` lists Ghana Police DOVVSU and Find A Helpline.
- **If it fails:** nothing is written. The app shows its bundled catalogue meanwhile.
- **If postgres can't `SET ROLE service_role`:** stop and tell the developer. Don't put the service-role key on a command line.

## 3. Edge functions

Deploy after the push, in this order, in one sitting, from the clean tree that step 0 checked (the script re-checks it before each batch). The crons that the push armed already call some of these. Until a function is deployed its call gets a 404, which is harmless and retried.

| # | Function | New/changed | verify_jwt | Secrets it needs | Order constraint |
|---|---|---|---|---|---|
| 1 | delete `upload-dating-photo` | removed (W3) | — | — | any time after the push |
| 2 | delete `verify-dating-profile` | removed (W4) | — | — | any time after the push |
| 3 | delete `activate-topics` | removed (Spec 3 W2) | — | — | after the push (its crons are gone) |
| 4 | delete `forum-quiet-check` | removed (Spec 3 W2) | — | — | after the push |
| 5 | `process-dating-photo` | changed (W3c CSAM-first) | true | `CSAM_MATCHER`, `GOOGLE_VISION_API_KEY` | right after the push: the 15-minute orphan sweep and the photo trigger call it |
| 6 | `scan-media` | new (S1 W7b) | true | `CSAM_MATCHER`, `SAFETY_ALERT_WEBHOOK` | after `CSAM_MATCHER=stub` is set |
| 7 | `identity-health-alert` | new (S1 W1/W6c/W7b) | true | `SAFETY_ALERT_WEBHOOK` | after the push (cron `*/15`) |
| 8 | `purge-recovery-holds` | new (S1 W6) | true | — | after the push |
| 9 | `process-dating-safety-outbox` | new (S2 W6) | true | — | with `20261120110000` (its cron calls it only while a message is pending) |
| 10 | `build-data-exports` | changed (S2 W9 `dating_part.ts`) | true | — | **only after** `20261123100000` and its twin; otherwise every export's data part fails |
| 11 | `accept-invite` | changed (S1 W2 guard, W4 v2) | true | — | after `20261102100000` |
| 12 | `create-relationship-invite` | changed (S1 W2/W4) | true | — | after `20261102100000` |
| 13 | `analyse-journal-entry` | changed (S1 W9c/W9e) | true | (existing AI keys) | together with 14 and 15: the three run the same crisis check |
| 14 | `generate-healing-portrait` | changed (S1 W9e) | true | (existing AI keys) | with 13 |
| 15 | `generate-healing-post-mortem` | changed (S1 W9e) | true | (existing AI keys) | with 13 |
| 16 | `process-scheduled-notifications` | changed (S2 W3a `route` allowlist) | true | — | after the push |
| 17 | `otp-delivery-intent` | new (S1 W2c) | **false** | `OTP_HMAC_KEY` | after `20261025110000`. Inert until the SMS hook is on. |
| 18 | `send-sms-hook` | new (S1 W2c) | **false** | `OTP_HMAC_KEY` and the SMS secrets | after `20261025110000`. Inert until the hook is on (step 7.4). |
| 19 | `start-fresh-account` | new (S1 W6a) | **false** | `OTP_HMAC_KEY`; Vault `fresh_start_key`, `dating_exclusion_key` | after the push |
| 20 | `dating-verification` | new (S2 W4) | true | Vendor secrets for `sandbox`/`live`; none for `fake` | after the push |
| 21 | `dating-photo-urls` | new (S2 W5) | true | — | after the push |
| 22 | `dating-device-check` | new (S2 W8) | true | — (bundles `ip_country.bin`) | **step 5**, after the IP table is built |
| 23 | `dating-moderation` | new (S2 W7/W10) | **false** | `DATING_CONSOLE_ORIGIN` | step 6, after `DATING_CONSOLE_ORIGIN` is set and TOTP MFA is on (step 7.2) |
| 24 | `purge-unfinished-signups` | new (S1 W1) | true | — | **GO only** (0.11) |

**Commands:**
```bash
supabase functions delete upload-dating-photo   --project-ref "$SUPABASE_PROJECT_REF"
supabase functions delete verify-dating-profile --project-ref "$SUPABASE_PROJECT_REF"
supabase functions delete activate-topics       --project-ref "$SUPABASE_PROJECT_REF"
supabase functions delete forum-quiet-check     --project-ref "$SUPABASE_PROJECT_REF"
for f in process-dating-photo scan-media identity-health-alert purge-recovery-holds process-dating-safety-outbox \
         build-data-exports accept-invite create-relationship-invite analyse-journal-entry \
         generate-healing-portrait generate-healing-post-mortem process-scheduled-notifications \
         dating-verification dating-photo-urls; do
  supabase functions deploy "$f" --project-ref "$SUPABASE_PROJECT_REF"
done
for f in otp-delivery-intent send-sms-hook start-fresh-account; do
  supabase functions deploy "$f" --no-verify-jwt --project-ref "$SUPABASE_PROJECT_REF"
done
supabase functions deploy dating-moderation --no-verify-jwt --project-ref "$SUPABASE_PROJECT_REF"   # step 6, after the origin + 7.2
supabase functions deploy purge-unfinished-signups --project-ref "$SUPABASE_PROJECT_REF"           # GO only
```
`--no-verify-jwt` matches `supabase/config.toml`. Passing it is harmless if the CLI already reads the file. Bundling needs Docker. Without Docker, run the script with `ATTUNE_DEPLOY_USE_API=1`: it adds `--use-api` to every deploy.

**Verify:**
- `supabase functions list --project-ref "$SUPABASE_PROJECT_REF"`: every name above is ACTIVE with today's update time, and none of the four deleted names appear.
- Smoke: `curl -s -X POST https://$SUPABASE_PROJECT_REF.supabase.co/functions/v1/start-fresh-account -H 'Content-Type: application/json' -d '{"nonce":"x"}'` → `{"error":"fresh_start:invalid"}` (HTTP 400). This is W6 item 3.
- After 15 minutes:
  ```sql
  select status_code, count(*) from net._http_response where created > now() - interval '20 minutes' group by 1;
  ```
  → only 2xx. A 404 means a function that a cron calls isn't deployed. A 401 means a wrong `service_role_key` in Vault.

**If a deploy fails:**
- The previous version keeps running, and a new function simply doesn't exist yet. Fix and re-run that one deploy.
- Never run `supabase functions deploy` with no names. It would deploy `purge-unfinished-signups` past the go/no-go, and from an old checkout it re-creates the forum functions.
- Never use `--prune`.

---

## 4. Crons and scheduled jobs

The migrations create all 23 jobs (exact SQL is in the files named below), so there is nothing to schedule by hand. Spec 3 W2 removes `activate-topics-sweep`, `forum-quiet-check` and `mark-quiet-forums`. The pre-existing jobs (`expire-dating-introductions`, `revalidate-dating-lifecycle-gates`, `process-scheduled-notifications`, the AI jobs from `dev_resume_ai_jobs.sql`) are unchanged.

| Job | Schedule (UTC) | Command (exact, from the migration) | Migration | First run |
|---|---|---|---|---|
| `metric-counters-retention` | `12 4 * * *` | `DELETE FROM public.metric_counters WHERE day < current_date - 400` | `20261025100100` | next 04:12 |
| `purge-unfinished-signups` | `41 * * * *` | `SELECT public.invoke_edge_function('purge-unfinished-signups')` | `20261025100500` | next :41 (GO only; unscheduled on NO-GO) |
| `otp-purge` | `13 * * * *` | `SELECT private.otp_purge()` | `20261025110000` | next :13 |
| `enqueue-journal-reminders` | `*/15 * * * *` | `SELECT public.enqueue_journal_reminders();` | `20261026100000` | ≤ 15 min |
| `invite-preview-retention` | `39 * * * *` | `SELECT private.purge_invite_preview_attempts();` | `20261102100000` | next :39 |
| `fresh-start-retention` | `43 * * * *` | `SELECT private.fresh_start_retention()` | `20261103100200` | next :43 |
| `purge-recovery-holds` | `55 3 * * *` | `SELECT public.invoke_edge_function('purge-recovery-holds')` | `20261103100200` | next 03:55 |
| `identity-health-alert` | `*/15 * * * *` | `SELECT public.invoke_edge_function('identity-health-alert')` | `20261103100200` | ≤ 15 min |
| `scan-media` | `* * * * *` | `SELECT public.invoke_edge_function('scan-media') WHERE private.spec1_flag_on('csam_hash_matching')` | `20261103140000` | every minute (calls only once the flag is on) |
| `media-scan-retention` | `27 4 * * *` | `SELECT private.media_scan_retention()` | `20261103140000` | next 04:27 |
| `enqueue-new-storage-objects` | `* * * * *` | `SELECT private.enqueue_new_storage_objects()` | `20261103140100` | **only on the sweep path** |
| `media-scan-reconcile` | `41 4 * * *` | `SELECT private.reconcile_media_scan_queue()` | `20261103140100` | next 04:41 |
| `opinion-enforcement-purge` | `19 3 * * *` | `SELECT private.opinion_enforcement_purge()` | `20261107100000` | next 03:19 |
| `sweep-dating-photo-orphans` | `*/15 * * * *` | `SELECT public.invoke_edge_function('process-dating-photo')` | `20261107170000` | ≤ 15 min |
| `recover-stale-dating-photo-jobs` | `*/5 * * * *` | `SELECT public.recover_stale_dating_photo_jobs()` | `20261107170000` | ≤ 5 min |
| `dating-verification-sweep` | `*/15 * * * *` | `SELECT public.sweep_dating_verification_sessions()` | `20261109100000` | ≤ 15 min |
| `dating-candidate-generation` | `17 * * * *` | `SELECT public.run_dating_generation_tick()` (replaces the weekly v1 job) | `20261119100000` | next :17 |
| `dating-digest` | `5 * * * *` | `SELECT public.send_dating_digests()` | `20261119110000` | next :05 |
| `dating-fairness-weekly` | `17 4 * * 1` | `SELECT public.dating_fairness_weekly()` | `20261119120000` | next Monday 04:17 |
| `process-dating-safety-outbox` | `* * * * *` | `SELECT public.invoke_edge_function('process-dating-safety-outbox') WHERE EXISTS (SELECT 1 FROM public.dating_message_safety_outbox WHERE state = 'pending')` | `20261120110000` | every minute (calls only while a message waits) |
| `recover-stale-dating-workers` | `*/5 * * * *` | `SELECT public.recover_stale_dating_safety_jobs()` | `20261120110000` | ≤ 5 min |
| `purge-dating-retention` | `47 2 * * *` | `CALL public.run_dating_retention_purge()` | `20261120120000` | next 02:47 |
| `release-dating-suspensions` | `4-59/15 * * * *` | `SELECT private.dating_release_expired_suspensions()` | `20261121100000`, re-offset `20261121120000` | ≤ 15 min |
| `dating-moderation-sla` | `11-59/15 * * * *` | `SELECT public.dating_moderation_sla_check()` | `20261121110000`, re-offset `20261121120000` | ≤ 15 min |

**One check for every job**, the cron.job_run_details check, run 20 minutes after the push. Run it again the next day for the daily and weekly jobs:
```sql
with names(n) as (values
  ('metric-counters-retention'),('purge-unfinished-signups'),('otp-purge'),('enqueue-journal-reminders'),
  ('invite-preview-retention'),('fresh-start-retention'),('purge-recovery-holds'),('identity-health-alert'),
  ('scan-media'),('media-scan-retention'),('enqueue-new-storage-objects'),('media-scan-reconcile'),
  ('opinion-enforcement-purge'),('sweep-dating-photo-orphans'),('recover-stale-dating-photo-jobs'),
  ('dating-verification-sweep'),('dating-candidate-generation'),('dating-digest'),('dating-fairness-weekly'),
  ('process-dating-safety-outbox'),('recover-stale-dating-workers'),('purge-dating-retention'),
  ('release-dating-suspensions'),('dating-moderation-sla'))
select n.n as jobname, j.schedule, j.active, d.status, d.start_time, left(d.return_message, 80) as message
  from names n
  left join cron.job j on j.jobname = n.n
  left join lateral (select r.status, r.start_time, r.return_message from cron.job_run_details r
                      where r.jobid = j.jobid order by r.start_time desc limit 1) d on true
 order by 1;
```
- **Expected:**
  - Every row has a schedule. The exceptions are `enqueue-new-storage-objects` on the trigger path, and `purge-unfinished-signups` after a NO-GO.
  - Every job that has run shows `succeeded`.
  - The daily and weekly jobs show no run until their first time (table above).
- **Specific lines (owner lists):**
  - `purge-dating-retention`: a row with `CALL public.run_dating_retention_purge()` that `succeeded` after 02:47 UTC (W6).
  - `opinion-enforcement-purge`: `19 3 * * *` (W9d 2a).
- **Forum crons gone** (the script stops if not): `select count(*) from cron.job where jobname in ('activate-topics-sweep','forum-quiet-check','mark-quiet-forums');` → `0`.
- `succeeded` on an `invoke_edge_function` job means only that the HTTP call was queued. Check the answers with the `net._http_response` query from step 3.

**If a job fails:**
- Read `return_message`.
  - A missing Vault `supabase_url` or `service_role_key` makes every `invoke_edge_function` job raise.
  - A missing function gives a 404 in `net._http_response`.
- Fix the cause; the job retries on its schedule.
- To stop one job: `select cron.unschedule('<jobname>');`. Re-create it with the exact command above via `cron.schedule('<jobname>', '<schedule>', $c$<command>$c$)`.

---

## 5. The IP country table (S2 W8b, R-74)

- **What:** builds `supabase/functions/dating-device-check/ip_country.bin` from DB-IP's "IP to Country Lite" (CC BY 4.0), then deploys `dating-device-check`. `config.toml`'s `static_files` line ships the table. The file is git-ignored.
- **Commands** (from the repo root; the CSV goes in a folder outside the repo):
  ```bash
  mkdir -p "$HOME/attune-deploy-tmp"
  DBIP_MONTH="$(date -u +%Y-%m)"    # early in a month, before the file is out: last month, e.g. DBIP_MONTH=2026-10
  curl -sSfL -o "$HOME/attune-deploy-tmp/dbip.csv.gz" "https://download.db-ip.com/free/dbip-country-lite-$DBIP_MONTH.csv.gz"
  gunzip -f "$HOME/attune-deploy-tmp/dbip.csv.gz"
  deno run --allow-read --allow-write scripts/ip_country/build_ip_country.ts \
    "$HOME/attune-deploy-tmp/dbip.csv" supabase/functions/dating-device-check/ip_country.bin
  wc -c supabase/functions/dating-device-check/ip_country.bin
  supabase functions deploy dating-device-check --project-ref "$SUPABASE_PROJECT_REF"
  ```
- **Verify:**
  - The builder prints `… N IPv4 and M IPv6 ranges, C claimed by two countries, B bytes`. On this first build, C should be 0 or small; note it.
  - The bin is about 4–6 MB. The whole bundle must stay at or under **20 MB**: read the size in the deploy output.
  - Dashboard → Edge Functions → `dating-device-check` → Logs shows neither `ip_table_unavailable` nor `ip_table_stale` after a call. In Logs Explorer: `select timestamp, event_message from function_logs where event_message like '%ip_table_%' order by timestamp desc limit 20` → no rows.
  - After a tester opens Dating (step 9): `select count(*) filter (where ip_resolved) as resolved, count(*) from public.dating_session_context where checked_at > now() - interval '1 hour';` → `resolved` > 0.
- **If it fails:**
  - **No CSV for this month yet** (early in the month): re-run step 5 with `DBIP_MONTH=YYYY-MM` set to last month.
  - **Deploy rejects the size:** stop and tell the developer.
  - **No table at all:** every IP is unresolved and the phone's country decides. That is safe, so the demo still works.
  - **Monthly:** rebuild and redeploy. A table over 60 days old logs `ip_table_stale`.

---

## 6. Moderation console hosting (S2 W7b/W10)

- **Build** (the CI line plus the two values; `SUPABASE_ANON_KEY` is the publishable key):
  ```bash
  flutter build web -t lib/console/main_console.dart -o build/console --pwa-strategy=none --no-web-resources-cdn \
    --dart-define=SUPABASE_URL="https://$SUPABASE_PROJECT_REF.supabase.co" \
    --dart-define=SUPABASE_ANON_KEY="$ATTUNE_ANON_KEY"
  ```
  The script asks for the key with a hidden prompt when `ATTUNE_ANON_KEY` is unset. CI pins Flutter 3.29.1. Use the same version if the build differs.
- **Host:**
  - Host `build/console/` as a **private** static site behind an access gate (Cloudflare Access or equivalent), on managed devices only.
  - Send `X-Robots-Tag: noindex` (and add `<meta name="robots" content="noindex">` if your host can't send the header).
  - Send `Referrer-Policy: no-referrer` and `X-Frame-Options: DENY`.
  - The repo defines **no CSP**. A starting header to test, then tighten using the browser console's report:
    `default-src 'self'; script-src 'self' 'wasm-unsafe-eval'; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:; font-src 'self' data:; connect-src 'self' https://<project-ref>.supabase.co wss://<project-ref>.supabase.co; frame-ancestors 'none'; base-uri 'none'; form-action 'none'`
    CanvasKit needs `'wasm-unsafe-eval'`. If a font fallback from `fonts.gstatic.com` is refused, add that host to `font-src` and `connect-src`, or bundle the font.
- **Origin:**
  - The script asks for the site's exact origin here (`https://host[:port]`, no path, no trailing slash; for example `https://console.example.com`). It sets `DATING_CONSOLE_ORIGIN` through a 600 env file.
  - Then it deploys `dating-moderation` (step 3, row 23), after you confirm TOTP MFA is on.
- **Verify:**
  - CORS preflight:
    ```bash
    curl -s -D - -o /dev/null -X OPTIONS -H "Origin: https://<console-origin>" -H 'Access-Control-Request-Method: POST' \
      "https://$SUPABASE_PROJECT_REF.supabase.co/functions/v1/dating-moderation"
    ```
    → an `Access-Control-Allow-Origin: https://<console-origin>` header. Any other origin gets none.
  - In the browser: sign in with an Attune phone account, enrol TOTP, then:
    - the rail shows Launch readiness, Metrics and Fairness after Audit;
    - Launch readiness shows the development note ("This project is in development mode… that is expected").
- **If it fails:**
  - **No CORS header:** the origin secret doesn't match exactly (scheme, host, port, no slash).
  - **"not a moderator":** step 7.
  - **Rollback:** take the site down, or `supabase secrets unset DATING_CONSOLE_ORIGIN --project-ref "$SUPABASE_PROJECT_REF"`. With no origin set, no browser can call the function.

---

## 7. Safety-owner and moderator rows, MFA and the Auth hooks

### 7.1 Two accounts, two rows
- **What:** the console and the SLA sentence need an active `safety_owner` and an active `moderator`. `dating_moderators.user_id` is the primary key, so one account can't hold both roles: use two Attune accounts, each signed up in the app (a `public.users` row).
- **Command** (SQL editor):
  ```sql
  insert into public.dating_moderators (user_id, role, sensitive_routing_allowed, languages)
  values ('<safety owner users.id>', 'safety_owner', true,  '{en}'),
         ('<moderator users.id>',    'moderator',    false, '{en,tw,gaa,pcm}')
  on conflict (user_id) do update
    set role = excluded.role, sensitive_routing_allowed = excluded.sensitive_routing_allowed,
        languages = excluded.languages, active = true;
  ```
  `languages` is free text. Twi, Ga and Pidgin are a human gate for production, not checked by code.
- **Verify:**
  - `select role, active, sensitive_routing_allowed, languages from public.dating_moderators order by role;` → one active `moderator` and one active `safety_owner`.
  - In `select public.get_dating_launch_readiness();` the `safety_owner` and `moderator` gates read green. The rest stays red in development, as expected.
- **To cut someone off at once:** `update public.dating_moderators set active = false where user_id = '<id>';`. A session lives about an hour after TOTP removal.

### 7.2 MFA (TOTP)
- Dashboard → Authentication → Multi-Factor: **TOTP enrol and verify enabled**. `config.toml` has no `[auth.mfa]` block, so nothing in the repo sets it.
- Both moderator accounts enrol at their first console sign-in. The function refuses anything below `aal2`.

### 7.3 JWT expiry (S1 W6 item 3)
- Dashboard → Authentication → Settings → JWT expiry ≤ `3600` seconds. "A held account's sessions stop within the hour" depends on it.

### 7.4 Auth hooks (optional for the demo; dashboard only, never `supabase config push`)
- **Custom Access Token hook (S1 W6 item 4).** This is what enforces holds and dormancy.
  1. Just before enabling, re-run the activity seed:
     ```sql
     INSERT INTO public.account_activity AS a (user_id, last_active_at)
     SELECT u.id, greatest(u.created_at, au.last_sign_in_at, au.updated_at,
            (SELECT max(greatest(s.updated_at, s.refreshed_at AT TIME ZONE 'utc')) FROM auth.sessions AS s WHERE s.user_id = u.id))
       FROM public.users AS u LEFT JOIN auth.users AS au ON au.id = u.id
     ON CONFLICT (user_id) DO UPDATE SET last_active_at = greatest(a.last_active_at, EXCLUDED.last_active_at);
     ```
  2. Authentication → Hooks → Custom Access Token → Postgres function `public.attune_access_token_hook`.
  3. **Verify:** sign in on a phone, then `select public.identity_alerts_due();` → `count` 0. Run W6 checks 1–3 with a test account (H1 for `safety_review`, DM1 for an account idle more than 200 days).
  4. **If sign-ins fail:** disable the hook in the dashboard. Rollback is instant.
- **Send SMS hook (S1 W2 item 6).** Only after the SMS provider secrets are set; otherwise every sign-in fails with "We couldn't send a code".
  1. Authentication → Hooks → Send SMS → HTTPS → `https://<project-ref>.supabase.co/functions/v1/send-sms-hook`.
  2. Generate the hook secret and set it as `SEND_SMS_HOOK_SECRET`.
  3. **Verify:** one sign-in logs `hook:sms:<provider>:sent`.
  4. Without the hook, WhatsApp choices arrive by SMS, which is fine for demos.

---

## 8. Switching every flag on for demos

### 8.1 STOP: verification mode for demos (decision)
- `sandbox` (the dev script's default) needs vendor sandbox credentials **and** the real capture SDK, which isn't built yet (S2 W4 R-9/R-10). So nobody could pass D11.
- **Recommended: `fake`.**
  - It runs only in development, on the dev ref.
  - The app offers the practice capture only in **debug or profile** builds.
  - At launch, W10 step 9 sets `live`, and step 10 revokes every pre-launch verification.
- **Command, before 8.3** (`fake` is not a secret; the dev script keeps an existing value):
  ```sql
  select vault.create_secret('fake', 'age_assurance_mode', 'demo: fake verification on the development project');
  -- if it already exists:
  select vault.update_secret((select id from vault.secrets where name = 'age_assurance_mode'), 'fake');
  ```
- **Verify:** `select public.app_setting('age_assurance_mode');` → `fake`.

### 8.2 Spec 1 flags, then the draft filter terms
```bash
psql "$ATTUNE_DB_URL" -X -v ON_ERROR_STOP=1 -f supabase/sql/dev_enable_spec1_flags.sql
psql "$ATTUNE_DB_URL" -X -v ON_ERROR_STOP=1 -f supabase/sql/load_content_filter_terms.sql
```
- Both refuse with `env:not_development` anywhere else, and turn nothing on when they refuse.
- Check: `select family, count(*) from private.content_filter_terms where source = 'draft' group by 1;` → `explicit 5`, `slur 4`.
- This turns on `flow_signin_v2`, so invites now need a birth date: see "Testers, read first".

### 8.3 Spec 2 Dating and traveller flags
```bash
psql "$ATTUNE_DB_URL" -X -v ON_ERROR_STOP=1 -f supabase/sql/dev_enable_spec2_dating_flags.sql
```
- **What it does:**
  - turns on the 8 Dating flags and `support_resources_v2`;
  - activates `introductions_v2` and `dating_chat_v1` with `DEV-` references;
  - sets `age_assurance_mode` only if none is set;
  - opens GH and GB.
- **It is one statement.** If it errors, nothing changed.
- **It must print no WARNING.** A WARNING means its flags **are** on but a key is missing: fix the key (step 1) and re-run.
- **Verify:** `select public.get_public_app_config() -> 'config' -> 'dating_open_countries';` → `["GB", "GH"]`.
- **Re-run it after any migration replay**, then repeat 8.5.

### 8.4 Spec 5, 7, 8 (the scripts you already use)
```bash
psql "$ATTUNE_DB_URL" -X -v ON_ERROR_STOP=1 -f supabase/sql/dev_enable_spec5_flags.sql
psql "$ATTUNE_DB_URL" -X -v ON_ERROR_STOP=1 -f supabase/sql/dev_enable_spec7_flags.sql
psql "$ATTUNE_DB_URL" -X -v ON_ERROR_STOP=1 -f supabase/sql/dev_enable_spec8_flags.sql
```
These three have no development guard. They run after Spec 1's, which stops first on any other project.

### 8.5 Hold generation until the demo profiles exist (review I-4)
- **Why:** the first `:17` tick after `dating_candidate_generation` goes on runs today's cohort in full. Testers haven't finished D1–D13 by then, so the partition is marked done with nobody in it. Later ticks only retry pending or failed partitions, so the demo profiles would get nothing until 03:17 UTC the next day.
- **Command** (right after 8.3; a tick then skips with `flag_disabled` and claims nothing):
  ```sql
  update public.feature_flags set enabled = false, updated_at = now() where key = 'dating_candidate_generation';
  ```
- **Next:** step 9.1 turns it back on once both demo enrolments are active.

### 8.6 STOP: `opinions_safety_v1` for testers (review I-7)
- **What it does:**
  - With it on, every Opinions post and comment, from any build, is checked server-side against the unreviewed `[DRAFT]` term list (`load_content_filter_terms.sql`) and the contact-detail rule.
  - Refusals reach the store build as a generic error.
  - Confirmed removals count toward the real 7-day ban.
- **Default: keep it on** (only testers use this project). The script asks [Y/n]. On "no", it runs `update public.feature_flags set enabled = false, updated_at = now() where key = 'opinions_safety_v1';` and expects one flag fewer.

### 8.7 Verify the count
```sql
select count(*) filter (where enabled) as enabled_total,
       count(*) filter (where enabled and key = any (array['flow_signin_v2','flow_paths_v2','flow_couples_v2','couple_profile',
         'dormancy_rule','platform_age_signals','support_resources_v2','csam_hash_matching','opinions_safety_v1',
         'journal_ai_insights','healing_ai_insights','text_scale_v2','dating_mode_enabled','dating_candidate_generation',
         'dating_match_messaging','dating_profile_photos','dating_same_gender_matching','dating_age_assurance',
         'dating_traveller_detection','dating_couple_link','quiz_clinical_signoff','couple_map_enabled',
         'appreciation_notes','share_a_win','quiet_states','private_safety_check','conflict_toolkit'])) as demo_on
  from public.feature_flags;
```
- **Expected now:**
  - `demo_on = 26` (generation is held); 25 if you turned `opinions_safety_v1` off.
  - `enabled_total = demo_on + N`, with N from 0.7a (which leaves out `dating_alignment_algorithm_v1`, deleted by `20261119100000`).
  - After 9.1, `demo_on = 27` (or 26).
- **Should stay off** unless you turned them on before: `chat_hostility_signals_enabled` and `ai_together_enabled`.
- `select * from public.production_flag_violations();` lists the gated flags without evidence. That is expected in development.

### 8.8 The app builds
- Every tester installs the W10 build now. Use **debug or profile** for Dating demos.
- Add `"FLOW_V2_DEFAULT": true` to the development `.env.json` (S1 W1 item 4). This plan didn't open `.env*`.

---

## 9. Introductions, then smoke checks (two phones, test accounts only)

### 9.1 Generation on, once both demo enrolments are active
- **Check:** `select count(*) from public.dating_enrollments where state = 'active';` → at least `2`. Both accounts need D1–D13 done, the fake D11, and the same open country (GH or GB).
- **Then, once:**
  ```sql
  update public.feature_flags set enabled = true, updated_at = now() where key = 'dating_candidate_generation';
  select public.run_dating_generation_tick();
  select count(*) as intros_today from public.dating_introductions where created_at > now() - interval '1 hour';
  ```
- **Expected:** the tick's answer lists the GB/GH partitions it ran, and the introductions show in Today on both phones.
- Forcing a tick only works while today's partition hasn't run yet. If one already ran (for example generation was left on through a `:17`), the profiles join at the next 03:17 UTC run.
- The script's `--from 9` does exactly this, after asking.

### 9.2 Smoke checks

| Area | Do | Expect |
|---|---|---|
| Sign-in | A new number on a fresh install of the new build: Welcome → A1–A5 (DOB, code by built-in SMS) → A6 path | Home for the chosen path. For an under-18 DOB: X1, and nothing written. `select public.get_identity_health();` shows no new failures. |
| Couples invite | R1 → share → second phone opens the link signed out → RI-3 "Join {name}?" | Both phones: "Welcome, {couple}" (or "Couples"), then Chat. Both accounts need a birth date (A2). |
| Dating setup | Me → Dating → D1–D13 with 2 photos (debug build, fake capture at D11) | Photos "Checking…" then "Ready". `select moderation_state, csam_state, count(*) from public.dating_profile_photos group by 1,2;` → `approved | clear`. `select state, count(*) from public.dating_enrollments group by 1;` → `active`. |
| Today | 9.1 | Introductions on both phones. |
| Dating chat | Match, send messages both ways, wait an hour (token refresh) | Live arrival. Masked until both swap (never before 72 h). A seeded money ask shows a safety card within a minute. `select public.get_dating_operational_health() -> 'chat_safety_outbox';` has no dead letters. |
| Report | Report from the chat's Safety sheet | The case appears in the console queue. A P0 ends the chat for both. An SLA line goes to `moderation_alert_webhook` (if set) with no name or id. |
| Console | Claim, note and decide one case; Ask for ID → the code in the app → Lift age check | Every action shows in Audit. The ID-check case has only its four actions. |
| CSAM stub | Upload `supabase/functions/scan-media/testdata/stub-match.gif` to `message-media` under a test folder (Storage dashboard) | Within 2 min: `match | stub` in `private.media_scan_queue`, and a `csam_match | t | open` escalation. Then clean up the test rows (S1 W7 item 5). |
| Couple link | Both: We met → Become a couple on Attune → Yes, let's | Both land on the Relationship home. About us shows "The day you matched" and How we met. The asker sees "You decided together." |
| Export | Settings → Download my data (an account that used Dating) | `dating.json` with only your own messages and the `about` line. A non-Dating account gets none. |
| Traveller | Open Dating on a VPN or abroad | `dating_session_context.ip_resolved` is true (step 5 query). The away note shows. |
| Plain icon | Settings → App settings → App icon → plain | The launcher icon changes. **Android:** a home-screen shortcut may drop once on the alias update (device check 21). |
| Storage header (W4 item 6) | Open a match's photos | Photos load. If they don't, tell the developer (signed URLs). |
| Opinions (if kept on) | Post "call me on 0 2 4 4 1 2 3 4 5 6" on the new build | Refused with the contact reason. "We met in 2015" posts fine. |

## 10. Do NOT do these (yet)

- **Don't let anyone but testers use the current store build on this project** until the W10 build is in the stores (see "Testers, read first").
- **Never set production mode:** no `vault.create_secret('production', 'attune_environment')` and no `ALTER DATABASE … SET app.settings.attune_environment`. Production mode waits for the W10 launch checklist (`lib/architecture/DATING_MODE_RELEASE_READINESS_CHECKLIST.md` §3).
- **No dashboard Database Webhooks** on `relationships`, `users`, the couple tables (`couple_profiles`, `couple_how_we_met`, `together_change_signals`, `relationship_invite_acceptances`) or any Dating table.
- **The Vault keys:**
  - Never rotate, replace or delete `dating_exclusion_key` or `dating_field_key`.
  - Never delete their fingerprint rows.
- **The flags:**
  - Never turn the Dating flags off with `where key like 'dating%'`. Switching `dating_same_gender_matching` off runs the same-gender purge through its trigger. To stop Dating, turn off `dating_mode_enabled` alone.
  - Don't run the kill switch through the API or the Table Editor (statement timeouts). Use the SQL editor only.
- **The CLI:**
  - No `supabase functions deploy` without names, and none from a tree with uncommitted changes.
  - Don't rely on `supabase link` for this deploy: every database command uses `--db-url "$ATTUNE_DB_URL"`.
  - No `--prune`, no `supabase config push` (it doesn't carry the hooks), no `db reset`.
  - No `db push --include-all` without knowing why.
- **Not until later waves:**
  - Don't set `CSAM_MATCHER=stub` on any future production project.
  - Don't set `DATING_PHOTO_VISION=stub` on any future production project; unset it here once `GOOGLE_VISION_API_KEY` exists.
  - Don't enable the Send SMS hook before the provider secrets are set.
  - Don't switch on the invite page's Play referrer before W4b is live on Play.
  - Don't revoke the direct opinions writes before the W9 client is the minimum build.
- **Not on a real-user project** without the gateway log check (W8 M-4): don't turn on `dating_traveller_detection` there.
- **Don't release a public Android build** before device check 21 is recorded.

---

## 11. Rollback notes

| Step | How to undo or stop safely |
|---|---|
| 0 | Read-only, except the optional dumps. Nothing to undo. |
| 1 Vault | Delete a **not yet used** key: `delete from vault.secrets where name = '<name>';`. Once the push has run, never delete `dating_exclusion_key`, `dating_field_key` or their fingerprints. A key that may have leaked (a log, a history file) is an incident, not a rotation (S2 W1 item 11). |
| 1 Edge secrets | `supabase secrets unset NAME --project-ref "$SUPABASE_PROJECT_REF"` |
| 2 Migrations | There are no down migrations. **Forward-fix** with a new migration, or restore the 0.3 backup / PITR point (this loses data written since). A push that stopped mid-way: re-run it (fail-closed twins). Restoring also needs every function redeployed from the old commit (`git worktree add <dir> ed7bfddd`). |
| 2.5 Purge | Re-arm only once the 0.11 probe reads 0: `select cron.schedule('purge-unfinished-signups', '41 * * * *', $cron$SELECT public.invoke_edge_function('purge-unfinished-signups')$cron$);`, then deploy the function. |
| 2.6 Catalogue | Re-load an earlier JSON (all or nothing). |
| 3 Functions | Redeploy the previous source from a worktree at `ed7bfddd` for a changed function, or `supabase functions delete <new function>`. Deleted v1 functions (`upload-dating-photo`, `verify-dating-profile`) can't come back against the new schema: don't. |
| 4 Crons | `select cron.unschedule('<job>');`. Re-create with the exact command from the table. |
| 5 IP table | Redeploy without the bin. IPs then read unresolved (safe). |
| 6 Console | Take the site down, or unset `DATING_CONSOLE_ORIGIN`. |
| 7 Moderators / hooks | `update public.dating_moderators set active = false …`. Disable a hook in the dashboard (instant). |
| 8 Flags | `update public.feature_flags set enabled = false where key = '<key>';` one at a time. `dating_candidate_generation` off stops new introductions. For Dating, turn `dating_mode_enabled` off first: that alone stops sends and swap offers. Close a country from the console (Countries → Publish `{"dating_enabled": false}`). Re-set `age_assurance_mode` with `vault.update_secret`. |
| 9 | Exit or delete the test accounts afterwards (W10 launch step 6 needs this anyway). |

---

## Sources

- **Memory:** `hosted_deploy_plan.md`, every `spec1_w*_status.md`, `spec2_w*_status.md` and `spec2_w9_w10_status.md`.
- **Plans' owner checklists:** `docs/superpowers/plans/2026-10-25-spec1-w1-identity.md` … `2026-11-24-spec2-w10-launch-guards.md`, `2026-10-25-spec3-forum-removal-w1-w2.md` and `2026-11-24-spec3-w3-forum-drop.md` (with `.superpowers/sdd/2026-11-24-spec3-w3-forum-drop/w3-owner-list.md`).
- **Ledgers:**
  - `.superpowers/sdd/2026-11-07-spec2-w3-setup-ui/final-server-review.md`
  - `…-spec2-w4-verification/final-server-review.md`
  - `…-spec2-w5-matching/final-server-review.md` and `final-server-fix-report.md`
  - `…-spec2-w6-chat/final-server-fix-report.md`
  - `…-spec2-w7-moderation/final-server-review.md` and `final-server-fix-report.md`
  - `…-spec2-w8-device/w8-owner-list.md` and `final-server-fix-report.md`
  - `…-spec2-w9-couple-link/w9-owner-list.md`
  - `…-spec2-w10-launch-guards/w10-owner-list.md`
- **Repo:**
  - `supabase/config.toml` (verify_jwt)
  - `supabase/sql/dev_enable_spec{1,2_dating,5,7,8}_flags.sql`, `load_content_filter_terms.sql`
  - `scripts/ip_country/build_ip_country.ts`
  - `.github/workflows/tests.yml` (`console-web`)
  - `lib/architecture/DATING_MODE_RELEASE_READINESS_CHECKLIST.md`

---

## Appendix A: the 127 migrations, in push order

**Spec 3 W2 forum retirement (crons off, client access revoked, queued pushes cancelled, health). NOT the table drop** (4 files)

1. `20261025090000_forum_retire_scheduled_jobs.sql`
2. `20261025090100_forum_revoke_client_access.sql`
3. `20261025090200_forum_cancel_queued_pushes.sql`
4. `20261025090300_forum_retirement_health.sql`

**Spec 1 W1 identity foundation** (13 files)

5. `20261025100000_identity_users_lockdown.sql`
6. `20261025100010_identity_users_lockdown_grants.sql`
7. `20261025100020_onboarding_profiles_mode_optional.sql`
8. `20261025100100_metric_counters.sql`
9. `20261025100110_metric_counters_grants.sql`
10. `20261025100200_account_birthdates_and_holds.sql`
11. `20261025100210_account_birthdates_and_holds_grants.sql`
12. `20261025100300_paths_and_home_state.sql`
13. `20261025100310_paths_and_home_state_grants.sql`
14. `20261025100400_spec1_flags_and_public_config.sql`
15. `20261025100410_spec1_flags_and_public_config_grants.sql`
16. `20261025100500_identity_health.sql`
17. `20261025100510_identity_health_grants.sql`

**Spec 1 W2 sign-in (OTP delivery)** (2 files)

18. `20261025110000_otp_delivery.sql`
19. `20261025110010_otp_delivery_grants.sql`

**Spec 1 W3 journal reminders** (2 files)

20. `20261026100000_journal_reminders.sql`
21. `20261026100010_journal_reminders_grants.sql`

**Spec 1 W4 invites v2** (2 files)

22. `20261102100000_accept_invite_v2.sql`
23. `20261102100010_accept_invite_v2_grants.sql`

**Spec 1 W5 About us** (4 files)

24. `20261102110000_couple_profiles.sql`
25. `20261102110010_couple_profiles_grants.sql`
26. `20261102110100_couple_profiles_links.sql`
27. `20261102110110_couple_profiles_links_grants.sql`

**Spec 1 W6 holds, hook, fresh start, DOB, child safety** (10 files)

28. `20261103100000_holds_enforced.sql`
29. `20261103100010_holds_enforced_grants.sql`
30. `20261103100100_access_token_hook.sql`
31. `20261103100110_access_token_hook_grants.sql`
32. `20261103100200_fresh_start.sql`
33. `20261103100210_fresh_start_grants.sql`
34. `20261103110000_birth_date_correction.sql`
35. `20261103110010_birth_date_correction_grants.sql`
36. `20261103120000_child_safety_reports.sql`
37. `20261103120010_child_safety_reports_grants.sql`

**Spec 1 W7 support resources v2 + media scan (CSAM)** (6 files)

38. `20261103130000_support_resources_v2.sql`
39. `20261103130010_support_resources_v2_grants.sql`
40. `20261103140000_media_scan.sql`
41. `20261103140010_media_scan_grants.sql`
42. `20261103140100_media_scan_enqueue.sql`
43. `20261103140110_media_scan_enqueue_grants.sql`

**Spec 1 W9 Opinions safety** (8 files)

44. `20261104100000_opinion_content_filter.sql`
45. `20261104100010_opinion_content_filter_grants.sql`
46. `20261104110000_opinion_at_risk_and_review_queue.sql`
47. `20261104110010_opinion_at_risk_and_review_queue_grants.sql`
48. `20261104120000_opinion_moderation_notices.sql`
49. `20261104120010_opinion_moderation_notices_grants.sql`
50. `20261104130000_opinion_remove_own.sql`
51. `20261104130010_opinion_remove_own_grants.sql`

**Spec 1 W9e Healing AI pause** (2 files)

52. `20261104140000_healing_ai_insights_flag.sql`
53. `20261104140010_healing_ai_insights_flag_grants.sql`

**Spec 2 W1 Dating foundation** (22 files)

54. `20261106100000_dating_v2_phone_hmac.sql`
55. `20261106100010_dating_v2_phone_hmac_grants.sql`
56. `20261106110000_dating_v2_enforcement_survival.sql`
57. `20261106110010_dating_v2_enforcement_survival_grants.sql`
58. `20261106120000_dating_v2_account_deletion.sql`
59. `20261106120010_dating_v2_account_deletion_grants.sql`
60. `20261106130000_dating_v2_country_config.sql`
61. `20261106130010_dating_v2_country_config_grants.sql`
62. `20261106140000_dating_v2_eligibility_base.sql`
63. `20261106140010_dating_v2_eligibility_base_grants.sql`
64. `20261106150000_dating_v2_profile_fields.sql`
65. `20261106150010_dating_v2_profile_fields_grants.sql`
66. `20261106160000_dating_v2_setup_writers.sql`
67. `20261106160010_dating_v2_setup_writers_grants.sql`
68. `20261106170000_dating_v2_profile_readers.sql`
69. `20261106170010_dating_v2_profile_readers_grants.sql`
70. `20261106180000_dating_v2_never_introduce.sql`
71. `20261106180010_dating_v2_never_introduce_grants.sql`
72. `20261106190000_dating_v2_lifecycle.sql`
73. `20261106190010_dating_v2_lifecycle_grants.sql`
74. `20261106200000_dating_v2_kill_switch.sql`
75. `20261106200010_dating_v2_kill_switch_grants.sql`

**Spec 1 W9d Opinions enforcement records** (4 files)

76. `20261107100000_opinion_enforcement_records.sql`
77. `20261107100010_opinion_enforcement_records_grants.sql`
78. `20261107110000_opinion_enforcement_restore.sql`
79. `20261107110010_opinion_enforcement_restore_grants.sql`

**Spec 2 W2 gentle wait** (6 files)

80. `20261107120000_dating_v2_gentle_wait.sql`
81. `20261107120010_dating_v2_gentle_wait_grants.sql`
82. `20261107130000_dating_v2_path_pause.sql`
83. `20261107130010_dating_v2_path_pause_grants.sql`
84. `20261107140000_dating_v2_home.sql`
85. `20261107140010_dating_v2_home_grants.sql`

**Spec 2 W3 setup UI + photos** (6 files)

86. `20261107150000_dating_v2_client_reads.sql`
87. `20261107150010_dating_v2_client_reads_grants.sql`
88. `20261107160000_dating_v2_setup_lists.sql`
89. `20261107160010_dating_v2_setup_lists_grants.sql`
90. `20261107170000_dating_v2_photos.sql`
91. `20261107170010_dating_v2_photos_grants.sql`

**Spec 2 W4 verification** (4 files)

92. `20261109100000_dating_v2_age_assurance.sql`
93. `20261109100010_dating_v2_age_assurance_grants.sql`
94. `20261109110000_dating_v2_trusted_devices.sql`
95. `20261109110010_dating_v2_trusted_devices_grants.sql`

**Spec 2 W5 matching** (8 files)

96. `20261119100000_dating_v2_matching.sql`
97. `20261119100010_dating_v2_matching_grants.sql`
98. `20261119110000_dating_v2_today.sql`
99. `20261119110010_dating_v2_today_grants.sql`
100. `20261119115000_dating_v2_block.sql`
101. `20261119115010_dating_v2_block_grants.sql`
102. `20261119120000_dating_v2_signals.sql`
103. `20261119120010_dating_v2_signals_grants.sql`

**Spec 2 W6 chat** (6 files)

104. `20261120100000_dating_v2_chat.sql`
105. `20261120100010_dating_v2_chat_grants.sql`
106. `20261120110000_dating_v2_chat_safety.sql`
107. `20261120110010_dating_v2_chat_safety_grants.sql`
108. `20261120120000_dating_v2_chat_guided.sql`
109. `20261120120010_dating_v2_chat_guided_grants.sql`

**Spec 2 W7 moderation** (6 files)

110. `20261121100000_dating_v2_reports.sql`
111. `20261121100010_dating_v2_reports_grants.sql`
112. `20261121110000_dating_v2_moderation_console.sql`
113. `20261121110010_dating_v2_moderation_console_grants.sql`
114. `20261121120000_dating_v2_escalations.sql`
115. `20261121120010_dating_v2_escalations_grants.sql`

**Spec 2 W8 traveller** (2 files)

116. `20261122100000_dating_v2_traveller.sql`
117. `20261122100010_dating_v2_traveller_grants.sql`

**Spec 2 W9 couple link** (2 files)

118. `20261123100000_dating_v2_couple_link.sql`
119. `20261123100010_dating_v2_couple_link_grants.sql`

**Spec 2 W10 launch guards** (2 files)

120. `20261124100000_dating_v2_launch_guards.sql`
121. `20261124100010_dating_v2_launch_guards_grants.sql`

**Spec 3 W3 forum drop (irreversible; preflight first, then the views, functions, tables, kept columns, shared branches and health v2)** (6 files)

122. `20261125100000_forum_drop_views.sql`
123. `20261125100010_forum_drop_functions.sql`
124. `20261125100020_forum_drop_tables.sql`
125. `20261125100030_forum_kept_table_columns.sql`
126. `20261125100040_forum_shared_function_branches.sql`
127. `20261125100050_forum_retirement_health_v2.sql`


Twin pairs: 58 (`<v>_<name>.sql` + `<v+10>_<name>_grants.sql`). Singles: the four forum files, `20261025100020_onboarding_profiles_mode_optional.sql` and the six Spec 3 W3 files.

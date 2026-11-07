# Spec 2 W1 (Dating data, identity, deletion, configuration, encryption) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build Spec 2's W1 server foundation for Dating Mode, all of it off in production: phone HMACs from `auth.users` with parked accounts, enforcement records and block pairs that survive deletion, `prepare_account_deletion`'s Dating carry-over and the CI canaries (W1a); the versioned country model, the session context, the base `dating_eligibility` and Spec 1's two re-created seams (W1b); field encryption, the v2 profile fields and every setup writer and own-profile reader (W1c); never-introduce, lifecycle v2 (pause, resume, exit's hard delete, readiness, the parked pause, the generation key guard, health v2) and the same-gender kill switch (W1d).

**Architecture:** Four sub-waves, thirteen tasks, eleven migrations (each with its `…10` grants twin), no app change. **W1a (Tasks 1-4).** Task 1 records the baselines and the "before" bodies, writes the two plan helpers and creates the dev script. Task 2 is migration 1 (`dating_phone_canonical`, `dating_phone_hmac_for_user`, the exclusion recorder/predicate/backfill from their live bodies, the guard trigger rewired). Task 3 is migration 2 (`enforcement_records`, `dating_block_hmacs`, reports and matches that survive deletion, `block_dating_user` and standing from their live bodies) and a grants twin that re-asserts every Dating table's and function's client grants, with the RLS canary, the bucket test and the CI secret scan. Task 4 is migration 3 (`prepare_account_deletion` from its live body with the carry-over; the `dating.` metric prefix) and the DPIA draft. **W1b (Tasks 5-7).** Task 5 is migration 4 (`country_safety_config` and its seeds, all closed; `publish_country_config`; `get_dating_availability`; the session context; `dating_notify_requests`; `dating_same_gender_matching`; gate rows for every Dating flag; Spec 1's open-country seam over the table). Task 6 is migration 5 (`dating_eligibility` gates 1-4 and 6; Spec 1's home-summary seam). Task 7 opens GH and GB from the dev script, proves its production refusal (mutant 25) and adds the CI `attune_environment` guard. **W1c (Tasks 8-10).** Task 8 is migration 6 (fields, `dating_profile_sensitive`, prompts, settings, the field-key functions, the trusted-device pass-through). Task 9 is migration 7 (the D2-D8 writers, mutants 4 and 7). Task 10 is migration 8 (D10, D12, settings, other countries, photos after mutual, `get_my_dating_profile`, `get_dating_profile_preview`). **W1d (Tasks 11-13).** Task 11 is migration 9 (never-introduce). Task 12 is migration 10 (lifecycle v2; mutants 5, 17, 30). Task 13 is migration 11 (`apply_same_gender_switch`, `publish_country_config` from its live body with it, the global-flag trigger). Every SQL block below was run while writing this plan on a scratch Postgres 17 cluster restored from `attune_spec3a`'s dump, task by task in this order: each contract red before its migration with the message quoted, each migration and twin applied twice (`exit=0` both times), each re-created function diffed against `pg_get_functiondef` (only the lines marked `Spec 2 W1x` differ), each contract green after, every mutant red with the message quoted (the database unchanged afterwards), and the whole contract suite with no new FAIL at the four sub-wave gates.

**Tech Stack:** Supabase Postgres 17 (RLS; `SECURITY DEFINER` with `SET search_path = ''`; pgcrypto in `extensions`; Vault through `public.app_setting`; pg_cron untouched), Supabase CLI 2.75, psql, Python 3 (edit, section and mutation scripts), GitHub Actions (gitleaks 8.18.4). Flutter 3.29.1 / Riverpod 2.6 / GoRouter and Deno 2 are not touched by W1. No new package.

**Spec:** `docs/superpowers/specs/2026-10-24-dating-mode-design.md` — header (Spec 1 dependencies, repo rules, environment), §1.3 (Q1, Q2, Q4, Q5, Q12-Q17 with the three Q17 exceptions, Q19, Q19b), §1.4, §2.1 (gates 1-4, 6; I-14), §2.2 (country model, writers, seeds, public config), §2.3 (effective tier, session context), §2.4 (same-gender rules, kill switch), §2.7, §3.2 D2-D13 storage rows, §3.8, §3.12, §4.1-§4.5, §4.8, §4.9 W1a-W1d, §4.10 (every W1 row), §5.2 filter 13, §6.3 (deletion and carry-over, parked accounts), §6.8 (DPIA), §6.9 (`dating.` keys), §7.1 (`dating_rls_canary`, `storage_bucket_policies`, `dating_v2_identity_contracts`, `country_safety_config_contracts`, `dating_v2_eligibility_contracts` base rows, `dating_exclusion_wiring_test`), §7.5 (mutants 1, 5, 16, 17, 25, 27, 30; 4 and 7 move here, P-26), §8 W1 and its gate, §9 (R5, R6, R10, R18, R19, R22), §10 items 2, 8, 9, 10, §11, owner approval (O3: no). `docs/superpowers/specs/2026-10-24-cross-spec-review.md` (I-3, I-11, I-14, A-10, S-2, S-4, S-5, R-2, R-6, W-2, W-3 and its controller rulings). `docs/superpowers/research/2026-10-24-flow-dating-research/11-synthesis-decisions.md` §12 (Q1, Q2, Q13, Q19, Q19b; Q4, Q5, Q12, Q14-Q17 accepted) and §4.8.5; research 04 §2.1.6 (the tier list); Spec 1 (`docs/superpowers/specs/2026-10-24-app-flow-identity-design.md`) D15, D18, D20 and the S1 objects named in "Interfaces consumed". Format reference: `docs/superpowers/plans/2026-11-04-spec1-w9-opinions-safety.md`.

## Global Constraints

- Work in the main working tree on `main` (`/Users/user/attune`). Spec 1 is complete and committed (HEAD `c6bc8e16`); the owner may have uncommitted edits (`supabase/.temp/cli-latest`, `backup-before-planning-p2.sql` at the time of writing): never revert, stash, stage, checkout or reformat them. Every edit to an existing file is an exact replacement made by a script that asserts each anchor occurs once; if an anchor has moved because a later fix changed it, apply the same change to the current text and say so in the task report.
- **NO commits.** No `git add`, `git commit`, `git stash`, `git checkout`, `git reset`, `git rm`. Tasks end with "Run tests", not "Commit".
- **No app change in W1.** No file under `lib/` or `test/` changes (`git status --short -- lib test` stays empty at every gate), so the copy rules (`arb_append.py` then `flutter gen-l10n --arb-dir=lib/i10n --template-arb-file=app_en.arb --output-dir=lib/i10n/generated --output-localization-file=app_localizations.dart --no-synthetic-package`, never W2 P-9's perl fix; never "they" for the partner; dates through `MyDateFormat`; `\u` escapes by script), the §2.3 accessibility rules (`AllowLargeText` for sheets and dialogs, goldens at 1.0, 1.3, 2.0 and RTL; `InfoRowWidget` and `BottomSheetUtils` already scale above 1.0, never per caller) and D8 shared phones bind W3 onward, where the screens are; W1 adds no string, screen or provider. The only non-SQL files are the dev script, `scripts/local_pg_grants.sql` (edited, never run), `.github/workflows/tests.yml` and the DPIA draft. Never `dart format` a pre-existing file (W1 formats nothing).
- **SQL:** contracts run only on the local database `attune_spec3a`, only as `psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f <file>` **from the repo root** (`country_safety_config_contracts.sql` reads the dev script with `\set … \`cat …\``), inside the file's own `BEGIN … ROLLBACK`. Confirm the target first (`psql -X -d attune_spec3a -Atc 'select current_database()'` prints `attune_spec3a`). NEVER `attune_test`. NEVER run `scripts/local_pg_setup.sh`, `scripts/local_pg_grants.sql` or `scripts/local_pg_bootstrap.sql`; tasks **edit** `scripts/local_pg_grants.sql`, never running it. The only writes to `attune_spec3a` are applying this plan's migration files; mutants run inside one transaction that the contract's own `ROLLBACK` ends (the mutant file is applied after a `BEGIN` and before the contract), so a mutant never persists. Never commit DDL except by applying a migration file.
- **Migrations:** `20261106100000` … `20261106200000`, each with its `…10` grants twin (P-1), later than every migration in the tree (the newest is W9e's `20261104140010_healing_ai_insights_flag_grants.sql`). If `ls supabase/migrations | sort | tail -1` shows anything at or after `20261106100000` when Task 2 starts, shift all twenty-two to the next free hours, keeping their order, and change every header, `\i` line and command below to match. Each file is one `BEGIN; … COMMIT;`, idempotent (applied twice, `exit=0` both times), with `SET LOCAL lock_timeout = '5s'` (no step has a lock fallback: a busy table fails the migration loudly and `db push` is re-run); grants are explicit and nothing reaches `anon` except `get_dating_availability()` (spec §4.4); server-only objects are revoked inside the migration and again in the twin; every new public table gives `service_role` DML except `dating_profile_sensitive` (no API role, spec §4.2). Every re-created function starts from its LIVE latest body (saved from `pg_get_functiondef` in Task 1, which on `attune_spec3a` is what the newest migration that names it printed) and changes only the lines marked `-- Spec 2 W1a` … `-- Spec 2 W1d`; each task diffs them. No `CREATE INDEX CONCURRENTLY`. No function names a table or column a later wave creates (the few forward reads go through `to_jsonb(row) ->> '<column>'` or `to_regclass`, P-11). Shared tables that gain a trigger (`relationships` rewired in Task 2, `users` in Task 12, `feature_flags` in Task 13) get a run of their existing writers' contracts.
- **Environment (R-6, Q19b):** Spec 1's `private.attune_environment()` reads `development` while `app.settings.attune_environment` is unset; production mode is when this plan's refusals apply. **No migration, script or edge function sets it** (Task 7 adds the CI guard). The current project is development until the owner flips it.
- **Flags:** W1 adds one flag, `dating_same_gender_matching`, inserted false, and a production gate row for it and for every existing Dating flag (P-13). Migrations never turn a flag on. `supabase/sql/dev_enable_spec2_dating_flags.sql` is created in Task 1 and extended in Task 7 so every Dating flag that exists is ON in development and GH and GB are open; it runs `private.assert_development_project()` first and in the same statement as every change.
- **Safety rules:** nothing in W1 depends on an LLM. Nothing tells a reported, blocked or listed person anything: never-introduce answers "added" whatever the number; the kill switch queues no notification; refusals of off-country same-gender answers raise nothing, store nothing, count nothing (§2.4). Safety notices go to the at-risk person only (W1 sends none). Quick exit works everywhere (W1 adds no route). No "dating" in any device key or value (D20; W1 writes nothing to devices).
- **Never touch:** `lib/**` and `test/**` (W1 is server-only), in-chat Games (`test/architecture/games_untouched_test.dart` stays green), `ATTUNE_SOUL.md`, `ATTUNE_THESIS.md`, Opinions (no Opinions object or contract changes; `private.content_filter_verdict` is called, never re-created), `lib/home/home_screen.dart`'s latch (byte-identical: Task 1 saves its hash, every gate compares), `get_public_app_config()`, `set_user_path_internal`, `consume_fresh_start`, `mark_fresh_start_parked`, `quick_exit_service.dart`, `auth_provider.dart`, `supabase/sql/dev_enable_spec1_flags.sql`, every applied migration, every edge function. Existing contracts are edited only where W1 changes what they pin (P-9, P-13, P-32: `dating_exclusion_wiring_test.sql`, `dating_mode_contracts.sql`, `identity_foundation_contracts.sql`, `service_role_grants_test.sql`).
- **No deploys.** `supabase db push`, Vault keys (`dating_field_key`, and `dating_exclusion_key` if not yet set), counsel's sign-offs and the DPIA are the owner's ("Owner deploy checklist"). Don't read `.env*`, credentials or the keychain.
- **Lessons baked in:** every fail-closed branch has a mutant; contract comparisons use `IS DISTINCT FROM` (never `<>`, which a NULL turns into a silent pass) and `coalesce` around regex checks; a write and the read that checks it are separate statements (one statement sees one snapshot); re-created functions are diffed against `pg_get_functiondef`.
- **Regression gate at the end of each sub-wave (Tasks 4, 7, 10, 13):** every SQL contract on `attune_spec3a` shows no new FAIL against Task 1's two baseline runs, outside the AI-session group (`ai_session_*`, `ai_assist*`, `ai_processing_*`: they read rows their own earlier runs leave in the database, so a second unchanged run already adds three, Task 1); for any new FAIL inside that group, its first ERROR names no Dating object; the named W1 contracts and `identity_foundation_contracts.sql`, `account_deletion_contracts.sql`, `dormancy_contracts.sql`, `dating_mode_contracts.sql`, `dating_exclusion_wiring_test.sql`, `service_role_grants_test.sql` are PASS; no `lib/` or `test/` change; the latch is unchanged; the Games test passes.

## Review Focus

1. **A former partner changes number after the breakup (both of them, through Spec 1's verified change).** Expect them to stay excluded from each other while both accounts exist: the exclusion rows are keyed by the numbers at the time, so the predicate also reads the ended Attune relationship itself (P-4). Tests: Task 2 contract A (`a former partner's new number undid the exclusion`), mutant `exclusion_by_number_only`.
2. **Deleting an account while the exclusion key is missing.** Expect it to complete when nothing would be lost (no live restriction), and to be refused only when a live restriction would be dropped (R5). Tests: Task 4 contract C (`without the key and with no live restriction the deletion did not complete`, `a deletion without the key went ahead with a live restriction`), mutant `no_key_guard`.
3. **A number typed the way people type it: `00` instead of `+`, spaces, brackets, dashes.** Expect "Never introduce me" to read `001 (555) 870-061` as `+1555870061` (the same entry, the same "added"), and to refuse a local number with no country code. Tests: Task 11 contract E1 (the third add and the `0244 123 456` refusal), mutant `double_zero_not_plus`.
4. **The country closes while someone is half-way through setup.** Expect the next step to answer `not_eligible` and write nothing (W2's `get_dating_home` then shows `country_closed`). Tests: Task 9 contract I (`a setup step went through after the country closed`), mutant `guard_skips_eligibility`.
5. **First names in any script, or with an emoji.** Expect an Arabic name and `Kofi 🌻` to save, and 31 characters (not bytes) to be refused. Tests: Task 10 contract F (`an Arabic first name was refused`, `a name was measured in bytes, not characters`).

## Decisions found while verifying the code (read before Task 1)

Each is a verified fact about today's code (HEAD `c6bc8e16`), the database or the platform, with the smallest change that keeps the spec's intent. *Changes spec intent* marks the ones the owner should see.

**W1a**

- **P-1 (timestamps and names).** Migrations 1-11 are `20261106100000` (`dating_v2_phone_hmac`), `…110000` (`dating_v2_enforcement_survival`), `…120000` (`dating_v2_account_deletion`), `…130000` (`dating_v2_country_config`), `…140000` (`dating_v2_eligibility_base`), `…150000` (`dating_v2_profile_fields`), `…160000` (`dating_v2_setup_writers`), `…170000` (`dating_v2_profile_readers`), `…180000` (`dating_v2_never_introduce`), `…190000` (`dating_v2_lifecycle`), `…200000` (`dating_v2_kill_switch`), each with its `…10` twin. §4.9's single W1c migration is three files and W1d's second is two (P-19, P-31), one per task; the order and contents are §4.9's.
- **P-2 (no app change; the v1 Dating screens in development).** W1 is server-only, as §8 W1 lists it. From Task 12 the v1 Dating screens can no longer set up or activate in development: their consent screen records the retired `age_gate` and `historical_data` purposes and `save_dating_profile_draft` can't satisfy readiness v2 (prompts, encrypted answers). W3 replaces them; production has Dating off. The client's `exit_dating_mode` call (one argument) still resolves (P-32); its "delete profile" (`delete_dating_profile`, dropped in Task 12) fails in development too (PF-F15).
- **P-3 (`dating_phone_hmac_for_user`).** `auth.users.phone`, canonical `'+' || digits`, through the existing `dating_phone_hmac(text)`; a parked account (`users.phone_released_at` set) returns `users.parked_phone_hmac` or NULL. It also treats an Auth phone already on Spec 1's `+999…` placeholder as parked, closing the window between `start-fresh-account`'s rewrite and `mark_fresh_start_parked` (adds a fail-safe). Revoked from every API role.
- **P-4 (exclusions).** The recorder and predicate read the helper; the recorder skips a relationship whose `user_a` is gone (a NULL `user_id` would fail the exclusion's NOT NULL); the backfill covers `archived` too; and the predicate also holds while both accounts still have their ended or archived Attune relationship, so a later number change can't undo it (Review Focus 1; adds a fail-safe). Existing exclusions are recomputed in the migration only when `dating_exclusion_key` is set (a NOTICE says to run the backfill otherwise; owner checklist 2).
- **P-5 (the guard trigger).** Today's `handle_relationship_dating_guard()` already covers `paused` (Spec 3a), so §4.10's "orphaned" note is half stale; the rewire still matters for null-safety (`user_a` can be NULL). `CREATE OR REPLACE TRIGGER` swaps the function with no moment without a trigger; the old function is dropped.
- **P-6 (matches survive deletion).** Besides the members, `dating_matches.introduction_id` becomes `ON DELETE SET NULL` (nullable): introductions cascade from their users, and the old `CASCADE` would have deleted the match with them. `closed_reason` takes §4.3's full list now, so no later wave re-creates the CHECK.
- **P-7 (reports).** `target_phone_hmac` is filled at deletion (`prepare_account_deletion` step 4); W7a's report writers fill it at insert (carry). `reporter_user_id` and `target_user_id` become nullable `SET NULL`.
- **P-8 (standing).** `dating_account_in_good_standing` (live body) also fails while an enforcement record for the person's number is in effect (`scope = 'dating'`, `effect_until` NULL or future, not past `purge_after`) or a Spec 1 `age_review` / `safety_review` hold is unresolved (§2.1 gate 3). Carry to W7a: once `begin_dating_enrollment` copies a record into a `carried_over` restriction, the record must stop counting (or a won appeal never reopens Dating).
- **P-9 (grants re-asserted; the canary is deterministic).** Hosted projects grant every new public table and function to `anon`, `authenticated` and `service_role` by default; the local harness doesn't. Several old Dating functions were revoked from `PUBLIC` only (e.g. `20260703194500`), and four tables (`dating_enrollments`, `dating_consent_events`, `dating_profiles`, `dating_preferences`) were never revoked from clients at all (RLS was their only gate). Migration 2's twin therefore re-asserts every existing Dating table's client grants (REVOKE ALL from `PUBLIC`, `anon`, `authenticated`; SELECT kept on the six tables the v1 app and the Storage policies read until W3a: those four plus `dating_profile_photos` and `dating_photo_upload_intents`) and every existing Dating function's EXECUTE (none for `PUBLIC` or `anon`; `authenticated` only on the 22 client RPCs; the 11 service entry points keep `service_role`), so `attune_spec3a`, CI and the hosted projects agree and the canary can be exact. `service_role` is revoked on introductions, interest actions and matches (S-5, R22: no edge function reads them, checked by grep). Spec 1's `service_role_grants_test.sql` asserts every table is readable by the service role; it gains the S-5 exemption list (the six tables of §4.5).
- **P-10 (the canary's scope).** Relations: `dating_*` plus §4.5's four. Functions: in `public` and `private`, every name containing `dating` or `date_reflection` (the two private-reflection RPCs), plus `publish_country_config` and `apply_same_gender_switch`. Client privileges (`anon`, `authenticated`, `PUBLIC`) must match the allow-list exactly; for `service_role` only table DML is compared (hosted projects add TRUNCATE, REFERENCES and TRIGGER by default), and S-4's rule is checked by scanning every function the service role can run whose body calls `dating_field_decrypt` (only `dating_export_for_job`, W9, may). That scan is why the four decrypting client RPCs are revoked from `service_role` too (Tasks 9, 10).
- **P-11 (`prepare_account_deletion`).** The live body (`20261018110000`) with the carry-over first. The restriction's `category` and the reports' `state` are read by name (`to_jsonb(row) ->> …`), so W7a's new columns fill `category` and `confirmed_report_count` with no re-creation; until then they are NULL and 0. With a live restriction and no key the deletion raises `deletion:enforcement_key_missing` (R5: retried, never completed); without either it completes (Review Focus 2).
- **P-12 (secret scan).** gitleaks 8.18.4 as the released binary (no action licence), over the whole history. Its first run may report a secret committed long ago (owner checklist 7).
- **P-13 (flag gate rows).** `private.flag_production_gates` has no row for any Dating flag today, so production mode would let one be switched on without recorded evidence. Migration 4 adds one per Dating flag (`dating_mode_enabled` → the W10 gate; generation → W5; messaging → W6; photos → W3, naming the inline CSAM match; the retired alignment flag; `dating_same_gender_matching` → the LGBTQ+ reviewer's W3 sign-off). Spec 1's ruling left `dating_mode_enabled`'s gate to Spec 2, but `identity_foundation_contracts.sql` (H1) pinned "no row"; Task 5 amends that line to Spec 2's row. Adds a fail-safe.

**W1b**

- **P-14 (region codes).** ISO 3166-2:GH for Ghana's 16 regions (so Greater Accra is `AA`; §2.2's `{GA, AH}` is written `{AA, AH}`) and ITL1 (`TLC` … `TLN`) for the UK; sides `accra`, `tema`, `kumasi`, `outside_kumasi`; `name_key` values are ARB keys W3b adds. *Changes spec intent* (codes only; the cultural reviewer confirms the lists at the W3 gate).
- **P-15 (seeds).** 73 rows, every one `dating_enabled = false`: GH (tier 1), GB (tier 3) and research 04 §2.1.6's 27 other Tier 1 and 44 Tier 2 countries (Niger tier 1). GH and GB carry a `legal_checklist` of null evidence keys W10 fills; the others an empty one. A country with no row resolves through `dating_country_config(code)` to tier 3, closed, same-gender allowed.
- **P-16 (`publish_country_config`).** Service role only; merges `p_values` (an allow-listed set of keys) over the current row and publishes the next version under an advisory lock; a published row can only stop being current (a trigger refuses any other change and any delete). Refusals are returned, never raised (`config:invalid_country`, `…invalid_values`, `…unknown_key`, `…invalid_tz`, `…invalid_lists`, `…invalid_regions`, `…production_checks_failed` with the failed checks). "Every `legal_checklist` key has an evidence reference" also requires the checklist to be non-empty, and a reference to be a non-blank string (an empty checklist never passes; adds a fail-safe). Turning same-gender off returns `config:kill_switch_pending` until Task 13 (spec §2.2).
- **P-17 (the session context).** `dating_effective_context(phone, dating, ip, network)` is pure (four country codes in, the five values out). "Here" is the IP country, or the phone country when the IP is unresolved (§2.3); same-gender here needs a known Dating country; away needs one too. `record_dating_session_context(user, ip, network)` (service role, for W8b) takes the phone country from Auth's number through a calling-code map of every seeded country (longest prefix; `+76`/`+77` Kazakhstan before `+7` Russia; NANP Caribbean codes) and the Dating country from the profile by name (the column arrives in Task 8); it overwrites one row and counts the away streak.
- **P-18 (gate 6 without a country).** With no Dating country chosen yet, the `setup` scope passes gate 6 and the `candidate` scope fails it (`country_closed`); the same for a missing region where `open_regions` is set (`region_closed`). An unknown scope raises `eligibility:invalid_scope` (22023; internal callers only).
- **P-19 (Spec 1's public-config contract).** `identity_foundation_contracts.sql` pinned the interim row (`["GB","GH"]`, then an `UPDATE` of the row) and listed `private.dating_open_countries()` among "W1 functions that must not name a later wave's table" with `country_safety_config` in the pattern. Task 5 amends those three lines: the seam is now Spec 2's, reading the table, and the row is gone (I-3).
- **P-20 (the dev script).** Publishes GH and GB with `dating_enabled = true` only when closed (re-runs publish nothing), and raises if a publish is refused.

**W1c**

- **P-21 (three files).** Migration 6 (fields, tables, field functions, the trusted-device pass-through), 7 (D2-D8 writers), 8 (D10, D12, settings, other countries, photos after mutual, the two readers).
- **P-22 (v1 columns stay until their last readers go).** `dating_preferences.gender_preferences` / `region_preferences` / `intention_preferences` and `dating_profiles.gender_identity` are read by today's `dating_pair_passes_hard_filters` (and `activate`/`ready` until Task 12); `city_region_code`, `relationship_intention` and `bio` by `get_my_dating_matches`, `get_my_dating_introductions` and `save_dating_profile_draft`. Dropping them now would break those at run time. W1c makes `city_region_code` and `relationship_intention` nullable and leaves the rest; the drops move to the batch that re-creates the last reader: W5a (the arrays, `gender_identity`) and W6a (`city_region_code`, `relationship_intention`, `bio`, after W3b drops `save_dating_profile_draft`). `adults_only_confirmed_at` goes in Task 12 with its two readers. *Changes spec intent* (timing only).
- **P-23 (field encryption).** `private.dating_field_encrypt(jsonb)` / `private.dating_field_decrypt(bytea)` in the `private` schema (PostgREST can't expose them), EXECUTE for no API role; the key is `app_setting('dating_field_key')`, present when at least 32 characters (Vault's 44-character base64 of 32 bytes); both raise `dating:field_key_missing` without it, and every writer and reader checks first and answers `unavailable`.
- **P-24 (writer shape).** §4.4's `p_key` is written `p_idempotency_key`, as every live Dating RPC and `claim_dating_idempotency` name it. Order: signed in (else `not_authenticated`, 42501, like every Dating RPC); `dating_require_trusted_device()` (`reverify_device`); `dating_eligibility(me, 'setup')` (any failure is the opaque `not_eligible`; W2's `get_dating_home` names the state); validation (`invalid` with `field`); consent (`consent_required`); the key (`unavailable`); then the idempotency claim (a repeat answers ok and writes nothing). Other answers: `not_available`, `country_closed`, `region_closed`, `country_change_limited`, `contact_details`, `unkind`, `not_yet`. Each success returns `next_step` (§3.14's step names). Counters are server-side (`dating.setup.started`, `dating.setup.step.d2` … `d12`; S-2).
- **P-25 (consent and marriage history).** D5 and D6 need `special_category_profile`, D8 both it and `special_category_faith` (§3.2 D4). D2 holds marital history; the spec says D2 holds no special-category data (it comes before D4's consent), so D2 needs no consent but encrypts the answer anyway (a fail-safe; marital status isn't an Art. 9 category).
- **P-26 (the setup contract starts here).** §7.1 dates `dating_v2_setup_contracts.sql` (and mutants 4, 7) to W3b, but W1c builds the writers, so the file starts in Task 9 with the off-country rows and mutants 4 and 7; W3b and W3c extend it.
- **P-27 (off-country).** Off means the global flag or the country's switch. There D5 accepts only `woman`/`man` with no specific term, pronouns or extra pools, and D6 only the opposite single set; anything else is `not_available` with nothing stored (§2.4). A changed identity there clears who-to-meet (D6 again).
- **P-28 (country change).** At most once per 30 days (`country_change_limited`); a change clears the encrypted identity and who-to-meet and the gender toggle (D5 and D6 are asked again, §2.4) rather than decrypting to delete only the disallowed values (a superset; simpler and safe).
- **P-29 (rows start approved).** New profile rows are `moderation_state = 'approved'`: no free text is left unfiltered (prompts pass the contact and kindness filters; the name the contact filter). A moderator can reject later (W7). The D12 writer also refuses contact details in the first name (adds a fail-safe). With a blank `users.display_name` (impossible after Spec 1's sign-up) the profile starts as `Me`.
- **P-30 (other countries; photos after mutual).** At most 10 countries, each open and not one's own; turning any on needs a verified profile (`verification_state = 'verified'` and `dating_age_gate_holds`, which W4 re-creates) and an account at least 14 days old (`not_yet`). Photos after mutual interest from account day 30 (`not_yet`).

**W1d**

- **P-31 (two files).** Migration 10 (lifecycle) and 11 (kill switch).
- **P-32 (live shapes kept).** `activate_dating_profile`, `pause_dating_mode` and the new `resume_dating_mode` return `dating_enrollments` and raise as the live functions do, so the v1 app's calls keep their shape until W3a. `exit_dating_mode(text)` becomes `exit_dating_mode(text, boolean DEFAULT false)` (a one-argument call still resolves); `delete_dating_profile` is dropped. Spec 1's `identity_foundation_contracts.sql` sections D and D2 pin both old functions and the `adults_only_confirmed_at` checkbox; Task 12 amends them to the v2 lifecycle (the D2 activation fixture becomes a v2-complete profile; its delete case becomes exit's hard delete). `dating_mode_contracts.sql`'s fixture gains what readiness v2 needs (encrypted answers, prompts, photos, place, intention).
- **P-33 (`dating_profile_complete`).** New: everything `dating_profile_ready` v2 needs except `profile_state = 'active'` (approved, verified, age gate, place, intention + attestation `2026-10-v1`, children, encrypted identity and who-to-meet, >= 2 approved photos, >= 2 approved prompts). Activation and resume use it; `dating_profile_ready` = active AND complete.
- **P-34 (pause, resume).** Pause only from `active` or `profile_draft` (`user`); an enrolment already paused keeps its first reason (everywhere: relationship, parked, kill switch). Resume needs `dating_eligibility(me, 'setup')` and a complete profile, nothing more (Fable L3: no rate limit, no age-gate re-run).
- **P-35 (exit and consent).** One internal hard delete (`private.dating_exit_internal`) for exit and for any consent withdrawal (§3.2 D4: "Withdrawing any of them later = exit") except faith's, which clears only the faith answer (owner ruling 2026-11-06, PF-F3: `private.dating_clear_faith`, no setup guard); it also deletes the person's introductions, v1 snapshots, session row and notify request (PF-F8), queues unattached uploads (photos go through `queue_media_deletion`, so the CSAM evidence guard holds), closes active matches (`exit`, 30-day seal) and records one `dating_opt_in` withdrawal as "when you left" (§3.8). Consent events, the age assurance result and a suspension stay (Q17 exception 3, §4.8). The retired purposes' rows are deleted (fresh start) and a CHECK refuses them. Batch 10: consent input is checked before any write, its time is the server's clock (M-12), a replay changes nothing and a key reused for another event is refused (fix round 1, M-3); completeness, activation and resume need the standing `dating_terms`, `dating_opt_in` and `special_category_profile` consents, and exit withdraws every standing consent, so re-entering needs D4 again (fix round 1, I-1); a second exit rewrites nothing (M-2); resume never makes a never-activated draft live (M-4); every lifecycle RPC takes the setup lock first; pause, exit and a withdrawal never check the device (W1 B8 ruling).
- **P-36 (the parked trigger).** `AFTER UPDATE OF phone_released_at` with `WHEN (OLD … IS NULL AND NEW … IS NOT NULL)`, never raises (a failure is a WARNING): pause with `account_parked`, profile paused (which already invalidates the open introductions through the profile-version trigger; the explicit invalidation stays as belt and braces). Writes no enforcement record (owner ruling O3).
- **P-37 (the kill switch).** `apply_same_gender_switch(country)` (NULL = every country) deletes, for every person whose Dating country now has same-gender off, an identity that isn't plain woman/man (a specific term, pronouns or extra pools count) and who-to-meet unless it is exactly the opposite single set, turns the gender toggle off, pauses (`same_gender_switch`), then invalidates every open introduction touching that country that isn't man-woman (both identities decrypted in the transaction; cross-border included). Active matches that aren't known to be man-woman close (`other`, sealed 30 days, nobody told; owner ruling 2026-11-06 on owner question 1, PF-F2; built in Task 13; W1 final fix M-2: moving one's Dating country into a same-gender-off country gives the mover's pairs the same treatment). The global flag is wired through an `AFTER UPDATE OF enabled` trigger on `feature_flags` for that one key (spec §2.4: "or the global flag off"); neither path can block the switch-off: without the field key the switch is still published (`affected: null`) and the owner re-runs `select public.apply_same_gender_switch(...)`. Shared-table run: Spec 1's flag contracts (`identity_foundation_contracts.sql`, `healing_ai_pause_contracts.sql`) stay green.
- **P-38 (health v2).** Adds `environment`, `field_key_present`, `exclusion_key_fingerprint_ok`, `field_key_fingerprint_ok`, `safety_counters_7d` (batch 10), `log_settings_safe` (`log_statement` in `none`/`ddl`, and `log_min_duration_statement = -1` or `log_parameter_max_length = 0`, and `log_parameter_max_length_on_error = 0`; anything unreadable is false) and `enabled_countries`. The other §4.10 health fields belong to the waves that create their objects.

**Fixtures.** `dating_v2_identity_contracts.sql`: ids `5e2a0000-0000-0000-0000-0000000000NN`, phones `15558700NN`; `country_safety_config_contracts.sql`: `5e2b…`, `15558701NN`; `dating_v2_eligibility_contracts.sql`: `5e2c…`, `15558702NN`; `dating_v2_setup_contracts.sql`: `5e2d…`, `15558703NN` (the 87xx range, unused by every other contract; Auth's form without `+`). Never-introduce probes use `+44 7700 900xxx` (Ofcom's drama range).

## Carried items

From Spec 1 (each placed in the Spec 2 batch that owns the code):

1. **CSAM inline matching (S1 W7 PF-H2) → W3c.** W3c owns `process-dating-photo`: it calls `_shared/csam_matcher.ts`, and on a match `_shared/csam_match_path.ts` `quarantineAndRecord()` with `record_inline_csam_match` (seven arguments: `p_bucket, p_object_name, p_owner, p_vendor, p_vendor_ref, p_quarantined DEFAULT true, p_quarantine_path DEFAULT NULL`, live in `attune_spec3a`), before any approval. W1 makes it a production gate: migration 4's gate row on `dating_profile_photos` names it, so production mode refuses that flag without recorded evidence (and `dating_mode_enabled`'s W10 gate covers the rest). Dating stays off in production until W3c ships it. `storage_bucket_policies.sql` (Task 3) already pins that `dating-profile-photos` is not in Spec 1's scan-trigger list (inline only, I-10).
2. **Shared normaliser (S1 W9 PF-C9) → W6b.** `_shared/dating_chat_safety.ts` re-runs its goldens against the widened shared folds and calls `private.content_filter_verdict` only through its own `SECURITY DEFINER` wrapper, never granted directly. (W1c's two writers call the verdict inside their own definer bodies, which is that rule's SQL form.)
3. **Hold kind on the wire (S1 W6 L7) → W3c; mid-session hold device block (S1 W6 minor #2) → W4a.** `get_my_home_state` sends `hold_kind = 'safety_review'` today; W3c (the first Dating path that places `safety_review`, through the CSAM match) re-creates it from its live body to send a generic `account_review` for every non-age hold (the app's `HoldKind.fromWire` already maps an unknown kind to H1 without the device block, so no client change is needed; its cache then stores `unknown`). W4a (the first Dating path that places `age_review` while the person is signed in, D11's far-below-18 estimate) adds the device block when a hold arrives mid-session instead of at the next sign-in.
4. **D8 shared phones → W3a.** W3a creates the Dating providers and repository: every one is keyed to the signed-in user and resets on a user change; its tests hold the new user's first read open and assert the frames shown meanwhile (never the previous user's data). W1 holds nothing on the device.

Found here, for later batches:

5. **W3a, Storage policies.** `dating_profile_photos_select_owner` and `dating_profile_photos_insert_by_intent` read `public.dating_profile_photos` and `public.dating_photo_upload_intents` as the caller. W3a's planned revoke of client SELECT on those tables would turn every Storage read into 42501 (the same failure `story_storage_policy_isolation_contracts.sql` documents for Stories); move the two reads into definer helpers first. Task 3 keeps both SELECT grants for that reason.
6. **W2.** Re-creates `dating_eligibility` from Task 6's live body (gate 5) and `private.dating_home_summary` if enrolment states change; `enforce_dating_lifecycle_gates` (cron, every 15 min) still calls `dating_healing_gates_hold` and v1 readiness semantics until W2.
7. **W4a/W4b.** `dating_profile_complete` reads `verification_state = 'verified'` and `dating_age_gate_holds` as W1's "identity and age passed"; W4 re-creates both; W4b's `dating_require_trusted_device()` replaces Task 8's pass-through.
8. **W5a.** Filter 13 calls `dating_never_introduce_excludes(a, b)`; generation v2 needs the same key guard as Task 12's v1; the P-22 drops.
9. **W7a.** Report writers fill `target_phone_hmac` at insert; P-8's carried-record rule.
10. **Harness.** `scripts/local_pg_grants.sql` has no `\i` line for W9e's twin (`20261104140010`); harmless (it only re-asserts `feature_flags` grants, which Task 5's twin re-asserts too), but the next Spec 1 touch should add it.
11. **W3a (W1 final fix, M-3).** The client retries a `dating:busy` (SQLSTATE 40P01, 55P03 or 40001) from any Dating RPC once, silently; the server already retried three times.
12. **W3b (W1 final fix, M-9).** `save_dating_profile_draft` (v1) is revoked from every API role (no flag, eligibility or filter check; it reopened an exited or paused enrolment); W3b drops it and W6a its v1 columns (P-22). The v1 photo writers `create_dating_photo_upload_intent` and `insert_dating_profile_photo` are revoked from every API role too (final re-review N-I1: they checked no flag, eligibility, standing or rate limit, so any signed-in user could upload into `dating-profile-photos` with Dating off, and Spec 1's CSAM scan doesn't cover that bucket; without an intent the bucket's INSERT policy admits nothing, and no client can write an intent). W3 re-creates both with the v2 checks and re-grants them; W3c's inline CSAM match must land first. Until then the `upload-dating-photo` diagnostic edge function answers an error. `delete_dating_profile_photo` stays (it only removes). The other v1 writers still granted to `authenticated` keep their spec dispositions: `begin_dating_enrollment` (W2) and `act_on_dating_introduction` (W5) check `dating_mode_enabled`, and `unmatch_dating_match` needs an active match, which can't exist yet.
13. **W5-W7 (W1 final fix, I-1 residual).** The pre-W1 writers that touch introductions or matches (`block_dating_user`, interest actions, reports, `unmatch_dating_match`) don't take the person's same-gender locks yet; each locks only the pair's rows today. The wave that re-creates each one starts it with `private.dating_lock_setup(me)` (and the partner's countries where it writes both sides). The switch itself still locks every enrolment in the switched country (decide-unlocked-then-lock was the review's optional third fix; not needed once every writer takes the locks).
14. **Later wave (W1 final fix, I-3).** The verify-only secondary exclusion key (`dating_exclusion_key_previous`, dual-HMAC reads) that makes a rotation possible; item 11 of the owner checklist.

## Owner questions (1 and 2 ruled 2026-11-06 and built; 3 open)

1. **Ruled and built (owner ruling 2026-11-06, PF-F2; Task 13): the switch closes them as recommended below.** **The kill switch and existing same-gender matches (P-37).** The spec invalidates introductions, deletes answers and pauses people, but leaves open matches (and from W6 their conversations) between same-gender people in the country that just switched off. *Recommendation:* close them in the same transaction with a neutral reason (`other`) and the 30-day evidence seal, no notice to either; an open same-gender conversation is the riskiest record in a country that just became unsafe. One added statement in `apply_same_gender_switch` and one contract line. (Built.)
2. **Ruled and built (owner ruling 2026-11-06, PF-F3; Task 12): a faith-only withdrawal clears only the faith answer.** **Withdrawing only the faith consent (P-35).** The spec makes any withdrawal "leaving Dating", so withdrawing `special_category_faith` deletes the whole profile. *Recommendation:* make a faith-only withdrawal clear the faith answer (as D8's Skip does) and keep the rest; leaving stays one tap away. (Built.)
3. **Owner nods:** P-13 (gate rows, including `dating_mode_enabled`'s W10 gate), P-14 (ISO region codes), P-22 (when the v1 columns go), P-2 (the v1 screens stop working in development from Task 12 until W3).

## Interfaces this plan consumes (read from the current code; adjust here if a later fix renames one)

- **Spec 1 W1a:** `public.users` (`phone` copied from `auth.users` by `private.users_phone_from_auth_on_insert` / `private.sync_users_phone_from_auth`; `path`, `path_previous`, `path_chosen_at`, `phone_released_at`, `display_name`, `created_at`, `eula_accepted_at`, `eula_version` (EULA v2 = `eula_version` an integer >= 2 with `eula_accepted_at` set), `mode` (column kept, no writer)); `auth.users` (`phone` in Auth's form without `+`, `phone_confirmed_at`, `banned_until`, `deleted_at`).
- **Spec 1 W1b:** `public.account_age(p_user uuid) → integer` (NULL with no DOB; ungranted), `public.account_birthdates (user_id, birth_date, …)`, `public.account_holds (user_id, kind IN ('age_review','recovery_hold','safety_review'), reason_ref, created_at, expires_at, resolved_at, resolved_by)` PK `(user_id, kind)`, `public.place_account_hold(p_user uuid, p_kind text, p_ref text DEFAULT NULL)`, `public.metric_key_prefixes (prefix, owner_spec)` (prefix CHECK `^[a-z0-9_:>.-]{1,80}$`), `private.bump_metric_internal(p_key text)` (counts a key under a listed prefix; never raises), `public.get_my_home_state()` (its `dating` key is `private.dating_home_summary(auth.uid())`).
- **Spec 1 W1c:** `private.attune_environment() → text` (`development` only when Vault and the GUC are unset/`development`), `private.assert_development_project()` (raises `env:not_development`), `public.get_attune_environment()`, `public.app_public_config (key, value jsonb, updated_at)` with the interim row `dating_open_countries = ["GH","GB"]`, `private.dating_open_countries() → text[]` (live body `20261025100400`), `public.get_public_app_config() → jsonb` (anon), `private.flag_production_gates (flag_key, gate, review_ref, recorded_by, recorded_at)` and the trigger `feature_flags_production_gate` (`private.guard_flag_production_gate()`: in production mode refuses `enabled = true` while the flag's gate row has no `review_ref`).
- **Spec 1 W3:** `private.dating_home_summary(p_user uuid) → jsonb {enabled, enrolled}` (live body `20261025100300`).
- **Spec 1 W6a:** `public.users.parked_phone_hmac` (written by `public.consume_fresh_start(p_nonce text, p_ip_hash text DEFAULT NULL)` as `dating_phone_hmac('+' || digits of auth.users.phone)`), `public.mark_fresh_start_parked(p_user uuid)` (needs a `recovery_hold` and an Auth phone matching `^\+?999[0-9]{12}$`; sets `phone_released_at`), `private.seal_fresh_start(p_user uuid, p_at timestamptz) → text`, `public.account_activity (user_id, last_active_at)`.
- **Spec 1 W7b / W9a:** `public.record_inline_csam_match(p_bucket, p_object_name, p_owner, p_vendor, p_vendor_ref, p_quarantined DEFAULT true, p_quarantine_path DEFAULT NULL) → bigint` (carried, W3c), `private.media_scan_buckets() → text[]` (no `dating-profile-photos`), `private.content_filter_verdict(p_text text, p_families text[]) → text` (`contact_info` | `slur` | `explicit` | NULL; `[DRAFT]` terms match only in development).
- **Existing Dating objects (live bodies saved in Task 1):** `public.dating_phone_hmac(p_phone text)` (HMAC-SHA256 with Vault's `dating_exclusion_key`; NULL without it), `record_dating_former_partner_exclusion(uuid, boolean DEFAULT false)`, `dating_former_partner_excluded(uuid, uuid)`, `backfill_dating_former_partner_exclusions()`, `sync_dating_pause_on_relationship()`, `handle_relationship_dating_guard()` (trigger `relationship_dating_guard`), `pause_dating_for_relationship_user(uuid)`, `block_dating_user(text, uuid)`, `dating_account_in_good_standing(uuid)`, `dating_age_gate_holds(uuid)`, `dating_has_relationship(uuid)`, `dating_flag_enabled(text)`, `dating_pair_key(uuid, uuid)`, `claim_dating_idempotency(text, text)` (key 8-200 of `[A-Za-z0-9_:.-]`), `invalidate_dating_for_user(uuid, text)`, `record_dating_consent(text, text, text, text, jsonb)`, `activate_dating_profile(text)`, `pause_dating_mode(text)`, `exit_dating_mode(text)`, `delete_dating_profile(text)`, `dating_profile_ready(uuid)`, `run_dating_candidate_generation(text)`, `get_dating_operational_health()`; tables `dating_enrollments`, `dating_consent_events` (unique `(user_id, idempotency_key)`), `dating_profiles`, `dating_preferences`, `dating_profile_photos`, `dating_photo_upload_intents`, `dating_introductions` (snapshot FKs to `dating_feature_snapshots`), `dating_interest_actions`, `dating_matches`, `dating_blocks`, `dating_reports`, `dating_account_restrictions` (its trigger suspends the enrolment), `dating_date_reflections (author_user_id, …)`, `dating_former_partner_exclusions`; `public.prepare_account_deletion(uuid)` (live body `20261018110000`), `public.app_setting(text)`, `public.queue_media_deletion(text, text)`, `public.end_relationship(uuid)`.

## Interfaces this plan produces (for W2 onward)

- **W1a:** `public.dating_phone_canonical(text) → text`, `public.dating_phone_hmac_for_user(uuid) → text`; tables `public.enforcement_records (id, phone_hmac, scope IN ('dating','opinions'), source_restriction_id UNIQUE, restriction_type, category, confirmed_report_count, effect_until, purge_after, created_at)`, `public.dating_block_hmacs (blocker_hmac, blocked_hmac, created_at, purge_after)`; `dating_reports.target_phone_hmac`; `dating_matches.closed_reason` (§4.3's ten values), `evidence_until`; the `dating.` metric prefix.
- **W1b:** `public.country_safety_config` (§2.2 columns), `public.dating_country_config(text) → country_safety_config`, `public.publish_country_config(text, jsonb) → jsonb` (service role), `public.get_dating_availability() → jsonb {countries: [{code, open_regions: [{code, name_key}] | null}]}` (anon, authenticated), `public.dating_session_context`, `public.dating_effective_context(text, text, text, text) → jsonb`, `public.record_dating_session_context(uuid, text, text) → jsonb` (service role), `private.dating_phone_country(text) → text`, `public.dating_notify_requests (user_id, country_code, region_code, created_at)`, flag `dating_same_gender_matching`, `public.dating_eligibility(uuid, text DEFAULT 'candidate') → text`.
- **W1c:** `public.dating_require_trusted_device() → boolean` (pass-through), `private.dating_field_key_present()`, `private.dating_field_encrypt(jsonb) → bytea`, `private.dating_field_decrypt(bytea) → jsonb`, `private.dating_consent_granted(uuid, text)`, `public.dating_profile_sensitive`, `public.dating_prompts`, `public.dating_settings`, the profile and preference columns of §4.3; `private.dating_setup_guard()`, `private.dating_ensure_profile(uuid)`, `private.dating_same_gender_on(text)`, `private.dating_default_ages(integer)`; the writers `save_dating_intention(text, text, text, boolean, boolean, text, boolean)`, `save_dating_location(text, text, text, text, text)`, `save_dating_identity(text, text, text, text, text[], boolean)`, `save_dating_who_to_meet(text, text[], integer, integer)`, `save_dating_children(text, boolean, text, boolean, boolean)`, `save_dating_faith(text, text, text, text, boolean)`, `clear_dating_faith(text)`, `save_dating_prompts(text, jsonb)`, `save_dating_display_name(text, text)`, `save_dating_family_involvement(text, text)`, `save_dating_settings(text, jsonb)`, `set_dating_open_abroad(text, char(2)[])`, `set_dating_photos_after_mutual(text, boolean)` (all `→ jsonb`, signed in); `get_my_dating_profile() → jsonb`, `get_dating_profile_preview() → jsonb`.
- **W1d:** `public.dating_never_introduce`, `add_dating_never_introduce(text, text, text)`, `remove_dating_never_introduce(uuid)`, `list_dating_never_introduce()`, `dating_never_introduce_excludes(uuid, uuid) → boolean`; `dating_enrollments.pause_reason`; `dating_profile_complete(uuid)`, `resume_dating_mode(text)`, `exit_dating_mode(text, boolean DEFAULT false)`, `private.dating_exit_internal(uuid, boolean)`, the trigger `dating_on_account_parked` on `users`; `apply_same_gender_switch(text) → integer`, the trigger `dating_same_gender_flag_off` on `feature_flags`.

## File map

**W1a (Tasks 1-4)**
- Create `.superpowers/sdd/2026-11-06-spec2-w1/{mutate.py, section.py, before/*.sql, sql-baseline-1.txt, sql-baseline-2.txt, latch.sha}` and `supabase/sql/dev_enable_spec2_dating_flags.sql` (Task 1).
- Create `supabase/migrations/20261106100000_dating_v2_phone_hmac.sql`, `…100010_…_grants.sql`, `supabase/tests/dating_v2_identity_contracts.sql`; modify `supabase/tests/dating_exclusion_wiring_test.sql`, `supabase/tests/dating_mode_contracts.sql`, `scripts/local_pg_grants.sql` (Task 2).
- Create `…110000_dating_v2_enforcement_survival.sql`, `…110010_…_grants.sql`, `supabase/tests/dating_rls_canary.sql`, `supabase/tests/storage_bucket_policies.sql`; modify `dating_v2_identity_contracts.sql` (section B), `supabase/tests/service_role_grants_test.sql`, `.github/workflows/tests.yml` (job `repo-guards`), `scripts/local_pg_grants.sql` (Task 3).
- Create `…120000_dating_v2_account_deletion.sql`, `…120010_…_grants.sql`, `lib/architecture/DATING_MODE_DPIA.md`; modify `dating_v2_identity_contracts.sql` (C), `scripts/local_pg_grants.sql` (Task 4).

**W1b (Tasks 5-7)**
- Create `…130000_dating_v2_country_config.sql`, `…130010_…_grants.sql`, `supabase/tests/country_safety_config_contracts.sql`; modify `dating_rls_canary.sql`, `supabase/tests/identity_foundation_contracts.sql`, `scripts/local_pg_grants.sql` (Task 5).
- Create `…140000_dating_v2_eligibility_base.sql`, `…140010_…_grants.sql`, `supabase/tests/dating_v2_eligibility_contracts.sql`; modify `dating_rls_canary.sql`, `scripts/local_pg_grants.sql` (Task 6).
- Modify `supabase/sql/dev_enable_spec2_dating_flags.sql`, `country_safety_config_contracts.sql` (H), `.github/workflows/tests.yml` (one step) (Task 7).

**W1c (Tasks 8-10)**
- Create `…150000_dating_v2_profile_fields.sql`, `…150010_…_grants.sql`; modify `dating_v2_identity_contracts.sql` (D1), `dating_v2_eligibility_contracts.sql` (B), `country_safety_config_contracts.sql` (F2), `dating_rls_canary.sql`, `scripts/local_pg_grants.sql` (Task 8).
- Create `…160000_dating_v2_setup_writers.sql`, `…160010_…_grants.sql`, `supabase/tests/dating_v2_setup_contracts.sql`; modify `dating_rls_canary.sql`, `scripts/local_pg_grants.sql` (Task 9).
- Create `…170000_dating_v2_profile_readers.sql`, `…170010_…_grants.sql`; modify `dating_v2_setup_contracts.sql` (F-H), `dating_v2_identity_contracts.sql` (D2), `dating_rls_canary.sql`, `scripts/local_pg_grants.sql` (Task 10).

**W1d (Tasks 11-13)**
- Create `…180000_dating_v2_never_introduce.sql`, `…180010_…_grants.sql`; modify `dating_v2_identity_contracts.sql` (E1), `dating_rls_canary.sql`, `scripts/local_pg_grants.sql` (Task 11).
- Create `…190000_dating_v2_lifecycle.sql`, `…190010_…_grants.sql`; modify `dating_v2_identity_contracts.sql` (E2), `dating_mode_contracts.sql`, `identity_foundation_contracts.sql`, `dating_rls_canary.sql`, `scripts/local_pg_grants.sql` (Task 12).
- Create `…200000_dating_v2_kill_switch.sql`, `…200010_…_grants.sql`; modify `country_safety_config_contracts.sql` (E), `dating_rls_canary.sql`, `scripts/local_pg_grants.sql` (Task 13).

**Not edited:** everything under `lib/` (except the new DPIA document in `lib/architecture/`) and `test/`, `supabase/functions/**`, `supabase/config.toml`, every applied migration, `supabase/sql/dev_enable_spec1_flags.sql`, `scripts/local_pg_setup.sh`, `scripts/local_pg_bootstrap.sql`, every contract not named above.

---

# W1a · Identity, enforcement survival, deletion carry-over, canaries (Tasks 1-4)

### Task 1: Baselines, the "before" bodies, the plan helpers, the dev script (§4.9 dev switch-on, R-6, R10)

**Files:**
- Create: `.superpowers/sdd/2026-11-06-spec2-w1/mutate.py`, `.superpowers/sdd/2026-11-06-spec2-w1/section.py`, `.superpowers/sdd/2026-11-06-spec2-w1/before/*.sql`, `.superpowers/sdd/2026-11-06-spec2-w1/sql-baseline-1.txt`, `.superpowers/sdd/2026-11-06-spec2-w1/sql-baseline-2.txt`, `.superpowers/sdd/2026-11-06-spec2-w1/latch.sha`
- Create: `supabase/sql/dev_enable_spec2_dating_flags.sql`

**Interfaces:**
- Consumes: `private.assert_development_project()`, `public.feature_flags (key, enabled, updated_at)`.
- Produces: `mutate.py <migration.sql> <contract.sql> <spec.py> <dir>` (each mutant in `spec.py`'s `MUTS` — `(old, new)` replaces one exact occurrence in the migration with its own `BEGIN`/`COMMIT` removed; `('MULTI', [(old, new), …])`; `('CUT', (start, end))` removes the span; `('RAW', sql)` is SQL of its own — runs after a `BEGIN` and before the contract, whose `ROLLBACK` undoes it, and prints the contract's first ERROR); `section.py` (adds a contract section once: `--end`, `--before '<title line>'`, `--replace '<title>' '<next title>'`); the dev script.

- [ ] **Step 1: Confirm the target and the newest migration**

```bash
psql -X -d attune_spec3a -Atc "select current_database(), current_setting('server_version_num')::int >= 170000"
ls supabase/migrations | sort | tail -1
git status --short -- lib test supabase/tests supabase/sql scripts .github
```

Expected: `attune_spec3a|t`; `20261104140010_healing_ai_insights_flag_grants.sql`; no line (only the owner's two files elsewhere).

- [ ] **Step 2: Two baseline runs of the whole SQL suite**

The AI-session contracts read rows that their own earlier runs leave in `attune_spec3a`, so a second run with nothing changed fails three more of them; both runs are the baseline.

```bash
D=.superpowers/sdd/2026-11-06-spec2-w1; mkdir -p $D/before
for run in 1 2; do
  for f in supabase/tests/*.sql; do
    if psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f "$f" >/dev/null 2>&1; then echo "PASS $(basename "$f")"; else echo "FAIL $(basename "$f")"; fi
  done > $D/sql-baseline-$run.txt
  echo "run $run: $(grep -c '^PASS' $D/sql-baseline-$run.txt) PASS, $(grep -c '^FAIL' $D/sql-baseline-$run.txt) FAIL"
done
```

Expected on the scratch copy (record whatever the real database prints): `run 1: 151 PASS, 13 FAIL` (`ai_assist_draft_share`, `ai_assistant_quota`, `ai_assistant_quota_evasion_regression`, `ai_assistant_schema`, `ai_processing_consent`, `ai_session_admit`, `ai_session_approve_activate`, `ai_session_dispatch_claim`, `ai_session_prepare`, `ai_session_purge`, `couple_map_presence`, `reminder_delivery`, `together_events`), and `run 2: 148 PASS, 16 FAIL` (the same plus `ai_session_commit_ideas`, `ai_session_nearby_staging`, `ai_session_read_authorization`). Every Dating contract and `account_deletion_contracts.sql`, `identity_foundation_contracts.sql`, `dormancy_contracts.sql` are PASS.

- [ ] **Step 3: Save the live bodies this plan re-creates, the latch hash, and check the Games test**

```bash
D=.superpowers/sdd/2026-11-06-spec2-w1
for sig in 'public.record_dating_former_partner_exclusion(uuid,boolean)' 'public.dating_former_partner_excluded(uuid,uuid)' \
           'public.backfill_dating_former_partner_exclusions()' 'public.block_dating_user(text,uuid)' \
           'public.dating_account_in_good_standing(uuid)' 'public.prepare_account_deletion(uuid)' \
           'private.dating_open_countries()' 'private.dating_home_summary(uuid)' \
           'public.record_dating_consent(text,text,text,text,jsonb)' 'public.dating_profile_ready(uuid)' \
           'public.activate_dating_profile(text)' 'public.pause_dating_mode(text)' \
           'public.pause_dating_for_relationship_user(uuid)' 'public.run_dating_candidate_generation(text)' \
           'public.get_dating_operational_health()'; do
  psql -X -d attune_spec3a -Atc "select pg_get_functiondef('$sig'::regprocedure)" > "$D/before/$sig.sql"
done
ls $D/before | wc -l
sed -n '/if (isAuthenticated \&\& !_gateData.isComplete) {/,/_redirectingToOnboarding = false;/p' lib/home/home_screen.dart | shasum > $D/latch.sha
flutter test test/architecture/games_untouched_test.dart 2>&1 | tail -1
```

Expected: `15`; `All tests passed!`. (`publish_country_config` is saved in Task 13, Step 1, after Task 5 creates it.)

- [ ] **Step 4: The two plan helpers**

Create `.superpowers/sdd/2026-11-06-spec2-w1/mutate.py` with exactly:

```python
#!/usr/bin/env python3
"""Spec 2 W1 mutation runner (attune_spec3a only).
usage: mutate.py <migration.sql> <contract.sql> <spec.py> <dir>
spec.py defines MUTS = {name: mutation}; a mutation is (old, new) (one exact
occurrence in the migration, whose own BEGIN/COMMIT are removed), ('MULTI',
[(old, new), ...]), ('CUT', (start, end)) (the span is removed) or ('RAW',
sql) (SQL of its own). Each runs after a BEGIN and before the contract,
whose ROLLBACK undoes it; the contract's first ERROR is printed."""
import pathlib, re, runpy, subprocess, sys

mig, con, spec, out = sys.argv[1], sys.argv[2], sys.argv[3], pathlib.Path(sys.argv[4])
m = pathlib.Path(mig).read_text()
assert m.count("\nBEGIN;\n") == 1 and m.count("\nCOMMIT;\n") == 1, mig
body = m.replace("\nBEGIN;\n", "\n").replace("\nCOMMIT;\n", "\n")
for name, (a, b) in runpy.run_path(spec)['MUTS'].items():
    if a == 'RAW':
        text = b
    elif a == 'MULTI':
        text = body
        for x, y in b:
            assert text.count(x) == 1, (name, x[:50], text.count(x))
            text = text.replace(x, y)
    elif a == 'CUT':
        st, en = b
        assert body.count(st) == 1 and body.count(en) == 1, name
        i, j = body.index(st), body.index(en) + len(en)
        text = body[:i] + body[j:]
    else:
        assert body.count(a) == 1, (name, body.count(a))
        text = body.replace(a, b)
    f = out / f"mut_{name}.sql"
    f.write_text(text)
    r = subprocess.run(['psql', '-X', '-q', '-v', 'ON_ERROR_STOP=1', '-d', 'attune_spec3a',
                        '-c', 'BEGIN', '-f', str(f), '-f', con], capture_output=True, text=True)
    lines = (r.stdout + r.stderr).splitlines()
    idx = [i for i, l in enumerate(lines) if 'ERROR' in l]
    line = lines[idx[0]] if idx else 'NO ERROR (mutant survived)'
    if idx and line.endswith(':') and idx[0] + 1 < len(lines) and lines[idx[0] + 1].startswith('  '):
        line += ' ' + lines[idx[0] + 1].strip()
    print(f"{name}: {re.sub(r'^psql:[^ ]* ', '', line)[:170]}")
    f.unlink()
```

Create `.superpowers/sdd/2026-11-06-spec2-w1/section.py` with exactly:

```python
#!/usr/bin/env python3
"""Adds a contract section from a file, exactly once.
usage: section.py <target.sql> <piece.sql> --end
       section.py <target.sql> <piece.sql> --before '<a banner's title line>'
       section.py <target.sql> <piece.sql> --replace '<first title line>' '<next title line>'
--end puts the piece before the file's closing NOTICE; --before puts it
above the banner whose title line is given; --replace swaps the section
from one banner to the next for the piece."""
import pathlib, sys

def banner_start(s, title):
    assert s.count(title) == 1, f'{title!r} occurs {s.count(title)} times'
    i = s.index(title)
    j = s.rfind('\n', 0, i - 1) + 1  # the banner rule just above the title
    assert s[j:j + 4] in ('-- =', '-- -'), 'no banner rule above ' + title
    return j

target, piece, mode = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2]), sys.argv[3]
s, add = target.read_text(), piece.read_text()
if mode == '--end':
    foot = "DO $$ BEGIN RAISE NOTICE '"
    assert s.count(foot) == 1
    i = s.index(foot)
    s = s[:i] + add + s[i:]
elif mode == '--before':
    i = banner_start(s, sys.argv[4])
    s = s[:i] + add + s[i:]
elif mode == '--replace':
    i, j = banner_start(s, sys.argv[4]), banner_start(s, sys.argv[5])
    s = s[:i] + add + s[j:]
else:
    sys.exit('unknown mode ' + mode)
target.write_text(s)
print(f'{target.name}: {piece.name} {mode[2:]}')
```

- [ ] **Step 5: Create the dev script (W1a: every Dating flag that exists)**

Create `supabase/sql/dev_enable_spec2_dating_flags.sql` with exactly:

```sql
-- DEV / MANUAL TESTING ONLY. Never a migration (Spec 2 §4.9, R-6, Q19b,
-- I-15). Turns every Spec 2 Dating flag that exists ON, on the development
-- project only. The guard comes first and everything is one statement, so
-- when Spec 1's guard raises env:not_development (the project doesn't read
-- 'development', or supabase_url is set and doesn't name the development
-- ref, or it can't be read) nothing changes. It never sets
-- attune_environment; nothing in Spec 2 does. Safe to re-run. Re-run it
-- after any migration replay: 20260705210000 forces the Dating flags off
-- when it replays (R10). Every later Spec 2 batch extends it.
DO $$
BEGIN
  PERFORM private.assert_development_project();

  -- W1a: every Dating flag that exists.
  INSERT INTO public.feature_flags (key, enabled) VALUES
    ('dating_mode_enabled', true),
    ('dating_candidate_generation', true),
    ('dating_match_messaging', true),
    ('dating_profile_photos', true),
    ('dating_alignment_algorithm_v1', true)
  ON CONFLICT (key) DO UPDATE SET enabled = EXCLUDED.enabled, updated_at = now();
END $$;
```

- [ ] **Step 6: Check it, in development and in production mode, inside a rolled-back transaction**

```bash
printf '%s\n' 'BEGIN;' '\i supabase/sql/dev_enable_spec2_dating_flags.sql' \
  "SELECT string_agg(key || '=' || enabled, ' ' ORDER BY key) FROM public.feature_flags WHERE key LIKE 'dating\\_%';" 'ROLLBACK;' \
  | psql -X -At -d attune_spec3a 2>&1 | grep -v -E '^(BEGIN|DO|ROLLBACK)$'
printf '%s\n' 'BEGIN;' "SELECT set_config('app.settings.attune_environment', 'production', true) \\g /dev/null" \
  '\i supabase/sql/dev_enable_spec2_dating_flags.sql' 'ROLLBACK;' \
  | psql -X -At -d attune_spec3a 2>&1 | grep -m1 ERROR | sed -E 's/^psql:[^ ]* //' 
```

Expected: `dating_alignment_algorithm_v1=true dating_candidate_generation=true dating_match_messaging=true dating_mode_enabled=true dating_profile_photos=true`, then `ERROR:  env:not_development` (Task 7 pins both in a contract, mutant 25). Nothing persists (both transactions roll back).

### Task 2: Migration 1: phone HMACs from `auth.users`, parked accounts, the guard trigger (§4.9 W1a #1; I-11; mutants 1, 27; P-3-P-5)

**Files:**
- Create: `supabase/migrations/20261106100000_dating_v2_phone_hmac.sql`, `…100010_dating_v2_phone_hmac_grants.sql`
- Create: `supabase/tests/dating_v2_identity_contracts.sql` (header, section A)
- Modify: `supabase/tests/dating_exclusion_wiring_test.sql`, `supabase/tests/dating_mode_contracts.sql` (fixture phones on `auth.users`), `scripts/local_pg_grants.sql`

**Interfaces:**
- Consumes: `public.dating_phone_hmac(text)`, `users.phone_released_at`, `users.parked_phone_hmac`, `consume_fresh_start`, `mark_fresh_start_parked`, `private.seal_fresh_start`, `end_relationship`, Task 1's `before/`.
- Produces: `public.dating_phone_canonical(text) → text` ('+' || digits, NULL without digits), `public.dating_phone_hmac_for_user(uuid) → text` (both server-only); the re-created recorder, predicate and backfill; trigger `relationship_dating_guard` → `sync_dating_pause_on_relationship()`.

- [ ] **Step 1: Write the failing contract**

Create `supabase/tests/dating_v2_identity_contracts.sql` with exactly:

```sql
-- supabase/tests/dating_v2_identity_contracts.sql
-- Spec 2 W1 (§4.1, §4.2, §6.3, §7.1, §7.5; I-11, R-2, S-5): phone HMACs from
-- auth.users and parked accounts (A), block pairs and standing (B),
-- deletion carry-over (C) (W1a); encryption at rest (D1, D2: W1c);
-- never-introduce (E1), activation, pause, exit, the parked pause and the
-- generation key guard (E2) (W1d).
-- One BEGIN ... ROLLBACK. Run only on attune_spec3a, from the repo root:
--   psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/dating_v2_identity_contracts.sql
-- Fixture ids 5e2a0000-0000-0000-0000-0000000000NN; phones 15558700NN on
-- auth.users (Auth's form, no '+'), copied to public.users by Spec 1's
-- trigger. Every refusal is checked by its message.
BEGIN;

DO $$
BEGIN
  PERFORM set_config('app.settings.dating_exclusion_key', 'spec2-w1-contract-exclusion-key', true);
  PERFORM set_config('app.settings.fresh_start_key', 'spec2-w1-contract-fresh-start-key-0123456789', true);
END $$;

CREATE FUNCTION pg_temp.id(p_n text) RETURNS uuid LANGUAGE sql IMMUTABLE AS $$
  SELECT ('5e2a0000-0000-0000-0000-0000000000' || p_n)::uuid;
$$;

-- An adult account [p_n] on the Dating path, phone 15558700<p_n>.
CREATE FUNCTION pg_temp.person(p_n text) RETURNS uuid LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO auth.users (id, phone, phone_confirmed_at, created_at)
  VALUES (pg_temp.id(p_n), '15558700' || p_n, now() - interval '400 days', now() - interval '400 days');
  INSERT INTO public.users (id, phone, display_name, path, created_at, eula_accepted_at, eula_version)
  VALUES (pg_temp.id(p_n), '15558700' || p_n, 'Person ' || p_n, 'dating', now() - interval '400 days', now(), '2');
  INSERT INTO public.account_birthdates (user_id, birth_date)
  VALUES (pg_temp.id(p_n), current_date - interval '30 years');
  RETURN pg_temp.id(p_n);
END $$;

CREATE FUNCTION pg_temp.as_user(p_user uuid) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claim.sub', p_user::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
END $$;

CREATE FUNCTION pg_temp.as_owner() RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  RESET ROLE;
  PERFORM set_config('request.jwt.claim.sub', '', true);
  PERFORM set_config('request.jwt.claims', '', true);
END $$;

-- [p_sql] run as the service role: its text result, or 'ERROR: <message>'.
CREATE FUNCTION pg_temp.as_service(p_sql text) RETURNS text LANGUAGE plpgsql AS $$
DECLARE
  v text;
BEGIN
  EXECUTE 'SET LOCAL ROLE service_role';
  PERFORM set_config('request.jwt.claims', json_build_object('role', 'service_role')::text, true);
  BEGIN
    EXECUTE p_sql INTO v;
  EXCEPTION WHEN raise_exception OR insufficient_privilege OR not_null_violation THEN
    PERFORM pg_temp.as_owner();
    RETURN 'ERROR: ' || SQLERRM;
  END;
  PERFORM pg_temp.as_owner();
  RETURN v;
END $$;

-- [p_sql] run as [p_user]: NULL, or the message it raised.
CREATE FUNCTION pg_temp.err_as(p_user uuid, p_sql text) RETURNS text LANGUAGE plpgsql AS $$
BEGIN
  PERFORM pg_temp.as_user(p_user);
  EXECUTE p_sql;
  PERFORM pg_temp.as_owner();
  RETURN NULL;
EXCEPTION WHEN raise_exception OR insufficient_privilege OR invalid_parameter_value THEN
  PERFORM pg_temp.as_owner();
  RETURN SQLERRM;
END $$;

-- =====================================================================
-- A. (W1a) HMACs from auth.users; parked accounts; the relationship guard.
-- =====================================================================
DO $$
DECLARE
  v_a constant uuid := pg_temp.person('01');
  v_b constant uuid := pg_temp.person('02');
  v_park constant uuid := pg_temp.person('03');
  v_nokey constant uuid := pg_temp.person('04');
  v_c constant uuid := pg_temp.person('05');
  v_d constant uuid := pg_temp.person('06');
  v_before text;
  v_nonce text;
  v_got text;
  v_rel uuid;
BEGIN
  IF to_regprocedure('public.dating_phone_hmac_for_user(uuid)') IS NULL
     OR to_regprocedure('public.dating_phone_canonical(text)') IS NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the W1a HMAC helpers are missing';
  END IF;
  IF has_function_privilege('anon', 'public.dating_phone_hmac_for_user(uuid)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.dating_phone_hmac_for_user(uuid)', 'EXECUTE')
     OR has_function_privilege('service_role', 'public.dating_phone_hmac_for_user(uuid)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.dating_phone_canonical(text)', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an HMAC helper is executable outside the database';
  END IF;
  IF public.dating_phone_canonical('+233 (20) 000-0001') IS DISTINCT FROM '+233200000001'
     OR public.dating_phone_canonical('233200000001') IS DISTINCT FROM '+233200000001'
     OR public.dating_phone_canonical('no digits') IS NOT NULL
     OR public.dating_phone_canonical(NULL) IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: dating_phone_canonical is not ''+'' || digits';
  END IF;

  -- From Auth's number, in the canonical form.
  IF public.dating_phone_hmac_for_user(v_a) IS DISTINCT FROM public.dating_phone_hmac('+1555870001') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the HMAC is not dating_phone_hmac(''+'' || digits of auth.users.phone)';
  END IF;
  -- Tamper: rewriting public.users.phone changes nothing (mutant 1).
  UPDATE public.users SET phone = '+15558709999' WHERE id = v_a;
  IF public.dating_phone_hmac_for_user(v_a) IS DISTINCT FROM public.dating_phone_hmac('+1555870001') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the HMAC followed public.users.phone (tamper)';
  END IF;

  -- Former partners: ending records both directions from Auth's numbers,
  -- and tampering both mirrors afterwards keeps them excluded.
  INSERT INTO public.relationships (user_a, user_b, status) VALUES (v_a, v_b, 'active') RETURNING id INTO v_rel;
  PERFORM pg_temp.as_user(v_a);
  PERFORM public.end_relationship(v_rel);
  PERFORM pg_temp.as_owner();
  UPDATE public.users SET phone = '+15558709998' WHERE id = v_b;
  IF (SELECT count(*) FROM public.dating_former_partner_exclusions WHERE relationship_id = v_rel) IS DISTINCT FROM 2
     OR NOT public.dating_former_partner_excluded(v_a, v_b)
     OR NOT public.dating_former_partner_excluded(v_b, v_a) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the former-partner exclusion did not survive a tampered public.users.phone';
  END IF;
  -- Real number changes afterwards (Spec 1's verified change, in Auth), by
  -- both: still excluded both ways while both accounts exist.
  UPDATE auth.users SET phone = '15558709997' WHERE id = v_b;
  UPDATE auth.users SET phone = '15558709996' WHERE id = v_a;
  IF NOT public.dating_former_partner_excluded(v_a, v_b) OR NOT public.dating_former_partner_excluded(v_b, v_a) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a former partner''s new number undid the exclusion';
  END IF;

  -- Parked (I-11): consume_fresh_start writes the same HMAC the helper gives
  -- before the park; after Auth's +999 rewrite (before and after the mark)
  -- the helper still gives it, never the placeholder's (mutant 27).
  INSERT INTO public.account_activity (user_id, last_active_at) VALUES (v_park, now() - interval '200 days')
  ON CONFLICT (user_id) DO UPDATE SET last_active_at = EXCLUDED.last_active_at;
  v_before := public.dating_phone_hmac_for_user(v_park);
  v_nonce := private.seal_fresh_start(v_park, now());
  v_got := pg_temp.as_service(format('SELECT public.consume_fresh_start(%L)::text', v_nonce));
  IF v_got IS DISTINCT FROM v_park::text
     OR (SELECT parked_phone_hmac FROM public.users WHERE id = v_park) IS DISTINCT FROM v_before
     OR v_before IS NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: parked_phone_hmac is not the helper''s pre-park HMAC';
  END IF;
  UPDATE auth.users SET phone = '999123456789203' WHERE id = v_park;
  IF public.dating_phone_hmac_for_user(v_park) IS DISTINCT FROM v_before THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: between the +999 rewrite and the mark, the helper left the real number';
  END IF;
  v_got := pg_temp.as_service(format('SELECT public.mark_fresh_start_parked(%L)::text', v_park));
  IF v_got IS DISTINCT FROM ''
     OR (SELECT phone_released_at FROM public.users WHERE id = v_park) IS NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the park fixture did not complete';
  END IF;
  IF public.dating_phone_hmac_for_user(v_park) IS DISTINCT FROM v_before THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a parked account''s HMAC is not the pre-park one';
  END IF;
  -- Parked while the key was missing: NULL, never the +999 HMAC.
  UPDATE auth.users SET phone = '999123456789204' WHERE id = v_nokey;
  UPDATE public.users SET phone_released_at = now(), parked_phone_hmac = NULL WHERE id = v_nokey;
  IF public.dating_phone_hmac_for_user(v_nokey) IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a parked account without parked_phone_hmac got an HMAC (the +999 one)';
  END IF;

  -- The relationship guard (R6): the trigger calls the null-safe function,
  -- and active, paused and pending relationships all pause Dating.
  IF to_regprocedure('public.handle_relationship_dating_guard()') IS NOT NULL
     OR NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'relationship_dating_guard'
                      AND tgrelid = 'public.relationships'::regclass
                      AND tgfoid = 'public.sync_dating_pause_on_relationship()'::regprocedure) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: relationship_dating_guard is not wired to sync_dating_pause_on_relationship';
  END IF;
  INSERT INTO public.dating_enrollments (user_id, state) VALUES (v_c, 'active'), (v_d, 'active');
  INSERT INTO public.relationships (user_a, user_b, status) VALUES (v_c, v_d, 'active') RETURNING id INTO v_rel;
  IF (SELECT count(*) FROM public.dating_enrollments WHERE user_id IN (v_c, v_d) AND state = 'paused') IS DISTINCT FROM 2 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an active relationship did not pause Dating for both';
  END IF;
  UPDATE public.dating_enrollments SET state = 'active' WHERE user_id IN (v_c, v_d);
  UPDATE public.relationships SET status = 'paused', paused_at = now(), paused_by = v_c WHERE id = v_rel;
  IF (SELECT count(*) FROM public.dating_enrollments WHERE user_id IN (v_c, v_d) AND state = 'paused') IS DISTINCT FROM 2 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a paused relationship did not pause Dating for both';
  END IF;
  UPDATE public.dating_enrollments SET state = 'active' WHERE user_id IN (v_c, v_d);
  UPDATE public.relationships SET status = 'active', paused_at = NULL, paused_by = NULL WHERE id = v_rel;
  IF (SELECT count(*) FROM public.dating_enrollments WHERE user_id IN (v_c, v_d) AND state = 'paused') IS DISTINCT FROM 2 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: paused back to active did not pause Dating for both';
  END IF;
END $$;

DO $$ BEGIN RAISE NOTICE 'dating_v2_identity_contracts: all held'; END $$;
ROLLBACK;
```

- [ ] **Step 2: Run it to make sure it fails**

```bash
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/dating_v2_identity_contracts.sql 2>&1 | grep -E 'ERROR|all held' | head -1 | sed -E 's/^psql:[^ ]* //'
```

Expected: `ERROR:  CONTRACT VIOLATED: the W1a HMAC helpers are missing`.

- [ ] **Step 3: Write migration 1 and its twin**

Create `supabase/migrations/20261106100000_dating_v2_phone_hmac.sql` with exactly:

```sql
-- Spec 2 W1a, migration 1 (spec §4.9 W1a #1, §4.1, §6.3, §7.1; I-11):
-- every Dating phone HMAC comes from auth.users, never public.users.
--   * dating_phone_canonical(text): '+' || digits (NULL when there are none),
--     the exact form consume_fresh_start hashes (S1 W6a, I-11).
--   * dating_phone_hmac_for_user(uuid): auth.users.phone, canonical, through
--     the existing dating_phone_hmac(text); for a parked account (Spec 1's
--     users.phone_released_at set, or Auth already on the +999 placeholder)
--     Spec 1's users.parked_phone_hmac, or NULL. Never the +999 HMAC.
--   * record_dating_former_partner_exclusion, dating_former_partner_excluded
--     and backfill_dating_former_partner_exclusions re-created from their
--     live bodies (20260931130000, 20260712160000) with only the lines marked
--     "Spec 2 W1a": the recorder and the predicate read the helper; the
--     recorder also skips a relationship whose user_a is gone (a NULL
--     user_id would fail its NOT NULL); the backfill covers 'archived' too;
--     and the predicate also holds while both accounts still have their
--     ended or archived Attune relationship, so a later number change can't
--     undo the exclusion (plan P-4).
--   * Existing exclusions recomputed from ended and archived relationships
--     (only when dating_exclusion_key is set; otherwise a NOTICE says to run
--     the backfill after setting it).
--   * The relationship guard trigger now calls the null-safe
--     sync_dating_pause_on_relationship() (pending, active and paused);
--     handle_relationship_dating_guard() is dropped.
-- Nothing here is granted to a client. Grants in
-- 20261106100010_dating_v2_phone_hmac_grants.sql.
BEGIN;
SET LOCAL lock_timeout = '5s';

CREATE OR REPLACE FUNCTION public.dating_phone_canonical(p_phone text)
RETURNS text
LANGUAGE sql
IMMUTABLE
SET search_path = ''
AS $fn$
  SELECT CASE WHEN d.digits = '' THEN NULL ELSE '+' || d.digits END
    FROM (SELECT pg_catalog.regexp_replace(coalesce(p_phone, ''), '\D', '', 'g') AS digits) AS d;
$fn$;

CREATE OR REPLACE FUNCTION public.dating_phone_hmac_for_user(p_user uuid)
RETURNS text
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_released timestamptz;
  v_parked text;
  v_phone text;
BEGIN
  IF p_user IS NULL THEN
    RETURN NULL;
  END IF;
  SELECT u.phone_released_at, u.parked_phone_hmac INTO v_released, v_parked
    FROM public.users AS u WHERE u.id = p_user;
  SELECT a.phone INTO v_phone FROM auth.users AS a WHERE a.id = p_user;
  -- A parked account (I-11): the real number's HMAC, written by
  -- consume_fresh_start before the park, or NULL when the key was missing
  -- then. Never the HMAC of Spec 1's +999 placeholder, even in the moment
  -- between Auth's rewrite and mark_fresh_start_parked.
  IF v_released IS NOT NULL OR coalesce(v_phone, '') ~ '^\+?999[0-9]{12}$' THEN
    RETURN v_parked;
  END IF;
  RETURN public.dating_phone_hmac(public.dating_phone_canonical(v_phone));
END;
$fn$;

CREATE OR REPLACE FUNCTION public.record_dating_former_partner_exclusion(p_relationship_id uuid, p_internal boolean DEFAULT false)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_rel public.relationships%ROWTYPE;
  v_hmac_a text;  v_hmac_b text;
BEGIN
  IF NOT p_internal
     AND auth.role() IS NOT NULL
     AND auth.role() = 'authenticated' THEN
    RAISE EXCEPTION 'exclusion_write_is_backend_only' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_rel FROM public.relationships WHERE id = p_relationship_id;
  IF NOT FOUND OR v_rel.user_a IS NULL OR v_rel.user_b IS NULL THEN RETURN; END IF; -- Spec 2 W1a
  v_hmac_a := public.dating_phone_hmac_for_user(v_rel.user_a); -- Spec 2 W1a: auth.users
  v_hmac_b := public.dating_phone_hmac_for_user(v_rel.user_b); -- Spec 2 W1a: auth.users

  -- Protect A from B (store B's phone-HMAC against A) and vice-versa.
  IF v_hmac_b IS NOT NULL THEN
    INSERT INTO public.dating_former_partner_exclusions(user_id, excluded_phone_hmac, relationship_id)
    VALUES (v_rel.user_a, v_hmac_b, p_relationship_id)
    ON CONFLICT (user_id, excluded_phone_hmac) DO NOTHING;
  END IF;
  IF v_hmac_a IS NOT NULL THEN
    INSERT INTO public.dating_former_partner_exclusions(user_id, excluded_phone_hmac, relationship_id)
    VALUES (v_rel.user_b, v_hmac_a, p_relationship_id)
    ON CONFLICT (user_id, excluded_phone_hmac) DO NOTHING;
  END IF;
END;
$function$;

CREATE OR REPLACE FUNCTION public.dating_former_partner_excluded(p_user_a uuid, p_user_b uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_hmac_a text;  v_hmac_b text;
BEGIN
  v_hmac_a := public.dating_phone_hmac_for_user(p_user_a); -- Spec 2 W1a: auth.users
  v_hmac_b := public.dating_phone_hmac_for_user(p_user_b); -- Spec 2 W1a: auth.users

  -- A is protected from B's phone, OR B is protected from A's phone.
  RETURN
    EXISTS ( -- Spec 2 W1a: and while both accounts exist, their ended Attune relationship itself
      SELECT 1 FROM public.relationships r
      WHERE r.status IN ('ended', 'archived')
        AND ((r.user_a = p_user_a AND r.user_b = p_user_b) OR (r.user_a = p_user_b AND r.user_b = p_user_a)))
    OR
    (v_hmac_b IS NOT NULL AND EXISTS (
       SELECT 1 FROM public.dating_former_partner_exclusions e
       WHERE e.user_id = p_user_a AND e.excluded_phone_hmac = v_hmac_b))
    OR
    (v_hmac_a IS NOT NULL AND EXISTS (
       SELECT 1 FROM public.dating_former_partner_exclusions e
       WHERE e.user_id = p_user_b AND e.excluded_phone_hmac = v_hmac_a));
END;
$function$;

CREATE OR REPLACE FUNCTION public.backfill_dating_former_partner_exclusions()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_rel record;
  v_done int := 0;
BEGIN
  IF public.app_setting('dating_exclusion_key') IS NULL THEN
    RAISE EXCEPTION 'dating_exclusion_key is not set; store it in Vault first';
  END IF;

  FOR v_rel IN
    SELECT id FROM public.relationships
    WHERE status IN ('ended', 'archived') AND user_b IS NOT NULL -- Spec 2 W1a: archived too
  LOOP
    PERFORM public.record_dating_former_partner_exclusion(v_rel.id, true);
    v_done := v_done + 1;
  END LOOP;

  RETURN v_done;
END;
$function$;

-- Recompute every exclusion that still has its relationship, from
-- auth.users (fresh start: the old rows were keyed by public.users.phone).
DO $do$
BEGIN
  IF public.app_setting('dating_exclusion_key') IS NULL THEN
    RAISE NOTICE 'dating_v2_phone_hmac: dating_exclusion_key is not set, so exclusions were not recomputed; run select public.backfill_dating_former_partner_exclusions(); after setting it';
    RETURN;
  END IF;
  DELETE FROM public.dating_former_partner_exclusions AS e
   USING public.relationships AS r
   WHERE e.relationship_id = r.id AND r.status IN ('ended', 'archived');
  PERFORM public.backfill_dating_former_partner_exclusions();
END
$do$;

-- The guard trigger calls the null-safe function (it covers paused too).
CREATE OR REPLACE TRIGGER relationship_dating_guard
  AFTER INSERT OR UPDATE OF status, user_b ON public.relationships
  FOR EACH ROW EXECUTE FUNCTION public.sync_dating_pause_on_relationship();
DROP FUNCTION IF EXISTS public.handle_relationship_dating_guard();

REVOKE ALL ON FUNCTION public.dating_phone_canonical(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.dating_phone_hmac_for_user(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.dating_former_partner_excluded(uuid, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.record_dating_former_partner_exclusion(uuid, boolean) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.backfill_dating_former_partner_exclusions() FROM PUBLIC, anon, authenticated;

COMMIT;
```

Create `supabase/migrations/20261106100010_dating_v2_phone_hmac_grants.sql` with exactly:

```sql
-- Spec 2 W1a: grants for 20261106100000_dating_v2_phone_hmac.sql. The HMAC
-- helpers are the database's own; the recorder and the backfill stay the
-- service role's (as live); no client reaches any of them.
BEGIN;
SET LOCAL lock_timeout = '5s';
REVOKE ALL ON FUNCTION public.dating_phone_canonical(text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.dating_phone_hmac_for_user(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.dating_former_partner_excluded(uuid, uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.record_dating_former_partner_exclusion(uuid, boolean) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.backfill_dating_former_partner_exclusions() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.record_dating_former_partner_exclusion(uuid, boolean) TO service_role;
GRANT EXECUTE ON FUNCTION public.backfill_dating_former_partner_exclusions() TO service_role;
COMMIT;
```

- [ ] **Step 4: Apply each file twice; diff the three functions against their live bodies**

```bash
for i in 1 2; do
  for f in 20261106100000_dating_v2_phone_hmac 20261106100010_dating_v2_phone_hmac_grants; do
    psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/migrations/$f.sql > /dev/null 2>&1; echo "$f exit=$?"
  done
done
```

```bash
D=.superpowers/sdd/2026-11-06-spec2-w1
for sig in 'public.record_dating_former_partner_exclusion(uuid,boolean)' 'public.dating_former_partner_excluded(uuid,uuid)' 'public.backfill_dating_former_partner_exclusions()'; do
  echo "== $sig"
  diff "$D/before/$sig.sql" <(psql -X -d attune_spec3a -Atc "select pg_get_functiondef('$sig'::regprocedure)") | grep '^[<>]'
done
```

Expected: four `exit=0` lines (each run of migration 1 also prints the NOTICE that `dating_exclusion_key` is not set when it isn't); then exactly:

```text
== public.record_dating_former_partner_exclusion(uuid,boolean)
<   v_phone_a text; v_phone_b text;
<   IF NOT FOUND OR v_rel.user_b IS NULL THEN RETURN; END IF;
>   IF NOT FOUND OR v_rel.user_a IS NULL OR v_rel.user_b IS NULL THEN RETURN; END IF; -- Spec 2 W1a
>   v_hmac_a := public.dating_phone_hmac_for_user(v_rel.user_a); -- Spec 2 W1a: auth.users
>   v_hmac_b := public.dating_phone_hmac_for_user(v_rel.user_b); -- Spec 2 W1a: auth.users
<   SELECT phone INTO v_phone_a FROM public.users WHERE id = v_rel.user_a;
<   SELECT phone INTO v_phone_b FROM public.users WHERE id = v_rel.user_b;
<   v_hmac_a := public.dating_phone_hmac(v_phone_a);
<   v_hmac_b := public.dating_phone_hmac(v_phone_b);
< 
== public.dating_former_partner_excluded(uuid,uuid)
<   v_phone_a text; v_phone_b text;
<   SELECT phone INTO v_phone_a FROM public.users WHERE id = p_user_a;
<   SELECT phone INTO v_phone_b FROM public.users WHERE id = p_user_b;
<   v_hmac_a := public.dating_phone_hmac(v_phone_a);
<   v_hmac_b := public.dating_phone_hmac(v_phone_b);
>   v_hmac_a := public.dating_phone_hmac_for_user(p_user_a); -- Spec 2 W1a: auth.users
>   v_hmac_b := public.dating_phone_hmac_for_user(p_user_b); -- Spec 2 W1a: auth.users
>     EXISTS ( -- Spec 2 W1a: and while both accounts exist, their ended Attune relationship itself
>       SELECT 1 FROM public.relationships r
>       WHERE r.status IN ('ended', 'archived')
>         AND ((r.user_a = p_user_a AND r.user_b = p_user_b) OR (r.user_a = p_user_b AND r.user_b = p_user_a)))
>     OR
== public.backfill_dating_former_partner_exclusions()
<     WHERE status = 'ended' AND user_b IS NOT NULL
>     WHERE status IN ('ended', 'archived') AND user_b IS NOT NULL -- Spec 2 W1a: archived too
```

- [ ] **Step 5: The two existing contracts that pin the old source fail; fix their fixtures**

```bash
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/dating_exclusion_wiring_test.sql 2>&1 | grep -E 'ERROR|all held' | head -1 | sed -E 's/^psql:[^ ]* //'
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/dating_mode_contracts.sql 2>&1 | grep -E 'ERROR|all held' | head -1 | sed -E 's/^psql:[^ ]* //'
```

Expected: `ERROR:  expected 2 exclusion rows after ending, got 0` and `ERROR:  C4: expected 2 exclusion rows, got 0` (their fixtures put the phone only on `public.users`, the mirror the HMAC no longer reads). Create `.superpowers/sdd/2026-11-06-spec2-w1/edit_wiring.py` with exactly:

```python
import pathlib
p = pathlib.Path('supabase/tests/dating_exclusion_wiring_test.sql')
s = p.read_text()
edits = [
("""  INSERT INTO auth.users(id) VALUES (a), (b) ON CONFLICT DO NOTHING;
  INSERT INTO public.users(id, phone, display_name)
  VALUES (a, '+15550000001', 'A'), (b, '+15550000002', 'B')
  ON CONFLICT (id) DO UPDATE SET phone = EXCLUDED.phone;
""",
"""  -- Spec 2 W1a: the recorder reads Auth's number (auth.users.phone, Auth's
  -- form without '+'), never public.users.phone.
  INSERT INTO auth.users(id, phone, phone_confirmed_at)
  VALUES (a, '15550000001', now()), (b, '15550000002', now()) ON CONFLICT DO NOTHING;
  INSERT INTO public.users(id, phone, display_name)
  VALUES (a, '15550000001', 'A'), (b, '15550000002', 'B')
  ON CONFLICT (id) DO UPDATE SET phone = EXCLUDED.phone;
"""),
("""  IF v <> 2 THEN
    RAISE EXCEPTION 'expected 2 exclusion rows after ending, got %', v;
  END IF;
END $$;
""",
"""  IF v <> 2 THEN
    RAISE EXCEPTION 'expected 2 exclusion rows after ending, got %', v;
  END IF;

  -- Spec 2 W1a tamper case: rewriting public.users.phone (it is only a
  -- mirror of Auth's) changes nothing; the pair stays excluded both ways.
  UPDATE public.users SET phone = '+15559990001' WHERE id = a;
  UPDATE public.users SET phone = '+15559990002' WHERE id = b;
  IF NOT public.dating_former_partner_excluded(a, b)
     OR NOT public.dating_former_partner_excluded(b, a) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a tampered public.users.phone undid the former-partner exclusion';
  END IF;
END $$;
"""),
("""  INSERT INTO auth.users(id) VALUES (a), (b) ON CONFLICT DO NOTHING;
  INSERT INTO public.users(id, phone, display_name)
  VALUES (a, '+15550000003', 'C'), (b, '+15550000004', 'D')
  ON CONFLICT (id) DO UPDATE SET phone = EXCLUDED.phone;
""",
"""  INSERT INTO auth.users(id, phone, phone_confirmed_at)
  VALUES (a, '15550000003', now()), (b, '15550000004', now()) ON CONFLICT DO NOTHING;
  INSERT INTO public.users(id, phone, display_name)
  VALUES (a, '15550000003', 'C'), (b, '15550000004', 'D')
  ON CONFLICT (id) DO UPDATE SET phone = EXCLUDED.phone;
"""),
]
for a, b in edits:
    assert s.count(a) == 1, a[:60]
    s = s.replace(a, b)
p.write_text(s)
print('dating_exclusion_wiring_test.sql: 3 edits')
```

Create `.superpowers/sdd/2026-11-06-spec2-w1/edit_dating_mode_w1a.py` with exactly:

```python
import pathlib
p = pathlib.Path('supabase/tests/dating_mode_contracts.sql')
s = p.read_text()
a = """  INSERT INTO auth.users (
    id, aud, role, email, encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data, created_at, updated_at
  ) VALUES
    (a, 'authenticated','authenticated','+233200000001','x',now(),'{}','{}',now(),now()),
    (b, 'authenticated','authenticated','+233200000002','x',now(),'{}','{}',now(),now()),
    (c, 'authenticated','authenticated','+233200000003','x',now(),'{}','{}',now(),now()),
    (d, 'authenticated','authenticated','+233200000004','x',now(),'{}','{}',now(),now())
  ON CONFLICT (id) DO NOTHING;
"""
b = """  -- Spec 2 W1a: Dating HMACs read Auth's number, so the fixture's phones
  -- are on auth.users (Auth's form, no '+'), confirmed.
  INSERT INTO auth.users (
    id, aud, role, email, encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
    phone, phone_confirmed_at
  ) VALUES
    (a, 'authenticated','authenticated','+233200000001','x',now(),'{}','{}',now(),now(),'233200000001',now()),
    (b, 'authenticated','authenticated','+233200000002','x',now(),'{}','{}',now(),now(),'233200000002',now()),
    (c, 'authenticated','authenticated','+233200000003','x',now(),'{}','{}',now(),now(),'233200000003',now()),
    (d, 'authenticated','authenticated','+233200000004','x',now(),'{}','{}',now(),now(),'233200000004',now())
  ON CONFLICT (id) DO NOTHING;
"""
assert s.count(a) == 1
s = s.replace(a, b)
p.write_text(s)
print('dating_mode_contracts.sql: 1 edit (W1a)')
```

```bash
D=.superpowers/sdd/2026-11-06-spec2-w1
python3 -I $D/edit_wiring.py && python3 -I $D/edit_dating_mode_w1a.py
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/dating_exclusion_wiring_test.sql 2>&1 | grep -E 'ERROR|all held' | head -1 | sed -E 's/^psql:[^ ]* //'; echo "wiring exit=${PIPESTATUS[0]}"
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/dating_mode_contracts.sql 2>&1 | grep -E 'ERROR|all held' | head -1 | sed -E 's/^psql:[^ ]* //'; echo "dating_mode exit=${PIPESTATUS[0]}"
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/dating_v2_identity_contracts.sql 2>&1 | grep -E 'ERROR|all held' | head -1 | sed -E 's/^psql:[^ ]* //'
```

Expected: `dating_exclusion_wiring_test.sql: 3 edits`, `dating_mode_contracts.sql: 1 edit (W1a)`, `wiring exit=0`, `dating_mode exit=0`, `NOTICE:  dating_v2_identity_contracts: all held`.

- [ ] **Step 6: Mutation checks (mutants 1 and 27; each must turn the contract red)**

Create `.superpowers/sdd/2026-11-06-spec2-w1/mut_T2.py` with exactly:

```python
MUTS = {
 'exclusion_by_number_only': ('MULTI', [("""    EXISTS ( -- Spec 2 W1a: and while both accounts exist, their ended Attune relationship itself
      SELECT 1 FROM public.relationships r
      WHERE r.status IN ('ended', 'archived')
        AND ((r.user_a = p_user_a AND r.user_b = p_user_b) OR (r.user_a = p_user_b AND r.user_b = p_user_a)))
    OR
""", "")]),
 'hmac_from_public_users': ("  SELECT a.phone INTO v_phone FROM auth.users AS a WHERE a.id = p_user;", "  SELECT u.phone INTO v_phone FROM public.users AS u WHERE u.id = p_user;"),
 'parked_ignored': ("  IF v_released IS NOT NULL OR coalesce(v_phone, '') ~ '^\\+?999[0-9]{12}$' THEN\n    RETURN v_parked;\n  END IF;\n", ""),
 'parked_only_after_mark': ("  IF v_released IS NOT NULL OR coalesce(v_phone, '') ~ '^\\+?999[0-9]{12}$' THEN", "  IF v_released IS NOT NULL THEN"),
 'parked_falls_back_to_placeholder': ("    RETURN v_parked;", "    RETURN coalesce(v_parked, public.dating_phone_hmac(public.dating_phone_canonical(v_phone)));"),
 'guard_skips_paused': ('RAW', """CREATE OR REPLACE FUNCTION public.sync_dating_pause_on_relationship() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
BEGIN
  IF NEW.status IN ('pending', 'active') THEN
    IF NEW.user_a IS NOT NULL THEN PERFORM public.pause_dating_for_relationship_user(NEW.user_a); END IF;
    IF NEW.user_b IS NOT NULL THEN PERFORM public.pause_dating_for_relationship_user(NEW.user_b); END IF;
  END IF;
  RETURN NEW;
END;
$function$;"""),
}
```

```bash
D=.superpowers/sdd/2026-11-06-spec2-w1
python3 -I $D/mutate.py supabase/migrations/20261106100000_dating_v2_phone_hmac.sql supabase/tests/dating_v2_identity_contracts.sql $D/mut_T2.py $D
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/dating_v2_identity_contracts.sql 2>&1 | grep -E 'ERROR|all held' | head -1 | sed -E 's/^psql:[^ ]* //'
```

Expected:

- `exclusion_by_number_only`: `ERROR:  CONTRACT VIOLATED: a former partner's new number undid the exclusion`
- `hmac_from_public_users`: `ERROR:  CONTRACT VIOLATED: the HMAC followed public.users.phone (tamper)`
- `parked_ignored`: `ERROR:  CONTRACT VIOLATED: between the +999 rewrite and the mark, the helper left the real number`
- `parked_only_after_mark`: `ERROR:  CONTRACT VIOLATED: between the +999 rewrite and the mark, the helper left the real number`
- `parked_falls_back_to_placeholder`: `ERROR:  CONTRACT VIOLATED: a parked account without parked_phone_hmac got an HMAC (the +999 one)`
- `guard_skips_paused`: `ERROR:  CONTRACT VIOLATED: a paused relationship did not pause Dating for both`

then `NOTICE:  dating_v2_identity_contracts: all held` (nothing persisted).

- [ ] **Step 7: The local harness (edit only, never run)**

`scripts/local_pg_grants.sql`: append after the last line (`\i supabase/migrations/20261104130010_opinion_remove_own_grants.sql`), exactly:

```sql

-- Spec 2 W1a: the Dating HMAC helpers are the database's own; the
-- exclusion recorder and backfill stay the service role's.
\i supabase/migrations/20261106100010_dating_v2_phone_hmac_grants.sql
```

```bash
python3 -I - <<'PY'
import pathlib
p = pathlib.Path('scripts/local_pg_grants.sql')
s = p.read_text()
assert s.endswith('\\i supabase/migrations/20261104130010_opinion_remove_own_grants.sql' + chr(10))
p.write_text(s + chr(10) + "-- Spec 2 W1a: the Dating HMAC helpers are the database's own; the\n-- exclusion recorder and backfill stay the service role's." + chr(10) + '\\i supabase/migrations/20261106100010_dating_v2_phone_hmac_grants.sql' + chr(10))
print('local_pg_grants.sql: one \\i block added')
PY
```

- [ ] **Step 8: Run tests (the relationship writers' contracts, R6)**

```bash
for t in relationship_lifecycle_contracts relationship_lifecycle_hardening_contracts relationships_lockdown_contracts invite_v2_contracts account_deletion_contracts dormancy_contracts; do
  psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/$t.sql >/dev/null 2>&1 && echo "PASS $t" || echo "FAIL $t"
done
```

Expected: six `PASS` lines (the guard now fires through `sync_dating_pause_on_relationship` for every relationship writer).

### Task 3: Migration 2: what survives deletion; every Dating grant re-asserted; the canaries; the secret scan (§4.9 W1a #2, §4.5, S-5, R22; P-6-P-10, P-12)

**Files:**
- Create: `supabase/migrations/20261106110000_dating_v2_enforcement_survival.sql`, `…110010_dating_v2_enforcement_survival_grants.sql`
- Create: `supabase/tests/dating_rls_canary.sql`, `supabase/tests/storage_bucket_policies.sql`
- Modify: `supabase/tests/dating_v2_identity_contracts.sql` (section B), `supabase/tests/service_role_grants_test.sql` (the S-5 exemption), `.github/workflows/tests.yml` (job `repo-guards`), `scripts/local_pg_grants.sql`

**Interfaces:**
- Consumes: Task 2's `dating_phone_hmac_for_user`; the live `block_dating_user`, `dating_account_in_good_standing`; `account_holds`; `place_account_hold`.
- Produces: `public.enforcement_records`, `public.dating_block_hmacs` (service role DML; no client); `dating_reports.target_phone_hmac`, nullable `SET NULL` reporter/target; `dating_matches` members and `introduction_id` nullable `SET NULL`, `closed_reason`, `evidence_until`; `block_dating_user` writes the HMAC pair and closes with `blocked` + 30 days; standing reads enforcement records and holds; the canary allow-list (extended by every later task).

- [ ] **Step 1: Write the failing contract section and the two new contracts**

Create `.superpowers/sdd/2026-11-06-spec2-w1/identity_B.sql` with exactly:

```sql
-- A pair's introduction ([p_state]), with the two snapshots today's schema
-- needs (dropped in W5a).
CREATE FUNCTION pg_temp.intro(p_a uuid, p_b uuid, p_state text DEFAULT 'presented') RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE
  v_low uuid;
  v_high uuid;
  v_id uuid;
BEGIN
  INSERT INTO public.dating_feature_snapshots (user_id, algorithm_version)
  VALUES (least(p_a, p_b), 'spec2-w1-contract') RETURNING id INTO v_low;
  INSERT INTO public.dating_feature_snapshots (user_id, algorithm_version)
  VALUES (greatest(p_a, p_b), 'spec2-w1-contract') RETURNING id INTO v_high;
  INSERT INTO public.dating_introductions (pair_key, user_low_id, user_high_id, display_band, state,
                                           algorithm_version, snapshot_low_id, snapshot_high_id, internal_score)
  VALUES (public.dating_pair_key(p_a, p_b), least(p_a, p_b), greatest(p_a, p_b), 'some_shared_ground', p_state,
          'spec2-w1-contract', v_low, v_high, 0.5)
  RETURNING id INTO v_id;
  RETURN v_id;
END $$;

-- An active match between [p_a] and [p_b] (with its introduction).
CREATE FUNCTION pg_temp.match(p_a uuid, p_b uuid) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE
  v_id uuid;
BEGIN
  INSERT INTO public.dating_matches (introduction_id, user_low_id, user_high_id, state)
  VALUES (pg_temp.intro(p_a, p_b, 'matched'), least(p_a, p_b), greatest(p_a, p_b), 'active')
  RETURNING id INTO v_id;
  RETURN v_id;
END $$;

-- =====================================================================
-- B. (W1a) Block pairs by HMAC; standing reads restrictions, enforcement
--    records and Spec 1's holds; the new tables are no client's (S-5).
-- =====================================================================
DO $$
DECLARE
  v_a constant uuid := pg_temp.person('10');
  v_b constant uuid := pg_temp.person('11');
  v_c constant uuid := pg_temp.person('12');
  v_m uuid;
  v_t text;
BEGIN
  FOREACH v_t IN ARRAY ARRAY['public.enforcement_records', 'public.dating_block_hmacs'] LOOP
    IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid = v_t::regclass)
       OR has_table_privilege('anon', v_t, 'SELECT') OR has_table_privilege('authenticated', v_t, 'SELECT')
       OR has_table_privilege('authenticated', v_t, 'INSERT')
       OR NOT has_table_privilege('service_role', v_t, 'SELECT') THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: % has the wrong RLS or grants', v_t;
    END IF;
  END LOOP;
  FOREACH v_t IN ARRAY ARRAY['public.dating_introductions', 'public.dating_interest_actions', 'public.dating_matches'] LOOP
    IF has_table_privilege('service_role', v_t, 'SELECT') OR has_table_privilege('authenticated', v_t, 'SELECT') THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: % is readable outside definer functions (S-5)', v_t;
    END IF;
  END LOOP;

  -- Blocking writes the HMAC pair and closes the match with its reason
  -- and evidence window.
  v_m := pg_temp.match(v_a, v_b);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_a, 'role', 'authenticated')::text, true);
  PERFORM public.block_dating_user('spec2-w1-block-0001', v_b);
  PERFORM pg_temp.as_owner();
  IF NOT EXISTS (SELECT 1 FROM public.dating_block_hmacs
                  WHERE blocker_hmac = public.dating_phone_hmac_for_user(v_a)
                    AND blocked_hmac = public.dating_phone_hmac_for_user(v_b)
                    AND purge_after IS NULL) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: block_dating_user wrote no HMAC pair';
  END IF;
  IF (SELECT state || '/' || coalesce(closed_reason, '-') FROM public.dating_matches WHERE id = v_m) IS DISTINCT FROM 'blocked/blocked'
     OR (SELECT evidence_until FROM public.dating_matches WHERE id = v_m)
          NOT BETWEEN now() + interval '29 days' AND now() + interval '31 days' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the blocked match has no closed_reason or 30-day evidence window';
  END IF;

  -- Standing.
  IF NOT public.dating_account_in_good_standing(v_c) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a clean account is not in good standing';
  END IF;
  INSERT INTO public.enforcement_records (phone_hmac, scope, restriction_type, effect_until, purge_after)
  VALUES (public.dating_phone_hmac_for_user(v_c), 'dating', 'suspended', NULL, now() + interval '2 years');
  IF public.dating_account_in_good_standing(v_c) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: standing ignores an enforcement record for the number';
  END IF;
  UPDATE public.enforcement_records SET effect_until = now() - interval '1 minute'
   WHERE phone_hmac = public.dating_phone_hmac_for_user(v_c);
  IF NOT public.dating_account_in_good_standing(v_c) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an enforcement record past effect_until still counts';
  END IF;
  UPDATE public.enforcement_records SET scope = 'opinions', effect_until = NULL
   WHERE phone_hmac = public.dating_phone_hmac_for_user(v_c);
  IF NOT public.dating_account_in_good_standing(v_c) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an Opinions-scope record closed Dating';
  END IF;
  DELETE FROM public.enforcement_records WHERE phone_hmac = public.dating_phone_hmac_for_user(v_c);
  PERFORM public.place_account_hold(v_c, 'safety_review', 'spec2-w1-contract');
  IF public.dating_account_in_good_standing(v_c) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: standing ignores an unresolved safety_review hold';
  END IF;
  UPDATE public.account_holds SET resolved_at = now(), resolved_by = 'contract' WHERE user_id = v_c;
  PERFORM public.place_account_hold(v_c, 'age_review', 'spec2-w1-contract');
  IF public.dating_account_in_good_standing(v_c) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: standing ignores an unresolved age_review hold';
  END IF;
  UPDATE public.account_holds SET resolved_at = now(), resolved_by = 'contract' WHERE user_id = v_c;
  IF NOT public.dating_account_in_good_standing(v_c) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: resolved holds still close Dating';
  END IF;
END $$;
```

Create `supabase/tests/dating_rls_canary.sql` with exactly:

```sql
-- supabase/tests/dating_rls_canary.sql
-- Spec 2 §4.5, §7.1 (S-4, S-5): every Dating relation and function has
-- exactly its allow-listed client grants, so a new Dating table or RPC
-- cannot ship readable or callable by accident. In scope: public
-- relations named dating_* plus country_safety_config, enforcement_records,
-- couple_how_we_met and law_enforcement_requests; public and private
-- functions whose name contains "dating" or "date_reflection", plus
-- publish_country_config and apply_same_gender_switch.
-- For each relation: anon's and authenticated's table privileges must equal
-- the list exactly, PUBLIC has none, RLS is on, and service_role's
-- SELECT/INSERT/UPDATE/DELETE equal the list (hosted projects also give it
-- TRUNCATE/REFERENCES/TRIGGER by default, which this file ignores).
-- For each function: PUBLIC has no EXECUTE and anon's and authenticated's
-- EXECUTE equal the list (service_role is checked only where the spec forbids
-- it: S-4's decrypt rule below). Every later batch adds its rows here.
-- One BEGIN ... ROLLBACK. Run only on attune_spec3a:
--   psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/dating_rls_canary.sql
BEGIN;

CREATE TEMP TABLE allowed_rel (
  name text PRIMARY KEY,
  anon text NOT NULL DEFAULT '',
  authenticated text NOT NULL DEFAULT '',
  service_dml text NOT NULL DEFAULT ''
) ON COMMIT DROP;
CREATE TEMP TABLE allowed_fn (
  sig text PRIMARY KEY,
  clients text NOT NULL DEFAULT ''
) ON COMMIT DROP;

-- ---------------------------------------------------------------------
-- W1a: the Dating tables of today, and the two survival tables.
-- (service_dml lists SELECT, INSERT, UPDATE, DELETE held by service_role.)
-- ---------------------------------------------------------------------
INSERT INTO allowed_rel (name, authenticated, service_dml) VALUES
  ('dating_account_restrictions', '', 'DELETE,INSERT,SELECT,UPDATE'),
  ('dating_age_verifications', '', 'DELETE,INSERT,SELECT,UPDATE'),
  ('dating_algorithm_configs', '', 'DELETE,INSERT,SELECT,UPDATE'),
  ('dating_block_hmacs', '', 'DELETE,INSERT,SELECT,UPDATE'),
  ('dating_blocks', '', 'DELETE,INSERT,SELECT,UPDATE'),
  ('dating_consent_events', 'SELECT', 'DELETE,INSERT,SELECT,UPDATE'),
  ('dating_date_reflections', '', 'DELETE,INSERT,SELECT,UPDATE'),
  ('dating_enrollments', 'SELECT', 'DELETE,INSERT,SELECT,UPDATE'),
  ('dating_feature_snapshots', '', 'DELETE,INSERT,SELECT,UPDATE'),
  ('dating_former_partner_exclusions', '', 'DELETE,INSERT,SELECT,UPDATE'),
  ('dating_generation_runs', '', 'DELETE,INSERT,SELECT,UPDATE'),
  ('dating_interest_actions', '', ''),
  ('dating_introductions', '', ''),
  ('dating_matches', '', ''),
  ('dating_photo_moderation_config', '', 'DELETE,INSERT,SELECT,UPDATE'),
  ('dating_photo_moderation_outbox', '', 'DELETE,INSERT,SELECT,UPDATE'),
  ('dating_photo_upload_intents', 'SELECT', 'DELETE,INSERT,SELECT,UPDATE'),
  ('dating_preferences', 'SELECT', 'DELETE,INSERT,SELECT,UPDATE'),
  ('dating_profile_photos', 'SELECT', 'DELETE,INSERT,SELECT,UPDATE'),
  ('dating_profiles', 'SELECT', 'DELETE,INSERT,SELECT,UPDATE'),
  ('dating_rate_limits', '', 'DELETE,INSERT,SELECT,UPDATE'),
  ('dating_reports', '', 'DELETE,INSERT,SELECT,UPDATE'),
  ('dating_rpc_idempotency', '', 'DELETE,INSERT,SELECT,UPDATE'),
  ('enforcement_records', '', 'DELETE,INSERT,SELECT,UPDATE');

INSERT INTO allowed_fn (sig, clients) VALUES
  ('act_on_dating_introduction(text,uuid,text)', 'authenticated'),
  ('activate_dating_profile(text)', 'authenticated'),
  ('backfill_dating_former_partner_exclusions()', ''),
  ('begin_dating_enrollment(text,text)', 'authenticated'),
  ('block_dating_introduction(text,uuid)', 'authenticated'),
  ('block_dating_match(text,uuid)', 'authenticated'),
  ('block_dating_user(text,uuid)', ''),
  ('build_dating_feature_snapshot(uuid,text)', ''),
  ('bump_dating_enrollment_version()', ''),
  ('bump_dating_profile_version()', ''),
  ('check_dating_rate_limit(text,integer,interval)', ''),
  ('claim_dating_idempotency(text,text)', ''),
  ('claim_dating_photo_jobs(integer,uuid)', ''),
  ('create_dating_photo_upload_intent(text)', 'authenticated'),
  ('dating_account_in_good_standing(uuid)', ''),
  ('dating_age_gate_holds(uuid)', ''),
  ('dating_alignment_reasons(jsonb,jsonb)', ''),
  ('dating_alignment_score(jsonb,jsonb,jsonb)', ''),
  ('dating_candidate_is_current(uuid)', ''),
  ('dating_component_similarity(numeric,numeric)', ''),
  ('dating_flag_enabled(text)', ''),
  ('dating_former_partner_excluded(uuid,uuid)', ''),
  ('dating_has_historical_consent(uuid)', ''),
  ('dating_has_relationship(uuid)', ''),
  ('dating_healing_gates_hold(uuid)', ''),
  ('dating_normalize_scalar(numeric,numeric,numeric)', ''),
  ('dating_pair_key(uuid,uuid)', ''),
  ('dating_pair_passes_hard_filters(uuid,uuid)', ''),
  ('dating_phone_canonical(text)', ''),
  ('dating_phone_hmac(text)', ''),
  ('dating_phone_hmac_for_user(uuid)', ''),
  ('dating_photos_queue_media_before_delete()', ''),
  ('dating_profile_ready(uuid)', ''),
  ('dating_set_similarity(jsonb,jsonb)', ''),
  ('delete_dating_profile(text)', 'authenticated'),
  ('delete_dating_profile_photo(uuid)', 'authenticated'),
  ('delete_private_date_reflection(text,uuid)', 'authenticated'),
  ('enforce_dating_age_verification_change()', ''),
  ('enforce_dating_lifecycle_gates()', ''),
  ('enforce_dating_restriction_change()', ''),
  ('enqueue_dating_photo_processing()', ''),
  ('exit_dating_mode(text)', 'authenticated'),
  ('expire_dating_introductions()', ''),
  ('generate_dating_candidates_for_user(uuid,text,text,text)', ''),
  ('get_dating_eligibility()', 'authenticated'),
  ('get_dating_operational_health()', ''),
  ('get_my_dating_introductions(integer)', 'authenticated'),
  ('get_my_dating_matches(integer)', 'authenticated'),
  ('insert_dating_profile_photo(uuid,smallint)', 'authenticated'),
  ('invalidate_dating_for_user(uuid,text)', ''),
  ('invalidate_dating_on_photo_change()', ''),
  ('invalidate_dating_on_profile_change()', ''),
  ('list_dating_profile_photos()', 'authenticated'),
  ('pause_dating_for_relationship_user(uuid)', ''),
  ('pause_dating_mode(text)', 'authenticated'),
  ('private.dating_home_summary(uuid)', ''),
  ('private.dating_open_countries()', ''),
  ('record_dating_consent(text,text,text,text,jsonb)', 'authenticated'),
  ('record_dating_date_reflection(text,uuid,text,text)', ''),
  ('record_dating_former_partner_exclusion(uuid,boolean)', ''),
  ('recover_stale_dating_photo_jobs()', ''),
  ('report_dating_introduction(text,uuid,text,text)', 'authenticated'),
  ('report_dating_match(text,uuid,text,text)', 'authenticated'),
  ('resolve_dating_introduction_target(uuid)', ''),
  ('resolve_dating_match_target(uuid)', ''),
  ('resolve_dating_verification_review(uuid,text)', ''),
  ('revoke_dating_age_verification(uuid)', ''),
  ('run_dating_candidate_generation(text)', ''),
  ('save_dating_profile_draft(text,text,text,text,text,integer,integer)', 'authenticated'),
  ('save_private_date_reflection(text,uuid,text,text)', 'authenticated'),
  ('submit_dating_report(text,uuid,text,text)', ''),
  ('sync_dating_pause_on_relationship()', ''),
  ('unmatch_dating_match(text,uuid)', 'authenticated'),
  ('verify_dating_age(uuid,date,text,uuid,timestamp with time zone)', '');

-- ---------------------------------------------------------------------
-- Checks (every batch adds its rows above this line).
-- ---------------------------------------------------------------------
CREATE FUNCTION pg_temp.table_privs(p_rel oid, p_role text, p_dml_only boolean) RETURNS text LANGUAGE sql AS $$
  SELECT coalesce(string_agg(x.priv, ',' ORDER BY x.priv), '')
    FROM (SELECT DISTINCT a.privilege_type AS priv
            FROM pg_class AS c, aclexplode(c.relacl) AS a
           WHERE c.oid = p_rel
             AND a.grantee = CASE WHEN p_role = 'PUBLIC' THEN 0 ELSE p_role::regrole::oid END
             AND (NOT p_dml_only OR a.privilege_type IN ('SELECT', 'INSERT', 'UPDATE', 'DELETE'))) AS x;
$$;

DO $$
DECLARE
  r record;
  v_bad text := '';
  v_allowed allowed_rel%ROWTYPE;
  v_clients text;
BEGIN
  FOR r IN
    SELECT c.oid, c.relname::text AS name, c.relkind, c.relrowsecurity
      FROM pg_class AS c JOIN pg_namespace AS n ON n.oid = c.relnamespace
     WHERE n.nspname = 'public' AND c.relkind IN ('r', 'v', 'm', 'p')
       AND (c.relname ~ '^dating_' OR c.relname IN ('country_safety_config', 'enforcement_records',
                                                   'couple_how_we_met', 'law_enforcement_requests'))
     ORDER BY c.relname
  LOOP
    SELECT * INTO v_allowed FROM allowed_rel WHERE name = r.name;
    IF NOT FOUND THEN
      v_bad := v_bad || format(E'\n  %s: not in the canary''s allow-list', r.name);
      CONTINUE;
    END IF;
    IF r.relkind IN ('r', 'p') AND NOT r.relrowsecurity THEN
      v_bad := v_bad || format(E'\n  %s: RLS is off', r.name);
    END IF;
    IF pg_temp.table_privs(r.oid, 'PUBLIC', false) IS DISTINCT FROM '' THEN
      v_bad := v_bad || format(E'\n  %s: PUBLIC has %s', r.name, pg_temp.table_privs(r.oid, 'PUBLIC', false));
    END IF;
    IF pg_temp.table_privs(r.oid, 'anon', false) IS DISTINCT FROM v_allowed.anon THEN
      v_bad := v_bad || format(E'\n  %s: anon has [%s], allowed [%s]', r.name, pg_temp.table_privs(r.oid, 'anon', false), v_allowed.anon);
    END IF;
    IF pg_temp.table_privs(r.oid, 'authenticated', false) IS DISTINCT FROM v_allowed.authenticated THEN
      v_bad := v_bad || format(E'\n  %s: authenticated has [%s], allowed [%s]', r.name,
                               pg_temp.table_privs(r.oid, 'authenticated', false), v_allowed.authenticated);
    END IF;
    IF pg_temp.table_privs(r.oid, 'service_role', true) IS DISTINCT FROM v_allowed.service_dml THEN
      v_bad := v_bad || format(E'\n  %s: service_role has [%s], allowed [%s]', r.name,
                               pg_temp.table_privs(r.oid, 'service_role', true), v_allowed.service_dml);
    END IF;
  END LOOP;

  FOR r IN
    SELECT p.oid,
           CASE WHEN n.nspname = 'public' THEN '' ELSE n.nspname || '.' END
             || p.proname || '(' || pg_catalog.oidvectortypes(p.proargtypes) || ')' AS sig
      FROM pg_proc AS p JOIN pg_namespace AS n ON n.oid = p.pronamespace
     WHERE n.nspname IN ('public', 'private')
       AND (p.proname ~ '(dating|date_reflection)' OR p.proname IN ('publish_country_config', 'apply_same_gender_switch'))
  LOOP
    r.sig := replace(r.sig, ', ', ',');
    SELECT a.clients INTO v_clients FROM allowed_fn AS a WHERE a.sig = r.sig;
    IF NOT FOUND THEN
      v_bad := v_bad || format(E'\n  %s: not in the canary''s allow-list', r.sig);
      CONTINUE;
    END IF;
    IF EXISTS (SELECT 1 FROM pg_proc AS p2, aclexplode(coalesce(p2.proacl, acldefault('f', p2.proowner))) AS a
                WHERE p2.oid = r.oid AND a.grantee = 0 AND a.privilege_type = 'EXECUTE') THEN
      v_bad := v_bad || format(E'\n  %s: PUBLIC can execute it', r.sig);
    END IF;
    IF concat_ws(',', CASE WHEN has_function_privilege('anon', r.oid, 'EXECUTE') THEN 'anon' END,
                      CASE WHEN has_function_privilege('authenticated', r.oid, 'EXECUTE') THEN 'authenticated' END)
       IS DISTINCT FROM v_clients THEN
      v_bad := v_bad || format(E'\n  %s: clients [%s], allowed [%s]', r.sig,
        concat_ws(',', CASE WHEN has_function_privilege('anon', r.oid, 'EXECUTE') THEN 'anon' END,
                       CASE WHEN has_function_privilege('authenticated', r.oid, 'EXECUTE') THEN 'authenticated' END),
        v_clients);
    END IF;
  END LOOP;

  IF v_bad IS DISTINCT FROM '' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: Dating grants differ from the allow-list:%', v_bad;
  END IF;
END $$;

-- S-5: the derived special-category tables are unreadable by every API
-- role, the service role included.
DO $$
DECLARE
  v_t text;
BEGIN
  FOREACH v_t IN ARRAY ARRAY['dating_profile_sensitive', 'dating_messages', 'dating_introductions',
                             'dating_interest_actions', 'dating_matches', 'dating_couple_link_requests'] LOOP
    CONTINUE WHEN to_regclass('public.' || v_t) IS NULL;
    IF has_table_privilege('anon', 'public.' || v_t, 'SELECT')
       OR has_table_privilege('authenticated', 'public.' || v_t, 'SELECT')
       OR has_table_privilege('service_role', 'public.' || v_t, 'SELECT') THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: public.% is readable by an API role (S-5)', v_t;
    END IF;
  END LOOP;
END $$;

-- S-4: the only function the service role can execute that decrypts
-- Dating fields is dating_export_for_job (W9); no column stores routing.
DO $$
DECLARE
  v_bad text;
BEGIN
  SELECT string_agg(p.oid::regprocedure::text, ', ') INTO v_bad
    FROM pg_proc AS p JOIN pg_namespace AS n ON n.oid = p.pronamespace
   WHERE n.nspname IN ('public', 'private')
     AND p.prosrc LIKE '%dating_field_decrypt%'
     AND p.proname IS DISTINCT FROM 'dating_field_decrypt'
     AND has_function_privilege('service_role', p.oid, 'EXECUTE')
     AND p.proname IS DISTINCT FROM 'dating_export_for_job';
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the service role can decrypt Dating fields through %', v_bad;
  END IF;
  IF to_regprocedure('private.dating_field_decrypt(bytea)') IS NOT NULL
     AND has_function_privilege('service_role', 'private.dating_field_decrypt(bytea)', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the service role can call dating_field_decrypt';
  END IF;
  SELECT string_agg(c.table_name || '.' || c.column_name, ', ') INTO v_bad
    FROM information_schema.columns AS c
   WHERE c.table_schema = 'public' AND c.column_name LIKE '%routing%'
     AND NOT (c.table_name = 'dating_moderators' AND c.column_name = 'sensitive_routing_allowed');
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a column stores routing (S-5): %', v_bad;
  END IF;
END $$;

DO $$ BEGIN RAISE NOTICE 'dating_rls_canary: all held'; END $$;
ROLLBACK;
```

Create `supabase/tests/storage_bucket_policies.sql` with exactly:

```sql
-- supabase/tests/storage_bucket_policies.sql
-- Spec 2 §4.5, §7.1 (I-10, F-1): the Dating buckets are private, their
-- storage.objects policies are exactly the listed ones, no trigger on
-- storage.objects is Dating's, and dating-profile-photos is not in Spec 1's
-- scan-trigger bucket list (each Dating photo is scanned once, inline, by
-- process-dating-photo). W4a adds dating-verification-review.
-- One BEGIN ... ROLLBACK. Run only on attune_spec3a:
--   psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/storage_bucket_policies.sql
BEGIN;

DO $$
DECLARE
  v_bucket text;
  v_got text;
  v_want constant jsonb := jsonb_build_object(
    'dating-profile-photos',
    'dating_profile_photos_insert_by_intent:INSERT:{authenticated};dating_profile_photos_select_owner:SELECT:{authenticated}');
BEGIN
  FOR v_bucket IN SELECT jsonb_object_keys(v_want) LOOP
    IF NOT EXISTS (SELECT 1 FROM storage.buckets WHERE id = v_bucket) THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: bucket % does not exist', v_bucket;
    END IF;
    IF (SELECT public FROM storage.buckets WHERE id = v_bucket) THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: bucket % is public', v_bucket;
    END IF;
    SELECT string_agg(p.policyname || ':' || p.cmd || ':' || p.roles::text, ';' ORDER BY p.policyname) INTO v_got
      FROM pg_policies AS p
     WHERE p.schemaname = 'storage' AND p.tablename = 'objects'
       AND (coalesce(p.qual, '') || coalesce(p.with_check, '')) LIKE '%' || quote_literal(v_bucket) || '%';
    IF v_got IS DISTINCT FROM v_want ->> v_bucket THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: % policies are [%], expected [%]', v_bucket, v_got, v_want ->> v_bucket;
    END IF;
  END LOOP;

  SELECT string_agg(t.tgname, ', ') INTO v_got
    FROM pg_trigger AS t JOIN pg_proc AS f ON f.oid = t.tgfoid
   WHERE t.tgrelid = 'storage.objects'::regclass AND NOT t.tgisinternal
     AND (t.tgname ~* 'dating' OR f.proname ~* 'dating' OR f.prosrc ~ 'dating-');
  IF v_got IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: storage.objects has a Dating trigger (F-1): %', v_got;
  END IF;

  IF to_regprocedure('private.media_scan_buckets()') IS NOT NULL
     AND 'dating-profile-photos' = ANY (private.media_scan_buckets()) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: dating-profile-photos is in the scan-trigger bucket list (I-10: inline only)';
  END IF;
END $$;

DO $$ BEGIN RAISE NOTICE 'storage_bucket_policies: all held'; END $$;
ROLLBACK;
```

```bash
D=.superpowers/sdd/2026-11-06-spec2-w1
python3 -I $D/section.py supabase/tests/dating_v2_identity_contracts.sql $D/identity_B.sql --end
```

Expected: `dating_v2_identity_contracts.sql: identity_B.sql end`.

- [ ] **Step 2: Run them to make sure they fail**

```bash
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/dating_v2_identity_contracts.sql 2>&1 | grep -E 'ERROR|all held' | head -1 | sed -E 's/^psql:[^ ]* //'
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/dating_rls_canary.sql 2>&1 | grep -E 'ERROR|all held' | head -1 | sed -E 's/^psql:[^ ]* //'
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/storage_bucket_policies.sql 2>&1 | grep -E 'ERROR|all held' | head -1 | sed -E 's/^psql:[^ ]* //'
```

Expected: `ERROR:  relation "public.enforcement_records" does not exist`; `ERROR:  CONTRACT VIOLATED: Dating grants differ from the allow-list: dating_account_restrictions: anon has [SELECT], allowed []` (`attune_spec3a` was built with the harness's blanket grants, P-9; the hosted projects hold their own leftovers); `NOTICE:  storage_bucket_policies: all held` (the bucket test pins what is already true; its mutants in Step 6 prove it can fail).

- [ ] **Step 3: Write migration 2 and its twin**

Create `supabase/migrations/20261106110000_dating_v2_enforcement_survival.sql` with exactly:

```sql
-- Spec 2 W1a, migration 2 (spec §4.9 W1a #2, §4.3, §4.5, §6.3; Q5, S-5,
-- I-16): what survives an account's deletion, keyed by phone HMAC.
--   * enforcement_records: one row per carried restriction (scope 'dating';
--     'opinions' reserved for Spec 1 W9d, never written here), idempotent
--     on source_restriction_id, purged after purge_after.
--   * dating_block_hmacs: a block pair by both numbers' HMACs; purge_after
--     stays NULL while both accounts exist.
--   * dating_reports: reporter and target become ON DELETE SET NULL; the
--     target's HMAC is kept in target_phone_hmac.
--   * dating_matches: both members and the introduction become ON DELETE
--     SET NULL (else the introduction's cascade would delete the match);
--     closed_reason and evidence_until; the order and self CHECKs say NULL
--     is allowed.
--   * block_dating_user re-created from its live body (20260703203000):
--     also writes the HMAC pair, and the match it closes gets
--     closed_reason 'blocked' and a 30-day evidence window.
--   * dating_account_in_good_standing re-created from its live body
--     (20260705210000): also false while an enforcement record for the
--     person's number is in effect, or a Spec 1 age_review / safety_review
--     hold is unresolved (spec §2.1 gate 3).
-- Grants (and the service_role revoke on introductions, interest actions
-- and matches, S-5) in 20261106110010_dating_v2_enforcement_survival_grants.sql.
BEGIN;
SET LOCAL lock_timeout = '5s';

CREATE TABLE IF NOT EXISTS public.enforcement_records (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  phone_hmac text NOT NULL CHECK (phone_hmac ~ '^[0-9a-f]{64}$'),
  scope text NOT NULL CHECK (scope IN ('dating', 'opinions')),
  source_restriction_id uuid UNIQUE,
  restriction_type text NOT NULL
    CHECK (restriction_type IN ('suspended', 'under_review', 'age_review', 'moderation_hold')),
  category text,
  confirmed_report_count integer NOT NULL DEFAULT 0 CHECK (confirmed_report_count >= 0),
  effect_until timestamptz,
  purge_after timestamptz NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS enforcement_records_phone_hmac_idx ON public.enforcement_records (phone_hmac);
ALTER TABLE public.enforcement_records ENABLE ROW LEVEL SECURITY;
COMMENT ON TABLE public.enforcement_records IS
  'Spec 2 W1a (Q5, §6.3): a Dating restriction carried past account deletion, keyed by the number''s HMAC (dating_phone_hmac_for_user), kept 2 years. scope opinions is reserved for Spec 1 W9d (O4) and never written by Spec 2.';

CREATE TABLE IF NOT EXISTS public.dating_block_hmacs (
  blocker_hmac text NOT NULL CHECK (blocker_hmac ~ '^[0-9a-f]{64}$'),
  blocked_hmac text NOT NULL CHECK (blocked_hmac ~ '^[0-9a-f]{64}$'),
  created_at timestamptz NOT NULL DEFAULT now(),
  purge_after timestamptz,
  PRIMARY KEY (blocker_hmac, blocked_hmac)
);
CREATE INDEX IF NOT EXISTS dating_block_hmacs_blocked_idx ON public.dating_block_hmacs (blocked_hmac);
ALTER TABLE public.dating_block_hmacs ENABLE ROW LEVEL SECURITY;
COMMENT ON TABLE public.dating_block_hmacs IS
  'Spec 2 W1a (Q5): a Dating block by both numbers'' HMACs. purge_after is NULL while both accounts exist and set to deletion + 2 years by prepare_account_deletion.';

-- Reports survive either side's deletion (anonymised), with the target's HMAC.
ALTER TABLE public.dating_reports ALTER COLUMN reporter_user_id DROP NOT NULL;
ALTER TABLE public.dating_reports ALTER COLUMN target_user_id DROP NOT NULL;
ALTER TABLE public.dating_reports ADD COLUMN IF NOT EXISTS target_phone_hmac text;
ALTER TABLE public.dating_reports DROP CONSTRAINT IF EXISTS dating_reports_reporter_user_id_fkey;
ALTER TABLE public.dating_reports ADD CONSTRAINT dating_reports_reporter_user_id_fkey
  FOREIGN KEY (reporter_user_id) REFERENCES public.users(id) ON DELETE SET NULL;
ALTER TABLE public.dating_reports DROP CONSTRAINT IF EXISTS dating_reports_target_user_id_fkey;
ALTER TABLE public.dating_reports ADD CONSTRAINT dating_reports_target_user_id_fkey
  FOREIGN KEY (target_user_id) REFERENCES public.users(id) ON DELETE SET NULL;

-- Matches survive deletion as sealed records for the evidence window.
ALTER TABLE public.dating_matches ALTER COLUMN user_low_id DROP NOT NULL;
ALTER TABLE public.dating_matches ALTER COLUMN user_high_id DROP NOT NULL;
ALTER TABLE public.dating_matches ALTER COLUMN introduction_id DROP NOT NULL;
ALTER TABLE public.dating_matches ADD COLUMN IF NOT EXISTS closed_reason text;
ALTER TABLE public.dating_matches ADD COLUMN IF NOT EXISTS evidence_until timestamptz;
ALTER TABLE public.dating_matches DROP CONSTRAINT IF EXISTS dating_matches_closed_reason_check;
ALTER TABLE public.dating_matches ADD CONSTRAINT dating_matches_closed_reason_check CHECK (
  closed_reason IS NULL OR closed_reason IN ('unmatched', 'blocked', 'closed_kindly', 'exit',
    'account_restricted', 'age_review', 'age_verification_invalid', 'couple_linked',
    'other_linked', 'account_deleted'));
ALTER TABLE public.dating_matches DROP CONSTRAINT IF EXISTS dating_matches_pair_order_check;
ALTER TABLE public.dating_matches ADD CONSTRAINT dating_matches_pair_order_check CHECK (
  user_low_id IS NULL OR user_high_id IS NULL OR user_low_id::text < user_high_id::text);
ALTER TABLE public.dating_matches DROP CONSTRAINT IF EXISTS dating_matches_no_self_pair_check;
ALTER TABLE public.dating_matches ADD CONSTRAINT dating_matches_no_self_pair_check CHECK (
  user_low_id IS NULL OR user_high_id IS NULL OR user_low_id <> user_high_id);
ALTER TABLE public.dating_matches DROP CONSTRAINT IF EXISTS dating_matches_user_low_id_fkey;
ALTER TABLE public.dating_matches ADD CONSTRAINT dating_matches_user_low_id_fkey
  FOREIGN KEY (user_low_id) REFERENCES public.users(id) ON DELETE SET NULL;
ALTER TABLE public.dating_matches DROP CONSTRAINT IF EXISTS dating_matches_user_high_id_fkey;
ALTER TABLE public.dating_matches ADD CONSTRAINT dating_matches_user_high_id_fkey
  FOREIGN KEY (user_high_id) REFERENCES public.users(id) ON DELETE SET NULL;
ALTER TABLE public.dating_matches DROP CONSTRAINT IF EXISTS dating_matches_introduction_id_fkey;
ALTER TABLE public.dating_matches ADD CONSTRAINT dating_matches_introduction_id_fkey
  FOREIGN KEY (introduction_id) REFERENCES public.dating_introductions(id) ON DELETE SET NULL;

CREATE OR REPLACE FUNCTION public.block_dating_user(p_idempotency_key text, p_target_user_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id uuid := auth.uid();
  v_pair_key text;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;

  IF v_user_id = p_target_user_id THEN
    RAISE EXCEPTION 'invalid_target' USING ERRCODE = '22023';
  END IF;

  IF NOT public.claim_dating_idempotency('block_dating_user', p_idempotency_key) THEN
    RETURN;
  END IF;

  v_pair_key := public.dating_pair_key(v_user_id, p_target_user_id);

  INSERT INTO public.dating_blocks (
    blocker_user_id,
    blocked_user_id,
    pair_key
  )
  VALUES (
    v_user_id,
    p_target_user_id,
    v_pair_key
  )
  ON CONFLICT (blocker_user_id, blocked_user_id) DO NOTHING;

  -- Spec 2 W1a: the pair also survives either account's deletion.
  INSERT INTO public.dating_block_hmacs (blocker_hmac, blocked_hmac)
  SELECT h.blocker, h.blocked
    FROM (SELECT public.dating_phone_hmac_for_user(v_user_id) AS blocker,
                 public.dating_phone_hmac_for_user(p_target_user_id) AS blocked) AS h
   WHERE h.blocker IS NOT NULL AND h.blocked IS NOT NULL
  ON CONFLICT (blocker_hmac, blocked_hmac) DO NOTHING;

  UPDATE public.dating_introductions
  SET state = 'invalidated'
  WHERE pair_key = v_pair_key
    AND state IN ('generated', 'presented', 'interested');

  UPDATE public.dating_matches
  SET state = 'blocked',
      closed_reason = 'blocked', -- Spec 2 W1a
      evidence_until = now() + interval '30 days', -- Spec 2 W1a
      closed_at = COALESCE(closed_at, now())
  WHERE public.dating_pair_key(user_low_id, user_high_id) = v_pair_key
    AND state = 'active';
END;
$function$;

CREATE OR REPLACE FUNCTION public.dating_account_in_good_standing(p_user_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
  SELECT EXISTS (
    SELECT 1 FROM auth.users au
    WHERE au.id = p_user_id
      AND au.deleted_at IS NULL
      AND (au.banned_until IS NULL OR au.banned_until <= now())
  ) AND NOT EXISTS (
    SELECT 1 FROM public.dating_account_restrictions dar
    WHERE dar.user_id = p_user_id
      AND dar.lifted_at IS NULL
      AND dar.starts_at <= now()
      AND (dar.ends_at IS NULL OR dar.ends_at > now())
  ) AND NOT EXISTS ( -- Spec 2 W1a: a restriction carried past a deletion
    SELECT 1 FROM public.enforcement_records er
    WHERE er.scope = 'dating'
      AND er.phone_hmac = public.dating_phone_hmac_for_user(p_user_id)
      AND (er.effect_until IS NULL OR er.effect_until > now())
      AND er.purge_after > now()
  ) AND NOT EXISTS ( -- Spec 2 W1a: Spec 1's account holds (gate 3)
    SELECT 1 FROM public.account_holds h
    WHERE h.user_id = p_user_id
      AND h.kind IN ('age_review', 'safety_review')
      AND h.resolved_at IS NULL
  );
$function$;

REVOKE ALL ON public.enforcement_records FROM PUBLIC, anon, authenticated;
REVOKE ALL ON public.dating_block_hmacs FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.block_dating_user(text, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.dating_account_in_good_standing(uuid) FROM PUBLIC, anon, authenticated;

COMMIT;
```

Create `supabase/migrations/20261106110010_dating_v2_enforcement_survival_grants.sql` with exactly:

```sql
-- Spec 2 W1a: grants for 20261106110000_dating_v2_enforcement_survival.sql,
-- and every Dating table's client grants re-asserted (spec §4.1, §4.5):
-- clients reach Dating through definer RPCs only; until W3a the app still
-- SELECTs its own rows from the four 20260811120000 tables and the two the
-- photo upload and Storage policies read (the owner-read policies keep
-- those reads to the person's own rows). S-5: introductions, interest
-- actions and matches are revoked from service_role too (no edge function
-- reads them; every reader is a definer function). The two new tables are
-- the service role's (the console, W7) and nobody else's.
BEGIN;
SET LOCAL lock_timeout = '5s';
REVOKE ALL ON public.dating_account_restrictions, public.dating_age_verifications,
  public.dating_algorithm_configs, public.dating_blocks, public.dating_consent_events,
  public.dating_date_reflections, public.dating_enrollments, public.dating_feature_snapshots,
  public.dating_former_partner_exclusions, public.dating_generation_runs,
  public.dating_interest_actions, public.dating_introductions, public.dating_matches,
  public.dating_photo_moderation_config, public.dating_photo_moderation_outbox,
  public.dating_photo_upload_intents, public.dating_preferences, public.dating_profile_photos,
  public.dating_profiles, public.dating_rate_limits, public.dating_reports,
  public.dating_rpc_idempotency
  FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.dating_enrollments, public.dating_consent_events, public.dating_profiles,
  public.dating_preferences, public.dating_profile_photos, public.dating_photo_upload_intents
  TO authenticated;
REVOKE ALL ON public.dating_introductions, public.dating_interest_actions, public.dating_matches
  FROM service_role;
REVOKE ALL ON public.enforcement_records, public.dating_block_hmacs FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.enforcement_records, public.dating_block_hmacs TO service_role;
REVOKE ALL ON FUNCTION public.block_dating_user(text, uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.dating_account_in_good_standing(uuid) FROM PUBLIC, anon, authenticated, service_role;
-- Every Dating function's client EXECUTE, re-asserted (hosted projects
-- grant new public functions to anon and authenticated by default; the
-- canary checks the result): no PUBLIC, no anon; authenticated only on the
-- client RPCs; the service role keeps its edge-function entry points.
REVOKE ALL ON FUNCTION
  public.act_on_dating_introduction(text, uuid, text),
  public.activate_dating_profile(text),
  public.backfill_dating_former_partner_exclusions(),
  public.begin_dating_enrollment(text, text),
  public.block_dating_introduction(text, uuid),
  public.block_dating_match(text, uuid),
  public.block_dating_user(text, uuid),
  public.build_dating_feature_snapshot(uuid, text),
  public.bump_dating_enrollment_version(),
  public.bump_dating_profile_version(),
  public.check_dating_rate_limit(text, integer, interval),
  public.claim_dating_idempotency(text, text),
  public.claim_dating_photo_jobs(integer, uuid),
  public.create_dating_photo_upload_intent(text),
  public.dating_account_in_good_standing(uuid),
  public.dating_age_gate_holds(uuid),
  public.dating_alignment_reasons(jsonb, jsonb),
  public.dating_alignment_score(jsonb, jsonb, jsonb),
  public.dating_candidate_is_current(uuid),
  public.dating_component_similarity(numeric, numeric),
  public.dating_flag_enabled(text),
  public.dating_former_partner_excluded(uuid, uuid),
  public.dating_has_historical_consent(uuid),
  public.dating_has_relationship(uuid),
  public.dating_healing_gates_hold(uuid),
  public.dating_normalize_scalar(numeric, numeric, numeric),
  public.dating_pair_key(uuid, uuid),
  public.dating_pair_passes_hard_filters(uuid, uuid),
  public.dating_phone_canonical(text),
  public.dating_phone_hmac(text),
  public.dating_phone_hmac_for_user(uuid),
  public.dating_photos_queue_media_before_delete(),
  public.dating_profile_ready(uuid),
  public.dating_set_similarity(jsonb, jsonb),
  public.delete_dating_profile(text),
  public.delete_dating_profile_photo(uuid),
  public.delete_private_date_reflection(text, uuid),
  public.enforce_dating_age_verification_change(),
  public.enforce_dating_lifecycle_gates(),
  public.enforce_dating_restriction_change(),
  public.enqueue_dating_photo_processing(),
  public.exit_dating_mode(text),
  public.expire_dating_introductions(),
  public.generate_dating_candidates_for_user(uuid, text, text, text),
  public.get_dating_eligibility(),
  public.get_dating_operational_health(),
  public.get_my_dating_introductions(integer),
  public.get_my_dating_matches(integer),
  public.insert_dating_profile_photo(uuid, smallint),
  public.invalidate_dating_for_user(uuid, text),
  public.invalidate_dating_on_photo_change(),
  public.invalidate_dating_on_profile_change(),
  public.list_dating_profile_photos(),
  public.pause_dating_for_relationship_user(uuid),
  public.pause_dating_mode(text),
  public.record_dating_consent(text, text, text, text, jsonb),
  public.record_dating_date_reflection(text, uuid, text, text),
  public.record_dating_former_partner_exclusion(uuid, boolean),
  public.recover_stale_dating_photo_jobs(),
  public.report_dating_introduction(text, uuid, text, text),
  public.report_dating_match(text, uuid, text, text),
  public.resolve_dating_introduction_target(uuid),
  public.resolve_dating_match_target(uuid),
  public.resolve_dating_verification_review(uuid, text),
  public.revoke_dating_age_verification(uuid),
  public.run_dating_candidate_generation(text),
  public.save_dating_profile_draft(text, text, text, text, text, integer, integer),
  public.save_private_date_reflection(text, uuid, text, text),
  public.submit_dating_report(text, uuid, text, text),
  public.sync_dating_pause_on_relationship(),
  public.unmatch_dating_match(text, uuid),
  public.verify_dating_age(uuid, date, text, uuid, timestamp with time zone),
  private.dating_home_summary(uuid),
  private.dating_open_countries()
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION
  public.act_on_dating_introduction(text, uuid, text),
  public.activate_dating_profile(text),
  public.begin_dating_enrollment(text, text),
  public.block_dating_introduction(text, uuid),
  public.block_dating_match(text, uuid),
  public.create_dating_photo_upload_intent(text),
  public.delete_dating_profile(text),
  public.delete_dating_profile_photo(uuid),
  public.delete_private_date_reflection(text, uuid),
  public.exit_dating_mode(text),
  public.get_dating_eligibility(),
  public.get_my_dating_introductions(integer),
  public.get_my_dating_matches(integer),
  public.insert_dating_profile_photo(uuid, smallint),
  public.list_dating_profile_photos(),
  public.pause_dating_mode(text),
  public.record_dating_consent(text, text, text, text, jsonb),
  public.report_dating_introduction(text, uuid, text, text),
  public.report_dating_match(text, uuid, text, text),
  public.save_dating_profile_draft(text, text, text, text, text, integer, integer),
  public.save_private_date_reflection(text, uuid, text, text),
  public.unmatch_dating_match(text, uuid)
  TO authenticated;
GRANT EXECUTE ON FUNCTION
  public.backfill_dating_former_partner_exclusions(),
  public.build_dating_feature_snapshot(uuid, text),
  public.claim_dating_photo_jobs(integer, uuid),
  public.dating_phone_hmac(text),
  public.get_dating_operational_health(),
  public.record_dating_former_partner_exclusion(uuid, boolean),
  public.recover_stale_dating_photo_jobs(),
  public.resolve_dating_verification_review(uuid, text),
  public.revoke_dating_age_verification(uuid),
  public.run_dating_candidate_generation(text),
  public.verify_dating_age(uuid, date, text, uuid, timestamp with time zone)
  TO service_role;
COMMIT;
```

- [ ] **Step 4: Apply each file twice; diff the two functions; run the three contracts**

```bash
for i in 1 2; do
  for f in 20261106110000_dating_v2_enforcement_survival 20261106110010_dating_v2_enforcement_survival_grants; do
    psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/migrations/$f.sql > /dev/null 2>&1; echo "$f exit=$?"
  done
done
```

```bash
D=.superpowers/sdd/2026-11-06-spec2-w1
for sig in 'public.block_dating_user(text,uuid)' 'public.dating_account_in_good_standing(uuid)'; do
  echo "== $sig"
  diff "$D/before/$sig.sql" <(psql -X -d attune_spec3a -Atc "select pg_get_functiondef('$sig'::regprocedure)") | grep '^[<>]'
done
```

```bash
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/dating_v2_identity_contracts.sql 2>&1 | grep -E 'ERROR|all held' | head -1 | sed -E 's/^psql:[^ ]* //'
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/dating_rls_canary.sql 2>&1 | grep -E 'ERROR|all held' | head -1 | sed -E 's/^psql:[^ ]* //'
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/storage_bucket_policies.sql 2>&1 | grep -E 'ERROR|all held' | head -1 | sed -E 's/^psql:[^ ]* //'
```

Expected: four `exit=0` lines; then exactly:

```text
== public.block_dating_user(text,uuid)
>   -- Spec 2 W1a: the pair also survives either account's deletion.
>   INSERT INTO public.dating_block_hmacs (blocker_hmac, blocked_hmac)
>   SELECT h.blocker, h.blocked
>     FROM (SELECT public.dating_phone_hmac_for_user(v_user_id) AS blocker,
>                  public.dating_phone_hmac_for_user(p_target_user_id) AS blocked) AS h
>    WHERE h.blocker IS NOT NULL AND h.blocked IS NOT NULL
>   ON CONFLICT (blocker_hmac, blocked_hmac) DO NOTHING;
> 
>       closed_reason = 'blocked', -- Spec 2 W1a
>       evidence_until = now() + interval '30 days', -- Spec 2 W1a
== public.dating_account_in_good_standing(uuid)
>   ) AND NOT EXISTS ( -- Spec 2 W1a: a restriction carried past a deletion
>     SELECT 1 FROM public.enforcement_records er
>     WHERE er.scope = 'dating'
>       AND er.phone_hmac = public.dating_phone_hmac_for_user(p_user_id)
>       AND (er.effect_until IS NULL OR er.effect_until > now())
>       AND er.purge_after > now()
>   ) AND NOT EXISTS ( -- Spec 2 W1a: Spec 1's account holds (gate 3)
>     SELECT 1 FROM public.account_holds h
>     WHERE h.user_id = p_user_id
>       AND h.kind IN ('age_review', 'safety_review')
>       AND h.resolved_at IS NULL
```

then `NOTICE:  dating_v2_identity_contracts: all held`, `NOTICE:  dating_rls_canary: all held`, `NOTICE:  storage_bucket_policies: all held`.

- [ ] **Step 5: Spec 1's service-role test pins every table readable; give it the S-5 list**

```bash
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/service_role_grants_test.sql 2>&1 | grep -E 'ERROR|all held' | head -1 | sed -E 's/^psql:[^ ]* //'
```

Expected: `ERROR:  3 table(s) unreadable by service_role -- their workers will read empty queues with no error: dating_interest_actions, dating_introductions, dating_matches`. Create `.superpowers/sdd/2026-11-06-spec2-w1/edit_service_role_grants.py` with exactly:

```python
import pathlib
p = pathlib.Path('supabase/tests/service_role_grants_test.sql')
s = p.read_text()
for priv in ('SELECT', 'UPDATE'):
    a = f"""    AND c.relkind = 'r'
    AND NOT has_table_privilege('service_role', c.oid, '{priv}');"""
    b = f"""    AND c.relkind = 'r'
    -- Spec 2 S-5 (W1a): the derived special-category tables are no API
    -- role's, the service role's included; definer functions read them,
    -- and dating_rls_canary.sql pins that they stay unreadable.
    AND c.relname NOT IN ('dating_introductions', 'dating_interest_actions', 'dating_matches',
                          'dating_profile_sensitive', 'dating_messages', 'dating_couple_link_requests')
    AND NOT has_table_privilege('service_role', c.oid, '{priv}');"""
    assert s.count(a) == 1, priv
    s = s.replace(a, b)
p.write_text(s)
print('service_role_grants_test.sql: 2 edits')
```

```bash
python3 -I .superpowers/sdd/2026-11-06-spec2-w1/edit_service_role_grants.py
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/service_role_grants_test.sql >/dev/null 2>&1; echo "exit=$?"
```

Expected: `service_role_grants_test.sql: 2 edits`, `exit=0`.

- [ ] **Step 6: Mutation checks**

Create `.superpowers/sdd/2026-11-06-spec2-w1/mut_T3_identity.py`, `.superpowers/sdd/2026-11-06-spec2-w1/mut_T3_canary.py` and `.superpowers/sdd/2026-11-06-spec2-w1/mut_T3_storage.py` with exactly:

```python
MUTS = {
 'block_no_hmac_pair': ("""  INSERT INTO public.dating_block_hmacs (blocker_hmac, blocked_hmac)
  SELECT h.blocker, h.blocked
    FROM (SELECT public.dating_phone_hmac_for_user(v_user_id) AS blocker,
                 public.dating_phone_hmac_for_user(p_target_user_id) AS blocked) AS h
   WHERE h.blocker IS NOT NULL AND h.blocked IS NOT NULL
  ON CONFLICT (blocker_hmac, blocked_hmac) DO NOTHING;
""", ""),
 'block_no_closed_reason': ("""      closed_reason = 'blocked', -- Spec 2 W1a
      evidence_until = now() + interval '30 days', -- Spec 2 W1a
""", ""),
 'standing_ignores_records': ("""      AND er.phone_hmac = public.dating_phone_hmac_for_user(p_user_id)""", """      AND false"""),
 'standing_counts_expired': ("""      AND (er.effect_until IS NULL OR er.effect_until > now())
""", ""),
 'standing_any_scope': ("""    WHERE er.scope = 'dating'
""", """    WHERE true
"""),
 'standing_ignores_holds': ("""      AND h.kind IN ('age_review', 'safety_review')""", """      AND h.kind IN ('age_review')"""),
 'service_reads_matches': ('RAW', "GRANT SELECT ON public.dating_matches TO service_role;"),
 'client_reads_records': ('RAW', "GRANT SELECT ON public.enforcement_records TO authenticated;"),
}
```

```python
MUTS = {
 'client_reads_matches': ('RAW', "GRANT SELECT ON public.dating_matches TO authenticated;"),
 'unlisted_table': ('RAW', "CREATE TABLE public.dating_canary_probe (id int); ALTER TABLE public.dating_canary_probe ENABLE ROW LEVEL SECURITY; REVOKE ALL ON public.dating_canary_probe FROM PUBLIC, anon, authenticated;"),
 'anon_rpc': ('RAW', "GRANT EXECUTE ON FUNCTION public.dating_flag_enabled(text) TO anon;"),
 'public_rpc': ('RAW', "GRANT EXECUTE ON FUNCTION public.invalidate_dating_for_user(uuid, text) TO PUBLIC;"),
 'rls_off': ('RAW', "ALTER TABLE public.dating_blocks DISABLE ROW LEVEL SECURITY;"),
 'service_reads_matches': ('RAW', "GRANT SELECT ON public.dating_matches TO service_role;"),
 'routing_column': ('RAW', "ALTER TABLE public.dating_reports ADD COLUMN sensitive_routing boolean;"),
}
```

```python
MUTS = {
 'bucket_public': ('RAW', "UPDATE storage.buckets SET public = true WHERE id = 'dating-profile-photos';"),
 'extra_policy': ('RAW', "CREATE POLICY dating_probe ON storage.objects FOR SELECT TO anon USING (bucket_id = 'dating-profile-photos');"),
 'scan_lists_dating': ('RAW', """CREATE OR REPLACE FUNCTION private.media_scan_buckets() RETURNS text[] LANGUAGE sql IMMUTABLE SET search_path TO '' AS $f$ SELECT ARRAY['message-media','story-media','relationship-avatars','journal-media','planning-media','avatars','dating-profile-photos']::text[]; $f$;"""),
 'dating_trigger': ('RAW', """CREATE FUNCTION public.dating_probe_trg() RETURNS trigger LANGUAGE plpgsql AS $f$ BEGIN RETURN NULL; END $f$; CREATE TRIGGER dating_probe AFTER INSERT ON storage.objects FOR EACH ROW EXECUTE FUNCTION public.dating_probe_trg();"""),
}
```

```bash
D=.superpowers/sdd/2026-11-06-spec2-w1
python3 -I $D/mutate.py supabase/migrations/20261106110000_dating_v2_enforcement_survival.sql supabase/tests/dating_v2_identity_contracts.sql $D/mut_T3_identity.py $D
python3 -I $D/mutate.py supabase/migrations/20261106110010_dating_v2_enforcement_survival_grants.sql supabase/tests/dating_rls_canary.sql $D/mut_T3_canary.py $D
python3 -I $D/mutate.py supabase/migrations/20261106110010_dating_v2_enforcement_survival_grants.sql supabase/tests/storage_bucket_policies.sql $D/mut_T3_storage.py $D
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/dating_rls_canary.sql 2>&1 | grep -E 'ERROR|all held' | head -1 | sed -E 's/^psql:[^ ]* //'
```

Expected (identity, then canary, then storage):

- `block_no_hmac_pair`: `ERROR:  CONTRACT VIOLATED: block_dating_user wrote no HMAC pair`
- `block_no_closed_reason`: `ERROR:  CONTRACT VIOLATED: the blocked match has no closed_reason or 30-day evidence window`
- `standing_ignores_records`: `ERROR:  CONTRACT VIOLATED: standing ignores an enforcement record for the number`
- `standing_counts_expired`: `ERROR:  CONTRACT VIOLATED: an enforcement record past effect_until still counts`
- `standing_any_scope`: `ERROR:  CONTRACT VIOLATED: an Opinions-scope record closed Dating`
- `standing_ignores_holds`: `ERROR:  CONTRACT VIOLATED: standing ignores an unresolved safety_review hold`
- `service_reads_matches`: `ERROR:  CONTRACT VIOLATED: public.dating_matches is readable outside definer functions (S-5)`
- `client_reads_records`: `ERROR:  CONTRACT VIOLATED: public.enforcement_records has the wrong RLS or grants`
- `client_reads_matches`: `ERROR:  CONTRACT VIOLATED: Dating grants differ from the allow-list: dating_matches: authenticated has [SELECT], allowed []`
- `unlisted_table`: `ERROR:  CONTRACT VIOLATED: Dating grants differ from the allow-list: dating_canary_probe: not in the canary's allow-list`
- `anon_rpc`: `ERROR:  CONTRACT VIOLATED: Dating grants differ from the allow-list: dating_flag_enabled(text): clients [anon], allowed []`
- `public_rpc`: `ERROR:  CONTRACT VIOLATED: Dating grants differ from the allow-list: invalidate_dating_for_user(uuid,text): PUBLIC can execute it`
- `rls_off`: `ERROR:  CONTRACT VIOLATED: Dating grants differ from the allow-list: dating_blocks: RLS is off`
- `service_reads_matches`: `ERROR:  CONTRACT VIOLATED: Dating grants differ from the allow-list: dating_matches: service_role has [SELECT], allowed []`
- `routing_column`: `ERROR:  CONTRACT VIOLATED: a column stores routing (S-5): dating_reports.sensitive_routing`
- `bucket_public`: `ERROR:  CONTRACT VIOLATED: bucket dating-profile-photos is public`
- `extra_policy`: `ERROR:  CONTRACT VIOLATED: dating-profile-photos policies are [dating_probe:SELECT:{anon};dating_profile_photos_insert_by_intent:INSERT:{authenticated};dating_profile_pho`
- `scan_lists_dating`: `ERROR:  CONTRACT VIOLATED: dating-profile-photos is in the scan-trigger bucket list (I-10: inline only)`
- `dating_trigger`: `ERROR:  CONTRACT VIOLATED: storage.objects has a Dating trigger (F-1): dating_probe`

then `NOTICE:  dating_rls_canary: all held` (nothing persisted, not even the probe table).

- [ ] **Step 7: The CI secret scan**

Create `.superpowers/sdd/2026-11-06-spec2-w1/edit_tests_yml_w1a.py` with exactly:

```python
import pathlib
p = pathlib.Path('.github/workflows/tests.yml')
s = p.read_text()
anchor = """  sql-contracts:
    name: SQL contract tests
"""
job = """  repo-guards:
    # Spec 2 W1a (§4.5, §7.6 items 2.7 and 7.3): fail on a committed secret
    # (a Vault key, a service-role key). The whole history is scanned, so a
    # secret committed and later deleted is still found. gitleaks is pinned
    # by version and run as the released binary (no action licence needed).
    name: Repository guards (secret scan)
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Install gitleaks 8.18.4
        run: |
          curl -sSfL -o gitleaks.tar.gz https://github.com/gitleaks/gitleaks/releases/download/v8.18.4/gitleaks_8.18.4_linux_x64.tar.gz
          tar -xzf gitleaks.tar.gz gitleaks

      - name: Scan the repository and its history
        run: ./gitleaks detect --source . --redact --no-banner --exit-code 1

"""
assert s.count(anchor) == 1
p.write_text(s.replace(anchor, job + anchor))
print('tests.yml: repo-guards job added')
```

```bash
python3 -I .superpowers/sdd/2026-11-06-spec2-w1/edit_tests_yml_w1a.py
ruby -e 'require "yaml"; y = YAML.load_file(".github/workflows/tests.yml"); puts y["jobs"].keys.join(" "); puts y["jobs"]["repo-guards"]["steps"].map { |s| s["name"] || s["uses"] }.join(" | ")' 
```

Expected: `tests.yml: repo-guards job added`; `flutter-tests deno-w9 repo-guards sql-contracts`; `actions/checkout@v4 | Install gitleaks 8.18.4 | Scan the repository and its history`. (The scan itself runs in CI; owner checklist 7.)

- [ ] **Step 8: The local harness (edit only, never run)**

`scripts/local_pg_grants.sql`: append after the last line (`\i supabase/migrations/20261106100010_dating_v2_phone_hmac_grants.sql`), exactly:

```sql

-- Spec 2 W1a: every Dating table's and function's client grants re-asserted;
-- introductions, interest actions and matches revoked from the service role (S-5).
\i supabase/migrations/20261106110010_dating_v2_enforcement_survival_grants.sql
```

```bash
python3 -I - <<'PY'
import pathlib
p = pathlib.Path('scripts/local_pg_grants.sql')
s = p.read_text()
assert s.endswith('\\i supabase/migrations/20261106100010_dating_v2_phone_hmac_grants.sql' + chr(10))
p.write_text(s + chr(10) + "-- Spec 2 W1a: every Dating table's and function's client grants re-asserted;\n-- introductions, interest actions and matches revoked from the service role (S-5)." + chr(10) + '\\i supabase/migrations/20261106110010_dating_v2_enforcement_survival_grants.sql' + chr(10))
print('local_pg_grants.sql: one \\i block added')
PY
```

- [ ] **Step 9: Run tests**

```bash
for t in dating_mode_contracts dating_exclusion_wiring_test dating_alignment_contracts account_deletion_contracts story_storage_policy_isolation_contracts identity_foundation_contracts; do
  psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/$t.sql >/dev/null 2>&1 && echo "PASS $t" || echo "FAIL $t"
done
```

Expected: six `PASS` lines (the re-asserted grants keep the v1 app's six SELECTs and every client RPC it calls; Stories' Storage policies are unaffected).

### Task 4: Migration 3: `prepare_account_deletion`'s Dating carry-over; the `dating.` prefix; the DPIA draft; the W1a gate (§4.9 W1a #3, §6.3, §6.8, R5, S-2; mutant 16; P-11)

**Files:**
- Create: `supabase/migrations/20261106120000_dating_v2_account_deletion.sql`, `…120010_dating_v2_account_deletion_grants.sql`, `lib/architecture/DATING_MODE_DPIA.md`
- Modify: `supabase/tests/dating_v2_identity_contracts.sql` (section C), `scripts/local_pg_grants.sql`

**Interfaces:**
- Consumes: Task 3's tables and columns; the live `prepare_account_deletion` (`before/`).
- Produces: `prepare_account_deletion` raising `deletion:enforcement_key_missing` only when a live restriction would be lost; `metric_key_prefixes ('dating.', 'spec2')`.

- [ ] **Step 1: Write the failing contract section**

Create `.superpowers/sdd/2026-11-06-spec2-w1/identity_C.sql` with exactly:

```sql
-- =====================================================================
-- C. (W1a) Deletion carry-over (§6.3): enforcement records, block pairs,
--    sealed matches and pseudonymised reports survive; delete, re-register on
--    the same SIM and tamper public.users.phone: still excluded, blocked
--    and restricted; a parked account is carried under its real number.
-- =====================================================================
DO $$
DECLARE
  v_gone constant uuid := pg_temp.person('20');
  v_blocker constant uuid := pg_temp.person('21');
  v_blocked constant uuid := pg_temp.person('22');
  v_match_with constant uuid := pg_temp.person('23');
  v_reporter constant uuid := pg_temp.person('24');
  v_reported constant uuid := pg_temp.person('25');
  v_ex constant uuid := pg_temp.person('27');
  v_nokey constant uuid := pg_temp.person('28');
  v_parked constant uuid := pg_temp.person('29');
  v_new constant uuid := pg_temp.id('26');
  v_fresh constant uuid := pg_temp.id('30');
  v_hmac text;
  v_real text;
  v_live uuid;
  v_m uuid;
  v_rel uuid;
  v_got text;
BEGIN
  v_hmac := public.dating_phone_hmac_for_user(v_gone);
  INSERT INTO public.dating_account_restrictions (user_id, restriction_type) VALUES (v_gone, 'suspended')
  RETURNING id INTO v_live;
  INSERT INTO public.dating_account_restrictions (user_id, restriction_type, lifted_at)
  VALUES (v_gone, 'under_review', now() - interval '1 day');
  INSERT INTO public.dating_account_restrictions (user_id, restriction_type, starts_at, ends_at)
  VALUES (v_gone, 'moderation_hold', now() - interval '9 days', now() - interval '2 days');
  -- A block made before W1a (no HMAC row yet), and one made through the RPC.
  INSERT INTO public.dating_blocks (blocker_user_id, blocked_user_id, pair_key)
  VALUES (v_blocker, v_gone, public.dating_pair_key(v_blocker, v_gone));
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_gone, 'role', 'authenticated')::text, true);
  PERFORM public.block_dating_user('spec2-w1-block-0020', v_blocked);
  PERFORM pg_temp.as_owner();
  v_m := pg_temp.match(v_gone, v_match_with);
  INSERT INTO public.dating_reports (reporter_user_id, target_user_id, category) VALUES
    (v_reporter, v_gone, 'harassment'), (v_gone, v_reported, 'spam');
  INSERT INTO public.relationships (user_a, user_b, status, ended_at) VALUES (v_gone, v_ex, 'ended', now())
  RETURNING id INTO v_rel;
  PERFORM public.record_dating_former_partner_exclusion(v_rel, true);

  v_got := pg_temp.as_service(format('SELECT public.prepare_account_deletion(%L)::text', v_gone));
  v_got := coalesce(v_got, '') || pg_temp.as_service(format('SELECT public.prepare_account_deletion(%L)::text', v_gone));
  IF v_got IS DISTINCT FROM '' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: prepare_account_deletion failed: %', v_got;
  END IF;
  DELETE FROM auth.users WHERE id = v_gone;

  -- 1. One enforcement record, for the live restriction only, run twice.
  IF (SELECT count(*) FROM public.enforcement_records WHERE phone_hmac = v_hmac) IS DISTINCT FROM 1
     OR NOT EXISTS (SELECT 1 FROM public.enforcement_records
                     WHERE phone_hmac = v_hmac AND scope = 'dating' AND source_restriction_id = v_live
                       AND restriction_type = 'suspended' AND effect_until IS NULL
                       AND purge_after BETWEEN now() + interval '729 days' AND now() + interval '731 days') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the live restriction was not carried exactly once as a 2-year enforcement record';
  END IF;
  -- 2. Both block pairs survive, kept 2 years.
  IF (SELECT count(*) FROM public.dating_block_hmacs
       WHERE ((blocker_hmac = public.dating_phone_hmac_for_user(v_blocker) AND blocked_hmac = v_hmac)
           OR (blocker_hmac = v_hmac AND blocked_hmac = public.dating_phone_hmac_for_user(v_blocked)))
         AND purge_after BETWEEN now() + interval '729 days' AND now() + interval '731 days') IS DISTINCT FROM 2 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the block pairs did not survive the deletion with a 2-year purge';
  END IF;
  -- 3. The match survives, sealed, closed for the deletion, members anonymised.
  IF NOT EXISTS (SELECT 1 FROM public.dating_matches
                  WHERE id = v_m AND state = 'closed' AND closed_reason = 'account_deleted'
                    AND evidence_until BETWEEN now() + interval '29 days' AND now() + interval '31 days'
                    AND introduction_id IS NULL
                    AND num_nulls(user_low_id, user_high_id) = 1
                    AND v_match_with IN (user_low_id, user_high_id)) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the match did not survive as a sealed, anonymised record';
  END IF;
  -- 4. Reports survive either side's deletion; the target keeps its HMAC.
  IF NOT EXISTS (SELECT 1 FROM public.dating_reports
                  WHERE reporter_user_id = v_reporter AND target_user_id IS NULL AND target_phone_hmac = v_hmac)
     OR NOT EXISTS (SELECT 1 FROM public.dating_reports
                     WHERE reporter_user_id IS NULL AND target_user_id = v_reported) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a report did not survive a deletion (with target_phone_hmac)';
  END IF;

  -- Delete -> re-register (same SIM) -> tamper public.users.phone.
  INSERT INTO auth.users (id, phone, phone_confirmed_at, created_at) VALUES (v_new, '1555870020', now(), now());
  INSERT INTO public.users (id, phone, display_name, path) VALUES (v_new, '1555870020', 'Back again', 'dating');
  UPDATE public.users SET phone = '+15558709920' WHERE id = v_new;
  IF public.dating_account_in_good_standing(v_new) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: re-registering on the same number lifted the restriction';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.dating_block_hmacs
                  WHERE blocker_hmac = public.dating_phone_hmac_for_user(v_blocker)
                    AND blocked_hmac = public.dating_phone_hmac_for_user(v_new)) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: re-registering on the same number escaped the block';
  END IF;
  IF NOT public.dating_former_partner_excluded(v_ex, v_new) OR NOT public.dating_former_partner_excluded(v_new, v_ex) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: re-registering on the same number escaped the former-partner exclusion';
  END IF;

  -- No key and a live restriction: the deletion is refused, nothing written.
  INSERT INTO public.dating_account_restrictions (user_id, restriction_type) VALUES (v_nokey, 'moderation_hold');
  PERFORM set_config('app.settings.dating_exclusion_key', '', true);
  v_got := pg_temp.as_service(format('SELECT public.prepare_account_deletion(%L)::text', v_nokey));
  PERFORM set_config('app.settings.dating_exclusion_key', 'spec2-w1-contract-exclusion-key', true);
  IF v_got IS DISTINCT FROM 'ERROR: deletion:enforcement_key_missing'
     OR EXISTS (SELECT 1 FROM public.enforcement_records AS e
                  JOIN public.dating_account_restrictions AS d ON d.id = e.source_restriction_id
                 WHERE d.user_id = v_nokey) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a deletion without the key went ahead with a live restriction: %', v_got;
  END IF;

  -- No key and NO live restriction: the deletion completes (blocks, a
  -- match), nothing is refused, the match is still sealed.
  v_m := pg_temp.match(v_nokey, v_reported);
  UPDATE public.dating_account_restrictions SET lifted_at = now() WHERE user_id = v_nokey;
  PERFORM set_config('app.settings.dating_exclusion_key', '', true);
  v_got := pg_temp.as_service(format('SELECT public.prepare_account_deletion(%L)::text', v_nokey));
  PERFORM set_config('app.settings.dating_exclusion_key', 'spec2-w1-contract-exclusion-key', true);
  IF v_got IS DISTINCT FROM ''
     OR NOT EXISTS (SELECT 1 FROM public.dating_matches WHERE id = v_m AND closed_reason = 'account_deleted') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: without the key and with no live restriction the deletion did not complete: %', v_got;
  END IF;

  -- A parked account (I-11, O3 default): nothing is written at parking; the
  -- purge carries the restriction under the REAL number, and its block
  -- pairs get their purge date; a fresh account on that number is closed.
  v_real := public.dating_phone_hmac_for_user(v_parked);
  INSERT INTO public.dating_account_restrictions (user_id, restriction_type) VALUES (v_parked, 'suspended');
  INSERT INTO public.dating_blocks (blocker_user_id, blocked_user_id, pair_key)
  VALUES (v_parked, v_blocker, public.dating_pair_key(v_parked, v_blocker));
  UPDATE public.users SET parked_phone_hmac = v_real WHERE id = v_parked;
  UPDATE auth.users SET phone = '999123456789229' WHERE id = v_parked;
  UPDATE public.users SET phone_released_at = now() WHERE id = v_parked;
  IF EXISTS (SELECT 1 FROM public.enforcement_records WHERE phone_hmac = v_real) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: parking wrote an enforcement record (built default O3: no)';
  END IF;
  v_got := pg_temp.as_service(format('SELECT public.prepare_account_deletion(%L)::text', v_parked));
  DELETE FROM auth.users WHERE id = v_parked;
  IF (SELECT count(*) FROM public.enforcement_records WHERE phone_hmac = v_real) IS DISTINCT FROM 1
     OR EXISTS (SELECT 1 FROM public.enforcement_records
                 WHERE phone_hmac = public.dating_phone_hmac('+999123456789229'))
     OR NOT EXISTS (SELECT 1 FROM public.dating_block_hmacs
                     WHERE blocker_hmac = v_real AND purge_after IS NOT NULL) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the purge of a parked account did not carry it under the real number';
  END IF;
  INSERT INTO auth.users (id, phone, phone_confirmed_at, created_at) VALUES (v_fresh, '1555870029', now(), now());
  INSERT INTO public.users (id, phone, display_name, path) VALUES (v_fresh, '1555870029', 'Fresh', 'dating');
  IF public.dating_account_in_good_standing(v_fresh) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a fresh account on a purged, restricted number is in good standing';
  END IF;
END $$;
```

```bash
python3 -I .superpowers/sdd/2026-11-06-spec2-w1/section.py supabase/tests/dating_v2_identity_contracts.sql .superpowers/sdd/2026-11-06-spec2-w1/identity_C.sql --end
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/dating_v2_identity_contracts.sql 2>&1 | grep -E 'ERROR|all held' | head -1 | sed -E 's/^psql:[^ ]* //'
```

Expected: `dating_v2_identity_contracts.sql: identity_C.sql end`, then `ERROR:  CONTRACT VIOLATED: the live restriction was not carried exactly once as a 2-year enforcement record`.

- [ ] **Step 2: Write migration 3 and its twin**

Create `supabase/migrations/20261106120000_dating_v2_account_deletion.sql` with exactly:

```sql
-- Spec 2 W1a, migration 3 (spec §4.9 W1a #3, §6.3, R5; S-2):
--   * prepare_account_deletion re-created from its live body
--     (20261018110000_chapters_deletion.sql; identical to pg_get_functiondef
--     on attune_spec3a) with only the lines marked "Spec 2 W1a": the Dating
--     carry-over runs first (enforcement records, block pairs, matches,
--     reports). The enforcement write must succeed (no key with a live
--     restriction refuses the deletion: 'deletion:enforcement_key_missing');
--     the other three steps warn and continue. The restriction's category
--     and the reports' state are read by name (to_jsonb), so W7a's new
--     columns (dating_account_restrictions.category, dating_reports.state)
--     fill confirmed_report_count and category with no change here; until
--     then they are 0 and NULL.
--   * The server metric prefix 'dating.' (owner spec2); no client key.
-- Grants in 20261106120010_dating_v2_account_deletion_grants.sql.
BEGIN;
SET LOCAL lock_timeout = '5s';

CREATE OR REPLACE FUNCTION public.prepare_account_deletion(p_user_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_rel record;
  v_hmac text; -- Spec 2 W1a
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'deletion:no_user';
  END IF;

  -- Spec 2 W1a (§6.3, R5): Dating carry-over, before anything is deleted.
  -- Every HMAC comes from dating_phone_hmac_for_user (the pre-park one for
  -- a parked account, I-11). Step 1 must succeed: a deletion that would
  -- drop a live restriction is refused and retried, never completed.
  -- Steps 2-4 each run in their own block, warn and continue.
  v_hmac := public.dating_phone_hmac_for_user(p_user_id);
  IF v_hmac IS NULL AND EXISTS (
       SELECT 1 FROM public.dating_account_restrictions AS dar
        WHERE dar.user_id = p_user_id AND dar.lifted_at IS NULL
          AND (dar.ends_at IS NULL OR dar.ends_at > now())) THEN
    RAISE EXCEPTION 'deletion:enforcement_key_missing';
  END IF;
  -- 1. Each live restriction becomes an enforcement record (once).
  INSERT INTO public.enforcement_records (phone_hmac, scope, source_restriction_id, restriction_type,
                                          category, confirmed_report_count, effect_until, purge_after)
  SELECT v_hmac, 'dating', dar.id, dar.restriction_type, to_jsonb(dar) ->> 'category',
         (SELECT count(*) FROM public.dating_reports AS r
           WHERE r.target_user_id = p_user_id AND to_jsonb(r) ->> 'state' = 'upheld')::int,
         dar.ends_at, now() + interval '2 years'
    FROM public.dating_account_restrictions AS dar
   WHERE dar.user_id = p_user_id AND dar.lifted_at IS NULL
     AND (dar.ends_at IS NULL OR dar.ends_at > now())
  ON CONFLICT (source_restriction_id) DO NOTHING;
  -- 2. Block pairs by number, kept 2 years from now.
  BEGIN
    IF v_hmac IS NOT NULL THEN
      INSERT INTO public.dating_block_hmacs (blocker_hmac, blocked_hmac)
      SELECT h.blocker, h.blocked
        FROM (SELECT public.dating_phone_hmac_for_user(b.blocker_user_id) AS blocker,
                     public.dating_phone_hmac_for_user(b.blocked_user_id) AS blocked
                FROM public.dating_blocks AS b
               WHERE p_user_id IN (b.blocker_user_id, b.blocked_user_id)) AS h
       WHERE h.blocker IS NOT NULL AND h.blocked IS NOT NULL
      ON CONFLICT (blocker_hmac, blocked_hmac) DO NOTHING;
      UPDATE public.dating_block_hmacs
         SET purge_after = now() + interval '2 years'
       WHERE v_hmac IN (blocker_hmac, blocked_hmac);
    END IF;
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'dating_deletion:block_pairs:%', SQLSTATE;
  END;
  -- 3. Matches close (account_deleted) and stay sealed for 30 days; the
  --    cascade sets their member ids to NULL.
  BEGIN
    UPDATE public.dating_matches AS m
       SET state = CASE WHEN m.state = 'active' THEN 'closed' ELSE m.state END,
           closed_reason = CASE WHEN m.state = 'active' THEN 'account_deleted' ELSE m.closed_reason END,
           closed_at = coalesce(m.closed_at, now()),
           evidence_until = CASE WHEN m.state = 'active' OR m.evidence_until IS NULL
                                 THEN now() + interval '30 days' ELSE m.evidence_until END
     WHERE p_user_id IN (m.user_low_id, m.user_high_id);
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'dating_deletion:matches:%', SQLSTATE;
  END;
  -- 4. Reports about the person keep the number's HMAC (the cascade sets
  --    reporter and target ids to NULL).
  BEGIN
    UPDATE public.dating_reports AS r
       SET target_phone_hmac = v_hmac
     WHERE r.target_user_id = p_user_id AND r.target_phone_hmac IS NULL AND v_hmac IS NOT NULL;
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'dating_deletion:reports:%', SQLSTATE;
  END;
  -- 5. The cascade removes everything else (profile, photos via the media
  --    queue below, introductions, the never-introduce list, ...).

  FOR v_rel IN
    SELECT r.id, r.status FROM public.relationships r
    WHERE p_user_id IN (r.user_a, r.user_b)
    FOR UPDATE
  LOOP
    IF v_rel.status IN ('active', 'paused') THEN
      PERFORM public.relationship_end_internal(v_rel.id, p_user_id);
    ELSIF v_rel.status = 'pending' THEN
      DELETE FROM public.relationships WHERE id = v_rel.id;
      CONTINUE;
    END IF;

    -- What carries the person's answers or profile and cannot be split by
    -- person: games (positional answer_a/answer_b; rounds, per-user answers,
    -- Love map rounds and mirror truth go with them), 36-question journeys
    -- (AI text about the pair), the analysis sessions' role attribution, the
    -- profile-derived compatibility card. The partner's own game answers go
    -- with the shared sessions (D.3 #1 over D.2; review I1). Pulse,
    -- verdicts and patterns stay: role-free, both already saw them, the
    -- partner may export them in the window; the 12-month purge removes them.
    DELETE FROM public.game_sessions WHERE relationship_id = v_rel.id;
    DELETE FROM public.game_session_rounds WHERE relationship_id = v_rel.id;
    DELETE FROM public.thirty_six_question_journeys WHERE relationship_id = v_rel.id;
    DELETE FROM public.thirty_six_questions_seen WHERE relationship_id = v_rel.id;
    DELETE FROM public.game_questions_seen WHERE relationship_id = v_rel.id;
    DELETE FROM public.analysis_sessions WHERE relationship_id = v_rel.id;
    DELETE FROM public.attachment_compatibility_cache WHERE relationship_id = v_rel.id;
    DELETE FROM public.ask2_state WHERE relationship_id = v_rel.id;
  END LOOP;

  -- The person's own media. Their messages, clips and dating photos go in
  -- the cascade; queue now so nothing depends on trigger order there.
  PERFORM public.queue_media_deletion('message-media', m.media_url),
          public.queue_media_deletion('message-media', m.media_thumbnail_url)
  FROM public.messages m WHERE m.sender_id = p_user_id;
  PERFORM public.queue_media_deletion('message-media', c.media_url)
  FROM public.streak_clips c JOIN public.messages m ON m.id = c.message_id
  WHERE m.sender_id = p_user_id;
  PERFORM public.queue_media_deletion('dating-profile-photos', p.storage_key)
  FROM public.dating_profile_photos p WHERE p.user_id = p_user_id;
  -- Uploads never attached to anything: no row names them (review I5).
  PERFORM public.queue_media_deletion('message-media', i.storage_key)
  FROM public.message_media_upload_intents i WHERE i.requester_id = p_user_id;
  PERFORM public.queue_media_deletion('dating-profile-photos', i.storage_key)
  FROM public.dating_photo_upload_intents i WHERE i.user_id = p_user_id;
  PERFORM public.queue_media_deletion('story-media', i.storage_key)
  FROM public.story_media_upload_intents i WHERE i.requester_id = p_user_id;
  PERFORM public.queue_media_deletion('relationship-avatars', i.storage_key)
  FROM public.relationship_avatar_upload_intents i WHERE i.requester_id = p_user_id;
  -- Their downloads (Spec 3c; data_export_jobs is created in 20261018120000,
  -- resolved when this runs): every part of every job goes now, then the jobs.
  IF to_regclass('public.data_export_jobs') IS NOT NULL THEN
    EXECUTE $q$
      UPDATE public.media_deletion_queue q SET not_before = now(), deleted_at = NULL
      FROM public.data_export_jobs j
      WHERE j.user_id = $1 AND q.bucket_id = 'data-exports' AND q.object_name LIKE j.id::text || '/%'
    $q$ USING p_user_id;
    EXECUTE 'DELETE FROM public.data_export_jobs WHERE user_id = $1' USING p_user_id;
  END IF;
END;
$function$;

INSERT INTO public.metric_key_prefixes (prefix, owner_spec) VALUES ('dating.', 'spec2')
ON CONFLICT (prefix) DO NOTHING;

REVOKE ALL ON FUNCTION public.prepare_account_deletion(uuid) FROM PUBLIC, anon, authenticated;

COMMIT;
```

Create `supabase/migrations/20261106120010_dating_v2_account_deletion_grants.sql` with exactly:

```sql
-- Spec 2 W1a: grants for 20261106120000_dating_v2_account_deletion.sql.
-- prepare_account_deletion stays the service role's (delete-account and
-- purge-recovery-holds), as 20261018110100 left it; the metric tables keep
-- Spec 1's grants (no client reads or writes them).
BEGIN;
SET LOCAL lock_timeout = '5s';
REVOKE ALL ON FUNCTION public.prepare_account_deletion(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.prepare_account_deletion(uuid) TO service_role;
COMMIT;
```

- [ ] **Step 3: Apply each file twice; diff the body; run the contracts**

```bash
for i in 1 2; do
  for f in 20261106120000_dating_v2_account_deletion 20261106120010_dating_v2_account_deletion_grants; do
    psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/migrations/$f.sql > /dev/null 2>&1; echo "$f exit=$?"
  done
done
```

```bash
D=.superpowers/sdd/2026-11-06-spec2-w1
for sig in 'public.prepare_account_deletion(uuid)'; do
  echo "== $sig"
  diff "$D/before/$sig.sql" <(psql -X -d attune_spec3a -Atc "select pg_get_functiondef('$sig'::regprocedure)") | grep '^[<>]'
done
```

```bash
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/dating_v2_identity_contracts.sql 2>&1 | grep -E 'ERROR|all held' | head -1 | sed -E 's/^psql:[^ ]* //'
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/account_deletion_contracts.sql 2>&1 | grep -E 'ERROR|all held' | head -1 | sed -E 's/^psql:[^ ]* //'
psql -X -d attune_spec3a -Atc "select prefix || ' ' || owner_spec from public.metric_key_prefixes where prefix = 'dating.'"
```

Expected: four `exit=0` lines; the diff is only added lines (the carry-over block before the relationship loop and the one new variable):

```text
== public.prepare_account_deletion(uuid)
>   v_hmac text; -- Spec 2 W1a
>   -- Spec 2 W1a (§6.3, R5): Dating carry-over, before anything is deleted.
>   -- Every HMAC comes from dating_phone_hmac_for_user (the pre-park one for
>   -- a parked account, I-11). Step 1 must succeed: a deletion that would
>   -- drop a live restriction is refused and retried, never completed.
>   -- Steps 2-4 each run in their own block, warn and continue.
>   v_hmac := public.dating_phone_hmac_for_user(p_user_id);
>   IF v_hmac IS NULL AND EXISTS (
>        SELECT 1 FROM public.dating_account_restrictions AS dar
>         WHERE dar.user_id = p_user_id AND dar.lifted_at IS NULL
>           AND (dar.ends_at IS NULL OR dar.ends_at > now())) THEN
>     RAISE EXCEPTION 'deletion:enforcement_key_missing';
>   END IF;
>   -- 1. Each live restriction becomes an enforcement record (once).
>   INSERT INTO public.enforcement_records (phone_hmac, scope, source_restriction_id, restriction_type,
>                                           category, confirmed_report_count, effect_until, purge_after)
>   SELECT v_hmac, 'dating', dar.id, dar.restriction_type, to_jsonb(dar) ->> 'category',
>          (SELECT count(*) FROM public.dating_reports AS r
>            WHERE r.target_user_id = p_user_id AND to_jsonb(r) ->> 'state' = 'upheld')::int,
>          dar.ends_at, now() + interval '2 years'
>     FROM public.dating_account_restrictions AS dar
>    WHERE dar.user_id = p_user_id AND dar.lifted_at IS NULL
>      AND (dar.ends_at IS NULL OR dar.ends_at > now())
>   ON CONFLICT (source_restriction_id) DO NOTHING;
>   -- 2. Block pairs by number, kept 2 years from now.
>   BEGIN
>     IF v_hmac IS NOT NULL THEN
>       INSERT INTO public.dating_block_hmacs (blocker_hmac, blocked_hmac)
>       SELECT h.blocker, h.blocked
>         FROM (SELECT public.dating_phone_hmac_for_user(b.blocker_user_id) AS blocker,
>                      public.dating_phone_hmac_for_user(b.blocked_user_id) AS blocked
>                 FROM public.dating_blocks AS b
>                WHERE p_user_id IN (b.blocker_user_id, b.blocked_user_id)) AS h
>        WHERE h.blocker IS NOT NULL AND h.blocked IS NOT NULL
>       ON CONFLICT (blocker_hmac, blocked_hmac) DO NOTHING;
>       UPDATE public.dating_block_hmacs
>          SET purge_after = now() + interval '2 years'
>        WHERE v_hmac IN (blocker_hmac, blocked_hmac);
>     END IF;
>   EXCEPTION WHEN OTHERS THEN
>     RAISE WARNING 'dating_deletion:block_pairs:%', SQLSTATE;
>   END;
>   -- 3. Matches close (account_deleted) and stay sealed for 30 days; the
>   --    cascade sets their member ids to NULL.
>   BEGIN
>     UPDATE public.dating_matches AS m
>        SET state = CASE WHEN m.state = 'active' THEN 'closed' ELSE m.state END,
>            closed_reason = CASE WHEN m.state = 'active' THEN 'account_deleted' ELSE m.closed_reason END,
>            closed_at = coalesce(m.closed_at, now()),
>            evidence_until = CASE WHEN m.state = 'active' OR m.evidence_until IS NULL
>                                  THEN now() + interval '30 days' ELSE m.evidence_until END
>      WHERE p_user_id IN (m.user_low_id, m.user_high_id);
>   EXCEPTION WHEN OTHERS THEN
>     RAISE WARNING 'dating_deletion:matches:%', SQLSTATE;
>   END;
>   -- 4. Reports about the person keep the number's HMAC (the cascade sets
>   --    reporter and target ids to NULL).
>   BEGIN
>     UPDATE public.dating_reports AS r
>        SET target_phone_hmac = v_hmac
>      WHERE r.target_user_id = p_user_id AND r.target_phone_hmac IS NULL AND v_hmac IS NOT NULL;
>   EXCEPTION WHEN OTHERS THEN
>     RAISE WARNING 'dating_deletion:reports:%', SQLSTATE;
>   END;
>   -- 5. The cascade removes everything else (profile, photos via the media
>   --    queue below, introductions, the never-introduce list, ...).
> 
```

then `NOTICE:  dating_v2_identity_contracts: all held`, `NOTICE:  account_deletion_contracts: all held`, `dating. spec2`.

- [ ] **Step 4: Mutation checks (mutant 16 is `no_enforcement_record`)**

Create `.superpowers/sdd/2026-11-06-spec2-w1/mut_T4.py` with exactly:

```python
MUTS = {
 'no_enforcement_record': ('CUT', ("  -- 1. Each live restriction becomes an enforcement record (once).\n", "  ON CONFLICT (source_restriction_id) DO NOTHING;\n")),
 'no_key_guard': ("""    RAISE EXCEPTION 'deletion:enforcement_key_missing';""", """    NULL;"""),
 'carries_lifted': ("""   WHERE dar.user_id = p_user_id AND dar.lifted_at IS NULL
     AND (dar.ends_at IS NULL OR dar.ends_at > now())
  ON CONFLICT""", """   WHERE dar.user_id = p_user_id
  ON CONFLICT"""),
 'no_block_purge': ("""      UPDATE public.dating_block_hmacs
         SET purge_after = now() + interval '2 years'
       WHERE v_hmac IN (blocker_hmac, blocked_hmac);
""", ""),
 'no_block_backfill': ("""      INSERT INTO public.dating_block_hmacs (blocker_hmac, blocked_hmac)
      SELECT h.blocker, h.blocked
        FROM (SELECT public.dating_phone_hmac_for_user(b.blocker_user_id) AS blocker,
                     public.dating_phone_hmac_for_user(b.blocked_user_id) AS blocked
                FROM public.dating_blocks AS b
               WHERE p_user_id IN (b.blocker_user_id, b.blocked_user_id)) AS h
       WHERE h.blocker IS NOT NULL AND h.blocked IS NOT NULL
      ON CONFLICT (blocker_hmac, blocked_hmac) DO NOTHING;
""", ""),
 'matches_not_sealed': ("""           evidence_until = CASE WHEN m.state = 'active' OR m.evidence_until IS NULL
                                 THEN now() + interval '30 days' ELSE m.evidence_until END
""", """           evidence_until = m.evidence_until
"""),
 'reports_lose_hmac': ("""       SET target_phone_hmac = v_hmac
""", """       SET target_phone_hmac = NULL
"""),
}
```

```bash
D=.superpowers/sdd/2026-11-06-spec2-w1
python3 -I $D/mutate.py supabase/migrations/20261106120000_dating_v2_account_deletion.sql supabase/tests/dating_v2_identity_contracts.sql $D/mut_T4.py $D
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/dating_v2_identity_contracts.sql 2>&1 | grep -E 'ERROR|all held' | head -1 | sed -E 's/^psql:[^ ]* //'
```

Expected:

- `no_enforcement_record`: `ERROR:  CONTRACT VIOLATED: the live restriction was not carried exactly once as a 2-year enforcement record`
- `no_key_guard`: `ERROR:  CONTRACT VIOLATED: a deletion without the key went ahead with a live restriction: ERROR: null value in column "phone_hmac" of relation "enforcement_records" viola`
- `carries_lifted`: `ERROR:  CONTRACT VIOLATED: the live restriction was not carried exactly once as a 2-year enforcement record`
- `no_block_purge`: `ERROR:  CONTRACT VIOLATED: the block pairs did not survive the deletion with a 2-year purge`
- `no_block_backfill`: `ERROR:  CONTRACT VIOLATED: the block pairs did not survive the deletion with a 2-year purge`
- `matches_not_sealed`: `ERROR:  CONTRACT VIOLATED: the match did not survive as a sealed, anonymised record`
- `reports_lose_hmac`: `ERROR:  CONTRACT VIOLATED: a report did not survive a deletion (with target_phone_hmac)`

then `NOTICE:  dating_v2_identity_contracts: all held`.

- [ ] **Step 5: Start the DPIA (§6.8; W10 needs it signed)**

Create `lib/architecture/DATING_MODE_DPIA.md` with exactly:

```markdown
# Dating Mode: data protection impact assessment (DPIA)

**Status:** started in Spec 2 W1a (2026-11-06); a working draft, not signed. Spec 2 W10 needs it signed by counsel and the owner before Dating is switched on in production. **Owner:** the safety owner. **Source:** `docs/superpowers/specs/2026-10-24-dating-mode-design.md` §6.8, §4.1-§4.3, §4.8; owner rulings Q4, Q5, Q16, Q17 (with the three exceptions for sign-off, R-2) and Q19b.

Every row below says what the built system does as of the batch named, so the assessment follows the code. A row marked **(open)** waits for the person named.

## 1. Processing

| Point | Answer |
|---|---|
| Purposes | Introductions between consenting adults; safety and enforcement; legal compliance. |
| Data subjects | Adults (18+ by Spec 1's date of birth, assured by liveness and facial age estimation from W4) who set up Dating; the people they block, report or list under "Never introduce me" (as phone HMACs only). |
| Categories | Identity and contact (phone, first name, age); profile (country, region, side, intention, children, prompts, photos); **special category**: gender identity, who you'd like to meet (reveals orientation, CJEU C-184/20), faith; **sensitive, not Art. 9**: marital history (owner ruling 2026-11-06, provisional until counsel confirms: not a GDPR Art. 9 category, so collected at D2 before the special-category consent, on the contract basis, and encrypted as defence in depth); **derived special category (S-5)**: introduction, interest-action, match and couple-link rows between two people, and a moderation case's routing (computed at read time, never stored); **biometric** at verification (transient, W4); messages (W6); safety and moderation records (W7). |
| Lawful basis | Explicit consent for special-category and biometric processing (GDPR / UK GDPR Art. 9(2)(a); Ghana Act 843 s.37 consent), recorded per purpose in `dating_consent_events` (`dating_terms`, `dating_opt_in`, `special_category_profile`, `special_category_faith`, `biometric_verification`); contract for the service; legitimate interests and legal obligation for safety and enforcement records. Withdrawing any consent is leaving Dating (W1d). **(open: counsel confirms each basis per country)** |

## 2. How it is stored (built in W1)

| Point | Answer |
|---|---|
| Encryption at rest | Gender identity, who you'd like to meet, faith and marital history are stored in `dating_profile_sensitive`, each value tagged with its key version and `pgp_sym_encrypt`ed (AES-256, a random session key per value, MDC integrity protection, compression off) with the Vault secret `dating_field_key` (W1c). In production the key is read from Vault only, never from a database setting (batch-6 fix round 1, M-4), so a dump or backup holds ciphertext and an encrypted key only. Interim (plan P-22): until W5a, the v1 plaintext columns `dating_profiles.gender_identity` and `dating_preferences.gender_preferences` remain for the v1 hard filter (owner-only under RLS, readable by the service role); W5a drops them. |
| Who can read it | Nobody through the API: the table is revoked from `anon`, `authenticated` and `service_role`, and the two field functions are executable by no API role. Only definer functions decrypt (the own-profile reader, the setup writers, the kill switch; later generation, the export builder, the fairness job and the console's routing check). The CI canary (`dating_rls_canary.sql`) fails if any other service-role path can decrypt (S-4). |
| Pair data | `dating_introductions`, `dating_interest_actions` and `dating_matches` are revoked from `service_role` too (W1a); no edge function reads them. |
| Phone numbers | Every Dating phone HMAC comes from `auth.users.phone` (`dating_phone_hmac_for_user`, W1a), never from the client-writable mirror; a parked account uses the HMAC of its real number taken before the park (Spec 1 I-11). |
| Logs | `get_dating_operational_health().log_settings_safe` reports whether Postgres can log RPC parameters (W1d). It must read `true` on the production project (W1 gate). |
| Residual risks | A live `postgres`-level attacker can decrypt; VPNs hide travellers (W8); a real person can pass liveness and act in bad faith; third parties can relay what they see; a restriction placed while `dating_exclusion_key` was missing and never stamped afterwards (or on an account parked before the key existed) carries nothing at deletion (the deletion completes and counts `dating.deletion.uncarried` once, PF-F6); a person who changes number after being restricted is not followed onto the new number at deletion (the restriction carries under the number it was placed under, batch-3 I-1); an encrypted answer is not bound to its owner or column, so a `postgres`-level writer (or a faulty definer function) could copy or restore a value under another row and it would still decrypt (batch-6 M-6; no API role can write the table). |

## 3. Retention and what survives deletion

| Data | Kept | Then |
|---|---|---|
| Profile, preferences, sensitive answers, prompts, settings, photos, private reflections, introductions, session context | while Dating is set up | hard-deleted at exit (`exit_dating_mode`, W1d) or account deletion |
| Conversations (matches now; messages from W6) | while active; after exit or deletion: sealed 30 days (`evidence_until`) | deleted (purge from W6c) — **Q17 exception 1 (open: counsel)** |
| "Never introduce me" list | while in Dating; at exit only if the person ticks "Keep my list" (unticked by default) | deleted with the account — **Q17 exception 2 (open: counsel)** |
| Consent events | the account's life + 1 year after exit (proof of consent and withdrawal) | deleted — **Q17 exception 3; the minimum is counsel's (open)** |
| Enforcement records (live restrictions at deletion), block pairs by HMAC | 2 years after the account's deletion (`purge_after`) | deleted — **Q5 (open: counsel confirms 2 years for Ghana and the UK)** |
| Reports (pseudonymised (HMAC): user ids set to NULL; the target's number kept only as its HMAC, re-identifiable with `dating_exclusion_key`; the category and the reporter's free-text details kept as evidence for a carried restriction — counsel decides whether W7a nulls details once the case closes) | 2 years | deleted |
| Former-partner exclusions (the deleted person's number as its HMAC, as recorded when the relationship ended — never the number held at deletion, batch-3 I-1 — kept against each ex who still has an account, so that ex is never introduced to the number) | while the ex's account exists (no 2-year bound) | deleted with the ex's account — **open: counsel (§7)** |
| Restriction stamps (`private.dating_restriction_hmacs`: each Dating restriction's number as its HMAC, recorded when the restriction is placed; the enforcement record is written under it, never under the number held at deletion, batch-3 I-1) | while the restriction exists | deleted with the restriction or the account; carried into the enforcement record above |
| Report evidence snapshots (W7a) | as long as an enforcement record they support | deleted with it — **(open, W7)** |
| Moderation cases and actions (W7b) | 2 years | deleted — **(open, W7)** |
| Law-enforcement request log (W7c) | 2 years | deleted — **(open, W7)** |
| Safety events | 90 days | stripped of identifiers per `SAFETY_SYSTEM_SPEC.md` §4.2 — **(open, W7)** |
| Verification sessions (W4) | 30 days | deleted — **(open, W4)** |
| Photos held for human review (W3c/W4) | at most 72 hours | deleted — **(open, W4)** |
| Introductions' actions and reasons (§6.8 minimisation) | until 30 days after the introduction is resolved | deleted (the introduction row keeps no reason) — **(open, W5)** |
| Age assurance result | while the account exists | deleted with the account |

The privacy policy must name the survivors (enforcement records, block pairs, pseudonymised (HMAC) reports with the reporter's details; 2 years; former-partner exclusions of the number recorded at the relationship's end, while the ex's account exists) — **open: counsel's wording, W1 gate**.

## 4. Minimisation

No GPS, distance or neighbourhood; region and an optional side only (others see the region, never the side). No ethnicity, tribe, income, job, education, politics, height, health or zodiac fields. Quiz, Healing and journal data are never read by Dating. Where same-gender introductions are off (Ghana and every Tier 1/2 country), the server refuses a same-gender answer without storing, counting or logging it, and the kill switch deletes such answers in one transaction when a country turns it off (W1d). No repeat-pair history is kept for deleted accounts.

## 5. Risks and controls

| Risk | Control (batch) |
|---|---|
| Outing and entrapment | same-gender off in Tier 1/2, nothing stored there, kill switch (W1b-W1d); traveller hiding (W8) |
| Compelled disclosure | minimal retention (above); law-enforcement policy (W7c) |
| Breach | field encryption, RLS and grant canaries, bucket test, secret scanning in CI (W1a), penetration test (W10) |
| Insider | no API role reads special-category data; console without sensitive fields, read-time routing and an append-only audit log (W7b) |
| Re-identification in thin pools | no side shown, no counts, metrics only at n >= 50 |
| Minors | Spec 1 DOB + age assurance (W4), holds, CSAM hash matching on every Dating photo before approval (W3c) |
| Biometric misuse | no templates, no kept videos or ID images; vendor deletion terms (W4 contracts) |
| Unfair exposure | fairness job (W5c) |

## 6. Transfers, registrations, rights

- **Transfers:** the Supabase project region; AWS Rekognition in an EU/UK region; the estimation and ID vendors' regions and retention, per contract (W4). **(open)**
- **Registrations:** Ghana DPC registration; a UK representative if the controller is outside the UK; an EU Art. 27 representative before any EU country opens. **(open: W10 gate)**
- **Rights:** export of one's own Dating data (W9); deletion (exit, account deletion); correction (DOB through Spec 1, everything else in Dating settings); withdrawal of consent = leaving Dating.
- **US (later):** BIPA written release, Texas CUBI consent, and a public retention and destruction schedule before any US user verifies.

## 7. Sign-off

| Who | What | Date | Reference |
|---|---|---|---|
| Counsel | retention (2 years), former-partner exclusions kept while the ex's account exists, consent minimum, Q17 exceptions, privacy-policy line | | |
| Counsel | lawful basis per country, transfers | | |
| Safety owner | risks and controls | | |
| Owner | accepts the residual risks | | |
```

- [ ] **Step 6: The local harness (edit only, never run)**

`scripts/local_pg_grants.sql`: append after the last line (`\i supabase/migrations/20261106110010_dating_v2_enforcement_survival_grants.sql`), exactly:

```sql

-- Spec 2 W1a: prepare_account_deletion stays the service role's.
\i supabase/migrations/20261106120010_dating_v2_account_deletion_grants.sql
```

```bash
python3 -I - <<'PY'
import pathlib
p = pathlib.Path('scripts/local_pg_grants.sql')
s = p.read_text()
assert s.endswith('\\i supabase/migrations/20261106110010_dating_v2_enforcement_survival_grants.sql' + chr(10))
p.write_text(s + chr(10) + "-- Spec 2 W1a: prepare_account_deletion stays the service role's." + chr(10) + '\\i supabase/migrations/20261106120010_dating_v2_account_deletion_grants.sql' + chr(10))
print('local_pg_grants.sql: one \\i block added')
PY
```

- [ ] **Step 7: Run tests (the W1a gate)**

```bash
D=.superpowers/sdd/2026-11-06-spec2-w1
for f in supabase/tests/*.sql; do
  if psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f "$f" >/dev/null 2>&1; then echo "PASS $(basename "$f")"; else echo "FAIL $(basename "$f")"; fi
done > $D/sql-after-task4.txt
grep '^FAIL' $D/sql-after-task4.txt | sort | comm -13 <(cat $D/sql-baseline*.txt | grep '^FAIL' | sort -u) - | grep -vE 'FAIL ai_(session|assist|assistant|processing)_'
grep '^FAIL' $D/sql-after-task4.txt | sort | comm -13 <(cat $D/sql-baseline*.txt | grep '^FAIL' | sort -u) - | grep -E 'FAIL ai_' | sed 's/^FAIL //' | while read t; do
  echo "$t: $(psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/$t 2>&1 | grep -m1 ERROR | grep -ci dating) Dating mentions"
done
git status --short -- lib test | head
sed -n '/if (isAuthenticated \&\& !_gateData.isComplete) {/,/_redirectingToOnboarding = false;/p' lib/home/home_screen.dart | shasum | diff - $D/latch.sha && echo latch-unchanged
flutter test test/architecture/games_untouched_test.dart 2>&1 | tail -1
```

Expected: no line from the first `grep` (no new FAIL outside the AI-session group); for any AI-session file the loop prints, `0 Dating mentions`; no `git status` line; `latch-unchanged`; `All tests passed!`. The W1 contracts so far (`dating_v2_identity_contracts`, `dating_rls_canary`, `storage_bucket_policies`) and `dating_mode_contracts`, `dating_exclusion_wiring_test`, `service_role_grants_test`, `account_deletion_contracts`, `identity_foundation_contracts`, `dormancy_contracts` are `PASS` in `$D/sql-after-task4.txt`.

**W1a gate (owner, before production switch-on; recorded in the checklist):** counsel signs the 2-year retention of enforcement records and block pairs, the Q17 exceptions and the privacy-policy line (checklist 5); the DPIA is started (Step 5).

# W1b · Country configuration, availability, public config, eligibility (Tasks 5-7)

### Task 5: Migration 4: the country model, the session context, Spec 1's open-country seam (§4.9 W1b #1, §2.2, §2.3, §2.7, I-3, R-6, R18; P-13-P-17, P-19)

**Files:**
- Create: `supabase/migrations/20261106130000_dating_v2_country_config.sql`, `…130010_dating_v2_country_config_grants.sql`, `supabase/tests/country_safety_config_contracts.sql`
- Modify: `supabase/tests/dating_rls_canary.sql`, `supabase/tests/identity_foundation_contracts.sql` (three lines, P-13, P-19), `scripts/local_pg_grants.sql`

**Interfaces:**
- Consumes: `private.attune_environment()`, `private.flag_production_gates`, `public.app_public_config`, the live `private.dating_open_countries()`, `get_public_app_config()` (read, never edited), `dating_flag_enabled`.
- Produces: `public.country_safety_config` + seeds; `public.dating_country_config(text)`; `private.country_config_checks(country_safety_config) → text[]`; `public.publish_country_config(text, jsonb) → jsonb` (service role; `config:kill_switch_pending` until Task 13); `public.get_dating_availability() → jsonb` (anon, authenticated); `private.dating_phone_country(text)`; `public.dating_session_context`; `public.dating_effective_context(text, text, text, text) → jsonb`; `public.record_dating_session_context(uuid, text, text) → jsonb` (service role); `public.dating_notify_requests`; flag `dating_same_gender_matching` (false); six gate rows; the re-created seam.

- [ ] **Step 1: Write the failing contract**

Create `supabase/tests/country_safety_config_contracts.sql` with exactly:

```sql
-- supabase/tests/country_safety_config_contracts.sql
-- Spec 2 W1b and W1d (§2.2, §2.3, §2.4, §7.1, §7.5; R-6, I-3, Q19b): the
-- seeds (A), immutable rows (B), the environment and production-mode
-- refusals (C), public-config parity (D), turning same-gender off (E: W1b
-- refuses it until W1d's kill switch replaces the section), the effective
-- context (F; the away streak F2 from W1c), validation (G) and the dev
-- script's refusal in production mode (H).
-- One BEGIN ... ROLLBACK. Run only on attune_spec3a, FROM THE REPO ROOT
-- (section H reads supabase/sql/dev_enable_spec2_dating_flags.sql):
--   psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/country_safety_config_contracts.sql
-- Fixture ids 5e2b0000-0000-0000-0000-0000000000NN; phones 15558701NN.
BEGIN;

DO $$
BEGIN
  PERFORM set_config('app.settings.attune_environment', '', true);
  PERFORM set_config('app.settings.supabase_url', '', true);
  PERFORM set_config('app.settings.dating_exclusion_key', 'spec2-w1b-contract-exclusion-key', true);
END $$;

CREATE FUNCTION pg_temp.id(p_n text) RETURNS uuid LANGUAGE sql IMMUTABLE AS $$
  SELECT ('5e2b0000-0000-0000-0000-0000000000' || p_n)::uuid;
$$;

CREATE FUNCTION pg_temp.as_owner() RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  RESET ROLE;
  PERFORM set_config('request.jwt.claims', '', true);
END $$;

-- publish_country_config as the service role (its only caller).
CREATE FUNCTION pg_temp.publish(p_country text, p_values jsonb) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
  v jsonb;
BEGIN
  EXECUTE 'SET LOCAL ROLE service_role';
  v := public.publish_country_config(p_country, p_values);
  PERFORM pg_temp.as_owner();
  RETURN v;
END $$;

CREATE FUNCTION pg_temp.current(p_country text) RETURNS public.country_safety_config LANGUAGE sql AS $$
  SELECT * FROM public.country_safety_config WHERE country_code = p_country AND is_current;
$$;

-- Anon's view of the two public reads.
CREATE FUNCTION pg_temp.anon_config() RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
  v jsonb;
BEGIN
  EXECUTE 'SET LOCAL ROLE anon';
  v := jsonb_build_object('public', public.get_public_app_config(), 'availability', public.get_dating_availability());
  PERFORM pg_temp.as_owner();
  RETURN v;
END $$;

-- The message [p_sql] raised (as the owner), or NULL.
CREATE FUNCTION pg_temp.err(p_sql text) RETURNS text LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE p_sql;
  RETURN NULL;
EXCEPTION WHEN raise_exception THEN
  RETURN SQLERRM;
END $$;

CREATE TEMP TABLE public_before (config jsonb) ON COMMIT DROP;
INSERT INTO public_before SELECT pg_temp.anon_config() -> 'public';

-- =====================================================================
-- A. Seeds: one current row per country, every one closed (R-6).
-- =====================================================================
DO $$
DECLARE
  v_gh public.country_safety_config := pg_temp.current('GH');
  v_gb public.country_safety_config := pg_temp.current('GB');
  v_fr public.country_safety_config := public.dating_country_config('fr');
BEGIN
  IF (SELECT count(*) FROM public.country_safety_config WHERE version = 1) IS DISTINCT FROM 73
     OR EXISTS (SELECT 1 FROM public.country_safety_config GROUP BY country_code HAVING count(*) FILTER (WHERE is_current) IS DISTINCT FROM 1)
     OR EXISTS (SELECT 1 FROM public.country_safety_config WHERE version = 1 AND dating_enabled) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the seeds are not 73 closed rows with one current row each';
  END IF;
  IF (SELECT count(*) FROM public.country_safety_config WHERE version = 1 AND tier = 1) IS DISTINCT FROM 28
     OR (SELECT count(*) FROM public.country_safety_config WHERE version = 1 AND tier = 2) IS DISTINCT FROM 44
     OR EXISTS (SELECT 1 FROM public.country_safety_config WHERE tier IN (1, 2) AND same_gender_enabled)
     OR (SELECT tier FROM public.country_safety_config WHERE country_code = 'NE' AND version = 1) IS DISTINCT FROM 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the Tier 1/2 seeds are wrong (28 + 44, same-gender off, Niger Tier 1)';
  END IF;
  IF v_gh.tier IS DISTINCT FROM 1 OR v_gh.open_regions IS DISTINCT FROM ARRAY['AA', 'AH'] OR v_gh.same_gender_enabled
     OR jsonb_array_length(v_gh.region_list) IS DISTINCT FROM 16 OR v_gh.reference_tz IS DISTINCT FROM 'Africa/Accra' OR v_gh.generation_hour_utc IS DISTINCT FROM 3
     OR (SELECT jsonb_agg(s ->> 'code' ORDER BY s ->> 'code') FROM jsonb_array_elements(v_gh.region_list) AS r,
                jsonb_array_elements(r -> 'sides') AS s) IS DISTINCT FROM '["accra", "kumasi", "outside_kumasi", "tema"]'::jsonb
     OR jsonb_array_length(v_gh.id_documents) IS DISTINCT FROM 2 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the Ghana seed is wrong';
  END IF;
  IF v_gb.tier IS DISTINCT FROM 3 OR v_gb.open_regions IS NOT NULL OR NOT v_gb.same_gender_enabled
     OR jsonb_array_length(v_gb.region_list) IS DISTINCT FROM 12 OR v_gb.reference_tz IS DISTINCT FROM 'Europe/London' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the UK seed is wrong';
  END IF;
  IF v_fr.version IS DISTINCT FROM 0 OR v_fr.tier IS DISTINCT FROM 3 OR v_fr.dating_enabled OR NOT v_fr.same_gender_enabled
     OR public.dating_country_config('X1') IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a country with no row does not resolve to the default (tier 3, closed, same-gender allowed)';
  END IF;
  IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid = 'public.country_safety_config'::regclass)
     OR has_table_privilege('anon', 'public.country_safety_config', 'SELECT')
     OR has_table_privilege('authenticated', 'public.country_safety_config', 'SELECT')
     OR has_function_privilege('authenticated', 'public.publish_country_config(text,jsonb)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.publish_country_config(text,jsonb)', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'public.publish_country_config(text,jsonb)', 'EXECUTE')
     OR NOT has_function_privilege('anon', 'public.get_dating_availability()', 'EXECUTE')
     OR has_function_privilege('service_role', 'public.record_dating_session_context(uuid,text,text)', 'EXECUTE') IS NOT TRUE THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the country config grants are wrong';
  END IF;
  IF (SELECT enabled FROM public.feature_flags WHERE key = 'dating_same_gender_matching') IS DISTINCT FROM false
     OR (SELECT count(*) FROM private.flag_production_gates
          WHERE flag_key IN ('dating_mode_enabled', 'dating_candidate_generation', 'dating_match_messaging',
                             'dating_profile_photos', 'dating_alignment_algorithm_v1', 'dating_same_gender_matching')) IS DISTINCT FROM 6 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: dating_same_gender_matching is not inserted off, or a Dating flag has no production gate row';
  END IF;
END $$;

-- =====================================================================
-- B. A published row never changes and is never deleted.
-- =====================================================================
DO $$
BEGIN
  IF pg_temp.err('UPDATE public.country_safety_config SET tier = 3 WHERE country_code = ''NG'' AND version = 1')
       IS DISTINCT FROM 'config:immutable'
     OR pg_temp.err('UPDATE public.country_safety_config SET is_current = false, dating_enabled = true WHERE country_code = ''NG''')
       IS DISTINCT FROM 'config:immutable'
     OR pg_temp.err('DELETE FROM public.country_safety_config WHERE country_code = ''NG''')
       IS DISTINCT FROM 'config:immutable' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a published country row could be changed or deleted';
  END IF;
END $$;

-- =====================================================================
-- C. Environment (R-6): development reports the checks, production
--    enforces them.
-- =====================================================================
DO $$
DECLARE
  v jsonb;
  v_evidence constant jsonb := '{"osa_illegal_harms_assessment": "REF-1", "osa_childrens_access_assessment": "REF-2",
    "highly_effective_age_assurance": "REF-3", "dpia": "REF-4", "pen_test": "REF-5",
    "safety_owner_and_moderator": "REF-6", "reviewer_signoffs": "REF-7"}';
BEGIN
  IF private.attune_environment() IS DISTINCT FROM 'development' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: with attune_environment unset the project does not read development';
  END IF;
  v := pg_temp.publish('GH', '{"dating_enabled": true, "published_by": "contract"}');
  IF (v ->> 'ok')::boolean IS NOT TRUE OR (v ->> 'version')::int IS DISTINCT FROM 2
     OR v -> 'checks' IS DISTINCT FROM '["evidence_missing", "resources_not_verified"]'::jsonb
     OR NOT (pg_temp.current('GH')).dating_enabled
     OR (SELECT is_current FROM public.country_safety_config WHERE country_code = 'GH' AND version = 1) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: development did not publish GH with the checks reported: %', v;
  END IF;

  PERFORM set_config('app.settings.attune_environment', 'production', true);
  v := pg_temp.publish('GB', '{"dating_enabled": true}');
  IF v IS DISTINCT FROM '{"ok": false, "reason": "config:production_checks_failed", "checks": ["evidence_missing", "resources_not_verified"]}'::jsonb
     OR (pg_temp.current('GB')).version IS DISTINCT FROM 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: production published Dating on without evidence: %', v;
  END IF;
  v := pg_temp.publish('GB', jsonb_build_object('dating_enabled', true, 'legal_checklist', v_evidence,
                                                 'resources_verified_at', now() - interval '91 days'));
  IF v ->> 'reason' IS DISTINCT FROM 'config:production_checks_failed' OR v -> 'checks' IS DISTINCT FROM '["resources_not_verified"]'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: production accepted support resources verified over 90 days ago: %', v;
  END IF;
  v := pg_temp.publish('GB', jsonb_build_object('dating_enabled', true, 'legal_checklist', v_evidence || '{"pen_test": " "}',
                                                 'resources_verified_at', now()));
  IF v -> 'checks' IS DISTINCT FROM '["evidence_missing"]'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: production accepted a blank evidence reference: %', v;
  END IF;
  v := pg_temp.publish('NG', '{"same_gender_enabled": true}');
  IF v -> 'checks' IS DISTINCT FROM '["same_gender_reconsideration_missing"]'::jsonb OR (pg_temp.current('NG')).same_gender_enabled THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: production turned same-gender on in a Tier 1 country without the reconsideration: %', v;
  END IF;
  v := pg_temp.publish('NG', '{"same_gender_enabled": true, "legal_checklist": {"same_gender_reconsideration":
          {"legal_opinion": "REF-A", "lgbtq_consultation": "REF-B", "tier1_protections": ""}}}');
  IF v -> 'checks' IS DISTINCT FROM '["same_gender_reconsideration_missing"]'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: production accepted a blank Tier 1 protections reference: %', v;
  END IF;
  v := pg_temp.publish('GB', jsonb_build_object('dating_enabled', true, 'legal_checklist', v_evidence,
                                                 'resources_verified_at', now()));
  IF (v ->> 'ok')::boolean IS NOT TRUE OR v -> 'checks' IS DISTINCT FROM '[]'::jsonb OR NOT (pg_temp.current('GB')).dating_enabled THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: production refused a fully evidenced publish: %', v;
  END IF;
  -- A country with no row has an empty checklist: never "every key has
  -- evidence".
  v := pg_temp.publish('FR', jsonb_build_object('dating_enabled', true, 'resources_verified_at', now()));
  IF v -> 'checks' IS DISTINCT FROM '["evidence_missing"]'::jsonb OR (public.dating_country_config('FR')).version IS DISTINCT FROM 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: production opened a country with an empty legal checklist: %', v;
  END IF;
  -- Closing a country needs no evidence.
  v := pg_temp.publish('GB', '{"dating_enabled": false}');
  IF (v ->> 'ok')::boolean IS NOT TRUE OR (pg_temp.current('GB')).dating_enabled THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: production refused to close a country: %', v;
  END IF;
  PERFORM set_config('app.settings.attune_environment', '', true);
END $$;

-- =====================================================================
-- D. Public config (I-3): the seam reads the table; the interim row is
--    gone; a close drops the country in the same transaction; every
--    other key of get_public_app_config is unchanged.
-- =====================================================================
DO $$
DECLARE
  v jsonb;
  v_before jsonb := (SELECT config FROM public_before);
BEGIN
  IF EXISTS (SELECT 1 FROM public.app_public_config WHERE key = 'dating_open_countries') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the interim app_public_config row is still there';
  END IF;
  IF v_before #> '{config,dating_open_countries}' IS DISTINCT FROM '[]'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: with every seed closed the open-country list is %', v_before #> '{config,dating_open_countries}';
  END IF;
  PERFORM pg_temp.publish('GB', '{"dating_enabled": true}');
  v := pg_temp.anon_config();
  IF v #> '{public,config,dating_open_countries}' IS DISTINCT FROM '["GB", "GH"]'::jsonb
     OR (SELECT jsonb_agg(c ->> 'code' ORDER BY c ->> 'code') FROM jsonb_array_elements(v #> '{availability,countries}') AS c)
          IS DISTINCT FROM v #> '{public,config,dating_open_countries}'
     OR v #> '{availability,countries}' IS DISTINCT FROM
          '[{"code": "GB", "open_regions": null},
            {"code": "GH", "open_regions": [{"code": "AA", "name_key": "dating_region_gh_aa"},
                                            {"code": "AH", "name_key": "dating_region_gh_ah"}]}]'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the public open-country list and get_dating_availability disagree: %', v;
  END IF;
  PERFORM pg_temp.publish('GB', '{"dating_enabled": false}');
  v := pg_temp.anon_config();
  IF v #> '{public,config,dating_open_countries}' IS DISTINCT FROM '["GH"]'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: closing GB did not drop it from the public list in the same transaction: %', v;
  END IF;
  IF (v -> 'public') #- '{config,dating_open_countries}' IS DISTINCT FROM v_before #- '{config,dating_open_countries}' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: another get_public_app_config key changed: % vs %', v -> 'public', v_before;
  END IF;
END $$;

-- =====================================================================
-- E. Same-gender off before W1d's switch: refused, nothing published.
--    (W1d replaces this section with the kill switch.)
-- =====================================================================
DO $$
DECLARE
  v jsonb;
  v_version int := (pg_temp.current('GB')).version;
BEGIN
  v := pg_temp.publish('GB', '{"same_gender_enabled": false}');
  IF v IS DISTINCT FROM '{"ok": false, "reason": "config:kill_switch_pending"}'::jsonb
     OR (pg_temp.current('GB')).version IS DISTINCT FROM v_version OR NOT (pg_temp.current('GB')).same_gender_enabled THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: turning same-gender off published without the kill switch: %', v;
  END IF;
END $$;

-- =====================================================================
-- F. The effective context (§2.3) and the session row.
-- =====================================================================
DO $$
DECLARE
  v_u constant uuid := pg_temp.id('01');
  v jsonb;
BEGIN
  IF private.dating_phone_country('233244123456') IS DISTINCT FROM 'GH'
     OR private.dating_phone_country('+44 7700 900123') IS DISTINCT FROM 'GB'
     OR private.dating_phone_country('77011234567') IS DISTINCT FROM 'KZ'
     OR private.dating_phone_country('79161234567') IS DISTINCT FROM 'RU'
     OR private.dating_phone_country('18765551234') IS DISTINCT FROM 'JM'
     OR private.dating_phone_country('15551234567') IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: dating_phone_country is not the longest calling-code prefix';
  END IF;
  -- Tier: the highest (lowest number) of the four.
  IF (public.dating_effective_context('GH', 'GB', NULL, NULL) ->> 'effective_tier')::int IS DISTINCT FROM 1
     OR (public.dating_effective_context('FR', 'GB', 'FR', NULL) ->> 'effective_tier')::int IS DISTINCT FROM 3
     OR (public.dating_effective_context(NULL, 'GB', 'FR', 'KE') ->> 'effective_tier')::int IS DISTINCT FROM 2 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: effective_tier is not the highest tier of the sources';
  END IF;
  -- Allowed here: false in a closed Tier 1/2 place or network; travel to a
  -- closed Tier 3 country changes nothing; an unresolved IP falls back to
  -- the phone country.
  IF (public.dating_effective_context('GB', 'GB', 'AE', NULL) ->> 'dating_allowed_here')::boolean
     OR (public.dating_effective_context('GB', 'GB', 'GB', 'AE') ->> 'dating_allowed_here')::boolean
     OR NOT (public.dating_effective_context('GB', 'GB', 'FR', NULL) ->> 'dating_allowed_here')::boolean
     OR (public.dating_effective_context('AE', 'GB', NULL, NULL) ->> 'dating_allowed_here')::boolean THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: dating_allowed_here is wrong';
  END IF;
  -- Same-gender here: the flag, the Dating country, the place and the network.
  IF (public.dating_effective_context('GB', 'GB', 'GB', NULL) ->> 'same_gender_allowed_here')::boolean THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: same-gender was allowed with the global flag off';
  END IF;
  UPDATE public.feature_flags SET enabled = true WHERE key = 'dating_same_gender_matching';
  IF NOT (public.dating_effective_context('GB', 'GB', 'GB', NULL) ->> 'same_gender_allowed_here')::boolean
     OR (public.dating_effective_context('GB', 'GB', 'GH', NULL) ->> 'same_gender_allowed_here')::boolean
     OR (public.dating_effective_context('GB', 'GB', 'GB', 'GH') ->> 'same_gender_allowed_here')::boolean
     OR (public.dating_effective_context('GH', 'GH', 'GB', NULL) ->> 'same_gender_allowed_here')::boolean
     OR (public.dating_effective_context('GB', NULL, 'GB', NULL) ->> 'same_gender_allowed_here')::boolean
     OR (public.dating_effective_context('GH', 'GB', NULL, NULL) ->> 'same_gender_allowed_here')::boolean THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: same_gender_allowed_here is wrong (a Ghana SIM in London, a UK user in Accra, no Dating country, an unresolved IP on a Ghana phone)';
  END IF;
  UPDATE public.feature_flags SET enabled = false WHERE key = 'dating_same_gender_matching';
  IF NOT (public.dating_effective_context('GB', 'GB', 'FR', NULL) ->> 'away_from_home')::boolean
     OR (public.dating_effective_context('FR', 'GB', NULL, NULL) ->> 'away_from_home')::boolean
     OR (public.dating_effective_context('GB', NULL, 'FR', NULL) ->> 'away_from_home')::boolean
     OR (public.dating_effective_context('GB', 'GB', NULL, NULL) ->> 'ip_resolved')::boolean THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: away_from_home or ip_resolved is wrong';
  END IF;

  -- The row: one per person, overwritten (W1c adds the away streak, once
  -- profiles carry a Dating country), and the table holds no country.
  INSERT INTO auth.users (id, phone, phone_confirmed_at) VALUES (v_u, '1555870101', now());
  INSERT INTO public.users (id, phone, display_name) VALUES (v_u, '1555870101', 'Context');
  EXECUTE 'SET LOCAL ROLE service_role';
  PERFORM public.record_dating_session_context(v_u, 'FR', NULL);
  PERFORM public.record_dating_session_context(v_u, NULL, 'AE');
  PERFORM pg_temp.as_owner();
  IF (SELECT count(*) FROM public.dating_session_context WHERE user_id = v_u) IS DISTINCT FROM 1
     OR (SELECT dating_allowed_here OR ip_resolved OR away_from_home OR mismatch_streak IS DISTINCT FROM 0
           FROM public.dating_session_context WHERE user_id = v_u) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the session row is not one overwritten row of the latest check';
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public'
                AND table_name = 'dating_session_context' AND (column_name LIKE '%country%' OR column_name LIKE '%ip%address%')) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: dating_session_context stores a country or an address';
  END IF;
END $$;

-- =====================================================================
-- G. Validation: nothing is published from a malformed request.
-- =====================================================================
DO $$
DECLARE
  v_version int := (pg_temp.current('GH')).version;
BEGIN
  IF pg_temp.publish('G1', '{}') ->> 'reason' IS DISTINCT FROM 'config:invalid_country'
     OR pg_temp.publish('GH', '[]') ->> 'reason' IS DISTINCT FROM 'config:invalid_values'
     OR pg_temp.publish('GH', '{"is_current": false}') ->> 'reason' IS DISTINCT FROM 'config:unknown_key'
     OR pg_temp.publish('GH', '{"tier": 4}') ->> 'reason' IS DISTINCT FROM 'config:invalid_values'
     OR pg_temp.publish('GH', '{"tier": "x"}') ->> 'reason' IS DISTINCT FROM 'config:invalid_values'
     OR pg_temp.publish('GH', '{"reference_tz": "Mars/Base"}') ->> 'reason' IS DISTINCT FROM 'config:invalid_tz'
     OR pg_temp.publish('GH', '{"open_regions": ["AA", "ZZ"]}') ->> 'reason' IS DISTINCT FROM 'config:invalid_regions'
     OR pg_temp.publish('GH', '{"region_list": [{"code": "AA"}, {"code": "AA"}], "open_regions": null}') ->> 'reason'
          IS DISTINCT FROM 'config:invalid_regions'
     OR pg_temp.publish('GH', '{"region_list": [{"name": "no code"}]}') ->> 'reason' IS DISTINCT FROM 'config:invalid_lists' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a malformed publish was not refused with its reason';
  END IF;
  IF (pg_temp.current('GH')).version IS DISTINCT FROM v_version THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a refused publish wrote a version';
  END IF;
END $$;

DO $$ BEGIN RAISE NOTICE 'country_safety_config_contracts: all held'; END $$;
ROLLBACK;
```

- [ ] **Step 2: Run it to make sure it fails**

```bash
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/country_safety_config_contracts.sql 2>&1 | grep -E 'ERROR|all held' | head -1 | sed -E 's/^psql:[^ ]* //'
```

Expected: `ERROR:  type "public.country_safety_config" does not exist`.

- [ ] **Step 3: Write migration 4 and its twin**

Create `supabase/migrations/20261106130000_dating_v2_country_config.sql` with exactly:

```sql
-- Spec 2 W1b, migration 4 (spec §4.9 W1b #1, §2.2, §2.3, §2.7; Q1, Q2,
-- Q19b, R-6, I-3): the country model.
--   * country_safety_config: versioned, one current row per country, a
--     published row never changes (only is_current true -> false, by the
--     publisher), never deleted. Seeds: GH (tier 1, Greater Accra + Ashanti
--     open, men-women only, 16 regions, sides), GB (tier 3, 12 ITL1
--     regions, same-gender on) and every Tier 1 and Tier 2 country of
--     research 04 §2.1.6 (same-gender off). EVERY seed has dating_enabled
--     false: a migration never switches anything on (R-6); the dev script
--     opens GH and GB in development.
--   * dating_country_config(code): the current row, or the default for a
--     country with none (tier 3, Dating closed, same-gender allowed).
--   * publish_country_config(code, values) (service role): merges values
--     over the current row and publishes the next version. In production
--     mode (Spec 1's private.attune_environment()) it refuses Dating on
--     without every legal_checklist evidence reference and support
--     resources verified within 90 days, and refuses same-gender on for a
--     Tier 1/2 row without the reconsideration references; in development
--     the same checks are returned, not enforced. Turning same-gender off
--     returns config:kill_switch_pending and publishes nothing (W1d wires
--     apply_same_gender_switch); W3a adds the notify queueing.
--   * get_dating_availability() (anon and signed in): the open countries
--     and their open regions.
--   * dating_session_context (one overwritten row per user, no country
--     codes), dating_effective_context(...) and record_dating_session_context
--     (service role; called by W8b's dating-device-check).
--   * dating_notify_requests (table only; RPCs in W3a).
--   * Flag dating_same_gender_matching (false), and a production gate row
--     for it and for every existing Dating flag.
--   * Spec 1's seam private.dating_open_countries() re-created from its live
--     body (20261025100400) to read the table (same shape: sorted alpha-2
--     codes), then the interim app_public_config row deleted (I-3).
--     get_public_app_config() is not touched.
-- Grants in 20261106130010_dating_v2_country_config_grants.sql.
BEGIN;
SET LOCAL lock_timeout = '5s';

CREATE TABLE IF NOT EXISTS public.country_safety_config (
  country_code char(2) NOT NULL CHECK (country_code ~ '^[A-Z]{2}$'),
  version integer NOT NULL CHECK (version >= 1),
  is_current boolean NOT NULL DEFAULT true,
  tier smallint NOT NULL CHECK (tier BETWEEN 1 AND 3),
  dating_enabled boolean NOT NULL DEFAULT false,
  open_regions text[],
  same_gender_enabled boolean NOT NULL,
  region_list jsonb NOT NULL DEFAULT '[]'::jsonb CHECK (jsonb_typeof(region_list) = 'array'),
  faith_list jsonb NOT NULL DEFAULT '[]'::jsonb CHECK (jsonb_typeof(faith_list) = 'array'),
  id_documents jsonb NOT NULL DEFAULT '[]'::jsonb CHECK (jsonb_typeof(id_documents) = 'array'),
  generation_hour_utc smallint NOT NULL DEFAULT 3 CHECK (generation_hour_utc BETWEEN 0 AND 23),
  reference_tz text NOT NULL DEFAULT 'UTC',
  resources_verified_at timestamptz,
  legal_checklist jsonb NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(legal_checklist) = 'object'),
  source_url text,
  reviewed_at timestamptz,
  reviewed_by text,
  published_at timestamptz NOT NULL DEFAULT now(),
  published_by text NOT NULL,
  PRIMARY KEY (country_code, version)
);
CREATE UNIQUE INDEX IF NOT EXISTS country_safety_config_one_current
  ON public.country_safety_config (country_code) WHERE is_current;
ALTER TABLE public.country_safety_config ENABLE ROW LEVEL SECURITY;
COMMENT ON TABLE public.country_safety_config IS
  'Spec 2 §2.2: per-country Dating configuration, versioned. Published rows are immutable; publish_country_config (service role) writes the next version.';

CREATE OR REPLACE FUNCTION private.country_safety_config_immutable()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $fn$
BEGIN
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'config:immutable';
  END IF;
  -- The only change a published row takes: stop being current.
  IF NOT OLD.is_current OR NEW.is_current
     OR (to_jsonb(NEW) - 'is_current') IS DISTINCT FROM (to_jsonb(OLD) - 'is_current') THEN
    RAISE EXCEPTION 'config:immutable';
  END IF;
  RETURN NEW;
END;
$fn$;
DROP TRIGGER IF EXISTS country_safety_config_immutable ON public.country_safety_config;
CREATE TRIGGER country_safety_config_immutable
  BEFORE UPDATE OR DELETE ON public.country_safety_config
  FOR EACH ROW EXECUTE FUNCTION private.country_safety_config_immutable();

-- Seeds (version 1; all closed). Codes: ISO 3166-2:GH for Ghana's regions,
-- ITL1 for the UK's. name_key values are ARB keys W3b adds.
INSERT INTO public.country_safety_config
  (country_code, version, tier, dating_enabled, open_regions, same_gender_enabled, region_list,
   id_documents, generation_hour_utc, reference_tz, legal_checklist, source_url, reviewed_at,
   reviewed_by, published_by)
VALUES
  ('GH', 1, 1, false, ARRAY['AA', 'AH'], false,
   '[{"code": "AF", "name_key": "dating_region_gh_af", "sides": []},
     {"code": "AH", "name_key": "dating_region_gh_ah", "sides": [
        {"code": "kumasi", "name_key": "dating_side_gh_kumasi"},
        {"code": "outside_kumasi", "name_key": "dating_side_gh_outside_kumasi"}]},
     {"code": "BO", "name_key": "dating_region_gh_bo", "sides": []},
     {"code": "BE", "name_key": "dating_region_gh_be", "sides": []},
     {"code": "CP", "name_key": "dating_region_gh_cp", "sides": []},
     {"code": "EP", "name_key": "dating_region_gh_ep", "sides": []},
     {"code": "AA", "name_key": "dating_region_gh_aa", "sides": [
        {"code": "accra", "name_key": "dating_side_gh_accra"},
        {"code": "tema", "name_key": "dating_side_gh_tema"}]},
     {"code": "NE", "name_key": "dating_region_gh_ne", "sides": []},
     {"code": "NP", "name_key": "dating_region_gh_np", "sides": []},
     {"code": "OT", "name_key": "dating_region_gh_ot", "sides": []},
     {"code": "SV", "name_key": "dating_region_gh_sv", "sides": []},
     {"code": "UE", "name_key": "dating_region_gh_ue", "sides": []},
     {"code": "UW", "name_key": "dating_region_gh_uw", "sides": []},
     {"code": "TV", "name_key": "dating_region_gh_tv", "sides": []},
     {"code": "WP", "name_key": "dating_region_gh_wp", "sides": []},
     {"code": "WN", "name_key": "dating_region_gh_wn", "sides": []}]'::jsonb,
   '[{"code": "ghana_card", "name_key": "dating_id_ghana_card"},
     {"code": "passport", "name_key": "dating_id_passport"}]'::jsonb,
   3, 'Africa/Accra',
   '{"ghana_legal_opinion": null, "dpc_registration": null, "dpia": null, "pen_test": null,
     "safety_owner_and_moderator": null, "reviewer_signoffs": null}'::jsonb,
   'docs/superpowers/research/2026-10-24-flow-dating-research/04-dating-safety-global.md#216',
   '2026-10-24', 'spec2', 'migration:spec2-w1b'),
  ('GB', 1, 3, false, NULL, true,
   '[{"code": "TLC", "name_key": "dating_region_gb_tlc", "sides": []},
     {"code": "TLD", "name_key": "dating_region_gb_tld", "sides": []},
     {"code": "TLE", "name_key": "dating_region_gb_tle", "sides": []},
     {"code": "TLF", "name_key": "dating_region_gb_tlf", "sides": []},
     {"code": "TLG", "name_key": "dating_region_gb_tlg", "sides": []},
     {"code": "TLH", "name_key": "dating_region_gb_tlh", "sides": []},
     {"code": "TLI", "name_key": "dating_region_gb_tli", "sides": []},
     {"code": "TLJ", "name_key": "dating_region_gb_tlj", "sides": []},
     {"code": "TLK", "name_key": "dating_region_gb_tlk", "sides": []},
     {"code": "TLL", "name_key": "dating_region_gb_tll", "sides": []},
     {"code": "TLM", "name_key": "dating_region_gb_tlm", "sides": []},
     {"code": "TLN", "name_key": "dating_region_gb_tln", "sides": []}]'::jsonb,
   '[{"code": "passport", "name_key": "dating_id_passport"},
     {"code": "uk_photocard_driving_licence", "name_key": "dating_id_uk_driving_licence"}]'::jsonb,
   3, 'Europe/London',
   '{"osa_illegal_harms_assessment": null, "osa_childrens_access_assessment": null,
     "highly_effective_age_assurance": null, "dpia": null, "pen_test": null,
     "safety_owner_and_moderator": null, "reviewer_signoffs": null}'::jsonb,
   'docs/superpowers/research/2026-10-24-flow-dating-research/04-dating-safety-global.md#216',
   '2026-10-24', 'spec2', 'migration:spec2-w1b')
ON CONFLICT (country_code, version) DO NOTHING;

INSERT INTO public.country_safety_config
  (country_code, version, tier, dating_enabled, same_gender_enabled, source_url, reviewed_at,
   reviewed_by, published_by)
SELECT t.code, 1, t.tier, false, false,
       'docs/superpowers/research/2026-10-24-flow-dating-research/04-dating-safety-global.md#216',
       '2026-10-24', 'spec2', 'migration:spec2-w1b'
  FROM (VALUES
    ('NG', 1), ('EG', 1), ('TN', 1), ('LB', 1), ('MA', 1), ('IQ', 1), ('JO', 1), ('RU', 1),
    ('ID', 1), ('MY', 1), ('TR', 1), ('UG', 1), ('SN', 1), ('NE', 1), ('ML', 1), ('BF', 1),
    ('IR', 1), ('SA', 1), ('YE', 1), ('AF', 1), ('BN', 1), ('MR', 1), ('SO', 1), ('QA', 1),
    ('AE', 1), ('PK', 1), ('SY', 1), ('DZ', 2), ('BI', 2), ('CM', 2), ('TD', 2), ('KM', 2),
    ('ER', 2), ('SZ', 2), ('ET', 2), ('GN', 2), ('KE', 2), ('LR', 2), ('LY', 2), ('MW', 2),
    ('SL', 2), ('SS', 2), ('SD', 2), ('TZ', 2), ('GM', 2), ('TG', 2), ('ZM', 2), ('ZW', 2),
    ('BD', 2), ('KW', 2), ('MV', 2), ('MM', 2), ('OM', 2), ('PS', 2), ('LK', 2), ('TM', 2),
    ('UZ', 2), ('GD', 2), ('GY', 2), ('JM', 2), ('VC', 2), ('TT', 2), ('KI', 2), ('PG', 2),
    ('WS', 2), ('SB', 2), ('TO', 2), ('TV', 2), ('BY', 2), ('KZ', 2), ('CN', 2)) AS t(code, tier)
ON CONFLICT (country_code, version) DO NOTHING;

-- The current row, or the default for a country with no row (spec §2.2).
CREATE OR REPLACE FUNCTION public.dating_country_config(p_country text)
RETURNS public.country_safety_config
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_code constant text := upper(coalesce(p_country, ''));
  v public.country_safety_config;
BEGIN
  SELECT * INTO v FROM public.country_safety_config AS c WHERE c.country_code = v_code AND c.is_current;
  IF FOUND THEN
    RETURN v;
  END IF;
  IF v_code !~ '^[A-Z]{2}$' THEN
    RETURN NULL;
  END IF;
  v.country_code := v_code;
  v.version := 0;
  v.is_current := true;
  v.tier := 3;
  v.dating_enabled := false;
  v.open_regions := NULL;
  v.same_gender_enabled := true;
  v.region_list := '[]'::jsonb;
  v.faith_list := '[]'::jsonb;
  v.id_documents := '[]'::jsonb;
  v.generation_hour_utc := 3;
  v.reference_tz := 'UTC';
  v.legal_checklist := '{}'::jsonb;
  v.published_at := now();
  v.published_by := 'default';
  RETURN v;
END;
$fn$;

-- The production-mode checks for a row about to be published (spec §2.2,
-- §2.4): the list of failed checks, empty when none.
CREATE OR REPLACE FUNCTION private.country_config_checks(p_row public.country_safety_config)
RETURNS text[]
LANGUAGE plpgsql
STABLE
SET search_path = ''
AS $fn$
DECLARE
  v_checks text[] := ARRAY[]::text[];
  v_sg jsonb := p_row.legal_checklist -> 'same_gender_reconsideration';
BEGIN
  IF p_row.dating_enabled THEN
    IF p_row.legal_checklist = '{}'::jsonb
       OR EXISTS (SELECT 1 FROM jsonb_each(p_row.legal_checklist) AS e
                   WHERE e.key <> 'same_gender_reconsideration'
                     AND (jsonb_typeof(e.value) <> 'string' OR btrim(e.value #>> '{}') = '')) THEN
      v_checks := array_append(v_checks, 'evidence_missing');
    END IF;
    IF p_row.resources_verified_at IS NULL OR p_row.resources_verified_at < now() - interval '90 days' THEN
      v_checks := array_append(v_checks, 'resources_not_verified');
    END IF;
  END IF;
  IF p_row.same_gender_enabled AND p_row.tier IN (1, 2)
     AND (jsonb_typeof(v_sg) IS DISTINCT FROM 'object'
          OR EXISTS (SELECT 1 FROM unnest(ARRAY['legal_opinion', 'lgbtq_consultation', 'tier1_protections']) AS k(key)
                      WHERE jsonb_typeof(v_sg -> k.key) IS DISTINCT FROM 'string'
                         OR btrim(v_sg ->> k.key) = '')) THEN
    v_checks := array_append(v_checks, 'same_gender_reconsideration_missing');
  END IF;
  RETURN v_checks;
END;
$fn$;

CREATE OR REPLACE FUNCTION public.publish_country_config(p_country text, p_values jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_code constant text := upper(coalesce(p_country, ''));
  v_allowed constant text[] := ARRAY['tier', 'dating_enabled', 'open_regions', 'same_gender_enabled',
    'region_list', 'faith_list', 'id_documents', 'generation_hour_utc', 'reference_tz',
    'resources_verified_at', 'legal_checklist', 'source_url', 'reviewed_at', 'reviewed_by', 'published_by'];
  v_old public.country_safety_config;
  v_new public.country_safety_config;
  v_codes text[];
  v_checks text[];
BEGIN
  IF v_code !~ '^[A-Z]{2}$' THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'config:invalid_country');
  END IF;
  IF jsonb_typeof(p_values) IS DISTINCT FROM 'object' THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'config:invalid_values');
  END IF;
  IF EXISTS (SELECT 1 FROM jsonb_object_keys(p_values) AS k WHERE k <> ALL (v_allowed)) THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'config:unknown_key');
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended('country_safety_config:' || v_code, 0));
  SELECT * INTO v_old FROM public.country_safety_config AS c
   WHERE c.country_code = v_code AND c.is_current FOR UPDATE;
  IF NOT FOUND THEN
    v_old := public.dating_country_config(v_code);
  END IF;

  BEGIN
    v_new := jsonb_populate_record(v_old, p_values - 'open_regions');
    IF p_values ? 'open_regions' THEN
      v_new.open_regions := CASE WHEN jsonb_typeof(p_values -> 'open_regions') = 'null' THEN NULL
                                 ELSE ARRAY(SELECT jsonb_array_elements_text(p_values -> 'open_regions')) END;
    END IF;
  EXCEPTION WHEN data_exception OR invalid_text_representation OR datatype_mismatch THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'config:invalid_values');
  END;
  v_new.country_code := v_code;
  v_new.version := v_old.version + 1;
  v_new.is_current := true;
  v_new.published_at := now();
  v_new.published_by := coalesce(nullif(btrim(p_values ->> 'published_by'), ''), 'service_role');

  IF v_new.tier IS NULL OR v_new.tier NOT BETWEEN 1 AND 3
     OR v_new.dating_enabled IS NULL OR v_new.same_gender_enabled IS NULL
     OR v_new.generation_hour_utc IS NULL OR v_new.generation_hour_utc NOT BETWEEN 0 AND 23 THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'config:invalid_values');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_timezone_names AS z WHERE z.name = v_new.reference_tz) THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'config:invalid_tz');
  END IF;
  IF jsonb_typeof(v_new.region_list) IS DISTINCT FROM 'array'
     OR jsonb_typeof(v_new.faith_list) IS DISTINCT FROM 'array'
     OR jsonb_typeof(v_new.id_documents) IS DISTINCT FROM 'array'
     OR jsonb_typeof(v_new.legal_checklist) IS DISTINCT FROM 'object'
     OR EXISTS (SELECT 1 FROM jsonb_array_elements(v_new.region_list) AS r
                 WHERE jsonb_typeof(r) <> 'object' OR coalesce(r ->> 'code', '') !~ '^[A-Z0-9]{2,3}$') THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'config:invalid_lists');
  END IF;
  v_codes := ARRAY(SELECT r ->> 'code' FROM jsonb_array_elements(v_new.region_list) AS r);
  IF cardinality(v_codes) <> (SELECT count(DISTINCT c) FROM unnest(v_codes) AS c)
     OR (v_new.open_regions IS NOT NULL AND NOT v_new.open_regions <@ v_codes) THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'config:invalid_regions');
  END IF;

  -- Same-gender off: the purge (apply_same_gender_switch) arrives in W1d.
  IF v_old.same_gender_enabled AND NOT v_new.same_gender_enabled THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'config:kill_switch_pending');
  END IF;

  v_checks := private.country_config_checks(v_new);
  IF cardinality(v_checks) > 0 AND private.attune_environment() = 'production' THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'config:production_checks_failed',
                              'checks', to_jsonb(v_checks));
  END IF;

  UPDATE public.country_safety_config AS c SET is_current = false
   WHERE c.country_code = v_code AND c.is_current;
  INSERT INTO public.country_safety_config SELECT v_new.*;
  RETURN jsonb_build_object('ok', true, 'country', v_code, 'version', v_new.version,
                            'dating_enabled', v_new.dating_enabled,
                            'same_gender_enabled', v_new.same_gender_enabled,
                            'environment', private.attune_environment(),
                            'checks', to_jsonb(v_checks));
END;
$fn$;

-- Anyone (Welcome, D1, the not-open screens): the open countries and their
-- open regions, sorted.
CREATE OR REPLACE FUNCTION public.get_dating_availability()
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $fn$
  SELECT jsonb_build_object('countries', coalesce(jsonb_agg(jsonb_build_object(
           'code', c.country_code::text,
           'open_regions', CASE WHEN c.open_regions IS NULL THEN NULL ELSE (
             SELECT jsonb_agg(jsonb_build_object('code', r ->> 'code', 'name_key', r ->> 'name_key')
                              ORDER BY r ->> 'code')
               FROM jsonb_array_elements(c.region_list) AS r
              WHERE (r ->> 'code') = ANY (c.open_regions)) END)
           ORDER BY c.country_code), '[]'::jsonb))
    FROM public.country_safety_config AS c
   WHERE c.is_current AND c.dating_enabled;
$fn$;

-- Spec 1's seam, re-created from its live body (20261025100400) over the
-- table; same shape (sorted ISO alpha-2 codes).
CREATE OR REPLACE FUNCTION private.dating_open_countries()
 RETURNS text[]
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  SELECT coalesce(array_agg(c.country_code::text ORDER BY c.country_code), ARRAY[]::text[]) -- Spec 2 W1b
    FROM public.country_safety_config AS c -- Spec 2 W1b (I-3)
   WHERE c.is_current AND c.dating_enabled; -- Spec 2 W1b
$function$;
DELETE FROM public.app_public_config WHERE key = 'dating_open_countries';

-- The country a phone number belongs to, from its calling code (longest
-- prefix), for every country with a seeded row; NULL otherwise.
CREATE OR REPLACE FUNCTION private.dating_phone_country(p_phone text)
RETURNS text
LANGUAGE sql
IMMUTABLE
SET search_path = ''
AS $fn$
  SELECT p.country
    FROM (VALUES
      ('233', 'GH'), ('234', 'NG'), ('20', 'EG'), ('216', 'TN'), ('961', 'LB'), ('212', 'MA'),
      ('964', 'IQ'), ('962', 'JO'), ('7', 'RU'), ('62', 'ID'), ('60', 'MY'), ('90', 'TR'),
      ('256', 'UG'), ('221', 'SN'), ('227', 'NE'), ('223', 'ML'), ('226', 'BF'), ('98', 'IR'),
      ('966', 'SA'), ('967', 'YE'), ('93', 'AF'), ('673', 'BN'), ('222', 'MR'), ('252', 'SO'),
      ('974', 'QA'), ('971', 'AE'), ('92', 'PK'), ('963', 'SY'),
      ('213', 'DZ'), ('257', 'BI'), ('237', 'CM'), ('235', 'TD'), ('269', 'KM'), ('291', 'ER'),
      ('268', 'SZ'), ('251', 'ET'), ('224', 'GN'), ('254', 'KE'), ('231', 'LR'), ('218', 'LY'),
      ('265', 'MW'), ('232', 'SL'), ('211', 'SS'), ('249', 'SD'), ('255', 'TZ'), ('220', 'GM'),
      ('228', 'TG'), ('260', 'ZM'), ('263', 'ZW'), ('880', 'BD'), ('965', 'KW'), ('960', 'MV'),
      ('95', 'MM'), ('968', 'OM'), ('970', 'PS'), ('94', 'LK'), ('993', 'TM'), ('998', 'UZ'),
      ('1473', 'GD'), ('592', 'GY'), ('1876', 'JM'), ('1658', 'JM'), ('1784', 'VC'), ('1868', 'TT'),
      ('686', 'KI'), ('675', 'PG'), ('685', 'WS'), ('677', 'SB'), ('676', 'TO'), ('688', 'TV'),
      ('375', 'BY'), ('76', 'KZ'), ('77', 'KZ'), ('86', 'CN'), ('44', 'GB')) AS p(prefix, country)
   WHERE pg_catalog.regexp_replace(coalesce(p_phone, ''), '\D', '', 'g') LIKE p.prefix || '%'
   ORDER BY char_length(p.prefix) DESC
   LIMIT 1;
$fn$;

CREATE TABLE IF NOT EXISTS public.dating_session_context (
  user_id uuid PRIMARY KEY REFERENCES public.users(id) ON DELETE CASCADE,
  effective_tier smallint NOT NULL CHECK (effective_tier BETWEEN 1 AND 3),
  dating_allowed_here boolean NOT NULL,
  same_gender_allowed_here boolean NOT NULL,
  away_from_home boolean NOT NULL,
  ip_resolved boolean NOT NULL,
  mismatch_streak integer NOT NULL DEFAULT 0 CHECK (mismatch_streak >= 0),
  trip_note_shown_at timestamptz,
  checked_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.dating_session_context ENABLE ROW LEVEL SECURITY;
COMMENT ON TABLE public.dating_session_context IS
  'Spec 2 §2.3: one overwritten row per user, no country codes, no history.';

-- Spec 2 §2.3: the context from the four countries (any may be NULL).
CREATE OR REPLACE FUNCTION public.dating_effective_context(p_phone_country text, p_dating_country text,
                                                           p_ip_country text, p_network_country text)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_phone constant text := CASE WHEN upper(p_phone_country) ~ '^[A-Z]{2}$' THEN upper(p_phone_country) END;
  v_dating constant text := CASE WHEN upper(p_dating_country) ~ '^[A-Z]{2}$' THEN upper(p_dating_country) END;
  v_ip constant text := CASE WHEN upper(p_ip_country) ~ '^[A-Z]{2}$' THEN upper(p_ip_country) END;
  v_net constant text := CASE WHEN upper(p_network_country) ~ '^[A-Z]{2}$' THEN upper(p_network_country) END;
  -- Where the person is: the IP country, or the phone country when the IP
  -- can't be resolved (VPN, unknown range).
  v_here constant text := coalesce(v_ip, v_phone);
  v_tier smallint;
  v_allowed boolean;
  v_same boolean;
BEGIN
  SELECT coalesce(min(c.tier), 3) INTO v_tier
    FROM unnest(ARRAY[v_phone, v_dating, v_ip, v_net]) AS k(code)
    CROSS JOIN LATERAL public.dating_country_config(k.code) AS c
   WHERE k.code IS NOT NULL;
  -- Not allowed where the place (or the network) is a closed Tier 1/2 country.
  v_allowed := NOT EXISTS (
    SELECT 1 FROM unnest(ARRAY[v_here, v_net]) AS k(code)
      CROSS JOIN LATERAL public.dating_country_config(k.code) AS c
     WHERE k.code IS NOT NULL AND NOT c.dating_enabled AND c.tier IN (1, 2));
  -- Same-gender: the global flag, the Dating country (which must be known),
  -- the place and the network, all allowing it.
  v_same := public.dating_flag_enabled('dating_same_gender_matching')
            AND v_dating IS NOT NULL
            AND NOT EXISTS (
              SELECT 1 FROM unnest(ARRAY[v_dating, v_here, v_net]) AS k(code)
                CROSS JOIN LATERAL public.dating_country_config(k.code) AS c
               WHERE k.code IS NOT NULL AND NOT c.same_gender_enabled);
  RETURN jsonb_build_object(
    'effective_tier', v_tier,
    'dating_allowed_here', v_allowed,
    'same_gender_allowed_here', v_same,
    'away_from_home', v_ip IS NOT NULL AND v_dating IS NOT NULL AND v_ip <> v_dating,
    'ip_resolved', v_ip IS NOT NULL);
END;
$fn$;

-- Service role (W8b's dating-device-check): overwrite the person's row.
-- The phone country comes from Auth's number, the Dating country from the
-- profile (read by name: the column arrives in W1c); nothing about the
-- countries is stored.
CREATE OR REPLACE FUNCTION public.record_dating_session_context(p_user uuid, p_ip_country text,
                                                               p_network_country text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_phone text;
  v_dating text;
  v_ctx jsonb;
BEGIN
  IF p_user IS NULL OR NOT EXISTS (SELECT 1 FROM public.users AS u WHERE u.id = p_user) THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'unavailable');
  END IF;
  SELECT private.dating_phone_country(a.phone) INTO v_phone FROM auth.users AS a WHERE a.id = p_user;
  SELECT to_jsonb(p) ->> 'country_code' INTO v_dating FROM public.dating_profiles AS p WHERE p.user_id = p_user;
  v_ctx := public.dating_effective_context(v_phone, v_dating, p_ip_country, p_network_country);
  INSERT INTO public.dating_session_context AS s
    (user_id, effective_tier, dating_allowed_here, same_gender_allowed_here, away_from_home,
     ip_resolved, mismatch_streak, checked_at)
  VALUES (p_user, (v_ctx ->> 'effective_tier')::smallint, (v_ctx ->> 'dating_allowed_here')::boolean,
          (v_ctx ->> 'same_gender_allowed_here')::boolean, (v_ctx ->> 'away_from_home')::boolean,
          (v_ctx ->> 'ip_resolved')::boolean, CASE WHEN (v_ctx ->> 'away_from_home')::boolean THEN 1 ELSE 0 END,
          now())
  ON CONFLICT (user_id) DO UPDATE
    SET effective_tier = EXCLUDED.effective_tier,
        dating_allowed_here = EXCLUDED.dating_allowed_here,
        same_gender_allowed_here = EXCLUDED.same_gender_allowed_here,
        away_from_home = EXCLUDED.away_from_home,
        ip_resolved = EXCLUDED.ip_resolved,
        mismatch_streak = CASE WHEN EXCLUDED.away_from_home THEN s.mismatch_streak + 1 ELSE 0 END,
        checked_at = EXCLUDED.checked_at;
  RETURN jsonb_build_object('ok', true) || v_ctx;
END;
$fn$;

CREATE TABLE IF NOT EXISTS public.dating_notify_requests (
  user_id uuid PRIMARY KEY REFERENCES public.users(id) ON DELETE CASCADE,
  country_code char(2) NOT NULL CHECK (country_code ~ '^[A-Z]{2}$'),
  region_code text,
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.dating_notify_requests ENABLE ROW LEVEL SECURITY;

-- The new flag (off), and a production gate row for it and for every
-- existing Dating flag, so none can be switched on in production mode
-- without recorded evidence (Spec 1's gate trigger).
INSERT INTO private.flag_production_gates (flag_key, gate) VALUES
  ('dating_mode_enabled', 'Spec 2 W10 gate: every W1-W10 gate signed, get_dating_launch_readiness() green, the launch project in production mode'),
  ('dating_candidate_generation', 'Spec 2 W5 gate: dating_exclusion_key provisioned, DV sign-off on never-introduce, introductions_v2 active with real review refs'),
  ('dating_match_messaging', 'Spec 2 W6 gate: DATING_CHAT_SAFETY_SPEC v2 section 12 checked by the safety owner, DV and cultural sign-offs'),
  ('dating_profile_photos', 'Spec 2 W3 gate: process-dating-photo runs the inline CSAM match first (S1 W7b PF-H2) and the W3 reviewers have signed'),
  ('dating_alignment_algorithm_v1', 'Spec 2: retired in W5a; never switched on in production'),
  ('dating_same_gender_matching', 'Spec 2 W3 gate (§2.4): the LGBTQ+ safety reviewer signs the off-country copy and the country note')
ON CONFLICT (flag_key) DO NOTHING;
INSERT INTO public.feature_flags (key, enabled) VALUES ('dating_same_gender_matching', false)
ON CONFLICT (key) DO NOTHING;

REVOKE ALL ON public.country_safety_config, public.dating_session_context, public.dating_notify_requests
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.country_safety_config_immutable(), public.dating_country_config(text),
  private.country_config_checks(public.country_safety_config), public.publish_country_config(text, jsonb),
  public.get_dating_availability(), private.dating_open_countries(), private.dating_phone_country(text),
  public.dating_effective_context(text, text, text, text), public.record_dating_session_context(uuid, text, text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_dating_availability() TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.publish_country_config(text, jsonb) TO service_role;
GRANT EXECUTE ON FUNCTION public.record_dating_session_context(uuid, text, text) TO service_role;

COMMIT;
```

Create `supabase/migrations/20261106130010_dating_v2_country_config_grants.sql` with exactly:

```sql
-- Spec 2 W1b: grants for 20261106130000_dating_v2_country_config.sql.
-- Anyone may read the open countries (get_dating_availability; Spec 1's
-- get_public_app_config keeps its own anon grant). Publishing and the
-- session context are the service role's; the tables are no client's.
BEGIN;
SET LOCAL lock_timeout = '5s';
REVOKE ALL ON public.country_safety_config, public.dating_session_context, public.dating_notify_requests
  FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.country_safety_config, public.dating_session_context,
  public.dating_notify_requests TO service_role;
REVOKE ALL ON FUNCTION private.country_safety_config_immutable(), public.dating_country_config(text),
  private.country_config_checks(public.country_safety_config), public.publish_country_config(text, jsonb),
  public.get_dating_availability(), private.dating_open_countries(), private.dating_phone_country(text),
  public.dating_effective_context(text, text, text, text), public.record_dating_session_context(uuid, text, text)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_dating_availability() TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.publish_country_config(text, jsonb) TO service_role;
GRANT EXECUTE ON FUNCTION public.record_dating_session_context(uuid, text, text) TO service_role;
REVOKE ALL ON public.feature_flags FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.feature_flags TO authenticated;
REVOKE ALL ON private.flag_production_gates FROM PUBLIC, anon, authenticated, service_role;
COMMIT;
```

- [ ] **Step 4: Apply each file twice; diff the seam; run the contract**

```bash
for i in 1 2; do
  for f in 20261106130000_dating_v2_country_config 20261106130010_dating_v2_country_config_grants; do
    psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/migrations/$f.sql > /dev/null 2>&1; echo "$f exit=$?"
  done
done
```

```bash
D=.superpowers/sdd/2026-11-06-spec2-w1
for sig in 'private.dating_open_countries()'; do
  echo "== $sig"
  diff "$D/before/$sig.sql" <(psql -X -d attune_spec3a -Atc "select pg_get_functiondef('$sig'::regprocedure)") | grep '^[<>]'
done
```

```bash
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/country_safety_config_contracts.sql 2>&1 | grep -E 'ERROR|all held' | head -1 | sed -E 's/^psql:[^ ]* //'
```

Expected: four `exit=0` lines; then exactly:

```text
== private.dating_open_countries()
<   SELECT coalesce(array_agg(c ORDER BY c), ARRAY[]::text[])
<     FROM public.app_public_config AS k,
<          jsonb_array_elements_text(k.value) AS c
<    WHERE k.key = 'dating_open_countries';
>   SELECT coalesce(array_agg(c.country_code::text ORDER BY c.country_code), ARRAY[]::text[]) -- Spec 2 W1b
>     FROM public.country_safety_config AS c -- Spec 2 W1b (I-3)
>    WHERE c.is_current AND c.dating_enabled; -- Spec 2 W1b
```

then `NOTICE:  country_safety_config_contracts: all held`.

- [ ] **Step 5: Spec 1's contract pinned the interim row and "no gate for dating_mode_enabled"; amend those lines**

```bash
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/identity_foundation_contracts.sql 2>&1 | grep -E 'ERROR|all held' | head -1 | sed -E 's/^psql:[^ ]* //'
```

Expected: `ERROR:  CONTRACT VIOLATED: a W1 function names a later wave's table (I-6): private.dating_open_countries()`. Create `.superpowers/sdd/2026-11-06-spec2-w1/edit_identity_foundation_w1b.py` with exactly:

```python
import pathlib
p = pathlib.Path('supabase/tests/identity_foundation_contracts.sql')
s = p.read_text()
edits = [
("""                   'private.guard_flag_production_gate()'::regprocedure,
                   'private.dating_open_countries()'::regprocedure,
                   'public.get_public_app_config()'::regprocedure,""",
"""                   'private.guard_flag_production_gate()'::regprocedure,
                   -- private.dating_open_countries() left the list in Spec 2
                   -- W1b, which re-creates the seam over country_safety_config (I-3).
                   'public.get_public_app_config()'::regprocedure,"""),
("""  IF v_cfg -> 'config' -> 'dating_open_countries' IS DISTINCT FROM '["GB", "GH"]'::jsonb
     OR v_cfg -> 'config' -> 'age_signal_storefronts'""",
"""  IF v_cfg -> 'config' -> 'dating_open_countries' IS DISTINCT FROM to_jsonb(private.dating_open_countries())
     OR v_cfg -> 'config' -> 'age_signal_storefronts'"""),
("""  UPDATE public.app_public_config SET value = '["GH"]' WHERE key = 'dating_open_countries';
  IF public.get_public_app_config() -> 'config' -> 'dating_open_countries' IS DISTINCT FROM '["GH"]'::jsonb
     OR private.dating_open_countries() IS DISTINCT FROM ARRAY['GH'] THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the open-country list does not come through the one seam';
  END IF;""",
"""  -- Spec 2 W1b (I-3): the seam reads country_safety_config and the interim
  -- row is gone (country_safety_config_contracts.sql section D pins the rest).
  IF EXISTS (SELECT 1 FROM public.app_public_config WHERE key = 'dating_open_countries')
     OR public.get_public_app_config() -> 'config' -> 'dating_open_countries'
          IS DISTINCT FROM to_jsonb(private.dating_open_countries()) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the open-country list does not come through the one seam';
  END IF;"""),
("""  IF EXISTS (SELECT 1 FROM private.flag_production_gates WHERE flag_key = 'dating_mode_enabled') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: dating_mode_enabled carries a production gate (ruling: it stays out)';
  END IF;""",
"""  -- Spec 2 W1b decided dating_mode_enabled's gate (the ruling left it to
  -- Spec 2): its W10 launch gate.
  IF NOT EXISTS (SELECT 1 FROM private.flag_production_gates
                  WHERE flag_key = 'dating_mode_enabled' AND gate LIKE 'Spec 2 W10 gate:%') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: dating_mode_enabled lacks Spec 2''s production gate';
  END IF;"""),
]
for a, b in edits:
    assert s.count(a) == 1, a[:70]
    s = s.replace(a, b)
p.write_text(s)
print('identity_foundation_contracts.sql: 4 edits (W1b)')
```

```bash
python3 -I .superpowers/sdd/2026-11-06-spec2-w1/edit_identity_foundation_w1b.py
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/identity_foundation_contracts.sql >/dev/null 2>&1; echo "exit=$?"
```

Expected: `identity_foundation_contracts.sql: 4 edits (W1b)`, `exit=0`.

- [ ] **Step 6: The canary's rows for this migration**

Create `.superpowers/sdd/2026-11-06-spec2-w1/canary_T5.sql` with exactly:

```sql
-- ---------------------------------------------------------------------
-- W1b (migration 4): the country model and the session context.
-- ---------------------------------------------------------------------
INSERT INTO allowed_rel (name, authenticated, service_dml) VALUES
  ('country_safety_config', '', 'DELETE,INSERT,SELECT,UPDATE'),
  ('dating_notify_requests', '', 'DELETE,INSERT,SELECT,UPDATE'),
  ('dating_session_context', '', 'DELETE,INSERT,SELECT,UPDATE');
INSERT INTO allowed_fn (sig, clients) VALUES
  ('dating_country_config(text)', ''),
  ('dating_effective_context(text,text,text,text)', ''),
  ('get_dating_availability()', 'anon,authenticated'),
  ('private.dating_phone_country(text)', ''),
  ('publish_country_config(text,jsonb)', ''),
  ('record_dating_session_context(uuid,text,text)', '');
```

```bash
D=.superpowers/sdd/2026-11-06-spec2-w1
python3 -I $D/section.py supabase/tests/dating_rls_canary.sql $D/canary_T5.sql --before '-- Checks (every batch adds its rows above this line).'
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/dating_rls_canary.sql 2>&1 | grep -E 'ERROR|all held' | head -1 | sed -E 's/^psql:[^ ]* //'
```

Expected: `dating_rls_canary.sql: canary_T5.sql before`, then `NOTICE:  dating_rls_canary: all held` (before this step, with the migration applied, the canary names every new object as `not in the canary's allow-list`).

- [ ] **Step 7: Mutation checks**

Create `.superpowers/sdd/2026-11-06-spec2-w1/mut_T5.py` with exactly:

```python
MUTS = {
 'rows_mutable': ("""  IF NOT OLD.is_current OR NEW.is_current
     OR (to_jsonb(NEW) - 'is_current') IS DISTINCT FROM (to_jsonb(OLD) - 'is_current') THEN""", """  IF NOT OLD.is_current OR NEW.is_current THEN"""),
 'rows_deletable': ("""  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'config:immutable';
  END IF;""", """  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  END IF;"""),
 'production_not_enforced': ("""  IF cardinality(v_checks) > 0 AND private.attune_environment() = 'production' THEN""", """  IF cardinality(v_checks) > 0 AND private.attune_environment() = 'nowhere' THEN"""),
 'empty_checklist_passes': ("""    IF p_row.legal_checklist = '{}'::jsonb
       OR EXISTS""", """    IF EXISTS"""),
 'blank_evidence_passes': ("""                     AND (jsonb_typeof(e.value) <> 'string' OR btrim(e.value #>> '{}') = '')) THEN""", """                     AND jsonb_typeof(e.value) <> 'string') THEN"""),
 'stale_resources_pass': ("""    IF p_row.resources_verified_at IS NULL OR p_row.resources_verified_at < now() - interval '90 days' THEN""", """    IF p_row.resources_verified_at IS NULL THEN"""),
 'no_reconsideration_check': ("""  IF p_row.same_gender_enabled AND p_row.tier IN (1, 2)""", """  IF p_row.same_gender_enabled AND p_row.tier IN (9)"""),
 'blank_reconsideration_passes': ("""                      WHERE jsonb_typeof(v_sg -> k.key) IS DISTINCT FROM 'string'
                         OR btrim(v_sg ->> k.key) = '')) THEN""", """                      WHERE jsonb_typeof(v_sg -> k.key) IS DISTINCT FROM 'string')) THEN"""),
 'kill_switch_unguarded': ("""  IF v_old.same_gender_enabled AND NOT v_new.same_gender_enabled THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'config:kill_switch_pending');
  END IF;
""", ""),
 'unknown_keys_pass': ("""  IF EXISTS (SELECT 1 FROM jsonb_object_keys(p_values) AS k WHERE k <> ALL (v_allowed)) THEN""", """  IF false THEN"""),
 'regions_unchecked': ("""     OR (v_new.open_regions IS NOT NULL AND NOT v_new.open_regions <@ v_codes) THEN""", """     THEN"""),
 'seam_ignores_enabled': ("""   WHERE c.is_current AND c.dating_enabled; -- Spec 2 W1b""", """   WHERE c.is_current; -- Spec 2 W1b"""),
 'seam_reads_history': ("""   WHERE c.is_current AND c.dating_enabled; -- Spec 2 W1b""", """   WHERE c.dating_enabled; -- Spec 2 W1b"""),
 'availability_ignores_enabled': ("""   WHERE c.is_current AND c.dating_enabled;
$fn$;""", """   WHERE c.is_current;
$fn$;"""),
 'tier_lowest': ("""  SELECT coalesce(min(c.tier), 3) INTO v_tier""", """  SELECT coalesce(max(c.tier), 3) INTO v_tier"""),
 'allowed_ignores_network': ("""    SELECT 1 FROM unnest(ARRAY[v_here, v_net]) AS k(code)""", """    SELECT 1 FROM unnest(ARRAY[v_here]) AS k(code)"""),
 'allowed_without_phone_fallback': ("""  v_here constant text := coalesce(v_ip, v_phone);""", """  v_here constant text := v_ip;"""),
 'same_gender_ignores_flag': ("""  v_same := public.dating_flag_enabled('dating_same_gender_matching')
            AND v_dating IS NOT NULL""", """  v_same := v_dating IS NOT NULL"""),
 'same_gender_ignores_place': ("""              SELECT 1 FROM unnest(ARRAY[v_dating, v_here, v_net]) AS k(code)""", """              SELECT 1 FROM unnest(ARRAY[v_dating]) AS k(code)"""),
 'same_gender_without_dating_country': ("""            AND v_dating IS NOT NULL
""", ""),
 'phone_shortest_prefix': ("""   ORDER BY char_length(p.prefix) DESC""", """   ORDER BY char_length(p.prefix)"""),
  'away_without_dating_country': ("    'away_from_home', v_ip IS NOT NULL AND v_dating IS NOT NULL AND v_ip <> v_dating,", "    'away_from_home', v_ip IS NOT NULL AND v_ip IS DISTINCT FROM v_dating,"),
}
```

```bash
D=.superpowers/sdd/2026-11-06-spec2-w1
python3 -I $D/mutate.py supabase/migrations/20261106130000_dating_v2_country_config.sql supabase/tests/country_safety_config_contracts.sql $D/mut_T5.py $D
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/country_safety_config_contracts.sql 2>&1 | grep -E 'ERROR|all held' | head -1 | sed -E 's/^psql:[^ ]* //'
```

Expected:

- `rows_mutable`: `ERROR:  CONTRACT VIOLATED: a published country row could be changed or deleted`
- `rows_deletable`: `ERROR:  CONTRACT VIOLATED: a published country row could be changed or deleted`
- `production_not_enforced`: `ERROR:  CONTRACT VIOLATED: production published Dating on without evidence: {"ok": true, "checks": ["evidence_missing", "resources_not_verified"], "country": "GB", "versi`
- `empty_checklist_passes`: `ERROR:  CONTRACT VIOLATED: production opened a country with an empty legal checklist: {"ok": true, "checks": [], "country": "FR", "version": 1, "environment": "production`
- `blank_evidence_passes`: `ERROR:  CONTRACT VIOLATED: production accepted a blank evidence reference: {"ok": true, "checks": [], "country": "GB", "version": 2, "environment": "production", "dating_`
- `stale_resources_pass`: `ERROR:  CONTRACT VIOLATED: production accepted support resources verified over 90 days ago: {"ok": true, "checks": [], "country": "GB", "version": 2, "environment": "prod`
- `no_reconsideration_check`: `ERROR:  CONTRACT VIOLATED: production turned same-gender on in a Tier 1 country without the reconsideration: {"ok": true, "checks": [], "country": "NG", "version": 2, "en`
- `blank_reconsideration_passes`: `ERROR:  CONTRACT VIOLATED: production accepted a blank Tier 1 protections reference: {"ok": true, "checks": [], "country": "NG", "version": 2, "environment": "production"`
- `kill_switch_unguarded`: `ERROR:  CONTRACT VIOLATED: turning same-gender off published without the kill switch: {"ok": true, "checks": [], "country": "GB", "version": 6, "environment": "developmen`
- `unknown_keys_pass`: `ERROR:  CONTRACT VIOLATED: a malformed publish was not refused with its reason`
- `regions_unchecked`: `ERROR:  CONTRACT VIOLATED: a malformed publish was not refused with its reason`
- `seam_ignores_enabled`: `ERROR:  CONTRACT VIOLATED: with every seed closed the open-country list is ["AE", "AF", "BD", "BF", "BI", "BN", "BY", "CM", "CN", "DZ", "EG", "ER", "ET", "GB", "GD", "GH"`
- `seam_reads_history`: `ERROR:  CONTRACT VIOLATED: the public open-country list and get_dating_availability disagree: {"public": {"flags": {"text_scale_v2": false, "flow_signin_v2": false, "plat`
- `availability_ignores_enabled`: `ERROR:  CONTRACT VIOLATED: the public open-country list and get_dating_availability disagree: {"public": {"flags": {"text_scale_v2": false, "flow_signin_v2": false, "plat`
- `tier_lowest`: `ERROR:  CONTRACT VIOLATED: effective_tier is not the highest tier of the sources`
- `allowed_ignores_network`: `ERROR:  CONTRACT VIOLATED: dating_allowed_here is wrong`
- `allowed_without_phone_fallback`: `ERROR:  CONTRACT VIOLATED: dating_allowed_here is wrong`
- `same_gender_ignores_flag`: `ERROR:  CONTRACT VIOLATED: same-gender was allowed with the global flag off`
- `same_gender_ignores_place`: `ERROR:  CONTRACT VIOLATED: same_gender_allowed_here is wrong (a Ghana SIM in London, a UK user in Accra, no Dating country, an unresolved IP on a Ghana phone)`
- `same_gender_without_dating_country`: `ERROR:  CONTRACT VIOLATED: same_gender_allowed_here is wrong (a Ghana SIM in London, a UK user in Accra, no Dating country, an unresolved IP on a Ghana phone)`
- `phone_shortest_prefix`: `ERROR:  CONTRACT VIOLATED: dating_phone_country is not the longest calling-code prefix`
- `away_without_dating_country`: `ERROR:  CONTRACT VIOLATED: away_from_home or ip_resolved is wrong`

then `NOTICE:  country_safety_config_contracts: all held`. (The seed rows, the interim row's deletion and the gate rows are data written once; a mutant of them changes nothing on a database that already has them, so section A and the gate-row check pin them on CI's fresh database instead.)

- [ ] **Step 8: The local harness (edit only, never run)**

`scripts/local_pg_grants.sql`: append after the last line (`\i supabase/migrations/20261106120010_dating_v2_account_deletion_grants.sql`), exactly:

```sql

-- Spec 2 W1b: anyone reads the open countries; publishing and the session
-- context are the service role's; the tables are no client's.
\i supabase/migrations/20261106130010_dating_v2_country_config_grants.sql
```

```bash
python3 -I - <<'PY'
import pathlib
p = pathlib.Path('scripts/local_pg_grants.sql')
s = p.read_text()
assert s.endswith('\\i supabase/migrations/20261106120010_dating_v2_account_deletion_grants.sql' + chr(10))
p.write_text(s + chr(10) + "-- Spec 2 W1b: anyone reads the open countries; publishing and the session\n-- context are the service role's; the tables are no client's." + chr(10) + '\\i supabase/migrations/20261106130010_dating_v2_country_config_grants.sql' + chr(10))
print('local_pg_grants.sql: one \\i block added')
PY
```

- [ ] **Step 9: Run tests (R18: the Welcome preview, A6 and the Me slot read the seam)**

```bash
psql -X -d attune_spec3a -Atc "set role anon; select public.get_public_app_config() -> 'config' -> 'dating_open_countries', public.get_dating_availability()"
for t in identity_foundation_contracts healing_ai_pause_contracts support_resources_contracts dating_rls_canary; do
  psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/$t.sql >/dev/null 2>&1 && echo "PASS $t" || echo "FAIL $t"
done
```

Expected: `[]|{"countries": []}` (every seed closed until Task 7's dev script opens GH and GB in development); four `PASS` lines.

### Task 6: Migration 5: `dating_eligibility` (gates 1-4, 6) and Spec 1's home-summary seam (§4.9 W1b #2, §2.1, I-14, A-10; P-18)

**Files:**
- Create: `supabase/migrations/20261106140000_dating_v2_eligibility_base.sql`, `…140010_dating_v2_eligibility_base_grants.sql`, `supabase/tests/dating_v2_eligibility_contracts.sql`
- Modify: `supabase/tests/dating_rls_canary.sql`, `scripts/local_pg_grants.sql`

**Interfaces:**
- Consumes: `account_age`, `auth.users.phone_confirmed_at`, `users.eula_*`, Task 3's standing, `dating_has_relationship`, Task 5's `dating_country_config`, the live `private.dating_home_summary`.
- Produces: `public.dating_eligibility(p_user uuid, p_scope text DEFAULT 'candidate') → text` (`feature_unavailable`, `account_unavailable`, `relationship_active`, `country_closed`, `region_closed`, `eligible`; server only; W2 adds gate 5, W4b gate 8, W8b gate 7 by re-creating it from its live body); the seam's `enabled` from it.

- [ ] **Step 1: Write the failing contract**

Create `supabase/tests/dating_v2_eligibility_contracts.sql` with exactly:

```sql
-- supabase/tests/dating_v2_eligibility_contracts.sql
-- Spec 2 W1b (and W2) (§2.1, §7.1, §7.5; I-14, A-10): dating_eligibility's
-- base gates 1-4 (A), its country and region gate 6 (B, from W1c, once
-- profiles carry a country) and Spec 1's re-created home-summary seam (C).
-- W2 adds the gentle wait, the shim and the path trigger.
-- One BEGIN ... ROLLBACK. Run only on attune_spec3a:
--   psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/dating_v2_eligibility_contracts.sql
-- Fixture ids 5e2c0000-0000-0000-0000-0000000000NN; phones 15558702NN.
BEGIN;

DO $$
BEGIN
  PERFORM set_config('app.settings.dating_exclusion_key', 'spec2-w1b-eligibility-key', true);
END $$;

CREATE FUNCTION pg_temp.id(p_n text) RETURNS uuid LANGUAGE sql IMMUTABLE AS $$
  SELECT ('5e2c0000-0000-0000-0000-0000000000' || p_n)::uuid;
$$;

-- An adult [p_n] who passes gates 1-4: a DOB 30 years ago, a confirmed
-- Auth phone, EULA v2, no relationship, nothing held.
CREATE FUNCTION pg_temp.person(p_n text) RETURNS uuid LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO auth.users (id, phone, phone_confirmed_at, created_at)
  VALUES (pg_temp.id(p_n), '15558702' || p_n, now(), now() - interval '40 days');
  INSERT INTO public.users (id, phone, display_name, path, created_at, eula_accepted_at, eula_version)
  VALUES (pg_temp.id(p_n), '15558702' || p_n, 'Person ' || p_n, 'dating', now() - interval '40 days', now(), '2');
  INSERT INTO public.account_birthdates (user_id, birth_date)
  VALUES (pg_temp.id(p_n), current_date - interval '30 years');
  RETURN pg_temp.id(p_n);
END $$;

CREATE FUNCTION pg_temp.both(p_user uuid) RETURNS text LANGUAGE sql AS $$
  SELECT public.dating_eligibility(p_user, 'setup') || '/' || public.dating_eligibility(p_user);
$$;

-- =====================================================================
-- A. (W1b) Gates 1-4, in order; the default scope is 'candidate'.
-- =====================================================================
DO $$
DECLARE
  v_ok constant uuid := pg_temp.person('01');
  v_young constant uuid := pg_temp.person('02');
  v_nodob constant uuid := pg_temp.person('03');
  v_unconfirmed constant uuid := pg_temp.person('04');
  v_eula1 constant uuid := pg_temp.person('05');
  v_noeula constant uuid := pg_temp.person('06');
  v_restricted constant uuid := pg_temp.person('07');
  v_held constant uuid := pg_temp.person('08');
  v_coupled constant uuid := pg_temp.person('09');
  v_partner constant uuid := pg_temp.person('10');
  v_msg text;
BEGIN
  IF has_function_privilege('authenticated', 'public.dating_eligibility(uuid,text)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.dating_eligibility(uuid,text)', 'EXECUTE')
     OR has_function_privilege('service_role', 'public.dating_eligibility(uuid,text)', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: dating_eligibility is callable outside the database';
  END IF;

  UPDATE public.feature_flags SET enabled = false WHERE key = 'dating_mode_enabled';
  IF pg_temp.both(v_ok) IS DISTINCT FROM 'feature_unavailable/feature_unavailable'
     OR pg_temp.both(v_young) IS DISTINCT FROM 'feature_unavailable/feature_unavailable' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: with dating_mode_enabled off the first reason is not feature_unavailable';
  END IF;
  UPDATE public.feature_flags SET enabled = true WHERE key = 'dating_mode_enabled';

  UPDATE public.account_birthdates SET birth_date = current_date - interval '17 years' WHERE user_id = v_young;
  DELETE FROM public.account_birthdates WHERE user_id = v_nodob;
  UPDATE auth.users SET phone_confirmed_at = NULL WHERE id = v_unconfirmed;
  UPDATE public.users SET eula_version = '1' WHERE id = v_eula1;
  UPDATE public.users SET eula_accepted_at = NULL WHERE id = v_noeula;
  INSERT INTO public.dating_account_restrictions (user_id, restriction_type) VALUES (v_restricted, 'suspended');
  PERFORM public.place_account_hold(v_held, 'age_review', 'spec2-w1b-contract');
  INSERT INTO public.relationships (user_a, user_b, status) VALUES (v_coupled, v_partner, 'active');

  IF pg_temp.both(v_ok) IS DISTINCT FROM 'eligible/country_closed' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an adult with no Dating country yet is % (expected eligible to set up, not a candidate)', pg_temp.both(v_ok);
  END IF;
  IF pg_temp.both(v_young) IS DISTINCT FROM 'account_unavailable/account_unavailable'
     OR pg_temp.both(v_nodob) IS DISTINCT FROM 'account_unavailable/account_unavailable' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an under-18 or undated account passed gate 2';
  END IF;
  IF pg_temp.both(v_unconfirmed) IS DISTINCT FROM 'account_unavailable/account_unavailable' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an unconfirmed phone passed gate 2';
  END IF;
  IF pg_temp.both(v_eula1) IS DISTINCT FROM 'account_unavailable/account_unavailable'
     OR pg_temp.both(v_noeula) IS DISTINCT FROM 'account_unavailable/account_unavailable' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an account without EULA v2 passed gate 2';
  END IF;
  IF pg_temp.both(v_restricted) IS DISTINCT FROM 'account_unavailable/account_unavailable'
     OR pg_temp.both(v_held) IS DISTINCT FROM 'account_unavailable/account_unavailable' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a restricted or held account passed gate 3';
  END IF;
  IF pg_temp.both(v_coupled) IS DISTINCT FROM 'relationship_active/relationship_active' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an account in a relationship is % (expected relationship_active)', pg_temp.both(v_coupled);
  END IF;
  -- First failing reason: an under-18 or restricted account in a
  -- relationship is account_unavailable.
  INSERT INTO public.relationships (user_a, user_b, status, invite_code, invite_expires_at)
  VALUES (v_young, NULL, 'pending', 'W1BELIG1', now() + interval '1 day'),
         (v_restricted, NULL, 'pending', 'W1BELIG2', now() + interval '1 day');
  IF pg_temp.both(v_young) IS DISTINCT FROM 'account_unavailable/account_unavailable'
     OR pg_temp.both(v_restricted) IS DISTINCT FROM 'account_unavailable/account_unavailable' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the gates are not checked in order';
  END IF;
  -- No Healing journey and no readiness score: Healing never gates Dating.
  IF EXISTS (SELECT 1 FROM public.healing_journeys WHERE user_id = v_ok) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the fixture has a Healing journey';
  END IF;
  BEGIN
    PERFORM public.dating_eligibility(v_ok, 'browse');
    RAISE EXCEPTION 'CONTRACT VIOLATED: an unknown scope was accepted';
  EXCEPTION WHEN invalid_parameter_value THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    IF v_msg IS DISTINCT FROM 'eligibility:invalid_scope' THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: an unknown scope raised %', v_msg;
    END IF;
  END;
END $$;

-- =====================================================================
-- C. (W1b, A-10) Spec 1's seam keeps exactly {enabled, enrolled}.
-- =====================================================================
DO $$
DECLARE
  v_ok constant uuid := pg_temp.id('01');
  v_young constant uuid := pg_temp.id('02');
  v jsonb;
BEGIN
  v := private.dating_home_summary(v_ok);
  IF (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(v) AS k) IS DISTINCT FROM ARRAY['enabled', 'enrolled']
     OR v IS DISTINCT FROM '{"enabled": true, "enrolled": false}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: dating_home_summary is %', v;
  END IF;
  -- Enabled means the feature is on for the person, not that they qualify.
  IF private.dating_home_summary(v_young) IS DISTINCT FROM '{"enabled": true, "enrolled": false}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: dating_home_summary.enabled followed a later gate';
  END IF;
  INSERT INTO public.dating_enrollments (user_id, state) VALUES (v_ok, 'profile_draft');
  UPDATE public.feature_flags SET enabled = false WHERE key = 'dating_mode_enabled';
  IF private.dating_home_summary(v_ok) IS DISTINCT FROM '{"enabled": false, "enrolled": true}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: with the flag off the summary is %', private.dating_home_summary(v_ok);
  END IF;
  UPDATE public.feature_flags SET enabled = true WHERE key = 'dating_mode_enabled';
  -- Through Spec 1's home state, as the person.
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_ok, 'role', 'authenticated')::text, true);
  PERFORM set_config('request.jwt.claim.sub', v_ok::text, true);
  v := public.get_my_home_state() -> 'dating';
  RESET ROLE;
  PERFORM set_config('request.jwt.claims', '', true);
  PERFORM set_config('request.jwt.claim.sub', '', true);
  IF v IS DISTINCT FROM '{"enabled": true, "enrolled": true}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: get_my_home_state().dating is %', v;
  END IF;
END $$;

DO $$ BEGIN RAISE NOTICE 'dating_v2_eligibility_contracts: all held'; END $$;
ROLLBACK;
```

```bash
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/dating_v2_eligibility_contracts.sql 2>&1 | grep -E 'ERROR|all held' | head -1 | sed -E 's/^psql:[^ ]* //'
```

Expected: `ERROR:  function public.dating_eligibility(uuid, unknown) does not exist`.

- [ ] **Step 2: Write migration 5 and its twin**

Create `supabase/migrations/20261106140000_dating_v2_eligibility_base.sql` with exactly:

```sql
-- Spec 2 W1b, migration 5 (spec §4.9 W1b #2, §2.1; I-14, A-10, I-4):
--   * dating_eligibility(p_user, p_scope DEFAULT 'candidate') -> the first
--     failing reason or 'eligible', with gates 1-4 and 6 (W2 adds 5, W4b 8,
--     W8b 7): 1 dating_mode_enabled -> feature_unavailable; 2 Spec 1's
--     account_age >= 18, a confirmed Auth phone and EULA v2 ->
--     account_unavailable; 3 dating_account_in_good_standing (W1a: bans,
--     restrictions, enforcement records, Spec 1 holds) ->
--     account_unavailable; 4 dating_has_relationship -> relationship_active;
--     6 the profile's Dating country open (country_closed) and its region
--     open (region_closed). The country is read by name (the column arrives
--     in W1c); with none chosen yet, the 'setup' scope passes gate 6 and the
--     'candidate' scope fails it (a candidate always has one). Server only.
--   * Spec 1's seam private.dating_home_summary(p_user) re-created from its
--     live body (20261025100300): 'enabled' = dating_eligibility(p_user,
--     'setup') <> 'feature_unavailable'; 'enrolled' unchanged; the shape
--     {enabled, enrolled} is kept (A-10).
-- Grants in 20261106140010_dating_v2_eligibility_base_grants.sql.
BEGIN;
SET LOCAL lock_timeout = '5s';

CREATE OR REPLACE FUNCTION public.dating_eligibility(p_user uuid, p_scope text DEFAULT 'candidate')
RETURNS text
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $fn$
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
  IF NOT public.dating_flag_enabled('dating_mode_enabled') THEN
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
  -- 3. Standing.
  IF NOT public.dating_account_in_good_standing(p_user) THEN
    RETURN 'account_unavailable';
  END IF;
  -- 4. Relationship guard.
  IF public.dating_has_relationship(p_user) THEN
    RETURN 'relationship_active';
  END IF;
  -- 6. Country and region.
  SELECT to_jsonb(p) INTO v_profile FROM public.dating_profiles AS p WHERE p.user_id = p_user;
  v_country := v_profile ->> 'country_code';
  v_region := v_profile ->> 'region_code';
  IF v_country IS NULL THEN
    RETURN CASE WHEN p_scope = 'setup' THEN 'eligible' ELSE 'country_closed' END;
  END IF;
  v_config := public.dating_country_config(v_country);
  IF v_config IS NULL OR NOT v_config.dating_enabled THEN
    RETURN 'country_closed';
  END IF;
  IF v_config.open_regions IS NOT NULL
     AND (v_region IS NULL OR NOT (v_region = ANY (v_config.open_regions))) THEN
    RETURN CASE WHEN v_region IS NULL AND p_scope = 'setup' THEN 'eligible' ELSE 'region_closed' END;
  END IF;
  RETURN 'eligible';
END;
$fn$;

CREATE OR REPLACE FUNCTION private.dating_home_summary(p_user uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  SELECT jsonb_build_object(
    'enabled', public.dating_eligibility(p_user, 'setup') <> 'feature_unavailable', -- Spec 2 W1b (A-10)
    'enrolled', EXISTS (
      SELECT 1 FROM public.dating_enrollments AS e
       WHERE e.user_id = p_user
         AND e.state IN ('profile_draft', 'active', 'paused', 'suspended')));
$function$;

REVOKE ALL ON FUNCTION public.dating_eligibility(uuid, text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_home_summary(uuid) FROM PUBLIC, anon, authenticated, service_role;

COMMIT;
```

Create `supabase/migrations/20261106140010_dating_v2_eligibility_base_grants.sql` with exactly:

```sql
-- Spec 2 W1b: grants for 20261106140000_dating_v2_eligibility_base.sql.
-- Both are the database's own: clients see eligibility only through
-- get_dating_home() (W2) and the summary through Spec 1's get_my_home_state().
BEGIN;
SET LOCAL lock_timeout = '5s';
REVOKE ALL ON FUNCTION public.dating_eligibility(uuid, text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_home_summary(uuid) FROM PUBLIC, anon, authenticated, service_role;
COMMIT;
```

- [ ] **Step 3: Apply each file twice; diff the seam; run the contracts**

```bash
for i in 1 2; do
  for f in 20261106140000_dating_v2_eligibility_base 20261106140010_dating_v2_eligibility_base_grants; do
    psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/migrations/$f.sql > /dev/null 2>&1; echo "$f exit=$?"
  done
done
```

```bash
D=.superpowers/sdd/2026-11-06-spec2-w1
for sig in 'private.dating_home_summary(uuid)'; do
  echo "== $sig"
  diff "$D/before/$sig.sql" <(psql -X -d attune_spec3a -Atc "select pg_get_functiondef('$sig'::regprocedure)") | grep '^[<>]'
done
```

```bash
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/dating_v2_eligibility_contracts.sql 2>&1 | grep -E 'ERROR|all held' | head -1 | sed -E 's/^psql:[^ ]* //'
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/identity_foundation_contracts.sql >/dev/null 2>&1; echo "identity_foundation exit=$?"
```

Expected: four `exit=0` lines; then exactly:

```text
== private.dating_home_summary(uuid)
<     'enabled', public.dating_flag_enabled('dating_mode_enabled'),
>     'enabled', public.dating_eligibility(p_user, 'setup') <> 'feature_unavailable', -- Spec 2 W1b (A-10)
```

then `NOTICE:  dating_v2_eligibility_contracts: all held`, `identity_foundation exit=0`.

- [ ] **Step 4: The canary's rows for this migration**

Create `.superpowers/sdd/2026-11-06-spec2-w1/canary_T6.sql` with exactly:

```sql
-- ---------------------------------------------------------------------
-- W1b (migration 5): eligibility.
-- ---------------------------------------------------------------------
INSERT INTO allowed_fn (sig, clients) VALUES
  ('dating_eligibility(uuid,text)', '');
```

```bash
D=.superpowers/sdd/2026-11-06-spec2-w1
python3 -I $D/section.py supabase/tests/dating_rls_canary.sql $D/canary_T6.sql --before '-- Checks (every batch adds its rows above this line).'
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/dating_rls_canary.sql 2>&1 | grep -E 'ERROR|all held' | head -1 | sed -E 's/^psql:[^ ]* //'
```

Expected: `dating_rls_canary.sql: canary_T6.sql before`, then `NOTICE:  dating_rls_canary: all held` (before this step, with the migration applied, the canary names every new object as `not in the canary's allow-list`).

- [ ] **Step 5: Mutation checks**

Create `.superpowers/sdd/2026-11-06-spec2-w1/mut_T6.py` with exactly:

```python
MUTS = {
 'no_feature_gate': ("""  IF NOT public.dating_flag_enabled('dating_mode_enabled') THEN
    RETURN 'feature_unavailable';
  END IF;""", ""),
 'no_age_gate': ("""     OR coalesce(public.account_age(p_user), 0) < 18
""", ""),
 'undated_passes': ("""     OR coalesce(public.account_age(p_user), 0) < 18""", """     OR coalesce(public.account_age(p_user), 18) < 18"""),
 'no_phone_gate': ("""     OR NOT EXISTS (SELECT 1 FROM auth.users AS a WHERE a.id = p_user AND a.phone_confirmed_at IS NOT NULL)
""", ""),
 'eula_v1_passes': ("""                       AND coalesce(substring(u.eula_version FROM '^[0-9]{1,3}$')::integer, 0) >= 2) THEN""", """                       ) THEN"""),
 'no_standing_gate': ("""  IF NOT public.dating_account_in_good_standing(p_user) THEN
    RETURN 'account_unavailable';
  END IF;""", ""),
 'no_relationship_gate': ("""  IF public.dating_has_relationship(p_user) THEN
    RETURN 'relationship_active';
  END IF;""", ""),
 'relationship_first': ("""  -- 3. Standing.
  IF NOT public.dating_account_in_good_standing(p_user) THEN""", """  IF public.dating_has_relationship(p_user) THEN
    RETURN 'relationship_active';
  END IF;
  IF NOT public.dating_account_in_good_standing(p_user) THEN"""),
 'candidate_without_country': ("""    RETURN CASE WHEN p_scope = 'setup' THEN 'eligible' ELSE 'country_closed' END;""", """    RETURN 'eligible';"""),
 'any_scope': ("""  IF p_scope IS NULL OR p_scope NOT IN ('setup', 'candidate') THEN""", """  IF p_scope IS NULL THEN"""),
 'summary_changes_shape': ("""    'enabled', public.dating_eligibility(p_user, 'setup') <> 'feature_unavailable', -- Spec 2 W1b (A-10)""", """    'enabled', public.dating_eligibility(p_user, 'setup') = 'eligible', -- Spec 2 W1b (A-10)"""),
}
```

```bash
D=.superpowers/sdd/2026-11-06-spec2-w1
python3 -I $D/mutate.py supabase/migrations/20261106140000_dating_v2_eligibility_base.sql supabase/tests/dating_v2_eligibility_contracts.sql $D/mut_T6.py $D
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/dating_v2_eligibility_contracts.sql 2>&1 | grep -E 'ERROR|all held' | head -1 | sed -E 's/^psql:[^ ]* //'
```

Expected:

- `no_feature_gate`: `ERROR:  CONTRACT VIOLATED: with dating_mode_enabled off the first reason is not feature_unavailable`
- `no_age_gate`: `ERROR:  CONTRACT VIOLATED: an under-18 or undated account passed gate 2`
- `undated_passes`: `ERROR:  CONTRACT VIOLATED: an under-18 or undated account passed gate 2`
- `no_phone_gate`: `ERROR:  CONTRACT VIOLATED: an unconfirmed phone passed gate 2`
- `eula_v1_passes`: `ERROR:  CONTRACT VIOLATED: an account without EULA v2 passed gate 2`
- `no_standing_gate`: `ERROR:  CONTRACT VIOLATED: a restricted or held account passed gate 3`
- `no_relationship_gate`: `ERROR:  CONTRACT VIOLATED: an account in a relationship is eligible/country_closed (expected relationship_active)`
- `relationship_first`: `ERROR:  CONTRACT VIOLATED: the gates are not checked in order`
- `candidate_without_country`: `ERROR:  CONTRACT VIOLATED: an adult with no Dating country yet is eligible/eligible (expected eligible to set up, not a candidate)`
- `any_scope`: `ERROR:  CONTRACT VIOLATED: an unknown scope was accepted`
- `summary_changes_shape`: `ERROR:  CONTRACT VIOLATED: dating_home_summary.enabled followed a later gate`

then `NOTICE:  dating_v2_eligibility_contracts: all held`.

- [ ] **Step 6: The local harness (edit only, never run)**

`scripts/local_pg_grants.sql`: append after the last line (`\i supabase/migrations/20261106130010_dating_v2_country_config_grants.sql`), exactly:

```sql

-- Spec 2 W1b: eligibility and the home-summary seam are the database's own.
\i supabase/migrations/20261106140010_dating_v2_eligibility_base_grants.sql
```

```bash
python3 -I - <<'PY'
import pathlib
p = pathlib.Path('scripts/local_pg_grants.sql')
s = p.read_text()
assert s.endswith('\\i supabase/migrations/20261106130010_dating_v2_country_config_grants.sql' + chr(10))
p.write_text(s + chr(10) + "-- Spec 2 W1b: eligibility and the home-summary seam are the database's own." + chr(10) + '\\i supabase/migrations/20261106140010_dating_v2_eligibility_base_grants.sql' + chr(10))
print('local_pg_grants.sql: one \\i block added')
PY
```

### Task 7: The dev script opens GH and GB; its production refusal (mutant 25); the CI `attune_environment` guard; the W1b gate (§4.9 dev switch-on, R-6, R10, Q19b; P-20)

**Files:**
- Modify: `supabase/sql/dev_enable_spec2_dating_flags.sql` (rewritten), `supabase/tests/country_safety_config_contracts.sql` (section H), `.github/workflows/tests.yml` (one step)

**Interfaces:**
- Consumes: Task 5's `publish_country_config`, `dating_country_config`; Task 1's dev script.
- Produces: the dev script in its W1 form (every Dating flag on, GH and GB open, idempotent).

- [ ] **Step 1: Write the failing contract section**

Create `.superpowers/sdd/2026-11-06-spec2-w1/country_H.sql` with exactly:

```sql
-- =====================================================================
-- H. (W1b, R-6, mutant 25) The dev script: refused in production mode
--    before it changes anything; in development it turns every Dating
--    flag on and opens GH and GB, and a re-run publishes nothing new.
--    (-v dev_script_path=<file> runs another copy, for the mutant.)
-- =====================================================================
\if :{?dev_script_path}
\else
\set dev_script_path supabase/sql/dev_enable_spec2_dating_flags.sql
\endif
\set dev_script `cat :dev_script_path`
CREATE TEMP TABLE dev_script ON COMMIT DROP AS SELECT :'dev_script'::text AS body;

DO $$
DECLARE
  v_body constant text := (SELECT body FROM dev_script);
  v_msg text;
  v_versions int;
BEGIN
  IF coalesce(v_body, '') = '' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the dev script is missing or empty';
  END IF;
  UPDATE public.feature_flags SET enabled = false WHERE key LIKE 'dating\_%';
  PERFORM pg_temp.publish('GH', '{"dating_enabled": false}');
  PERFORM pg_temp.publish('GB', '{"dating_enabled": false}');

  PERFORM set_config('app.settings.attune_environment', 'production', true);
  BEGIN
    EXECUTE v_body;
  EXCEPTION WHEN raise_exception THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
  END;
  PERFORM set_config('app.settings.attune_environment', '', true);
  IF v_msg IS DISTINCT FROM 'env:not_development'
     OR EXISTS (SELECT 1 FROM public.feature_flags WHERE key LIKE 'dating\_%' AND enabled)
     OR (pg_temp.current('GH')).dating_enabled OR (pg_temp.current('GB')).dating_enabled THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the dev script was not refused in production mode before any change (%)', v_msg;
  END IF;
  IF v_body ~* '(set_config\s*\(\s*''app\.settings\.attune_environment''|SET\s+(LOCAL\s+)?app\.settings\.attune_environment|create_secret\s*\([^)]*''attune_environment'')' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the dev script sets attune_environment';
  END IF;

  EXECUTE v_body;
  IF EXISTS (SELECT 1 FROM public.feature_flags
              WHERE key IN ('dating_mode_enabled', 'dating_candidate_generation', 'dating_match_messaging',
                            'dating_profile_photos', 'dating_alignment_algorithm_v1', 'dating_same_gender_matching')
                AND NOT enabled)
     OR NOT (pg_temp.current('GH')).dating_enabled OR NOT (pg_temp.current('GB')).dating_enabled
     OR (pg_temp.current('GH')).open_regions IS DISTINCT FROM ARRAY['AA', 'AH'] THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: in development the dev script did not turn every Dating flag on and open GH and GB';
  END IF;
  v_versions := (SELECT count(*) FROM public.country_safety_config);
  EXECUTE v_body;
  IF (SELECT count(*) FROM public.country_safety_config) IS DISTINCT FROM v_versions THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: re-running the dev script published new versions';
  END IF;
END $$;
```

```bash
python3 -I .superpowers/sdd/2026-11-06-spec2-w1/section.py supabase/tests/country_safety_config_contracts.sql .superpowers/sdd/2026-11-06-spec2-w1/country_H.sql --end
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/country_safety_config_contracts.sql 2>&1 | grep -E 'ERROR|all held' | head -1 | sed -E 's/^psql:[^ ]* //'
```

Expected: `country_safety_config_contracts.sql: country_H.sql end`, then `ERROR:  CONTRACT VIOLATED: in development the dev script did not turn every Dating flag on and open GH and GB` (Task 1's script neither turns `dating_same_gender_matching` on nor opens a country).

- [ ] **Step 2: Rewrite the dev script**

Replace the whole of `supabase/sql/dev_enable_spec2_dating_flags.sql` with exactly:

```sql
-- DEV / MANUAL TESTING ONLY. Never a migration (Spec 2 §4.9, R-6, Q19b,
-- I-15). Turns every Spec 2 Dating flag that exists ON, and opens Ghana and
-- the UK for Dating, on the development project only. The guard comes
-- first and everything is one statement, so when Spec 1's guard raises
-- env:not_development (the project doesn't read 'development', or
-- supabase_url is set and doesn't name the development ref, or it can't be
-- read) nothing changes. It never sets attune_environment; nothing in Spec
-- 2 does. Safe to re-run (a country already open is not published again).
-- Re-run it after any migration replay: 20260705210000 forces the Dating
-- flags off when it replays (R10). Every later Spec 2 batch extends it.
DO $$
DECLARE
  v jsonb;
  v_country text;
BEGIN
  PERFORM private.assert_development_project();

  -- W1a: every Dating flag that exists. W1b: dating_same_gender_matching.
  INSERT INTO public.feature_flags (key, enabled) VALUES
    ('dating_mode_enabled', true),
    ('dating_candidate_generation', true),
    ('dating_match_messaging', true),
    ('dating_profile_photos', true),
    ('dating_alignment_algorithm_v1', true),
    ('dating_same_gender_matching', true)
  ON CONFLICT (key) DO UPDATE SET enabled = EXCLUDED.enabled, updated_at = now();

  -- W1b: Ghana (Greater Accra and Ashanti, as seeded) and the UK open.
  FOREACH v_country IN ARRAY ARRAY['GH', 'GB'] LOOP
    IF NOT (public.dating_country_config(v_country)).dating_enabled THEN
      v := public.publish_country_config(v_country,
             '{"dating_enabled": true, "published_by": "dev_enable_spec2_dating_flags"}'::jsonb);
      IF (v ->> 'ok')::boolean IS NOT TRUE THEN
        RAISE EXCEPTION 'dev_enable_spec2_dating_flags: % was not opened: %', v_country, v;
      END IF;
    END IF;
  END LOOP;
END $$;
```

```bash
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/country_safety_config_contracts.sql 2>&1 | grep -E 'ERROR|all held' | head -1 | sed -E 's/^psql:[^ ]* //'
```

Expected: `NOTICE:  country_safety_config_contracts: all held`.

- [ ] **Step 3: Mutation checks on the script (mutant 25 and two more)**

```bash
D=.superpowers/sdd/2026-11-06-spec2-w1
grep -v 'assert_development_project' supabase/sql/dev_enable_spec2_dating_flags.sql > $D/mut_dev_no_guard.sql
sed "s/('dating_same_gender_matching', true)/('dating_same_gender_matching', false)/" supabase/sql/dev_enable_spec2_dating_flags.sql > $D/mut_dev_flag_off.sql
sed 's/    IF NOT (public.dating_country_config(v_country)).dating_enabled THEN/    IF true THEN/' supabase/sql/dev_enable_spec2_dating_flags.sql > $D/mut_dev_republish.sql
for m in no_guard flag_off republish; do
  echo "$m: $(psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -v dev_script_path=$D/mut_dev_$m.sql -f supabase/tests/country_safety_config_contracts.sql 2>&1 | grep -m1 ERROR | sed -E 's/^psql:[^ ]* //' | cut -c1-170)"
done
rm $D/mut_dev_*.sql
```

Expected:
- `no_guard` (mutant 25): `ERROR:  CONTRACT VIOLATED: the dev script was not refused in production mode before any change (flag:gate_evidence_required)` (without the guard the script runs in production mode until Spec 1's flag gate stops it: the contract demands `env:not_development` before any change)
- `flag_off`: `ERROR:  CONTRACT VIOLATED: in development the dev script did not turn every Dating flag on and open GH and GB`
- `republish`: `ERROR:  CONTRACT VIOLATED: re-running the dev script published new versions`

- [ ] **Step 4: The CI guard: nothing sets `attune_environment`**

Create `.superpowers/sdd/2026-11-06-spec2-w1/edit_tests_yml_w1b.py` with exactly:

```python
import pathlib
p = pathlib.Path('.github/workflows/tests.yml')
s = p.read_text()
anchor = """      - name: Scan the repository and its history
        run: ./gitleaks detect --source . --redact --no-banner --exit-code 1
"""
step = """
      # Spec 2 W1b (R-6, Q19b, §7.1): only the owner sets the project to
      # production mode; no migration, script or edge function writes
      # app.settings.attune_environment (comment lines are ignored).
      - name: Nothing sets attune_environment
        run: |
          if grep -rniE "(set_config[[:space:]]*\\([[:space:]]*'app\\.settings\\.attune_environment'|SET[[:space:]]+(LOCAL[[:space:]]+)?app\\.settings\\.attune_environment|(create|update)_secret[[:space:]]*\\([^)]*'attune_environment')" \\
               supabase/migrations supabase/sql scripts supabase/functions \\
             | grep -vE ':[0-9]+:[[:space:]]*(--|//)'; then
            echo "::error::A migration, script or edge function sets attune_environment; only the owner does (Spec 2 R-6)"
            exit 1
          fi
"""
assert s.count(anchor) == 1
p.write_text(s.replace(anchor, anchor + step))
print('tests.yml: attune_environment guard added')
```

```bash
python3 -I .superpowers/sdd/2026-11-06-spec2-w1/edit_tests_yml_w1b.py
ruby -e 'require "yaml"; y = YAML.load_file(".github/workflows/tests.yml"); s = y["jobs"]["repo-guards"]["steps"].last; puts s["name"]; File.write(".superpowers/sdd/2026-11-06-spec2-w1/env_guard.sh", s["run"])'
bash .superpowers/sdd/2026-11-06-spec2-w1/env_guard.sh; echo "tree exit=$?"
printf "%s\n" "SELECT set_config('app.settings.attune_environment', 'production', false);" > supabase/sql/zz_env_probe.sql
bash .superpowers/sdd/2026-11-06-spec2-w1/env_guard.sh; echo "probe exit=$?"
rm supabase/sql/zz_env_probe.sql
```

Expected: `tests.yml: attune_environment guard added`; `Nothing sets attune_environment`; `tree exit=0` (no output line before it); then `supabase/sql/zz_env_probe.sql:1:SELECT set_config('app.settings.attune_environment', 'production', false);`, the `::error::` line and `probe exit=1`.

- [ ] **Step 5: Run tests (the W1b gate)**

```bash
D=.superpowers/sdd/2026-11-06-spec2-w1
for f in supabase/tests/*.sql; do
  if psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f "$f" >/dev/null 2>&1; then echo "PASS $(basename "$f")"; else echo "FAIL $(basename "$f")"; fi
done > $D/sql-after-task7.txt
grep '^FAIL' $D/sql-after-task7.txt | sort | comm -13 <(cat $D/sql-baseline*.txt | grep '^FAIL' | sort -u) - | grep -vE 'FAIL ai_(session|assist|assistant|processing)_'
grep '^FAIL' $D/sql-after-task7.txt | sort | comm -13 <(cat $D/sql-baseline*.txt | grep '^FAIL' | sort -u) - | grep -E 'FAIL ai_' | sed 's/^FAIL //' | while read t; do
  echo "$t: $(psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/$t 2>&1 | grep -m1 ERROR | grep -ci dating) Dating mentions"
done
git status --short -- lib test | head
sed -n '/if (isAuthenticated \&\& !_gateData.isComplete) {/,/_redirectingToOnboarding = false;/p' lib/home/home_screen.dart | shasum | diff - $D/latch.sha && echo latch-unchanged
flutter test test/architecture/games_untouched_test.dart 2>&1 | tail -1
```

Expected: as Task 4 Step 7, against `$D/sql-after-task7.txt`, with `country_safety_config_contracts.sql`, `dating_v2_eligibility_contracts.sql` and `dating_rls_canary.sql` also `PASS`.

**W1b gate:** nothing beyond W1's (the seeds are closed; production opens a country only through `publish_country_config`'s checks, W10).

# W1c · Encryption, profile fields, setup writers (Tasks 8-10)

### Task 8: Migration 6: the profile and preference fields, `dating_profile_sensitive`, prompts, settings, the field key (§4.9 W1c, §4.2, §4.3; P-21-P-23)

**Files:**
- Create: `supabase/migrations/20261106150000_dating_v2_profile_fields.sql`, `…150010_dating_v2_profile_fields_grants.sql`
- Modify: `supabase/tests/dating_v2_identity_contracts.sql` (D1), `supabase/tests/dating_v2_eligibility_contracts.sql` (B), `supabase/tests/country_safety_config_contracts.sql` (F2), `supabase/tests/dating_rls_canary.sql`, `scripts/local_pg_grants.sql`

**Interfaces:**
- Consumes: `public.app_setting('dating_field_key')`, `extensions.pgp_sym_encrypt` / `pgp_sym_decrypt`, `dating_consent_events (user_id, purpose, action, occurred_at, created_at)`.
- Produces: the §4.3 columns on `dating_profiles` and `dating_preferences` (P-22 keeps the v1 ones); `public.dating_profile_sensitive (user_id, identity_enc, seeking_enc, faith_enc, marital_enc, key_version, updated_at)`; `public.dating_prompts (user_id, position 1-3, prompt_id, answer 10-200, moderation_state, updated_at)`; `public.dating_settings (user_id, drop_time, data_saver, digest_push, chat_push, show_when_away, updated_at)`; `private.dating_field_key_present() → boolean`, `private.dating_field_encrypt(jsonb) → bytea`, `private.dating_field_decrypt(bytea) → jsonb` (raise `dating:field_key_missing`), `private.dating_consent_granted(uuid, text) → boolean` (the latest event decides), `public.dating_require_trusted_device() → boolean` (true until W4b).

- [ ] **Step 1: Write the failing sections**

Create `.superpowers/sdd/2026-11-06-spec2-w1/identity_D1.sql` with exactly:

```sql
-- =====================================================================
-- D1. (W1c) The field key and its two functions (§4.2): pgp_sym_encrypt
--    under dating_field_key, a fresh ciphertext each time, no plaintext,
--    nothing without the key, and no API role (the service role included)
--    reads the sensitive table or calls the functions.
-- =====================================================================
DO $$
DECLARE
  v_u constant uuid := pg_temp.person('39');
  v_one bytea;
  v_two bytea;
  v_t text;
  v_msg text;
BEGIN
  PERFORM set_config('app.settings.dating_field_key', 'spec2-w1c-identity-field-key-0123456789abcdef', true);
  IF NOT private.dating_field_key_present() THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a 44-character dating_field_key reads as missing';
  END IF;
  v_one := private.dating_field_encrypt('{"identity": "woman", "pools": ["woman"]}');
  v_two := private.dating_field_encrypt('{"identity": "woman", "pools": ["woman"]}');
  IF v_one IS NULL OR v_one = v_two
     OR position('woman' IN encode(v_one, 'escape')) IS DISTINCT FROM 0
     OR position('identity' IN encode(v_one, 'escape')) IS DISTINCT FROM 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the field ciphertext is deterministic or holds a plaintext marker';
  END IF;
  IF private.dating_field_decrypt(v_one) IS DISTINCT FROM '{"identity": "woman", "pools": ["woman"]}'::jsonb
     OR extensions.pgp_sym_decrypt(v_one, 'spec2-w1c-identity-field-key-0123456789abcdef')::jsonb ->> 'identity'
          IS DISTINCT FROM 'woman'
     OR private.dating_field_encrypt(NULL) IS NOT NULL OR private.dating_field_decrypt(NULL) IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the field functions are not pgp_sym under dating_field_key';
  END IF;
  -- A short key is no key.
  PERFORM set_config('app.settings.dating_field_key', 'too-short', true);
  IF private.dating_field_key_present() THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a 9-character key reads as present';
  END IF;
  PERFORM set_config('app.settings.dating_field_key', '', true);
  BEGIN
    PERFORM private.dating_field_encrypt('{"x": 1}');
    v_msg := NULL;
  EXCEPTION WHEN raise_exception THEN
    v_msg := SQLERRM;
  END;
  IF v_msg IS DISTINCT FROM 'dating:field_key_missing' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: dating_field_encrypt ran without the key (%)', v_msg;
  END IF;
  BEGIN
    PERFORM private.dating_field_decrypt(v_one);
    v_msg := NULL;
  EXCEPTION WHEN raise_exception THEN
    v_msg := SQLERRM;
  END;
  IF v_msg IS DISTINCT FROM 'dating:field_key_missing' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: dating_field_decrypt ran without the key (%)', v_msg;
  END IF;
  PERFORM set_config('app.settings.dating_field_key', 'spec2-w1c-identity-field-key-0123456789abcdef', true);
  -- Consent: the latest event decides (a withdrawal ends it; a new grant restores it).
  INSERT INTO public.dating_consent_events (user_id, idempotency_key, purpose, action, policy_version, occurred_at)
  VALUES (v_u, 'w1c-c1', 'special_category_profile', 'granted', 'dating-2.0', clock_timestamp());
  IF NOT private.dating_consent_granted(v_u, 'special_category_profile')
     OR private.dating_consent_granted(v_u, 'special_category_faith') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: dating_consent_granted does not read the granted purpose';
  END IF;
  INSERT INTO public.dating_consent_events (user_id, idempotency_key, purpose, action, policy_version, occurred_at)
  VALUES (v_u, 'w1c-c2', 'special_category_profile', 'withdrawn', 'dating-2.0', clock_timestamp());
  IF private.dating_consent_granted(v_u, 'special_category_profile') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a withdrawn consent still counts';
  END IF;
  INSERT INTO public.dating_consent_events (user_id, idempotency_key, purpose, action, policy_version, occurred_at)
  VALUES (v_u, 'w1c-c3', 'special_category_profile', 'granted', 'dating-2.0', clock_timestamp());
  IF NOT private.dating_consent_granted(v_u, 'special_category_profile') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a consent granted again after a withdrawal does not count';
  END IF;
  IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid = 'public.dating_profile_sensitive'::regclass)
     OR has_table_privilege('service_role', 'public.dating_profile_sensitive', 'SELECT')
     OR has_table_privilege('authenticated', 'public.dating_profile_sensitive', 'SELECT')
     OR has_table_privilege('anon', 'public.dating_profile_sensitive', 'SELECT') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an API role can read dating_profile_sensitive';
  END IF;
  FOREACH v_t IN ARRAY ARRAY['private.dating_field_encrypt(jsonb)', 'private.dating_field_decrypt(bytea)',
                             'private.dating_field_key_present()', 'private.dating_consent_granted(uuid,text)'] LOOP
    IF has_function_privilege('service_role', v_t, 'EXECUTE') OR has_function_privilege('authenticated', v_t, 'EXECUTE')
       OR has_function_privilege('anon', v_t, 'EXECUTE') THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: % is callable by an API role', v_t;
    END IF;
  END LOOP;
END $$;
```

Create `.superpowers/sdd/2026-11-06-spec2-w1/elig_B.sql` with exactly:

```sql
-- =====================================================================
-- B. (W1c) Gate 6: the profile's Dating country and region are open.
-- =====================================================================
DO $$
DECLARE
  v_accra constant uuid := pg_temp.person('20');
  v_volta constant uuid := pg_temp.person('21');
  v_lagos constant uuid := pg_temp.person('22');
  v_noregion constant uuid := pg_temp.person('23');
  v_london constant uuid := pg_temp.person('24');
BEGIN
  PERFORM public.publish_country_config('GH', '{"dating_enabled": true}');
  PERFORM public.publish_country_config('GB', '{"dating_enabled": true}');
  INSERT INTO public.dating_profiles (user_id, display_name, country_code, region_code) VALUES
    (v_accra, 'Accra', 'GH', 'AA'), (v_volta, 'Volta', 'GH', 'TV'), (v_lagos, 'Lagos', 'NG', NULL),
    (v_noregion, 'No region', 'GH', NULL), (v_london, 'London', 'GB', NULL);
  IF pg_temp.both(v_accra) IS DISTINCT FROM 'eligible/eligible' OR pg_temp.both(v_london) IS DISTINCT FROM 'eligible/eligible' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an open country and region failed gate 6 (%, %)', pg_temp.both(v_accra), pg_temp.both(v_london);
  END IF;
  IF pg_temp.both(v_volta) IS DISTINCT FROM 'region_closed/region_closed' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a closed Ghana region is % (expected region_closed)', pg_temp.both(v_volta);
  END IF;
  IF pg_temp.both(v_lagos) IS DISTINCT FROM 'country_closed/country_closed' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a closed country is % (expected country_closed)', pg_temp.both(v_lagos);
  END IF;
  IF pg_temp.both(v_noregion) IS DISTINCT FROM 'eligible/region_closed' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: Ghana without a region yet is % (eligible to set up, not a candidate)', pg_temp.both(v_noregion);
  END IF;
  PERFORM public.publish_country_config('GH', '{"dating_enabled": false}');
  IF pg_temp.both(v_accra) IS DISTINCT FROM 'country_closed/country_closed' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: closing Ghana did not close it for its people at once';
  END IF;
END $$;
```

Create `.superpowers/sdd/2026-11-06-spec2-w1/country_F2.sql` with exactly:

```sql
-- =====================================================================
-- F2. (W1c) The away streak, once profiles carry a Dating country:
--    consecutive checks away from it count up, one at home resets it.
-- =====================================================================
DO $$
DECLARE
  v_u constant uuid := pg_temp.id('02');
BEGIN
  INSERT INTO auth.users (id, phone, phone_confirmed_at) VALUES (v_u, '1555870102', now());
  INSERT INTO public.users (id, phone, display_name) VALUES (v_u, '1555870102', 'Traveller');
  INSERT INTO public.dating_profiles (user_id, display_name, country_code, region_code) VALUES (v_u, 'Traveller', 'GB', 'TLI');
  EXECUTE 'SET LOCAL ROLE service_role';
  PERFORM public.record_dating_session_context(v_u, 'FR', NULL);
  PERFORM public.record_dating_session_context(v_u, 'ES', NULL);
  PERFORM pg_temp.as_owner();
  IF (SELECT mismatch_streak::text || away_from_home::text FROM public.dating_session_context WHERE user_id = v_u) IS DISTINCT FROM '2true' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: two checks away did not count a streak of 2';
  END IF;
  EXECUTE 'SET LOCAL ROLE service_role';
  PERFORM public.record_dating_session_context(v_u, 'GB', NULL);
  PERFORM pg_temp.as_owner();
  IF (SELECT mismatch_streak::text || away_from_home::text FROM public.dating_session_context WHERE user_id = v_u) IS DISTINCT FROM '0false' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a check at home did not reset the away streak';
  END IF;
END $$;
```

```bash
D=.superpowers/sdd/2026-11-06-spec2-w1
python3 -I $D/section.py supabase/tests/dating_v2_identity_contracts.sql $D/identity_D1.sql --end
python3 -I $D/section.py supabase/tests/dating_v2_eligibility_contracts.sql $D/elig_B.sql --before "-- C. (W1b, A-10) Spec 1's seam keeps exactly {enabled, enrolled}."
python3 -I $D/section.py supabase/tests/country_safety_config_contracts.sql $D/country_F2.sql --before '-- G. Validation: nothing is published from a malformed request.'
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/dating_v2_identity_contracts.sql 2>&1 | grep -E 'ERROR|all held' | head -1 | sed -E 's/^psql:[^ ]* //'
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/dating_v2_eligibility_contracts.sql 2>&1 | grep -E 'ERROR|all held' | head -1 | sed -E 's/^psql:[^ ]* //'
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/country_safety_config_contracts.sql 2>&1 | grep -E 'ERROR|all held' | head -1 | sed -E 's/^psql:[^ ]* //'
```

Expected: the three `section.py` lines; then `ERROR:  function private.dating_field_key_present() does not exist`, `ERROR:  column "country_code" of relation "dating_profiles" does not exist`, `ERROR:  column "country_code" of relation "dating_profiles" does not exist`.

- [ ] **Step 2: Write migration 6 and its twin**

Create `supabase/migrations/20261106150000_dating_v2_profile_fields.sql` with exactly:

```sql
-- Spec 2 W1c, migration 6 (spec §4.9 W1c #1, part 1 of 3: fields and
-- encryption; §4.2, §4.3, §4.4):
--   * dating_require_trusted_device() as a pass-through that always allows
--     (W4b re-creates it with the real check; every Dating RPC already
--     calls it, so none is re-created then).
--   * dating_profiles: country, region, side, intention, marriage timeline,
--     attestation, children, family involvement, the visibility toggles,
--     photos after mutual interest, country_changed_at; display_name 1-30
--     (NOT VALID: older rows are not rewritten); the v1 gender-visibility
--     CHECK dropped (gender now lives encrypted). The v1 columns
--     city_region_code, relationship_intention, bio and gender_identity stay,
--     nullable, until their last readers go (plan P-14).
--   * dating_preferences: ages 18-99; region_scope, intention_open,
--     open_abroad, want_must_match, exclude_parents (the v1 arrays stay
--     until W5a's hard filters v2, P-14).
--   * dating_profile_sensitive (identity, seeking, faith, marital history,
--     each pgp_sym_encrypt'ed with the Vault key dating_field_key; revoked
--     from service_role too), dating_prompts, dating_settings.
--   * private.dating_field_key_present(), dating_field_encrypt(jsonb),
--     dating_field_decrypt(bytea): EXECUTE for nobody (definer callers only).
--   * private.dating_consent_granted(user, purpose): granted, never
--     withdrawn since.
-- Grants in 20261106150010_dating_v2_profile_fields_grants.sql.
BEGIN;
SET LOCAL lock_timeout = '5s';

CREATE OR REPLACE FUNCTION public.dating_require_trusted_device()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $fn$
  -- W1c pass-through; W4b reads the x-attune-device header here.
  SELECT true;
$fn$;

ALTER TABLE public.dating_profiles
  ALTER COLUMN city_region_code DROP NOT NULL,
  ALTER COLUMN relationship_intention DROP NOT NULL,
  ADD COLUMN IF NOT EXISTS country_code char(2),
  ADD COLUMN IF NOT EXISTS region_code text,
  ADD COLUMN IF NOT EXISTS side_code text,
  ADD COLUMN IF NOT EXISTS intention text,
  ADD COLUMN IF NOT EXISTS marriage_timeline text,
  ADD COLUMN IF NOT EXISTS timeline_visible boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS not_married_attested_at timestamptz,
  ADD COLUMN IF NOT EXISTS attestation_version text,
  ADD COLUMN IF NOT EXISTS children_have boolean,
  ADD COLUMN IF NOT EXISTS children_want text,
  ADD COLUMN IF NOT EXISTS family_involvement text,
  ADD COLUMN IF NOT EXISTS faith_visible boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS marital_visible boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS photos_after_mutual boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS country_changed_at timestamptz;
ALTER TABLE public.dating_profiles DROP CONSTRAINT IF EXISTS dating_profiles_gender_visibility_check;
ALTER TABLE public.dating_profiles DROP CONSTRAINT IF EXISTS dating_profiles_display_name_length_check;
ALTER TABLE public.dating_profiles ADD CONSTRAINT dating_profiles_display_name_length_check
  CHECK (char_length(btrim(display_name)) BETWEEN 1 AND 30) NOT VALID;
ALTER TABLE public.dating_profiles DROP CONSTRAINT IF EXISTS dating_profiles_v2_check;
ALTER TABLE public.dating_profiles ADD CONSTRAINT dating_profiles_v2_check CHECK (
  (country_code IS NULL OR country_code ~ '^[A-Z]{2}$')
  AND (intention IS NULL OR intention IN ('marriage', 'committed', 'companionship', 'not_sure'))
  AND (marriage_timeline IS NULL OR (intention = 'marriage'
       AND marriage_timeline IN ('within_two_years', 'few_years', 'no_set_time')))
  AND (children_want IS NULL OR children_want IN ('yes', 'no', 'open'))
  AND (family_involvement IS NULL OR family_involvement IN ('early', 'when_serious', 'our_decision'))
  AND (side_code IS NULL OR region_code IS NOT NULL)
  AND (region_code IS NULL OR country_code IS NOT NULL));

ALTER TABLE public.dating_preferences
  ADD COLUMN IF NOT EXISTS region_scope text NOT NULL DEFAULT 'region',
  ADD COLUMN IF NOT EXISTS intention_open text[],
  ADD COLUMN IF NOT EXISTS open_abroad char(2)[] NOT NULL DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS want_must_match boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS exclude_parents boolean NOT NULL DEFAULT false;
ALTER TABLE public.dating_preferences DROP CONSTRAINT IF EXISTS dating_preferences_min_age_check;
ALTER TABLE public.dating_preferences ADD CONSTRAINT dating_preferences_min_age_check CHECK (min_age BETWEEN 18 AND 99);
ALTER TABLE public.dating_preferences DROP CONSTRAINT IF EXISTS dating_preferences_max_age_check;
ALTER TABLE public.dating_preferences ADD CONSTRAINT dating_preferences_max_age_check CHECK (max_age BETWEEN 18 AND 99);
ALTER TABLE public.dating_preferences DROP CONSTRAINT IF EXISTS dating_preferences_v2_check;
ALTER TABLE public.dating_preferences ADD CONSTRAINT dating_preferences_v2_check CHECK (
  region_scope IN ('side', 'region', 'country')
  AND (intention_open IS NULL OR intention_open <@ ARRAY['marriage', 'committed', 'companionship', 'not_sure']));

CREATE TABLE IF NOT EXISTS public.dating_profile_sensitive (
  user_id uuid PRIMARY KEY REFERENCES public.users(id) ON DELETE CASCADE,
  identity_enc bytea,
  seeking_enc bytea,
  faith_enc bytea,
  marital_enc bytea,
  key_version smallint NOT NULL DEFAULT 1,
  updated_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.dating_profile_sensitive ENABLE ROW LEVEL SECURITY;
COMMENT ON TABLE public.dating_profile_sensitive IS
  'Spec 2 §4.2: special-category answers, encrypted with the Vault key dating_field_key. No API role reads it, the service role included; only definer functions decrypt.';

CREATE TABLE IF NOT EXISTS public.dating_prompts (
  user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  position smallint NOT NULL CHECK (position BETWEEN 1 AND 3),
  prompt_id text NOT NULL CHECK (prompt_id IN ('perfect_sunday', 'feel_at_home', 'friends_say',
    'looking_for', 'small_thing', 'win_me_over', 'learning_to', 'family_describe', 'place_love', 'ask_me_about')),
  answer text NOT NULL CHECK (char_length(answer) BETWEEN 10 AND 200),
  moderation_state text NOT NULL DEFAULT 'approved' CHECK (moderation_state IN ('approved', 'removed')),
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, position),
  UNIQUE (user_id, prompt_id)
);
ALTER TABLE public.dating_prompts ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.dating_settings (
  user_id uuid PRIMARY KEY REFERENCES public.users(id) ON DELETE CASCADE,
  drop_time time NOT NULL DEFAULT '19:00'
    CHECK (drop_time BETWEEN '07:00' AND '22:00' AND extract(second FROM drop_time) = 0
           AND extract(minute FROM drop_time) IN (0, 30)),
  data_saver boolean NOT NULL DEFAULT false,
  digest_push boolean NOT NULL DEFAULT false,
  chat_push boolean NOT NULL DEFAULT true,
  show_when_away boolean NOT NULL DEFAULT false,
  updated_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.dating_settings ENABLE ROW LEVEL SECURITY;

-- The field key (Vault through Spec 1's app_setting; a local GUC falls
-- back). Present means at least 32 characters.
CREATE OR REPLACE FUNCTION private.dating_field_key_present()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $fn$
  SELECT coalesce(char_length(public.app_setting('dating_field_key')) >= 32, false);
$fn$;

CREATE OR REPLACE FUNCTION private.dating_field_encrypt(p_plain jsonb)
RETURNS bytea
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_key constant text := public.app_setting('dating_field_key');
BEGIN
  IF p_plain IS NULL THEN
    RETURN NULL;
  END IF;
  IF coalesce(char_length(v_key), 0) < 32 THEN
    RAISE EXCEPTION 'dating:field_key_missing';
  END IF;
  -- Compression off, so the ciphertext's length says nothing about the content.
  RETURN extensions.pgp_sym_encrypt(p_plain::text, v_key, 'cipher-algo=aes256, compress-algo=0');
END;
$fn$;

CREATE OR REPLACE FUNCTION private.dating_field_decrypt(p_cipher bytea)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_key constant text := public.app_setting('dating_field_key');
BEGIN
  IF p_cipher IS NULL THEN
    RETURN NULL;
  END IF;
  IF coalesce(char_length(v_key), 0) < 32 THEN
    RAISE EXCEPTION 'dating:field_key_missing';
  END IF;
  RETURN extensions.pgp_sym_decrypt(p_cipher, v_key)::jsonb;
END;
$fn$;

CREATE OR REPLACE FUNCTION private.dating_consent_granted(p_user uuid, p_purpose text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $fn$
  SELECT coalesce((
    SELECT e.action = 'granted'
      FROM public.dating_consent_events AS e
     WHERE e.user_id = p_user AND e.purpose = p_purpose
     ORDER BY e.occurred_at DESC, e.created_at DESC
     LIMIT 1), false);
$fn$;

REVOKE ALL ON public.dating_profile_sensitive FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON public.dating_prompts, public.dating_settings FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.dating_require_trusted_device(), private.dating_field_key_present(),
  private.dating_field_encrypt(jsonb), private.dating_field_decrypt(bytea),
  private.dating_consent_granted(uuid, text)
  FROM PUBLIC, anon, authenticated, service_role;

COMMIT;
```

Create `supabase/migrations/20261106150010_dating_v2_profile_fields_grants.sql` with exactly:

```sql
-- Spec 2 W1c: grants for 20261106150000_dating_v2_profile_fields.sql.
-- dating_profile_sensitive is no API role's, the service role's included
-- (S-5, §4.2); prompts and settings are the service role's (moderation,
-- W7) and no client's; the key and consent helpers are definer-only.
BEGIN;
SET LOCAL lock_timeout = '5s';
REVOKE ALL ON public.dating_profile_sensitive FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON public.dating_prompts, public.dating_settings FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.dating_prompts, public.dating_settings TO service_role;
REVOKE ALL ON FUNCTION public.dating_require_trusted_device(), private.dating_field_key_present(),
  private.dating_field_encrypt(jsonb), private.dating_field_decrypt(bytea),
  private.dating_consent_granted(uuid, text)
  FROM PUBLIC, anon, authenticated, service_role;
COMMIT;
```

- [ ] **Step 3: Apply each file twice; run the contracts**

```bash
for i in 1 2; do
  for f in 20261106150000_dating_v2_profile_fields 20261106150010_dating_v2_profile_fields_grants; do
    psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/migrations/$f.sql > /dev/null 2>&1; echo "$f exit=$?"
  done
done
```

```bash
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/dating_v2_identity_contracts.sql 2>&1 | grep -E 'ERROR|all held' | head -1 | sed -E 's/^psql:[^ ]* //'
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/dating_v2_eligibility_contracts.sql 2>&1 | grep -E 'ERROR|all held' | head -1 | sed -E 's/^psql:[^ ]* //'
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/country_safety_config_contracts.sql 2>&1 | grep -E 'ERROR|all held' | head -1 | sed -E 's/^psql:[^ ]* //'
```

Expected: four `exit=0` lines; `NOTICE:  dating_v2_identity_contracts: all held`, `NOTICE:  dating_v2_eligibility_contracts: all held`, `NOTICE:  country_safety_config_contracts: all held`.

- [ ] **Step 4: The canary's rows for this migration**

Create `.superpowers/sdd/2026-11-06-spec2-w1/canary_T8.sql` with exactly:

```sql
-- ---------------------------------------------------------------------
-- W1c (migration 6): the encrypted answers (no API role, the service role
-- included), prompts, settings, the key and consent helpers.
-- ---------------------------------------------------------------------
INSERT INTO allowed_rel (name, authenticated, service_dml) VALUES
  ('dating_profile_sensitive', '', ''),
  ('dating_prompts', '', 'DELETE,INSERT,SELECT,UPDATE'),
  ('dating_settings', '', 'DELETE,INSERT,SELECT,UPDATE');
INSERT INTO allowed_fn (sig, clients) VALUES
  ('dating_require_trusted_device()', ''),
  ('private.dating_consent_granted(uuid,text)', ''),
  ('private.dating_field_decrypt(bytea)', ''),
  ('private.dating_field_encrypt(jsonb)', ''),
  ('private.dating_field_key_present()', '');
```

```bash
D=.superpowers/sdd/2026-11-06-spec2-w1
python3 -I $D/section.py supabase/tests/dating_rls_canary.sql $D/canary_T8.sql --before '-- Checks (every batch adds its rows above this line).'
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/dating_rls_canary.sql 2>&1 | grep -E 'ERROR|all held' | head -1 | sed -E 's/^psql:[^ ]* //'
```

Expected: `dating_rls_canary.sql: canary_T8.sql before`, then `NOTICE:  dating_rls_canary: all held` (before this step, with the migration applied, the canary names every new object as `not in the canary's allow-list`).

- [ ] **Step 5: Mutation checks**

Create `.superpowers/sdd/2026-11-06-spec2-w1/mut_T8.py` with exactly:

```python
MUTS = {
 'encrypt_without_key': ("""  IF coalesce(char_length(v_key), 0) < 32 THEN
    RAISE EXCEPTION 'dating:field_key_missing';
  END IF;
  -- Compression off""", """  -- Compression off"""),
 'key_always_present': ("""  SELECT coalesce(char_length(public.app_setting('dating_field_key')) >= 32, false);""", """  SELECT true;"""),
 'consent_ignores_withdrawal': ("""    SELECT e.action = 'granted'
      FROM public.dating_consent_events AS e
     WHERE e.user_id = p_user AND e.purpose = p_purpose""", """    SELECT true
      FROM public.dating_consent_events AS e
     WHERE e.user_id = p_user AND e.purpose = p_purpose AND e.action = 'granted'"""),
 'service_reads_sensitive': ('RAW', "GRANT SELECT ON public.dating_profile_sensitive TO service_role;"),
 'client_calls_decrypt': ('RAW', "GRANT EXECUTE ON FUNCTION private.dating_field_decrypt(bytea) TO authenticated;"),
}
```

```bash
D=.superpowers/sdd/2026-11-06-spec2-w1
python3 -I $D/mutate.py supabase/migrations/20261106150000_dating_v2_profile_fields.sql supabase/tests/dating_v2_identity_contracts.sql $D/mut_T8.py $D
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/dating_v2_identity_contracts.sql 2>&1 | grep -E 'ERROR|all held' | head -1 | sed -E 's/^psql:[^ ]* //'
```

Expected:

- `encrypt_without_key`: `ERROR:  CONTRACT VIOLATED: dating_field_encrypt ran without the key (<NULL>)`
- `key_always_present`: `ERROR:  CONTRACT VIOLATED: a 9-character key reads as present`
- `consent_ignores_withdrawal`: `ERROR:  CONTRACT VIOLATED: a withdrawn consent still counts`
- `service_reads_sensitive`: `ERROR:  CONTRACT VIOLATED: an API role can read dating_profile_sensitive`
- `client_calls_decrypt`: `ERROR:  CONTRACT VIOLATED: private.dating_field_decrypt(bytea) is callable by an API role`

then `NOTICE:  dating_v2_identity_contracts: all held`.

- [ ] **Step 6: The local harness (edit only, never run)**

`scripts/local_pg_grants.sql`: append after the last line (`\i supabase/migrations/20261106140010_dating_v2_eligibility_base_grants.sql`), exactly:

```sql

-- Spec 2 W1c: the encrypted answers are no API role's, the service role's
-- included; prompts and settings are the service role's; the key helpers are
-- the database's own.
\i supabase/migrations/20261106150010_dating_v2_profile_fields_grants.sql
```

```bash
python3 -I - <<'PY'
import pathlib
p = pathlib.Path('scripts/local_pg_grants.sql')
s = p.read_text()
assert s.endswith('\\i supabase/migrations/20261106140010_dating_v2_eligibility_base_grants.sql' + chr(10))
p.write_text(s + chr(10) + "-- Spec 2 W1c: the encrypted answers are no API role's, the service role's\n-- included; prompts and settings are the service role's; the key helpers are\n-- the database's own." + chr(10) + '\\i supabase/migrations/20261106150010_dating_v2_profile_fields_grants.sql' + chr(10))
print('local_pg_grants.sql: one \\i block added')
PY
```

### Task 9: Migration 7: the D2-D8 setup writers (§4.4, §3.2 D2-D8, §2.4; mutants 4 and 7; P-24-P-28)

**Files:**
- Create: `supabase/migrations/20261106160000_dating_v2_setup_writers.sql`, `…160010_dating_v2_setup_writers_grants.sql`, `supabase/tests/dating_v2_setup_contracts.sql` (A-E, I, J)
- Modify: `supabase/tests/dating_rls_canary.sql`, `scripts/local_pg_grants.sql`

**Interfaces:**
- Consumes: Task 6's `dating_eligibility`, Task 8's fields and functions, `claim_dating_idempotency`, `account_age`, `private.bump_metric_internal`, `dating_country_config`.
- Produces: `private.dating_setup_guard() → text`, `private.dating_ensure_profile(uuid) → boolean`, `private.dating_same_gender_on(text) → boolean`, `private.dating_default_ages(integer) → integer[]`, `private.dating_invalid(text) → jsonb`; `save_dating_intention`, `save_dating_location`, `save_dating_identity`, `save_dating_who_to_meet`, `save_dating_children`, `save_dating_faith`, `clear_dating_faith` (signatures in "Interfaces produced"; signed in; `save_dating_identity` and `save_dating_who_to_meet` revoked from the service role, P-10).

- [ ] **Step 1: Write the failing contract**

Create `supabase/tests/dating_v2_setup_contracts.sql` with exactly:

```sql
-- supabase/tests/dating_v2_setup_contracts.sql
-- Spec 2 W1c (W3b and W3c extend it) (§2.4, §3.2, §4.4, §7.1, §7.5; plan
-- P-15): the setup writers and the own-profile readers. Off-country
-- same-gender answers return not_available, raise nothing and change no
-- row (A, mutants 4 and 7); D2 (B), D3 (C), D5-D6 on-country (D), D7-D8
-- (E), D10 and D12 (F, W1c migration 8), settings, other countries and
-- photos after mutual (G, migration 8), the readers (H, migration 8), the
-- guards (I), and no field key (J).
-- One BEGIN ... ROLLBACK. Run only on attune_spec3a:
--   psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/dating_v2_setup_contracts.sql
-- Fixture ids 5e2d0000-0000-0000-0000-0000000000NN; phones 15558703NN.
BEGIN;

DO $$
BEGIN
  PERFORM set_config('app.settings.dating_field_key', 'spec2-w1c-contract-field-key-0123456789abcdef', true);
  PERFORM set_config('app.settings.dating_exclusion_key', 'spec2-w1c-contract-exclusion-key', true);
  PERFORM set_config('app.settings.attune_environment', '', true);
  UPDATE public.feature_flags SET enabled = true WHERE key = 'dating_mode_enabled';
  UPDATE public.feature_flags SET enabled = false WHERE key = 'dating_same_gender_matching';
  PERFORM public.publish_country_config('GH', '{"dating_enabled": true, "faith_list": [
      {"code": "christian", "name_key": "dating_faith_christian", "denominations": [
         {"code": "catholic", "name_key": "dating_denomination_catholic"}]},
      {"code": "muslim", "name_key": "dating_faith_muslim", "denominations": []}]}');
  PERFORM public.publish_country_config('GB', '{"dating_enabled": true}');
END $$;

CREATE FUNCTION pg_temp.id(p_n text) RETURNS uuid LANGUAGE sql IMMUTABLE AS $$
  SELECT ('5e2d0000-0000-0000-0000-0000000000' || p_n)::uuid;
$$;

-- An eligible adult [p_n], [p_age] years old, account [p_days] days old,
-- with the D4 consents (and faith's) granted.
CREATE FUNCTION pg_temp.person(p_n text, p_age int DEFAULT 30, p_days int DEFAULT 40) RETURNS uuid LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO auth.users (id, phone, phone_confirmed_at, created_at)
  VALUES (pg_temp.id(p_n), '15558703' || p_n, now(), now() - make_interval(days => p_days));
  INSERT INTO public.users (id, phone, display_name, path, created_at, eula_accepted_at, eula_version)
  VALUES (pg_temp.id(p_n), '15558703' || p_n, 'Ama Person ' || p_n, 'dating', now() - make_interval(days => p_days), now(), '2');
  INSERT INTO public.account_birthdates (user_id, birth_date)
  VALUES (pg_temp.id(p_n), current_date - make_interval(years => p_age) - interval '10 days');
  INSERT INTO public.dating_consent_events (user_id, idempotency_key, purpose, action, policy_version, occurred_at)
  SELECT pg_temp.id(p_n), 'consent-' || p, p, 'granted', 'dating-2.0', clock_timestamp()
    FROM unnest(ARRAY['dating_terms', 'dating_opt_in', 'special_category_profile', 'special_category_faith']) AS p;
  RETURN pg_temp.id(p_n);
END $$;

-- [p_sql] (a writer returning jsonb) as [p_user].
CREATE FUNCTION pg_temp.call(p_user uuid, p_sql text) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
  v jsonb;
BEGIN
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claim.sub', p_user::text, true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
  EXECUTE p_sql INTO v;
  RESET ROLE;
  PERFORM set_config('request.jwt.claim.sub', '', true);
  PERFORM set_config('request.jwt.claims', '', true);
  RETURN v;
END $$;

CREATE FUNCTION pg_temp.key(p text) RETURNS text LANGUAGE sql AS $$
  SELECT 'w1c-' || p || '-' || replace(gen_random_uuid()::text, '-', '');
$$;

-- Everything a person's Dating rows hold, for "nothing changed" checks.
CREATE FUNCTION pg_temp.snapshot(p_user uuid) RETURNS text LANGUAGE sql AS $$
  SELECT md5(concat_ws('|',
    (SELECT to_jsonb(p) - 'updated_at' FROM public.dating_profiles AS p WHERE p.user_id = p_user),
    (SELECT encode(s.identity_enc, 'hex') || encode(coalesce(s.seeking_enc, ''), 'hex') FROM public.dating_profile_sensitive AS s WHERE s.user_id = p_user),
    (SELECT to_jsonb(d) - 'updated_at' FROM public.dating_preferences AS d WHERE d.user_id = p_user),
    (SELECT count(*) FROM public.dating_rpc_idempotency AS i WHERE i.user_id = p_user),
    (SELECT sum(c.count) FROM public.metric_counters AS c WHERE c.key LIKE 'dating.%')));
$$;

CREATE FUNCTION pg_temp.metric(p_key text) RETURNS bigint LANGUAGE sql AS $$
  SELECT coalesce(sum(c.count), 0) FROM public.metric_counters AS c WHERE c.key = p_key;
$$;

-- A person through D2 and D3 in [p_country] / [p_region].
CREATE FUNCTION pg_temp.located(p_n text, p_country text, p_region text) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE
  v_u constant uuid := pg_temp.person(p_n);
  v jsonb;
BEGIN
  v := pg_temp.call(v_u, format('SELECT public.save_dating_intention(%L, ''committed'', NULL, true, true, NULL, false)', pg_temp.key('d2')));
  IF (v ->> 'ok')::boolean IS NOT TRUE THEN RAISE EXCEPTION 'fixture: D2 failed %', v; END IF;
  v := pg_temp.call(v_u, format('SELECT public.save_dating_location(%L, %L, %L, NULL, ''region'')', pg_temp.key('d3'), p_country, p_region));
  IF (v ->> 'ok')::boolean IS NOT TRUE THEN RAISE EXCEPTION 'fixture: D3 failed %', v; END IF;
  RETURN v_u;
END $$;

-- =====================================================================
-- A. Off-country (§2.4, mutants 4 and 7): a same-gender answer in Ghana
--    is not_available, raises nothing, changes nothing, counts nothing.
-- =====================================================================
DO $$
DECLARE
  v_u constant uuid := pg_temp.located('01', 'GH', 'AA');
  v_before text;
  v jsonb;
  v_case text;
BEGIN
  v := pg_temp.call(v_u, format('SELECT public.save_dating_identity(%L, ''man'', NULL, NULL, NULL, false)', pg_temp.key('d5')));
  IF v IS DISTINCT FROM '{"ok": true, "next_step": "meet"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: Man was refused in Ghana: %', v;
  END IF;
  v_before := pg_temp.snapshot(v_u);
  FOREACH v_case IN ARRAY ARRAY[
    'SELECT public.save_dating_identity(%L, ''non_binary'', NULL, NULL, NULL, false)',
    'SELECT public.save_dating_identity(%L, ''non_binary'', NULL, NULL, ARRAY[''woman''], true)',
    'SELECT public.save_dating_identity(%L, ''woman'', ''trans_woman'', NULL, NULL, false)',
    'SELECT public.save_dating_identity(%L, ''man'', NULL, ''they/them'', NULL, false)',
    'SELECT public.save_dating_identity(%L, ''man'', NULL, NULL, ARRAY[''man''], false)',
    'SELECT public.save_dating_who_to_meet(%L, ARRAY[''man''], 25, 35)',
    'SELECT public.save_dating_who_to_meet(%L, ARRAY[''man'', ''woman'', ''non_binary''], 25, 35)'] LOOP
    BEGIN
      v := pg_temp.call(v_u, format(v_case, pg_temp.key('off')));
    EXCEPTION WHEN OTHERS THEN
      RESET ROLE;
      RAISE EXCEPTION 'CONTRACT VIOLATED: an off-country same-gender answer raised (%): %', SQLERRM, v_case;
    END;
    IF v IS DISTINCT FROM '{"ok": false, "reason": "not_available"}'::jsonb THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: an off-country same-gender answer was not refused with not_available (%): %', v_case, v;
    END IF;
    IF pg_temp.snapshot(v_u) IS DISTINCT FROM v_before THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: an off-country same-gender answer changed a row or a counter (%)', v_case;
    END IF;
  END LOOP;
  v := pg_temp.call(v_u, format('SELECT public.save_dating_who_to_meet(%L, ARRAY[''woman''], 25, 35)', pg_temp.key('d6')));
  IF v IS DISTINCT FROM '{"ok": true, "next_step": "children"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a man meeting women was refused in Ghana: %', v;
  END IF;
  -- The global flag off makes every country off, the UK included.
  UPDATE public.feature_flags SET enabled = false WHERE key = 'dating_same_gender_matching';
  IF NOT EXISTS (SELECT 1 FROM public.country_safety_config WHERE country_code = 'GB' AND is_current AND same_gender_enabled) THEN
    RAISE EXCEPTION 'fixture: GB should allow same-gender';
  END IF;
END $$;

DO $$
DECLARE
  v_uk constant uuid := pg_temp.located('02', 'GB', 'TLI');
  v jsonb;
BEGIN
  v := pg_temp.call(v_uk, format('SELECT public.save_dating_identity(%L, ''non_binary'', NULL, NULL, NULL, false)', pg_temp.key('d5')));
  IF v IS DISTINCT FROM '{"ok": false, "reason": "not_available"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: with dating_same_gender_matching off, the UK took a non-binary identity: %', v;
  END IF;
END $$;

-- =====================================================================
-- B. D2: intention, timeline, the attestation (re-asked on every change),
--    the enrolment and profile rows, the counters.
-- =====================================================================
DO $$
DECLARE
  v_u constant uuid := pg_temp.person('03');
  v jsonb;
  v_started bigint := pg_temp.metric('dating.setup.started');
  v_k constant text := pg_temp.key('d2');
BEGIN
  IF pg_temp.call(v_u, format('SELECT public.save_dating_intention(%L, ''casual'', NULL, true, true, NULL, false)', pg_temp.key('x')))
       IS DISTINCT FROM '{"ok": false, "reason": "invalid", "field": "intention"}'::jsonb
     OR pg_temp.call(v_u, format('SELECT public.save_dating_intention(%L, ''committed'', ''few_years'', true, true, NULL, false)', pg_temp.key('x')))
       IS DISTINCT FROM '{"ok": false, "reason": "invalid", "field": "timeline"}'::jsonb
     OR pg_temp.call(v_u, format('SELECT public.save_dating_intention(%L, ''marriage'', ''soon'', true, true, NULL, false)', pg_temp.key('x')))
       IS DISTINCT FROM '{"ok": false, "reason": "invalid", "field": "timeline"}'::jsonb
     OR pg_temp.call(v_u, format('SELECT public.save_dating_intention(%L, ''marriage'', NULL, true, false, NULL, false)', pg_temp.key('x')))
       IS DISTINCT FROM '{"ok": false, "reason": "invalid", "field": "attestation"}'::jsonb
     OR pg_temp.call(v_u, format('SELECT public.save_dating_intention(%L, ''marriage'', NULL, true, true, ''separated'', false)', pg_temp.key('x')))
       IS DISTINCT FROM '{"ok": false, "reason": "invalid", "field": "marital"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: D2 validation is wrong (intention enum, timeline only with marriage, attestation required, marital values)';
  END IF;
  IF EXISTS (SELECT 1 FROM public.dating_profiles WHERE user_id = v_u) OR EXISTS (SELECT 1 FROM public.dating_enrollments WHERE user_id = v_u)
     OR EXISTS (SELECT 1 FROM public.dating_rpc_idempotency WHERE user_id = v_u) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a refused D2 wrote a row or claimed its idempotency key';
  END IF;
  v := pg_temp.call(v_u, format('SELECT public.save_dating_intention(%L, ''marriage'', ''within_two_years'', false, true, ''divorced'', true)', v_k));
  PERFORM pg_temp.call(v_u, format('SELECT public.save_dating_intention(%L, ''marriage'', ''within_two_years'', false, true, ''divorced'', true)', v_k));
  IF v IS DISTINCT FROM '{"ok": true, "next_step": "where"}'::jsonb
     OR NOT EXISTS (SELECT 1 FROM public.dating_enrollments WHERE user_id = v_u AND state = 'profile_draft')
     OR NOT EXISTS (SELECT 1 FROM public.dating_profiles
                     WHERE user_id = v_u AND intention = 'marriage' AND marriage_timeline = 'within_two_years'
                       AND NOT timeline_visible AND marital_visible AND attestation_version = '2026-10-v1'
                       AND not_married_attested_at IS NOT NULL AND display_name = 'Ama Person 03'
                       AND moderation_state = 'approved') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: D2 did not create the enrolment and profile as answered: %', v;
  END IF;
  IF pg_temp.metric('dating.setup.started') IS DISTINCT FROM v_started + 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: dating.setup.started was not counted once (a repeated key counts nothing)';
  END IF;
  IF position('divorced' IN encode((SELECT marital_enc FROM public.dating_profile_sensitive WHERE user_id = v_u), 'escape')) IS DISTINCT FROM 0
     OR private.dating_field_decrypt((SELECT marital_enc FROM public.dating_profile_sensitive WHERE user_id = v_u))
          IS DISTINCT FROM '{"marital": "divorced"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: marriage history is not stored encrypted';
  END IF;
END $$;

-- =====================================================================
-- C. D3: open countries and regions only; sides; scope; one country
--    change per 30 days, which asks D5 and D6 again.
-- =====================================================================
DO $$
DECLARE
  v_u constant uuid := pg_temp.person('04');
  v jsonb;
BEGIN
  PERFORM pg_temp.call(v_u, format('SELECT public.save_dating_intention(%L, ''committed'', NULL, true, true, NULL, false)', pg_temp.key('d2')));
  IF pg_temp.call(v_u, format('SELECT public.save_dating_location(%L, ''NG'', ''LA'', NULL, ''region'')', pg_temp.key('x')))
       IS DISTINCT FROM '{"ok": false, "reason": "country_closed"}'::jsonb
     OR pg_temp.call(v_u, format('SELECT public.save_dating_location(%L, ''GH'', ''TV'', NULL, ''region'')', pg_temp.key('x')))
       IS DISTINCT FROM '{"ok": false, "reason": "region_closed"}'::jsonb
     OR pg_temp.call(v_u, format('SELECT public.save_dating_location(%L, ''GH'', ''XX'', NULL, ''region'')', pg_temp.key('x')))
       IS DISTINCT FROM '{"ok": false, "reason": "invalid", "field": "region"}'::jsonb
     OR pg_temp.call(v_u, format('SELECT public.save_dating_location(%L, ''GH'', ''AA'', ''kumasi'', ''side'')', pg_temp.key('x')))
       IS DISTINCT FROM '{"ok": false, "reason": "invalid", "field": "side"}'::jsonb
     OR pg_temp.call(v_u, format('SELECT public.save_dating_location(%L, ''GH'', ''AA'', NULL, ''side'')', pg_temp.key('x')))
       IS DISTINCT FROM '{"ok": false, "reason": "invalid", "field": "scope"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: D3 accepted a closed country or region, a foreign side, or side scope without a side';
  END IF;
  v := pg_temp.call(v_u, format('SELECT public.save_dating_location(%L, ''GH'', ''AA'', ''tema'', ''side'')', pg_temp.key('d3')));
  IF v IS DISTINCT FROM '{"ok": true, "next_step": "privacy"}'::jsonb
     OR NOT EXISTS (SELECT 1 FROM public.dating_profiles WHERE user_id = v_u AND country_code = 'GH'
                      AND region_code = 'AA' AND side_code = 'tema' AND country_changed_at IS NULL)
     OR (SELECT region_scope || ':' || min_age || '-' || max_age FROM public.dating_preferences WHERE user_id = v_u) IS DISTINCT FROM 'side:25-35' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: D3 did not save the place, the scope and the default ages: %', v;
  END IF;
  PERFORM pg_temp.call(v_u, format('SELECT public.save_dating_identity(%L, ''woman'', NULL, NULL, NULL, true)', pg_temp.key('d5')));
  PERFORM pg_temp.call(v_u, format('SELECT public.save_dating_who_to_meet(%L, ARRAY[''man''], 25, 35)', pg_temp.key('d6')));
  -- A move to the UK: allowed once, and D5 and D6 are asked again.
  v := pg_temp.call(v_u, format('SELECT public.save_dating_location(%L, ''GB'', ''TLI'', NULL, ''region'')', pg_temp.key('d3b')));
  IF v IS DISTINCT FROM '{"ok": true, "next_step": "privacy"}'::jsonb
     OR (SELECT identity_enc IS NOT NULL OR seeking_enc IS NOT NULL FROM public.dating_profile_sensitive WHERE user_id = v_u)
     OR (SELECT gender_visible OR country_changed_at IS NULL FROM public.dating_profiles WHERE user_id = v_u) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a country change kept the gender and who-to-meet answers: %', v;
  END IF;
  IF pg_temp.call(v_u, format('SELECT public.save_dating_location(%L, ''GH'', ''AA'', NULL, ''region'')', pg_temp.key('d3c')))
       IS DISTINCT FROM '{"ok": false, "reason": "country_change_limited"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a second country change within 30 days was allowed';
  END IF;
END $$;

-- =====================================================================
-- D. D5-D6 where same-gender is on (the UK, flag on): the full set;
--    "Everyone" stored explicitly; the D4 consent is required.
-- =====================================================================
DO $$
DECLARE
  v_u constant uuid := pg_temp.located('05', 'GB', 'TLD');
  v_noconsent constant uuid := pg_temp.located('06', 'GB', 'TLD');
  v jsonb;
BEGIN
  UPDATE public.feature_flags SET enabled = true WHERE key = 'dating_same_gender_matching';
  v := pg_temp.call(v_u, format('SELECT public.save_dating_identity(%L, ''non_binary'', ''Two spirit'', ''they/them'', ARRAY[''woman'', ''man'', ''woman''], true)', pg_temp.key('d5')));
  IF v IS DISTINCT FROM '{"ok": true, "next_step": "meet"}'::jsonb
     OR private.dating_field_decrypt((SELECT identity_enc FROM public.dating_profile_sensitive WHERE user_id = v_u))
          IS DISTINCT FROM '{"identity": "non_binary", "specific": null, "specific_text": "Two spirit", "pronouns": "they/them", "pools": ["non_binary", "man", "woman"]}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the UK refused or mis-stored a non-binary identity: %', v;
  END IF;
  IF pg_temp.call(v_u, format('SELECT public.save_dating_identity(%L, ''woman'', NULL, NULL, ARRAY[''man''], false)', pg_temp.key('x')))
       IS DISTINCT FROM '{"ok": false, "reason": "invalid", "field": "pools"}'::jsonb
     OR pg_temp.call(v_u, format('SELECT public.save_dating_identity(%L, ''woman'', ''123'', NULL, NULL, false)', pg_temp.key('x')))
       IS DISTINCT FROM '{"ok": false, "reason": "invalid", "field": "specific"}'::jsonb
     OR pg_temp.call(v_u, format('SELECT public.save_dating_identity(%L, ''other'', NULL, NULL, NULL, false)', pg_temp.key('x')))
       IS DISTINCT FROM '{"ok": false, "reason": "invalid", "field": "identity"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: D5 validation is wrong';
  END IF;
  v := pg_temp.call(v_u, format('SELECT public.save_dating_who_to_meet(%L, ARRAY[''woman'', ''non_binary'', ''man''], 18, 99)', pg_temp.key('d6')));
  IF v IS DISTINCT FROM '{"ok": true, "next_step": "children"}'::jsonb
     OR private.dating_field_decrypt((SELECT seeking_enc FROM public.dating_profile_sensitive WHERE user_id = v_u))
          IS DISTINCT FROM '{"seeking": ["man", "non_binary", "woman"]}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: "Everyone" was not stored as the explicit full set: %', v;
  END IF;
  IF pg_temp.call(v_u, format('SELECT public.save_dating_who_to_meet(%L, ARRAY[''woman'', ''man''], 25, 35)', pg_temp.key('x')))
       IS DISTINCT FROM '{"ok": false, "reason": "invalid", "field": "seeking"}'::jsonb
     OR pg_temp.call(v_u, format('SELECT public.save_dating_who_to_meet(%L, ARRAY[''woman''], 17, 35)', pg_temp.key('x')))
       IS DISTINCT FROM '{"ok": false, "reason": "invalid", "field": "ages"}'::jsonb
     OR pg_temp.call(v_u, format('SELECT public.save_dating_who_to_meet(%L, ARRAY[''woman''], 40, 30)', pg_temp.key('x')))
       IS DISTINCT FROM '{"ok": false, "reason": "invalid", "field": "ages"}'::jsonb
     OR pg_temp.call(v_u, format('SELECT public.save_dating_who_to_meet(%L, ARRAY[''woman''], 30, 100)', pg_temp.key('x')))
       IS DISTINCT FROM '{"ok": false, "reason": "invalid", "field": "ages"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: D6 accepted a partial set or an age outside 18-99';
  END IF;
  IF private.dating_default_ages(18) IS DISTINCT FROM ARRAY[18, 25] OR private.dating_default_ages(20) IS DISTINCT FROM ARRAY[18, 27]
     OR private.dating_default_ages(21) IS DISTINCT FROM ARRAY[18, 26] OR private.dating_default_ages(40) IS DISTINCT FROM ARRAY[35, 45]
     OR private.dating_default_ages(97) IS DISTINCT FROM ARRAY[92, 99] THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the default age ranges are wrong';
  END IF;
  -- Without the D4 consent, D5 and D6 write nothing.
  DELETE FROM public.dating_consent_events WHERE user_id = v_noconsent AND purpose = 'special_category_profile';
  INSERT INTO public.dating_consent_events (user_id, idempotency_key, purpose, action, policy_version, occurred_at)
  VALUES (v_noconsent, 'consent-withdrawn', 'special_category_profile', 'withdrawn', 'dating-2.0', clock_timestamp());
  IF pg_temp.call(v_noconsent, format('SELECT public.save_dating_identity(%L, ''woman'', NULL, NULL, NULL, false)', pg_temp.key('x')))
       IS DISTINCT FROM '{"ok": false, "reason": "consent_required"}'::jsonb
     OR pg_temp.call(v_noconsent, format('SELECT public.save_dating_who_to_meet(%L, ARRAY[''man''], 25, 35)', pg_temp.key('x')))
       IS DISTINCT FROM '{"ok": false, "reason": "consent_required"}'::jsonb
     OR (SELECT identity_enc IS NOT NULL FROM public.dating_profile_sensitive WHERE user_id = v_noconsent) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a special-category answer was saved without the special_category_profile consent';
  END IF;
  UPDATE public.feature_flags SET enabled = false WHERE key = 'dating_same_gender_matching';
END $$;

-- =====================================================================
-- E. D7 (no "seek parents" anywhere) and D8 (the country's list, both
--    consents, "must share" stored, Skip clears).
-- =====================================================================
DO $$
DECLARE
  v_u constant uuid := pg_temp.located('07', 'GH', 'AH');
  v jsonb;
BEGIN
  IF EXISTS (SELECT 1 FROM pg_proc WHERE proname ~ '^save_dating_' AND pg_get_function_arguments(oid) ~* 'seek.*parent|parent.*seek') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a setup writer offers seeking parents (10 S22)';
  END IF;
  IF pg_temp.call(v_u, format('SELECT public.save_dating_children(%L, NULL, ''yes'', false, false)', pg_temp.key('x')))
       IS DISTINCT FROM '{"ok": false, "reason": "invalid", "field": "have"}'::jsonb
     OR pg_temp.call(v_u, format('SELECT public.save_dating_children(%L, true, ''maybe'', false, false)', pg_temp.key('x')))
       IS DISTINCT FROM '{"ok": false, "reason": "invalid", "field": "want"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: D7 validation is wrong';
  END IF;
  v := pg_temp.call(v_u, format('SELECT public.save_dating_children(%L, true, ''open'', true, true)', pg_temp.key('d7')));
  IF v IS DISTINCT FROM '{"ok": true, "next_step": "faith"}'::jsonb
     OR NOT EXISTS (SELECT 1 FROM public.dating_profiles WHERE user_id = v_u AND children_have AND children_want = 'open')
     OR NOT EXISTS (SELECT 1 FROM public.dating_preferences WHERE user_id = v_u AND want_must_match AND exclude_parents) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: D7 was not saved: %', v;
  END IF;
  IF pg_temp.call(v_u, format('SELECT public.save_dating_faith(%L, ''hindu'', NULL, ''must_share'', false)', pg_temp.key('x')))
       IS DISTINCT FROM '{"ok": false, "reason": "invalid", "field": "faith"}'::jsonb
     OR pg_temp.call(v_u, format('SELECT public.save_dating_faith(%L, ''muslim'', ''catholic'', ''must_share'', false)', pg_temp.key('x')))
       IS DISTINCT FROM '{"ok": false, "reason": "invalid", "field": "denomination"}'::jsonb
     OR pg_temp.call(v_u, format('SELECT public.save_dating_faith(%L, ''christian'', NULL, ''a lot'', false)', pg_temp.key('x')))
       IS DISTINCT FROM '{"ok": false, "reason": "invalid", "field": "importance"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: D8 accepted a faith outside the country''s list, a foreign denomination or an unknown importance';
  END IF;
  v := pg_temp.call(v_u, format('SELECT public.save_dating_faith(%L, ''christian'', ''catholic'', ''must_share'', true)', pg_temp.key('d8')));
  IF v IS DISTINCT FROM '{"ok": true, "next_step": "photos"}'::jsonb
     OR private.dating_field_decrypt((SELECT faith_enc FROM public.dating_profile_sensitive WHERE user_id = v_u))
          IS DISTINCT FROM '{"faith": "christian", "denomination": "catholic", "importance": "must_share"}'::jsonb
     OR NOT (SELECT faith_visible FROM public.dating_profiles WHERE user_id = v_u) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: "must share" was not stored: %', v;
  END IF;
  -- Without the faith consent: refused.
  INSERT INTO public.dating_consent_events (user_id, idempotency_key, purpose, action, policy_version, occurred_at)
  VALUES (v_u, 'consent-faith-withdrawn', 'special_category_faith', 'withdrawn', 'dating-2.0', clock_timestamp());
  IF pg_temp.call(v_u, format('SELECT public.save_dating_faith(%L, ''muslim'', NULL, ''nice_to_share'', false)', pg_temp.key('x')))
       IS DISTINCT FROM '{"ok": false, "reason": "consent_required"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: faith was saved without the special_category_faith consent';
  END IF;
  v := pg_temp.call(v_u, format('SELECT public.clear_dating_faith(%L)', pg_temp.key('d8skip')));
  IF v IS DISTINCT FROM '{"ok": true, "next_step": "photos"}'::jsonb
     OR (SELECT faith_enc IS NOT NULL FROM public.dating_profile_sensitive WHERE user_id = v_u)
     OR (SELECT faith_visible FROM public.dating_profiles WHERE user_id = v_u) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: Skip left a faith answer stored';
  END IF;
END $$;

-- =====================================================================
-- I. The guards: signed in; eligible to set up (opaque not_eligible).
-- =====================================================================
DO $$
DECLARE
  v_young constant uuid := pg_temp.person('12', 17);
  v_mid uuid;
  v jsonb;
  v_msg text;
BEGIN
  IF pg_temp.call(v_young, format('SELECT public.save_dating_intention(%L, ''committed'', NULL, true, true, NULL, false)', pg_temp.key('x')))
       IS DISTINCT FROM '{"ok": false, "reason": "not_eligible"}'::jsonb
     OR pg_temp.call(v_young, format('SELECT public.save_dating_children(%L, false, ''yes'', false, false)', pg_temp.key('x')))
       IS DISTINCT FROM '{"ok": false, "reason": "not_eligible"}'::jsonb
     OR EXISTS (SELECT 1 FROM public.dating_enrollments WHERE user_id = v_young) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an under-18 account could start Dating setup';
  END IF;
  -- Ghana closes mid-setup: the next step answers not_eligible and writes nothing.
  v_mid := pg_temp.located('14', 'GH', 'AA');
  PERFORM public.publish_country_config('GH', '{"dating_enabled": false}');
  v := pg_temp.call(v_mid, format('SELECT public.save_dating_children(%L, false, ''yes'', false, false)', pg_temp.key('mid')));
  PERFORM public.publish_country_config('GH', '{"dating_enabled": true}');
  IF v IS DISTINCT FROM '{"ok": false, "reason": "not_eligible"}'::jsonb
     OR (SELECT children_have FROM public.dating_profiles WHERE user_id = v_mid) IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a setup step went through after the country closed: %', v;
  END IF;
  BEGIN
    PERFORM public.save_dating_children('w1c-anon-000000', false, 'yes', false, false);
    RAISE EXCEPTION 'CONTRACT VIOLATED: a setup writer answered without a signed-in user';
  EXCEPTION WHEN insufficient_privilege THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    IF v_msg IS DISTINCT FROM 'not_authenticated' THEN RAISE EXCEPTION 'CONTRACT VIOLATED: expected not_authenticated, got %', v_msg; END IF;
  END;
  IF has_function_privilege('anon', 'public.save_dating_identity(text,text,text,text,text[],boolean)', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.save_dating_identity(text,text,text,text,text[],boolean)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'private.dating_setup_guard()', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the setup writers'' grants are wrong';
  END IF;
END $$;

-- =====================================================================
-- J. Without dating_field_key every special-category writer answers
--    unavailable, raises nothing and changes nothing (§4.2).
-- =====================================================================
DO $$
DECLARE
  v_u constant uuid := pg_temp.located('13', 'GH', 'AA');
  v_before text;
  v jsonb;
BEGIN
  PERFORM set_config('app.settings.dating_field_key', '', true);
  v_before := pg_temp.snapshot(v_u);
  BEGIN
    v := jsonb_build_array(
      pg_temp.call(v_u, format('SELECT public.save_dating_intention(%L, ''committed'', NULL, true, true, ''widowed'', false)', pg_temp.key('k'))),
      pg_temp.call(v_u, format('SELECT public.save_dating_identity(%L, ''woman'', NULL, NULL, NULL, false)', pg_temp.key('k'))),
      pg_temp.call(v_u, format('SELECT public.save_dating_who_to_meet(%L, ARRAY[''man''], 25, 35)', pg_temp.key('k'))),
      pg_temp.call(v_u, format('SELECT public.save_dating_faith(%L, ''christian'', NULL, ''must_share'', false)', pg_temp.key('k'))));
  EXCEPTION WHEN raise_exception THEN
    RESET ROLE;
    RAISE EXCEPTION 'CONTRACT VIOLATED: without dating_field_key a writer raised (%) instead of answering unavailable', SQLERRM;
  END;
  PERFORM set_config('app.settings.dating_field_key', 'spec2-w1c-contract-field-key-0123456789abcdef', true);
  IF v IS DISTINCT FROM '[{"ok": false, "reason": "unavailable"}, {"ok": false, "reason": "unavailable"},
                          {"ok": false, "reason": "unavailable"}, {"ok": false, "reason": "unavailable"}]'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: without dating_field_key a special-category writer did not answer unavailable: %', v;
  END IF;
  IF pg_temp.snapshot(v_u) IS DISTINCT FROM v_before THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: without dating_field_key a writer changed a row';
  END IF;
END $$;

DO $$ BEGIN RAISE NOTICE 'dating_v2_setup_contracts: all held'; END $$;
ROLLBACK;
```

```bash
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/dating_v2_setup_contracts.sql 2>&1 | grep -E 'ERROR|all held' | head -1 | sed -E 's/^psql:[^ ]* //'
```

Expected: `ERROR:  function public.save_dating_intention(unknown, unknown, unknown, boolean, boolean, unknown, boolean) does not exist`.

- [ ] **Step 2: Write migration 7 and its twin**

Create `supabase/migrations/20261106160000_dating_v2_setup_writers.sql` with exactly:

```sql
-- Spec 2 W1c, migration 7 (spec §4.9 W1c #1, part 2 of 3: the setup
-- writers D2-D8; §3.2, §2.4, §4.4):
--   save_dating_intention (D2), save_dating_location (D3),
--   save_dating_identity (D5), save_dating_who_to_meet (D6),
--   save_dating_children (D7), save_dating_faith / clear_dating_faith (D8).
-- Every writer: signed in (else not_authenticated, 42501, like every
-- Dating RPC); dating_require_trusted_device() (reverify_device); then
-- dating_eligibility(me, 'setup') (any failure -> the opaque not_eligible;
-- get_dating_home, W2, says which); then its own validation (invalid, with
-- the field); the special-category writers (D5, D6, D8) need the
-- special_category_profile consent (and D8 special_category_faith) and the
-- field key (unavailable); THEN the idempotency key is claimed
-- (claim_dating_idempotency: a repeat answers ok and writes nothing). Each
-- returns {"ok": true, "next_step": ...} or {"ok": false, "reason": ...}
-- and never raises for a person's own input.
-- Where same-gender is off (the Dating country's same_gender_enabled, and
-- the global flag dating_same_gender_matching), D5 and D6 accept only
-- woman/man and the opposite seeking; anything else returns
-- {"ok": false, "reason": "not_available"} WITHOUT raising (a raise can
-- reach the Postgres log), stores nothing and counts nothing (§2.4).
-- Changing the Dating country (at most once per 30 days) clears the
-- encrypted identity and seeking, so D5 and D6 are asked again (§2.4,
-- plan P-17). Counters are server-side (S-2): dating.setup.started,
-- dating.setup.step.d2..d8.
-- Grants in 20261106160010_dating_v2_setup_writers_grants.sql.
BEGIN;
SET LOCAL lock_timeout = '5s';

-- The checks every setup writer runs first: NULL to go on, else the reason.
CREATE OR REPLACE FUNCTION private.dating_setup_guard()
RETURNS text
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_user constant uuid := auth.uid();
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;
  IF NOT public.dating_require_trusted_device() THEN
    RETURN 'reverify_device';
  END IF;
  IF public.dating_eligibility(v_user, 'setup') <> 'eligible' THEN
    RETURN 'not_eligible';
  END IF;
  RETURN NULL;
END;
$fn$;

-- The enrolment (profile_draft) and the profile row a step writes into;
-- true when this starts a setup (no profile row before).
CREATE OR REPLACE FUNCTION private.dating_ensure_profile(p_user uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_name text;
BEGIN
  INSERT INTO public.dating_enrollments AS e (user_id, state) VALUES (p_user, 'profile_draft')
  ON CONFLICT (user_id) DO UPDATE SET state = 'profile_draft', exited_at = NULL, updated_at = now()
   WHERE e.state IN ('ineligible', 'eligible_to_opt_in', 'exited');
  INSERT INTO public.dating_profile_sensitive (user_id) VALUES (p_user) ON CONFLICT (user_id) DO NOTHING;
  IF EXISTS (SELECT 1 FROM public.dating_profiles AS p WHERE p.user_id = p_user) THEN
    RETURN false;
  END IF;
  SELECT left(btrim(coalesce(u.display_name, '')), 30) INTO v_name FROM public.users AS u WHERE u.id = p_user;
  INSERT INTO public.dating_profiles (user_id, display_name, moderation_state)
  VALUES (p_user, coalesce(nullif(v_name, ''), 'Me'), 'approved');
  RETURN true;
END;
$fn$;

-- Same-gender allowed for a Dating country (§2.4): the global flag and
-- the country's switch.
CREATE OR REPLACE FUNCTION private.dating_same_gender_on(p_country text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $fn$
  SELECT public.dating_flag_enabled('dating_same_gender_matching')
         AND coalesce((public.dating_country_config(p_country)).same_gender_enabled, false);
$fn$;

-- The default age range for a person of [p_age] (§3.2 D6).
CREATE OR REPLACE FUNCTION private.dating_default_ages(p_age integer)
RETURNS integer[]
LANGUAGE sql
IMMUTABLE
SET search_path = ''
AS $fn$
  SELECT CASE WHEN p_age IS NULL THEN ARRAY[18, 99]
              WHEN p_age <= 20 THEN ARRAY[18, least(99, p_age + 7)]
              ELSE ARRAY[greatest(18, p_age - 5), least(99, p_age + 5)] END;
$fn$;

CREATE OR REPLACE FUNCTION private.dating_invalid(p_field text)
RETURNS jsonb
LANGUAGE sql
IMMUTABLE
SET search_path = ''
AS $fn$
  SELECT jsonb_build_object('ok', false, 'reason', 'invalid', 'field', p_field);
$fn$;

-- D2: what are you looking for, the attestation, marriage history.
CREATE OR REPLACE FUNCTION public.save_dating_intention(p_idempotency_key text, p_intention text, p_timeline text,
  p_timeline_visible boolean, p_attested boolean, p_marital text, p_marital_visible boolean)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_user constant uuid := auth.uid();
  v_reason text;
  v_started boolean;
BEGIN
  v_reason := private.dating_setup_guard();
  IF v_reason IS NOT NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', v_reason);
  END IF;
  IF p_intention IS NULL OR p_intention NOT IN ('marriage', 'committed', 'companionship', 'not_sure') THEN
    RETURN private.dating_invalid('intention');
  END IF;
  IF (p_intention = 'marriage' AND p_timeline IS NOT NULL
        AND p_timeline NOT IN ('within_two_years', 'few_years', 'no_set_time'))
     OR (p_intention <> 'marriage' AND p_timeline IS NOT NULL) THEN
    RETURN private.dating_invalid('timeline');
  END IF;
  IF p_attested IS NOT TRUE THEN
    RETURN private.dating_invalid('attestation');
  END IF;
  IF p_marital IS NOT NULL AND p_marital NOT IN ('never', 'divorced', 'widowed') THEN
    RETURN private.dating_invalid('marital');
  END IF;
  IF NOT private.dating_field_key_present() THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'unavailable');
  END IF;
  IF NOT public.claim_dating_idempotency('save_dating_intention', p_idempotency_key) THEN
    RETURN jsonb_build_object('ok', true, 'next_step', 'where');
  END IF;

  v_started := private.dating_ensure_profile(v_user);
  UPDATE public.dating_profiles AS p
     SET intention = p_intention,
         marriage_timeline = CASE WHEN p_intention = 'marriage' THEN p_timeline END,
         timeline_visible = coalesce(p_timeline_visible, true),
         not_married_attested_at = now(),
         attestation_version = '2026-10-v1',
         marital_visible = coalesce(p_marital_visible, false) AND p_marital IN ('divorced', 'widowed'),
         updated_at = now()
   WHERE p.user_id = v_user;
  UPDATE public.dating_profile_sensitive AS s
     SET marital_enc = private.dating_field_encrypt(CASE WHEN p_marital IS NULL THEN NULL
                                                        ELSE jsonb_build_object('marital', p_marital) END),
         updated_at = now()
   WHERE s.user_id = v_user;
  IF v_started THEN
    PERFORM private.bump_metric_internal('dating.setup.started');
  END IF;
  PERFORM private.bump_metric_internal('dating.setup.step.d2');
  RETURN jsonb_build_object('ok', true, 'next_step', 'where');
END;
$fn$;

-- D3: where (country, region, side, how far).
CREATE OR REPLACE FUNCTION public.save_dating_location(p_idempotency_key text, p_country text, p_region text,
  p_side text, p_scope text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_user constant uuid := auth.uid();
  v_reason text;
  v_country constant text := upper(coalesce(p_country, ''));
  v_config public.country_safety_config;
  v_region jsonb;
  v_old_country text;
  v_changed_at timestamptz;
  v_ages integer[];
BEGIN
  v_reason := private.dating_setup_guard();
  IF v_reason IS NOT NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', v_reason);
  END IF;
  v_config := public.dating_country_config(v_country);
  IF v_config IS NULL THEN
    RETURN private.dating_invalid('country');
  END IF;
  IF NOT v_config.dating_enabled THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'country_closed');
  END IF;
  SELECT r INTO v_region FROM jsonb_array_elements(v_config.region_list) AS r WHERE r ->> 'code' = p_region;
  IF v_region IS NULL THEN
    RETURN private.dating_invalid('region');
  END IF;
  IF v_config.open_regions IS NOT NULL AND NOT (p_region = ANY (v_config.open_regions)) THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'region_closed');
  END IF;
  IF p_side IS NOT NULL AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(coalesce(v_region -> 'sides', '[]'::jsonb)) AS s
                                         WHERE s ->> 'code' = p_side) THEN
    RETURN private.dating_invalid('side');
  END IF;
  IF p_scope IS NULL OR p_scope NOT IN ('side', 'region', 'country') OR (p_scope = 'side' AND p_side IS NULL) THEN
    RETURN private.dating_invalid('scope');
  END IF;
  SELECT p.country_code, p.country_changed_at INTO v_old_country, v_changed_at
    FROM public.dating_profiles AS p WHERE p.user_id = v_user;
  IF v_old_country IS NOT NULL AND v_old_country <> v_country
     AND v_changed_at IS NOT NULL AND v_changed_at > now() - interval '30 days' THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'country_change_limited');
  END IF;
  IF NOT public.claim_dating_idempotency('save_dating_location', p_idempotency_key) THEN
    RETURN jsonb_build_object('ok', true, 'next_step', 'privacy');
  END IF;

  PERFORM private.dating_ensure_profile(v_user);
  UPDATE public.dating_profiles AS p
     SET country_code = v_country, region_code = p_region, side_code = p_side,
         country_changed_at = CASE WHEN p.country_code IS DISTINCT FROM v_country AND p.country_code IS NOT NULL
                                   THEN now() ELSE p.country_changed_at END,
         updated_at = now()
   WHERE p.user_id = v_user;
  -- A new Dating country: gender and who-to-meet are asked again (§2.4).
  IF v_old_country IS NOT NULL AND v_old_country <> v_country THEN
    UPDATE public.dating_profile_sensitive AS s
       SET identity_enc = NULL, seeking_enc = NULL, updated_at = now()
     WHERE s.user_id = v_user;
    UPDATE public.dating_profiles AS p SET gender_visible = false WHERE p.user_id = v_user;
    UPDATE public.dating_preferences AS d
       SET open_abroad = array_remove(d.open_abroad, v_country::char(2)) WHERE d.user_id = v_user;
  END IF;
  v_ages := private.dating_default_ages(public.account_age(v_user));
  INSERT INTO public.dating_preferences AS d (user_id, min_age, max_age, region_scope)
  VALUES (v_user, v_ages[1], v_ages[2], p_scope)
  ON CONFLICT (user_id) DO UPDATE SET region_scope = EXCLUDED.region_scope, updated_at = now();
  PERFORM private.bump_metric_internal('dating.setup.step.d3');
  RETURN jsonb_build_object('ok', true, 'next_step', 'privacy');
END;
$fn$;

-- D5: which best describes you.
CREATE OR REPLACE FUNCTION public.save_dating_identity(p_idempotency_key text, p_identity text, p_specific text,
  p_pronouns text, p_extra_pools text[], p_visible boolean)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_user constant uuid := auth.uid();
  v_reason text;
  v_country text;
  v_extra constant text[] := coalesce(p_extra_pools, ARRAY[]::text[]);
  v_known constant text[] := ARRAY['trans_woman', 'trans_man', 'genderfluid', 'genderqueer', 'agender', 'intersex'];
  v_old jsonb;
  v_pools text[];
BEGIN
  v_reason := private.dating_setup_guard();
  IF v_reason IS NOT NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', v_reason);
  END IF;
  IF NOT private.dating_consent_granted(v_user, 'special_category_profile') THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'consent_required');
  END IF;
  SELECT p.country_code INTO v_country FROM public.dating_profiles AS p WHERE p.user_id = v_user;
  IF v_country IS NULL THEN
    RETURN private.dating_invalid('country');
  END IF;
  -- Off-country (§2.4): only Woman or Man, nothing more; anything else is
  -- not_available, raised by nothing, stored nowhere, counted nowhere.
  IF NOT private.dating_same_gender_on(v_country)
     AND (p_identity IS DISTINCT FROM 'woman' AND p_identity IS DISTINCT FROM 'man'
          OR p_specific IS NOT NULL OR p_pronouns IS NOT NULL OR cardinality(v_extra) > 0) THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'not_available');
  END IF;
  IF p_identity IS NULL OR p_identity NOT IN ('woman', 'man', 'non_binary') THEN
    RETURN private.dating_invalid('identity');
  END IF;
  IF p_specific IS NOT NULL AND NOT (p_specific = ANY (v_known))
     AND NOT ((p_specific COLLATE "pg_c_utf8") ~ '^[[:alpha:]][[:alpha:] -]{0,29}$' AND char_length(btrim(p_specific)) BETWEEN 1 AND 30) THEN
    RETURN private.dating_invalid('specific');
  END IF;
  IF p_pronouns IS NOT NULL AND char_length(btrim(p_pronouns)) NOT BETWEEN 1 AND 20 THEN
    RETURN private.dating_invalid('pronouns');
  END IF;
  IF NOT v_extra <@ ARRAY['woman', 'man'] OR (cardinality(v_extra) > 0 AND p_identity <> 'non_binary') THEN
    RETURN private.dating_invalid('pools');
  END IF;
  IF NOT private.dating_field_key_present() THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'unavailable');
  END IF;
  IF NOT public.claim_dating_idempotency('save_dating_identity', p_idempotency_key) THEN
    RETURN jsonb_build_object('ok', true, 'next_step', 'meet');
  END IF;

  PERFORM private.dating_ensure_profile(v_user);
  v_pools := CASE p_identity WHEN 'non_binary'
               THEN ARRAY['non_binary'] || ARRAY(SELECT DISTINCT e FROM unnest(v_extra) AS e ORDER BY e)
               ELSE ARRAY[p_identity] END;
  SELECT private.dating_field_decrypt(s.identity_enc) INTO v_old
    FROM public.dating_profile_sensitive AS s WHERE s.user_id = v_user;
  UPDATE public.dating_profile_sensitive AS s
     SET identity_enc = private.dating_field_encrypt(jsonb_build_object(
           'identity', p_identity,
           'specific', CASE WHEN p_specific = ANY (v_known) THEN p_specific END,
           'specific_text', CASE WHEN p_specific IS NOT NULL AND NOT (p_specific = ANY (v_known)) THEN btrim(p_specific) END,
           'pronouns', nullif(btrim(p_pronouns), ''),
           'pools', to_jsonb(v_pools))),
         -- A changed identity where same-gender is off: who-to-meet is asked again.
         seeking_enc = CASE WHEN NOT private.dating_same_gender_on(v_country)
                             AND v_old ->> 'identity' IS DISTINCT FROM p_identity THEN NULL
                            ELSE s.seeking_enc END,
         updated_at = now()
   WHERE s.user_id = v_user;
  UPDATE public.dating_profiles AS p SET gender_visible = coalesce(p_visible, false), updated_at = now()
   WHERE p.user_id = v_user;
  PERFORM private.bump_metric_internal('dating.setup.step.d5');
  RETURN jsonb_build_object('ok', true, 'next_step', 'meet');
END;
$fn$;

-- D6: who would you like to meet, and their ages.
CREATE OR REPLACE FUNCTION public.save_dating_who_to_meet(p_idempotency_key text, p_seeking text[],
  p_min_age integer, p_max_age integer)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_user constant uuid := auth.uid();
  v_reason text;
  v_country text;
  v_identity jsonb;
  v_seeking text[];
BEGIN
  v_reason := private.dating_setup_guard();
  IF v_reason IS NOT NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', v_reason);
  END IF;
  IF NOT private.dating_consent_granted(v_user, 'special_category_profile') THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'consent_required');
  END IF;
  IF NOT private.dating_field_key_present() THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'unavailable');
  END IF;
  SELECT p.country_code INTO v_country FROM public.dating_profiles AS p WHERE p.user_id = v_user;
  SELECT private.dating_field_decrypt(s.identity_enc) INTO v_identity
    FROM public.dating_profile_sensitive AS s WHERE s.user_id = v_user;
  IF v_country IS NULL OR v_identity IS NULL THEN
    RETURN private.dating_invalid('identity');
  END IF;
  v_seeking := ARRAY(SELECT DISTINCT e FROM unnest(coalesce(p_seeking, ARRAY[]::text[])) AS e ORDER BY e);
  -- Off-country (§2.4): only the opposite of a woman or a man.
  IF NOT private.dating_same_gender_on(v_country)
     AND v_seeking IS DISTINCT FROM (CASE v_identity ->> 'identity' WHEN 'woman' THEN ARRAY['man']
                                                                  WHEN 'man' THEN ARRAY['woman'] END) THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'not_available');
  END IF;
  IF v_seeking NOT IN (ARRAY['man'], ARRAY['woman'], ARRAY['man', 'non_binary', 'woman']) THEN
    RETURN private.dating_invalid('seeking');
  END IF;
  IF p_min_age IS NULL OR p_max_age IS NULL OR p_min_age < 18 OR p_max_age > 99 OR p_min_age > p_max_age THEN
    RETURN private.dating_invalid('ages');
  END IF;
  IF NOT public.claim_dating_idempotency('save_dating_who_to_meet', p_idempotency_key) THEN
    RETURN jsonb_build_object('ok', true, 'next_step', 'children');
  END IF;

  UPDATE public.dating_profile_sensitive AS s
     SET seeking_enc = private.dating_field_encrypt(jsonb_build_object('seeking', to_jsonb(v_seeking))),
         updated_at = now()
   WHERE s.user_id = v_user;
  INSERT INTO public.dating_preferences AS d (user_id, min_age, max_age)
  VALUES (v_user, p_min_age, p_max_age)
  ON CONFLICT (user_id) DO UPDATE SET min_age = EXCLUDED.min_age, max_age = EXCLUDED.max_age, updated_at = now();
  PERFORM private.bump_metric_internal('dating.setup.step.d6');
  RETURN jsonb_build_object('ok', true, 'next_step', 'children');
END;
$fn$;

-- D7: children (no option to seek parents, §3.2, 10 S22).
CREATE OR REPLACE FUNCTION public.save_dating_children(p_idempotency_key text, p_have boolean, p_want text,
  p_must_match boolean, p_exclude_parents boolean)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_user constant uuid := auth.uid();
  v_reason text;
  v_ages integer[];
BEGIN
  v_reason := private.dating_setup_guard();
  IF v_reason IS NOT NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', v_reason);
  END IF;
  IF p_have IS NULL THEN
    RETURN private.dating_invalid('have');
  END IF;
  IF p_want IS NULL OR p_want NOT IN ('yes', 'no', 'open') THEN
    RETURN private.dating_invalid('want');
  END IF;
  IF NOT public.claim_dating_idempotency('save_dating_children', p_idempotency_key) THEN
    RETURN jsonb_build_object('ok', true, 'next_step', 'faith');
  END IF;

  PERFORM private.dating_ensure_profile(v_user);
  UPDATE public.dating_profiles AS p SET children_have = p_have, children_want = p_want, updated_at = now()
   WHERE p.user_id = v_user;
  v_ages := private.dating_default_ages(public.account_age(v_user));
  INSERT INTO public.dating_preferences AS d (user_id, min_age, max_age, want_must_match, exclude_parents)
  VALUES (v_user, v_ages[1], v_ages[2], coalesce(p_must_match, false), coalesce(p_exclude_parents, false))
  ON CONFLICT (user_id) DO UPDATE
    SET want_must_match = EXCLUDED.want_must_match, exclude_parents = EXCLUDED.exclude_parents, updated_at = now();
  PERFORM private.bump_metric_internal('dating.setup.step.d7');
  RETURN jsonb_build_object('ok', true, 'next_step', 'faith');
END;
$fn$;

-- D8: faith (optional): the country's list, how much sharing it matters.
CREATE OR REPLACE FUNCTION public.save_dating_faith(p_idempotency_key text, p_faith text, p_denomination text,
  p_importance text, p_visible boolean)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_user constant uuid := auth.uid();
  v_reason text;
  v_country text;
  v_faith jsonb;
BEGIN
  v_reason := private.dating_setup_guard();
  IF v_reason IS NOT NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', v_reason);
  END IF;
  IF NOT private.dating_consent_granted(v_user, 'special_category_profile')
     OR NOT private.dating_consent_granted(v_user, 'special_category_faith') THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'consent_required');
  END IF;
  SELECT p.country_code INTO v_country FROM public.dating_profiles AS p WHERE p.user_id = v_user;
  SELECT f INTO v_faith FROM jsonb_array_elements((public.dating_country_config(v_country)).faith_list) AS f
   WHERE f ->> 'code' = p_faith;
  IF v_faith IS NULL THEN
    RETURN private.dating_invalid('faith');
  END IF;
  IF p_denomination IS NOT NULL
     AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(coalesce(v_faith -> 'denominations', '[]'::jsonb)) AS d
                      WHERE d ->> 'code' = p_denomination) THEN
    RETURN private.dating_invalid('denomination');
  END IF;
  IF p_importance IS NULL OR p_importance NOT IN ('doesnt_matter', 'nice_to_share', 'must_share') THEN
    RETURN private.dating_invalid('importance');
  END IF;
  IF NOT private.dating_field_key_present() THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'unavailable');
  END IF;
  IF NOT public.claim_dating_idempotency('save_dating_faith', p_idempotency_key) THEN
    RETURN jsonb_build_object('ok', true, 'next_step', 'photos');
  END IF;

  PERFORM private.dating_ensure_profile(v_user);
  UPDATE public.dating_profile_sensitive AS s
     SET faith_enc = private.dating_field_encrypt(jsonb_build_object(
           'faith', p_faith, 'denomination', p_denomination, 'importance', p_importance)),
         updated_at = now()
   WHERE s.user_id = v_user;
  UPDATE public.dating_profiles AS p SET faith_visible = coalesce(p_visible, false), updated_at = now()
   WHERE p.user_id = v_user;
  PERFORM private.bump_metric_internal('dating.setup.step.d8');
  RETURN jsonb_build_object('ok', true, 'next_step', 'photos');
END;
$fn$;

-- D8 "Skip", or removing a faith answer later: nothing stays.
CREATE OR REPLACE FUNCTION public.clear_dating_faith(p_idempotency_key text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_user constant uuid := auth.uid();
  v_reason text;
BEGIN
  v_reason := private.dating_setup_guard();
  IF v_reason IS NOT NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', v_reason);
  END IF;
  IF NOT public.claim_dating_idempotency('clear_dating_faith', p_idempotency_key) THEN
    RETURN jsonb_build_object('ok', true, 'next_step', 'photos');
  END IF;
  UPDATE public.dating_profile_sensitive AS s SET faith_enc = NULL, updated_at = now() WHERE s.user_id = v_user;
  UPDATE public.dating_profiles AS p SET faith_visible = false, updated_at = now() WHERE p.user_id = v_user;
  RETURN jsonb_build_object('ok', true, 'next_step', 'photos');
END;
$fn$;

REVOKE ALL ON FUNCTION private.dating_setup_guard(), private.dating_ensure_profile(uuid),
  private.dating_same_gender_on(text), private.dating_default_ages(integer), private.dating_invalid(text)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION
  public.save_dating_intention(text, text, text, boolean, boolean, text, boolean),
  public.save_dating_location(text, text, text, text, text),
  public.save_dating_identity(text, text, text, text, text[], boolean),
  public.save_dating_who_to_meet(text, text[], integer, integer),
  public.save_dating_children(text, boolean, text, boolean, boolean),
  public.save_dating_faith(text, text, text, text, boolean),
  public.clear_dating_faith(text)
  FROM PUBLIC, anon;
-- The two writers that decrypt are no one else's (S-4: hosted projects
-- grant new functions to the service role by default).
REVOKE ALL ON FUNCTION public.save_dating_identity(text, text, text, text, text[], boolean),
  public.save_dating_who_to_meet(text, text[], integer, integer) FROM service_role;
GRANT EXECUTE ON FUNCTION
  public.save_dating_intention(text, text, text, boolean, boolean, text, boolean),
  public.save_dating_location(text, text, text, text, text),
  public.save_dating_identity(text, text, text, text, text[], boolean),
  public.save_dating_who_to_meet(text, text[], integer, integer),
  public.save_dating_children(text, boolean, text, boolean, boolean),
  public.save_dating_faith(text, text, text, text, boolean),
  public.clear_dating_faith(text)
  TO authenticated;

COMMIT;
```

Create `supabase/migrations/20261106160010_dating_v2_setup_writers_grants.sql` with exactly:

```sql
-- Spec 2 W1c: grants for 20261106160000_dating_v2_setup_writers.sql. The
-- D2-D8 writers are the signed-in app's (they take the actor from
-- auth.uid()); their helpers are the database's own.
BEGIN;
SET LOCAL lock_timeout = '5s';
REVOKE ALL ON FUNCTION private.dating_setup_guard(), private.dating_ensure_profile(uuid),
  private.dating_same_gender_on(text), private.dating_default_ages(integer), private.dating_invalid(text)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION
  public.save_dating_intention(text, text, text, boolean, boolean, text, boolean),
  public.save_dating_location(text, text, text, text, text),
  public.save_dating_identity(text, text, text, text, text[], boolean),
  public.save_dating_who_to_meet(text, text[], integer, integer),
  public.save_dating_children(text, boolean, text, boolean, boolean),
  public.save_dating_faith(text, text, text, text, boolean),
  public.clear_dating_faith(text)
  FROM PUBLIC, anon;
-- The two writers that decrypt are no one else's (S-4: hosted projects
-- grant new functions to the service role by default).
REVOKE ALL ON FUNCTION public.save_dating_identity(text, text, text, text, text[], boolean),
  public.save_dating_who_to_meet(text, text[], integer, integer) FROM service_role;
GRANT EXECUTE ON FUNCTION
  public.save_dating_intention(text, text, text, boolean, boolean, text, boolean),
  public.save_dating_location(text, text, text, text, text),
  public.save_dating_identity(text, text, text, text, text[], boolean),
  public.save_dating_who_to_meet(text, text[], integer, integer),
  public.save_dating_children(text, boolean, text, boolean, boolean),
  public.save_dating_faith(text, text, text, text, boolean),
  public.clear_dating_faith(text)
  TO authenticated;
COMMIT;
```

- [ ] **Step 3: Apply each file twice; run the contract**

```bash
for i in 1 2; do
  for f in 20261106160000_dating_v2_setup_writers 20261106160010_dating_v2_setup_writers_grants; do
    psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/migrations/$f.sql > /dev/null 2>&1; echo "$f exit=$?"
  done
done
```

```bash
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/dating_v2_setup_contracts.sql 2>&1 | grep -E 'ERROR|all held' | head -1 | sed -E 's/^psql:[^ ]* //'
```

Expected: four `exit=0` lines; `NOTICE:  dating_v2_setup_contracts: all held`.

- [ ] **Step 4: The canary's rows for this migration**

Create `.superpowers/sdd/2026-11-06-spec2-w1/canary_T9.sql` with exactly:

```sql
-- ---------------------------------------------------------------------
-- W1c (migration 7): the D2-D8 writers (the app's) and their helpers.
-- ---------------------------------------------------------------------
INSERT INTO allowed_fn (sig, clients) VALUES
  ('clear_dating_faith(text)', 'authenticated'),
  ('private.dating_default_ages(integer)', ''),
  ('private.dating_ensure_profile(uuid)', ''),
  ('private.dating_invalid(text)', ''),
  ('private.dating_same_gender_on(text)', ''),
  ('private.dating_setup_guard()', ''),
  ('save_dating_children(text,boolean,text,boolean,boolean)', 'authenticated'),
  ('save_dating_faith(text,text,text,text,boolean)', 'authenticated'),
  ('save_dating_identity(text,text,text,text,text[],boolean)', 'authenticated'),
  ('save_dating_intention(text,text,text,boolean,boolean,text,boolean)', 'authenticated'),
  ('save_dating_location(text,text,text,text,text)', 'authenticated'),
  ('save_dating_who_to_meet(text,text[],integer,integer)', 'authenticated');
```

```bash
D=.superpowers/sdd/2026-11-06-spec2-w1
python3 -I $D/section.py supabase/tests/dating_rls_canary.sql $D/canary_T9.sql --before '-- Checks (every batch adds its rows above this line).'
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/dating_rls_canary.sql 2>&1 | grep -E 'ERROR|all held' | head -1 | sed -E 's/^psql:[^ ]* //'
```

Expected: `dating_rls_canary.sql: canary_T9.sql before`, then `NOTICE:  dating_rls_canary: all held` (before this step, with the migration applied, the canary names every new object as `not in the canary's allow-list`).

- [ ] **Step 5: Mutation checks (mutant 4 is `identity_stores_before_country`, mutant 7 `identity_raises_not_available`)**

Create `.superpowers/sdd/2026-11-06-spec2-w1/mut_T9.py` with exactly:

```python
OFF = """  -- Off-country (§2.4): only Woman or Man, nothing more; anything else is
  -- not_available, raised by nothing, stored nowhere, counted nowhere.
  IF NOT private.dating_same_gender_on(v_country)
     AND (p_identity IS DISTINCT FROM 'woman' AND p_identity IS DISTINCT FROM 'man'
          OR p_specific IS NOT NULL OR p_pronouns IS NOT NULL OR cardinality(v_extra) > 0) THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'not_available');
  END IF;
"""
MUTS = {
 # Mutant 4: the identity is stored before the country is checked.
 'identity_stores_before_country': ('MULTI', [
    (OFF, ""),
    ("""  PERFORM private.bump_metric_internal('dating.setup.step.d5');""", OFF + """  PERFORM private.bump_metric_internal('dating.setup.step.d5');""")]),
 # Mutant 7: raise instead of returning not_available.
 'identity_raises_not_available': (OFF, OFF.replace("""    RETURN jsonb_build_object('ok', false, 'reason', 'not_available');""", """    RAISE EXCEPTION 'not_available';""")),
 'identity_off_country_unchecked': (OFF, ""),
 'off_country_allows_pronouns': ("""          OR p_specific IS NOT NULL OR p_pronouns IS NOT NULL OR cardinality(v_extra) > 0) THEN""", """          OR p_specific IS NOT NULL OR cardinality(v_extra) > 0) THEN"""),
 'who_off_country_unchecked': ("""  IF NOT private.dating_same_gender_on(v_country)
     AND v_seeking IS DISTINCT FROM""", """  IF false
     AND v_seeking IS DISTINCT FROM"""),
 'same_gender_ignores_flag': ("""  SELECT public.dating_flag_enabled('dating_same_gender_matching')
         AND coalesce""", """  SELECT coalesce"""),
 'identity_no_consent': ("""  IF NOT private.dating_consent_granted(v_user, 'special_category_profile') THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'consent_required');
  END IF;
  SELECT p.country_code INTO v_country FROM public.dating_profiles AS p WHERE p.user_id = v_user;
  IF v_country IS NULL THEN""", """  SELECT p.country_code INTO v_country FROM public.dating_profiles AS p WHERE p.user_id = v_user;
  IF v_country IS NULL THEN"""),
 'faith_no_faith_consent': ("""     OR NOT private.dating_consent_granted(v_user, 'special_category_faith') THEN""", """     THEN"""),
 'identity_no_key_check': ("""  IF NOT private.dating_field_key_present() THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'unavailable');
  END IF;
  IF NOT public.claim_dating_idempotency('save_dating_identity', p_idempotency_key) THEN""", """  IF NOT public.claim_dating_idempotency('save_dating_identity', p_idempotency_key) THEN"""),
 'guard_skips_eligibility': ("""  IF public.dating_eligibility(v_user, 'setup') <> 'eligible' THEN
    RETURN 'not_eligible';
  END IF;""", ""),
 'attestation_optional': ("""  IF p_attested IS NOT TRUE THEN
    RETURN private.dating_invalid('attestation');
  END IF;""", ""),
 'closed_country_accepted': ("""  IF NOT v_config.dating_enabled THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'country_closed');
  END IF;""", ""),
 'closed_region_accepted': ("""  IF v_config.open_regions IS NOT NULL AND NOT (p_region = ANY (v_config.open_regions)) THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'region_closed');
  END IF;""", ""),
 'country_change_unlimited': ("""     AND v_changed_at IS NOT NULL AND v_changed_at > now() - interval '30 days' THEN""", """     AND false THEN"""),
 'country_change_keeps_answers': ("""    UPDATE public.dating_profile_sensitive AS s
       SET identity_enc = NULL, seeking_enc = NULL, updated_at = now()
     WHERE s.user_id = v_user;""", ""),
 'young_default_wrong': ("""              WHEN p_age <= 20 THEN ARRAY[18, least(99, p_age + 7)]""", """              WHEN p_age <= 20 THEN ARRAY[18, least(99, p_age + 5)]"""),
 'partial_seeking_accepted': ("""  IF v_seeking NOT IN (ARRAY['man'], ARRAY['woman'], ARRAY['man', 'non_binary', 'woman']) THEN""", """  IF cardinality(v_seeking) = 0 THEN"""),
 'ages_unbounded': ("""  IF p_min_age IS NULL OR p_max_age IS NULL OR p_min_age < 18 OR p_max_age > 99 OR p_min_age > p_max_age THEN""", """  IF p_min_age IS NULL OR p_max_age IS NULL OR p_min_age > p_max_age THEN"""),
 'faith_not_in_list': ("""  IF v_faith IS NULL THEN
    RETURN private.dating_invalid('faith');
  END IF;""", """  IF p_faith IS NULL THEN
    RETURN private.dating_invalid('faith');
  END IF;"""),
 'clear_keeps_faith': ("""  UPDATE public.dating_profile_sensitive AS s SET faith_enc = NULL, updated_at = now() WHERE s.user_id = v_user;""", ""),
 'claim_before_validation': ('MULTI', [
    ("""  IF p_intention IS NULL OR p_intention NOT IN ('marriage', 'committed', 'companionship', 'not_sure') THEN
    RETURN private.dating_invalid('intention');""", """  PERFORM public.claim_dating_idempotency('save_dating_intention_early', p_idempotency_key);
  IF p_intention IS NULL OR p_intention NOT IN ('marriage', 'committed', 'companionship', 'not_sure') THEN
    RETURN private.dating_invalid('intention');""")]),
}
```

```bash
D=.superpowers/sdd/2026-11-06-spec2-w1
python3 -I $D/mutate.py supabase/migrations/20261106160000_dating_v2_setup_writers.sql supabase/tests/dating_v2_setup_contracts.sql $D/mut_T9.py $D
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/dating_v2_setup_contracts.sql 2>&1 | grep -E 'ERROR|all held' | head -1 | sed -E 's/^psql:[^ ]* //'
```

Expected (`ages_unbounded` is caught by the table's own CHECK, which backs the writer):

- `identity_stores_before_country`: `ERROR:  CONTRACT VIOLATED: an off-country same-gender answer changed a row or a counter (SELECT public.save_dating_identity(%L, 'non_binary', NULL, NULL, NULL, false))`
- `identity_raises_not_available`: `ERROR:  CONTRACT VIOLATED: an off-country same-gender answer raised (not_available): SELECT public.save_dating_identity(%L, 'non_binary', NULL, NULL, NULL, false)`
- `identity_off_country_unchecked`: `ERROR:  CONTRACT VIOLATED: an off-country same-gender answer was not refused with not_available (SELECT public.save_dating_identity(%L, 'non_binary', NULL, NULL, NULL, fa`
- `off_country_allows_pronouns`: `ERROR:  CONTRACT VIOLATED: an off-country same-gender answer was not refused with not_available (SELECT public.save_dating_identity(%L, 'man', NULL, 'they/them', NULL, fa`
- `who_off_country_unchecked`: `ERROR:  CONTRACT VIOLATED: an off-country same-gender answer was not refused with not_available (SELECT public.save_dating_who_to_meet(%L, ARRAY['man'], 25, 35)): {"ok":`
- `same_gender_ignores_flag`: `ERROR:  CONTRACT VIOLATED: with dating_same_gender_matching off, the UK took a non-binary identity: {"ok": true, "next_step": "meet"}`
- `identity_no_consent`: `ERROR:  CONTRACT VIOLATED: a special-category answer was saved without the special_category_profile consent`
- `faith_no_faith_consent`: `ERROR:  CONTRACT VIOLATED: faith was saved without the special_category_faith consent`
- `identity_no_key_check`: `ERROR:  CONTRACT VIOLATED: without dating_field_key a writer raised (dating:field_key_missing) instead of answering unavailable`
- `guard_skips_eligibility`: `ERROR:  CONTRACT VIOLATED: an under-18 account could start Dating setup`
- `attestation_optional`: `ERROR:  CONTRACT VIOLATED: D2 validation is wrong (intention enum, timeline only with marriage, attestation required, marital values)`
- `closed_country_accepted`: `ERROR:  CONTRACT VIOLATED: D3 accepted a closed country or region, a foreign side, or side scope without a side`
- `closed_region_accepted`: `ERROR:  CONTRACT VIOLATED: D3 accepted a closed country or region, a foreign side, or side scope without a side`
- `country_change_unlimited`: `ERROR:  CONTRACT VIOLATED: a second country change within 30 days was allowed`
- `country_change_keeps_answers`: `ERROR:  CONTRACT VIOLATED: a country change kept the gender and who-to-meet answers: {"ok": true, "next_step": "privacy"}`
- `young_default_wrong`: `ERROR:  CONTRACT VIOLATED: the default age ranges are wrong`
- `partial_seeking_accepted`: `ERROR:  CONTRACT VIOLATED: D6 accepted a partial set or an age outside 18-99`
- `ages_unbounded`: `ERROR:  new row for relation "dating_preferences" violates check constraint "dating_preferences_min_age_check"`
- `faith_not_in_list`: `ERROR:  CONTRACT VIOLATED: D8 accepted a faith outside the country's list, a foreign denomination or an unknown importance`
- `clear_keeps_faith`: `ERROR:  CONTRACT VIOLATED: Skip left a faith answer stored`
- `claim_before_validation`: `ERROR:  CONTRACT VIOLATED: a refused D2 wrote a row or claimed its idempotency key`

then `NOTICE:  dating_v2_setup_contracts: all held`.

- [ ] **Step 6: The local harness (edit only, never run)**

`scripts/local_pg_grants.sql`: append after the last line (`\i supabase/migrations/20261106150010_dating_v2_profile_fields_grants.sql`), exactly:

```sql

-- Spec 2 W1c: the D2-D8 writers are the signed-in app's; their helpers are
-- the database's own.
\i supabase/migrations/20261106160010_dating_v2_setup_writers_grants.sql
```

```bash
python3 -I - <<'PY'
import pathlib
p = pathlib.Path('scripts/local_pg_grants.sql')
s = p.read_text()
assert s.endswith('\\i supabase/migrations/20261106150010_dating_v2_profile_fields_grants.sql' + chr(10))
p.write_text(s + chr(10) + "-- Spec 2 W1c: the D2-D8 writers are the signed-in app's; their helpers are\n-- the database's own." + chr(10) + '\\i supabase/migrations/20261106160010_dating_v2_setup_writers_grants.sql' + chr(10))
print('local_pg_grants.sql: one \\i block added')
PY
```

### Task 10: Migration 8: D10, D12, settings, other countries, photos after mutual, the two readers; the W1c gate (§4.4, §3.2 D9-D13, §3.4 card, §3.12; P-29, P-30)

**Files:**
- Create: `supabase/migrations/20261106170000_dating_v2_profile_readers.sql`, `…170010_dating_v2_profile_readers_grants.sql`
- Modify: `supabase/tests/dating_v2_setup_contracts.sql` (F, G, H), `supabase/tests/dating_v2_identity_contracts.sql` (D2), `supabase/tests/dating_rls_canary.sql`, `scripts/local_pg_grants.sql`

**Interfaces:**
- Consumes: Task 9's helpers, `private.content_filter_verdict(text, text[])`, `dating_age_gate_holds`, `users.created_at`.
- Produces: `save_dating_prompts(text, jsonb)`, `save_dating_display_name(text, text)`, `save_dating_family_involvement(text, text)`, `save_dating_settings(text, jsonb)`, `set_dating_open_abroad(text, char(2)[])`, `set_dating_photos_after_mutual(text, boolean)` (all `→ jsonb`); `get_my_dating_profile() → jsonb` (`{ok, profile: {…, identity, seeking, faith, marital, preferences, settings, prompts}}`), `get_dating_profile_preview() → jsonb` (`{ok, card: {display_name, age, region_code, region_name_key, intention, marriage_timeline, children_have, children_want, gender, pronouns, faith, marital, prompts, photos}}`; both readers revoked from the service role).

- [ ] **Step 1: Write the failing sections**

Create `.superpowers/sdd/2026-11-06-spec2-w1/setup_F.sql` with exactly:

```sql
-- =====================================================================
-- F. D10 prompts (both filters) and D12 the name.
-- =====================================================================
DO $$
DECLARE
  v_u constant uuid := pg_temp.located('08', 'GH', 'AA');
  v jsonb;
BEGIN
  IF pg_temp.call(v_u, format('SELECT public.save_dating_prompts(%L, %L)', pg_temp.key('x'),
         '[{"prompt_id": "perfect_sunday", "answer": "Church, then jollof with my sisters."}]'))
       IS DISTINCT FROM '{"ok": false, "reason": "invalid", "field": "prompts"}'::jsonb
     OR pg_temp.call(v_u, format('SELECT public.save_dating_prompts(%L, %L)', pg_temp.key('x'),
         '[{"prompt_id": "perfect_sunday", "answer": "Church, then jollof."}, {"prompt_id": "perfect_sunday", "answer": "Again the same one."}]'))
       IS DISTINCT FROM '{"ok": false, "reason": "invalid", "field": "prompts"}'::jsonb
     OR pg_temp.call(v_u, format('SELECT public.save_dating_prompts(%L, %L)', pg_temp.key('x'),
         '[{"prompt_id": "perfect_sunday", "answer": "Church."}, {"prompt_id": "ask_me_about", "answer": "My grandmother''s garden."}]'))
       IS DISTINCT FROM '{"ok": false, "reason": "invalid", "field": "answer", "position": 1}'::jsonb
     OR pg_temp.call(v_u, format('SELECT public.save_dating_prompts(%L, %L)', pg_temp.key('x'),
         '[{"prompt_id": "perfect_sunday", "answer": "Church, then jollof."}, {"prompt_id": "ask_me_about", "answer": "Call me on 024 412 3456 any time"}]'))
       IS DISTINCT FROM '{"ok": false, "reason": "contact_details", "position": 2}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: D10 accepted one prompt, a repeated prompt, a short answer or contact details';
  END IF;
  v := pg_temp.call(v_u, format('SELECT public.save_dating_prompts(%L, %L)', pg_temp.key('d10'),
         '[{"prompt_id": "perfect_sunday", "answer": "Church, then jollof."}, {"prompt_id": "ask_me_about", "answer": "  My grandmother''s garden.  "}]'));
  IF v IS DISTINCT FROM '{"ok": true, "next_step": "verify"}'::jsonb
     OR (SELECT string_agg(prompt_id || '=' || answer, ';' ORDER BY position) FROM public.dating_prompts WHERE user_id = v_u)
          IS DISTINCT FROM 'perfect_sunday=Church, then jollof.;ask_me_about=My grandmother''s garden.' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: D10 did not save the answers: %', v;
  END IF;
  IF pg_temp.call(v_u, format('SELECT public.save_dating_display_name(%L, %L)', pg_temp.key('x'), '   '))
       IS DISTINCT FROM '{"ok": false, "reason": "invalid", "field": "name"}'::jsonb
     OR pg_temp.call(v_u, format('SELECT public.save_dating_display_name(%L, %L)', pg_temp.key('x'), repeat('a', 31)))
       IS DISTINCT FROM '{"ok": false, "reason": "invalid", "field": "name"}'::jsonb
     OR pg_temp.call(v_u, format('SELECT public.save_dating_display_name(%L, %L)', pg_temp.key('x'), 'Ama 0244123456'))
       IS DISTINCT FROM '{"ok": false, "reason": "contact_details"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: D12 name rules are wrong (1-30 characters, no contact details)';
  END IF;
  -- Names in any script count characters, not bytes: Arabic and an emoji
  -- name fit; 31 characters don't.
  v := pg_temp.call(v_u, format('SELECT public.save_dating_display_name(%L, %L)', pg_temp.key('ar'), U&'\0623\0645\064A\0646\0629'));
  IF v IS DISTINCT FROM '{"ok": true, "next_step": "preview"}'::jsonb
     OR (SELECT display_name FROM public.dating_profiles WHERE user_id = v_u) IS DISTINCT FROM U&'\0623\0645\064A\0646\0629' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an Arabic first name was refused: %', v;
  END IF;
  IF pg_temp.call(v_u, format('SELECT public.save_dating_display_name(%L, %L)', pg_temp.key('em'), 'Kofi ' || U&'\+01F33B'))
       IS DISTINCT FROM '{"ok": true, "next_step": "preview"}'::jsonb
     OR pg_temp.call(v_u, format('SELECT public.save_dating_display_name(%L, %L)', pg_temp.key('x'), repeat(U&'\0623', 31)))
       IS DISTINCT FROM '{"ok": false, "reason": "invalid", "field": "name"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a name was measured in bytes, not characters';
  END IF;
  -- (One statement sees one snapshot: the write and its read are separate.)
  v := pg_temp.call(v_u, format('SELECT public.save_dating_display_name(%L, %L)', pg_temp.key('d12'), ' Ama '));
  IF v IS DISTINCT FROM '{"ok": true, "next_step": "preview"}'::jsonb
     OR (SELECT display_name FROM public.dating_profiles WHERE user_id = v_u) IS DISTINCT FROM 'Ama' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: D12 did not save the trimmed name: %', v;
  END IF;
END $$;
```

Create `.superpowers/sdd/2026-11-06-spec2-w1/setup_G.sql` with exactly:

```sql
-- =====================================================================
-- G. Settings; other countries (verified and 14+ days only); photos
--    after mutual interest (from day 30); the family question.
-- =====================================================================
DO $$
DECLARE
  v_u constant uuid := pg_temp.located('09', 'GH', 'AA');
  v_new constant uuid := pg_temp.person('10', 30, 5);
  v jsonb;
BEGIN
  IF pg_temp.call(v_u, format('SELECT public.save_dating_settings(%L, %L)', pg_temp.key('x'), '{"drop_time": "06:30"}'))
       IS DISTINCT FROM '{"ok": false, "reason": "invalid", "field": "drop_time"}'::jsonb
     OR pg_temp.call(v_u, format('SELECT public.save_dating_settings(%L, %L)', pg_temp.key('x'), '{"drop_time": "19:15"}'))
       IS DISTINCT FROM '{"ok": false, "reason": "invalid", "field": "drop_time"}'::jsonb
     OR pg_temp.call(v_u, format('SELECT public.save_dating_settings(%L, %L)', pg_temp.key('x'), '{"theme": "dark"}'))
       IS DISTINCT FROM '{"ok": false, "reason": "invalid", "field": "settings"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: settings accepted a time outside 07:00-22:00 in 30-minute steps, or an unknown key';
  END IF;
  v := pg_temp.call(v_u, format('SELECT public.save_dating_settings(%L, %L)', pg_temp.key('s'), '{"drop_time": "21:30", "digest_push": true}'));
  IF v IS DISTINCT FROM '{"ok": true}'::jsonb
     OR (SELECT drop_time::text || digest_push::text || chat_push::text FROM public.dating_settings WHERE user_id = v_u) IS DISTINCT FROM '21:30:00truetrue' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: settings were not saved: %', v;
  END IF;
  IF pg_temp.call(v_u, format('SELECT public.set_dating_open_abroad(%L, ARRAY[''GB'']::char(2)[])', pg_temp.key('x')))
       IS DISTINCT FROM '{"ok": false, "reason": "not_yet"}'::jsonb
     OR pg_temp.call(v_u, format('SELECT public.set_dating_open_abroad(%L, ARRAY[''GH'']::char(2)[])', pg_temp.key('x')))
       IS DISTINCT FROM '{"ok": false, "reason": "invalid", "field": "countries"}'::jsonb
     OR pg_temp.call(v_u, format('SELECT public.set_dating_open_abroad(%L, ARRAY[''NG'']::char(2)[])', pg_temp.key('x')))
       IS DISTINCT FROM '{"ok": false, "reason": "invalid", "field": "countries"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: other countries were allowed before verification, or for one''s own or a closed country';
  END IF;
  UPDATE public.dating_profiles SET verification_state = 'verified' WHERE user_id = v_u;
  INSERT INTO public.dating_age_verifications (user_id, birth_date, verification_method, verified_at)
  VALUES (v_u, current_date - interval '30 years', 'contract', now());
  v := pg_temp.call(v_u, format('SELECT public.set_dating_open_abroad(%L, ARRAY[''gb'']::char(2)[])', pg_temp.key('ab')));
  IF v IS DISTINCT FROM '{"ok": true}'::jsonb
     OR (SELECT open_abroad FROM public.dating_preferences WHERE user_id = v_u) IS DISTINCT FROM ARRAY['GB']::char(2)[] THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a verified 40-day account could not open to the UK';
  END IF;
  IF pg_temp.call(v_new, format('SELECT public.set_dating_photos_after_mutual(%L, true)', pg_temp.key('x')))
       IS DISTINCT FROM '{"ok": false, "reason": "not_yet"}'::jsonb
     OR pg_temp.call(v_u, format('SELECT public.set_dating_photos_after_mutual(%L, true)', pg_temp.key('pm')))
       IS DISTINCT FROM '{"ok": true}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: photos after mutual interest is wrong before or after account day 30';
  END IF;
  IF pg_temp.call(v_u, format('SELECT public.save_dating_family_involvement(%L, ''soon'')', pg_temp.key('x')))
       IS DISTINCT FROM '{"ok": false, "reason": "invalid", "field": "family_involvement"}'::jsonb
     OR pg_temp.call(v_u, format('SELECT public.save_dating_family_involvement(%L, ''early'')', pg_temp.key('f')))
       IS DISTINCT FROM '{"ok": true}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the family question is wrong';
  END IF;
END $$;
```

Create `.superpowers/sdd/2026-11-06-spec2-w1/setup_H.sql` with exactly:

```sql
-- =====================================================================
-- H. The readers: own profile decrypted; the preview is the card others
--    see, never who you'd like to meet, the side, the DOB or hidden fields.
-- =====================================================================
DO $$
DECLARE
  v_u constant uuid := pg_temp.located('11', 'GH', 'AA');
  v jsonb;
BEGIN
  PERFORM pg_temp.call(v_u, format('SELECT public.save_dating_location(%L, ''GH'', ''AA'', ''accra'', ''region'')', pg_temp.key('d3')));
  PERFORM pg_temp.call(v_u, format('SELECT public.save_dating_identity(%L, ''woman'', NULL, NULL, NULL, false)', pg_temp.key('d5')));
  PERFORM pg_temp.call(v_u, format('SELECT public.save_dating_who_to_meet(%L, ARRAY[''man''], 28, 40)', pg_temp.key('d6')));
  PERFORM pg_temp.call(v_u, format('SELECT public.save_dating_faith(%L, ''christian'', NULL, ''nice_to_share'', false)', pg_temp.key('d8')));
  v := pg_temp.call(v_u, 'SELECT public.get_my_dating_profile()');
  IF v #>> '{profile,identity,identity}' IS DISTINCT FROM 'woman' OR v #> '{profile,seeking}' IS DISTINCT FROM '["man"]'::jsonb
     OR v #>> '{profile,faith,importance}' IS DISTINCT FROM 'nice_to_share' OR v #>> '{profile,side_code}' IS DISTINCT FROM 'accra'
     OR v #> '{profile,preferences,min_age}' IS DISTINCT FROM '28'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: get_my_dating_profile did not return the person''s own answers: %', v;
  END IF;
  v := pg_temp.call(v_u, 'SELECT public.get_dating_profile_preview()');
  IF v #>> '{card,display_name}' IS DISTINCT FROM 'Ama Person 11' OR (v #>> '{card,age}')::int IS DISTINCT FROM 30
     OR v #>> '{card,region_name_key}' IS DISTINCT FROM 'dating_region_gh_aa'
     OR v::text ~* '(seeking|accra|side|birth|"man"|nice_to_share|christian)'
     OR v #> '{card,gender}' IS DISTINCT FROM 'null'::jsonb OR v #> '{card,faith}' IS DISTINCT FROM 'null'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the preview shows something others must never see: %', v;
  END IF;
  UPDATE public.dating_profiles SET gender_visible = true, faith_visible = true WHERE user_id = v_u;
  v := pg_temp.call(v_u, 'SELECT public.get_dating_profile_preview()');
  IF v #>> '{card,gender,identity}' IS DISTINCT FROM 'woman' OR v #>> '{card,faith,faith}' IS DISTINCT FROM 'christian'
     OR v::text ~* '(seeking|importance|nice_to_share)' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the preview does not show exactly what the person chose to show: %', v;
  END IF;
END $$;
```

Create `.superpowers/sdd/2026-11-06-spec2-w1/identity_D2.sql` with exactly:

```sql
-- =====================================================================
-- D2. (W1c) Through the writers and readers: what lands in
--    dating_profile_sensitive is ciphertext only (no plaintext marker, a
--    fresh ciphertext each write), and every special-category writer and
--    the own-profile reader fail closed (unavailable) without the key.
-- =====================================================================
DO $$
DECLARE
  v_u constant uuid := pg_temp.person('40');
  v jsonb;
  v_first bytea;
BEGIN
  PERFORM set_config('app.settings.dating_field_key', 'spec2-w1c-identity-field-key-0123456789abcdef', true);
  UPDATE public.feature_flags SET enabled = true WHERE key = 'dating_mode_enabled';
  PERFORM pg_temp.as_service('SELECT public.publish_country_config(''GH'', ''{"dating_enabled": true}'')::text');
  INSERT INTO public.dating_consent_events (user_id, idempotency_key, purpose, action, policy_version, occurred_at)
  VALUES (v_u, 'w1c-consent-profile', 'special_category_profile', 'granted', 'dating-2.0', clock_timestamp());
  PERFORM pg_temp.as_user(v_u);
  v := jsonb_build_array(public.save_dating_intention('w1c-identity-d2-0001', 'committed', NULL, true, true, 'widowed', false));
  v := v || jsonb_build_array(public.save_dating_location('w1c-identity-d3-0001', 'GH', 'AA', NULL, 'region'));
  v := v || jsonb_build_array(public.save_dating_identity('w1c-identity-d5-0001', 'woman', NULL, NULL, NULL, false));
  PERFORM pg_temp.as_owner();
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(v) AS e WHERE e ->> 'ok' IS DISTINCT FROM 'true') THEN
    RAISE EXCEPTION 'fixture: the W1c writers failed: %', v;
  END IF;
  v_first := (SELECT identity_enc FROM public.dating_profile_sensitive WHERE user_id = v_u);
  IF v_first IS NULL
     OR position('woman' IN encode(v_first, 'escape')) IS DISTINCT FROM 0
     OR position('widowed' IN encode((SELECT marital_enc FROM public.dating_profile_sensitive WHERE user_id = v_u), 'escape')) IS DISTINCT FROM 0
     OR position('identity' IN encode(v_first, 'escape')) IS DISTINCT FROM 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: dating_profile_sensitive holds a plaintext marker';
  END IF;
  PERFORM pg_temp.as_user(v_u);
  PERFORM public.save_dating_identity('w1c-identity-d5-0002', 'woman', NULL, NULL, NULL, false);
  PERFORM pg_temp.as_owner();
  IF (SELECT identity_enc FROM public.dating_profile_sensitive WHERE user_id = v_u) = v_first THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the same answer encrypted to the same ciphertext twice';
  END IF;

  -- Without the key: every special-category writer and both readers say
  -- unavailable, and nothing changes.
  PERFORM set_config('app.settings.dating_field_key', '', true);
  PERFORM pg_temp.as_user(v_u);
  BEGIN
    v := jsonb_build_array(
      public.save_dating_intention('w1c-identity-d2-0009', 'committed', NULL, true, true, NULL, false),
      public.save_dating_identity('w1c-identity-d5-0009', 'woman', NULL, NULL, NULL, false),
      public.save_dating_who_to_meet('w1c-identity-d6-0009', ARRAY['man'], 25, 35),
      public.get_my_dating_profile());
  EXCEPTION WHEN raise_exception THEN
    PERFORM pg_temp.as_owner();
    RAISE EXCEPTION 'CONTRACT VIOLATED: without dating_field_key a writer or reader raised (%) instead of answering unavailable', SQLERRM;
  END;
  PERFORM pg_temp.as_owner();
  IF v IS DISTINCT FROM '[{"ok": false, "reason": "unavailable"}, {"ok": false, "reason": "unavailable"},
                          {"ok": false, "reason": "unavailable"}, {"ok": false, "reason": "unavailable"}]'::jsonb
     OR (SELECT seeking_enc IS NOT NULL FROM public.dating_profile_sensitive WHERE user_id = v_u) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: without dating_field_key a writer or reader did not fail closed: %', v;
  END IF;
  PERFORM set_config('app.settings.dating_field_key', 'spec2-w1c-identity-field-key-0123456789abcdef', true);
END $$;
```

```bash
D=.superpowers/sdd/2026-11-06-spec2-w1
for x in F G H; do
  python3 -I $D/section.py supabase/tests/dating_v2_setup_contracts.sql $D/setup_$x.sql --before '-- I. The guards: signed in; eligible to set up (opaque not_eligible).'
done
python3 -I $D/section.py supabase/tests/dating_v2_identity_contracts.sql $D/identity_D2.sql --end
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/dating_v2_setup_contracts.sql 2>&1 | grep -E 'ERROR|all held' | head -1 | sed -E 's/^psql:[^ ]* //'
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/dating_v2_identity_contracts.sql 2>&1 | grep -E 'ERROR|all held' | head -1 | sed -E 's/^psql:[^ ]* //'
```

Expected: the four `section.py` lines; `ERROR:  function public.save_dating_prompts(unknown, unknown) does not exist`; `ERROR:  function public.get_my_dating_profile() does not exist`.

- [ ] **Step 2: Write migration 8 and its twin**

Create `supabase/migrations/20261106170000_dating_v2_profile_readers.sql` with exactly:

```sql
-- Spec 2 W1c, migration 8 (spec §4.9 W1c #1, part 3 of 3: the remaining
-- setup writers and the two own-profile readers; §3.2, §3.4, §3.12, §4.4):
--   save_dating_prompts (D10: 2-3 answers, 10-200 characters, Spec 1's
--   pre-post filter private.content_filter_verdict: contact details ->
--   contact_details, slurs or explicit -> unkind), save_dating_display_name
--   (D12: 1-30 characters, no contact details), save_dating_family_involvement,
--   save_dating_settings (drop time, data saver, digest and chat pushes,
--   show when away), set_dating_open_abroad (verified and 14+ days old,
--   open countries other than one's own), set_dating_photos_after_mutual
--   (from account day 30); get_my_dating_profile() (own, decrypted) and
--   get_dating_profile_preview() (exactly what others see: never who you'd
--   like to meet, the side, the DOB or hidden fields).
-- Same order of checks as migration 7 (signed in, device, eligibility,
-- validation, key, then the idempotency claim). Counters: d10, d12.
-- Grants in 20261106170010_dating_v2_profile_readers_grants.sql.
BEGIN;
SET LOCAL lock_timeout = '5s';

-- D10: two required answers, a third optional.
CREATE OR REPLACE FUNCTION public.save_dating_prompts(p_idempotency_key text, p_items jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_user constant uuid := auth.uid();
  v_reason text;
  v_item record;
  v_verdict text;
BEGIN
  v_reason := private.dating_setup_guard();
  IF v_reason IS NOT NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', v_reason);
  END IF;
  IF jsonb_typeof(p_items) IS DISTINCT FROM 'array' OR jsonb_array_length(p_items) NOT BETWEEN 2 AND 3
     OR (SELECT count(DISTINCT i ->> 'prompt_id') FROM jsonb_array_elements(p_items) AS i) <> jsonb_array_length(p_items)
     OR EXISTS (SELECT 1 FROM jsonb_array_elements(p_items) AS i
                 WHERE jsonb_typeof(i) <> 'object' OR coalesce(i ->> 'prompt_id', '') NOT IN ('perfect_sunday',
                   'feel_at_home', 'friends_say', 'looking_for', 'small_thing', 'win_me_over', 'learning_to',
                   'family_describe', 'place_love', 'ask_me_about')) THEN
    RETURN private.dating_invalid('prompts');
  END IF;
  FOR v_item IN SELECT o AS position, i ->> 'prompt_id' AS prompt_id, btrim(coalesce(i ->> 'answer', '')) AS answer
                  FROM jsonb_array_elements(p_items) WITH ORDINALITY AS x(i, o) LOOP
    IF char_length(v_item.answer) NOT BETWEEN 10 AND 200 THEN
      RETURN private.dating_invalid('answer') || jsonb_build_object('position', v_item.position);
    END IF;
    v_verdict := private.content_filter_verdict(v_item.answer, NULL);
    IF v_verdict IS NOT NULL THEN
      RETURN jsonb_build_object('ok', false,
        'reason', CASE WHEN v_verdict = 'contact_info' THEN 'contact_details' ELSE 'unkind' END,
        'position', v_item.position);
    END IF;
  END LOOP;
  IF NOT public.claim_dating_idempotency('save_dating_prompts', p_idempotency_key) THEN
    RETURN jsonb_build_object('ok', true, 'next_step', 'verify');
  END IF;

  PERFORM private.dating_ensure_profile(v_user);
  DELETE FROM public.dating_prompts AS d WHERE d.user_id = v_user;
  INSERT INTO public.dating_prompts (user_id, position, prompt_id, answer)
  SELECT v_user, o, i ->> 'prompt_id', btrim(i ->> 'answer')
    FROM jsonb_array_elements(p_items) WITH ORDINALITY AS x(i, o);
  PERFORM private.bump_metric_internal('dating.setup.step.d10');
  RETURN jsonb_build_object('ok', true, 'next_step', 'verify');
END;
$fn$;

-- D12: the first name others see.
CREATE OR REPLACE FUNCTION public.save_dating_display_name(p_idempotency_key text, p_name text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_user constant uuid := auth.uid();
  v_reason text;
  v_name constant text := btrim(coalesce(p_name, ''));
BEGIN
  v_reason := private.dating_setup_guard();
  IF v_reason IS NOT NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', v_reason);
  END IF;
  IF char_length(v_name) NOT BETWEEN 1 AND 30 THEN
    RETURN private.dating_invalid('name');
  END IF;
  IF private.content_filter_verdict(v_name, ARRAY['contact_info']) IS NOT NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'contact_details');
  END IF;
  IF NOT public.claim_dating_idempotency('save_dating_display_name', p_idempotency_key) THEN
    RETURN jsonb_build_object('ok', true, 'next_step', 'preview');
  END IF;
  PERFORM private.dating_ensure_profile(v_user);
  UPDATE public.dating_profiles AS p SET display_name = v_name, updated_at = now() WHERE p.user_id = v_user;
  PERFORM private.bump_metric_internal('dating.setup.step.d12');
  RETURN jsonb_build_object('ok', true, 'next_step', 'preview');
END;
$fn$;

-- The family question (§3.4; shared ground only, never shown as a field).
CREATE OR REPLACE FUNCTION public.save_dating_family_involvement(p_idempotency_key text, p_value text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_user constant uuid := auth.uid();
  v_reason text;
BEGIN
  v_reason := private.dating_setup_guard();
  IF v_reason IS NOT NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', v_reason);
  END IF;
  IF p_value IS NOT NULL AND p_value NOT IN ('early', 'when_serious', 'our_decision') THEN
    RETURN private.dating_invalid('family_involvement');
  END IF;
  IF NOT public.claim_dating_idempotency('save_dating_family_involvement', p_idempotency_key) THEN
    RETURN jsonb_build_object('ok', true);
  END IF;
  PERFORM private.dating_ensure_profile(v_user);
  UPDATE public.dating_profiles AS p SET family_involvement = p_value, updated_at = now() WHERE p.user_id = v_user;
  RETURN jsonb_build_object('ok', true);
END;
$fn$;

-- Dating settings (§3.12, D12, D13): any subset of the five keys.
CREATE OR REPLACE FUNCTION public.save_dating_settings(p_idempotency_key text, p_values jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_user constant uuid := auth.uid();
  v_reason text;
  v_drop time;
BEGIN
  v_reason := private.dating_setup_guard();
  IF v_reason IS NOT NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', v_reason);
  END IF;
  IF jsonb_typeof(p_values) IS DISTINCT FROM 'object'
     OR EXISTS (SELECT 1 FROM jsonb_object_keys(p_values) AS k
                 WHERE k NOT IN ('drop_time', 'data_saver', 'digest_push', 'chat_push', 'show_when_away'))
     OR EXISTS (SELECT 1 FROM jsonb_each(p_values) AS e
                 WHERE e.key <> 'drop_time' AND jsonb_typeof(e.value) <> 'boolean') THEN
    RETURN private.dating_invalid('settings');
  END IF;
  IF p_values ? 'drop_time' THEN
    IF coalesce(p_values ->> 'drop_time', '') !~ '^([01][0-9]|2[0-3]):(00|30)$' THEN
      RETURN private.dating_invalid('drop_time');
    END IF;
    v_drop := (p_values ->> 'drop_time')::time;
    IF v_drop NOT BETWEEN '07:00' AND '22:00' THEN
      RETURN private.dating_invalid('drop_time');
    END IF;
  END IF;
  IF NOT public.claim_dating_idempotency('save_dating_settings', p_idempotency_key) THEN
    RETURN jsonb_build_object('ok', true);
  END IF;
  INSERT INTO public.dating_settings AS s (user_id) VALUES (v_user) ON CONFLICT (user_id) DO NOTHING;
  UPDATE public.dating_settings AS s
     SET drop_time = coalesce(v_drop, s.drop_time),
         data_saver = coalesce((p_values ->> 'data_saver')::boolean, s.data_saver),
         digest_push = coalesce((p_values ->> 'digest_push')::boolean, s.digest_push),
         chat_push = coalesce((p_values ->> 'chat_push')::boolean, s.chat_push),
         show_when_away = coalesce((p_values ->> 'show_when_away')::boolean, s.show_when_away),
         updated_at = now()
   WHERE s.user_id = v_user;
  RETURN jsonb_build_object('ok', true);
END;
$fn$;

-- "Other countries" (§2.6, §3.12): only for verified accounts at least 14
-- days old, only open countries other than one's own.
CREATE OR REPLACE FUNCTION public.set_dating_open_abroad(p_idempotency_key text, p_countries char(2)[])
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_user constant uuid := auth.uid();
  v_reason text;
  v_own text;
  v_list char(2)[];
BEGIN
  v_reason := private.dating_setup_guard();
  IF v_reason IS NOT NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', v_reason);
  END IF;
  v_list := ARRAY(SELECT DISTINCT upper(c)::char(2) FROM unnest(coalesce(p_countries, ARRAY[]::char(2)[])) AS c ORDER BY 1);
  SELECT p.country_code INTO v_own FROM public.dating_profiles AS p WHERE p.user_id = v_user;
  IF v_own IS NULL OR cardinality(v_list) > 10
     OR EXISTS (SELECT 1 FROM unnest(v_list) AS c
                 WHERE c::text = v_own OR NOT coalesce((public.dating_country_config(c)).dating_enabled, false)) THEN
    RETURN private.dating_invalid('countries');
  END IF;
  IF cardinality(v_list) > 0
     AND (NOT EXISTS (SELECT 1 FROM public.dating_profiles AS p WHERE p.user_id = v_user AND p.verification_state = 'verified')
          OR NOT public.dating_age_gate_holds(v_user)
          OR (SELECT u.created_at FROM public.users AS u WHERE u.id = v_user) > now() - interval '14 days') THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'not_yet');
  END IF;
  IF NOT public.claim_dating_idempotency('set_dating_open_abroad', p_idempotency_key) THEN
    RETURN jsonb_build_object('ok', true);
  END IF;
  UPDATE public.dating_preferences AS d SET open_abroad = v_list, updated_at = now() WHERE d.user_id = v_user;
  IF NOT FOUND THEN
    RETURN private.dating_invalid('countries');
  END IF;
  RETURN jsonb_build_object('ok', true);
END;
$fn$;

-- "Show my photos only after we're both interested" (D9): from account day 30.
CREATE OR REPLACE FUNCTION public.set_dating_photos_after_mutual(p_idempotency_key text, p_on boolean)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_user constant uuid := auth.uid();
  v_reason text;
BEGIN
  v_reason := private.dating_setup_guard();
  IF v_reason IS NOT NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', v_reason);
  END IF;
  IF p_on IS NULL THEN
    RETURN private.dating_invalid('on');
  END IF;
  IF p_on AND (SELECT u.created_at FROM public.users AS u WHERE u.id = v_user) > now() - interval '30 days' THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'not_yet');
  END IF;
  IF NOT public.claim_dating_idempotency('set_dating_photos_after_mutual', p_idempotency_key) THEN
    RETURN jsonb_build_object('ok', true);
  END IF;
  PERFORM private.dating_ensure_profile(v_user);
  UPDATE public.dating_profiles AS p SET photos_after_mutual = p_on, updated_at = now() WHERE p.user_id = v_user;
  RETURN jsonb_build_object('ok', true);
END;
$fn$;

-- The person's own Dating profile, decrypted (setup resume, settings).
CREATE OR REPLACE FUNCTION public.get_my_dating_profile()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_user constant uuid := auth.uid();
  v_p public.dating_profiles;
  v_s public.dating_profile_sensitive;
  v_d public.dating_preferences;
  v_t public.dating_settings;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;
  IF NOT public.dating_require_trusted_device() THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'reverify_device');
  END IF;
  SELECT * INTO v_p FROM public.dating_profiles AS p WHERE p.user_id = v_user;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', true, 'profile', NULL);
  END IF;
  SELECT * INTO v_s FROM public.dating_profile_sensitive AS s WHERE s.user_id = v_user;
  IF num_nonnulls(v_s.identity_enc, v_s.seeking_enc, v_s.faith_enc, v_s.marital_enc) > 0
     AND NOT private.dating_field_key_present() THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'unavailable');
  END IF;
  SELECT * INTO v_d FROM public.dating_preferences AS d WHERE d.user_id = v_user;
  SELECT * INTO v_t FROM public.dating_settings AS t WHERE t.user_id = v_user;
  RETURN jsonb_build_object('ok', true, 'profile', jsonb_build_object(
    'display_name', v_p.display_name,
    'country_code', v_p.country_code, 'region_code', v_p.region_code, 'side_code', v_p.side_code,
    'intention', v_p.intention, 'marriage_timeline', v_p.marriage_timeline, 'timeline_visible', v_p.timeline_visible,
    'attested', v_p.not_married_attested_at IS NOT NULL,
    'children_have', v_p.children_have, 'children_want', v_p.children_want,
    'family_involvement', v_p.family_involvement,
    'gender_visible', v_p.gender_visible, 'faith_visible', v_p.faith_visible, 'marital_visible', v_p.marital_visible,
    'photos_after_mutual', v_p.photos_after_mutual,
    'identity', private.dating_field_decrypt(v_s.identity_enc),
    'seeking', private.dating_field_decrypt(v_s.seeking_enc) -> 'seeking',
    'faith', private.dating_field_decrypt(v_s.faith_enc),
    'marital', private.dating_field_decrypt(v_s.marital_enc) ->> 'marital',
    'preferences', CASE WHEN v_d.user_id IS NULL THEN NULL ELSE jsonb_build_object(
      'min_age', v_d.min_age, 'max_age', v_d.max_age, 'region_scope', v_d.region_scope,
      'open_abroad', to_jsonb(v_d.open_abroad), 'want_must_match', v_d.want_must_match,
      'exclude_parents', v_d.exclude_parents) END,
    'settings', jsonb_build_object(
      'drop_time', to_char(coalesce(v_t.drop_time, '19:00'::time), 'HH24:MI'),
      'data_saver', coalesce(v_t.data_saver, false), 'digest_push', coalesce(v_t.digest_push, false),
      'chat_push', coalesce(v_t.chat_push, true), 'show_when_away', coalesce(v_t.show_when_away, false)),
    'prompts', coalesce((SELECT jsonb_agg(jsonb_build_object('position', q.position, 'prompt_id', q.prompt_id,
                                                             'answer', q.answer) ORDER BY q.position)
                           FROM public.dating_prompts AS q
                          WHERE q.user_id = v_user AND q.moderation_state = 'approved'), '[]'::jsonb)));
END;
$fn$;

-- D12: exactly what others will see on the introduction card (§3.4):
-- name, age (never the DOB), region (never the side), intention (with the
-- timeline only if shown), children, prompts, approved photo slots, and
-- gender, pronouns, faith and "Divorced" / "Widowed" only if shown.
CREATE OR REPLACE FUNCTION public.get_dating_profile_preview()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_user constant uuid := auth.uid();
  v_p public.dating_profiles;
  v_s public.dating_profile_sensitive;
  v_identity jsonb;
  v_faith jsonb;
  v_marital text;
  v_region jsonb;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;
  IF NOT public.dating_require_trusted_device() THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'reverify_device');
  END IF;
  SELECT * INTO v_p FROM public.dating_profiles AS p WHERE p.user_id = v_user;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', true, 'card', NULL);
  END IF;
  SELECT * INTO v_s FROM public.dating_profile_sensitive AS s WHERE s.user_id = v_user;
  IF (v_p.gender_visible OR v_p.faith_visible OR v_p.marital_visible) AND NOT private.dating_field_key_present() THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'unavailable');
  END IF;
  IF v_p.gender_visible THEN
    v_identity := private.dating_field_decrypt(v_s.identity_enc);
  END IF;
  IF v_p.faith_visible THEN
    v_faith := private.dating_field_decrypt(v_s.faith_enc);
  END IF;
  IF v_p.marital_visible THEN
    v_marital := private.dating_field_decrypt(v_s.marital_enc) ->> 'marital';
  END IF;
  SELECT r INTO v_region FROM jsonb_array_elements((public.dating_country_config(v_p.country_code)).region_list) AS r
   WHERE r ->> 'code' = v_p.region_code;
  RETURN jsonb_build_object('ok', true, 'card', jsonb_build_object(
    'display_name', v_p.display_name,
    'age', public.account_age(v_user),
    'region_code', v_p.region_code,
    'region_name_key', v_region ->> 'name_key',
    'intention', v_p.intention,
    'marriage_timeline', CASE WHEN v_p.intention = 'marriage' AND v_p.timeline_visible THEN v_p.marriage_timeline END,
    'children_have', v_p.children_have,
    'children_want', v_p.children_want,
    'gender', CASE WHEN v_identity IS NULL THEN NULL ELSE jsonb_build_object(
      'identity', v_identity ->> 'identity', 'specific', v_identity ->> 'specific',
      'specific_text', v_identity ->> 'specific_text') END,
    'pronouns', v_identity ->> 'pronouns',
    'faith', CASE WHEN v_faith IS NULL THEN NULL ELSE jsonb_build_object(
      'faith', v_faith ->> 'faith', 'denomination', v_faith ->> 'denomination') END,
    'marital', CASE WHEN v_marital IN ('divorced', 'widowed') THEN v_marital END,
    'prompts', coalesce((SELECT jsonb_agg(jsonb_build_object('prompt_id', q.prompt_id, 'answer', q.answer)
                                          ORDER BY q.position)
                           FROM public.dating_prompts AS q
                          WHERE q.user_id = v_user AND q.moderation_state = 'approved'), '[]'::jsonb),
    'photos', coalesce((SELECT jsonb_agg(jsonb_build_object('id', f.id, 'position', f.position) ORDER BY f.position)
                          FROM public.dating_profile_photos AS f
                         WHERE f.user_id = v_user AND f.moderation_state = 'approved'), '[]'::jsonb)));
END;
$fn$;

REVOKE ALL ON FUNCTION
  public.save_dating_prompts(text, jsonb), public.save_dating_display_name(text, text),
  public.save_dating_family_involvement(text, text), public.save_dating_settings(text, jsonb),
  public.set_dating_open_abroad(text, char(2)[]), public.set_dating_photos_after_mutual(text, boolean),
  public.get_my_dating_profile(), public.get_dating_profile_preview()
  FROM PUBLIC, anon;
-- The two readers decrypt: no one but the person (S-4).
REVOKE ALL ON FUNCTION public.get_my_dating_profile(), public.get_dating_profile_preview() FROM service_role;
GRANT EXECUTE ON FUNCTION
  public.save_dating_prompts(text, jsonb), public.save_dating_display_name(text, text),
  public.save_dating_family_involvement(text, text), public.save_dating_settings(text, jsonb),
  public.set_dating_open_abroad(text, char(2)[]), public.set_dating_photos_after_mutual(text, boolean),
  public.get_my_dating_profile(), public.get_dating_profile_preview()
  TO authenticated;

COMMIT;
```

Create `supabase/migrations/20261106170010_dating_v2_profile_readers_grants.sql` with exactly:

```sql
-- Spec 2 W1c: grants for 20261106170000_dating_v2_profile_readers.sql. The
-- writers and the two own-profile readers are the signed-in app's.
BEGIN;
SET LOCAL lock_timeout = '5s';
REVOKE ALL ON FUNCTION
  public.save_dating_prompts(text, jsonb), public.save_dating_display_name(text, text),
  public.save_dating_family_involvement(text, text), public.save_dating_settings(text, jsonb),
  public.set_dating_open_abroad(text, char(2)[]), public.set_dating_photos_after_mutual(text, boolean),
  public.get_my_dating_profile(), public.get_dating_profile_preview()
  FROM PUBLIC, anon;
-- The two readers decrypt: no one but the person (S-4).
REVOKE ALL ON FUNCTION public.get_my_dating_profile(), public.get_dating_profile_preview() FROM service_role;
GRANT EXECUTE ON FUNCTION
  public.save_dating_prompts(text, jsonb), public.save_dating_display_name(text, text),
  public.save_dating_family_involvement(text, text), public.save_dating_settings(text, jsonb),
  public.set_dating_open_abroad(text, char(2)[]), public.set_dating_photos_after_mutual(text, boolean),
  public.get_my_dating_profile(), public.get_dating_profile_preview()
  TO authenticated;
COMMIT;
```

- [ ] **Step 3: Apply each file twice; run the contracts**

```bash
for i in 1 2; do
  for f in 20261106170000_dating_v2_profile_readers 20261106170010_dating_v2_profile_readers_grants; do
    psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/migrations/$f.sql > /dev/null 2>&1; echo "$f exit=$?"
  done
done
```

```bash
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/dating_v2_setup_contracts.sql 2>&1 | grep -E 'ERROR|all held' | head -1 | sed -E 's/^psql:[^ ]* //'
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/dating_v2_identity_contracts.sql 2>&1 | grep -E 'ERROR|all held' | head -1 | sed -E 's/^psql:[^ ]* //'
```

Expected: four `exit=0` lines; `NOTICE:  dating_v2_setup_contracts: all held`; `NOTICE:  dating_v2_identity_contracts: all held`.

- [ ] **Step 4: The canary's rows for this migration**

Create `.superpowers/sdd/2026-11-06-spec2-w1/canary_T10.sql` with exactly:

```sql
-- ---------------------------------------------------------------------
-- W1c (migration 8): the remaining writers and the own-profile readers.
-- ---------------------------------------------------------------------
INSERT INTO allowed_fn (sig, clients) VALUES
  ('get_dating_profile_preview()', 'authenticated'),
  ('get_my_dating_profile()', 'authenticated'),
  ('save_dating_display_name(text,text)', 'authenticated'),
  ('save_dating_family_involvement(text,text)', 'authenticated'),
  ('save_dating_prompts(text,jsonb)', 'authenticated'),
  ('save_dating_settings(text,jsonb)', 'authenticated'),
  ('set_dating_open_abroad(text,character[])', 'authenticated'),
  ('set_dating_photos_after_mutual(text,boolean)', 'authenticated');
```

```bash
D=.superpowers/sdd/2026-11-06-spec2-w1
python3 -I $D/section.py supabase/tests/dating_rls_canary.sql $D/canary_T10.sql --before '-- Checks (every batch adds its rows above this line).'
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/dating_rls_canary.sql 2>&1 | grep -E 'ERROR|all held' | head -1 | sed -E 's/^psql:[^ ]* //'
```

Expected: `dating_rls_canary.sql: canary_T10.sql before`, then `NOTICE:  dating_rls_canary: all held` (before this step, with the migration applied, the canary names every new object as `not in the canary's allow-list`).

- [ ] **Step 5: Mutation checks**

Create `.superpowers/sdd/2026-11-06-spec2-w1/mut_T10.py` and `.superpowers/sdd/2026-11-06-spec2-w1/mut_T10_identity.py` with exactly:

```python
MUTS = {
 'prompts_unfiltered': ("""    v_verdict := private.content_filter_verdict(v_item.answer, NULL);""", """    v_verdict := NULL;"""),
 'prompts_any_length': ("""    IF char_length(v_item.answer) NOT BETWEEN 10 AND 200 THEN""", """    IF char_length(v_item.answer) = 0 THEN"""),
 'one_prompt_enough': ("""OR jsonb_array_length(p_items) NOT BETWEEN 2 AND 3""", """OR jsonb_array_length(p_items) NOT BETWEEN 1 AND 3"""),
 'name_unfiltered': ("""  IF private.content_filter_verdict(v_name, ARRAY['contact_info']) IS NOT NULL THEN""", """  IF false THEN"""),
 'drop_time_any_hour': ("""    IF v_drop NOT BETWEEN '07:00' AND '22:00' THEN""", """    IF false THEN"""),
 'abroad_before_verified': ("""  IF cardinality(v_list) > 0
     AND (NOT EXISTS""", """  IF false
     AND (NOT EXISTS"""),
 'abroad_own_country': ("""                 WHERE c::text = v_own OR NOT coalesce""", """                 WHERE NOT coalesce"""),
 'photos_hidden_before_day_30': ("""  IF p_on AND (SELECT u.created_at FROM public.users AS u WHERE u.id = v_user) > now() - interval '30 days' THEN""", """  IF false THEN"""),
 'preview_shows_seeking': ("""    'children_want', v_p.children_want,
    'gender'""", """    'children_want', v_p.children_want,
    'seeking', private.dating_field_decrypt(v_s.seeking_enc),
    'gender'"""),
 'preview_shows_side': ("""    'region_code', v_p.region_code,
    'region_name_key'""", """    'region_code', v_p.region_code, 'side_code', v_p.side_code,
    'region_name_key'"""),
 'preview_ignores_faith_toggle': ("""  IF v_p.faith_visible THEN
    v_faith := private.dating_field_decrypt(v_s.faith_enc);
  END IF;""", """  v_faith := private.dating_field_decrypt(v_s.faith_enc);"""),
 'preview_ignores_gender_toggle': ("""  IF v_p.gender_visible THEN
    v_identity := private.dating_field_decrypt(v_s.identity_enc);
  END IF;""", """  v_identity := private.dating_field_decrypt(v_s.identity_enc);"""),
}
```

```python
MUTS = {
 'own_profile_without_key': ("""  IF num_nonnulls(v_s.identity_enc, v_s.seeking_enc, v_s.faith_enc, v_s.marital_enc) > 0
     AND NOT private.dating_field_key_present() THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'unavailable');
  END IF;""", ""),
}
```

```bash
D=.superpowers/sdd/2026-11-06-spec2-w1
python3 -I $D/mutate.py supabase/migrations/20261106170000_dating_v2_profile_readers.sql supabase/tests/dating_v2_setup_contracts.sql $D/mut_T10.py $D
python3 -I $D/mutate.py supabase/migrations/20261106170000_dating_v2_profile_readers.sql supabase/tests/dating_v2_identity_contracts.sql $D/mut_T10_identity.py $D
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/dating_v2_setup_contracts.sql 2>&1 | grep -E 'ERROR|all held' | head -1 | sed -E 's/^psql:[^ ]* //'
```

Expected (`prompts_any_length` and `drop_time_any_hour` are caught by the tables' CHECKs):

- `prompts_unfiltered`: `ERROR:  CONTRACT VIOLATED: D10 accepted one prompt, a repeated prompt, a short answer or contact details`
- `prompts_any_length`: `ERROR:  new row for relation "dating_prompts" violates check constraint "dating_prompts_answer_check"`
- `one_prompt_enough`: `ERROR:  CONTRACT VIOLATED: D10 accepted one prompt, a repeated prompt, a short answer or contact details`
- `name_unfiltered`: `ERROR:  CONTRACT VIOLATED: D12 name rules are wrong (1-30 characters, no contact details)`
- `drop_time_any_hour`: `ERROR:  new row for relation "dating_settings" violates check constraint "dating_settings_drop_time_check"`
- `abroad_before_verified`: `ERROR:  CONTRACT VIOLATED: other countries were allowed before verification, or for one's own or a closed country`
- `abroad_own_country`: `ERROR:  CONTRACT VIOLATED: other countries were allowed before verification, or for one's own or a closed country`
- `photos_hidden_before_day_30`: `ERROR:  CONTRACT VIOLATED: photos after mutual interest is wrong before or after account day 30`
- `preview_shows_seeking`: `ERROR:  CONTRACT VIOLATED: the preview shows something others must never see: {"ok": true, "card": {"age": 30, "faith": null, "gender": null, "photos": [], "marital": nul`
- `preview_shows_side`: `ERROR:  CONTRACT VIOLATED: the preview shows something others must never see: {"ok": true, "card": {"age": 30, "faith": null, "gender": null, "photos": [], "marital": nul`
- `preview_ignores_faith_toggle`: `ERROR:  CONTRACT VIOLATED: the preview shows something others must never see: {"ok": true, "card": {"age": 30, "faith": {"faith": "christian", "denomination": null}, "gen`
- `preview_ignores_gender_toggle`: `ERROR:  CONTRACT VIOLATED: the preview shows something others must never see: {"ok": true, "card": {"age": 30, "faith": null, "gender": {"identity": "woman", "specific":`
- `own_profile_without_key`: `ERROR:  CONTRACT VIOLATED: without dating_field_key a writer or reader raised (dating:field_key_missing) instead of answering unavailable`

then `NOTICE:  dating_v2_setup_contracts: all held`.

- [ ] **Step 6: The local harness (edit only, never run)**

`scripts/local_pg_grants.sql`: append after the last line (`\i supabase/migrations/20261106160010_dating_v2_setup_writers_grants.sql`), exactly:

```sql

-- Spec 2 W1c: the remaining writers and the own-profile readers are the
-- signed-in app's.
\i supabase/migrations/20261106170010_dating_v2_profile_readers_grants.sql
```

```bash
python3 -I - <<'PY'
import pathlib
p = pathlib.Path('scripts/local_pg_grants.sql')
s = p.read_text()
assert s.endswith('\\i supabase/migrations/20261106160010_dating_v2_setup_writers_grants.sql' + chr(10))
p.write_text(s + chr(10) + "-- Spec 2 W1c: the remaining writers and the own-profile readers are the\n-- signed-in app's." + chr(10) + '\\i supabase/migrations/20261106170010_dating_v2_profile_readers_grants.sql' + chr(10))
print('local_pg_grants.sql: one \\i block added')
PY
```

- [ ] **Step 7: Run tests (the W1c gate)**

```bash
D=.superpowers/sdd/2026-11-06-spec2-w1
for f in supabase/tests/*.sql; do
  if psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f "$f" >/dev/null 2>&1; then echo "PASS $(basename "$f")"; else echo "FAIL $(basename "$f")"; fi
done > $D/sql-after-task10.txt
grep '^FAIL' $D/sql-after-task10.txt | sort | comm -13 <(cat $D/sql-baseline*.txt | grep '^FAIL' | sort -u) - | grep -vE 'FAIL ai_(session|assist|assistant|processing)_'
grep '^FAIL' $D/sql-after-task10.txt | sort | comm -13 <(cat $D/sql-baseline*.txt | grep '^FAIL' | sort -u) - | grep -E 'FAIL ai_' | sed 's/^FAIL //' | while read t; do
  echo "$t: $(psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/$t 2>&1 | grep -m1 ERROR | grep -ci dating) Dating mentions"
done
git status --short -- lib test | head
sed -n '/if (isAuthenticated \&\& !_gateData.isComplete) {/,/_redirectingToOnboarding = false;/p' lib/home/home_screen.dart | shasum | diff - $D/latch.sha && echo latch-unchanged
flutter test test/architecture/games_untouched_test.dart 2>&1 | tail -1
```

Expected: as Task 4 Step 7, against `$D/sql-after-task10.txt`, with `dating_v2_setup_contracts.sql` also `PASS`.

**W1c gate (owner):** `dating_field_key` provisioned in Vault on every project before any profile is written there (checklist 3; until then every special-category writer answers `unavailable`).

# W1d · Lifecycle v2, never-introduce data, kill switch (Tasks 11-13)

### Task 11: Migration 9: "Never introduce me to these numbers" (data and RPCs) (§4.9 W1d #1, §3.12, §5.2 filter 13, 10 S5)

**Files:**
- Create: `supabase/migrations/20261106180000_dating_v2_never_introduce.sql`, `…180010_dating_v2_never_introduce_grants.sql`
- Modify: `supabase/tests/dating_v2_identity_contracts.sql` (E1), `supabase/tests/dating_rls_canary.sql`, `scripts/local_pg_grants.sql`

**Interfaces:**
- Consumes: Task 9's `private.dating_setup_guard`, `private.dating_invalid`; Task 2's `dating_phone_canonical`, `dating_phone_hmac_for_user`.
- Produces: `public.dating_never_introduce (id, owner_user_id, phone_hmac, label <= 20, last_two, created_at)` (50 per owner); `add_dating_never_introduce(p_idempotency_key text, p_phone_e164 text, p_label text) → jsonb` (`{"ok": true, "message": "added"}` whatever the number), `remove_dating_never_introduce(p_id uuid) → jsonb` (`{"ok": true}` for any id), `list_dating_never_introduce() → jsonb` (`{ok, items: [{id, label, last_two}]}`), `dating_never_introduce_excludes(uuid, uuid) → boolean` (both directions; for W5a's filter 13).

- [ ] **Step 1: Write the failing section**

Create `.superpowers/sdd/2026-11-06-spec2-w1/identity_E1.sql` with exactly:

```sql
-- =====================================================================
-- E1. (W1d) Never introduce me (§3.12, 10 S5): symmetric; silent (the
--    same "added" whatever the number); HMACs, never numbers; the listed
--    person sees nothing; an open introduction ends at once; at most 50.
-- =====================================================================
DO $$
DECLARE
  v_a constant uuid := pg_temp.person('60');
  v_b constant uuid := pg_temp.person('61');
  v_c constant uuid := pg_temp.person('62');
  v_d constant uuid := pg_temp.person('63');
  v_i uuid;
  v jsonb;
  n int;
BEGIN
  UPDATE public.feature_flags SET enabled = true WHERE key = 'dating_mode_enabled';
  -- Silent: an Attune member's number (B), a number nobody uses, B again
  -- typed with 00 and punctuation (the same number).
  PERFORM pg_temp.as_user(v_a);
  v := jsonb_build_array(
    public.add_dating_never_introduce('w1d-never-0001', '+1 555 870 061', 'Ex'),
    public.add_dating_never_introduce('w1d-never-0002', '+447700900999', NULL),
    public.add_dating_never_introduce('w1d-never-0003', '001 (555) 870-061', 'Again'));
  PERFORM pg_temp.as_owner();
  IF v IS DISTINCT FROM '[{"ok": true, "message": "added"}, {"ok": true, "message": "added"}, {"ok": true, "message": "added"}]'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: adding a number did not answer "added" whatever the number: %', v;
  END IF;
  -- Symmetric: neither is introduced to the other.
  IF NOT public.dating_never_introduce_excludes(v_a, v_b) OR NOT public.dating_never_introduce_excludes(v_b, v_a)
     OR public.dating_never_introduce_excludes(v_b, v_c) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: never-introduce is not symmetric (or matched the wrong person)';
  END IF;
  IF (SELECT count(*) FROM public.dating_never_introduce WHERE owner_user_id = v_a) IS DISTINCT FROM 2
     OR EXISTS (SELECT 1 FROM public.dating_never_introduce WHERE phone_hmac ~ '555870061')
     OR (SELECT label || ':' || last_two FROM public.dating_never_introduce
          WHERE owner_user_id = v_a AND phone_hmac = public.dating_phone_hmac('+1555870061')) IS DISTINCT FROM 'Again:61' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the list does not hold one HMAC per number with its label and last two digits';
  END IF;
  -- The listed person sees nothing; the table is no client's.
  PERFORM pg_temp.as_user(v_b);
  v := public.list_dating_never_introduce();
  PERFORM pg_temp.as_owner();
  IF v IS DISTINCT FROM '{"ok": true, "items": []}'::jsonb
     OR has_table_privilege('authenticated', 'public.dating_never_introduce', 'SELECT') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the listed person can see the list: %', v;
  END IF;
  PERFORM pg_temp.as_user(v_a);
  v := public.list_dating_never_introduce();
  PERFORM pg_temp.as_owner();
  IF jsonb_array_length(v -> 'items') IS DISTINCT FROM 2 OR v::text ~ '555870061' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the owner''s list is wrong or shows a number: %', v;
  END IF;
  -- Malformed input (no country code; a long label).
  PERFORM pg_temp.as_user(v_a);
  v := jsonb_build_array(public.add_dating_never_introduce('w1d-never-0009', '0244 123 456', NULL),
                         public.add_dating_never_introduce('w1d-never-0008', '+233244123456', repeat('x', 21)));
  PERFORM pg_temp.as_owner();
  IF v IS DISTINCT FROM '[{"ok": false, "reason": "invalid", "field": "phone"}, {"ok": false, "reason": "invalid", "field": "label"}]'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a number without its country code or a long label was accepted: %', v;
  END IF;
  -- An open introduction with the person on that number ends; nobody is told.
  v_i := pg_temp.intro(v_c, v_d);
  PERFORM pg_temp.as_user(v_c);
  PERFORM public.add_dating_never_introduce('w1d-never-0010', '+1555870063', NULL);
  PERFORM pg_temp.as_owner();
  IF (SELECT state FROM public.dating_introductions WHERE id = v_i) IS DISTINCT FROM 'invalidated' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an open introduction with a never-introduce number was not ended';
  END IF;
  -- Remove: own rows only, the same answer for any id.
  v_i := (SELECT id FROM public.dating_never_introduce WHERE owner_user_id = v_a LIMIT 1);
  PERFORM pg_temp.as_user(v_b);
  v := public.remove_dating_never_introduce(v_i);
  PERFORM pg_temp.as_owner();
  IF v IS DISTINCT FROM '{"ok": true}'::jsonb
     OR (SELECT count(*) FROM public.dating_never_introduce WHERE owner_user_id = v_a) IS DISTINCT FROM 2 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: someone else removed an entry from a list';
  END IF;
  -- At most 50 (re-adding a listed number still says added).
  PERFORM pg_temp.as_user(v_d);
  FOR n IN 1..50 LOOP
    PERFORM public.add_dating_never_introduce('w1d-limit-' || lpad(n::text, 4, '0'), '+4477009' || lpad(n::text, 5, '0'), NULL);
  END LOOP;
  v := jsonb_build_array(public.add_dating_never_introduce('w1d-limit-0051', '+447700999999', NULL),
                         public.add_dating_never_introduce('w1d-limit-0052', '+447700900001', NULL));
  PERFORM pg_temp.as_owner();
  IF v IS DISTINCT FROM '[{"ok": false, "reason": "limit_reached"}, {"ok": true, "message": "added"}]'::jsonb
     OR (SELECT count(*) FROM public.dating_never_introduce WHERE owner_user_id = v_d) IS DISTINCT FROM 50 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the 50-entry limit is wrong: %', v;
  END IF;
END $$;
```

```bash
python3 -I .superpowers/sdd/2026-11-06-spec2-w1/section.py supabase/tests/dating_v2_identity_contracts.sql .superpowers/sdd/2026-11-06-spec2-w1/identity_E1.sql --end
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/dating_v2_identity_contracts.sql 2>&1 | grep -E 'ERROR|all held' | head -1 | sed -E 's/^psql:[^ ]* //'
```

Expected: `dating_v2_identity_contracts.sql: identity_E1.sql end`; `ERROR:  function public.add_dating_never_introduce(unknown, unknown, unknown) does not exist`.

- [ ] **Step 2: Write migration 9 and its twin**

Create `supabase/migrations/20261106180000_dating_v2_never_introduce.sql` with exactly:

```sql
-- Spec 2 W1d, migration 9 (spec §4.9 W1d #1, §3.12, §4.3, §4.4, §5.2
-- filter 13; 10 S5): "Never introduce me to these numbers" (data and RPCs;
-- the screen is W5c).
--   * dating_never_introduce: the owner's list of phone HMACs (never the
--     number), with an optional private label (<= 20) and the last two
--     digits for the list row; at most 50 per owner.
--   * add_dating_never_introduce(key, phone, label): the same "added"
--     answer whatever the number (whether anyone uses it, whether it was
--     already listed), so the list can't test who uses Attune; it ends any
--     open introduction with the person on that number, silently.
--   * remove_dating_never_introduce(id), list_dating_never_introduce().
--   * dating_never_introduce_excludes(a, b): the hard-filter helper, both
--     directions (W5a's filter 13 calls it).
-- Nobody on a list is ever told. Grants in
-- 20261106180010_dating_v2_never_introduce_grants.sql.
BEGIN;
SET LOCAL lock_timeout = '5s';

CREATE TABLE IF NOT EXISTS public.dating_never_introduce (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  phone_hmac text NOT NULL CHECK (phone_hmac ~ '^[0-9a-f]{64}$'),
  label text CHECK (label IS NULL OR char_length(label) BETWEEN 1 AND 20),
  last_two char(2) NOT NULL CHECK (last_two ~ '^[0-9]{2}$'),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (owner_user_id, phone_hmac)
);
CREATE INDEX IF NOT EXISTS dating_never_introduce_hmac_idx ON public.dating_never_introduce (phone_hmac);
ALTER TABLE public.dating_never_introduce ENABLE ROW LEVEL SECURITY;
COMMENT ON TABLE public.dating_never_introduce IS
  'Spec 2 §3.12: numbers (as HMACs) the owner is never introduced to. Kept at exit only if the owner ticks "Keep my list" (R-2); deleted with the account.';

CREATE OR REPLACE FUNCTION public.add_dating_never_introduce(p_idempotency_key text, p_phone_e164 text, p_label text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_user constant uuid := auth.uid();
  v_reason text;
  -- Spaces, dots, dashes and brackets go; a leading 00 is the + it stands for.
  v_phone constant text := pg_catalog.regexp_replace(
    pg_catalog.regexp_replace(coalesce(p_phone_e164, ''), '[\s().-]', '', 'g'), '^00', '+');
  v_label constant text := nullif(btrim(coalesce(p_label, '')), '');
  v_hmac text;
BEGIN
  v_reason := private.dating_setup_guard();
  IF v_reason IS NOT NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', v_reason);
  END IF;
  IF v_phone !~ '^\+[1-9][0-9]{7,14}$' THEN
    RETURN private.dating_invalid('phone');
  END IF;
  IF v_label IS NOT NULL AND char_length(v_label) > 20 THEN
    RETURN private.dating_invalid('label');
  END IF;
  v_hmac := public.dating_phone_hmac(public.dating_phone_canonical(v_phone));
  IF v_hmac IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'unavailable');
  END IF;
  IF (SELECT count(*) FROM public.dating_never_introduce AS n WHERE n.owner_user_id = v_user) >= 50
     AND NOT EXISTS (SELECT 1 FROM public.dating_never_introduce AS n
                      WHERE n.owner_user_id = v_user AND n.phone_hmac = v_hmac) THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'limit_reached');
  END IF;
  IF NOT public.claim_dating_idempotency('add_dating_never_introduce', p_idempotency_key) THEN
    RETURN jsonb_build_object('ok', true, 'message', 'added');
  END IF;

  INSERT INTO public.dating_never_introduce AS n (owner_user_id, phone_hmac, label, last_two)
  VALUES (v_user, v_hmac, v_label, right(v_phone, 2))
  ON CONFLICT (owner_user_id, phone_hmac) DO UPDATE SET label = coalesce(EXCLUDED.label, n.label);
  -- An introduction not yet matched ends now, silently (§3.12).
  UPDATE public.dating_introductions AS i
     SET state = 'invalidated'
   WHERE i.state IN ('generated', 'presented', 'interested')
     AND v_user IN (i.user_low_id, i.user_high_id)
     AND public.dating_phone_hmac_for_user(CASE WHEN i.user_low_id = v_user THEN i.user_high_id ELSE i.user_low_id END) = v_hmac;
  RETURN jsonb_build_object('ok', true, 'message', 'added');
END;
$fn$;

CREATE OR REPLACE FUNCTION public.remove_dating_never_introduce(p_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_user constant uuid := auth.uid();
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;
  IF NOT public.dating_require_trusted_device() THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'reverify_device');
  END IF;
  -- The same answer whether the row was the caller's, someone else's or none.
  DELETE FROM public.dating_never_introduce AS n WHERE n.id = p_id AND n.owner_user_id = v_user;
  RETURN jsonb_build_object('ok', true);
END;
$fn$;

CREATE OR REPLACE FUNCTION public.list_dating_never_introduce()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_user constant uuid := auth.uid();
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;
  IF NOT public.dating_require_trusted_device() THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'reverify_device');
  END IF;
  RETURN jsonb_build_object('ok', true, 'items', coalesce((
    SELECT jsonb_agg(jsonb_build_object('id', n.id, 'label', n.label, 'last_two', n.last_two)
                     ORDER BY n.created_at, n.id)
      FROM public.dating_never_introduce AS n WHERE n.owner_user_id = v_user), '[]'::jsonb));
END;
$fn$;

-- Filter 13 (§5.2), both directions.
CREATE OR REPLACE FUNCTION public.dating_never_introduce_excludes(p_a uuid, p_b uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $fn$
  SELECT EXISTS (SELECT 1 FROM public.dating_never_introduce AS n
                  WHERE n.owner_user_id = p_a AND n.phone_hmac = public.dating_phone_hmac_for_user(p_b))
      OR EXISTS (SELECT 1 FROM public.dating_never_introduce AS n
                  WHERE n.owner_user_id = p_b AND n.phone_hmac = public.dating_phone_hmac_for_user(p_a));
$fn$;

REVOKE ALL ON public.dating_never_introduce FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.dating_never_introduce_excludes(uuid, uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.add_dating_never_introduce(text, text, text), public.remove_dating_never_introduce(uuid),
  public.list_dating_never_introduce() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.add_dating_never_introduce(text, text, text), public.remove_dating_never_introduce(uuid),
  public.list_dating_never_introduce() TO authenticated;

COMMIT;
```

Create `supabase/migrations/20261106180010_dating_v2_never_introduce_grants.sql` with exactly:

```sql
-- Spec 2 W1d: grants for 20261106180000_dating_v2_never_introduce.sql. The
-- list is no client's table (the three RPCs are the app's way in); the
-- service role keeps DML for support and deletion jobs; the filter helper
-- is the database's own.
BEGIN;
SET LOCAL lock_timeout = '5s';
REVOKE ALL ON public.dating_never_introduce FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.dating_never_introduce TO service_role;
REVOKE ALL ON FUNCTION public.dating_never_introduce_excludes(uuid, uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.add_dating_never_introduce(text, text, text), public.remove_dating_never_introduce(uuid),
  public.list_dating_never_introduce() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.add_dating_never_introduce(text, text, text), public.remove_dating_never_introduce(uuid),
  public.list_dating_never_introduce() TO authenticated;
COMMIT;
```

- [ ] **Step 3: Apply each file twice; run the contract**

```bash
for i in 1 2; do
  for f in 20261106180000_dating_v2_never_introduce 20261106180010_dating_v2_never_introduce_grants; do
    psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/migrations/$f.sql > /dev/null 2>&1; echo "$f exit=$?"
  done
done
```

```bash
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/dating_v2_identity_contracts.sql 2>&1 | grep -E 'ERROR|all held' | head -1 | sed -E 's/^psql:[^ ]* //'
```

Expected: four `exit=0` lines; `NOTICE:  dating_v2_identity_contracts: all held`.

- [ ] **Step 4: The canary's rows for this migration**

Create `.superpowers/sdd/2026-11-06-spec2-w1/canary_T11.sql` with exactly:

```sql
-- ---------------------------------------------------------------------
-- W1d (migration 9): never introduce.
-- ---------------------------------------------------------------------
INSERT INTO allowed_rel (name, authenticated, service_dml) VALUES
  ('dating_never_introduce', '', 'DELETE,INSERT,SELECT,UPDATE');
INSERT INTO allowed_fn (sig, clients) VALUES
  ('add_dating_never_introduce(text,text,text)', 'authenticated'),
  ('dating_never_introduce_excludes(uuid,uuid)', ''),
  ('list_dating_never_introduce()', 'authenticated'),
  ('remove_dating_never_introduce(uuid)', 'authenticated');
```

```bash
D=.superpowers/sdd/2026-11-06-spec2-w1
python3 -I $D/section.py supabase/tests/dating_rls_canary.sql $D/canary_T11.sql --before '-- Checks (every batch adds its rows above this line).'
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/dating_rls_canary.sql 2>&1 | grep -E 'ERROR|all held' | head -1 | sed -E 's/^psql:[^ ]* //'
```

Expected: `dating_rls_canary.sql: canary_T11.sql before`, then `NOTICE:  dating_rls_canary: all held` (before this step, with the migration applied, the canary names every new object as `not in the canary's allow-list`).

- [ ] **Step 5: Mutation checks**

Create `.superpowers/sdd/2026-11-06-spec2-w1/mut_T11.py` with exactly:

```python
MUTS = {
 'double_zero_not_plus': ("    pg_catalog.regexp_replace(coalesce(p_phone_e164, ''), '[\\s().-]', '', 'g'), '^00', '+');", "    pg_catalog.regexp_replace(coalesce(p_phone_e164, ''), '[\\s().-]', '', 'g'), '^00', '00');"),
 'excludes_one_way': ("""      OR EXISTS (SELECT 1 FROM public.dating_never_introduce AS n
                  WHERE n.owner_user_id = p_b AND n.phone_hmac = public.dating_phone_hmac_for_user(p_a));""", """;"""),
 'add_reveals_existing': ("""  RETURN jsonb_build_object('ok', true, 'message', 'added');
END;
$fn$;

CREATE OR REPLACE FUNCTION public.remove_dating_never_introduce""", """  RETURN jsonb_build_object('ok', true, 'message', CASE WHEN EXISTS (SELECT 1 FROM auth.users AS a
           WHERE public.dating_phone_canonical(a.phone) = v_phone) THEN 'added_user' ELSE 'added' END);
END;
$fn$;

CREATE OR REPLACE FUNCTION public.remove_dating_never_introduce"""),
 'no_intro_end': ("""  UPDATE public.dating_introductions AS i
     SET state = 'invalidated'
   WHERE i.state IN ('generated', 'presented', 'interested')
     AND v_user IN (i.user_low_id, i.user_high_id)""", """  UPDATE public.dating_introductions AS i
     SET state = 'invalidated'
   WHERE false
     AND v_user IN (i.user_low_id, i.user_high_id)"""),
 'local_numbers_accepted': ("""  IF v_phone !~ '^\\+[1-9][0-9]{7,14}$' THEN""", """  IF v_phone !~ '^\\+?[0-9]{7,15}$' THEN"""),
 'lists_others': ("""      FROM public.dating_never_introduce AS n WHERE n.owner_user_id = v_user), '[]'::jsonb));""", """      FROM public.dating_never_introduce AS n), '[]'::jsonb));"""),
}
```

```bash
D=.superpowers/sdd/2026-11-06-spec2-w1
python3 -I $D/mutate.py supabase/migrations/20261106180000_dating_v2_never_introduce.sql supabase/tests/dating_v2_identity_contracts.sql $D/mut_T11.py $D
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/dating_v2_identity_contracts.sql 2>&1 | grep -E 'ERROR|all held' | head -1 | sed -E 's/^psql:[^ ]* //'
```

Expected:

- `double_zero_not_plus`: `ERROR:  CONTRACT VIOLATED: adding a number did not answer "added" whatever the number: [{"ok": true, "message": "added"}, {"ok": true, "message": "added"}, {"ok": false,`
- `excludes_one_way`: `ERROR:  CONTRACT VIOLATED: never-introduce is not symmetric (or matched the wrong person)`
- `add_reveals_existing`: `ERROR:  CONTRACT VIOLATED: adding a number did not answer "added" whatever the number: [{"ok": true, "message": "added_user"}, {"ok": true, "message": "added"}, {"ok": tr`
- `no_intro_end`: `ERROR:  CONTRACT VIOLATED: an open introduction with a never-introduce number was not ended`
- `local_numbers_accepted`: `ERROR:  CONTRACT VIOLATED: a number without its country code or a long label was accepted: [{"ok": true, "message": "added"}, {"ok": false, "field": "label", "reason": "i`
- `lists_others`: `ERROR:  CONTRACT VIOLATED: the listed person can see the list: {"ok": true, "items": [{"id": "32796119-9c44-4d6b-838e-601a149164cd", "label": "Again", "last_two": "61"},`

then `NOTICE:  dating_v2_identity_contracts: all held`.

- [ ] **Step 6: The local harness (edit only, never run)**

`scripts/local_pg_grants.sql`: append after the last line (`\i supabase/migrations/20261106170010_dating_v2_profile_readers_grants.sql`), exactly:

```sql

-- Spec 2 W1d: never-introduce is reached through its three RPCs; the
-- filter helper is the database's own.
\i supabase/migrations/20261106180010_dating_v2_never_introduce_grants.sql
```

```bash
python3 -I - <<'PY'
import pathlib
p = pathlib.Path('scripts/local_pg_grants.sql')
s = p.read_text()
assert s.endswith('\\i supabase/migrations/20261106170010_dating_v2_profile_readers_grants.sql' + chr(10))
p.write_text(s + chr(10) + "-- Spec 2 W1d: never-introduce is reached through its three RPCs; the\n-- filter helper is the database's own." + chr(10) + '\\i supabase/migrations/20261106180010_dating_v2_never_introduce_grants.sql' + chr(10))
print('local_pg_grants.sql: one \\i block added')
PY
```

### Task 12: Migration 10: lifecycle v2 (readiness, activation, pause, resume, exit's hard delete, consent purposes, the parked pause, the generation key guard, health v2) (§4.9 W1d #2, §3.8, §4.8, §6.3, Q17, R-2, R19; mutants 5, 17, 30; P-32-P-36, P-38)

**Files:**
- Create: `supabase/migrations/20261106190000_dating_v2_lifecycle.sql`, `…190010_dating_v2_lifecycle_grants.sql`
- Modify: `supabase/tests/dating_v2_identity_contracts.sql` (E2), `supabase/tests/dating_mode_contracts.sql` (readiness v2 fixture), `supabase/tests/identity_foundation_contracts.sql` (sections D, D2), `supabase/tests/dating_rls_canary.sql`, `scripts/local_pg_grants.sql`

**Interfaces:**
- Consumes: everything above; `queue_media_deletion`, `users.phone_released_at`, the live bodies in `before/`.
- Produces: `dating_enrollments.pause_reason` (`user`, `relationship`, `path_change`, `same_gender_switch`, `away`, `account_parked`; W2 writes `path_change`); `public.dating_profile_complete(uuid)`; `dating_profile_ready` v2; `activate_dating_profile` / `pause_dating_mode` v2; `resume_dating_mode(text) → dating_enrollments` (raises `not_paused`, `resume_gates_not_met`, `profile_or_preferences_incomplete`); `exit_dating_mode(p_idempotency_key text, p_keep_never_introduce boolean DEFAULT false) → dating_enrollments`; `private.dating_exit_internal(uuid, boolean)`; `record_dating_consent` purposes v2 (withdrawal = exit); `public.dating_on_account_parked()` + trigger; `run_dating_candidate_generation` → `{"skipped": "missing_key"}` without either key; health's four new fields.

- [ ] **Step 1: Write the failing section**

Create `.superpowers/sdd/2026-11-06-spec2-w1/identity_E2.sql` with exactly:

```sql
-- =====================================================================
-- E2. (W1d) Activation with explicit "Everyone"; pause, resume and their
--    reasons; exit's hard delete (the never-introduce list kept only if
--    ticked, matches sealed, consents kept; mutants 17, 30); consent
--    withdrawal is exit; the parked pause (R19); generation's key guard
--    (mutant 5); health v2; no Dating function mentions users.mode.
-- =====================================================================
-- A person [p_n] in Accra through D2-D10 with [p_seeking], verified, two
-- approved photos: everything activation needs.
CREATE FUNCTION pg_temp.complete(p_n text, p_identity text, p_seeking text[]) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE
  v_u constant uuid := pg_temp.person(p_n);
  v jsonb := '[]'::jsonb;
BEGIN
  INSERT INTO public.dating_consent_events (user_id, idempotency_key, purpose, action, policy_version, occurred_at)
  SELECT v_u, 'w1d-consent-' || c, c, 'granted', 'dating-2.0', clock_timestamp()
    FROM unnest(ARRAY['dating_terms', 'dating_opt_in', 'special_category_profile']) AS c;
  PERFORM pg_temp.as_user(v_u);
  v := v || jsonb_build_array(public.save_dating_intention('w1d-' || p_n || '-d2-0001', 'committed', NULL, true, true, NULL, false));
  v := v || jsonb_build_array(public.save_dating_location('w1d-' || p_n || '-d3-0001', 'GB', 'TLI', NULL, 'region'));
  v := v || jsonb_build_array(public.save_dating_identity('w1d-' || p_n || '-d5-0001', p_identity, NULL, NULL, NULL, false));
  v := v || jsonb_build_array(public.save_dating_who_to_meet('w1d-' || p_n || '-d6-0001', p_seeking, 25, 40));
  v := v || jsonb_build_array(public.save_dating_children('w1d-' || p_n || '-d7-0001', false, 'yes', false, false));
  v := v || jsonb_build_array(public.save_dating_prompts('w1d-' || p_n || '-d10-001',
         '[{"prompt_id": "perfect_sunday", "answer": "A long walk by the river."},
           {"prompt_id": "ask_me_about", "answer": "The book I am reading now."}]'));
  PERFORM pg_temp.as_owner();
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(v) AS e WHERE e ->> 'ok' IS DISTINCT FROM 'true') THEN
    RAISE EXCEPTION 'fixture: setup failed for %: %', p_n, v;
  END IF;
  UPDATE public.dating_profiles SET verification_state = 'verified' WHERE user_id = v_u;
  INSERT INTO public.dating_age_verifications (user_id, birth_date, verification_method, verified_at)
  VALUES (v_u, current_date - interval '30 years', 'w1d-contract', now());
  INSERT INTO public.dating_profile_photos (user_id, storage_key, position, moderation_state) VALUES
    (v_u, 'w1d/' || p_n || '-1.jpg', 1, 'approved'), (v_u, 'w1d/' || p_n || '-2.jpg', 2, 'approved');
  RETURN v_u;
END $$;

DO $$
DECLARE
  v_a uuid;
  v_b uuid;
  v_keeper uuid;
  v_withdraw uuid;
  v_parked uuid;
  v_outsider constant uuid := pg_temp.person('55');
  v_e public.dating_enrollments;
  v_m uuid;
  v_i uuid;
  v jsonb;
  v_answers jsonb;
  v_msg text;
BEGIN
  PERFORM set_config('app.settings.dating_field_key', 'spec2-w1d-identity-field-key-0123456789abcdef', true);
  UPDATE public.feature_flags SET enabled = true WHERE key IN ('dating_mode_enabled', 'dating_same_gender_matching');
  PERFORM pg_temp.as_service('SELECT public.publish_country_config(''GB'', ''{"dating_enabled": true}'')::text');
  v_a := pg_temp.complete('50', 'woman', ARRAY['man', 'non_binary', 'woman']);
  v_b := pg_temp.complete('51', 'man', ARRAY['woman']);
  v_keeper := pg_temp.complete('52', 'man', ARRAY['woman']);
  v_withdraw := pg_temp.complete('53', 'woman', ARRAY['man']);
  v_parked := pg_temp.complete('54', 'woman', ARRAY['man']);

  -- Activation: explicit "Everyone" works; no checkbox; dating_profile_ready v2.
  IF public.dating_profile_ready(v_a) OR NOT public.dating_profile_complete(v_a) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: readiness before activation is wrong';
  END IF;
  -- Who-to-meet is part of completeness.
  v_answers := jsonb_build_object('seeking', encode((SELECT seeking_enc FROM public.dating_profile_sensitive WHERE user_id = v_keeper), 'base64'));
  UPDATE public.dating_profile_sensitive SET seeking_enc = NULL WHERE user_id = v_keeper;
  IF public.dating_profile_complete(v_keeper) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a profile with no who-to-meet answer is complete';
  END IF;
  UPDATE public.dating_profile_sensitive SET seeking_enc = decode(v_answers ->> 'seeking', 'base64') WHERE user_id = v_keeper;
  PERFORM pg_temp.as_user(v_a);
  v_e := public.activate_dating_profile('w1d-activate-a-0001');
  PERFORM pg_temp.as_owner();
  IF v_e.state IS DISTINCT FROM 'active' OR NOT public.dating_profile_ready(v_a) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a complete profile seeking Everyone did not activate';
  END IF;
  DELETE FROM public.dating_prompts WHERE user_id = v_b AND position = 2;
  PERFORM pg_temp.as_user(v_b);
  BEGIN
    PERFORM public.activate_dating_profile('w1d-activate-b-0001');
    v_msg := NULL;
  EXCEPTION WHEN invalid_parameter_value THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
  END;
  PERFORM pg_temp.as_owner();
  IF v_msg IS DISTINCT FROM 'profile_or_preferences_incomplete' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a profile with one prompt activated (%)', v_msg;
  END IF;
  INSERT INTO public.dating_prompts (user_id, position, prompt_id, answer)
  VALUES (v_b, 2, 'small_thing', 'Fresh bread in the morning.');
  PERFORM pg_temp.as_user(v_b);
  PERFORM public.activate_dating_profile('w1d-activate-b-0002');
  PERFORM pg_temp.as_owner();
  IF NOT public.dating_profile_ready(v_b) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a complete man-seeking-women profile did not activate';
  END IF;

  -- Pause, resume, reasons.
  PERFORM pg_temp.as_user(v_a);
  v_e := public.pause_dating_mode('w1d-pause-a-0001');
  PERFORM pg_temp.as_owner();
  IF v_e.state IS DISTINCT FROM 'paused' OR v_e.pause_reason IS DISTINCT FROM 'user' OR public.dating_profile_ready(v_a) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: pausing did not pause with the user reason';
  END IF;
  PERFORM public.pause_dating_for_relationship_user(v_a);
  IF (SELECT pause_reason FROM public.dating_enrollments WHERE user_id = v_a) IS DISTINCT FROM 'user' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a second pause replaced the first reason';
  END IF;
  PERFORM pg_temp.as_user(v_a);
  v_e := public.resume_dating_mode('w1d-resume-a-0001');
  PERFORM pg_temp.as_owner();
  IF v_e.state IS DISTINCT FROM 'active' OR v_e.pause_reason IS NOT NULL OR NOT public.dating_profile_ready(v_a) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: resume did not reactivate a complete, eligible profile';
  END IF;
  PERFORM public.pause_dating_for_relationship_user(v_b);
  IF (SELECT state || '/' || pause_reason FROM public.dating_enrollments WHERE user_id = v_b) IS DISTINCT FROM 'paused/relationship' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the relationship pause has no relationship reason';
  END IF;
  -- A later pause keeps the first reason; resuming needs eligibility.
  INSERT INTO public.relationships (user_a, user_b, status, invite_code, invite_expires_at)
  VALUES (v_b, NULL, 'pending', 'W1DRESUME1', now() + interval '1 day');
  PERFORM pg_temp.as_user(v_b);
  PERFORM public.pause_dating_mode('w1d-pause-b-0001');
  BEGIN
    PERFORM public.resume_dating_mode('w1d-resume-b-0001');
    v_msg := NULL;
  EXCEPTION WHEN invalid_parameter_value THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
  END;
  PERFORM pg_temp.as_owner();
  IF v_msg IS DISTINCT FROM 'resume_gates_not_met' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: resume ignored eligibility (a pending relationship): %', v_msg;
  END IF;
  IF (SELECT pause_reason FROM public.dating_enrollments WHERE user_id = v_b) IS DISTINCT FROM 'relationship' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: pausing again replaced the relationship reason';
  END IF;
  DELETE FROM public.relationships WHERE invite_code = 'W1DRESUME1';

  -- Exit: the hard delete (mutants 17, 30).
  v_m := pg_temp.match(v_a, v_b);
  PERFORM pg_temp.as_user(v_a);
  PERFORM public.add_dating_never_introduce('w1d-never-a-0001', '+447700900111', NULL);
  PERFORM public.save_dating_settings('w1d-settings-a-01', '{"digest_push": true}');
  v_e := public.exit_dating_mode('w1d-exit-a-0001');
  PERFORM pg_temp.as_owner();
  IF v_e.state IS DISTINCT FROM 'exited'
     OR EXISTS (SELECT 1 FROM public.dating_profiles WHERE user_id = v_a)
     OR EXISTS (SELECT 1 FROM public.dating_profile_sensitive WHERE user_id = v_a)
     OR EXISTS (SELECT 1 FROM public.dating_prompts WHERE user_id = v_a)
     OR EXISTS (SELECT 1 FROM public.dating_settings WHERE user_id = v_a)
     OR EXISTS (SELECT 1 FROM public.dating_profile_photos WHERE user_id = v_a)
     OR EXISTS (SELECT 1 FROM public.dating_preferences WHERE user_id = v_a)
     OR EXISTS (SELECT 1 FROM public.dating_introductions WHERE v_a IN (user_low_id, user_high_id)) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: exit left Dating data behind';
  END IF;
  IF EXISTS (SELECT 1 FROM public.dating_never_introduce WHERE owner_user_id = v_a) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: exit kept the never-introduce list by default (R-2)';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.dating_matches WHERE id = v_m AND state = 'closed' AND closed_reason = 'exit'
                   AND evidence_until BETWEEN now() + interval '29 days' AND now() + interval '31 days') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: exit did not seal the conversation for the 30-day evidence window';
  END IF;
  IF (SELECT count(*) FROM public.dating_consent_events WHERE user_id = v_a AND action = 'granted') IS DISTINCT FROM 3
     OR NOT EXISTS (SELECT 1 FROM public.dating_consent_events WHERE user_id = v_a AND purpose = 'dating_opt_in' AND action = 'withdrawn')
     OR NOT EXISTS (SELECT 1 FROM public.media_deletion_queue
                     WHERE bucket_id = 'dating-profile-photos' AND object_name = 'w1d/50-1.jpg') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: exit did not keep the consent record and its withdrawal, or did not queue the photos';
  END IF;
  -- Kept only when ticked.
  PERFORM pg_temp.as_user(v_keeper);
  PERFORM public.add_dating_never_introduce('w1d-never-k-0001', '+447700900222', NULL);
  PERFORM public.exit_dating_mode('w1d-exit-k-0001', true);
  PERFORM pg_temp.as_owner();
  IF NOT EXISTS (SELECT 1 FROM public.dating_never_introduce WHERE owner_user_id = v_keeper) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a ticked "Keep my list" lost the list';
  END IF;
  -- Withdrawing a consent is leaving Dating (§3.2 D4).
  PERFORM pg_temp.as_user(v_withdraw);
  PERFORM public.record_dating_consent('w1d-withdraw-0001', 'special_category_profile', 'withdrawn', 'dating-2.0', '[]');
  PERFORM pg_temp.as_owner();
  IF (SELECT state FROM public.dating_enrollments WHERE user_id = v_withdraw) IS DISTINCT FROM 'exited'
     OR EXISTS (SELECT 1 FROM public.dating_profile_sensitive WHERE user_id = v_withdraw) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: withdrawing the special-category consent did not exit and delete';
  END IF;
  PERFORM pg_temp.as_user(v_outsider);
  BEGIN
    PERFORM public.record_dating_consent('w1d-oldpurpose-01', 'historical_data', 'granted', 'dating-2.0', '[]');
    v_msg := NULL;
  EXCEPTION WHEN invalid_parameter_value THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
  END;
  PERFORM pg_temp.as_owner();
  IF v_msg IS DISTINCT FROM 'invalid_consent_event'
     OR EXISTS (SELECT 1 FROM public.dating_consent_events WHERE purpose IN ('historical_data', 'age_gate')) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the v1 consent purposes still exist';
  END IF;
  IF to_regprocedure('public.delete_dating_profile(text)') IS NOT NULL
     OR to_regprocedure('public.exit_dating_mode(text)') IS NOT NULL
     OR EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public'
                  AND table_name = 'dating_enrollments' AND column_name = 'adults_only_confirmed_at') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: delete_dating_profile, the one-argument exit or the adults-only checkbox survives';
  END IF;

  -- The parked pause (R19, I-11): Spec 1's mark sets phone_released_at;
  -- the account leaves Today at once; nothing is carried at parking (O3).
  PERFORM pg_temp.as_user(v_parked);
  PERFORM public.activate_dating_profile('w1d-activate-p-0001');
  PERFORM pg_temp.as_owner();
  v_i := pg_temp.intro(v_parked, v_b);
  UPDATE public.users SET phone_released_at = now() WHERE id = v_parked;
  IF (SELECT state || '/' || pause_reason FROM public.dating_enrollments WHERE user_id = v_parked) IS DISTINCT FROM 'paused/account_parked'
     OR (SELECT state FROM public.dating_introductions WHERE id = v_i) IS DISTINCT FROM 'invalidated' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: parking did not pause with account_parked and end the introductions';
  END IF;
  -- (Section C checks that parking writes no enforcement record, O3.)
  UPDATE public.users SET phone_released_at = now() + interval '1 minute' WHERE id = v_parked;
  IF (SELECT pause_reason FROM public.dating_enrollments WHERE user_id = v_parked) IS DISTINCT FROM 'account_parked' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the parked trigger fired on a later change';
  END IF;

  -- Generation's key guard (mutant 5).
  UPDATE public.feature_flags SET enabled = true WHERE key = 'dating_candidate_generation';
  PERFORM set_config('app.settings.dating_exclusion_key', '', true);
  v := public.run_dating_candidate_generation(NULL);
  PERFORM set_config('app.settings.dating_exclusion_key', 'spec2-w1-contract-exclusion-key', true);
  PERFORM set_config('app.settings.dating_field_key', '', true);
  v := jsonb_build_array(v, public.run_dating_candidate_generation(NULL));
  PERFORM set_config('app.settings.dating_field_key', 'spec2-w1d-identity-field-key-0123456789abcdef', true);
  UPDATE public.feature_flags SET enabled = false WHERE key = 'dating_candidate_generation';
  IF v IS DISTINCT FROM '[{"skipped": "missing_key"}, {"skipped": "missing_key"}]'::jsonb
     OR EXISTS (SELECT 1 FROM public.dating_generation_runs WHERE started_at > now() - interval '1 minute') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: generation ran without dating_exclusion_key or dating_field_key: %', v;
  END IF;

  -- Health v2.
  v := public.get_dating_operational_health();
  IF NOT (v ?& ARRAY['environment', 'field_key_present', 'log_settings_safe', 'enabled_countries'])
     OR v ->> 'environment' IS DISTINCT FROM 'development' OR (v ->> 'field_key_present')::boolean IS NOT TRUE
     OR v -> 'enabled_countries' IS DISTINCT FROM to_jsonb(private.dating_open_countries()) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: health v2 is missing or wrong: %', v;
  END IF;

  -- No Dating function body writes (or mentions) users.mode.
  IF EXISTS (SELECT 1 FROM pg_proc AS p JOIN pg_namespace AS n ON n.oid = p.pronamespace
              WHERE n.nspname IN ('public', 'private') AND p.proname ~ 'dating'
                AND p.prosrc ~* '(users\M[^;]*\mmode\M|\mu\.mode\M)') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a Dating function mentions users.mode';
  END IF;
END $$;
```

```bash
python3 -I .superpowers/sdd/2026-11-06-spec2-w1/section.py supabase/tests/dating_v2_identity_contracts.sql .superpowers/sdd/2026-11-06-spec2-w1/identity_E2.sql --end
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/dating_v2_identity_contracts.sql 2>&1 | grep -E 'ERROR|all held' | head -1 | sed -E 's/^psql:[^ ]* //'
```

Expected: `dating_v2_identity_contracts.sql: identity_E2.sql end`; `ERROR:  function public.dating_profile_complete(uuid) does not exist`.

- [ ] **Step 2: Write migration 10 and its twin**

Create `supabase/migrations/20261106190000_dating_v2_lifecycle.sql` with exactly:

```sql
-- Spec 2 W1d, migration 10 (spec §4.9 W1d #2, §3.8, §4.3, §4.4, §4.8,
-- §6.3; Q17 exceptions, R-2, I-11, R19):
--   * dating_enrollments: pause_reason (user, relationship, path_change,
--     same_gender_switch, away, account_parked); adults_only_confirmed_at
--     dropped (the "I am 18" checkbox is gone; activate and consent were its
--     only readers and are re-created here).
--   * Consent purposes v2: dating_terms, dating_opt_in,
--     special_category_profile, special_category_faith,
--     biometric_verification; historical_data and age_gate rows deleted
--     (fresh start). record_dating_consent re-created from its live body:
--     withdrawing any purpose is leaving Dating (§3.2 D4).
--   * private.dating_exit_internal(user, keep_list): the one hard delete
--     (profile, sensitive answers, photos, prompts, settings, preferences,
--     private reflections, introductions, the session row; the
--     never-introduce list unless kept). Active matches close ('exit') and
--     stay sealed 30 days (Q17 exception 1); consent events stay (exception
--     3); the list stays only if ticked (exception 2, unticked by default).
--   * exit_dating_mode(key, keep_never_introduce DEFAULT false) replaces
--     exit_dating_mode(key); delete_dating_profile dropped (one hard delete).
--   * dating_profile_complete (new) and dating_profile_ready v2: approved,
--     verified, age gate, intention + attestation, place, children, the
--     sensitive identity and who-to-meet, >= 2 approved photos, >= 2
--     approved prompts (and, for ready, profile_state active).
--   * activate_dating_profile v2 (dating_eligibility 'setup', the age gate,
--     complete; no checkbox; explicit "Everyone" works), pause_dating_mode
--     v2 ('user'), resume_dating_mode (new: eligibility and a complete
--     profile only, Fable L3), pause_dating_for_relationship_user v2
--     ('relationship'). An enrolment already paused keeps its first reason.
--   * The parked-account trigger dating_on_account_parked on public.users
--     (AFTER UPDATE OF phone_released_at; a no-op unless NULL -> a value;
--     never raises): pauses with account_parked and invalidates the open
--     introductions. Nothing is written to enforcement_records at parking
--     (owner ruling O3: no).
--   * run_dating_candidate_generation re-created from its live body with the
--     key guard: no run without dating_exclusion_key or dating_field_key
--     ({"skipped": "missing_key"}).
--   * get_dating_operational_health v2: + environment, field_key_present,
--     log_settings_safe, enabled_countries.
-- Every re-created body is its live one plus the lines marked "Spec 2 W1d".
-- Grants in 20261106190010_dating_v2_lifecycle_grants.sql.
BEGIN;
SET LOCAL lock_timeout = '5s';

ALTER TABLE public.dating_enrollments ADD COLUMN IF NOT EXISTS pause_reason text;
ALTER TABLE public.dating_enrollments DROP CONSTRAINT IF EXISTS dating_enrollments_pause_reason_check;
ALTER TABLE public.dating_enrollments ADD CONSTRAINT dating_enrollments_pause_reason_check CHECK (
  pause_reason IS NULL OR pause_reason IN ('user', 'relationship', 'path_change', 'same_gender_switch', 'away', 'account_parked'));
DELETE FROM public.dating_consent_events WHERE purpose IN ('historical_data', 'age_gate');

-- The one hard delete (§3.8, §4.8).
CREATE OR REPLACE FUNCTION private.dating_exit_internal(p_user uuid, p_keep_never_introduce boolean)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
BEGIN
  -- Uploads never attached go with their storage objects; photo rows queue
  -- their own objects (dating_photos_queue_media_before_delete).
  PERFORM public.queue_media_deletion('dating-profile-photos', i.storage_key)
     FROM public.dating_photo_upload_intents AS i WHERE i.user_id = p_user;
  DELETE FROM public.dating_photo_upload_intents AS i WHERE i.user_id = p_user;
  DELETE FROM public.dating_profile_photos AS f WHERE f.user_id = p_user;
  DELETE FROM public.dating_prompts AS q WHERE q.user_id = p_user;
  DELETE FROM public.dating_settings AS t WHERE t.user_id = p_user;
  DELETE FROM public.dating_profile_sensitive AS s WHERE s.user_id = p_user;
  DELETE FROM public.dating_preferences AS d WHERE d.user_id = p_user;
  DELETE FROM public.dating_profiles AS p WHERE p.user_id = p_user;
  DELETE FROM public.dating_date_reflections AS r WHERE r.author_user_id = p_user;
  DELETE FROM public.dating_session_context AS c WHERE c.user_id = p_user;
  IF to_regclass('public.dating_gentle_wait_reflections') IS NOT NULL THEN -- W2's table
    EXECUTE 'DELETE FROM public.dating_gentle_wait_reflections WHERE user_id = $1' USING p_user;
  END IF;
  IF NOT coalesce(p_keep_never_introduce, false) THEN
    DELETE FROM public.dating_never_introduce AS n WHERE n.owner_user_id = p_user;
  END IF;
  -- Conversations close for both and stay sealed for the evidence window.
  UPDATE public.dating_matches AS m
     SET state = 'closed', closed_reason = 'exit', closed_at = coalesce(m.closed_at, now()),
         evidence_until = now() + interval '30 days'
   WHERE p_user IN (m.user_low_id, m.user_high_id) AND m.state = 'active';
  -- Introductions go (their interest actions cascade; a match keeps its row).
  DELETE FROM public.dating_introductions AS i WHERE p_user IN (i.user_low_id, i.user_high_id);
  DELETE FROM public.dating_feature_snapshots AS f WHERE f.user_id = p_user;
  UPDATE public.dating_enrollments AS e
     SET state = 'exited', exited_at = now(), paused_at = NULL, pause_reason = NULL, updated_at = now()
   WHERE e.user_id = p_user;
  PERFORM private.bump_metric_internal('dating.exit');
END;
$fn$;

CREATE OR REPLACE FUNCTION public.record_dating_consent(p_idempotency_key text, p_purpose text, p_action text, p_policy_version text, p_categories jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_id uuid := auth.uid();
  v_action text := CASE
    WHEN p_action IN ('grant','granted') THEN 'granted'
    WHEN p_action IN ('withdraw','withdrawn') THEN 'withdrawn'
    ELSE NULL END;
BEGIN
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'not_authenticated' USING ERRCODE='42501'; END IF;
  IF p_purpose NOT IN ('dating_terms','dating_opt_in','special_category_profile', -- Spec 2 W1d
                       'special_category_faith','biometric_verification') -- Spec 2 W1d
     OR v_action IS NULL OR btrim(COALESCE(p_policy_version,'')) = ''
     OR jsonb_typeof(COALESCE(p_categories,'[]'::jsonb)) <> 'array' THEN
    RAISE EXCEPTION 'invalid_consent_event' USING ERRCODE='22023';
  END IF;
  INSERT INTO public.dating_consent_events(
    user_id,idempotency_key,purpose,action,policy_version,categories,occurred_at
  ) VALUES(
    v_user_id,p_idempotency_key,p_purpose,v_action,p_policy_version,
    COALESCE(p_categories,'[]'::jsonb),now()
  ) ON CONFLICT(user_id,idempotency_key) DO NOTHING;

  IF v_action = 'withdrawn' THEN -- Spec 2 W1d: withdrawing any consent is leaving Dating
    PERFORM private.dating_exit_internal(v_user_id, false); -- Spec 2 W1d
  END IF;
END;
$function$;

CREATE OR REPLACE FUNCTION public.dating_profile_complete(p_user_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $fn$
  SELECT EXISTS (
    SELECT 1
      FROM public.dating_profiles AS dp
      JOIN public.dating_preferences AS pref ON pref.user_id = dp.user_id
      JOIN public.dating_profile_sensitive AS s ON s.user_id = dp.user_id
     WHERE dp.user_id = p_user_id
       AND dp.moderation_state = 'approved'
       AND dp.verification_state = 'verified'
       AND dp.country_code IS NOT NULL AND dp.region_code IS NOT NULL
       AND dp.intention IS NOT NULL
       AND dp.not_married_attested_at IS NOT NULL AND dp.attestation_version = '2026-10-v1'
       AND dp.children_have IS NOT NULL AND dp.children_want IS NOT NULL
       AND s.identity_enc IS NOT NULL AND s.seeking_enc IS NOT NULL)
    AND public.dating_age_gate_holds(p_user_id)
    AND (SELECT count(*) FROM public.dating_profile_photos AS f
          WHERE f.user_id = p_user_id AND f.moderation_state = 'approved') >= 2
    AND (SELECT count(*) FROM public.dating_prompts AS q
          WHERE q.user_id = p_user_id AND q.moderation_state = 'approved') >= 2;
$fn$;

CREATE OR REPLACE FUNCTION public.dating_profile_ready(p_user_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT EXISTS ( -- Spec 2 W1d: v2 readiness
    SELECT 1 FROM public.dating_profiles dp
    WHERE dp.user_id = p_user_id
      AND dp.profile_state = 'active'
  ) AND public.dating_profile_complete(p_user_id); -- Spec 2 W1d
$function$;

CREATE OR REPLACE FUNCTION public.activate_dating_profile(p_idempotency_key text)
 RETURNS dating_enrollments
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_user_id uuid := auth.uid();
  v_enrollment public.dating_enrollments%ROWTYPE;
BEGIN
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'not_authenticated' USING ERRCODE='42501'; END IF;
  IF NOT public.dating_require_trusted_device() THEN RAISE EXCEPTION 'reverify_device' USING ERRCODE='22023'; END IF; -- Spec 2 W1d
  PERFORM public.check_dating_rate_limit('profile_activation',10,interval '1 day');
  IF public.dating_eligibility(v_user_id, 'setup') <> 'eligible' -- Spec 2 W1d (gates 1-4, 6)
     OR NOT public.dating_age_gate_holds(v_user_id) THEN
    RAISE EXCEPTION 'activation_gates_not_met' USING ERRCODE='22023';
  END IF;
  SELECT * INTO v_enrollment FROM public.dating_enrollments WHERE user_id=v_user_id FOR UPDATE;
  IF NOT FOUND OR v_enrollment.state NOT IN ('profile_draft','paused','active') THEN -- Spec 2 W1d: no checkbox
    RAISE EXCEPTION 'enrollment_incomplete' USING ERRCODE='22023';
  END IF;
  IF NOT public.dating_profile_complete(v_user_id) THEN -- Spec 2 W1d
    RAISE EXCEPTION 'profile_or_preferences_incomplete' USING ERRCODE='22023';
  END IF;
  IF NOT public.claim_dating_idempotency('activate_dating_profile',p_idempotency_key) THEN RETURN v_enrollment; END IF;
  UPDATE public.dating_profiles SET profile_state='active',updated_at=now() WHERE user_id=v_user_id;
  UPDATE public.dating_enrollments SET state='active',activated_at=COALESCE(activated_at,now()),
    paused_at=NULL,pause_reason=NULL,exited_at=NULL,updated_at=now() WHERE user_id=v_user_id RETURNING * INTO v_enrollment; -- Spec 2 W1d: pause_reason
  PERFORM private.bump_metric_internal('dating.activated'); -- Spec 2 W1d
  RETURN v_enrollment;
END;
$function$;

CREATE OR REPLACE FUNCTION public.pause_dating_mode(p_idempotency_key text)
 RETURNS dating_enrollments
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_user_id uuid := auth.uid();
  v_enrollment public.dating_enrollments%ROWTYPE;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;
  IF NOT public.dating_require_trusted_device() THEN RAISE EXCEPTION 'reverify_device' USING ERRCODE='22023'; END IF; -- Spec 2 W1d

  IF NOT public.claim_dating_idempotency('pause_dating_mode', p_idempotency_key) THEN
    SELECT * INTO v_enrollment
    FROM public.dating_enrollments
    WHERE user_id = v_user_id;
    RETURN v_enrollment;
  END IF;

  UPDATE public.dating_profiles
  SET profile_state = 'paused',
      updated_at = now()
  WHERE user_id = v_user_id
    AND profile_state = 'active'; -- Spec 2 W1d

  UPDATE public.dating_enrollments
  SET state = 'paused',
      paused_at = now(),
      pause_reason = 'user', -- Spec 2 W1d
      updated_at = now()
  WHERE user_id = v_user_id
    AND state IN ('active', 'profile_draft') -- Spec 2 W1d: an already-paused enrolment keeps its first reason
  RETURNING * INTO v_enrollment;
  IF FOUND THEN PERFORM private.bump_metric_internal('dating.pause'); END IF; -- Spec 2 W1d

  SELECT * INTO v_enrollment FROM public.dating_enrollments WHERE user_id = v_user_id; -- Spec 2 W1d
  RETURN v_enrollment;
END;
$function$;

-- §3.8 "Resume Dating": eligibility and a complete profile, nothing more.
CREATE OR REPLACE FUNCTION public.resume_dating_mode(p_idempotency_key text)
RETURNS public.dating_enrollments
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_user_id uuid := auth.uid();
  v_enrollment public.dating_enrollments%ROWTYPE;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;
  IF NOT public.dating_require_trusted_device() THEN RAISE EXCEPTION 'reverify_device' USING ERRCODE = '22023'; END IF;
  SELECT * INTO v_enrollment FROM public.dating_enrollments AS e WHERE e.user_id = v_user_id FOR UPDATE;
  IF NOT FOUND OR v_enrollment.state <> 'paused' THEN
    RAISE EXCEPTION 'not_paused' USING ERRCODE = '22023';
  END IF;
  IF public.dating_eligibility(v_user_id, 'setup') <> 'eligible' THEN
    RAISE EXCEPTION 'resume_gates_not_met' USING ERRCODE = '22023';
  END IF;
  IF NOT public.dating_profile_complete(v_user_id) THEN
    RAISE EXCEPTION 'profile_or_preferences_incomplete' USING ERRCODE = '22023';
  END IF;
  IF NOT public.claim_dating_idempotency('resume_dating_mode', p_idempotency_key) THEN
    RETURN v_enrollment;
  END IF;
  UPDATE public.dating_profiles AS p SET profile_state = 'active', updated_at = now() WHERE p.user_id = v_user_id;
  UPDATE public.dating_enrollments AS e
     SET state = 'active', paused_at = NULL, pause_reason = NULL, updated_at = now()
   WHERE e.user_id = v_user_id
  RETURNING * INTO v_enrollment;
  RETURN v_enrollment;
END;
$fn$;

DROP FUNCTION IF EXISTS public.exit_dating_mode(text);
CREATE OR REPLACE FUNCTION public.exit_dating_mode(p_idempotency_key text, p_keep_never_introduce boolean DEFAULT false)
RETURNS public.dating_enrollments
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_user_id uuid := auth.uid();
  v_enrollment public.dating_enrollments%ROWTYPE;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;
  IF NOT public.dating_require_trusted_device() THEN RAISE EXCEPTION 'reverify_device' USING ERRCODE = '22023'; END IF;
  IF NOT public.claim_dating_idempotency('exit_dating_mode', p_idempotency_key) THEN
    SELECT * INTO v_enrollment FROM public.dating_enrollments AS e WHERE e.user_id = v_user_id;
    RETURN v_enrollment;
  END IF;
  -- "When you left" (§3.8): one withdrawal record, kept with the consents.
  INSERT INTO public.dating_consent_events (user_id, idempotency_key, purpose, action, policy_version, occurred_at)
  SELECT v_user_id, 'exit:' || p_idempotency_key, 'dating_opt_in', 'withdrawn',
         coalesce(e.terms_version, 'dating-2.0'), now()
    FROM public.dating_enrollments AS e WHERE e.user_id = v_user_id
  ON CONFLICT (user_id, idempotency_key) DO NOTHING;
  PERFORM private.dating_exit_internal(v_user_id, coalesce(p_keep_never_introduce, false));
  SELECT * INTO v_enrollment FROM public.dating_enrollments AS e WHERE e.user_id = v_user_id;
  RETURN v_enrollment;
END;
$fn$;

DROP FUNCTION IF EXISTS public.delete_dating_profile(text);
-- The checkbox column goes now that its two readers are re-created above.
ALTER TABLE public.dating_enrollments DROP COLUMN IF EXISTS adults_only_confirmed_at;

CREATE OR REPLACE FUNCTION public.pause_dating_for_relationship_user(p_user_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
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
      pause_reason = CASE WHEN state = 'suspended' THEN pause_reason ELSE 'relationship' END, -- Spec 2 W1d
      updated_at = now()
  WHERE user_id = p_user_id
    AND state IN ('active', 'profile_draft', 'eligible_to_opt_in');

  PERFORM public.invalidate_dating_for_user(p_user_id, 'relationship_guard');
END;
$function$;

-- §6.3, I-11, R19: a parked account leaves everyone's Today at once.
CREATE OR REPLACE FUNCTION public.dating_on_account_parked()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
BEGIN
  IF OLD.phone_released_at IS NOT NULL OR NEW.phone_released_at IS NULL THEN
    RETURN NULL;
  END IF;
  BEGIN
    UPDATE public.dating_enrollments AS e
       SET state = 'paused', pause_reason = 'account_parked', paused_at = coalesce(e.paused_at, now()),
           updated_at = now()
     WHERE e.user_id = NEW.id AND e.state IN ('active', 'profile_draft');
    UPDATE public.dating_profiles AS p SET profile_state = 'paused', updated_at = now()
     WHERE p.user_id = NEW.id AND p.profile_state = 'active';
    PERFORM public.invalidate_dating_for_user(NEW.id, 'account_parked');
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'dating_on_account_parked:%', SQLSTATE;
  END;
  RETURN NULL;
END;
$fn$;
DROP TRIGGER IF EXISTS dating_on_account_parked ON public.users;
CREATE TRIGGER dating_on_account_parked
  AFTER UPDATE OF phone_released_at ON public.users
  FOR EACH ROW
  WHEN (OLD.phone_released_at IS NULL AND NEW.phone_released_at IS NOT NULL)
  EXECUTE FUNCTION public.dating_on_account_parked();

CREATE OR REPLACE FUNCTION public.run_dating_candidate_generation(p_partition_key text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_version text;
  v_config jsonb;
  v_window text := to_char(date_trunc('week', now()), 'IYYY-"W"IW');
  v_partition text := COALESCE(p_partition_key, 'all');
  v_run public.dating_generation_runs%ROWTYPE;
  v_seed text;
  v_user uuid;
  v_total int := 0;
  v_users int := 0;
  v_max_attempts int;
BEGIN
  IF NOT public.dating_flag_enabled('dating_candidate_generation') THEN
    RETURN jsonb_build_object('skipped', 'flag_disabled');
  END IF;
  -- Spec 2 W1d: no run without both keys (exclusions, blocks and the
  -- encrypted fields all depend on them).
  IF public.app_setting('dating_exclusion_key') IS NULL OR NOT private.dating_field_key_present() THEN -- Spec 2 W1d
    RETURN jsonb_build_object('skipped', 'missing_key'); -- Spec 2 W1d
  END IF; -- Spec 2 W1d

  SELECT version, config INTO v_version, v_config
  FROM public.dating_algorithm_configs
  WHERE state = 'active'
  ORDER BY activated_at DESC
  LIMIT 1;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('skipped', 'no_active_config');
  END IF;

  v_max_attempts := COALESCE((v_config->>'max_attempts')::int, 3);

  -- The seed is per (version, window, partition) and stored, so a rerun of
  -- the same partition shuffles identically -- replayability (§6.2).
  v_seed := encode(digest(v_version || v_window || v_partition, 'sha256'), 'hex');

  INSERT INTO public.dating_generation_runs
    (algorithm_version, cohort_window, state, seed, partition_key, attempts,
     started_at)
  VALUES (v_version, v_window, 'processing', v_seed, v_partition, 1, now())
  ON CONFLICT (algorithm_version, cohort_window, partition_key) DO UPDATE
    SET state = 'processing',
        attempts = public.dating_generation_runs.attempts + 1,
        started_at = now()
    WHERE public.dating_generation_runs.state IN ('pending', 'failed')
      AND public.dating_generation_runs.attempts < v_max_attempts
  RETURNING * INTO v_run;

  -- No row returned means the partition is already completed, already
  -- processing, or has exhausted its attempts. All three mean "not ours".
  IF v_run.id IS NULL THEN
    RETURN jsonb_build_object('skipped', 'partition_unavailable',
                              'partition', v_partition);
  END IF;

  BEGIN
    FOR v_user IN
      SELECT de.user_id
      FROM public.dating_enrollments de
      WHERE de.state = 'active'
        AND public.dating_candidate_is_current(de.user_id)
      ORDER BY de.user_id
      LIMIT COALESCE((v_config->>'batch_user_limit')::int, 500)
    LOOP
      PERFORM public.build_dating_feature_snapshot(v_user, v_version);
      v_users := v_users + 1;
    END LOOP;

    FOR v_user IN
      SELECT de.user_id
      FROM public.dating_enrollments de
      WHERE de.state = 'active'
        AND public.dating_candidate_is_current(de.user_id)
      ORDER BY de.user_id
      LIMIT COALESCE((v_config->>'batch_user_limit')::int, 500)
    LOOP
      v_total := v_total + public.generate_dating_candidates_for_user(
        v_user, v_version, v_window, v_seed);
    END LOOP;

    UPDATE public.dating_generation_runs
    SET state = 'completed', completed_at = now()
    WHERE id = v_run.id;
  EXCEPTION WHEN OTHERS THEN
    -- Exhausted attempts go to dead_letter rather than failed, so the
    -- health view's failed_generation_runs_24h surfaces them and no
    -- further tick picks them up.
    UPDATE public.dating_generation_runs
    SET state = CASE
          WHEN attempts >= v_max_attempts THEN 'dead_letter' ELSE 'failed' END,
        last_error_code = sqlstate,
        completed_at = now()
    WHERE id = v_run.id;
    RETURN jsonb_build_object('error', sqlstate, 'partition', v_partition);
  END;

  RETURN jsonb_build_object(
    'algorithm_version', v_version,
    'cohort_window', v_window,
    'partition', v_partition,
    'users_processed', v_users,
    'introductions_created', v_total
  );
END;
$function$;

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
    'enabled_countries',to_jsonb(private.dating_open_countries()) -- Spec 2 W1d
  );
$function$;

REVOKE ALL ON FUNCTION private.dating_exit_internal(uuid, boolean), public.dating_profile_complete(uuid),
  public.dating_on_account_parked(), public.dating_profile_ready(uuid), public.pause_dating_for_relationship_user(uuid)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.record_dating_consent(text, text, text, text, jsonb), public.activate_dating_profile(text),
  public.pause_dating_mode(text), public.resume_dating_mode(text), public.exit_dating_mode(text, boolean)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.record_dating_consent(text, text, text, text, jsonb), public.activate_dating_profile(text),
  public.pause_dating_mode(text), public.resume_dating_mode(text), public.exit_dating_mode(text, boolean)
  TO authenticated;
REVOKE ALL ON FUNCTION public.run_dating_candidate_generation(text), public.get_dating_operational_health()
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.run_dating_candidate_generation(text), public.get_dating_operational_health() TO service_role;

COMMIT;
```

Create `supabase/migrations/20261106190010_dating_v2_lifecycle_grants.sql` with exactly:

```sql
-- Spec 2 W1d: grants for 20261106190000_dating_v2_lifecycle.sql. The
-- lifecycle RPCs are the signed-in app's (exit_dating_mode is a new
-- signature, so its grant is new); the hard delete, readiness, the parked
-- trigger and the relationship pause are the database's own; generation
-- and health stay the service role's.
BEGIN;
SET LOCAL lock_timeout = '5s';
REVOKE ALL ON FUNCTION private.dating_exit_internal(uuid, boolean), public.dating_profile_complete(uuid),
  public.dating_on_account_parked(), public.dating_profile_ready(uuid), public.pause_dating_for_relationship_user(uuid)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.record_dating_consent(text, text, text, text, jsonb), public.activate_dating_profile(text),
  public.pause_dating_mode(text), public.resume_dating_mode(text), public.exit_dating_mode(text, boolean)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.record_dating_consent(text, text, text, text, jsonb), public.activate_dating_profile(text),
  public.pause_dating_mode(text), public.resume_dating_mode(text), public.exit_dating_mode(text, boolean)
  TO authenticated;
REVOKE ALL ON FUNCTION public.run_dating_candidate_generation(text), public.get_dating_operational_health()
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.run_dating_candidate_generation(text), public.get_dating_operational_health() TO service_role;
COMMIT;
```

- [ ] **Step 3: Apply each file twice; diff the seven re-created functions**

```bash
for i in 1 2; do
  for f in 20261106190000_dating_v2_lifecycle 20261106190010_dating_v2_lifecycle_grants; do
    psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/migrations/$f.sql > /dev/null 2>&1; echo "$f exit=$?"
  done
done
```

```bash
D=.superpowers/sdd/2026-11-06-spec2-w1
for sig in 'public.record_dating_consent(text,text,text,text,jsonb)' 'public.dating_profile_ready(uuid)' 'public.activate_dating_profile(text)' 'public.pause_dating_mode(text)' 'public.pause_dating_for_relationship_user(uuid)' 'public.run_dating_candidate_generation(text)' 'public.get_dating_operational_health()'; do
  echo "== $sig"
  diff "$D/before/$sig.sql" <(psql -X -d attune_spec3a -Atc "select pg_get_functiondef('$sig'::regprocedure)") | grep '^[<>]'
done
```

Expected: four `exit=0` lines; then exactly:

```text
== public.record_dating_consent(text,text,text,text,jsonb)
<   IF p_purpose NOT IN ('dating_terms','dating_opt_in','historical_data','age_gate')
>   IF p_purpose NOT IN ('dating_terms','dating_opt_in','special_category_profile', -- Spec 2 W1d
>                        'special_category_faith','biometric_verification') -- Spec 2 W1d
<   IF p_purpose = 'age_gate' AND v_action = 'granted' THEN
<     INSERT INTO public.dating_enrollments(user_id,adults_only_confirmed_at)
<     VALUES(v_user_id,now()) ON CONFLICT(user_id) DO UPDATE
<     SET adults_only_confirmed_at = COALESCE(public.dating_enrollments.adults_only_confirmed_at,now());
<   ELSIF p_purpose = 'historical_data' AND v_action = 'withdrawn' THEN
<     PERFORM public.invalidate_dating_for_user(v_user_id,'historical_consent_withdrawn');
<   ELSIF p_purpose IN ('dating_terms','dating_opt_in') AND v_action = 'withdrawn' THEN
<     UPDATE public.dating_profiles SET profile_state='exited' WHERE user_id=v_user_id;
<     UPDATE public.dating_enrollments SET state='exited',exited_at=now() WHERE user_id=v_user_id;
<     PERFORM public.invalidate_dating_for_user(v_user_id,'dating_consent_withdrawn');
>   IF v_action = 'withdrawn' THEN -- Spec 2 W1d: withdrawing any consent is leaving Dating
>     PERFORM private.dating_exit_internal(v_user_id, false); -- Spec 2 W1d
== public.dating_profile_ready(uuid)
<   SELECT EXISTS (
>   SELECT EXISTS ( -- Spec 2 W1d: v2 readiness
<     JOIN public.dating_preferences pref ON pref.user_id = dp.user_id
<       AND dp.moderation_state = 'approved'
<       AND dp.verification_state = 'verified'
<       AND jsonb_array_length(pref.gender_preferences) > 0
<       AND jsonb_array_length(pref.region_preferences) > 0
<       AND jsonb_array_length(pref.intention_preferences) > 0
<   );
>   ) AND public.dating_profile_complete(p_user_id); -- Spec 2 W1d
== public.activate_dating_profile(text)
>   IF NOT public.dating_require_trusted_device() THEN RAISE EXCEPTION 'reverify_device' USING ERRCODE='22023'; END IF; -- Spec 2 W1d
<   IF NOT public.dating_flag_enabled('dating_mode_enabled')
<      OR NOT public.dating_healing_gates_hold(v_user_id)
<      OR NOT public.dating_age_gate_holds(v_user_id)
<      OR NOT public.dating_account_in_good_standing(v_user_id)
<      OR public.dating_has_relationship(v_user_id) THEN
>   IF public.dating_eligibility(v_user_id, 'setup') <> 'eligible' -- Spec 2 W1d (gates 1-4, 6)
>      OR NOT public.dating_age_gate_holds(v_user_id) THEN
<   IF NOT FOUND OR v_enrollment.state NOT IN ('profile_draft','paused','active')
<      OR v_enrollment.adults_only_confirmed_at IS NULL THEN
>   IF NOT FOUND OR v_enrollment.state NOT IN ('profile_draft','paused','active') THEN -- Spec 2 W1d: no checkbox
<   IF NOT EXISTS (
<     SELECT 1 FROM public.dating_profiles dp
<     JOIN public.dating_preferences pref ON pref.user_id=dp.user_id
<     WHERE dp.user_id=v_user_id AND dp.moderation_state='approved'
<       AND jsonb_array_length(pref.gender_preferences)>0
<       AND jsonb_array_length(pref.region_preferences)>0
<       AND jsonb_array_length(pref.intention_preferences)>0
<   ) THEN RAISE EXCEPTION 'profile_or_preferences_incomplete' USING ERRCODE='22023'; END IF;
>   IF NOT public.dating_profile_complete(v_user_id) THEN -- Spec 2 W1d
>     RAISE EXCEPTION 'profile_or_preferences_incomplete' USING ERRCODE='22023';
>   END IF;
<     paused_at=NULL,exited_at=NULL,updated_at=now() WHERE user_id=v_user_id RETURNING * INTO v_enrollment;
>     paused_at=NULL,pause_reason=NULL,exited_at=NULL,updated_at=now() WHERE user_id=v_user_id RETURNING * INTO v_enrollment; -- Spec 2 W1d: pause_reason
>   PERFORM private.bump_metric_internal('dating.activated'); -- Spec 2 W1d
== public.pause_dating_mode(text)
>   IF NOT public.dating_require_trusted_device() THEN RAISE EXCEPTION 'reverify_device' USING ERRCODE='22023'; END IF; -- Spec 2 W1d
<   WHERE user_id = v_user_id;
>   WHERE user_id = v_user_id
>     AND profile_state = 'active'; -- Spec 2 W1d
>       pause_reason = 'user', -- Spec 2 W1d
>     AND state IN ('active', 'profile_draft') -- Spec 2 W1d: an already-paused enrolment keeps its first reason
>   IF FOUND THEN PERFORM private.bump_metric_internal('dating.pause'); END IF; -- Spec 2 W1d
>   SELECT * INTO v_enrollment FROM public.dating_enrollments WHERE user_id = v_user_id; -- Spec 2 W1d
== public.pause_dating_for_relationship_user(uuid)
>       pause_reason = CASE WHEN state = 'suspended' THEN pause_reason ELSE 'relationship' END, -- Spec 2 W1d
== public.run_dating_candidate_generation(text)
>   -- Spec 2 W1d: no run without both keys (exclusions, blocks and the
>   -- encrypted fields all depend on them).
>   IF public.app_setting('dating_exclusion_key') IS NULL OR NOT private.dating_field_key_present() THEN -- Spec 2 W1d
>     RETURN jsonb_build_object('skipped', 'missing_key'); -- Spec 2 W1d
>   END IF; -- Spec 2 W1d
== public.get_dating_operational_health()
<     'pending_photo_moderation',(SELECT count(*) FROM public.dating_profile_photos WHERE moderation_state='pending')
>     'pending_photo_moderation',(SELECT count(*) FROM public.dating_profile_photos WHERE moderation_state='pending'),
>     'environment',private.attune_environment(), -- Spec 2 W1d
>     'field_key_present',private.dating_field_key_present(), -- Spec 2 W1d
>     -- Spec 2 W1d (§2.4): nothing can write an RPC's parameters to the log.
>     'log_settings_safe',coalesce(current_setting('log_statement', true) IN ('none', 'ddl')
>       AND (current_setting('log_min_duration_statement', true) = '-1'
>            OR current_setting('log_parameter_max_length', true) = '0')
>       AND current_setting('log_parameter_max_length_on_error', true) = '0', false),
>     'enabled_countries',to_jsonb(private.dating_open_countries()) -- Spec 2 W1d
```

- [ ] **Step 4: The two contracts that pin v1 lifecycle fail; move their fixtures to v2**

```bash
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/dating_mode_contracts.sql 2>&1 | grep -E 'ERROR|all held' | head -1 | sed -E 's/^psql:[^ ]* //'
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/identity_foundation_contracts.sql 2>&1 | grep -E 'ERROR|all held' | head -1 | sed -E 's/^psql:[^ ]* //'
```

Expected: `ERROR:  introduction_unavailable` (its candidates aren't ready under v2) and `ERROR:  function "public.exit_dating_mode(text)" does not exist`. Create `.superpowers/sdd/2026-11-06-spec2-w1/edit_dating_mode_w1d.py` and `.superpowers/sdd/2026-11-06-spec2-w1/edit_identity_foundation_w1d.py` with exactly:

```python
import pathlib
p = pathlib.Path('supabase/tests/dating_mode_contracts.sql')
s = p.read_text()
edits = [
("""BEGIN;

-- ---------------------------------------------------------------------------
-- Fixture
-- ---------------------------------------------------------------------------
""",
"""BEGIN;

-- Spec 2 W1d: readiness v2 reads the encrypted answers, so the fixture
-- encrypts them under a transaction-local field key.
SET LOCAL app.settings.dating_field_key = 'dating-mode-contracts-field-key-0123456789abcdef';

-- ---------------------------------------------------------------------------
-- Fixture
-- ---------------------------------------------------------------------------
"""),
("""  INSERT INTO public.dating_profiles(user_id, display_name, city_region_code, relationship_intention, bio, profile_state, moderation_state, verification_state)
  VALUES
    (a, 'Dating A','Accra','Intentional dating',NULL,'active','approved','verified'),
    (b, 'Dating B','Kumasi','Intentional dating',NULL,'active','approved','verified'),
    (d, 'Dating D','Takoradi','Intentional dating',NULL,'active','approved','verified'),
    (c, 'Dating C','Tamale','Intentional dating',NULL,'draft','approved','verified')
  ON CONFLICT (user_id) DO UPDATE
    SET profile_state=EXCLUDED.profile_state,
        moderation_state=EXCLUDED.moderation_state,
        verification_state=EXCLUDED.verification_state;
""",
"""  -- Spec 2 W1d: readiness v2 also needs the place, the intention and its
  -- attestation, and the children answers.
  INSERT INTO public.dating_profiles(user_id, display_name, city_region_code, relationship_intention, bio, profile_state, moderation_state, verification_state,
                                     country_code, region_code, intention, not_married_attested_at, attestation_version, children_have, children_want)
  VALUES
    (a, 'Dating A','Accra','Intentional dating',NULL,'active','approved','verified','GH','AA','committed',now(),'2026-10-v1',false,'yes'),
    (b, 'Dating B','Kumasi','Intentional dating',NULL,'active','approved','verified','GH','AH','committed',now(),'2026-10-v1',false,'yes'),
    (d, 'Dating D','Takoradi','Intentional dating',NULL,'active','approved','verified','GH','WP','committed',now(),'2026-10-v1',false,'yes'),
    (c, 'Dating C','Tamale','Intentional dating',NULL,'draft','approved','verified','GH','NP','committed',now(),'2026-10-v1',false,'yes')
  ON CONFLICT (user_id) DO UPDATE
    SET profile_state=EXCLUDED.profile_state,
        moderation_state=EXCLUDED.moderation_state,
        verification_state=EXCLUDED.verification_state;
"""),
("""  ON CONFLICT (user_id) DO UPDATE
    SET gender_preferences=EXCLUDED.gender_preferences,
        region_preferences=EXCLUDED.region_preferences,
        intention_preferences=EXCLUDED.intention_preferences;
""",
"""  ON CONFLICT (user_id) DO UPDATE
    SET gender_preferences=EXCLUDED.gender_preferences,
        region_preferences=EXCLUDED.region_preferences,
        intention_preferences=EXCLUDED.intention_preferences;

  -- Spec 2 W1d: readiness v2's encrypted identity and who-to-meet, two
  -- approved prompts and two approved photos each (before any snapshot or
  -- introduction exists, so the photo trigger invalidates nothing).
  INSERT INTO public.dating_profile_sensitive (user_id, identity_enc, seeking_enc)
  SELECT u, private.dating_field_encrypt(jsonb_build_object('identity', g, 'pools', jsonb_build_array(g))),
         private.dating_field_encrypt(jsonb_build_object('seeking', jsonb_build_array(CASE g WHEN 'man' THEN 'woman' ELSE 'man' END)))
    FROM (VALUES (a, 'man'), (b, 'woman'), (d, 'woman')) AS x(u, g);
  INSERT INTO public.dating_prompts (user_id, position, prompt_id, answer)
  SELECT u, n, CASE n WHEN 1 THEN 'perfect_sunday' ELSE 'ask_me_about' END, 'A contract fixture answer ' || n
    FROM (VALUES (a), (b), (d)) AS x(u), generate_series(1, 2) AS n;
  INSERT INTO public.dating_profile_photos (user_id, storage_key, position, moderation_state)
  SELECT u, 'dating-contract/' || u || '-' || n || '.jpg', n, 'approved'
    FROM (VALUES (a), (b), (d)) AS x(u), generate_series(1, 2) AS n;
"""),
]
for a, b in edits:
    assert s.count(a) == 1, a[:70]
    s = s.replace(a, b)
p.write_text(s)
print('dating_mode_contracts.sql: 3 edits (W1d)')
```

```python
import pathlib
p = pathlib.Path('supabase/tests/identity_foundation_contracts.sql')
s = p.read_text()
edits = [
# Section D: the five functions as Spec 2 W1d leaves them.
("""                   'public.exit_dating_mode(text)'::regprocedure,
                   'public.pause_dating_for_relationship_user(uuid)'::regprocedure,
                   'public.delete_dating_profile(text)'::regprocedure)""",
"""                   'public.exit_dating_mode(text,boolean)'::regprocedure, -- Spec 2 W1d: (text) became (text, boolean)
                   'public.pause_dating_for_relationship_user(uuid)'::regprocedure,
                   'public.resume_dating_mode(text)'::regprocedure) -- Spec 2 W1d: replaces delete_dating_profile"""),
("""     OR NOT has_function_privilege('authenticated', 'public.exit_dating_mode(text)', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.activate_dating_profile(text)', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.delete_dating_profile(text)', 'EXECUTE') THEN""",
"""     OR NOT has_function_privilege('authenticated', 'public.exit_dating_mode(text,boolean)', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.activate_dating_profile(text)', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.resume_dating_mode(text)', 'EXECUTE') THEN"""),
# Section D2: activation v2 (no checkbox; Spec 2 readiness) and exit's hard
# delete in place of delete_dating_profile.
("""--     with the flag and every gate really met (inside this file's rollback),
--     delete on a profile with a photo and preferences. Fixtures 90-91.""",
"""--     with the flag and every gate really met (inside this file's rollback),
--     Spec 2 W1d's exit (the hard delete that replaced delete_dating_profile)
--     on a profile with a photo and preferences. Fixtures 90-91."""),
("""  INSERT INTO public.dating_enrollments (user_id, state, adults_only_confirmed_at) VALUES
    (v_c, 'profile_draft', now()), (v_d, 'active', now());
  INSERT INTO public.dating_profiles (user_id, display_name, city_region_code, relationship_intention,
                                      moderation_state, profile_state) VALUES
    (v_c, 'Dating C', 'GH-AA', 'long_term', 'approved', 'draft'),
    (v_d, 'Dating D', 'GH-AA', 'long_term', 'approved', 'active');""",
"""  -- Spec 2 W1d: no checkbox; readiness v2 (place, intention and attestation,
  -- children, verified, encrypted answers, two prompts, two photos); gate 2
  -- needs Spec 1's DOB and EULA v2; gate 6 an open country.
  PERFORM set_config('app.settings.dating_field_key', 'w1-contract-dating-field-key-0123456789abcdef', true);
  PERFORM public.publish_country_config('GH', '{"dating_enabled": true}');
  UPDATE public.users SET eula_accepted_at = now(), eula_version = '2' WHERE id = v_c;
  INSERT INTO public.account_birthdates (user_id, birth_date) VALUES (v_c, DATE '1990-01-01');
  INSERT INTO public.dating_enrollments (user_id, state) VALUES
    (v_c, 'profile_draft'), (v_d, 'active');
  INSERT INTO public.dating_profiles (user_id, display_name, city_region_code, relationship_intention,
                                      moderation_state, profile_state, verification_state, country_code, region_code,
                                      intention, not_married_attested_at, attestation_version, children_have, children_want) VALUES
    (v_c, 'Dating C', 'GH-AA', 'long_term', 'approved', 'draft', 'verified', 'GH', 'AA',
     'committed', now(), '2026-10-v1', false, 'yes'),
    (v_d, 'Dating D', 'GH-AA', 'long_term', 'approved', 'active', 'unverified', 'GH', 'AA',
     'committed', now(), '2026-10-v1', false, 'yes');
  INSERT INTO public.dating_profile_sensitive (user_id, identity_enc, seeking_enc) VALUES
    (v_c, private.dating_field_encrypt('{"identity": "man", "pools": ["man"]}'),
          private.dating_field_encrypt('{"seeking": ["woman"]}'));
  INSERT INTO public.dating_prompts (user_id, position, prompt_id, answer) VALUES
    (v_c, 1, 'perfect_sunday', 'A walk and a long lunch.'), (v_c, 2, 'ask_me_about', 'My grandmother''s stories.');
  INSERT INTO public.dating_profile_photos (user_id, position, storage_key, moderation_state) VALUES
    (v_c, 1, 'w1-contract/c1.jpg', 'approved'), (v_c, 2, 'w1-contract/c2.jpg', 'approved');"""),
("""  -- 3. delete_dating_profile: photo, preferences and profile go; the
  --    enrollment is back to profile_draft.
  PERFORM pg_temp.as_user(v_d);
  BEGIN
    PERFORM public.delete_dating_profile('w1-contract-delete-0001');
    v_msg := NULL;
  EXCEPTION WHEN OTHERS THEN
    v_msg := SQLERRM;
  END;
  RESET ROLE;
  IF v_msg IS NOT NULL
     OR EXISTS (SELECT 1 FROM public.dating_profile_photos WHERE user_id = v_d)
     OR EXISTS (SELECT 1 FROM public.dating_preferences WHERE user_id = v_d)
     OR EXISTS (SELECT 1 FROM public.dating_profiles WHERE user_id = v_d)
     OR (SELECT state FROM public.dating_enrollments WHERE user_id = v_d) IS DISTINCT FROM 'profile_draft' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: delete_dating_profile gave % (enrollment %)',
      coalesce(v_msg, 'no error'), (SELECT state FROM public.dating_enrollments WHERE user_id = v_d);
  END IF;""",
"""  -- 3. Spec 2 W1d: exit_dating_mode's hard delete (delete_dating_profile is
  --    gone): photo, preferences and profile go; the enrollment is exited.
  PERFORM pg_temp.as_user(v_d);
  BEGIN
    PERFORM public.exit_dating_mode('w1-contract-delete-0001');
    v_msg := NULL;
  EXCEPTION WHEN OTHERS THEN
    v_msg := SQLERRM;
  END;
  RESET ROLE;
  IF v_msg IS NOT NULL
     OR EXISTS (SELECT 1 FROM public.dating_profile_photos WHERE user_id = v_d)
     OR EXISTS (SELECT 1 FROM public.dating_preferences WHERE user_id = v_d)
     OR EXISTS (SELECT 1 FROM public.dating_profiles WHERE user_id = v_d)
     OR (SELECT state FROM public.dating_enrollments WHERE user_id = v_d) IS DISTINCT FROM 'exited' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: exit_dating_mode gave % (enrollment %)',
      coalesce(v_msg, 'no error'), (SELECT state FROM public.dating_enrollments WHERE user_id = v_d);
  END IF;"""),
]
for a, b in edits:
    assert s.count(a) == 1, a[:70]
    s = s.replace(a, b)
p.write_text(s)
print('identity_foundation_contracts.sql: 5 edits (W1d)')
```

```bash
D=.superpowers/sdd/2026-11-06-spec2-w1
python3 -I $D/edit_dating_mode_w1d.py && python3 -I $D/edit_identity_foundation_w1d.py
for t in dating_mode_contracts identity_foundation_contracts; do
  psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/$t.sql >/dev/null 2>&1; echo "$t exit=$?"
done
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/dating_v2_identity_contracts.sql 2>&1 | grep -E 'ERROR|all held' | head -1 | sed -E 's/^psql:[^ ]* //'
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/dormancy_contracts.sql 2>&1 | grep -E 'ERROR|all held' | head -1 | sed -E 's/^psql:[^ ]* //'
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/account_deletion_contracts.sql 2>&1 | grep -E 'ERROR|all held' | head -1 | sed -E 's/^psql:[^ ]* //'
```

Expected: `dating_mode_contracts.sql: 3 edits (W1d)`, `identity_foundation_contracts.sql: 5 edits (W1d)`, `dating_mode_contracts exit=0`, `identity_foundation_contracts exit=0`, `NOTICE:  dating_v2_identity_contracts: all held`, `NOTICE:  dormancy_contracts: all held` (Spec 1's park path end to end with the new `users` trigger, R19), `NOTICE:  account_deletion_contracts: all held`.

- [ ] **Step 5: The canary's rows (and the two W1a rows that are gone)**

Create `.superpowers/sdd/2026-11-06-spec2-w1/canary_T12.sql` with exactly:

```sql
-- ---------------------------------------------------------------------
-- W1d (migration 10): the lifecycle (exit_dating_mode(text) and
-- delete_dating_profile(text) are gone; their W1a rows are removed).
-- ---------------------------------------------------------------------
INSERT INTO allowed_fn (sig, clients) VALUES
  ('dating_on_account_parked()', ''),
  ('dating_profile_complete(uuid)', ''),
  ('exit_dating_mode(text,boolean)', 'authenticated'),
  ('private.dating_exit_internal(uuid,boolean)', ''),
  ('resume_dating_mode(text)', 'authenticated');
```

```bash
D=.superpowers/sdd/2026-11-06-spec2-w1
python3 -I $D/section.py supabase/tests/dating_rls_canary.sql $D/canary_T12.sql --before '-- Checks (every batch adds its rows above this line).'
python3 -I - <<'PY'
import pathlib
p = pathlib.Path('supabase/tests/dating_rls_canary.sql')
s = p.read_text()
for line in ["  ('delete_dating_profile(text)', 'authenticated'),\n", "  ('exit_dating_mode(text)', 'authenticated'),\n"]:
    assert s.count(line) == 1
    s = s.replace(line, '')
p.write_text(s)
print('dating_rls_canary.sql: 2 rows removed')
PY
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/dating_rls_canary.sql 2>&1 | grep -E 'ERROR|all held' | head -1 | sed -E 's/^psql:[^ ]* //'
```

Expected: `dating_rls_canary.sql: canary_T12.sql before`, `dating_rls_canary.sql: 2 rows removed`, `NOTICE:  dating_rls_canary: all held`.

- [ ] **Step 6: Mutation checks (mutant 5 `generation_without_exclusion_key`, 17 `exit_keeps_sensitive`, 30 `exit_default_keeps`)**

Create `.superpowers/sdd/2026-11-06-spec2-w1/mut_T12.py` with exactly:

```python
MUTS = {
 # Mutant 17: exit keeps dating_profile_sensitive.
 'exit_keeps_sensitive': ("""  DELETE FROM public.dating_profile_sensitive AS s WHERE s.user_id = p_user;
""", ""),
 # Mutant 30: exit keeps the never-introduce list by default.
 'exit_keeps_list_always': ("""    DELETE FROM public.dating_never_introduce AS n WHERE n.owner_user_id = p_user;
""", ""),
 'exit_default_keeps': ("""CREATE OR REPLACE FUNCTION public.exit_dating_mode(p_idempotency_key text, p_keep_never_introduce boolean DEFAULT false)""", """CREATE OR REPLACE FUNCTION public.exit_dating_mode(p_idempotency_key text, p_keep_never_introduce boolean DEFAULT true)"""),
 'exit_keeps_prompts': ("""  DELETE FROM public.dating_prompts AS q WHERE q.user_id = p_user;
""", ""),
 'exit_unseals': ("""     SET state = 'closed', closed_reason = 'exit', closed_at = coalesce(m.closed_at, now()),
         evidence_until = now() + interval '30 days'""", """     SET state = 'closed', closed_reason = 'exit', closed_at = coalesce(m.closed_at, now())"""),
 'exit_keeps_intros': ("""  DELETE FROM public.dating_introductions AS i WHERE p_user IN (i.user_low_id, i.user_high_id);
""", ""),
 'exit_no_withdrawal_record': ("""  INSERT INTO public.dating_consent_events (user_id, idempotency_key, purpose, action, policy_version, occurred_at)
  SELECT v_user_id, 'exit:' || p_idempotency_key, 'dating_opt_in', 'withdrawn',""", """  INSERT INTO public.dating_consent_events (user_id, idempotency_key, purpose, action, policy_version, occurred_at)
  SELECT v_user_id, 'exit:' || p_idempotency_key, 'dating_opt_in', 'granted',"""),
 'withdrawal_not_exit': ("""  IF v_action = 'withdrawn' THEN -- Spec 2 W1d: withdrawing any consent is leaving Dating""", """  IF false THEN -- Spec 2 W1d: withdrawing any consent is leaving Dating"""),
 'old_purposes_accepted': ("""  IF p_purpose NOT IN ('dating_terms','dating_opt_in','special_category_profile', -- Spec 2 W1d""", """  IF p_purpose NOT IN ('dating_terms','dating_opt_in','special_category_profile','historical_data', -- Spec 2 W1d"""),
 'ready_one_prompt': ("""          WHERE q.user_id = p_user_id AND q.moderation_state = 'approved') >= 2;""", """          WHERE q.user_id = p_user_id AND q.moderation_state = 'approved') >= 1;"""),
 'ready_ignores_seeking': ("""       AND s.identity_enc IS NOT NULL AND s.seeking_enc IS NOT NULL)""", """       AND s.identity_enc IS NOT NULL)"""),
 'activate_skips_completeness': ("""  IF NOT public.dating_profile_complete(v_user_id) THEN -- Spec 2 W1d
    RAISE EXCEPTION 'profile_or_preferences_incomplete' USING ERRCODE='22023';
  END IF;
  IF NOT public.claim_dating_idempotency('activate_dating_profile',p_idempotency_key)""", """  IF NOT public.claim_dating_idempotency('activate_dating_profile',p_idempotency_key)"""),
 'pause_overwrites_reason': ("""    AND state IN ('active', 'profile_draft') -- Spec 2 W1d: an already-paused enrolment keeps its first reason""", """    AND state IN ('active', 'profile_draft', 'paused') -- Spec 2 W1d: an already-paused enrolment keeps its first reason"""),
 'relationship_pause_no_reason': ("""      pause_reason = CASE WHEN state = 'suspended' THEN pause_reason ELSE 'relationship' END, -- Spec 2 W1d""", ""),
 'resume_skips_eligibility': ("""  IF public.dating_eligibility(v_user_id, 'setup') <> 'eligible' THEN
    RAISE EXCEPTION 'resume_gates_not_met' USING ERRCODE = '22023';
  END IF;""", ""),
 'parked_not_paused': ("""    UPDATE public.dating_enrollments AS e
       SET state = 'paused', pause_reason = 'account_parked', paused_at = coalesce(e.paused_at, now()),
           updated_at = now()
     WHERE e.user_id = NEW.id AND e.state IN ('active', 'profile_draft');""", ""),
 'parked_carries_restrictions': ("""    PERFORM public.invalidate_dating_for_user(NEW.id, 'account_parked');""", """    PERFORM public.invalidate_dating_for_user(NEW.id, 'account_parked');
    INSERT INTO public.enforcement_records (phone_hmac, scope, source_restriction_id, restriction_type, purge_after)
    SELECT NEW.parked_phone_hmac, 'dating', d.id, d.restriction_type, now() + interval '2 years'
      FROM public.dating_account_restrictions AS d WHERE d.user_id = NEW.id AND NEW.parked_phone_hmac IS NOT NULL;"""),
 # Mutant 5: generation runs without dating_exclusion_key.
 'generation_without_exclusion_key': ("""  IF public.app_setting('dating_exclusion_key') IS NULL OR NOT private.dating_field_key_present() THEN -- Spec 2 W1d""", """  IF NOT private.dating_field_key_present() THEN -- Spec 2 W1d"""),
 'generation_without_field_key': ("""  IF public.app_setting('dating_exclusion_key') IS NULL OR NOT private.dating_field_key_present() THEN -- Spec 2 W1d""", """  IF public.app_setting('dating_exclusion_key') IS NULL THEN -- Spec 2 W1d"""),
}
```

```bash
D=.superpowers/sdd/2026-11-06-spec2-w1
python3 -I $D/mutate.py supabase/migrations/20261106190000_dating_v2_lifecycle.sql supabase/tests/dating_v2_identity_contracts.sql $D/mut_T12.py $D
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/dating_v2_identity_contracts.sql 2>&1 | grep -E 'ERROR|all held' | head -1 | sed -E 's/^psql:[^ ]* //'
```

Expected (`exit_keeps_intros` is caught by the v1 snapshot foreign key, which W5a drops with the snapshots; the contract's exit row check stands behind it):

- `exit_keeps_sensitive`: `ERROR:  CONTRACT VIOLATED: exit left Dating data behind`
- `exit_keeps_list_always`: `ERROR:  CONTRACT VIOLATED: exit kept the never-introduce list by default (R-2)`
- `exit_default_keeps`: `ERROR:  CONTRACT VIOLATED: exit kept the never-introduce list by default (R-2)`
- `exit_keeps_prompts`: `ERROR:  CONTRACT VIOLATED: exit left Dating data behind`
- `exit_unseals`: `ERROR:  CONTRACT VIOLATED: exit did not seal the conversation for the 30-day evidence window`
- `exit_keeps_intros`: `ERROR:  update or delete on table "dating_feature_snapshots" violates foreign key constraint "dating_introductions_snapshot_low_id_fkey" on table "dating_introductions"`
- `exit_no_withdrawal_record`: `ERROR:  CONTRACT VIOLATED: exit did not keep the consent record and its withdrawal, or did not queue the photos`
- `withdrawal_not_exit`: `ERROR:  CONTRACT VIOLATED: withdrawing the special-category consent did not exit and delete`
- `old_purposes_accepted`: `ERROR:  CONTRACT VIOLATED: the v1 consent purposes still exist`
- `ready_one_prompt`: `ERROR:  CONTRACT VIOLATED: a profile with one prompt activated (<NULL>)`
- `ready_ignores_seeking`: `ERROR:  CONTRACT VIOLATED: a profile with no who-to-meet answer is complete`
- `activate_skips_completeness`: `ERROR:  CONTRACT VIOLATED: a profile with one prompt activated (<NULL>)`
- `pause_overwrites_reason`: `ERROR:  CONTRACT VIOLATED: pausing again replaced the relationship reason`
- `relationship_pause_no_reason`: `ERROR:  CONTRACT VIOLATED: the relationship pause has no relationship reason`
- `resume_skips_eligibility`: `ERROR:  CONTRACT VIOLATED: resume ignored eligibility (a pending relationship): <NULL>`
- `parked_not_paused`: `ERROR:  CONTRACT VIOLATED: parking did not pause with account_parked and end the introductions`
- `parked_carries_restrictions`: `ERROR:  CONTRACT VIOLATED: parking wrote an enforcement record (built default O3: no)`
- `generation_without_exclusion_key`: `ERROR:  CONTRACT VIOLATED: generation ran without dating_exclusion_key or dating_field_key: [{"skipped": "no_active_config"}, {"skipped": "missing_key"}]`
- `generation_without_field_key`: `ERROR:  CONTRACT VIOLATED: generation ran without dating_exclusion_key or dating_field_key: [{"skipped": "missing_key"}, {"skipped": "no_active_config"}]`

then `NOTICE:  dating_v2_identity_contracts: all held`.

- [ ] **Step 7: The local harness (edit only, never run)**

`scripts/local_pg_grants.sql`: append after the last line (`\i supabase/migrations/20261106180010_dating_v2_never_introduce_grants.sql`), exactly:

```sql

-- Spec 2 W1d: the lifecycle RPCs are the signed-in app's; the hard delete,
-- readiness and the parked trigger are the database's own.
\i supabase/migrations/20261106190010_dating_v2_lifecycle_grants.sql
```

```bash
python3 -I - <<'PY'
import pathlib
p = pathlib.Path('scripts/local_pg_grants.sql')
s = p.read_text()
assert s.endswith('\\i supabase/migrations/20261106180010_dating_v2_never_introduce_grants.sql' + chr(10))
p.write_text(s + chr(10) + "-- Spec 2 W1d: the lifecycle RPCs are the signed-in app's; the hard delete,\n-- readiness and the parked trigger are the database's own." + chr(10) + '\\i supabase/migrations/20261106190010_dating_v2_lifecycle_grants.sql' + chr(10))
print('local_pg_grants.sql: one \\i block added')
PY
```

### Task 13: Migration 11: the same-gender kill switch; the W1d and W1 gate (§4.9 W1d #2, §2.2, §2.4, 10 S3; P-37)

**Files:**
- Create: `supabase/migrations/20261106200000_dating_v2_kill_switch.sql`, `…200010_dating_v2_kill_switch_grants.sql`
- Modify: `supabase/tests/country_safety_config_contracts.sql` (section E replaced), `supabase/tests/dating_rls_canary.sql`, `scripts/local_pg_grants.sql`

**Interfaces:**
- Consumes: Task 5's live `publish_country_config`; Tasks 8-9's `private.dating_field_decrypt`, `private.dating_same_gender_on`.
- Produces: `public.apply_same_gender_switch(p_country text) → integer` (NULL = every country; raises `dating:field_key_missing` without the key); `publish_country_config` turning same-gender off now publishes and switches (`"switched": true, "affected": n | null`); trigger `dating_same_gender_flag_off` on `feature_flags` (`private.dating_same_gender_flag_off()`).

- [ ] **Step 1: Save `publish_country_config`'s live body; replace section E with the kill switch**

```bash
D=.superpowers/sdd/2026-11-06-spec2-w1
psql -X -d attune_spec3a -Atc "select pg_get_functiondef('public.publish_country_config(text,jsonb)'::regprocedure)" > "$D/before/public.publish_country_config(text,jsonb).sql"
```

Create `.superpowers/sdd/2026-11-06-spec2-w1/country_E_switch.sql` with exactly:

```sql
-- =====================================================================
-- E. (W1d) The kill switch (§2.4, 10 S3): turning same-gender off for a
--    country, or the global flag off, deletes the disallowed answers,
--    pauses those people and invalidates every open introduction there
--    that isn't man-woman, in the publishing transaction; man-woman
--    people and introductions are untouched; nothing is sent.
-- =====================================================================
CREATE FUNCTION pg_temp.sg_person(p_n text, p_country text, p_identity jsonb, p_seeking jsonb) RETURNS uuid LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO auth.users (id, phone, phone_confirmed_at) VALUES (pg_temp.id(p_n), '15558701' || p_n, now());
  INSERT INTO public.users (id, phone, display_name) VALUES (pg_temp.id(p_n), '15558701' || p_n, 'SG ' || p_n);
  INSERT INTO public.dating_enrollments (user_id, state) VALUES (pg_temp.id(p_n), 'active');
  INSERT INTO public.dating_profiles (user_id, display_name, country_code, region_code, profile_state, gender_visible)
  VALUES (pg_temp.id(p_n), 'SG ' || p_n, p_country, CASE p_country WHEN 'GH' THEN 'AA' ELSE 'TLI' END, 'active', true);
  INSERT INTO public.dating_profile_sensitive (user_id, identity_enc, seeking_enc)
  VALUES (pg_temp.id(p_n), private.dating_field_encrypt(p_identity), private.dating_field_encrypt(p_seeking));
  RETURN pg_temp.id(p_n);
END $$;

CREATE FUNCTION pg_temp.intro(p_a uuid, p_b uuid) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE
  v_low uuid;
  v_high uuid;
  v_id uuid;
BEGIN
  INSERT INTO public.dating_feature_snapshots (user_id, algorithm_version) VALUES (least(p_a, p_b), 'w1d-switch') RETURNING id INTO v_low;
  INSERT INTO public.dating_feature_snapshots (user_id, algorithm_version) VALUES (greatest(p_a, p_b), 'w1d-switch') RETURNING id INTO v_high;
  INSERT INTO public.dating_introductions (pair_key, user_low_id, user_high_id, display_band, state,
                                           algorithm_version, snapshot_low_id, snapshot_high_id, internal_score)
  VALUES (public.dating_pair_key(p_a, p_b), least(p_a, p_b), greatest(p_a, p_b), 'some_shared_ground', 'presented',
          'w1d-switch', v_low, v_high, 0.5) RETURNING id INTO v_id;
  RETURN v_id;
END $$;

DO $$
DECLARE
  v_nb uuid;
  v_man uuid;
  v_woman uuid;
  v_uk_nb uuid;
  v_uk_man uuid;
  v_pronouns uuid;
  v_i_nb_woman uuid;
  v_i_man_woman uuid;
  v_i_man_uknb uuid;
  v_i_uk uuid;
  v jsonb;
  v_scheduled bigint := (SELECT count(*) FROM public.scheduled_notifications);
BEGIN
  PERFORM set_config('app.settings.dating_field_key', 'spec2-w1d-switch-field-key-0123456789abcdef', true);
  UPDATE public.feature_flags SET enabled = true WHERE key = 'dating_same_gender_matching';
  PERFORM pg_temp.publish('GH', '{"same_gender_enabled": true}');
  v_nb := pg_temp.sg_person('10', 'GH', '{"identity": "non_binary", "specific": null, "specific_text": null, "pronouns": "they/them", "pools": ["non_binary", "woman"]}',
                            '{"seeking": ["man", "non_binary", "woman"]}');
  v_man := pg_temp.sg_person('11', 'GH', '{"identity": "man", "specific": null, "specific_text": null, "pronouns": null, "pools": ["man"]}',
                             '{"seeking": ["woman"]}');
  v_woman := pg_temp.sg_person('12', 'GH', '{"identity": "woman", "specific": null, "specific_text": null, "pronouns": null, "pools": ["woman"]}',
                               '{"seeking": ["man"]}');
  v_uk_nb := pg_temp.sg_person('13', 'GB', '{"identity": "non_binary", "specific": null, "specific_text": null, "pronouns": null, "pools": ["non_binary", "woman"]}',
                               '{"seeking": ["man", "non_binary", "woman"]}');
  v_pronouns := pg_temp.sg_person('15', 'GH', '{"identity": "woman", "specific": null, "specific_text": null, "pronouns": "she/her", "pools": ["woman"]}',
                                  '{"seeking": ["man"]}');
  v_uk_man := pg_temp.sg_person('14', 'GB', '{"identity": "man", "specific": null, "specific_text": null, "pronouns": null, "pools": ["man"]}',
                                '{"seeking": ["man"]}');
  v_i_nb_woman := pg_temp.intro(v_nb, v_woman);
  v_i_man_woman := pg_temp.intro(v_man, v_woman);
  v_i_man_uknb := pg_temp.intro(v_man, v_uk_nb);
  v_i_uk := pg_temp.intro(v_uk_nb, v_uk_man);

  v := pg_temp.publish('GH', '{"same_gender_enabled": false}');
  IF (v ->> 'ok')::boolean IS NOT TRUE OR (v ->> 'switched')::boolean IS NOT TRUE OR (v ->> 'affected')::int IS DISTINCT FROM 2
     OR (pg_temp.current('GH')).same_gender_enabled THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: turning same-gender off in Ghana did not publish and switch exactly two people: %', v;
  END IF;
  IF (SELECT identity_enc IS NOT NULL OR seeking_enc IS NOT NULL FROM public.dating_profile_sensitive WHERE user_id = v_nb)
     OR (SELECT gender_visible FROM public.dating_profiles WHERE user_id = v_nb)
     OR (SELECT state || '/' || pause_reason FROM public.dating_enrollments WHERE user_id = v_nb) IS DISTINCT FROM 'paused/same_gender_switch'
     OR (SELECT identity_enc IS NOT NULL FROM public.dating_profile_sensitive WHERE user_id = v_pronouns) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the Ghana non-binary answers were not deleted with a same_gender_switch pause';
  END IF;
  IF (SELECT identity_enc IS NULL OR seeking_enc IS NULL FROM public.dating_profile_sensitive WHERE user_id = v_man)
     OR (SELECT state FROM public.dating_enrollments WHERE user_id = v_man) IS DISTINCT FROM 'active'
     OR (SELECT state FROM public.dating_enrollments WHERE user_id = v_uk_nb) IS DISTINCT FROM 'active'
     OR (SELECT identity_enc IS NULL FROM public.dating_profile_sensitive WHERE user_id = v_uk_nb) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the switch touched a man-woman person in Ghana or anyone in the UK';
  END IF;
  IF (SELECT state FROM public.dating_introductions WHERE id = v_i_nb_woman) IS DISTINCT FROM 'invalidated'
     OR (SELECT state FROM public.dating_introductions WHERE id = v_i_man_uknb) IS DISTINCT FROM 'invalidated'
     OR (SELECT state FROM public.dating_introductions WHERE id = v_i_man_woman) IS DISTINCT FROM 'presented'
     OR (SELECT state FROM public.dating_introductions WHERE id = v_i_uk) IS DISTINCT FROM 'presented' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the switch did not invalidate exactly the not-man-woman introductions touching Ghana (cross-border included)';
  END IF;
  IF (SELECT count(*) FROM public.scheduled_notifications) IS DISTINCT FROM v_scheduled THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the kill switch queued a notification';
  END IF;

  -- The global flag off: the UK too.
  UPDATE public.feature_flags SET enabled = false WHERE key = 'dating_same_gender_matching';
  IF (SELECT identity_enc IS NOT NULL FROM public.dating_profile_sensitive WHERE user_id = v_uk_nb)
     OR (SELECT seeking_enc IS NOT NULL FROM public.dating_profile_sensitive WHERE user_id = v_uk_man)
     OR (SELECT identity_enc IS NULL FROM public.dating_profile_sensitive WHERE user_id = v_uk_man)
     OR (SELECT state FROM public.dating_introductions WHERE id = v_i_uk) IS DISTINCT FROM 'invalidated' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: turning dating_same_gender_matching off did not switch every country';
  END IF;

  -- Without the key the switch is still published; the purge is reported pending.
  UPDATE public.feature_flags SET enabled = true WHERE key = 'dating_same_gender_matching';
  PERFORM set_config('app.settings.dating_field_key', '', true);
  BEGIN
    v := pg_temp.publish('GB', '{"same_gender_enabled": false}');
  EXCEPTION WHEN raise_exception THEN
    PERFORM pg_temp.as_owner();
    RAISE EXCEPTION 'CONTRACT VIOLATED: without the key, turning same-gender off raised (%)', SQLERRM;
  END;
  IF (v ->> 'ok')::boolean IS NOT TRUE OR v -> 'affected' IS DISTINCT FROM 'null'::jsonb OR (pg_temp.current('GB')).same_gender_enabled THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: without the key the UK switch was not published (purge pending): %', v;
  END IF;
  BEGIN
    UPDATE public.feature_flags SET enabled = false WHERE key = 'dating_same_gender_matching';
  EXCEPTION WHEN raise_exception THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: without the key, turning the global flag off raised (%)', SQLERRM;
  END;
  IF (SELECT enabled FROM public.feature_flags WHERE key = 'dating_same_gender_matching') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a purge that cannot run blocked turning the global flag off';
  END IF;
  PERFORM set_config('app.settings.dating_field_key', 'spec2-w1d-switch-field-key-0123456789abcdef', true);
  PERFORM pg_temp.publish('GB', '{"same_gender_enabled": true}');
END $$;
```

```bash
python3 -I .superpowers/sdd/2026-11-06-spec2-w1/section.py supabase/tests/country_safety_config_contracts.sql .superpowers/sdd/2026-11-06-spec2-w1/country_E_switch.sql --replace "-- E. Same-gender off before W1d's switch: refused, nothing published." '-- F. The effective context (§2.3) and the session row.'
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/country_safety_config_contracts.sql 2>&1 | grep -E 'ERROR|all held' | head -1 | sed -E 's/^psql:[^ ]* //'
```

Expected: `country_safety_config_contracts.sql: country_E_switch.sql replace`; `ERROR:  CONTRACT VIOLATED: turning same-gender off in Ghana did not publish and switch exactly two people: {"ok": false, "reason": "config:kill_switch_pending"}`.

- [ ] **Step 2: Write migration 11 and its twin**

Create `supabase/migrations/20261106200000_dating_v2_kill_switch.sql` with exactly:

```sql
-- Spec 2 W1d, migration 11 (spec §4.9 W1d #2, the kill switch; §2.2,
-- §2.4; 10 S3; plan P-20):
--   * apply_same_gender_switch(country) (NULL = every country): for every
--     person whose Dating country no longer allows same-gender
--     introductions (the country's switch or the global flag), the
--     disallowed answers are deleted (an identity other than woman/man, a
--     specific term, pronouns or extra pools; and who-to-meet unless it is
--     exactly the opposite single set), gender_visible goes off, and the
--     person is paused with same_gender_switch (an enrolment already paused
--     keeps its first reason); then every open introduction with a member
--     in that country that is not man-woman is invalidated (decrypted
--     inside this transaction, cross-border included). Returns the number of
--     people changed. Needs the field key (raises dating:field_key_missing
--     otherwise). Never sends anything (no push; W3a's note reads
--     pause_reason).
--   * publish_country_config re-created from its live body (W1b,
--     20261106130000): turning same_gender_enabled off now publishes and
--     runs the switch in the same transaction instead of refusing; if the
--     purge can't run (no key) the switch is still published and the answer
--     says affected: null, so the owner re-runs
--     select public.apply_same_gender_switch('<code>');
--   * The global flag: turning dating_same_gender_matching off runs the
--     switch for every country, through an AFTER UPDATE trigger on
--     public.feature_flags that fires for that one key only and never
--     blocks the flag change (a failed purge is a WARNING; re-run it).
-- Grants in 20261106200010_dating_v2_kill_switch_grants.sql.
BEGIN;
SET LOCAL lock_timeout = '5s';

CREATE OR REPLACE FUNCTION public.apply_same_gender_switch(p_country text)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_code constant text := upper(p_country);
  r record;
  v_identity jsonb;
  v_seeking jsonb;
  v_bad_identity boolean;
  v_bad_seeking boolean;
  v_count integer := 0;
BEGIN
  IF NOT private.dating_field_key_present() THEN
    RAISE EXCEPTION 'dating:field_key_missing';
  END IF;
  FOR r IN
    SELECT p.user_id, p.country_code, s.identity_enc, s.seeking_enc
      FROM public.dating_profiles AS p
      JOIN public.dating_profile_sensitive AS s ON s.user_id = p.user_id
     WHERE (v_code IS NULL OR p.country_code = v_code)
       AND p.country_code IS NOT NULL
       AND NOT private.dating_same_gender_on(p.country_code)
     ORDER BY p.user_id
       FOR UPDATE OF s
  LOOP
    v_identity := private.dating_field_decrypt(r.identity_enc);
    v_seeking := private.dating_field_decrypt(r.seeking_enc);
    v_bad_identity := v_identity IS NOT NULL
      AND (coalesce(v_identity ->> 'identity', '') NOT IN ('woman', 'man')
           OR v_identity ->> 'specific' IS NOT NULL OR v_identity ->> 'specific_text' IS NOT NULL
           OR v_identity ->> 'pronouns' IS NOT NULL
           OR v_identity -> 'pools' IS DISTINCT FROM jsonb_build_array(v_identity ->> 'identity'));
    v_bad_seeking := v_seeking IS NOT NULL
      AND (v_bad_identity OR v_identity IS NULL
           OR v_seeking -> 'seeking' IS DISTINCT FROM
              jsonb_build_array(CASE v_identity ->> 'identity' WHEN 'woman' THEN 'man' ELSE 'woman' END));
    CONTINUE WHEN NOT (v_bad_identity OR v_bad_seeking);
    UPDATE public.dating_profile_sensitive AS s
       SET identity_enc = CASE WHEN v_bad_identity THEN NULL ELSE s.identity_enc END,
           seeking_enc = NULL,
           updated_at = now()
     WHERE s.user_id = r.user_id;
    UPDATE public.dating_profiles AS p
       SET gender_visible = CASE WHEN v_bad_identity THEN false ELSE p.gender_visible END,
           profile_state = CASE WHEN p.profile_state = 'active' THEN 'paused' ELSE p.profile_state END,
           updated_at = now()
     WHERE p.user_id = r.user_id;
    UPDATE public.dating_enrollments AS e
       SET state = 'paused', pause_reason = 'same_gender_switch', paused_at = coalesce(e.paused_at, now()),
           updated_at = now()
     WHERE e.user_id = r.user_id AND e.state IN ('active', 'profile_draft');
    v_count := v_count + 1;
  END LOOP;

  -- Every open introduction touching the country that isn't man-woman.
  UPDATE public.dating_introductions AS i
     SET state = 'invalidated'
   WHERE i.state IN ('generated', 'presented', 'interested')
     AND EXISTS (SELECT 1 FROM public.dating_profiles AS p
                  WHERE p.user_id IN (i.user_low_id, i.user_high_id)
                    AND p.country_code IS NOT NULL
                    AND (v_code IS NULL OR p.country_code = v_code)
                    AND NOT private.dating_same_gender_on(p.country_code))
     AND NOT EXISTS (
       SELECT 1
         FROM public.dating_profile_sensitive AS a, public.dating_profile_sensitive AS b
        WHERE a.user_id = i.user_low_id AND b.user_id = i.user_high_id
          AND ARRAY[private.dating_field_decrypt(a.identity_enc) ->> 'identity',
                    private.dating_field_decrypt(b.identity_enc) ->> 'identity'] IN (ARRAY['woman', 'man'], ARRAY['man', 'woman']));
  RETURN v_count;
END;
$fn$;

CREATE OR REPLACE FUNCTION public.publish_country_config(p_country text, p_values jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_code constant text := upper(coalesce(p_country, ''));
  v_allowed constant text[] := ARRAY['tier', 'dating_enabled', 'open_regions', 'same_gender_enabled',
    'region_list', 'faith_list', 'id_documents', 'generation_hour_utc', 'reference_tz',
    'resources_verified_at', 'legal_checklist', 'source_url', 'reviewed_at', 'reviewed_by', 'published_by'];
  v_old public.country_safety_config;
  v_new public.country_safety_config;
  v_codes text[];
  v_checks text[];
  v_switch boolean; -- Spec 2 W1d
  v_affected integer; -- Spec 2 W1d
BEGIN
  IF v_code !~ '^[A-Z]{2}$' THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'config:invalid_country');
  END IF;
  IF jsonb_typeof(p_values) IS DISTINCT FROM 'object' THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'config:invalid_values');
  END IF;
  IF EXISTS (SELECT 1 FROM jsonb_object_keys(p_values) AS k WHERE k <> ALL (v_allowed)) THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'config:unknown_key');
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended('country_safety_config:' || v_code, 0));
  SELECT * INTO v_old FROM public.country_safety_config AS c
   WHERE c.country_code = v_code AND c.is_current FOR UPDATE;
  IF NOT FOUND THEN
    v_old := public.dating_country_config(v_code);
  END IF;

  BEGIN
    v_new := jsonb_populate_record(v_old, p_values - 'open_regions');
    IF p_values ? 'open_regions' THEN
      v_new.open_regions := CASE WHEN jsonb_typeof(p_values -> 'open_regions') = 'null' THEN NULL
                                 ELSE ARRAY(SELECT jsonb_array_elements_text(p_values -> 'open_regions')) END;
    END IF;
  EXCEPTION WHEN data_exception OR invalid_text_representation OR datatype_mismatch THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'config:invalid_values');
  END;
  v_new.country_code := v_code;
  v_new.version := v_old.version + 1;
  v_new.is_current := true;
  v_new.published_at := now();
  v_new.published_by := coalesce(nullif(btrim(p_values ->> 'published_by'), ''), 'service_role');

  IF v_new.tier IS NULL OR v_new.tier NOT BETWEEN 1 AND 3
     OR v_new.dating_enabled IS NULL OR v_new.same_gender_enabled IS NULL
     OR v_new.generation_hour_utc IS NULL OR v_new.generation_hour_utc NOT BETWEEN 0 AND 23 THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'config:invalid_values');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_timezone_names AS z WHERE z.name = v_new.reference_tz) THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'config:invalid_tz');
  END IF;
  IF jsonb_typeof(v_new.region_list) IS DISTINCT FROM 'array'
     OR jsonb_typeof(v_new.faith_list) IS DISTINCT FROM 'array'
     OR jsonb_typeof(v_new.id_documents) IS DISTINCT FROM 'array'
     OR jsonb_typeof(v_new.legal_checklist) IS DISTINCT FROM 'object'
     OR EXISTS (SELECT 1 FROM jsonb_array_elements(v_new.region_list) AS r
                 WHERE jsonb_typeof(r) <> 'object' OR coalesce(r ->> 'code', '') !~ '^[A-Z0-9]{2,3}$') THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'config:invalid_lists');
  END IF;
  v_codes := ARRAY(SELECT r ->> 'code' FROM jsonb_array_elements(v_new.region_list) AS r);
  IF cardinality(v_codes) <> (SELECT count(DISTINCT c) FROM unnest(v_codes) AS c)
     OR (v_new.open_regions IS NOT NULL AND NOT v_new.open_regions <@ v_codes) THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'config:invalid_regions');
  END IF;

  -- Same-gender off: the kill switch runs in this transaction (§2.4).
  v_switch := v_old.same_gender_enabled AND NOT v_new.same_gender_enabled; -- Spec 2 W1d

  v_checks := private.country_config_checks(v_new);
  IF cardinality(v_checks) > 0 AND private.attune_environment() = 'production' THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'config:production_checks_failed',
                              'checks', to_jsonb(v_checks));
  END IF;

  UPDATE public.country_safety_config AS c SET is_current = false
   WHERE c.country_code = v_code AND c.is_current;
  INSERT INTO public.country_safety_config SELECT v_new.*;
  IF v_switch THEN -- Spec 2 W1d
    BEGIN -- Spec 2 W1d: the switch is published even if the purge can't run (no key); re-run it then
      v_affected := public.apply_same_gender_switch(v_code); -- Spec 2 W1d
    EXCEPTION WHEN raise_exception THEN -- Spec 2 W1d
      v_affected := NULL; -- Spec 2 W1d
    END; -- Spec 2 W1d
  END IF; -- Spec 2 W1d
  RETURN jsonb_build_object('ok', true, 'country', v_code, 'version', v_new.version,
                            'dating_enabled', v_new.dating_enabled,
                            'same_gender_enabled', v_new.same_gender_enabled,
                            'environment', private.attune_environment(),
                            'checks', to_jsonb(v_checks))
         || CASE WHEN v_switch THEN jsonb_build_object('switched', true, 'affected', v_affected) -- Spec 2 W1d
                 ELSE '{}'::jsonb END; -- Spec 2 W1d
END;
$function$;

-- The global flag off is the kill switch everywhere (§2.4).
CREATE OR REPLACE FUNCTION private.dating_same_gender_flag_off()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
BEGIN
  BEGIN
    PERFORM public.apply_same_gender_switch(NULL);
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'dating_same_gender_flag_off:%; re-run select public.apply_same_gender_switch(NULL);', SQLSTATE;
  END;
  RETURN NULL;
END;
$fn$;
DROP TRIGGER IF EXISTS dating_same_gender_flag_off ON public.feature_flags;
CREATE TRIGGER dating_same_gender_flag_off
  AFTER UPDATE OF enabled ON public.feature_flags
  FOR EACH ROW
  WHEN (NEW.key = 'dating_same_gender_matching' AND OLD.enabled AND NOT NEW.enabled)
  EXECUTE FUNCTION private.dating_same_gender_flag_off();

REVOKE ALL ON FUNCTION public.apply_same_gender_switch(text), private.dating_same_gender_flag_off()
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.publish_country_config(text, jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.publish_country_config(text, jsonb) TO service_role;

COMMIT;
```

Create `supabase/migrations/20261106200010_dating_v2_kill_switch_grants.sql` with exactly:

```sql
-- Spec 2 W1d: grants for 20261106200000_dating_v2_kill_switch.sql. The
-- switch and its flag trigger are the database's own (they decrypt);
-- publishing stays the service role's.
BEGIN;
SET LOCAL lock_timeout = '5s';
REVOKE ALL ON FUNCTION public.apply_same_gender_switch(text), private.dating_same_gender_flag_off()
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.publish_country_config(text, jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.publish_country_config(text, jsonb) TO service_role;
COMMIT;
```

- [ ] **Step 3: Apply each file twice; diff the publisher; run the contract**

```bash
for i in 1 2; do
  for f in 20261106200000_dating_v2_kill_switch 20261106200010_dating_v2_kill_switch_grants; do
    psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/migrations/$f.sql > /dev/null 2>&1; echo "$f exit=$?"
  done
done
```

```bash
D=.superpowers/sdd/2026-11-06-spec2-w1
for sig in 'public.publish_country_config(text,jsonb)'; do
  echo "== $sig"
  diff "$D/before/$sig.sql" <(psql -X -d attune_spec3a -Atc "select pg_get_functiondef('$sig'::regprocedure)") | grep '^[<>]'
done
```

```bash
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/country_safety_config_contracts.sql 2>&1 | grep -E 'ERROR|all held' | head -1 | sed -E 's/^psql:[^ ]* //'
```

Expected: four `exit=0` lines; then exactly:

```text
== public.publish_country_config(text,jsonb)
>   v_switch boolean; -- Spec 2 W1d
>   v_affected integer; -- Spec 2 W1d
<   -- Same-gender off: the purge (apply_same_gender_switch) arrives in W1d.
<   IF v_old.same_gender_enabled AND NOT v_new.same_gender_enabled THEN
<     RETURN jsonb_build_object('ok', false, 'reason', 'config:kill_switch_pending');
<   END IF;
>   -- Same-gender off: the kill switch runs in this transaction (§2.4).
>   v_switch := v_old.same_gender_enabled AND NOT v_new.same_gender_enabled; -- Spec 2 W1d
>   IF v_switch THEN -- Spec 2 W1d
>     BEGIN -- Spec 2 W1d: the switch is published even if the purge can't run (no key); re-run it then
>       v_affected := public.apply_same_gender_switch(v_code); -- Spec 2 W1d
>     EXCEPTION WHEN raise_exception THEN -- Spec 2 W1d
>       v_affected := NULL; -- Spec 2 W1d
>     END; -- Spec 2 W1d
>   END IF; -- Spec 2 W1d
<                             'checks', to_jsonb(v_checks));
>                             'checks', to_jsonb(v_checks))
>          || CASE WHEN v_switch THEN jsonb_build_object('switched', true, 'affected', v_affected) -- Spec 2 W1d
>                  ELSE '{}'::jsonb END; -- Spec 2 W1d
```

then `NOTICE:  country_safety_config_contracts: all held` (the run prints one `WARNING:  dating_same_gender_flag_off:P0001; re-run …` from the no-key case, as designed).

- [ ] **Step 4: The canary's rows for this migration**

Create `.superpowers/sdd/2026-11-06-spec2-w1/canary_T13.sql` with exactly:

```sql
-- ---------------------------------------------------------------------
-- W1d (migration 11): the kill switch.
-- ---------------------------------------------------------------------
INSERT INTO allowed_fn (sig, clients) VALUES
  ('apply_same_gender_switch(text)', ''),
  ('private.dating_same_gender_flag_off()', '');
```

```bash
D=.superpowers/sdd/2026-11-06-spec2-w1
python3 -I $D/section.py supabase/tests/dating_rls_canary.sql $D/canary_T13.sql --before '-- Checks (every batch adds its rows above this line).'
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/dating_rls_canary.sql 2>&1 | grep -E 'ERROR|all held' | head -1 | sed -E 's/^psql:[^ ]* //'
```

Expected: `dating_rls_canary.sql: canary_T13.sql before`, then `NOTICE:  dating_rls_canary: all held` (before this step, with the migration applied, the canary names every new object as `not in the canary's allow-list`).

- [ ] **Step 5: Mutation checks**

Create `.superpowers/sdd/2026-11-06-spec2-w1/mut_T13.py` with exactly:

```python
MUTS = {
 'switch_not_run': ("""      v_affected := public.apply_same_gender_switch(v_code); -- Spec 2 W1d""", """      v_affected := 0; -- Spec 2 W1d"""),
 'switch_blocks_publish_without_key': ("""    EXCEPTION WHEN raise_exception THEN -- Spec 2 W1d
      v_affected := NULL; -- Spec 2 W1d""", """    EXCEPTION WHEN division_by_zero THEN -- Spec 2 W1d
      v_affected := NULL; -- Spec 2 W1d"""),
 'switch_any_country': ("""     WHERE (v_code IS NULL OR p.country_code = v_code)
       AND p.country_code IS NOT NULL
       AND NOT private.dating_same_gender_on(p.country_code)""", """     WHERE p.country_code IS NOT NULL"""),
 'switch_keeps_pronouns': ("""           OR v_identity ->> 'pronouns' IS NOT NULL
""", ""),
 'switch_keeps_seeking': ("""           seeking_enc = NULL,""", """           seeking_enc = s.seeking_enc,"""),
 'switch_no_pause': ("""    UPDATE public.dating_enrollments AS e
       SET state = 'paused', pause_reason = 'same_gender_switch', paused_at = coalesce(e.paused_at, now()),
           updated_at = now()
     WHERE e.user_id = r.user_id AND e.state IN ('active', 'profile_draft');""", ""),
 'switch_misses_cross_border': ("""                  WHERE p.user_id IN (i.user_low_id, i.user_high_id)""", """                  WHERE p.user_id = i.user_high_id"""),
 'switch_ends_man_woman_too': ("""IN (ARRAY['woman', 'man'], ARRAY['man', 'woman']));""", """IN (ARRAY['nobody', 'nobody']));"""),
 'flag_off_no_switch': ("""    PERFORM public.apply_same_gender_switch(NULL);""", """    NULL;"""),
 'flag_off_blocks_without_key': ("""  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'dating_same_gender_flag_off:%; re-run select public.apply_same_gender_switch(NULL);', SQLSTATE;
  END;""", """  EXCEPTION WHEN division_by_zero THEN
    NULL;
  END;"""),
}
```

```bash
D=.superpowers/sdd/2026-11-06-spec2-w1
python3 -I $D/mutate.py supabase/migrations/20261106200000_dating_v2_kill_switch.sql supabase/tests/country_safety_config_contracts.sql $D/mut_T13.py $D
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/country_safety_config_contracts.sql 2>&1 | grep -E 'ERROR|all held' | head -1 | sed -E 's/^psql:[^ ]* //'
```

Expected:

- `switch_not_run`: `ERROR:  CONTRACT VIOLATED: turning same-gender off in Ghana did not publish and switch exactly two people: {"ok": true, "checks": ["evidence_missing", "resources_not_veri`
- `switch_blocks_publish_without_key`: `ERROR:  CONTRACT VIOLATED: without the key, turning same-gender off raised (dating:field_key_missing)`
- `switch_any_country`: `ERROR:  CONTRACT VIOLATED: turning same-gender off in Ghana did not publish and switch exactly two people: {"ok": true, "checks": ["evidence_missing", "resources_not_veri`
- `switch_keeps_pronouns`: `ERROR:  CONTRACT VIOLATED: turning same-gender off in Ghana did not publish and switch exactly two people: {"ok": true, "checks": ["evidence_missing", "resources_not_veri`
- `switch_keeps_seeking`: `ERROR:  CONTRACT VIOLATED: the Ghana non-binary answers were not deleted with a same_gender_switch pause`
- `switch_no_pause`: `ERROR:  CONTRACT VIOLATED: the Ghana non-binary answers were not deleted with a same_gender_switch pause`
- `switch_misses_cross_border`: `ERROR:  CONTRACT VIOLATED: the switch did not invalidate exactly the not-man-woman introductions touching Ghana (cross-border included)`
- `switch_ends_man_woman_too`: `ERROR:  CONTRACT VIOLATED: the switch did not invalidate exactly the not-man-woman introductions touching Ghana (cross-border included)`
- `flag_off_no_switch`: `ERROR:  CONTRACT VIOLATED: turning dating_same_gender_matching off did not switch every country`
- `flag_off_blocks_without_key`: `ERROR:  CONTRACT VIOLATED: without the key, turning the global flag off raised (dating:field_key_missing)`

then `NOTICE:  country_safety_config_contracts: all held`.

- [ ] **Step 6: The local harness (edit only, never run)**

`scripts/local_pg_grants.sql`: append after the last line (`\i supabase/migrations/20261106190010_dating_v2_lifecycle_grants.sql`), exactly:

```sql

-- Spec 2 W1d: the kill switch and its flag trigger are the database's own;
-- publishing stays the service role's.
\i supabase/migrations/20261106200010_dating_v2_kill_switch_grants.sql
```

```bash
python3 -I - <<'PY'
import pathlib
p = pathlib.Path('scripts/local_pg_grants.sql')
s = p.read_text()
assert s.endswith('\\i supabase/migrations/20261106190010_dating_v2_lifecycle_grants.sql' + chr(10))
p.write_text(s + chr(10) + "-- Spec 2 W1d: the kill switch and its flag trigger are the database's own;\n-- publishing stays the service role's." + chr(10) + '\\i supabase/migrations/20261106200010_dating_v2_kill_switch_grants.sql' + chr(10))
print('local_pg_grants.sql: one \\i block added')
PY
```

- [ ] **Step 7: Run tests (the W1d gate, which closes W1)**

```bash
D=.superpowers/sdd/2026-11-06-spec2-w1
for f in supabase/tests/*.sql; do
  if psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f "$f" >/dev/null 2>&1; then echo "PASS $(basename "$f")"; else echo "FAIL $(basename "$f")"; fi
done > $D/sql-after-task13.txt
grep '^FAIL' $D/sql-after-task13.txt | sort | comm -13 <(cat $D/sql-baseline*.txt | grep '^FAIL' | sort -u) - | grep -vE 'FAIL ai_(session|assist|assistant|processing)_'
grep '^FAIL' $D/sql-after-task13.txt | sort | comm -13 <(cat $D/sql-baseline*.txt | grep '^FAIL' | sort -u) - | grep -E 'FAIL ai_' | sed 's/^FAIL //' | while read t; do
  echo "$t: $(psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/$t 2>&1 | grep -m1 ERROR | grep -ci dating) Dating mentions"
done
git status --short -- lib test | head
sed -n '/if (isAuthenticated \&\& !_gateData.isComplete) {/,/_redirectingToOnboarding = false;/p' lib/home/home_screen.dart | shasum | diff - $D/latch.sha && echo latch-unchanged
flutter test test/architecture/games_untouched_test.dart 2>&1 | tail -1
```

```bash
for t in dating_v2_identity_contracts dating_v2_setup_contracts dating_v2_eligibility_contracts country_safety_config_contracts dating_rls_canary storage_bucket_policies dating_mode_contracts dating_exclusion_wiring_test dating_alignment_contracts identity_foundation_contracts account_deletion_contracts dormancy_contracts service_role_grants_test healing_ai_pause_contracts; do
  grep -q "^PASS $t.sql" .superpowers/sdd/2026-11-06-spec2-w1/sql-after-task13.txt && echo "PASS $t" || echo "FAIL $t"
done
ls supabase/migrations | grep -c '^20261106'
grep -c '20261106' scripts/local_pg_grants.sql
```

Expected: as Task 4 Step 7 against `$D/sql-after-task13.txt`; fourteen `PASS` lines; `22`; `11`.

## Owner deploy checklist (the plan never runs any of this)

1. **Order.** Spec 1 is deployed first. Then, in one `supabase db push`: the twenty-two files `20261106100000` … `20261106200010` in order. Nothing in the app changes, so there is no build to ship with it. On a hosted project, `20261106100000` prints a NOTICE if `dating_exclusion_key` isn't set (exclusions not recomputed; item 2).
2. **`dating_exclusion_key` (Vault).** If it isn't set on a project yet (its health field says so), set it now rather than at the W5 gate: without it no exclusion, block pair or never-introduce entry can be keyed, and a deletion with a live Dating restriction is refused (`deletion:enforcement_key_missing`, by design). `select vault.create_secret('<48+ random characters from a password manager>', 'dating_exclusion_key');`, then `select public.backfill_dating_former_partner_exclusions();` (recomputes every ended or archived relationship from Auth's numbers), `select private.seed_dating_exclusion_key_fingerprint();` (→ `ready`; batch-5 fix round 1, M-4, I-1: required before anyone is Dating-eligible) and `select private.dating_stamp_restriction_hmacs();` (batch-3 fix round 1, I-1: stamps each Dating restriction placed while the key was missing with the HMAC of its account's number now; → the count, `-1` if the key is still missing). A restriction without a stamp carries nothing at deletion (`dating.deletion.uncarried`). Run the stamping before Dating opens anywhere (W1 final ruling on batch 3 N-M1: the stamp uses the number held when it runs). **While the key is missing on a project with live Dating restrictions, those people's account deletions are refused** (`deletion:enforcement_key_missing`; `get_dating_operational_health() ->> 'deletions_refused_key_missing_7d'` counts the app's refusals) until it is restored: restore it within days (erasure must complete within a month). Any other failure to carry is counted (`dating.deletion.prepare_carry_failed`, `dating.deletion.late_carry_failed` in `safety_counters_7d`) and never refuses the deletion (W1 final fix, M-4, PF-F6).
3. **`dating_field_key` (Vault; W1 gate).** 32 random bytes, base64 (44 characters), never reused: `select vault.create_secret('<base64 of 32 random bytes>', 'dating_field_key');`. Check: `select public.get_dating_operational_health() ->> 'field_key_present';` → `true`. Keep an offline copy under the owner's control: losing it makes every encrypted answer unreadable (people re-enter D5, D6, D8; rotation, `dating_field_key_v2`, is a later wave). Then seed its fingerprint (item 15).
4. **Right after the push (SQL editor), each project:**
   - `select public.get_dating_operational_health() -> 'log_settings_safe', public.get_dating_operational_health() ->> 'environment';` → `true` and `development` on the development project. **On the production project `log_settings_safe` must read `true` (W1 gate)**; if not, set `log_statement` to `none` or `ddl` and `log_parameter_max_length_on_error` to `0` in the project's database settings, and recheck.
   - `select private.dating_open_countries(), (select count(*) from public.country_safety_config where is_current and dating_enabled);` → `{}` and `0` (every seed closed); `select count(*) from public.app_public_config where key = 'dating_open_countries';` → `0`.
   - `select has_function_privilege('anon','public.get_dating_availability()','EXECUTE'), has_function_privilege('authenticated','public.publish_country_config(text,jsonb)','EXECUTE'), has_table_privilege('service_role','public.dating_matches','SELECT'), has_table_privilege('service_role','public.dating_profile_sensitive','SELECT'), has_function_privilege('service_role','public.get_my_dating_profile()','EXECUTE');` → `t | f | f | f | f`.
   - `select flag_key from private.flag_production_gates where flag_key like 'dating%' order by 1;` → the six Dating flags.
   - `select has_table_privilege('service_role','public.country_safety_config','SELECT'), has_table_privilege('service_role','public.country_safety_config','INSERT');` → `t | f` (batch-4 fix round 1, C-1: only `publish_country_config` writes the table).
   - **Development only:** run `supabase/sql/dev_enable_spec2_dating_flags.sql` in the SQL editor (it refuses anywhere else) **straight after the push** (batch-4 review M-10: until it runs, every country is closed, so the Welcome preview shows no countries line and the Me slot shows Dating as closed). Then `select public.get_public_app_config() -> 'config' -> 'dating_open_countries';` → `["GB", "GH"]` (the Welcome preview, the A6 card and the Me slot follow, R18). Re-run it after any migration replay (R10).
5. **Counsel (W1 gate).** Sign: the 2-year retention of enforcement records and block pairs after deletion (Q5; Ghana and the UK); the consent-event minimum kept after exit (built: the account's life + 1 year after exit); the three Q17 exceptions as stated on the Leave screen (sealed conversations 30 days; the never-introduce list only if ticked, unticked by default; consent events kept); and the privacy-policy line naming what survives deletion (enforcement records, block pairs, pseudonymised (HMAC) reports; 2 years). Record each in `lib/architecture/DATING_MODE_DPIA.md` §7.
6. **The DPIA.** `lib/architecture/DATING_MODE_DPIA.md` is the started draft (§6.8): the safety owner keeps it current per wave; W10 needs it signed.
7. **CI.** The first run of the new `repo-guards` job scans the whole history; run the scan of item 12 before that push, and handle a finding as item 12 says (a real secret is rotated at its provider first; a test fixture is allowlisted by its exact line in `.gitleaks.toml`). The `Nothing sets attune_environment` step must stay green; only the owner ever sets production mode, at launch.
8. **Development notes.** From migration 10 the v1 Dating screens in the development app can't set up, activate or delete a profile (P-2, PF-F15); that is expected until W3. Dating stays off in production (every Dating flag is off there and now carries a production gate row).
9. **Carried production gates.** `dating_profile_photos` can't go on in production until W3c's `process-dating-photo` runs the inline CSAM match first (S1 W7 PF-H2; its gate row says so). The hold-kind (W3c), mid-session device block (W4a), D8 provider resets (W3a) and the PF-C9 normaliser rule (W6b) are carried in "Carried items".
10. **Owner decisions.** Owner questions 1 and 2 were ruled on 2026-11-06 and are built (the switch closes matches that aren't man-woman, `other`, sealed 30 days; a faith-only withdrawal clears only the faith answer). Still to nod: question 3's four nods (P-13, P-14, P-22, P-2).
11. **`dating_exclusion_key` is never rotated, and never replaced (batch 2 I-5; W1 final fix, I-3).** Every exclusion, block pair, enforcement record, report HMAC, **never-introduce entry and restriction stamp** is keyed by it, and most can't be re-keyed: a never-introduce list stores only the HMAC of the typed number (and its last two digits), a restriction stamp only the HMAC of the number it was placed under, and a deleted number's carried rows only its HMAC. A new key would silently void every list (someone who listed an abuser's number could be introduced to them again, while their list still shows the label and the last two digits) and every live restriction's stamp. So:
    - Never delete or replace the Vault secret, never re-HMAC rows under a new key, and never delete its fingerprint row.
    - Rotation becomes possible only in a later wave that adds a **verify-only secondary key** (`dating_exclusion_key_previous`, a dual-HMAC check): every reader (never-introduce, standing, block pairs, former-partner exclusions, the deletion carry) matches either HMAC, new rows are written under the new key only, and the old key is retired only when nothing keyed by it remains (lists re-entered by their owners through W5c's screen, records past their 2-year purge). Until that wave ships there is no rotation procedure.
    - **A compromised key is an incident, not a rotation.** The safety owner and counsel assess it as a personal-data breach within 72 hours (UK/EU GDPR Art. 33; Ghana DPC); revoke whatever exposed it (rotate the database and service-role credentials that can read Vault, review who had SQL access); keep the key in place (replacing it would void the protections above); record the incident and the decision in `lib/architecture/DATING_MODE_DPIA.md` §7; and schedule the dual-key wave as the remedy.
    - Until the fingerprint matches the live key, enrolment, activation and generation refuse quietly and `dating.exclusion_key.mismatch` counts each refusal; watch that counter (a non-zero value means the secret was changed: put the original back). A deletion never stores the fingerprint (batch-3 M-7); at the delete it counts `dating.exclusion_key.mismatch` (a stored fingerprint that differs) or `dating.exclusion_key.unseeded` (none stored) for an account with a Dating footprint, and never refuses. After first setting the key (item 2), run `select private.seed_dating_exclusion_key_fingerprint();` once (→ `ready`; batch-5 fix round 1, M-4: no user RPC seeds it any more, and until it is seeded enrolment, activation and generation refuse, and `dating_eligibility` answers `feature_unavailable` for everyone, counted as `dating.eligibility.key_not_ready`); `dating.exclusion_key.unseeded` above 0 means that was missed.
12. **Secret scan, before the first push that carries `repo-guards`** (batch 2). Run `gitleaks detect --source . --redact -v` (8.18.4) once over the whole history. A test-fixture hit goes into `.gitleaks.toml`'s allowlist as its exact line (never a path or a broad pattern); a real hit is rotated at its provider first. Commit `.gitleaks.toml`, then make `repo-guards` a required status check on `main`.
13. **Counsel: marital history (batch-6 fix round 1, I-4).** The owner ruled (provisional) that marital history is not GDPR / UK GDPR Art. 9 special-category data: D2 collects it before D4's special-category consent, on the contract basis, and it stays encrypted in `dating_profile_sensitive` as defence in depth. Counsel confirms this per country (Ghana Act 843 included) and records it in `lib/architecture/DATING_MODE_DPIA.md` §7; if counsel disagrees, move "Married before?" after D4 and require `special_category_profile` in `save_dating_intention` before launch. Spec §6.8 still lists it as special category until then.
14. **A typed never-introduce number is never logged (batch-9 fix round 1, M-6).** The SQL never logs, raises or counts it. On each project, confirm that `log_min_duration_statement`, `log_parameter_max_length`, `log_parameter_max_length_on_error` and pgaudit (if enabled) cannot capture RPC parameters for the `authenticator` role. W5c (client) calls `add_dating_never_introduce` by POST only (never `get: true`, so the number is never in a gateway URL log) and keeps its arguments out of client error reports, analytics and breadcrumbs; no edge function receives or logs it.

15. **`dating_field_key`'s fingerprint (batch-6 M-5, W1d).** Right after setting the key (item 3): `select private.seed_dating_field_key_fingerprint();` → `ready` (migration 10 seeds it itself if the key was already in Vault at the push; `missing_key` means the key isn't readable). The secret must have no surrounding whitespace (production reads it trimmed). A Vault key is held to its fingerprint in development too (batch-10 fix round 1, M-1). Until it is seeded, in production every special-category writer answers `unavailable`, activation refuses quietly and generation skips (`dating.field_key.missing` / `.mismatch` count it); `get_dating_operational_health() ->> 'field_key_fingerprint_ok'` must read `true`. The key is never replaced in place: a replaced value is refused everywhere (`dating.field_key.mismatch`, `field_key_fingerprint_ok = false`); a real rotation re-encrypts every value first, then `delete from private.dating_key_fingerprints where name = 'dating_field_key'; select private.seed_dating_field_key_fingerprint();`. From migration 11, production also refuses to open or widen a country until this fingerprint matches (`field_key_not_ready`, batch-10 carry), exactly as for the exclusion key (`exclusion_key_not_ready`).
16. **The kill switch (W1d, migration 11; owner ruling 1).** Turning `same_gender_enabled` off for a country (`publish_country_config`) or `dating_same_gender_matching` off (or deleting, renaming or truncating that flag's row) strips the disallowed answers (pronouns, a specific term, extra pools: a woman/man identity is kept as the plain base; any other identity and a who-to-meet that no longer fits are deleted), pauses those people (`same_gender_switch`), takes the country out of not-plain people's other-countries lists, invalidates the introductions there that aren't known to be man-woman and closes such active matches (`other`, sealed 30 days); a pair where either member has no stored or readable identity counts as not man-woman (batch-11 fix round 1, I-3: so a man-woman match where one member moved country and hasn't re-answered closes too). Nobody is notified. **Do it from the SQL editor** (no statement timeout), never through the API or the Table Editor: a statement timeout or a cancel during a large switch aborts the whole change, so the flag or the country stays on (batch-11 M-3; the W10 drill rehearses it). Dating writers for people in the switched country wait for it (every writer takes the person's same-gender locks shared before any row; W1 final fix, I-1), and a lock conflict across a border is retried on both sides, so nobody's pause, exit or withdrawal is lost (`scripts/concurrency/dating_kill_switch_races.sh`). It never blocks the change: a deadlock or lock timeout is retried three times; if the purge still can't run (no field key, a replaced key, a lock conflict that persists), the switch is still published, the answer says `"affected": null` with `"pending_sqlstate"` (the flag change prints a WARNING), and a pending row is recorded for the country (or `*` for the flag). Then fix the cause (items 3, 15: `dating:field_key_missing` means no key, `dating:field_key_not_ready` a replaced or unseeded one) and run `select public.apply_same_gender_switch('<code>');` (or `(NULL)` for the global flag) in the SQL editor; it answers the number of people changed. **`get_dating_operational_health() -> 'kill_switch_pending'` must read `[]` after the re-run** (it lists every scope still pending, with its first failure and SQLSTATE, for as long as it is pending); `safety_counters_7d -> 'dating.kill_switch.pending'` is a 7-day history of failures only and never goes down. `dating.kill_switch.unreadable` above 0 means stored answers the live key couldn't read (those people were paused and those answers deleted). An exposure-reducing publish (closing, narrowing the regions, a stricter tier, same-gender off, an ID document removed; nothing widened and no ID document added) is never refused in production for lapsed evidence, a key that isn't ready or a missing calling code: read the `checks` it returns and fix them afterwards (PF-F1, batch-5 M-3). A combined publish that also widens anything or adds an ID document is held to every check: split it.
17. **Spec amendments to sign (owner-visible).** Each changes what the spec says, and none is in `docs/superpowers/specs/2026-10-24-dating-mode-design.md` yet (only the "pseudonymised" lines, the faith-withdrawal lines and the W1 final I-3/M-10 key and residual lines are): once the owner signs, the controller applies each tagged edit. Each line names its cost:
    - **§4.9 W1a #3, §3.8, §6.3 step 1, §1.3 Q5 (batch-3 fix round 1, I-1):** a restriction carries at deletion under the phone HMAC stamped when it was placed (a former-partner exclusion: at the relationship's end), never the number held at deletion time, so a restricted person who moves their account onto a victim's number can't get the victim suspended; text in `batch-3-report.md` "Spec amendment for the owner". *Cost:* a restricted person who later changes number isn't followed onto the new one, and their old number, if a carrier recycles it, carries the record to its next holder (DPIA §2, M-10).
    - **§4.2 (batch-6):** the stored value is a version byte (`\x01`) followed by the `pgp_sym_encrypt` message (MDC on, `sess-key=1`, SHA-256 S2K), not the raw message; production reads the field key from Vault only. *Cost:* none for people; one byte per value, and a key kept only in a database setting stops working in production.
    - **§3.12 and the 10 S5 row (batch-9 fix round 1, I-1):** adding a never-introduce number changes nothing the adder can see straight away; the listed person sees an open introduction end at the next run, as a pass; the pair can never match (replacement text in `batch-9-report.md` fix round 1). Needs DV specialist review of the copy. *Cost:* the adder keeps seeing an open introduction with the person they listed until they pass on it or it expires.
    - **§4.4 device-check and eligibility exceptions (batch-7, 8, 9, 10 rulings):** removing or reducing your own data never needs a device check or setup eligibility: the faith Skip, clearing the family answer, closing other countries, pushes off, photos-after-mutual on, adding to the never-introduce list, pause, exit and consent withdrawals. *Cost:* anyone holding the signed-in phone can pause, leave or withdraw a consent (which hard-deletes the Dating profile) with no device re-check: nothing is exposed, but the person's Dating data is destroyed.
    - **§6.8:** marital history is not special-category (item 13, counsel). *Cost if counsel disagrees:* D2 moves after D4 and `save_dating_intention` needs `special_category_profile` before launch.
    - **§2.2 (batch-4 M-2, a question):** whether a Tier 3 country may open with an empty region list; built as refused (`open_regions` `{}`). *Cost:* the owner lists a Tier 3 country's regions to open it everywhere (`open_regions` NULL means every listed region).
    - **§2.2 / PF-F1 (batch-5 M-3):** the production checks don't apply to an exposure-reducing publish (item 16). *Cost:* a reduction goes live with lapsed evidence (the checks are returned and fixed afterwards).
    - **§2.4, the kill switch (owner ruling 1, 2026-11-06, PF-F2; batch-11 fix round 1, I-3; W1 final fix, M-2):** the switch also closes every active match touching the country that isn't known to be man-woman (`other`, sealed 30 days; nobody told), and a missing or unreadable identity is never man-woman; moving one's Dating country into a same-gender-off country gives the mover's pairs the same treatment and pauses the mover as the switch would. *Cost:* the people in such a match lose their conversation without notice, and a man-woman match where one member moved country and hasn't re-answered D5 is closed by a switch (fail-safe; the fix is carried to W5a/W6a).
    - **§2.2, Ghana's first regions (P-14):** the spec's `{GA, AH}` are built as the ISO 3166-2 codes `{AA, AH}` (Greater Accra, Ashanti). *Cost:* none; the spec text changes to the ISO codes.
    - **§4.4 / §4.9 W1d, the lock order (W1 final fix, I-1, M-3):** every Dating writer takes the person's same-gender locks (their country and other countries, shared) with the setup lock before any row, and a lock conflict with a running switch is retried three times, then answers `dating:busy` with the original SQLSTATE (40P01, 55P03 or 40001; W3a's client retries it once, silently). *Cost:* while a whole-country switch runs, Dating writers for people there wait for it; a long switch can let the API's statement timeout cancel them (the person taps again).
18. **Never-introduce list (batch 9).** Review the 108-row trunk-0 table (`private.dating_phone_trunk_rules`: which calling codes drop a trunk 0 written after the country code) for every country you open: a gap answers "Check the number", never "Added." with an unmatchable entry. Nod the built limits: a Dating profile (any state) is needed to add; at most 50 numbers and 60 adds a day; a label with 5 or more digits (any script) is refused.
19. **Content filter term lists (batch 7).** The pronoun, specific-term and display-name screening calls `private.content_filter_verdict`, whose reviewed term lists are empty on the local database: load and review the production lists before Dating opens anywhere.
20. **Not W1 (found at the W1 gates; owner fixes).** `supabase/tests/together_rituals_contracts.sql` fixes `p_now` but its anchor date defaults to `CURRENT_DATE`, so it fails from 2026-11-07: pin the anchor date. `test/features/planning/planning_recent_test.dart` ("Recent sits above the categories…") fails between 00:00 and about 03:00 because two plans read "Yesterday": pin its clock.
21. **The edited Spec 1 twin and the local harness (W1 final fix, I-2).** `20261025100010_identity_users_lockdown_grants.sql` (already applied on hosted projects) now re-asserts `exit_dating_mode(text)` and `delete_dating_profile(text)` only while they exist (a `to_regprocedure` check), as does `20261106110010`; `db push` never re-runs an applied migration and a first apply grants exactly as before, so hosted is unchanged, and `scripts/local_pg_setup.sh` builds again (the twins replay cleanly after migration 10). Rebuild the local `attune_test` with it once to confirm. **Concurrency:** `scripts/concurrency/dating_kill_switch_races.sh <scratch_db>` races pause, a withdrawal, exit and a country change against the switch, in one country and across a border; run it on a throwaway copy (never `attune_test` or `attune_spec3a`: it installs delay triggers and test keys) before W3a ships the pause and leave buttons.

## Spec coverage (self-review)

| Spec item | Where |
|---|---|
| Header: Spec 1 dependencies by name (S1 W1a-c, W2b, W3, W6a, W7b, W9a) | "Interfaces consumed" (read from the live database); P-9, P-19, P-32 for the three Spec 1 contracts W1 amends |
| Header repo rules: local SQL only on `attune_spec3a`, twins, atomic and replay-safe, live bodies, environment never set | Global Constraints; every task's apply-twice and diff steps; Task 7's CI guard |
| §1.3 Q4/Q5 (survivors by HMAC from `auth.users`, 2 years), Q12 (ex-exclusion mandatory), Q13 (attestation), Q16, Q17 + exceptions, Q19/Q19b | Tasks 2-4 (HMAC, survivors, carry-over), Task 9 (attestation), Task 12 (exit and the three exceptions), Tasks 5 and 7 (development on, production gated) |
| §2.1 `dating_eligibility` gates 1-4, 6 (I-14), setup vs candidate scope | Task 6 (A), Task 8 (B), P-18 |
| §2.2 country model: versioned, immutable, seeds all closed, GH/GB/Tier 1-2, `publish_country_config` production refusals, kill switch pending then wired, public config through the seam (I-3) | Task 5 (A-D, E pending, G), Task 7 (dev script), Task 13 (E kill switch); P-14-P-16 |
| §2.3 effective tier, allowed here, same-gender here, away, session row, freshness inputs | Task 5 (F), Task 8 (F2); P-17 (freshness is read by W5a's filters) |
| §2.4 same-gender off: UI-independent server refusal, nothing stored/logged/counted, country change re-asks D5/D6, kill switch; logging health | Task 9 (A, mutants 4 and 7), Task 9 (C), Task 13, Task 12 (health `log_settings_safe`) |
| §2.7 `dating_notify_requests` table (RPCs W3a) | Task 5 |
| §3.2 D2-D13 storage rows, consents, attestation version, ages, children (no seek-parents), faith list and must-share, prompts with both filters, name, settings, photos after mutual | Tasks 9-10 |
| §3.8 pause / exit / delete; §3.12 never-introduce | Task 12; Task 11 |
| §4.1 principles (RLS, revoked, definer, `extensions.*`, auth HMACs, S-2 server metrics, S-5, opaque errors) | Tasks 3 (twin, canary), 9-10 (writers), 4 (prefix) |
| §4.2 encryption, two functions, service role can't read, fail closed | Task 8 (D1), Task 10 (D2), P-23 |
| §4.3 W1 rows (enrollments, consent purposes, profiles, preferences, matches, blocks, reports, survivors, sensitive, prompts, settings, notify, never-introduce, session context, country config) | Tasks 3, 5, 8, 11, 12; P-22 for the deferred drops |
| §4.4 W1 functions (setup writers, readers, lifecycle, never-introduce, `dating_phone_*`, `dating_effective_context`, `record_dating_session_context`, `apply_same_gender_switch`, `publish_country_config`, health v2, `dating_require_trusted_device` pass-through) | Tasks 2, 5, 8-13 |
| §4.5 RLS, grants, canaries (RLS, bucket, gitleaks) | Task 3 (+ rows in every later task), P-9, P-10, P-12 |
| §4.8 retention (W1 parts) | Tasks 4, 12; DPIA §3 |
| §4.9 W1a #1-3, W1b #1-2, W1c #1, W1d #1-2 (names and order; dev script with the guard first) | Tasks 2-13, P-1 (W1c is three files, W1d #2 two) |
| §4.10 W1 verdicts (exclusions from auth.users, `handle_relationship_dating_guard` removed, `sync_…` attached, `delete_dating_profile` removed, `exit_dating_mode`, `activate_dating_profile`, `record_dating_consent`, `dating_profile_ready`, `pause_*`, standing, `block_dating_user`, seams, `prepare_account_deletion`, health, `dating_same_gender_matching`, interim row removed, the key guard on today's generation) | Tasks 2-6, 12, 13 |
| §5.2 filter 13 helper | Task 11 (`dating_never_introduce_excludes`) |
| §6.3 deletion and carry-over steps 1-5, parked accounts (I-11, O3: no) | Task 4 (C), Task 2 (A), Task 12 (parked pause) |
| §6.8 DPIA started | Task 4 Step 5 |
| §6.9 `dating.` keys server-side | Task 4 (prefix), Tasks 9-12 (setup, activated, pause, exit counters) |
| §7.1 W1 files and rows | Tasks 2-13 (every listed row; the setup file starts in W1c, P-26) |
| §7.5 mutants 1, 5, 16, 17, 25, 27, 30 (and 4, 7) | Task 2 (`hmac_from_public_users`, `parked_*`), Task 12 (`generation_without_exclusion_key`, `exit_keeps_sensitive`, `exit_default_keeps`), Task 4 (`no_enforcement_record`), Task 7 (`no_guard`), Task 9 (`identity_stores_before_country`, `identity_raises_not_available`) |
| §8 W1 gate (counsel, `dating_field_key`, log health on production) | Owner checklist 3-5 |
| §9 R5, R6, R10, R18, R19, R22 | Task 4 (R5), Task 2 Step 8 (R6), Task 7 (R10), Task 5 Step 9 (R18), Task 12 Step 4 (R19), Task 3 (R22) |
| §10 items 2 (counsel), 8 (O3: no), 9 (`opinions` reserved, never written), 10 (Q17 exceptions) | checklist 5; Task 4 (C, O3); Task 3 (the CHECK, B's Opinions-scope row); checklist 5 |
| Cross-spec review I-3, I-11, I-14, A-10, S-2, S-4, S-5, R-2, R-6, W-2/W-3 | Tasks 5, 2/4/12, 6, 6, 4, 3/9/10, 3, 12, 1/5/7, the batch split |
| Carried Spec 1 items (PF-H2, PF-C9, L7 and minor #2, D8) | "Carried items" 1-4 (W3c, W6b, W3c/W4a, W3a) |

Placeholder scan: no "TBD", "TODO", "later", "similar to" or undefined name; every code step has its full text; `<…>` in the owner checklist are values only the owner has. Type consistency: every SQL signature is used as created (each file was applied, each contract run and each mutant executed while writing this plan, in task order, on a scratch restore of `attune_spec3a`).


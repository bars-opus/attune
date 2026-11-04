# Spec 1 W7 (support resources v2, image safety) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Route everyone to checked, country-specific help (W7a: migration 14 `support_resources` + `get_support_resources`, the bundled catalogue and its loader, Support resources v2 behind `support_resources_v2`, X1's youth link and the Healing row's breakup-or-loss choice), and match every image upload against known CSAM hashes (W7b: migration 15 as the queue, the escalations, the `safety-quarantine` bucket, the one match path and the storage enqueue with its sweep fallback; the `CSAM_MATCHER` seam with `photodna`, `safer` and `stub`; `_shared/csam_match_path.ts`; `scan-media`; the webhook), behind `csam_hash_matching`.

**Architecture:** Two sub-waves, eight tasks. **W7a (Tasks 1-4).** Task 1 is migration 14 (`support_resources`, the anon-readable `get_support_resources`, the service-role loader `load_support_resources`) proven by `support_resources_contracts.sql` with eight mutants. Task 2 is the catalogue file (only today's three helplines, verbatim, plus the international directory), `scripts/load_support_resources.sh`, the Dart repository (server first, the bundled catalogue offline or when the server is empty, the server's ordering rule ported and tested on the contract's fixture rows) and the release check. Task 3 is the v2 screen (country line and picker, emergency first, a confirmation before every call, text, WhatsApp or link, "Not the police", the fallback, the grief and youth views) under the same route, with goldens. Task 4 wires the earlier screens (X1's youth link, the Healing choice, Settings -> Support "Find support", the manual's gated passage) and runs the W7a gate. **W7b (Tasks 5-8).** Task 5 is migration 15 as 15a (`media_scan`: queue, escalations, quarantine bucket, `private.handle_csam_match`, claim/complete/inline, alerts, expiry, retention, identity health, crons) and 15b (`media_scan_enqueue`: the trigger function, the sweep, and the F-1 install that chooses between them inside the migration and records which), proven by `media_scan_contracts.sql` on both paths with seventeen mutants. Task 6 is `_shared/csam_matcher.ts` (the seam, the two vendor adapters as thin HTTP clients on mocked fetch, the stub refused in production). Task 7 is `_shared/csam_match_path.ts` (quarantine first, then record, for both entry points). Task 8 is `scan-media`, the two escalation sources in `identity-health-alert`, and the W7b gate. Every SQL, Dart and Deno block below was run while writing this plan: the SQL on a scratch Postgres 17 cluster restored from `attune_spec3a`'s dump (each migration applied twice, `exit=0` both times; each contract red before its migration with the message quoted and green after; `media_scan_contracts.sql` also green with the install forced to the sweep path; every SQL mutant red with the message quoted; the whole contract suite with no new FAIL against the baseline: 142 PASS = 140 + the two new files), the Dart in a scratch copy of the tree (every new test red before its code and green after, goldens generated and looked at, the analyzer clean on every touched file, the touched suites green), and the Deno tests plus `deno check` of every new function and four TypeScript mutants.

**Tech Stack:** Flutter 3.29.1 (Dart 3.7), Riverpod 2.6, GoRouter, Supabase Postgres 17 (RLS, `SECURITY DEFINER` with `search_path = ''`, pg_cron, Vault through `public.app_setting`), Supabase CLI 2.75, Deno 2 (Web Crypto, `fetch`, `FormData`), Supabase Storage (`storage.objects`, `storage.buckets`), psql, Python 3 (edit and check scripts), bash + curl (the loader). No new Dart package, no new Deno import beyond `std@0.177.0/http/server.ts` already used by every function.

**Spec:** `docs/superpowers/specs/2026-10-24-app-flow-identity-design.md` — §1.3-§1.5, §2 (copy, §2.2 never animated, §2.3 accessibility, §2.5 `support_resources_v2` and `csam_hash_matching`, the production-mode note that `scan-media` refuses the `stub` matcher), §3.6 X1, §3.10 the Healing row, §4.2 (`support_resources`, `media_scan_queue`, `safety_escalations`, `safety-quarantine`), §4.3 W7a and W7b, §4.4 `enqueue_media_scan` (review F-1), §4.5 `scan-media`, §4.6 the three W7b crons, §4.7 #14-#15, §4.8, §5 rows tagged W7*, §7.1 (`support_resources_contracts.sql`, `media_scan_contracts.sql`), §7.2 (`scan-media`, `csam_match_path.test.ts`), §7.4 (the `dating-profile-photos` and exception-guard mutants), §8 W7a-b and their gates, §9, §10 (outside parties), §11 (I-10, F-1). Owner rulings: `docs/superpowers/research/2026-10-24-flow-dating-research/11-synthesis-decisions.md` §12 (Q1: W7 is a worldwide launch item; 11 rows 11-12 and the W7 gate line). The controller's rulings for this plan (the F-1 spike inside the migration, the catalogue content, the matcher seam) are P-16, P-4 and P-23 below. Format reference: `docs/superpowers/plans/2026-11-03-spec1-w6-holds.md`.

## Global Constraints

- Work in the main working tree on `main` (`/Users/user/attune`). W1-W6 are committed (HEAD `b514d6fe`); the owner may have uncommitted edits (`supabase/.temp/cli-latest`, `backup-before-planning-p2.sql` at the time of writing): never revert, stash, stage, checkout or reformat them. Every edit below is an exact-string replacement; if the text to replace has moved because a later fix changed it, apply the same change to the current text and say so in the task report.
- **NO commits.** No `git add`, `git commit`, `git stash`, `git checkout`, `git reset`, `git rm`. Tasks end with "Run tests", not "Commit".
- Never `dart format` a pre-existing file (the repo predates the 3.7 formatter). The Dart files this plan creates are given already formatted; Task 4 Step 8 re-runs `dart format` on exactly those paths (it changes nothing).
- **SQL:** contracts run only on the local scratch database `attune_spec3a`, only as `psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f <file>`, inside the file's own `BEGIN … ROLLBACK`. Confirm the target first (`psql -X -d attune_spec3a -Atc 'select current_database()'` prints `attune_spec3a`). NEVER `attune_test`. NEVER run `scripts/local_pg_setup.sh`, `scripts/local_pg_grants.sql` or `scripts/local_pg_bootstrap.sql`; Tasks 1 and 5 **edit** `scripts/local_pg_grants.sql`, never running it. `scripts/local_pg_bootstrap.sql` needs no edit (P-26).
- **Migrations:** `20261103130000_support_resources_v2.sql` + `…130010_support_resources_v2_grants.sql` (Task 1); `20261103140000_media_scan.sql` + `…140010_media_scan_grants.sql`, `20261103140100_media_scan_enqueue.sql` + `…140110_media_scan_enqueue_grants.sql` (Task 5); later than every migration in the tree (the newest is W6's `20261103120010_child_safety_reports_grants.sql`). If `ls supabase/migrations | sort | tail -1` shows anything at or after `20261103130000` when Task 1 starts, shift all six to the next free hour, keeping their order, and change every header, `\i` line and command below to match. Each file is one `BEGIN; … COMMIT;`, idempotent (applied twice, `exit=0` both times), `SET LOCAL lock_timeout = '5s'`, every `SECURITY DEFINER` function has `SET search_path = ''` and schema-qualifies every name, server-only objects are revoked inside the migration itself and again in the twin, grants are explicit. Nothing reaches `anon` except `get_support_resources` (spec §4.3 W7a). `service_role` gets DML on every new public table (`support_resources`, `safety_escalations`); the private queue and state tables get no grant at all (functions only). No `CREATE INDEX CONCURRENTLY`.
- **Re-created function:** `get_identity_health` starts from its live latest body (`20261103100200_fresh_start.sql`, checked identical to `pg_get_functiondef` on `attune_spec3a` while writing this plan) and gains exactly `|| private.identity_health_w7b()` (Task 5 diffs it).
- **Flags:** W7 adds no flag row. `support_resources_v2` and `csam_hash_matching` exist from W1c (`20261025100400`), inserted false, each with its production gate row in `private.flag_production_gates`; `get_public_app_config()` already returns `support_resources_v2` (effective); `supabase/sql/dev_enable_spec1_flags.sql` already turns both on in development and is not edited.
- **Never touch:** `lib/features/games/**`, `ChatScreen`'s Games entry points, `UniversalBubble` / `ChatTextField` parameters, `lib/features/auth/utility/auth_exports.dart`, every Games route in `app_router.dart` (`test/architecture/games_untouched_test.dart` stays green), `lib/features/opinions/**` (Opinions stays as it is), `ATTUNE_SOUL.md`, `ATTUNE_THESIS.md`, every applied migration, `supabase/sql/dev_enable_spec1_flags.sql`, the existing SQL contracts, `lib/home/home_screen.dart` (its latch block, from `if (isAuthenticated && !_gateData.isComplete) {` to `_redirectingToOnboarding = false;`, stays byte-identical: Task 1 saves its hash, Tasks 4 and 8 compare). The flag-off path of `SafetyResourcesScreen` is today's body, unchanged below the new first lines.
- **Safety system rules:** nothing in W7 depends on an LLM (the directory is a table and a JSON file; the matcher is a hash service; the match path is SQL). Safety notifications go only to the team's `SAFETY_ALERT_WEBHOOK` (counts and times only), never to a user: the uploader learns nothing beyond W6's H1 at the next token refresh, the partner nothing, and nothing is reported to any authority automatically (a person decides). A scan failure never blocks an upload (the trigger's exception guard, contract C; the sweep is outside the upload). A stub never marks anything clear in production (Task 6, Task 8). Quick exit works everywhere (the app shell's `QuickExitZone` sits above every route; the v2 screen keeps today's quick-exit button and bar action).
- **Shared phones (D20):** the chosen country is held in memory only (never stored; Task 3 test); no key or value names Dating; the support screen keeps nothing on the phone.
- **Copy:** every new string is an English key appended to `lib/i10n/app_en.arb` (`support_*` for the directory and Settings, `flow_*` for the Healing choice) by W3's `.superpowers/sdd/2026-10-26-spec1-w3/arb_append.py`, then generated with `flutter gen-l10n --arb-dir=lib/i10n --template-arb-file=app_en.arb --output-dir=lib/i10n/generated --output-localization-file=app_localizations.dart --no-synthetic-package`; other locales fall back to English. The fragment is pure ASCII (no en dash, no curly quote, no ellipsis), so no `\uXXXX` escape is needed; Task 3 checks it with `grep -cP '[^\x00-\x7F]' <fragment>` (prints `0`). Should a later copy fix need a non-ASCII character, write it as a JSON `\uXXXX` escape by script and verify it with `grep -P`, never by hand. Never "they" for the partner, never "both of you" (W7 copy names no partner). W7 shows no date (the catalogue's `verified_at` is not displayed); any later date uses `MyDateFormat`.
- **UI:** Material 3 from the app theme; every new screen and sheet is wrapped in `AllowLargeText` (the v2 screen) or sits in a flow frame's scope (the Healing sheet); every control labelled, targets at least 48 dp, text contrast at least 4.5:1, goldens at 1.0, 1.3, 2.0 and right to left (`expectFlowGoldens`), `androidTapTargetGuideline`, `labeledTapTargetGuideline` and `textContrastGuideline` (`expectFlowGuidelines`). Nothing on the support screen or the Healing sheet is animated (§2.2: safety and support sheets are never animated); a wait shows nothing for 400 ms, then a bar with words.
- **No deploys.** `supabase db push`, function deploys, secrets, loading the catalogue on a hosted project, the vendor contract and keys, and the webhook destination are the owner's ("Owner deploy checklist"). Don't read `.env*`, credentials or the keychain. No `flutter pub get` (no package change; the one `pubspec.yaml` line adds an asset folder).
- **Regression gate at the end of each sub-wave (Tasks 4, 8):** every SQL contract on `attune_spec3a` shows no new FAIL against the Task 1 baseline, and `support_resources_contracts.sql` (and from Task 5 `media_scan_contracts.sql`), `identity_foundation_contracts.sql`, `dormancy_contracts.sql`, `child_safety_contracts.sql` and `account_deletion_contracts.sql` are PASS; the Deno tests of `identity-health-alert`, `start-fresh-account`, `purge-recovery-holds` (and from Task 8 `scan-media` and the two shared files) pass; the full `flutter test` passes; `flutter analyze --no-pub lib test` shows no `error` line that the Task 1 baseline didn't; the Games test passes; no Opinions, Games or `auth_exports.dart` change; the latch is unchanged.

## Review Focus

1. **Someone opens Support with no signal, or on a project where nobody has loaded the catalogue yet.** `get_support_resources` then fails or answers an empty list. Expect the bundled catalogue, never an empty screen, and the same order the server would give. Tests: Task 2 `support_resources_repository_test.dart` (`a failing server falls back to the bundle`, `a server with nothing loaded falls back to the bundle`, `a slow server falls back to the bundle after the timeout`, `the app bundles the catalogue (pubspec assets)`), and the order test on the contract's own fixture rows.
2. **A country without a checked list, a phone that knows no country, a checked list without an emergency number, and the youth or grief view with nothing for that country.** Expect the "We don't have a checked list for {country} yet." card with "Find a helpline" (confirmed, then the international directory) and "In an emergency, call your local emergency number.", or the same emergency line above a list that has no emergency entry, and never another country's numbers. Tests: Task 3 (`a country without a checked list: the fallback`, `a checked list without an emergency number says what to do`, `no country known: asked to choose one`, `grief, signed out: no journal; youth with no list: fallback`), Task 1 contract B (`ZZ`, `zz`, `XX`, `''`, `Ghana`, NULL).
3. **Hosted Supabase won't let `postgres` put a trigger on `storage.objects` (review F-1).** Expect `db push` to succeed anyway, the one-minute sweep scheduled instead, the path recorded and shown by identity health, and the same queueing rules on either path. Tests: Task 5 contract E (the install run as a role without the right falls back to the sweep, records it, and returns to the trigger when the right is there), the whole contract green with the install forced to the sweep path (Task 5 Step 6), mutant `no_fallback`.
4. **The matcher is down, misconfigured, answers something unexpected, or the stub was left on when the project became production.** Expect nothing marked clear: unavailable, the back-off (1, 5, 15, 60 minutes), and after 24 hours `failed` with one `scan_failed` escalation that reaches the webhook. Tests: Task 6 (`stub is refused in production`, `no matcher, an unknown one, or a vendor without its key`, the PhotoDNA and Safer unreadable bodies, the timeout), Task 8 (`production: the stub is refused and clears nothing`, `a download that fails is unavailable`), Task 5 contract G, TypeScript mutants `stub_allowed_in_production`, `photodna_unknown_is_clear`.
5. **A match where the quarantine copy fails, a profile picture replaced in place, and the same dating photo reported twice by Spec 2's pipeline.** Expect: held and escalated at once with the original kept as the evidence (never deleted without a copy); the replaced picture queued again; one escalation and one hold per object, and a reviewer's resolved hold left resolved. Tests: Task 7 (`a copy that keeps failing`), Task 8 (`a failing quarantine still records the match, as unquarantined`), Task 5 contract B (written over in place), H (`match_unquarantined`, `an inline match twice`), mutants `delete_unquarantined`, `repeat_not_idempotent`.

## Decisions found while verifying the code (read before Task 1)

Each is a verified fact about today's code (HEAD `b514d6fe`), the database or the vendors, with the smallest change that keeps the spec's intent. *Changes spec intent* marks the ones the owner should see.

**W7a**

- **P-1 (timestamps).** Migration 14 is `20261103130000` (+ twin `…130010`); migration 15 is `20261103140000`/`…140010` (15a) and `20261103140100`/`…140110` (15b, P-15).
- **P-2 (flags already exist).** Both W7 flags, their production gate rows (`'W7a gate: resource entries verified per country by the DV professional and the cultural reviewer; clinician reviewed the grief copy'`, `'W7b gate: hash-vendor contract, escalation runbook approved by counsel, named child-safety contact'`) and the dev script lines were made by W1c. `PublicAppConfig.supportResourcesV2` already parses the anon config; W7a adds only `supportResourcesV2Provider` (live, else cached, else off, the `ageSignalSettingsProvider` pattern).
- **P-3 (the loader).** §4.2 says the script loads the table "(service role)". The load is a service-role function, `load_support_resources(p_catalogue jsonb) → jsonb`, so a load is one transaction: every entry upserted by id and made active, every row the file no longer has made inactive (never deleted), and the whole file refused, by message, when it is not a catalogue (`support_resources:invalid_catalogue`), repeats an id (`support_resources:duplicate_id`) or has no anywhere entry with a link (`support_resources:no_international_directory`); a bad row is refused by its table check. `scripts/load_support_resources.sh` posts the file to it with the key in a mode-600 header file (never on the command line), reading `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` from the caller's environment and never from `.env`; `--check <database>` runs the same load as the service role on a local database inside a rolled-back transaction.
- **P-4 (catalogue content; controller ruling).** Never invent a hotline number: a wrong crisis number is a safety harm. Today's Safety resources screen has no structured data, only three hard-coded cards in `safety_resources_screen.dart` (Ghana Police DOVVSU `055 100 0900` `https://police.gov.gh/`; National Domestic Violence Hotline `800-799-SAFE (7233)` `https://www.thehotline.org/`; Refuge National Domestic Abuse Helpline `0808 2000 247` `https://www.refuge.org.uk/`). `assets/support_resources/catalogue.json` (version `2026-11-03.1`) carries exactly those three, verbatim, as category `dv` (DOVVSU with `is_police: true`, it is a police unit), plus the international (`XX`) directory "Find A Helpline" `https://findahelpline.com` (category `crisis`), each `verified_by: "carried-from-v1"`, `verified_at: "2026-11-03"`. No emergency number ships (today's screen has none; it says "call your local emergency number", which v2 keeps, P-10). `support_resources_v2` stays off in production until the owner's verification pass adds the per-country rows for the launch countries with `verified_by` set to a real person (owner checklist 4). *Changes spec intent*: the W7a gate's list (Ghana, the UK, the US and Canada with every category) is not something the build can fill; it is the gate.
- **P-5 (fixtures).** Contracts and widget tests use fixture rows (`5f7a0000-0000-0000-0000-0000000000NN`), never the shipped file; the shipped file is read only by the parse test and the release check, which are about the file itself.
- **P-6 (the country).** The SIM's country, else the phone's region (W2b's `deviceCountryProvider`); the picker (W2's `PhoneCountryPickerSheet`) changes it for this run only, held in memory (`supportCountryOverrideProvider`), never stored: nothing on the phone shows that someone looked for help.
- **P-7 (one route, two narrow views).** `RouteNames.safetyResources` stays the route (every existing link keeps working); `?focus=grief` and `?focus=youth` narrow the v2 screen to the emergency entries plus that category (grief adds "Write about it in your journal" when signed in). With the flag off the query is ignored and today's screen shows. The first-launch allow-list and the under-18 block match on the path, so both views open before sign-in and from X1.
- **P-8 (X1).** X1 stays a `StatelessWidget` (its bare-frame "never animates" test pumps it without a `ProviderScope`); the flag is read when the link is tapped, through `ProviderScope.containerOf`, and a missing scope reads as off. Off: `https://findahelpline.com`, as before W7. On: `/safety-resources?focus=youth`.
- **P-9 (the Healing choice).** Only under `support_resources_v2`: "What happened?" with "A breakup" (today's `openHealing`, unchanged) and "Someone I love died" (`/safety-resources?focus=grief`). `YourSpaceSection` is shared by Me and the Relationship space, so both get it. Off: today's tap, no question.
- **P-10 (leaving the app is always confirmed).** §8 W7a names the call confirmation ("Call {number}? Calls may show in your phone's call history."); the manual already promises that the app never dials or opens a website without asking (`safety_docs.dart`, `safety_calling_confirm`), so texts, WhatsApp and websites get the same confirmation ("Text {number}?" "Messages may stay on your phone."; "Open {site}?" "It may show in your browser history."). Numbers dial as printed: digits, a leading `+`, keypad letters (`800-799-SAFE (7233)` dials `8007997233`; a bracketed repeat is dropped when letters stand outside it; `(0)` after a country code is dropped). A checked list without an emergency number shows "In an emergency, call your local emergency number." above it.
- **P-11 (copy the spec doesn't give).** Category headings ("Domestic abuse", "Someone to talk to now", "Sexual assault", "Threats to share images", "A child at risk", "For young people", "LGBTQ+ and legal help", "Grief", "Pregnancy and after birth", "Alcohol, drugs and gambling", "Money and control"), "In an emergency", "Anywhere in the world", "Help for {country}", "Change", "Choose your country to see help near you.", "Choose a country", "Looking for help near you", "Police" (beside the spec's "Not the police"), the text and link confirmations (P-10), "We don't have a checked list for this in {country} yet." (a narrow view), "Grief support", "Support for young people", "Write about it in your journal", Settings "Find support" / "Helplines for where you are", Healing "What happened?" / "A breakup" / "Someone I love died". Today's screen's lines are kept word for word. The DV professional and the cultural reviewer read them at the W7a gate; the clinician reads the grief branch.
- **P-12 (Settings).** "Find support" at the top of Settings -> Support (a section shown signed in or out), only under the flag; Settings -> Safety's "Safety resources" row is unchanged.
- **P-13 (the manual).** One passage, "Help for where you are", in the Support Resources section of `safety_docs.dart`, gated as `supportResourcesV2` in `DocumentationRegistry._passageFlags` (the B7 M-3 pattern). `documentation_registry_flags_test.dart`'s allow-list of flags the app reads gains `'support_resources_v2'` (a one-line edit, as W5 did).
- **P-14 (found: v1 overflow).** Today's helpline cards overflow on a 390-wide phone (the website line sits in a `Row` without `Expanded`). The flag-off body is left byte-identical (the flag-off test pumps it on a wide view); v2 replaces it. Listed for the owner, not fixed here.

**W7b**

- **P-15 (migration 15 as two files).** 15a `media_scan` (queue, escalations, quarantine bucket, the match path and its service functions, alerts, expiry, retention, identity health, the two crons) and 15b `media_scan_enqueue` (the trigger function, the sweep and the install), each with its twin.
- **P-16 (the F-1 spike inside the migration; controller ruling).** The development project can't be touched first, so 15b's `private.install_media_scan_enqueue()` (SECURITY INVOKER: it runs with the migration's own rights) keeps the trigger if it is there, else tries `CREATE TRIGGER enqueue_media_scan AFTER INSERT OR UPDATE OF metadata ON storage.objects`; on `insufficient_privilege` it schedules `enqueue-new-storage-objects` (`* * * * *`, `SELECT private.enqueue_new_storage_objects()`) instead. Either way it records the path in `private.media_scan_state.enqueue_path` (identity health's `media_scan_enqueue_path`) and raises `NOTICE: media_scan: new uploads reach the scan queue by …`, which `db push` prints. It never drops a trigger it didn't need to (dropping needs ownership; creating needs only the TRIGGER right). The contract covers both paths: the trigger locally; the sweep by calling it directly; the fallback branch by running the install as a role without the right; and the whole file again with the install forced to the sweep. Cost if wrong: one extra cron. The owner checks the path after `db push` (checklist 2).
- **P-17 (`avatars`; found).** Profile pictures are uploaded to a bucket named `avatars` (`upload_profile_image.dart`: public URL, `upsert: true`, the fixed path `<uid>/avatar.jpg`). No migration creates it, so §4.4's list of five buckets missed it, and it is the most visible image in the app (every signed-in user sees profile pictures). It is added to `private.media_scan_buckets()`, and because it is written over in place, an `UPDATE` whose eTag or mime type changed is queued again (unless the object already matched); the sweep sees the same through `updated_at`. *Changes spec intent* (owner question 1).
- **P-18 (a match whose quarantine copy fails).** §4.5 says the copy comes first, then the record. If the copy still fails after three tries, the match is recorded at once as unquarantined: the account is held and the escalation opened (`quarantined = false`, a note saying the original is still in place and must be copied by hand), but the original is NOT queued for deletion, because it is then the only copy of the evidence. `private.handle_csam_match` and `record_inline_csam_match` gain `p_quarantined boolean DEFAULT true` (Spec 2's five-argument call is unchanged); `complete_media_scan` takes `p_result = 'match_unquarantined'`. *Changes spec intent* (owner question 2).
- **P-19 (video, and objects gone).** No adapter hashes video in W7b (it depends on the vendor contract): a video job is completed `skipped` (`video_not_hashed`) without a download, and its poster image, which every upload path stores as its own image object (`media_thumbnail_url`, `thumbnail_key`), is scanned like any image. An object deleted before its scan is `skipped` (`object_missing`). `skipped` is a new queue status (never `clear`), kept 7 days and counted by identity health (`media_scan_skipped_7d`). *Changes spec intent* (the status; owner question 4).
- **P-20 (the queue's rules).** `claim_media_scan_jobs` answers nothing while the flag is off, leases each job for 10 minutes (a run that dies is claimed again), adds an attempt, takes at most 50, and first expires anything queued 24 hours ago (`failed` + one `scan_failed` escalation); it returns a `TABLE (id, bucket, object_name, owner_user_id, mime, attempts)` rather than a `setof` of the private table's row type, which PostgREST can't name. `complete_media_scan`: a match is never dropped, whatever the row's state; `clear`, `skipped` and `unavailable` only answer a job that is `scanning` (a picture written over while it was being scanned is not marked clear by the stale answer); an unknown result raises `media_scan:invalid_result`, an unknown job `media_scan:no_job`. `media-scan-retention` also runs the expiry, so a dead `scan-media` cron still reaches a person.
- **P-21 (the webhook).** `safety_escalations` gains `vendor`, `vendor_ref` (§9: "the escalation records the vendor reference"), `quarantined` and `alerted_at`; `user_id` has no foreign key (evidence outlives the account). Two sources join W6's `identity-health-alert`: `csam_match` (`csam_escalations_due`) and `scan_failed` (`scan_failed_escalations_due`), both marked by `mark_safety_escalations_alerted`, each post a count and a time only. `scan-media` posts them straight after a run that recorded a match or an unavailable answer, through the same `sendAlerts` helper; the 15-minute run is the backstop. They sit before W6c's source in `ALERT_SOURCES`, so W6c's test (its mark is the last call) stays as it is.
- **P-22 (identity health).** `private.identity_health_w7b()` (`media_scan_enqueue_path`, `media_scan_enqueue_failures`, `media_scan_pending`, `media_scan_oldest_pending_minutes`, `media_scan_skipped_7d`, `safety_escalations_open`, `safety_escalations_unalerted`); `get_identity_health` re-created from its live body with `|| private.identity_health_w7b()` and nothing else, so it names no W7 table itself (the W6 split).
- **P-23 (the matcher seam; controller ruling).** `CSAM_MATCHER` = `photodna` (`PHOTODNA_SUBSCRIPTION_KEY`, optional `PHOTODNA_URL`), `safer` (`SAFER_API_KEY`, `SAFER_MATCH_URL`, https only) or `stub` (`CSAM_STUB_MATCH_SHA256`, comma separated, plus the built-in test hash of `scan-media/testdata/stub-match.png`). Missing or unknown: every job `unavailable`. The stub is refused unless `get_attune_environment()` reads exactly `development` (an unreadable environment is production): refused, it answers `unavailable` (`stub_refused_in_production`) for everything, so a stub never clears anything in production. Every adapter turns anything it does not positively understand (a non-200, a non-3000 PhotoDNA status, an unreadable body, a timeout, an image type PhotoDNA doesn't take) into `unavailable`, never `clear`.
- **P-24 (the vendor shapes).** PhotoDNA: the Cloud Service Match call (`POST …/photodna/v1.0/Match?enhance=false`, the image bytes as the body with their content type, `Ocp-Apim-Subscription-Key`; a 200 with `Status.Code` 3000 carries `IsMatch` and `TrackingId`). Safer: Thorn gives its API reference to customers only (checked 2026-11-03), so the adapter follows the published response for Thorn-backed hash matching (`output.file.reasons` holds `"matched"`, `output.hashes[].sources[].matches[].sourceId`), the image as multipart `media` and `Authorization: Token <key>`; the owner compares it with Thorn's reference before choosing `safer` (checklist 5). *Changes spec intent* only in that `safer` is built unconfirmed (owner question 3: PhotoDNA first).
- **P-25 (grants).** `safety_escalations`: RLS on, no policy, `service_role` DML (house rule), nothing for clients. `private.media_scan_queue` and `private.media_scan_state`: no grant to anyone (functions only). The six service functions: `service_role` only. Everything else: nobody.
- **P-26 (no bootstrap or config edit).** `scripts/local_pg_bootstrap.sql` already stubs `storage.buckets` and `storage.objects` (`bucket_id`, `name`, `owner`, `metadata`, `created_at`); the trigger and the sweep read `owner_id` and `updated_at` by name when a newer storage schema has them (`to_jsonb(row)`), so both the stub and hosted Storage work. `supabase/config.toml` needs no `scan-media` entry (the cron calls it with the service-role key, like `identity-health-alert`).
- **P-27 (the sweep's cost).** Where the sweep runs it reads `storage.objects` in the listed buckets once a minute; an index on `created_at` can't be added without owning the table. Fine at launch volumes; listed in the runbook.
- **P-28 (fixtures).** `support_resources_contracts.sql`: ids `5f7a…NN`, no person. `media_scan_contracts.sql`: ids `5f7b0000-0000-0000-0000-0000000000NN`, phones `15558500NN` (§7.1's 85xx range) on `auth.users` and `public.users`, objects under `w7-contract/`.

## Owner questions (open; the plan builds the recommendation)

1. **Scan the `avatars` bucket too, including pictures written over in place (P-17).** *Recommendation:* accept; profile pictures are public, seen by every signed-in user, and were outside §4.4's list only because no migration creates their bucket. Confirm the bucket's name on the hosted project (checklist 2).
2. **A match whose quarantine copy fails keeps the original as the evidence (P-18).** *Recommendation:* accept; the account is held at once and a person is told, and deleting the only copy of CSAM evidence would break the reporting duty counsel will set.
3. **Vendor: PhotoDNA or Safer (P-23, P-24).** *Recommendation:* PhotoDNA first (its API is public and the adapter follows it exactly; free for eligible organisations); Safer only after its adapter is checked against Thorn's reference.
4. **Video is not hashed until the vendor contract covers it; posters are (P-19).** *Recommendation:* accept for launch and list the gap in the runbook; turn it on with the vendor's video hashing.
5. **The catalogue verification pass (P-4).** *Recommendation:* name the DV professional and the cultural reviewer now; `support_resources_v2` stays off in production until their rows are loaded.

## W1-W6 interfaces this plan consumes (adjust here if a later fix renames one)

- SQL: `public.place_account_hold(p_user uuid, p_kind text, p_ref text DEFAULT NULL)` (re-opens a resolved hold; the caller guards repeats), `public.account_holds` (PK `user_id, kind`; `kind` IN `age_review`, `recovery_hold`, `safety_review`; `user_id` → `public.users`), `public.queue_media_deletion(p_bucket_id text, p_object_name text)` (`20260930120000`; `ON CONFLICT DO NOTHING`; drained by `process-media-deletion-queue`), `public.media_deletion_queue (bucket_id, object_name, not_before, deleted_at)`, `private.spec1_flag_on(text)`, `public.feature_flags`, `private.flag_production_gates`, `public.get_attune_environment()` (service role), `public.get_identity_health()` (live body in `20261103100200`), `private.identity_health_w6a()`, `public.invoke_edge_function(text)`, `cron.schedule` / `cron.unschedule`, `storage.buckets` (`message-media`, `story-media`, `relationship-avatars`, `journal-media`, `planning-media`, `dating-profile-photos`, `data-exports`; checked on `attune_spec3a`), `storage.objects` (`bucket_id`, `name`, `owner`, `metadata->>'mimetype'`, `metadata->>'eTag'`, `created_at`). No storage trigger exists today (only the local stub's `reject_direct_object_delete`).
- Edge: `_shared/attune_auth.ts` (`serviceRoleClient`, `requireServiceRole`, `jsonResponse`, `HttpError`), `identity-health-alert/handler.ts` (`AlertSource`, `AlertClient`, `PostFn`, `AlertResult`, `sendAlerts`, `ALERT_SOURCES`), `SAFETY_ALERT_WEBHOOK` (W6a), supabase-js 2.39 (`storage.from(b).download(path)` → `Blob`; `.upload(path, body, {contentType, upsert})`; no cross-bucket copy, so the quarantine is an upload of the bytes already downloaded).
- Dart: `PublicAppConfig.supportResourcesV2`, `publicAppConfigProvider`, `cachedPublicAppConfigProvider`, `deviceCountryProvider` (`({String? sim, String? region})`), `PhoneCountries`, `PhoneCountryPickerSheet`, `countryNameFor`, `BottomSheetUtils.showDocumentationBottomSheet`, `quickExitProvider`, `SafetyPinPromptCard` (`dismissedKey`), `SafetySelfCheckRow`, `safetySelfCheckEnabledProvider`, `ReportChildConcernLink`, `homeAuthProvider`, `UrlLauncherUtils.launchUrlWithFeedback`, `RouteNames.safetyResources` (`/safety-resources`), `RouteNames.reflectionJournal`, `RouteNames.healingJourney`, `openHealing`, `hasActiveSoloHealingJourneyProvider`, `YourSpaceSection`, `SpaceRow`, `UnderAgeStopScreen.youthSupportUrl`, `SettingsDataSource.getSettingsSections`, `SettingsConfig`, `SettingsItemType`, `DocumentationRegistry.passageVisible`, `documentationFlagsOf`, `documentationFlagsProvider`, `AllowLargeText`, `Spacing`, `BorderRadiusTokens`, `flow_countryUk` / `flow_countryUs`; test helpers `pumpFlowScreen` (`size`, `overrides`, `prefsValues`), `expectFlowGoldens`, `expectFlowGuidelines` (`test/helpers/flow_harness.dart`), `FakeHomeAuth`, `testUser` (`test/helpers/home_harness.dart`).

## File map

**W7a (Tasks 1-4)**
- Create `supabase/migrations/20261103130000_support_resources_v2.sql`, `…130010_support_resources_v2_grants.sql`, `supabase/tests/support_resources_contracts.sql`; modify `scripts/local_pg_grants.sql` (Task 1).
- Create `assets/support_resources/catalogue.json`, `scripts/load_support_resources.sh`, `lib/features/safety/data/support_resources_repository.dart`, `test/features/safety/w7/support_resources_repository_test.dart`, `test/launch/support_resources_release_test.dart`; modify `pubspec.yaml` (one asset line) (Task 2).
- Create `lib/features/safety/presentation/providers/support_resources_providers.dart`, `lib/features/safety/presentation/screens/support_resources_v2_screen.dart`, `test/features/safety/w7/support_resources_v2_test.dart` (+ 12 goldens); modify `lib/features/safety/presentation/screens/safety_resources_screen.dart` (two edits), `lib/app/routing/app_router.dart` (an import and the `safetyResources` builder), `lib/i10n/app_en.arb` (+ generated) (Task 3).
- Create `lib/features/me/presentation/widgets/healing_choice_sheet.dart`, `test/features/safety/w7/support_hooks_test.dart` (+ 4 goldens); modify `lib/features/me/presentation/widgets/your_space_section.dart`, `lib/features/auth/sign_up/presentation/screens/under_age_stop_screen.dart`, `lib/features/settings/data/settings_data.dart`, `lib/features/settings/screens/settings_screen.dart`, `lib/app/documentations/user_manual/data/manual_documentation_registry.dart`, `lib/app/documentations/user_manual/data/safety_docs.dart`, `test/app/documentations/documentation_registry_flags_test.dart` (one line) (Task 4).

**W7b (Tasks 5-8)**
- Create `supabase/migrations/20261103140000_media_scan.sql`, `…140010_media_scan_grants.sql`, `…140100_media_scan_enqueue.sql`, `…140110_media_scan_enqueue_grants.sql`, `supabase/tests/media_scan_contracts.sql`; modify `scripts/local_pg_grants.sql` (Task 5).
- Create `supabase/functions/_shared/csam_matcher.ts`, `_shared/csam_matcher.test.ts` (Task 6).
- Create `supabase/functions/_shared/csam_match_path.ts`, `_shared/csam_match_path.test.ts` (Task 7).
- Create `supabase/functions/scan-media/{index,handler,handler.test}.ts`, `supabase/functions/scan-media/testdata/stub-match.png`; modify `supabase/functions/identity-health-alert/handler.ts`, `handler.test.ts` (Task 8).

**Not edited:** `lib/home/home_screen.dart`, `lib/app/app_shell.dart`, the quick-exit and sign-out files, `lib/features/chat/**`, `lib/features/opinions/**`, `lib/features/games/**`, `auth_exports.dart`, `lib/core/flags/public_app_config.dart`, `supabase/config.toml`, `scripts/local_pg_bootstrap.sql`, `supabase/sql/dev_enable_spec1_flags.sql`, every applied migration, every existing SQL contract, every existing test except `documentation_registry_flags_test.dart` (one line added) and `identity-health-alert/handler.test.ts` (one test added).

---

# W7a · Support resources v2 (Tasks 1-4)

### Task 1: Baselines; migration 14: the support directory (§4.2, §4.3 W7a, §4.7 #14, §7.1; P-1-P-3, P-5, P-28)

**Files:**
- Create: `supabase/migrations/20261103130000_support_resources_v2.sql`
- Create: `supabase/migrations/20261103130010_support_resources_v2_grants.sql`
- Create: `supabase/tests/support_resources_contracts.sql`
- Modify: `scripts/local_pg_grants.sql` (one `\i` block; never run)

**Interfaces:**
- Consumes: nothing from earlier waves (the table is a public directory).
- Produces: `public.support_resources` (`id uuid` PK from the catalogue, `country_code` `^([A-Z]{2}|XX)$`, `category` IN the twelve of §4.2, `name`, `description`, `phone`, `sms`, `whatsapp`, `url` https only, `hours`, `languages text[]`, `is_police`, `sort_order`, `verified_at date`, `verified_by`, `catalogue_version`, `active`; at least one of phone/sms/whatsapp/url; RLS on, no policy); `public.get_support_resources(p_country text) → jsonb` `{country, country_supported, catalogue_version, resources:[{id, country_code, category, name, description, phone, sms, whatsapp, url, hours, languages, is_police, verified_at}]}` (anon, authenticated; emergency first, then the country before `XX`, then `sort_order`, then name); `public.load_support_resources(p_catalogue jsonb) → jsonb {catalogue_version, loaded, deactivated}` (service role; raises `support_resources:invalid_catalogue|duplicate_id|no_international_directory`).

- [ ] **Step 1: Record the baselines**

```bash
psql -X -d attune_spec3a -Atc 'select current_database()'
mkdir -p .superpowers/sdd/2026-11-03-spec1-w7
ls supabase/migrations | sort | tail -1
for f in supabase/tests/*.sql; do
  if psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f "$f" >/dev/null 2>&1; then echo "PASS $(basename "$f")"; else echo "FAIL $(basename "$f")"; fi
done > .superpowers/sdd/2026-11-03-spec1-w7/sql-baseline.txt
grep -c PASS .superpowers/sdd/2026-11-03-spec1-w7/sql-baseline.txt
flutter analyze --no-pub lib test 2>&1 | grep -E '^\s*error ' | sort > .superpowers/sdd/2026-11-03-spec1-w7/analyze-baseline.txt
sed -n '/if (isAuthenticated && !_gateData.isComplete) {/,/_redirectingToOnboarding = false;/p' lib/home/home_screen.dart | shasum > .superpowers/sdd/2026-11-03-spec1-w7/latch.sha
(cd supabase/functions && NO_COLOR=1 deno test --allow-read identity-health-alert/ start-fresh-account/ purge-recovery-holds/ 2>&1 | grep -E '^(ok|FAILED) \|')
```

Expected: `attune_spec3a`; `20261103120010_child_safety_reports_grants.sql`; the PASS count (140 on the scratch copy used for this plan, with 17 pre-existing FAILs: the fourteen `ai_*` files, `couple_map_presence_contracts.sql`, `reminder_delivery_contracts.sql`, `together_events_contracts.sql`); `ok | 17 passed | 0 failed`.

- [ ] **Step 2: Write the failing contract**

Create `supabase/tests/support_resources_contracts.sql` with exactly:

```sql
-- supabase/tests/support_resources_contracts.sql
-- Spec 1 W7a (§4.2, §4.3 W7a, §7.1): support resources v2. Anyone reads the
-- directory through get_support_resources (anon too); emergency first,
-- then the country's own rows, then anywhere (XX); only active rows; no
-- client writes the table; the service-role loader replaces the catalogue
-- whole or not at all. Fixture rows only, never the shipped catalogue.
-- One BEGIN ... ROLLBACK.
-- Run only on attune_spec3a:
--   psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/support_resources_contracts.sql
-- Fixture ids 5f7a0000-0000-0000-0000-0000000000NN (spec §7.1's W7 range;
-- no person is needed, so no phone). Every refusal is checked by its
-- message or SQLSTATE.
BEGIN;

CREATE FUNCTION pg_temp.id(p_n text) RETURNS uuid LANGUAGE sql AS $$
  SELECT ('5f7a0000-0000-0000-0000-0000000000' || p_n)::uuid;
$$;

-- get_support_resources as [p_role] (anon or authenticated).
CREATE FUNCTION pg_temp.read_as(p_role text, p_country text) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
  v jsonb;
BEGIN
  EXECUTE format('SET LOCAL ROLE %I', p_role);
  v := public.get_support_resources(p_country);
  RESET ROLE;
  RETURN v;
END $$;

-- The SQLSTATE (or NULL) of [p_sql] run as [p_role].
CREATE FUNCTION pg_temp.client_error(p_role text, p_sql text) RETURNS text LANGUAGE plpgsql AS $$
DECLARE
  v text;
BEGIN
  EXECUTE format('SET LOCAL ROLE %I', p_role);
  BEGIN
    EXECUTE p_sql;
  EXCEPTION WHEN OTHERS THEN
    v := SQLSTATE;
  END;
  RESET ROLE;
  RETURN v;
END $$;

-- The loader as the service role: NULL, or the refusal's message.
CREATE FUNCTION pg_temp.load(p_catalogue jsonb) RETURNS text LANGUAGE plpgsql AS $$
DECLARE
  v text;
BEGIN
  EXECUTE 'SET LOCAL ROLE service_role';
  BEGIN
    PERFORM public.load_support_resources(p_catalogue);
  EXCEPTION WHEN OTHERS THEN
    v := SQLERRM;
  END;
  RESET ROLE;
  RETURN v;
END $$;

-- One catalogue entry (the file's shape).
CREATE FUNCTION pg_temp.entry(p_n text, p_country text, p_category text, p_name text,
                              p_sort int DEFAULT 100, p_url text DEFAULT NULL, p_phone text DEFAULT '0800 000 000')
RETURNS jsonb LANGUAGE sql AS $$
  SELECT jsonb_build_object('id', pg_temp.id(p_n), 'country_code', p_country, 'category', p_category,
                            'name', p_name, 'phone', p_phone, 'url', p_url, 'languages', jsonb_build_array('en'),
                            'is_police', p_category = 'emergency', 'sort_order', p_sort,
                            'verified_at', '2026-11-03', 'verified_by', 'contract fixture');
$$;

-- Fixture rows only: whatever the scratch database holds is set aside
-- (rolled back with the rest).
DO $$
BEGIN
  IF to_regclass('public.support_resources') IS NOT NULL THEN
    DELETE FROM public.support_resources;
  END IF;
END $$;

-- =====================================================================
-- A. Objects and grants: anon and signed-in read through the function
--    only; nobody but the service role writes (spec §4.2, §7.1).
-- =====================================================================
DO $$
BEGIN
  IF to_regclass('public.support_resources') IS NULL
     OR to_regprocedure('public.get_support_resources(text)') IS NULL
     OR to_regprocedure('public.load_support_resources(jsonb)') IS NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: W7a objects are missing';
  END IF;
  IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid = 'public.support_resources'::regclass)
     OR EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'support_resources') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: support_resources must have RLS on and no policy (read through the function only)';
  END IF;
  IF has_table_privilege('anon', 'public.support_resources', 'SELECT')
     OR has_table_privilege('anon', 'public.support_resources', 'INSERT')
     OR has_table_privilege('anon', 'public.support_resources', 'UPDATE')
     OR has_table_privilege('anon', 'public.support_resources', 'DELETE')
     OR has_table_privilege('authenticated', 'public.support_resources', 'SELECT')
     OR has_table_privilege('authenticated', 'public.support_resources', 'INSERT')
     OR has_table_privilege('authenticated', 'public.support_resources', 'UPDATE')
     OR has_table_privilege('authenticated', 'public.support_resources', 'DELETE')
     OR NOT has_table_privilege('service_role', 'public.support_resources', 'INSERT') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: support_resources table grants are wrong (no client write)';
  END IF;
  IF NOT has_function_privilege('anon', 'public.get_support_resources(text)', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.get_support_resources(text)', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: get_support_resources is not readable by anon and authenticated';
  END IF;
  IF has_function_privilege('anon', 'public.load_support_resources(jsonb)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.load_support_resources(jsonb)', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'public.load_support_resources(jsonb)', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: load_support_resources must be the service role''s only';
  END IF;
END $$;

-- =====================================================================
-- B. Reading: emergency first, the country before anywhere, sort_order,
--    active rows only, never another country's (spec §4.3 W7a).
-- =====================================================================
DO $$
DECLARE
  v jsonb;
  v_names text;
BEGIN
  IF pg_temp.load(jsonb_build_object('catalogue_version', 'fixture-1', 'resources', jsonb_build_array(
       pg_temp.entry('01', 'GH', 'dv', 'GH DV line', 10),
       pg_temp.entry('02', 'GH', 'emergency', 'GH emergency', 90),
       pg_temp.entry('03', 'GH', 'crisis', 'GH crisis line', 5),
       pg_temp.entry('04', 'XX', 'crisis', 'Anywhere directory', 1, 'https://findahelpline.com', NULL),
       pg_temp.entry('05', 'GB', 'dv', 'GB DV line', 1),
       pg_temp.entry('06', 'GH', 'grief', 'GH grief line', 20)))) IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a valid fixture catalogue was refused';
  END IF;
  UPDATE public.support_resources SET active = false WHERE id = pg_temp.id('06');

  v := pg_temp.read_as('anon', ' gh ');
  SELECT string_agg(x ->> 'name', ' | ' ORDER BY o) INTO v_names
    FROM jsonb_array_elements(v -> 'resources') WITH ORDINALITY AS t(x, o);
  IF v_names IS DISTINCT FROM 'GH emergency | GH crisis line | GH DV line | Anywhere directory' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: Ghana''s list is not emergency first, then the country by sort_order, then anywhere (inactive and other countries left out): %', v_names;
  END IF;
  IF (v ->> 'country') IS DISTINCT FROM 'GH' OR (v -> 'country_supported') IS DISTINCT FROM 'true'::jsonb
     OR (v ->> 'catalogue_version') IS DISTINCT FROM 'fixture-1' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: Ghana''s answer has the wrong header: %', v - 'resources';
  END IF;
  IF (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(v) AS k)
       <> ARRAY['catalogue_version', 'country', 'country_supported', 'resources']
     OR (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(v -> 'resources' -> 0) AS k)
       <> ARRAY['category', 'country_code', 'description', 'hours', 'id', 'is_police', 'languages',
                'name', 'phone', 'sms', 'url', 'verified_at', 'whatsapp'] THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: get_support_resources returns other keys: %', v -> 'resources' -> 0;
  END IF;

  -- Signed in reads the same.
  IF pg_temp.read_as('authenticated', 'GH') IS DISTINCT FROM v THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a signed-in read differs from an anon one';
  END IF;

  -- A country with no list: anywhere only, and said so.
  FOREACH v_names IN ARRAY ARRAY['ZZ', 'zz', 'XX', '', 'Ghana'] LOOP
    v := pg_temp.read_as('anon', v_names);
    IF (v -> 'country_supported') IS DISTINCT FROM 'false'::jsonb
       OR jsonb_array_length(v -> 'resources') <> 1
       OR (v -> 'resources' -> 0 ->> 'country_code') IS DISTINCT FROM 'XX' THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: % without a list did not answer anywhere-only and unsupported: %', quote_literal(v_names), v;
    END IF;
  END LOOP;
  v := pg_temp.read_as('anon', NULL);
  IF (v -> 'country_supported') IS DISTINCT FROM 'false'::jsonb OR (v -> 'country') <> 'null'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: no country did not answer anywhere-only: %', v;
  END IF;
END $$;

-- =====================================================================
-- C. No client writes the directory, or reaches the loader (spec §7.1).
-- =====================================================================
DO $$
BEGIN
  IF pg_temp.client_error('anon', format(
       'INSERT INTO public.support_resources (id, country_code, category, name, phone, verified_at, verified_by, catalogue_version) VALUES (%L, ''GH'', ''dv'', ''Fake line'', ''0800'', current_date, ''x'', ''x'')',
       pg_temp.id('90'))) IS DISTINCT FROM '42501'
     OR pg_temp.client_error('authenticated', 'UPDATE public.support_resources SET phone = ''0800 999'' WHERE true') IS DISTINCT FROM '42501'
     OR pg_temp.client_error('authenticated', 'DELETE FROM public.support_resources WHERE true') IS DISTINCT FROM '42501'
     OR pg_temp.client_error('anon', 'SELECT count(*) FROM public.support_resources') IS DISTINCT FROM '42501'
     OR pg_temp.client_error('authenticated', 'SELECT public.load_support_resources(''{}''::jsonb)') IS DISTINCT FROM '42501'
     OR pg_temp.client_error('anon', 'SELECT public.load_support_resources(''{}''::jsonb)') IS DISTINCT FROM '42501' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a client wrote the directory or reached the loader';
  END IF;
  IF (SELECT phone FROM public.support_resources WHERE id = pg_temp.id('01')) IS DISTINCT FROM '0800 000 000' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a client changed a helpline number';
  END IF;
END $$;

-- =====================================================================
-- D. The loader: the whole file or nothing; a row the file drops goes
--    inactive; a bad file is refused by its message (plan P-3).
-- =====================================================================
DO $$
DECLARE
  v_got text;
BEGIN
  -- Version 2 drops GH crisis (03) and changes GH DV's number.
  v_got := pg_temp.load(jsonb_build_object('catalogue_version', 'fixture-2', 'resources', jsonb_build_array(
             pg_temp.entry('01', 'GH', 'dv', 'GH DV line', 10, NULL, '0800 111 111'),
             pg_temp.entry('02', 'GH', 'emergency', 'GH emergency', 90),
             pg_temp.entry('04', 'XX', 'crisis', 'Anywhere directory', 1, 'https://findahelpline.com', NULL))));
  IF v_got IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: version 2 was refused: %', v_got;
  END IF;
  IF (SELECT active FROM public.support_resources WHERE id = pg_temp.id('03'))
     OR (SELECT active FROM public.support_resources WHERE id = pg_temp.id('05'))
     OR (SELECT phone FROM public.support_resources WHERE id = pg_temp.id('01')) IS DISTINCT FROM '0800 111 111'
     OR EXISTS (SELECT 1 FROM public.support_resources WHERE active AND catalogue_version <> 'fixture-2') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a row the new catalogue dropped is still shown, or a change did not land';
  END IF;
  IF (pg_temp.read_as('anon', 'GH') ->> 'catalogue_version') IS DISTINCT FROM 'fixture-2' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the answer does not name the loaded version';
  END IF;

  -- Refusals, each by its message, each leaving version 2 in place.
  IF pg_temp.load('{"resources": []}'::jsonb) IS DISTINCT FROM 'support_resources:invalid_catalogue'
     OR pg_temp.load(jsonb_build_object('catalogue_version', 'fixture-3', 'resources', jsonb_build_array(
          pg_temp.entry('01', 'GH', 'dv', 'GH DV line'), pg_temp.entry('01', 'GH', 'dv', 'GH DV line twice'),
          pg_temp.entry('04', 'XX', 'crisis', 'Anywhere directory', 1, 'https://findahelpline.com', NULL))))
          IS DISTINCT FROM 'support_resources:duplicate_id'
     OR pg_temp.load(jsonb_build_object('catalogue_version', 'fixture-3', 'resources', jsonb_build_array(
          pg_temp.entry('01', 'GH', 'dv', 'GH DV line'))))
          IS DISTINCT FROM 'support_resources:no_international_directory' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a bad catalogue was not refused by its message';
  END IF;
  v_got := pg_temp.load(jsonb_build_object('catalogue_version', 'fixture-3', 'resources', jsonb_build_array(
             pg_temp.entry('07', 'GH', 'astrology', 'Not a category'),
             pg_temp.entry('04', 'XX', 'crisis', 'Anywhere directory', 1, 'https://findahelpline.com', NULL))));
  IF v_got !~ 'support_resources_category_check' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an unknown category was not refused by its check: %', v_got;
  END IF;
  v_got := pg_temp.load(jsonb_build_object('catalogue_version', 'fixture-3', 'resources', jsonb_build_array(
             pg_temp.entry('07', 'gh', 'dv', 'Lower-case country'),
             pg_temp.entry('04', 'XX', 'crisis', 'Anywhere directory', 1, 'https://findahelpline.com', NULL))));
  IF v_got !~ 'support_resources_country_check' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a lower-case country was not refused by its check: %', v_got;
  END IF;
  v_got := pg_temp.load(jsonb_build_object('catalogue_version', 'fixture-3', 'resources', jsonb_build_array(
             pg_temp.entry('07', 'GH', 'dv', 'Plain http', 1, 'http://example.org', NULL),
             pg_temp.entry('04', 'XX', 'crisis', 'Anywhere directory', 1, 'https://findahelpline.com', NULL))));
  IF v_got !~ 'support_resources_url_check' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a link that is not https was not refused by its check: %', v_got;
  END IF;
  v_got := pg_temp.load(jsonb_build_object('catalogue_version', 'fixture-3', 'resources', jsonb_build_array(
             pg_temp.entry('07', 'GH', 'dv', 'No way to reach', 1, NULL, NULL),
             pg_temp.entry('04', 'XX', 'crisis', 'Anywhere directory', 1, 'https://findahelpline.com', NULL))));
  IF v_got !~ 'support_resources_reachable_check' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an entry with no number or link was not refused by its check: %', v_got;
  END IF;
  IF EXISTS (SELECT 1 FROM public.support_resources WHERE active AND catalogue_version <> 'fixture-2')
     OR EXISTS (SELECT 1 FROM public.support_resources WHERE id = pg_temp.id('07')) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a refused catalogue changed the directory';
  END IF;
END $$;

DO $$ BEGIN RAISE NOTICE 'support_resources_contracts: all held'; END $$;

ROLLBACK;
```

- [ ] **Step 3: Run it to make sure it fails**

```bash
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/support_resources_contracts.sql 2>&1 | grep ERROR | sed -E 's/^psql:[^ ]* //'
```

Expected: `ERROR:  CONTRACT VIOLATED: W7a objects are missing`.

- [ ] **Step 4: Write migration 14 and its twin**

Create `supabase/migrations/20261103130000_support_resources_v2.sql` with exactly:

```sql
-- Spec 1 W7a, migration 14 (spec §4.7 #14): support resources v2.
--   * public.support_resources (spec §4.2): one row per checked helpline,
--     by country (ISO 3166-1 alpha-2, or XX for anywhere) and category.
--     RLS on with no policy: read only through get_support_resources.
--     Loaded by scripts/load_support_resources.sh (service role) from
--     assets/support_resources/catalogue.json, the file the app bundles for
--     offline use.
--   * get_support_resources(p_country) (anon, authenticated): the active
--     rows for the country plus XX, emergency first, then the country's own
--     rows before XX, then sort_order, then name:
--     {country, country_supported, catalogue_version, resources:[...]}.
--     country_supported is true only when the country has a row of its own.
--   * load_support_resources(p_catalogue) (service role, plan P-3): the
--     catalogue file in one transaction: every entry upserted by id and
--     active, every other row made inactive, refused whole when an entry is
--     bad, an id repeats, or there is no XX entry with a link (the
--     fallback "Find a helpline" always has somewhere to go).
-- Nothing here holds a person's data: the table is a public directory.
-- Grants in 20261103130010_support_resources_v2_grants.sql.
BEGIN;
SET LOCAL lock_timeout = '5s';

CREATE TABLE IF NOT EXISTS public.support_resources (
  id uuid PRIMARY KEY,
  country_code text NOT NULL
    CONSTRAINT support_resources_country_check CHECK (country_code ~ '^([A-Z]{2}|XX)$'),
  category text NOT NULL
    CONSTRAINT support_resources_category_check CHECK (category IN (
      'emergency', 'dv', 'crisis', 'sexual_assault', 'sextortion', 'child_safety',
      'youth', 'lgbtq_legal', 'grief', 'perinatal', 'addiction', 'financial_control')),
  name text NOT NULL
    CONSTRAINT support_resources_name_check CHECK (char_length(btrim(name)) BETWEEN 1 AND 120),
  description text
    CONSTRAINT support_resources_description_check CHECK (description IS NULL OR char_length(description) <= 400),
  phone text
    CONSTRAINT support_resources_phone_check CHECK (phone IS NULL OR phone ~ '^[0-9A-Za-z+() .-]{2,40}$'),
  sms text
    CONSTRAINT support_resources_sms_check CHECK (sms IS NULL OR sms ~ '^[0-9A-Za-z+() .-]{2,40}$'),
  whatsapp text
    CONSTRAINT support_resources_whatsapp_check CHECK (whatsapp IS NULL OR whatsapp ~ '^\+[0-9 ]{6,24}$'),
  url text
    CONSTRAINT support_resources_url_check CHECK (url IS NULL OR (url ~ '^https://\S+$' AND char_length(url) <= 300)),
  hours text
    CONSTRAINT support_resources_hours_check CHECK (hours IS NULL OR char_length(hours) <= 120),
  languages text[] NOT NULL DEFAULT '{}',
  is_police boolean NOT NULL DEFAULT false,
  sort_order int NOT NULL DEFAULT 100,
  verified_at date NOT NULL,
  verified_by text NOT NULL
    CONSTRAINT support_resources_verified_by_check CHECK (char_length(btrim(verified_by)) BETWEEN 1 AND 120),
  catalogue_version text NOT NULL
    CONSTRAINT support_resources_version_check CHECK (catalogue_version ~ '^[0-9A-Za-z._-]{1,40}$'),
  active boolean NOT NULL DEFAULT true,
  -- A row with no way to reach anyone helps nobody.
  CONSTRAINT support_resources_reachable_check
    CHECK (phone IS NOT NULL OR sms IS NOT NULL OR whatsapp IS NOT NULL OR url IS NOT NULL)
);
CREATE INDEX IF NOT EXISTS support_resources_country_idx
  ON public.support_resources (country_code) WHERE active;
ALTER TABLE public.support_resources ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.get_support_resources(p_country text)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  WITH c AS (
    SELECT CASE WHEN upper(btrim(coalesce(p_country, ''))) ~ '^[A-Z]{2}$'
                 AND upper(btrim(p_country)) <> 'XX'
                THEN upper(btrim(p_country)) END AS code
  ), picked AS (
    SELECT r.*
      FROM public.support_resources AS r, c
     WHERE r.active AND (r.country_code = c.code OR r.country_code = 'XX')
  )
  SELECT jsonb_build_object(
    'country', (SELECT c.code FROM c),
    'country_supported', EXISTS (SELECT 1 FROM picked AS p, c WHERE p.country_code = c.code),
    'catalogue_version', (SELECT max(r.catalogue_version) FROM public.support_resources AS r WHERE r.active),
    'resources', coalesce((
      SELECT jsonb_agg(jsonb_build_object(
               'id', p.id, 'country_code', p.country_code, 'category', p.category,
               'name', p.name, 'description', p.description, 'phone', p.phone,
               'sms', p.sms, 'whatsapp', p.whatsapp, 'url', p.url, 'hours', p.hours,
               'languages', to_jsonb(p.languages), 'is_police', p.is_police,
               'verified_at', p.verified_at)
             ORDER BY (p.category <> 'emergency'), (p.country_code = 'XX'), p.sort_order, p.name, p.id)
        FROM picked AS p), '[]'::jsonb));
$$;

CREATE OR REPLACE FUNCTION public.load_support_resources(p_catalogue jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_version constant text := btrim(coalesce(p_catalogue ->> 'catalogue_version', ''));
  v_entries constant jsonb := p_catalogue -> 'resources';
  v_loaded int;
  v_inactive int;
BEGIN
  IF v_version = '' OR jsonb_typeof(v_entries) IS DISTINCT FROM 'array' OR jsonb_array_length(v_entries) = 0 THEN
    RAISE EXCEPTION 'support_resources:invalid_catalogue';
  END IF;
  IF (SELECT count(*) <> count(DISTINCT e ->> 'id') FROM jsonb_array_elements(v_entries) AS e) THEN
    RAISE EXCEPTION 'support_resources:duplicate_id';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_entries) AS e
                  WHERE e ->> 'country_code' = 'XX' AND coalesce(e ->> 'url', '') <> '') THEN
    RAISE EXCEPTION 'support_resources:no_international_directory';
  END IF;

  INSERT INTO public.support_resources AS r
    (id, country_code, category, name, description, phone, sms, whatsapp, url, hours,
     languages, is_police, sort_order, verified_at, verified_by, catalogue_version, active)
  SELECT x.id, x.country_code, x.category, x.name, x.description, x.phone, x.sms, x.whatsapp,
         x.url, x.hours, coalesce(x.languages, '{}'), coalesce(x.is_police, false),
         coalesce(x.sort_order, 100), x.verified_at, x.verified_by, v_version, true
    FROM jsonb_to_recordset(v_entries) AS x(
           id uuid, country_code text, category text, name text, description text,
           phone text, sms text, whatsapp text, url text, hours text, languages text[],
           is_police boolean, sort_order int, verified_at date, verified_by text)
  ON CONFLICT (id) DO UPDATE
    SET country_code = EXCLUDED.country_code, category = EXCLUDED.category, name = EXCLUDED.name,
        description = EXCLUDED.description, phone = EXCLUDED.phone, sms = EXCLUDED.sms,
        whatsapp = EXCLUDED.whatsapp, url = EXCLUDED.url, hours = EXCLUDED.hours,
        languages = EXCLUDED.languages, is_police = EXCLUDED.is_police,
        sort_order = EXCLUDED.sort_order, verified_at = EXCLUDED.verified_at,
        verified_by = EXCLUDED.verified_by, catalogue_version = EXCLUDED.catalogue_version,
        active = true;
  GET DIAGNOSTICS v_loaded = ROW_COUNT;

  UPDATE public.support_resources AS r
     SET active = false
   WHERE r.active
     AND r.id NOT IN (SELECT (e ->> 'id')::uuid FROM jsonb_array_elements(v_entries) AS e);
  GET DIAGNOSTICS v_inactive = ROW_COUNT;

  RETURN jsonb_build_object('catalogue_version', v_version, 'loaded', v_loaded, 'deactivated', v_inactive);
END;
$$;

-- Revoked here as well as in the twin (the W1 precedent): the hosted
-- default privileges grant a new table and function to anon and
-- authenticated, and a late twin must not leave the table writable or the
-- loader callable. get_support_resources is the one client read and is
-- granted in the twin.
REVOKE ALL ON public.support_resources FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.load_support_resources(jsonb) FROM PUBLIC, anon, authenticated;

COMMIT;
```

Create `supabase/migrations/20261103130010_support_resources_v2_grants.sql` with exactly:

```sql
-- Spec 1 W7a: grants for 20261103130000_support_resources_v2.sql. Anyone,
-- signed in or not, reads the directory through get_support_resources (the
-- Support screen opens before sign-in, spec §5.4); only the service role
-- writes it, through load_support_resources.
BEGIN;
SET LOCAL lock_timeout = '5s';
REVOKE ALL ON public.support_resources FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.support_resources TO service_role;
REVOKE ALL ON FUNCTION public.get_support_resources(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.load_support_resources(jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_support_resources(text) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.load_support_resources(jsonb) TO service_role;
COMMIT;
```

- [ ] **Step 5: Apply each file twice, then run the contract**

```bash
for i in 1 2; do
  for f in 20261103130000_support_resources_v2 20261103130010_support_resources_v2_grants; do
    psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/migrations/$f.sql > /dev/null 2>&1; echo "$f exit=$?"
  done
done
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/support_resources_contracts.sql 2>&1 | tail -1 | sed -E 's/^psql:[^ ]* //'
```

Expected: four `exit=0` lines; `NOTICE:  support_resources_contracts: all held`.

- [ ] **Step 6: Mutation checks (each must turn the contract red with the message quoted)**

```bash
M=supabase/migrations/20261103130000_support_resources_v2.sql
G=supabase/migrations/20261103130010_support_resources_v2_grants.sql
C=supabase/tests/support_resources_contracts.sql
D=.superpowers/sdd/2026-11-03-spec1-w7
python3 -I - "$M" "$D" <<'PY'
import pathlib, sys
m = pathlib.Path(sys.argv[1]).read_text()
d = pathlib.Path(sys.argv[2])
muts = {
  'emergency_not_first': ("ORDER BY (p.category <> 'emergency'), (p.country_code = 'XX'), p.sort_order",
                          "ORDER BY (p.country_code = 'XX'), p.sort_order"),
  'inactive_shown': ("WHERE r.active AND (r.country_code = c.code OR r.country_code = 'XX')",
                     "WHERE (r.country_code = c.code OR r.country_code = 'XX')"),
  'every_country': ("WHERE r.active AND (r.country_code = c.code OR r.country_code = 'XX')", "WHERE r.active"),
  'no_deactivate': ("     SET active = false\n   WHERE r.active\n", "     SET active = r.active\n   WHERE r.active\n"),
  'no_directory_check': ("    RAISE EXCEPTION 'support_resources:no_international_directory';", "    NULL;"),
}
for name, (a, b) in muts.items():
    assert m.count(a) == 1, name
    (d / f"mut_{name}.sql").write_text(m.replace(a, b))
(d / 'mut_anon_write.sql').write_text("GRANT INSERT, UPDATE ON public.support_resources TO anon;\n")
(d / 'mut_anon_no_read.sql').write_text("REVOKE EXECUTE ON FUNCTION public.get_support_resources(text) FROM anon;\n")
(d / 'mut_client_loader.sql').write_text("GRANT EXECUTE ON FUNCTION public.load_support_resources(jsonb) TO authenticated;\n")
print('mutants written')
PY
for m in emergency_not_first inactive_shown every_country no_deactivate no_directory_check anon_write anon_no_read client_loader; do
  psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f $D/mut_$m.sql > /dev/null 2>&1
  echo "$m: $(psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f $C 2>&1 | grep ERROR | sed -E 's/^psql:[^ ]* //' | cut -c1-140)"
  psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f $M -f $G > /dev/null 2>&1
done
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f $C 2>&1 | tail -1
rm $D/mut_*.sql
```

Expected: `mutants written`, then:
- `emergency_not_first`: `ERROR:  CONTRACT VIOLATED: Ghana's list is not emergency first, then the country by sort_order, then anywhere (inactive and other countries …`
- `inactive_shown`: the same message (an inactive row is listed)
- `every_country`: the same message (Britain's row is listed for Ghana)
- `no_deactivate`: `ERROR:  CONTRACT VIOLATED: a row the new catalogue dropped is still shown, or a change did not land`
- `no_directory_check`: `ERROR:  CONTRACT VIOLATED: a bad catalogue was not refused by its message`
- `anon_write`: `ERROR:  CONTRACT VIOLATED: support_resources table grants are wrong (no client write)`
- `anon_no_read`: `ERROR:  CONTRACT VIOLATED: get_support_resources is not readable by anon and authenticated`
- `client_loader`: `ERROR:  CONTRACT VIOLATED: load_support_resources must be the service role's only`

then `NOTICE:  support_resources_contracts: all held`.

- [ ] **Step 7: The local harness (edit only, never run)**

`scripts/local_pg_grants.sql`, edit 1 of 1. Replace exactly:

```sql
\i supabase/migrations/20261103120010_child_safety_reports_grants.sql
```

with:

```sql
\i supabase/migrations/20261103120010_child_safety_reports_grants.sql

-- Spec 1 W7a: anyone reads the support directory through
-- get_support_resources; only the service role loads it.
\i supabase/migrations/20261103130010_support_resources_v2_grants.sql
```

- [ ] **Step 8: Run tests**

```bash
for f in supabase/tests/*.sql; do
  if psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f "$f" >/dev/null 2>&1; then echo "PASS $(basename "$f")"; else echo "FAIL $(basename "$f")"; fi
done > .superpowers/sdd/2026-11-03-spec1-w7/sql-after-task1.txt
grep '^FAIL' .superpowers/sdd/2026-11-03-spec1-w7/sql-after-task1.txt | comm -13 <(grep '^FAIL' .superpowers/sdd/2026-11-03-spec1-w7/sql-baseline.txt) -
grep -E 'support_resources|identity_foundation' .superpowers/sdd/2026-11-03-spec1-w7/sql-after-task1.txt
```

Expected: no new FAIL line; `PASS identity_foundation_contracts.sql`, `PASS support_resources_contracts.sql`.

### Task 2: The catalogue, its loader, the phone's directory and the release check (§4.2, §8 W7a; P-3-P-6, P-10)

**Files:**
- Create: `assets/support_resources/catalogue.json`
- Create: `scripts/load_support_resources.sh` (executable)
- Create: `lib/features/safety/data/support_resources_repository.dart`
- Create: `test/features/safety/w7/support_resources_repository_test.dart`
- Create: `test/launch/support_resources_release_test.dart`
- Modify: `pubspec.yaml` (one asset folder)

**Interfaces:**
- Consumes: Task 1's `get_support_resources` (its JSON shape) and `load_support_resources`.
- Produces: `enum SupportCategory` (`.wire`, `fromWire`), `supportAnywhere = 'XX'`, `supportDirectoryUrl = 'https://findahelpline.com'`, `class SupportResource` (`id`, `countryCode`, `category`, `name`, `description`, `phone`, `sms`, `whatsapp`, `url`, `hours`, `languages`, `isPolice`, `sortOrder`, `isAnywhere`; `static SupportResource? fromJson(Object?)`), `class SupportResources` (`country`, `countrySupported`, `catalogueVersion`, `resources`, `fromServer`; `emergency`, `inCategory(c)`, `anywhere`, `directoryUrl`; `SupportResources.fromServer(Map)`), `String? normaliseSupportCountry(String?)`, `class SupportCatalogue` (`parse(String)`, `forCountry(String?)`), `String supportDialString(String)`, `typedef SupportRpc`, `class SupportResourcesRepository({rpc, loadBundled, timeout = defaultTimeout})` with `Future<SupportResources> load(String? country)` and `defaultTimeout = 8 s`.

- [ ] **Step 1: Write the failing tests**

Create `test/features/safety/w7/support_resources_repository_test.dart` with exactly:

```dart
// Spec 1 W7a (§4.3 W7a): the support directory on the phone. The bundled
// catalogue answers with the server's own rule (the same fixture rows as
// support_resources_contracts.sql section B give the same order); the
// server is read first and the bundle answers when it fails, times out or
// is empty; numbers dial as printed.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:attune/features/safety/data/support_resources_repository.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> _entry(
  String n,
  String country,
  String category,
  String name, {
  int sort = 100,
  String? url,
  String? phone = '0800 000 000',
}) => {
  'id': '5f7a0000-0000-0000-0000-0000000000$n',
  'country_code': country,
  'category': category,
  'name': name,
  'phone': phone,
  'url': url,
  'languages': ['en'],
  'is_police': category == 'emergency',
  'sort_order': sort,
  'verified_at': '2026-11-03',
  'verified_by': 'test fixture',
};

final _fixture = jsonEncode({
  'catalogue_version': 'fixture-1',
  'resources': [
    _entry('01', 'GH', 'dv', 'GH DV line', sort: 10),
    _entry('02', 'GH', 'emergency', 'GH emergency', sort: 90),
    _entry('03', 'GH', 'crisis', 'GH crisis line', sort: 5),
    _entry(
      '04',
      'XX',
      'crisis',
      'Anywhere directory',
      sort: 1,
      url: 'https://findahelpline.com',
      phone: null,
    ),
    _entry('05', 'GB', 'dv', 'GB DV line', sort: 1),
    _entry('06', 'GH', 'astrology', 'Unknown category'),
    _entry('07', 'GH', 'dv', 'No way to reach', phone: null),
  ],
});

SupportResourcesRepository _repo(
  Future<Object?> Function() server, {
  List<String>? calls,
}) => SupportResourcesRepository(
  rpc: (fn, params) {
    calls?.add('$fn ${jsonEncode(params)}');
    return server();
  },
  loadBundled: () async => _fixture,
);

void main() {
  test(
    'the bundle answers with the server rule (contract section B order)',
    () {
      final gh = SupportCatalogue.parse(_fixture).forCountry(' gh ');
      expect(
        [for (final r in gh.resources) r.name],
        ['GH emergency', 'GH crisis line', 'GH DV line', 'Anywhere directory'],
      );
      expect(gh.country, 'GH');
      expect(gh.countrySupported, isTrue);
      expect(gh.catalogueVersion, 'fixture-1');
      expect(gh.fromServer, isFalse);
      expect([for (final r in gh.emergency) r.name], ['GH emergency']);
      expect([for (final r in gh.anywhere) r.name], ['Anywhere directory']);
    },
  );

  test('no list for a country, or no country: anywhere only, unsupported', () {
    final catalogue = SupportCatalogue.parse(_fixture);
    for (final country in ['ZZ', 'xx', '', 'Ghana', null]) {
      final answer = catalogue.forCountry(country);
      expect(answer.countrySupported, isFalse, reason: '$country');
      expect(
        [for (final r in answer.resources) r.countryCode],
        ['XX'],
        reason: '$country',
      );
      expect(answer.directoryUrl, 'https://findahelpline.com');
    }
  });

  test('server first; its answer is used as it comes', () async {
    final calls = <String>[];
    final answer = await _repo(
      () async => {
        'country': 'GB',
        'country_supported': true,
        'catalogue_version': 'server-7',
        'resources': [_entry('05', 'GB', 'dv', 'GB DV line from server')],
      },
      calls: calls,
    ).load('gb');
    expect(calls, ['get_support_resources {"p_country":"GB"}']);
    expect(answer.fromServer, isTrue);
    expect(answer.catalogueVersion, 'server-7');
    expect(answer.resources.single.name, 'GB DV line from server');
  });

  test('a failing server falls back to the bundle', () async {
    final answer = await _repo(
      () async => throw const SocketException('x'),
    ).load('GH');
    expect(answer.fromServer, isFalse);
    expect(answer.resources.first.name, 'GH emergency');
  });

  test('a server with nothing loaded falls back to the bundle', () async {
    final answer = await _repo(
      () async => {
        'country': 'GH',
        'country_supported': false,
        'catalogue_version': null,
        'resources': <Object>[],
      },
    ).load('GH');
    expect(answer.fromServer, isFalse);
    expect(answer.countrySupported, isTrue);
  });

  test('a malformed answer falls back to the bundle', () async {
    final answer = await _repo(() async => 'not a map').load('GH');
    expect(answer.fromServer, isFalse);
  });

  test('a slow server falls back to the bundle after the timeout', () async {
    final never = Completer<Object?>();
    final answer = await SupportResourcesRepository(
      rpc: (_, __) => never.future,
      loadBundled: () async => _fixture,
      timeout: const Duration(milliseconds: 50),
    ).load('GH');
    expect(answer.fromServer, isFalse);
    expect(
      SupportResourcesRepository.defaultTimeout,
      const Duration(seconds: 8),
    );
  });

  test('rows this build cannot show are left out, never half shown', () {
    final names = [
      for (final r in SupportCatalogue.parse(_fixture).entries) r.name,
    ];
    expect(names, isNot(contains('Unknown category')));
    expect(names, isNot(contains('No way to reach')));
  });

  test('numbers dial as printed', () {
    expect(supportDialString('055 100 0900'), '0551000900');
    expect(supportDialString('800-799-SAFE (7233)'), '8007997233');
    expect(supportDialString('0808 2000 247'), '08082000247');
    expect(supportDialString('+44 (0)20 0000 0000'), '+442000000000');
    expect(supportDialString('116 123'), '116123');
  });

  testWidgets('the app bundles the catalogue (pubspec assets)', (tester) async {
    final bundled = await rootBundle.loadString(
      'assets/support_resources/catalogue.json',
    );
    expect(
      bundled,
      File('assets/support_resources/catalogue.json').readAsStringSync(),
    );
  });

  test('the shipped catalogue parses whole and has its directory', () {
    final source =
        File('assets/support_resources/catalogue.json').readAsStringSync();
    final raw = (jsonDecode(source) as Map)['resources'] as List;
    final catalogue = SupportCatalogue.parse(source);
    expect(catalogue.entries, hasLength(raw.length));
    expect(
      catalogue.forCountry('ZZ').directoryUrl,
      'https://findahelpline.com',
    );
  });
}
```

Create `test/launch/support_resources_release_test.dart` with exactly:

```dart
// Spec 1 W7a (§8 W7a): the bundled support catalogue is never shipped
// stale. Every entry for a Tier A country (Ghana, the UK, the US, Canada)
// must have been checked within 90 days, and within 7 days on a release
// tag (GitHub sets GITHUB_REF_TYPE=tag for a tag push). There must always
// be an anywhere (XX) entry with a link, the fallback for every country
// without a checked list. A wrong crisis number is a safety harm, so the
// rule is applied to the shipped file itself (last test); the rule is
// proven on fixtures first.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const tierA = {'GH', 'GB', 'US', 'CA'};

/// Everything wrong with [catalogue] on [today]; empty when it may ship.
List<String> catalogueProblems(
  Map<String, dynamic> catalogue, {
  required DateTime today,
  required bool releaseTag,
}) {
  final maxDays = releaseTag ? 7 : 90;
  final day = DateTime.utc(today.year, today.month, today.day);
  final problems = <String>[];
  final entries = (catalogue['resources'] as List).cast<Map>();
  for (final e in entries) {
    final country = e['country_code'];
    if (!tierA.contains(country)) continue;
    final checked = DateTime.tryParse('${e['verified_at']}');
    if (checked == null) {
      problems.add('$country ${e['name']}: no verified_at');
      continue;
    }
    final age =
        day
            .difference(DateTime.utc(checked.year, checked.month, checked.day))
            .inDays;
    if (age > maxDays) {
      problems.add(
        '$country ${e['name']}: checked $age days ago (at most $maxDays)',
      );
    }
  }
  final directory = entries.any(
    (e) =>
        e['country_code'] == 'XX' && '${e['url'] ?? ''}'.startsWith('https://'),
  );
  if (!directory) problems.add('no anywhere (XX) entry with a link');
  return problems;
}

Map<String, dynamic> _catalogue(List<Map<String, Object?>> rows) => {
  'catalogue_version': 'fixture',
  'resources': rows,
};

Map<String, Object?> _row(String country, String verifiedAt, {String? url}) => {
  'country_code': country,
  'name': '$country line',
  'url': url,
  'verified_at': verifiedAt,
};

final _directory = _row('XX', '2020-01-01', url: 'https://findahelpline.com');

void main() {
  final today = DateTime.utc(2026, 11, 3);

  test('90 days ordinarily; Tier A only', () {
    final fresh = _catalogue([
      _row('GH', '2026-08-05'),
      _row('KE', '2020-01-01'),
      _directory,
    ]);
    expect(catalogueProblems(fresh, today: today, releaseTag: false), isEmpty);
    final stale = _catalogue([_row('GB', '2026-08-04'), _directory]);
    expect(catalogueProblems(stale, today: today, releaseTag: false), [
      'GB GB line: checked 91 days ago (at most 90)',
    ]);
  });

  test('7 days on a release tag', () {
    final week = _catalogue([_row('US', '2026-10-27'), _directory]);
    expect(catalogueProblems(week, today: today, releaseTag: true), isEmpty);
    final eight = _catalogue([_row('CA', '2026-10-26'), _directory]);
    expect(catalogueProblems(eight, today: today, releaseTag: true), [
      'CA CA line: checked 8 days ago (at most 7)',
    ]);
  });

  test('there is always somewhere to go', () {
    expect(
      catalogueProblems(
        _catalogue([_row('GH', '2026-11-03')]),
        today: today,
        releaseTag: false,
      ),
      ['no anywhere (XX) entry with a link'],
    );
  });

  test('the shipped catalogue may ship today', () {
    final catalogue =
        jsonDecode(
              File(
                'assets/support_resources/catalogue.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    final releaseTag = Platform.environment['GITHUB_REF_TYPE'] == 'tag';
    expect(
      catalogueProblems(
        catalogue,
        today: DateTime.now().toUtc(),
        releaseTag: releaseTag,
      ),
      isEmpty,
      reason:
          'Re-check these entries with a named reviewer, update verified_at and '
          'verified_by in assets/support_resources/catalogue.json, and load it '
          '(scripts/load_support_resources.sh).',
    );
  });
}
```

- [ ] **Step 2: Run them to make sure they fail**

```bash
flutter test test/features/safety/w7/support_resources_repository_test.dart test/launch/support_resources_release_test.dart 2>&1 | grep -E "No such file|PathNotFound|Some tests failed" | head -3
```

Expected: the repository test does not load (`Error when reading 'lib/features/safety/data/support_resources_repository.dart': No such file or directory`), and the release check's last test fails with `PathNotFoundException` for `assets/support_resources/catalogue.json`; `Some tests failed`.

- [ ] **Step 3: Write the catalogue, the repository, the asset line and the loader**

The catalogue holds only today's three helplines, word for word, and the international directory (P-4). Never add a number here that a named person has not checked.

Create `assets/support_resources/catalogue.json` with exactly:

```json
{
  "catalogue_version": "2026-11-03.1",
  "resources": [
    {
      "id": "4aa75099-930c-4bf5-b773-ee9387f04fab",
      "country_code": "GH",
      "category": "dv",
      "name": "Ghana Police DOVVSU",
      "description": null,
      "phone": "055 100 0900",
      "sms": null,
      "whatsapp": null,
      "url": "https://police.gov.gh/",
      "hours": null,
      "languages": [],
      "is_police": true,
      "sort_order": 10,
      "verified_at": "2026-11-03",
      "verified_by": "carried-from-v1"
    },
    {
      "id": "d244340f-397a-4d07-ad11-c4f017f1dca6",
      "country_code": "US",
      "category": "dv",
      "name": "National Domestic Violence Hotline",
      "description": null,
      "phone": "800-799-SAFE (7233)",
      "sms": null,
      "whatsapp": null,
      "url": "https://www.thehotline.org/",
      "hours": null,
      "languages": [],
      "is_police": false,
      "sort_order": 10,
      "verified_at": "2026-11-03",
      "verified_by": "carried-from-v1"
    },
    {
      "id": "bcc82e60-d2bf-424a-9686-0bb2a15a195d",
      "country_code": "GB",
      "category": "dv",
      "name": "Refuge National Domestic Abuse Helpline",
      "description": null,
      "phone": "0808 2000 247",
      "sms": null,
      "whatsapp": null,
      "url": "https://www.refuge.org.uk/",
      "hours": null,
      "languages": [],
      "is_police": false,
      "sort_order": 10,
      "verified_at": "2026-11-03",
      "verified_by": "carried-from-v1"
    },
    {
      "id": "e4fc8603-3679-468e-86c9-e8d6e0a3e89e",
      "country_code": "XX",
      "category": "crisis",
      "name": "Find A Helpline",
      "description": null,
      "phone": null,
      "sms": null,
      "whatsapp": null,
      "url": "https://findahelpline.com",
      "hours": null,
      "languages": [],
      "is_police": false,
      "sort_order": 10,
      "verified_at": "2026-11-03",
      "verified_by": "carried-from-v1"
    }
  ]
}
```

Create `lib/features/safety/data/support_resources_repository.dart` with exactly:

```dart
import 'dart:async';
import 'dart:convert';

/// Spec 1 W7a (§4.2, §4.3 W7a): the support directory, by country.
///
/// The server's `get_support_resources` is read first; the catalogue the app
/// bundles (`assets/support_resources/catalogue.json`, the same file the
/// server is loaded from) answers when the server can't, or has nothing
/// loaded, so the screen is never empty offline. [SupportCatalogue.forCountry]
/// applies the server's rule exactly: active rows for the country plus
/// anywhere (`XX`), emergency first, then the country's own rows, then
/// `sort_order`, then name.
enum SupportCategory {
  emergency('emergency'),
  dv('dv'),
  crisis('crisis'),
  sexualAssault('sexual_assault'),
  sextortion('sextortion'),
  childSafety('child_safety'),
  youth('youth'),
  lgbtqLegal('lgbtq_legal'),
  grief('grief'),
  perinatal('perinatal'),
  addiction('addiction'),
  financialControl('financial_control');

  const SupportCategory(this.wire);

  final String wire;

  static SupportCategory? fromWire(Object? value) {
    for (final c in values) {
      if (c.wire == value) return c;
    }
    return null;
  }
}

/// `XX`: anywhere in the world.
const supportAnywhere = 'XX';

/// The international helpline directory: the fallback when a country has
/// no checked list and the catalogue offers no link of its own.
const supportDirectoryUrl = 'https://findahelpline.com';

class SupportResource {
  const SupportResource({
    required this.id,
    required this.countryCode,
    required this.category,
    required this.name,
    this.description,
    this.phone,
    this.sms,
    this.whatsapp,
    this.url,
    this.hours,
    this.languages = const [],
    this.isPolice = false,
    this.sortOrder = 100,
  });

  final String id;
  final String countryCode;
  final SupportCategory category;
  final String name;
  final String? description;
  final String? phone;
  final String? sms;
  final String? whatsapp;
  final String? url;
  final String? hours;
  final List<String> languages;
  final bool isPolice;
  final int sortOrder;

  bool get isAnywhere => countryCode == supportAnywhere;

  /// A row this build can't show (an unknown category, no name, no way to
  /// reach anyone) is null and left out, never shown half-formed.
  static SupportResource? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final category = SupportCategory.fromWire(raw['category']);
    final id = raw['id'];
    final country = raw['country_code'];
    final name = raw['name'];
    if (category == null ||
        id is! String ||
        country is! String ||
        name is! String ||
        name.trim().isEmpty) {
      return null;
    }
    String? text(String key) {
      final value = raw[key];
      return value is String && value.trim().isNotEmpty ? value.trim() : null;
    }

    final url = text('url');
    final resource = SupportResource(
      id: id,
      countryCode: country,
      category: category,
      name: name.trim(),
      description: text('description'),
      phone: text('phone'),
      sms: text('sms'),
      whatsapp: text('whatsapp'),
      url: url != null && url.startsWith('https://') ? url : null,
      hours: text('hours'),
      languages: [
        for (final l in (raw['languages'] as List?) ?? const [])
          if (l is String) l,
      ],
      isPolice: raw['is_police'] == true,
      sortOrder: raw['sort_order'] is int ? raw['sort_order'] as int : 100,
    );
    final reachable =
        resource.phone != null ||
        resource.sms != null ||
        resource.whatsapp != null ||
        resource.url != null;
    return reachable ? resource : null;
  }
}

class SupportResources {
  const SupportResources({
    required this.country,
    required this.countrySupported,
    required this.catalogueVersion,
    required this.resources,
    required this.fromServer,
  });

  /// The normalised country asked about, or null (none, or not a country).
  final String? country;
  final bool countrySupported;
  final String? catalogueVersion;
  final List<SupportResource> resources;

  /// False when the bundled catalogue answered.
  final bool fromServer;

  List<SupportResource> get emergency => [
    for (final r in resources)
      if (r.category == SupportCategory.emergency) r,
  ];

  List<SupportResource> inCategory(SupportCategory category) => [
    for (final r in resources)
      if (r.category == category && !r.isAnywhere) r,
  ];

  List<SupportResource> get anywhere => [
    for (final r in resources)
      if (r.isAnywhere && r.category != SupportCategory.emergency) r,
  ];

  /// Where "Find a helpline" goes: the first anywhere entry with a link,
  /// else the international directory.
  String get directoryUrl {
    for (final r in resources) {
      if (r.isAnywhere && r.url != null) return r.url!;
    }
    return supportDirectoryUrl;
  }

  factory SupportResources.fromServer(Map<String, dynamic> json) =>
      SupportResources(
        country: json['country'] is String ? json['country'] as String : null,
        countrySupported: json['country_supported'] == true,
        catalogueVersion:
            json['catalogue_version'] is String
                ? json['catalogue_version'] as String
                : null,
        resources: [
          for (final raw in (json['resources'] as List?) ?? const [])
            if (SupportResource.fromJson(raw) case final r?) r,
        ],
        fromServer: true,
      );
}

/// get_support_resources' country rule: two letters, upper-cased, never XX.
String? normaliseSupportCountry(String? raw) {
  final code = (raw ?? '').trim().toUpperCase();
  if (!RegExp(r'^[A-Z]{2}$').hasMatch(code) || code == supportAnywhere) {
    return null;
  }
  return code;
}

/// The bundled catalogue.
class SupportCatalogue {
  const SupportCatalogue({required this.version, required this.entries});

  final String version;
  final List<SupportResource> entries;

  static SupportCatalogue parse(String source) {
    final json = jsonDecode(source) as Map<String, dynamic>;
    return SupportCatalogue(
      version: json['catalogue_version'] as String,
      entries: [
        for (final raw in json['resources'] as List)
          if (SupportResource.fromJson(raw) case final r?) r,
      ],
    );
  }

  SupportResources forCountry(String? rawCountry) {
    final country = normaliseSupportCountry(rawCountry);
    final picked = [
      for (final r in entries)
        if (r.countryCode == country || r.isAnywhere) r,
    ];
    int rank(bool b) => b ? 1 : 0;
    picked.sort((a, b) {
      for (final c in [
        rank(a.category != SupportCategory.emergency) -
            rank(b.category != SupportCategory.emergency),
        rank(a.isAnywhere) - rank(b.isAnywhere),
        a.sortOrder - b.sortOrder,
        a.name.compareTo(b.name),
        a.id.compareTo(b.id),
      ]) {
        if (c != 0) return c;
      }
      return 0;
    });
    return SupportResources(
      country: country,
      countrySupported: picked.any((r) => r.countryCode == country),
      catalogueVersion: version,
      resources: picked,
      fromServer: false,
    );
  }
}

/// What a phone dials for [phone] as printed: the leading +, the digits,
/// and letters as the keypad has them ("800-799-SAFE (7233)" dials
/// 8007997233). A bracketed part is a spelled-out repeat and is dropped
/// when letters stand outside it; a "(0)" after a country code is the
/// domestic trunk digit and is never dialled with the +.
String supportDialString(String phone) {
  var source = phone.trim();
  if (source.startsWith('+')) source = source.replaceAll('(0)', '');
  final outside = source.replaceAll(RegExp(r'\([^)]*\)'), '');
  if (RegExp(r'[A-Za-z]').hasMatch(outside)) source = outside;
  const keypad = {
    'ABC': '2', 'DEF': '3', 'GHI': '4', 'JKL': '5', //
    'MNO': '6', 'PQRS': '7', 'TUV': '8', 'WXYZ': '9',
  };
  final out = StringBuffer();
  for (final ch in source.trim().split('')) {
    if (ch == '+' && out.isEmpty) {
      out.write(ch);
    } else if (RegExp(r'[0-9]').hasMatch(ch)) {
      out.write(ch);
    } else if (RegExp(r'[A-Za-z]').hasMatch(ch)) {
      final upper = ch.toUpperCase();
      for (final entry in keypad.entries) {
        if (entry.key.contains(upper)) out.write(entry.value);
      }
    }
  }
  return out.toString();
}

typedef SupportRpc =
    Future<Object?> Function(String fn, Map<String, dynamic> params);

class SupportResourcesRepository {
  SupportResourcesRepository({
    required SupportRpc rpc,
    required Future<String> Function() loadBundled,
    this.timeout = defaultTimeout,
  }) : _rpc = rpc,
       _loadBundled = loadBundled;

  final SupportRpc _rpc;
  final Future<String> Function() _loadBundled;
  SupportCatalogue? _bundled;

  static const defaultTimeout = Duration(seconds: 8);

  /// How long the server gets before the bundled catalogue answers.
  final Duration timeout;

  Future<SupportCatalogue> bundled() async =>
      _bundled ??= SupportCatalogue.parse(await _loadBundled());

  /// The server's answer, or the bundled catalogue's when the server fails,
  /// times out, or has no rows at all (a project the catalogue was never
  /// loaded into).
  Future<SupportResources> load(String? country) async {
    try {
      final data = await _rpc('get_support_resources', {
        'p_country': normaliseSupportCountry(country),
      }).timeout(timeout);
      final answer = SupportResources.fromServer(
        Map<String, dynamic>.from(data as Map),
      );
      if (answer.resources.isNotEmpty) return answer;
    } catch (_) {
      // Offline, refused or malformed: the bundled catalogue answers.
    }
    return (await bundled()).forCountry(country);
  }
}
```

`pubspec.yaml`, edit 1 of 1. Replace exactly:

```yaml
    - assets/config/
```

with:

```yaml
    - assets/config/
    # Spec 1 W7a: the support catalogue, for offline (the server's source).
    - assets/support_resources/
```

Create `scripts/load_support_resources.sh` with exactly:

```bash
#!/usr/bin/env bash
# scripts/load_support_resources.sh — Spec 1 W7a (spec §4.2): loads the
# support catalogue (assets/support_resources/catalogue.json, the file the
# app bundles for offline use) into public.support_resources through the
# service-role function load_support_resources, which takes the whole file
# or nothing.
#
#   Load (owner, per project; the two values are exported by the caller,
#   this script never reads .env or any credential file):
#     SUPABASE_URL=https://<ref>.supabase.co SUPABASE_SERVICE_ROLE_KEY=<key> \
#       scripts/load_support_resources.sh [catalogue.json]
#   Check against a local database, rolled back (writes nothing):
#     scripts/load_support_resources.sh --check <database> [catalogue.json]
set -euo pipefail

mode=load
if [[ "${1:-}" == "--check" ]]; then
  mode=check
  db="${2:?--check needs a database name}"
  shift 2
fi
file="${1:-assets/support_resources/catalogue.json}"
if [[ ! -f "$file" ]]; then
  echo "load_support_resources: no catalogue at $file" >&2
  exit 2
fi
# Valid JSON, compacted (a broken file stops here, before any request).
catalogue=$(python3 -I -c 'import json, sys; print(json.dumps(json.load(open(sys.argv[1], encoding="utf-8")), ensure_ascii=False, separators=(",", ":")))' "$file")

if [[ $mode == check ]]; then
  printf '%s\n' 'BEGIN;' 'SET LOCAL ROLE service_role;' \
    "SELECT public.load_support_resources(:'catalogue'::jsonb);" 'ROLLBACK;' |
    psql -X -q -v ON_ERROR_STOP=1 -At -d "$db" -v catalogue="$catalogue"
  exit 0
fi

: "${SUPABASE_URL:?export SUPABASE_URL (https://<ref>.supabase.co)}"
: "${SUPABASE_SERVICE_ROLE_KEY:?export SUPABASE_SERVICE_ROLE_KEY}"
# The key goes in a header file (mode 600), never on curl's command line.
headers=$(mktemp)
trap 'rm -f "$headers"' EXIT
chmod 600 "$headers"
printf 'apikey: %s\nAuthorization: Bearer %s\nContent-Type: application/json\n' \
  "$SUPABASE_SERVICE_ROLE_KEY" "$SUPABASE_SERVICE_ROLE_KEY" > "$headers"
printf '%s' "$catalogue" | python3 -I -c 'import json, sys; print(json.dumps({"p_catalogue": json.load(sys.stdin)}))' |
  curl -sS --fail-with-body -X POST "${SUPABASE_URL%/}/rest/v1/rpc/load_support_resources" \
    -H @"$headers" --data-binary @-
echo
```

Then `chmod +x scripts/load_support_resources.sh`.

- [ ] **Step 4: Run the tests**

```bash
flutter test test/features/safety/w7/support_resources_repository_test.dart test/launch/support_resources_release_test.dart 2>&1 | tail -1
GITHUB_REF_TYPE=tag flutter test test/launch/support_resources_release_test.dart 2>&1 | tail -1
```

Expected: `+15: All tests passed!` (11 + 4); then `+4: All tests passed!` (a release tag within 7 days of `2026-11-03`; from `2026-11-11` a tag fails until the entries are re-checked, which is the rule).

- [ ] **Step 5: The loader against the local database (rolled back, writes nothing)**

```bash
scripts/load_support_resources.sh --check attune_spec3a
psql -X -d attune_spec3a -Atc 'select count(*) from public.support_resources'
env -u SUPABASE_URL scripts/load_support_resources.sh 2>&1 | tail -1
```

Expected: `{"loaded": 4, "deactivated": 0, "catalogue_version": "2026-11-03.1"}`; `0` (nothing kept); `…: SUPABASE_URL: export SUPABASE_URL (https://<ref>.supabase.co)` (the load mode needs the caller's two values and never reads a file for them).

- [ ] **Step 6: Mutation checks (each must turn a test red)**

```bash
D=.superpowers/sdd/2026-11-03-spec1-w7
R=lib/features/safety/data/support_resources_repository.dart
T=test/features/safety/w7/support_resources_repository_test.dart
dmut() { # name file old new test
  cp "$2" "$D/mut.orig"
  python3 -I - "$2" "$3" "$4" <<'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1]); s = p.read_text()
assert s.count(sys.argv[2]) == 1, sys.argv[2]
p.write_text(s.replace(sys.argv[2], sys.argv[3]))
PY
  echo "$1: $(flutter test "$5" 2>&1 | tail -1 | grep -oE '(All tests passed|Some tests failed)')"
  cp "$D/mut.orig" "$2"; rm "$D/mut.orig"
}
dmut empty_server_shown $R '      if (answer.resources.isNotEmpty) return answer;' '      return answer;' $T
dmut emergency_not_first $R '        rank(a.category != SupportCategory.emergency) -
            rank(b.category != SupportCategory.emergency),' '        0,' $T
dmut half_rows_shown $R '    return reachable ? resource : null;' '    return resource;' $T
dmut no_bundle pubspec.yaml '    - assets/support_resources/
' '' $T
flutter test $T test/launch/support_resources_release_test.dart 2>&1 | tail -1 | grep -oE '(All tests passed|Some tests failed)'
```

Expected: `empty_server_shown: Some tests failed` (`a server with nothing loaded falls back to the bundle`), `emergency_not_first: Some tests failed` (the contract-order test), `half_rows_shown: Some tests failed` (`rows this build cannot show are left out`), `no_bundle: Some tests failed` (`the app bundles the catalogue`), then `All tests passed`.

### Task 3: Support resources v2 on the same route (§2.2, §2.3, §5.1, §5.2, §8 W7a; P-6, P-7, P-10, P-11, P-14)

**Files:**
- Create: `lib/features/safety/presentation/providers/support_resources_providers.dart`
- Create: `lib/features/safety/presentation/screens/support_resources_v2_screen.dart`
- Create: `test/features/safety/w7/support_resources_v2_test.dart` (+ 12 goldens under `test/features/safety/w7/goldens/`)
- Create: `.superpowers/sdd/2026-11-03-spec1-w7/w7a_arb.txt` (the copy fragment)
- Modify: `lib/features/safety/presentation/screens/safety_resources_screen.dart` (two edits), `lib/app/routing/app_router.dart` (two edits), `lib/i10n/app_en.arb` (+ `lib/i10n/generated/*`)

**Interfaces:**
- Consumes: Task 2's repository API; `PublicAppConfig.supportResourcesV2`, `deviceCountryProvider`, `quickExitProvider`, `UrlLauncherUtils.launchUrlWithFeedback`.
- Produces: `supportResourcesV2Provider` (`Provider<bool>`), `supportResourcesRepositoryProvider`, `supportCountryOverrideProvider` (`StateProvider<String?>`, memory only), `supportCountryProvider` (`FutureProvider<String?>`), `supportResourcesProvider` (`FutureProvider.family<SupportResources, String?>`), `supportLauncherProvider` (`Provider<Future<void> Function(BuildContext, String url)>`); `enum SupportFocus { grief, youth }` with `SupportFocus.parse(String?)`; `SupportResourcesV2Screen({SupportFocus? focus})`; `SettingsConfig supportResourcesSetting(BuildContext)` (used by Task 4); `SafetyResourcesScreen({SupportFocus? focus})`; the route `RouteNames.safetyResources` reads `?focus=`. Keys `support_*` and `flow_healing*` (Task 4 uses `flow_healingChoiceTitle`, `flow_healingBreakup`, `flow_healingLoss`, `support_settingsTitle`, `support_settingsSubtitle`).

- [ ] **Step 1: Write the failing widget test**

Create `test/features/safety/w7/support_resources_v2_test.dart` with exactly:

```dart
// Spec 1 W7a (§8 W7a, §2.3): Support resources v2. Today's screen while
// support_resources_v2 is off; with it on: the country line, emergency
// first, every number and link only after a confirmation that says what it
// may leave on the phone, "Not the police" on help that isn't, the
// fallback for a country without a checked list, the grief and youth
// views; goldens at 1.0, 1.3, 2.0 and right to left.
//   flutter test --update-goldens test/features/safety/w7/support_resources_v2_test.dart
import 'dart:convert';

import 'package:attune/core/platform/sim_country.dart';
import 'package:attune/features/auth/log_in/presentation/widgets/phone_country_picker_sheet.dart';
import 'package:attune/features/safety/data/support_resources_repository.dart';
import 'package:attune/features/safety/presentation/providers/support_resources_providers.dart';
import 'package:attune/features/safety/presentation/screens/safety_resources_screen.dart';
import 'package:attune/features/safety/presentation/screens/support_resources_v2_screen.dart';
import 'package:attune/features/safety/self_check/safety_self_check_service.dart';
import 'package:attune/features/safety/presentation/screens/safety_pin_screen.dart';
import 'package:attune/home/home_seams.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/flow_harness.dart';
import '../../../helpers/home_harness.dart';

Map<String, Object?> _entry(
  String n,
  String country,
  String category,
  String name, {
  int sort = 100,
  String? url,
  String? phone = '0800 000 000',
  bool police = false,
}) => {
  'id': '5f7a0000-0000-0000-0000-0000000000$n',
  'country_code': country,
  'category': category,
  'name': name,
  'phone': phone,
  'url': url,
  'languages': <String>[],
  'is_police': police,
  'sort_order': sort,
  'verified_at': '2026-11-03',
  'verified_by': 'test fixture',
};

/// Test rows only (never the shipped catalogue; plan P-4).
final _fixture = jsonEncode({
  'catalogue_version': 'fixture-1',
  'resources': [
    _entry(
      '01',
      'GH',
      'emergency',
      'Fixture emergency',
      phone: '999',
      police: true,
    ),
    _entry('02', 'GH', 'dv', 'Fixture police unit', sort: 10, police: true),
    _entry(
      '03',
      'GH',
      'dv',
      'Fixture DV line',
      sort: 20,
      url: 'https://dv.example.org/help',
    ),
    _entry('04', 'GH', 'grief', 'Fixture grief line', sort: 10),
    _entry(
      '05',
      'XX',
      'crisis',
      'Fixture directory',
      url: 'https://findahelpline.com',
      phone: null,
    ),
  ],
});

class _Launches {
  final urls = <String>[];
}

List<Override> _overrides(
  _Launches launches, {
  bool v2 = true,
  String? region = 'GH',
  bool signedIn = false,
}) => [
  supportResourcesV2Provider.overrideWithValue(v2),
  supportResourcesRepositoryProvider.overrideWithValue(
    SupportResourcesRepository(
      rpc: (_, __) async => throw StateError('offline'),
      loadBundled: () async => _fixture,
    ),
  ),
  deviceCountryProvider.overrideWith(
    (ref) async => (sim: null, region: region),
  ),
  supportLauncherProvider.overrideWithValue(
    (context, url) async => launches.urls.add(url),
  ),
  safetySelfCheckEnabledProvider.overrideWith((ref) async => false),
  homeAuthProvider.overrideWithValue(
    FakeHomeAuth(signedIn ? testUser('u-support') : null),
  ),
];

const _noPinOffer = {SafetyPinPromptCard.dismissedKey: true};

Future<FlowHarness> _pump(
  WidgetTester tester,
  _Launches launches, {
  bool v2 = true,
  String? region = 'GH',
  SupportFocus? focus,
  bool signedIn = false,
}) => pumpFlowScreen(
  tester,
  () => SafetyResourcesScreen(focus: focus),
  prefsValues: _noPinOffer,
  overrides: _overrides(launches, v2: v2, region: region, signedIn: signedIn),
);

void main() {
  testWidgets('flag off: today\'s screen, unchanged', (tester) async {
    // A tall view: today's helpline cards overflow a 390-wide phone (a
    // pre-existing layout bug of the v1 screen, plan P-14; not touched).
    await pumpFlowScreen(
      tester,
      () => const SafetyResourcesScreen(),
      prefsValues: _noPinOffer,
      overrides: _overrides(_Launches(), v2: false),
      size: const Size(800, 1600),
    );
    expect(find.text('Helplines'), findsOneWidget);
    expect(find.text('Ghana Police DOVVSU'), findsOneWidget);
    expect(find.byType(SupportResourcesV2Screen), findsNothing);
  });

  testWidgets('flag on: the country, emergency first, the tags', (
    tester,
  ) async {
    await _pump(tester, _Launches());
    expect(find.byType(SupportResourcesV2Screen), findsOneWidget);
    expect(find.text('Help for Ghana'), findsOneWidget);
    final emergency = tester.getTopLeft(find.text('In an emergency')).dy;
    final abuse = tester.getTopLeft(find.text('Domestic abuse')).dy;
    expect(emergency, lessThan(abuse));
    expect(
      tester.getTopLeft(find.text('Fixture police unit')).dy,
      lessThan(tester.getTopLeft(find.text('Fixture DV line')).dy),
    );
    expect(find.text('Police'), findsNWidgets(2));
    // The DV line, the grief line and the directory.
    expect(find.text('Not the police'), findsNWidgets(3));
    expect(find.text('Anywhere in the world'), findsOneWidget);
    expect(find.text('Fixture directory'), findsOneWidget);
    expect(find.text('Helplines'), findsNothing);
  });

  testWidgets('a call is confirmed first, and says what it leaves', (
    tester,
  ) async {
    final launches = _Launches();
    await _pump(tester, launches);
    await tester.tap(find.text('Call 999'));
    await tester.pumpAndSettle();
    expect(find.text('Call 999?'), findsOneWidget);
    expect(
      find.text("Calls may show in your phone's call history."),
      findsOneWidget,
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(launches.urls, isEmpty);
    await tester.tap(find.text('Call 999'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Call'));
    await tester.pumpAndSettle();
    expect(launches.urls, ['tel:999']);
  });

  testWidgets('a website is confirmed first too', (tester) async {
    final launches = _Launches();
    await _pump(tester, launches);
    await tester.ensureVisible(find.text('Website').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Website').first);
    await tester.pumpAndSettle();
    expect(find.text('Open dv.example.org?'), findsOneWidget);
    expect(find.text('It may show in your browser history.'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Open'));
    await tester.pumpAndSettle();
    expect(launches.urls, ['https://dv.example.org/help']);
  });

  testWidgets('a country without a checked list: the fallback', (tester) async {
    final launches = _Launches();
    await _pump(tester, launches, region: 'KE');
    expect(find.text('Help for Kenya'), findsOneWidget);
    expect(
      find.text("We don't have a checked list for Kenya yet."),
      findsOneWidget,
    );
    expect(
      find.text('In an emergency, call your local emergency number.'),
      findsOneWidget,
    );
    expect(find.text('Fixture DV line'), findsNothing);
    await tester.tap(find.text('Find a helpline'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Open'));
    await tester.pumpAndSettle();
    expect(launches.urls, ['https://findahelpline.com']);
  });

  testWidgets('a checked list without an emergency number says what to do', (
    tester,
  ) async {
    await pumpFlowScreen(
      tester,
      () => const SafetyResourcesScreen(),
      prefsValues: _noPinOffer,
      overrides: [
        ..._overrides(_Launches(), region: 'GB'),
        supportResourcesRepositoryProvider.overrideWithValue(
          SupportResourcesRepository(
            rpc: (_, __) async => throw StateError('offline'),
            loadBundled:
                () async => jsonEncode({
                  'catalogue_version': 'fixture-2',
                  'resources': [
                    _entry('11', 'GB', 'dv', 'Fixture GB line'),
                    _entry(
                      '12',
                      'XX',
                      'crisis',
                      'Fixture directory',
                      url: 'https://findahelpline.com',
                      phone: null,
                    ),
                  ],
                }),
          ),
        ),
      ],
    );
    expect(find.text('Fixture GB line'), findsOneWidget);
    expect(find.text('In an emergency'), findsNothing);
    expect(
      find.text('In an emergency, call your local emergency number.'),
      findsOneWidget,
    );
  });

  testWidgets('no country known: asked to choose one', (tester) async {
    await _pump(tester, _Launches(), region: null);
    expect(
      find.text('Choose your country to see help near you.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Choose a country'));
    await tester.pumpAndSettle();
    expect(find.byType(PhoneCountryPickerSheet), findsOneWidget);
  });

  testWidgets('a chosen country is used, and kept in memory only', (
    tester,
  ) async {
    final harness = await _pump(tester, _Launches(), region: 'KE');
    final container = ProviderScope.containerOf(
      tester.element(find.byType(SupportResourcesV2Screen)),
    );
    container.read(supportCountryOverrideProvider.notifier).state = 'GH';
    await tester.pumpAndSettle();
    expect(find.text('Help for Ghana'), findsOneWidget);
    expect(find.text('Fixture DV line'), findsOneWidget);
    expect(
      harness.prefs.getKeys().where(
        (k) => k != SafetyPinPromptCard.dismissedKey,
      ),
      isEmpty,
    );
  });

  testWidgets('grief: grief help and the journal, signed in', (tester) async {
    await _pump(tester, _Launches(), focus: SupportFocus.grief, signedIn: true);
    expect(find.text('Grief support'), findsOneWidget);
    expect(find.text('Fixture grief line'), findsOneWidget);
    expect(find.text('Fixture DV line'), findsNothing);
    expect(find.text('Fixture emergency'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Write about it in your journal'),
      200,
    );
    await tester.tap(find.text('Write about it in your journal'));
    await tester.pumpAndSettle();
    expect(find.text('at /reflectionJournal'), findsOneWidget);
  });

  testWidgets('grief, signed out: no journal; youth with no list: fallback', (
    tester,
  ) async {
    await _pump(tester, _Launches(), focus: SupportFocus.grief);
    expect(find.text('Write about it in your journal'), findsNothing);
    await _pump(tester, _Launches(), focus: SupportFocus.youth);
    expect(find.text('Support for young people'), findsOneWidget);
    expect(
      find.text("We don't have a checked list for this in Ghana yet."),
      findsOneWidget,
    );
    expect(find.text('Find a helpline'), findsOneWidget);
  });

  testWidgets('nothing moves and quick exit is in reach', (tester) async {
    await _pump(tester, _Launches());
    expect(find.byTooltip('Quick exit'), findsOneWidget);
    expect(find.byType(AnimatedSwitcher), findsNothing);
    await tester.scrollUntilVisible(find.text('Exit now'), 200);
    expect(find.text('Exit now'), findsOneWidget);
  });

  testWidgets('accessibility guidelines', (tester) async {
    await _pump(tester, _Launches());
    await expectFlowGuidelines(tester);
    await _pump(tester, _Launches(), region: 'KE');
    await expectFlowGuidelines(tester);
  });

  testWidgets('goldens: Ghana', (tester) async {
    await expectFlowGoldens(
      tester,
      'support_v2_ghana',
      () => const SafetyResourcesScreen(),
      prefsValues: _noPinOffer,
      overrides: _overrides(_Launches()),
    );
  });

  testWidgets('goldens: no checked list', (tester) async {
    await expectFlowGoldens(
      tester,
      'support_v2_unsupported',
      () => const SafetyResourcesScreen(),
      prefsValues: _noPinOffer,
      overrides: _overrides(_Launches(), region: 'KE'),
    );
  });

  testWidgets('goldens: grief', (tester) async {
    await expectFlowGoldens(
      tester,
      'support_v2_grief',
      () => const SafetyResourcesScreen(focus: SupportFocus.grief),
      prefsValues: _noPinOffer,
      overrides: _overrides(_Launches(), signedIn: true),
    );
  });
}
```

- [ ] **Step 2: Run it to make sure it fails**

```bash
flutter test test/features/safety/w7/support_resources_v2_test.dart 2>&1 | grep -E "Error when reading|Some tests failed" | head -2
```

Expected: `Error when reading 'lib/features/safety/presentation/providers/support_resources_providers.dart': No such file or directory`; `Some tests failed`.

- [ ] **Step 3: The copy**

Create `.superpowers/sdd/2026-11-03-spec1-w7/w7a_arb.txt` with exactly (all of W7a's strings, Task 4's included):

```json
  "support_resourcesTitle": "Support resources",
  "support_resourcesIntro": "If something does not feel safe, these contacts and planning resources may be useful.",
  "support_resourcesNoEmergencyService": "Attune cannot assess an emergency or contact help for you.",
  "support_quickExit": "Quick exit",
  "support_quickExitBody": "Tap to exit the app and show a neutral screen.",
  "support_exitNow": "Exit now",
  "support_notNow": "Not relevant right now",
  "support_helpFor": "Help for {country}",
  "@support_helpFor": {
    "placeholders": {
      "country": {"type": "String"}
    }
  },
  "support_changeCountry": "Change",
  "support_changeCountryLabel": "Change country. Now showing {country}",
  "@support_changeCountryLabel": {
    "placeholders": {
      "country": {"type": "String"}
    }
  },
  "support_chooseCountry": "Choose your country to see help near you.",
  "support_chooseCountryButton": "Choose a country",
  "support_loading": "Looking for help near you",
  "support_emergencyHeading": "In an emergency",
  "support_anywhereHeading": "Anywhere in the world",
  "support_categoryEmergency": "Emergency",
  "support_categoryDv": "Domestic abuse",
  "support_categoryCrisis": "Someone to talk to now",
  "support_categorySexualAssault": "Sexual assault",
  "support_categorySextortion": "Threats to share images",
  "support_categoryChildSafety": "A child at risk",
  "support_categoryYouth": "For young people",
  "support_categoryLgbtqLegal": "LGBTQ+ and legal help",
  "support_categoryGrief": "Grief",
  "support_categoryPerinatal": "Pregnancy and after birth",
  "support_categoryAddiction": "Alcohol, drugs and gambling",
  "support_categoryFinancialControl": "Money and control",
  "support_notPolice": "Not the police",
  "support_police": "Police",
  "support_call": "Call {number}",
  "@support_call": {
    "placeholders": {
      "number": {"type": "String"}
    }
  },
  "support_text": "Text {number}",
  "@support_text": {
    "placeholders": {
      "number": {"type": "String"}
    }
  },
  "support_whatsapp": "WhatsApp",
  "support_website": "Website",
  "support_callConfirmTitle": "Call {number}?",
  "@support_callConfirmTitle": {
    "placeholders": {
      "number": {"type": "String"}
    }
  },
  "support_callConfirmBody": "Calls may show in your phone's call history.",
  "support_callConfirmCall": "Call",
  "support_textConfirmTitle": "Text {number}?",
  "@support_textConfirmTitle": {
    "placeholders": {
      "number": {"type": "String"}
    }
  },
  "support_textConfirmBody": "Messages may stay on your phone.",
  "support_linkConfirmTitle": "Open {site}?",
  "@support_linkConfirmTitle": {
    "placeholders": {
      "site": {"type": "String"}
    }
  },
  "support_linkConfirmBody": "It may show in your browser history.",
  "support_open": "Open",
  "support_cancel": "Cancel",
  "support_unsupported": "We don't have a checked list for {country} yet.",
  "@support_unsupported": {
    "placeholders": {
      "country": {"type": "String"}
    }
  },
  "support_noFocusList": "We don't have a checked list for this in {country} yet.",
  "@support_noFocusList": {
    "placeholders": {
      "country": {"type": "String"}
    }
  },
  "support_findHelpline": "Find a helpline",
  "support_localEmergency": "In an emergency, call your local emergency number.",
  "support_griefTitle": "Grief support",
  "support_youthTitle": "Support for young people",
  "support_writeInJournal": "Write about it in your journal",
  "support_settingsTitle": "Find support",
  "support_settingsSubtitle": "Helplines for where you are",
  "flow_healingChoiceTitle": "What happened?",
  "flow_healingBreakup": "A breakup",
  "flow_healingLoss": "Someone I love died"
```

```bash
grep -cP '[^\x00-\x7F]' .superpowers/sdd/2026-11-03-spec1-w7/w7a_arb.txt
python3 -I .superpowers/sdd/2026-10-26-spec1-w3/arb_append.py .superpowers/sdd/2026-11-03-spec1-w7/w7a_arb.txt
flutter gen-l10n --arb-dir=lib/i10n --template-arb-file=app_en.arb --output-dir=lib/i10n/generated --output-localization-file=app_localizations.dart --no-synthetic-package
grep -c 'String support_helpFor(String country)' lib/i10n/generated/app_localizations.dart
```

Expected: `0`; `added 54 keys`; gen-l10n's usual untranslated-messages note; `1`.

- [ ] **Step 4: The providers, the v2 screen, the switch and the route**

Create `lib/features/safety/presentation/providers/support_resources_providers.dart` with exactly:

```dart
import 'package:attune/core/flags/public_app_config.dart';
import 'package:attune/core/platform/sim_country.dart';
import 'package:attune/core/utils/url_launcher_utils.dart';
import 'package:attune/features/safety/data/support_resources_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// support_resources_v2 (Spec 1 §2.5, W7a), from the anon config: live,
/// else the cached copy; off until either is known (today's screen).
final supportResourcesV2Provider = Provider<bool>((ref) {
  final config =
      ref.watch(
        publicAppConfigProvider.select((config) => config.valueOrNull),
      ) ??
      ref.watch(cachedPublicAppConfigProvider);
  return config?.supportResourcesV2 ?? false;
});

final supportResourcesRepositoryProvider = Provider<SupportResourcesRepository>(
  (ref) => SupportResourcesRepository(
    rpc: (fn, params) => Supabase.instance.client.rpc(fn, params: params),
    loadBundled:
        () => rootBundle.loadString('assets/support_resources/catalogue.json'),
  ),
);

/// The country chosen on the screen, this run only: never stored, so
/// nothing on the phone says someone looked for help (plan P-6).
final supportCountryOverrideProvider = StateProvider<String?>((ref) => null);

/// The country to show: the one chosen, else the SIM's, else the phone's
/// region; null when none is known.
final supportCountryProvider = FutureProvider<String?>((ref) async {
  final chosen = ref.watch(supportCountryOverrideProvider);
  if (chosen != null) return normaliseSupportCountry(chosen);
  final device = await ref.watch(deviceCountryProvider.future);
  return normaliseSupportCountry(device.sim ?? device.region);
});

final supportResourcesProvider = FutureProvider.family<
  SupportResources,
  String?
>((ref, country) => ref.read(supportResourcesRepositoryProvider).load(country));

/// Opens a tel:, sms: or https: link (replaceable in tests). Only ever
/// after the person confirmed it (§3, the manual's promise).
final supportLauncherProvider =
    Provider<Future<void> Function(BuildContext context, String url)>(
      (ref) =>
          (context, url) => UrlLauncherUtils.launchUrlWithFeedback(
            context: context,
            url: url,
          ),
    );
```

Create `lib/features/safety/presentation/screens/support_resources_v2_screen.dart` with exactly:

```dart
import 'dart:async';

import 'package:attune/app/routing/app_router.dart' show RouteNames;
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/ui/text/allow_large_text.dart';
import 'package:attune/core/utils/bottom_sheet_utils.dart';
import 'package:attune/features/auth/log_in/domain/phone_country.dart';
import 'package:attune/features/auth/log_in/presentation/widgets/phone_country_picker_sheet.dart';
import 'package:attune/features/auth/sign_up/domain/country_names.dart';
import 'package:attune/features/safety/data/support_resources_repository.dart';
import 'package:attune/features/safety/presentation/providers/safety_providers.dart';
import 'package:attune/features/safety/presentation/providers/support_resources_providers.dart';
import 'package:attune/features/safety/presentation/screens/report_child_concern_screen.dart';
import 'package:attune/features/safety/presentation/screens/safety_pin_screen.dart';
import 'package:attune/features/safety/self_check/safety_self_check_row.dart';
import 'package:attune/features/settings/models/settings_config.dart';
import 'package:attune/home/home_seams.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// A narrower view of the screen, opened from another place: grief support
/// from Healing's "Someone I love died", help for young people from X1.
enum SupportFocus {
  grief(SupportCategory.grief),
  youth(SupportCategory.youth);

  const SupportFocus(this.category);

  final SupportCategory category;

  /// The route's `focus` query value; anything else is the whole screen.
  static SupportFocus? parse(String? value) {
    for (final f in values) {
      if (f.name == value) return f;
    }
    return null;
  }
}

/// Settings -> Support (Spec 1 §5.2, W7a): "Find support", signed in or
/// not, built by the Settings screen only while support_resources_v2 is on.
SettingsConfig supportResourcesSetting(BuildContext context) {
  final loc = AppLocalizations.of(context)!;
  return SettingsConfig(
    id: 'support_resources',
    title: loc.support_settingsTitle,
    subtitle: loc.support_settingsSubtitle,
    icon: Icons.support_outlined,
    type: SettingsItemType.navigation,
    routeName: RouteNames.safetyResources,
    onTap: () => context.push(RouteNames.safetyResources),
    iconColor: Colors.red,
    order: 0,
  );
}

/// The order categories are shown in, after emergency (Spec 1 §8 W7a).
const supportCategoryOrder = [
  SupportCategory.dv,
  SupportCategory.crisis,
  SupportCategory.sexualAssault,
  SupportCategory.sextortion,
  SupportCategory.childSafety,
  SupportCategory.youth,
  SupportCategory.lgbtqLegal,
  SupportCategory.grief,
  SupportCategory.perinatal,
  SupportCategory.addiction,
  SupportCategory.financialControl,
];

String supportCategoryLabel(AppLocalizations loc, SupportCategory c) =>
    switch (c) {
      SupportCategory.emergency => loc.support_categoryEmergency,
      SupportCategory.dv => loc.support_categoryDv,
      SupportCategory.crisis => loc.support_categoryCrisis,
      SupportCategory.sexualAssault => loc.support_categorySexualAssault,
      SupportCategory.sextortion => loc.support_categorySextortion,
      SupportCategory.childSafety => loc.support_categoryChildSafety,
      SupportCategory.youth => loc.support_categoryYouth,
      SupportCategory.lgbtqLegal => loc.support_categoryLgbtqLegal,
      SupportCategory.grief => loc.support_categoryGrief,
      SupportCategory.perinatal => loc.support_categoryPerinatal,
      SupportCategory.addiction => loc.support_categoryAddiction,
      SupportCategory.financialControl => loc.support_categoryFinancialControl,
    };

/// Support resources v2 (Spec 1 §8 W7a), shown by [SafetyResourcesScreen]
/// under support_resources_v2 (same route, so every link keeps working).
/// The country line and picker; emergency numbers first; each number and
/// link opened only after a confirmation that says what it may leave on the
/// phone; categories, with "Not the police" on help that isn't; the fallback
/// for a country without a checked list; the bundled catalogue offline.
/// Never animated (§2.2); quick exit in the bar and the app shell's gesture.
class SupportResourcesV2Screen extends ConsumerWidget {
  const SupportResourcesV2Screen({super.key, this.focus});

  final SupportFocus? focus;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loc = AppLocalizations.of(context)!;
    final title = switch (focus) {
      SupportFocus.grief => loc.support_griefTitle,
      SupportFocus.youth => loc.support_youthTitle,
      null => loc.support_resourcesTitle,
    };
    final country = ref.watch(supportCountryProvider);
    return AllowLargeText(
      child: Scaffold(
        appBar: AppBar(
          title: Text(title),
          actions: [
            IconButton(
              icon: const Icon(Icons.exit_to_app),
              tooltip: loc.support_quickExit,
              onPressed: () => ref.read(quickExitProvider).call(context),
            ),
          ],
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(Spacing.lg),
            children: [
              if (focus == null) ...[
                const SafetyPinPromptCard(),
                const SafetySelfCheckRow(),
                const ReportChildConcernLink(),
                Text(
                  loc.support_resourcesIntro,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: Spacing.xs),
                Text(
                  loc.support_resourcesNoEmergencyService,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: Spacing.md),
              ],
              switch (country) {
                AsyncData(:final value) => _Directory(
                  country: value,
                  focus: focus,
                ),
                AsyncError() => _Directory(country: null, focus: focus),
                _ => const _Waiting(),
              },
              if (focus == null) ...[
                const SizedBox(height: Spacing.xl),
                const _QuickExitCard(),
              ],
              const SizedBox(height: Spacing.lg),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton(
                  style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                  onPressed: () => Navigator.of(context).maybePop(),
                  child: Text(loc.support_notNow),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _countryName(AppLocalizations loc, String iso) => countryNameFor(
  iso,
  special: {'GB': loc.flow_countryUk, 'US': loc.flow_countryUs},
);

class _Directory extends ConsumerWidget {
  const _Directory({required this.country, required this.focus});

  final String? country;
  final SupportFocus? focus;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final answer = ref.watch(supportResourcesProvider(country));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _CountryLine(country: country),
        const SizedBox(height: Spacing.md),
        switch (answer) {
          AsyncData(:final value) => _Listing(answer: value, focus: focus),
          AsyncError() => _Unsupported(
            country: country,
            directoryUrl: supportDirectoryUrl,
          ),
          _ => const _Waiting(),
        },
      ],
    );
  }
}

class _CountryLine extends ConsumerWidget {
  const _CountryLine({required this.country});

  final String? country;

  Future<void> _choose(BuildContext context, WidgetRef ref) async {
    final current = country;
    final selected =
        current == null
            ? PhoneCountries.defaultCountry
            : PhoneCountries.all.firstWhere(
              (c) => c.isoCode == current,
              orElse: () => PhoneCountries.defaultCountry,
            );
    await BottomSheetUtils.showDocumentationBottomSheet<void>(
      context: context,
      padding: 0,
      widget: PhoneCountryPickerSheet(
        selectedCountry: selected,
        onCountrySelected:
            (picked) =>
                ref.read(supportCountryOverrideProvider.notifier).state =
                    picked.isoCode,
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final iso = country;
    return Row(
      children: [
        Expanded(
          child: Text(
            iso == null
                ? loc.support_chooseCountry
                : loc.support_helpFor(_countryName(loc, iso)),
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.onSurface,
            ),
          ),
        ),
        TextButton(
          style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
          onPressed: () => _choose(context, ref),
          child: Text(
            iso == null
                ? loc.support_chooseCountryButton
                : loc.support_changeCountry,
            semanticsLabel:
                iso == null
                    ? loc.support_chooseCountryButton
                    : loc.support_changeCountryLabel(_countryName(loc, iso)),
          ),
        ),
      ],
    );
  }
}

class _Listing extends ConsumerWidget {
  const _Listing({required this.answer, required this.focus});

  final SupportResources answer;
  final SupportFocus? focus;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loc = AppLocalizations.of(context)!;
    final signedIn = ref.watch(homeAuthProvider).currentUser != null;
    final focused = focus;
    final children = <Widget>[];

    void section(String heading, List<SupportResource> rows) {
      if (rows.isEmpty) return;
      children
        ..add(_Heading(heading))
        ..addAll([for (final r in rows) _ResourceCard(resource: r)]);
    }

    section(loc.support_emergencyHeading, answer.emergency);
    // A checked list without an emergency number still says what to do in
    // an emergency (the unsupported card says it for the rest).
    if (answer.emergency.isEmpty && answer.countrySupported) {
      children.add(
        Padding(
          padding: const EdgeInsets.only(bottom: Spacing.sm),
          child: Text(
            loc.support_localEmergency,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ),
      );
    }
    if (!answer.countrySupported) {
      children.add(
        _Unsupported(
          country: answer.country,
          directoryUrl: answer.directoryUrl,
        ),
      );
    } else if (focused != null) {
      final rows = answer.inCategory(focused.category);
      if (rows.isEmpty) {
        children.add(
          _Unsupported(
            country: answer.country,
            directoryUrl: answer.directoryUrl,
            line: loc.support_noFocusList(
              _countryName(loc, answer.country ?? ''),
            ),
          ),
        );
      } else {
        section(supportCategoryLabel(loc, focused.category), rows);
      }
    } else {
      for (final c in supportCategoryOrder) {
        section(supportCategoryLabel(loc, c), answer.inCategory(c));
      }
      section(loc.support_anywhereHeading, answer.anywhere);
    }
    if (focused == SupportFocus.grief && signedIn) {
      children.add(
        Padding(
          padding: const EdgeInsets.only(top: Spacing.lg),
          child: FilledButton.tonal(
            style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
            onPressed: () => context.push(RouteNames.reflectionJournal),
            child: Text(loc.support_writeInJournal),
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: Spacing.md, bottom: Spacing.sm),
      child: Semantics(
        header: true,
        child: Text(
          text,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.onSurface,
          ),
        ),
      ),
    );
  }
}

/// Asks before anything leaves the app, and says what it may leave behind.
Future<bool> _confirm(
  BuildContext context, {
  required String title,
  required String body,
  required String action,
}) async {
  final loc = AppLocalizations.of(context)!;
  final ok = await showDialog<bool>(
    context: context,
    builder:
        (dialogContext) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(loc.support_cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(action),
            ),
          ],
        ),
  );
  return ok ?? false;
}

Future<void> _openLink(BuildContext context, WidgetRef ref, String url) async {
  final loc = AppLocalizations.of(context)!;
  final site = Uri.tryParse(url)?.host ?? url;
  if (await _confirm(
        context,
        title: loc.support_linkConfirmTitle(site),
        body: loc.support_linkConfirmBody,
        action: loc.support_open,
      ) &&
      context.mounted) {
    await ref.read(supportLauncherProvider)(context, url);
  }
}

class _ResourceCard extends ConsumerWidget {
  const _ResourceCard({required this.resource});

  final SupportResource resource;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final r = resource;
    final emergency = r.category == SupportCategory.emergency;
    final tag =
        r.isPolice
            ? loc.support_police
            : emergency
            ? null
            : loc.support_notPolice;

    Future<void> call(String number) async {
      if (await _confirm(
            context,
            title: loc.support_callConfirmTitle(number),
            body: loc.support_callConfirmBody,
            action: loc.support_callConfirmCall,
          ) &&
          context.mounted) {
        await ref.read(supportLauncherProvider)(
          context,
          'tel:${supportDialString(number)}',
        );
      }
    }

    Future<void> text(String number) async {
      if (await _confirm(
            context,
            title: loc.support_textConfirmTitle(number),
            body: loc.support_textConfirmBody,
            action: loc.support_open,
          ) &&
          context.mounted) {
        await ref.read(supportLauncherProvider)(
          context,
          'sms:${supportDialString(number)}',
        );
      }
    }

    final actions = <Widget>[
      if (r.phone case final phone?)
        _Action(
          icon: Icons.call_outlined,
          label: loc.support_call(phone),
          onPressed: () => call(phone),
        ),
      if (r.sms case final sms?)
        _Action(
          icon: Icons.sms_outlined,
          label: loc.support_text(sms),
          onPressed: () => text(sms),
        ),
      if (r.whatsapp case final whatsapp?)
        _Action(
          icon: Icons.chat_outlined,
          label: loc.support_whatsapp,
          onPressed:
              () => _openLink(
                context,
                ref,
                'https://wa.me/${supportDialString(whatsapp).replaceAll('+', '')}',
              ),
        ),
      if (r.url case final url?)
        _Action(
          icon: Icons.open_in_new,
          label: loc.support_website,
          onPressed: () => _openLink(context, ref, url),
        ),
    ];

    return Card(
      margin: const EdgeInsets.only(bottom: Spacing.sm),
      elevation: 0,
      color: scheme.surfaceContainerLow,
      // Emergency numbers stand out by a border, never by colour alone:
      // they also sit first, under their own heading.
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(BorderRadiusTokens.md),
        side:
            emergency
                ? BorderSide(color: scheme.error, width: 2)
                : BorderSide.none,
      ),
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              r.name,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: scheme.onSurface,
              ),
            ),
            if (tag != null) ...[const SizedBox(height: Spacing.xs), _Tag(tag)],
            if (r.description case final description?) ...[
              const SizedBox(height: Spacing.xs),
              Text(description, style: theme.textTheme.bodyMedium),
            ],
            if (r.hours case final hours?) ...[
              const SizedBox(height: Spacing.xs),
              Text(
                hours,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: Spacing.sm),
            Wrap(
              spacing: Spacing.sm,
              runSpacing: Spacing.xs,
              children: actions,
            ),
          ],
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(BorderRadiusTokens.sm),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.sm,
          vertical: 2,
        ),
        child: Text(
          text,
          style: Theme.of(
            context,
          ).textTheme.labelMedium?.copyWith(color: scheme.onSecondaryContainer),
        ),
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    style: OutlinedButton.styleFrom(
      minimumSize: const Size(48, 48),
      foregroundColor: Theme.of(context).colorScheme.onSurface,
    ),
    onPressed: onPressed,
    icon: Icon(icon, size: 18),
    label: Text(label),
  );
}

class _Unsupported extends ConsumerWidget {
  const _Unsupported({
    required this.country,
    required this.directoryUrl,
    this.line,
  });

  final String? country;
  final String directoryUrl;

  /// Replaces the "no checked list" sentence (a focused view).
  final String? line;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final iso = country;
    final sentence =
        line ??
        (iso == null ? null : loc.support_unsupported(_countryName(loc, iso)));
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (sentence != null) ...[
              Text(sentence, style: theme.textTheme.bodyLarge),
              const SizedBox(height: Spacing.sm),
            ],
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
              onPressed: () => _openLink(context, ref, directoryUrl),
              child: Text(loc.support_findHelpline),
            ),
            const SizedBox(height: Spacing.sm),
            Text(
              loc.support_localEmergency,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Nothing for the first 400 ms; then a bar with words (§2.2).
class _Waiting extends StatefulWidget {
  const _Waiting();

  @override
  State<_Waiting> createState() => _WaitingState();
}

class _WaitingState extends State<_Waiting> {
  bool _show = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(milliseconds: 400), () {
      if (mounted) setState(() => _show = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_show) return const SizedBox(height: 48);
    final loc = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const LinearProgressIndicator(),
        const SizedBox(height: Spacing.sm),
        Text(loc.support_loading),
      ],
    );
  }
}

class _QuickExitCard extends ConsumerWidget {
  const _QuickExitCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      elevation: 0,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(BorderRadiusTokens.md),
        side: BorderSide(color: scheme.error, width: 2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          children: [
            Text(
              loc.support_quickExit,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(height: Spacing.xs),
            Text(
              loc.support_quickExitBody,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(height: Spacing.sm),
            FilledButton(
              style: FilledButton.styleFrom(
                minimumSize: const Size(48, 48),
                backgroundColor: scheme.error,
                foregroundColor: scheme.onError,
              ),
              onPressed: () => ref.read(quickExitProvider).call(context),
              child: Text(loc.support_exitNow),
            ),
          ],
        ),
      ),
    );
  }
}
```

`lib/features/safety/presentation/screens/safety_resources_screen.dart`, edit 1 of 2. Replace exactly:

```dart
import 'safety_pin_screen.dart';
import 'report_child_concern_screen.dart';
```

with:

```dart
import 'safety_pin_screen.dart';
import 'report_child_concern_screen.dart';
import '../providers/support_resources_providers.dart';
import 'support_resources_v2_screen.dart';
```

`lib/features/safety/presentation/screens/safety_resources_screen.dart`, edit 2 of 2. Replace exactly:

```dart
  const SafetyResourcesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
```

with:

```dart
  const SafetyResourcesScreen({super.key, this.focus});

  /// Spec 1 W7a: grief or youth only (the route's `focus`), under v2.
  final SupportFocus? focus;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Spec 1 W7a (§5.2): the v2 body under support_resources_v2, on the
    // same route; with the flag off, today's screen below, unchanged.
    if (ref.watch(supportResourcesV2Provider)) {
      return SupportResourcesV2Screen(focus: focus);
    }
```

Everything below those first lines of `build` stays exactly as it is (the flag-off screen).

`lib/app/routing/app_router.dart`, edit 1 of 2. Replace exactly:

```dart
import 'package:attune/features/safety/presentation/screens/safety_resources_screen.dart';
```

with:

```dart
import 'package:attune/features/safety/presentation/screens/safety_resources_screen.dart';
import 'package:attune/features/safety/presentation/screens/support_resources_v2_screen.dart'
    show SupportFocus;
```

`lib/app/routing/app_router.dart`, edit 2 of 2. Replace exactly:

```dart
        builder: (context, state) => const SafetyResourcesScreen(),
```

with:

```dart
        // Spec 1 W7a: `?focus=grief|youth` narrows the v2 screen.
        builder:
            (context, state) => SafetyResourcesScreen(
              focus: SupportFocus.parse(state.uri.queryParameters['focus']),
            ),
```

- [ ] **Step 5: Run the test, write the goldens, look at them**

```bash
flutter test --update-goldens test/features/safety/w7/support_resources_v2_test.dart 2>&1 | tail -1
flutter test test/features/safety/w7/support_resources_v2_test.dart 2>&1 | tail -1
ls test/features/safety/w7/goldens | wc -l
```

Expected: `+15: All tests passed!` twice; `12` (`support_v2_ghana`, `support_v2_unsupported`, `support_v2_grief` × `scale1.0`, `scale1.3`, `scale2.0`, `rtl`). Open `support_v2_ghana.scale2.0.png` and `support_v2_unsupported.rtl.png`: the emergency card first with its red border, "Police" and "Not the police" tags, every action button full-size, the country line's "Change" on the trailing side in RTL, nothing clipped.

- [ ] **Step 6: Analyzer on the touched files**

```bash
flutter analyze --no-pub lib/features/safety lib/app/routing test/features/safety/w7 2>&1 | grep -E '^\s*(error|warning) '
```

Expected: no output (the one pre-existing `info` in `safety_self_check_screen.dart` is not this task's).

- [ ] **Step 7: Mutation checks (each must turn the widget test red)**

```bash
D=.superpowers/sdd/2026-11-03-spec1-w7
V=lib/features/safety/presentation/screens/support_resources_v2_screen.dart
S=lib/features/safety/presentation/screens/safety_resources_screen.dart
T=test/features/safety/w7/support_resources_v2_test.dart
dmut() { # name file old new test
  cp "$2" "$D/mut.orig"
  python3 -I - "$2" "$3" "$4" <<'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1]); s = p.read_text()
assert s.count(sys.argv[2]) == 1, sys.argv[2]
p.write_text(s.replace(sys.argv[2], sys.argv[3]))
PY
  echo "$1: $(flutter test "$5" 2>&1 | tail -1 | grep -oE '(All tests passed|Some tests failed)')"
  cp "$D/mut.orig" "$2"; rm "$D/mut.orig"
}
dmut call_without_asking $V '      if (await _confirm(
            context,
            title: loc.support_callConfirmTitle(number),
            body: loc.support_callConfirmBody,
            action: loc.support_callConfirmCall,
          ) &&
          context.mounted) {' '      if (context.mounted) {' $T
dmut v2_without_flag $S '    if (ref.watch(supportResourcesV2Provider)) {' '    if (true) {' $T
dmut police_tagged_not_police $V '        r.isPolice
            ? loc.support_police' '        false
            ? loc.support_police' $T
dmut no_emergency_line $V '    if (answer.emergency.isEmpty && answer.countrySupported) {' '    if (false) {' $T
dmut no_fallback_card $V '    if (!answer.countrySupported) {' '    if (false) {' $T
flutter test $T 2>&1 | tail -1 | grep -oE '(All tests passed|Some tests failed)'
```

Expected: `call_without_asking`, `v2_without_flag`, `police_tagged_not_police`, `no_emergency_line` and `no_fallback_card` each `Some tests failed`; then `All tests passed`.

### Task 4: Where Support is reached from (X1, Healing, Settings, the manual) and the W7a gate (§3.6, §3.10, §5.2, §5.4, §8 W7a; P-8, P-9, P-12, P-13)

**Files:**
- Create: `lib/features/me/presentation/widgets/healing_choice_sheet.dart`
- Create: `test/features/safety/w7/support_hooks_test.dart` (+ 4 goldens)
- Modify: `lib/features/me/presentation/widgets/your_space_section.dart` (two edits), `lib/features/auth/sign_up/presentation/screens/under_age_stop_screen.dart` (four), `lib/features/settings/data/settings_data.dart` (two), `lib/features/settings/screens/settings_screen.dart` (two), `lib/app/documentations/user_manual/data/manual_documentation_registry.dart` (one), `lib/app/documentations/user_manual/data/safety_docs.dart` (two), `test/app/documentations/documentation_registry_flags_test.dart` (one line)

**Interfaces:**
- Consumes: Task 3's `supportResourcesV2Provider`, `supportResourcesSetting`, `SupportFocus`, the `?focus=` route and the `flow_healing*` / `support_settings*` keys; `openHealing`, `childReportSetting`.
- Produces: `enum HealingChoice { breakup, loss }`, `griefSupportLocation` (`/safety-resources?focus=grief`), `Future<void> openHealingOrGrief(BuildContext, WidgetRef)`, `HealingChoiceSheet`; `UnderAgeStopScreen.youthSupportLocation` (`/safety-resources?focus=youth`); `getSettingsSections(..., SettingsConfig? supportResources)`; the manual passage id `supportResourcesV2`.

- [ ] **Step 1: Write the failing test**

Create `test/features/safety/w7/support_hooks_test.dart` with exactly:

```dart
// Spec 1 W7a (§3.6 X1, §3.10 Healing, §5.2, §5.4): where Support resources
// v2 is reached from. X1's "Support for young people" opens the youth view
// for this phone's country; the Healing row asks "A breakup" or "Someone I
// love died" (grief support, with the journal); Settings -> Support has
// "Find support"; the route takes ?focus=; the manual's passage shows only
// with the flag. With support_resources_v2 off, each is exactly as before.
//   flutter test --update-goldens test/features/safety/w7/support_hooks_test.dart
import 'dart:io';

import 'package:attune/app/documentations/user_manual/data/documentation_flags.dart';
import 'package:attune/app/documentations/user_manual/data/manual_documentation_registry.dart';
import 'package:attune/features/auth/sign_up/presentation/screens/under_age_stop_screen.dart';
import 'package:attune/features/healing/presentation/providers/healing_providers.dart';
import 'package:attune/features/me/presentation/widgets/healing_choice_sheet.dart';
import 'package:attune/features/me/presentation/widgets/your_space_section.dart';
import 'package:attune/features/safety/presentation/providers/support_resources_providers.dart';
import 'package:attune/features/safety/presentation/screens/report_child_concern_screen.dart';
import 'package:attune/features/safety/presentation/screens/support_resources_v2_screen.dart';
import 'package:attune/features/settings/data/settings_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/flow_harness.dart';

Future<FlowHarness> _space(WidgetTester tester, {required bool v2}) =>
    pumpFlowScreen(
      tester,
      () => const Scaffold(body: YourSpaceSection()),
      overrides: [
        supportResourcesV2Provider.overrideWithValue(v2),
        // An active journey: "A breakup" goes straight to it, as today.
        hasActiveSoloHealingJourneyProvider.overrideWith((ref) async => true),
      ],
    );

void main() {
  testWidgets('Healing, flag on: asked first; a loss opens grief support', (
    tester,
  ) async {
    await _space(tester, v2: true);
    await tester.tap(find.text('Healing'));
    await tester.pumpAndSettle();
    expect(find.text('What happened?'), findsOneWidget);
    expect(find.text('A breakup'), findsOneWidget);
    await tester.tap(find.text('Someone I love died'));
    await tester.pumpAndSettle();
    expect(find.text('at /safety-resources?focus=grief'), findsOneWidget);
  });

  testWidgets('Healing, flag on: a breakup opens Healing as before', (
    tester,
  ) async {
    await _space(tester, v2: true);
    await tester.tap(find.text('Healing'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('A breakup'));
    await tester.pumpAndSettle();
    expect(find.text('at /healingJourney'), findsOneWidget);
  });

  testWidgets('Healing, flag off: no question, Healing as before', (
    tester,
  ) async {
    await _space(tester, v2: false);
    await tester.tap(find.text('Healing'));
    await tester.pumpAndSettle();
    expect(find.text('What happened?'), findsNothing);
    expect(find.text('at /healingJourney'), findsOneWidget);
  });

  testWidgets('the Healing question: guidelines and goldens', (tester) async {
    await pumpFlowScreen(
      tester,
      () => const Scaffold(body: HealingChoiceSheet()),
    );
    await expectFlowGuidelines(tester);
    await expectFlowGoldens(
      tester,
      'healing_choice',
      () => const Scaffold(body: HealingChoiceSheet()),
    );
  });

  testWidgets('X1, flag on: the youth view for this country', (tester) async {
    await pumpFlowScreen(
      tester,
      () => const UnderAgeStopScreen(),
      overrides: [supportResourcesV2Provider.overrideWithValue(true)],
    );
    await tester.tap(find.text('Support for young people'));
    await tester.pumpAndSettle();
    expect(find.text('at /safety-resources?focus=youth'), findsOneWidget);
  });

  test('X1, flag off: the international directory, as before W7', () {
    expect(UnderAgeStopScreen.youthSupportUrl, 'https://findahelpline.com');
    expect(
      UnderAgeStopScreen.youthSupportLocation,
      '/safety-resources?focus=youth',
    );
  });

  test('the route takes ?focus= and nothing else', () {
    expect(SupportFocus.parse('grief'), SupportFocus.grief);
    expect(SupportFocus.parse('youth'), SupportFocus.youth);
    expect(SupportFocus.parse('dv'), isNull);
    expect(SupportFocus.parse(null), isNull);
    expect(griefSupportLocation, '/safety-resources?focus=grief');
    final router = File('lib/app/routing/app_router.dart').readAsStringSync();
    expect(
      router,
      contains("focus: SupportFocus.parse(state.uri.queryParameters['focus'])"),
    );
  });

  testWidgets('Settings -> Support: Find support first, only when given', (
    tester,
  ) async {
    late List<String> on;
    late List<String> off;
    await pumpFlowScreen(
      tester,
      () => Builder(
        builder: (context) {
          List<String> support(List sections) => [
            for (final s in sections)
              if (s.id == 'support')
                for (final i in s.items) i.id as String,
          ];
          final report = childReportSetting(
            context,
            id: 'child_report_support',
            order: 0,
          );
          on = support(
            SettingsDataSource.getSettingsSections(
              context,
              'me',
              childReportSupport: report,
              supportResources: supportResourcesSetting(context),
            ),
          );
          off = support(
            SettingsDataSource.getSettingsSections(
              context,
              'me',
              childReportSupport: report,
            ),
          );
          return const SizedBox();
        },
      ),
    );
    expect(on.first, 'support_resources');
    expect(on[1], 'child_report_support');
    expect(on.skip(1), off);
    expect(off, isNot(contains('support_resources')));
  });

  testWidgets('the manual says "Help for where you are" only with the flag', (
    tester,
  ) async {
    DocumentationRegistry.initialize();
    Future<String> text(Set<String> flags) async {
      late BuildContext context;
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            documentationFlagsProvider.overrideWith((ref) async => flags),
          ],
          child: MaterialApp(
            home: Consumer(
              builder: (c, ref, _) {
                ref.watch(documentationFlagsProvider);
                context = c;
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final module = DocumentationRegistry.getById('safety')!;
      return [
        for (final s in module.getSections(context))
          for (final c in s.contents) '${c.title} ${c.content}',
      ].join('\n');
    }

    expect(await text(const {}), isNot(contains('Help for where you are')));
    expect(
      await text(const {'support_resources_v2'}),
      contains('Help for where you are'),
    );
  });
}
```

- [ ] **Step 2: Run it to make sure it fails**

```bash
flutter test test/features/safety/w7/support_hooks_test.dart 2>&1 | grep -E "Error when reading|Some tests failed" | head -2
```

Expected: `Error when reading 'lib/features/me/presentation/widgets/healing_choice_sheet.dart': No such file or directory`; `Some tests failed`.

- [ ] **Step 3: The Healing choice**

Create `lib/features/me/presentation/widgets/healing_choice_sheet.dart` with exactly:

```dart
import 'package:attune/app/routing/app_router.dart' show RouteNames;
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/utils/bottom_sheet_utils.dart';
import 'package:attune/features/me/presentation/widgets/your_space_section.dart';
import 'package:attune/features/safety/presentation/providers/support_resources_providers.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// What the Healing row's "After a breakup or a loss" was (Spec 1 §3.10).
enum HealingChoice { breakup, loss }

/// Where grief support lives: the Support screen's grief view (W7a).
final griefSupportLocation = '${RouteNames.safetyResources}?focus=grief';

/// Spec 1 W7a (§3.10): with support_resources_v2 on, the Healing row asks
/// first. "A breakup" opens Healing as before; "Someone I love died" opens
/// grief support, with "Write about it in your journal". Off: Healing as
/// before, no question.
Future<void> openHealingOrGrief(BuildContext context, WidgetRef ref) async {
  if (!ref.read(supportResourcesV2Provider)) return openHealing(context, ref);
  final choice =
      await BottomSheetUtils.showDocumentationBottomSheet<HealingChoice>(
        context: context,
        backgroundColor: Theme.of(context).colorScheme.surface,
        widget: const HealingChoiceSheet(),
      );
  if (!context.mounted) return;
  switch (choice) {
    case HealingChoice.breakup:
      await openHealing(context, ref);
    case HealingChoice.loss:
      await context.push(griefSupportLocation);
    case null:
      break;
  }
}

class HealingChoiceSheet extends StatelessWidget {
  const HealingChoiceSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    Widget option(String label, HealingChoice choice) => Padding(
      padding: const EdgeInsets.only(top: Spacing.sm),
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 56),
          alignment: AlignmentDirectional.centerStart,
          foregroundColor: theme.colorScheme.onSurface,
        ),
        onPressed: () => Navigator.of(context).pop(choice),
        child: Text(label),
      ),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Spacing.lg,
        Spacing.sm,
        Spacing.lg,
        Spacing.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(
              loc.flow_healingChoiceTitle,
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
          option(loc.flow_healingBreakup, HealingChoice.breakup),
          option(loc.flow_healingLoss, HealingChoice.loss),
        ],
      ),
    );
  }
}
```

`lib/features/me/presentation/widgets/your_space_section.dart`, edit 1 of 2. Replace exactly:

```dart
import 'package:attune/features/healing/presentation/widgets/healing_self_report_sheet.dart';
```

with:

```dart
import 'package:attune/features/healing/presentation/widgets/healing_self_report_sheet.dart';
import 'package:attune/features/me/presentation/widgets/healing_choice_sheet.dart';
```

`lib/features/me/presentation/widgets/your_space_section.dart`, edit 2 of 2. Replace exactly:

```dart
              icon: Icons.healing_outlined,
              onTap: () => openHealing(context, ref),
```

with:

```dart
              icon: Icons.healing_outlined,
              // Spec 1 W7a: a breakup or a loss, asked first (flag on).
              onTap: () => openHealingOrGrief(context, ref),
```

- [ ] **Step 4: X1's youth link**

`lib/features/auth/sign_up/presentation/screens/under_age_stop_screen.dart`, edit 1 of 4. Replace exactly:

```dart
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_frame.dart';
```

with:

```dart
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_frame.dart';
import 'package:attune/features/safety/presentation/providers/support_resources_providers.dart';
```

`lib/features/auth/sign_up/presentation/screens/under_age_stop_screen.dart`, edit 2 of 4. Replace exactly:

```dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
```

with:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
```

`lib/features/auth/sign_up/presentation/screens/under_age_stop_screen.dart`, edit 3 of 4. Replace exactly:

```dart
  /// Before W7's country list: the international helpline directory.
  static const youthSupportUrl = 'https://findahelpline.com';
```

with:

```dart
  /// Before W7's country list: the international helpline directory.
  static const youthSupportUrl = 'https://findahelpline.com';

  /// Spec 1 W7a (§3.6): the youth help for this phone's country, with the
  /// directory as its fallback, on the Support screen.
  static final youthSupportLocation =
      '${RouteNames.safetyResources}?focus=youth';

  /// support_resources_v2, read when the link is tapped. No ProviderScope
  /// (a bare test frame) reads as off: the directory, as before W7.
  static bool _supportV2(BuildContext context) {
    try {
      return ProviderScope.containerOf(
        context,
        listen: false,
      ).read(supportResourcesV2Provider);
    } catch (_) {
      return false;
    }
  }
```

`lib/features/auth/sign_up/presentation/screens/under_age_stop_screen.dart`, edit 4 of 4. Replace exactly:

```dart
            onPressed:
                () => UrlLauncherUtils.launchUrlWithFeedback(
                  context: context,
                  url: youthSupportUrl,
                ),
```

with:

```dart
            onPressed:
                () =>
                    _supportV2(context)
                        ? context.push(youthSupportLocation)
                        : UrlLauncherUtils.launchUrlWithFeedback(
                          context: context,
                          url: youthSupportUrl,
                        ),
```

- [ ] **Step 5: Settings -> Support, and the manual**

`lib/features/settings/data/settings_data.dart`, edit 1 of 2. Replace exactly:

```dart
    SettingsConfig? childReportSupport,
  }) {
```

with:

```dart
    SettingsConfig? childReportSupport,
    SettingsConfig? supportResources,
  }) {
```

`lib/features/settings/data/settings_data.dart`, edit 2 of 2. Replace exactly:

```dart
// Spec 1 W6c (§3.15): the same report, from Support too (signed in).
if (childReportSupport != null) childReportSupport,
```

with:

```dart
// Spec 1 W7a (§5.2): Find support, signed in or not (support_resources_v2).
if (supportResources != null) supportResources,
// Spec 1 W6c (§3.15): the same report, from Support too (signed in).
if (childReportSupport != null) childReportSupport,
```

`lib/features/settings/screens/settings_screen.dart`, edit 1 of 2. Replace exactly:

```dart
import 'package:attune/features/safety/presentation/screens/report_child_concern_screen.dart';
```

with:

```dart
import 'package:attune/features/safety/presentation/screens/report_child_concern_screen.dart';
import 'package:attune/features/safety/presentation/providers/support_resources_providers.dart';
import 'package:attune/features/safety/presentation/screens/support_resources_v2_screen.dart'
    show supportResourcesSetting;
```

`lib/features/settings/screens/settings_screen.dart`, edit 2 of 2. Replace exactly:

```dart
              : childReportSetting(
                context,
                id: 'child_report_support',
                order: 0,
              ),
    );
```

with:

```dart
              : childReportSetting(
                context,
                id: 'child_report_support',
                order: 0,
              ),
      supportResources:
          ref.watch(supportResourcesV2Provider)
              ? supportResourcesSetting(context)
              : null,
    );
```

`lib/app/documentations/user_manual/data/manual_documentation_registry.dart`, edit 1 of 1. Replace exactly:

```dart
    // Spec 1 W3c: the journal reminder (Your space, Settings).
    'journalReminder': ['flow_signin_v2', 'flow_paths_v2'],
```

with:

```dart
    // Spec 1 W3c: the journal reminder (Your space, Settings).
    'journalReminder': ['flow_signin_v2', 'flow_paths_v2'],
    // Spec 1 W7a: help for the country you're in (Support resources v2).
    'supportResourcesV2': ['support_resources_v2'],
```

`lib/app/documentations/user_manual/data/safety_docs.dart`, edit 1 of 2. Replace exactly:

```dart
import 'package:flutter/material.dart';
import 'package:attune/app/documentations/user_manual/models/documentation_model.dart'
    show DocumentationModule;
```

with:

```dart
import 'package:flutter/material.dart';
import 'package:attune/app/documentations/user_manual/data/documentation_flags.dart';
import 'package:attune/app/documentations/user_manual/data/manual_documentation_registry.dart';
import 'package:attune/app/documentations/user_manual/models/documentation_model.dart'
    show DocumentationModule;
```

`lib/app/documentations/user_manual/data/safety_docs.dart`, edit 2 of 2. Replace exactly:

```dart
        ManualContent(
          id: 'safety_no_erase_claim',
```

with:

```dart
        // Spec 1 W7a: only while Support resources v2 is on.
        if (DocumentationRegistry.passageVisible(
          'supportResourcesV2',
          documentationFlagsOf(context),
        ))
          ManualContent(
            id: 'safety_resources_by_country',
            title: 'Help for where you are',
            content:
                'Support resources shows checked helplines for your country, with emergency numbers first. Help that isn\'t the police is marked "Not the police". If we don\'t have a checked list for your country yet, "Find a helpline" opens an international directory. You can change the country; your choice isn\'t saved on your phone. It works offline too.',
            numberPrefix: '3',
            type: ManualContentType.text,
          ),
        ManualContent(
          id: 'safety_no_erase_claim',
```

`test/app/documentations/documentation_registry_flags_test.dart`, edit 1 of 1. Replace exactly:

```dart
          // Spec 1 W5: About us.
          'flow_couples_v2',
          'couple_profile',
```

with:

```dart
          // Spec 1 W5: About us.
          'flow_couples_v2',
          'couple_profile',
          // Spec 1 W7a: Support resources v2.
          'support_resources_v2',
```

- [ ] **Step 6: Run the test, write the goldens, look at them; then the touched suites**

```bash
flutter test --update-goldens test/features/safety/w7/support_hooks_test.dart 2>&1 | tail -1
flutter test test/features/safety/w7 test/launch test/features/me test/features/settings test/app/documentations test/features/auth/sign_up/guest_age_gate_screen_test.dart test/features/safety test/core/flags 2>&1 | tail -1
flutter analyze --no-pub lib/features/me lib/features/settings lib/features/auth/sign_up lib/app/documentations lib/features/safety test/features/safety/w7 test/app/documentations 2>&1 | grep -E '^\s*(error|warning) '
```

Expected: `+9: All tests passed!`; `All tests passed!` (the `healing_choice.*.png` goldens: the question as a heading and two full-width 56-dp choices, nothing clipped at 2.0 or in RTL); no analyzer output.

- [ ] **Step 7: Mutation checks (each must turn the hooks test red)**

```bash
D=.superpowers/sdd/2026-11-03-spec1-w7
T=test/features/safety/w7/support_hooks_test.dart
dmut() { # name file old new test
  cp "$2" "$D/mut.orig"
  python3 -I - "$2" "$3" "$4" <<'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1]); s = p.read_text()
assert s.count(sys.argv[2]) == 1, sys.argv[2]
p.write_text(s.replace(sys.argv[2], sys.argv[3]))
PY
  echo "$1: $(flutter test "$5" 2>&1 | tail -1 | grep -oE '(All tests passed|Some tests failed)')"
  cp "$D/mut.orig" "$2"; rm "$D/mut.orig"
}
dmut healing_asks_without_flag lib/features/me/presentation/widgets/healing_choice_sheet.dart \
  '  if (!ref.read(supportResourcesV2Provider)) return openHealing(context, ref);' '' $T
dmut x1_ignores_flag lib/features/auth/sign_up/presentation/screens/under_age_stop_screen.dart \
  '                    _supportV2(context)' '                    false' $T
dmut passage_ungated lib/app/documentations/user_manual/data/safety_docs.dart \
  "        if (DocumentationRegistry.passageVisible(
          'supportResourcesV2',
          documentationFlagsOf(context),
        ))" '        if (true)' $T
dmut find_support_last lib/features/settings/data/settings_data.dart \
  '// Spec 1 W7a (§5.2): Find support, signed in or not (support_resources_v2).
if (supportResources != null) supportResources,
// Spec 1 W6c (§3.15): the same report, from Support too (signed in).
if (childReportSupport != null) childReportSupport,' '// Spec 1 W6c (§3.15): the same report, from Support too (signed in).
if (childReportSupport != null) childReportSupport,
if (supportResources != null) supportResources,' $T
flutter test $T 2>&1 | tail -1 | grep -oE '(All tests passed|Some tests failed)'
```

Expected: `healing_asks_without_flag`, `x1_ignores_flag`, `passage_ungated` and `find_support_last` each `Some tests failed`; then `All tests passed`.

- [ ] **Step 8: W7a gate (run tests)**

```bash
dart format lib/features/safety/data/support_resources_repository.dart lib/features/safety/presentation/providers/support_resources_providers.dart lib/features/safety/presentation/screens/support_resources_v2_screen.dart lib/features/me/presentation/widgets/healing_choice_sheet.dart test/features/safety/w7/support_resources_repository_test.dart test/features/safety/w7/support_resources_v2_test.dart test/features/safety/w7/support_hooks_test.dart test/launch/support_resources_release_test.dart
flutter test 2>&1 | tail -1
flutter analyze --no-pub lib test 2>&1 | grep -E '^\s*error ' | sort | comm -13 .superpowers/sdd/2026-11-03-spec1-w7/analyze-baseline.txt -
flutter test test/architecture/games_untouched_test.dart 2>&1 | tail -1
sed -n '/if (isAuthenticated && !_gateData.isComplete) {/,/_redirectingToOnboarding = false;/p' lib/home/home_screen.dart | shasum | diff - .superpowers/sdd/2026-11-03-spec1-w7/latch.sha && echo latch-unchanged
git status --short lib/features/games lib/features/opinions lib/features/auth/utility/auth_exports.dart lib/home ATTUNE_SOUL.md ATTUNE_THESIS.md supabase/sql
for f in supabase/tests/*.sql; do
  if psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f "$f" >/dev/null 2>&1; then echo "PASS $(basename "$f")"; else echo "FAIL $(basename "$f")"; fi
done > .superpowers/sdd/2026-11-03-spec1-w7/sql-after-w7a.txt
grep '^FAIL' .superpowers/sdd/2026-11-03-spec1-w7/sql-after-w7a.txt | comm -13 <(grep '^FAIL' .superpowers/sdd/2026-11-03-spec1-w7/sql-baseline.txt) -
grep -E 'support_resources|identity_foundation|dormancy|child_safety|account_deletion' .superpowers/sdd/2026-11-03-spec1-w7/sql-after-w7a.txt
```

Expected: `Formatted 8 files (0 changed)`; `All tests passed!`; no new analyzer `error` line; the Games test passes; `latch-unchanged`; no `git status` line; no new FAIL; `PASS` for `account_deletion_contracts.sql`, `child_safety_contracts.sql`, `dormancy_contracts.sql`, `identity_foundation_contracts.sql`, `support_resources_contracts.sql`.

**W7a gate (before `support_resources_v2` in production; spec §8 W7a):** resource entries verified per country (Ghana, the UK, the US and Canada with every category: emergency, dv, crisis, sexual_assault, sextortion including CSA 292 and StopNCII, child_safety, youth, lgbtq_legal, grief, perinatal) within 7 days of release, every other country's emergency number and the international directory, by the DV professional and the cultural reviewer; the clinician reviews the grief branch copy (P-11). The shipped file meets none of that by design (P-4): owner checklist 4.

---

# W7b · Image safety (Tasks 5-8)

### Task 5: Migration 15: the queue, the one match path, the enqueue with its F-1 fallback (§4.2, §4.3 W7b, §4.4, §4.6, §4.7 #15, §4.8, §7.1, §7.4; I-10, F-1; P-15-P-22, P-25-P-28)

**Files:**
- Create: `supabase/migrations/20261103140000_media_scan.sql`, `…140010_media_scan_grants.sql`
- Create: `supabase/migrations/20261103140100_media_scan_enqueue.sql`, `…140110_media_scan_enqueue_grants.sql`
- Create: `supabase/tests/media_scan_contracts.sql`
- Modify: `scripts/local_pg_grants.sql` (one `\i` block; never run)

**Interfaces:**
- Consumes: `public.place_account_hold(uuid, text, text)`, `public.queue_media_deletion(text, text)`, `private.spec1_flag_on(text)`, `public.get_identity_health()` (live body), `private.identity_health_w6a()`, `public.invoke_edge_function(text)`, `storage.objects`, `storage.buckets`, `cron.*`.
- Produces (Tasks 7-8 and Spec 2 rely on these names): `private.media_scan_queue` (`id bigserial`, `bucket`, `object_name`, `owner_user_id`, `mime`, `source` queue|inline, `status` pending|scanning|clear|match|failed|skipped, `attempts`, `next_attempt_at`, `enqueued_at`, `scanned_at`, `vendor`, `vendor_ref`; UNIQUE (`bucket`, `object_name`)); `public.safety_escalations` (`id bigint` identity, `kind` csam_match|scan_failed, `user_id`, `bucket`, `object_name`, `status` open|reported|closed, `created_at`, `notes`, `vendor`, `vendor_ref`, `quarantined`, `alerted_at`); bucket `safety-quarantine` (private); `private.media_scan_state` (`enqueue_path` trigger|sweep, `path_recorded_at`, `sweep_watermark`, `enqueue_failures`, `last_enqueue_failure_at`); `private.media_scan_buckets() → text[]`; `private.enqueue_media_object(text, text, uuid, text, timestamptz)`; `private.handle_csam_match(p_bucket, p_object_name, p_owner uuid, p_vendor, p_vendor_ref, p_quarantined boolean DEFAULT true) → bigint`; `public.claim_media_scan_jobs(p_limit int) → TABLE (id bigint, bucket text, object_name text, owner_user_id uuid, mime text, attempts int)`; `public.complete_media_scan(p_job_id bigint, p_result text, p_vendor text, p_vendor_ref text) → void` (`p_result` IN clear, match, match_unquarantined, unavailable, skipped; raises `media_scan:invalid_result|no_job`); `public.record_inline_csam_match(p_bucket, p_object_name, p_owner uuid, p_vendor, p_vendor_ref, p_quarantined boolean DEFAULT true) → bigint`; `public.csam_escalations_due()`, `public.scan_failed_escalations_due()` (→ `{ids, count, first_at, last_at}`), `public.mark_safety_escalations_alerted(bigint[])`; `private.expire_media_scan_jobs()`, `private.media_scan_retention()`, `private.identity_health_w7b()`; `private.enqueue_media_scan()` (trigger), `private.enqueue_new_storage_objects() → int`, `private.install_media_scan_enqueue(p_force_sweep boolean DEFAULT false) → text`; crons `scan-media` (`* * * * *`), `media-scan-retention` (`27 4 * * *`), and, on the sweep path only, `enqueue-new-storage-objects` (`* * * * *`).

- [ ] **Step 1: Write the failing contract**

Create `supabase/tests/media_scan_contracts.sql` with exactly:

```sql
-- supabase/tests/media_scan_contracts.sql
-- Spec 1 W7b (§4.2, §4.3 W7b, §4.4, §4.6, §7.1, §7.4; reviews F-1, I-10):
-- image safety. New uploads in the listed buckets are queued (by the
-- trigger, or by the sweep where the trigger can't be created), never a
-- dating-profile-photos object, only with csam_hash_matching on; a failing
-- queue insert never blocks the upload; a queued match and an inline match
-- each give exactly one hold and one escalation through the one path; an
-- inline match twice is idempotent; no client reaches the queue, the
-- escalations or the quarantine. One BEGIN ... ROLLBACK.
-- Run only on attune_spec3a:
--   psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/media_scan_contracts.sql
-- Fixture ids 5f7b0000-0000-0000-0000-0000000000NN; phones +15558500NN
-- (§7.1's 85xx range), on auth.users and public.users; objects under
-- w7-contract/. Every refusal is checked by its message or SQLSTATE.
BEGIN;

CREATE FUNCTION pg_temp.id(p_n text) RETURNS uuid LANGUAGE sql AS $$
  SELECT ('5f7b0000-0000-0000-0000-0000000000' || p_n)::uuid;
$$;

CREATE FUNCTION pg_temp.person(p_n text) RETURNS uuid LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO auth.users (id, phone, phone_confirmed_at) VALUES (pg_temp.id(p_n), '15558500' || p_n, now());
  INSERT INTO public.users (id, phone, display_name, path)
  VALUES (pg_temp.id(p_n), '15558500' || p_n, 'Person ' || p_n, 'just_me');
  RETURN pg_temp.id(p_n);
END $$;

-- An upload, the way Storage writes the row.
CREATE FUNCTION pg_temp.upload(p_bucket text, p_name text, p_owner uuid, p_mime text,
                               p_created timestamptz DEFAULT now()) RETURNS void LANGUAGE sql AS $$
  INSERT INTO storage.objects (bucket_id, name, owner, metadata, created_at)
  VALUES (p_bucket, 'w7-contract/' || p_name, p_owner,
          jsonb_build_object('mimetype', p_mime, 'eTag', '"' || md5(p_name) || '"', 'size', 1024), p_created);
$$;

CREATE FUNCTION pg_temp.queued(p_bucket text, p_name text) RETURNS text LANGUAGE plpgsql AS $$
BEGIN
  RETURN (SELECT q.status FROM private.media_scan_queue AS q
           WHERE q.bucket = p_bucket AND q.object_name = 'w7-contract/' || p_name);
END $$;

CREATE FUNCTION pg_temp.flag(p_on boolean) RETURNS void LANGUAGE sql AS $$
  INSERT INTO public.feature_flags (key, enabled) VALUES ('csam_hash_matching', p_on)
  ON CONFLICT (key) DO UPDATE SET enabled = EXCLUDED.enabled;
$$;

-- [p_sql] as the service role: NULL, or the refusal's message.
CREATE FUNCTION pg_temp.service(p_sql text) RETURNS text LANGUAGE plpgsql AS $$
DECLARE
  v text;
BEGIN
  EXECUTE 'SET LOCAL ROLE service_role';
  BEGIN
    EXECUTE p_sql;
  EXCEPTION WHEN OTHERS THEN
    v := SQLERRM;
  END;
  RESET ROLE;
  RETURN v;
END $$;

-- The SQLSTATE (or NULL) of [p_sql] as [p_role].
CREATE FUNCTION pg_temp.client_error(p_role text, p_sql text) RETURNS text LANGUAGE plpgsql AS $$
DECLARE
  v text;
BEGIN
  EXECUTE format('SET LOCAL ROLE %I', p_role);
  BEGIN
    EXECUTE p_sql;
  EXCEPTION WHEN OTHERS THEN
    v := SQLSTATE;
  END;
  RESET ROLE;
  RETURN v;
END $$;

-- How uploads reach the queue on this database: 'trigger' or 'sweep'.
CREATE FUNCTION pg_temp.path() RETURNS text LANGUAGE plpgsql AS $$
BEGIN
  RETURN (SELECT s.enqueue_path FROM private.media_scan_state AS s);
END $$;

-- On the sweep path, run the sweep now (what its cron does every minute);
-- on the trigger path the uploads are already queued.
CREATE FUNCTION pg_temp.settle() RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  IF pg_temp.path() = 'sweep' THEN
    UPDATE private.media_scan_state SET sweep_watermark = now() - interval '1 minute';
    PERFORM private.enqueue_new_storage_objects();
  END IF;
END $$;

-- The job id of an object.
CREATE FUNCTION pg_temp.job(p_bucket text, p_name text) RETURNS bigint LANGUAGE plpgsql AS $$
BEGIN
  RETURN (SELECT q.id FROM private.media_scan_queue AS q
           WHERE q.bucket = p_bucket AND q.object_name = 'w7-contract/' || p_name);
END $$;

-- Buckets the fixtures need that this database may not have.
INSERT INTO storage.buckets (id, name, public) VALUES ('avatars', 'avatars', true) ON CONFLICT (id) DO NOTHING;
INSERT INTO storage.buckets (id, name, public) VALUES ('dating-profile-photos', 'dating-profile-photos', false) ON CONFLICT (id) DO NOTHING;
INSERT INTO storage.buckets (id, name, public) VALUES ('data-exports', 'data-exports', false) ON CONFLICT (id) DO NOTHING;

-- =====================================================================
-- A. Objects, grants and the crons; nothing reaches a client (§4.2, §7.1).
-- =====================================================================
DO $$
DECLARE
  v_bad text;
BEGIN
  IF to_regclass('private.media_scan_queue') IS NULL
     OR to_regclass('public.safety_escalations') IS NULL
     OR to_regclass('private.media_scan_state') IS NULL
     OR to_regprocedure('private.handle_csam_match(text,text,uuid,text,text,boolean)') IS NULL
     OR to_regprocedure('public.claim_media_scan_jobs(integer)') IS NULL
     OR to_regprocedure('public.complete_media_scan(bigint,text,text,text)') IS NULL
     OR to_regprocedure('public.record_inline_csam_match(text,text,uuid,text,text,boolean)') IS NULL
     OR to_regprocedure('private.enqueue_media_scan()') IS NULL
     OR to_regprocedure('private.enqueue_new_storage_objects()') IS NULL
     OR to_regprocedure('private.install_media_scan_enqueue(boolean)') IS NULL
     OR NOT EXISTS (SELECT 1 FROM storage.buckets WHERE id = 'safety-quarantine' AND NOT public) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: W7b objects are missing';
  END IF;
  IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid = 'public.safety_escalations'::regclass)
     OR EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'safety_escalations')
     OR EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'storage' AND tablename = 'objects'
                 AND (coalesce(qual, '') || coalesce(with_check, '')) ~ 'safety-quarantine') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: escalations or the quarantine have a client policy';
  END IF;
  SELECT string_agg(r || ' ' || t, ', ') INTO v_bad
    FROM unnest(ARRAY['anon', 'authenticated']) AS r,
         unnest(ARRAY['private.media_scan_queue', 'public.safety_escalations', 'private.media_scan_state']) AS t
   WHERE has_table_privilege(r, t, 'SELECT') OR has_table_privilege(r, t, 'INSERT')
      OR has_table_privilege(r, t, 'UPDATE') OR has_table_privilege(r, t, 'DELETE');
  IF v_bad IS NOT NULL
     OR has_table_privilege('service_role', 'private.media_scan_queue', 'SELECT')
     OR NOT has_table_privilege('service_role', 'public.safety_escalations', 'SELECT')
     OR NOT has_table_privilege('service_role', 'public.safety_escalations', 'UPDATE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: table grants are wrong (no client; the service role works the escalations; the queue is function-only): %', v_bad;
  END IF;
  SELECT string_agg(f, ', ') INTO v_bad
    FROM unnest(ARRAY['public.claim_media_scan_jobs(integer)', 'public.complete_media_scan(bigint,text,text,text)',
                      'public.record_inline_csam_match(text,text,uuid,text,text,boolean)',
                      'public.csam_escalations_due()', 'public.scan_failed_escalations_due()',
                      'public.mark_safety_escalations_alerted(bigint[])']) AS f
   WHERE has_function_privilege('anon', f, 'EXECUTE') OR has_function_privilege('authenticated', f, 'EXECUTE')
      OR NOT has_function_privilege('service_role', f, 'EXECUTE');
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a W7b service function has the wrong grants: %', v_bad;
  END IF;
  SELECT string_agg(f, ', ') INTO v_bad
    FROM unnest(ARRAY['private.handle_csam_match(text,text,uuid,text,text,boolean)',
                      'private.enqueue_media_object(text,text,uuid,text,timestamp with time zone)',
                      'private.enqueue_media_scan()', 'private.enqueue_new_storage_objects()',
                      'private.install_media_scan_enqueue(boolean)', 'private.expire_media_scan_jobs()',
                      'private.media_scan_retention()', 'private.identity_health_w7b()']) AS f
   WHERE has_function_privilege('anon', f, 'EXECUTE') OR has_function_privilege('authenticated', f, 'EXECUTE')
      OR has_function_privilege('service_role', f, 'EXECUTE');
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a server-only W7b function is executable by a role: %', v_bad;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'scan-media' AND schedule = '* * * * *'
                  AND command ~ 'invoke_edge_function\(''scan-media''\)')
     OR NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'media-scan-retention' AND schedule = '27 4 * * *') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the scan-media or media-scan-retention cron is missing';
  END IF;
  -- Both entry points go through the one path; nothing tells anyone.
  IF (SELECT prosrc FROM pg_proc WHERE oid = 'public.complete_media_scan(bigint,text,text,text)'::regprocedure) !~ 'private\.handle_csam_match'
     OR (SELECT prosrc FROM pg_proc WHERE oid = 'public.record_inline_csam_match(text,text,uuid,text,text,boolean)'::regprocedure) !~ 'private\.handle_csam_match' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a match entry point does not use private.handle_csam_match (review I-10)';
  END IF;
  IF (SELECT prosrc FROM pg_proc WHERE oid = 'private.handle_csam_match(text,text,uuid,text,text,boolean)'::regprocedure)
       ~* '(notification|push|net\.http|invoke_edge_function|relationships|messages)' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the match path reaches beyond the hold, the escalation and the deletion (nothing may tell anyone)';
  END IF;
END $$;

-- =====================================================================
-- B. The trigger (§4.4): listed buckets, images and videos, with the flag;
--    never dating-profile-photos (I-10); a picture written over in place
--    is queued again (plan P-17).
-- =====================================================================
DO $$
DECLARE
  v_ama constant uuid := pg_temp.person('01');
BEGIN
  -- The recorded path is the real one: a trigger and no sweep, or the
  -- sweep's cron and no trigger (plan P-16). Locally it is the trigger.
  IF pg_temp.path() IS NULL
     OR (pg_temp.path() = 'trigger') IS DISTINCT FROM
        EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid = 'storage.objects'::regclass AND tgname = 'enqueue_media_scan')
     OR (pg_temp.path() = 'sweep') IS DISTINCT FROM
        EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'enqueue-new-storage-objects') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the recorded enqueue path (%) is not the one installed', pg_temp.path();
  END IF;

  PERFORM pg_temp.flag(false);
  PERFORM pg_temp.upload('message-media', 'off.jpg', v_ama, 'image/jpeg');
  PERFORM pg_temp.settle();
  IF pg_temp.queued('message-media', 'off.jpg') IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an upload was queued with csam_hash_matching off';
  END IF;

  PERFORM pg_temp.flag(true);
  PERFORM pg_temp.upload('message-media', 'chat.jpg', v_ama, 'image/jpeg');
  PERFORM pg_temp.upload('story-media', 'story.mp4', v_ama, 'video/mp4');
  PERFORM pg_temp.upload('relationship-avatars', 'pair.png', v_ama, 'image/png');
  PERFORM pg_temp.upload('journal-media', 'note.jpg', v_ama, 'image/jpeg');
  PERFORM pg_temp.upload('planning-media', 'plan.jpg', v_ama, 'image/jpeg');
  PERFORM pg_temp.upload('avatars', 'me.jpg', v_ama, 'image/jpeg');
  PERFORM pg_temp.upload('dating-profile-photos', 'dating.jpg', v_ama, 'image/jpeg');
  PERFORM pg_temp.upload('data-exports', 'export.zip', v_ama, 'application/zip');
  PERFORM pg_temp.upload('message-media', 'voice.m4a', v_ama, 'audio/mp4');
  PERFORM pg_temp.settle();

  IF pg_temp.queued('message-media', 'chat.jpg') IS DISTINCT FROM 'pending'
     OR pg_temp.queued('story-media', 'story.mp4') IS DISTINCT FROM 'pending'
     OR pg_temp.queued('relationship-avatars', 'pair.png') IS DISTINCT FROM 'pending'
     OR pg_temp.queued('journal-media', 'note.jpg') IS DISTINCT FROM 'pending'
     OR pg_temp.queued('planning-media', 'plan.jpg') IS DISTINCT FROM 'pending'
     OR pg_temp.queued('avatars', 'me.jpg') IS DISTINCT FROM 'pending' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an image or video in a listed bucket was not queued';
  END IF;
  IF pg_temp.queued('dating-profile-photos', 'dating.jpg') IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a dating-profile-photos object was queued (Spec 2 matches it inline, review I-10)';
  END IF;
  IF pg_temp.queued('data-exports', 'export.zip') IS NOT NULL OR pg_temp.queued('message-media', 'voice.m4a') IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an unlisted bucket or a non-image object was queued';
  END IF;
  IF (SELECT owner_user_id FROM private.media_scan_queue WHERE id = pg_temp.job('message-media', 'chat.jpg')) IS DISTINCT FROM v_ama
     OR (SELECT source FROM private.media_scan_queue WHERE id = pg_temp.job('message-media', 'chat.jpg')) IS DISTINCT FROM 'queue' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the queued row does not name its uploader or source';
  END IF;

  -- The avatar was scanned clear, then written over in place: queued again
  -- (the trigger compares the eTag; the sweep, where it runs, sees the
  -- row's updated_at).
  IF pg_temp.path() <> 'trigger' THEN
    RETURN;
  END IF;
  UPDATE private.media_scan_queue SET status = 'clear', scanned_at = now(), enqueued_at = now() - interval '1 hour'
   WHERE id = pg_temp.job('avatars', 'me.jpg');
  UPDATE storage.objects SET metadata = metadata || '{"eTag": "\"new-bytes\""}'
   WHERE bucket_id = 'avatars' AND name = 'w7-contract/me.jpg';
  IF pg_temp.queued('avatars', 'me.jpg') IS DISTINCT FROM 'pending' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a picture written over in place was not queued again';
  END IF;
  -- A metadata change that isn't new bytes queues nothing.
  UPDATE private.media_scan_queue SET status = 'clear', scanned_at = now(), enqueued_at = now() - interval '1 hour'
   WHERE id = pg_temp.job('avatars', 'me.jpg');
  UPDATE storage.objects SET metadata = metadata || '{"cacheControl": "max-age=60"}'
   WHERE bucket_id = 'avatars' AND name = 'w7-contract/me.jpg';
  IF pg_temp.queued('avatars', 'me.jpg') IS DISTINCT FROM 'clear' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a metadata change without new bytes queued the object again';
  END IF;
END $$;

-- =====================================================================
-- C. A failing queue insert never blocks the upload (§4.4, R13); the
--    failure is counted for identity health.
-- =====================================================================
DO $$
DECLARE
  v_before bigint := (SELECT enqueue_failures FROM private.media_scan_state);
BEGIN
  ALTER TABLE private.media_scan_queue ADD CONSTRAINT w7_contract_refuse CHECK (object_name <> 'w7-contract/refused.jpg');
  BEGIN
    PERFORM pg_temp.upload('message-media', 'refused.jpg', pg_temp.id('01'), 'image/jpeg');
    PERFORM pg_temp.settle();
  EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a failing queue insert blocked the upload (%)', SQLERRM;
  END;
  IF NOT EXISTS (SELECT 1 FROM storage.objects WHERE bucket_id = 'message-media' AND name = 'w7-contract/refused.jpg') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a failing queue insert blocked the upload';
  END IF;
  IF pg_temp.queued('message-media', 'refused.jpg') IS NOT NULL
     OR (SELECT enqueue_failures FROM private.media_scan_state) <> v_before + 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the failed enqueue was not counted';
  END IF;
  ALTER TABLE private.media_scan_queue DROP CONSTRAINT w7_contract_refuse;
END $$;

-- =====================================================================
-- D. The sweep (F-1 fallback), called directly, on uploads the trigger
--    didn't queue (made with the flag off): what changed since the last
--    sweep (2-minute overlap), the same buckets and rules, once each; with
--    the flag off it queues nothing but moves on.
-- =====================================================================
DO $$
DECLARE
  v_ama constant uuid := pg_temp.id('01');
BEGIN
  PERFORM pg_temp.flag(false);
  PERFORM pg_temp.upload('message-media', 'old.jpg', v_ama, 'image/jpeg', now() - interval '1 hour');
  PERFORM pg_temp.upload('message-media', 'swept.jpg', v_ama, 'image/jpeg');
  PERFORM pg_temp.upload('dating-profile-photos', 'swept-dating.jpg', v_ama, 'image/jpeg');
  PERFORM pg_temp.upload('journal-media', 'swept.txt', v_ama, 'text/plain');
  PERFORM pg_temp.flag(true);
  UPDATE private.media_scan_state SET sweep_watermark = now() - interval '1 minute';
  PERFORM private.enqueue_new_storage_objects();
  IF pg_temp.queued('message-media', 'swept.jpg') IS DISTINCT FROM 'pending' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the sweep did not queue a new upload';
  END IF;
  IF pg_temp.queued('message-media', 'old.jpg') IS NOT NULL
     OR pg_temp.queued('dating-profile-photos', 'swept-dating.jpg') IS NOT NULL
     OR pg_temp.queued('journal-media', 'swept.txt') IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the sweep queued an old, a dating or a non-image object';
  END IF;
  IF (SELECT sweep_watermark FROM private.media_scan_state) < now() THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the sweep did not move its watermark';
  END IF;
  -- Again: nothing new, nothing doubled.
  UPDATE private.media_scan_queue SET status = 'clear', scanned_at = now() WHERE id = pg_temp.job('message-media', 'swept.jpg');
  PERFORM private.enqueue_new_storage_objects();
  IF pg_temp.queued('message-media', 'swept.jpg') IS DISTINCT FROM 'clear'
     OR (SELECT count(*) FROM private.media_scan_queue WHERE object_name = 'w7-contract/swept.jpg') <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a second sweep queued an object again';
  END IF;
  -- Flag off: nothing queued, the watermark still moves.
  PERFORM pg_temp.flag(false);
  UPDATE private.media_scan_state SET sweep_watermark = now() - interval '1 minute';
  PERFORM pg_temp.upload('message-media', 'swept-off.jpg', v_ama, 'image/jpeg');
  PERFORM private.enqueue_new_storage_objects();
  IF pg_temp.queued('message-media', 'swept-off.jpg') IS NOT NULL
     OR (SELECT sweep_watermark FROM private.media_scan_state) < now() THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the sweep queued with the flag off, or stood still';
  END IF;
  PERFORM pg_temp.flag(true);
END $$;

-- =====================================================================
-- E. The F-1 choice (plan P-16): without the right to put a trigger on
--    storage.objects, the install schedules the sweep and records it; with
--    it, the trigger and no sweep.
-- =====================================================================
CREATE ROLE w7_contract_not_owner NOLOGIN;
GRANT USAGE ON SCHEMA private, cron, storage TO w7_contract_not_owner;
GRANT SELECT, UPDATE ON private.media_scan_state TO w7_contract_not_owner;
GRANT SELECT, INSERT, UPDATE, DELETE ON cron.job TO w7_contract_not_owner;
GRANT USAGE ON ALL SEQUENCES IN SCHEMA cron TO w7_contract_not_owner;
GRANT EXECUTE ON FUNCTION private.install_media_scan_enqueue(boolean) TO w7_contract_not_owner;
DO $$
DECLARE
  v text;
BEGIN
  -- Only where this role may drop the trigger (locally, where it owns
  -- storage.objects); a hosted-like CI database keeps it and skips E.
  BEGIN
    DROP TRIGGER IF EXISTS enqueue_media_scan ON storage.objects;
  EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'media_scan_contracts: section E skipped (this role cannot drop a storage.objects trigger)';
    RETURN;
  END;
  EXECUTE 'SET LOCAL ROLE w7_contract_not_owner';
  BEGIN
    v := private.install_media_scan_enqueue();
  EXCEPTION WHEN OTHERS THEN
    v := 'refused: ' || SQLERRM;
  END;
  RESET ROLE;
  IF v IS DISTINCT FROM 'sweep'
     OR EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid = 'storage.objects'::regclass AND tgname = 'enqueue_media_scan')
     OR NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'enqueue-new-storage-objects' AND schedule = '* * * * *'
                     AND command = 'SELECT private.enqueue_new_storage_objects()')
     OR (SELECT enqueue_path FROM private.media_scan_state) IS DISTINCT FROM 'sweep' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: without the trigger right the install did not fall back to the recorded sweep (got %)', v;
  END IF;
  IF (public.get_identity_health() ->> 'media_scan_enqueue_path') IS DISTINCT FROM 'sweep' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: identity health does not report the sweep path';
  END IF;

  -- With the right, the trigger alone again (the sweep's cron removed).
  v := private.install_media_scan_enqueue();
  IF v IS DISTINCT FROM 'trigger'
     OR NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid = 'storage.objects'::regclass AND tgname = 'enqueue_media_scan')
     OR EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'enqueue-new-storage-objects')
     OR pg_temp.path() IS DISTINCT FROM 'trigger' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: with the trigger right the install did not choose the trigger alone (got %)', v;
  END IF;
END $$;

-- =====================================================================
-- F. Claiming (§4.3): due jobs only, a lease, nothing with the flag off.
-- =====================================================================
DO $$
DECLARE
  v_ids bigint[];
  v_row record;
BEGIN
  -- Only this file's jobs are due.
  UPDATE private.media_scan_queue SET next_attempt_at = now() + interval '1 day'
   WHERE object_name NOT LIKE 'w7-contract/%' AND status IN ('pending', 'scanning');
  UPDATE private.media_scan_queue SET next_attempt_at = now() + interval '1 day'
   WHERE object_name LIKE 'w7-contract/%' AND status = 'pending';
  UPDATE private.media_scan_queue SET next_attempt_at = now() - interval '1 second'
   WHERE id IN (pg_temp.job('message-media', 'chat.jpg'), pg_temp.job('journal-media', 'note.jpg'),
                pg_temp.job('planning-media', 'plan.jpg'));

  PERFORM pg_temp.flag(false);
  EXECUTE 'SET LOCAL ROLE service_role';
  SELECT array_agg(c.id) INTO v_ids FROM public.claim_media_scan_jobs(10) AS c;
  RESET ROLE;
  IF v_ids IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: jobs were claimed with csam_hash_matching off';
  END IF;
  PERFORM pg_temp.flag(true);

  EXECUTE 'SET LOCAL ROLE service_role';
  SELECT array_agg(c.id ORDER BY c.id) INTO v_ids FROM public.claim_media_scan_jobs(2) AS c;
  RESET ROLE;
  IF cardinality(v_ids) IS DISTINCT FROM 2
     OR EXISTS (SELECT 1 FROM private.media_scan_queue WHERE id = ANY (v_ids)
                 AND (status <> 'scanning' OR attempts <> 1 OR next_attempt_at < now() + interval '9 minutes')) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a claim did not lease exactly the jobs asked for: %', v_ids;
  END IF;
  EXECUTE 'SET LOCAL ROLE service_role';
  SELECT array_agg(c.id) INTO v_ids FROM public.claim_media_scan_jobs(10) AS c;
  RESET ROLE;
  IF cardinality(v_ids) IS DISTINCT FROM 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a leased job was claimed twice, or a due one missed: %', v_ids;
  END IF;
  -- A lease that lapsed (the run died) is claimed again.
  UPDATE private.media_scan_queue SET next_attempt_at = now() - interval '1 second' WHERE id = v_ids[1];
  EXECUTE 'SET LOCAL ROLE service_role';
  SELECT * INTO v_row FROM public.claim_media_scan_jobs(10);
  RESET ROLE;
  IF v_row.id IS DISTINCT FROM v_ids[1] OR v_row.attempts <> 2 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a lapsed lease was not claimed again';
  END IF;
END $$;

-- =====================================================================
-- G. Completing (§4.3): clear, skipped, the back-off, 24 hours -> failed
--    and one scan_failed escalation; a stale answer changes nothing.
-- =====================================================================
DO $$
DECLARE
  v_job bigint := pg_temp.job('journal-media', 'note.jpg');
  v_got text;
BEGIN
  IF pg_temp.service(format('SELECT public.complete_media_scan(%s, ''maybe'', ''stub'', NULL)', v_job))
       IS DISTINCT FROM 'media_scan:invalid_result'
     OR pg_temp.service('SELECT public.complete_media_scan(-1, ''clear'', ''stub'', NULL)') IS DISTINCT FROM 'media_scan:no_job' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a bad completion was not refused by its message';
  END IF;

  -- unavailable: 1, 5, 15, 60 minutes.
  FOR i IN 1..5 LOOP
    UPDATE private.media_scan_queue SET status = 'scanning', attempts = i WHERE id = v_job;
    v_got := pg_temp.service(format('SELECT public.complete_media_scan(%s, ''unavailable'', ''photodna'', ''code:3208'')', v_job));
    IF v_got IS NOT NULL
       OR (SELECT status FROM private.media_scan_queue WHERE id = v_job) <> 'pending'
       OR abs(extract(epoch FROM (SELECT next_attempt_at FROM private.media_scan_queue WHERE id = v_job) - now())
              - CASE i WHEN 1 THEN 60 WHEN 2 THEN 300 WHEN 3 THEN 900 ELSE 3600 END) > 5 THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: attempt % did not back off as §4.3 says', i;
    END IF;
  END LOOP;

  -- clear, and a stale clear for a job that isn't scanning changes nothing.
  UPDATE private.media_scan_queue SET status = 'scanning' WHERE id = v_job;
  PERFORM pg_temp.service(format('SELECT public.complete_media_scan(%s, ''clear'', ''photodna'', ''t-1'')', v_job));
  IF (SELECT status || '/' || vendor || '/' || vendor_ref FROM private.media_scan_queue WHERE id = v_job) IS DISTINCT FROM 'clear/photodna/t-1'
     OR (SELECT scanned_at FROM private.media_scan_queue WHERE id = v_job) IS NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a clear result was not recorded';
  END IF;
  UPDATE private.media_scan_queue SET status = 'pending' WHERE id = pg_temp.job('planning-media', 'plan.jpg');
  PERFORM pg_temp.service(format('SELECT public.complete_media_scan(%s, ''clear'', ''photodna'', NULL)', pg_temp.job('planning-media', 'plan.jpg')));
  IF pg_temp.queued('planning-media', 'plan.jpg') IS DISTINCT FROM 'pending' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a stale clear (the job was queued again) was recorded';
  END IF;

  -- skipped (a video, or gone): never clear.
  UPDATE private.media_scan_queue SET status = 'scanning' WHERE id = pg_temp.job('story-media', 'story.mp4');
  PERFORM pg_temp.service(format('SELECT public.complete_media_scan(%s, ''skipped'', ''photodna'', ''video_not_hashed'')', pg_temp.job('story-media', 'story.mp4')));
  IF pg_temp.queued('story-media', 'story.mp4') IS DISTINCT FROM 'skipped' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a skipped result was not recorded as skipped';
  END IF;

  -- 24 hours unavailable: failed, one scan_failed escalation, no hold.
  UPDATE private.media_scan_queue SET status = 'scanning', enqueued_at = now() - interval '25 hours'
   WHERE id = pg_temp.job('relationship-avatars', 'pair.png');
  PERFORM pg_temp.service(format('SELECT public.complete_media_scan(%s, ''unavailable'', ''stub'', ''stub_refused_in_production'')',
                                 pg_temp.job('relationship-avatars', 'pair.png')));
  IF pg_temp.queued('relationship-avatars', 'pair.png') IS DISTINCT FROM 'failed'
     OR (SELECT count(*) FROM public.safety_escalations
          WHERE kind = 'scan_failed' AND object_name = 'w7-contract/pair.png' AND status = 'open'
            AND vendor_ref = 'stub_refused_in_production') <> 1
     OR EXISTS (SELECT 1 FROM public.account_holds WHERE user_id = pg_temp.id('01')) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: 24 hours unscanned did not fail with one scan_failed escalation (and no hold)';
  END IF;

  -- A job nobody answers is expired too (the claim and the retention).
  UPDATE private.media_scan_queue SET status = 'pending', enqueued_at = now() - interval '25 hours', next_attempt_at = now() + interval '1 day'
   WHERE id = pg_temp.job('planning-media', 'plan.jpg');
  PERFORM private.media_scan_retention();
  IF pg_temp.queued('planning-media', 'plan.jpg') IS DISTINCT FROM 'failed'
     OR NOT EXISTS (SELECT 1 FROM public.safety_escalations WHERE kind = 'scan_failed' AND object_name = 'w7-contract/plan.jpg') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a job left 24 hours was not failed and escalated';
  END IF;
END $$;

-- =====================================================================
-- H. A match: one path for the queue and inline (I-10); exactly one hold,
--    one escalation, the deletion queued after quarantine; idempotent; a
--    failed quarantine keeps the original (plan P-18).
-- =====================================================================
DO $$
DECLARE
  v_ama constant uuid := pg_temp.id('01');
  v_kofi constant uuid := pg_temp.person('02');
  v_job bigint := pg_temp.job('message-media', 'chat.jpg');
  v_esc bigint;
  v_again bigint;
BEGIN
  UPDATE private.media_scan_queue SET status = 'scanning' WHERE id = v_job;
  PERFORM pg_temp.service(format('SELECT public.complete_media_scan(%s, ''match'', ''photodna'', ''track-1'')', v_job));
  SELECT id INTO v_esc FROM public.safety_escalations WHERE kind = 'csam_match' AND object_name = 'w7-contract/chat.jpg';
  IF pg_temp.queued('message-media', 'chat.jpg') IS DISTINCT FROM 'match'
     OR v_esc IS NULL
     OR (SELECT user_id::text || '/' || status || '/' || vendor || '/' || vendor_ref || '/' || quarantined
           FROM public.safety_escalations WHERE id = v_esc) IS DISTINCT FROM v_ama::text || '/open/photodna/track-1/true' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a queued match did not open its escalation with the vendor reference';
  END IF;
  IF (SELECT count(*) FROM public.account_holds WHERE user_id = v_ama AND kind = 'safety_review' AND resolved_at IS NULL
         AND reason_ref = 'safety_escalation:' || v_esc) <> 1
     OR (SELECT count(*) FROM public.media_deletion_queue WHERE bucket_id = 'message-media' AND object_name = 'w7-contract/chat.jpg') <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a queued match did not hold the uploader and queue the original''s deletion';
  END IF;
  -- The same answer twice: still one of each, and no error.
  UPDATE private.media_scan_queue SET status = 'scanning' WHERE id = v_job;
  IF pg_temp.service(format('SELECT public.complete_media_scan(%s, ''match'', ''photodna'', ''track-2'')', v_job)) IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a repeated queued match was refused';
  END IF;
  IF (SELECT count(*) FROM public.safety_escalations WHERE object_name = 'w7-contract/chat.jpg') <> 1
     OR (SELECT count(*) FROM public.account_holds WHERE user_id = v_ama) <> 1
     OR (SELECT count(*) FROM public.media_deletion_queue WHERE object_name = 'w7-contract/chat.jpg') <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a repeated queued match made a second escalation, hold or deletion';
  END IF;

  -- Inline (Spec 2's process-dating-photo): the same path, once per object.
  EXECUTE 'SET LOCAL ROLE service_role';
  v_esc := public.record_inline_csam_match('dating-profile-photos', 'w7-contract/inline.jpg', v_kofi, 'photodna', 'track-3');
  RESET ROLE;
  IF v_esc IS NULL
     OR (SELECT source || '/' || status FROM private.media_scan_queue
          WHERE bucket = 'dating-profile-photos' AND object_name = 'w7-contract/inline.jpg') IS DISTINCT FROM 'inline/match'
     OR (SELECT count(*) FROM public.account_holds WHERE user_id = v_kofi AND kind = 'safety_review'
          AND reason_ref = 'safety_escalation:' || v_esc) <> 1
     OR (SELECT count(*) FROM public.media_deletion_queue WHERE bucket_id = 'dating-profile-photos' AND object_name = 'w7-contract/inline.jpg') <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an inline match did not take the same path (queue row, hold, deletion)';
  END IF;
  -- A reviewer clears the hold (a false match); the pipeline retries: the
  -- same escalation, and the resolved hold stays resolved.
  UPDATE public.account_holds SET resolved_at = now(), resolved_by = 'contract reviewer' WHERE user_id = v_kofi;
  EXECUTE 'SET LOCAL ROLE service_role';
  BEGIN
    v_again := public.record_inline_csam_match('dating-profile-photos', 'w7-contract/inline.jpg', v_kofi, 'photodna', 'track-4');
  EXCEPTION WHEN OTHERS THEN
    v_again := NULL;
  END;
  RESET ROLE;
  IF v_again IS DISTINCT FROM v_esc
     OR (SELECT count(*) FROM public.safety_escalations WHERE object_name = 'w7-contract/inline.jpg') <> 1
     OR (SELECT resolved_at FROM public.account_holds WHERE user_id = v_kofi) IS NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an inline match twice was not idempotent';
  END IF;

  -- The quarantine copy failed: held and escalated, the original kept.
  PERFORM pg_temp.service(format('SELECT public.record_inline_csam_match(%L, %L, %L, %L, %L, false)',
                                 'message-media', 'w7-contract/unquarantined.jpg', v_ama, 'photodna', 'track-5'));
  IF (SELECT quarantined FROM public.safety_escalations WHERE object_name = 'w7-contract/unquarantined.jpg') IS DISTINCT FROM false
     OR (SELECT notes FROM public.safety_escalations WHERE object_name = 'w7-contract/unquarantined.jpg') !~ 'still in place'
     OR EXISTS (SELECT 1 FROM public.media_deletion_queue WHERE object_name = 'w7-contract/unquarantined.jpg') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a match without a quarantine copy queued the evidence for deletion';
  END IF;
  -- match_unquarantined through the queue: the same.
  UPDATE private.media_scan_queue SET status = 'scanning' WHERE id = pg_temp.job('avatars', 'me.jpg');
  PERFORM pg_temp.service(format('SELECT public.complete_media_scan(%s, ''match_unquarantined'', ''photodna'', ''track-6'')', pg_temp.job('avatars', 'me.jpg')));
  IF (SELECT quarantined FROM public.safety_escalations WHERE object_name = 'w7-contract/me.jpg') IS DISTINCT FROM false
     OR EXISTS (SELECT 1 FROM public.media_deletion_queue WHERE object_name = 'w7-contract/me.jpg') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a queued match_unquarantined queued the evidence for deletion';
  END IF;

  -- No owner (a server upload): escalated, nobody held.
  PERFORM pg_temp.service(format('SELECT public.record_inline_csam_match(%L, %L, NULL, %L, %L)',
                                 'story-media', 'w7-contract/ownerless.jpg', 'photodna', 'track-7'));
  IF (SELECT user_id FROM public.safety_escalations WHERE object_name = 'w7-contract/ownerless.jpg') IS NOT NULL
     OR NOT EXISTS (SELECT 1 FROM public.safety_escalations WHERE object_name = 'w7-contract/ownerless.jpg') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an ownerless match was not escalated';
  END IF;
  -- A match is never dropped, even for a job no longer scanning.
  UPDATE private.media_scan_queue SET status = 'pending' WHERE id = pg_temp.job('story-media', 'story.mp4');
  PERFORM pg_temp.service(format('SELECT public.complete_media_scan(%s, ''match'', ''photodna'', ''track-8'')', pg_temp.job('story-media', 'story.mp4')));
  IF NOT EXISTS (SELECT 1 FROM public.safety_escalations WHERE object_name = 'w7-contract/story.mp4' AND kind = 'csam_match') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a match for a job that was not scanning was dropped';
  END IF;
END $$;

-- =====================================================================
-- I. The webhook's sources: ids, a count and times, never a person or a
--    path; marked once sent (plan P-21).
-- =====================================================================
DO $$
DECLARE
  v jsonb;
  v_ids bigint[];
BEGIN
  UPDATE public.safety_escalations SET alerted_at = now() WHERE object_name NOT LIKE 'w7-contract/%';
  EXECUTE 'SET LOCAL ROLE service_role';
  v := public.csam_escalations_due();
  RESET ROLE;
  IF (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(v) AS k) <> ARRAY['count', 'first_at', 'ids', 'last_at']
     OR v::text ~ '(w7-contract|5f7b0000|photodna|track)'
     OR (v ->> 'count')::int <> 6 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the match alert carries more than ids, a count and times, or the wrong count: %', v;
  END IF;
  SELECT array_agg(x::bigint) INTO v_ids FROM jsonb_array_elements_text(v -> 'ids') AS x;
  EXECUTE 'SET LOCAL ROLE service_role';
  PERFORM public.mark_safety_escalations_alerted(v_ids);
  v := public.csam_escalations_due();
  RESET ROLE;
  IF (v ->> 'count')::int <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: alerted escalations were due again';
  END IF;
  EXECUTE 'SET LOCAL ROLE service_role';
  v := public.scan_failed_escalations_due();
  RESET ROLE;
  IF (v ->> 'count')::int <> 2 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the scan_failed source counted wrongly: %', v;
  END IF;
END $$;

-- =====================================================================
-- J. Retention (§4.6, §4.8): clear and skipped rows go after 7 days;
--    matches and failures stay with their escalation. Identity health.
-- =====================================================================
DO $$
DECLARE
  v jsonb;
BEGIN
  UPDATE private.media_scan_queue SET scanned_at = now() - interval '8 days'
   WHERE object_name LIKE 'w7-contract/%' AND status IN ('clear', 'skipped', 'match', 'failed');
  PERFORM private.media_scan_retention();
  IF pg_temp.queued('journal-media', 'note.jpg') IS NOT NULL
     OR pg_temp.queued('message-media', 'chat.jpg') IS DISTINCT FROM 'match'
     OR pg_temp.queued('relationship-avatars', 'pair.png') IS DISTINCT FROM 'failed' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: retention removed a match or a failure, or kept a clear row';
  END IF;
  EXECUTE 'SET LOCAL ROLE service_role';
  v := public.get_identity_health();
  RESET ROLE;
  IF NOT (v ?& ARRAY['media_scan_enqueue_path', 'media_scan_enqueue_failures', 'media_scan_pending',
                     'media_scan_oldest_pending_minutes', 'media_scan_skipped_7d',
                     'safety_escalations_open', 'safety_escalations_unalerted',
                     'fresh_starts_7d', 'accounts_without_path'])
     OR (v ->> 'media_scan_enqueue_path') IS DISTINCT FROM pg_temp.path()
     OR (v ->> 'media_scan_enqueue_failures')::int < 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: identity health lacks the W7b lines (or lost the earlier ones): %', v;
  END IF;
  IF (SELECT prosrc FROM pg_proc WHERE oid = 'public.get_identity_health()'::regprocedure)
       ~* '(media_scan_queue|safety_escalations|media_scan_state)' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: get_identity_health names a W7 table itself (keep them in private.identity_health_w7b)';
  END IF;
END $$;

-- =====================================================================
-- K. No client reaches the queue, the escalations or the functions.
-- =====================================================================
DO $$
BEGIN
  IF pg_temp.client_error('authenticated', 'SELECT count(*) FROM public.safety_escalations') IS DISTINCT FROM '42501'
     OR pg_temp.client_error('authenticated', 'SELECT count(*) FROM private.media_scan_queue') IS DISTINCT FROM '42501'
     OR pg_temp.client_error('anon', 'SELECT count(*) FROM public.safety_escalations') IS DISTINCT FROM '42501'
     OR pg_temp.client_error('authenticated', 'SELECT * FROM public.claim_media_scan_jobs(5)') IS DISTINCT FROM '42501'
     OR pg_temp.client_error('authenticated', 'SELECT public.complete_media_scan(1, ''clear'', ''x'', NULL)') IS DISTINCT FROM '42501'
     OR pg_temp.client_error('authenticated', format('SELECT public.record_inline_csam_match(''avatars'', ''x'', %L, ''x'', NULL)', pg_temp.id('02'))) IS DISTINCT FROM '42501'
     OR pg_temp.client_error('anon', 'SELECT public.csam_escalations_due()') IS DISTINCT FROM '42501' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a client reached the image-safety tables or functions';
  END IF;
END $$;

DO $$ BEGIN RAISE NOTICE 'media_scan_contracts: all held'; END $$;

ROLLBACK;
```

- [ ] **Step 2: Run it to make sure it fails**

```bash
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/media_scan_contracts.sql 2>&1 | grep ERROR | sed -E 's/^psql:[^ ]* //'
```

Expected: `ERROR:  CONTRACT VIOLATED: W7b objects are missing`.

- [ ] **Step 3: Write migration 15a and its twin**

Create `supabase/migrations/20261103140000_media_scan.sql` with exactly:

```sql
-- Spec 1 W7b, migration 15a (spec §4.7 #15, as two files, plan P-15):
-- image safety, the queue and the one match path.
--   * private.media_scan_queue (spec §4.2): one row per object to match,
--     UNIQUE (bucket, object_name); source 'queue' or 'inline' (a match a
--     synchronous pipeline recorded, review I-10). Status 'skipped' (plan
--     P-19) is a video or an object gone before its scan: never 'clear'.
--   * public.safety_escalations (spec §4.2): csam_match and scan_failed,
--     read by the named child-safety contact (service role). Also records
--     the vendor and its reference (spec §9: "the escalation records the
--     vendor reference"), whether the evidence was copied to quarantine
--     (plan P-18), and alerted_at for the webhook post (plan P-21). No
--     foreign key on user_id: evidence outlives the account.
--   * storage bucket safety-quarantine: private, no storage.objects policy.
--   * private.media_scan_state: the enqueue path (trigger or sweep, set by
--     20261103140100 and shown by identity health, plan P-16), the sweep's
--     watermark, and how many uploads the enqueue failed to queue.
--   * private.media_scan_buckets(): what is scanned. Never
--     dating-profile-photos (Spec 2 matches those inline, review I-10).
--     Plus the profile-picture bucket 'avatars' (plan P-17).
--   * private.enqueue_media_object(): the one queue writer, used by the
--     trigger and the sweep: only with csam_hash_matching on, only listed
--     buckets, only images and videos; a changed object (an avatar written
--     over in place) is queued again unless it already matched.
--   * private.handle_csam_match(): THE match path, shared by
--     complete_media_scan and record_inline_csam_match: one csam_match
--     escalation per object, a safety_review hold on the uploader
--     (place_account_hold, reason_ref = the escalation id), the original
--     queued for deletion (queue_media_deletion) once it was quarantined.
--     A repeat for the same object returns the same escalation and does
--     nothing else (a reviewer's resolved hold stays resolved). Nothing
--     tells anyone: the uploader learns only H1 at the next token refresh
--     (W6a's hook), the partner nothing.
--   * claim_media_scan_jobs, complete_media_scan, record_inline_csam_match
--     (service role; spec §4.3 W7b), the alert pair for the webhook,
--     expiry (24 h unscanned -> failed + scan_failed), retention (clear and
--     skipped rows after 7 days), identity health, the two crons.
-- Grants in 20261103140010_media_scan_grants.sql.
BEGIN;
SET LOCAL lock_timeout = '5s';

CREATE TABLE IF NOT EXISTS private.media_scan_queue (
  id bigserial PRIMARY KEY,
  bucket text NOT NULL,
  object_name text NOT NULL,
  owner_user_id uuid,
  mime text,
  source text NOT NULL DEFAULT 'queue'
    CONSTRAINT media_scan_queue_source_check CHECK (source IN ('queue', 'inline')),
  status text NOT NULL DEFAULT 'pending'
    CONSTRAINT media_scan_queue_status_check
    CHECK (status IN ('pending', 'scanning', 'clear', 'match', 'failed', 'skipped')),
  attempts int NOT NULL DEFAULT 0,
  next_attempt_at timestamptz NOT NULL DEFAULT now(),
  enqueued_at timestamptz NOT NULL DEFAULT now(),
  scanned_at timestamptz,
  vendor text,
  vendor_ref text,
  CONSTRAINT media_scan_queue_object_key UNIQUE (bucket, object_name)
);
CREATE INDEX IF NOT EXISTS media_scan_queue_due_idx
  ON private.media_scan_queue (next_attempt_at) WHERE status IN ('pending', 'scanning');
CREATE INDEX IF NOT EXISTS media_scan_queue_done_idx
  ON private.media_scan_queue (scanned_at) WHERE status IN ('clear', 'skipped');

CREATE TABLE IF NOT EXISTS public.safety_escalations (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  kind text NOT NULL CONSTRAINT safety_escalations_kind_check CHECK (kind IN ('csam_match', 'scan_failed')),
  user_id uuid,
  bucket text NOT NULL,
  object_name text NOT NULL,
  status text NOT NULL DEFAULT 'open'
    CONSTRAINT safety_escalations_status_check CHECK (status IN ('open', 'reported', 'closed')),
  created_at timestamptz NOT NULL DEFAULT now(),
  notes text,
  vendor text,
  vendor_ref text,
  quarantined boolean,
  alerted_at timestamptz
);
-- One csam_match per object, ever; one open scan_failed per object.
CREATE UNIQUE INDEX IF NOT EXISTS safety_escalations_match_once
  ON public.safety_escalations (bucket, object_name) WHERE kind = 'csam_match';
CREATE UNIQUE INDEX IF NOT EXISTS safety_escalations_failed_open
  ON public.safety_escalations (bucket, object_name) WHERE kind = 'scan_failed' AND status = 'open';
CREATE INDEX IF NOT EXISTS safety_escalations_unalerted_idx
  ON public.safety_escalations (created_at) WHERE alerted_at IS NULL;
ALTER TABLE public.safety_escalations ENABLE ROW LEVEL SECURITY;

INSERT INTO storage.buckets (id, name, public)
VALUES ('safety-quarantine', 'safety-quarantine', false)
ON CONFLICT (id) DO NOTHING;

CREATE TABLE IF NOT EXISTS private.media_scan_state (
  id boolean PRIMARY KEY DEFAULT true CONSTRAINT media_scan_state_one_row CHECK (id),
  enqueue_path text CONSTRAINT media_scan_state_path_check CHECK (enqueue_path IN ('trigger', 'sweep')),
  path_recorded_at timestamptz,
  sweep_watermark timestamptz,
  enqueue_failures bigint NOT NULL DEFAULT 0,
  last_enqueue_failure_at timestamptz
);
INSERT INTO private.media_scan_state (id) VALUES (true) ON CONFLICT (id) DO NOTHING;

CREATE OR REPLACE FUNCTION private.media_scan_buckets()
RETURNS text[]
LANGUAGE sql
IMMUTABLE
SET search_path = ''
AS $$
  SELECT ARRAY['message-media', 'story-media', 'relationship-avatars', 'journal-media',
               'planning-media', 'avatars']::text[];
$$;

-- The one queue writer (trigger and sweep). [p_changed_at] is when the
-- object's bytes last changed: an existing row is queued again only when
-- it was queued before that, and never once it matched.
CREATE OR REPLACE FUNCTION private.enqueue_media_object(
  p_bucket text, p_object_name text, p_owner uuid, p_mime text, p_changed_at timestamptz)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF p_bucket IS NULL OR p_object_name IS NULL
     OR NOT (p_bucket = ANY (private.media_scan_buckets()))
     OR coalesce(p_mime, '') !~* '^(image|video)/'
     OR NOT private.spec1_flag_on('csam_hash_matching') THEN
    RETURN;
  END IF;
  INSERT INTO private.media_scan_queue AS q (bucket, object_name, owner_user_id, mime)
  VALUES (p_bucket, p_object_name, p_owner, lower(p_mime))
  ON CONFLICT (bucket, object_name) DO UPDATE
    SET status = 'pending', attempts = 0, next_attempt_at = now(), enqueued_at = now(),
        scanned_at = NULL, vendor = NULL, vendor_ref = NULL,
        owner_user_id = EXCLUDED.owner_user_id, mime = EXCLUDED.mime
    WHERE q.status <> 'match' AND q.enqueued_at < p_changed_at;
END;
$$;

-- THE match path (review I-10). The caller has already copied the object
-- to safety-quarantine when [p_quarantined]; otherwise the original is the
-- only copy of the evidence and is NOT queued for deletion (plan P-18).
CREATE OR REPLACE FUNCTION private.handle_csam_match(
  p_bucket text, p_object_name text, p_owner uuid, p_vendor text, p_vendor_ref text,
  p_quarantined boolean DEFAULT true)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_id bigint;
BEGIN
  IF p_bucket IS NULL OR p_object_name IS NULL THEN
    RAISE EXCEPTION 'media_scan:invalid_object';
  END IF;
  -- One escalation per object, under one lock, so the queue and an inline
  -- pipeline racing on the same object still make one.
  PERFORM pg_advisory_xact_lock(hashtextextended('csam-match:' || p_bucket || '/' || p_object_name, 0));
  SELECT e.id INTO v_id FROM public.safety_escalations AS e
   WHERE e.kind = 'csam_match' AND e.bucket = p_bucket AND e.object_name = p_object_name;
  IF v_id IS NOT NULL THEN
    RETURN v_id;
  END IF;

  INSERT INTO public.safety_escalations
    (kind, user_id, bucket, object_name, vendor, vendor_ref, quarantined, notes)
  VALUES ('csam_match', p_owner, p_bucket, p_object_name, p_vendor, p_vendor_ref,
          coalesce(p_quarantined, false),
          CASE WHEN coalesce(p_quarantined, false)
               THEN 'Copied to safety-quarantine; the original is queued for deletion. A person reviews before any report.'
               ELSE 'Quarantine copy FAILED: the original is still in place and is the evidence. Copy it to safety-quarantine by hand, then queue its deletion. A person reviews before any report.'
          END)
  RETURNING id INTO v_id;

  -- The uploader's account is held (reversible; W6a's hook refuses its
  -- tokens). An object with no owner, or an owner with no account row, is
  -- escalated without a hold.
  IF p_owner IS NOT NULL AND EXISTS (SELECT 1 FROM public.users AS u WHERE u.id = p_owner) THEN
    PERFORM public.place_account_hold(p_owner, 'safety_review', 'safety_escalation:' || v_id);
  END IF;

  IF coalesce(p_quarantined, false) THEN
    PERFORM public.queue_media_deletion(p_bucket, p_object_name);
  END IF;
  RETURN v_id;
END;
$$;

-- Due jobs, oldest first: pending and due, or scanning with a lapsed lease
-- (a scan-media run that died). Each claim adds an attempt and a 10-minute
-- lease. Nothing while csam_hash_matching is off.
CREATE OR REPLACE FUNCTION public.claim_media_scan_jobs(p_limit int)
RETURNS TABLE (id bigint, bucket text, object_name text, owner_user_id uuid, mime text, attempts int)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF NOT private.spec1_flag_on('csam_hash_matching') THEN
    RETURN;
  END IF;
  PERFORM private.expire_media_scan_jobs();
  RETURN QUERY
  WITH due AS (
    SELECT q.id FROM private.media_scan_queue AS q
     WHERE q.status IN ('pending', 'scanning') AND q.next_attempt_at <= now()
     ORDER BY q.next_attempt_at, q.id
     LIMIT least(greatest(coalesce(p_limit, 1), 1), 50)
     FOR UPDATE SKIP LOCKED
  )
  UPDATE private.media_scan_queue AS q
     SET status = 'scanning', attempts = q.attempts + 1, next_attempt_at = now() + interval '10 minutes'
    FROM due
   WHERE q.id = due.id
  RETURNING q.id, q.bucket, q.object_name, q.owner_user_id, q.mime, q.attempts;
END;
$$;

-- 24 hours without a result: failed, and a person is told (scan_failed).
CREATE OR REPLACE FUNCTION private.expire_media_scan_jobs()
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_job record;
  v_count int := 0;
BEGIN
  FOR v_job IN
    UPDATE private.media_scan_queue AS q
       SET status = 'failed', scanned_at = now()
     WHERE q.status IN ('pending', 'scanning') AND q.enqueued_at < now() - interval '24 hours'
    RETURNING q.bucket, q.object_name, q.owner_user_id, q.vendor, q.vendor_ref
  LOOP
    INSERT INTO public.safety_escalations (kind, user_id, bucket, object_name, vendor, vendor_ref, notes)
    VALUES ('scan_failed', v_job.owner_user_id, v_job.bucket, v_job.object_name, v_job.vendor, v_job.vendor_ref,
            'Not scanned within 24 hours. Check the matcher (CSAM_MATCHER, its keys) and scan-media''s logs, then scan it by hand.')
    ON CONFLICT DO NOTHING;
    v_count := v_count + 1;
  END LOOP;
  RETURN v_count;
END;
$$;

CREATE OR REPLACE FUNCTION public.complete_media_scan(
  p_job_id bigint, p_result text, p_vendor text, p_vendor_ref text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_job private.media_scan_queue%ROWTYPE;
BEGIN
  IF p_result IS NULL OR p_result NOT IN ('clear', 'match', 'match_unquarantined', 'unavailable', 'skipped') THEN
    RAISE EXCEPTION 'media_scan:invalid_result';
  END IF;
  SELECT * INTO v_job FROM private.media_scan_queue AS q WHERE q.id = p_job_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'media_scan:no_job';
  END IF;

  -- A match is never dropped, whatever the row's state (plan P-20).
  IF p_result IN ('match', 'match_unquarantined') THEN
    UPDATE private.media_scan_queue AS q
       SET status = 'match', scanned_at = now(), vendor = p_vendor, vendor_ref = p_vendor_ref
     WHERE q.id = p_job_id;
    PERFORM private.handle_csam_match(v_job.bucket, v_job.object_name, v_job.owner_user_id,
                                      p_vendor, p_vendor_ref, p_result = 'match');
    RETURN;
  END IF;

  -- Anything else only answers the claim it belongs to.
  IF v_job.status <> 'scanning' THEN
    RETURN;
  END IF;
  IF p_result IN ('clear', 'skipped') THEN
    UPDATE private.media_scan_queue AS q
       SET status = p_result, scanned_at = now(), vendor = p_vendor, vendor_ref = p_vendor_ref
     WHERE q.id = p_job_id;
    RETURN;
  END IF;

  -- unavailable: back off 1, 5, 15, 60 minutes, then hourly; 24 hours
  -- after it was queued, failed and escalated.
  IF v_job.enqueued_at < now() - interval '24 hours' THEN
    UPDATE private.media_scan_queue AS q
       SET status = 'failed', scanned_at = now(), vendor = p_vendor, vendor_ref = p_vendor_ref
     WHERE q.id = p_job_id;
    INSERT INTO public.safety_escalations (kind, user_id, bucket, object_name, vendor, vendor_ref, notes)
    VALUES ('scan_failed', v_job.owner_user_id, v_job.bucket, v_job.object_name, p_vendor, p_vendor_ref,
            'Not scanned within 24 hours. Check the matcher (CSAM_MATCHER, its keys) and scan-media''s logs, then scan it by hand.')
    ON CONFLICT DO NOTHING;
    RETURN;
  END IF;
  UPDATE private.media_scan_queue AS q
     SET status = 'pending', vendor = p_vendor, vendor_ref = p_vendor_ref,
         next_attempt_at = now() + CASE
           WHEN v_job.attempts <= 1 THEN interval '1 minute'
           WHEN v_job.attempts = 2 THEN interval '5 minutes'
           WHEN v_job.attempts = 3 THEN interval '15 minutes'
           ELSE interval '60 minutes' END
   WHERE q.id = p_job_id;
END;
$$;

-- For synchronous pipelines (Spec 2's process-dating-photo): the same
-- path as a queued match. Idempotent per object.
CREATE OR REPLACE FUNCTION public.record_inline_csam_match(
  p_bucket text, p_object_name text, p_owner uuid, p_vendor text, p_vendor_ref text,
  p_quarantined boolean DEFAULT true)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF p_bucket IS NULL OR p_object_name IS NULL THEN
    RAISE EXCEPTION 'media_scan:invalid_object';
  END IF;
  INSERT INTO private.media_scan_queue AS q
    (bucket, object_name, owner_user_id, source, status, scanned_at, vendor, vendor_ref)
  VALUES (p_bucket, p_object_name, p_owner, 'inline', 'match', now(), p_vendor, p_vendor_ref)
  ON CONFLICT (bucket, object_name) DO UPDATE
    SET status = 'match', scanned_at = coalesce(q.scanned_at, now()),
        vendor = coalesce(q.vendor, EXCLUDED.vendor), vendor_ref = coalesce(q.vendor_ref, EXCLUDED.vendor_ref);
  RETURN private.handle_csam_match(p_bucket, p_object_name, p_owner, p_vendor, p_vendor_ref,
                                   coalesce(p_quarantined, false));
END;
$$;

-- The webhook's two sources (identity-health-alert every 15 minutes, and
-- scan-media straight after a run that escalated): ids, a count and times.
CREATE OR REPLACE FUNCTION private.safety_escalations_due(p_kind text)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT jsonb_build_object(
    'ids', coalesce(jsonb_agg(e.id ORDER BY e.created_at, e.id), '[]'::jsonb),
    'count', count(*),
    'first_at', min(e.created_at),
    'last_at', max(e.created_at))
    FROM (SELECT x.id, x.created_at FROM public.safety_escalations AS x
           WHERE x.kind = p_kind AND x.alerted_at IS NULL
           ORDER BY x.created_at, x.id LIMIT 500) AS e;
$$;

CREATE OR REPLACE FUNCTION public.csam_escalations_due()
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT private.safety_escalations_due('csam_match');
$$;

CREATE OR REPLACE FUNCTION public.scan_failed_escalations_due()
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT private.safety_escalations_due('scan_failed');
$$;

CREATE OR REPLACE FUNCTION public.mark_safety_escalations_alerted(p_ids bigint[])
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = ''
AS $$
  UPDATE public.safety_escalations AS e
     SET alerted_at = now()
   WHERE e.id = ANY (coalesce(p_ids, ARRAY[]::bigint[])) AND e.alerted_at IS NULL;
$$;

-- media-scan-retention (spec §4.6, §4.8): clear and skipped rows after 7
-- days; matches and failures stay with their escalation. Also expires any
-- job left 24 hours (so a dead scan-media cron still reaches a person).
CREATE OR REPLACE FUNCTION private.media_scan_retention()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  PERFORM private.expire_media_scan_jobs();
  DELETE FROM private.media_scan_queue AS q
   WHERE q.status IN ('clear', 'skipped') AND q.scanned_at < now() - interval '7 days';
END;
$$;

-- Identity health (plan P-22): W7b's lines live here, so get_identity_health
-- names no W7 table itself (the W6 split, dormancy contract F).
CREATE OR REPLACE FUNCTION private.identity_health_w7b()
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT jsonb_build_object(
    'media_scan_enqueue_path', (SELECT s.enqueue_path FROM private.media_scan_state AS s),
    'media_scan_enqueue_failures', coalesce((SELECT s.enqueue_failures FROM private.media_scan_state AS s), 0),
    'media_scan_pending', (SELECT count(*) FROM private.media_scan_queue AS q
                            WHERE q.status IN ('pending', 'scanning')),
    'media_scan_oldest_pending_minutes', (
      SELECT coalesce(floor(extract(epoch FROM now() - min(q.enqueued_at)) / 60)::int, 0)
        FROM private.media_scan_queue AS q WHERE q.status IN ('pending', 'scanning')),
    'media_scan_skipped_7d', (SELECT count(*) FROM private.media_scan_queue AS q
                               WHERE q.status = 'skipped' AND q.scanned_at > now() - interval '7 days'),
    'safety_escalations_open', (SELECT count(*) FROM public.safety_escalations AS e WHERE e.status = 'open'),
    'safety_escalations_unalerted', (SELECT count(*) FROM public.safety_escalations AS e
                                      WHERE e.alerted_at IS NULL
                                        AND e.created_at < now() - interval '15 minutes'));
$$;

-- get_identity_health re-created from its live body
-- (20261103100200_fresh_start.sql), with one addition: || identity_health_w7b().
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
    'unfinished_signups_awaiting_purge', (SELECT count(*) FROM private.unfinished_signups AS s))
    || private.identity_health_w6a()
    || private.identity_health_w7b();
$$;

-- Server-only objects revoked here as well as in the twin.
REVOKE ALL ON private.media_scan_queue FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON SEQUENCE private.media_scan_queue_id_seq FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON private.media_scan_state FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON public.safety_escalations FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.media_scan_buckets() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.enqueue_media_object(text, text, uuid, text, timestamptz) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.handle_csam_match(text, text, uuid, text, text, boolean) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.expire_media_scan_jobs() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.safety_escalations_due(text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.media_scan_retention() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.identity_health_w7b() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.claim_media_scan_jobs(int) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.complete_media_scan(bigint, text, text, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.record_inline_csam_match(text, text, uuid, text, text, boolean) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.csam_escalations_due() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.scan_failed_escalations_due() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.mark_safety_escalations_alerted(bigint[]) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.get_identity_health() FROM PUBLIC, anon, authenticated;

DO $$
BEGIN
  PERFORM cron.unschedule(jobid) FROM cron.job WHERE jobname IN ('scan-media', 'media-scan-retention');
END;
$$;
SELECT cron.schedule('scan-media', '* * * * *', $cron$SELECT public.invoke_edge_function('scan-media')$cron$);
SELECT cron.schedule('media-scan-retention', '27 4 * * *', $cron$SELECT private.media_scan_retention()$cron$);

COMMIT;
```

Create `supabase/migrations/20261103140010_media_scan_grants.sql` with exactly:

```sql
-- Spec 1 W7b: grants for 20261103140000_media_scan.sql. scan-media and
-- Spec 2's process-dating-photo (service role) work through the functions;
-- the named child-safety contact works safety_escalations (service role,
-- SQL editor; the house rule gives the service role DML on a new public
-- table). No client reaches any of it.
BEGIN;
SET LOCAL lock_timeout = '5s';
REVOKE ALL ON private.media_scan_queue FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON SEQUENCE private.media_scan_queue_id_seq FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON private.media_scan_state FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON public.safety_escalations FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.safety_escalations TO service_role;
REVOKE ALL ON FUNCTION private.media_scan_buckets() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.enqueue_media_object(text, text, uuid, text, timestamptz) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.handle_csam_match(text, text, uuid, text, text, boolean) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.expire_media_scan_jobs() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.safety_escalations_due(text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.media_scan_retention() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.identity_health_w7b() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.claim_media_scan_jobs(int) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.complete_media_scan(bigint, text, text, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.record_inline_csam_match(text, text, uuid, text, text, boolean) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.csam_escalations_due() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.scan_failed_escalations_due() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.mark_safety_escalations_alerted(bigint[]) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.get_identity_health() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.claim_media_scan_jobs(int) TO service_role;
GRANT EXECUTE ON FUNCTION public.complete_media_scan(bigint, text, text, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.record_inline_csam_match(text, text, uuid, text, text, boolean) TO service_role;
GRANT EXECUTE ON FUNCTION public.csam_escalations_due() TO service_role;
GRANT EXECUTE ON FUNCTION public.scan_failed_escalations_due() TO service_role;
GRANT EXECUTE ON FUNCTION public.mark_safety_escalations_alerted(bigint[]) TO service_role;
GRANT EXECUTE ON FUNCTION public.get_identity_health() TO service_role;
COMMIT;
```

- [ ] **Step 4: Write migration 15b and its twin**

Create `supabase/migrations/20261103140100_media_scan_enqueue.sql` with exactly:

```sql
-- Spec 1 W7b, migration 15b (spec §4.4 enqueue_media_scan, review F-1;
-- plan P-15, P-16): how a new upload reaches the queue.
--   * private.enqueue_media_scan(): AFTER INSERT OR UPDATE OF metadata ON
--     storage.objects. An insert, or an update that changed the bytes (the
--     eTag or the mime type; a picture written over in place, plan P-17),
--     is passed to private.enqueue_media_object, which applies the flag,
--     the buckets and the mime rule. Inside an exception block: a failure
--     is counted in private.media_scan_state and NEVER blocks the upload.
--   * private.enqueue_new_storage_objects(): the F-1 fallback, a one-minute
--     sweep of objects created or changed since the last sweep (2-minute
--     overlap, ON CONFLICT in the writer). It moves the watermark even
--     while the flag is off, so turning the flag on doesn't queue the past
--     (the same as the trigger).
--   * private.install_media_scan_enqueue(p_force_sweep): the F-1 spike,
--     done by the migration itself (the development project can't be
--     touched first, plan P-16): keep the trigger if it is there, else try
--     to create it; on
--     insufficient_privilege (hosted Supabase may not let postgres put a
--     trigger on storage.objects) schedule the sweep instead. Either way
--     it records the path in private.media_scan_state (identity health's
--     media_scan_enqueue_path) and raises a NOTICE that db push prints.
--     SECURITY INVOKER: it must run with the migration's own rights.
-- Grants in 20261103140110_media_scan_enqueue_grants.sql (none: nothing
-- here is granted to anyone).
BEGIN;
SET LOCAL lock_timeout = '5s';

CREATE OR REPLACE FUNCTION private.enqueue_media_scan()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_row jsonb;
  v_owner text;
BEGIN
  BEGIN
    IF TG_OP = 'UPDATE'
       AND (OLD.metadata ->> 'eTag') IS NOT DISTINCT FROM (NEW.metadata ->> 'eTag')
       AND (OLD.metadata ->> 'mimetype') IS NOT DISTINCT FROM (NEW.metadata ->> 'mimetype') THEN
      RETURN NULL;
    END IF;
    -- owner (uuid) on today's storage schema, owner_id (text) on newer
    -- ones: read by name so either schema works.
    v_row := to_jsonb(NEW);
    v_owner := coalesce(v_row ->> 'owner', v_row ->> 'owner_id');
    PERFORM private.enqueue_media_object(
      NEW.bucket_id,
      NEW.name,
      CASE WHEN v_owner ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
           THEN v_owner::uuid END,
      coalesce(NEW.metadata ->> 'mimetype', NEW.metadata ->> 'contentType'),
      now());
  EXCEPTION WHEN OTHERS THEN
    BEGIN
      UPDATE private.media_scan_state
         SET enqueue_failures = enqueue_failures + 1, last_enqueue_failure_at = now();
    EXCEPTION WHEN OTHERS THEN
      NULL;
    END;
  END;
  RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION private.enqueue_new_storage_objects()
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_now constant timestamptz := clock_timestamp();
  v_from timestamptz;
  v_object record;
  v_count int := 0;
BEGIN
  SELECT s.sweep_watermark INTO v_from FROM private.media_scan_state AS s FOR UPDATE;
  v_from := coalesce(v_from, v_now) - interval '2 minutes';
  IF private.spec1_flag_on('csam_hash_matching') THEN
    FOR v_object IN
      SELECT o.bucket_id, o.name, o.metadata, x.changed_at,
             coalesce(to_jsonb(o) ->> 'owner', to_jsonb(o) ->> 'owner_id') AS owner_text
        FROM storage.objects AS o
        CROSS JOIN LATERAL (
          SELECT greatest(o.created_at, coalesce((to_jsonb(o) ->> 'updated_at')::timestamptz, o.created_at))
                 AS changed_at) AS x
       WHERE o.bucket_id = ANY (private.media_scan_buckets())
         AND x.changed_at > v_from
    LOOP
      BEGIN
        PERFORM private.enqueue_media_object(
          v_object.bucket_id,
          v_object.name,
          CASE WHEN v_object.owner_text ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
               THEN v_object.owner_text::uuid END,
          coalesce(v_object.metadata ->> 'mimetype', v_object.metadata ->> 'contentType'),
          v_object.changed_at);
        v_count := v_count + 1;
      EXCEPTION WHEN OTHERS THEN
        UPDATE private.media_scan_state
           SET enqueue_failures = enqueue_failures + 1, last_enqueue_failure_at = now();
      END;
    END LOOP;
  END IF;
  UPDATE private.media_scan_state SET sweep_watermark = v_now;
  RETURN v_count;
END;
$$;

CREATE OR REPLACE FUNCTION private.install_media_scan_enqueue(p_force_sweep boolean DEFAULT false)
RETURNS text
LANGUAGE plpgsql
SET search_path = ''
AS $$
DECLARE
  v_path text := 'sweep';
BEGIN
  IF NOT p_force_sweep THEN
    -- Creating a trigger needs the TRIGGER right on storage.objects;
    -- dropping one needs ownership, so an existing trigger is kept as it
    -- is (its function was just replaced above).
    IF EXISTS (SELECT 1 FROM pg_catalog.pg_trigger AS t
                WHERE t.tgrelid = 'storage.objects'::regclass AND t.tgname = 'enqueue_media_scan') THEN
      v_path := 'trigger';
    ELSE
      BEGIN
        CREATE TRIGGER enqueue_media_scan
          AFTER INSERT OR UPDATE OF metadata ON storage.objects
          FOR EACH ROW EXECUTE FUNCTION private.enqueue_media_scan();
        v_path := 'trigger';
      EXCEPTION WHEN insufficient_privilege THEN
        v_path := 'sweep';
      END;
    END IF;
  ELSE
    BEGIN
      DROP TRIGGER IF EXISTS enqueue_media_scan ON storage.objects;
    EXCEPTION WHEN insufficient_privilege THEN
      NULL;
    END;
  END IF;

  PERFORM cron.unschedule(j.jobid) FROM cron.job AS j WHERE j.jobname = 'enqueue-new-storage-objects';
  IF v_path = 'sweep' THEN
    PERFORM cron.schedule('enqueue-new-storage-objects', '* * * * *',
                          'SELECT private.enqueue_new_storage_objects()');
  END IF;

  UPDATE private.media_scan_state AS s
     SET enqueue_path = v_path,
         path_recorded_at = now(),
         sweep_watermark = coalesce(s.sweep_watermark, now());
  RAISE NOTICE 'media_scan: new uploads reach the scan queue by %',
    CASE v_path WHEN 'trigger' THEN 'the storage.objects trigger (enqueue_media_scan)'
                ELSE 'the one-minute sweep (cron enqueue-new-storage-objects)' END;
  RETURN v_path;
END;
$$;

REVOKE ALL ON FUNCTION private.enqueue_media_scan() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.enqueue_new_storage_objects() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.install_media_scan_enqueue(boolean) FROM PUBLIC, anon, authenticated, service_role;

SELECT private.install_media_scan_enqueue();

COMMIT;
```

Create `supabase/migrations/20261103140110_media_scan_enqueue_grants.sql` with exactly:

```sql
-- Spec 1 W7b: grants for 20261103140100_media_scan_enqueue.sql. The
-- trigger function, the sweep and the install are the database's own:
-- nothing is granted to anyone.
BEGIN;
SET LOCAL lock_timeout = '5s';
REVOKE ALL ON FUNCTION private.enqueue_media_scan() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.enqueue_new_storage_objects() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.install_media_scan_enqueue(boolean) FROM PUBLIC, anon, authenticated, service_role;
COMMIT;
```

- [ ] **Step 5: Apply each file twice; check `get_identity_health`'s diff; run the contract**

```bash
for i in 1 2; do
  for f in 20261103140000_media_scan 20261103140010_media_scan_grants 20261103140100_media_scan_enqueue 20261103140110_media_scan_enqueue_grants; do
    psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/migrations/$f.sql > /dev/null 2>&1; echo "$f exit=$?"
  done
done
diff <(awk '/CREATE OR REPLACE FUNCTION public.get_identity_health/,/^\$\$;/' supabase/migrations/20261103100200_fresh_start.sql) \
     <(awk '/CREATE OR REPLACE FUNCTION public.get_identity_health/,/^\$\$;/' supabase/migrations/20261103140000_media_scan.sql)
psql -X -d attune_spec3a -Atc "select enqueue_path from private.media_scan_state"
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/media_scan_contracts.sql 2>&1 | tail -1 | sed -E 's/^psql:[^ ]* //'
```

Expected: eight `exit=0` lines; the diff is exactly

```
21c21,22
<     || private.identity_health_w6a();
---
>     || private.identity_health_w6a()
>     || private.identity_health_w7b();
```

`trigger` (locally `storage.objects` belongs to the bootstrap's owner, so the install creates the trigger); `NOTICE:  media_scan_contracts: all held`.

- [ ] **Step 6: The same contract on the sweep path (what a hosted project without the trigger right gets)**

```bash
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -c 'BEGIN' -c 'SELECT private.install_media_scan_enqueue(true)' \
  -f supabase/tests/media_scan_contracts.sql 2>&1 | grep -E 'ERROR|all held' | sed -E 's/^psql:[^ ]* //'
psql -X -d attune_spec3a -Atc "select enqueue_path from private.media_scan_state; select count(*) from cron.job where jobname = 'enqueue-new-storage-objects'"
```

Expected: `NOTICE:  media_scan_contracts: all held` (sections B-D ran through the sweep; E put the trigger back inside the rolled-back transaction); then `trigger` and `0` (nothing kept).

- [ ] **Step 7: Mutation checks (each must turn the contract red with the message quoted)**

```bash
M=supabase/migrations/20261103140000_media_scan.sql
G=supabase/migrations/20261103140010_media_scan_grants.sql
E=supabase/migrations/20261103140100_media_scan_enqueue.sql
EG=supabase/migrations/20261103140110_media_scan_enqueue_grants.sql
C=supabase/tests/media_scan_contracts.sql
D=.superpowers/sdd/2026-11-03-spec1-w7
python3 -I - "$M" "$E" "$D" <<'PY'
import pathlib, sys
m = pathlib.Path(sys.argv[1]).read_text()
e = pathlib.Path(sys.argv[2]).read_text()
d = pathlib.Path(sys.argv[3])
def body(text, start):
    i = text.index(start)
    return text[i:text.index('\n$$;\n', i) + 5]
H = "CREATE OR REPLACE FUNCTION private.handle_csam_match("
CMS = "CREATE OR REPLACE FUNCTION public.complete_media_scan("
muts = {
  # spec §7.4: re-add dating-profile-photos to the scan trigger's buckets (I-10)
  'dating_bucket': (m, "CREATE OR REPLACE FUNCTION private.media_scan_buckets()",
                    "'planning-media', 'avatars']::text[];", "'planning-media', 'avatars', 'dating-profile-photos']::text[];"),
  'flag_ignored': (m, "CREATE OR REPLACE FUNCTION private.enqueue_media_object(",
                   "     OR coalesce(p_mime, '') !~* '^(image|video)/'\n     OR NOT private.spec1_flag_on('csam_hash_matching') THEN",
                   "     OR coalesce(p_mime, '') !~* '^(image|video)/' THEN"),
  'repeat_not_idempotent': (m, H, "  IF v_id IS NOT NULL THEN\n    RETURN v_id;\n  END IF;\n", ""),
  'no_hold': (m, H, "    PERFORM public.place_account_hold(p_owner, 'safety_review', 'safety_escalation:' || v_id);", "    NULL;"),
  'delete_unquarantined': (m, H, "  IF coalesce(p_quarantined, false) THEN\n    PERFORM public.queue_media_deletion",
                           "  IF true THEN\n    PERFORM public.queue_media_deletion"),
  'tells_someone': (m, H, "  RETURN v_id;\nEND;\n$$;",
                    "  PERFORM 1 FROM public.relationships LIMIT 1; -- enqueue a notification\n  RETURN v_id;\nEND;\n$$;"),
  'inline_own_path': (m, "CREATE OR REPLACE FUNCTION public.record_inline_csam_match(",
                      "  RETURN private.handle_csam_match(p_bucket, p_object_name, p_owner, p_vendor, p_vendor_ref,\n                                   coalesce(p_quarantined, false));",
                      "  INSERT INTO public.safety_escalations (kind, user_id, bucket, object_name)\n  VALUES ('csam_match', p_owner, p_bucket, p_object_name) ON CONFLICT DO NOTHING;\n  RETURN 0;"),
  'match_dropped': (m, CMS, "  -- A match is never dropped, whatever the row's state (plan P-20).\n  IF p_result IN",
                    "  IF v_job.status <> 'scanning' THEN RETURN; END IF;\n  IF p_result IN"),
  'stale_clear': (m, CMS, "  IF v_job.status <> 'scanning' THEN\n    RETURN;\n  END IF;\n  IF p_result IN ('clear', 'skipped') THEN",
                  "  IF p_result IN ('clear', 'skipped') THEN"),
  'backoff_10': (m, CMS, "WHEN v_job.attempts = 2 THEN interval '5 minutes'", "WHEN v_job.attempts = 2 THEN interval '10 minutes'"),
  'claim_flag_off': (m, "CREATE OR REPLACE FUNCTION public.claim_media_scan_jobs(",
                     "  IF NOT private.spec1_flag_on('csam_hash_matching') THEN\n    RETURN;\n  END IF;\n", ""),
  'retention_all': (m, "CREATE OR REPLACE FUNCTION private.media_scan_retention(",
                    "   WHERE q.status IN ('clear', 'skipped') AND q.scanned_at < now() - interval '7 days';",
                    "   WHERE q.scanned_at < now() - interval '7 days';"),
  # spec §7.4: drop the exception guard in enqueue_media_scan
  'no_guard': (e, "CREATE OR REPLACE FUNCTION private.enqueue_media_scan()",
               "  EXCEPTION WHEN OTHERS THEN\n    BEGIN\n      UPDATE private.media_scan_state\n         SET enqueue_failures = enqueue_failures + 1, last_enqueue_failure_at = now();\n    EXCEPTION WHEN OTHERS THEN\n      NULL;\n    END;\n  END;\n",
               "  END;\n"),
  'sweep_everything': (e, "CREATE OR REPLACE FUNCTION private.enqueue_new_storage_objects()", "         AND x.changed_at > v_from\n", ""),
  'no_fallback': (e, "CREATE OR REPLACE FUNCTION private.install_media_scan_enqueue(",
                  "      EXCEPTION WHEN insufficient_privilege THEN\n        v_path := 'sweep';\n      END;\n", "      END;\n"),
}
for name, (src, start, a, b) in muts.items():
    fn = body(src, start)
    assert fn.count(a) == 1, name
    (d / f"mut_{name}.sql").write_text(fn.replace(a, b))
(d / 'mut_client_queue.sql').write_text("GRANT SELECT ON private.media_scan_queue TO authenticated;\n")
(d / 'mut_client_inline.sql').write_text(
    "GRANT EXECUTE ON FUNCTION public.record_inline_csam_match(text,text,uuid,text,text,boolean) TO authenticated;\n")
print('mutants written')
PY
for m in dating_bucket flag_ignored repeat_not_idempotent no_hold delete_unquarantined tells_someone inline_own_path match_dropped stale_clear backoff_10 claim_flag_off retention_all no_guard sweep_everything no_fallback client_queue client_inline; do
  psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f $D/mut_$m.sql > /dev/null 2>&1
  echo "$m: $(psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f $C 2>&1 | grep ERROR | sed -E 's/^psql:[^ ]* //' | cut -c1-130)"
  psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f $M -f $G -f $E -f $EG > /dev/null 2>&1
done
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f $C 2>&1 | tail -1
rm $D/mut_*.sql
```

Expected: `mutants written`, then:
- `dating_bucket` (spec §7.4): `ERROR:  CONTRACT VIOLATED: a dating-profile-photos object was queued (Spec 2 matches it inline, review I-10)`
- `flag_ignored`: `ERROR:  CONTRACT VIOLATED: an upload was queued with csam_hash_matching off`
- `repeat_not_idempotent`: `ERROR:  CONTRACT VIOLATED: a repeated queued match was refused`
- `no_hold`: `ERROR:  CONTRACT VIOLATED: a queued match did not hold the uploader and queue the original's deletion`
- `delete_unquarantined`: `ERROR:  CONTRACT VIOLATED: a match without a quarantine copy queued the evidence for deletion`
- `tells_someone`: `ERROR:  CONTRACT VIOLATED: the match path reaches beyond the hold, the escalation and the deletion (nothing may tell anyone)`
- `inline_own_path`: `ERROR:  CONTRACT VIOLATED: a match entry point does not use private.handle_csam_match (review I-10)`
- `match_dropped`: `ERROR:  CONTRACT VIOLATED: a match for a job that was not scanning was dropped`
- `stale_clear`: `ERROR:  CONTRACT VIOLATED: a stale clear (the job was queued again) was recorded`
- `backoff_10`: `ERROR:  CONTRACT VIOLATED: attempt 2 did not back off as §4.3 says`
- `claim_flag_off`: `ERROR:  CONTRACT VIOLATED: jobs were claimed with csam_hash_matching off`
- `retention_all`: `ERROR:  CONTRACT VIOLATED: retention removed a match or a failure, or kept a clear row`
- `no_guard` (spec §7.4): `ERROR:  CONTRACT VIOLATED: a failing queue insert blocked the upload (new row for relation "media_scan_queue" violates check const…`
- `sweep_everything`: `ERROR:  CONTRACT VIOLATED: the sweep queued an old, a dating or a non-image object`
- `no_fallback`: `ERROR:  CONTRACT VIOLATED: without the trigger right the install did not fall back to the recorded sweep (got refused: permission …`
- `client_queue`: `ERROR:  CONTRACT VIOLATED: table grants are wrong (no client; the service role works the escalations; the queue is function-only):…`
- `client_inline`: `ERROR:  CONTRACT VIOLATED: a W7b service function has the wrong grants: public.record_inline_csam_match(text,text,uuid,text,text,b…`

then `NOTICE:  media_scan_contracts: all held`.

- [ ] **Step 8: The local harness (edit only, never run)**

`scripts/local_pg_grants.sql`, edit 1 of 1 (after Task 1's). Replace exactly:

```sql
\i supabase/migrations/20261103130010_support_resources_v2_grants.sql
```

with:

```sql
\i supabase/migrations/20261103130010_support_resources_v2_grants.sql

-- Spec 1 W7b: image safety is the service role's (scan-media, Spec 2's
-- inline pipeline) and the database's own (the enqueue); no client.
\i supabase/migrations/20261103140010_media_scan_grants.sql
\i supabase/migrations/20261103140110_media_scan_enqueue_grants.sql
```

- [ ] **Step 9: Run tests**

```bash
for f in supabase/tests/*.sql; do
  if psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f "$f" >/dev/null 2>&1; then echo "PASS $(basename "$f")"; else echo "FAIL $(basename "$f")"; fi
done > .superpowers/sdd/2026-11-03-spec1-w7/sql-after-task5.txt
grep '^FAIL' .superpowers/sdd/2026-11-03-spec1-w7/sql-after-task5.txt | comm -13 <(grep '^FAIL' .superpowers/sdd/2026-11-03-spec1-w7/sql-baseline.txt) -
grep -E 'media_scan|support_resources|identity_foundation|dormancy|child_safety|account_deletion' .superpowers/sdd/2026-11-03-spec1-w7/sql-after-task5.txt
grep -c PASS .superpowers/sdd/2026-11-03-spec1-w7/sql-after-task5.txt
```

Expected: no new FAIL line; `PASS` for all six named files; the Task 1 count plus 2.

### Task 6: The matcher seam: PhotoDNA, Safer and the stub (§2.5 production mode, §4.5; P-23, P-24)

**Files:**
- Create: `supabase/functions/_shared/csam_matcher.ts`
- Create: `supabase/functions/_shared/csam_matcher.test.ts`

**Interfaces:**
- Consumes: Web Crypto, `fetch`, `FormData`, `AbortSignal.timeout` (Deno 2).
- Produces: `type MatchOutcome = "clear" | "match" | "unavailable" | "skipped"`, `interface MatchResult { outcome; vendor: string; vendorRef: string | null }`, `interface CsamMatcher { name; supportsVideo; match(bytes: Uint8Array, mime: string): Promise<MatchResult> }`, `type FetchFn`, `type AttuneEnvironment = "development" | "production"`, `interface MatcherConfig { env(name): string | undefined; fetch: FetchFn; environment; timeoutMs? }`, `matcherFromEnv(config): CsamMatcher`, `photoDnaMatcher`, `readPhotoDnaMatch`, `saferMatcher`, `readSaferMatch`, `stubMatcher`, `sha256Hex`, `PHOTODNA_DEFAULT_URL`, `PHOTODNA_TYPES`, `STUB_MATCH_SHA256` (SHA-256 of `attune-csam-stub-match`), `STUB_UNAVAILABLE_SHA256`.

- [ ] **Step 1: Write the failing test**

Create `supabase/functions/_shared/csam_matcher.test.ts` with exactly:

```ts
// Spec 1 W7b (§4.5, §7.2; plan P-23, P-24): the matcher seam, on mocked
// fetch. Nothing a matcher doesn't positively understand is clear; the
// stub is refused in production.
import {
  type FetchFn,
  matcherFromEnv,
  PHOTODNA_DEFAULT_URL,
  photoDnaMatcher,
  readPhotoDnaMatch,
  readSaferMatch,
  saferMatcher,
  STUB_MATCH_SHA256,
  STUB_UNAVAILABLE_SHA256,
  sha256Hex,
  stubMatcher,
} from "./csam_matcher.ts";

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

const enc = new TextEncoder();
const IMAGE = enc.encode("not really a jpeg");

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}

function recorder(answer: () => Response | Promise<Response>) {
  const calls: { url: string; init: RequestInit }[] = [];
  const fetchFn: FetchFn = async (url, init) => {
    calls.push({ url, init });
    return await answer();
  };
  return { calls, fetchFn };
}

const env = (values: Record<string, string>) => (name: string): string | undefined => values[name];

Deno.test("stub: the test hashes match and are unavailable; anything else is clear", async () => {
  assert(STUB_MATCH_SHA256 === await sha256Hex(enc.encode("attune-csam-stub-match")), "match hash");
  assert(STUB_UNAVAILABLE_SHA256 === await sha256Hex(enc.encode("attune-csam-stub-unavailable")), "unavailable hash");
  const stub = stubMatcher();
  assert((await stub.match(enc.encode("attune-csam-stub-match"), "image/png")).outcome === "match", "match");
  assert((await stub.match(enc.encode("attune-csam-stub-unavailable"), "image/png")).outcome === "unavailable", "unavail");
  assert((await stub.match(IMAGE, "image/jpeg")).outcome === "clear", "clear");
  const extra = stubMatcher([` ${(await sha256Hex(IMAGE)).toUpperCase()} `]);
  assert((await extra.match(IMAGE, "image/jpeg")).outcome === "match", "extra hash");
});

Deno.test("stub is refused in production: unavailable for everything, never clear", async () => {
  const { calls, fetchFn } = recorder(() => json({}));
  const m = matcherFromEnv({ env: env({ CSAM_MATCHER: "stub" }), fetch: fetchFn, environment: "production" });
  for (const bytes of [IMAGE, enc.encode("attune-csam-stub-match")]) {
    const r = await m.match(bytes, "image/jpeg");
    assert(r.outcome === "unavailable" && r.vendorRef === "stub_refused_in_production", JSON.stringify(r));
  }
  assert(calls.length === 0, "the stub called out");
  const dev = matcherFromEnv({ env: env({ CSAM_MATCHER: "stub" }), fetch: fetchFn, environment: "development" });
  assert((await dev.match(IMAGE, "image/jpeg")).outcome === "clear", "dev stub");
});

Deno.test("no matcher, an unknown one, or a vendor without its key: unavailable", async () => {
  const { fetchFn } = recorder(() => json({}));
  const configs: Record<string, string>[] = [
    {},
    { CSAM_MATCHER: "magic" },
    { CSAM_MATCHER: "photodna" },
    { CSAM_MATCHER: "safer", SAFER_API_KEY: "k" },
    { CSAM_MATCHER: "safer", SAFER_API_KEY: "k", SAFER_MATCH_URL: "http://plain" },
  ];
  for (const values of configs) {
    const m = matcherFromEnv({ env: env(values), fetch: fetchFn, environment: "development" });
    const r = await m.match(IMAGE, "image/jpeg");
    assert(r.outcome === "unavailable", `${JSON.stringify(values)} -> ${JSON.stringify(r)}`);
  }
});

Deno.test("photodna: the documented request; 3000 answers; anything else unavailable", async () => {
  const ok = recorder(() => json({ Status: { Code: 3000, Description: "OK" }, IsMatch: false, TrackingId: "trk-1" }));
  const m = matcherFromEnv({ env: env({ CSAM_MATCHER: "photodna", PHOTODNA_SUBSCRIPTION_KEY: "k-1" }), fetch: ok.fetchFn, environment: "production" });
  const r = await m.match(IMAGE, "IMAGE/JPEG");
  assert(r.outcome === "clear" && r.vendor === "photodna" && r.vendorRef === "trk-1", JSON.stringify(r));
  const call = ok.calls[0];
  const headers = call.init.headers as Record<string, string>;
  assert(call.url === `${PHOTODNA_DEFAULT_URL}?enhance=false` && call.init.method === "POST", call.url);
  assert(headers["Ocp-Apim-Subscription-Key"] === "k-1" && headers["Content-Type"] === "image/jpeg", JSON.stringify(headers));
  const sent = call.init.body as Uint8Array;
  assert(sent.length === IMAGE.length && sent.every((b, i) => b === IMAGE[i]), "the image bytes are the body");

  assert(readPhotoDnaMatch({ Status: { Code: 3000 }, IsMatch: true, TrackingId: "trk-2" }).outcome === "match", "match");
  for (const body of [{ Status: { Code: 3208 }, IsMatch: false }, { Status: { Code: 3000 } }, { IsMatch: false }, null, "x"]) {
    const read = readPhotoDnaMatch(body);
    assert(read.outcome === "unavailable", `${JSON.stringify(body)} -> ${read.outcome}`);
  }
  const busy = photoDnaMatcher("k", PHOTODNA_DEFAULT_URL, recorder(() => json({}, 429)).fetchFn);
  assert((await busy.match(IMAGE, "image/png")).vendorRef === "http:429", "429");
  const down = photoDnaMatcher("k", PHOTODNA_DEFAULT_URL, () => Promise.reject(new TypeError("dns")));
  assert((await down.match(IMAGE, "image/png")).outcome === "unavailable", "network");
  const webp = photoDnaMatcher("k", PHOTODNA_DEFAULT_URL, ok.fetchFn);
  assert((await webp.match(IMAGE, "image/webp")).vendorRef === "unsupported_type:image/webp", "webp");
});

Deno.test("photodna: a slow answer times out as unavailable", async () => {
  const slow: FetchFn = (_url, init) =>
    new Promise((_resolve, reject) => {
      init.signal?.addEventListener("abort", () => reject(init.signal?.reason));
    });
  const r = await photoDnaMatcher("k", PHOTODNA_DEFAULT_URL, slow, 20).match(IMAGE, "image/jpeg");
  assert(r.outcome === "unavailable" && r.vendorRef === "timeout", JSON.stringify(r));
});

Deno.test("safer: multipart media and the token; matched / empty / anything else", async () => {
  const ok = recorder(() => json({ id: "task-1", output: { file: { reasons: [] }, hashes: [] } }));
  const m = matcherFromEnv({
    env: env({ CSAM_MATCHER: "safer", SAFER_API_KEY: "s-1", SAFER_MATCH_URL: "https://safer.example/match" }),
    fetch: ok.fetchFn,
    environment: "production",
  });
  const r = await m.match(IMAGE, "image/jpeg");
  assert(r.outcome === "clear" && r.vendorRef === "task-1", JSON.stringify(r));
  const call = ok.calls[0];
  assert(call.url === "https://safer.example/match", call.url);
  assert((call.init.headers as Record<string, string>).Authorization === "Token s-1", "token");
  const form = call.init.body as FormData;
  assert(form instanceof FormData && form.get("media") instanceof Blob, "multipart media");

  const matched = readSaferMatch({
    output: { file: { reasons: ["matched"] }, hashes: [{ sources: [{ matches: [{ sourceId: "src-9" }] }] }] },
  });
  assert(matched.outcome === "match" && matched.vendorRef === "src-9", JSON.stringify(matched));
  for (const body of [{}, { output: { file: { reasons: ["other"] }, hashes: [] } },
                      { output: { file: { reasons: [] }, hashes: [{}] } }, { output: { file: {} } }, null]) {
    assert(readSaferMatch(body).outcome === "unavailable", JSON.stringify(body));
  }
  const err = saferMatcher("k", "https://safer.example/match", recorder(() => json({}, 500)).fetchFn);
  assert((await err.match(IMAGE, "image/jpeg")).vendorRef === "http:500", "500");
});
```

- [ ] **Step 2: Run it to make sure it fails**

```bash
(cd supabase/functions && NO_COLOR=1 deno test --allow-read _shared/csam_matcher.test.ts 2>&1 | grep -E 'Module not found' | head -1)
```

Expected: `error: Module not found "file:///…/supabase/functions/_shared/csam_matcher.ts".`

- [ ] **Step 3: Write the seam**

Create `supabase/functions/_shared/csam_matcher.ts` with exactly:

```ts
// supabase/functions/_shared/csam_matcher.ts
//
// Spec 1 W7b (§4.5 scan-media; plan P-23): the CSAM hash-matching seam.
// CSAM_MATCHER picks the adapter: `photodna` (Microsoft PhotoDNA Cloud
// Service), `safer` (Thorn Safer) or `stub` (a test hash list, development
// only). Every adapter answers clear, match, unavailable or skipped, and
// is written so that anything it does not positively understand is
// `unavailable`, never `clear`: an unknown status, a malformed body, a
// timeout, a missing key. In production (get_attune_environment) the stub
// is refused: it answers `unavailable` for everything, so nothing is ever
// marked clear by a stub and a person hears within 24 hours (scan_failed).
// Nothing here depends on an LLM. No adapter hashes video in W7b (plan
// P-19): scan-media skips a video and scans its poster image, which every
// app upload path stores as its own image object.
export type MatchOutcome = "clear" | "match" | "unavailable" | "skipped";

export interface MatchResult {
  outcome: MatchOutcome;
  vendor: string;
  /// The vendor's reference for this answer (tracking id), or why it was
  /// unavailable. Never the image, never a person.
  vendorRef: string | null;
}

export interface CsamMatcher {
  readonly name: string;
  readonly supportsVideo: boolean;
  match(bytes: Uint8Array, mime: string): Promise<MatchResult>;
}

export type FetchFn = (input: string, init: RequestInit) => Promise<Response>;
export type AttuneEnvironment = "development" | "production";

export interface MatcherConfig {
  env(name: string): string | undefined;
  fetch: FetchFn;
  environment: AttuneEnvironment;
  /// Per call; the default leaves room in scan-media's run budget.
  timeoutMs?: number;
}

export const PHOTODNA_DEFAULT_URL = "https://api.microsoftmoderator.com/photodna/v1.0/Match";

/// The image types PhotoDNA's Match call accepts.
export const PHOTODNA_TYPES = ["image/jpeg", "image/png", "image/gif", "image/bmp", "image/tiff"];

/// SHA-256 of the UTF-8 text "attune-csam-stub-match": the stub's built-in
/// match (scan-media/testdata/stub-match.png holds exactly those bytes).
export const STUB_MATCH_SHA256 = "e626741fb1d4120438b2d38427087d3ae68863b1d657cc4d43eaa744ffbd93bc";

/// SHA-256 of "attune-csam-stub-unavailable": the stub answers unavailable.
export const STUB_UNAVAILABLE_SHA256 = "0c46e55b57ee5b883d1f28bd61366c046dea0b2fe64e7140e2b113b5a90e7292";

const DEFAULT_TIMEOUT_MS = 15_000;

export async function sha256Hex(bytes: Uint8Array): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new Uint8Array(bytes));
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

function unavailable(vendor: string, reason: string): CsamMatcher {
  return {
    name: vendor,
    supportsVideo: false,
    match: () => Promise.resolve({ outcome: "unavailable", vendor, vendorRef: reason }),
  };
}

/// Microsoft PhotoDNA Cloud Service, Match: the image bytes in the body,
/// the subscription key in Ocp-Apim-Subscription-Key; a 200 whose
/// Status.Code is 3000 carries IsMatch and a TrackingId.
export function photoDnaMatcher(key: string, url: string, fetchFn: FetchFn, timeoutMs = DEFAULT_TIMEOUT_MS): CsamMatcher {
  return {
    name: "photodna",
    supportsVideo: false,
    async match(bytes, mime) {
      const type = mime.toLowerCase();
      if (!PHOTODNA_TYPES.includes(type)) {
        return { outcome: "unavailable", vendor: "photodna", vendorRef: `unsupported_type:${type}` };
      }
      try {
        const response = await fetchFn(`${url}?enhance=false`, {
          method: "POST",
          headers: { "Ocp-Apim-Subscription-Key": key, "Content-Type": type },
          body: new Uint8Array(bytes),
          signal: AbortSignal.timeout(timeoutMs),
        });
        if (!response.ok) {
          return { outcome: "unavailable", vendor: "photodna", vendorRef: `http:${response.status}` };
        }
        return readPhotoDnaMatch(await response.json());
      } catch (error) {
        return {
          outcome: "unavailable",
          vendor: "photodna",
          vendorRef: error instanceof Error && error.name === "TimeoutError" ? "timeout" : "network",
        };
      }
    },
  };
}

export function readPhotoDnaMatch(body: unknown): MatchResult {
  const b = (body ?? {}) as Record<string, unknown>;
  const status = (b.Status ?? {}) as Record<string, unknown>;
  const tracking = typeof b.TrackingId === "string" ? b.TrackingId : null;
  if (status.Code !== 3000) {
    return { outcome: "unavailable", vendor: "photodna", vendorRef: `status:${String(status.Code ?? "missing")}` };
  }
  if (b.IsMatch === true) return { outcome: "match", vendor: "photodna", vendorRef: tracking };
  if (b.IsMatch === false) return { outcome: "clear", vendor: "photodna", vendorRef: tracking };
  return { outcome: "unavailable", vendor: "photodna", vendorRef: "status:3000_without_answer" };
}

/// Thorn Safer. Thorn publishes its API reference to customers only, so
/// this follows the response published for Thorn-backed hash matching
/// (output.file.reasons holds "matched" on a match and is empty otherwise;
/// output.hashes lists what matched) with the image sent as multipart
/// `media` and the key as `Authorization: Token <key>`. The owner checks
/// both against Thorn's reference before CSAM_MATCHER=safer (plan P-24);
/// any other shape is unavailable, never clear.
export function saferMatcher(key: string, url: string, fetchFn: FetchFn, timeoutMs = DEFAULT_TIMEOUT_MS): CsamMatcher {
  return {
    name: "safer",
    supportsVideo: false,
    async match(bytes, mime) {
      try {
        const form = new FormData();
        form.append("media", new Blob([new Uint8Array(bytes)], { type: mime }), "upload");
        const response = await fetchFn(url, {
          method: "POST",
          headers: { Authorization: `Token ${key}` },
          body: form,
          signal: AbortSignal.timeout(timeoutMs),
        });
        if (!response.ok) {
          return { outcome: "unavailable", vendor: "safer", vendorRef: `http:${response.status}` };
        }
        return readSaferMatch(await response.json());
      } catch (error) {
        return {
          outcome: "unavailable",
          vendor: "safer",
          vendorRef: error instanceof Error && error.name === "TimeoutError" ? "timeout" : "network",
        };
      }
    },
  };
}

export function readSaferMatch(body: unknown): MatchResult {
  const b = (body ?? {}) as Record<string, unknown>;
  const output = (b.output ?? {}) as Record<string, unknown>;
  const file = (output.file ?? {}) as Record<string, unknown>;
  const reasons = file.reasons;
  const hashes = output.hashes;
  const id = typeof b.id === "string" ? b.id : null;
  if (!Array.isArray(reasons) || !Array.isArray(hashes)) {
    return { outcome: "unavailable", vendor: "safer", vendorRef: "unreadable_response" };
  }
  if (reasons.includes("matched")) {
    const first = hashes[0] as Record<string, unknown> | undefined;
    const source = Array.isArray(first?.sources) ? (first!.sources as Record<string, unknown>[])[0] : undefined;
    const matchRow = Array.isArray(source?.matches) ? (source!.matches as Record<string, unknown>[])[0] : undefined;
    const sourceId = typeof matchRow?.sourceId === "string" ? matchRow.sourceId : null;
    return { outcome: "match", vendor: "safer", vendorRef: id ?? sourceId };
  }
  if (reasons.length === 0 && hashes.length === 0) {
    return { outcome: "clear", vendor: "safer", vendorRef: id };
  }
  return { outcome: "unavailable", vendor: "safer", vendorRef: "unreadable_response" };
}

/// Development only: a match when the bytes' SHA-256 is on the test list
/// (STUB_MATCH_SHA256 and any in CSAM_STUB_MATCH_SHA256, comma separated),
/// unavailable for STUB_UNAVAILABLE_SHA256, otherwise clear.
export function stubMatcher(extraMatches: string[] = []): CsamMatcher {
  const matches = new Set([STUB_MATCH_SHA256, ...extraMatches.map((h) => h.trim().toLowerCase()).filter(Boolean)]);
  return {
    name: "stub",
    supportsVideo: false,
    async match(bytes) {
      const hash = await sha256Hex(bytes);
      if (matches.has(hash)) return { outcome: "match", vendor: "stub", vendorRef: `stub:${hash.slice(0, 12)}` };
      if (hash === STUB_UNAVAILABLE_SHA256) return { outcome: "unavailable", vendor: "stub", vendorRef: "stub:unavailable" };
      return { outcome: "clear", vendor: "stub", vendorRef: null };
    },
  };
}

export function matcherFromEnv(config: MatcherConfig): CsamMatcher {
  const choice = (config.env("CSAM_MATCHER") ?? "").trim().toLowerCase();
  const timeoutMs = config.timeoutMs ?? DEFAULT_TIMEOUT_MS;
  switch (choice) {
    case "photodna": {
      const key = config.env("PHOTODNA_SUBSCRIPTION_KEY")?.trim();
      if (!key) return unavailable("photodna", "not_configured");
      return photoDnaMatcher(key, config.env("PHOTODNA_URL")?.trim() || PHOTODNA_DEFAULT_URL, config.fetch, timeoutMs);
    }
    case "safer": {
      const key = config.env("SAFER_API_KEY")?.trim();
      const url = config.env("SAFER_MATCH_URL")?.trim();
      if (!key || !url?.startsWith("https://")) return unavailable("safer", "not_configured");
      return saferMatcher(key, url, config.fetch, timeoutMs);
    }
    case "stub":
      if (config.environment !== "development") return unavailable("stub", "stub_refused_in_production");
      return stubMatcher((config.env("CSAM_STUB_MATCH_SHA256") ?? "").split(","));
    default:
      return unavailable(choice || "none", "matcher_not_configured");
  }
}
```

- [ ] **Step 4: Run the test and type-check**

```bash
(cd supabase/functions && NO_COLOR=1 deno test --allow-read _shared/csam_matcher.test.ts 2>&1 | grep -E '^(ok|FAILED) \|')
(cd supabase/functions && deno check _shared/csam_matcher.ts _shared/csam_matcher.test.ts 2>&1 | grep -vE '^Check ' | head -3)
```

Expected: `ok | 6 passed | 0 failed`; no `deno check` output.

- [ ] **Step 5: Mutation checks (each must turn the test red)**

```bash
cd supabase/functions
D=../../.superpowers/sdd/2026-11-03-spec1-w7
tmut() { # name file old new tests...
  local name=$1 file=$2 old=$3 new=$4; shift 4
  cp "$file" "$D/mut.orig"
  python3 -I - "$file" "$old" "$new" <<'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1]); s = p.read_text()
assert s.count(sys.argv[2]) == 1, sys.argv[2]
p.write_text(s.replace(sys.argv[2], sys.argv[3]))
PY
  echo "$name: $(NO_COLOR=1 deno test --allow-read "$@" 2>&1 | grep -E '^(ok|FAILED) \|')"
  cp "$D/mut.orig" "$file"; rm "$D/mut.orig"
}
tmut stub_allowed_in_production _shared/csam_matcher.ts \
  '    if (config.environment !== "development") return unavailable("stub", "stub_refused_in_production");' '' \
  _shared/csam_matcher.test.ts
tmut photodna_unknown_is_clear _shared/csam_matcher.ts \
  '  if (b.IsMatch === false) return { outcome: "clear", vendor: "photodna", vendorRef: tracking };' \
  '  if (b.IsMatch !== true) return { outcome: "clear", vendor: "photodna", vendorRef: tracking };' \
  _shared/csam_matcher.test.ts
tmut safer_unknown_is_clear _shared/csam_matcher.ts \
  '  if (reasons.length === 0 && hashes.length === 0) {' '  if (true) {' _shared/csam_matcher.test.ts
NO_COLOR=1 deno test --allow-read _shared/csam_matcher.test.ts 2>&1 | grep -E '^(ok|FAILED) \|'
```

Expected: `stub_allowed_in_production`, `photodna_unknown_is_clear` and `safer_unknown_is_clear` each `FAILED | 5 passed | 1 failed`; then `ok | 6 passed | 0 failed`.

### Task 7: The one quarantine-and-record path (§4.5, §7.2; I-10; P-18)

**Files:**
- Create: `supabase/functions/_shared/csam_match_path.ts`
- Create: `supabase/functions/_shared/csam_match_path.test.ts`

**Interfaces:**
- Consumes: Task 5's `complete_media_scan` (`match` / `match_unquarantined`) and `record_inline_csam_match` (`p_quarantined`).
- Produces: `interface MatchRpcClient { rpc(fn, args?) }`, `type QuarantineOutcome = "stored" | "exists" | "failed"`, `interface QuarantineStore { put(path, bytes, mime) }`, `type MatchRecorder = (quarantined: boolean) => Promise<{ escalationId: number | null; error: string | null }>`, `QUARANTINE_BUCKET = "safety-quarantine"`, `quarantinePath(bucket, objectName) = "<bucket>/<objectName>"`, `interface StorageBucketLike { upload(path, body, {contentType, upsert}) }`, `storageQuarantine(bucket)`, `queuedRecorder(client, jobId, vendor, vendorRef)`, `inlineRecorder(client, {bucket, objectName, ownerUserId, vendor, vendorRef})` (Spec 2's `process-dating-photo` calls this one), `quarantineAndRecord({bucket, objectName, bytes, mime, store, record, tries = 3}) → {quarantined, recorded, escalationId}`.

- [ ] **Step 1: Write the failing test**

Create `supabase/functions/_shared/csam_match_path.test.ts` with exactly:

```ts
// Spec 1 W7b (§7.2, review I-10; plan P-18): the one match path. The
// quarantine copy happens before the record call, for both the queued and
// the inline entry point; a copy that keeps failing is recorded as
// unquarantined (held and escalated, the original kept as evidence).
import {
  inlineRecorder,
  type MatchRpcClient,
  quarantineAndRecord,
  type QuarantineOutcome,
  queuedRecorder,
  storageQuarantine,
} from "./csam_match_path.ts";

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

const BYTES = new TextEncoder().encode("evidence");

function rig(puts: QuarantineOutcome[], rpcData: unknown = 41) {
  const log: string[] = [];
  const store = {
    put(path: string, _bytes: Uint8Array, mime: string) {
      log.push(`put ${path} ${mime}`);
      return Promise.resolve(puts.shift() ?? "failed");
    },
  };
  const client: MatchRpcClient = {
    rpc(fn, args) {
      log.push(`rpc ${fn} ${JSON.stringify(args)}`);
      return Promise.resolve({ data: rpcData, error: null });
    },
  };
  return { log, store, client };
}

Deno.test("queued: copied to quarantine first, then complete_media_scan(match)", async () => {
  const r = rig(["stored"]);
  const result = await quarantineAndRecord({
    bucket: "message-media",
    objectName: "rel/1/a.jpg",
    bytes: BYTES,
    mime: "image/jpeg",
    store: r.store,
    record: queuedRecorder(r.client, 7, "photodna", "trk-1"),
  });
  assert(r.log[0] === "put message-media/rel/1/a.jpg image/jpeg", r.log.join(" | "));
  assert(r.log[1] === 'rpc complete_media_scan {"p_job_id":7,"p_result":"match","p_vendor":"photodna","p_vendor_ref":"trk-1"}', r.log.join(" | "));
  assert(r.log.length === 2 && result.quarantined && result.recorded, JSON.stringify(result));
});

Deno.test("inline: copied to quarantine first, then record_inline_csam_match", async () => {
  const r = rig(["exists"], 99);
  const result = await quarantineAndRecord({
    bucket: "dating-profile-photos",
    objectName: "u/1.jpg",
    bytes: BYTES,
    mime: "image/jpeg",
    store: r.store,
    record: inlineRecorder(r.client, {
      bucket: "dating-profile-photos",
      objectName: "u/1.jpg",
      ownerUserId: "5f7b0000-0000-0000-0000-000000000002",
      vendor: "photodna",
      vendorRef: "trk-3",
    }),
  });
  assert(r.log[0].startsWith("put dating-profile-photos/u/1.jpg"), r.log.join(" | "));
  assert(r.log[1].startsWith("rpc record_inline_csam_match ") && r.log[1].includes('"p_quarantined":true'), r.log[1]);
  assert(result.escalationId === 99 && result.quarantined, JSON.stringify(result));
});

Deno.test("a copy that keeps failing: three tries, then recorded unquarantined", async () => {
  const q = rig(["failed", "failed", "failed"]);
  const queued = await quarantineAndRecord({
    bucket: "avatars",
    objectName: "u/avatar.jpg",
    bytes: BYTES,
    mime: "image/jpeg",
    store: q.store,
    record: queuedRecorder(q.client, 8, "photodna", "trk-4"),
  });
  assert(q.log.filter((l) => l.startsWith("put")).length === 3, q.log.join(" | "));
  assert(q.log[3].includes('"p_result":"match_unquarantined"'), q.log[3]);
  assert(!queued.quarantined && queued.recorded, JSON.stringify(queued));

  const i = rig(["failed", "stored"]);
  const inline = await quarantineAndRecord({
    bucket: "dating-profile-photos",
    objectName: "u/2.jpg",
    bytes: BYTES,
    mime: "image/jpeg",
    store: i.store,
    record: inlineRecorder(i.client, { bucket: "dating-profile-photos", objectName: "u/2.jpg", ownerUserId: null, vendor: "safer", vendorRef: null }),
  });
  assert(inline.quarantined && i.log.filter((l) => l.startsWith("put")).length === 2, i.log.join(" | "));
});

Deno.test("the storage quarantine never overwrites; a copy already there counts", async () => {
  const calls: unknown[] = [];
  const answer = (error: { message: string; statusCode?: string } | null) =>
    storageQuarantine({
      upload(path, _body, options) {
        calls.push([path, options]);
        return Promise.resolve({ error });
      },
    });
  assert(await answer(null).put("b/x.jpg", BYTES, "image/jpeg") === "stored", "stored");
  assert(JSON.stringify(calls[0]) === '["b/x.jpg",{"contentType":"image/jpeg","upsert":false}]', JSON.stringify(calls[0]));
  assert(await answer({ message: "The resource already exists", statusCode: "409" }).put("b/x.jpg", BYTES, "image/jpeg") === "exists", "409");
  assert(await answer({ message: "Internal error", statusCode: "500" }).put("b/x.jpg", BYTES, "image/jpeg") === "failed", "500");
  const throwing = storageQuarantine({ upload: () => Promise.reject(new Error("net")) });
  assert(await throwing.put("b/x.jpg", BYTES, "") === "failed", "thrown");
});
```

- [ ] **Step 2: Run it to make sure it fails**

```bash
(cd supabase/functions && NO_COLOR=1 deno test --allow-read _shared/csam_match_path.test.ts 2>&1 | grep -E 'Module not found' | head -1)
```

Expected: `error: Module not found "file:///…/supabase/functions/_shared/csam_match_path.ts".`

- [ ] **Step 3: Write the path**

Create `supabase/functions/_shared/csam_match_path.ts` with exactly:

```ts
// supabase/functions/_shared/csam_match_path.ts
//
// Spec 1 W7b (§4.5, review I-10): THE quarantine-and-record path, used by
// scan-media (a queued job) and by Spec 2's process-dating-photo (an
// inline match). The bytes go to the private safety-quarantine bucket
// FIRST; only then is the match recorded (complete_media_scan or
// record_inline_csam_match -> private.handle_csam_match: one escalation,
// one safety_review hold, the original queued for deletion). If the copy
// fails after [tries] attempts the match is still recorded at once, as
// unquarantined: the account is held and a person is told, and the
// original is NOT deleted, because it is then the only copy of the
// evidence (plan P-18). Nothing here tells the uploader or anyone else.
type RpcResult = PromiseLike<{ data: unknown; error: { message: string } | null }>;

export interface MatchRpcClient {
  rpc(fn: string, args?: Record<string, unknown>): RpcResult;
}

export type QuarantineOutcome = "stored" | "exists" | "failed";

export interface QuarantineStore {
  put(path: string, bytes: Uint8Array, mime: string): Promise<QuarantineOutcome>;
}

/// What the match is recorded as; [quarantined] says whether the copy is in
/// safety-quarantine.
export type MatchRecorder = (quarantined: boolean) => Promise<{ escalationId: number | null; error: string | null }>;

export const QUARANTINE_BUCKET = "safety-quarantine";

/// The original's bucket and name, kept whole, so a reviewer finds both.
export function quarantinePath(bucket: string, objectName: string): string {
  return `${bucket}/${objectName}`;
}

/// Storage's upload, never overwriting: a copy already there (a retry) is
/// the same evidence.
export interface StorageBucketLike {
  upload(
    path: string,
    body: Uint8Array,
    options: { contentType: string; upsert: boolean },
  ): PromiseLike<{ error: { message: string; statusCode?: string | number } | null }>;
}

export function storageQuarantine(bucket: StorageBucketLike): QuarantineStore {
  return {
    async put(path, bytes, mime) {
      try {
        const { error } = await bucket.upload(path, bytes, { contentType: mime || "application/octet-stream", upsert: false });
        if (!error) return "stored";
        const duplicate = String(error.statusCode ?? "") === "409" || /already exists|duplicate/i.test(error.message);
        return duplicate ? "exists" : "failed";
      } catch {
        return "failed";
      }
    },
  };
}

export function queuedRecorder(client: MatchRpcClient, jobId: number, vendor: string, vendorRef: string | null): MatchRecorder {
  return async (quarantined) => {
    const { error } = await client.rpc("complete_media_scan", {
      p_job_id: jobId,
      p_result: quarantined ? "match" : "match_unquarantined",
      p_vendor: vendor,
      p_vendor_ref: vendorRef,
    });
    return { escalationId: null, error: error ? "complete_failed" : null };
  };
}

export function inlineRecorder(
  client: MatchRpcClient,
  object: { bucket: string; objectName: string; ownerUserId: string | null; vendor: string; vendorRef: string | null },
): MatchRecorder {
  return async (quarantined) => {
    const { data, error } = await client.rpc("record_inline_csam_match", {
      p_bucket: object.bucket,
      p_object_name: object.objectName,
      p_owner: object.ownerUserId,
      p_vendor: object.vendor,
      p_vendor_ref: object.vendorRef,
      p_quarantined: quarantined,
    });
    if (error) return { escalationId: null, error: "record_failed" };
    return { escalationId: typeof data === "number" ? data : Number(data) || null, error: null };
  };
}

export interface QuarantineAndRecordResult {
  quarantined: boolean;
  recorded: boolean;
  escalationId: number | null;
}

export async function quarantineAndRecord(input: {
  bucket: string;
  objectName: string;
  bytes: Uint8Array;
  mime: string;
  store: QuarantineStore;
  record: MatchRecorder;
  tries?: number;
}): Promise<QuarantineAndRecordResult> {
  const path = quarantinePath(input.bucket, input.objectName);
  let quarantined = false;
  for (let i = 0; i < (input.tries ?? 3) && !quarantined; i++) {
    const outcome = await input.store.put(path, input.bytes, input.mime);
    quarantined = outcome === "stored" || outcome === "exists";
  }
  const recorded = await input.record(quarantined);
  return { quarantined, recorded: recorded.error === null, escalationId: recorded.escalationId };
}
```

- [ ] **Step 4: Run the test and type-check**

```bash
(cd supabase/functions && NO_COLOR=1 deno test --allow-read _shared/csam_match_path.test.ts 2>&1 | grep -E '^(ok|FAILED) \|')
(cd supabase/functions && deno check _shared/csam_match_path.ts _shared/csam_match_path.test.ts 2>&1 | grep -vE '^Check ' | head -3)
```

Expected: `ok | 4 passed | 0 failed`; no `deno check` output.

- [ ] **Step 5: Mutation checks (each must turn the test red)**

```bash
cd supabase/functions
D=../../.superpowers/sdd/2026-11-03-spec1-w7
tmut() { # name file old new tests...
  local name=$1 file=$2 old=$3 new=$4; shift 4
  cp "$file" "$D/mut.orig"
  python3 -I - "$file" "$old" "$new" <<'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1]); s = p.read_text()
assert s.count(sys.argv[2]) == 1, sys.argv[2]
p.write_text(s.replace(sys.argv[2], sys.argv[3]))
PY
  echo "$name: $(NO_COLOR=1 deno test --allow-read "$@" 2>&1 | grep -E '^(ok|FAILED) \|')"
  cp "$D/mut.orig" "$file"; rm "$D/mut.orig"
}
tmut record_before_quarantine _shared/csam_match_path.ts \
  '  const path = quarantinePath(input.bucket, input.objectName);' \
  '  await input.record(true);
  const path = quarantinePath(input.bucket, input.objectName);' _shared/csam_match_path.test.ts
tmut failed_copy_counts_as_quarantined _shared/csam_match_path.ts \
  '    quarantined = outcome === "stored" || outcome === "exists";' '    quarantined = true;' _shared/csam_match_path.test.ts
NO_COLOR=1 deno test --allow-read _shared/csam_match_path.test.ts 2>&1 | grep -E '^(ok|FAILED) \|'
```

Expected: `record_before_quarantine: FAILED | 1 passed | 3 failed`, `failed_copy_counts_as_quarantined: FAILED | 3 passed | 1 failed`; then `ok | 4 passed | 0 failed`.

### Task 8: scan-media, the escalation webhook, and the W7b gate (§4.5, §4.6, §7.2, §8 W7b; P-19-P-21, P-23)

> **As built** (the text below is the brief as written): see `.superpowers/sdd/2026-11-03-spec1-w7-resources-image-safety/batch-6-report.md`, D1-D7 and Fix round 1. In short:
> - the test file is `testdata/stub-match.gif` (28 bytes);
> - one job is claimed at a time;
> - the kind is sniffed from a 4 KiB Range read (`objects.ts`), and only images up to 4 MiB are read whole;
> - scan-media answers 202 and runs in `EdgeRuntime.waitUntil`;
> - the W7b Deno gate is 88 tests, not 37 (it adds `_shared/timed_fetch.test.ts`).

**Files:**
- Create: `supabase/functions/scan-media/handler.ts`, `supabase/functions/scan-media/index.ts`, `supabase/functions/scan-media/handler.test.ts`
- Create: `supabase/functions/scan-media/testdata/stub-match.png` (22 bytes, the stub's test image)
- Modify: `supabase/functions/identity-health-alert/handler.ts` (one edit), `supabase/functions/identity-health-alert/handler.test.ts` (one test added)

**Interfaces:**
- Consumes: Task 5's `claim_media_scan_jobs`, `complete_media_scan`, `csam_escalations_due`, `scan_failed_escalations_due`, `mark_safety_escalations_alerted`, `get_attune_environment` (W1c); Task 6's `CsamMatcher`, `matcherFromEnv`; Task 7's `quarantineAndRecord`, `queuedRecorder`, `storageQuarantine`, `QUARANTINE_BUCKET`, `StorageBucketLike`; W6a's `sendAlerts`, `AlertClient`, `AlertResult`, `PostFn`.
- Produces: `CSAM_MATCH_ESCALATIONS`, `SCAN_FAILED_ESCALATIONS` (`AlertSource`s, in `ALERT_SOURCES` before W6c's); `interface ScanClient`, `interface ScanJob`, `interface ScanResult { claimed, clear, match, unquarantined, unavailable, skipped, unanswered, alerts }`, `BATCH = 20`, `RUN_BUDGET_MS = 50_000`, `readJobs(data)`, `scanMedia(client, matcher, {webhook, post}, {now?, budgetMs?, batch?})`; the `scan-media` function (service role only).

- [ ] **Step 1: Write the failing tests**

Create `supabase/functions/scan-media/handler.test.ts` with exactly:

```ts
// Spec 1 W7b (§4.5, §7.2): scan-media against a fake database and storage.
// Stub matcher match / clear / unavailable; the quarantine copy before the
// record; with get_attune_environment() = production the stub clears
// nothing; videos and vanished objects are skipped, never clear; a match
// reaches the safety webhook at once, as a count.
import { matcherFromEnv, stubMatcher } from "../_shared/csam_matcher.ts";
import { type ScanClient, scanMedia } from "./handler.ts";

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

const enc = new TextEncoder();

interface Rig {
  client: ScanClient;
  log: string[];
  completes: Record<string, unknown>[];
}

function rig(
  jobs: Record<string, unknown>[],
  objects: Record<string, string | null>,
  o: { quarantineFails?: boolean; completeFails?: boolean } = {},
): Rig {
  const log: string[] = [];
  const completes: Record<string, unknown>[] = [];
  const client: ScanClient = {
    rpc(fn, args) {
      log.push(`rpc ${fn}`);
      if (fn === "claim_media_scan_jobs") return Promise.resolve({ data: jobs, error: null });
      if (fn === "complete_media_scan") {
        completes.push(args ?? {});
        return Promise.resolve({ data: null, error: o.completeFails ? { message: "boom" } : null });
      }
      if (fn === "csam_escalations_due") {
        return Promise.resolve({ data: { ids: [1], count: 1, first_at: "t1", last_at: "t1" }, error: null });
      }
      if (fn.endsWith("_due")) {
        return Promise.resolve({ data: { ids: [], count: 0, first_at: null, last_at: null }, error: null });
      }
      return Promise.resolve({ data: null, error: null });
    },
    storage: {
      from(bucket) {
        return {
          download(path) {
            log.push(`download ${bucket}/${path}`);
            const text = objects[`${bucket}/${path}`];
            if (text === undefined) return Promise.resolve({ data: null, error: { message: "Object not found", statusCode: "404" } });
            if (text === null) return Promise.resolve({ data: null, error: { message: "Internal error", statusCode: "500" } });
            return Promise.resolve({ data: new Blob([enc.encode(text)]), error: null });
          },
          upload(path) {
            log.push(`upload ${bucket}/${path}`);
            return Promise.resolve({ error: o.quarantineFails ? { message: "Internal error", statusCode: "500" } : null });
          },
        };
      },
    },
  };
  return { client, log, completes };
}

const job = (id: number, name: string, mime = "image/jpeg", bucket = "message-media") => ({
  id,
  bucket,
  object_name: name,
  owner_user_id: "5f7b0000-0000-0000-0000-000000000001",
  mime,
  attempts: 1,
});

const quietAlert = { webhook: undefined, post: () => Promise.resolve({ ok: true, status: 200 }) };

Deno.test("stub: clear, match (quarantined first) and unavailable", async () => {
  const r = rig(
    [job(1, "a.jpg"), job(2, "b.jpg"), job(3, "c.jpg")],
    {
      "message-media/a.jpg": "an ordinary photo",
      "message-media/b.jpg": "attune-csam-stub-match",
      "message-media/c.jpg": "attune-csam-stub-unavailable",
    },
  );
  const result = await scanMedia(r.client, stubMatcher(), quietAlert);
  assert(result.claimed === 3 && result.clear === 1 && result.match === 1 && result.unavailable === 1, JSON.stringify(result));
  const byJob = Object.fromEntries(r.completes.map((c) => [c.p_job_id, c.p_result]));
  assert(byJob[1] === "clear" && byJob[2] === "match" && byJob[3] === "unavailable", JSON.stringify(byJob));
  const upload = r.log.indexOf("upload safety-quarantine/message-media/b.jpg");
  const record = r.log.findIndex((l, i) => i > upload && l === "rpc complete_media_scan");
  assert(upload > -1 && record > upload, r.log.join(" | "));
  assert(r.completes.find((c) => c.p_job_id === 2)?.p_vendor === "stub", "vendor recorded");
});

Deno.test("production: the stub is refused and clears nothing", async () => {
  const r = rig([job(1, "a.jpg"), job(2, "b.jpg")], {
    "message-media/a.jpg": "an ordinary photo",
    "message-media/b.jpg": "attune-csam-stub-match",
  });
  const matcher = matcherFromEnv({ env: (n) => (n === "CSAM_MATCHER" ? "stub" : undefined), fetch, environment: "production" });
  const result = await scanMedia(r.client, matcher, quietAlert);
  assert(result.clear === 0 && result.match === 0 && result.unavailable === 2, JSON.stringify(result));
  assert(r.completes.every((c) => c.p_result === "unavailable" && c.p_vendor_ref === "stub_refused_in_production"), JSON.stringify(r.completes));
  assert(!r.log.some((l) => l.startsWith("upload")), "quarantined with a refused stub");
});

Deno.test("a video is skipped without a download; a vanished object is skipped", async () => {
  const r = rig([job(1, "v.mp4", "video/mp4", "story-media"), job(2, "gone.jpg")], {});
  const result = await scanMedia(r.client, stubMatcher(), quietAlert);
  assert(result.skipped === 2 && result.clear === 0, JSON.stringify(result));
  assert(!r.log.includes("download story-media/v.mp4"), r.log.join(" | "));
  const refs = r.completes.map((c) => `${c.p_result}:${c.p_vendor_ref}`);
  assert(refs.join(",") === "skipped:video_not_hashed,skipped:object_missing", refs.join(","));
});

Deno.test("a download that fails is unavailable, never clear", async () => {
  const r = rig([job(1, "x.jpg")], { "message-media/x.jpg": null });
  const result = await scanMedia(r.client, stubMatcher(), quietAlert);
  assert(result.unavailable === 1 && r.completes[0].p_vendor_ref === "download_failed", JSON.stringify(result));
});

Deno.test("a failing quarantine still records the match, as unquarantined", async () => {
  const r = rig([job(9, "m.jpg")], { "message-media/m.jpg": "attune-csam-stub-match" }, { quarantineFails: true });
  const result = await scanMedia(r.client, stubMatcher(), quietAlert);
  assert(result.unquarantined === 1 && result.match === 0, JSON.stringify(result));
  assert(r.log.filter((l) => l.startsWith("upload")).length === 3, r.log.join(" | "));
  assert(r.completes[0].p_result === "match_unquarantined", JSON.stringify(r.completes));
});

Deno.test("a match reaches the safety webhook at once, as a count", async () => {
  const r = rig([job(1, "b.jpg")], { "message-media/b.jpg": "attune-csam-stub-match" });
  const posts: string[] = [];
  const result = await scanMedia(r.client, stubMatcher(), {
    webhook: "https://hooks.example/x",
    post: (_url, body) => {
      posts.push(body);
      return Promise.resolve({ ok: true, status: 200 });
    },
  });
  assert(result.alerts !== "not_needed" && result.alerts.csam_match === "sent", JSON.stringify(result.alerts));
  assert(posts.length === 1 && !posts[0].includes("b.jpg") && !posts[0].includes("5f7b"), posts.join(" | "));
});

Deno.test("nothing claimed (flag off): no download, no post", async () => {
  const r = rig([], {});
  const result = await scanMedia(r.client, stubMatcher(), quietAlert);
  assert(result.claimed === 0 && result.alerts === "not_needed", JSON.stringify(result));
  assert(r.log.join(",") === "rpc claim_media_scan_jobs", r.log.join(","));
});

Deno.test("an unanswered completion is counted (the lease brings it back)", async () => {
  const r = rig([job(1, "a.jpg")], { "message-media/a.jpg": "ordinary" }, { completeFails: true });
  const result = await scanMedia(r.client, stubMatcher(), quietAlert);
  assert(result.unanswered === 1 && result.clear === 0, JSON.stringify(result));
});

Deno.test("the run budget stops new work", async () => {
  let t = 0;
  const r = rig([job(1, "a.jpg"), job(2, "b.jpg")], { "message-media/a.jpg": "x", "message-media/b.jpg": "y" });
  const result = await scanMedia(r.client, stubMatcher(), quietAlert, { now: () => (t += 30_000), budgetMs: 50_000 });
  assert(result.clear === 1 && result.unanswered === 1, JSON.stringify(result));
});
```

`supabase/functions/identity-health-alert/handler.test.ts`, edit 1 of 1. Replace exactly:

```ts
Deno.test("a failed read or mark is reported, never thrown", async () => {
```

with:

```ts
Deno.test("W7b: CSAM matches and scan failures post a count and a time, then are marked", async () => {
  const calls: string[] = [];
  const client: AlertClient = {
    rpc(fn, args) {
      calls.push(`${fn}:${JSON.stringify(args ?? {})}`);
      if (fn === "csam_escalations_due") {
        return Promise.resolve({ data: { ids: [41], count: 1, first_at: "2026-11-03T14:00:00Z", last_at: "2026-11-03T14:00:00Z" }, error: null });
      }
      if (fn === "scan_failed_escalations_due") {
        return Promise.resolve({ data: { ids: [42, 43], count: 2, first_at: "2026-11-03T13:00:00Z", last_at: "2026-11-03T13:30:00Z" }, error: null });
      }
      if (fn.endsWith("_due")) {
        return Promise.resolve({ data: { ids: [], count: 0, first_at: null, last_at: null }, error: null });
      }
      return Promise.resolve({ data: null, error: null });
    },
  };
  const posts: string[] = [];
  const result = await sendAlerts(client, "https://hooks.example/x", async (_url, body) => {
    posts.push(JSON.parse(body).text);
    return { ok: true, status: 200 };
  });
  assert(result.csam_match === "sent" && result.scan_failed === "sent", JSON.stringify(result));
  assert(posts.length === 2, `posts ${posts.length}`);
  assert(posts[0].includes("1 image(s) matched") && posts[0].includes("nothing has been reported"), posts[0]);
  assert(posts[1].includes("2 upload(s) could not be scanned"), posts[1]);
  assert(!posts.join(" ").match(/\b(41|42|43)\b/), "an escalation id was posted");
  assert(calls.includes('mark_safety_escalations_alerted:{"p_ids":[41]}'), calls.join(" "));
  assert(calls.includes('mark_safety_escalations_alerted:{"p_ids":[42,43]}'), calls.join(" "));
});

Deno.test("a failed read or mark is reported, never thrown", async () => {
```

- [ ] **Step 2: Run them to make sure they fail**

```bash
(cd supabase/functions && NO_COLOR=1 deno test --allow-read scan-media/ identity-health-alert/ 2>&1 | grep -E 'Module not found|^(ok|FAILED) \|' | head -2)
```

Expected: `error: Module not found "file:///…/supabase/functions/scan-media/handler.ts".` (and the new identity-health-alert test fails once the module error is out of the way: `result.csam_match` is undefined).

- [ ] **Step 3: The two escalation sources**

`supabase/functions/identity-health-alert/handler.ts`, edit 1 of 1. Replace exactly:

```ts
export const ALERT_SOURCES: AlertSource[] = [
  HOOK_FAIL_OPENS,
  FRESH_START_UNPARKED,
  PARKED_KEPT_FOR_REVIEW,
  RECOVERY_PURGE_STUCK,
  CHILD_SAFETY_REPORTS,
];
```

with:

```ts
/// Spec 1 W7b (plan P-21): an image matched a known CSAM hash. The named
/// child-safety contact reviews it before anything is reported; the
/// uploader's account is already held. A count and a time only. scan-media
/// posts this straight after its run; this 15-minute run is the backstop.
export const CSAM_MATCH_ESCALATIONS: AlertSource = {
  name: "csam_match",
  due: "csam_escalations_due",
  mark: "mark_safety_escalations_alerted",
  line: (count, firstAt) =>
    `Attune: ${count} image(s) matched a known child sexual abuse hash, the first at ${firstAt}. ` +
    "The uploader's account is on hold and the image is in safety-quarantine. The named child-safety " +
    "contact must review them now (public.safety_escalations, status open); nothing has been reported to anyone.",
};

/// Spec 1 W7b: uploads not scanned within 24 hours (the matcher was down,
/// unconfigured, or the stub was refused in production).
export const SCAN_FAILED_ESCALATIONS: AlertSource = {
  name: "scan_failed",
  due: "scan_failed_escalations_due",
  mark: "mark_safety_escalations_alerted",
  line: (count, firstAt) =>
    `Attune: ${count} upload(s) could not be scanned for CSAM within 24 hours, the first at ${firstAt}. ` +
    "Check CSAM_MATCHER and its keys and scan-media's logs, then review public.safety_escalations (kind scan_failed).",
};

export const ALERT_SOURCES: AlertSource[] = [
  HOOK_FAIL_OPENS,
  FRESH_START_UNPARKED,
  PARKED_KEPT_FOR_REVIEW,
  RECOVERY_PURGE_STUCK,
  // W7b's two before W6c's, so W6c's test still sees its mark last.
  CSAM_MATCH_ESCALATIONS,
  SCAN_FAILED_ESCALATIONS,
  CHILD_SAFETY_REPORTS,
];
```

- [ ] **Step 4: scan-media and its test image**

Create `supabase/functions/scan-media/handler.ts` with exactly:

```ts
// supabase/functions/scan-media/handler.ts
//
// Spec 1 W7b (§4.5, §4.6): every minute, the scan-media cron claims due
// jobs (claim_media_scan_jobs: nothing while csam_hash_matching is off),
// downloads each object with the service role, asks the matcher, and
// answers complete_media_scan. A match goes through the one match path
// (_shared/csam_match_path.ts: quarantine first, then the record). A video
// is skipped without a download (no adapter hashes video in W7b, plan
// P-19; its poster image is its own object and is scanned). An object
// gone before its scan is skipped. A download or matcher failure is
// unavailable (the database backs off, and after 24 hours a person is
// told). When the run recorded a match or an unavailable answer, the
// safety webhook is told straight away through identity-health-alert's
// sendAlerts (counts and times only); identity-health-alert's 15-minute
// run is the backstop. Logs counts only: never a name, a path or a person.
import type { CsamMatcher } from "../_shared/csam_matcher.ts";
import {
  queuedRecorder,
  quarantineAndRecord,
  QUARANTINE_BUCKET,
  type StorageBucketLike,
  storageQuarantine,
} from "../_shared/csam_match_path.ts";
import {
  type AlertClient,
  type AlertResult,
  CSAM_MATCH_ESCALATIONS,
  type PostFn,
  SCAN_FAILED_ESCALATIONS,
  sendAlerts,
} from "../identity-health-alert/handler.ts";

type RpcResult = PromiseLike<{ data: unknown; error: { message: string } | null }>;

export interface ScanClient {
  rpc(fn: string, args?: Record<string, unknown>): RpcResult;
  storage: {
    from(bucket: string): StorageBucketLike & {
      download(path: string): PromiseLike<{
        data: Blob | null;
        error: { message: string; statusCode?: string | number } | null;
      }>;
    };
  };
}

export interface ScanJob {
  id: number;
  bucket: string;
  object_name: string;
  owner_user_id: string | null;
  mime: string | null;
  attempts: number;
}

export interface ScanResult {
  claimed: number;
  clear: number;
  match: number;
  unquarantined: number;
  unavailable: number;
  skipped: number;
  unanswered: number;
  alerts: AlertResult | "not_needed";
}

export const BATCH = 20;
export const RUN_BUDGET_MS = 50_000;

export function readJobs(data: unknown): ScanJob[] {
  if (!Array.isArray(data)) return [];
  return data.flatMap((row) => {
    const r = row as Record<string, unknown>;
    return typeof r?.id === "number" && typeof r.bucket === "string" && typeof r.object_name === "string"
      ? [{
        id: r.id,
        bucket: r.bucket,
        object_name: r.object_name,
        owner_user_id: typeof r.owner_user_id === "string" ? r.owner_user_id : null,
        mime: typeof r.mime === "string" ? r.mime : null,
        attempts: typeof r.attempts === "number" ? r.attempts : 0,
      }]
      : [];
  });
}

function missing(error: { message: string; statusCode?: string | number }): boolean {
  return String(error.statusCode ?? "") === "404" || /not.?found/i.test(error.message);
}

export async function scanMedia(
  client: ScanClient,
  matcher: CsamMatcher,
  alert: { webhook: string | undefined; post: PostFn },
  options: { now?: () => number; budgetMs?: number; batch?: number } = {},
): Promise<ScanResult> {
  const now = options.now ?? Date.now;
  const started = now();
  const result: ScanResult = {
    claimed: 0, clear: 0, match: 0, unquarantined: 0, unavailable: 0, skipped: 0, unanswered: 0, alerts: "not_needed",
  };
  const { data, error } = await client.rpc("claim_media_scan_jobs", { p_limit: options.batch ?? BATCH });
  if (error) throw new Error("claim_failed");
  const jobs = readJobs(data);
  result.claimed = jobs.length;

  const complete = async (job: ScanJob, outcome: string, vendor: string, vendorRef: string | null) => {
    const { error: completeError } = await client.rpc("complete_media_scan", {
      p_job_id: job.id,
      p_result: outcome,
      p_vendor: vendor,
      p_vendor_ref: vendorRef,
    });
    // Unanswered: the 10-minute lease lapses and the job is claimed again.
    if (completeError) result.unanswered++;
    return !completeError;
  };

  for (const job of jobs) {
    if (now() - started >= (options.budgetMs ?? RUN_BUDGET_MS)) {
      result.unanswered++;
      continue;
    }
    const mime = (job.mime ?? "").toLowerCase();
    if (mime.startsWith("video/") && !matcher.supportsVideo) {
      if (await complete(job, "skipped", matcher.name, "video_not_hashed")) result.skipped++;
      continue;
    }
    let bytes: Uint8Array;
    try {
      const { data: blob, error: downloadError } = await client.storage.from(job.bucket).download(job.object_name);
      if (downloadError || !blob) {
        if (downloadError && missing(downloadError)) {
          if (await complete(job, "skipped", matcher.name, "object_missing")) result.skipped++;
        } else if (await complete(job, "unavailable", matcher.name, "download_failed")) {
          result.unavailable++;
        }
        continue;
      }
      bytes = new Uint8Array(await blob.arrayBuffer());
    } catch {
      if (await complete(job, "unavailable", matcher.name, "download_failed")) result.unavailable++;
      continue;
    }

    let answer;
    try {
      answer = await matcher.match(bytes, mime);
    } catch {
      answer = { outcome: "unavailable" as const, vendor: matcher.name, vendorRef: "matcher_error" };
    }
    if (answer.outcome === "match") {
      const matched = await quarantineAndRecord({
        bucket: job.bucket,
        objectName: job.object_name,
        bytes,
        mime,
        store: storageQuarantine(client.storage.from(QUARANTINE_BUCKET)),
        record: queuedRecorder(client, job.id, answer.vendor, answer.vendorRef),
      });
      if (!matched.recorded) result.unanswered++;
      else if (matched.quarantined) result.match++;
      else result.unquarantined++;
      continue;
    }
    if (await complete(job, answer.outcome, answer.vendor, answer.vendorRef)) {
      result[answer.outcome]++;
    }
  }

  if (result.match + result.unquarantined + result.unavailable > 0) {
    result.alerts = await sendAlerts(
      client as unknown as AlertClient,
      alert.webhook,
      alert.post,
      [CSAM_MATCH_ESCALATIONS, SCAN_FAILED_ESCALATIONS],
    );
  }
  return result;
}
```

Create `supabase/functions/scan-media/index.ts` with exactly:

```ts
// supabase/functions/scan-media/index.ts — see handler.ts.
// Run every minute by the scan-media cron (20261103140000) with the
// service-role key; any other caller gets 403. The matcher is chosen by
// CSAM_MATCHER (photodna, safer, stub); the stub is refused unless
// get_attune_environment() reads exactly 'development' (an unreadable
// environment is production). Logs counts only.
import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { HttpError, jsonResponse, requireServiceRole, serviceRoleClient } from "../_shared/attune_auth.ts";
import { type AttuneEnvironment, matcherFromEnv } from "../_shared/csam_matcher.ts";
import { type ScanClient, scanMedia } from "./handler.ts";

serve(async (req) => {
  if (req.method === "OPTIONS") return jsonResponse({ ok: true });
  try {
    requireServiceRole(req);
    const client = serviceRoleClient();
    const { data: environment, error: environmentError } = await client.rpc("get_attune_environment");
    const env: AttuneEnvironment = !environmentError && environment === "development" ? "development" : "production";
    const matcher = matcherFromEnv({ env: (name) => Deno.env.get(name), fetch, environment: env });
    const result = await scanMedia(client as unknown as ScanClient, matcher, {
      webhook: Deno.env.get("SAFETY_ALERT_WEBHOOK"),
      post: async (url, body) => {
        const response = await fetch(url, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body,
          signal: AbortSignal.timeout(10_000),
        });
        return { ok: response.ok, status: response.status };
      },
    });
    console.log("scan-media", matcher.name, env, JSON.stringify(result));
    return jsonResponse({ success: true, matcher: matcher.name, ...result });
  } catch (error) {
    if (error instanceof HttpError) return jsonResponse({ error: error.message }, error.status);
    console.error("scan-media failed:", error instanceof Error ? error.message : typeof error);
    return jsonResponse({ error: "scan_failed" }, 500);
  }
});
```

Then the stub's test image (exactly these 22 bytes, no newline; the stub matches its SHA-256):

```bash
mkdir -p supabase/functions/scan-media/testdata
printf 'attune-csam-stub-match' > supabase/functions/scan-media/testdata/stub-match.png
shasum -a 256 supabase/functions/scan-media/testdata/stub-match.png
```

Expected: `e626741fb1d4120438b2d38427087d3ae68863b1d657cc4d43eaa744ffbd93bc  supabase/functions/scan-media/testdata/stub-match.png`.

- [ ] **Step 5: Run the tests and type-check**

```bash
(cd supabase/functions && NO_COLOR=1 deno test --allow-read scan-media/ identity-health-alert/ 2>&1 | grep -E '^(ok|FAILED) \|')
(cd supabase/functions && deno check scan-media/index.ts scan-media/handler.test.ts identity-health-alert/index.ts 2>&1 | grep -vE '^Check ' | head -3)
```

Expected: `ok | 17 passed | 0 failed` (9 + 8); no `deno check` output.

- [ ] **Step 6: Mutation checks (each must turn the test red)**

```bash
cd supabase/functions
D=../../.superpowers/sdd/2026-11-03-spec1-w7
tmut() { # name file old new tests...
  local name=$1 file=$2 old=$3 new=$4; shift 4
  cp "$file" "$D/mut.orig"
  python3 -I - "$file" "$old" "$new" <<'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1]); s = p.read_text()
assert s.count(sys.argv[2]) == 1, sys.argv[2]
p.write_text(s.replace(sys.argv[2], sys.argv[3]))
PY
  echo "$name: $(NO_COLOR=1 deno test --allow-read "$@" 2>&1 | grep -E '^(ok|FAILED) \|')"
  cp "$D/mut.orig" "$file"; rm "$D/mut.orig"
}
tmut video_downloaded scan-media/handler.ts \
  '    if (mime.startsWith("video/") && !matcher.supportsVideo) {' '    if (false) {' scan-media/
tmut missing_is_clear scan-media/handler.ts \
  '          if (await complete(job, "skipped", matcher.name, "object_missing")) result.skipped++;' \
  '          if (await complete(job, "clear", matcher.name, "object_missing")) result.clear++;' scan-media/
tmut no_webhook_after_match scan-media/handler.ts \
  '  if (result.match + result.unquarantined + result.unavailable > 0) {' '  if (false) {' scan-media/
NO_COLOR=1 deno test --allow-read scan-media/ 2>&1 | grep -E '^(ok|FAILED) \|'
```

Expected: `video_downloaded`, `missing_is_clear` and `no_webhook_after_match` each `FAILED | 8 passed | 1 failed`; then `ok | 9 passed | 0 failed`.

- [ ] **Step 7: W7b gate (run tests)**

```bash
(cd supabase/functions && NO_COLOR=1 deno test --allow-read identity-health-alert/ start-fresh-account/ purge-recovery-holds/ scan-media/ _shared/csam_matcher.test.ts _shared/csam_match_path.test.ts 2>&1 | grep -E '^(ok|FAILED) \|')
for f in supabase/tests/*.sql; do
  if psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f "$f" >/dev/null 2>&1; then echo "PASS $(basename "$f")"; else echo "FAIL $(basename "$f")"; fi
done > .superpowers/sdd/2026-11-03-spec1-w7/sql-after-w7b.txt
grep '^FAIL' .superpowers/sdd/2026-11-03-spec1-w7/sql-after-w7b.txt | comm -13 <(grep '^FAIL' .superpowers/sdd/2026-11-03-spec1-w7/sql-baseline.txt) -
grep -E 'media_scan|support_resources|identity_foundation|dormancy|child_safety|account_deletion' .superpowers/sdd/2026-11-03-spec1-w7/sql-after-w7b.txt
flutter test 2>&1 | tail -1
flutter analyze --no-pub lib test 2>&1 | grep -E '^\s*error ' | sort | comm -13 .superpowers/sdd/2026-11-03-spec1-w7/analyze-baseline.txt -
sed -n '/if (isAuthenticated && !_gateData.isComplete) {/,/_redirectingToOnboarding = false;/p' lib/home/home_screen.dart | shasum | diff - .superpowers/sdd/2026-11-03-spec1-w7/latch.sha && echo latch-unchanged
git status --short lib/features/games lib/features/opinions lib/features/auth/utility/auth_exports.dart lib/home ATTUNE_SOUL.md ATTUNE_THESIS.md supabase/sql supabase/config.toml scripts/local_pg_bootstrap.sql
git status --short supabase/migrations | grep -v '^??'
```

Expected: `ok | 37 passed | 0 failed` (Task 1's 17, the one new identity-health-alert test, and 19 new); no new SQL FAIL; `PASS` for all six named files; `All tests passed!`; no new analyzer `error` line; `latch-unchanged`; no `git status` line from the last two commands (no applied migration edited; only new `??` migration files).

**W7b gate (before `csam_hash_matching` in production; spec §8 W7b):** the CSAM hash-vendor's eligibility and contract (PhotoDNA, Google's Content Safety API or Thorn Safer; owner); the escalation runbook approved by counsel; the named child-safety contact receives escalations (owner checklist 5-8).

---

## Owner deploy checklist (the plan never runs any of this)

1. **Order.** W1-W6 are deployed first (their checklists). Push W7a's migrations (`20261103130000`, `…130010`), load the catalogue (item 3), then, on development, `supabase secrets set CSAM_MATCHER=stub` (PF-L8, below) before W7b's (`20261103140000`, `…140010`, `…140100`, `…140110`); deploy `scan-media` and redeploy `identity-health-alert` (it carries the three new sources: CSAM matches, scan failures, and enqueue failures, final review M-1); production's vendor secrets are item 5. A build with the v2 screen can reach testers as soon as W7a's migrations are pushed: with nothing loaded it shows the bundled catalogue.
   - **Development, before pushing W7b (PF-L8):** `supabase secrets set CSAM_MATCHER=stub` on the development project first. `csam_hash_matching` is on in development, so once W7b is pushed every upload is queued; without a matcher each one answers `matcher_not_configured` and becomes a `scan_failed` escalation after 24 hours.
   - **Production, before deploying `scan-media` (PF-H1):** `select public.get_attune_environment();` must read `production`. An unset environment reads `development`, and the stub's second check (the exact development host) is then the only thing between a `CSAM_MATCHER=stub` secret and a stub that clears everything.
2. **Server, right after `db push`** (SQL editor):
   - **The F-1 path (P-16).** `db push` printed `NOTICE: media_scan: new uploads reach the scan queue by …`. Confirm: `select public.get_identity_health() ->> 'media_scan_enqueue_path';` (service role) → `trigger` or `sweep`; `select tgname from pg_trigger where tgrelid = 'storage.objects'::regclass and tgname = 'enqueue_media_scan';` → one row on the trigger path; `select jobname, schedule from cron.job where jobname = 'enqueue-new-storage-objects';` → one row (`* * * * *`) on the sweep path, none on the trigger path. Either is correct; record which in the runbook. Cost if the sweep runs: one extra cron each minute.
     - **PF-M4.** The NOTICE's `why:` may say the sweep was chosen because `storage.objects was busy past the lock timeout` (`lock_not_available`), rather than `this role may not put a trigger on storage.objects` (`insufficient_privilege`). In that case run `select private.install_media_scan_enqueue();` again at a quiet time to get the trigger (it removes the sweep's cron on the trigger path), then re-check the queries above.
   - `select id, public from storage.buckets where id in ('safety-quarantine', 'avatars');` → `safety-quarantine | f`, and the profile-picture bucket (`avatars`, public). If profile pictures live in a bucket with another name, tell the developer: `private.media_scan_buckets()` must name it (P-17).
   - `select jobname, schedule from cron.job where jobname in ('scan-media', 'media-scan-retention');` → `* * * * *`, `27 4 * * *`.
   - Grants: `select has_function_privilege('anon', 'public.get_support_resources(text)', 'EXECUTE'), has_function_privilege('anon', 'public.load_support_resources(jsonb)', 'EXECUTE'), has_table_privilege('authenticated', 'public.safety_escalations', 'SELECT'), has_function_privilege('authenticated', 'public.record_inline_csam_match(text,text,uuid,text,text,boolean,text)', 'EXECUTE'), has_function_privilege('authenticated', 'public.complete_media_scan(bigint,text,text,text,uuid,text)', 'EXECUTE');` → `t | f | f | f | f`.
   - Grants, final fix wave (I-2, M-1): `select has_function_privilege('authenticated', 'public.mark_escalation_quarantined(bigint,text)', 'EXECUTE'), has_function_privilege('service_role', 'public.mark_escalation_quarantined(bigint,text)', 'EXECUTE'), has_function_privilege('authenticated', 'public.media_scan_enqueue_alerts_due()', 'EXECUTE'), has_function_privilege('service_role', 'public.mark_media_scan_enqueue_alerted(bigint[])', 'EXECUTE');` → `f | t | f | t`.
   - `select public.get_identity_health();` (service role) → the earlier keys plus `media_scan_enqueue_path`, `media_scan_enqueue_failures` (`0`), `media_scan_enqueue_read_failures` (`0`), `media_scan_pending`, `media_scan_oldest_pending_minutes`, `media_scan_skipped_7d`, `safety_escalations_open`, `safety_escalations_unalerted`.
   - **No storage policy reaches `safety-quarantine` (final review M-4).** The `avatars` bucket and its policies were made outside migrations (P-17), so a dashboard-made policy may lack a bucket test. Run `select policyname, roles, cmd, qual, with_check from pg_policies where schemaname = 'storage' and tablename = 'objects' order by policyname;`. Every row's `qual` or `with_check` must contain `bucket_id = '<a bucket>'` naming a bucket other than `safety-quarantine`, and no row may name `safety-quarantine`. The one-line check `select policyname from pg_policies where schemaname = 'storage' and tablename = 'objects' and ((coalesce(qual, '') || coalesce(with_check, '')) ~ 'safety-quarantine' or (coalesce(qual, '') || coalesce(with_check, '')) !~ 'bucket_id = ');` must return no row. Fix any row it returns before the switch-on (item 10). The local contract checks the same thing (`media_scan_contracts.sql` A, for client roles).
3. **Load the catalogue (each project; never by hand in the table).** From the repo root, with the project's two values exported in your shell for this command only: `SUPABASE_URL=https://<ref>.supabase.co SUPABASE_SERVICE_ROLE_KEY=<key> scripts/load_support_resources.sh` → `{"loaded": 4, "deactivated": 0, "catalogue_version": "2026-11-03.1"}`. Then `select public.get_support_resources('GH');` (anon is fine) lists Ghana Police DOVVSU and Find A Helpline. Every later catalogue change: edit the JSON, run the release check (`flutter test test/launch/support_resources_release_test.dart`), load again.
4. **The verification pass (W7a gate; P-4).** The DV professional and the cultural reviewer check and add, in `assets/support_resources/catalogue.json`, the rows for Ghana, the UK, the US and Canada in every category (emergency, dv, crisis, sexual_assault, sextortion including CSA 292 and StopNCII, child_safety, youth, lgbtq_legal, grief, perinatal), every other launch country's emergency number, and re-check the four carried rows; each row gets `verified_by` = the person's name and `verified_at` = the day checked, a new `catalogue_version`, and a new uuid per new row. Re-check within 7 days of each release (the release check fails a tag otherwise). The clinician reads the grief branch (Healing's "Someone I love died" and the grief view's copy, P-11). Then load it (item 3), and in production `select public.record_flag_gate_evidence('support_resources_v2', '<review ref>');` and switch the flag on.
   - **The release check's dates (PF-L6).** `test/launch/support_resources_release_test.dart` goes red for every build from 2027-02-02 by design (the catalogue is then too old), and a release tag goes red 7 days after a row's `verified_at`: 2026-11-11 for the rows shipped now. Re-verify, and bump `verified_at`, before each release.
   - **Names and copy for the reviewers (final review M-7).** The cultural reviewer: one screen has three names, "Safety resources" (Settings → Safety row, kept by P-12), "Find support" (Settings → Support) and "Support resources" (the screen's title and the manual); confirm or choose one. The clinician's grief-copy list adds the focused views' way out, now "Back" (`support_back`; the whole screen keeps v1's "Not relevant right now").
   - **The carried rows (PF-L11).** The four `carried-from-v1` rows pass the release check, so a tag isn't blocked by them; that is not a verification. `support_resources_v2` stays off in production until a named DV professional and the cultural reviewer have verified the rows (their names in `verified_by`).
   - **Device check (PF-H3).** On a real Android 11+ phone and an iPhone, Call opens the dialer with the number and Text opens the SMS app, from the confirmation; a phone with no SMS app shows the SnackBar.
5. **CSAM hash vendor (W7b gate; P-23, P-24).**
   - Contract and eligibility: PhotoDNA (recommended) or Thorn Safer; keep the agreement and the vendor's API reference with the runbook.
   - Development project (the stub secret is already set, item 1): deploy `scan-media`. End-to-end check: in the Storage dashboard upload `supabase/functions/scan-media/testdata/stub-match.gif` into `message-media` under a test folder; within two minutes `select status, vendor from private.media_scan_queue order by id desc limit 1;` → `match | stub`, `select kind, quarantined, status from public.safety_escalations order by id desc limit 1;` → `csam_match | t | open`, `select quarantine_path from public.safety_escalations order by id desc limit 1;` → `message-media/<path>/<match id>` and the copy is in `safety-quarantine` at exactly that path (one copy per match), `select count(*) from public.media_deletion_queue where object_name = '<path>';` → `1`, and the webhook (item 6) received "1 image(s) matched…". (A dashboard upload has no owner, so no hold: the contracts cover the hold.) The test file is the GIF signature followed by the stub's text (`GIF89aattune-csam-stub-match`, 28 bytes, not a viewable picture): scan-media reads the kind from the bytes, so it is scanned as an image. If the bucket's allowed types refuse `image/gif`, upload it under a `.jpg` name; the name doesn't matter. Then clean up the test rows (service role) and the quarantine copies under `safety-quarantine/message-media/<path>/`. Also check, in the function's logs, that each cron call answered `202` and that the run's own `scan-media stub development {…"match":1…}` count line followed it (the run continues in the background, B6 I-1).
   - Production (and the development project once the contract exists): `supabase secrets set CSAM_MATCHER=photodna PHOTODNA_SUBSCRIPTION_KEY=<key>` (and `PHOTODNA_URL` only if the vendor gives a regional endpoint; it must be https). The stub is refused in production whatever the secret says.
   - **PhotoDNA's limits (PF-L9).** Check PhotoDNA's size and type limits against what the app stores: its thumbnails and posters, profile pictures, story and chat images. scan-media sends the type it reads from the bytes. `PHOTODNA_TYPES` is JPEG, PNG, GIF, BMP and TIFF, so a WebP, HEIC/HEIF or AVIF object answers `unavailable` (`unsupported_type:…`), is retried, and after 24 hours becomes a `scan_failed` escalation. If the app stores any of those types, tell the developer before production. **Size (B6 I-2):** scan-media reads an image whole only up to `PHOTODNA_MAX_BYTES` = 4 MiB, a value taken as PhotoDNA's limit and not verified; confirm it against the contract. A larger image answers `unavailable:too_large` without being read, never clear, and becomes `scan_failed` after 24 hours. The app's own ceilings are higher: journal and planning images are allowed 10 MB, story images up to 5 MB. Either confirm that the app's uploads stay under the vendor's limit, or have the developer change the cap.
   - Only if Safer is chosen (P-24, B5 N-2): compare `saferMatcher`/`readSaferMatch` in `_shared/csam_matcher.ts` with Thorn's API reference (endpoint, auth header, request field, response fields) and have the developer adjust them and their tests before `supabase secrets set CSAM_MATCHER=safer SAFER_API_KEY=<key> SAFER_MATCH_URL=<https url>`. In particular, the adapter reads **any 2xx with empty `reasons` and `hashes` as clear**: confirm that Thorn never answers that way for a scan that isn't finished (an asynchronous 202, say). Otherwise a clear must require a 200 or a finished-status field.
   - Video (P-19): ask the vendor whether the contract includes video hashing; until then the runbook lists that videos are not hashed (their poster images are).
6. **`SAFETY_ALERT_WEBHOOK`** (set in W6a) must reach the named child-safety contact and a deputy, out of hours too: send one test post and confirm a person saw it. With it unset nothing is lost (escalations stay unalerted and show in `get_identity_health`), but nobody is told.
7. **Counsel (W7b gate).** The escalation runbook: who reviews a match and how fast (P0: hours), when and how to report (NCMEC CyberTipline, the IWF, Ghana's Cyber Security Authority, local police, per counsel and per country), how evidence is preserved, and what the reviewer does with a false match: resolve the `safety_review` hold (`update public.account_holds set resolved_at = now(), resolved_by = '<name>' where user_id = '<id>' and kind = 'safety_review';`); **restore the person's image (final review M-3)**: a quarantined match's original was deleted by the deletion drain within about 10 minutes, so put the evidence back with the service role: download it from `safety-quarantine` at `quarantine_path` and upload it to `<bucket>` at `<object_name>` (Storage dashboard), and check that the person's avatar or chat image shows again (the app's rows still name the original key; a server thumbnail of it, M-5, was deleted too and is not restored, so the chat shows the full image); **the restored bytes are queued and scanned again, and they will match again: close the escalation only after that re-scan has answered (re-review N-3)**. Wait until `select status, scanned_at from private.media_scan_queue where bucket = '<bucket>' and object_name = '<object_name>';` shows a `scanned_at` after the restore (a `match` on the still-open escalation is a harmless repeat: no new escalation, hold or deletion; closing first would make that re-scan a new escalation, a new hold and a new deletion of the restored image). Only then close the escalation (`update public.safety_escalations set status = 'closed', notes = notes || ' False match: restored <date>.' where id = <id>;`), and report the false positive to the vendor, since the same bytes will match on every later upload. For a match with `quarantined = false` the original was never deleted: resolve and close only. Quarantine retention: §4.8's default is one year after a report; counsel sets the rule per country. No purge job is built for `safety-quarantine` or `safety_escalations`; the runbook carries it.
8. **The named child-safety contact** reads `public.safety_escalations` (service role, SQL editor) on every webhook post and at least daily, finds the evidence at `quarantine_path` in `safety-quarantine` (exact; NULL when `quarantined = false`), and sets `status` (`reported`, `closed`) and `notes`. Nothing is ever reported automatically, and the uploader and the partner are never told.
   - **A row with `quarantined = false` (the copy failed; final review I-2).** The original is still in its own bucket (for `avatars` that is a public URL; in `message-media` or `story-media` the partner can still open it), and the evidence guard holds **every** deletion of it until the escalation is marked quarantined. Marking it `reported` or `closed` first does not delete it. In this order:
     1. Copy the original by hand (Storage dashboard or API, service role) to `safety-quarantine` at `<bucket>/<object_name>/<id>`, for example `message-media/chat-media/ab12.jpg/hand-1`.
     2. `select public.mark_escalation_quarantined(<escalation id>, '<bucket>/<object_name>/<id>');` (service role). It refuses with `media_scan:quarantine_copy_missing` until the copy is there, and with `media_scan:other_quarantine_path` if a later scan already recorded a copy (pass that `quarantine_path` instead). It records the path, marks the escalation quarantined and releases any held deletion; its answer's `released` says how many.
     3. `select public.queue_media_deletion('<bucket>', '<object_name>');` (service role).
     4. Check: `select not_before, deleted_at from public.media_deletion_queue where bucket_id = '<bucket>' and object_name = '<object_name>';` → `not_before` is not `infinity`, and `deleted_at` is set within about 10 minutes (the drain).
     5. Only then set `status` (`reported` or `closed`).
   - **Server thumbnails (final review M-5).** A match of a chat image or a couple's chat picture also queues the deletion of the thumbnails the server made of it (`chat-thumbnails/<uuid>.thumb` in `message-media`; `…/thumb-<uuid>.thumb` in `relationship-avatars`); the note says how many. If a thumbnail's own scan matches as well, its escalation names the original (in `notes`) and the original's uploader (`user_id`, held): review it with the original's escalation.
9. **Runbook lines (W7b).** The enqueue path recorded in item 2; the sweep's per-minute read of `storage.objects` (P-27) to revisit at scale; `media_scan_enqueue_failures` above 0 means uploads went unqueued (find the cause in the database logs). Each new failure is posted once to the webhook ("the CSAM scan queue failed to take uploads…", final review M-1); `media_scan_enqueue_read_failures` counts the sweep's or the reconcile's whole read of `storage.objects` failing, when nothing at all was queued (the sweep then keeps its watermark and reads the same window next minute; the daily reconcile queues the last 25 hours again); `media_scan_oldest_pending_minutes` growing means `scan-media` isn't running or the matcher is down; `media_scan_skipped_7d` counts videos (`video_not_hashed`, the video gap), vanished objects (`object_missing`), and objects that are neither image nor video by their bytes (`not_image_or_video`, `empty_object`: voice notes, documents), whatever mime the client declared. Also:
   - **Orphan copies.** A copy that timed out but finished later, or a match whose record call failed and was claimed again, leaves a copy under `safety-quarantine/<bucket>/<object>/` that no escalation's `quarantine_path` names. It is a duplicate, never lost evidence: it falls under the counsel's retention rule (item 7).
   - **Direct Storage removals.** The evidence guard on `media_deletion_queue` (B4 I-2) holds queued deletions only. Code that calls Storage `remove()` directly bypasses it, so any new code that deletes media goes through the deletion queue.
   - **scan-media's run time.**
     - scan-media answers the cron's call with 202 at once, and the run continues in the background (`EdgeRuntime.waitUntil`). pg_net gives up after 5 s, so a long run is never cut.
     - No job is claimed after 50 s, and every step of a job is bounded and aborted when its time is up: database and Storage calls 10 s each, the 4 KiB head 5 s, the image read 10 s, the matcher 16 s, the copy 24.75 s.
     - The last job therefore ends within about 126 s of the start, and the immediate webhook post is skipped (left to the 15-minute run) if the run is past 90 s, so the post ends by 140 s. Both are counted from before the environment read, and both stay at least 10 s under the 150 s edge limit.
     - Runs overlap, one starting each minute; the claim's lease keeps them apart.
     - A job claimed but not answered (a run that died) is claimed again after its 10-minute lease; after 24 hours it is failed and escalated.
   - **Throughput ceiling (B6 M-10).** A run scans at most 20 objects (`BATCH`), so about 20 a minute, or 28 800 a day. A sustained upload rate above that grows the backlog, shown by `media_scan_oldest_pending_minutes`. Anything still pending after 24 hours becomes `scan_failed`, so raise `BATCH` (up to 50) before that happens.
   - **Server thumbnails at scale (M-5).** A match of a thumbnail under `chat-thumbnails/` finds its message by reading `messages.media_thumbnail_url`, which has no index: one scan of `messages` per such match (rare). If `messages` grows past a few million rows, have the developer add an index on it (created concurrently, outside a migration).
   - **Duplicate posts (B6 M-6).** The same match or scan failure may be posted twice: by two overlapping scan-media runs, or by scan-media and the 15-minute run. A post is never missed. `public.safety_escalations` is the truth; count rows there, not posts.
10. **Production switch-on.** `select public.record_flag_gate_evidence('csam_hash_matching', '<ref>');` only after items 5-8, then `update public.feature_flags set enabled = true where key = 'csam_hash_matching';`.
   - **What is scanned from before the switch-on (final review M-2).** The trigger and the sweep queue only what is uploaded or changed after the switch-on (the sweep moves its watermark while the flag is off). The daily `media-scan-reconcile` (`41 4 * * *`, cron time, UTC on hosted Supabase) queues every object in the scanned buckets created or changed in the 25 hours before it runs, so its first run after the switch-on also scans uploads made before it: between about 1 and 25 hours of them, depending on how long before 04:41 the flag went on. Everything older, the existing production corpus, is never scanned. **Owner decision:** whether to scan that corpus once (a one-off backfill: a variant of `reconcile_media_scan_queue` with a wider window, run in batches); ask the developer, it is not built.
   - **Production smoke check (final review M-1),** the same day:
     1. On development first (stub matcher, item 5), the known test-hash upload end to end: upload `stub-match.gif`, then confirm the `match | stub` queue row, the `csam_match` escalation with its `quarantine_path`, the deletion row, and the webhook post, as item 5 lists.
     2. In production, upload one ordinary, known-benign JPEG (a photo you took) to a test chat. Within 2 minutes `select status, vendor from private.media_scan_queue order by id desc limit 1;` → `clear | photodna` (or `safer`).
     3. Then `select public.get_identity_health();` (service role) → `media_scan_enqueue_path` set, `media_scan_enqueue_failures` and `media_scan_enqueue_read_failures` `0`, `media_scan_pending` small and `media_scan_oldest_pending_minutes` under 5. Read it again the next day, after the 04:41 reconcile: still `0` failures. A `pending` row that stays, or any failure count above 0, means production may be scanning nothing: tell the developer the same day (switching the flag off is not a fix; nothing would be scanned at all).
11. **Owner decisions to confirm** (the plan built the recommendation): P-17 (`avatars`), P-18 (an unquarantined match keeps the original), P-19 (video skipped, posters scanned), P-23/P-24 (PhotoDNA first; Safer unconfirmed), P-4 (the shipped catalogue is the v1 list plus the directory), P-14 (the v1 screen's overflow, left as is behind the flag).
12. **Dating stays off in production (PF-H2).** `dating-profile-photos` is not scanned by the queue (spec I-10). Dating stays off in production until `process-dating-photo` calls the matcher and then `record_inline_csam_match` with all 7 arguments, including `p_quarantine_path` (through `_shared/csam_match_path.ts`'s `inlineRecorder`), before a photo is approved. This is a Spec 2 follow-up and it gates Dating's production flag.
13. **Theme contrast (owner item, B2).** The app's light-theme `colorScheme.error` / `onError` pair is 3.68:1, below 4.5:1, everywhere it is used. W7's "Exit now" button uses its own darker red (6.54:1), and the theme itself is unchanged. Decide whether to change the app's light error colour, which would be an app-wide visual change with its goldens.

## Spec coverage (self-review)

| Spec item | Where |
|---|---|
| §1.3 Q1 (W7 worldwide, not country-gated) | the whole plan; the directory serves any country, with the fallback (Task 3) |
| §1.5 never touch (Games, Opinions, latch, SOUL/THESIS, quick exit) | Global Constraints; Task 4 Step 8, Task 8 Step 7 |
| §2.1 copy (`support_*`, `flow_*`; the partner never named) | Task 3 Step 3 (P-11) |
| §2.2 never animated (support, report sheets) | Task 3 (`nothing moves and quick exit is in reach`; the 400 ms wait) |
| §2.3 accessibility (AllowLargeText, goldens 1.0/1.3/2.0/RTL, guidelines) | Tasks 3, 4 |
| §2.5 `support_resources_v2` (client, anon), `csam_hash_matching` (scan-media, trigger or sweep); production refuses the stub | P-2; Task 3 (`flag off: today's screen`), Task 5 (B, D, F with the flag off), Task 6, Task 8 |
| §3.6 X1 youth link | Task 4 (P-8) |
| §3.10 Healing: "A breakup" / "Someone I love died" + journal | Task 4 (P-9), Task 3 (grief view) |
| §4.2 `support_resources`; loaded by the script from the bundled file | Tasks 1, 2 (P-3, P-4) |
| §4.2 `media_scan_queue` (with `source`), `safety_escalations`, `safety-quarantine` | Task 5 (P-19, P-21, P-25) |
| §4.3 W7a `get_support_resources` (anon; emergency first) | Task 1 (contract B, mutants) |
| §4.3 W7b `enqueue_media_scan`, `claim_media_scan_jobs`, `private.handle_csam_match`, `complete_media_scan` (back-off, 24 h, failed + escalation), `record_inline_csam_match`; no `media_scan_status` | Task 5 (P-18, P-20) |
| §4.4 `enqueue_media_scan` (flag, buckets, never dating, image/video, exception guard), F-1 spike and sweep, bootstrap stub | Task 5 (P-16, P-17, P-26) |
| §4.5 `scan-media` (claim, download, matcher, stub refused in production, quarantine first, webhook, video gap, inline helper) | Tasks 6-8 |
| §4.6 crons `scan-media`, `media-scan-retention`, `enqueue-new-storage-objects` (fallback only) | Task 5 (contract A, E) |
| §4.7 #14, #15 | Task 1; Task 5 (as two files, P-15) |
| §4.8 retention (queue 7 days after clear; matches with the escalation; evidence per counsel) | Task 5 (contract J); checklist 7 |
| §5.1/§5.2 files (`support_resources_v2_screen.dart`, `support_resources_repository.dart`, `catalogue.json`, `csam_match_path.ts`, `safety_resources_screen.dart`, `settings_data.dart` Support, `app_router.dart`, user manual, `local_pg_*`) | Tasks 1-5, 7 |
| §5.3 `supportResourcesV2Provider`, `supportResourcesProvider(country)` | Task 3 |
| §5.4 the support screen keeps `RouteNames.safetyResources` | Task 3 (P-7) |
| §7.1 `support_resources_contracts.sql`, `media_scan_contracts.sql` (every listed case) | Tasks 1, 5 |
| §7.2 `scan-media` (stub match/clear/unavailable, quarantine before removal, production), `csam_match_path.test.ts` (both entry points) | Tasks 7, 8 |
| §7.4 mutants: `dating-profile-photos` re-added, exception guard dropped | Task 5 Step 7 (`dating_bucket`, `no_guard`) |
| §8 W7a contents (country line and picker, emergency first, tap-to-call confirmation, categories, "Not the police", unsupported fallback, offline catalogue, grief branch, youth link, release check) and gate | Tasks 2-4; checklist 4 |
| §8 W7b contents (F-1 spike, migration 15, scan-media, matcher, match path, quarantine, escalations) and gate | Tasks 5-8; checklist 2, 5-8 |
| §9 risks (upload blocked or trigger impossible; dating scanned twice; false match) | Task 5 (C, E, B, H); checklist 7 |
| §10 outside parties (counsel, cultural reviewer, DV specialist, clinician, CSAM vendor, named child-safety contact) | checklist 4-8 |
| §11 I-10, F-1 | Task 5 (P-16), Task 7 |

Placeholder scan: no "TBD", "TODO", "later", "similar to" or undefined name; every code step has its full text; the `<key>`, `<ref>`, `<id>` and `<path>` in the owner checklist are values only the owner has. Type consistency: `SupportFocus`, `supportResourcesSetting`, `openHealingOrGrief`, `griefSupportLocation`, `youthSupportLocation`, `quarantineAndRecord`, `queuedRecorder`, `inlineRecorder`, `CSAM_MATCH_ESCALATIONS`, `SCAN_FAILED_ESCALATIONS`, `p_quarantined` and every SQL signature are used as they are defined (each file was compiled, type-checked or applied while writing this plan).

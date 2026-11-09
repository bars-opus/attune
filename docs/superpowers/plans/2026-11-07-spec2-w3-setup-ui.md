# Spec 2 W3 (Dating setup UI) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

## Plan fix round 1 (2026-11-08)

The pre-flight review (`.superpowers/sdd/2026-11-07-spec2-w3-setup-ui/preflight-review.md`, NOT READY: C2 I14 M13) ran this plan in a scratch copy. This round fixed every finding and then **re-ran the whole plan from the repo's tree** in a fresh scratch worktree (every "Create … with exactly" block, edit script, heredoc, `arb_append.py`, `gen-l10n` and `dart format` line, task by task), with the SQL on a clone of `attune_spec3a`. Verified: the six migration files apply twice with exit 0; the wrapped SQL suite reads **159 PASS / 14 FAIL, no new FAIL** after W3a, W3b and W3c; every SQL mutant (T3 18, T5 m4/m7 2, T5b 4 + the planned `lists_no_device` equivalent, T8 21) dies; the race script passes 20/20; Deno 32/32; `flutter analyze` reads **571 issues, no new one**; the Dart mutants die (T2 11, T4 12, T6 9, T7 11, T10 12, T11 15, T12 12) and every anchor is exact against the formatted files; the large-text audit at 2.0 reads 0 sites; the full `flutter test` run reads 7,542 passed against the untouched tree's 7,280, with the same 19 failures in both (scratch-copy artefacts: the copy has no `android/`, `ios/` or `docs/`), so no new failure. Owner decisions 2026-11-07: R-5, R-18 and R-22 approved.

| Finding | What changed |
|---|---|
| C-1 | Task 2's `edit_T2.py` points Spec 1's slot button at `DatingPaths.step('how')` (and drops its now-unused `RouteNames` import) before `RouteNames.datingMode` goes; the shared table says `dating_slot.dart` is 2 (one line), 4 (body). |
| C-2 | `get_dating_home()` carries `has_data` in every answer (R-43; `private.dating_has_data`, contract section F, mutants `home_no_has_data`, `has_data_never`); `DatingHome.hasData`; every section card, `_plain` included, links to Dating settings with Dating data (tests for all 14 states, mutant `plain_no_settings`); settings is a non-lazy Column, so Clear and Leave are always built; Leave shows with any data (R-41, tests for all 14 states, mutant `leave_ignores_data`). |
| I-1 | Every call and its read-back are separate statements (T3 sections C and D; W3c sections Q and R). |
| I-2 | Task 3 turns `dating_mode_contracts.sql` section 1 into "authenticated is refused" (`edit_contracts_T3.py`). |
| I-3 | Task 5's `edit_contracts_T5.py` makes `country_safety_config_contracts.sql`'s GH and GB version pins relative, and its orphan probe restores the row that was current. |
| I-4 | W3b ids `a0`–`a2`, W3c ids `b0`–`b8` (none used by the file, checked by listing every fixture id it creates); unique phones; a UK phone for section N's Tier 3 person (the +1 555 phones have no country, which had let `lists_note_any_tier` survive); section N reads GB and GH only. |
| I-5 | `setup_W3c.sql` defines `pg_temp.as_person` / `pg_temp.as_db`. |
| I-6 | `edit_T8.py` flips W1's N-I1 pin: the v2 intent and insert RPCs are the app's; no client writes the intent table, and no other client function does. |
| I-7 | `mutate.py` is W3's own (Task 1 creates it): an optional grants twin runs after each non-RAW mutant (Tasks 3, 5, 8 pass it), and `W3_DB` may name a scratch clone; `owner_read_kept` is a RAW mutant that puts the policy and grant back. |
| I-8 | The section keys its `AnimatedSwitcher` by account; new tests: a refused Resume and a failed refresh never carry to the next account or frame (they also kill `d8_taps_carry_over` and `stale_after_error`). |
| I-9 | `write_slot_T4.py` imports `HomeSnapshot` from `home_state_providers.dart`; the slot test imports the real `relationship_lifecycle_providers.dart`. |
| I-10 | Every "Create … with exactly" Dart block is now the formatter's own output (so each task's `dart format` is a no-op); edited files are never formatted again; `edit_T11.py`'s anchor and the T6, T7, T10, T12 mutant anchors are the formatted text (`dmut.py --check` verifies every anchor before a run; `dmut.py` also reports a mutant that doesn't compile as COMPILE, not a kill, and takes multi-edit mutants). |
| I-11 | `where_step.dart` promotes `country`; `SemanticsFlag` and `CustomSemanticsAction` imported; `datingDropTimes` is `final`. |
| I-12 | All screen tests pass as written: a pump between taps that change state; `lastWrite` (not the profile re-read) in the setup fake; real file I/O settled in D9's add tests (`_settleIo`); the "Add photo" link tapped, not the slot text; D6's adjustable has `value`; the D13 PIN set after `pumpFlowScreen` empties the keystore mock; settings' switches are `SwitchListTile`s (semantic labels); route tests read the screen shown (a push doesn't change `currentConfiguration.uri` in go_router 10); the settings and Leave screens are Columns in a scroll view; D2's separated sheet scrolls. New tests kill the T7 survivors (`d5_offcountry_sends_pronouns`, `d5_unknown_rule_on`) and the T12 one (`docs_ungated`). |
| I-13 | The boundaries test asserts no `features/dating` import and no `Dating[A-Z]…` identifier, so the comment "the Dating lock" passes. |
| I-14 | The orphan sweep (R-46): `claim_dating_orphan_uploads` / `record_dating_orphan_scan` (service role), cron `sweep-dating-photo-orphans`, `sweepOrphan` in `process-dating-photo` (CSAM first; clear → deleted; a match → Spec 1's inline record, which keeps the original when the quarantine copy failed; an error → released, retried); contract section U, six SQL mutants, three Deno tests and a Deno mutant. Nothing is deleted unscanned. |
| M-1 | Task 1's `dart format` names the six new files (no pre-existing model is reformatted). |
| M-2 | The three changed lines without the marker carry it; the check prints `0` three times. |
| M-3 | Expected lines name the four mutants that die at a raw error or a constraint (`request_unvalidated`, `m7_identity_raises_not_available`, `replace_keeps_old`, `caption_unbounded`); `prompt_four` now compiles. |
| M-4 | One name, `privacy_allowlist.test.ts`. |
| M-5 | File map and tables corrected (`dating_list_names.dart` is Task 4's; Task 7's files; two race cases; Task 5's format note). |
| M-6 | `why_reads` and `d5_why_reads` are real two-edit mutants. |
| M-7 | No new analyzer issue (unused imports, `avoid_renaming_method_parameters`, braces, `_known` cleaned). |
| M-8 | The push key is its own secret and fails closed (R-44; contract case, mutant `push_key_fallback`; race step sets it on the scratch copy; owner deploy item). |
| M-9 | Bounded retry → `dating:busy` on the intent insert and the reorder (R-47). |
| M-10 | 20 notice requests a day (R-45; contract case, mutant `request_unlimited`). |
| M-11 | Checked: `MyDateFormat.toDate` is `yMMMMEEEEd` ("Tuesday, December 1, 2026"), so the cool-off line has its weekday; no change. |
| M-12 | Owner checklist 7 carries the guided-date private reflection to W6. |
| M-13 | Record-with-Map comparisons split into `.$1` and `.$2` (Tasks 1, 5). |

New rulings: R-43 (`has_data`), R-44 (push key), R-45 (notice rate limit), R-46 (orphan sweep), R-47 (lock retries); R-41 restated.

**Goal:** Build the whole Dating setup surface on the W1/W2 server: the Dating section inside Me (driven by `get_dating_home()`), the `/dating/*` route group behind the Dating lock, the RPC-only repository, the neutral `me_update` push, "Tell me when it's here", D1–D13, the CSAM-first photo pipeline, Dating settings with pause and leave, and the rewritten manual topic; with every client `SELECT` on a Dating table revoked and the `get_dating_eligibility()` shim dropped.

**Batch summary (one paragraph).** W3 is large (12 tasks, 3 migrations, 14 screens, one edge-function rewrite); it stays one file, and each batch ships on its own (Dating is off in production; each batch's gate is green before the next starts, and a step the next batch builds simply sends the person back to Me). **W3a** (Tasks 1–4) → migration `20261107150000_dating_v2_client_reads.sql` (+ `…150010_…_grants.sql`): the Dating data layer and providers (Task 1); the route group, the lock redirect, `me_update` push routing, the one device-wipe line, D0 routed and every v1 Dating screen removed (Task 2); the migration — notify-request RPCs, the neutral push queued by `publish_country_config`, the owner-read policies and `20260811120000` grants revoked, `get_dating_eligibility()` dropped, `get_dating_home` v2, the reflection trim (Task 3); `DatingSection` in Spec 1's slot, the §3.10 not-open screens and the Dating settings shell, and the W3a gate (Task 4). **W3b** (Tasks 5–7) → migration `20261107160000_dating_v2_setup_lists.sql` (+ twin): faith and denomination lists published, `get_dating_setup_lists()`, every region/side/faith name in the app (Task 5); the step frame and D1–D4 (Task 6); D5–D8 with the off-country screens, the "Why?" sheet, the support sheet and the country note, and the W3b gate (Task 7). **W3c** (Tasks 8–12) → migration `20261107170000_dating_v2_photos.sql` (+ twin): photo positions 1–6, captions, `csam_state`, child-label config, the v2 photo RPCs, the storage policies moved onto definer predicates and the last two client grants revoked (Task 8); `process-dating-photo` CSAM-first with child labels and slot reasons, `upload-dating-photo` removed, the image preparer at 1600 px (Task 9); D9 and D10 (Task 10); D11's shell, the introduction card, D12 and D13 (Task 11); full Dating settings with pause and leave, the Leave screen, the manual topic and its flags, and the W3c/W3 gate (Task 12).

**Architecture:** Server first inside each batch where the client needs it, else client first (W3a: the client stops reading tables and calling the shim *before* the migration revokes and drops them, R11/R21). Every re-created SQL function is generated by a script from its LIVE body (`pg_get_functiondef` on `attune_spec3a`) plus the replacements this plan names, each marked `-- Spec 2 W3a|W3b|W3c`; every new function is `SECURITY DEFINER SET search_path = ''`, pre-validates its input and answers `{ok:false, reason}` instead of raising with the input. The app keeps all Dating state in account-keyed, `autoDispose` Riverpod providers (D8) and route-scoped widgets, nothing on disk (D20, C-5); the `/dating` route group's single redirect enforces sign-in and the Dating lock for every screen, deep link and push tap.

**Tech Stack:** Supabase Postgres 17 (RLS, `SECURITY DEFINER`, `pg_net` trigger unchanged), psql, Python 3 (edit, build and mutation scripts), Deno 2.8.1 (edge function tests), Flutter 3.29.1 / Dart 3.7 / Riverpod 2.6.1 / go_router 10.2.0, `uuid`, `image`, `image_picker`, `connectivity_plus` (all already dependencies). No new package.

**Spec:** `docs/superpowers/specs/2026-10-24-dating-mode-design.md` — §8 W3 (W3a, W3b, W3c contents, dependencies, tests, gate); §3.0, §3.1, §3.2 D0–D13, §3.8, §3.10, §3.12, §3.13 (W3a part), §3.14, §3.15; §2.4 (off-country rules, kill-switch note), §2.7; §4.1, §4.3 (`dating_profile_photos`, `dating_photo_moderation_config`, `dating_notify_requests`), §4.4, §4.5, §4.7 (`process-dating-photo`, `upload-dating-photo`), §4.9 W3a/W3b/W3c, §4.10 (every row tagged W3); §7.1 (`dating_v2_setup_contracts.sql` W3b/W3c rows), §7.2 S3/S17/S19/S22, §7.3 (`process-dating-photo`), §7.4, §7.5 mutants 4 and 7, §7.7; §9 R1, R2, R3, R11, R14, R16, R21. `docs/superpowers/specs/2026-10-24-app-flow-identity-design.md` §3.9 (Me slot, Dating lock), §3.11 (`/home?tab=me`), §5.5 (S19 allow-list), §5.8 (device wipe registry), D15, D19, D20. `docs/superpowers/specs/2026-10-24-cross-spec-review.md` I-4, I-9, I-10, A-7, A-10, A-11, C-5, R-5, W-2. Carries: `.superpowers/sdd/2026-11-07-spec2-w3/carries.md` (all 15, mapped below). Format reference: `docs/superpowers/plans/2026-11-07-spec2-w2-gentle-wait.md`.

## Global Constraints

- **Where and how.** Work in the main working tree on `main` (`/Users/user/attune`). HEAD is `62839cce` (S2 W1, W2, S1 W9d committed). The owner may have uncommitted edits (`supabase/.temp/cli-latest`, `backup-before-planning-p2.sql`): never revert, stash, stage, checkout or reformat them. Every edit to an existing file is an exact replacement made by a script that asserts each anchor occurs once; if an anchor moved because a later fix changed it, apply the same change to the current text and say so in the task report.
- **NO commits.** No `git add`, `git commit`, `git stash`, `git checkout`, `git reset`, `git rm` (delete files with `rm`). Where a skill says "commit", instead: **do not commit; record the tree in the report** with `T=$(mktemp -u); GIT_INDEX_FILE=$T git read-tree HEAD && GIT_INDEX_FILE=$T git add -A && GIT_INDEX_FILE=$T git write-tree; rm -f $T` (a private index; the real index is untouched). The controller commits only when the owner approves.
- **Formatting.** Never `dart format` a pre-existing file (the repo uses an older formatter; formatting reflows it). `dart format` only the files a task creates. A later task that edits a file an earlier W3 task created writes its edit in `dart format` style by hand and does not run the formatter on it.
- **SQL target.** Contracts run only on `attune_spec3a`, from the repo root. A file with a top-level `BEGIN;` runs as `psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f F`; one without runs wrapped: `psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -c 'BEGIN' -f F -c 'ROLLBACK'` (Task 1's `suite.sh` does both). Migrations and their grants twins are applied with `psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f <file>`. Confirm the target first (`psql -X -d attune_spec3a -Atc 'select current_database()'` prints `attune_spec3a`). **NEVER `attune_test`. NEVER run `scripts/local_pg_setup.sh` or `scripts/local_pg_grants.sql`** — but DO append each new twin's `\i` line to `scripts/local_pg_grants.sql` (Task 1's `grants_line.py`). Mutants run inside one transaction that the contract's own `ROLLBACK` ends (`mutate.py`). Scratch databases only if the task creates and drops them; the race script refuses `attune_spec3a`.
- **Migrations.** `20261107150000_dating_v2_client_reads.sql`, `20261107160000_dating_v2_setup_lists.sql`, `20261107170000_dating_v2_photos.sql`, each with its `…10` grants twin, later than every file in `supabase/migrations/` (the newest is `20261107140010_dating_v2_home_grants.sql`). If `ls supabase/migrations | sort | tail -1` shows anything at or after `20261107150000` when Task 3 starts, shift all six to the next free hours keeping their order and change every header, `\i` line and command. Each file is one `BEGIN; … COMMIT;`, idempotent (applied twice, `exit=0` both times), with `SET LOCAL lock_timeout = '5s'`. Every new function: `SECURITY DEFINER SET search_path = ''`, fully-qualified names, `REVOKE ALL … FROM PUBLIC, anon` and `service_role` unless the spec gives it the service role, `GRANT EXECUTE … TO authenticated` only for the §4.4 client RPCs, every grant/revoke in the twin (the migration also revokes server-only objects). Re-created functions start from their LIVE body and change only lines marked `-- Spec 2 W3a|W3b|W3c` (each task diffs them). Pre-validate input so no raw constraint error echoes input; NULL never counts as eligible (`IS DISTINCT FROM`, `IS NOT TRUE`, `coalesce`). Shared lock order for every writer that can meet the country switch: per-person setup lock (`private.dating_lock_setup`) → the country's same-gender lock → the profile row `FOR UPDATE`, with a bounded 40P01/55P03/40001 retry (3) and then `dating:busy`. Exposure-reducing changes are never gated (clearing a reflection, cancelling a notice, deleting a photo, skipping faith, pausing, leaving); deletion is never blocked. No `CREATE INDEX CONCURRENTLY`; no function names a table a later wave creates.
- **Production stays off.** No Dating flag turns on in production; no migration turns a flag on or sets `attune_environment`. `supabase/sql/dev_enable_spec2_dating_flags.sql` already turns every Dating flag that exists ON in development; W3 adds no flag, so it is unchanged (Ruling R-34).
- **Copy.** New strings go into `lib/i10n/app_en.arb` under `dating_` only through `python3 -I .superpowers/sdd/2026-10-26-spec1-w3/arb_append.py <fragment>`, then `flutter gen-l10n --arb-dir=lib/i10n --template-arb-file=app_en.arb --output-dir=lib/i10n/generated --output-localization-file=app_localizations.dart --no-synthetic-package`. Straight apostrophes only; any `\u` escape is written by a script, never by hand. Copy names people, never "they" for the partner or another person ("{Name}", "you both"). Every displayed date goes through `MyDateFormat` (`toDate`, `toTime`, joined with `MyDateFormat.join`). Exact spec strings are copied verbatim; strings this plan adds are listed for the owner's reviewers (Owner checklist).
- **UI.** Every Dating screen and sheet is under `AllowLargeText` (screens through `FlowFrame`/`DatingStepFrame`; sheets wrap their body); `InfoRowWidget` and `BottomSheetUtils` already scale — never scale per caller. Error red is `#C62828` (`AppColors.error`), and errors are icon-plus-text (`FlowErrorLine`) announced as live regions. Goldens at 1.0, 1.3, 2.0 and RTL (`expectFlowGoldens`), the three guidelines (`expectFlowGuidelines`). Taps in widget tests use `tapInReach` (`test/helpers/tap_in_reach.dart`); a missed tap is a failure (the large-text audit counts it). Touch targets ≥ 44 dp; every control has a semantic label. Motion per §3.0/§3.15 (shared-axis X on forward steps; none on D0, D4, notes, not-open, leave; 150 ms fade under reduce motion).
- **D8 shared phones.** Every Dating provider is keyed to the signed-in account (`FutureProvider.autoDispose.family<…, String?>` on `datingAccountProvider`) and every screen clears its typed state on an account change; tests hold the next account's read open and assert every frame shows nothing of the last account.
- **D20 / C-5.** Nothing Dating is written to `SharedPreferences`, secure storage (except Spec 1's `me_section_lock`), files, the image disk cache or the gallery; no key, value or file name the app writes contains "dating" (any case). Photo temp files are neutral-named and deleted after upload.
- **Off limits.** In-chat Games (`test/architecture/games_untouched_test.dart` stays green), Opinions (unchanged), `ATTUNE_SOUL.md`, `ATTUNE_THESIS.md`, `lib/home/home_screen.dart` and its latch (byte-identical; Task 1 saves its hash), `quick_exit_service.dart`, `auth_provider.dart`, `lib/main.dart`, `set_user_path_internal`, `get_public_app_config()`, every applied migration, every Spec 1 Me file except `dating_slot.dart`, every edge function except `process-dating-photo`, `upload-dating-photo` (removed) and the one-line allowlist in `process-scheduled-notifications`. **No deploys** (`supabase db push`, function deploys and app builds are the owner's; Owner checklist). Don't read `.env*`, credentials or the keychain.
- **Gates, every batch (Tasks 4, 7, 12).** (1) The wrapped SQL suite on `attune_spec3a`: no new FAIL against Task 1's two baseline runs (baseline **158 PASS / 14 FAIL**; after W3a **159 / 14** — `dating_v2_client_reads_contracts.sql` is new — and still 159 / 14 after W3b and W3c, whose rows extend existing files). (2) Full `flutter test`: no failure beyond the two known pre-existing ones (the `planning_recent` clock flake; baseline `+7299`) — the count moves by the tests each task removes and adds, listed per task. (3) `flutter analyze --no-pub lib test`: 571 issues, 0 errors, 0 new (compared line-insensitively against Task 1's saved list). (4) `shasum -c .superpowers/sdd/2026-11-04-spec1-w10-accessibility-docs/w10-1.0.sha` and `shasum -c .superpowers/sdd/2026-11-04-spec1-w9/flag_off.sha`: every line `OK`. (5) `scripts/concurrency/dating_kill_switch_races.sh` on a scratch DB built from `pg_dump -s attune_spec3a` (plus the config tables' data, R-33), dropped after: every case `PASS`. (6) Each task's named mutants all red, with the RED line quoted in the report. (7) `test/architecture/games_untouched_test.dart` passes; `shasum -c $D/latch.sha` OK. The known `together_rituals_contracts.sql` clock failure is one of the 14 baseline FAILs.

## Review Focus

1. **Another account signs in on a shared phone mid-setup** (D8). Expect no frame of D3/D5/D6/D8 or the Dating section to show the first account's answers, typed text or home state, also while the next account's read is held or fails. Tests: Task 1 (`datingHomeProvider: the next account starts empty`), Task 6 (`D8: switching accounts on D2 clears the typed answer and holds the next read`), Task 7 (`D8: D5 shows nothing of the last account while the next read is held`).
2. **200% text on every setup screen** (R14, §3.0). Expect every action reachable (scrolling), nothing clipped, the step counter and Skip still visible. Tests: each screen's `expectFlowGoldens` at 2.0, plus `python3 scripts/large_text_audit.py --scale 2.0 test/features/dating` with `0 site(s) to fix` in Tasks 4, 7, 10, 11, 12.
3. **An off-country (Ghana) person never calls a same-gender setup RPC and the "Why?" sheet calls nothing** (§2.4, 10 S3, §7.4). Expect D5 to offer only Woman/Man, D6 no choice, and zero RPCs from the sheet. Tests: Task 7 (`off-country: the Why? sheet makes no request`, `off-country: D5 and D6 never send a same-gender set`), Task 5 contract A rows re-run with mutants 4 and 7.
4. **A photo that matches the CSAM list** (I-10, §3.2 D9). Expect the matcher to run first and exactly once, the bytes quarantined, Spec 1's inline-match function called once, Vision never called, the slot to read only "Photo {n} can't be used.", and a matcher error never to approve. Tests: Task 9 Deno (`a match: quarantined, recorded once, Vision never called`, `a matcher error leaves the photo unapproved`), Task 8 contract (`csam hit: rejected/unsafe and one moderation hold`).
5. **A deep link or a push tap into Dating while the Dating lock is on** (§3.0, §3.14, §3.13). Expect `/dating/*` to ask for the Safety PIN first, `me_update` to open Me with the locked row, and the unlock to end when the app is put away. Tests: Task 2 (`a deep link to a step asks for the PIN first`, `me_update opens Me`, `the unlock ends when the app is hidden`), Task 4 (`with the lock on, Me shows the locked row`).

## Pre-flight (read before Task 1)

### Shared files and interfaces between tasks

| File or interface | Tasks | Rule |
|---|---|---|
| `lib/i10n/app_en.arb` + `lib/i10n/generated/*` | 2, 4, 5, 6, 7, 10, 11, 12 | each task appends its own fragment (`arb_fragment_T<n>.txt`) with `arb_append.py`, then gen-l10n; Task 2 also deletes `dating_dashboardFallbackReason` by script |
| `lib/features/dating/data/{dating_rpc,dating_home,dating_providers}.dart` | 1 creates; 2, 4, 6, 7, 10, 11, 12 consume | names in "Interfaces this plan produces" |
| `lib/features/dating/routes/dating_routes.dart` | 2 creates; 4 adds `settings`, `not-open`; 11 passes `from` to the step route (R-40); 12 adds `leave` | one `GoRoute` added per screen, inside the `/dating` group |
| `lib/features/dating/routes/dating_setup_steps.dart` (`datingStepScreen` switch) | 2 creates (`wait`); 6 (`how`…`privacy`), 7 (`you`…`faith`), 10 (`photos`, `prompts`), 11 (`verify`, `preview`, `ready`, and `from` in `DatingSetupStepRoute`, R-40) | `case` lines only, except Task 11's `from` |
| `lib/features/dating/settings/dating_settings_screen.dart` | 4 creates (shell); 12 extends | rows at Task 4's marker in §3.12 order; Pause/Resume and Leave after the last row |
| `test/architecture/text_scale_routes_test.dart`, `lib/app/text_scale_policy.dart` | 2 (prefix + 2 names, 7 v1 names out), 4 (+2), 12 (+1) | names only |
| `supabase/tests/dating_rls_canary.sql` | 3, 5, 8 | each adds a section above the "Checks" line; W3a also updates four W1 rows and deletes the shim row |
| `scripts/local_pg_grants.sql` | 3, 5, 8 | one `\i` block each, by `grants_line.py` |
| `supabase/tests/dating_v2_setup_contracts.sql` | 5 (W3b sections), 8 (W3c sections, G3 update) | sections appended before the final `ROLLBACK;` |
| `supabase/tests/dating_v2_home_contracts.sql` | 3 | the `pg_temp.home` helper strips the W3a keys (`notify`, `can_shorten`, `has_data`, `first_drop_at`); H9's reflection-readers pin names `private.dating_has_data(uuid)` (R-43) |
| `supabase/tests/dating_mode_contracts.sql` | 3 (section 1), 8 (fixture line) | section 1's owner-RLS reads become "authenticated is refused" (R11, I-2) |
| `supabase/tests/dating_v2_eligibility_contracts.sql` | 3 | section F (the shim) becomes "the shim is gone" |
| `supabase/tests/storage_bucket_policies.sql` | 8 | the two policy hashes |
| `scripts/concurrency/dating_kill_switch_races.sh` | 3 | two cases (notice vs publish, both orders) |
| `lib/features/dating/gentle_wait/gentle_wait_screen.dart` (W2) | 2 | carry 7 states; no other change |
| `lib/app/routing/app_router.dart`, `notification_config.dart`, `lib/app/device_wipes.dart` | 2 only | R1, R2, R3 |
| `supabase/tests/{dating_v2_setup_contracts,dating_v2_identity_contracts,dating_v2_home_contracts,dating_mode_contracts,identity_foundation_contracts}.sql` | 8 | one transaction-scoped `ALTER … csam_state SET DEFAULT 'clear'` line after each file's top-level `BEGIN;` (R-24: their approved-photo fixtures stand for scanned photos); nothing else |
| `test/features/dating/routes/dating_routes_test.dart` | 2 creates; 11, 12 add one test each | appended before the final `}` |
| `test/features/dating/support/dating_photos_fakes.dart` | 10 creates; 11 adds `FakeDatingPreviewGateway` | appended |
| `lib/app/documentations/user_manual/data/{manual_documentation_registry,documentation_flags}.dart`, `test/app/documentations/{documentation_registry_flags,manual_content_guard}_test.dart` | 12 only | one entry or line each (R-35) |
| `lib/features/me/presentation/widgets/dating_slot.dart` (Spec 1) | 4 only | the slot body renders `DatingSection` |
| `get_dating_home()` payload | 3 changes; 1, 4, 6 read | keys in Task 3's contract |

### Carries → tasks

| # | Carry (`carries.md`) | Where |
|---|---|---|
| 1 | `path_not_dating` → "choose Dating" state | Task 1 (`DatingLifecycleError.pathNotDating`), Task 4 (section resume copy + link), Task 12 (settings resume; test `resume on a path that is not Dating`) |
| 2 | a failed path pause waits ≤ 15 min for the sweep | Ruling R-15 (no W3 screen claims an instant pause) |
| 3 | Spec 1's slot still shows a wait after both seal | Task 4 (`DatingSection` from `get_dating_home`; test `both sealed: no wait card`) |
| 4 | undated ending: `active` in home while candidate refuses | Task 3 (home v2 → `unavailable`; contract B2; mutant `home_active_ignores_candidate`) |
| 5 | "Clear my answers" reachable in any home state | Task 4 (Dating settings row; test) |
| 6 | D0's route; quick-exit wipe if kept mounted | Task 2 (`/dating/setup/wait` behind the lock; R-9 wipe entry; shell test `quick exit from D0 on the real route`) |
| 7 | harden the reflection trim; map `unavailable`/`notEligible`/`reverify` | Task 3 (server `private.dating_trim`), Task 2 (D0 client states) |
| 8 | home `can_shorten` | Task 3 (gentle_wait payload), Task 4 (the section never promises a shorter wait) |
| 9 | a reason for every pause, NULL included | Task 4 (`DatingPauseReason.unknown` → generic paused + Resume), Task 3 contract (NULL reason passes through) |
| 10 | a new cron pause cause mirrored in resume | Ruling R-14 (W3 adds none) |
| 11 | drop the shim; move its two lib callers | Task 1 (`dating_feature_flags.dart` on `get_dating_home`), Task 2 (v1 repository deleted; grep test), Task 3 (drop) |
| 12 | replace `delete_dating_profile` callers with exit v2 | Task 1 (`exit` in the lifecycle repository), Task 2 (v1 callers deleted; grep test), Task 12 (Leave screen; W3 gate grep `no v1 path`) |
| 13 | lifecycle error copy; exit can return `suspended` | Task 1 (mapping), Task 4 (resume errors), Task 11 (D13's activation errors), Task 12 (Leave's `suspended` outcome) |
| 14 | dashboard + `dating_dashboardFallbackReason` replaced | Task 2 (deleted; key removed) |
| 15 | `ReadinessScoringService.getResultMessage` unused | Ruling R-13 (kept) |

### Rulings (the spec wins over this plan; each records its cost if wrong)

- **Ruling R-1:** one migration per batch, named as §4.9; timestamps `20261107150000`/`160000`/`170000`. Cost if wrong: renaming before the push.
- **Ruling R-2:** the two `storage.objects` policies (`dating_profile_photos_insert_by_intent`, `dating_profile_photos_select_owner`) read `dating_photo_upload_intents` and `dating_profile_photos` as `authenticated`, so revoking those two tables' `SELECT` in W3a would break uploads and the owner's own photo download. W3a revokes the four `20260811120000` tables and drops their four owner-read policies; W3c moves both storage policies onto two definer predicates (same names, commands, roles and bucket literal), then revokes the photo and intent tables and drops their row policies. By the end of W3 the client has no direct `SELECT` on any Dating table (§4.1). Cost if wrong: none.
- **Ruling R-3:** `save_dating_profile_draft` ("Replace [W3]") is already replaced by W1c's per-step writers and revoked from every API role (W1 final M-9); dropping it would break `dating_v2_identity_contracts.sql`'s permission-denied pin, so it stays, ungranted. Cost: one dead function until W10.
- **Ruling R-4:** `get_dating_home` v2 adds only: `notify {available, requested}` on `feature_unavailable`/`country_closed`/`region_closed`; `first_drop_at` on `not_started`/`setup_in_progress`/`gentle_wait` (D1 line 6, D13); `can_shorten` on `gentle_wait` (carry 8); `country` on `paused` with `same_gender_switch` (the §2.4 note); `unavailable` for an `active` enrolment whose candidate check refuses for anything but the wait (carry 4); and `has_data` in every answer (R-43, C-2). W2's home contract strips these keys (and `has_data`) in its helper; W3a's contract pins them.
- **Ruling R-5 (owner-approved 2026-11-07):** §3.1 shows "Tell me when it's here" for `feature_unavailable` too; when the person's country is already open in the config (Dating off by the global switch) a request could never fire, so the button shows only when `notify.available` (the country itself is closed). Cost if wrong: one condition.
- **Ruling R-6:** one request per person (a new one replaces the old); refused as `already_open` for a country or region open now; queued only when a publish opens it; the request takes `publish_country_config`'s own advisory lock so the two serialise (race case in Task 3).
- **Ruling R-7:** §3.13's payload `{"route": "me"}`: `process-scheduled-notifications` drops keys outside its allowlist, so Task 3 adds `"route"` to it (one line + a Deno test). The app routes on the type alone, so an undeployed worker still opens Me. Deploy item.
- **Ruling R-8:** §3.14's "PIN screen" is `/dating/unlock?from=…`, inside the group and exempt from its own redirect; it shows the existing Safety PIN sheet. The unlock lasts the foreground session (cleared when the app is hidden or paused, on an account change, and by the quick-exit/sign-out wipe). A `from` outside `/dating/` goes to Me (no open redirect); an unreadable lock setting asks (fail closed).
- **Ruling R-9:** §4.10 puts the `device_wipes.dart` line in W8a; carry 6 needs the unlock and D0's state gone on quick exit now. Task 2 adds the spec's one call line `registerDatingDeviceWipes(target);` (and its import) with one in-memory entry `spec2.dating_session`; W8a extends that function and never edits `device_wipes.dart` again. Every Dating route is a top-level `GoRoute` (no shell branch, no `IndexedStack`), so quick exit's `go('neutralScreen')` disposes it.
- **Ruling R-10:** W3 registers only routes whose screens exist (`/dating/setup/:step`, `/dating/unlock`, `/dating/settings`, `/dating/not-open`, `/dating/leave`); W4–W9 add theirs inside `datingRoutes()`. A step id no batch has built opens Me.
- **Ruling R-11:** Task 2 deletes every v1 Dating screen, the v1 providers and the v1 repository with their routes (§3.14 removes the routes; each v1 screen reads a table W3a revokes). W4 and W6 build their v2 screens as new files. `dating_introduction.dart` and `dating_match.dart` stay for W5/W6. Cost: none (Dating is off in production).
- **Ruling R-12:** v1's activation wrote `seen_feature_intro_datingMode` to prefs; Dating never ran in production, so no real device holds it; no cleanup entry. Owner checklist: clear app data on test phones before the S19 device check.
- **Ruling R-13 (carry 15):** `ReadinessScoringService.getResultMessage` stays: it is Healing's mirror of the server message the clinician reviews, and its test pins the words; W3 is a Dating wave. Cost: 8 lines.
- **Ruling R-14 (carry 10):** W3 adds no pause cause.
- **Ruling R-15 (carry 2):** no W3 screen says a path pause is instant: the section shows only on the Dating path and re-reads on resume; introductions are W5's.
- **Ruling R-16:** D1's "Set up later" saves nothing (D20: nothing on the device), so Me shows the `not_started` card as the one quiet card; "Finish setting up Dating" appears once any step has saved (`setup_in_progress`).
- **Ruling R-17:** D3/D5/D6/D8 need each open country's regions with sides, its faith list and its same-gender switch, which no RPC returns; Task 5 adds `get_dating_setup_lists()` (signed in, config only, plus the caller's own default ages and phone-country note).
- **Ruling R-18 (owner-approved 2026-11-07):** the D6 country note's phone variant is built now; its location variant needs the IP/network country from `dating-device-check` and comes with W4b/W8b.
- **Ruling R-19:** the W3b migration publishes a faith list only when it differs from the current one (a replay publishes nothing) and raises if the publish refuses.
- **Ruling R-20:** D3 preselects the SIM country, else the device region, else the phone number's country — the first that is open; never hard-coded.
- **Ruling R-21:** D8's Skip always calls `clear_dating_faith` (never gated, idempotent): nothing is stored, and Skip on a revisit removes an earlier answer.
- **Ruling R-22 (owner-approved 2026-11-07):** `supabase_flutter`'s storage upload reports no progress, so D9's slots say "Preparing photo {n}…", "Uploading photo {n}…", then "Checking…" (no percentage).
- **Ruling R-23:** §4.10 "Keep" assumed the preparer is 1600 px / quality 80; today it is 2000 px / 1.5 MB through a native pass, and its temp file is named `dating_photo_…` (a C-5 breach). Task 9 makes it 1600 px, quality 80 (stepping down only to fit 1.5 MB), the Dart encoder only (a deterministic EXIF strip), temp name `p_<micros>.jpg` deleted after upload; D9 picks with `image_picker` directly (`ImagePickerService` copies to a permanent directory).
- **Ruling R-24:** `CHECK (moderation_state <> 'approved' OR csam_state = 'clear')`; existing approved rows (development only) go back to `pending` and are re-queued.
- **Ruling R-25:** D9's Dating `moderation_hold` "with category `csam`": the category and source columns are W7a's; Task 8 inserts the `moderation_hold` (one live per person) and W7a stamps category/source (carry).
- **Ruling R-26:** D11 is a shell until W4a: Continue goes to D12; D13's activation refuses `activation_gates_not_met` until W4a, shown as "We still need to check it's you before introductions start." with "Verify it's you".
- **Ruling R-27:** D12's push ask uses Spec 1's push asker with no metric (no Dating client metric key, S-2): `askInContext(PushAskContext.j3)` (the argument is unused by `askInContext` today).
- **Ruling R-28:** D13's "While you wait" shows "Write in your journal" (the first-date guide is W6c's).
- **Ruling R-29:** before W7a, `restricted`/`hold`/`age_review` use neutral copy with no category or date (listed for the DV reviewer).
- **Ruling R-30:** before W5b, `active` reads "Dating is on. Your introductions will show here."
- **Ruling R-31:** D4's "Dating terms" and "Privacy notice" open Spec 1's terms and privacy sheets; counsel's Dating-specific terms text is an owner item.
- **Ruling R-32:** the SQL and Dart below were written against the live bodies read from `attune_spec3a` on 2026-11-07 (`pg_get_functiondef`) and today's files, but not executed while planning (W2's plan was); every task re-verifies its anchors first, and an expected line that doesn't appear is a finding to report, never to paper over.
- **Ruling R-33:** the race scratch DB is `pg_dump -s attune_spec3a` plus the data of `public.metric_key_prefixes`, `public.feature_flags`, `public.country_safety_config` and `private.dating_calling_codes` (the script refuses a copy without the `dating.` prefix row), dropped after.
- **Ruling R-34:** the dev script is unchanged (every existing Dating flag is already ON; W3 adds no flag; the lists arrive by migration).
- **Ruling R-35:** `dating_%` flags are server-only (DATING-H1), so the manual can't read `dating_mode_enabled`; the registry declares it and `documentationFlagsProvider` resolves it through `DatingFeatureFlags.isDatingModeAvailable` (`get_dating_home`).
- **Ruling R-36:** §3.10's "It's open in Ghana and the United Kingdom now." and D1's line 7 are built from `get_dating_availability()`, never hard-coded.
- **Ruling R-37:** `list_dating_profile_photos()` returns `{ok, photos, after_mutual, after_mutual_from}` (DROP + CREATE), so D9's day-30 line needs no other read.
- **Ruling R-38:** D12 shows "exactly the §3.4 card" without the parts that need another person: "Why you two were introduced" (a pair, §5.8, W5a) and the Interested / Not for me actions (W5b). `DatingCardView` takes both as later slots. Cost if wrong: one slot each.
- **Ruling R-39:** D13's "While you wait" shows one item, "Write in your journal" (R-28); the plain-icon offer is not built (A-11, W8b).
- **Ruling R-40:** D12's edit links and Dating settings' rows open a setup step with `?from=preview` / `?from=settings`, and that step's Continue goes back instead of walking forward; the card re-reads when an answer or photo changes.
- **Ruling R-41:** "Leave Dating and delete my data" shows whenever there is anything to leave: every home state except a `not_started` with no Dating data (`has_data`, R-43), so restricted, held, age-review, unavailable, reverify and closed-country enrolments can always leave (deletion is never blocked; C-2). A restricted account's exit answers `suspended` and reads "You've left Dating." with no "set it up again". Pause shows for `active`/`cool_off`, Resume for `paused`. §3.12's Other countries and Never introduce me rows are W5c's; App icon W8b's.
- **Ruling R-42:** D9 drags by the thumbnail (no long-press delay) beside Move earlier / Move later; empty slots follow the filled ones and are not draggable.
- **Ruling R-43 (C-2):** every `get_dating_home()` answer carries `has_data` (`private.dating_has_data`: any Dating enrolment, profile, gentle-wait reflection or notice request; a kept never-introduce list is not counted, it stays until the account is deleted, §3.8). Every Dating section card, `_plain` ones included, links to Dating settings whenever `has_data` (or a profile or a notice) is there, and settings always has Clear and, with data, Leave. The helper reads only whether the person's own rows exist, so W2's "who reaches the reflections" pin names it (H9). Cost if wrong: one key on the home payload.
- **Ruling R-44 (M-8):** the neutral push's source key is an HMAC under its own server secret `dating_push_key` (vault or `app.settings.dating_push_key`), never the never-introduce key; with the key missing nothing is queued (fail closed): the publish still succeeds, the requests wait for the next opening, and `dating.notify.queue_failed` counts it. Owner: set the secret in every project (deploy item).
- **Ruling R-45 (M-10):** "Tell me when it's here" takes at most 20 requests a day per person (`check_dating_rate_limit('notify_request', 20, 1 day)`, answered `rate_limited`), so the aggregate can't be inflated from one app.
- **Ruling R-46 (I-14, controller):** an object uploaded under an intent that expired unused (15 minutes past expiry, no photo row) is an orphan: `process-dating-photo`'s cron call (`sweep-dating-photo-orphans`, every 15 minutes) claims up to 10, scans each CSAM first with the same matcher, and only a recorded scan deletes: clear → deleted (`dating.photo.orphan_swept`); a match → Spec 1's inline record (quarantine copy, hold, escalation; the original deleted only when the copy exists, else kept as the only evidence), `dating.photo.orphan_csam`; a matcher that can't answer → the claim is released and retried (`dating.photo.orphan_scan_error`). No orphan is ever deleted unscanned; the sweep is the service role's only.
- **Ruling R-47 (M-9):** `create_dating_photo_upload_intent` and `reorder_dating_photos` follow the shared lock rule: after the setup guard's locks, the write retries three times on 40P01/55P03/40001, then `dating:busy` (`lock_timeout` 2 s).

## Interfaces this plan consumes (read from the current code; adjust here if a later fix renames one)

- **Spec 1:** `homeLocation({AppTab? tab})` (`lib/home/home_location.dart`); `AppTab.me`; `homeAuthProvider`, `HomeSnapshot`, `homeStateProvider(userId)`; `switchPath(context, ref, {required AppPath to, bool oneTap, HomeSnapshot? home}) → PathChoiceOutcome` (`lib/features/me/presentation/path_switch.dart`); `datingLockProvider` (`AsyncNotifierProvider<DatingLockNotifier, bool>`), `datingLockAccountProvider`, `DatingLockStore.key == 'me_section_lock'` (`lib/features/safety/data/dating_lock_store.dart`); `setDatingLock(context, ref, bool on)` (`dating_lock_setting.dart`); `confirmSafetyPin(context) → Future<bool>`; `SafetyPinStore.instance.hasPin()/setEveryOpen(bool)`; `RouteNames.safetyPin`, `RouteNames.howYouUseAttune`, `RouteNames.reflectionJournal`, `RouteNames.login`; `DeviceWipeRegistry`, `DeviceWipeEntry`, `WipeMoment`; `FlowFrame`, `FlowPrimaryButton`, `FlowSecondaryButton`, `FlowTextLink`, `FlowErrorLine`, `showTermsSheet`, `showPrivacySheet`; `countryNameFor(iso, special:)`, `formatCountryList(list, nameOf:, pair:)` (`country_names.dart`); `countryOfPhone(e164)`; `deviceCountryProvider` (`lib/core/platform/sim_country.dart`); `supportResourcesProvider(country)`, `openSupportUrl(context, url)`, `SupportCategory.lgbtqLegal/.crisis`; `pushAskerProvider.askInContext(PushAskContext)`; `MyDateFormat`; `AllowLargeText`; motion tokens `kStepForwardDuration`, `kStepBackDuration`, `kReducedMotionFade`, `kSharedAxisOffset`; test helpers `pumpFlowScreen`, `expectFlowGoldens`, `expectFlowGuidelines`, `tapInReach`, `FakeHomeAuth`, `testUser`.
- **S2 W1/W2 (live):** `get_dating_home()` (W2 v1 body, re-created in Task 3); `get_dating_availability()` → `{countries:[{code, open_regions:[{code,name_key}]|null}]}`; `get_my_dating_profile()` → `{ok, profile:{…}}`; `get_dating_profile_preview()` → `{ok, card:{display_name, age, region_name_key, intention, marriage_timeline, children_have, children_want, gender, pronouns, faith, marital, prompts, photos_after_mutual, photos:[{id,position}]}}`; writers `save_dating_intention(p_idempotency_key, p_intention, p_timeline, p_timeline_visible, p_attested, p_marital, p_marital_visible)`, `save_dating_location(…, p_country, p_region, p_side, p_scope)`, `record_dating_consent(p_idempotency_key, p_purpose, p_action, p_policy_version, p_categories)`, `begin_dating_enrollment(p_terms_version, p_idempotency_key)`, `save_dating_identity(…, p_identity, p_specific, p_pronouns, p_extra_pools, p_visible)`, `save_dating_who_to_meet(…, p_seeking, p_min_age, p_max_age)`, `save_dating_children(…, p_have, p_want, p_must_match, p_exclude_parents)`, `save_dating_faith(…, p_faith, p_denomination, p_importance, p_visible)`, `clear_dating_faith(p_idempotency_key)`, `save_dating_prompts(p_idempotency_key, p_items)`, `save_dating_display_name(…, p_name)`, `save_dating_settings(…, p_values)`, `set_dating_photos_after_mutual(…, p_on)`, lifecycle `activate_dating_profile`/`pause_dating_mode`/`resume_dating_mode(p_idempotency_key)` and `exit_dating_mode(p_idempotency_key, p_keep_never_introduce)` (raise `path_not_dating`, `not_paused`, `activation_required`, `resume_gates_not_met`, `activation_gates_not_met`, `enrollment_incomplete`, `consent_required`, `profile_or_preferences_incomplete`, `reverify_device`, `not_eligible`, `rate_limited`, `dating:busy`); `GentleWaitScreen({required VoidCallback onSetUp, VoidCallback? onBack})`, `gentleWaitGatewayProvider`, `gentleWaitAccountProvider`, `datingOnlineProvider`, `GentleWaitSave`, `GentleWaitUnavailable`; private helpers `private.dating_invalid(text)`, `private.dating_iso_country(text)`, `private.dating_trim(text)`, `private.dating_setup_guard()`, `private.dating_lock_setup(uuid)`, `private.dating_first_drop_at(uuid, timestamptz)`, `private.dating_gentle_wait_can_shorten(uuid)`, `private.bump_metric_internal(text)`, `public.dating_country_config(text)`, `public.app_setting(text)`, `public.check_dating_rate_limit(text, integer, interval)` (raises `rate_limited`), `public.claim_dating_idempotency(text, text)`, `public.record_inline_csam_match(…)`.

## Interfaces this plan produces (for W4 onward)

- **SQL (W3a):** `request_dating_country_notice(p_country text, p_region text DEFAULT NULL) → jsonb` (`{ok:true}` | `{ok:false, reason:'invalid', field}` | `already_open` | `busy`); `cancel_dating_country_notice() → jsonb`; `private.dating_push_source_key(uuid, text, date) → text`; `private.dating_queue_me_update(p_user uuid, p_purpose text, p_kind text) → boolean` (`p_kind` `notify` → "Something you asked about is ready in Attune.", `new` → "You have something new in Attune."; W5b/W6b reuse it); `private.dating_notify_opened(text, boolean, text[], text[]) → integer`; `private.dating_notice_state(uuid, text, text) → jsonb`; `private.dating_has_data(uuid) → boolean`; `get_dating_home()` v2 (R-4; `has_data` in every answer, R-43); the push key setting `dating_push_key` (R-44). **(W3b):** `get_dating_setup_lists() → jsonb`. **(W3c):** the orphan sweep `claim_dating_orphan_uploads(integer)` / `record_dating_orphan_scan(uuid, text)` (service role, R-46) and cron `sweep-dating-photo-orphans`; `create_dating_photo_upload_intent(p_mime_type) → jsonb`, `insert_dating_profile_photo(p_intent_id, p_position) → jsonb`, `list_dating_profile_photos() → jsonb`, `delete_dating_profile_photo(p_photo_id) → jsonb`, `reorder_dating_photos(p_idempotency_key, p_order uuid[]) → jsonb`, `set_dating_photo_caption(p_photo_id, p_caption) → jsonb`, `record_dating_photo_csam(p_photo_id, p_outcome) → jsonb` (service), `public.dating_storage_intent_open(text)`, `public.dating_storage_owns(text)` (storage-policy predicates).
- **App:** `lib/features/dating/data/dating_supabase_client.dart` (`datingSupabaseClientProvider` — W4b swaps its body); `dating_rpc.dart` (`DatingRpc`, `DatingBusy`, `DatingLifecycleError`, `DatingWrite`, `DatingActionKeys`, `datingWrite()`); `dating_home.dart` (`DatingHome` with `hasData`, `DatingHomeState`, `DatingPauseReason`, `DatingNotice`, `DatingAvailability`, `DatingOpenCountry`); `dating_home_repository.dart` (`DatingHomeGateway`, `DatingNoticeResult`); `dating_lifecycle_repository.dart` (`DatingLifecycleGateway`, `DatingLifecycleResult`); `dating_providers.dart` (`datingAccountProvider`, `datingRpcProvider`, `datingHomeGatewayProvider`, `datingLifecycleGatewayProvider`, `datingHomeProvider`, `datingAvailabilityProvider`); `lock/dating_unlock.dart` (`DatingSessionMemory`, `datingUnlockedProvider`, `datingRedirect`, `DatingUnlockScreen`); `dating_device_wipes.dart` (`registerDatingDeviceWipes`); `routes/dating_routes.dart` (`DatingPaths`, `datingRoutes()`, `datingPage()`, `DatingMotion`); `routes/dating_setup_steps.dart` (`datingSetupOrder`, `datingStepNumber`, `DatingStepNav`, `datingStepScreen`); `section/dating_section.dart` (`DatingSection`); `not_open/dating_not_open_screen.dart`; `settings/dating_settings_screen.dart`, `settings/dating_leave_screen.dart`; `setup/*` (step screens, `DatingStepFrame`, `DatingSetupGateway`, `datingListName`); `photos/*`.

## File map

**W3a.** Task 1 creates `.superpowers/sdd/2026-11-07-spec2-w3/{suite.sh, grants_line.py, mutate.py, before/, sql-baseline-{1,2}.txt, flutter-baseline.txt, analyze-baseline.txt, latch.sha}`, `lib/features/dating/data/{dating_supabase_client,dating_rpc,dating_home,dating_home_repository,dating_lifecycle_repository,dating_providers}.dart`, `test/features/dating/support/dating_fakes.dart`, `test/features/dating/data/{dating_rpc,dating_home,dating_lifecycle_repository,dating_providers}_test.dart`; modifies `lib/features/dating/domain/services/dating_feature_flags.dart`. Task 2 creates `lib/features/dating/{lock/dating_unlock.dart, dating_device_wipes.dart, routes/dating_routes.dart, routes/dating_setup_steps.dart}`, `test/features/dating/routes/dating_routes_test.dart`, `test/features/dating/gentle_wait/gentle_wait_states_test.dart`, `test/architecture/{dating_rpc_only,dating_boundaries}_test.dart`, `test/core/notifications/me_update_routing_test.dart`; modifies `lib/app/routing/app_router.dart`, `lib/core/notifications/config/notification_config.dart`, `lib/app/device_wipes.dart`, `lib/app/text_scale_policy.dart`, `lib/features/dating/gentle_wait/gentle_wait_screen.dart`, `lib/features/dating/data/models/dating_enrollment.dart`, `lib/features/ai_assistant/data/services/ai_session_capabilities.dart` (one comment), `lib/i10n/app_en.arb`, the generated l10n, `test/architecture/text_scale_routes_test.dart`, `test/app/routing/{app_router_sign_in,feature_intro_route_wiring}_test.dart`, `test/features/chat/chat_couples_locked_screen_healing_entry_test.dart`; deletes `lib/features/dating/data/repositories/dating_repository.dart`, `lib/features/dating/presentation/**`, `test/features/dating/{dating_dashboard_never_gates_on_healing,dating_profile_activation_marks_intro_seen}_test.dart`. Task 3 creates the two migration files, `supabase/tests/dating_v2_client_reads_contracts.sql`, `$D/{build_mig_T3.py, mut_T3.py, canary_T3.sql, edit_*_T3.py}`, `supabase/functions/process-scheduled-notifications/privacy_allowlist.test.ts`; modifies `supabase/tests/{dating_rls_canary,dating_v2_home_contracts,dating_v2_eligibility_contracts}.sql`, `scripts/local_pg_grants.sql`, `scripts/concurrency/dating_kill_switch_races.sh`, `supabase/functions/process-scheduled-notifications/index.ts` (one line). Task 4 creates `lib/features/dating/{section/dating_section.dart, not_open/dating_not_open_screen.dart, settings/dating_settings_screen.dart}` and their tests and goldens, `test/features/dating/no_disk_writes_test.dart`; modifies `dating_slot.dart`, `dating_routes.dart`, `test/features/me/dating_slot_test.dart` and its goldens, `test/features/me/me_home_screen_test.dart` goldens (`me_dating_open.*`).

**W3b.** Task 5 creates the two migration files, `lib/features/dating/setup/{dating_setup_models,dating_setup_repository,dating_setup_providers}.dart`, `test/features/dating/setup/{dating_list_names,dating_setup_repository}_test.dart`, `test/features/dating/support/dating_setup_fakes.dart`; modifies `lib/features/dating/setup/dating_list_names.dart` (Task 4's file: the faith names at its marker), `dating_rls_canary.sql`, `dating_v2_setup_contracts.sql`, `country_safety_config_contracts.sql` (I-3), `scripts/local_pg_grants.sql`. Task 6 creates `lib/features/dating/setup/{dating_step_frame,dating_picker_sheet,how_step,looking_for_step,where_step,privacy_step}.dart`, `test/features/dating/setup/d1_d4_test.dart` and goldens; modifies `dating_setup_steps.dart`. Task 7 creates `lib/features/dating/setup/{you_step,meet_step,country_note_screen,children_step,faith_step,dating_support_sheet}.dart`, `test/features/dating/setup/d5_d8_test.dart` and goldens; modifies `dating_setup_steps.dart`, `test/features/dating/support/dating_setup_fakes.dart` (one list appended). The "Why?" sheet is Task 4's `section/dating_why_sheet.dart`.

**W3c.** Task 8 creates the two migration files; modifies `dating_rls_canary.sql`, `dating_v2_setup_contracts.sql` (G3 + new sections), `storage_bucket_policies.sql`, `scripts/local_pg_grants.sql`. Task 9 creates `supabase/functions/process-dating-photo/{handler.ts, handler.test.ts}`; modifies `process-dating-photo/index.ts`, `_shared/google_vision.ts`, `_shared/google_vision.test.ts`, `lib/features/dating/domain/services/dating_image_preparer.dart`, its two tests, `.github/workflows/tests.yml` (one path in the Deno job); deletes `supabase/functions/upload-dating-photo/`. Task 10 creates `lib/features/dating/photos/{dating_photos_repository,dating_photos_providers}.dart`, `lib/features/dating/setup/{photos_step,prompts_step}.dart`, tests and goldens; modifies `dating_profile_photo.dart`, its test, `dating_setup_steps.dart`. Task 11 creates `lib/features/dating/card/dating_card.dart`, `lib/features/dating/setup/{dating_preview_providers,verify_step,preview_step,ready_step}.dart`, `lib/features/dating/section/dating_lifecycle_errors.dart`, `test/features/dating/setup/d11_d13_test.dart` and goldens; modifies `dating_setup_steps.dart`, `dating_routes.dart` (R-40's `from`), `dating_routes_test.dart`, `dating_photos_fakes.dart`. Task 12 creates `lib/features/dating/settings/dating_leave_screen.dart`, `test/features/dating/settings/{dating_settings_rows,dating_leave_screen}_test.dart` and goldens; modifies `dating_settings_screen.dart`, `dating_routes.dart`, `dating_routes_test.dart`, `lib/app/documentations/user_manual/data/{dating_mode_docs,manual_documentation_registry,documentation_flags}.dart`, `test/app/documentations/{documentation_registry_flags,manual_content_guard}_test.dart`, `test/architecture/text_scale_routes_test.dart`.

**Not edited:** `lib/main.dart`, `lib/home/home_screen.dart`, `quick_exit_service.dart`, `auth_provider.dart`, `set_user_path_internal`, `get_public_app_config()`, every Spec 1 Me file except `dating_slot.dart`, every applied migration, `supabase/sql/*`, `scripts/local_pg_setup.sh`, `scripts/local_pg_bootstrap.sql`, every contract not named above, Games, Opinions, Healing (R-13), `ATTUNE_SOUL.md`, `ATTUNE_THESIS.md`.

---

## Batch W3a — section, routes, repository, neutral push type

### Task 1: The W3 tool folder, the baselines, the Dating data layer (§4.4, §4.10 repository/providers/feature flags, Fable H3c; carries 1, 11, 12, 13; D8)

**Files:**
- Create: `.superpowers/sdd/2026-11-07-spec2-w3/{suite.sh, grants_line.py, mutate.py, before/*.sql, sql-baseline-1.txt, sql-baseline-2.txt, flutter-baseline.txt, analyze-baseline.txt, latch.sha}`
- Create: `lib/features/dating/data/dating_supabase_client.dart`, `lib/features/dating/data/dating_rpc.dart`, `lib/features/dating/data/dating_home.dart`, `lib/features/dating/data/dating_home_repository.dart`, `lib/features/dating/data/dating_lifecycle_repository.dart`, `lib/features/dating/data/dating_providers.dart`
- Create: `test/features/dating/support/dating_fakes.dart`, `test/features/dating/data/dating_rpc_test.dart`, `test/features/dating/data/dating_home_test.dart`, `test/features/dating/data/dating_lifecycle_repository_test.dart`, `test/features/dating/data/dating_providers_test.dart`
- Modify: `lib/features/dating/domain/services/dating_feature_flags.dart` (whole file replaced; `DatingMonitoring` removed, Fable L4)

**Interfaces:**
- Consumes: `currentUserProvider` (`lib/features/auth/providers/auth_provider.dart`); `datingOnlineProvider` (W2); the W1/W2 RPCs listed above.
- Produces: everything in "Interfaces this plan produces → App" under `data/`; `$D=.superpowers/sdd/2026-11-07-spec2-w3` and its tools for every later task.

- [ ] **Step 1: Confirm the target, the tree and the newest migration**

```bash
cd /Users/user/attune
psql -X -d attune_spec3a -Atc "select current_database(), to_regprocedure('public.get_dating_eligibility()') is not null, to_regprocedure('public.get_dating_home()') is not null"
ls supabase/migrations | sort | tail -1
git log --oneline -1
git status --short -- lib test supabase scripts
```

Expected: `attune_spec3a|t|t`; `20261107140010_dating_v2_home_grants.sql`; `62839cce feat(dating): Spec 2 W2 gentle wait, path pause, home v1 (Dating off)`; at most the owner's `supabase/.temp/cli-latest`.

- [ ] **Step 2: The tool folder**

```bash
D=.superpowers/sdd/2026-11-07-spec2-w3; mkdir -p $D/before
cp .superpowers/sdd/2026-11-07-spec2-w2/suite.sh $D/
chmod +x $D/suite.sh
```

Create `$D/mutate.py` (W2's runner plus the grants twin, I-7) with exactly:

```python
#!/usr/bin/env python3
"""Spec 2 W3 mutation runner (attune_spec3a only; W3_DB names a scratch
clone of it when the plan says so).
usage: mutate.py <migration.sql> <contract.sql> <spec.py> <dir> [<twin.sql>]
spec.py defines MUTS = {name: mutation}; a mutation is (old, new) (one exact
occurrence in the migration, whose own BEGIN/COMMIT are removed), ('MULTI',
[(old, new), ...]), ('CUT', (start, end)) (the span is removed) or ('RAW',
sql) (SQL of its own). Each runs after a BEGIN and before the contract,
whose ROLLBACK undoes it. With <twin.sql>, the twin (its BEGIN/COMMIT
removed) runs right after a non-RAW mutant, as it does after the real
migration: a DROP + CREATE'd function then has its real grants, so a
mutant dies at its own assertion, not at a privilege list (I-7). The
contract's first ERROR is printed."""
import os, pathlib, re, runpy, subprocess, sys

mig, con, spec, out = sys.argv[1], sys.argv[2], sys.argv[3], pathlib.Path(sys.argv[4])
db = os.environ.get('W3_DB', 'attune_spec3a')

def strip(path):
    t = pathlib.Path(path).read_text()
    assert t.count("\nBEGIN;\n") <= 1 and t.count("\nCOMMIT;\n") <= 1, path
    return t.replace("\nBEGIN;\n", "\n").replace("\nCOMMIT;\n", "\n")

m = pathlib.Path(mig).read_text()
assert m.count("\nBEGIN;\n") == 1 and m.count("\nCOMMIT;\n") == 1, mig
body = strip(mig)
twin = strip(sys.argv[5]) if len(sys.argv) > 5 else None
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
    if twin is not None and a != 'RAW':
        text += '\n' + twin
    f = out / f"mut_{name}.sql"
    f.write_text(text)
    r = subprocess.run(['psql', '-X', '-q', '-v', 'ON_ERROR_STOP=1', '-d', db,
                        '-c', 'BEGIN', '-f', str(f), '-f', con], capture_output=True, text=True)
    lines = (r.stdout + r.stderr).splitlines()
    idx = [i for i, l in enumerate(lines) if 'ERROR' in l]
    line = lines[idx[0]] if idx else 'NO ERROR (mutant survived)'
    if idx and line.endswith(':') and idx[0] + 1 < len(lines) and lines[idx[0] + 1].startswith('  '):
        line += ' ' + lines[idx[0] + 1].strip()
    print(f"{name}: {re.sub(r'^psql:[^ ]* ', '', line)[:170]}")
    f.unlink()
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

Create `$D/anchor.py` (every later edit script imports it) with exactly:

```python
# Exact-anchor edits: each (old, new) must occur exactly once.
import pathlib

def edit(path, pairs, label):
    p = pathlib.Path(path)
    s = p.read_text()
    for old, new in pairs:
        n = s.count(old)
        assert n == 1, f'{label}: anchor occurs {n} times in {path}: {old[:70]!r}'
        s = s.replace(old, new)
    p.write_text(s)
    print(f'{path}: {len(pairs)} edit(s) ({label})')
```

- [ ] **Step 3: Two baseline runs of the SQL suite; the Flutter, analyzer and latch baselines**

```bash
D=.superpowers/sdd/2026-11-07-spec2-w3
for run in 1 2; do
  $D/suite.sh attune_spec3a > $D/sql-baseline-$run.txt
  echo "run $run: $(grep -c '^PASS' $D/sql-baseline-$run.txt) PASS, $(grep -c '^FAIL' $D/sql-baseline-$run.txt) FAIL"
done
diff $D/sql-baseline-1.txt $D/sql-baseline-2.txt && echo stable
shasum -a 256 lib/home/home_screen.dart > $D/latch.sha; cat $D/latch.sha
flutter test --reporter compact > $D/flutter-baseline.txt 2>&1; tail -c 160 $D/flutter-baseline.txt
flutter analyze --no-pub lib test > $D/analyze-baseline.txt 2>&1; tail -1 $D/analyze-baseline.txt
shasum -c .superpowers/sdd/2026-11-04-spec1-w10-accessibility-docs/w10-1.0.sha | grep -vc ': OK$'
shasum -c .superpowers/sdd/2026-11-04-spec1-w9/flag_off.sha | grep -vc ': OK$'
```

Expected: `run 1: 158 PASS, 14 FAIL`, `run 2: 158 PASS, 14 FAIL`, `stable`; the latch hash; the Flutter tail ending `+7299 …` with only the known `planning_recent` failure if the clock trips it; `571 issues found.`; `0` and `0`. Record the exact numbers in the report; every gate compares against them. To compare analyzer runs later: `sed -E 's/:[0-9]+:[0-9]+ /:L:C /' FILE | sort` on both and `diff` (line numbers move when files are edited).

- [ ] **Step 4: Save the live bodies W3 re-creates**

```bash
D=.superpowers/sdd/2026-11-07-spec2-w3
for sig in 'public.get_dating_home()' 'public.publish_country_config(text,jsonb)' \
           'public.save_gentle_wait_reflection(jsonb)' 'public.get_dating_eligibility()' \
           'public.create_dating_photo_upload_intent(text)' 'public.insert_dating_profile_photo(uuid,smallint)' \
           'public.list_dating_profile_photos()' 'public.delete_dating_profile_photo(uuid)' \
           'public.claim_dating_photo_jobs(integer,uuid)'; do
  psql -X -d attune_spec3a -Atc "select pg_get_functiondef('$sig'::regprocedure)" > "$D/before/$sig.sql"
done
ls $D/before | wc -l
```

Expected: `9`.

- [ ] **Step 5: Write the failing data-layer tests**

Create `test/features/dating/support/dating_fakes.dart` with exactly:

```dart
// Spec 2 W3: in-memory Dating gateways for widget and provider tests.
import 'dart:async';

import 'package:attune/features/dating/data/dating_home.dart';
import 'package:attune/features/dating/data/dating_home_repository.dart';
import 'package:attune/features/dating/data/dating_lifecycle_repository.dart';
import 'package:attune/features/dating/data/dating_rpc.dart';

class FakeDatingHomeGateway implements DatingHomeGateway {
  FakeDatingHomeGateway({
    this.home = const DatingHome(state: DatingHomeState.notStarted),
  });

  DatingHome home;
  Object? readError;
  Completer<DatingHome>? hold;
  int reads = 0;
  DatingAvailability available = const DatingAvailability(
    countries: [
      DatingOpenCountry(code: 'GB'),
      DatingOpenCountry(
        code: 'GH',
        openRegionKeys: ['dating_region_gh_aa', 'dating_region_gh_ah'],
      ),
    ],
  );
  final requests = <(String, String?)>[];
  int cancels = 0;
  DatingNoticeResult noticeResult = DatingNoticeResult.saved;

  @override
  Future<DatingHome> read() async {
    reads++;
    final held = hold;
    if (held != null) return held.future;
    final error = readError;
    if (error != null) throw error;
    return home;
  }

  @override
  Future<DatingAvailability> availability() async => available;

  @override
  Future<DatingNoticeResult> requestNotice(
    String country, {
    String? region,
  }) async {
    requests.add((country, region));
    return noticeResult;
  }

  @override
  Future<DatingNoticeResult> cancelNotice() async {
    cancels++;
    return noticeResult;
  }
}

class FakeDatingLifecycleGateway implements DatingLifecycleGateway {
  final calls = <String>[];
  final keys = <String>[];
  DatingLifecycleResult result = const DatingLifecycleResult.done('active');
  bool? keptList;

  Future<DatingLifecycleResult> _record(String name, String key) async {
    calls.add(name);
    keys.add(key);
    return result;
  }

  @override
  Future<DatingLifecycleResult> pause(String key) => _record('pause', key);

  @override
  Future<DatingLifecycleResult> resume(String key) => _record('resume', key);

  @override
  Future<DatingLifecycleResult> activate(String key) =>
      _record('activate', key);

  @override
  Future<DatingLifecycleResult> exit(
    String key, {
    required bool keepNeverIntroduce,
  }) {
    keptList = keepNeverIntroduce;
    return _record('exit', key);
  }
}

/// A [DatingRpc] over a scripted list of answers; records every call.
class ScriptedRpc {
  ScriptedRpc(this.answers);

  final List<Object? Function(String fn, Map<String, dynamic>? params)> answers;
  final calls = <(String, Map<String, dynamic>?)>[];

  DatingRpc get rpc => DatingRpc.withCall((fn, params) async {
    calls.add((fn, params));
    final answer = answers.removeAt(0)(fn, params);
    if (answer is Exception) throw answer;
    if (answer is Error) throw answer;
    return answer;
  });
}
```

Create `test/features/dating/data/dating_rpc_test.dart` with exactly:

```dart
import 'package:attune/features/dating/data/dating_rpc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../support/dating_fakes.dart';

PostgrestException _raised(String message) =>
    PostgrestException(message: message, code: '22023');

void main() {
  group('DatingRpc', () {
    test('dating:busy is retried once, silently', () async {
      final s = ScriptedRpc([
        (_, __) => _raised('dating:busy'),
        (_, __) => {'ok': true},
      ]);
      expect(await s.rpc.call('get_dating_home'), {'ok': true});
      expect(s.calls.length, 2);
    });

    test('a second dating:busy is DatingBusy', () async {
      final s = ScriptedRpc([
        (_, __) => _raised('dating:busy'),
        (_, __) => _raised('dating:busy'),
      ]);
      await expectLater(
        s.rpc.call('get_dating_home'),
        throwsA(isA<DatingBusy>()),
      );
    });

    test('any other refusal is raised as it came, never retried', () async {
      final s = ScriptedRpc([(_, __) => _raised('path_not_dating')]);
      await expectLater(
        s.rpc.call('resume_dating_mode'),
        throwsA(isA<PostgrestException>()),
      );
      expect(s.calls.length, 1);
    });
  });

  group('DatingLifecycleError (carries 1, 13)', () {
    final cases = {
      'path_not_dating': DatingLifecycleError.pathNotDating,
      'not_paused': DatingLifecycleError.notPaused,
      'activation_required': DatingLifecycleError.activationRequired,
      'resume_gates_not_met': DatingLifecycleError.resumeGatesNotMet,
      'activation_gates_not_met': DatingLifecycleError.activationGatesNotMet,
      'enrollment_incomplete': DatingLifecycleError.enrollmentIncomplete,
      'consent_required': DatingLifecycleError.consentRequired,
      'terms_consent_required': DatingLifecycleError.consentRequired,
      'dating_opt_in_required': DatingLifecycleError.consentRequired,
      'profile_or_preferences_incomplete':
          DatingLifecycleError.profileIncomplete,
      'reverify_device': DatingLifecycleError.reverifyDevice,
      'not_eligible': DatingLifecycleError.notEligible,
      'rate_limited': DatingLifecycleError.rateLimited,
      'something new': DatingLifecycleError.failed,
    };
    for (final entry in cases.entries) {
      test('${entry.key} -> ${entry.value.name}', () {
        expect(DatingLifecycleError.of(_raised(entry.key)), entry.value);
      });
    }
    test('busy and anything else', () {
      expect(
        DatingLifecycleError.of(const DatingBusy()),
        DatingLifecycleError.busy,
      );
      expect(
        DatingLifecycleError.of(StateError('x')),
        DatingLifecycleError.failed,
      );
    });
  });

  group('DatingWrite', () {
    test('ok with the next step', () {
      final w = DatingWrite.fromJson({'ok': true, 'next_step': 'where'});
      expect(w.ok, isTrue);
      expect(w.nextStep, 'where');
      expect(w.reason, isNull);
    });
    test('a refusal with its field and position', () {
      final w = DatingWrite.fromJson({
        'ok': false,
        'reason': 'contact_details',
        'position': 2,
      });
      expect(w.ok, isFalse);
      expect(w.reason, 'contact_details');
      expect(w.position, 2);
    });
    test('anything malformed is failed, never ok', () {
      expect(DatingWrite.fromJson(null).ok, isFalse);
      expect(DatingWrite.fromJson('ok').reason, 'failed');
      expect(DatingWrite.fromJson({'ok': 'true'}).ok, isFalse);
    });
    test('datingWrite maps DatingBusy and errors', () async {
      expect(
        (await datingWrite(() => throw const DatingBusy())).reason,
        'busy',
      );
      expect((await datingWrite(() => throw StateError('x'))).reason, 'failed');
    });
  });

  group('DatingActionKeys (Fable H3c)', () {
    test('a double tap sends one key; a changed answer a new one', () {
      var n = 0;
      final keys = DatingActionKeys(newKey: () => 'k${++n}');
      final a = keys.keyFor('d2', {'intention': 'marriage'});
      expect(keys.keyFor('d2', {'intention': 'marriage'}), a);
      final b = keys.keyFor('d2', {'intention': 'committed'});
      expect(b, isNot(a));
      expect(keys.keyFor('d3', {'intention': 'committed'}), isNot(b));
    });
    test('real keys fit the server rule (8-200 of [A-Za-z0-9_:.-])', () {
      final key = DatingActionKeys().keyFor('d2');
      expect(RegExp(r'^[A-Za-z0-9_:.-]{8,200}$').hasMatch(key), isTrue);
    });
  });
}
```

Create `test/features/dating/data/dating_home_test.dart` with exactly:

```dart
import 'package:attune/features/dating/data/dating_home.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every server state maps; an unknown or missing one is unavailable '
      '(fail closed: never "you\'re live")', () {
    for (final s in DatingHomeState.values) {
      expect(DatingHome.fromJson({'state': s.wire}).state, s);
    }
    expect(
      DatingHome.fromJson({'state': 'verifying'}).state,
      DatingHomeState.unavailable,
    );
    expect(DatingHome.fromJson({}).state, DatingHomeState.unavailable);
  });

  test('a closed country carries its notice', () {
    final h = DatingHome.fromJson({
      'state': 'region_closed',
      'country': 'GH',
      'region': 'TV',
      'open_regions': ['AA', 'AH'],
      'notify': {'available': true, 'requested': true},
    });
    expect(h.country, 'GH');
    expect(h.region, 'TV');
    expect(h.openRegions, ['AA', 'AH']);
    expect(h.notice.available, isTrue);
    expect(h.notice.requested, isTrue);
    expect(
      DatingHome.fromJson({'state': 'country_closed'}).notice.available,
      isFalse,
    );
  });

  test('every pause reason maps; NULL and unknown are unknown (carry 9)', () {
    const wires = {
      'user': DatingPauseReason.user,
      'relationship': DatingPauseReason.relationship,
      'path_change': DatingPauseReason.pathChange,
      'same_gender_switch': DatingPauseReason.sameGenderSwitch,
      'away': DatingPauseReason.away,
      'account_parked': DatingPauseReason.accountParked,
      'gates': DatingPauseReason.gates,
    };
    for (final e in wires.entries) {
      expect(
        DatingHome.fromJson({
          'state': 'paused',
          'pause_reason': e.key,
        }).pauseReason,
        e.value,
      );
    }
    expect(
      DatingHome.fromJson({
        'state': 'paused',
        'pause_reason': null,
      }).pauseReason,
      DatingPauseReason.unknown,
    );
    expect(
      DatingHome.fromJson({
        'state': 'paused',
        'pause_reason': 'age_review',
      }).pauseReason,
      DatingPauseReason.unknown,
    );
  });

  test('has_data is read in any state, and is false when missing (C-2)', () {
    expect(
      DatingHome.fromJson({'state': 'restricted', 'has_data': true}).hasData,
      isTrue,
    );
    expect(DatingHome.fromJson({'state': 'not_started'}).hasData, isFalse);
  });

  test('the dates are read as instants', () {
    final h = DatingHome.fromJson({
      'state': 'gentle_wait',
      'ended_at': '2026-11-01T10:00:00+00:00',
      'opens_at': '2026-12-01T10:00:00+00:00',
      'first_drop_at': '2026-12-01T19:00:00+00:00',
      'can_shorten': true,
      'next_step': 'where',
    });
    expect(h.opensAt, DateTime.utc(2026, 12, 1, 10));
    expect(h.firstDropAt, DateTime.utc(2026, 12, 1, 19));
    expect(h.canShorten, isTrue);
    expect(h.nextStep, 'where');
  });

  test('availability: GB open everywhere, GH in two regions', () {
    final a = DatingAvailability.fromJson({
      'countries': [
        {'code': 'GB', 'open_regions': null},
        {
          'code': 'GH',
          'open_regions': [
            {'code': 'AA', 'name_key': 'dating_region_gh_aa'},
            {'code': 'AH', 'name_key': 'dating_region_gh_ah'},
          ],
        },
      ],
    });
    expect(a.countries.map((c) => c.code), ['GB', 'GH']);
    expect(a.countries.first.openRegionKeys, isNull);
    expect(a.countries.last.openRegionKeys, [
      'dating_region_gh_aa',
      'dating_region_gh_ah',
    ]);
    expect(a.isOpen('GH'), isTrue);
    expect(a.isOpen('NG'), isFalse);
  });
}
```

Create `test/features/dating/data/dating_lifecycle_repository_test.dart` with exactly:

```dart
import 'package:attune/features/dating/data/dating_lifecycle_repository.dart';
import 'package:attune/features/dating/data/dating_rpc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../support/dating_fakes.dart';

void main() {
  test('exit v2 sends the key and the keep choice (carry 12)', () async {
    final s = ScriptedRpc([
      (_, __) => {'state': 'exited'},
    ]);
    final r = await DatingLifecycleRepository(
      s.rpc,
    ).exit('k-exit-0001', keepNeverIntroduce: true);
    expect(r.ok, isTrue);
    expect(r.state, 'exited');
    // A record holding a Map compares the Map by identity: check each part.
    expect(s.calls.single.$1, 'exit_dating_mode');
    expect(s.calls.single.$2, {
      'p_idempotency_key': 'k-exit-0001',
      'p_keep_never_introduce': true,
    });
  });

  test('exit can answer suspended (W1 B10 M-8, carry 13)', () async {
    final s = ScriptedRpc([
      (_, __) => {'state': 'suspended'},
    ]);
    final r = await DatingLifecycleRepository(
      s.rpc,
    ).exit('k-exit-0002', keepNeverIntroduce: false);
    expect(r.state, 'suspended');
  });

  test('a raised refusal is its named error (carry 1)', () async {
    final s = ScriptedRpc([
      (_, __) => PostgrestException(message: 'path_not_dating', code: '22023'),
    ]);
    final r = await DatingLifecycleRepository(s.rpc).resume('k-res-0001');
    expect(r.ok, isFalse);
    expect(r.error, DatingLifecycleError.pathNotDating);
  });

  test('pause, resume and activate call their RPC with the key', () async {
    final s = ScriptedRpc([
      (_, __) => {'state': 'paused'},
      (_, __) => {'state': 'active'},
      (_, __) => {'state': 'active'},
    ]);
    final repo = DatingLifecycleRepository(s.rpc);
    await repo.pause('k-p-000001');
    await repo.resume('k-r-000001');
    await repo.activate('k-a-000001');
    expect(s.calls.map((c) => c.$1), [
      'pause_dating_mode',
      'resume_dating_mode',
      'activate_dating_profile',
    ]);
    expect(s.calls.first.$2, {'p_idempotency_key': 'k-p-000001'});
  });
}
```

Create `test/features/dating/data/dating_providers_test.dart` with exactly:

```dart
import 'dart:async';

import 'package:attune/features/dating/data/dating_home.dart';
import 'package:attune/features/dating/data/dating_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/dating_fakes.dart';

void main() {
  test('signed out: unavailable, and the server is never asked', () async {
    final gateway = FakeDatingHomeGateway();
    final c = ProviderContainer(
      overrides: [
        datingHomeGatewayProvider.overrideWithValue(gateway),
        datingAccountProvider.overrideWithValue(null),
      ],
    );
    addTearDown(c.dispose);
    final home = await c.read(datingHomeProvider(null).future);
    expect(home.state, DatingHomeState.unavailable);
    expect(gateway.reads, 0);
  });

  test('D8: the next account starts empty while its read is held, and the '
      'last account\'s entry is disposed', () async {
    final gateway = FakeDatingHomeGateway(
      home: const DatingHome(state: DatingHomeState.active),
    );
    final account = StateProvider<String?>((ref) => 'ama');
    final c = ProviderContainer(
      overrides: [
        datingHomeGatewayProvider.overrideWithValue(gateway),
        datingAccountProvider.overrideWith((ref) => ref.watch(account)),
      ],
    );
    addTearDown(c.dispose);
    final first = c.listen(datingHomeProvider('ama'), (_, __) {});
    expect(
      (await c.read(datingHomeProvider('ama').future)).state,
      DatingHomeState.active,
    );
    gateway.hold = Completer<DatingHome>();
    c.read(account.notifier).state = 'kofi';
    final next = c.listen(datingHomeProvider('kofi'), (_, __) {});
    first.close();
    await Future<void>.delayed(Duration.zero);
    expect(c.read(datingHomeProvider('kofi')).hasValue, isFalse);
    expect(c.exists(datingHomeProvider('ama')), isFalse);
    gateway.hold!.complete(const DatingHome(state: DatingHomeState.notStarted));
    await Future<void>.delayed(Duration.zero);
    expect(
      c.read(datingHomeProvider('kofi')).value?.state,
      DatingHomeState.notStarted,
    );
    next.close();
  });
}
```

- [ ] **Step 6: Run the tests to see them fail**

Run: `flutter test test/features/dating/data 2>&1 | tail -3`
Expected: FAIL — compilation errors `Target of URI doesn't exist: 'package:attune/features/dating/data/dating_rpc.dart'` (and the other new files).

- [ ] **Step 7: Write the data layer**

Create `lib/features/dating/data/dating_supabase_client.dart` with exactly:

```dart
// Spec 2 W3a (§4.10, C-6, S-7): the one Supabase client every Dating
// repository uses. Today it is the app's own client; W4b replaces this
// provider's body with the Dating-scoped client that sends the trusted-device
// header. No repository changes then.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final datingSupabaseClientProvider = Provider<SupabaseClient>(
  (ref) => Supabase.instance.client,
);
```

Create `lib/features/dating/data/dating_rpc.dart` with exactly:

```dart
// Spec 2 W3a (§4.4, §4.10 RPC-only repository, Fable H3c): one way to call a
// Dating RPC. Every Dating read and write goes through here: no table is
// ever read directly (R11); a busy server is retried once (S2 W1 carried
// item 11); every call is bounded.
import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

typedef DatingRpcCall =
    Future<dynamic> Function(String fn, Map<String, dynamic>? params);

/// The server was still busy after its own three tries and the app's one.
class DatingBusy implements Exception {
  const DatingBusy();

  @override
  String toString() => 'DatingBusy';
}

class DatingRpc {
  DatingRpc(SupabaseClient client)
    : _call = ((fn, params) => client.rpc(fn, params: params));

  @visibleForTesting
  DatingRpc.withCall(DatingRpcCall call) : _call = call;

  final DatingRpcCall _call;

  static const timeout = Duration(seconds: 30);

  Future<dynamic> call(String fn, [Map<String, dynamic>? params]) async {
    for (var attempt = 1; ; attempt++) {
      try {
        return await _call(fn, params).timeout(timeout);
      } on PostgrestException catch (e) {
        if (e.message != 'dating:busy') rethrow;
        if (attempt == 1) continue;
        throw const DatingBusy();
      }
    }
  }
}

/// A lifecycle RPC's raised refusal, by its message (never its DETAIL).
enum DatingLifecycleError {
  pathNotDating,
  notPaused,
  activationRequired,
  resumeGatesNotMet,
  activationGatesNotMet,
  enrollmentIncomplete,
  consentRequired,
  profileIncomplete,
  reverifyDevice,
  notEligible,
  rateLimited,
  busy,
  failed;

  static DatingLifecycleError of(Object error) {
    if (error is DatingBusy) return busy;
    if (error is! PostgrestException) return failed;
    return switch (error.message) {
      'path_not_dating' => pathNotDating,
      'not_paused' => notPaused,
      'activation_required' => activationRequired,
      'resume_gates_not_met' => resumeGatesNotMet,
      'activation_gates_not_met' => activationGatesNotMet,
      'enrollment_incomplete' => enrollmentIncomplete,
      'consent_required' ||
      'terms_consent_required' ||
      'dating_opt_in_required' => consentRequired,
      'profile_or_preferences_incomplete' => profileIncomplete,
      'reverify_device' => reverifyDevice,
      'not_eligible' => notEligible,
      'rate_limited' => rateLimited,
      _ => failed,
    };
  }
}

/// A setup writer's answer: `{ok: true, next_step}` or
/// `{ok: false, reason, field?, position?}`. Anything else is `failed`.
class DatingWrite {
  const DatingWrite({
    required this.ok,
    this.nextStep,
    this.reason,
    this.field,
    this.position,
  });

  static const busy = DatingWrite(ok: false, reason: 'busy');
  static const failed = DatingWrite(ok: false, reason: 'failed');

  final bool ok;
  final String? nextStep;
  final String? reason;
  final String? field;
  final int? position;

  factory DatingWrite.fromJson(Object? raw) {
    if (raw is! Map) return failed;
    final ok = raw['ok'] == true;
    String? text(String key) => raw[key] is String ? raw[key] as String : null;
    final position = raw['position'];
    return DatingWrite(
      ok: ok,
      nextStep: text('next_step'),
      reason: ok ? null : (text('reason') ?? 'failed'),
      field: text('field'),
      position: position is int ? position : null,
    );
  }
}

/// Runs [write] and turns a busy server or any failure into its answer.
Future<DatingWrite> datingWrite(Future<dynamic> Function() write) async {
  try {
    return DatingWrite.fromJson(await write());
  } on DatingBusy {
    return DatingWrite.busy;
  } catch (_) {
    return DatingWrite.failed;
  }
}

/// One idempotency key per action while the screen lives (Fable H3c): a
/// double tap sends the same key, so the server acts once; a changed answer
/// gets a new key, so it is never mistaken for a replay of the old one.
class DatingActionKeys {
  DatingActionKeys({String Function()? newKey})
    : _newKey = newKey ?? (() => const Uuid().v4());

  final String Function() _newKey;
  final _held = <String, (String, String)>{};

  String keyFor(String action, [Object? payload]) {
    final signature = '$payload';
    final held = _held[action];
    if (held != null && held.$1 == signature) return held.$2;
    final key = _newKey();
    _held[action] = (signature, key);
    return key;
  }
}
```

Create `lib/features/dating/data/dating_home.dart` with exactly:

```dart
// Spec 2 W3a (§3.1): what get_dating_home() says, and the open countries.
// An unknown or missing state is `unavailable`: the app never shows a state
// the server did not name (fail closed: never "you're live").

enum DatingHomeState {
  featureUnavailable('feature_unavailable'),
  countryClosed('country_closed'),
  regionClosed('region_closed'),
  reverifyDevice('reverify_device'),
  restricted('restricted'),
  hold('hold'),
  ageReview('age_review'),
  unavailable('unavailable'),
  paused('paused'),
  coolOff('cool_off'),
  active('active'),
  gentleWait('gentle_wait'),
  notStarted('not_started'),
  setupInProgress('setup_in_progress');

  const DatingHomeState(this.wire);

  final String wire;

  static DatingHomeState fromWire(Object? value) => values.firstWhere(
    (s) => s.wire == value,
    orElse: () => DatingHomeState.unavailable,
  );
}

/// Why Dating is paused (§4.3); NULL or a reason this app doesn't know is
/// [unknown] and gets the plain paused card (carry 9).
enum DatingPauseReason {
  user('user'),
  relationship('relationship'),
  pathChange('path_change'),
  sameGenderSwitch('same_gender_switch'),
  away('away'),
  accountParked('account_parked'),
  gates('gates'),
  unknown('');

  const DatingPauseReason(this.wire);

  final String wire;

  static DatingPauseReason fromWire(Object? value) => values.firstWhere(
    (r) => r != unknown && r.wire == value,
    orElse: () => DatingPauseReason.unknown,
  );
}

/// "Tell me when it's here" (§2.7): whether it can be asked for here, and
/// whether it already has been.
class DatingNotice {
  const DatingNotice({this.available = false, this.requested = false});

  final bool available;
  final bool requested;

  factory DatingNotice.fromJson(Object? raw) =>
      raw is Map
          ? DatingNotice(
            available: raw['available'] == true,
            requested: raw['requested'] == true,
          )
          : const DatingNotice();
}

class DatingHome {
  const DatingHome({
    required this.state,
    this.country,
    this.region,
    this.openRegions = const [],
    this.pauseReason = DatingPauseReason.unknown,
    this.firstDropAt,
    this.endedAt,
    this.opensAt,
    this.canShorten = false,
    this.hasData = false,
    this.nextStep,
    this.notice = const DatingNotice(),
  });

  final DatingHomeState state;
  final String? country;
  final String? region;
  final List<String> openRegions;
  final DatingPauseReason pauseReason;
  final DateTime? firstDropAt;
  final DateTime? endedAt;
  final DateTime? opensAt;
  final bool canShorten;

  /// The person has Dating data to leave or clear (a profile, an
  /// enrolment, a reflection, a notice request), whatever the state (C-2).
  final bool hasData;
  final String? nextStep;
  final DatingNotice notice;

  factory DatingHome.fromJson(Map<String, dynamic> json) {
    DateTime? at(String key) {
      final value = json[key];
      return value is String ? DateTime.tryParse(value) : null;
    }

    String? text(String key) =>
        json[key] is String ? json[key] as String : null;
    final regions = json['open_regions'];
    return DatingHome(
      state: DatingHomeState.fromWire(json['state']),
      country: text('country'),
      region: text('region'),
      openRegions:
          regions is List ? regions.whereType<String>().toList() : const [],
      pauseReason: DatingPauseReason.fromWire(json['pause_reason']),
      firstDropAt: at('first_drop_at'),
      endedAt: at('ended_at'),
      opensAt: at('opens_at'),
      canShorten: json['can_shorten'] == true,
      hasData: json['has_data'] == true,
      nextStep: text('next_step'),
      notice: DatingNotice.fromJson(json['notify']),
    );
  }

  /// A Dating profile exists, so Dating settings have something to show.
  bool get hasProfile => const {
    DatingHomeState.setupInProgress,
    DatingHomeState.gentleWait,
    DatingHomeState.coolOff,
    DatingHomeState.active,
    DatingHomeState.paused,
  }.contains(state);
}

/// One open country (get_dating_availability): its open regions' name keys,
/// or null when every region is open.
class DatingOpenCountry {
  const DatingOpenCountry({required this.code, this.openRegionKeys});

  final String code;
  final List<String>? openRegionKeys;
}

class DatingAvailability {
  const DatingAvailability({this.countries = const []});

  final List<DatingOpenCountry> countries;

  bool isOpen(String? code) => countries.any((c) => c.code == code);

  factory DatingAvailability.fromJson(Map<String, dynamic> json) {
    final raw = json['countries'];
    if (raw is! List) return const DatingAvailability();
    return DatingAvailability(
      countries: [
        for (final c in raw.whereType<Map>())
          if (c['code'] is String)
            DatingOpenCountry(
              code: c['code'] as String,
              openRegionKeys:
                  c['open_regions'] is List
                      ? [
                        for (final r
                            in (c['open_regions'] as List).whereType<Map>())
                          if (r['name_key'] is String) r['name_key'] as String,
                      ]
                      : null,
            ),
      ],
    );
  }
}
```

Create `lib/features/dating/data/dating_home_repository.dart` with exactly:

```dart
// Spec 2 W3a (§3.1, §2.7, §3.10): the home, the open countries and "Tell me
// when it's here", RPC-only.
import 'package:attune/features/dating/data/dating_home.dart';
import 'package:attune/features/dating/data/dating_rpc.dart';

enum DatingNoticeResult { saved, alreadyOpen, invalid, busy, failed }

abstract class DatingHomeGateway {
  Future<DatingHome> read();

  Future<DatingAvailability> availability();

  Future<DatingNoticeResult> requestNotice(String country, {String? region});

  /// Never gated (exposure-reducing).
  Future<DatingNoticeResult> cancelNotice();
}

class DatingHomeRepository implements DatingHomeGateway {
  DatingHomeRepository(this._rpc);

  final DatingRpc _rpc;

  @override
  Future<DatingHome> read() async => DatingHome.fromJson(
    Map<String, dynamic>.from(await _rpc.call('get_dating_home') as Map),
  );

  @override
  Future<DatingAvailability> availability() async =>
      DatingAvailability.fromJson(
        Map<String, dynamic>.from(
          await _rpc.call('get_dating_availability') as Map,
        ),
      );

  @override
  Future<DatingNoticeResult> requestNotice(String country, {String? region}) =>
      _notice(
        () => _rpc.call('request_dating_country_notice', {
          'p_country': country,
          'p_region': region,
        }),
      );

  @override
  Future<DatingNoticeResult> cancelNotice() =>
      _notice(() => _rpc.call('cancel_dating_country_notice'));

  Future<DatingNoticeResult> _notice(Future<dynamic> Function() call) async {
    final w = await datingWrite(call);
    if (w.ok) return DatingNoticeResult.saved;
    return switch (w.reason) {
      'already_open' => DatingNoticeResult.alreadyOpen,
      'invalid' => DatingNoticeResult.invalid,
      'busy' => DatingNoticeResult.busy,
      _ => DatingNoticeResult.failed,
    };
  }
}
```

Create `lib/features/dating/data/dating_lifecycle_repository.dart` with exactly:

```dart
// Spec 2 W3a (§3.8, §4.4 Lifecycle; carries 1, 12, 13): pause, resume,
// activate and leave (exit v2: one hard delete; the never-introduce list
// kept only if ticked, R-2). Each returns the enrolment's new state or the
// named refusal; exit may answer `suspended` (W1 B10 M-8).
import 'package:attune/features/dating/data/dating_rpc.dart';

class DatingLifecycleResult {
  const DatingLifecycleResult.done(this.state) : error = null;

  const DatingLifecycleResult.refused(DatingLifecycleError this.error)
    : state = null;

  final String? state;
  final DatingLifecycleError? error;

  bool get ok => error == null;
}

abstract class DatingLifecycleGateway {
  Future<DatingLifecycleResult> pause(String key);

  Future<DatingLifecycleResult> resume(String key);

  Future<DatingLifecycleResult> activate(String key);

  Future<DatingLifecycleResult> exit(
    String key, {
    required bool keepNeverIntroduce,
  });
}

class DatingLifecycleRepository implements DatingLifecycleGateway {
  DatingLifecycleRepository(this._rpc);

  final DatingRpc _rpc;

  Future<DatingLifecycleResult> _run(
    String fn,
    Map<String, dynamic> params,
  ) async {
    try {
      final row = await _rpc.call(fn, params);
      final state =
          row is Map && row['state'] is String ? row['state'] as String : null;
      return DatingLifecycleResult.done(state);
    } catch (e) {
      return DatingLifecycleResult.refused(DatingLifecycleError.of(e));
    }
  }

  @override
  Future<DatingLifecycleResult> pause(String key) =>
      _run('pause_dating_mode', {'p_idempotency_key': key});

  @override
  Future<DatingLifecycleResult> resume(String key) =>
      _run('resume_dating_mode', {'p_idempotency_key': key});

  @override
  Future<DatingLifecycleResult> activate(String key) =>
      _run('activate_dating_profile', {'p_idempotency_key': key});

  @override
  Future<DatingLifecycleResult> exit(
    String key, {
    required bool keepNeverIntroduce,
  }) => _run('exit_dating_mode', {
    'p_idempotency_key': key,
    'p_keep_never_introduce': keepNeverIntroduce,
  });
}
```

Create `lib/features/dating/data/dating_providers.dart` with exactly:

```dart
// Spec 2 W3a (§4.10 per-state providers; D8 shared phones): every Dating
// read belongs to the signed-in account, lives in memory only, and is
// disposed when nothing shows it. Another account on the same phone starts
// from nothing.
import 'package:attune/features/auth/providers/auth_provider.dart'
    show currentUserProvider;
import 'package:attune/features/dating/data/dating_home.dart';
import 'package:attune/features/dating/data/dating_home_repository.dart';
import 'package:attune/features/dating/data/dating_lifecycle_repository.dart';
import 'package:attune/features/dating/data/dating_rpc.dart';
import 'package:attune/features/dating/data/dating_supabase_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The signed-in account's id (null when signed out).
final datingAccountProvider = Provider<String?>(
  (ref) => ref.watch(currentUserProvider.select((u) => u?.id)),
);

final datingRpcProvider = Provider<DatingRpc>(
  (ref) => DatingRpc(ref.watch(datingSupabaseClientProvider)),
);

final datingHomeGatewayProvider = Provider<DatingHomeGateway>(
  (ref) => DatingHomeRepository(ref.watch(datingRpcProvider)),
);

final datingLifecycleGatewayProvider = Provider<DatingLifecycleGateway>(
  (ref) => DatingLifecycleRepository(ref.watch(datingRpcProvider)),
);

/// The home, one entry per account: the next account's entry starts as a
/// plain loading value, never holding the last one's state.
final datingHomeProvider = FutureProvider.autoDispose
    .family<DatingHome, String?>((ref, account) async {
      if (account == null) {
        return const DatingHome(state: DatingHomeState.unavailable);
      }
      return ref.read(datingHomeGatewayProvider).read();
    });

/// The countries Dating is open in (config, no personal data).
final datingAvailabilityProvider =
    FutureProvider.autoDispose<DatingAvailability>(
      (ref) => ref.read(datingHomeGatewayProvider).availability(),
    );
```

Replace the whole of `lib/features/dating/domain/services/dating_feature_flags.dart` with exactly (the file is rewritten whole, so it is formatted as a new file):

```dart
import 'package:supabase_flutter/supabase_flutter.dart';

class DatingFeatureFlags {
  static const String datingModeEnabled = 'dating_mode_enabled';
  static const String candidateGeneration = 'dating_candidate_generation';
  static const String matchMessaging = 'dating_match_messaging';
  static const String profilePhotos = 'dating_profile_photos';

  // These `dating_*` keys are authored and read server-side only (RLS hides
  // them from clients, DATING-H1). Listed as the canonical names; the client
  // never reads their values.

  /// Whether Dating is available to this client (Spec 2 W3a, I-4): from
  /// get_dating_home(), which answers `feature_unavailable` when the switch
  /// is off. Any error or unexpected shape is false.
  static Future<bool> isDatingModeAvailable(SupabaseClient supabase) async {
    try {
      final result = await supabase.rpc('get_dating_home');
      if (result is! Map) return false;
      final state = result['state'];
      return state is String && state != 'feature_unavailable';
    } catch (_) {
      return false;
    }
  }
}
```

(`alignmentAlgorithmV1` is gone with the alignment algorithm (W5 drops the flag); nothing in `lib/` or `test/` names it — `grep -rn alignmentAlgorithmV1 lib test` prints nothing after this step.)

- [ ] **Step 8: Format the new files and run the tests**

```bash
dart format lib/features/dating/data/dating_supabase_client.dart lib/features/dating/data/dating_rpc.dart lib/features/dating/data/dating_home.dart lib/features/dating/data/dating_home_repository.dart lib/features/dating/data/dating_lifecycle_repository.dart lib/features/dating/data/dating_providers.dart test/features/dating/data test/features/dating/support/dating_fakes.dart lib/features/dating/domain/services/dating_feature_flags.dart
flutter analyze --no-pub lib/features/dating test/features/dating 2>&1 | tail -1
flutter test test/features/dating/data 2>&1 | tail -1
grep -rn "alignmentAlgorithmV1\|DatingMonitoring" lib test
```

Expected: `Formatted …`; `No issues found!` (the v1 files under `presentation/` still compile against the old repository: they are untouched until Task 2); `All tests passed!` (36 tests); no `grep` output.

- [ ] **Step 9: Do not commit; record the tree in the report**

Run the tree command from Global Constraints and paste its hash and the test counts into the report.

### Task 2: The `/dating` route group behind the Dating lock, `me_update` push routing, the device-wipe line, D0 routed, v1 removed (§3.0 Lock, §3.13, §3.14, §4.10, R1–R3, R11, R21; carries 6, 7 (client), 11, 12, 14; R-8–R-12)

**Files:**
- Create: `lib/features/dating/lock/dating_unlock.dart`, `lib/features/dating/dating_device_wipes.dart`, `lib/features/dating/routes/dating_routes.dart`, `lib/features/dating/routes/dating_setup_steps.dart`
- Create: `test/features/dating/support/dating_shell.dart`, `test/features/dating/routes/dating_routes_test.dart`, `test/features/dating/gentle_wait/gentle_wait_states_test.dart`, `test/core/notifications/me_update_routing_test.dart`, `test/architecture/dating_rpc_only_test.dart`, `test/architecture/dating_boundaries_test.dart`, `$D/{dmut.py, mut_T2.py, edit_T2.py, arb_fragment_T2.txt}`
- Modify: `lib/app/routing/app_router.dart` (the Dating block, its imports and the seven `RouteNames.dating*` only), `lib/core/notifications/config/notification_config.dart` (one case), `lib/app/device_wipes.dart` (one import, one call), `lib/app/text_scale_policy.dart` (one prefix), `lib/features/dating/gentle_wait/gentle_wait_screen.dart` (carry 7), `lib/features/dating/data/models/dating_enrollment.dart` (§4.10: no adults flag, `pauseReason`), `lib/features/ai_assistant/data/services/ai_session_capabilities.dart` (one comment), `lib/i10n/app_en.arb` + generated, `test/architecture/text_scale_routes_test.dart`, `test/app/routing/app_router_sign_in_test.dart`, `test/app/routing/feature_intro_route_wiring_test.dart`, `test/features/chat/chat_couples_locked_screen_healing_entry_test.dart`
- Delete: `lib/features/dating/data/repositories/dating_repository.dart`, `lib/features/dating/presentation/` (providers + the seven v1 screens), `test/features/dating/dating_dashboard_never_gates_on_healing_test.dart`, `test/features/dating/dating_profile_activation_marks_intro_seen_test.dart`

**Interfaces:**
- Consumes: Task 1's providers; `datingLockProvider`, `datingLockAccountProvider`, `confirmSafetyPin`, `DeviceWipeRegistry`, `homeLocation`, `GentleWaitScreen`.
- Produces: `datingUnlockPath = '/dating/unlock'`; `DatingSessionMemory.track(Object owner, Ref ref, void Function() clear)` / `clear()`; `datingUnlockedProvider` (`NotifierProvider<DatingUnlock, bool>`, `unlock()`, `lock()`); `Future<String?> datingRedirect(BuildContext, GoRouterState, {required bool signedIn})`; `String datingSafeReturn(String? from)`; `DatingUnlockScreen({required String from})`; `registerDatingDeviceWipes([DeviceWipeRegistry?])`; `DatingPaths` (`unlock`, `settings`, `notOpen`, `leave`, `step(String)`, `notOpenFor({country, region})`); `DatingMotion {sharedAxis, fade, none}`, `datingPage(GoRouterState, Widget, {DatingMotion motion})`, `datingStepMotion(String)`, `kDatingCrossFade`; `List<RouteBase> datingRoutes({required bool Function() signedIn})`; `datingSetupOrder`, `int? datingStepNumber(String)`, `DatingStepNav({next, back, toMe})`, `Widget? datingStepScreen(String step, DatingStepNav nav)`, `DatingSetupStepRoute({required String step})`, `DatingWaitStep({required DatingStepNav nav})`; test helper `pumpDatingShell(…)` → `DatingShell`.

- [ ] **Step 1: Write the failing tests**

Create `test/features/dating/support/dating_shell.dart` with exactly:

```dart
// Spec 2 W3: the app's Dating route group in a test router, every Dating
// gateway faked, and the places Dating sends people stubbed by name.
import 'package:attune/app/routing/app_router.dart' show RouteNames;
import 'package:attune/app/theme/app_theme.dart';
import 'package:attune/core/utils/screen_util_config.dart';
import 'package:attune/features/auth/providers/auth_provider.dart'
    show currentUserProvider;
import 'package:attune/features/dating/data/dating_providers.dart';
import 'package:attune/features/dating/gentle_wait/gentle_wait_providers.dart';
import 'package:attune/features/dating/gentle_wait/gentle_wait_repository.dart';
import 'package:attune/features/dating/routes/dating_routes.dart';
import 'package:attune/features/safety/data/dating_lock_store.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../helpers/home_harness.dart' show testUser;
import 'dating_fakes.dart';

class FakeLock extends DatingLockStore {
  FakeLock(this.on, {this.unreadable = false});

  bool on;
  final bool unreadable;

  @override
  Future<bool> isOn() async {
    if (unreadable) throw StateError('keystore');
    return on;
  }

  @override
  Future<void> setOn(bool value) async => on = value;
}

class FakeWait implements GentleWaitGateway {
  GentleWait value = GentleWait(
    endedAt: DateTime.utc(2026, 11, 1, 10),
    opensAt: DateTime.utc(2026, 12, 1, 10),
    answers: const {'q1': 'Patience with myself'},
  );
  Object? readError;
  GentleWaitSave result = GentleWaitSave.saved;
  final saves = <Map<String, String>>[];
  int reads = 0;
  int clears = 0;

  @override
  Future<GentleWait> read() async {
    reads++;
    final error = readError;
    if (error != null) throw error;
    return value;
  }

  @override
  Future<GentleWaitSave> save(Map<String, String> answers) async {
    saves.add(answers);
    return result;
  }

  @override
  Future<GentleWaitSave> clear() async {
    clears++;
    return result;
  }
}

/// The signed-in account in every Dating shell (D8 tests switch it).
final datingTestAccount = StateProvider<String?>((ref) => 'ama');

class DatingShell {
  DatingShell(
    this.tester,
    this.router,
    this.home,
    this.life,
    this.wait,
    this.lock,
  );

  final WidgetTester tester;
  final GoRouter router;
  final FakeDatingHomeGateway home;
  final FakeDatingLifecycleGateway life;
  final FakeWait wait;
  final FakeLock lock;

  String get location =>
      router.routerDelegate.currentConfiguration.uri.toString();

  ProviderContainer get container =>
      ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
}

Future<DatingShell> pumpDatingShell(
  WidgetTester t, {
  String initial = '/home',
  bool locked = false,
  bool lockUnreadable = false,
  bool pinSet = false,
  bool signedIn = true,
  bool online = true,
  double textScale = 1.0,
  FakeDatingHomeGateway? home,
  List<Override> overrides = const [],
  Widget Function(GoRouter router, Widget child)? wrap,
}) async {
  // A fresh ProviderScope each time (pumpWidget would reuse the last one).
  await t.pumpWidget(const SizedBox());
  t.view.physicalSize = const Size(390, 844);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  t.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(t.platformDispatcher.clearAllTestValues);
  SharedPreferences.setMockInitialValues({});
  FlutterSecureStorage.setMockInitialValues({
    // A well-formed hash is a PIN (SafetyPinStore.hasPin); never checked here.
    if (pinSet) 'safety_pin_hash': r'v1$c2FsdA$aGFzaA$100000',
  });
  final homeGateway = home ?? FakeDatingHomeGateway();
  final life = FakeDatingLifecycleGateway();
  final wait = FakeWait();
  final lock = FakeLock(locked, unreadable: lockUnreadable);
  final router = GoRouter(
    initialLocation: initial,
    routes: [
      GoRoute(
        path: RouteNames.home,
        builder:
            (_, s) => Scaffold(
              body: Text('ME ${s.uri.queryParameters['tab'] ?? ''}'),
            ),
      ),
      for (final (path, label) in [
        (RouteNames.login, 'LOGIN'),
        (RouteNames.safetyPin, 'PIN SETUP'),
        (RouteNames.howYouUseAttune, 'HOW YOU USE ATTUNE'),
        (RouteNames.reflectionJournal, 'JOURNAL'),
        (RouteNames.healingJourney, 'HEALING'),
      ])
        GoRoute(path: path, builder: (_, __) => Scaffold(body: Text(label))),
      GoRoute(
        path: RouteNames.neutralScreen,
        name: 'neutralScreen',
        builder: (_, __) => const Scaffold(body: Text('DECOY')),
      ),
      ...datingRoutes(signedIn: () => signedIn),
    ],
  );
  addTearDown(router.dispose);
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        currentUserProvider.overrideWith((ref) {
          final id = ref.watch(datingTestAccount);
          return id == null ? null : testUser(id);
        }),
        datingAccountProvider.overrideWith(
          (ref) => ref.watch(datingTestAccount),
        ),
        gentleWaitAccountProvider.overrideWith(
          (ref) => ref.watch(datingTestAccount),
        ),
        datingLockStoreProvider.overrideWithValue(lock),
        datingLockAccountProvider.overrideWith(
          (ref) => Stream.value(ref.watch(datingTestAccount)),
        ),
        datingHomeGatewayProvider.overrideWithValue(homeGateway),
        datingLifecycleGatewayProvider.overrideWithValue(life),
        gentleWaitGatewayProvider.overrideWithValue(wait),
        datingOnlineProvider.overrideWith((ref) => Stream.value(online)),
        ...overrides,
      ],
      child: ScreenUtilConfig.builder(
        builder:
            (_) => MaterialApp.router(
              theme: AppTheme.lightTheme,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              routerConfig: router,
              builder:
                  (context, child) =>
                      wrap == null ? child! : wrap(router, child!),
            ),
      ),
    ),
  );
  await t.pumpAndSettle();
  return DatingShell(t, router, homeGateway, life, wait, lock);
}

/// The Dating overrides for a screen pumped alone (pumpFlowScreen).
List<Override> datingShellOverrides({
  FakeDatingHomeGateway? home,
  FakeDatingLifecycleGateway? life,
  FakeWait? wait,
  bool online = true,
}) => [
  currentUserProvider.overrideWith((ref) {
    final id = ref.watch(datingTestAccount);
    return id == null ? null : testUser(id);
  }),
  datingAccountProvider.overrideWith((ref) => ref.watch(datingTestAccount)),
  gentleWaitAccountProvider.overrideWith((ref) => ref.watch(datingTestAccount)),
  datingLockStoreProvider.overrideWithValue(FakeLock(false)),
  datingLockAccountProvider.overrideWith(
    (ref) => Stream.value(ref.watch(datingTestAccount)),
  ),
  datingHomeGatewayProvider.overrideWithValue(home ?? FakeDatingHomeGateway()),
  datingLifecycleGatewayProvider.overrideWithValue(
    life ?? FakeDatingLifecycleGateway(),
  ),
  gentleWaitGatewayProvider.overrideWithValue(wait ?? FakeWait()),
  datingOnlineProvider.overrideWith((ref) => Stream.value(online)),
];
```

Create `test/features/dating/routes/dating_routes_test.dart` with exactly:

```dart
// Spec 2 W3a (§3.0 Lock, §3.14; R-8, R-9, R-10; carry 6): one redirect for
// every Dating route: signed in, then the Dating lock; D0 routed; quick
// exit takes the unlock and D0's typed answers with it.
import 'package:attune/core/device/device_wipe_registry.dart';
import 'package:attune/features/dating/data/dating_home.dart';
import 'package:attune/features/dating/dating_device_wipes.dart';
import 'package:attune/features/dating/lock/dating_unlock.dart';
import 'package:attune/features/dating/routes/dating_routes.dart';
import 'package:attune/features/dating/routes/dating_setup_steps.dart';
import 'package:attune/features/safety/domain/services/quick_exit_service.dart';
import 'package:attune/features/safety/presentation/widgets/quick_exit_zone.dart';
import 'package:attune/features/stories/data/story_device_wipe.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/flow_harness.dart';
import '../../../helpers/tap_in_reach.dart';
import '../support/dating_fakes.dart';
import '../support/dating_shell.dart';

void main() {
  setUpAll(() => registerDatingDeviceWipes(DeviceWipeRegistry.instance));

  testWidgets('signed out: every Dating route goes to sign in', (t) async {
    for (final path in [DatingPaths.step('wait'), DatingPaths.unlock]) {
      final s = await pumpDatingShell(t, initial: path, signedIn: false);
      expect(find.text('LOGIN'), findsOneWidget, reason: path);
      expect(s.location, '/login');
    }
  });

  testWidgets('lock off: D0 opens straight away at /dating/setup/wait', (
    t,
  ) async {
    final s = await pumpDatingShell(t, initial: DatingPaths.step('wait'));
    expect(find.text('Before you begin'), findsOneWidget);
    expect(s.location, '/dating/setup/wait');
  });

  testWidgets('lock on: a deep link to a step asks for the PIN first', (
    t,
  ) async {
    final s = await pumpDatingShell(
      t,
      initial: DatingPaths.step('wait'),
      locked: true,
      pinSet: true,
    );
    expect(s.location, startsWith('/dating/unlock?from='));
    expect(find.text('Enter your Safety PIN'), findsOneWidget);
    expect(find.text('Before you begin'), findsNothing);
  });

  testWidgets('lock on, no PIN set: the unlock goes on to the step asked for', (
    t,
  ) async {
    final s = await pumpDatingShell(
      t,
      initial: DatingPaths.step('wait'),
      locked: true,
    );
    expect(find.text('Before you begin'), findsOneWidget);
    expect(s.location, '/dating/setup/wait');
    expect(s.container.read(datingUnlockedProvider), isTrue);
  });

  testWidgets('the unlock ends when the app is put away', (t) async {
    final s = await pumpDatingShell(
      t,
      initial: DatingPaths.step('wait'),
      locked: true,
    );
    expect(s.container.read(datingUnlockedProvider), isTrue);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await t.pump();
    expect(s.container.read(datingUnlockedProvider), isFalse);
  });

  testWidgets('an unreadable lock setting asks for the PIN (fail closed)', (
    t,
  ) async {
    final s = await pumpDatingShell(
      t,
      initial: DatingPaths.step('wait'),
      lockUnreadable: true,
      pinSet: true,
    );
    expect(s.location, startsWith('/dating/unlock'));
  });

  test('an unlock never returns outside Dating (no open redirect)', () {
    expect(datingSafeReturn('/dating/setup/where'), '/dating/setup/where');
    for (final from in [
      null,
      '',
      '/home',
      'https://example.com/dating/x',
      '//evil/dating/x',
      '/dating/unlock?from=/dating/setup/how',
      '/dating/../home',
    ]) {
      expect(datingSafeReturn(from), startsWith('/home?tab=me'), reason: from);
    }
  });

  testWidgets('a step no batch has built yet opens Me', (t) async {
    final s = await pumpDatingShell(t, initial: DatingPaths.step('nowhere'));
    expect(find.text('ME me'), findsOneWidget);
    expect(s.location, startsWith('/home?tab=me'));
  });

  test(
    'step numbers: looking-for is 1, ready is 12; how and wait have none',
    () {
      expect(datingStepNumber('looking-for'), 1);
      expect(datingStepNumber('ready'), 12);
      expect(datingStepNumber('how'), isNull);
      expect(datingStepNumber('wait'), isNull);
      expect(datingSetupOrder.length, 13);
    },
  );

  test(
    'motion: D0, D4 and D13 never move; D12 cross-fades; the rest slide',
    () {
      expect(datingStepMotion('wait'), DatingMotion.none);
      expect(datingStepMotion('privacy'), DatingMotion.none);
      expect(datingStepMotion('ready'), DatingMotion.none);
      expect(datingStepMotion('preview'), DatingMotion.fade);
      expect(datingStepMotion('where'), DatingMotion.sharedAxis);
    },
  );

  testWidgets('D0: "Set up Dating now" opens the saved next step', (t) async {
    final home = FakeDatingHomeGateway(
      home: const DatingHome(
        state: DatingHomeState.gentleWait,
        nextStep: 'looking-for',
      ),
    );
    final steps = <String>[];
    await pumpFlowScreen(
      t,
      () => DatingWaitStep(
        nav: DatingStepNav(next: steps.add, back: () {}, toMe: () {}),
      ),
      overrides: datingShellOverrides(home: home),
    );
    await tapInReach(t, find.text('Set up Dating now'));
    await t.pumpAndSettle();
    expect(steps, ['looking-for']);
  });

  group('quick exit (carry 6, R-9)', () {
    setUp(() {
      QuickExitService.clearStories = () async {};
      addTearDown(() => QuickExitService.clearStories = clearStoryDeviceCaches);
    });

    testWidgets('from D0 on the real route: the typed answers and the unlock '
        'go with it', (t) async {
      final s = await pumpDatingShell(
        t,
        initial: DatingPaths.step('wait'),
        locked: true,
        wrap: (router, child) => QuickExitZone(router: router, child: child),
      );
      expect(s.container.read(datingUnlockedProvider), isTrue);
      await t.enterText(
        find.byKey(const ValueKey('gentle_wait_q3')),
        'Ama typed this',
      );
      for (var i = 0; i < 3; i++) {
        await t.tap(
          find.byKey(const Key('quick_exit_zone')),
          warnIfMissed: false,
        );
        await t.pump(const Duration(milliseconds: 50));
      }
      await t.pumpAndSettle(const Duration(milliseconds: 400));
      expect(find.text('DECOY'), findsOneWidget);
      expect(s.container.read(datingUnlockedProvider), isFalse);
      // The lock itself is protective: still on (D19).
      expect(s.lock.on, isTrue);
      // Back on D0 (no PIN on this phone, so the unlock lets it through):
      // a new read, and nothing typed before is left.
      final reads = s.wait.reads;
      s.router.go(DatingPaths.step('wait'));
      await t.pumpAndSettle();
      expect(s.location, '/dating/setup/wait');
      expect(s.wait.reads, reads + 1);
      expect(find.text('Ama typed this'), findsNothing);
    });
  });
}
```

(`datingShellOverrides`, the overrides the screen tests share, is the last function in the block above.)

Create `test/features/dating/gentle_wait/gentle_wait_states_test.dart` with exactly:

```dart
// Spec 2 W3a (W2 carry, batch-5 M-3): D0 names "not eligible" and "confirm
// it's you" as their own states, and an untrusted phone can still clear.
import 'package:attune/features/dating/gentle_wait/gentle_wait_repository.dart';
import 'package:attune/features/dating/gentle_wait/gentle_wait_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/flow_harness.dart';
import '../../../helpers/tap_in_reach.dart';
import '../support/dating_shell.dart';

Future<FakeWait> _open(WidgetTester t, {Object? readError}) async {
  final wait = FakeWait()..readError = readError;
  await pumpFlowScreen(
    t,
    () => GentleWaitScreen(onSetUp: () {}),
    overrides: datingShellOverrides(wait: wait),
  );
  await t.pumpAndSettle();
  return wait;
}

void main() {
  testWidgets('a save refused as not eligible says so, not "went wrong"', (
    t,
  ) async {
    final wait = await _open(t);
    wait.result = GentleWaitSave.notEligible;
    await t.enterText(find.byKey(const ValueKey('gentle_wait_q2')), 'Calm');
    await tapInReach(t, find.text('Save my answers'));
    await t.pumpAndSettle();
    expect(
      find.text(
        "Dating isn't available on this account right now, so your answers "
        "weren't saved.",
      ),
      findsOneWidget,
    );
    expect(find.text('Something went wrong. Try again.'), findsNothing);
  });

  testWidgets('a save on an untrusted phone asks to confirm it\'s you', (
    t,
  ) async {
    final wait = await _open(t);
    wait.result = GentleWaitSave.reverifyDevice;
    await t.enterText(find.byKey(const ValueKey('gentle_wait_q2')), 'Calm');
    await tapInReach(t, find.text('Save my answers'));
    await t.pumpAndSettle();
    expect(
      find.text("Confirm it's you on this phone to see Dating."),
      findsOneWidget,
    );
  });

  testWidgets('an unreadable reflection on an untrusted phone still offers '
      'the clear, which needs no device', (t) async {
    final wait = await _open(
      t,
      readError: const GentleWaitUnavailable('reverify_device'),
    );
    expect(
      find.text("Confirm it's you on this phone to see Dating."),
      findsOneWidget,
    );
    expect(find.text('Patience with myself'), findsNothing);
    await tapInReach(t, find.text('Clear my answers'));
    await t.pumpAndSettle();
    expect(wait.clears, 1);
    expect(wait.saves, isEmpty);
    expect(find.text('Your answers are cleared.'), findsOneWidget);
    await expectFlowGuidelines(t);
  });
}
```

Create `test/core/notifications/me_update_routing_test.dart` with exactly:

```dart
// Spec 2 W3a (§3.13, I-9, A-7): the neutral Dating push opens Me; the old
// match push opens Me too for one release.
import 'package:attune/app/routing/app_router.dart' show RouteNames;
import 'package:attune/core/notifications/config/notification_config.dart';
import 'package:attune/core/notifications/domain/entities/app_notification.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  for (final type in ['me_update', 'dating_mutual_match']) {
    testWidgets('$type opens Me (/home?tab=me)', (tester) async {
      late BuildContext tapContext;
      final router = GoRouter(
        initialLocation: '/somewhere',
        routes: [
          GoRoute(
            path: '/somewhere',
            builder:
                (context, _) => Builder(
                  builder: (c) {
                    tapContext = c;
                    return const Text('ELSEWHERE');
                  },
                ),
          ),
          GoRoute(
            path: RouteNames.home,
            builder: (_, s) => Text('HOME ${s.uri.queryParameters['tab']}'),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      buildNanoEmbryoNotificationConfig().onNotificationTap!(
        AppNotification(
          id: 'n1',
          title: 'Attune',
          body: 'You have something new in Attune.',
          data: {'type': type, 'route': 'me'},
          createdAt: DateTime.utc(2026, 11, 7, 20),
        ),
        tapContext,
      );
      await tester.pumpAndSettle();
      expect(find.text('HOME me'), findsOneWidget);
    });
  }
}
```

Create `test/architecture/dating_rpc_only_test.dart` with exactly:

```dart
// Spec 2 W3a (R11, R21, I-4; W1 B10 M-9): the app reads Dating only through
// RPCs, never calls the dropped shim, and keeps no v1 writer or purpose.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

Iterable<File> _libDart() => Directory('lib')
    .listSync(recursive: true)
    .whereType<File>()
    .where(
      (f) => f.path.endsWith('.dart') && !f.path.contains('/i10n/generated/'),
    );

void _noneMatch(RegExp pattern) {
  final hits = [
    for (final f in _libDart())
      if (pattern.hasMatch(f.readAsStringSync())) f.path,
  ];
  expect(hits, isEmpty, reason: pattern.pattern);
}

void main() {
  test("no direct read of a Dating table (.from('dating_…'))", () {
    _noneMatch(RegExp(r'''\.from\(\s*['"]dating_'''));
  });
  test('no caller of get_dating_eligibility', () {
    _noneMatch(RegExp('get_dating_eligibility'));
  });
  test('no v1 writer: delete_dating_profile, save_dating_profile_draft', () {
    _noneMatch(RegExp(r'delete_dating_profile(?!_photo)'));
    _noneMatch(RegExp('save_dating_profile_draft'));
  });
  test("no v1 consent purpose: 'historical_data', 'age_gate'", () {
    _noneMatch(RegExp(r'''['"](historical_data|age_gate)['"]'''));
  });
}
```

Create `test/architecture/dating_boundaries_test.dart` with exactly:

```dart
// Spec 2 W3a (§7.4, C-2, C-3, D8): Dating imports nothing from chat or
// Games; quick exit and sign-out name no Dating file; Dating's providers
// that hold data are autoDispose.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

Iterable<File> _dating() => Directory('lib/features/dating')
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'));

void main() {
  test('no chat or Games import; ChatScreen never named', () {
    for (final f in _dating()) {
      final src = f.readAsStringSync();
      expect(
        src,
        isNot(contains('package:attune/features/chat/')),
        reason: f.path,
      );
      expect(
        src,
        isNot(contains('package:attune/features/games/')),
        reason: f.path,
      );
      expect(src, isNot(contains('ChatScreen')), reason: f.path);
    }
  });

  test('quick exit and sign-out reach Dating only through the registry', () {
    for (final path in [
      'lib/features/safety/domain/services/quick_exit_service.dart',
      'lib/features/auth/providers/auth_provider.dart',
    ]) {
      final src = File(path).readAsStringSync();
      expect(src, isNot(contains('features/dating')), reason: path);
      // No Dating identifier (a comment may say "the Dating lock"; I-13).
      expect(src, isNot(matches(RegExp(r'\bDating[A-Z]\w*'))), reason: path);
    }
  });

  test('every Dating provider that holds data is autoDispose (D8)', () {
    final holding = RegExp(
      r'\b(FutureProvider|StreamProvider|StateProvider|StateNotifierProvider|'
      r'AsyncNotifierProvider|ChangeNotifierProvider)\b(?!\.autoDispose)',
    );
    for (final f in _dating()) {
      for (final line in f.readAsLinesSync()) {
        if (line.trimLeft().startsWith('//')) continue;
        expect(holding.hasMatch(line), isFalse, reason: '${f.path}: $line');
      }
    }
  });
}
```

- [ ] **Step 2: Run them to see them fail**

Run: `flutter test test/features/dating/routes test/features/dating/gentle_wait/gentle_wait_states_test.dart test/core/notifications/me_update_routing_test.dart test/architecture/dating_rpc_only_test.dart test/architecture/dating_boundaries_test.dart 2>&1 | tail -3`
Expected: FAIL — `Target of URI doesn't exist: 'package:attune/features/dating/lock/dating_unlock.dart'` (the routes and shell tests), and in `dating_rpc_only_test.dart` `lib/features/dating/data/repositories/dating_repository.dart` and `lib/features/ai_assistant/data/services/ai_session_capabilities.dart` listed as hits; `dating_boundaries_test.dart` lists `lib/features/dating/presentation/providers/dating_providers.dart` lines (`FutureProvider<…>` without autoDispose) and the v1 screens' `quick_exit_service` import does not matter (only the reverse is checked).

- [ ] **Step 3: The strings**

Create `$D/arb_fragment_T2.txt` with exactly:

```
  "dating_unlockButton": "Enter my PIN",
  "@dating_unlockButton": {
    "description": "The Dating lock's PIN screen: asks for the Safety PIN again after the sheet was dismissed (Spec 2 W3a, R-8)."
  },

  "dating_sectionReverify": "Confirm it's you on this phone to see Dating.",
  "@dating_sectionReverify": {
    "description": "Spec 2 §3.1 state reverify_device, and D0 when the phone isn't trusted (W2 carry M-3)."
  },

  "dating_gentleWaitNotEligible": "Dating isn't available on this account right now, so your answers weren't saved.",
  "@dating_gentleWaitNotEligible": {
    "description": "D0, after Save, when the server answers not_eligible (Spec 2 W3a, W2 carry M-3). For the DV reviewer."
  }
```

Create `$D/remove_fallback_key_T2.py` with exactly:

```python
# Carry 14: the v1 dashboard's fallback string goes with the dashboard.
import json, pathlib, re
p = pathlib.Path('lib/i10n/app_en.arb')
s = p.read_text()
s, n = re.subn(r'  "dating_dashboardFallbackReason": [^\n]*\n  "@dating_dashboardFallbackReason": \{\n[^\n]*\n  \},\n\n', '', s)
assert n == 1, n
json.loads(s)
p.write_text(s)
print('app_en.arb: dating_dashboardFallbackReason removed')
```

```bash
D=.superpowers/sdd/2026-11-07-spec2-w3
python3 -I $D/remove_fallback_key_T2.py
python3 -I .superpowers/sdd/2026-10-26-spec1-w3/arb_append.py $D/arb_fragment_T2.txt
```

Expected: `app_en.arb: dating_dashboardFallbackReason removed`; `added 3 keys`. (gen-l10n runs in Step 7, after the v1 dashboard that reads the removed key is deleted.)

- [ ] **Step 4: The lock, the wipe entry and the route group**

Create `lib/features/dating/lock/dating_unlock.dart` with exactly:

```dart
// Spec 2 W3a (§3.0 Lock, §3.14; R-8): with Spec 1's Dating lock on, every
// Dating route, deep link and push tap asks for the Safety PIN first, once
// per foreground session. The unlock is memory only: putting the app away,
// another account, quick exit and sign-out all end it. The lock itself is
// Spec 1's protective setting and is never cleared here.
import 'package:attune/app/routing/app_router.dart' show RouteNames;
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_buttons.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_frame.dart';
import 'package:attune/features/onboarding/domain/home_state.dart' show AppTab;
import 'package:attune/features/safety/data/dating_lock_store.dart';
import 'package:attune/features/safety/presentation/widgets/confirm_safety_pin.dart';
import 'package:attune/home/home_location.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

const datingUnlockPath = '/dating/unlock';

/// Dating state held in memory, cleared on quick exit and sign-out through
/// Spec 1's registry (registerDatingDeviceWipes). No device key.
abstract final class DatingSessionMemory {
  static final _clears = <Object, void Function()>{};

  /// [owner]'s [clear], until [ref] is disposed or rebuilt.
  static void track(Object owner, Ref ref, void Function() clear) {
    _clears[owner] = clear;
    ref.onDispose(() => _clears.remove(owner));
  }

  static Future<void> clear() async {
    for (final clear in List.of(_clears.values)) {
      try {
        clear();
      } catch (_) {
        // Something being torn down has nothing left to clear.
      }
    }
  }
}

/// Whether the Safety PIN was entered for Dating in this foreground session.
class DatingUnlock extends Notifier<bool> with WidgetsBindingObserver {
  @override
  bool build() {
    // Another account (or a sign-out) starts locked again (D8).
    ref.watch(datingLockAccountProvider);
    final binding = WidgetsBinding.instance;
    binding.addObserver(this);
    ref.onDispose(() => binding.removeObserver(this));
    DatingSessionMemory.track(this, ref, lock);
    return false;
  }

  void unlock() => state = true;

  void lock() {
    if (state) state = false;
  }

  @override
  // The parameter keeps the framework's name; `this.state` is the unlock.
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      lock();
    }
  }
}

final datingUnlockedProvider = NotifierProvider<DatingUnlock, bool>(
  DatingUnlock.new,
);

/// The one redirect every Dating route carries: signed out → sign in; the
/// Dating lock on and not yet unlocked → the PIN first. A lock setting that
/// can't be read asks (fail closed).
Future<String?> datingRedirect(
  BuildContext context,
  GoRouterState state, {
  required bool signedIn,
}) async {
  if (!signedIn) return RouteNames.login;
  if (state.uri.path == datingUnlockPath) return null;
  final ProviderContainer container;
  try {
    container = ProviderScope.containerOf(context, listen: false);
  } catch (_) {
    return homeLocation(tab: AppTab.me);
  }
  bool locked;
  try {
    locked = await container.read(datingLockProvider.future);
  } catch (_) {
    locked = true;
  }
  if (!locked || container.read(datingUnlockedProvider)) return null;
  return Uri(
    path: datingUnlockPath,
    queryParameters: {'from': state.uri.toString()},
  ).toString();
}

/// Where an unlock goes on: only a Dating location, never the unlock
/// itself, never anything with a scheme, a host or `..` (no open redirect).
String datingSafeReturn(String? from) {
  final uri = Uri.tryParse(from ?? '');
  if (uri == null ||
      uri.hasScheme ||
      uri.hasAuthority ||
      !uri.path.startsWith('/dating/') ||
      uri.path == datingUnlockPath ||
      uri.path.contains('..')) {
    return homeLocation(tab: AppTab.me);
  }
  return uri.toString();
}

/// §3.14's "PIN screen": the existing Safety PIN sheet, then the place asked
/// for. Dismissing the sheet stays here; Back goes to Me.
class DatingUnlockScreen extends ConsumerStatefulWidget {
  const DatingUnlockScreen({super.key, required this.from});

  final String from;

  @override
  ConsumerState<DatingUnlockScreen> createState() => _DatingUnlockScreenState();
}

class _DatingUnlockScreenState extends ConsumerState<DatingUnlockScreen> {
  bool _asking = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _ask());
  }

  Future<void> _ask() async {
    if (_asking || !mounted) return;
    setState(() => _asking = true);
    final ok = await confirmSafetyPin(context);
    if (!mounted) return;
    setState(() => _asking = false);
    if (!ok) return;
    ref.read(datingUnlockedProvider.notifier).unlock();
    context.go(datingSafeReturn(widget.from));
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return FlowFrame(
      title: loc.flow_slotLocked,
      onBack: () => context.go(homeLocation(tab: AppTab.me)),
      body: Text(
        loc.flow_slotLockedLine,
        style: Theme.of(context).textTheme.bodyLarge,
      ),
      actions: [
        FlowPrimaryButton(
          label: loc.dating_unlockButton,
          busy: _asking,
          onPressed: _ask,
        ),
      ],
    );
  }
}
```

Create `lib/features/dating/dating_device_wipes.dart` with exactly:

```dart
// Spec 2 (§3.0, §6.7; S1 §5.8, D19; R-9): Dating's entries in Spec 1's
// device wipe registry, reached by one line in lib/app/device_wipes.dart.
// W3a: the in-memory session (the Dating unlock, open setup answers). W8a
// adds the caches here; quick_exit_service.dart and auth_provider.dart are
// never edited. Nothing here is protective: the Dating lock stays.
import 'package:attune/core/device/device_wipe_registry.dart';
import 'package:attune/features/dating/lock/dating_unlock.dart';

void registerDatingDeviceWipes([DeviceWipeRegistry? registry]) {
  (registry ?? DeviceWipeRegistry.instance).register(
    const DeviceWipeEntry(
      id: 'spec2.dating_session',
      moments: {WipeMoment.signOut, WipeMoment.quickExit},
      run: DatingSessionMemory.clear,
    ),
  );
}
```

Create `lib/features/dating/routes/dating_routes.dart` with exactly:

```dart
// Spec 2 W3a (§3.14; R1, R-8, R-10): the Dating routes. Each is a top-level
// route (no shell branch: quick exit's go() disposes it) with the same one
// redirect (signed in, then the Dating lock). A route is added here when
// its screen lands: W3a the steps and the unlock (Task 4: settings,
// not-open), W3c leave; W4-W9 theirs.
import 'package:attune/core/ui/motion/motion_tokens.dart';
import 'package:attune/features/dating/lock/dating_unlock.dart';
import 'package:attune/features/dating/routes/dating_setup_steps.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

abstract final class DatingPaths {
  static const unlock = datingUnlockPath;
  static const settings = '/dating/settings';
  static const notOpen = '/dating/not-open';
  static const leave = '/dating/leave';

  static String step(String step) => '/dating/setup/$step';

  static String notOpenFor({String? country, String? region}) =>
      Uri(
        path: notOpen,
        queryParameters: {
          if (country != null) 'country': country,
          if (region != null) 'region': region,
        },
      ).toString();
}

enum DatingMotion { sharedAxis, fade, none }

/// §3.15: D12's preview cross-fades in at 200 ms.
const kDatingCrossFade = Duration(milliseconds: 200);

/// §3.0, §3.15: D0, D4 and D13 never move; D12 cross-fades; every other
/// step is shared-axis X.
DatingMotion datingStepMotion(String step) => switch (step) {
  'wait' || 'privacy' || 'ready' => DatingMotion.none,
  'preview' => DatingMotion.fade,
  _ => DatingMotion.sharedAxis,
};

bool _reduceMotion() =>
    WidgetsBinding
        .instance
        .platformDispatcher
        .accessibilityFeatures
        .disableAnimations;

/// A Dating page: shared-axis X (30 dp, 300 ms forward, 250 ms back,
/// emphasized curves, mirrored right to left), a cross-fade, or nothing;
/// with reduce motion on, every moving page is a 150 ms cross-fade.
Page<void> datingPage(
  GoRouterState state,
  Widget child, {
  DatingMotion motion = DatingMotion.sharedAxis,
}) {
  if (motion == DatingMotion.none) {
    return NoTransitionPage<void>(key: state.pageKey, child: child);
  }
  final reduce = _reduceMotion();
  final fade = reduce || motion == DatingMotion.fade;
  final forward =
      reduce
          ? kReducedMotionFade
          : fade
          ? kDatingCrossFade
          : kStepForwardDuration;
  final back =
      reduce
          ? kReducedMotionFade
          : fade
          ? kDatingCrossFade
          : kStepBackDuration;
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: forward,
    reverseTransitionDuration: back,
    transitionsBuilder: (context, animation, secondary, child) {
      if (fade) return FadeTransition(opacity: animation, child: child);
      final rtl = Directionality.of(context) == TextDirection.rtl;
      final curved = CurvedAnimation(
        parent: animation,
        curve: Easing.emphasizedDecelerate,
        reverseCurve: Easing.emphasizedAccelerate,
      );
      return AnimatedBuilder(
        animation: curved,
        child: child,
        builder:
            (context, child) => Opacity(
              opacity: curved.value,
              child: Transform.translate(
                offset: Offset(
                  (rtl ? -kSharedAxisOffset : kSharedAxisOffset) *
                      (1 - curved.value),
                  0,
                ),
                child: child,
              ),
            ),
      );
    },
  );
}

GoRoute datingRoute(
  String path,
  String name,
  bool Function() signedIn,
  Widget Function(GoRouterState state) screen, {
  DatingMotion Function(GoRouterState state)? motion,
}) => GoRoute(
  path: path,
  name: name,
  redirect:
      (context, state) => datingRedirect(context, state, signedIn: signedIn()),
  pageBuilder:
      (context, state) => datingPage(
        state,
        screen(state),
        motion: motion?.call(state) ?? DatingMotion.none,
      ),
);

List<RouteBase> datingRoutes({required bool Function() signedIn}) => [
  datingRoute(
    DatingPaths.unlock,
    'datingUnlock',
    signedIn,
    (s) => DatingUnlockScreen(from: s.uri.queryParameters['from'] ?? ''),
  ),
  datingRoute(
    '/dating/setup/:step',
    'datingSetupStep',
    signedIn,
    (s) => DatingSetupStepRoute(step: s.pathParameters['step'] ?? ''),
    motion: (s) => datingStepMotion(s.pathParameters['step'] ?? ''),
  ),
];
```

Create `lib/features/dating/routes/dating_setup_steps.dart` with exactly:

```dart
// Spec 2 (§3.2, §3.14): the setup steps, in order, and the screen for each.
// Each batch adds its steps' cases to datingStepScreen; a step not built yet
// opens Me (R-10).
import 'package:attune/features/dating/data/dating_providers.dart';
import 'package:attune/features/dating/gentle_wait/gentle_wait_screen.dart';
import 'package:attune/features/dating/routes/dating_routes.dart';
import 'package:attune/features/onboarding/domain/home_state.dart' show AppTab;
import 'package:attune/home/home_location.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// §3.14's step ids after D0, in order. "Step {n} of 12" counts from
/// looking-for (1) to ready (12).
const datingSetupOrder = [
  'how',
  'looking-for',
  'where',
  'privacy',
  'you',
  'meet',
  'children',
  'faith',
  'photos',
  'prompts',
  'verify',
  'preview',
  'ready',
];

int? datingStepNumber(String step) {
  final i = datingSetupOrder.indexOf(step);
  return i >= 1 ? i : null;
}

/// How a step moves on: [next] opens a step ('done' is Me), [back] the step
/// before (or Me), [toMe] leaves setup.
class DatingStepNav {
  const DatingStepNav({
    required this.next,
    required this.back,
    required this.toMe,
  });

  final void Function(String step) next;
  final VoidCallback back;
  final VoidCallback toMe;
}

Widget? datingStepScreen(String step, DatingStepNav nav) => switch (step) {
  'wait' => DatingWaitStep(nav: nav),
  _ => null,
};

class DatingSetupStepRoute extends StatelessWidget {
  const DatingSetupStepRoute({super.key, required this.step});

  final String step;

  @override
  Widget build(BuildContext context) {
    void toMe() => context.go(homeLocation(tab: AppTab.me));
    final nav = DatingStepNav(
      next:
          (next) =>
              next == 'done' ? toMe() : context.push(DatingPaths.step(next)),
      back: () => context.canPop() ? context.pop() : toMe(),
      toMe: toMe,
    );
    return datingStepScreen(step, nav) ?? _NotBuiltYet(onShown: toMe);
  }
}

class _NotBuiltYet extends StatefulWidget {
  const _NotBuiltYet({required this.onShown});

  final VoidCallback onShown;

  @override
  State<_NotBuiltYet> createState() => _NotBuiltYetState();
}

class _NotBuiltYetState extends State<_NotBuiltYet> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onShown();
    });
  }

  @override
  Widget build(BuildContext context) => const Scaffold(body: SizedBox.shrink());
}

/// D0 (W2's screen) at /dating/setup/wait: "Set up Dating now" opens the
/// step the server says is next.
class DatingWaitStep extends ConsumerWidget {
  const DatingWaitStep({super.key, required this.nav});

  final DatingStepNav nav;

  @override
  Widget build(BuildContext context, WidgetRef ref) => GentleWaitScreen(
    onBack: nav.back,
    onSetUp: () async {
      final gateway = ref.read(datingHomeGatewayProvider);
      var next = 'how';
      try {
        next = (await gateway.read()).nextStep ?? 'how';
      } catch (_) {
        // Unreadable: setup starts at the beginning; each step resumes.
      }
      if (context.mounted) nav.next(next);
    },
  );
}
```

- [ ] **Step 5: Edit the shared files**

Create `$D/edit_T2.py` with exactly:

```python
import pathlib, sys
sys.path.insert(0, '.superpowers/sdd/2026-11-07-spec2-w3')
from anchor import edit

def cut(path, start, end, replacement, label):
    p = pathlib.Path(path)
    s = p.read_text()
    assert s.count(start) == 1 and s.count(end) == 1, (label, s.count(start), s.count(end))
    i = s.index(start)
    j = s.index(end, i) + len(end)
    p.write_text(s[:i] + replacement + s[j:])
    print(f'{path}: cut ({label})')

R = 'lib/app/routing/app_router.dart'
edit(R, [
    ("import 'package:attune/app/documentations/user_manual/data/dating_mode_docs.dart';\n", ''),
    ("import 'package:attune/features/dating/presentation/screens/dating_dashboard_screen.dart';\n",
     "import 'package:attune/features/dating/routes/dating_routes.dart';\n"),
    ("import 'package:attune/features/dating/presentation/screens/dating_consent_screen.dart';\n"
     "import 'package:attune/features/dating/presentation/screens/dating_guided_date_screen.dart';\n"
     "import 'package:attune/features/dating/presentation/screens/dating_matches_screen.dart';\n"
     "import 'package:attune/features/dating/presentation/screens/dating_profile_screen.dart';\n"
     "import 'package:attune/features/dating/presentation/screens/dating_photos_screen.dart';\n"
     "import 'package:attune/features/dating/presentation/screens/dating_verification_screen.dart';\n", ''),
    ("  static const String datingMode = '/dating-mode';\n", ''),
    ("  static const String datingConsent = '/datingConsent';\n"
     "  static const String datingProfile = '/datingProfile';\n"
     "  static const String datingMatches = '/datingMatches';\n"
     "  static const String datingGuidedDate = '/datingGuidedDate';\n"
     "  static const String datingPhotos = '/datingPhotos';\n"
     "  static const String datingVerification = '/datingVerification';\n", ''),
], 'T2 router imports and names')
cut(R, "      GoRoute(\n        path: RouteNames.datingConsent,",
    "        builder: (context, state) => const DatingVerificationScreen(),\n      ),\n",
    "      // Spec 2 W3a (§3.14): the Dating routes, behind the Dating lock.\n"
    "      ...datingRoutes(signedIn: () => routingNotifier.isSignedIn),\n",
    'T2 v1 Dating routes')
cut(R, "      GoRoute(\n        path: RouteNames.datingMode,",
    "              buildFeature: () => const DatingDashboardScreen(),\n            ),\n      ),\n",
    '', 'T2 /dating-mode')

edit('lib/core/notifications/config/notification_config.dart', [
    ("        case 'dating_mutual_match':\n          GoRouter.of(context).go(RouteNames.datingMatches);\n          return;\n",
     "        // Spec 2 W3a (§3.13, I-9): every Dating push is the neutral\n"
     "        // me_update and opens Me, where the Dating section shows its locked\n"
     "        // row while the Dating lock is on. The old match push opens Me too\n"
     "        // for one release (A-7; W10 removes it).\n"
     "        case 'me_update':\n"
     "        case 'dating_mutual_match':\n"
     "          GoRouter.of(context).go(homeLocation(tab: AppTab.me));\n"
     "          return;\n"),
], 'T2 me_update')

edit('lib/app/device_wipes.dart', [
    ("import 'package:attune/features/couple_profile/data/about_us_outbox.dart';\n",
     "import 'package:attune/features/couple_profile/data/about_us_outbox.dart';\n"
     "import 'package:attune/features/dating/dating_device_wipes.dart';\n"),
    ("  for (final entry in spec1DeviceWipes()) {\n    target.register(entry);\n  }\n}\n",
     "  for (final entry in spec1DeviceWipes()) {\n    target.register(entry);\n  }\n"
     "  registerDatingDeviceWipes(target);\n}\n"),
], 'T2 device wipes (R-9)')

# C-1: Spec 1's slot opens setup by its new path until Task 4 rewrites the
# slot's body (RouteNames.datingMode is removed above).
edit('lib/features/me/presentation/widgets/dating_slot.dart', [
    ("import 'package:attune/app/routing/app_router.dart' show RouteNames;\n", ''),
    ("import 'package:attune/features/auth/sign_up/presentation/widgets/flow_buttons.dart';\n",
     "import 'package:attune/features/auth/sign_up/presentation/widgets/flow_buttons.dart';\n"
     "import 'package:attune/features/dating/routes/dating_routes.dart';\n"),
    ("          onPressed: () => context.push(RouteNames.datingMode),\n",
     "          onPressed: () => context.push(DatingPaths.step('how')),\n"),
], 'T2 slot setup path (C-1)')

edit('lib/app/text_scale_policy.dart', [
    ("  static const List<String> auditedRoutePrefixes = [\n    '/home',\n",
     "  static const List<String> auditedRoutePrefixes = [\n    '/home',\n"
     "    // Spec 2 W3a: every Dating screen is audited before it lands (§3.0).\n"
     "    '/dating/',\n"),
], 'T2 text scale')

G = 'lib/features/dating/gentle_wait/gentle_wait_screen.dart'
edit(G, [
    ("enum _Status { none, saved, cleared, busy, clearBusy, failed }",
     "enum _Status { none, saved, cleared, busy, clearBusy, failed, notEligible, reverify }"),
    ("        GentleWaitSave.busy => clearing ? _Status.clearBusy : _Status.busy,\n        _ => _Status.failed,\n",
     "        GentleWaitSave.busy => clearing ? _Status.clearBusy : _Status.busy,\n"
     "        // Spec 2 W3a (W2 carry M-3): their own states, never \"went wrong\".\n"
     "        GentleWaitSave.notEligible => _Status.notEligible,\n"
     "        GentleWaitSave.reverifyDevice => _Status.reverify,\n"
     "        _ => _Status.failed,\n"),
    ("              : wait is AsyncError<GentleWait>\n              ? _readFailed(\n",
     "              // Spec 2 W3a (W2 carry M-3): an untrusted phone can't read the\n"
     "              // answers but can still clear them (the clear needs no device).\n"
     "              : wait is AsyncError<GentleWait> &&\n"
     "                  wait.error is GentleWaitUnavailable\n"
     "              ? _unavailable(loc)\n"
     "              : wait is AsyncError<GentleWait>\n"
     "              ? _readFailed(\n"),
    ("  Widget _readFailed(\n    BuildContext context,\n",
     "  Future<void> _clearOnly() async {\n"
     "    final account = ref.read(gentleWaitAccountProvider);\n"
     "    setState(() {\n"
     "      _saving = true;\n"
     "      _status = _Status.none;\n"
     "    });\n"
     "    var result = GentleWaitSave.failed;\n"
     "    try {\n"
     "      result = await ref.read(gentleWaitGatewayProvider).clear();\n"
     "    } catch (_) {\n"
     "      result = GentleWaitSave.failed;\n"
     "    }\n"
     "    if (!mounted || ref.read(gentleWaitAccountProvider) != account) return;\n"
     "    setState(() {\n"
     "      _saving = false;\n"
     "      _status = switch (result) {\n"
     "        GentleWaitSave.saved => _Status.cleared,\n"
     "        GentleWaitSave.busy => _Status.clearBusy,\n"
     "        _ => _Status.failed,\n"
     "      };\n"
     "    });\n"
     "  }\n\n"
     "  Widget _unavailable(AppLocalizations loc) => Column(\n"
     "    crossAxisAlignment: CrossAxisAlignment.stretch,\n"
     "    children: [\n"
     "      _CalmLine(text: loc.dating_sectionReverify),\n"
     "      const SizedBox(height: Spacing.md),\n"
     "      FlowSecondaryButton(\n"
     "        label: loc.dating_gentleWaitClear,\n"
     "        busy: _saving,\n"
     "        onPressed: _saving ? null : _clearOnly,\n"
     "      ),\n"
     "      if (_status == _Status.cleared) ...[\n"
     "        const SizedBox(height: Spacing.sm),\n"
     "        _CalmLine(text: loc.dating_gentleWaitCleared),\n"
     "      ],\n"
     "      if (_status == _Status.clearBusy) ...[\n"
     "        const SizedBox(height: Spacing.sm),\n"
     "        _CalmLine(text: loc.dating_gentleWaitClearBusy),\n"
     "      ],\n"
     "      if (_status == _Status.failed) ...[\n"
     "        const SizedBox(height: Spacing.sm),\n"
     "        FlowErrorLine(text: loc.dating_errorGeneric, liveRegion: true),\n"
     "      ],\n"
     "    ],\n"
     "  );\n\n"
     "  Widget _readFailed(\n    BuildContext context,\n"),
    ("        if (_status == _Status.failed) ...[\n          const SizedBox(height: Spacing.sm),\n"
     "          FlowErrorLine(text: loc.dating_errorGeneric, liveRegion: true),\n        ],\n",
     "        if (_status == _Status.failed) ...[\n          const SizedBox(height: Spacing.sm),\n"
     "          FlowErrorLine(text: loc.dating_errorGeneric, liveRegion: true),\n        ],\n"
     "        if (_status == _Status.notEligible) ...[\n"
     "          const SizedBox(height: Spacing.sm),\n"
     "          _CalmLine(text: loc.dating_gentleWaitNotEligible),\n"
     "        ],\n"
     "        if (_status == _Status.reverify) ...[\n"
     "          const SizedBox(height: Spacing.sm),\n"
     "          _CalmLine(text: loc.dating_sectionReverify),\n"
     "        ],\n"),
], 'T2 D0 states (carry 7)')

edit('lib/features/dating/data/models/dating_enrollment.dart', [
    ("  final DateTime? adultsOnlyConfirmedAt;\n", "  final String? pauseReason;\n"),
    ("    this.adultsOnlyConfirmedAt,\n  });", "    this.pauseReason,\n  });"),
    ("      adultsOnlyConfirmedAt: parseNullable('adults_only_confirmed_at'),\n",
     "      pauseReason: json['pause_reason'] as String?,\n"),
    ("    adultsOnlyConfirmedAt,\n    createdAt,", "    pauseReason,\n    createdAt,"),
], 'T2 enrolment model (§4.10)')

edit('lib/features/ai_assistant/data/services/ai_session_capabilities.dart', [
    ("// `get_dating_eligibility()`, the precedent that migration points at.\n",
     "// a server RPC (`get_dating_home()` since Spec 2 W3a), the precedent that\n// migration points at.\n"),
], 'T2 comment')

T = 'test/architecture/text_scale_routes_test.dart'
edit(T, [
    ("  'datingConsent',\n  'datingProfile',\n  'datingMatches',\n  'datingGuidedDate',\n"
     "  'datingPhotos',\n  'datingVerification',\n  'datingMode',\n", ''),
    ("const _audited = {\n",
     "const _audited = {\n  // Spec 2 W3a (§3.0): every Dating screen.\n  'datingSetupStep',\n  'datingUnlock',\n"),
], 'T2 text scale routes')

edit('test/app/routing/app_router_sign_in_test.dart', [
    ("  '/datingConsent',\n  '/datingProfile',\n  '/datingMatches',\n  '/datingGuidedDate',\n"
     "  '/datingPhotos',\n  '/datingVerification',\n",
     "  // Spec 2 W3a (§3.14) removed the seven v1 Dating paths.\n"),
    ("  '/dating-mode',\n", ''),
], 'T2 frozen paths')

cut('test/app/routing/feature_intro_route_wiring_test.dart',
    "  testWidgets('Dating Mode intro gate shows DatingModeDocs content on first entry', (tester) async {",
    "    expect(find.text('Dating Dashboard Stub'), findsNothing);\n  });\n\n",
    '', 'T2 intro wiring')
edit('test/app/routing/feature_intro_route_wiring_test.dart', [
    ("import 'package:attune/app/documentations/user_manual/data/dating_mode_docs.dart';\n", ''),
], 'T2 intro wiring import')

edit('test/features/chat/chat_couples_locked_screen_healing_entry_test.dart', [
    ("      GoRoute(\n        path: RouteNames.datingMode,\n"
     "        builder: (context, state) => const Scaffold(body: Text('Dating stub')),\n      ),\n", ''),
], 'T2 locked screen stub')
```

```bash
D=.superpowers/sdd/2026-11-07-spec2-w3
grep -n "Dating stub" test/features/chat/chat_couples_locked_screen_healing_entry_test.dart
python3 -I $D/edit_T2.py
```

Expected: the `grep` prints only the stub route's `builder` line (no test looks for the stub: the button was removed by S1 W3b); then one line per edit, ending `test/features/chat/chat_couples_locked_screen_healing_entry_test.dart: 1 edit(s) (T2 locked screen stub)`. If the cut for the `feature_intro_route_wiring_test.dart` Dating case misses its end marker, open the file, find the Dating test's last `expect` and the blank line before the Healing test, and cut exactly that test.

- [ ] **Step 6: Delete v1**

```bash
rm lib/features/dating/data/repositories/dating_repository.dart
rmdir lib/features/dating/data/repositories
rm -r lib/features/dating/presentation
rm test/features/dating/dating_dashboard_never_gates_on_healing_test.dart test/features/dating/dating_profile_activation_marks_intro_seen_test.dart
grep -rn "features/dating/presentation\|dating_repository.dart\|RouteNames.dating\|DatingModeDocs()" lib test | grep -v "manual_documentation_registry.dart\|healing_never_gates_dating_test.dart"
```

Expected: no output (`DatingModeDocs()` stays registered in the manual and read by the Healing test; W3c rewrites the topic).

- [ ] **Step 7: Generate the strings, format the new files, analyze, run the tests**

```bash
flutter gen-l10n --arb-dir=lib/i10n --template-arb-file=app_en.arb --output-dir=lib/i10n/generated --output-localization-file=app_localizations.dart --no-synthetic-package
git diff --stat -- lib/i10n/generated
dart format lib/features/dating/lock lib/features/dating/routes lib/features/dating/dating_device_wipes.dart test/features/dating/support/dating_shell.dart test/features/dating/routes test/features/dating/gentle_wait/gentle_wait_states_test.dart test/core/notifications/me_update_routing_test.dart test/architecture/dating_rpc_only_test.dart test/architecture/dating_boundaries_test.dart
flutter analyze --no-pub lib test 2>&1 | tail -1
flutter test test/features/dating test/core/notifications test/architecture test/app 2>&1 | tail -1
```

Expected: the generated files change by the three added getters and the one removed (`git diff --stat` lists `app_localizations.dart` and `app_localizations_en.dart` plus the other locales' files); `Formatted …`; analyzer `571 issues found.` or fewer, with no new one against the baseline (if the analyzer reports the `FeatureIntroFlowGate` import in `app_router.dart` unused, remove that one import line with an exact-anchor edit and say so); `All tests passed!`.

- [ ] **Step 8: Mutants (each must turn a test red)**

Create `$D/dmut.py` with exactly:

```python
#!/usr/bin/env python3
"""Dart mutation runner. usage: dmut.py <spec.py> [--check] [name ...]
spec.py defines MUTS = {name: (path, old, new, [test paths])}; for a mutant
that needs more than one edit in its file (an import and a call), old is a
list of (old, new) pairs and new is None. Every anchor
is checked first (old must occur exactly once in the file as it is now,
after the task's own dart format). Each mutant is then applied, its tests
run, and the file restored byte for byte. KILLED = a test failed; a
mutant that stops the code compiling is COMPILE and is not a kill (fix
the mutant). --check only verifies the anchors."""
import pathlib, runpy, subprocess, sys
muts = runpy.run_path(sys.argv[1])['MUTS']
check = '--check' in sys.argv[2:]
only = {a for a in sys.argv[2:] if a != '--check'}
chosen = {n: m for n, m in muts.items() if not only or n in only}
def pairs(old, new):
    return old if isinstance(old, list) else [(old, new)]
bad = [f'{n}: anchor {o[:60]!r} occurs {pathlib.Path(p).read_text().count(o)} times'
       for n, (p, old, new, _) in chosen.items() for o, _ in pairs(old, new)
       if pathlib.Path(p).read_text().count(o) != 1]
if bad:
    print('\n'.join(bad))
    sys.exit(1)
if check:
    print(f'{len(chosen)} anchors OK')
    sys.exit(0)
killed = 0
for name, (path, old, new, tests) in chosen.items():
    p = pathlib.Path(path)
    orig = p.read_bytes()
    text = orig.decode()
    for o, n in pairs(old, new):
        text = text.replace(o, n)
    p.write_text(text)
    try:
        r = subprocess.run(['flutter', 'test', '--no-pub', *tests], capture_output=True, text=True)
    finally:
        p.write_bytes(orig)
    assert p.read_bytes() == orig, name
    out = (r.stdout + r.stderr).splitlines()
    compile_error = any('Compilation failed' in l or ': Error: ' in l for l in out)
    why = next((l.strip() for l in out if l.strip().startswith(('Expected:', 'Error:', 'Some tests failed'))), out[-1] if out else '')
    status = 'COMPILE' if compile_error else ('KILLED' if r.returncode != 0 else 'SURVIVED')
    killed += status == 'KILLED'
    print(f'{name}: {status}  {why[:150]}')
print(f'{killed}/{len(chosen)} killed')
```

Create `$D/mut_T2.py` with exactly:

```python
L = 'lib/features/dating/lock/dating_unlock.dart'
RT = ['test/features/dating/routes/dating_routes_test.dart']
MUTS = {
  'signed_out_passes': (L, "  if (!signedIn) return RouteNames.login;\n", "", RT),
  'lock_unreadable_open': (L, "  } catch (_) {\n    locked = true;\n  }", "  } catch (_) {\n    locked = false;\n  }", RT),
  'unlock_ignored': (L, "  if (!locked || container.read(datingUnlockedProvider)) return null;", "  return null;", RT),
  'open_redirect': (L, "      !uri.path.startsWith('/dating/') ||\n", "", RT),
  'unlock_survives_hidden': (L, "      lock();\n    }\n  }", "    }\n  }", RT),
  'unlock_survives_quick_exit': (L, "    DatingSessionMemory.track(this, ref, lock);\n", "", RT),
  'unbuilt_step_blank': ('lib/features/dating/routes/dating_setup_steps.dart', "      if (mounted) widget.onShown();", "", RT),
  'd0_wrong_next': ('lib/features/dating/routes/dating_setup_steps.dart', "      if (context.mounted) nav.next(next);", "      if (context.mounted) nav.next('how');", RT),
  'me_update_to_home': ('lib/core/notifications/config/notification_config.dart', "        case 'dating_mutual_match':\n          GoRouter.of(context).go(homeLocation(tab: AppTab.me));", "        case 'dating_mutual_match':\n          GoRouter.of(context).go(RouteNames.home);", ['test/core/notifications/me_update_routing_test.dart']),
  'd0_not_eligible_generic': ('lib/features/dating/gentle_wait/gentle_wait_screen.dart', "        GentleWaitSave.notEligible => _Status.notEligible,\n", "", ['test/features/dating/gentle_wait/gentle_wait_states_test.dart']),
  'd0_unavailable_no_clear': ('lib/features/dating/gentle_wait/gentle_wait_screen.dart', "              ? _unavailable(loc)\n", "              ? _readFailed(context, loc, busy: false, retrying: false)\n", ['test/features/dating/gentle_wait/gentle_wait_states_test.dart']),
}
```

```bash
python3 -I $D/dmut.py $D/mut_T2.py | tee $D/mut_T2.txt | tail -1
```

Expected: `11/11 killed`. Quote each mutant's line in the report.

- [ ] **Step 9: Do not commit; record the tree in the report** (with the Flutter test count of the touched folders and the mutant file).

### Task 3: Migration `dating_v2_client_reads`: notify requests, the neutral push, the revokes, the shim dropped, `get_dating_home` v2 (§4.9 W3a, §2.7, §3.1, §3.13, §4.1, §4.10; I-4, I-9, R11, R21; carries 4, 7, 8, 9, 11; R-2–R-7)

**Files:**
- Create: `supabase/migrations/20261107150000_dating_v2_client_reads.sql`, `supabase/migrations/20261107150010_dating_v2_client_reads_grants.sql`, `supabase/tests/dating_v2_client_reads_contracts.sql`, `supabase/functions/process-scheduled-notifications/privacy_allowlist.test.ts`, `$D/{new_functions_T3.sql, build_mig_T3.py, edit_contracts_T3.py, edit_races_T3.py, mut_T3.py}`
- Modify: `supabase/tests/dating_rls_canary.sql`, `supabase/tests/dating_v2_home_contracts.sql` (the `pg_temp.home` helper; H9's pin), `supabase/tests/dating_mode_contracts.sql` (section 1, I-2), `supabase/tests/dating_v2_eligibility_contracts.sql` (section F, one probe), `scripts/local_pg_grants.sql`, `scripts/concurrency/dating_kill_switch_races.sh` (two cases), `supabase/functions/process-scheduled-notifications/index.ts` (one allowlist entry)

**Interfaces:**
- Consumes: Task 1's `$D/before/{public.get_dating_home(),public.publish_country_config(text,jsonb),public.save_gentle_wait_reflection(jsonb)}.sql`; Task 2's grep test (green before this migration may drop the shim).
- Produces: the W3a SQL interfaces listed under "Interfaces this plan produces"; `get_dating_home()` v2 payloads: `feature_unavailable {country, notify}`, `country_closed {country, notify}`, `region_closed {country, region, open_regions, notify}`, `not_started {first_drop_at}`, `setup_in_progress {next_step, first_drop_at}`, `gentle_wait {ended_at, opens_at, next_step, can_shorten, first_drop_at}`, `paused {pause_reason[, country]}`, `active` → `unavailable` when the candidate check refuses for anything but the wait; every answer, in every state, also carries `has_data` (R-43); all other states unchanged. New helpers: `private.dating_has_data(uuid)`; the push key `dating_push_key` (R-44); `request_dating_country_notice` answers `rate_limited` after 20 a day (R-45).

- [ ] **Step 1: The grep test is green first (R11, R21)**

Run: `flutter test test/architecture/dating_rpc_only_test.dart 2>&1 | tail -1`
Expected: `All tests passed!`. If it fails, stop: Task 2 is not done, and dropping the shim or revoking the reads now would break the app.

- [ ] **Step 2: Write the failing contract**

Create `supabase/tests/dating_v2_client_reads_contracts.sql` with exactly:

```sql
-- supabase/tests/dating_v2_client_reads_contracts.sql
-- Spec 2 W3a (§2.7, §3.1, §3.13, §4.1, §4.9 W3a, §4.10; I-4, I-9, R11, R21;
-- carries 4, 7, 8, 9): the client reads no Dating table and the shim is
-- gone (A); get_dating_home v2 (B); "Tell me when it's here" (C); a publish
-- that opens a country or region tells each person once, neutrally (D);
-- the reflection trims every Unicode space (E); every home answer says
-- whether the person has Dating data to leave or clear (F, C-2).
-- One BEGIN ... ROLLBACK. Run only on attune_spec3a:
--   psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/dating_v2_client_reads_contracts.sql
-- Fixture ids 5e300000-0000-0000-0000-0000000000NN; phones 15558706NN.
BEGIN;

DO $$
BEGIN
  PERFORM set_config('app.settings.dating_exclusion_key', 'spec2-w3a-reads-key', true);
  -- The push key is its own secret (M-8); section D also runs without it.
  PERFORM set_config('app.settings.dating_push_key', 'spec2-w3a-push-key', true);
END $$;
SELECT private.seed_dating_exclusion_key_fingerprint() AS seeded \gset
INSERT INTO public.feature_flags (key, enabled) VALUES ('dating_mode_enabled', true)
ON CONFLICT (key) DO UPDATE SET enabled = true;
SELECT public.publish_country_config('GH', '{"dating_enabled": true, "open_regions": ["AA", "AH"]}') AS gh \gset
SELECT public.publish_country_config('GB', '{"dating_enabled": true}') AS gb \gset

CREATE FUNCTION pg_temp.id(p_n text) RETURNS uuid LANGUAGE sql IMMUTABLE AS $$
  SELECT ('5e300000-0000-0000-0000-0000000000' || p_n)::uuid;
$$;
-- An adult [p_n] on the Dating path whose account is [p_age] old.
CREATE FUNCTION pg_temp.person(p_n text, p_age interval DEFAULT interval '40 days') RETURNS uuid LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO auth.users (id, phone, phone_confirmed_at, created_at)
  VALUES (pg_temp.id(p_n), '15558706' || p_n, now(), now() - p_age);
  INSERT INTO public.users (id, phone, display_name, path, created_at, eula_accepted_at, eula_version)
  VALUES (pg_temp.id(p_n), '15558706' || p_n, 'Reads ' || p_n, 'dating', now() - p_age, now(), '2');
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
CREATE FUNCTION pg_temp.call(p uuid, p_sql text) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
  v jsonb;
BEGIN
  PERFORM pg_temp.as_person(p);
  EXECUTE p_sql INTO v;
  PERFORM pg_temp.as_db();
  RETURN v;
END $$;
-- The payloads below are pinned without has_data; section F pins it.
CREATE FUNCTION pg_temp.home(p uuid) RETURNS jsonb LANGUAGE sql AS $$
  SELECT pg_temp.call(p, 'SELECT public.get_dating_home()') - 'has_data';
$$;
CREATE FUNCTION pg_temp.has_data(p uuid) RETURNS text LANGUAGE sql AS $$
  SELECT pg_temp.call(p, 'SELECT public.get_dating_home()') ->> 'has_data';
$$;
CREATE FUNCTION pg_temp.metric(p_key text) RETURNS bigint LANGUAGE sql AS $$
  SELECT coalesce((SELECT sum(c.count) FROM public.metric_counters AS c
                    WHERE c.day = (now() AT TIME ZONE 'utc')::date AND c.key = p_key), 0)::bigint;
$$;

-- =====================================================================
-- A. (R11, R21, I-4, A-10, R-2) No client SELECT on the four 20260811120000
--    tables, no owner-read policy, no client-callable invoker reader; the
--    shim is gone and nothing names it; Spec 1's seam still answers.
-- =====================================================================
DO $a$
DECLARE
  v_t text;
  v_got text;
  v_p constant uuid := pg_temp.person('01');
BEGIN
  FOREACH v_t IN ARRAY ARRAY['dating_enrollments', 'dating_consent_events', 'dating_profiles', 'dating_preferences'] LOOP
    IF has_table_privilege('authenticated', 'public.' || v_t, 'SELECT')
       OR has_any_column_privilege('authenticated', 'public.' || v_t, 'SELECT')
       OR has_any_column_privilege('anon', 'public.' || v_t, 'SELECT') THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: a client can still read public.%', v_t;
    END IF;
  END LOOP;
  IF EXISTS (SELECT 1 FROM pg_policies AS p WHERE p.schemaname = 'public'
              AND p.policyname IN ('dating enrollments owner read', 'dating consent owner read',
                                   'dating profiles owner read', 'dating preferences owner read')) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an owner-read policy is still there';
  END IF;
  INSERT INTO public.dating_enrollments (user_id, state) VALUES (v_p, 'profile_draft');
  INSERT INTO public.dating_profiles (user_id, display_name) VALUES (v_p, 'Reads');
  PERFORM pg_temp.as_person(v_p);
  BEGIN
    PERFORM 1 FROM public.dating_profiles LIMIT 1;
    RAISE EXCEPTION 'CONTRACT VIOLATED: authenticated read dating_profiles directly';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;
  PERFORM pg_temp.as_db();
  -- A-10: the seam is a definer read, so the revoke doesn't touch it.
  IF pg_temp.call(v_p, 'SELECT public.get_my_home_state()') #>> '{dating,enrolled}' IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: after the revoke get_my_home_state().dating.enrolled is not true';
  END IF;
  SELECT string_agg(p.oid::regprocedure::text, ', ' ORDER BY p.oid::regprocedure::text) INTO v_got
    FROM pg_proc AS p JOIN pg_namespace AS n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND NOT p.prosecdef AND p.prorettype <> 'trigger'::regtype
     AND has_function_privilege('authenticated', p.oid, 'EXECUTE')
     AND p.prosrc ~ '(dating_enrollments|dating_consent_events|dating_profiles|dating_preferences)';
  IF v_got IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: client-callable invoker functions read the revoked tables: %', v_got;
  END IF;
  IF to_regprocedure('public.get_dating_eligibility()') IS NOT NULL
     OR EXISTS (SELECT 1 FROM pg_proc AS p WHERE p.prosrc ~ 'get_dating_eligibility') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: get_dating_eligibility() or a caller of it is still there';
  END IF;
  IF pg_get_functiondef('public.request_dating_country_notice(text,text)'::regprocedure)
       !~ 'pg_advisory_xact_lock\(hashtextextended\(''country_safety_config:''' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the notice request does not take the publisher''s lock (R-6)';
  END IF;
END $a$;

-- =====================================================================
-- B. get_dating_home v2 (R-4, R-5; carries 4, 8, 9).
-- =====================================================================
DO $b$
DECLARE
  v_new constant uuid := pg_temp.person('10', interval '1 day');
  v_lagos constant uuid := pg_temp.person('11');
  v_volta constant uuid := pg_temp.person('12');
  v_ghana constant uuid := pg_temp.person('13');
  v_wait constant uuid := pg_temp.person('14');
  v_ex constant uuid := pg_temp.person('15');
  v_undated constant uuid := pg_temp.person('16');
  v_ex2 constant uuid := pg_temp.person('17');
  v_switched constant uuid := pg_temp.person('18');
  v_nullreason constant uuid := pg_temp.person('19');
  v_live constant uuid := pg_temp.person('20');
  v jsonb;
  v_after timestamptz;
BEGIN
  -- not_started: the first possible drop, 72 h after creation at the latest.
  v := pg_temp.home(v_new);
  v_after := (SELECT u.created_at FROM public.users AS u WHERE u.id = v_new) + interval '72 hours';
  IF v ->> 'state' IS DISTINCT FROM 'not_started'
     OR (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(v) AS k) IS DISTINCT FROM ARRAY['first_drop_at', 'state']
     OR (v ->> 'first_drop_at')::timestamptz < v_after OR (v ->> 'first_drop_at')::timestamptz >= v_after + interval '1 day' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: not_started reads % (72 h after creation: %)', v, v_after;
  END IF;
  -- Closed country and region carry their notice.
  INSERT INTO public.dating_profiles (user_id, display_name, country_code) VALUES (v_lagos, 'Lagos', 'NG');
  INSERT INTO public.dating_profiles (user_id, display_name, country_code, region_code) VALUES (v_volta, 'Volta', 'GH', 'TV');
  IF pg_temp.home(v_lagos) IS DISTINCT FROM
       '{"state": "country_closed", "country": "NG", "notify": {"available": true, "requested": false}}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a closed country reads %', pg_temp.home(v_lagos);
  END IF;
  IF pg_temp.home(v_volta) IS DISTINCT FROM
       '{"state": "region_closed", "country": "GH", "region": "TV", "open_regions": ["AA", "AH"], "notify": {"available": true, "requested": false}}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a closed region reads %', pg_temp.home(v_volta);
  END IF;
  -- R-5: Dating off everywhere; Ghana itself is open, so asking can't fire.
  INSERT INTO public.dating_profiles (user_id, display_name, country_code, region_code) VALUES (v_ghana, 'Ghana', 'GH', 'AA');
  UPDATE public.feature_flags SET enabled = false WHERE key = 'dating_mode_enabled';
  v := pg_temp.home(v_ghana);
  IF v IS DISTINCT FROM '{"state": "feature_unavailable", "country": "GH", "notify": {"available": false, "requested": false}}'::jsonb
     OR pg_temp.home(v_lagos) #>> '{notify,available}' IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: feature_unavailable reads % (Ghana) / % (Lagos)', v, pg_temp.home(v_lagos);
  END IF;
  UPDATE public.feature_flags SET enabled = true WHERE key = 'dating_mode_enabled';
  -- gentle_wait: can_shorten (carry 8) and the first drop after the open date.
  INSERT INTO public.relationships (user_a, user_b, status, ended_at) VALUES (v_wait, v_ex, 'ended', now() - interval '5 days');
  v := pg_temp.home(v_wait);
  IF v ->> 'state' IS DISTINCT FROM 'gentle_wait' OR jsonb_typeof(v -> 'can_shorten') IS DISTINCT FROM 'boolean'
     OR (v ->> 'first_drop_at')::timestamptz < (v ->> 'opens_at')::timestamptz THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: gentle_wait reads %', v;
  END IF;
  -- Carry 4: active, but an ending with no date: never "you're live".
  INSERT INTO public.dating_enrollments (user_id, state, activated_at) VALUES (v_undated, 'active', now());
  INSERT INTO public.dating_profiles (user_id, display_name, profile_state, country_code, region_code)
  VALUES (v_undated, 'Undated', 'active', 'GH', 'AA');
  INSERT INTO public.relationships (user_a, user_b, status, ended_at) VALUES (v_undated, v_ex2, 'ended', NULL);
  IF pg_temp.home(v_undated) IS DISTINCT FROM '{"state": "unavailable"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: active with an undated ending reads %', pg_temp.home(v_undated);
  END IF;
  -- ... while a plain active person is still active.
  INSERT INTO public.dating_enrollments (user_id, state, activated_at) VALUES (v_live, 'active', now());
  INSERT INTO public.dating_profiles (user_id, display_name, profile_state, country_code, region_code)
  VALUES (v_live, 'Live', 'active', 'GH', 'AA');
  IF pg_temp.home(v_live) IS DISTINCT FROM '{"state": "active"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a plain active person reads %', pg_temp.home(v_live);
  END IF;
  -- The §2.4 note needs the country; a NULL reason passes through (carry 9).
  INSERT INTO public.dating_enrollments (user_id, state, pause_reason) VALUES
    (v_switched, 'paused', 'same_gender_switch'), (v_nullreason, 'paused', NULL);
  INSERT INTO public.dating_profiles (user_id, display_name, country_code, region_code) VALUES
    (v_switched, 'Switched', 'GH', 'AA'), (v_nullreason, 'Null', 'GH', 'AA');
  IF pg_temp.home(v_switched) IS DISTINCT FROM '{"state": "paused", "pause_reason": "same_gender_switch", "country": "GH"}'::jsonb
     OR pg_temp.home(v_nullreason) IS DISTINCT FROM '{"state": "paused", "pause_reason": null}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: paused reads % / %', pg_temp.home(v_switched), pg_temp.home(v_nullreason);
  END IF;
END $b$;

-- =====================================================================
-- C. "Tell me when it's here" (§2.7, §3.10; R-6): signed in only;
--    pre-validated; refused for what is open now; one request per person;
--    cancelling is never gated; counted, aggregate only.
-- =====================================================================
DO $c$
DECLARE
  v_a constant uuid := pg_temp.person('30');
  v_b constant uuid := pg_temp.person('31');
  v_r constant uuid := pg_temp.person('32');
  v jsonb;
  v2 jsonb;
  v_msg text;
  v_before bigint := pg_temp.metric('dating.notify.requested');
BEGIN
  BEGIN
    PERFORM public.request_dating_country_notice('NG', NULL);
    RAISE EXCEPTION 'CONTRACT VIOLATED: a signed-out request was taken';
  EXCEPTION WHEN insufficient_privilege THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    IF v_msg IS DISTINCT FROM 'not_authenticated' THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: signed out raised %', v_msg;
    END IF;
  END;
  IF pg_temp.call(v_a, $q$SELECT public.request_dating_country_notice('G1', NULL)$q$)
       IS DISTINCT FROM '{"ok": false, "reason": "invalid", "field": "country"}'::jsonb
     OR pg_temp.call(v_a, $q$SELECT public.request_dating_country_notice(repeat('x', 5000), NULL)$q$)
       IS DISTINCT FROM '{"ok": false, "reason": "invalid", "field": "country"}'::jsonb
     OR pg_temp.call(v_a, $q$SELECT public.request_dating_country_notice('GH', 'NOPE')$q$)
       IS DISTINCT FROM '{"ok": false, "reason": "invalid", "field": "region"}'::jsonb
     OR pg_temp.call(v_a, $q$SELECT public.request_dating_country_notice('GH', 'ZZ')$q$)
       IS DISTINCT FROM '{"ok": false, "reason": "invalid", "field": "region"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: malformed notice requests are not answered invalid';
  END IF;
  IF pg_temp.call(v_a, $q$SELECT public.request_dating_country_notice('GB', NULL)$q$)
       IS DISTINCT FROM '{"ok": false, "reason": "already_open"}'::jsonb
     OR pg_temp.call(v_a, $q$SELECT public.request_dating_country_notice('gh', 'aa')$q$)
       IS DISTINCT FROM '{"ok": false, "reason": "already_open"}'::jsonb
     OR pg_temp.call(v_a, $q$SELECT public.request_dating_country_notice('GH', NULL)$q$)
       IS DISTINCT FROM '{"ok": false, "reason": "already_open"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a request for something open now was taken';
  END IF;
  IF EXISTS (SELECT 1 FROM public.dating_notify_requests WHERE user_id = v_a) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a refused request left a row';
  END IF;
  -- Each call is its own statement: a sub-read in the same IF expression
  -- shares one snapshot and would not see the call's write (I-1).
  v := pg_temp.call(v_a, $q$SELECT public.request_dating_country_notice('NG', NULL)$q$);
  v2 := pg_temp.call(v_a, $q$SELECT public.request_dating_country_notice('GH', 'TV')$q$);
  IF v IS DISTINCT FROM '{"ok": true}'::jsonb OR v2 IS DISTINCT FROM '{"ok": true}'::jsonb
     OR (SELECT count(*) FROM public.dating_notify_requests WHERE user_id = v_a) <> 1
     OR (SELECT country_code::text || '/' || region_code FROM public.dating_notify_requests WHERE user_id = v_a) IS DISTINCT FROM 'GH/TV' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: one request per person, the newest kept';
  END IF;
  IF pg_temp.metric('dating.notify.requested') <> v_before + 2 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the requests were not counted';
  END IF;
  -- The home says so, to that person only.
  INSERT INTO public.dating_profiles (user_id, display_name, country_code, region_code) VALUES
    (v_a, 'A', 'GH', 'TV'), (v_b, 'B', 'GH', 'TV');
  IF pg_temp.home(v_a) #>> '{notify,requested}' IS DISTINCT FROM 'true'
     OR pg_temp.home(v_b) #>> '{notify,requested}' IS DISTINCT FROM 'false' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the notice shows on the wrong person''s home';
  END IF;
  -- Cancelling: never gated (Dating off), idempotent.
  UPDATE public.feature_flags SET enabled = false WHERE key = 'dating_mode_enabled';
  v := pg_temp.call(v_a, 'SELECT public.cancel_dating_country_notice()');
  v2 := pg_temp.call(v_a, 'SELECT public.cancel_dating_country_notice()');
  IF v IS DISTINCT FROM '{"ok": true}'::jsonb OR v2 IS DISTINCT FROM '{"ok": true}'::jsonb
     OR EXISTS (SELECT 1 FROM public.dating_notify_requests WHERE user_id = v_a) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: cancelling failed or was gated';
  END IF;
  UPDATE public.feature_flags SET enabled = true WHERE key = 'dating_mode_enabled';
  -- M-10: at most 20 accepted requests a day; the 21st is refused, calmly.
  FOR i IN 1..20 LOOP
    v := pg_temp.call(v_r, $q$SELECT public.request_dating_country_notice('NG', NULL)$q$);
    IF v IS DISTINCT FROM '{"ok": true}'::jsonb THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: request % of 20 refused: %', i, v;
    END IF;
  END LOOP;
  v := pg_temp.call(v_r, $q$SELECT public.request_dating_country_notice('NG', NULL)$q$);
  IF v IS DISTINCT FROM '{"ok": false, "reason": "rate_limited"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the 21st request in a day reads %', v;
  END IF;
  PERFORM pg_temp.call(v_r, 'SELECT public.cancel_dating_country_notice()');
END $c$;

-- =====================================================================
-- D. A publish that opens a country or a region queues one neutral
--    me_update per request and forgets the request (§2.7, §3.13, I-9);
--    nothing else is queued; the payload and key name nobody and no Dating.
-- =====================================================================
DO $d$
DECLARE
  v_tv constant uuid := pg_temp.person('40');
  v_ng constant uuid := pg_temp.person('41');
  v_stale constant uuid := pg_temp.person('42');
  v_country constant uuid := pg_temp.person('43');
  v_stale_gb constant uuid := pg_temp.person('44');
  v_nokey constant uuid := pg_temp.person('45');
  v_failed bigint;
  v_row public.scheduled_notifications;
  v jsonb;
  v2 jsonb;
BEGIN
  PERFORM pg_temp.call(v_tv, $q$SELECT public.request_dating_country_notice('GH', 'TV')$q$);
  PERFORM pg_temp.call(v_ng, $q$SELECT public.request_dating_country_notice('NG', NULL)$q$);
  -- A stale row for a region already open (no RPC can make one).
  INSERT INTO public.dating_notify_requests (user_id, country_code, region_code) VALUES
    (v_stale, 'GH', 'AA'), (v_stale_gb, 'GB', NULL);
  -- Something that isn't an opening queues nothing (an open country's
  -- republish never tells a country-wide request).
  v := public.publish_country_config('GH', '{"reviewed_by": "w3a contract"}');
  v2 := public.publish_country_config('GB', '{"reviewed_by": "w3a contract"}');
  IF v ? 'notified' OR v2 ? 'notified'
     OR EXISTS (SELECT 1 FROM public.scheduled_notifications WHERE user_id IN (v_tv, v_ng, v_stale, v_stale_gb)) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a publish that opened nothing queued %', v;
  END IF;
  -- M-8: with no push key nothing is queued, the publish still succeeds,
  -- the request waits for the next opening, and the failure is counted.
  PERFORM pg_temp.call(v_nokey, $q$SELECT public.request_dating_country_notice('GH', 'WP')$q$);
  v_failed := pg_temp.metric('dating.notify.queue_failed');
  PERFORM set_config('app.settings.dating_push_key', '', true);
  v := public.publish_country_config('GH', '{"open_regions": ["AA", "AH", "WP"]}');
  PERFORM set_config('app.settings.dating_push_key', 'spec2-w3a-push-key', true);
  IF (v ->> 'ok')::boolean IS NOT TRUE OR v ? 'notified'
     OR EXISTS (SELECT 1 FROM public.scheduled_notifications WHERE user_id = v_nokey)
     OR NOT EXISTS (SELECT 1 FROM public.dating_notify_requests WHERE user_id = v_nokey)
     OR pg_temp.metric('dating.notify.queue_failed') <> v_failed + 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: with no push key the publish reads % (nothing queued, request kept, counted)', v;
  END IF;
  v := public.publish_country_config('GH', '{"open_regions": ["AA", "AH", "TV"]}');
  IF (v ->> 'notified')::int IS DISTINCT FROM 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: opening Volta told % people (1 expected): %', v ->> 'notified', v;
  END IF;
  SELECT * INTO v_row FROM public.scheduled_notifications WHERE user_id = v_tv;
  IF v_row.metadata IS DISTINCT FROM '{"type": "me_update", "route": "me", "title": "Attune", "body": "Something you asked about is ready in Attune."}'::jsonb
     OR v_row.notification_type IS DISTINCT FROM 'immediate' OR v_row.status IS DISTINCT FROM 'pending'
     OR position('dating' IN lower(v_row.metadata::text || v_row.source_key)) > 0
     OR position(v_tv::text IN v_row.source_key) > 0 OR position('GH' IN v_row.source_key) > 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the queued push is not the neutral me_update: % / %', v_row.metadata, v_row.source_key;
  END IF;
  IF EXISTS (SELECT 1 FROM public.dating_notify_requests WHERE user_id = v_tv)
     OR NOT EXISTS (SELECT 1 FROM public.dating_notify_requests WHERE user_id = v_ng)
     OR EXISTS (SELECT 1 FROM public.scheduled_notifications WHERE user_id IN (v_ng, v_stale)) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the wrong requests were told or forgotten';
  END IF;
  -- Opening the whole of Nigeria (it has no region list), then closing it.
  PERFORM pg_temp.call(v_country, $q$SELECT public.request_dating_country_notice('NG', NULL)$q$);
  v := public.publish_country_config('NG', '{"dating_enabled": true}');
  IF (v ->> 'ok')::boolean IS NOT TRUE OR (v ->> 'notified')::int IS DISTINCT FROM 2
     OR EXISTS (SELECT 1 FROM public.dating_notify_requests WHERE country_code = 'NG') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: opening Nigeria reads % (2 told expected)', v;
  END IF;
  v := public.publish_country_config('NG', '{"dating_enabled": false}');
  IF v ? 'notified' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a closing publish queued a push';
  END IF;
END $d$;

-- =====================================================================
-- E. (W2 carry) The reflection trims every Unicode space: an answer of
--    nothing but spaces is the clear; a padded answer is saved trimmed.
-- =====================================================================
DO $e$
DECLARE
  v_p constant uuid := pg_temp.person('50');
  v jsonb;
BEGIN
  v := pg_temp.call(v_p, $q$SELECT public.save_gentle_wait_reflection(jsonb_build_object('q1', E' Patience \t', 'q2', E'　\n'))$q$);
  IF (v ->> 'ok')::boolean IS NOT TRUE
     OR (SELECT answers FROM public.dating_gentle_wait_reflections WHERE user_id = v_p) IS DISTINCT FROM '{"q1": "Patience"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: Unicode spaces were kept: % / %', v,
      (SELECT answers FROM public.dating_gentle_wait_reflections WHERE user_id = v_p);
  END IF;
  v := pg_temp.call(v_p, $q$SELECT public.save_gentle_wait_reflection(jsonb_build_object('q1', E'   \t\n'))$q$);
  IF v IS DISTINCT FROM '{"ok": true, "saved_at": null}'::jsonb
     OR (SELECT answers FROM public.dating_gentle_wait_reflections WHERE user_id = v_p) IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an answer of Unicode spaces was not the clear: %', v;
  END IF;
END $e$;

-- =====================================================================
-- F. (C-2) has_data in every home answer: no Dating data reads false; a
--    reflection, a notice request or an enrolment reads true, whatever
--    the state (Dating off included), so Leave and Clear stay reachable.
-- =====================================================================
DO $f$
DECLARE
  v_none constant uuid := pg_temp.person('60');
  v_reflect constant uuid := pg_temp.person('61');
  v_notice constant uuid := pg_temp.person('62');
  v_enrolled constant uuid := pg_temp.person('63');
BEGIN
  PERFORM pg_temp.call(v_reflect, $q$SELECT public.save_gentle_wait_reflection('{"q1": "Patience"}'::jsonb)$q$);
  PERFORM pg_temp.call(v_notice, $q$SELECT public.request_dating_country_notice('NG', NULL)$q$);
  INSERT INTO public.dating_enrollments (user_id) VALUES (v_enrolled);
  IF pg_temp.has_data(v_none) IS DISTINCT FROM 'false'
     OR pg_temp.has_data(v_reflect) IS DISTINCT FROM 'true'
     OR pg_temp.has_data(v_notice) IS DISTINCT FROM 'true'
     OR pg_temp.has_data(v_enrolled) IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: has_data reads % / % / % / % (false, true, true, true expected)',
      pg_temp.has_data(v_none), pg_temp.has_data(v_reflect), pg_temp.has_data(v_notice), pg_temp.has_data(v_enrolled);
  END IF;
  UPDATE public.feature_flags SET enabled = false WHERE key = 'dating_mode_enabled';
  IF pg_temp.home(v_enrolled) ->> 'state' IS DISTINCT FROM 'feature_unavailable'
     OR pg_temp.has_data(v_enrolled) IS DISTINCT FROM 'true' OR pg_temp.has_data(v_none) IS DISTINCT FROM 'false' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: with Dating off has_data reads % / %', pg_temp.has_data(v_enrolled), pg_temp.has_data(v_none);
  END IF;
  UPDATE public.feature_flags SET enabled = true WHERE key = 'dating_mode_enabled';
END $f$;

ROLLBACK;
```

- [ ] **Step 3: Run it to see it fail**

Run: `psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/dating_v2_client_reads_contracts.sql 2>&1 | grep -m1 ERROR`
Expected: `ERROR:  CONTRACT VIOLATED: a client can still read public.dating_enrollments`.

- [ ] **Step 4: The new functions**

Create `$D/new_functions_T3.sql` with exactly:

```sql
-- 1. The neutral push (§3.13, I-9): every Dating push is me_update, title
--    "Attune", one of two bodies, data {"route": "me"}; the key is opaque.
CREATE OR REPLACE FUNCTION private.dating_push_source_key(p_user uuid, p_purpose text, p_day date)
RETURNS text
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  -- Its own server secret (§3.13), never the never-introduce key (M-8).
  v_key constant text := public.app_setting('dating_push_key');
BEGIN
  -- Fail closed: with no key nothing is queued; the caller keeps its
  -- requests for the next publish (publish_country_config counts it).
  IF v_key IS NULL THEN
    RAISE EXCEPTION 'dating:push_key_missing' USING ERRCODE = 'P0001';
  END IF;
  -- Fable M4: a keyed hash of who, why and which day; never a match id,
  -- never readable as a person, a country or Dating.
  RETURN 'me_update:' || encode(extensions.hmac(
           p_user::text || '|' || p_purpose || '|' || p_day::text, v_key, 'sha256'), 'hex');
END;
$$;

CREATE OR REPLACE FUNCTION private.dating_queue_me_update(p_user uuid, p_purpose text, p_kind text)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_body text;
  v_n integer;
BEGIN
  v_body := CASE p_kind
    WHEN 'notify' THEN 'Something you asked about is ready in Attune.'
    WHEN 'new' THEN 'You have something new in Attune.'
  END;
  IF p_user IS NULL OR p_purpose IS NULL OR v_body IS NULL THEN
    RAISE EXCEPTION 'dating:invalid_push' USING ERRCODE = '22023';
  END IF;
  INSERT INTO public.scheduled_notifications
    (user_id, notification_type, scheduled_for, status, metadata, source_key, created_at, updated_at)
  VALUES (p_user, 'immediate', now(), 'pending',
          jsonb_build_object('type', 'me_update', 'route', 'me', 'title', 'Attune', 'body', v_body),
          private.dating_push_source_key(p_user, p_purpose, (now() AT TIME ZONE 'UTC')::date), now(), now())
  ON CONFLICT (source_key) WHERE source_key IS NOT NULL DO NOTHING;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n > 0;
END;
$$;

-- 2. Whether the person has any Dating data to leave or clear (C-2): a
--    profile, an enrolment, a reflection or a notice request (a kept
--    never-introduce list stays until the account is deleted, §3.8, and
--    is not read here). get_dating_home carries it in every state, so
--    Dating settings (Leave, Clear) are always reachable when they matter.
--    It reads only whether the person's own rows exist, never their text.
CREATE OR REPLACE FUNCTION private.dating_has_data(p_user uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT p_user IS NOT NULL AND (
         EXISTS (SELECT 1 FROM public.dating_enrollments AS e WHERE e.user_id = p_user)
      OR EXISTS (SELECT 1 FROM public.dating_profiles AS p WHERE p.user_id = p_user)
      OR EXISTS (SELECT 1 FROM public.dating_gentle_wait_reflections AS r WHERE r.user_id = p_user)
      OR EXISTS (SELECT 1 FROM public.dating_notify_requests AS n WHERE n.user_id = p_user));
$$;

-- 3. "Tell me when it's here" (§2.7, §3.10; R-5, R-6).
CREATE OR REPLACE FUNCTION private.dating_notice_state(p_user uuid, p_country text, p_region text)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  -- available: the place itself is closed (a request for an open country,
  -- with Dating off by the global switch, could never fire; R-5).
  SELECT jsonb_build_object(
    'available', coalesce(p_country IS NOT NULL AND private.dating_iso_country(p_country) IS NOT NULL
                   AND NOT coalesce((SELECT c.dating_enabled
                                            AND (p_region IS NULL OR c.open_regions IS NULL OR p_region = ANY (c.open_regions))
                                       FROM public.dating_country_config(p_country) AS c), false), false),
    'requested', EXISTS (SELECT 1 FROM public.dating_notify_requests AS n
                          WHERE n.user_id = p_user AND n.country_code = p_country
                            AND n.region_code IS NOT DISTINCT FROM p_region));
$$;

CREATE OR REPLACE FUNCTION public.request_dating_country_notice(p_country text, p_region text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
SET lock_timeout = '2s'
AS $$
DECLARE
  v_user constant uuid := auth.uid();
  v_code text;
  v_region text;
  v_config public.country_safety_config;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;
  -- Pre-validated: nothing the person typed reaches an error.
  IF p_country IS NULL OR char_length(p_country) > 8 THEN
    RETURN private.dating_invalid('country');
  END IF;
  v_code := upper(btrim(p_country));
  IF v_code !~ '^[A-Z]{2}$' OR private.dating_iso_country(v_code) IS NULL THEN
    RETURN private.dating_invalid('country');
  END IF;
  IF p_region IS NOT NULL AND (char_length(p_region) > 8 OR upper(btrim(p_region)) !~ '^[A-Z0-9]{2,3}$') THEN
    RETURN private.dating_invalid('region');
  END IF;
  v_region := nullif(upper(btrim(coalesce(p_region, ''))), '');
  -- At most 20 a day (M-10): the aggregate can't be inflated from one app.
  BEGIN
    PERFORM public.check_dating_rate_limit('notify_request', 20, interval '1 day');
  EXCEPTION WHEN invalid_parameter_value THEN
    IF SQLERRM = 'rate_limited' THEN
      RETURN jsonb_build_object('ok', false, 'reason', 'rate_limited');
    END IF;
    RAISE;
  END;
  -- The publisher's own lock first (R-6): a request and a publish that
  -- opens the place serialise, so neither misses the other.
  BEGIN
    PERFORM pg_advisory_xact_lock(hashtextextended('country_safety_config:' || v_code, 0));
  EXCEPTION WHEN lock_not_available OR query_canceled THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'busy');
  END;
  v_config := public.dating_country_config(v_code);
  IF v_region IS NOT NULL AND NOT EXISTS (
       SELECT 1 FROM jsonb_array_elements(coalesce(v_config.region_list, '[]'::jsonb)) AS r
        WHERE r ->> 'code' = v_region) THEN
    RETURN private.dating_invalid('region');
  END IF;
  IF v_config.dating_enabled IS TRUE
     AND (v_region IS NULL OR v_config.open_regions IS NULL OR v_region = ANY (v_config.open_regions)) THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'already_open');
  END IF;
  BEGIN
    INSERT INTO public.dating_notify_requests AS n (user_id, country_code, region_code, created_at)
    VALUES (v_user, v_code, v_region, now())
    ON CONFLICT (user_id) DO UPDATE
      SET country_code = EXCLUDED.country_code, region_code = EXCLUDED.region_code, created_at = now();
  EXCEPTION WHEN lock_not_available OR deadlock_detected OR serialization_failure OR query_canceled THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'busy');
  END;
  BEGIN
    PERFORM private.bump_metric_internal('dating.notify.requested');
  EXCEPTION WHEN OTHERS THEN
    NULL;
  END;
  RETURN jsonb_build_object('ok', true);
END;
$$;

-- Exposure-reducing: never gated, idempotent, never raises for a busy row.
CREATE OR REPLACE FUNCTION public.cancel_dating_country_notice()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
SET lock_timeout = '1s'
AS $$
DECLARE
  v_user constant uuid := auth.uid();
  v_try integer;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;
  FOR v_try IN 1..3 LOOP
    BEGIN
      DELETE FROM public.dating_notify_requests AS n WHERE n.user_id = v_user;
      RETURN jsonb_build_object('ok', true);
    EXCEPTION WHEN deadlock_detected OR lock_not_available OR serialization_failure OR query_canceled THEN
      NULL;
    END;
  END LOOP;
  RETURN jsonb_build_object('ok', false, 'reason', 'busy');
END;
$$;

-- What a publish opened, told once (publish_country_config calls it in
-- its own transaction, under its own lock): a country-wide request when
-- the country opens from closed (a country with no region list opens with
-- none); a region request when that region newly opens. Each told request
-- is deleted.
CREATE OR REPLACE FUNCTION private.dating_notify_opened(p_country text, p_was_open boolean, p_open_old text[], p_open_new text[])
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_old constant text[] := coalesce(p_open_old, ARRAY[]::text[]);
  v_new constant text[] := coalesce(p_open_new, ARRAY[]::text[]);
  v_user uuid;
  v_told integer := 0;
BEGIN
  FOR v_user IN
    SELECT n.user_id FROM public.dating_notify_requests AS n
     WHERE n.country_code = p_country
       AND ((n.region_code IS NULL AND p_was_open IS NOT TRUE)
            OR (n.region_code IS NOT NULL AND n.region_code = ANY (v_new) AND NOT (n.region_code = ANY (v_old))))
     ORDER BY n.user_id
       FOR UPDATE OF n
  LOOP
    IF private.dating_queue_me_update(v_user, 'notify:' || p_country, 'notify') THEN
      v_told := v_told + 1;
    END IF;
    DELETE FROM public.dating_notify_requests AS d WHERE d.user_id = v_user;
  END LOOP;
  RETURN v_told;
END;
$$;
```

- [ ] **Step 5: Build the migration from the live bodies, and its twin**

Create `$D/build_mig_T3.py` with exactly:

```python
# Builds 20261107150000_dating_v2_client_reads.sql: the new functions, then
# three functions re-created from their LIVE bodies (Task 1's before/ copies)
# with only the lines marked "-- Spec 2 W3a" changed.
import pathlib
D = pathlib.Path('.superpowers/sdd/2026-11-07-spec2-w3')

def live(sig, pairs):
    s = (D / 'before' / f'{sig}.sql').read_text().rstrip('\n')
    for old, new in pairs:
        assert s.count(old) == 1, (sig, s.count(old), old[:70])
        s = s.replace(old, new)
    return s + ';\n'

HOME = live('public.get_dating_home()', [
    ("  v_err text;\nBEGIN", "  v_err text;\n  v_cand text; -- Spec 2 W3a\nBEGIN"),
    ("    RETURN jsonb_build_object('state', 'feature_unavailable', 'country',\n"
     "      coalesce(v_country, private.dating_phone_country((SELECT a.phone FROM auth.users AS a WHERE a.id = v_user))));",
     "    v_country := coalesce(v_country, private.dating_phone_country((SELECT a.phone FROM auth.users AS a WHERE a.id = v_user))); -- Spec 2 W3a\n"
     "    RETURN jsonb_build_object('state', 'feature_unavailable', 'country', v_country,\n"
     "      'notify', private.dating_notice_state(v_user, v_country, NULL)); -- Spec 2 W3a (R-4, R-5)"),
    ("    RETURN jsonb_build_object('state', 'country_closed', 'country', v_country);",
     "    RETURN jsonb_build_object('state', 'country_closed', 'country', v_country,\n"
     "      'notify', private.dating_notice_state(v_user, v_country, NULL)); -- Spec 2 W3a"),
    ("      'open_regions', to_jsonb(coalesce(v_config.open_regions, ARRAY[]::text[])));",
     "      'open_regions', to_jsonb(coalesce(v_config.open_regions, ARRAY[]::text[])), -- Spec 2 W3a\n"
     "      'notify', private.dating_notice_state(v_user, v_country, v_region)); -- Spec 2 W3a"),
    ("    RETURN jsonb_build_object('state', 'paused', 'pause_reason', v_enrol.pause_reason);\n  END IF;\n  v_opens :=",
     "    RETURN jsonb_build_object('state', 'paused', 'pause_reason', v_enrol.pause_reason)\n"
     "      || CASE WHEN v_enrol.pause_reason = 'same_gender_switch' THEN jsonb_build_object('country', v_country) -- Spec 2 W3a (the §2.4 note)\n"
     "              ELSE '{}'::jsonb END; -- Spec 2 W3a\n  END IF;\n  v_opens :="),
    ("  IF v_enrol.state = 'active' THEN\n",
     "  IF v_enrol.state = 'active' THEN\n"
     "    -- Spec 2 W3a (W2 carry): never \"you're live\" while the candidate check\n"
     "    -- Spec 2 W3a refuses for anything but the wait (an undated ending, a\n"
     "    -- Spec 2 W3a path off Dating); the wait itself is the cool-off below.\n"
     "    v_cand := public.dating_eligibility(v_user, 'candidate'); -- Spec 2 W3a\n"
     "    IF v_cand IS DISTINCT FROM 'eligible' AND v_cand IS DISTINCT FROM 'gentle_wait' THEN -- Spec 2 W3a\n"
     "      RETURN jsonb_build_object('state', 'unavailable'); -- Spec 2 W3a\n"
     "    END IF; -- Spec 2 W3a\n"),
    ("                              'next_step', private.dating_next_step(v_user));",
     "                              'next_step', private.dating_next_step(v_user), -- Spec 2 W3a\n"
     "                              'can_shorten', coalesce(private.dating_gentle_wait_can_shorten(v_user), false), -- Spec 2 W3a (carry 8)\n"
     "                              'first_drop_at', private.dating_first_drop_at(v_user, greatest(v_opens, now(), -- Spec 2 W3a\n"
     "                                (SELECT u.created_at FROM public.users AS u WHERE u.id = v_user) + interval '72 hours'))); -- Spec 2 W3a"),
    ("    RETURN jsonb_build_object('state', 'not_started');",
     "    RETURN jsonb_build_object('state', 'not_started', -- Spec 2 W3a (D1 line 6)\n"
     "      'first_drop_at', private.dating_first_drop_at(v_user, greatest(now(), -- Spec 2 W3a\n"
     "        (SELECT u.created_at FROM public.users AS u WHERE u.id = v_user) + interval '72 hours'))); -- Spec 2 W3a"),
    ("  RETURN jsonb_build_object('state', 'setup_in_progress', 'next_step', private.dating_next_step(v_user));",
     "  RETURN jsonb_build_object('state', 'setup_in_progress', 'next_step', private.dating_next_step(v_user),\n"
     "    'first_drop_at', private.dating_first_drop_at(v_user, greatest(now(), -- Spec 2 W3a (D13)\n"
     "      (SELECT u.created_at FROM public.users AS u WHERE u.id = v_user) + interval '72 hours'))); -- Spec 2 W3a"),
])

# C-2: every home answer carries has_data (any Dating profile, enrolment,
# reflection or notice request), so the section
# offers Dating settings, and with them Leave and Clear, whenever there is
# something to leave or clear, in every state.
def with_has_data(s):
    for old, new in [
        ("  v_cand text; -- Spec 2 W3a\nBEGIN",
         "  v_cand text; -- Spec 2 W3a\n  v_has jsonb; -- Spec 2 W3a (C-2)\nBEGIN"),
        ("  v_reason := public.dating_eligibility(v_user, 'setup');\n",
         "  v_has := jsonb_build_object('has_data', private.dating_has_data(v_user)); -- Spec 2 W3a (C-2)\n"
         "  v_reason := public.dating_eligibility(v_user, 'setup');\n"),
    ]:
        assert s.count(old) == 1, old[:60]
        s = s.replace(old, new)
    out = []
    for line in s.split('\n'):
        for old in ('RETURN jsonb_build_object(', 'RETURN CASE WHEN'):
            if old in line:
                line = line.replace(old, 'RETURN coalesce(v_has, \'{"has_data": true}\') || ' + old[len('RETURN '):], 1)
                if '-- Spec 2 W3a' not in line:
                    line += ' -- Spec 2 W3a (C-2)'
        out.append(line)
    return '\n'.join(out)

HOME = with_has_data(HOME)

PUBLISH = live('public.publish_country_config(text,jsonb)', [
    ("  v_failed text; -- Spec 2 W1d (fix round 1, I-1)\nBEGIN",
     "  v_failed text; -- Spec 2 W1d (fix round 1, I-1)\n  v_told integer; -- Spec 2 W3a\nBEGIN"),
    ("  INSERT INTO public.country_safety_config SELECT v_new.*;\n",
     "  INSERT INTO public.country_safety_config SELECT v_new.*;\n"
     "  -- Spec 2 W3a (§2.7, R-6): \"Tell me when it's here\": what this publish\n"
     "  -- Spec 2 W3a opened is told once, then forgotten. A failure here never\n"
     "  -- Spec 2 W3a stops the publish (its requests stay for the next one).\n"
     "  IF v_new.dating_enabled THEN -- Spec 2 W3a\n"
     "    BEGIN -- Spec 2 W3a\n"
     "      v_told := private.dating_notify_opened(v_code, v_old.dating_enabled IS TRUE, v_open_old, v_open_new); -- Spec 2 W3a\n"
     "    EXCEPTION WHEN OTHERS THEN -- Spec 2 W3a\n"
     "      v_told := NULL; -- Spec 2 W3a\n"
     "      BEGIN PERFORM private.bump_metric_internal('dating.notify.queue_failed'); EXCEPTION WHEN OTHERS THEN NULL; END; -- Spec 2 W3a\n"
     "    END; -- Spec 2 W3a\n"
     "  END IF; -- Spec 2 W3a\n"),
    ("                 ELSE '{}'::jsonb END; -- Spec 2 W1d\nEND;",
     "                 ELSE '{}'::jsonb END -- Spec 2 W1d -- Spec 2 W3a (no semicolon)\n"
     "         || CASE WHEN coalesce(v_told, 0) > 0 THEN jsonb_build_object('notified', v_told) -- Spec 2 W3a\n"
     "                 ELSE '{}'::jsonb END; -- Spec 2 W3a\nEND;"),
])

SAVE = live('public.save_gentle_wait_reflection(jsonb)', [
    ("    'q1', nullif(btrim(p_answers ->> 'q1'), ''),\n"
     "    'q2', nullif(btrim(p_answers ->> 'q2'), ''),\n"
     "    'q3', nullif(btrim(p_answers ->> 'q3'), '')));",
     "    -- Spec 2 W3a (W2 carry): every Unicode space, not only ' '.\n"
     "    'q1', nullif(private.dating_trim(p_answers ->> 'q1'), ''), -- Spec 2 W3a\n"
     "    'q2', nullif(private.dating_trim(p_answers ->> 'q2'), ''), -- Spec 2 W3a\n"
     "    'q3', nullif(private.dating_trim(p_answers ->> 'q3'), ''))); -- Spec 2 W3a"),
])

HEAD = """-- Spec 2 W3a, migration 1 (§4.9 W3a; §2.7, §3.1, §3.13, §4.1, §4.4, §4.10;
-- I-4, I-9, R11, R21; plan R-2 to R-7): the neutral me_update push and
-- "Tell me when it's here" (queued by publish_country_config when it opens
-- a country or a region); the four "owner read" policies dropped (their
-- 20260811120000 grants are revoked in the twin; the photo and intent
-- tables wait for W3c, R-2); get_dating_eligibility() dropped (the app's
-- last callers went in Task 2; the lib/ grep test is green); get_dating_home
-- v2 (R-4) and the reflection's Unicode trim, re-created from their live
-- bodies (only the lines marked "-- Spec 2 W3a" differ).
-- Grants in 20261107150010_dating_v2_client_reads_grants.sql.
BEGIN;
SET LOCAL lock_timeout = '5s';

"""
TAIL = """
-- 4. No client reads a Dating table (§4.1, R11): the four owner-read policies.
DROP POLICY IF EXISTS "dating enrollments owner read" ON public.dating_enrollments;
DROP POLICY IF EXISTS "dating consent owner read" ON public.dating_consent_events;
DROP POLICY IF EXISTS "dating profiles owner read" ON public.dating_profiles;
DROP POLICY IF EXISTS "dating preferences owner read" ON public.dating_preferences;

-- 5. The shim's last day (I-4, R21).
DROP FUNCTION IF EXISTS public.get_dating_eligibility();

REVOKE ALL ON FUNCTION private.dating_push_source_key(uuid, text, date) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_queue_me_update(uuid, text, text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_notice_state(uuid, text, text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_notify_opened(text, boolean, text[], text[]) FROM PUBLIC, anon, authenticated, service_role;

COMMIT;
"""
body = (D / 'new_functions_T3.sql').read_text()
out = (HEAD + body + "\n-- 3. Re-created from their live bodies.\n" + PUBLISH + '\n' + HOME + '\n' + SAVE + TAIL)
pathlib.Path('supabase/migrations/20261107150000_dating_v2_client_reads.sql').write_text(out)
print('written', out.count('-- Spec 2 W3a'), 'marked lines')
```

Create `supabase/migrations/20261107150010_dating_v2_client_reads_grants.sql` with exactly:

```sql
-- Spec 2 W3a: grants for 20261107150000_dating_v2_client_reads.sql.
-- R11: the 20260811120000 client SELECT on the four tables is revoked
-- (table and any column grant); the photo and intent tables keep theirs
-- until W3c moves the storage policies (R-2). The notice RPCs are the
-- app's; the push and notice helpers are no API role's; the re-created
-- functions keep their W1/W2 grants (re-asserted).
BEGIN;
SET LOCAL lock_timeout = '5s';
REVOKE SELECT ON TABLE public.dating_enrollments, public.dating_consent_events,
  public.dating_profiles, public.dating_preferences FROM authenticated, anon;
DO $cols$
DECLARE
  r record;
BEGIN
  FOR r IN SELECT DISTINCT c.table_name, c.column_name, c.grantee
             FROM information_schema.column_privileges AS c
            WHERE c.table_schema = 'public' AND c.privilege_type = 'SELECT'
              AND c.grantee IN ('authenticated', 'anon')
              AND c.table_name IN ('dating_enrollments', 'dating_consent_events', 'dating_profiles', 'dating_preferences') LOOP
    EXECUTE format('REVOKE SELECT (%I) ON TABLE public.%I FROM %I', r.column_name, r.table_name, r.grantee);
  END LOOP;
END $cols$;
REVOKE ALL ON FUNCTION public.request_dating_country_notice(text, text) FROM PUBLIC, anon, service_role;
REVOKE ALL ON FUNCTION public.cancel_dating_country_notice() FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.request_dating_country_notice(text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.cancel_dating_country_notice() TO authenticated;
REVOKE ALL ON FUNCTION private.dating_push_source_key(uuid, text, date) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_queue_me_update(uuid, text, text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_notice_state(uuid, text, text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_has_data(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION private.dating_notify_opened(text, boolean, text[], text[]) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.get_dating_home() FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.get_dating_home() TO authenticated;
REVOKE ALL ON FUNCTION public.save_gentle_wait_reflection(jsonb) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.save_gentle_wait_reflection(jsonb) TO authenticated;
REVOKE ALL ON FUNCTION public.publish_country_config(text, jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.publish_country_config(text, jsonb) TO service_role;
COMMIT;
```

```bash
D=.superpowers/sdd/2026-11-07-spec2-w3
python3 -I $D/build_mig_T3.py
for f in supabase/migrations/20261107150000_dating_v2_client_reads.sql supabase/migrations/20261107150010_dating_v2_client_reads_grants.sql; do
  for run in 1 2; do psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f $f > /dev/null; echo "$(basename $f) run $run exit=$?"; done
done
for sig in 'public.get_dating_home()' 'public.publish_country_config(text,jsonb)' 'public.save_gentle_wait_reflection(jsonb)'; do
  psql -X -d attune_spec3a -Atc "select pg_get_functiondef('$sig'::regprocedure)" > /tmp/w3a_after.sql
  echo "== $sig: changed lines not marked W3a:"; diff "$D/before/$sig.sql" /tmp/w3a_after.sql | grep '^>' | grep -vc -- '-- Spec 2 W3a' ; rm -f /tmp/w3a_after.sql
done
python3 -I $D/grants_line.py supabase/migrations/20261107140010_dating_v2_home_grants.sql \
  "Spec 2 W3a: the four owner-read grants revoked (R11); the notice RPCs are the app's; the push helpers are the database's own." \
  supabase/migrations/20261107150010_dating_v2_client_reads_grants.sql
```

Expected: `written 61 marked lines` (any count is fine; it is printed for the report); four `exit=0` lines; for each function `0` (verified, fix round 1, M-2) (every changed line carries the marker; a `0` for `publish_country_config` also proves its v1d body was the live one); `local_pg_grants.sql: one \i block added`.

- [ ] **Step 6: The existing contracts W3a changes, and the canary**

Create `$D/edit_contracts_T3.py` with exactly:

```python
import pathlib, sys
sys.path.insert(0, '.superpowers/sdd/2026-11-07-spec2-w3')
from anchor import edit

def cut(path, start, end, replacement, label):
    p = pathlib.Path(path)
    s = p.read_text()
    assert s.count(start) == 1 and s.count(end) == 1, (label, s.count(start), s.count(end))
    i = s.index(start)
    j = s.index(end, i) + len(end)
    p.write_text(s[:i] + replacement + s[j:])
    print(f'{path}: cut ({label})')

# W2's home contract pins v1's payloads; the keys W3a adds are pinned in
# dating_v2_client_reads_contracts.sql (R-4).
edit('supabase/tests/dating_v2_home_contracts.sql', [
    ("  PERFORM pg_temp.as_person(p);\n  v := public.get_dating_home();\n  PERFORM pg_temp.as_db();\n  RETURN v;",
     "  PERFORM pg_temp.as_person(p);\n  v := public.get_dating_home();\n  PERFORM pg_temp.as_db();\n"
     "  -- Spec 2 W3a (R-4): the keys W3a adds are pinned in dating_v2_client_reads_contracts.sql.\n"
     "  v := v - 'notify' - 'can_shorten' - 'has_data';\n"
     "  IF v ->> 'state' IN ('not_started', 'setup_in_progress', 'gentle_wait') THEN\n"
     "    v := v - 'first_drop_at';\n"
     "  END IF;\n  RETURN v;"),
], 'T3 home helper')

E = 'supabase/tests/dating_v2_eligibility_contracts.sql'
cut(E, "-- F. (W2, I-4) get_dating_eligibility() is a same-shape shim over the\n",
    "END $shim$;\n",
    "-- F. (W3a, I-4, R21) get_dating_eligibility() is gone. Its W2 fixture\n"
    "--    (person 55 and the pending relationship) stays for later sections.\n"
    "-- =====================================================================\n"
    "DO $shim$\n"
    "DECLARE\n"
    "  v_inviter constant uuid := pg_temp.person('55');\n"
    "BEGIN\n"
    "  INSERT INTO public.relationships (user_a, user_b, status, invite_code, invite_expires_at)\n"
    "  VALUES (v_inviter, NULL, 'pending', 'W2SHIM01', now() + interval '1 day');\n"
    "  IF to_regprocedure('public.get_dating_eligibility()') IS NOT NULL THEN\n"
    "    RAISE EXCEPTION 'CONTRACT VIOLATED: get_dating_eligibility() still exists (W3a drops it)';\n"
    "  END IF;\n"
    "END $shim$;\n",
    'T3 eligibility F')
cut(E, "  -- The shim: a NULL age answer is not verified.\n",
    "    RAISE EXCEPTION 'CONTRACT VIOLATED: the shim read a NULL age answer as % (expected true/false)', v;\n  END IF;\n\n",
    '', 'T3 eligibility shim probe')

edit('supabase/tests/dating_rls_canary.sql', [
    ("-- ---------------------------------------------------------------------\n"
     "-- Checks (every batch adds its rows above this line).\n",
     "-- ---------------------------------------------------------------------\n"
     "-- W3a (migration 1): the four 20260811120000 tables lose the client\n"
     "-- SELECT (R11); the shim is gone (I-4); the notice RPCs are the app's;\n"
     "-- the push and notice helpers are no API role's.\n"
     "-- ---------------------------------------------------------------------\n"
     "UPDATE allowed_rel SET authenticated = ''\n"
     " WHERE name IN ('dating_consent_events', 'dating_enrollments', 'dating_preferences', 'dating_profiles');\n"
     "DELETE FROM allowed_fn WHERE sig = 'get_dating_eligibility()';\n"
     "INSERT INTO allowed_fn (sig, clients, service) VALUES\n"
     "  ('cancel_dating_country_notice()', 'authenticated', ''),\n"
     "  ('request_dating_country_notice(text,text)', 'authenticated', ''),\n"
     "  ('private.dating_has_data(uuid)', '', ''),\n"
     "  ('private.dating_notice_state(uuid,text,text)', '', ''),\n"
     "  ('private.dating_notify_opened(text,boolean,text[],text[])', '', ''),\n"
     "  ('private.dating_push_source_key(uuid,text,date)', '', ''),\n"
     "  ('private.dating_queue_me_update(uuid,text,text)', '', '');\n"
     "-- ---------------------------------------------------------------------\n"
     "-- Checks (every batch adds its rows above this line).\n"),
], 'T3 canary')

# I-2: W1's owner-RLS reads of dating_profiles / dating_enrollments become
# "authenticated is refused" (R11: no client SELECT on a Dating table).
edit('supabase/tests/dating_mode_contracts.sql', [
    ("-- 1. Owner RLS — each account sees only its own dating rows.\n"
     "-- ---------------------------------------------------------------------------\n"
     "SELECT public.test_set_dating_auth('00000000-0000-0000-0000-00000000da01');\n"
     "DO $$ DECLARE v int; BEGIN\n"
     "  SELECT count(*) INTO v FROM public.dating_profiles;\n"
     "  IF v <> 1 THEN RAISE EXCEPTION 'A: profile RLS expected 1 own row, got %', v; END IF;\n"
     "  SELECT count(*) INTO v FROM public.dating_enrollments;\n"
     "  IF v <> 1 THEN RAISE EXCEPTION 'A: enrollment RLS expected 1 own row, got %', v; END IF;\n"
     "END $$;\n",
     "-- 1. Owner reads — Spec 2 W3a (R11): the app reads its own Dating rows\n"
     "--    only through definer RPCs; a direct SELECT is refused outright.\n"
     "-- ---------------------------------------------------------------------------\n"
     "SELECT public.test_set_dating_auth('00000000-0000-0000-0000-00000000da01');\n"
     "DO $$ DECLARE v int; BEGIN\n"
     "  BEGIN\n"
     "    SELECT count(*) INTO v FROM public.dating_profiles;\n"
     "    RAISE EXCEPTION 'A: a signed-in user can still SELECT dating_profiles (% rows)', v;\n"
     "  EXCEPTION WHEN insufficient_privilege THEN NULL;\n"
     "  END;\n"
     "  BEGIN\n"
     "    SELECT count(*) INTO v FROM public.dating_enrollments;\n"
     "    RAISE EXCEPTION 'A: a signed-in user can still SELECT dating_enrollments (% rows)', v;\n"
     "  EXCEPTION WHEN insufficient_privilege THEN NULL;\n"
     "  END;\n"
     "END $$;\n"),
    ("DO $$ DECLARE v int; BEGIN\n"
     "  SELECT count(*) INTO v FROM public.dating_profiles;\n"
     "  IF v <> 1 THEN RAISE EXCEPTION 'C: profile RLS expected 1 own row, got %', v; END IF;\n",
     "DO $$ DECLARE v int; BEGIN\n"
     "  BEGIN\n"
     "    SELECT count(*) INTO v FROM public.dating_profiles;\n"
     "    RAISE EXCEPTION 'C: a signed-in user can still SELECT dating_profiles (% rows)', v;\n"
     "  EXCEPTION WHEN insufficient_privilege THEN NULL;\n"
     "  END;\n"),
], 'T3 dating_mode owner reads (I-2)')

# C-2 (R-43): get_dating_home's has_data asks only whether the person's own
# reflection row exists; W2's "who reaches the reflections" pin names it.
edit('supabase/tests/dating_v2_home_contracts.sql', [
    ("  IF v IS DISTINCT FROM 'get_my_gentle_wait_reflection(), private.dating_carry_on_auth_user_delete(), '\n"
     "                        'private.dating_exit_internal(uuid,boolean), save_gentle_wait_reflection(jsonb)' THEN\n",
     "  -- Spec 2 W3a (C-2, R-43): private.dating_has_data reads only whether the\n"
     "  -- person's own row exists (get_dating_home's has_data), never the text.\n"
     "  IF v IS DISTINCT FROM 'get_my_gentle_wait_reflection(), private.dating_carry_on_auth_user_delete(), '\n"
     "                        'private.dating_exit_internal(uuid,boolean), private.dating_has_data(uuid), '\n"
     "                        'save_gentle_wait_reflection(jsonb)' THEN\n"),
], 'T3 reflection readers pin (C-2)')
```

```bash
D=.superpowers/sdd/2026-11-07-spec2-w3
python3 -I $D/edit_contracts_T3.py
for f in dating_v2_client_reads_contracts dating_v2_home_contracts dating_v2_eligibility_contracts dating_rls_canary dating_v2_setup_contracts dating_v2_identity_contracts country_safety_config_contracts dating_mode_contracts; do
  psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/$f.sql > /dev/null 2>/tmp/w3a.err && echo "PASS $f" || echo "FAIL $f: $(grep -m1 ERROR /tmp/w3a.err)"
done; rm -f /tmp/w3a.err
```

Expected: the six edit lines print (`T3 home helper`, the two `cut` lines, `T3 canary`, `T3 dating_mode owner reads (I-2)`, `T3 reflection readers pin (C-2)`); eight `PASS` lines (verified on a clone of `attune_spec3a`, fix round 1). A FAIL in a W1/W2 contract is examined: if it pins a payload or grant W3a changes on purpose (R-4, R11), amend that one assertion with an exact-anchor script and say so in the report; anything else is a regression to fix in the migration.

- [ ] **Step 7: Mutants**

Create `$D/mut_T3.py` with exactly:

```python
MUTS = {
 'home_active_ignores_candidate': ('CUT', ("    -- Spec 2 W3a (W2 carry): never \"you're live\" while the candidate check\n",
                                           "    END IF; -- Spec 2 W3a\n")),
 'home_country_closed_no_notify': ("jsonb_build_object('state', 'country_closed', 'country', v_country, -- Spec 2 W3a (C-2)\n      'notify', private.dating_notice_state(v_user, v_country, NULL)); -- Spec 2 W3a",
                                   "jsonb_build_object('state', 'country_closed', 'country', v_country);"),
 'home_no_has_data': ("  v_has := jsonb_build_object('has_data', private.dating_has_data(v_user)); -- Spec 2 W3a (C-2)\n",
                      "  v_has := jsonb_build_object('has_data', false);\n"),
 'home_no_can_shorten': ("                              'can_shorten', coalesce(private.dating_gentle_wait_can_shorten(v_user), false), -- Spec 2 W3a (carry 8)\n", ""),
 'notice_available_always': ("    'available', coalesce(p_country IS NOT NULL", "    'available', coalesce(true OR p_country IS NOT NULL"),
 'request_open_taken': ("    RETURN jsonb_build_object('ok', false, 'reason', 'already_open');", "    NULL;"),
 'request_unvalidated': ("  IF v_code !~ '^[A-Z]{2}$' OR private.dating_iso_country(v_code) IS NULL THEN\n    RETURN private.dating_invalid('country');\n  END IF;\n", ""),
 'request_no_lock': ("    PERFORM pg_advisory_xact_lock(hashtextextended('country_safety_config:' || v_code, 0));\n", "    NULL;\n"),
 'queue_reopened': ("            OR (n.region_code IS NOT NULL AND n.region_code = ANY (v_new) AND NOT (n.region_code = ANY (v_old))))",
                    "            OR (n.region_code IS NOT NULL AND n.region_code = ANY (v_new)))"),
 'queue_keeps_requests': ("    DELETE FROM public.dating_notify_requests AS d WHERE d.user_id = v_user;\n", ""),
 'queue_names_dating': ("jsonb_build_object('type', 'me_update', 'route', 'me',", "jsonb_build_object('type', 'dating_notice', 'route', 'me',"),
 'queue_country_while_open': ("       AND ((n.region_code IS NULL AND p_was_open IS NOT TRUE)", "       AND ((n.region_code IS NULL)"),
 'trim_spaces_only': ("    'q1', nullif(private.dating_trim(p_answers ->> 'q1'), ''), -- Spec 2 W3a\n", "    'q1', nullif(btrim(p_answers ->> 'q1'), ''), -- Spec 2 W3a\n"),
 # RAW: the applied migration already dropped the policy, so the mutant puts
 # the owner read back (policy and grant) on top of it (I-7).
 'owner_read_kept': ('RAW', 'CREATE POLICY "dating profiles owner read" ON public.dating_profiles FOR SELECT TO authenticated USING (user_id = auth.uid());\n'
                            'GRANT SELECT ON TABLE public.dating_profiles TO authenticated;\n'),
 'has_data_never': ("      OR EXISTS (SELECT 1 FROM public.dating_gentle_wait_reflections AS r WHERE r.user_id = p_user)\n", ""),
 'push_key_fallback': ("  IF v_key IS NULL THEN\n    RAISE EXCEPTION 'dating:push_key_missing' USING ERRCODE = 'P0001';\n  END IF;\n", ""),
 'request_unlimited': ("    PERFORM public.check_dating_rate_limit('notify_request', 20, interval '1 day');\n", "    NULL;\n"),
 'shim_kept': ("DROP FUNCTION IF EXISTS public.get_dating_eligibility();\n",
               "CREATE OR REPLACE FUNCTION public.get_dating_eligibility() RETURNS jsonb LANGUAGE sql AS $m$ SELECT '{}'::jsonb $m$;\n"),
}
```

```bash
D=.superpowers/sdd/2026-11-07-spec2-w3; mkdir -p $D/mut
python3 -I $D/mutate.py supabase/migrations/20261107150000_dating_v2_client_reads.sql supabase/tests/dating_v2_client_reads_contracts.sql $D/mut_T3.py $D/mut supabase/migrations/20261107150010_dating_v2_client_reads_grants.sql | tee $D/mut_T3.txt
```

Expected (verified on a clone of `attune_spec3a`, fix round 1): 18 lines, none `NO ERROR (mutant survived)`. 17 die at a `CONTRACT VIOLATED` line, e.g. `home_active_ignores_candidate: … active with an undated ending reads {"state": "active"}`, `home_no_has_data: … has_data reads false / false / false / false …`, `request_no_lock: … the notice request does not take the publisher's lock (R-6)`, `owner_read_kept: … a client can still read public.dating_profiles` (a RAW mutant that puts the policy and grant back, I-7), `push_key_fallback: … with no push key the publish reads …`, `request_unlimited: … the 21st request in a day reads {"ok": true}`. `request_unvalidated` dies at the table's own CHECK (`violates check constraint "dating_notify_requests_country_code_check"`): an unvalidated country reaches a raw error, which is the failure the pre-validation prevents (M-3). Note each mutant's line in the report.

- [ ] **Step 8: The race cases (notice vs publish, both orders)**

Create `$D/edit_races_T3.py` with exactly:

```python
import sys
sys.path.insert(0, '.superpowers/sdd/2026-11-07-spec2-w3')
from anchor import edit
CASES = r'''
# Spec 2 W3a (R-6): "Tell me when it's here" vs the publish that opens it.
# The request takes the publisher's advisory lock, so whichever lands first,
# no request is left behind for a place that is open, and a request made
# first is told.
FX_NOTICE="SELECT race.reset(); DELETE FROM public.scheduled_notifications WHERE user_id::text LIKE '5e2f%';
SELECT public.publish_country_config('GH', '{\"open_regions\": [\"AA\", \"AH\"]}') ->> 'ok';
SELECT race.person('05', 'GH', 'AA', 'woman', ARRAY['man']);"
NOTICE_LEFT="(SELECT count(*) FROM public.dating_notify_requests WHERE user_id = race.id('05'))"
NOTICE_TOLD="(SELECT count(*) FROM public.scheduled_notifications WHERE user_id = race.id('05') AND metadata ->> 'type' = 'me_update')"

run "a notice request behind the publish that opens its region" "$FX_NOTICE" \
  "SELECT pg_sleep(0.5); SELECT race.call(race.id('05'), 'SELECT public.request_dating_country_notice(''GH'', ''TV'')') ->> 'reason';" \
  "BEGIN; SELECT public.publish_country_config('GH', '{\"open_regions\": [\"AA\", \"AH\", \"TV\"]}') ->> 'ok'; SELECT pg_sleep(1.2); COMMIT;" \
  "SELECT CASE WHEN $NOTICE_LEFT = 0 THEN 'ok' ELSE 'a request was left for an open region' END;" serialised

run "the publish behind a notice request for its region" "$FX_NOTICE" \
  "BEGIN; SELECT race.call(race.id('05'), 'SELECT public.request_dating_country_notice(''GH'', ''TV'')') ->> 'ok'; SELECT pg_sleep(1.2); COMMIT;" \
  "SELECT pg_sleep(0.5); SELECT public.publish_country_config('GH', '{\"open_regions\": [\"AA\", \"AH\", \"TV\"]}') ->> 'notified';" \
  "SELECT CASE WHEN $NOTICE_LEFT = 0 AND $NOTICE_TOLD = 1 THEN 'ok' ELSE 'left ' || $NOTICE_LEFT || ', told ' || $NOTICE_TOLD END;" serialised
'''
edit('scripts/concurrency/dating_kill_switch_races.sh', [
    ('\n$P -c "SELECT race.reset();" > /dev/null 2>&1\nexit $fail\n',
     CASES + '\n$P -c "SELECT race.reset();" > /dev/null 2>&1\nexit $fail\n'),
], 'T3 races')
```

```bash
D=.superpowers/sdd/2026-11-07-spec2-w3
python3 -I $D/edit_races_T3.py
dropdb --if-exists w3_race; createdb w3_race
pg_dump -s attune_spec3a | psql -X -q -d w3_race > /dev/null
pg_dump -a -t public.metric_key_prefixes -t public.feature_flags -t public.country_safety_config -t private.dating_calling_codes attune_spec3a | psql -X -q -d w3_race > /dev/null
psql -X -q -d w3_race -c "ALTER DATABASE w3_race SET app.settings.dating_push_key = 'race-push-key'"
scripts/concurrency/dating_kill_switch_races.sh w3_race | tee $D/race_T3.txt | tail -4
dropdb w3_race
```

Expected: every line `PASS` (20 cases: W2's 18 and these two), the last two `PASS  a notice request behind the publish …` and `PASS  the publish behind a notice request …`. If setup refuses the schema-only copy for a missing seed table, add that table to the `pg_dump -a` line, re-run, and name it in the report (R-33). Race mutant: with `request_no_lock` applied to the scratch copy (`psql -d w3_race` the function with the lock line removed), the first case fails `a request was left for an open region`; record it.

- [ ] **Step 9: The push data carries the neutral route (R-7)**

Create `supabase/functions/process-scheduled-notifications/privacy_allowlist.test.ts` with exactly:

```ts
// Spec 2 W3a (§3.13, R-7): the push's data allowlist carries the neutral
// Dating push's only key, {"route": "me"}, and names nothing Dating.
const src = await Deno.readTextFile(new URL("./index.ts", import.meta.url));

Deno.test("privacySafeData keeps 'route' and no Dating-named key", () => {
  const start = src.indexOf("function privacySafeData");
  const end = src.indexOf("return Object.fromEntries", start);
  if (start < 0 || end < 0) throw new Error("privacySafeData not found");
  const list = src.slice(start, end);
  if (!/"route",/.test(list)) throw new Error("'route' is not in the allowlist");
  if (/"dating/i.test(list)) throw new Error("a Dating-named key is in the allowlist");
});
```

```bash
cd supabase/functions && deno test --allow-read process-scheduled-notifications/privacy_allowlist.test.ts 2>&1 | tail -1; cd ../..
python3 -I - <<'PY'
import sys; sys.path.insert(0, '.superpowers/sdd/2026-11-07-spec2-w3')
from anchor import edit
edit('supabase/functions/process-scheduled-notifications/index.ts', [
    ('    // Together event alarm deep link (Together spec §6.1).\n    "event_id",\n  ];',
     '    // Together event alarm deep link (Together spec §6.1).\n    "event_id",\n'
     '    // Spec 2 W3a (§3.13): the neutral Dating push\'s only data, {"route": "me"}.\n'
     '    "route",\n  ];'),
], 'T3 push allowlist')
PY
cd supabase/functions && deno test --allow-read process-scheduled-notifications/ 2>&1 | tail -1; cd ../..
```

Expected: first `FAILED | 0 passed | 1 failed` (`'route' is not in the allowlist`); then the edit line; then `ok | N passed | 0 failed` for the whole folder (its existing tests unchanged).

- [ ] **Step 10: The whole suite, then record the tree**

```bash
D=.superpowers/sdd/2026-11-07-spec2-w3
$D/suite.sh attune_spec3a > $D/sql-after-T3.txt; echo "$(grep -c '^PASS' $D/sql-after-T3.txt) PASS, $(grep -c '^FAIL' $D/sql-after-T3.txt) FAIL"
diff <(grep '^FAIL' $D/sql-baseline-1.txt) <(grep '^FAIL' $D/sql-after-T3.txt) && echo "no new FAIL"
```

Expected: `159 PASS, 14 FAIL`; `no new FAIL`. Do not commit; record the tree in the report.

### Task 4: `DatingSection` in Spec 1's slot, the §3.10 not-open screens, the Dating settings shell; the W3a gate (§3.1, §3.10, §3.12 (lock, notice), §3.15; carries 1, 3, 5, 8, 9, 13; R-5, R-16, R-29, R-30, R-36)

**Files:**
- Create: `lib/features/dating/data/dating_names.dart`, `lib/features/dating/setup/dating_list_names.dart` (regions and sides now; Task 5 adds faith), `lib/features/dating/section/dating_why_sheet.dart`, `lib/features/dating/section/dating_section.dart`, `lib/features/dating/not_open/dating_not_open_screen.dart`, `lib/features/dating/settings/dating_settings_screen.dart`
- Create: `test/features/dating/section/dating_section_test.dart` (+ goldens), `test/features/dating/not_open/dating_not_open_screen_test.dart` (+ goldens), `test/features/dating/settings/dating_settings_screen_test.dart`, `test/features/dating/no_disk_writes_test.dart`, `test/features/dating/setup/dating_region_names_test.dart`, `$D/{arb_fragment_T4.txt, write_slot_T4.py, edit_T4.py, mut_T4.py}`
- Modify: `lib/features/me/presentation/widgets/dating_slot.dart` (whole body; Spec 1's only Me file this spec touches), `lib/features/dating/routes/dating_routes.dart` (two routes), `test/features/me/dating_slot_test.dart` (rewritten for the new body), `test/architecture/text_scale_routes_test.dart` (two names), `test/features/dating/support/dating_shell.dart` (one helper), every Spec 1 test the new section changes (listed in Step 8), `lib/i10n/app_en.arb` + generated
- Goldens: new `test/features/dating/section/goldens/*`, `test/features/dating/not_open/goldens/*`; regenerated `test/features/me/goldens/me_dating_open.*`, `test/accessibility/w10/goldens/j4_more_ways.*` (the Me home on the Dating path now shows the section's card)

**Interfaces:**
- Consumes: Tasks 1–3 (`datingHomeProvider`, `datingAvailabilityProvider`, `DatingHome`, the notice RPCs, `datingUnlockedProvider`, `DatingPaths`, `datingRoute`); Spec 1's `switchPath`, `showSharedSpaceSheetAfterRefusal`, `setDatingLock`, `SpaceRow`, `PhoneCountryPickerSheet`, `BottomSheetUtils.showDocumentationBottomSheet`.
- Produces: `DatingSection()`; `DatingNotOpenScreen({String? country, String? region})`; `DatingSettingsScreen()` (a `// W3c (Task 12): §3.12's rows go here.` marker); `datingCountryName(AppLocalizations, String iso)`, `datingOpenList(AppLocalizations, DatingAvailability)`, `datingOpenRegionNames(AppLocalizations, DatingAvailability, String country)`; `String? datingListName(AppLocalizations, String key)`, `datingRegionName(AppLocalizations, String country, String code)`, `datingRegionList(AppLocalizations, String country, List<String> codes)`; `showDatingWhySheet(BuildContext, {required String country})`; test helper `datingHomeOnlyOverrides({FakeDatingHomeGateway? home, String account})`.

- [ ] **Step 1: The strings (spec copy verbatim; plan copy listed for the reviewers)**

Create `$D/arb_fragment_T4.txt` with exactly (the region and side names are W1b's `name_key`s, so every seeded key resolves; Task 5's test checks it):

```
  "dating_countryUk": "the United Kingdom",
  "@dating_countryUk": {"description": "The UK inside a Dating sentence (Spec 2 §3.10 copy names it in full)."},

  "dating_countryWithRegions": "{country} ({regions})",
  "@dating_countryWithRegions": {"description": "An open country with its open regions, e.g. Ghana (Greater Accra and Ashanti) (Spec 2 §3.2 D1 line 7, §3.10).", "placeholders": {"country": {"type": "String"}, "regions": {"type": "String"}}},

  "dating_sectionNotOpen": "Dating isn't open in {country} yet.",
  "@dating_sectionNotOpen": {"description": "Spec 2 §3.1 states feature_unavailable and country_closed.", "placeholders": {"country": {"type": "String"}}},

  "dating_sectionRegionOpenOnly": "Dating is open in {regions} for now.",
  "@dating_sectionRegionOpenOnly": {"description": "Spec 2 §3.1 state region_closed.", "placeholders": {"regions": {"type": "String"}}},

  "dating_tellMe": "Tell me when it's here",
  "@dating_tellMe": {"description": "Spec 2 §3.1, §3.10 primary."},

  "dating_tellMeRegion": "Tell me when it's open in {region}",
  "@dating_tellMeRegion": {"description": "Spec 2 §3.1, §3.10 region variant.", "placeholders": {"region": {"type": "String"}}},

  "dating_tellMeDone": "We'll let you know. You can turn this off in Settings.",
  "@dating_tellMeDone": {"description": "Spec 2 §3.10, after Tell me when it's here. Settings = Dating settings."},

  "dating_tellMeOff": "Turn this off",
  "@dating_tellMeOff": {"description": "Cancels Tell me when it's here (Spec 2 W3a). For the DV reviewer."},

  "dating_notOpenTitle": "Dating isn't open in {country} yet",
  "@dating_notOpenTitle": {"description": "Spec 2 §3.10 title.", "placeholders": {"country": {"type": "String"}}},

  "dating_notOpenBody": "Attune opens Dating one country at a time, so we can keep it safe and well looked after. It's open in {countries} now.",
  "@dating_notOpenBody": {"description": "Spec 2 §3.10 body; {countries} is built from get_dating_availability (R-36).", "placeholders": {"countries": {"type": "String"}}},

  "dating_notOpenRegionTitle": "Dating is open in {regions} for now",
  "@dating_notOpenRegionTitle": {"description": "Spec 2 §3.10 region variant title.", "placeholders": {"regions": {"type": "String"}}},

  "dating_notOpenRegionBody": "We're opening other regions as soon as we can look after them well.",
  "@dating_notOpenRegionBody": {"description": "Spec 2 §3.10 region variant body."},

  "dating_justForMe": "Use Attune just for me",
  "@dating_justForMe": {"description": "Spec 2 §3.10 secondary (Dating path only)."},

  "dating_sectionNotStarted": "Meet a few people a day. Only when it's mutual.",
  "@dating_sectionNotStarted": {"description": "Spec 2 §3.1 state not_started."},

  "dating_sectionFinish": "Finish setting up Dating",
  "@dating_sectionFinish": {"description": "Spec 2 §3.1 state setup_in_progress."},

  "dating_sectionFirstDrop": "Your first introductions arrive {date} at {time}.",
  "@dating_sectionFirstDrop": {"description": "Spec 2 §3.1 cool_off/ready, §3.2 D13.", "placeholders": {"date": {"type": "String"}, "time": {"type": "String"}}},

  "dating_sectionActive": "Dating is on. Your introductions will show here.",
  "@dating_sectionActive": {"description": "Spec 2 §3.1 active until W5b's Today (plan R-30). For the DV reviewer."},

  "dating_sectionPaused": "Dating is paused. Nobody new sees you.",
  "@dating_sectionPaused": {"description": "Spec 2 §3.1 state paused."},

  "dating_resume": "Resume",
  "@dating_resume": {"description": "Spec 2 §3.1 paused."},

  "dating_sectionPausedRelationship": "Dating is paused while you have a shared space on Attune.",
  "@dating_sectionPausedRelationship": {"description": "Paused by the relationship guard; resume isn't offered (plan, carry 9). For the DV reviewer."},

  "dating_sectionSameGenderNote": "Introductions between people of the same gender aren't available in {country} now. We've removed that choice from your profile.",
  "@dating_sectionSameGenderNote": {"description": "Spec 2 §2.4 kill-switch note (then Why?). For the LGBTQ+ reviewer.", "placeholders": {"country": {"type": "String"}}},

  "dating_why": "Why?",
  "@dating_why": {"description": "Spec 2 §2.4, §3.2 D5/D6 link to the static sheet."},

  "dating_whyBody": "In {country}, relationships between people of the same gender can carry legal risk, and people have been targeted through dating apps, including by people they know. Until we can protect people properly here, Attune only introduces men and women to each other. Nothing you choose here is stored unless you continue. We'll look at this again after legal advice and talking with local groups.",
  "@dating_whyBody": {"description": "Spec 2 §3.2 D5 Why? sheet (static; opening it calls nothing). For the LGBTQ+ reviewer.", "placeholders": {"country": {"type": "String"}}},

  "dating_close": "Close",
  "@dating_close": {"description": "Closes a Dating sheet."},

  "dating_chooseAgain": "Choose again",
  "@dating_chooseAgain": {"description": "After the same-gender kill switch: back to D5 (plan). For the LGBTQ+ reviewer."},

  "dating_sectionAway": "Dating is hidden while you're away.",
  "@dating_sectionAway": {"description": "Spec 2 §3.1 away."},

  "dating_sectionRestricted": "Your Dating account is restricted. The rest of Attune works as usual.",
  "@dating_sectionRestricted": {"description": "Spec 2 §3.1 restricted, before W7a's category and date (plan R-29). For the DV reviewer."},

  "dating_sectionHold": "Your Dating profile is paused while we look into something. This isn't a decision yet.",
  "@dating_sectionHold": {"description": "Spec 2 §3.1 hold, before W7a (plan R-29). For the DV reviewer."},

  "dating_sectionAgeReview": "We need to confirm your age before you can use Dating.",
  "@dating_sectionAgeReview": {"description": "Spec 2 §3.7 age check copy."},

  "dating_sectionUnavailable": "Dating isn't available on this account right now.",
  "@dating_sectionUnavailable": {"description": "Spec 2 home state unavailable (W2 owner decision 1)."},

  "dating_sectionLockedLabel": "Dating, locked",
  "@dating_sectionLockedLabel": {"description": "Spec 2 §3.15: the locked section's semantic label."},

  "dating_settingsTitle": "Dating settings",
  "@dating_settingsTitle": {"description": "Spec 2 §3.12."},

  "dating_settingsNotice": "Tell me when Dating opens",
  "@dating_settingsNotice": {"description": "Dating settings row while a Tell me request exists (plan). For the DV reviewer."},

  "dating_settingsClearReflection": "Clear my answers to the three questions",
  "@dating_settingsClearReflection": {"description": "Dating settings: the gentle-wait reflection's clear, reachable in any state (W2 carry 5). For the DV reviewer."},

  "dating_errorPathNotDating": "Choose Dating in How you use Attune to carry on.",
  "@dating_errorPathNotDating": {"description": "A resume or activation refused with path_not_dating (W2 carry 1)."},

  "dating_openHowYouUse": "How you use Attune",
  "@dating_openHowYouUse": {"description": "Link to Spec 1's How you use Attune."},

  "dating_errorResumeGates": "Dating can't resume on this account right now.",
  "@dating_errorResumeGates": {"description": "Resume refused (resume_gates_not_met)."},

  "dating_errorConsent": "Agree to Dating's terms again to carry on.",
  "@dating_errorConsent": {"description": "A lifecycle call refused for consent (back to D4)."},

  "dating_errorIncomplete": "Finish setting up Dating first.",
  "@dating_errorIncomplete": {"description": "A lifecycle call refused: profile incomplete."},

  "dating_errorRateLimited": "You've done this a lot today. Try again tomorrow.",
  "@dating_errorRateLimited": {"description": "Spec 2 §3.0 rate limit."},

  "dating_region_gh_af": "Ahafo", "dating_region_gh_ah": "Ashanti", "dating_region_gh_bo": "Bono", "dating_region_gh_be": "Bono East",
  "dating_region_gh_cp": "Central", "dating_region_gh_ep": "Eastern", "dating_region_gh_aa": "Greater Accra", "dating_region_gh_ne": "North East",
  "dating_region_gh_np": "Northern", "dating_region_gh_ot": "Oti", "dating_region_gh_sv": "Savannah", "dating_region_gh_ue": "Upper East",
  "dating_region_gh_uw": "Upper West", "dating_region_gh_tv": "Volta", "dating_region_gh_wp": "Western", "dating_region_gh_wn": "Western North",
  "dating_side_gh_accra": "Accra", "dating_side_gh_tema": "Tema and Ashaiman", "dating_side_gh_kumasi": "Kumasi", "dating_side_gh_outside_kumasi": "Outside Kumasi",
  "dating_region_gb_tlc": "North East", "dating_region_gb_tld": "North West", "dating_region_gb_tle": "Yorkshire and the Humber", "dating_region_gb_tlf": "East Midlands",
  "dating_region_gb_tlg": "West Midlands", "dating_region_gb_tlh": "East of England", "dating_region_gb_tli": "London", "dating_region_gb_tlj": "South East",
  "dating_region_gb_tlk": "South West", "dating_region_gb_tll": "Wales", "dating_region_gb_tlm": "Scotland", "dating_region_gb_tln": "Northern Ireland"
```

```bash
D=.superpowers/sdd/2026-11-07-spec2-w3
python3 -I .superpowers/sdd/2026-10-26-spec1-w3/arb_append.py $D/arb_fragment_T4.txt
flutter gen-l10n --arb-dir=lib/i10n --template-arb-file=app_en.arb --output-dir=lib/i10n/generated --output-localization-file=app_localizations.dart --no-synthetic-package
```

Expected: `added 72 keys`; gen-l10n prints nothing (or only the untranslated-messages note it already prints). The region names are reviewer content (W3 gate: the cultural reviewer signs the region and side lists).

- [ ] **Step 2: Write the failing tests**

Add to `test/features/dating/support/dating_shell.dart` (appended at the end of the file, below `datingShellOverrides`; this file is not formatted again):

```dart
/// The Dating section's overrides for a Spec 1 test that renders Me on the
/// Dating path (W3a: the slot's body is DatingSection).
List<Override> datingHomeOnlyOverrides({
  FakeDatingHomeGateway? home,
  String account = 'u-test',
}) => [
  datingAccountProvider.overrideWithValue(account),
  datingHomeGatewayProvider.overrideWithValue(home ?? FakeDatingHomeGateway()),
  datingLifecycleGatewayProvider.overrideWithValue(FakeDatingLifecycleGateway()),
  datingLockStoreProvider.overrideWithValue(FakeLock(false)),
  datingLockAccountProvider.overrideWith((ref) => Stream.value(account)),
  datingOnlineProvider.overrideWith((ref) => Stream.value(true)),
];
```

Create `test/features/dating/section/dating_section_test.dart` with exactly:

```dart
// Spec 2 W3a (§3.1, §3.15; carries 1, 3, 8, 9, 13; D8): every home state
// has its card; resume's refusals have their own words; nothing of one
// account reaches the next.
import 'dart:async';

import 'package:attune/features/dating/data/dating_home.dart';
import 'package:attune/features/dating/data/dating_lifecycle_repository.dart';
import 'package:attune/features/dating/data/dating_providers.dart';
import 'package:attune/features/dating/data/dating_rpc.dart';
import 'package:attune/features/dating/section/dating_section.dart';
import 'package:attune/features/onboarding/data/home_state_service.dart';
import 'package:attune/home/home_seams.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/fake_home_state.dart';
import '../../../helpers/flow_harness.dart';
import '../../../helpers/home_harness.dart';
import '../../../helpers/tap_in_reach.dart';
import '../support/dating_fakes.dart';
import '../support/dating_shell.dart';

Widget _screen() => const Scaffold(
  body: SingleChildScrollView(
    padding: EdgeInsets.all(16),
    child: DatingSection(),
  ),
);

class _Pumped {
  _Pumped(this.harness, this.home, this.life, this.spec1);
  final FlowHarness harness;
  final FakeDatingHomeGateway home;
  final FakeDatingLifecycleGateway life;
  final FakeHomeStateGateway spec1;
}

Future<_Pumped> _pump(
  WidgetTester t,
  DatingHome state, {
  bool online = true,
}) async {
  await t.pumpWidget(const SizedBox());
  final home = FakeDatingHomeGateway(home: state);
  final life = FakeDatingLifecycleGateway();
  final spec1 = FakeHomeStateGateway(state: homeJson(path: 'dating'));
  final h = await pumpFlowScreen(
    t,
    _screen,
    overrides: [
      ...datingShellOverrides(home: home, life: life, online: online),
      homeAuthProvider.overrideWithValue(FakeHomeAuth(testUser('ama'))),
      homeStateServiceProvider.overrideWithValue(HomeStateService(spec1)),
    ],
  );
  return _Pumped(h, home, life, spec1);
}

void main() {
  final cases = <String, (DatingHome, List<String>)>{
    'feature_unavailable': (
      const DatingHome(
        state: DatingHomeState.featureUnavailable,
        country: 'NG',
        notice: DatingNotice(available: true),
      ),
      ["Dating isn't open in Nigeria yet.", "Tell me when it's here"],
    ),
    'country_closed, already asked': (
      const DatingHome(
        state: DatingHomeState.countryClosed,
        country: 'NG',
        notice: DatingNotice(available: true, requested: true),
      ),
      [
        "We'll let you know. You can turn this off in Settings.",
        'Dating settings',
      ],
    ),
    'region_closed': (
      const DatingHome(
        state: DatingHomeState.regionClosed,
        country: 'GH',
        region: 'TV',
        openRegions: ['AA', 'AH'],
        notice: DatingNotice(available: true),
      ),
      [
        'Dating is open in Greater Accra and Ashanti for now.',
        "Tell me when it's open in Volta",
      ],
    ),
    'not_started': (
      const DatingHome(state: DatingHomeState.notStarted),
      [
        "Meet a few people a day. Only when it's mutual.",
        'Set up Dating',
        'Not ready? Use Attune just for me',
      ],
    ),
    'setup_in_progress': (
      const DatingHome(
        state: DatingHomeState.setupInProgress,
        nextStep: 'where',
      ),
      ['Finish setting up Dating', 'Dating settings'],
    ),
    'active': (
      const DatingHome(state: DatingHomeState.active),
      ['Dating is on. Your introductions will show here.'],
    ),
    'reverify_device': (
      const DatingHome(state: DatingHomeState.reverifyDevice),
      ["Confirm it's you on this phone to see Dating."],
    ),
    'restricted': (
      const DatingHome(state: DatingHomeState.restricted),
      ['Your Dating account is restricted. The rest of Attune works as usual.'],
    ),
    'hold': (
      const DatingHome(state: DatingHomeState.hold),
      [
        "Your Dating profile is paused while we look into something. This "
            "isn't a decision yet.",
      ],
    ),
    'age_review': (
      const DatingHome(state: DatingHomeState.ageReview),
      ['We need to confirm your age before you can use Dating.'],
    ),
    'unavailable': (
      const DatingHome(state: DatingHomeState.unavailable),
      ["Dating isn't available on this account right now."],
    ),
    'paused, no reason (carry 9)': (
      const DatingHome(state: DatingHomeState.paused),
      ['Dating is paused. Nobody new sees you.', 'Resume'],
    ),
    'paused by a shared space': (
      const DatingHome(
        state: DatingHomeState.paused,
        pauseReason: DatingPauseReason.relationship,
      ),
      ['Dating is paused while you have a shared space on Attune.'],
    ),
    'paused by the country switch': (
      const DatingHome(
        state: DatingHomeState.paused,
        pauseReason: DatingPauseReason.sameGenderSwitch,
        country: 'GH',
      ),
      [
        "Introductions between people of the same gender aren't available in "
            "Ghana now. We've removed that choice from your profile.",
        'Why?',
        'Choose again',
      ],
    ),
  };
  for (final MapEntry(key: name, value: (home, texts)) in cases.entries) {
    testWidgets('$name: its card', (t) async {
      await _pump(t, home);
      for (final text in texts) {
        expect(find.text(text), findsOneWidget, reason: text);
      }
    });
  }

  // C-2: whenever there is Dating data, every card links to Dating
  // settings (Leave, Clear), restricted, held and unavailable included.
  for (final state in DatingHomeState.values) {
    testWidgets('C-2: ${state.wire} with Dating data links to settings', (
      t,
    ) async {
      await _pump(
        t,
        DatingHome(state: state, hasData: true, country: 'NG', region: 'TV'),
      );
      await tapInReach(t, find.text('Dating settings'));
      await t.pumpAndSettle();
      expect(find.text('at /dating/settings'), findsOneWidget);
    });
  }

  testWidgets('C-2: no Dating data, no settings link', (t) async {
    await _pump(t, const DatingHome(state: DatingHomeState.notStarted));
    expect(find.text('Dating settings'), findsNothing);
    await _pump(t, const DatingHome(state: DatingHomeState.restricted));
    expect(find.text('Dating settings'), findsNothing);
  });

  testWidgets('a shared-space pause offers no Resume', (t) async {
    await _pump(
      t,
      const DatingHome(
        state: DatingHomeState.paused,
        pauseReason: DatingPauseReason.relationship,
      ),
    );
    expect(find.text('Resume'), findsNothing);
  });

  testWidgets('cool-off: the first drop in full words, local time', (t) async {
    final at = DateTime.utc(2026, 11, 12, 19);
    await _pump(t, DatingHome(state: DatingHomeState.coolOff, firstDropAt: at));
    expect(
      find.textContaining('Your first introductions arrive '),
      findsOneWidget,
    );
    expect(find.textContaining(' at '), findsOneWidget);
  });

  testWidgets('carry 3: a wait both partners ended is no wait here', (t) async {
    await _pump(t, const DatingHome(state: DatingHomeState.notStarted));
    expect(find.textContaining('Dating opens for you on'), findsNothing);
  });

  testWidgets('carry 8: the wait card never promises a shorter wait', (
    t,
  ) async {
    await _pump(
      t,
      DatingHome(
        state: DatingHomeState.gentleWait,
        opensAt: DateTime.utc(2026, 12, 1, 10),
        canShorten: true,
      ),
    );
    expect(find.textContaining('Dating opens for you on'), findsOneWidget);
    expect(find.textContaining('sooner'), findsNothing);
    await tapInReach(t, find.text('Before you begin'));
    await t.pumpAndSettle();
    expect(find.text('at /dating/setup/wait'), findsOneWidget);
  });

  testWidgets('Set up Dating opens D1; Finish opens the saved step', (t) async {
    await _pump(t, const DatingHome(state: DatingHomeState.notStarted));
    await tapInReach(t, find.text('Set up Dating'));
    await t.pumpAndSettle();
    expect(find.text('at /dating/setup/how'), findsOneWidget);
    await _pump(
      t,
      const DatingHome(
        state: DatingHomeState.setupInProgress,
        nextStep: 'faith',
      ),
    );
    await tapInReach(t, find.text('Finish setting up Dating'));
    await t.pumpAndSettle();
    expect(find.text('at /dating/setup/faith'), findsOneWidget);
  });

  testWidgets('Tell me when it\'s here asks once, then says so', (t) async {
    final p = await _pump(
      t,
      const DatingHome(
        state: DatingHomeState.countryClosed,
        country: 'NG',
        notice: DatingNotice(available: true),
      ),
    );
    await tapInReach(t, find.text("Tell me when it's here"));
    await t.pumpAndSettle();
    expect(p.home.requests, [('NG', null)]);
    expect(
      find.text("We'll let you know. You can turn this off in Settings."),
      findsOneWidget,
    );
  });

  testWidgets('R-5: Dating off where the country is open: no Tell me', (
    t,
  ) async {
    await _pump(
      t,
      const DatingHome(
        state: DatingHomeState.featureUnavailable,
        country: 'GH',
        notice: DatingNotice(available: false),
      ),
    );
    expect(find.text("Tell me when it's here"), findsNothing);
  });

  testWidgets('a region: the request names it', (t) async {
    final p = await _pump(
      t,
      const DatingHome(
        state: DatingHomeState.regionClosed,
        country: 'GH',
        region: 'TV',
        openRegions: ['AA', 'AH'],
        notice: DatingNotice(available: true),
      ),
    );
    await tapInReach(t, find.text("Tell me when it's open in Volta"));
    await t.pumpAndSettle();
    expect(p.home.requests, [('GH', 'TV')]);
  });

  testWidgets('Resume: one call, one key, then the home again', (t) async {
    final p = await _pump(t, const DatingHome(state: DatingHomeState.paused));
    final reads = p.home.reads;
    p.home.home = const DatingHome(state: DatingHomeState.active);
    await tapInReach(t, find.text('Resume'));
    await t.pumpAndSettle();
    expect(p.life.calls, ['resume']);
    expect(p.home.reads, reads + 1);
    expect(
      find.text('Dating is on. Your introductions will show here.'),
      findsOneWidget,
    );
  });

  for (final (error, text) in [
    (
      DatingLifecycleError.pathNotDating,
      'Choose Dating in How you use Attune to carry on.',
    ),
    (
      DatingLifecycleError.resumeGatesNotMet,
      "Dating can't resume on this account right now.",
    ),
    (
      DatingLifecycleError.consentRequired,
      "Agree to Dating's terms again to carry on.",
    ),
    (DatingLifecycleError.profileIncomplete, 'Finish setting up Dating first.'),
    (
      DatingLifecycleError.busy,
      'This is taking a little longer than usual. Try again in a moment.',
    ),
  ]) {
    testWidgets('Resume refused (${error.name}): its own words', (t) async {
      final p = await _pump(t, const DatingHome(state: DatingHomeState.paused));
      p.life.result = DatingLifecycleResult.refused(error);
      await tapInReach(t, find.text('Resume'));
      await t.pumpAndSettle();
      expect(find.text(text), findsOneWidget);
      expect(find.text('Something went wrong. Try again.'), findsNothing);
    });
  }

  testWidgets('pathNotDating links to How you use Attune', (t) async {
    final p = await _pump(t, const DatingHome(state: DatingHomeState.paused));
    p.life.result = const DatingLifecycleResult.refused(
      DatingLifecycleError.pathNotDating,
    );
    await tapInReach(t, find.text('Resume'));
    await t.pumpAndSettle();
    await tapInReach(t, find.text('How you use Attune'));
    await t.pumpAndSettle();
    expect(find.text('at /settings/how-you-use-attune'), findsOneWidget);
  });

  testWidgets(
    'the kill-switch note: Why? calls nothing; Choose again opens D5',
    (t) async {
      final p = await _pump(
        t,
        const DatingHome(
          state: DatingHomeState.paused,
          pauseReason: DatingPauseReason.sameGenderSwitch,
          country: 'GH',
        ),
      );
      final reads = p.home.reads;
      await tapInReach(t, find.text('Why?'));
      await t.pumpAndSettle();
      expect(
        find.textContaining('In Ghana, relationships between people'),
        findsOneWidget,
      );
      expect(p.home.reads, reads);
      expect(p.life.calls, isEmpty);
      await tapInReach(t, find.text('Close'));
      await t.pumpAndSettle();
      await tapInReach(t, find.text('Choose again'));
      await t.pumpAndSettle();
      expect(find.text('at /dating/setup/you'), findsOneWidget);
    },
  );

  testWidgets('"Not ready?" is one tap to Just for me', (t) async {
    final p = await _pump(
      t,
      const DatingHome(state: DatingHomeState.notStarted),
    );
    await tapInReach(t, find.text('Not ready? Use Attune just for me'));
    await t.pumpAndSettle();
    expect(p.spec1.count('set_my_path'), 1);
  });

  testWidgets('a failed refresh never shows the last state', (t) async {
    final p = await _pump(t, const DatingHome(state: DatingHomeState.active));
    expect(
      find.text('Dating is on. Your introductions will show here.'),
      findsOneWidget,
    );
    p.home.readError = Exception('down');
    ProviderScope.containerOf(
      t.element(find.byType(DatingSection)),
    ).invalidate(datingHomeProvider);
    await t.pumpAndSettle();
    expect(find.text('Something went wrong. Try again.'), findsOneWidget);
    expect(
      find.text('Dating is on. Your introductions will show here.'),
      findsNothing,
    );
  });

  testWidgets('D8: a Resume refusal for one account is not shown to the '
      'next', (t) async {
    final p = await _pump(t, const DatingHome(state: DatingHomeState.paused));
    p.life.result = const DatingLifecycleResult.refused(
      DatingLifecycleError.rateLimited,
    );
    await tapInReach(t, find.text('Resume'));
    await t.pumpAndSettle();
    const refusal = "You've done this a lot today. Try again tomorrow.";
    expect(find.text(refusal), findsOneWidget);
    ProviderScope.containerOf(t.element(find.byType(DatingSection)))
        .read(datingTestAccount.notifier)
        .state = 'kofi';
    await t.pumpAndSettle();
    expect(find.text('Resume'), findsOneWidget);
    expect(find.text(refusal), findsNothing);
  });

  testWidgets('a failed read: the error and Retry; offline: says so', (
    t,
  ) async {
    await t.pumpWidget(const SizedBox());
    final home = FakeDatingHomeGateway()..readError = Exception('down');
    await pumpFlowScreen(
      t,
      _screen,
      overrides: datingShellOverrides(home: home),
    );
    expect(find.text('Something went wrong. Try again.'), findsOneWidget);
    home.readError = null;
    await tapInReach(t, find.text('Retry'));
    await t.pumpAndSettle();
    expect(find.text('Set up Dating'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    final off = FakeDatingHomeGateway()..readError = Exception('offline');
    await pumpFlowScreen(
      t,
      _screen,
      overrides: datingShellOverrides(home: off, online: false),
    );
    expect(
      find.text("You're offline. Dating needs a connection."),
      findsOneWidget,
    );
  });

  testWidgets('D8: the next account sees nothing of the last one, also while '
      'its read is held', (t) async {
    final p = await _pump(t, const DatingHome(state: DatingHomeState.active));
    expect(
      find.text('Dating is on. Your introductions will show here.'),
      findsOneWidget,
    );
    p.home.hold = Completer<DatingHome>();
    ProviderScope.containerOf(t.element(find.byType(DatingSection)))
        .read(datingTestAccount.notifier)
        .state = 'kofi';
    for (var i = 0; i < 5; i++) {
      await t.pump(const Duration(milliseconds: 40));
      expect(
        find.text('Dating is on. Your introductions will show here.'),
        findsNothing,
      );
    }
    p.home.hold!.complete(const DatingHome(state: DatingHomeState.notStarted));
    await t.pumpAndSettle();
    expect(find.text('Set up Dating'), findsOneWidget);
  });

  testWidgets('a semantic region "Dating"; guidelines', (t) async {
    final semantics = t.ensureSemantics();
    await _pump(t, const DatingHome(state: DatingHomeState.notStarted));
    expect(find.bySemanticsLabel('Dating'), findsWidgets);
    await expectFlowGuidelines(t);
    semantics.dispose();
  });

  for (final (name, home) in [
    (
      'section_not_started',
      const DatingHome(state: DatingHomeState.notStarted),
    ),
    (
      'section_region_closed',
      const DatingHome(
        state: DatingHomeState.regionClosed,
        country: 'GH',
        region: 'TV',
        openRegions: ['AA', 'AH'],
        notice: DatingNotice(available: true),
      ),
    ),
    ('section_paused', const DatingHome(state: DatingHomeState.paused)),
  ]) {
    testWidgets('$name goldens', (t) async {
      await expectFlowGoldens(
        t,
        name,
        _screen,
        overrides: [
          ...datingShellOverrides(home: FakeDatingHomeGateway(home: home)),
          homeAuthProvider.overrideWithValue(FakeHomeAuth(testUser('ama'))),
          homeStateServiceProvider.overrideWithValue(
            HomeStateService(
              FakeHomeStateGateway(state: homeJson(path: 'dating')),
            ),
          ),
        ],
      );
    });
  }
}
```

(`RouteNames.howYouUseAttune` is `/how-you-use-attune`; if the constant differs, assert on its value instead: `find.text('at ${RouteNames.howYouUseAttune}')`.)

Create `test/features/dating/not_open/dating_not_open_screen_test.dart` with exactly:

```dart
// Spec 2 W3a (§3.10; R-36): the not-open screens, built from the open
// countries; Tell me once; Turn this off; offline disabled; no animation.
import 'package:attune/features/dating/data/dating_home_repository.dart';
import 'package:attune/features/dating/not_open/dating_not_open_screen.dart';
import 'package:attune/features/onboarding/data/home_state_service.dart';
import 'package:attune/features/onboarding/presentation/providers/home_state_providers.dart';
import 'package:attune/home/home_seams.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/fake_home_state.dart';
import '../../../helpers/flow_harness.dart';
import '../../../helpers/home_harness.dart';
import '../../../helpers/tap_in_reach.dart';
import '../support/dating_fakes.dart';
import '../support/dating_shell.dart';

List<Override> _overrides(
  FakeDatingHomeGateway home, {
  bool online = true,
  FakeHomeStateGateway? spec1,
}) => [
  ...datingShellOverrides(home: home, online: online),
  homeAuthProvider.overrideWithValue(FakeHomeAuth(testUser('ama'))),
  homeStateServiceProvider.overrideWithValue(
    HomeStateService(
      spec1 ?? FakeHomeStateGateway(state: homeJson(path: 'dating')),
    ),
  ),
];

void main() {
  testWidgets('a closed country: the open list is built, never hard-coded', (
    t,
  ) async {
    await pumpFlowScreen(
      t,
      () => const DatingNotOpenScreen(country: 'NG'),
      overrides: _overrides(FakeDatingHomeGateway()),
    );
    expect(find.text("Dating isn't open in Nigeria yet"), findsOneWidget);
    expect(
      find.text(
        'Attune opens Dating one country at a time, so we can keep it safe '
        "and well looked after. It's open in the United Kingdom and Ghana "
        '(Greater Accra and Ashanti) now.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('Tell me, then Turn this off', (t) async {
    final home = FakeDatingHomeGateway();
    await pumpFlowScreen(
      t,
      () => const DatingNotOpenScreen(country: 'NG'),
      overrides: _overrides(home),
    );
    await tapInReach(t, find.text("Tell me when it's here"));
    await t.pumpAndSettle();
    expect(home.requests, [('NG', null)]);
    expect(
      find.text("We'll let you know. You can turn this off in Settings."),
      findsOneWidget,
    );
    await tapInReach(t, find.text('Turn this off'));
    await t.pumpAndSettle();
    expect(home.cancels, 1);
    expect(find.text("Tell me when it's here"), findsOneWidget);
  });

  testWidgets('the region variant', (t) async {
    final home = FakeDatingHomeGateway();
    await pumpFlowScreen(
      t,
      () => const DatingNotOpenScreen(country: 'GH', region: 'TV'),
      overrides: _overrides(home),
    );
    expect(
      find.text('Dating is open in Greater Accra and Ashanti for now'),
      findsOneWidget,
    );
    expect(
      find.text(
        "We're opening other regions as soon as we can look after them well.",
      ),
      findsOneWidget,
    );
    await tapInReach(t, find.text("Tell me when it's open in Volta"));
    await t.pumpAndSettle();
    expect(home.requests, [('GH', 'TV')]);
  });

  testWidgets('offline: Tell me is disabled', (t) async {
    final home = FakeDatingHomeGateway();
    await pumpFlowScreen(
      t,
      () => const DatingNotOpenScreen(country: 'NG'),
      overrides: _overrides(home, online: false),
    );
    await tapInReach(t, find.text("Tell me when it's here"));
    await t.pumpAndSettle();
    expect(home.requests, isEmpty);
    expect(
      find.text("You're offline. Dating needs a connection."),
      findsOneWidget,
    );
  });

  testWidgets('an answer the server refuses is said calmly', (t) async {
    final home =
        FakeDatingHomeGateway()..noticeResult = DatingNoticeResult.busy;
    await pumpFlowScreen(
      t,
      () => const DatingNotOpenScreen(country: 'NG'),
      overrides: _overrides(home),
    );
    await tapInReach(t, find.text("Tell me when it's here"));
    await t.pumpAndSettle();
    expect(
      find.text(
        'This is taking a little longer than usual. Try again in a moment.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('no country known: choose one first (kept in memory only)', (
    t,
  ) async {
    final h = await pumpFlowScreen(
      t,
      () => const DatingNotOpenScreen(),
      overrides: _overrides(FakeDatingHomeGateway()),
    );
    expect(find.text("Dating isn't open yet"), findsOneWidget);
    expect(find.text('Choose your country'), findsOneWidget);
    expect(h.prefs.getKeys(), isEmpty);
  });

  testWidgets('"Use Attune just for me" switches in one tap', (t) async {
    final spec1 = FakeHomeStateGateway(state: homeJson(path: 'dating'));
    await pumpFlowScreen(
      t,
      () => const DatingNotOpenScreen(country: 'NG'),
      overrides: _overrides(FakeDatingHomeGateway(), spec1: spec1),
    );
    // The path is Spec 1's home state, which Me's shell reads; read it here.
    await ProviderScope.containerOf(
      t.element(find.byType(DatingNotOpenScreen)),
    ).read(homeStateProvider('ama').notifier).refresh();
    await t.pumpAndSettle();
    await tapInReach(t, find.text('Use Attune just for me'));
    await t.pumpAndSettle();
    expect(spec1.count('set_my_path'), 1);
  });

  testWidgets('guidelines', (t) async {
    final semantics = t.ensureSemantics();
    await pumpFlowScreen(
      t,
      () => const DatingNotOpenScreen(country: 'NG'),
      overrides: _overrides(FakeDatingHomeGateway()),
    );
    await expectFlowGuidelines(t);
    semantics.dispose();
  });

  for (final (name, country, region) in [
    ('not_open_country', 'NG', null),
    ('not_open_region', 'GH', 'TV'),
  ]) {
    testWidgets('$name goldens', (t) async {
      await expectFlowGoldens(
        t,
        name,
        () => DatingNotOpenScreen(country: country, region: region),
        overrides: _overrides(FakeDatingHomeGateway()),
      );
    });
  }
}
```

Create `test/features/dating/settings/dating_settings_screen_test.dart` with exactly:

```dart
// Spec 2 W3a (§3.12 lock row; carry 5): the settings shell: the Dating lock
// (Spec 1's setting), the notice while asked for, and the reflection's clear
// in every home state.
import 'package:attune/features/dating/data/dating_home.dart';
import 'package:attune/features/dating/gentle_wait/gentle_wait_repository.dart';
import 'package:attune/features/dating/settings/dating_settings_screen.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/flow_harness.dart';
import '../../../helpers/tap_in_reach.dart';
import '../support/dating_fakes.dart';
import '../support/dating_shell.dart';

void main() {
  for (final state in DatingHomeState.values) {
    testWidgets('carry 5: the clear is there when the home is ${state.wire}', (
      t,
    ) async {
      final wait = FakeWait();
      await pumpFlowScreen(
        t,
        () => const DatingSettingsScreen(),
        overrides: datingShellOverrides(
          home: FakeDatingHomeGateway(home: DatingHome(state: state)),
          wait: wait,
        ),
      );
      await tapInReach(t, find.text('Clear my answers to the three questions'));
      await t.pumpAndSettle();
      expect(wait.clears, 1);
      expect(wait.saves, isEmpty);
      expect(find.text('Your answers are cleared.'), findsOneWidget);
    });
  }

  testWidgets('a busy clear says so calmly', (t) async {
    final wait = FakeWait()..result = GentleWaitSave.busy;
    await pumpFlowScreen(
      t,
      () => const DatingSettingsScreen(),
      overrides: datingShellOverrides(wait: wait),
    );
    await tapInReach(t, find.text('Clear my answers to the three questions'));
    await t.pumpAndSettle();
    expect(
      find.text(
        'This is taking a little longer than usual. Try clearing again in a moment.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('the notice row shows while asked for; off cancels it', (
    t,
  ) async {
    final home = FakeDatingHomeGateway(
      home: const DatingHome(
        state: DatingHomeState.countryClosed,
        country: 'NG',
        notice: DatingNotice(available: true, requested: true),
      ),
    );
    await pumpFlowScreen(
      t,
      () => const DatingSettingsScreen(),
      overrides: datingShellOverrides(home: home),
    );
    await tapInReach(t, find.text('Tell me when Dating opens'));
    await t.pumpAndSettle();
    expect(home.cancels, 1);
  });

  testWidgets('the Dating lock row is Spec 1\'s setting', (t) async {
    await pumpFlowScreen(
      t,
      () => const DatingSettingsScreen(),
      overrides: datingShellOverrides(),
    );
    expect(find.text('Dating lock'), findsOneWidget);
    expect(
      find.text('Ask for your Safety PIN before showing Dating.'),
      findsOneWidget,
    );
    await expectFlowGuidelines(t);
  });
}
```

Create `test/features/dating/no_disk_writes_test.dart` with exactly:

```dart
// Spec 2 §3.0, §7.2 S19 (C-5, D20): using the Dating section, the not-open
// screen and Dating settings writes nothing to SharedPreferences and nothing
// to the secure store but Spec 1's own me_section_lock.
import 'package:attune/features/dating/data/dating_home.dart';
import 'package:attune/features/dating/not_open/dating_not_open_screen.dart';
import 'package:attune/features/dating/section/dating_section.dart';
import 'package:attune/features/dating/settings/dating_settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/flow_harness.dart';
import '../../helpers/tap_in_reach.dart';
import 'support/dating_fakes.dart';
import 'support/dating_shell.dart';

Future<void> _expectNothingWritten() async {
  final prefs = await SharedPreferences.getInstance();
  for (final key in prefs.getKeys()) {
    expect(key.toLowerCase(), isNot(contains('dating')), reason: key);
    expect(
      '${prefs.get(key)}'.toLowerCase(),
      isNot(contains('dating')),
      reason: key,
    );
  }
  final secure = await const FlutterSecureStorage().readAll();
  expect(secure.keys.toSet().difference({'me_section_lock'}), isEmpty);
}

void main() {
  testWidgets('the section, the not-open screen and settings write nothing', (
    t,
  ) async {
    final home = FakeDatingHomeGateway(
      home: const DatingHome(
        state: DatingHomeState.countryClosed,
        country: 'NG',
        notice: DatingNotice(available: true),
      ),
    );
    await pumpFlowScreen(
      t,
      () => const Scaffold(body: SingleChildScrollView(child: DatingSection())),
      overrides: datingShellOverrides(home: home),
    );
    await tapInReach(t, find.text("Tell me when it's here"));
    await t.pumpAndSettle();
    await _expectNothingWritten();
    await t.pumpWidget(const SizedBox());
    await pumpFlowScreen(
      t,
      () => const DatingNotOpenScreen(country: 'NG'),
      overrides: datingShellOverrides(home: home),
    );
    await _expectNothingWritten();
    await t.pumpWidget(const SizedBox());
    await pumpFlowScreen(
      t,
      () => const DatingSettingsScreen(),
      overrides: datingShellOverrides(home: home),
    );
    await tapInReach(t, find.text('Clear my answers to the three questions'));
    await t.pumpAndSettle();
    await _expectNothingWritten();
  });
}
```

Create `test/features/dating/setup/dating_region_names_test.dart` with exactly:

```dart
// Spec 2 W3a: every region and side the country config can send has a name
// in the app (W1b's name_key values); an unknown code reads as itself.
import 'dart:io';

import 'package:attune/features/dating/setup/dating_list_names.dart';
import 'package:attune/i10n/generated/app_localizations_en.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final loc = AppLocalizationsEn();
  test('every seeded region and side key resolves', () {
    final seed =
        File(
          'supabase/migrations/20261106130000_dating_v2_country_config.sql',
        ).readAsStringSync();
    final keys =
        RegExp(
          r'"name_key": "(dating_(?:region|side)_[a-z_]+)"',
        ).allMatches(seed).map((m) => m.group(1)!).toSet();
    expect(keys.length, 32);
    for (final key in keys) {
      expect(datingListName(loc, key), isNotNull, reason: key);
    }
  });

  test('by code: Ghana and the UK; an unknown code reads as its code', () {
    expect(datingRegionName(loc, 'GH', 'AA'), 'Greater Accra');
    expect(datingRegionName(loc, 'gb', 'tli'), 'London');
    expect(datingRegionName(loc, 'GH', 'ZZ'), 'ZZ');
    expect(
      datingRegionList(loc, 'GH', ['AA', 'AH']),
      'Greater Accra and Ashanti',
    );
  });
}
```

Run: `flutter test test/features/dating/section test/features/dating/not_open test/features/dating/settings test/features/dating/no_disk_writes_test.dart test/features/dating/setup/dating_region_names_test.dart 2>&1 | tail -2`
Expected: FAIL — `Target of URI doesn't exist` for the four new screen files and `dating_list_names.dart`.

- [ ] **Step 3: Names, the Why? sheet**

Create `lib/features/dating/data/dating_names.dart` with exactly:

```dart
// Spec 2 W3a: country and open-place names inside Dating sentences. The
// open lists are always built from get_dating_availability (R-36).
import 'package:attune/features/auth/sign_up/domain/country_names.dart';
import 'package:attune/features/dating/data/dating_home.dart';
import 'package:attune/features/dating/setup/dating_list_names.dart';
import 'package:attune/i10n/generated/app_localizations.dart';

String datingCountryName(AppLocalizations loc, String iso) =>
    countryNameFor(iso, special: {'GB': loc.dating_countryUk});

String _list(AppLocalizations loc, List<String> names) =>
    formatCountryList(names, nameOf: (name) => name, pair: loc.flow_listTwo);

/// "the United Kingdom and Ghana (Greater Accra and Ashanti)".
String datingOpenList(AppLocalizations loc, DatingAvailability open) =>
    _list(loc, [
      for (final c in open.countries)
        c.openRegionKeys == null
            ? datingCountryName(loc, c.code)
            : loc.dating_countryWithRegions(
              datingCountryName(loc, c.code),
              _list(loc, [
                for (final key in c.openRegionKeys!)
                  datingListName(loc, key) ?? key,
              ]),
            ),
    ]);

/// The open regions of [country] ("Greater Accra and Ashanti"), else its name.
String datingOpenRegionNames(
  AppLocalizations loc,
  DatingAvailability open,
  String country,
) {
  for (final c in open.countries) {
    if (c.code == country && c.openRegionKeys != null) {
      return _list(loc, [
        for (final key in c.openRegionKeys!) datingListName(loc, key) ?? key,
      ]);
    }
  }
  return datingCountryName(loc, country);
}
```

Create `lib/features/dating/setup/dating_list_names.dart` with exactly:

```dart
// Spec 2 W3 (§2.2 region_list, faith_list): the app's name for every
// name_key the country config can send. A key with no name here is not
// offered (Task 5's test proves every seeded key has one).
import 'package:attune/features/auth/sign_up/domain/country_names.dart';
import 'package:attune/i10n/generated/app_localizations.dart';

String? datingListName(AppLocalizations loc, String key) => switch (key) {
  'dating_region_gh_af' => loc.dating_region_gh_af,
  'dating_region_gh_ah' => loc.dating_region_gh_ah,
  'dating_region_gh_bo' => loc.dating_region_gh_bo,
  'dating_region_gh_be' => loc.dating_region_gh_be,
  'dating_region_gh_cp' => loc.dating_region_gh_cp,
  'dating_region_gh_ep' => loc.dating_region_gh_ep,
  'dating_region_gh_aa' => loc.dating_region_gh_aa,
  'dating_region_gh_ne' => loc.dating_region_gh_ne,
  'dating_region_gh_np' => loc.dating_region_gh_np,
  'dating_region_gh_ot' => loc.dating_region_gh_ot,
  'dating_region_gh_sv' => loc.dating_region_gh_sv,
  'dating_region_gh_ue' => loc.dating_region_gh_ue,
  'dating_region_gh_uw' => loc.dating_region_gh_uw,
  'dating_region_gh_tv' => loc.dating_region_gh_tv,
  'dating_region_gh_wp' => loc.dating_region_gh_wp,
  'dating_region_gh_wn' => loc.dating_region_gh_wn,
  'dating_side_gh_accra' => loc.dating_side_gh_accra,
  'dating_side_gh_tema' => loc.dating_side_gh_tema,
  'dating_side_gh_kumasi' => loc.dating_side_gh_kumasi,
  'dating_side_gh_outside_kumasi' => loc.dating_side_gh_outside_kumasi,
  'dating_region_gb_tlc' => loc.dating_region_gb_tlc,
  'dating_region_gb_tld' => loc.dating_region_gb_tld,
  'dating_region_gb_tle' => loc.dating_region_gb_tle,
  'dating_region_gb_tlf' => loc.dating_region_gb_tlf,
  'dating_region_gb_tlg' => loc.dating_region_gb_tlg,
  'dating_region_gb_tlh' => loc.dating_region_gb_tlh,
  'dating_region_gb_tli' => loc.dating_region_gb_tli,
  'dating_region_gb_tlj' => loc.dating_region_gb_tlj,
  'dating_region_gb_tlk' => loc.dating_region_gb_tlk,
  'dating_region_gb_tll' => loc.dating_region_gb_tll,
  'dating_region_gb_tlm' => loc.dating_region_gb_tlm,
  'dating_region_gb_tln' => loc.dating_region_gb_tln,
  // W3b (Task 5): faith and denomination names.
  _ => null,
};

/// A region by code, through W1b's key convention; an unknown code reads as
/// itself (a sentence about where Dating is open must still read).
String datingRegionName(AppLocalizations loc, String country, String code) =>
    datingListName(
      loc,
      'dating_region_${country.toLowerCase()}_${code.toLowerCase()}',
    ) ??
    code.toUpperCase();

String datingRegionList(
  AppLocalizations loc,
  String country,
  List<String> codes,
) => formatCountryList(
  codes,
  nameOf: (code) => datingRegionName(loc, country, code),
  pair: loc.flow_listTwo,
);
```

Create `lib/features/dating/section/dating_why_sheet.dart` with exactly:

```dart
// Spec 2 §2.4, §3.2 D5 (10 S3): the static "Why?" sheet. Opening it calls
// nothing: no RPC, no counter, no log. Used by the kill-switch note, D5 and
// D6.
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/ui/text/allow_large_text.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_buttons.dart';
import 'package:attune/features/dating/data/dating_names.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';

Future<void> showDatingWhySheet(
  BuildContext context, {
  required String country,
}) {
  final loc = AppLocalizations.of(context)!;
  final name = datingCountryName(loc, country);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder:
        (sheet) => AllowLargeText(
          child: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                Spacing.lg,
                0,
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
                      loc.dating_why,
                      style: Theme.of(sheet).textTheme.titleLarge,
                    ),
                  ),
                  const SizedBox(height: Spacing.md),
                  Text(
                    loc.dating_whyBody(name),
                    style: Theme.of(sheet).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: Spacing.lg),
                  FlowSecondaryButton(
                    label: loc.dating_close,
                    onPressed: () => Navigator.of(sheet).pop(),
                  ),
                ],
              ),
            ),
          ),
        ),
  );
}
```

- [ ] **Step 4: The section**

Create `lib/features/dating/section/dating_section.dart` with exactly:

```dart
// Spec 2 W3a (§3.1, §3.15; carries 1, 3, 8, 9, 13): the Dating section in
// Me, driven by get_dating_home() alone. Every state the server names has
// its card; any other reads as unavailable (Task 1's model). A 200 ms
// cross-fade between states (none with reduce motion); one semantic region
// "Dating"; a failed or offline read says so (nothing is cached). Nothing
// here is kept on the phone (D20); taps belong to the account that made
// them (D8).
import 'package:attune/app/routing/app_router.dart' show RouteNames;
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/ui/motion/reduce_motion.dart';
import 'package:attune/core/utils/date_formatter.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_buttons.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_text_field.dart'
    show FlowErrorLine;
import 'package:attune/features/dating/data/dating_home.dart';
import 'package:attune/features/dating/data/dating_home_repository.dart';
import 'package:attune/features/dating/data/dating_names.dart';
import 'package:attune/features/dating/data/dating_providers.dart';
import 'package:attune/features/dating/data/dating_rpc.dart';
import 'package:attune/features/dating/gentle_wait/gentle_wait_providers.dart'
    show datingOnlineProvider;
import 'package:attune/features/dating/routes/dating_routes.dart';
import 'package:attune/features/dating/section/dating_why_sheet.dart';
import 'package:attune/features/dating/setup/dating_list_names.dart';
import 'package:attune/features/me/presentation/path_switch.dart';
import 'package:attune/features/onboarding/domain/home_state.dart';
import 'package:attune/features/onboarding/presentation/path_chooser.dart'
    show PathChoiceOutcome;
import 'package:attune/features/onboarding/presentation/providers/home_state_providers.dart';
import 'package:attune/home/home_seams.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class DatingSection extends ConsumerStatefulWidget {
  const DatingSection({super.key});

  @override
  ConsumerState<DatingSection> createState() => _DatingSectionState();
}

class _DatingSectionState extends ConsumerState<DatingSection>
    with WidgetsBindingObserver {
  final _keys = DatingActionKeys();
  bool _busy = false;
  DatingLifecycleError? _error;
  DatingNoticeResult? _notice;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ref.listenManual<String?>(datingAccountProvider, (previous, next) {
      if (previous == next || !mounted) return;
      setState(() {
        _busy = false;
        _error = null;
        _notice = null;
      });
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  void _refresh() =>
      ref.invalidate(datingHomeProvider(ref.read(datingAccountProvider)));

  Future<void> _resume() async {
    if (_busy) return;
    final account = ref.read(datingAccountProvider);
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await ref
        .read(datingLifecycleGatewayProvider)
        .resume(_keys.keyFor('resume', account));
    if (!mounted || ref.read(datingAccountProvider) != account) return;
    final error = result.error;
    setState(() {
      _busy = false;
      // Already resumed elsewhere: just read the home again.
      _error = error == DatingLifecycleError.notPaused ? null : error;
    });
    if (result.ok || error == DatingLifecycleError.notPaused) _refresh();
  }

  Future<void> _tellMe(String country, String? region) async {
    if (_busy) return;
    final account = ref.read(datingAccountProvider);
    setState(() {
      _busy = true;
      _notice = null;
    });
    final result = await ref
        .read(datingHomeGatewayProvider)
        .requestNotice(country, region: region);
    if (!mounted || ref.read(datingAccountProvider) != account) return;
    setState(() {
      _busy = false;
      _notice = result;
    });
    if (result == DatingNoticeResult.alreadyOpen) _refresh();
  }

  /// Spec 1's one-tap "Not ready?" (as the slot had it).
  Future<void> _notReady() async {
    final userId = ref.read(homeAuthProvider).currentUser?.id;
    if (userId == null) return;
    final shown = ref.read(homeStateProvider(userId));
    final outcome = await switchPath(
      context,
      ref,
      to: AppPath.justMe,
      oneTap: true,
      home: shown,
    );
    if (outcome == PathChoiceOutcome.relationshipOpen && mounted) {
      await showSharedSpaceSheetAfterRefusal(context, shown);
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final account = ref.watch(datingAccountProvider);
    final home = ref.watch(datingHomeProvider(account));
    final online = ref.watch(datingOnlineProvider).valueOrNull ?? true;
    // One entry per account (D8), so a value here is this account's; a
    // failed refresh never shows the last state (nothing is cached).
    final data = home.hasError ? null : home.valueOrNull;
    final Object key;
    final Widget child;
    if (data != null) {
      key = data.state;
      child = _card(context, loc, data, online);
    } else if (home.hasError) {
      key = 'error';
      child = _SectionCard(
        title: loc.flow_slotDatingTitle,
        children: [
          if (!online)
            _Calm(loc.dating_offline)
          else
            FlowErrorLine(text: loc.dating_errorGeneric, liveRegion: true),
          FlowSecondaryButton(
            label: loc.dating_retry,
            busy: home.isLoading,
            onPressed: _refresh,
          ),
        ],
      );
    } else {
      key = 'loading';
      child = const SizedBox(height: 96);
    }
    return Semantics(
      container: true,
      label: loc.flow_slotDatingTitle,
      // A new account gets a new switcher (D8, I-8): the last account's
      // card never stays in the tree while it would fade out.
      child: KeyedSubtree(
        key: ValueKey(account),
        child: AnimatedSwitcher(
          duration:
              reduceMotionOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 200),
          child: KeyedSubtree(key: ValueKey(key), child: child),
        ),
      ),
    );
  }

  Widget _card(
    BuildContext context,
    AppLocalizations loc,
    DatingHome h,
    bool online,
  ) {
    final country = h.country;
    // C-2: whenever there is Dating data to leave or clear, in every state,
    // Dating settings (and with it Leave and Clear) is one tap away.
    final settings =
        h.hasData || h.hasProfile || h.notice.requested
            ? FlowTextLink(
              label: loc.dating_settingsTitle,
              alignment: AlignmentDirectional.centerStart,
              onPressed: () => context.push(DatingPaths.settings),
            )
            : null;
    final notReady = FlowTextLink(
      label: loc.flow_slotNotReady,
      alignment: AlignmentDirectional.centerStart,
      onPressed: _notReady,
    );
    switch (h.state) {
      case DatingHomeState.featureUnavailable:
      case DatingHomeState.countryClosed:
        return _SectionCard(
          title:
              country == null
                  ? loc.flow_slotClosedTitle
                  : loc.dating_sectionNotOpen(datingCountryName(loc, country)),
          onTap: () => context.push(DatingPaths.notOpenFor(country: country)),
          children: [
            ..._notice_(loc, h, online, loc.dating_tellMe, null),
            notReady,
            if (settings != null) settings,
          ],
        );
      case DatingHomeState.regionClosed:
        final c = country ?? '';
        return _SectionCard(
          title: loc.dating_sectionRegionOpenOnly(
            datingRegionList(loc, c, h.openRegions),
          ),
          onTap:
              () => context.push(
                DatingPaths.notOpenFor(country: country, region: h.region),
              ),
          children: [
            ..._notice_(
              loc,
              h,
              online,
              loc.dating_tellMeRegion(datingRegionName(loc, c, h.region ?? '')),
              h.region,
            ),
            notReady,
            if (settings != null) settings,
          ],
        );
      case DatingHomeState.gentleWait:
        final opens = h.opensAt;
        return _SectionCard(
          title:
              opens == null
                  ? loc.flow_slotGentleWaitNoDate
                  : loc.flow_slotGentleWait(
                    MyDateFormat.toDate(opens.toLocal()),
                  ),
          onTap: () => context.push(DatingPaths.step('wait')),
          children: [
            FlowTextLink(
              label: loc.dating_gentleWaitTitle,
              alignment: AlignmentDirectional.centerStart,
              onPressed: () => context.push(DatingPaths.step('wait')),
            ),
            if (settings != null) settings,
          ],
        );
      case DatingHomeState.notStarted:
        return _SectionCard(
          title: loc.flow_slotDatingTitle,
          lines: [loc.dating_sectionNotStarted],
          children: [
            FlowPrimaryButton(
              label: loc.flow_slotSetUp,
              onPressed: () => context.push(DatingPaths.step('how')),
            ),
            notReady,
            if (settings != null) settings,
          ],
        );
      case DatingHomeState.setupInProgress:
        return _SectionCard(
          title: loc.flow_slotDatingTitle,
          children: [
            FlowSecondaryButton(
              label: loc.dating_sectionFinish,
              onPressed:
                  () => context.push(DatingPaths.step(h.nextStep ?? 'how')),
            ),
            if (settings != null) settings,
          ],
        );
      case DatingHomeState.coolOff:
        final at = h.firstDropAt?.toLocal();
        return _SectionCard(
          title: loc.flow_slotDatingTitle,
          lines: [
            if (at != null)
              loc.dating_sectionFirstDrop(
                MyDateFormat.toDate(at),
                MyDateFormat.toTime(at),
              ),
          ],
          children: [if (settings != null) settings],
        );
      case DatingHomeState.active:
        return _SectionCard(
          title: loc.flow_slotDatingTitle,
          lines: [loc.dating_sectionActive],
          children: [if (settings != null) settings],
        );
      case DatingHomeState.paused:
        return _paused(context, loc, h, online, settings);
      case DatingHomeState.reverifyDevice:
        return _plain(loc, loc.dating_sectionReverify, settings);
      case DatingHomeState.restricted:
        return _plain(loc, loc.dating_sectionRestricted, settings);
      case DatingHomeState.hold:
        return _plain(loc, loc.dating_sectionHold, settings);
      case DatingHomeState.ageReview:
        return _plain(loc, loc.dating_sectionAgeReview, settings);
      case DatingHomeState.unavailable:
        return _plain(loc, loc.dating_sectionUnavailable, settings);
    }
  }

  Widget _plain(AppLocalizations loc, String line, Widget? settings) =>
      _SectionCard(
        title: loc.flow_slotDatingTitle,
        lines: [line],
        children: [if (settings != null) settings],
      );

  List<Widget> _notice_(
    AppLocalizations loc,
    DatingHome h,
    bool online,
    String label,
    String? region,
  ) {
    final country = h.country;
    return [
      if (h.notice.requested || _notice == DatingNoticeResult.saved)
        _Calm(loc.dating_tellMeDone)
      else if (h.notice.available && country != null)
        FlowSecondaryButton(
          label: label,
          busy: _busy,
          onPressed: online ? () => _tellMe(country, region) : null,
        ),
      if (_notice == DatingNoticeResult.busy) _Calm(loc.dating_busy),
      if (_notice == DatingNoticeResult.failed ||
          _notice == DatingNoticeResult.invalid)
        FlowErrorLine(text: loc.dating_errorGeneric, liveRegion: true),
    ];
  }

  Widget _paused(
    BuildContext context,
    AppLocalizations loc,
    DatingHome h,
    bool online,
    Widget? settings,
  ) {
    final reason = h.pauseReason;
    // Every reason has a safe card (carry 9); Resume only where resume can
    // work (the shared space, a parked number or travel keep it paused).
    final canResume = const {
      DatingPauseReason.user,
      DatingPauseReason.gates,
      DatingPauseReason.pathChange,
      DatingPauseReason.unknown,
    }.contains(reason);
    final line = switch (reason) {
      DatingPauseReason.relationship => loc.dating_sectionPausedRelationship,
      DatingPauseReason.sameGenderSwitch => loc.dating_sectionSameGenderNote(
        datingCountryName(loc, h.country ?? ''),
      ),
      DatingPauseReason.away => loc.dating_sectionAway,
      _ => loc.dating_sectionPaused,
    };
    return _SectionCard(
      title: loc.flow_slotDatingTitle,
      lines: [line],
      children: [
        if (reason == DatingPauseReason.sameGenderSwitch) ...[
          FlowTextLink(
            label: loc.dating_why,
            alignment: AlignmentDirectional.centerStart,
            onPressed:
                () => showDatingWhySheet(context, country: h.country ?? ''),
          ),
          FlowSecondaryButton(
            label: loc.dating_chooseAgain,
            onPressed: () => context.push(DatingPaths.step('you')),
          ),
        ],
        if (canResume)
          FlowPrimaryButton(
            label: loc.dating_resume,
            busy: _busy,
            onPressed: online ? _resume : null,
          ),
        if (_error != null) ..._errorRows(context, loc, _error!),
        if (settings != null) settings,
      ],
    );
  }

  List<Widget> _errorRows(
    BuildContext context,
    AppLocalizations loc,
    DatingLifecycleError error,
  ) {
    Widget link(String label, String to) => FlowTextLink(
      label: label,
      alignment: AlignmentDirectional.centerStart,
      onPressed: () => context.push(to),
    );
    return switch (error) {
      DatingLifecycleError.pathNotDating => [
        FlowErrorLine(text: loc.dating_errorPathNotDating, liveRegion: true),
        link(loc.dating_openHowYouUse, RouteNames.howYouUseAttune),
      ],
      DatingLifecycleError.consentRequired => [
        FlowErrorLine(text: loc.dating_errorConsent, liveRegion: true),
        link(loc.dating_sectionFinish, DatingPaths.step('privacy')),
      ],
      DatingLifecycleError.profileIncomplete ||
      DatingLifecycleError.activationRequired ||
      DatingLifecycleError.enrollmentIncomplete => [
        FlowErrorLine(text: loc.dating_errorIncomplete, liveRegion: true),
        link(loc.dating_sectionFinish, DatingPaths.step('how')),
      ],
      DatingLifecycleError.resumeGatesNotMet ||
      DatingLifecycleError.notEligible => [
        FlowErrorLine(text: loc.dating_errorResumeGates, liveRegion: true),
      ],
      DatingLifecycleError.reverifyDevice => [
        _Calm(loc.dating_sectionReverify),
      ],
      DatingLifecycleError.busy => [_Calm(loc.dating_busy)],
      DatingLifecycleError.rateLimited => [
        FlowErrorLine(text: loc.dating_errorRateLimited, liveRegion: true),
      ],
      _ => [FlowErrorLine(text: loc.dating_errorGeneric, liveRegion: true)],
    };
  }
}

/// A calm line, read out when it appears (never the error colour).
class _Calm extends StatelessWidget {
  const _Calm(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Text(
      text,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
        color: Theme.of(context).colorScheme.onSurface,
      ),
    ),
  );
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    this.lines = const [],
    this.children = const [],
    this.onTap,
  });

  final String title;
  final List<String> lines;
  final List<Widget> children;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.md),
      child: Card(
        margin: EdgeInsets.zero,
        elevation: 0,
        clipBehavior: Clip.antiAlias,
        color: theme.colorScheme.surfaceContainerLow,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(Spacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                for (final line in lines) ...[
                  const SizedBox(height: Spacing.xs),
                  Text(
                    line,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                for (final child in children) ...[
                  const SizedBox(height: Spacing.sm),
                  child,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 5: The not-open screen and the settings shell**

Create `lib/features/dating/not_open/dating_not_open_screen.dart` with exactly:

```dart
// Spec 2 W3a (§3.10; R-36): "Dating isn't open in {country} yet", or its
// region variant. No animation, no waitlist number; the open list is
// built from get_dating_availability. A country chosen here stays in this
// screen's memory only (D20). "Use Attune just for me" only on the Dating
// path.
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/utils/bottom_sheet_utils.dart';
import 'package:attune/features/auth/log_in/domain/phone_country.dart';
import 'package:attune/features/auth/log_in/presentation/widgets/phone_country_picker_sheet.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_buttons.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_frame.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_text_field.dart'
    show FlowErrorLine;
import 'package:attune/features/dating/data/dating_home.dart';
import 'package:attune/features/dating/data/dating_home_repository.dart';
import 'package:attune/features/dating/data/dating_names.dart';
import 'package:attune/features/dating/data/dating_providers.dart';
import 'package:attune/features/dating/gentle_wait/gentle_wait_providers.dart'
    show datingOnlineProvider;
import 'package:attune/features/dating/routes/dating_routes.dart';
import 'package:attune/features/dating/setup/dating_list_names.dart';
import 'package:attune/features/me/presentation/path_switch.dart';
import 'package:attune/features/onboarding/domain/home_state.dart';
import 'package:attune/features/onboarding/presentation/providers/home_state_providers.dart';
import 'package:attune/home/home_location.dart';
import 'package:attune/home/home_seams.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class DatingNotOpenScreen extends ConsumerStatefulWidget {
  const DatingNotOpenScreen({super.key, this.country, this.region});

  final String? country;
  final String? region;

  @override
  ConsumerState<DatingNotOpenScreen> createState() =>
      _DatingNotOpenScreenState();
}

class _DatingNotOpenScreenState extends ConsumerState<DatingNotOpenScreen> {
  String? _country;
  bool _busy = false;
  bool? _requested;
  DatingNoticeResult? _result;

  static String? _iso(String? code) {
    final upper = code?.trim().toUpperCase();
    return upper != null && RegExp(r'^[A-Z]{2}$').hasMatch(upper)
        ? upper
        : null;
  }

  @override
  void initState() {
    super.initState();
    _country = _iso(widget.country);
  }

  String? get _region => _country == null ? null : widget.region?.toUpperCase();

  Future<void> _ask() async {
    final country = _country;
    if (_busy || country == null) return;
    setState(() {
      _busy = true;
      _result = null;
    });
    final result = await ref
        .read(datingHomeGatewayProvider)
        .requestNotice(country, region: _region);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _result = result;
      if (result == DatingNoticeResult.saved) _requested = true;
    });
  }

  Future<void> _cancel() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _result = null;
    });
    final result = await ref.read(datingHomeGatewayProvider).cancelNotice();
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (result == DatingNoticeResult.saved) {
        _requested = false;
      } else {
        _result = result;
      }
    });
  }

  Future<void> _pick() async {
    await BottomSheetUtils.showDocumentationBottomSheet<void>(
      context: context,
      padding: 0,
      widget: PhoneCountryPickerSheet(
        selectedCountry: PhoneCountries.defaultCountry,
        onCountrySelected: (country) {
          if (mounted) setState(() => _country = country.isoCode);
        },
      ),
    );
  }

  Future<void> _justMe() async {
    await switchPath(context, ref, to: AppPath.justMe, oneTap: true);
    if (mounted) context.go(homeLocation(tab: AppTab.me));
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final online = ref.watch(datingOnlineProvider).valueOrNull ?? true;
    final open =
        ref.watch(datingAvailabilityProvider).valueOrNull ??
        const DatingAvailability();
    final home =
        ref
            .watch(datingHomeProvider(ref.watch(datingAccountProvider)))
            .valueOrNull;
    final userId = ref.watch(homeAuthProvider).currentUser?.id;
    final onDating =
        userId != null &&
        ref.watch(homeStateProvider(userId)).path == AppPath.dating;
    final country = _country;
    final region = _region;
    final requested =
        _requested ??
        (home != null &&
            home.country == country &&
            home.region == region &&
            home.notice.requested);
    final regional = region != null && country != null;
    final title =
        country == null
            ? loc.flow_slotClosedTitle
            : regional
            ? loc.dating_notOpenRegionTitle(
              datingOpenRegionNames(loc, open, country),
            )
            : loc.dating_notOpenTitle(datingCountryName(loc, country));
    return FlowFrame(
      title: title,
      onBack:
          () =>
              context.canPop()
                  ? context.pop()
                  : context.go(homeLocation(tab: AppTab.me)),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!online) ...[
            Text(loc.dating_offline, style: theme.textTheme.bodyMedium),
            const SizedBox(height: Spacing.md),
          ],
          Text(
            regional
                ? loc.dating_notOpenRegionBody
                : loc.dating_notOpenBody(datingOpenList(loc, open)),
            style: theme.textTheme.bodyLarge,
          ),
          if (requested) ...[
            const SizedBox(height: Spacing.md),
            Semantics(
              liveRegion: true,
              child: Text(
                loc.dating_tellMeDone,
                style: theme.textTheme.bodyMedium,
              ),
            ),
            FlowTextLink(
              label: loc.dating_settingsTitle,
              alignment: AlignmentDirectional.centerStart,
              onPressed: () => context.push(DatingPaths.settings),
            ),
            if (online)
              FlowTextLink(
                label: loc.dating_tellMeOff,
                alignment: AlignmentDirectional.centerStart,
                onPressed: _cancel,
              ),
          ],
          if (_result == DatingNoticeResult.busy) ...[
            const SizedBox(height: Spacing.sm),
            Text(loc.dating_busy, style: theme.textTheme.bodyMedium),
          ],
          if (_result == DatingNoticeResult.failed ||
              _result == DatingNoticeResult.invalid) ...[
            const SizedBox(height: Spacing.sm),
            FlowErrorLine(text: loc.dating_errorGeneric, liveRegion: true),
          ],
        ],
      ),
      actions: [
        if (country == null)
          FlowPrimaryButton(label: loc.flow_slotChooseCountry, onPressed: _pick)
        else if (!requested)
          FlowPrimaryButton(
            label:
                regional
                    ? loc.dating_tellMeRegion(
                      datingRegionName(loc, country, region),
                    )
                    : loc.dating_tellMe,
            busy: _busy,
            onPressed: online ? _ask : null,
          ),
        if (onDating)
          FlowSecondaryButton(label: loc.dating_justForMe, onPressed: _justMe),
      ],
    );
  }
}
```

Create `lib/features/dating/settings/dating_settings_screen.dart` with exactly:

```dart
// Spec 2 §3.12 (W3a shell; W3c adds the rest): Dating settings. W3a: the
// Dating lock (Spec 1's setting, R-8), "Tell me when Dating opens" while
// asked for, and the gentle-wait reflection's clear in every state (carry
// 5; exposure-reducing, never gated). Large text through AllowLargeText;
// InfoRowWidget scales by itself.
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/ui/text/allow_large_text.dart';
import 'package:attune/core/widgets/info_row_widget.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_text_field.dart'
    show FlowErrorLine;
import 'package:attune/features/dating/data/dating_providers.dart';
import 'package:attune/features/dating/gentle_wait/gentle_wait_providers.dart';
import 'package:attune/features/dating/gentle_wait/gentle_wait_repository.dart';
import 'package:attune/features/me/presentation/widgets/dating_lock_setting.dart'
    show setDatingLock;
import 'package:attune/features/safety/data/dating_lock_store.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class DatingSettingsScreen extends ConsumerStatefulWidget {
  const DatingSettingsScreen({super.key});

  @override
  ConsumerState<DatingSettingsScreen> createState() =>
      _DatingSettingsScreenState();
}

class _DatingSettingsScreenState extends ConsumerState<DatingSettingsScreen> {
  bool _clearing = false;
  GentleWaitSave? _cleared;

  Future<void> _clearReflection() async {
    if (_clearing) return;
    final account = ref.read(datingAccountProvider);
    setState(() {
      _clearing = true;
      _cleared = null;
    });
    var result = GentleWaitSave.failed;
    try {
      result = await ref.read(gentleWaitGatewayProvider).clear();
    } catch (_) {
      result = GentleWaitSave.failed;
    }
    if (!mounted || ref.read(datingAccountProvider) != account) return;
    setState(() {
      _clearing = false;
      _cleared = result;
    });
  }

  Future<void> _cancelNotice() async {
    await ref.read(datingHomeGatewayProvider).cancelNotice();
    if (mounted) {
      ref.invalidate(datingHomeProvider(ref.read(datingAccountProvider)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final home =
        ref
            .watch(datingHomeProvider(ref.watch(datingAccountProvider)))
            .valueOrNull;
    final online = ref.watch(datingOnlineProvider).valueOrNull ?? true;
    final lock = ref.watch(datingLockProvider).valueOrNull ?? false;
    Widget calm(String text) => Semantics(
      liveRegion: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Spacing.sm),
        child: Text(text, style: theme.textTheme.bodyMedium),
      ),
    );
    return AllowLargeText(
      child: Scaffold(
        appBar: AppBar(title: Text(loc.dating_settingsTitle)),
        body: SafeArea(
          // Not a lazy list: every row is built, so Leave and Clear are
          // always in the tree to scroll to (C-2).
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(Spacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!online) calm(loc.dating_offline),
                // W3c (Task 12): §3.12's rows go here.
                // Switches are SwitchListTiles: the title is the switch's own
                // semantic label and a tap anywhere on the row toggles it.
                if (home?.notice.requested ?? false)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    secondary: const Icon(Icons.notifications_none),
                    title: Text(loc.dating_settingsNotice),
                    value: true,
                    onChanged: (on) {
                      if (!on) _cancelNotice();
                    },
                  ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  secondary: const Icon(Icons.lock_outline),
                  title: Text(loc.flow_lockTitle),
                  subtitle: Text(loc.flow_lockSubtitle),
                  value: lock,
                  onChanged: (on) => setDatingLock(context, ref, on),
                ),
                InfoRowWidget(
                  key: const ValueKey('dating_settings_clear_reflection'),
                  title: loc.dating_settingsClearReflection,
                  subtitle: '',
                  icon: Icons.delete_outline,
                  showAvatar: false,
                  onTap: _clearing ? null : _clearReflection,
                ),
                if (_cleared == GentleWaitSave.saved)
                  calm(loc.dating_gentleWaitCleared),
                if (_cleared == GentleWaitSave.busy)
                  calm(loc.dating_gentleWaitClearBusy),
                if (_cleared != null &&
                    _cleared != GentleWaitSave.saved &&
                    _cleared != GentleWaitSave.busy)
                  FlowErrorLine(
                    text: loc.dating_errorGeneric,
                    liveRegion: true,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
```

(If the settings test's toggle tap lands on the row and not the `Switch`, tap `find.byType(Switch)` inside the row instead; `InfoRowWidget`'s toggle row calls `onToggleChanged` from its own `Switch`.)

- [ ] **Step 6: The routes, the slot**

Create `$D/edit_T4.py` with exactly:

```python
import sys
sys.path.insert(0, '.superpowers/sdd/2026-11-07-spec2-w3')
from anchor import edit
edit('lib/features/dating/routes/dating_routes.dart', [
    ("import 'package:attune/features/dating/lock/dating_unlock.dart';\n",
     "import 'package:attune/features/dating/lock/dating_unlock.dart';\n"
     "import 'package:attune/features/dating/not_open/dating_not_open_screen.dart';\n"),
    ("import 'package:attune/features/dating/routes/dating_setup_steps.dart';\n",
     "import 'package:attune/features/dating/routes/dating_setup_steps.dart';\n"
     "import 'package:attune/features/dating/settings/dating_settings_screen.dart';\n"),
    ("    motion: (s) => datingStepMotion(s.pathParameters['step'] ?? ''),\n  ),\n];",
     "    motion: (s) => datingStepMotion(s.pathParameters['step'] ?? ''),\n  ),\n"
     "  datingRoute(\n    DatingPaths.settings,\n    'datingSettings',\n    signedIn,\n"
     "    (s) => const DatingSettingsScreen(),\n    motion: (s) => DatingMotion.sharedAxis,\n  ),\n"
     "  datingRoute(\n    DatingPaths.notOpen,\n    'datingNotOpen',\n    signedIn,\n"
     "    (s) => DatingNotOpenScreen(\n      country: s.uri.queryParameters['country'],\n"
     "      region: s.uri.queryParameters['region'],\n    ),\n  ),\n];"),
], 'T4 routes')
edit('test/architecture/text_scale_routes_test.dart', [
    ("  'datingSetupStep',\n  'datingUnlock',\n",
     "  'datingSetupStep',\n  'datingUnlock',\n  'datingSettings',\n  'datingNotOpen',\n"),
], 'T4 text scale names')
```

Create `$D/write_slot_T4.py` with exactly (the whole body changes, so the file is replaced after its old header is confirmed):

```python
import pathlib
p = pathlib.Path('lib/features/me/presentation/widgets/dating_slot.dart')
old = p.read_text()
assert '/// Spec 2 W3 replaces it with DatingSection.' in old and 'class DatingSlot extends ConsumerStatefulWidget' in old, 'not the Spec 1 slot'
p.write_text('''import 'package:attune/features/dating/lock/dating_unlock.dart';
import 'package:attune/features/dating/section/dating_section.dart';
import 'package:attune/features/me/presentation/widgets/your_space_section.dart';
import 'package:attune/features/onboarding/presentation/providers/home_state_providers.dart'
    show HomeSnapshot;
import 'package:attune/features/safety/data/dating_lock_store.dart';
import 'package:attune/features/safety/presentation/widgets/confirm_safety_pin.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The Dating slot at the top of Me, Dating path only (Spec 1 §3.9). Since
/// Spec 2 W3a its body is Spec 2's DatingSection (get_dating_home()). The
/// slot keeps the Dating lock's row: one row until the Safety PIN is
/// entered, for this foreground session only; the unlock is Spec 2's
/// datingUnlockedProvider, shared with every /dating route (R-8).
class DatingSlot extends ConsumerWidget {
  const DatingSlot({super.key, required this.home});

  final HomeSnapshot home;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loc = AppLocalizations.of(context)!;
    final locked = ref.watch(datingLockProvider);
    // Unknown yet: show nothing rather than a flash of Dating.
    if (!locked.hasValue) return const SizedBox.shrink();
    if (locked.value! && !ref.watch(datingUnlockedProvider)) {
      return Semantics(
        container: true,
        label: loc.dating_sectionLockedLabel,
        child: SpaceRow(
          title: loc.flow_slotLocked,
          subtitle: loc.flow_slotLockedLine,
          icon: Icons.lock_outline,
          onTap: () async {
            if (await confirmSafetyPin(context)) {
              ref.read(datingUnlockedProvider.notifier).unlock();
            }
          },
        ),
      );
    }
    return const DatingSection();
  }
}
''')
print('dating_slot.dart: the body is DatingSection')
```

```bash
D=.superpowers/sdd/2026-11-07-spec2-w3
python3 -I $D/edit_T4.py
python3 -I $D/write_slot_T4.py
```

Expected: `… 3 edit(s) (T4 routes)`, `… 1 edit(s) (T4 text scale names)`, `dating_slot.dart: the body is DatingSection`.

- [ ] **Step 7: Rewrite the slot's test for the new body**

Replace the whole of `test/features/me/dating_slot_test.dart` with exactly:

```dart
// Spec 1 §3.9 slot, Spec 2 W3a body: the Dating lock's one row, then
// DatingSection; the unlock is shared with the Dating routes and ends when
// the app is put away.
import 'package:attune/features/dating/data/dating_home.dart';
import 'package:attune/features/dating/lock/dating_unlock.dart';
import 'package:attune/features/me/presentation/screens/me_home_screen.dart';
import 'package:attune/features/me/presentation/me_providers.dart';
import 'package:attune/features/me/data/journal_reminder_service.dart';
import 'package:attune/features/onboarding/data/home_state_service.dart';
import 'package:attune/features/relationships/presentation/relationship_lifecycle_providers.dart';
import 'package:attune/features/safety/data/dating_lock_store.dart';
import 'package:attune/home/home_seams.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_home_state.dart';
import '../../helpers/fake_reminder_rpc.dart';
import '../../helpers/flow_harness.dart';
import '../../helpers/home_harness.dart';
import '../dating/support/dating_fakes.dart';
import '../dating/support/dating_shell.dart';

List<Override> _overrides({
  bool locked = false,
  DatingHome home = const DatingHome(state: DatingHomeState.notStarted),
}) {
  final json = homeJson(path: 'dating', datingEnabled: true);
  return [
    ...datingHomeOnlyOverrides(
      home: FakeDatingHomeGateway(home: home),
      account: 'u-slot',
    ),
    datingLockStoreProvider.overrideWithValue(FakeLock(locked)),
    homeAuthProvider.overrideWithValue(FakeHomeAuth(testUser('u-slot'))),
    homeStateServiceProvider.overrideWithValue(
      HomeStateService(FakeHomeStateGateway(state: json)),
    ),
    relationshipLifecycleProvider.overrideWith((ref) async => null),
    firstActionInputsProvider.overrideWithValue((hasNote: true, hasQuiz: true)),
    journalReminderRpcProvider.overrideWithValue(FakeReminderRpc().call),
  ];
}

Future<void> _pump(
  WidgetTester t, {
  bool locked = false,
  DatingHome? home,
}) async {
  await t.pumpWidget(const SizedBox());
  FlutterSecureStorage.setMockInitialValues({});
  await pumpFlowScreen(
    t,
    () => MeHomeScreen(
      home: snapshotOf(homeJson(path: 'dating', datingEnabled: true)),
    ),
    overrides: _overrides(
      locked: locked,
      home: home ?? const DatingHome(state: DatingHomeState.notStarted),
    ),
  );
}

void main() {
  testWidgets('no lock: the section shows at once', (t) async {
    await _pump(t);
    expect(find.text('Set up Dating'), findsOneWidget);
    expect(find.text('Dating is locked'), findsNothing);
  });

  testWidgets('the Dating lock: one row until the PIN is entered', (t) async {
    await _pump(t, locked: true);
    expect(find.text('Dating is locked'), findsOneWidget);
    expect(find.text('Set up Dating'), findsNothing);
    expect(find.bySemanticsLabel(RegExp('Dating, locked')), findsOneWidget);
    // No PIN on this phone: confirmSafetyPin lets it through.
    await t.tap(find.text('Dating is locked'));
    await t.pumpAndSettle();
    expect(find.text('Set up Dating'), findsOneWidget);
    final c = ProviderScope.containerOf(t.element(find.byType(MeHomeScreen)));
    expect(c.read(datingUnlockedProvider), isTrue);
  });

  testWidgets('the unlock ends when the app is put away', (t) async {
    await _pump(t, locked: true);
    await t.tap(find.text('Dating is locked'));
    await t.pumpAndSettle();
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      t.binding.handleAppLifecycleStateChanged(state);
      await t.pump();
    }
    await t.pumpAndSettle();
    expect(find.text('Dating is locked'), findsOneWidget);
    expect(find.text('Set up Dating'), findsNothing);
  });

  testWidgets('carry 3: both partners ended the space early: no wait card', (
    t,
  ) async {
    await t.pumpWidget(const SizedBox());
    final json = homeJson(
      path: 'dating',
      datingEnabled: true,
      link: 'ended_window',
      windowEndsAt: '2026-11-20T12:00:00Z',
    );
    await pumpFlowScreen(
      t,
      () => MeHomeScreen(home: snapshotOf(json)),
      overrides: _overrides(),
    );
    expect(find.textContaining('Dating opens for you on'), findsNothing);
    expect(find.text('Set up Dating'), findsOneWidget);
  });

  testWidgets('guidelines, locked and not', (t) async {
    final semantics = t.ensureSemantics();
    for (final locked in [true, false]) {
      await _pump(t, locked: locked);
      await expectFlowGuidelines(t);
    }
    semantics.dispose();
  });

  testWidgets('me_dating_open goldens', (t) async {
    final json = homeJson(path: 'dating', datingEnabled: true);
    await expectFlowGoldens(
      t,
      'me_dating_open',
      () => MeHomeScreen(home: snapshotOf(json)),
      overrides: _overrides(),
    );
  });
}
```

(Import paths: take `firstActionInputsProvider`, `journalReminderRpcProvider` and `relationshipLifecycleProvider` from the files the old test imported — copy its import block for those three names if the paths above differ, and keep only what the new file uses.)

- [ ] **Step 8: Spec 1 tests that render Me on the Dating path**

```bash
flutter test test/features/me test/home test/accessibility/w10/spec1_rtl_goldens_test.dart test/features/settings test/features/safety/w6 test/features/onboarding 2>&1 | grep -E '^\S.*\[E\]|Some tests failed|All tests passed' | head -40
```

Expected (verified, fix round 1): `402 passed, 2 failed` — `"Not ready?" refused: the sheet shows; End acts` (`test/features/me/shared_space_sheet_shell_test.dart`: its "Not ready?" now comes from the section's not-started card) and `J4 "More ways to use Attune" on the Dating path` (`test/accessibility/w10/spec1_rtl_goldens_test.dart`). Both get the section's fakes and nothing else:

Create `$D/edit_T4_spec1.py` with exactly:

```python
# Spec 2 W3a Task 4 Step 8: the two Spec 1 tests whose Me is on the Dating
# path render Spec 2's section now; they get its fakes, nothing else.
import sys
sys.path.insert(0, '.superpowers/sdd/2026-11-07-spec2-w3')
from anchor import edit

edit('test/features/me/shared_space_sheet_shell_test.dart', [
    ("import '../../helpers/tap_in_reach.dart';\n",
     "import '../../helpers/tap_in_reach.dart';\n"
     "import '../dating/support/dating_shell.dart';\n"),
    ("      publicAppConfigGatewayProvider.overrideWithValue(\n"
     "        FakePublicConfigGateway(),\n      ),\n    ],\n",
     "      publicAppConfigGatewayProvider.overrideWithValue(\n"
     "        FakePublicConfigGateway(),\n      ),\n"
     "      // Spec 2 W3a: Me's Dating card is the section now.\n"
     "      ...datingHomeOnlyOverrides(account: 'u-home'),\n    ],\n"),
], 'T4 shared-space shell test')

edit('test/accessibility/w10/spec1_rtl_goldens_test.dart', [
    ("import '../../helpers/fake_home_state.dart';\n",
     "import '../../features/dating/support/dating_shell.dart';\n"
     "import '../../helpers/fake_home_state.dart';\n"),
    ("          relationshipLifecycleProvider.overrideWith((ref) async => null),\n"
     "          firstActionInputsProvider.overrideWithValue((\n"
     "            hasNote: true,\n            hasQuiz: true,\n          )),\n"
     "        ],\n      );\n"
     "      await tapInReach(t, find.text('More ways to use Attune'));\n",
     "          relationshipLifecycleProvider.overrideWith((ref) async => null),\n"
     "          firstActionInputsProvider.overrideWithValue((\n"
     "            hasNote: true,\n            hasQuiz: true,\n          )),\n"
     "          // Spec 2 W3a: Me's Dating card is the section now.\n"
     "          ...datingHomeOnlyOverrides(account: 'u-rtl'),\n"
     "        ],\n      );\n"
     "      await tapInReach(t, find.text('More ways to use Attune'));\n"),
], 'T4 J4 goldens test')
```

```bash
python3 -I $D/edit_T4_spec1.py
flutter test test/features/me/shared_space_sheet_shell_test.dart 2>&1 | tail -1
flutter test --update-goldens --plain-name 'J4 "More ways to use Attune" on the Dating path' test/accessibility/w10/spec1_rtl_goldens_test.dart 2>&1 | tail -1
```

Expected: the two edit lines; `All tests passed!` twice. Open each regenerated `j4_more_ways` PNG (the Dating card is the section's not-started card) and list them in the report. No other Spec 1 test's assertions change.

- [ ] **Step 9: Format, analyze, goldens, run**

```bash
dart format lib/features/dating/data/dating_names.dart lib/features/dating/setup/dating_list_names.dart lib/features/dating/section lib/features/dating/not_open lib/features/dating/settings test/features/dating/section test/features/dating/not_open test/features/dating/settings test/features/dating/no_disk_writes_test.dart test/features/dating/setup/dating_region_names_test.dart test/features/me/dating_slot_test.dart
flutter analyze --no-pub lib test 2>&1 | tail -1
flutter test --update-goldens test/features/dating/section test/features/dating/not_open test/features/me/dating_slot_test.dart 2>&1 | tail -1
flutter test test/features/dating test/features/me test/architecture test/app test/core/notifications test/accessibility 2>&1 | tail -1
python3 scripts/large_text_audit.py --scale 2.0 test/features/dating 2>&1 | tail -1
```

Expected: `Formatted …`; no new analyzer issue; goldens written (`section_{not_started,region_closed,paused}`, `not_open_{country,region}`, `me_dating_open` ×4 variants) — open each `scale2.0.png` and check nothing is clipped and every action is reachable; `All tests passed!`; `SCALE 2.0: 0 site(s) to fix, 0 listed apart`.

- [ ] **Step 10: Mutants**

Create `$D/mut_T4.py` with exactly:

```python
S = 'lib/features/dating/section/dating_section.dart'
T = ['test/features/dating/section/dating_section_test.dart']
MUTS = {
  'unknown_reason_no_resume': (S, "      DatingPauseReason.unknown,\n    }.contains(reason);", "    }.contains(reason);", T),
  'relationship_resumable': (S, "      DatingPauseReason.user,\n", "      DatingPauseReason.user,\n      DatingPauseReason.relationship,\n", T),
  'path_error_generic': (S, "      DatingLifecycleError.pathNotDating => [\n", "      DatingLifecycleError.failed => [\n", T),
  'stale_after_error': (S, "    final data = home.hasError ? null : home.valueOrNull;", "    final data = home.valueOrNull;", T),
  'notice_always': (S, "      else if (h.notice.available && country != null)", "      else if (country != null)", T),
  'd8_taps_carry_over': (S, "      setState(() {\n        _busy = false;\n        _error = null;\n        _notice = null;\n      });\n    });", "    });", T),
  # The sheet reads the home (a request) when it opens: the test sees one
  # more read. Two edits: the imports, then the call (M-6).
  'why_reads': ('lib/features/dating/section/dating_why_sheet.dart', [
      ("import 'package:flutter/material.dart';\n",
       "import 'package:flutter/material.dart';\n"
       "import 'package:flutter_riverpod/flutter_riverpod.dart';\n"
       "import 'package:attune/features/dating/data/dating_providers.dart';\n"),
      ("  return showModalBottomSheet<void>(",
       "  ProviderScope.containerOf(context).read(datingHomeGatewayProvider).read();\n"
       "  return showModalBottomSheet<void>("),
  ], None, T),
  # C-2: a restricted, held or unavailable card without the settings link.
  'plain_no_settings': (S, "        children: [if (settings != null) settings],\n      );", "      );", T),
  # I-8: one switcher for every account (the last card fades out in view).
  'd8_shared_switcher': (S, "        key: ValueKey(account),\n", "        key: const ValueKey('one'),\n", T),
  'slot_ignores_lock': ('lib/features/me/presentation/widgets/dating_slot.dart', "    if (locked.value! && !ref.watch(datingUnlockedProvider)) {", "    if (false) {", ['test/features/me/dating_slot_test.dart']),
  'settings_clear_gated': ('lib/features/dating/settings/dating_settings_screen.dart', "                  onTap: _clearing ? null : _clearReflection,", "                  onTap: (home?.hasProfile ?? false) && !_clearing ? _clearReflection : null,", ['test/features/dating/settings/dating_settings_screen_test.dart']),
  'not_open_hardcoded': ('lib/features/dating/not_open/dating_not_open_screen.dart', "                : loc.dating_notOpenBody(datingOpenList(loc, open)),", "                : loc.dating_notOpenBody('Ghana and the United Kingdom'),", ['test/features/dating/not_open/dating_not_open_screen_test.dart']),
}
```

```bash
python3 -I $D/dmut.py $D/mut_T4.py | tee $D/mut_T4.txt | tail -1
```

Expected: `12/12 killed` (`why_reads` is a two-edit mutant: the imports, then a home read when the sheet opens; `plain_no_settings` dies at `C-2: restricted with Dating data links to settings`; `d8_shared_switcher` at the D8 test).

- [ ] **Step 11: The W3a gate**

```bash
D=.superpowers/sdd/2026-11-07-spec2-w3
$D/suite.sh attune_spec3a > $D/sql-after-W3a.txt; echo "$(grep -c '^PASS' $D/sql-after-W3a.txt) PASS, $(grep -c '^FAIL' $D/sql-after-W3a.txt) FAIL"
diff <(grep '^FAIL' $D/sql-baseline-1.txt) <(grep '^FAIL' $D/sql-after-W3a.txt) && echo "no new FAIL"
flutter test --reporter compact > $D/flutter-after-W3a.txt 2>&1; tail -c 200 $D/flutter-after-W3a.txt
flutter analyze --no-pub lib test > $D/analyze-after-W3a.txt 2>&1; tail -1 $D/analyze-after-W3a.txt
diff <(sed -E 's/:[0-9]+:[0-9]+ /:L:C /' $D/analyze-baseline.txt | sort) <(sed -E 's/:[0-9]+:[0-9]+ /:L:C /' $D/analyze-after-W3a.txt | sort) | grep '^>' | grep -v 'issues found' || echo "no new analyzer issue"
shasum -c .superpowers/sdd/2026-11-04-spec1-w10-accessibility-docs/w10-1.0.sha | grep -vc ': OK$'
shasum -c .superpowers/sdd/2026-11-04-spec1-w9/flag_off.sha | grep -vc ': OK$'
shasum -c $D/latch.sha
flutter test test/architecture/games_untouched_test.dart 2>&1 | tail -1
```

Expected: `159 PASS, 14 FAIL`; `no new FAIL`; the Flutter tail with no failure beyond the known `planning_recent` flake (the count is the baseline minus the 5 tests of the two deleted v1 files and the 15 old slot tests, plus every test Tasks 1–4 added); analyzer `571 issues found.` or fewer and `no new analyzer issue`; `0`, `0`; `lib/home/home_screen.dart: OK`; `All tests passed!`. The race script already ran in Task 3 on a scratch copy; it needs no re-run here (no SQL changed since). Do not commit; record the tree in the report. **W3a ships here** (Dating off in production; every unbuilt step opens Me).


---

## Batch W3b — setup D1–D8

### Task 5: Migration `dating_v2_setup_lists`: the faith lists, `get_dating_setup_lists()`, the setup repository and every list name (§4.9 W3b, §2.2 faith lists, §3.2 D3/D5/D6/D8, §7.1 setup rows, §7.5 mutants 4 and 7; R-17, R-18, R-19)

**Files:**
- Create: `supabase/migrations/20261107160000_dating_v2_setup_lists.sql`, `supabase/migrations/20261107160010_dating_v2_setup_lists_grants.sql`, `lib/features/dating/setup/dating_setup_models.dart`, `lib/features/dating/setup/dating_setup_repository.dart`, `lib/features/dating/setup/dating_setup_providers.dart`, `test/features/dating/setup/dating_list_names_test.dart`, `test/features/dating/setup/dating_setup_repository_test.dart`, `test/features/dating/support/dating_setup_fakes.dart`, `$D/{setup_W3b.sql, mut_T5.py, arb_fragment_T5.txt, edit_T5.py}`
- Modify: `supabase/tests/dating_v2_setup_contracts.sql` (sections M–O appended), `supabase/tests/dating_rls_canary.sql`, `scripts/local_pg_grants.sql`, `lib/features/dating/setup/dating_list_names.dart` (faith cases), `lib/i10n/app_en.arb` + generated

**Interfaces:**
- Consumes: W1's setup writers (signatures in "Interfaces this plan consumes"), `private.dating_phone_country`, `private.dating_same_gender_on`, `private.dating_default_ages(integer) → integer[]`, `public.account_age(uuid) → integer`; Task 1's `DatingRpc`, `DatingWrite`, `datingWrite()`; Task 4's `datingListName`.
- Produces: `get_dating_setup_lists() → jsonb {ok, countries:[{code, same_gender, regions:[{code, name_key, open, sides:[{code, name_key}]}], faiths:[{code, name_key, denominations:[…]}]}], phone_country, note_country, default_ages:[min, max]}` (or `{ok:false, reason:'reverify_device'}`); `DatingSetupLists`, `DatingCountryLists`, `DatingRegion`, `DatingOption`, `DatingFaith`, `DatingMyProfile`; `DatingSetupGateway` (`lists()`, `myProfile()`, `saveIntention(...)`, `saveLocation(...)`, `agreeAndBegin(String key)`, `saveIdentity(...)`, `saveWhoToMeet(...)`, `saveChildren(...)`, `saveFaith(...)`, `clearFaith(String key)`, `savePrompts(...)`, `saveDisplayName(...)`, `saveSettings(...)`), `DatingSetupRepository`; providers `datingSetupGatewayProvider`, `datingSetupListsProvider(account)`, `datingMyProfileProvider(account)`; test fake `FakeDatingSetupGateway`.

- [ ] **Step 1: Write the failing contract sections**

Create `$D/setup_W3b.sql` with exactly (appended to `dating_v2_setup_contracts.sql` before its final `ROLLBACK;` in Step 3):

```sql
-- =====================================================================
-- M. (W3b, §2.2, R-19) The reviewed faith lists, as the W3b migration
--    published them (this file's own fixture republished GH's list for its
--    D8 rows, so the migration's version is found by its publisher).
-- =====================================================================
DO $m$
DECLARE
  v_gh jsonb;
  v_gb jsonb;
BEGIN
  SELECT c.faith_list INTO v_gh FROM public.country_safety_config AS c
   WHERE c.country_code = 'GH' AND c.published_by = 'migration:dating_v2_setup_lists';
  SELECT c.faith_list INTO v_gb FROM public.country_safety_config AS c
   WHERE c.country_code = 'GB' AND c.published_by = 'migration:dating_v2_setup_lists';
  IF (SELECT array_agg(f ->> 'code' ORDER BY ord) FROM jsonb_array_elements(v_gh) WITH ORDINALITY AS x(f, ord))
       IS DISTINCT FROM ARRAY['christian', 'muslim', 'traditional', 'other', 'none', 'prefer_not_to_say']
     OR (SELECT array_agg(d ->> 'code' ORDER BY ord) FROM jsonb_array_elements(v_gh -> 0 -> 'denominations') WITH ORDINALITY AS x(d, ord))
       IS DISTINCT FROM ARRAY['catholic', 'anglican', 'methodist', 'presbyterian', 'pentecostal_charismatic', 'seventh_day_adventist', 'other_christian'] THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the Ghana faith list is not the reviewed one: %', v_gh;
  END IF;
  IF (SELECT array_agg(f ->> 'code' ORDER BY ord) FROM jsonb_array_elements(v_gb) WITH ORDINALITY AS x(f, ord))
       IS DISTINCT FROM ARRAY['christian', 'muslim', 'hindu', 'sikh', 'jewish', 'buddhist', 'other', 'none', 'prefer_not_to_say']
     OR (SELECT array_agg(d ->> 'code' ORDER BY ord) FROM jsonb_array_elements(v_gb -> 0 -> 'denominations') WITH ORDINALITY AS x(d, ord))
       IS DISTINCT FROM ARRAY['catholic', 'church_of_england_anglican', 'orthodox', 'pentecostal_charismatic', 'other_christian'] THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the UK faith list is not the reviewed one: %', v_gb;
  END IF;
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(v_gh || v_gb) AS f
              WHERE f ->> 'name_key' IS DISTINCT FROM 'dating_faith_' || (f ->> 'code')
                 OR EXISTS (SELECT 1 FROM jsonb_array_elements(coalesce(f -> 'denominations', '[]'::jsonb)) AS d
                             WHERE d ->> 'name_key' IS DISTINCT FROM 'dating_denomination_' || (d ->> 'code'))) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a faith name_key breaks the dating_faith_/dating_denomination_ convention';
  END IF;
  -- Publishing a list never opened or closed a country.
  IF EXISTS (SELECT 1 FROM public.country_safety_config AS c
              WHERE c.published_by = 'migration:dating_v2_setup_lists'
                AND c.dating_enabled IS DISTINCT FROM (SELECT p.dating_enabled FROM public.country_safety_config AS p
                                                        WHERE p.country_code = c.country_code AND p.version = c.version - 1)) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the faith-list publish changed a country''s dating_enabled';
  END IF;
END $m$;

-- =====================================================================
-- N. (W3b, R-17, R-18) get_dating_setup_lists: signed in; the device
--    check; every open country's regions (open or not, with sides), faith
--    list and same-gender switch; the person's own phone country, the
--    country note's country (Tier 1/2 phone countries only) and default ages.
-- =====================================================================
DO $n$
DECLARE
  v_us constant uuid := pg_temp.ready('a0', 'GB', 'TLI', 'woman', ARRAY['man']);
  v_gh constant uuid := pg_temp.id('a1');
  v_young constant uuid := pg_temp.id('a2');
  v jsonb;
  v_msg text;
  v_country jsonb;
BEGIN
  BEGIN
    PERFORM public.get_dating_setup_lists();
    RAISE EXCEPTION 'CONTRACT VIOLATED: the lists answered a signed-out caller';
  EXCEPTION WHEN insufficient_privilege THEN
    GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
    IF v_msg IS DISTINCT FROM 'not_authenticated' THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: signed out raised %', v_msg;
    END IF;
  END;
  -- A UK phone (Tier 3): its country is read, and Tier 3 gets no note. (The
  -- fixture's own +1 555 phone has no country, so no note either way.)
  UPDATE auth.users SET phone = '447700900' || '190' WHERE id = v_us;
  UPDATE public.users SET phone = '447700900' || '190' WHERE id = v_us;
  UPDATE public.feature_flags SET enabled = true WHERE key = 'dating_same_gender_matching';
  v := pg_temp.call(v_us, 'SELECT public.get_dating_setup_lists()');
  IF (v ->> 'ok')::boolean IS NOT TRUE
     -- (Earlier sections of this file open other countries: only GB and GH
     -- are this section's.)
     OR (SELECT array_agg(c ->> 'code' ORDER BY c ->> 'code') FROM jsonb_array_elements(v -> 'countries') AS c
          WHERE c ->> 'code' IN ('GB', 'GH')) IS DISTINCT FROM ARRAY['GB', 'GH'] THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the lists are not GB and GH: %', v;
  END IF;
  SELECT c INTO v_country FROM jsonb_array_elements(v -> 'countries') AS c WHERE c ->> 'code' = 'GH';
  IF v_country ->> 'same_gender' IS DISTINCT FROM 'false'
     OR jsonb_array_length(v_country -> 'regions') <> 16
     OR (SELECT r ->> 'open' FROM jsonb_array_elements(v_country -> 'regions') AS r WHERE r ->> 'code' = 'AA') IS DISTINCT FROM 'true'
     OR (SELECT r ->> 'open' FROM jsonb_array_elements(v_country -> 'regions') AS r WHERE r ->> 'code' = 'TV') IS DISTINCT FROM 'false'
     OR (SELECT jsonb_array_length(r -> 'sides') FROM jsonb_array_elements(v_country -> 'regions') AS r WHERE r ->> 'code' = 'AA') <> 2
     OR v_country -> 'faiths' IS DISTINCT FROM (public.dating_country_config('GH')).faith_list THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: Ghana''s lists read %', v_country;
  END IF;
  SELECT c INTO v_country FROM jsonb_array_elements(v -> 'countries') AS c WHERE c ->> 'code' = 'GB';
  IF v_country ->> 'same_gender' IS DISTINCT FROM 'true' OR jsonb_array_length(v_country -> 'regions') <> 12 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the UK''s lists read %', v_country;
  END IF;
  IF v -> 'note_country' IS DISTINCT FROM 'null'::jsonb OR v ->> 'phone_country' IS DISTINCT FROM 'GB'
     OR v -> 'default_ages' IS DISTINCT FROM '[25, 35]'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a 30-year-old with a Tier 3 phone reads note % ages %', v -> 'note_country', v -> 'default_ages';
  END IF;
  -- A Ghana phone (Tier 1): the note names Ghana. A 19-year-old: 18 to 26.
  INSERT INTO auth.users (id, phone, phone_confirmed_at, created_at) VALUES
    (v_gh, '233558703' || '91', now(), now() - interval '40 days'),
    (v_young, '15558709' || '92', now(), now() - interval '40 days');
  INSERT INTO public.users (id, phone, display_name, path, created_at, eula_accepted_at, eula_version) VALUES
    (v_gh, '233558703' || '91', 'Lists a1', 'dating', now() - interval '40 days', now(), '2'),
    (v_young, '15558709' || '92', 'Lists a2', 'dating', now() - interval '40 days', now(), '2');
  INSERT INTO public.account_birthdates (user_id, birth_date) VALUES
    (v_gh, current_date - interval '30 years'), (v_young, current_date - interval '19 years 10 days');
  IF pg_temp.call(v_gh, 'SELECT public.get_dating_setup_lists()') ->> 'note_country' IS DISTINCT FROM 'GH'
     OR pg_temp.call(v_gh, 'SELECT public.get_dating_setup_lists()') ->> 'phone_country' IS DISTINCT FROM 'GH'
     OR pg_temp.call(v_young, 'SELECT public.get_dating_setup_lists()') -> 'default_ages' IS DISTINCT FROM '[18, 26]'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the note or the 18-20 default ages are wrong: % / %',
      pg_temp.call(v_gh, 'SELECT public.get_dating_setup_lists()'), pg_temp.call(v_young, 'SELECT public.get_dating_setup_lists()');
  END IF;
  -- A closed country is not offered; the global switch off makes every same_gender false.
  PERFORM public.publish_country_config('GB', '{"dating_enabled": false}');
  UPDATE public.feature_flags SET enabled = false WHERE key = 'dating_same_gender_matching';
  v := pg_temp.call(v_us, 'SELECT public.get_dating_setup_lists()');
  IF (SELECT array_agg(c ->> 'code') FROM jsonb_array_elements(v -> 'countries') AS c
       WHERE c ->> 'code' IN ('GB', 'GH')) IS DISTINCT FROM ARRAY['GH']
     OR EXISTS (SELECT 1 FROM jsonb_array_elements(v -> 'countries') AS c WHERE c ->> 'same_gender' = 'true') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a closed country or a switched-off same-gender rule is still offered: %', v;
  END IF;
  PERFORM public.publish_country_config('GB', '{"dating_enabled": true}');
  -- No person's data but the caller's own (no gender, no seeking, no other person).
  IF position('woman' IN v::text) > 0 OR position(v_us::text IN v::text) > 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the lists carry a person''s data: %', v;
  END IF;
END $n$;

-- =====================================================================
-- O. (§7.1 "notify requests aggregate only") No API role reads the
--    request table; the only client-callable functions naming it are the
--    request and the cancel; its counter carries no country.
-- =====================================================================
DO $o$
DECLARE
  v_got text;
BEGIN
  IF has_table_privilege('authenticated', 'public.dating_notify_requests', 'SELECT')
     OR has_table_privilege('anon', 'public.dating_notify_requests', 'SELECT') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a client can read dating_notify_requests';
  END IF;
  SELECT string_agg(p.oid::regprocedure::text, ', ' ORDER BY p.oid::regprocedure::text) INTO v_got
    FROM pg_proc AS p
   WHERE p.prosrc ~ 'dating_notify_requests' AND has_function_privilege('authenticated', p.oid, 'EXECUTE');
  IF v_got IS DISTINCT FROM 'cancel_dating_country_notice(), request_dating_country_notice(text,text)' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: client-callable readers of the notice table: %', v_got;
  END IF;
  IF EXISTS (SELECT 1 FROM public.metric_counters AS c WHERE c.key LIKE 'dating.notify.%' AND c.key ~ '\.[A-Z]{2}$') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a notice counter names a country';
  END IF;
END $o$;
```

(`pg_temp.ready(n, country, region, identity, seeking)`, `pg_temp.id(n)` and `pg_temp.call(user, sql)` are the file's own helpers; `ready` makes an adult with the D4 consents through D2, D3, D5, D6. Before writing, check the phones are unused: `grep -rn "23355870391\|1555870392" supabase/tests` prints nothing.)

- [ ] **Step 2: Mutants 4 and 7, on the live D5 writer (§7.5)**

Create `$D/mut_T5.py` with exactly:

```python
# Spec mutants 4 and 7 on save_dating_identity's LIVE body (W1c's file is
# no longer its whole truth: re-applying it would undo later re-creations).
import os, subprocess
LIVE = subprocess.run(
    ['psql', '-X', '-At', '-d', os.environ.get('W3_DB', 'attune_spec3a'), '-c',
     "select pg_get_functiondef('public.save_dating_identity(text,text,text,text,text[],boolean)'::regprocedure)"],
    capture_output=True, text=True, check=True).stdout.rstrip('\n') + ';\n'
OFF = """  IF private.dating_same_gender_on(v_country) IS NOT TRUE
     AND (p_identity IS DISTINCT FROM 'woman' AND p_identity IS DISTINCT FROM 'man'
          OR p_specific IS NOT NULL OR p_pronouns IS NOT NULL OR cardinality(v_extra) > 0) THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'not_available');
  END IF;
"""
STORE = """    UPDATE public.dating_profiles AS p SET gender_visible = coalesce(p_visible, false), updated_at = now()
     WHERE p.user_id = v_user;
"""
assert LIVE.count(OFF) == 1 and LIVE.count(STORE) == 1, 'the live D5 body moved: re-anchor'
MUTS = {
  # 4: the identity is stored before the country is checked.
  'm4_identity_stores_before_country': ('RAW', LIVE.replace(OFF, '').replace(STORE, STORE + OFF)),
  # 7: raise instead of returning not_available.
  'm7_identity_raises_not_available': ('RAW', LIVE.replace(OFF, OFF.replace(
      "    RETURN jsonb_build_object('ok', false, 'reason', 'not_available');",
      "    RAISE EXCEPTION 'not_available';"))),
}
```

```bash
D=.superpowers/sdd/2026-11-07-spec2-w3; mkdir -p $D/mut
python3 -I $D/mutate.py supabase/migrations/20261107150000_dating_v2_client_reads.sql supabase/tests/dating_v2_setup_contracts.sql $D/mut_T5.py $D/mut | tee $D/mut_T5_m4m7.txt
```

Expected (verified, fix round 1): two lines; `m4_identity_stores_before_country: … CONTRACT VIOLATED: an off-country same-gender answer changed a row or a counter …`; `m7_identity_raises_not_available: ERROR:  not_available` (the raise itself: section A expects a returned refusal, so a raise aborts it, M-3); quote both in the report. (The migration argument only satisfies the runner's shape check; RAW mutants don't use it.)

- [ ] **Step 3: Append the sections; see them fail**

```bash
D=.superpowers/sdd/2026-11-07-spec2-w3
python3 -I - <<'PY'
import pathlib
p = pathlib.Path('supabase/tests/dating_v2_setup_contracts.sql')
s = p.read_text()
assert s.rstrip().endswith('ROLLBACK;'), 'the contract does not end with ROLLBACK;'
body = s.rstrip()[:-len('ROLLBACK;')]
add = pathlib.Path('.superpowers/sdd/2026-11-07-spec2-w3/setup_W3b.sql').read_text()
p.write_text(body + add + '\nROLLBACK;\n')
print('dating_v2_setup_contracts.sql: sections M-O added')
PY
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/dating_v2_setup_contracts.sql 2>&1 | grep -m1 ERROR
```

Expected: `ERROR:  CONTRACT VIOLATED: the Ghana faith list is not the reviewed one: <NULL>` (no row published by the migration yet).

- [ ] **Step 4: The migration and its twin**

Create `supabase/migrations/20261107160000_dating_v2_setup_lists.sql` with exactly:

```sql
-- Spec 2 W3b, migration 1 (§4.9 W3b; §2.2 "Faith lists (W3b seed)"; plan
-- R-17, R-18, R-19): the reviewed faith and denomination lists for Ghana and
-- the UK, published through publish_country_config (which keeps each row's
-- dating_enabled; only when the list differs, so a replay publishes
-- nothing; a refusal raises), and get_dating_setup_lists() for D3, D5, D6
-- and D8. The lists are reviewer content (W3 gate). No region-list edit:
-- the cultural reviewer has none yet.
-- Grants in 20261107160010_dating_v2_setup_lists_grants.sql.
BEGIN;
SET LOCAL lock_timeout = '5s';

DO $lists$
DECLARE
  v jsonb;
  v_code text;
  v_list jsonb;
BEGIN
  FOR v_code, v_list IN VALUES
    ('GH', '[{"code": "christian", "name_key": "dating_faith_christian", "denominations": [
               {"code": "catholic", "name_key": "dating_denomination_catholic"},
               {"code": "anglican", "name_key": "dating_denomination_anglican"},
               {"code": "methodist", "name_key": "dating_denomination_methodist"},
               {"code": "presbyterian", "name_key": "dating_denomination_presbyterian"},
               {"code": "pentecostal_charismatic", "name_key": "dating_denomination_pentecostal_charismatic"},
               {"code": "seventh_day_adventist", "name_key": "dating_denomination_seventh_day_adventist"},
               {"code": "other_christian", "name_key": "dating_denomination_other_christian"}]},
             {"code": "muslim", "name_key": "dating_faith_muslim", "denominations": []},
             {"code": "traditional", "name_key": "dating_faith_traditional", "denominations": []},
             {"code": "other", "name_key": "dating_faith_other", "denominations": []},
             {"code": "none", "name_key": "dating_faith_none", "denominations": []},
             {"code": "prefer_not_to_say", "name_key": "dating_faith_prefer_not_to_say", "denominations": []}]'::jsonb),
    ('GB', '[{"code": "christian", "name_key": "dating_faith_christian", "denominations": [
               {"code": "catholic", "name_key": "dating_denomination_catholic"},
               {"code": "church_of_england_anglican", "name_key": "dating_denomination_church_of_england_anglican"},
               {"code": "orthodox", "name_key": "dating_denomination_orthodox"},
               {"code": "pentecostal_charismatic", "name_key": "dating_denomination_pentecostal_charismatic"},
               {"code": "other_christian", "name_key": "dating_denomination_other_christian"}]},
             {"code": "muslim", "name_key": "dating_faith_muslim", "denominations": []},
             {"code": "hindu", "name_key": "dating_faith_hindu", "denominations": []},
             {"code": "sikh", "name_key": "dating_faith_sikh", "denominations": []},
             {"code": "jewish", "name_key": "dating_faith_jewish", "denominations": []},
             {"code": "buddhist", "name_key": "dating_faith_buddhist", "denominations": []},
             {"code": "other", "name_key": "dating_faith_other", "denominations": []},
             {"code": "none", "name_key": "dating_faith_none", "denominations": []},
             {"code": "prefer_not_to_say", "name_key": "dating_faith_prefer_not_to_say", "denominations": []}]'::jsonb)
  LOOP
    IF (public.dating_country_config(v_code)).faith_list IS DISTINCT FROM v_list THEN
      v := public.publish_country_config(v_code, jsonb_build_object(
             'faith_list', v_list, 'published_by', 'migration:dating_v2_setup_lists'));
      IF (v ->> 'ok')::boolean IS NOT TRUE THEN
        RAISE EXCEPTION 'dating_v2_setup_lists: the % faith list was not published: %', v_code, v;
      END IF;
    END IF;
  END LOOP;
END $lists$;

-- D3, D5, D6, D8 (R-17): config only, plus the caller's own phone country,
-- its note (Tier 1/2 phone countries; the location variant is W4b/W8b's,
-- R-18) and default ages. No gender, no seeking, nobody else.
CREATE OR REPLACE FUNCTION public.get_dating_setup_lists()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user constant uuid := auth.uid();
  v_phone_country text;
  v_tier smallint;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;
  IF public.dating_require_trusted_device() IS NOT TRUE THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'reverify_device');
  END IF;
  v_phone_country := private.dating_phone_country((SELECT a.phone FROM auth.users AS a WHERE a.id = v_user));
  IF v_phone_country IS NOT NULL THEN
    v_tier := (public.dating_country_config(v_phone_country)).tier;
  END IF;
  RETURN jsonb_build_object(
    'ok', true,
    'countries', coalesce((
      SELECT jsonb_agg(jsonb_build_object(
               'code', c.country_code::text,
               'same_gender', coalesce(private.dating_same_gender_on(c.country_code::text), false),
               'regions', coalesce((
                 SELECT jsonb_agg(jsonb_build_object(
                          'code', r ->> 'code',
                          'name_key', r ->> 'name_key',
                          'open', c.open_regions IS NULL OR (r ->> 'code') = ANY (c.open_regions),
                          'sides', coalesce(r -> 'sides', '[]'::jsonb)) ORDER BY r ->> 'code')
                   FROM jsonb_array_elements(c.region_list) AS r), '[]'::jsonb),
               'faiths', c.faith_list) ORDER BY c.country_code)
        FROM public.country_safety_config AS c
       WHERE c.is_current AND c.dating_enabled), '[]'::jsonb),
    'phone_country', v_phone_country,
    'note_country', CASE WHEN v_tier IN (1, 2) THEN v_phone_country END,
    'default_ages', to_jsonb(private.dating_default_ages(public.account_age(v_user))));
END;
$$;
REVOKE ALL ON FUNCTION public.get_dating_setup_lists() FROM PUBLIC, anon, service_role;

COMMIT;
```

Create `supabase/migrations/20261107160010_dating_v2_setup_lists_grants.sql` with exactly:

```sql
-- Spec 2 W3b: grants for 20261107160000_dating_v2_setup_lists.sql. The
-- lists RPC is the app's (authenticated only).
BEGIN;
SET LOCAL lock_timeout = '5s';
REVOKE ALL ON FUNCTION public.get_dating_setup_lists() FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.get_dating_setup_lists() TO authenticated;
COMMIT;
```

Create `$D/edit_contracts_T5.py` with exactly:

```python
# Spec 2 W3b Task 5: the canary row, and W1b's GH publish pin made relative
# (the W3b faith-list publish moves GH's and GB's versions on, I-3).
import sys
sys.path.insert(0, '.superpowers/sdd/2026-11-07-spec2-w3')
from anchor import edit

edit('supabase/tests/dating_rls_canary.sql', [
    ("-- ---------------------------------------------------------------------\n"
     "-- Checks (every batch adds its rows above this line).\n",
     "-- W3b (migration 1): the setup lists RPC is the app's.\n"
     "INSERT INTO allowed_fn (sig, clients, service) VALUES\n"
     "  ('get_dating_setup_lists()', 'authenticated', '');\n"
     "-- ---------------------------------------------------------------------\n"
     "-- Checks (every batch adds its rows above this line).\n"),
], 'T5 canary')

edit('supabase/tests/country_safety_config_contracts.sql', [
    ("  v := pg_temp.publish('GH', '{\"dating_enabled\": true, \"published_by\": \"contract\"}');\n"
     "  IF (v ->> 'ok')::boolean IS NOT TRUE OR (v ->> 'version')::int IS DISTINCT FROM 2\n",
     "  -- Spec 2 W3b (I-3): a later migration may have published GH again (its\n"
     "  -- faith list), so the new version is the current one plus one.\n"
     "  v_gh_before := (pg_temp.current('GH')).version;\n"
     "  v := pg_temp.publish('GH', '{\"dating_enabled\": true, \"published_by\": \"contract\"}');\n"
     "  IF (v ->> 'ok')::boolean IS NOT TRUE OR (v ->> 'version')::int IS DISTINCT FROM v_gh_before + 1\n"),
    ("     OR (SELECT is_current FROM public.country_safety_config WHERE country_code = 'GH' AND version = 1) IS NOT FALSE THEN\n"
     "    RAISE EXCEPTION 'CONTRACT VIOLATED: development did not publish GH with the checks reported: %', v;\n",
     "     OR (SELECT is_current FROM public.country_safety_config WHERE country_code = 'GH' AND version = v_gh_before) IS NOT FALSE THEN\n"
     "    RAISE EXCEPTION 'CONTRACT VIOLATED: development did not publish GH with the checks reported: %', v;\n"),
    ("DO $$\nDECLARE\n  v jsonb;\n  v_evidence constant jsonb := '{\"osa_illegal_harms_assessment\": \"REF-1\",",
     "DO $$\nDECLARE\n  v jsonb;\n  v_gh_before integer; -- Spec 2 W3b (I-3)\n  v_evidence constant jsonb := '{\"osa_illegal_harms_assessment\": \"REF-1\","),
    ("  PERFORM set_config('app.settings.attune_environment', 'production', true);\n"
     "  v := pg_temp.publish('GB', '{\"dating_enabled\": true}');\n"
     "  IF v IS DISTINCT FROM '{\"ok\": false, \"reason\": \"config:production_checks_failed\", \"checks\": [\"evidence_missing\", \"resources_not_verified\"]}'::jsonb\n"
     "     OR (pg_temp.current('GB')).version IS DISTINCT FROM 1 THEN\n",
     "  PERFORM set_config('app.settings.attune_environment', 'production', true);\n"
     "  v_gb_before := (pg_temp.current('GB')).version; -- Spec 2 W3b (I-3)\n"
     "  v := pg_temp.publish('GB', '{\"dating_enabled\": true}');\n"
     "  IF v IS DISTINCT FROM '{\"ok\": false, \"reason\": \"config:production_checks_failed\", \"checks\": [\"evidence_missing\", \"resources_not_verified\"]}'::jsonb\n"
     "     OR (pg_temp.current('GB')).version IS DISTINCT FROM v_gb_before THEN\n"),
    ("  v_gh_before integer; -- Spec 2 W3b (I-3)\n",
     "  v_gh_before integer; -- Spec 2 W3b (I-3)\n  v_gb_before integer; -- Spec 2 W3b (I-3)\n"),
], 'T5 GH and GB version pins (I-3)')

# The orphan probe puts back the row that was current (W3b published GB's
# version 2), not version 1.
edit('supabase/tests/country_safety_config_contracts.sql', [
    ("  UPDATE public.country_safety_config SET is_current = true WHERE country_code = 'GB' AND version = 1;\n",
     "  -- Spec 2 W3b (I-3): the newest row was the current one before the probe.\n"
     "  UPDATE public.country_safety_config SET is_current = true WHERE country_code = 'GB'\n"
     "     AND version = (SELECT max(c.version) FROM public.country_safety_config AS c WHERE c.country_code = 'GB');\n"),
], 'T5 GB orphan probe (I-3)')
```

```bash
D=.superpowers/sdd/2026-11-07-spec2-w3
for f in supabase/migrations/20261107160000_dating_v2_setup_lists.sql supabase/migrations/20261107160010_dating_v2_setup_lists_grants.sql; do
  for run in 1 2; do psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f $f > /dev/null; echo "$(basename $f) run $run exit=$?"; done
done
psql -X -d attune_spec3a -Atc "select country_code, count(*) filter (where published_by = 'migration:dating_v2_setup_lists') from country_safety_config where country_code in ('GH','GB') group by 1 order by 1"
python3 -I $D/grants_line.py supabase/migrations/20261107150010_dating_v2_client_reads_grants.sql \
  "Spec 2 W3b: the setup lists RPC is the app's." \
  supabase/migrations/20261107160010_dating_v2_setup_lists_grants.sql
python3 -I $D/edit_contracts_T5.py
for f in dating_v2_setup_contracts dating_rls_canary country_safety_config_contracts dating_v2_client_reads_contracts; do
  psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/$f.sql > /dev/null 2>/tmp/w3b.err && echo "PASS $f" || echo "FAIL $f: $(grep -m1 ERROR /tmp/w3b.err)"
done; rm -f /tmp/w3b.err
```

Expected: four `exit=0`; `GB|1` and `GH|1` (the second run published nothing: R-19); the grants line; the three edit lines (`T5 canary`, `T5 GH and GB version pins (I-3)`, `T5 GB orphan probe (I-3)`); four `PASS` (verified on a clone, fix round 1). (W1b's `country_safety_config_contracts.sql` pinned GH's next version as 2 and put GB's version 1 back after its orphan probe; W3b's faith-list publish moves both on by one, so the pins read the version that was current, I-3.) (If `get_dating_setup_lists`'s `name_key`-sorted regions upset `get_dating_availability`'s unchanged contract, nothing in it changed: re-check the diff.)

- [ ] **Step 5: SQL mutants for W3b**

Create `$D/mut_T5b.py` with exactly:

```python
MUTS = {
 'lists_closed_countries': ("       WHERE c.is_current AND c.dating_enabled), '[]'::jsonb),", "       WHERE c.is_current), '[]'::jsonb),"),
 'lists_note_any_tier': ("    'note_country', CASE WHEN v_tier IN (1, 2) THEN v_phone_country END,", "    'note_country', v_phone_country,"),
 'lists_same_gender_raw': ("               'same_gender', coalesce(private.dating_same_gender_on(c.country_code::text), false),", "               'same_gender', c.same_gender_enabled,"),
 'lists_no_device': ("  IF public.dating_require_trusted_device() IS NOT TRUE THEN\n    RETURN jsonb_build_object('ok', false, 'reason', 'reverify_device');\n  END IF;\n", ""),
 'lists_open_flag_wrong': ("                          'open', c.open_regions IS NULL OR (r ->> 'code') = ANY (c.open_regions),", "                          'open', true,"),
}
```

```bash
D=.superpowers/sdd/2026-11-07-spec2-w3
python3 -I $D/mutate.py supabase/migrations/20261107160000_dating_v2_setup_lists.sql supabase/tests/dating_v2_setup_contracts.sql $D/mut_T5b.py $D/mut supabase/migrations/20261107160010_dating_v2_setup_lists_grants.sql | tee $D/mut_T5b.txt
```

Expected (verified, fix round 1): four `CONTRACT VIOLATED` lines from section N (`lists_note_any_tier` dies at `a 30-year-old with a Tier 3 phone reads note "GB"`: the section gives its person a UK phone, since the fixtures' +1 555 phones have no country); `lists_no_device` survives: W1c's pass-through device check makes it equivalent until W4b (record it as equivalent with that reason, and carry it to W4b's mutant list).

- [ ] **Step 6: The faith names**

Create `$D/arb_fragment_T5.txt` with exactly:

```
  "dating_faith_christian": "Christian", "dating_faith_muslim": "Muslim", "dating_faith_traditional": "Traditional",
  "dating_faith_hindu": "Hindu", "dating_faith_sikh": "Sikh", "dating_faith_jewish": "Jewish", "dating_faith_buddhist": "Buddhist",
  "dating_faith_other": "Other", "dating_faith_none": "None", "dating_faith_prefer_not_to_say": "Prefer not to say",
  "dating_denomination_catholic": "Catholic", "dating_denomination_anglican": "Anglican", "dating_denomination_methodist": "Methodist",
  "dating_denomination_presbyterian": "Presbyterian", "dating_denomination_pentecostal_charismatic": "Pentecostal or Charismatic",
  "dating_denomination_seventh_day_adventist": "Seventh-day Adventist", "dating_denomination_other_christian": "Other Christian",
  "dating_denomination_church_of_england_anglican": "Church of England or Anglican", "dating_denomination_orthodox": "Orthodox"
```

Create `$D/edit_T5.py` with exactly:

```python
import sys
sys.path.insert(0, '.superpowers/sdd/2026-11-07-spec2-w3')
from anchor import edit
names = ['christian', 'muslim', 'traditional', 'hindu', 'sikh', 'jewish', 'buddhist', 'other', 'none', 'prefer_not_to_say']
denoms = ['catholic', 'anglican', 'methodist', 'presbyterian', 'pentecostal_charismatic', 'seventh_day_adventist',
          'other_christian', 'church_of_england_anglican', 'orthodox']
lines = ''.join(f"  'dating_faith_{n}' => loc.dating_faith_{n},\n" for n in names)
lines += ''.join(f"  'dating_denomination_{d}' => loc.dating_denomination_{d},\n" for d in denoms)
edit('lib/features/dating/setup/dating_list_names.dart', [
    ("  // W3b (Task 5): faith and denomination names.\n", lines),
], 'T5 faith names')
```

```bash
D=.superpowers/sdd/2026-11-07-spec2-w3
python3 -I .superpowers/sdd/2026-10-26-spec1-w3/arb_append.py $D/arb_fragment_T5.txt
flutter gen-l10n --arb-dir=lib/i10n --template-arb-file=app_en.arb --output-dir=lib/i10n/generated --output-localization-file=app_localizations.dart --no-synthetic-package
python3 -I $D/edit_T5.py
```

Expected: `added 19 keys`; the edit line.

- [ ] **Step 7: The setup models, repository and providers (with their tests first)**

Create `test/features/dating/setup/dating_list_names_test.dart` with exactly:

```dart
// Spec 2 W3b: every name_key the config can send (W1b's regions and sides,
// W3b's faiths and denominations) has a name in the app.
import 'dart:io';

import 'package:attune/features/dating/setup/dating_list_names.dart';
import 'package:attune/i10n/generated/app_localizations_en.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every seeded and published name_key resolves', () {
    final loc = AppLocalizationsEn();
    final sql = [
      'supabase/migrations/20261106130000_dating_v2_country_config.sql',
      'supabase/migrations/20261107160000_dating_v2_setup_lists.sql',
    ].map((p) => File(p).readAsStringSync()).join('\n');
    final keys =
        RegExp(r'"name_key": "(dating_[a-z_]+)"')
            .allMatches(sql)
            .map((m) => m.group(1)!)
            .where((k) => !k.startsWith('dating_id_'))
            .toSet();
    expect(keys.length, 51);
    for (final key in keys) {
      expect(datingListName(loc, key), isNotNull, reason: key);
    }
  });
}
```

(`dating_id_*` are W4a's ID documents. 32 regions/sides + 10 faiths + 9 denominations = 51.)

Create `test/features/dating/setup/dating_setup_repository_test.dart` with exactly:

```dart
import 'package:attune/features/dating/setup/dating_setup_models.dart';
import 'package:attune/features/dating/setup/dating_setup_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../support/dating_fakes.dart';

void main() {
  test('the lists parse; a region knows whether it is open', () async {
    final s = ScriptedRpc([
      (_, __) => {
        'ok': true,
        'countries': [
          {
            'code': 'GH',
            'same_gender': false,
            'regions': [
              {
                'code': 'AA',
                'name_key': 'dating_region_gh_aa',
                'open': true,
                'sides': [
                  {'code': 'accra', 'name_key': 'dating_side_gh_accra'},
                ],
              },
              {
                'code': 'TV',
                'name_key': 'dating_region_gh_tv',
                'open': false,
                'sides': [],
              },
            ],
            'faiths': [
              {
                'code': 'christian',
                'name_key': 'dating_faith_christian',
                'denominations': [
                  {
                    'code': 'catholic',
                    'name_key': 'dating_denomination_catholic',
                  },
                ],
              },
            ],
          },
        ],
        'phone_country': 'GH',
        'note_country': 'GH',
        'default_ages': [25, 35],
      },
    ]);
    final lists = await DatingSetupRepository(s.rpc).lists();
    final gh = lists.country('GH')!;
    expect(gh.sameGender, isFalse);
    expect(gh.regions.map((r) => (r.code, r.open)), [
      ('AA', true),
      ('TV', false),
    ]);
    expect(gh.regions.first.sides.single.code, 'accra');
    expect(gh.faiths.single.denominations.single.code, 'catholic');
    expect(lists.noteCountry, 'GH');
    expect(lists.defaultAges, (25, 35));
    expect(s.calls.single.$1, 'get_dating_setup_lists');
  });

  test('D2 sends exactly the writer\'s parameters', () async {
    final s = ScriptedRpc([
      (_, __) => {'ok': true, 'next_step': 'where'},
    ]);
    final w = await DatingSetupRepository(s.rpc).saveIntention(
      'k-d2-000001',
      intention: 'marriage',
      timeline: 'few_years',
      timelineVisible: true,
      marital: 'divorced',
      maritalVisible: false,
    );
    expect(w.nextStep, 'where');
    // A record holding a Map compares the Map by identity: check each part.
    expect(s.calls.single.$1, 'save_dating_intention');
    expect(s.calls.single.$2, {
      'p_idempotency_key': 'k-d2-000001',
      'p_intention': 'marriage',
      'p_timeline': 'few_years',
      'p_timeline_visible': true,
      'p_attested': true,
      'p_marital': 'divorced',
      'p_marital_visible': false,
    });
  });

  test(
    'D4: three consents, then the enrolment, all under one key family',
    () async {
      final s = ScriptedRpc([
        (_, __) => null,
        (_, __) => null,
        (_, __) => null,
        (_, __) => {'state': 'profile_draft'},
      ]);
      final w = await DatingSetupRepository(s.rpc).agreeAndBegin('k-d4-000001');
      expect(w.ok, isTrue);
      expect(w.nextStep, 'you');
      expect(s.calls.map((c) => c.$1), [
        'record_dating_consent',
        'record_dating_consent',
        'record_dating_consent',
        'begin_dating_enrollment',
      ]);
      expect(s.calls.take(3).map((c) => c.$2!['p_purpose']), [
        'dating_terms',
        'dating_opt_in',
        'special_category_profile',
      ]);
      expect(
        s.calls.take(3).map((c) => c.$2!['p_idempotency_key']).toSet().length,
        3,
      );
      expect(s.calls.last.$2, {
        'p_terms_version': 'dating-2.0',
        'p_idempotency_key': 'k-d4-000001:begin',
      });
    },
  );

  test('D4 refused: its message is the reason', () async {
    final s = ScriptedRpc([
      (_, __) => PostgrestException(message: 'reverify_device', code: '22023'),
    ]);
    final w = await DatingSetupRepository(s.rpc).agreeAndBegin('k-d4-000002');
    expect(w.ok, isFalse);
    expect(w.reason, 'reverify_device');
  });

  test('D8: the faith consent, then the faith; Skip is the clear', () async {
    final s = ScriptedRpc([
      (_, __) => null,
      (_, __) => {'ok': true, 'next_step': 'photos'},
      (_, __) => {'ok': true, 'next_step': 'photos'},
    ]);
    final repo = DatingSetupRepository(s.rpc);
    await repo.saveFaith(
      'k-d8-000001',
      faith: 'christian',
      denomination: null,
      importance: 'must_share',
      visible: false,
    );
    await repo.clearFaith('k-d8-000002');
    expect(s.calls.map((c) => c.$1), [
      'record_dating_consent',
      'save_dating_faith',
      'clear_dating_faith',
    ]);
    expect(s.calls.first.$2!['p_purpose'], 'special_category_faith');
  });

  test('a busy server is busy, never ok', () async {
    final s = ScriptedRpc([
      (_, __) => PostgrestException(message: 'dating:busy', code: '55P03'),
      (_, __) => PostgrestException(message: 'dating:busy', code: '55P03'),
    ]);
    final w = await DatingSetupRepository(s.rpc).saveChildren(
      'k-d7-000001',
      have: true,
      want: 'open',
      mustMatch: false,
      excludeParents: false,
    );
    expect(w.reason, 'busy');
  });

  test(
    'my profile: a missing profile is empty, never another account\'s',
    () async {
      final s = ScriptedRpc([
        (_, __) => {'ok': true, 'profile': null},
      ]);
      expect(
        await DatingSetupRepository(s.rpc).myProfile(),
        const DatingMyProfile(),
      );
    },
  );
}
```

Create `lib/features/dating/setup/dating_setup_models.dart` with exactly:

```dart
// Spec 2 W3b (§3.2 D2-D8): the setup lists (get_dating_setup_lists) and the
// person's own answers (get_my_dating_profile), in memory only.

class DatingOption {
  const DatingOption({required this.code, required this.nameKey});

  final String code;
  final String nameKey;

  static List<DatingOption> listOf(Object? raw) => [
    if (raw is List)
      for (final o in raw.whereType<Map>())
        if (o['code'] is String && o['name_key'] is String)
          DatingOption(
            code: o['code'] as String,
            nameKey: o['name_key'] as String,
          ),
  ];
}

class DatingRegion {
  const DatingRegion({
    required this.code,
    required this.nameKey,
    required this.open,
    this.sides = const [],
  });

  final String code;
  final String nameKey;
  final bool open;
  final List<DatingOption> sides;
}

class DatingFaith {
  const DatingFaith({
    required this.code,
    required this.nameKey,
    this.denominations = const [],
  });

  final String code;
  final String nameKey;
  final List<DatingOption> denominations;
}

class DatingCountryLists {
  const DatingCountryLists({
    required this.code,
    required this.sameGender,
    this.regions = const [],
    this.faiths = const [],
  });

  final String code;
  final bool sameGender;
  final List<DatingRegion> regions;
  final List<DatingFaith> faiths;

  DatingRegion? region(String? code) {
    for (final r in regions) {
      if (r.code == code) return r;
    }
    return null;
  }
}

class DatingSetupLists {
  const DatingSetupLists({
    this.countries = const [],
    this.phoneCountry,
    this.noteCountry,
    this.defaultAges = (18, 99),
  });

  final List<DatingCountryLists> countries;
  final String? phoneCountry;
  final String? noteCountry;
  final (int, int) defaultAges;

  DatingCountryLists? country(String? code) {
    for (final c in countries) {
      if (c.code == code) return c;
    }
    return null;
  }

  factory DatingSetupLists.fromJson(Map<String, dynamic> json) {
    final ages = json['default_ages'];
    return DatingSetupLists(
      countries: [
        if (json['countries'] is List)
          for (final c in (json['countries'] as List).whereType<Map>())
            if (c['code'] is String)
              DatingCountryLists(
                code: c['code'] as String,
                sameGender: c['same_gender'] == true,
                regions: [
                  if (c['regions'] is List)
                    for (final r in (c['regions'] as List).whereType<Map>())
                      if (r['code'] is String && r['name_key'] is String)
                        DatingRegion(
                          code: r['code'] as String,
                          nameKey: r['name_key'] as String,
                          open: r['open'] == true,
                          sides: DatingOption.listOf(r['sides']),
                        ),
                ],
                faiths: [
                  if (c['faiths'] is List)
                    for (final f in (c['faiths'] as List).whereType<Map>())
                      if (f['code'] is String && f['name_key'] is String)
                        DatingFaith(
                          code: f['code'] as String,
                          nameKey: f['name_key'] as String,
                          denominations: DatingOption.listOf(
                            f['denominations'],
                          ),
                        ),
                ],
              ),
      ],
      phoneCountry:
          json['phone_country'] is String
              ? json['phone_country'] as String
              : null,
      noteCountry:
          json['note_country'] is String
              ? json['note_country'] as String
              : null,
      defaultAges:
          ages is List && ages.length == 2 && ages[0] is int && ages[1] is int
              ? (ages[0] as int, ages[1] as int)
              : (18, 99),
    );
  }
}

/// The person's own answers (get_my_dating_profile), for prefilling a step.
class DatingMyProfile {
  const DatingMyProfile({
    this.intention,
    this.marriageTimeline,
    this.timelineVisible = true,
    this.attested = false,
    this.marital,
    this.maritalVisible = false,
    this.countryCode,
    this.regionCode,
    this.sideCode,
    this.regionScope,
    this.identity,
    this.specific,
    this.specificText,
    this.pronouns,
    this.pools = const [],
    this.genderVisible = false,
    this.seeking = const [],
    this.minAge,
    this.maxAge,
    this.childrenHave,
    this.childrenWant,
    this.wantMustMatch = false,
    this.excludeParents = false,
    this.faith,
    this.denomination,
    this.importance,
    this.faithVisible = false,
    this.displayName,
    this.prompts = const [],
    this.dropTime,
    this.digestPush = false,
    this.chatPush = true,
    this.dataSaver = false,
    this.photosAfterMutual = false,
  });

  final String? intention;
  final String? marriageTimeline;
  final bool timelineVisible;
  final bool attested;
  final String? marital;
  final bool maritalVisible;
  final String? countryCode;
  final String? regionCode;
  final String? sideCode;
  final String? regionScope;
  final String? identity;
  final String? specific;
  final String? specificText;
  final String? pronouns;
  final List<String> pools;
  final bool genderVisible;
  final List<String> seeking;
  final int? minAge;
  final int? maxAge;
  final bool? childrenHave;
  final String? childrenWant;
  final bool wantMustMatch;
  final bool excludeParents;
  final String? faith;
  final String? denomination;
  final String? importance;
  final bool faithVisible;
  final String? displayName;
  final List<(String, String)> prompts;
  final String? dropTime;
  final bool digestPush;
  final bool chatPush;
  final bool dataSaver;
  final bool photosAfterMutual;

  factory DatingMyProfile.fromJson(Map<String, dynamic> p) {
    String? text(Object? v) => v is String ? v : null;
    Map<dynamic, dynamic> map(Object? v) => v is Map ? v : const {};
    List<String> strings(Object? v) =>
        v is List ? v.whereType<String>().toList() : const [];
    final identity = map(p['identity']);
    final faith = map(p['faith']);
    final prefs = map(p['preferences']);
    final settings = map(p['settings']);
    return DatingMyProfile(
      intention: text(p['intention']),
      marriageTimeline: text(p['marriage_timeline']),
      timelineVisible: p['timeline_visible'] != false,
      attested: p['attested'] == true,
      marital: text(p['marital']),
      maritalVisible: p['marital_visible'] == true,
      countryCode: text(p['country_code']),
      regionCode: text(p['region_code']),
      sideCode: text(p['side_code']),
      regionScope: text(prefs['region_scope']),
      identity: text(identity['identity']),
      specific: text(identity['specific']),
      specificText: text(identity['specific_text']),
      pronouns: text(identity['pronouns']),
      pools: strings(identity['pools']),
      genderVisible: p['gender_visible'] == true,
      seeking: strings(p['seeking']),
      minAge: prefs['min_age'] is int ? prefs['min_age'] as int : null,
      maxAge: prefs['max_age'] is int ? prefs['max_age'] as int : null,
      childrenHave:
          p['children_have'] is bool ? p['children_have'] as bool : null,
      childrenWant: text(p['children_want']),
      wantMustMatch: prefs['want_must_match'] == true,
      excludeParents: prefs['exclude_parents'] == true,
      faith: text(faith['faith']),
      denomination: text(faith['denomination']),
      importance: text(faith['importance']),
      faithVisible: p['faith_visible'] == true,
      displayName: text(p['display_name']),
      prompts: [
        if (p['prompts'] is List)
          for (final q in (p['prompts'] as List).whereType<Map>())
            if (q['prompt_id'] is String && q['answer'] is String)
              (q['prompt_id'] as String, q['answer'] as String),
      ],
      dropTime: text(settings['drop_time']),
      digestPush: settings['digest_push'] == true,
      chatPush: settings['chat_push'] != false,
      dataSaver: settings['data_saver'] == true,
      photosAfterMutual: p['photos_after_mutual'] == true,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is DatingMyProfile && other.toString() == toString();

  @override
  int get hashCode => toString().hashCode;

  @override
  String toString() =>
      'DatingMyProfile($intention,$countryCode,$regionCode,$identity,$seeking,$faith)';
}
```

Create `lib/features/dating/setup/dating_setup_repository.dart` with exactly:

```dart
// Spec 2 W3b-W3c (§3.2, §4.4 Setup writers): every setup read and write,
// RPC-only. Each writer answers DatingWrite ({ok, next_step} or a reason);
// D4's three consents and the enrolment are one step. Keys come from the
// screen (one per action until it goes, Fable H3c).
import 'package:attune/features/dating/data/dating_rpc.dart';
import 'package:attune/features/dating/setup/dating_setup_models.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The consents' policy version (§3.2 D4).
const datingPolicyVersion = 'dating-2.0';

abstract class DatingSetupGateway {
  Future<DatingSetupLists> lists();
  Future<DatingMyProfile> myProfile();
  Future<DatingWrite> saveIntention(
    String key, {
    required String intention,
    String? timeline,
    required bool timelineVisible,
    String? marital,
    required bool maritalVisible,
  });
  Future<DatingWrite> saveLocation(
    String key, {
    required String country,
    required String region,
    String? side,
    required String scope,
  });
  Future<DatingWrite> agreeAndBegin(String key);
  Future<DatingWrite> saveIdentity(
    String key, {
    required String identity,
    String? specific,
    String? pronouns,
    List<String> extraPools = const [],
    required bool visible,
  });
  Future<DatingWrite> saveWhoToMeet(
    String key, {
    required List<String> seeking,
    required int minAge,
    required int maxAge,
  });
  Future<DatingWrite> saveChildren(
    String key, {
    required bool have,
    required String want,
    required bool mustMatch,
    required bool excludeParents,
  });
  Future<DatingWrite> saveFaith(
    String key, {
    required String faith,
    String? denomination,
    required String importance,
    required bool visible,
  });
  Future<DatingWrite> clearFaith(String key);
  Future<DatingWrite> savePrompts(String key, List<(String, String)> items);
  Future<DatingWrite> saveDisplayName(String key, String name);
  Future<DatingWrite> saveSettings(String key, Map<String, Object> values);
}

class DatingSetupRepository implements DatingSetupGateway {
  DatingSetupRepository(this._rpc);

  final DatingRpc _rpc;

  @override
  Future<DatingSetupLists> lists() async {
    final json = Map<String, dynamic>.from(
      await _rpc.call('get_dating_setup_lists') as Map,
    );
    if (json['ok'] != true) throw StateError('lists:${json['reason']}');
    return DatingSetupLists.fromJson(json);
  }

  @override
  Future<DatingMyProfile> myProfile() async {
    final json = Map<String, dynamic>.from(
      await _rpc.call('get_my_dating_profile') as Map,
    );
    if (json['ok'] != true) throw StateError('profile:${json['reason']}');
    final profile = json['profile'];
    return profile is Map
        ? DatingMyProfile.fromJson(Map<String, dynamic>.from(profile))
        : const DatingMyProfile();
  }

  @override
  Future<DatingWrite> saveIntention(
    String key, {
    required String intention,
    String? timeline,
    required bool timelineVisible,
    String? marital,
    required bool maritalVisible,
  }) => datingWrite(
    () => _rpc.call('save_dating_intention', {
      'p_idempotency_key': key,
      'p_intention': intention,
      'p_timeline': intention == 'marriage' ? timeline : null,
      'p_timeline_visible': timelineVisible,
      // The screen sends only after the box is ticked (§3.2 D2).
      'p_attested': true,
      'p_marital': marital,
      'p_marital_visible': maritalVisible,
    }),
  );

  @override
  Future<DatingWrite> saveLocation(
    String key, {
    required String country,
    required String region,
    String? side,
    required String scope,
  }) => datingWrite(
    () => _rpc.call('save_dating_location', {
      'p_idempotency_key': key,
      'p_country': country,
      'p_region': region,
      'p_side': side,
      'p_scope': scope,
    }),
  );

  @override
  Future<DatingWrite> agreeAndBegin(String key) async {
    try {
      for (final purpose in const [
        'dating_terms',
        'dating_opt_in',
        'special_category_profile',
      ]) {
        await _rpc.call('record_dating_consent', {
          'p_idempotency_key': '$key:$purpose',
          'p_purpose': purpose,
          'p_action': 'granted',
          'p_policy_version': datingPolicyVersion,
          'p_categories':
              purpose == 'special_category_profile'
                  ? ['gender', 'who_to_meet']
                  : <String>[],
        });
      }
      await _rpc.call('begin_dating_enrollment', {
        'p_terms_version': datingPolicyVersion,
        'p_idempotency_key': '$key:begin',
      });
      return const DatingWrite(ok: true, nextStep: 'you');
    } on DatingBusy {
      return DatingWrite.busy;
    } on PostgrestException catch (e) {
      return DatingWrite(ok: false, reason: e.message);
    } catch (_) {
      return DatingWrite.failed;
    }
  }

  @override
  Future<DatingWrite> saveIdentity(
    String key, {
    required String identity,
    String? specific,
    String? pronouns,
    List<String> extraPools = const [],
    required bool visible,
  }) => datingWrite(
    () => _rpc.call('save_dating_identity', {
      'p_idempotency_key': key,
      'p_identity': identity,
      'p_specific': specific,
      'p_pronouns': pronouns,
      'p_extra_pools': extraPools,
      'p_visible': visible,
    }),
  );

  @override
  Future<DatingWrite> saveWhoToMeet(
    String key, {
    required List<String> seeking,
    required int minAge,
    required int maxAge,
  }) => datingWrite(
    () => _rpc.call('save_dating_who_to_meet', {
      'p_idempotency_key': key,
      'p_seeking': seeking,
      'p_min_age': minAge,
      'p_max_age': maxAge,
    }),
  );

  @override
  Future<DatingWrite> saveChildren(
    String key, {
    required bool have,
    required String want,
    required bool mustMatch,
    required bool excludeParents,
  }) => datingWrite(
    () => _rpc.call('save_dating_children', {
      'p_idempotency_key': key,
      'p_have': have,
      'p_want': want,
      'p_must_match': mustMatch,
      'p_exclude_parents': excludeParents,
    }),
  );

  @override
  Future<DatingWrite> saveFaith(
    String key, {
    required String faith,
    String? denomination,
    required String importance,
    required bool visible,
  }) async {
    try {
      await _rpc.call('record_dating_consent', {
        'p_idempotency_key': '$key:consent',
        'p_purpose': 'special_category_faith',
        'p_action': 'granted',
        'p_policy_version': datingPolicyVersion,
        'p_categories': ['faith'],
      });
    } on DatingBusy {
      return DatingWrite.busy;
    } on PostgrestException catch (e) {
      return DatingWrite(ok: false, reason: e.message);
    } catch (_) {
      return DatingWrite.failed;
    }
    return datingWrite(
      () => _rpc.call('save_dating_faith', {
        'p_idempotency_key': key,
        'p_faith': faith,
        'p_denomination': denomination,
        'p_importance': importance,
        'p_visible': visible,
      }),
    );
  }

  @override
  Future<DatingWrite> clearFaith(String key) => datingWrite(
    () => _rpc.call('clear_dating_faith', {'p_idempotency_key': key}),
  );

  @override
  Future<DatingWrite> savePrompts(String key, List<(String, String)> items) =>
      datingWrite(
        () => _rpc.call('save_dating_prompts', {
          'p_idempotency_key': key,
          'p_items': [
            for (final (id, answer) in items)
              {'prompt_id': id, 'answer': answer},
          ],
        }),
      );

  @override
  Future<DatingWrite> saveDisplayName(String key, String name) => datingWrite(
    () => _rpc.call('save_dating_display_name', {
      'p_idempotency_key': key,
      'p_name': name,
    }),
  );

  @override
  Future<DatingWrite> saveSettings(String key, Map<String, Object> values) =>
      datingWrite(
        () => _rpc.call('save_dating_settings', {
          'p_idempotency_key': key,
          'p_values': values,
        }),
      );
}
```

Create `lib/features/dating/setup/dating_setup_providers.dart` with exactly:

```dart
// Spec 2 W3b (D8): the setup lists and the person's own answers, one entry
// per account, memory only, disposed with the step that shows them.
import 'package:attune/features/dating/data/dating_providers.dart';
import 'package:attune/features/dating/setup/dating_setup_models.dart';
import 'package:attune/features/dating/setup/dating_setup_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final datingSetupGatewayProvider = Provider<DatingSetupGateway>(
  (ref) => DatingSetupRepository(ref.watch(datingRpcProvider)),
);

final datingSetupListsProvider = FutureProvider.autoDispose
    .family<DatingSetupLists, String?>((ref, account) async {
      if (account == null) return const DatingSetupLists();
      return ref.read(datingSetupGatewayProvider).lists();
    });

final datingMyProfileProvider = FutureProvider.autoDispose
    .family<DatingMyProfile, String?>((ref, account) async {
      if (account == null) return const DatingMyProfile();
      return ref.read(datingSetupGatewayProvider).myProfile();
    });
```

Create `test/features/dating/support/dating_setup_fakes.dart` with exactly:

```dart
// Spec 2 W3b: an in-memory setup gateway; every call is recorded, and a
// test can make any call fail the test (the off-country no-call proof).
import 'dart:async';

import 'package:attune/features/dating/data/dating_rpc.dart';
import 'package:attune/features/dating/setup/dating_setup_models.dart';
import 'package:attune/features/dating/setup/dating_setup_repository.dart';

const ghanaLists = DatingSetupLists(
  countries: [
    DatingCountryLists(
      code: 'GB',
      sameGender: true,
      regions: [
        DatingRegion(code: 'TLI', nameKey: 'dating_region_gb_tli', open: true),
        DatingRegion(code: 'TLM', nameKey: 'dating_region_gb_tlm', open: true),
      ],
      faiths: [
        DatingFaith(
          code: 'christian',
          nameKey: 'dating_faith_christian',
          denominations: [
            DatingOption(
              code: 'catholic',
              nameKey: 'dating_denomination_catholic',
            ),
          ],
        ),
        DatingFaith(code: 'none', nameKey: 'dating_faith_none'),
      ],
    ),
    DatingCountryLists(
      code: 'GH',
      sameGender: false,
      regions: [
        DatingRegion(
          code: 'AA',
          nameKey: 'dating_region_gh_aa',
          open: true,
          sides: [
            DatingOption(code: 'accra', nameKey: 'dating_side_gh_accra'),
            DatingOption(code: 'tema', nameKey: 'dating_side_gh_tema'),
          ],
        ),
        DatingRegion(code: 'AH', nameKey: 'dating_region_gh_ah', open: true),
        DatingRegion(code: 'TV', nameKey: 'dating_region_gh_tv', open: false),
      ],
      faiths: [
        DatingFaith(
          code: 'christian',
          nameKey: 'dating_faith_christian',
          denominations: [
            DatingOption(
              code: 'catholic',
              nameKey: 'dating_denomination_catholic',
            ),
            DatingOption(
              code: 'methodist',
              nameKey: 'dating_denomination_methodist',
            ),
          ],
        ),
        DatingFaith(code: 'muslim', nameKey: 'dating_faith_muslim'),
      ],
    ),
  ],
  phoneCountry: 'GH',
  defaultAges: (25, 35),
);

class FakeDatingSetupGateway implements DatingSetupGateway {
  FakeDatingSetupGateway({
    this.profile = const DatingMyProfile(),
    this.listsValue = ghanaLists,
  });

  DatingMyProfile profile;
  DatingSetupLists listsValue;
  final calls = <(String, Map<String, Object?>)>[];
  DatingWrite answer = const DatingWrite(ok: true);
  Completer<DatingMyProfile>? holdProfile;

  /// Called before every write; throw (or fail) to forbid a call.
  void Function(String name, Map<String, Object?> args)? guard;

  Future<DatingWrite> _w(
    String name,
    Map<String, Object?> args,
    String next,
  ) async {
    guard?.call(name, args);
    calls.add((name, args));
    return answer.ok ? DatingWrite(ok: true, nextStep: next) : answer;
  }

  @override
  Future<DatingSetupLists> lists() async {
    calls.add(('lists', const {}));
    return listsValue;
  }

  @override
  Future<DatingMyProfile> myProfile() async {
    calls.add(('myProfile', const {}));
    final hold = holdProfile;
    if (hold != null) return hold.future;
    return profile;
  }

  @override
  Future<DatingWrite> saveIntention(
    String key, {
    required String intention,
    String? timeline,
    required bool timelineVisible,
    String? marital,
    required bool maritalVisible,
  }) => _w('saveIntention', {
    'key': key,
    'intention': intention,
    'timeline': timeline,
    'timelineVisible': timelineVisible,
    'marital': marital,
    'maritalVisible': maritalVisible,
  }, 'where');

  @override
  Future<DatingWrite> saveLocation(
    String key, {
    required String country,
    required String region,
    String? side,
    required String scope,
  }) => _w('saveLocation', {
    'key': key,
    'country': country,
    'region': region,
    'side': side,
    'scope': scope,
  }, 'privacy');

  @override
  Future<DatingWrite> agreeAndBegin(String key) =>
      _w('agreeAndBegin', {'key': key}, 'you');

  @override
  Future<DatingWrite> saveIdentity(
    String key, {
    required String identity,
    String? specific,
    String? pronouns,
    List<String> extraPools = const [],
    required bool visible,
  }) => _w('saveIdentity', {
    'key': key,
    'identity': identity,
    'specific': specific,
    'pronouns': pronouns,
    'extraPools': extraPools,
    'visible': visible,
  }, 'meet');

  @override
  Future<DatingWrite> saveWhoToMeet(
    String key, {
    required List<String> seeking,
    required int minAge,
    required int maxAge,
  }) => _w('saveWhoToMeet', {
    'key': key,
    'seeking': seeking,
    'minAge': minAge,
    'maxAge': maxAge,
  }, 'children');

  @override
  Future<DatingWrite> saveChildren(
    String key, {
    required bool have,
    required String want,
    required bool mustMatch,
    required bool excludeParents,
  }) => _w('saveChildren', {
    'key': key,
    'have': have,
    'want': want,
    'mustMatch': mustMatch,
    'excludeParents': excludeParents,
  }, 'faith');

  @override
  Future<DatingWrite> saveFaith(
    String key, {
    required String faith,
    String? denomination,
    required String importance,
    required bool visible,
  }) => _w('saveFaith', {
    'key': key,
    'faith': faith,
    'denomination': denomination,
    'importance': importance,
    'visible': visible,
  }, 'photos');

  @override
  Future<DatingWrite> clearFaith(String key) =>
      _w('clearFaith', {'key': key}, 'photos');

  @override
  Future<DatingWrite> savePrompts(String key, List<(String, String)> items) =>
      _w('savePrompts', {'key': key, 'items': items}, 'verify');

  @override
  Future<DatingWrite> saveDisplayName(String key, String name) =>
      _w('saveDisplayName', {'key': key, 'name': name}, 'preview');

  @override
  Future<DatingWrite> saveSettings(String key, Map<String, Object> values) =>
      _w('saveSettings', {'key': key, 'values': values}, '');

  /// The last write (a re-read of the profile after a save is no write).
  (String, Map<String, Object?>) get lastWrite =>
      calls.lastWhere((c) => c.$1 != 'lists' && c.$1 != 'myProfile');

  Iterable<String> get writes =>
      calls.map((c) => c.$1).where((n) => n != 'lists' && n != 'myProfile');
}
```

```bash
dart format lib/features/dating/setup/dating_setup_models.dart lib/features/dating/setup/dating_setup_repository.dart lib/features/dating/setup/dating_setup_providers.dart test/features/dating/setup test/features/dating/support/dating_setup_fakes.dart
flutter analyze --no-pub lib/features/dating test/features/dating 2>&1 | tail -1
flutter test test/features/dating/setup 2>&1 | tail -1
```

Expected (verified, fix round 1): `Formatted …` (this task's new files only; `dating_list_names.dart`, edited at its marker, is not formatted again); `No issues found!`; `All tests passed!` (10 tests: the two Task 4 tests and the eight here).

- [ ] **Step 8: Do not commit; record the tree in the report** (with the mutant files and the suite: `$D/suite.sh attune_spec3a` → `159 PASS, 14 FAIL`, no new FAIL).

### Task 6: The step frame and D1–D4 (§3.0, §3.2 D1–D4, §3.15 rows D1–D4; R-16, R-20, R-31; D8)

**Files:**
- Create: `lib/features/dating/setup/dating_step_frame.dart`, `lib/features/dating/setup/dating_picker_sheet.dart`, `lib/features/dating/setup/how_step.dart`, `lib/features/dating/setup/looking_for_step.dart`, `lib/features/dating/setup/where_step.dart`, `lib/features/dating/setup/privacy_step.dart`, `test/features/dating/setup/d1_d4_test.dart` (+ goldens), `$D/{arb_fragment_T6.txt, edit_T6.py, mut_T6.py}`
- Modify: `lib/features/dating/routes/dating_setup_steps.dart` (four cases), `lib/i10n/app_en.arb` + generated

**Interfaces:**
- Consumes: Task 5's gateway, models and providers; Task 4's `DatingNotOpenScreen`, `datingCountryName`, `datingOpenList`, `datingRegionName`, `datingOpenRegionNames`, `datingListName`; Task 1's `DatingActionKeys`, `DatingWrite`, `datingHomeProvider`, `datingAvailabilityProvider`, `datingHomeGatewayProvider`; Spec 1's `switchPath`, `deviceCountryProvider`, `showTermsSheet`, `showPrivacySheet`.
- Produces: `DatingStepFrame({required String step, required String title, String? hint, required Widget body, required VoidCallback onBack, Widget? primary, List<Widget> more, VoidCallback? onSkip})`; `DatingOfflineBanner`; `DatingChoiceGroup<T>({required String label, required List<(T, String)> options, required T? value, required ValueChanged<T>? onChanged})`; `String datingWriteError(AppLocalizations, DatingWrite)`; `mixin DatingStepState<W extends ConsumerStatefulWidget> on ConsumerState<W>` (`keys`, `saving`, `refusal`, `resetAnswers()`, `seedAnswers(DatingMyProfile)`, `DatingMyProfile? watchProfile()`, `Future<void> write(String action, Object payload, Future<DatingWrite> Function(String key) call, void Function(DatingWrite) onSaved)`); `Future<T?> showDatingPicker<T>(BuildContext, {required String title, required List<(T, String)> items, T? selected})`; `DatingHowStep`, `DatingLookingForStep`, `DatingWhereStep`, `DatingPrivacyStep` (each `({required DatingStepNav nav})`).

- [ ] **Step 1: The strings**

Create `$D/arb_fragment_T6.txt` with exactly (spec copy verbatim; the four marked "(plan)" are this plan's and go to the reviewers):

```
  "dating_stepOf": "Step {n} of {total}",
  "@dating_stepOf": {"description": "Spec 2 §3.0 progress.", "placeholders": {"n": {"type": "int"}, "total": {"type": "int"}}},
  "dating_skip": "Skip",
  "@dating_skip": {"description": "Spec 2 §3.0: bottom-left where allowed."},
  "dating_continue": "Continue",
  "@dating_continue": {"description": "A setup step's primary."},
  "dating_notAvailableHere": "This choice isn't available here.",
  "@dating_notAvailableHere": {"description": "Spec 2 §3.15 D5: a modified-client refusal."},
  "dating_contactFilter": "Contact details can't go on your profile. You can swap them in a chat when you're both ready.",
  "@dating_contactFilter": {"description": "Spec 2 §3.2 D10 contact filter (also D5's own words)."},
  "dating_kindnessFilter": "Please rephrase this so it's kind to everyone.",
  "@dating_kindnessFilter": {"description": "Spec 2 §3.2 D10 kindness filter."},
  "dating_countryChangeLimited": "You can change your Dating country once every 30 days.",
  "@dating_countryChangeLimited": {"description": "D3 refused: country_change_limited (plan; §3.2 D3 rule)."},

  "dating_howTitle": "How Dating works",
  "@dating_howTitle": {"description": "Spec 2 §3.2 D1."},
  "dating_how1": "Up to 3 introductions a day, at a time you choose.",
  "@dating_how1": {"description": "D1 item 1."},
  "dating_how2": "Saying 'Interested' is private. You only match when you're both interested.",
  "@dating_how2": {"description": "D1 item 2."},
  "dating_how3": "Dating chats are separate from the rest of Attune. Phone numbers stay hidden until you both choose to swap.",
  "@dating_how3": {"description": "D1 item 3."},
  "dating_how4": "Before your first introduction, a short video selfie checks your age and that your photos are you. The video is deleted straight away.",
  "@dating_how4": {"description": "D1 item 4 (also D11's shell until W4a)."},
  "dating_how5": "You'll add at least 2 photos and answer 2 short questions.",
  "@dating_how5": {"description": "D1 item 5."},
  "dating_how6": "Your first introductions can arrive from {date}.",
  "@dating_how6": {"description": "D1 item 6; {date} in full words.", "placeholders": {"date": {"type": "String"}}},
  "dating_how7": "Dating is open in {countries}.",
  "@dating_how7": {"description": "D1 item 7, built from get_dating_availability.", "placeholders": {"countries": {"type": "String"}}},
  "dating_how8": "Setting up uses about 15 MB of data, mostly for the video check.",
  "@dating_how8": {"description": "D1 item 8 (measured on the W10 device matrix)."},
  "dating_setUpLater": "Set up later",
  "@dating_setUpLater": {"description": "D1 tertiary."},
  "dating_justMeDone": "You're on 'Just for me'.",
  "@dating_justMeDone": {"description": "D1 snackbar after Not ready? (with Undo)."},
  "dating_undo": "Undo",
  "@dating_undo": {"description": "Undo."},

  "dating_lookingTitle": "What are you looking for?",
  "@dating_lookingTitle": {"description": "Spec 2 §3.2 D2."},
  "dating_intentMarriage": "Marriage", "dating_intentCommitted": "A committed relationship",
  "dating_intentCompanionship": "Companionship, at my own pace", "dating_intentNotSure": "Not sure yet",
  "dating_timelineQ": "When would you like to marry?",
  "dating_timelineSoon": "In the next year or two", "dating_timelineFew": "In a few years", "dating_timelineNone": "No set time",
  "dating_timelineShow": "Show this on my profile",
  "dating_attestation": "I'm not married in any form (customary, religious or civil), I'm not separated from a spouse, and I'm not in a relationship.",
  "@dating_attestation": {"description": "D2 attestation (cultural reviewer, W3 gate)."},
  "dating_attestationHelper": "Dating on Attune is for people who are free to start a relationship.",
  "dating_attestationError": "Please confirm you're free to start a relationship.",
  "dating_separatedLink": "I'm separated but not divorced",
  "dating_separatedSheet": "Dating isn't open to you yet. Once your divorce is final, you're welcome here. Attune just for me is open to you now.",
  "dating_marriedBefore": "Married before? (optional)",
  "dating_maritalNever": "Never", "dating_maritalDivorced": "Divorced", "dating_maritalWidowed": "Widowed",
  "dating_maritalShow": "Show on my profile",

  "dating_whereTitle": "Where are you?",
  "@dating_whereTitle": {"description": "Spec 2 §3.2 D3."},
  "dating_countryLabel": "Country", "dating_regionLabel": "Region",
  "dating_countryNotListed": "My country isn't listed",
  "dating_regionClosed": "Dating is open in {regions} for now. We're opening other regions as soon as we can look after them well.",
  "@dating_regionClosed": {"description": "D3 closed region, inline.", "placeholders": {"regions": {"type": "String"}}},
  "dating_sideLabel": "Which side of {region}? (optional)",
  "@dating_sideLabel": {"description": "D3 side.", "placeholders": {"region": {"type": "String"}}},
  "dating_sideEither": "Either side",
  "@dating_sideEither": {"description": "D3: no side chosen (plan)."},
  "dating_scopeQ": "How far would you like to meet people?",
  "dating_scopeSide": "My side", "dating_scopeRegion": "My region",
  "dating_scopeCountry": "Anywhere in {country}",
  "@dating_scopeCountry": {"description": "D3 scope.", "placeholders": {"country": {"type": "String"}}},
  "dating_abroadRow": "Also open to people in other countries",
  "dating_abroadDisabled": "Available once you're verified and your account is 14 days old.",
  "dating_whereHelper": "We never use your exact location. Others see your region only.",
  "dating_search": "Search",
  "@dating_search": {"description": "A searchable picker's field (plan)."},
  "dating_choose": "Choose",
  "@dating_choose": {"description": "A picker row with nothing chosen yet (plan)."},

  "dating_privacyTitle": "Your answers stay private",
  "@dating_privacyTitle": {"description": "Spec 2 §3.2 D4."},
  "dating_privacyWhyHead": "Why we ask", "dating_privacyWhoHead": "Who sees what", "dating_privacyNeverHead": "What we never do",
  "dating_privacyProtectedHead": "How it's protected", "dating_privacyLeavingHead": "Leaving",
  "dating_privacyWhy": "The next questions are about you and who you'd like to meet. We use your answers only to introduce you to people who'd like to meet you too.",
  "dating_privacyWho": "Nobody ever sees who you'd like to meet. Your gender, faith and marriage history appear on your profile only if you choose. We never collect your exact location.",
  "dating_privacyNever": "Nothing from your journal, quizzes or Healing is used to introduce you. Your answers are never used for ads, never sold, and never read by AI.",
  "dating_privacyProtected": "These answers are stored encrypted. The people who review reports can't see them.",
  "dating_privacyLeaving": "You can leave Dating at any time, and these answers are deleted.",
  "dating_privacyConsent": "I agree that Attune can use my answers about my gender and who I'd like to meet to introduce me.",
  "dating_datingTerms": "Dating terms", "dating_privacyNotice": "Privacy notice", "dating_agreeContinue": "Agree and continue"
```

```bash
D=.superpowers/sdd/2026-11-07-spec2-w3
python3 -I .superpowers/sdd/2026-10-26-spec1-w3/arb_append.py $D/arb_fragment_T6.txt
flutter gen-l10n --arb-dir=lib/i10n --template-arb-file=app_en.arb --output-dir=lib/i10n/generated --output-localization-file=app_localizations.dart --no-synthetic-package
```

Expected: `added 70 keys`.

- [ ] **Step 2: Write the failing tests**

Create `test/features/dating/setup/d1_d4_test.dart` with exactly:

```dart
// Spec 2 W3b (§3.2 D1-D4, §3.0, §3.15): the first four setup screens.
import 'dart:async';
import 'dart:ui' show SemanticsFlag;

import 'package:attune/core/platform/sim_country.dart';
import 'package:attune/features/dating/data/dating_home.dart';
import 'package:attune/features/dating/data/dating_rpc.dart';
import 'package:attune/features/dating/routes/dating_setup_steps.dart';
import 'package:attune/features/dating/setup/dating_setup_models.dart';
import 'package:attune/features/dating/setup/dating_setup_providers.dart';
import 'package:attune/features/dating/setup/how_step.dart';
import 'package:attune/features/dating/setup/looking_for_step.dart';
import 'package:attune/features/dating/setup/privacy_step.dart';
import 'package:attune/features/dating/setup/where_step.dart';
import 'package:attune/features/onboarding/data/home_state_service.dart';
import 'package:attune/home/home_seams.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/fake_home_state.dart';
import '../../../helpers/flow_harness.dart';
import '../../../helpers/home_harness.dart';
import '../../../helpers/tap_in_reach.dart';
import '../support/dating_fakes.dart';
import '../support/dating_setup_fakes.dart';
import '../support/dating_shell.dart';

class _Run {
  _Run(this.setup, this.home, this.spec1, this.steps, this.harness);
  final FakeDatingSetupGateway setup;
  final FakeDatingHomeGateway home;
  final FakeHomeStateGateway spec1;
  final List<String> steps;
  final FlowHarness harness;
}

Future<_Run> _open(
  WidgetTester t,
  Widget Function(DatingStepNav nav) screen, {
  DatingMyProfile profile = const DatingMyProfile(),
  DatingHome home = const DatingHome(state: DatingHomeState.notStarted),
  bool online = true,
  ({String? sim, String? region}) device = (sim: null, region: null),
}) async {
  await t.pumpWidget(const SizedBox());
  final setup = FakeDatingSetupGateway(profile: profile);
  final homeGateway = FakeDatingHomeGateway(home: home);
  final spec1 = FakeHomeStateGateway(state: homeJson(path: 'dating'));
  final steps = <String>[];
  final nav = DatingStepNav(
    next: steps.add,
    back: () => steps.add('<back>'),
    toMe: () => steps.add('<me>'),
  );
  final h = await pumpFlowScreen(
    t,
    () => screen(nav),
    overrides: [
      ...datingShellOverrides(home: homeGateway, online: online),
      datingSetupGatewayProvider.overrideWithValue(setup),
      deviceCountryProvider.overrideWith((ref) async => device),
      homeAuthProvider.overrideWithValue(FakeHomeAuth(testUser('ama'))),
      homeStateServiceProvider.overrideWithValue(HomeStateService(spec1)),
    ],
  );
  await t.pumpAndSettle();
  return _Run(setup, homeGateway, spec1, steps, h);
}

ProviderContainer _c(WidgetTester t) =>
    ProviderScope.containerOf(t.element(find.byType(MaterialApp)));

void main() {
  group('D1', () {
    testWidgets('eight lines, the open list built and the first drop dated', (
      t,
    ) async {
      await _open(
        t,
        (nav) => DatingHowStep(nav: nav),
        home: DatingHome(
          state: DatingHomeState.notStarted,
          firstDropAt: DateTime.utc(2026, 11, 12, 19),
        ),
      );
      expect(find.text('How Dating works'), findsOneWidget);
      expect(
        find.text('Up to 3 introductions a day, at a time you choose.'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Your first introductions can arrive from '),
        findsOneWidget,
      );
      expect(
        find.text(
          'Dating is open in the United Kingdom and Ghana (Greater Accra and Ashanti).',
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          'Setting up uses about 15 MB of data, mostly for the video check.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('Set up Dating, Set up later', (t) async {
      final r = await _open(t, (nav) => DatingHowStep(nav: nav));
      await tapInReach(t, find.text('Set up Dating'));
      await t.pump();
      await tapInReach(t, find.text('Set up later'));
      expect(r.steps, ['looking-for', '<me>']);
    });

    testWidgets('Not ready? switches in one tap, with Undo', (t) async {
      final r = await _open(t, (nav) => DatingHowStep(nav: nav));
      await tapInReach(t, find.text('Not ready? Use Attune just for me'));
      await t.pumpAndSettle();
      expect(r.spec1.count('set_my_path'), 1);
      expect(find.text("You're on 'Just for me'."), findsOneWidget);
      await t.tap(find.text('Undo'));
      await t.pumpAndSettle();
      expect(r.spec1.count('set_my_path'), 2);
    });

    testWidgets('a closed country: §3.10 instead', (t) async {
      await _open(
        t,
        (nav) => DatingHowStep(nav: nav),
        home: const DatingHome(
          state: DatingHomeState.countryClosed,
          country: 'NG',
          notice: DatingNotice(available: true),
        ),
      );
      expect(find.text("Dating isn't open in Nigeria yet"), findsOneWidget);
      expect(find.text('How Dating works'), findsNothing);
    });
  });

  group('D2', () {
    testWidgets(
      'Continue waits for an intention; the attestation is required',
      (t) async {
        final r = await _open(t, (nav) => DatingLookingForStep(nav: nav));
        expect(find.text('Step 1 of 12'), findsOneWidget);
        await tapInReach(t, find.text('Continue'));
        await t.pumpAndSettle();
        expect(r.setup.writes, isEmpty);
        await tapInReach(t, find.text('A committed relationship'));
        await t.pump();
        await tapInReach(t, find.text('Continue'));
        await t.pumpAndSettle();
        expect(
          find.text("Please confirm you're free to start a relationship."),
          findsOneWidget,
        );
        expect(r.setup.writes, isEmpty);
        await tapInReach(t, find.textContaining("I'm not married in any form"));
        await t.pump();
        await tapInReach(t, find.text('Continue'));
        await t.pumpAndSettle();
        expect(r.setup.lastWrite.$2['intention'], 'committed');
        expect(r.setup.lastWrite.$2['timeline'], isNull);
        expect(r.steps, ['where']);
      },
    );

    testWidgets('Marriage opens the timeline; a double tap is one key', (
      t,
    ) async {
      final r = await _open(t, (nav) => DatingLookingForStep(nav: nav));
      await tapInReach(t, find.text('Marriage'));
      await t.pumpAndSettle();
      expect(find.text('When would you like to marry?'), findsOneWidget);
      await tapInReach(t, find.text('In a few years'));
      await t.pump();
      await tapInReach(t, find.textContaining("I'm not married in any form"));
      await t.pump();
      await tapInReach(t, find.text('Continue'));
      await t.pump();
      await tapInReach(t, find.text('Continue'));
      await t.pumpAndSettle();
      final saves =
          r.setup.calls.where((c) => c.$1 == 'saveIntention').toList();
      expect(saves.map((c) => c.$2['key']).toSet().length, 1);
      expect(saves.first.$2['timeline'], 'few_years');
    });

    testWidgets('a changed answer asks the attestation again', (t) async {
      await _open(
        t,
        (nav) => DatingLookingForStep(nav: nav),
        profile: const DatingMyProfile(intention: 'committed', attested: true),
      );
      final box = find.byType(CheckboxListTile);
      expect(t.widget<CheckboxListTile>(box).value, isTrue);
      await tapInReach(t, find.text('Marriage'));
      await t.pumpAndSettle();
      expect(t.widget<CheckboxListTile>(box).value, isFalse);
    });

    testWidgets('separated but not divorced: the sheet', (t) async {
      await _open(t, (nav) => DatingLookingForStep(nav: nav));
      await tapInReach(t, find.text("I'm separated but not divorced"));
      await t.pumpAndSettle();
      expect(find.textContaining('Once your divorce is final'), findsOneWidget);
    });

    testWidgets(
      'D8: another account starts empty, even while its read is held',
      (t) async {
        final r = await _open(
          t,
          (nav) => DatingLookingForStep(nav: nav),
          profile: const DatingMyProfile(
            intention: 'marriage',
            marriageTimeline: 'few_years',
            attested: true,
          ),
        );
        expect(find.text('When would you like to marry?'), findsOneWidget);
        r.setup.holdProfile = Completer<DatingMyProfile>();
        _c(t).read(datingTestAccount.notifier).state = 'kofi';
        for (var i = 0; i < 4; i++) {
          await t.pump(const Duration(milliseconds: 40));
          expect(find.text('When would you like to marry?'), findsNothing);
          expect(
            t.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
            isFalse,
          );
        }
        r.setup.holdProfile!.complete(const DatingMyProfile());
        await t.pumpAndSettle();
        expect(find.text('When would you like to marry?'), findsNothing);
      },
    );

    testWidgets('a busy server is said calmly; offline disables Continue', (
      t,
    ) async {
      final r = await _open(t, (nav) => DatingLookingForStep(nav: nav));
      r.setup.answer = DatingWrite.busy;
      await tapInReach(t, find.text('Not sure yet'));
      await t.pump();
      await tapInReach(t, find.textContaining("I'm not married in any form"));
      await t.pump();
      await tapInReach(t, find.text('Continue'));
      await t.pumpAndSettle();
      expect(
        find.text(
          'This is taking a little longer than usual. Try again in a moment.',
        ),
        findsOneWidget,
      );
      final off = await _open(
        t,
        (nav) => DatingLookingForStep(nav: nav),
        online: false,
      );
      await tapInReach(t, find.text('Not sure yet'));
      await t.pump();
      await tapInReach(t, find.textContaining("I'm not married in any form"));
      await t.pump();
      await tapInReach(t, find.text('Continue'));
      await t.pumpAndSettle();
      expect(off.setup.writes, isEmpty);
      expect(find.text('Connect to save this answer.'), findsOneWidget);
    });
  });

  group('D3', () {
    testWidgets('preselected from the SIM; a closed region blocks Continue and '
        'can be asked for', (t) async {
      final r = await _open(
        t,
        (nav) => DatingWhereStep(nav: nav),
        device: (sim: 'GH', region: 'GB'),
      );
      expect(find.text('Ghana'), findsOneWidget);
      await tapInReach(t, find.text('Region'));
      await t.pumpAndSettle();
      await tapInReach(t, find.text('Volta').last);
      await t.pumpAndSettle();
      expect(
        find.textContaining(
          'Dating is open in Greater Accra and Ashanti for now.',
        ),
        findsOneWidget,
      );
      await tapInReach(t, find.text('Continue'));
      await t.pumpAndSettle();
      expect(r.setup.writes, isEmpty);
      await tapInReach(t, find.text("Tell me when it's open in Volta"));
      await t.pumpAndSettle();
      expect(r.home.requests, [('GH', 'TV')]);
    });

    testWidgets('a side, the scope, and the save', (t) async {
      final r = await _open(
        t,
        (nav) => DatingWhereStep(nav: nav),
        device: (sim: 'GH', region: null),
      );
      await tapInReach(t, find.text('Region'));
      await t.pumpAndSettle();
      await tapInReach(t, find.text('Greater Accra').last);
      await t.pumpAndSettle();
      await tapInReach(t, find.text('Tema and Ashaiman'));
      await t.pump();
      await tapInReach(t, find.text('My side'));
      await t.pump();
      await tapInReach(t, find.text('Continue'));
      await t.pumpAndSettle();
      expect(r.setup.lastWrite.$2, {
        'key': r.setup.lastWrite.$2['key'],
        'country': 'GH',
        'region': 'AA',
        'side': 'tema',
        'scope': 'side',
      });
      expect(r.steps, ['privacy']);
    });

    testWidgets('the abroad row is disabled and says why', (t) async {
      await _open(t, (nav) => DatingWhereStep(nav: nav));
      expect(
        find.text('Also open to people in other countries'),
        findsOneWidget,
      );
      expect(
        find.text(
          "Available once you're verified and your account is 14 days old.",
        ),
        findsOneWidget,
      );
    });

    testWidgets('a refused country change is named', (t) async {
      final r = await _open(
        t,
        (nav) => DatingWhereStep(nav: nav),
        profile: const DatingMyProfile(
          countryCode: 'GB',
          regionCode: 'TLI',
          regionScope: 'region',
        ),
      );
      r.setup.answer = const DatingWrite(
        ok: false,
        reason: 'country_change_limited',
      );
      await tapInReach(t, find.text('Continue'));
      await t.pumpAndSettle();
      expect(
        find.text('You can change your Dating country once every 30 days.'),
        findsOneWidget,
      );
    });
  });

  group('D4', () {
    testWidgets(
      'Agree waits for the box; then three consents and the enrolment',
      (t) async {
        final r = await _open(t, (nav) => DatingPrivacyStep(nav: nav));
        expect(find.text('Step 3 of 12'), findsOneWidget);
        await tapInReach(t, find.text('Agree and continue'));
        await t.pumpAndSettle();
        expect(r.setup.writes, isEmpty);
        await tapInReach(
          t,
          find.textContaining('I agree that Attune can use my answers'),
        );
        await t.pump();
        await tapInReach(t, find.text('Agree and continue'));
        await t.pumpAndSettle();
        expect(r.setup.writes, ['agreeAndBegin']);
        expect(r.steps, ['you']);
      },
    );

    testWidgets('five semantic headings', (t) async {
      final semantics = t.ensureSemantics();
      await _open(t, (nav) => DatingPrivacyStep(nav: nav));
      for (final head in [
        'Why we ask',
        'Who sees what',
        'What we never do',
        "How it's protected",
        'Leaving',
      ]) {
        expect(
          t.getSemantics(find.text(head)).hasFlag(SemanticsFlag.isHeader),
          isTrue,
          reason: head,
        );
      }
      semantics.dispose();
    });
  });

  testWidgets('guidelines on every screen', (t) async {
    final semantics = t.ensureSemantics();
    for (final screen in <Widget Function(DatingStepNav)>[
      (nav) => DatingHowStep(nav: nav),
      (nav) => DatingLookingForStep(nav: nav),
      (nav) => DatingWhereStep(nav: nav),
      (nav) => DatingPrivacyStep(nav: nav),
    ]) {
      await _open(t, screen, device: (sim: 'GH', region: null));
      await expectFlowGuidelines(t);
    }
    semantics.dispose();
  });

  for (final (name, screen) in <(String, Widget Function(DatingStepNav))>[
    ('d1_how', (nav) => DatingHowStep(nav: nav)),
    ('d2_looking_for', (nav) => DatingLookingForStep(nav: nav)),
    ('d3_where', (nav) => DatingWhereStep(nav: nav)),
    ('d4_privacy', (nav) => DatingPrivacyStep(nav: nav)),
  ]) {
    testWidgets('$name goldens', (t) async {
      final nav = DatingStepNav(next: (_) {}, back: () {}, toMe: () {});
      await expectFlowGoldens(
        t,
        name,
        () => screen(nav),
        overrides: [
          ...datingShellOverrides(
            home: FakeDatingHomeGateway(
              home: DatingHome(
                state: DatingHomeState.notStarted,
                firstDropAt: DateTime.utc(2026, 11, 12, 19),
              ),
            ),
          ),
          datingSetupGatewayProvider.overrideWithValue(
            FakeDatingSetupGateway(),
          ),
          deviceCountryProvider.overrideWith(
            (ref) async => (sim: 'GH', region: null),
          ),
          homeAuthProvider.overrideWithValue(FakeHomeAuth(testUser('ama'))),
          homeStateServiceProvider.overrideWithValue(
            HomeStateService(
              FakeHomeStateGateway(state: homeJson(path: 'dating')),
            ),
          ),
        ],
      );
    });
  }
}
```

(`SemanticsFlag` comes from `dart:ui`; add `import 'dart:ui' show SemanticsFlag;`.)

Run: `flutter test test/features/dating/setup/d1_d4_test.dart 2>&1 | tail -2`
Expected: FAIL — `Target of URI doesn't exist: 'package:attune/features/dating/setup/how_step.dart'`.

- [ ] **Step 3: The frame, the picker, the state mixin**

Create `lib/features/dating/setup/dating_step_frame.dart` with exactly:

```dart
// Spec 2 W3b (§3.0): what every setup step shares. "Step {n} of 12" as text
// and dots (no motion); the offline banner, with the primary disabled and
// "Connect to save this answer."; Skip bottom-left where allowed; large
// text through FlowFrame's AllowLargeText. The mixin: one idempotency key
// per action (Fable H3c), the person's saved answers seeded once per
// account, and nothing of one account shown to the next (D8).
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_buttons.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_frame.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_text_field.dart'
    show FlowErrorLine;
import 'package:attune/features/dating/data/dating_providers.dart';
import 'package:attune/features/dating/data/dating_rpc.dart';
import 'package:attune/features/dating/gentle_wait/gentle_wait_providers.dart'
    show datingOnlineProvider;
import 'package:attune/features/dating/routes/dating_setup_steps.dart';
import 'package:attune/features/dating/setup/dating_setup_models.dart';
import 'package:attune/features/dating/setup/dating_setup_providers.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class DatingStepFrame extends ConsumerWidget {
  const DatingStepFrame({
    super.key,
    required this.step,
    required this.title,
    required this.body,
    required this.onBack,
    this.hint,
    this.primary,
    this.more = const [],
    this.onSkip,
  });

  final String step;
  final String title;
  final String? hint;
  final Widget body;
  final VoidCallback onBack;
  final Widget? primary;
  final List<Widget> more;
  final VoidCallback? onSkip;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loc = AppLocalizations.of(context)!;
    final online = ref.watch(datingOnlineProvider).valueOrNull ?? true;
    final n = datingStepNumber(step);
    return FlowFrame(
      title: title,
      hint: hint,
      onBack: onBack,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (n != null) ...[
            DatingStepProgress(n: n),
            const SizedBox(height: Spacing.md),
          ],
          if (!online) ...[
            DatingOfflineBanner(text: loc.dating_offline),
            const SizedBox(height: Spacing.md),
          ],
          body,
        ],
      ),
      actions: [
        if (primary != null) primary!,
        if (primary != null && !online)
          Text(
            loc.dating_connectToSave,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ...more,
        if (onSkip != null)
          FlowTextLink(
            label: loc.dating_skip,
            alignment: AlignmentDirectional.centerStart,
            onPressed: onSkip!,
          ),
      ],
    );
  }
}

class DatingStepProgress extends StatelessWidget {
  const DatingStepProgress({super.key, required this.n, this.total = 12});

  final int n;
  final int total;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          loc.dating_stepOf(n, total),
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: Spacing.xs),
        ExcludeSemantics(
          child: Wrap(
            spacing: 4,
            children: [
              for (var i = 1; i <= total; i++)
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i <= n ? scheme.primary : scheme.outlineVariant,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class DatingOfflineBanner extends StatelessWidget {
  const DatingOfflineBanner({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(Spacing.sm),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(Icons.cloud_off_outlined, color: scheme.onSurface),
            const SizedBox(width: Spacing.sm),
            Expanded(
              child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
            ),
          ],
        ),
      ),
    );
  }
}

/// A radio group read as one labelled group; a choice clicks (§3.0).
class DatingChoiceGroup<T> extends StatelessWidget {
  const DatingChoiceGroup({
    super.key,
    required this.label,
    required this.options,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final List<(T, String)> options;
  final T? value;
  final ValueChanged<T>? onChanged;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    label: label,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: Theme.of(context).textTheme.titleSmall),
        for (final (option, text) in options)
          RadioListTile<T>(
            value: option,
            groupValue: value,
            contentPadding: EdgeInsets.zero,
            title: Text(text),
            onChanged:
                onChanged == null
                    ? null
                    : (v) {
                      HapticFeedback.selectionClick();
                      if (v != null) onChanged!(v);
                    },
          ),
      ],
    ),
  );
}

/// A writer's refusal in words (never another person's state).
String datingWriteError(AppLocalizations loc, DatingWrite w) => switch (w
    .reason) {
  'busy' => loc.dating_busy,
  'not_eligible' => loc.dating_sectionUnavailable,
  'reverify_device' => loc.dating_sectionReverify,
  'rate_limited' => loc.dating_errorRateLimited,
  'not_available' => loc.dating_notAvailableHere,
  'contact_details' => loc.dating_contactFilter,
  'unkind' => loc.dating_kindnessFilter,
  'consent_required' => loc.dating_errorConsent,
  'country_change_limited' => loc.dating_countryChangeLimited,
  _ => loc.dating_errorGeneric,
};

/// The refusal line: calm for busy, error-red with an icon otherwise.
Widget datingRefusalLine(AppLocalizations loc, DatingWrite w) =>
    w.reason == 'busy'
        ? Semantics(liveRegion: true, child: Text(loc.dating_busy))
        : FlowErrorLine(text: datingWriteError(loc, w), liveRegion: true);

mixin DatingStepState<W extends ConsumerStatefulWidget> on ConsumerState<W> {
  DatingActionKeys keys = DatingActionKeys();
  bool saving = false;
  DatingWrite? refusal;
  String? _seededFor;

  /// Empties every answer typed on this screen.
  void resetAnswers();

  /// Fills the answers from the person's saved ones.
  void seedAnswers(DatingMyProfile profile);

  @override
  void initState() {
    super.initState();
    ref.listenManual<String?>(datingAccountProvider, (previous, next) {
      if (previous == next || !mounted) return;
      setState(() {
        resetAnswers();
        _seededFor = null;
        saving = false;
        refusal = null;
        keys = DatingActionKeys();
      });
    });
  }

  /// The saved answers; seeds the screen once per account, from a finished
  /// read only (a loading or failed frame never shows anything old).
  DatingMyProfile? watchProfile() {
    final account = ref.watch(datingAccountProvider);
    final read = ref.watch(datingMyProfileProvider(account));
    final profile = read.hasError ? null : read.valueOrNull;
    if (profile != null && _seededFor != account) {
      _seededFor = account;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _seededFor == account) {
          setState(() => seedAnswers(profile));
        }
      });
    }
    return profile;
  }

  Future<void> write(
    String action,
    Object payload,
    Future<DatingWrite> Function(String key) call,
    void Function(DatingWrite w) onSaved,
  ) async {
    if (saving) return;
    final account = ref.read(datingAccountProvider);
    setState(() {
      saving = true;
      refusal = null;
    });
    final w = await call(keys.keyFor(action, '$account|$payload'));
    if (!mounted || ref.read(datingAccountProvider) != account) return;
    setState(() {
      saving = false;
      refusal = w.ok ? null : w;
    });
    if (w.ok) {
      ref.invalidate(datingMyProfileProvider(account));
      onSaved(w);
    }
  }
}
```

Create `lib/features/dating/setup/dating_picker_sheet.dart` with exactly:

```dart
// Spec 2 W3b (§3.2 D3, §3.15 D3): a searchable, labelled picker sheet.
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/ui/text/allow_large_text.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';

Future<T?> showDatingPicker<T>(
  BuildContext context, {
  required String title,
  required List<(T, String)> items,
  T? selected,
}) => showModalBottomSheet<T>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder:
      (sheet) => AllowLargeText(
        child: _Picker<T>(title: title, items: items, selected: selected),
      ),
);

class _Picker<T> extends StatefulWidget {
  const _Picker({required this.title, required this.items, this.selected});

  final String title;
  final List<(T, String)> items;
  final T? selected;

  @override
  State<_Picker<T>> createState() => _PickerState<T>();
}

class _PickerState<T> extends State<_Picker<T>> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final shown = [
      for (final item in widget.items)
        if (item.$2.toLowerCase().contains(_query.toLowerCase())) item,
    ];
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.8,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
              child: Semantics(
                header: true,
                child: Text(
                  widget.title,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
            ),
            if (widget.items.length > 6)
              Padding(
                padding: const EdgeInsets.all(Spacing.md),
                child: TextField(
                  decoration: InputDecoration(labelText: loc.dating_search),
                  onChanged: (q) => setState(() => _query = q),
                ),
              ),
            Expanded(
              child: ListView(
                children: [
                  for (final (value, label) in shown)
                    ListTile(
                      title: Text(label),
                      selected: value == widget.selected,
                      trailing:
                          value == widget.selected
                              ? const Icon(Icons.check)
                              : null,
                      onTap: () => Navigator.of(context).pop(value),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: D1–D4**

Create `lib/features/dating/setup/how_step.dart` with exactly:

```dart
// Spec 2 §3.2 D1 (§3.15: shared-axis on Continue; an 8-item list; a closed
// country is §3.10 instead; R-16, R-36).
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/utils/date_formatter.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_buttons.dart';
import 'package:attune/features/dating/data/dating_home.dart';
import 'package:attune/features/dating/data/dating_names.dart';
import 'package:attune/features/dating/data/dating_providers.dart';
import 'package:attune/features/dating/not_open/dating_not_open_screen.dart';
import 'package:attune/features/dating/routes/dating_setup_steps.dart';
import 'package:attune/features/dating/setup/dating_step_frame.dart';
import 'package:attune/features/me/presentation/path_switch.dart';
import 'package:attune/features/onboarding/domain/home_state.dart';
import 'package:attune/features/onboarding/presentation/path_chooser.dart'
    show PathChoiceOutcome;
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class DatingHowStep extends ConsumerStatefulWidget {
  const DatingHowStep({super.key, required this.nav});

  final DatingStepNav nav;

  @override
  ConsumerState<DatingHowStep> createState() => _DatingHowStepState();
}

class _DatingHowStepState extends ConsumerState<DatingHowStep> {
  bool _switching = false;

  Future<void> _justMe() async {
    if (_switching) return;
    setState(() => _switching = true);
    final loc = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final reader = MediaQuery.of(context).accessibleNavigation;
    final outcome = await switchPath(
      context,
      ref,
      to: AppPath.justMe,
      oneTap: true,
    );
    if (!mounted) return;
    setState(() => _switching = false);
    if (outcome != PathChoiceOutcome.done) return;
    var undone = false;
    final bar = messenger.showSnackBar(
      SnackBar(
        content: Text(loc.dating_justMeDone),
        // §3.0: undo lasts at least 20 s with a screen reader on.
        duration:
            reader ? const Duration(seconds: 20) : const Duration(seconds: 5),
        action: SnackBarAction(
          label: loc.dating_undo,
          onPressed: () async {
            undone = true;
            if (mounted) await switchPath(context, ref, to: AppPath.dating);
          },
        ),
      ),
    );
    await bar.closed;
    if (mounted && !undone) widget.nav.toMe();
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final home =
        ref
            .watch(datingHomeProvider(ref.watch(datingAccountProvider)))
            .valueOrNull;
    if (home != null &&
        const {
          DatingHomeState.featureUnavailable,
          DatingHomeState.countryClosed,
          DatingHomeState.regionClosed,
        }.contains(home.state)) {
      return DatingNotOpenScreen(
        country: home.country,
        region: home.state == DatingHomeState.regionClosed ? home.region : null,
      );
    }
    final open = ref.watch(datingAvailabilityProvider).valueOrNull;
    final first = home?.firstDropAt?.toLocal();
    final items = [
      loc.dating_how1,
      loc.dating_how2,
      loc.dating_how3,
      loc.dating_how4,
      loc.dating_how5,
      if (first != null) loc.dating_how6(MyDateFormat.toDate(first)),
      if (open != null && open.countries.isNotEmpty)
        loc.dating_how7(datingOpenList(loc, open)),
      loc.dating_how8,
    ];
    final style = Theme.of(context).textTheme.bodyLarge;
    return DatingStepFrame(
      step: 'how',
      title: loc.dating_howTitle,
      onBack: widget.nav.back,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < items.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: Spacing.sm),
              child: MergeSemantics(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ExcludeSemantics(child: Text('${i + 1}.  ', style: style)),
                    Expanded(child: Text(items[i], style: style)),
                  ],
                ),
              ),
            ),
        ],
      ),
      primary: FlowPrimaryButton(
        label: loc.flow_slotSetUp,
        onPressed: () => widget.nav.next('looking-for'),
      ),
      more: [
        FlowSecondaryButton(
          label: loc.flow_slotNotReady,
          busy: _switching,
          onPressed: _justMe,
        ),
        FlowTextLink(label: loc.dating_setUpLater, onPressed: widget.nav.toMe),
      ],
    );
  }
}
```

Create `lib/features/dating/setup/looking_for_step.dart` with exactly:

```dart
// Spec 2 §3.2 D2 (Step 1 of 12): intention, the marriage timeline, the
// attestation (asked again whenever intention or marriage history change),
// separated-but-not-divorced, married before (optional). §3.15: the
// timeline expands over 200 ms (none with reduce motion); the attestation's
// error is a live region.
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/ui/motion/reduce_motion.dart';
import 'package:attune/core/ui/text/allow_large_text.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_buttons.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_text_field.dart'
    show FlowErrorLine;
import 'package:attune/features/dating/gentle_wait/gentle_wait_providers.dart'
    show datingOnlineProvider;
import 'package:attune/features/dating/routes/dating_setup_steps.dart';
import 'package:attune/features/dating/setup/dating_setup_models.dart';
import 'package:attune/features/dating/setup/dating_setup_providers.dart';
import 'package:attune/features/dating/setup/dating_step_frame.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class DatingLookingForStep extends ConsumerStatefulWidget {
  const DatingLookingForStep({super.key, required this.nav});

  final DatingStepNav nav;

  @override
  ConsumerState<DatingLookingForStep> createState() =>
      _DatingLookingForStepState();
}

class _DatingLookingForStepState extends ConsumerState<DatingLookingForStep>
    with DatingStepState<DatingLookingForStep> {
  String? _intention;
  String? _timeline;
  bool _timelineVisible = true;
  bool _attested = false;
  bool _attestError = false;
  String? _marital;
  bool _maritalVisible = false;
  bool _marriedOpen = false;

  @override
  void resetAnswers() {
    _intention = null;
    _timeline = null;
    _timelineVisible = true;
    _attested = false;
    _attestError = false;
    _marital = null;
    _maritalVisible = false;
    _marriedOpen = false;
  }

  @override
  void seedAnswers(DatingMyProfile p) {
    _intention = p.intention;
    _timeline = p.marriageTimeline;
    _timelineVisible = p.timelineVisible;
    _marital = p.marital;
    _maritalVisible = p.maritalVisible;
    _marriedOpen = p.marital != null;
    _attested = p.attested;
  }

  void _changed(VoidCallback change) => setState(() {
    change();
    // §3.2 D2: any change to intention or marriage history asks again.
    _attested = false;
  });

  void _continue() {
    final intention = _intention;
    if (intention == null) return;
    if (!_attested) {
      setState(() => _attestError = true);
      return;
    }
    final gateway = ref.read(datingSetupGatewayProvider);
    write(
      'd2',
      [intention, _timeline, _timelineVisible, _marital, _maritalVisible],
      (key) => gateway.saveIntention(
        key,
        intention: intention,
        timeline: intention == 'marriage' ? _timeline : null,
        timelineVisible: _timelineVisible,
        marital: _marital,
        maritalVisible: _maritalVisible,
      ),
      (w) => widget.nav.next(w.nextStep ?? 'where'),
    );
  }

  Future<void> _separated() => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder:
        (sheet) => AllowLargeText(
          child: SafeArea(
            // Scrolls at large text sizes (§3.0).
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                Spacing.lg,
                0,
                Spacing.lg,
                Spacing.lg,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    AppLocalizations.of(sheet)!.dating_separatedSheet,
                    style: Theme.of(sheet).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: Spacing.lg),
                  FlowSecondaryButton(
                    label: AppLocalizations.of(sheet)!.dating_close,
                    onPressed: () => Navigator.of(sheet).pop(),
                  ),
                ],
              ),
            ),
          ),
        ),
  );

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    watchProfile();
    final online = ref.watch(datingOnlineProvider).valueOrNull ?? true;
    return DatingStepFrame(
      step: 'looking-for',
      title: loc.dating_lookingTitle,
      onBack: widget.nav.back,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DatingChoiceGroup<String>(
            label: loc.dating_lookingTitle,
            options: [
              ('marriage', loc.dating_intentMarriage),
              ('committed', loc.dating_intentCommitted),
              ('companionship', loc.dating_intentCompanionship),
              ('not_sure', loc.dating_intentNotSure),
            ],
            value: _intention,
            onChanged: (v) => _changed(() => _intention = v),
          ),
          AnimatedSize(
            duration:
                reduceMotionOf(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 200),
            child:
                _intention != 'marriage'
                    ? const SizedBox(width: double.infinity)
                    : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: Spacing.md),
                        DatingChoiceGroup<String>(
                          label: loc.dating_timelineQ,
                          options: [
                            ('within_two_years', loc.dating_timelineSoon),
                            ('few_years', loc.dating_timelineFew),
                            ('no_set_time', loc.dating_timelineNone),
                          ],
                          value: _timeline,
                          onChanged: (v) => setState(() => _timeline = v),
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(loc.dating_timelineShow),
                          value: _timelineVisible,
                          onChanged:
                              (v) => setState(() => _timelineVisible = v),
                        ),
                      ],
                    ),
          ),
          const SizedBox(height: Spacing.md),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(loc.dating_attestation),
            value: _attested,
            onChanged:
                (v) => setState(() {
                  _attested = v ?? false;
                  if (_attested) _attestError = false;
                }),
          ),
          Text(
            loc.dating_attestationHelper,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (_attestError) ...[
            const SizedBox(height: Spacing.xs),
            FlowErrorLine(text: loc.dating_attestationError, liveRegion: true),
          ],
          FlowTextLink(
            label: loc.dating_separatedLink,
            alignment: AlignmentDirectional.centerStart,
            onPressed: _separated,
          ),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            initiallyExpanded: _marriedOpen,
            title: Text(loc.dating_marriedBefore),
            onExpansionChanged: (v) => _marriedOpen = v,
            children: [
              DatingChoiceGroup<String>(
                label: loc.dating_marriedBefore,
                options: [
                  ('never', loc.dating_maritalNever),
                  ('divorced', loc.dating_maritalDivorced),
                  ('widowed', loc.dating_maritalWidowed),
                ],
                value: _marital,
                onChanged: (v) => _changed(() => _marital = v),
              ),
              if (_marital == 'divorced' || _marital == 'widowed')
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(loc.dating_maritalShow),
                  value: _maritalVisible,
                  onChanged: (v) => setState(() => _maritalVisible = v),
                ),
            ],
          ),
          if (refusal != null) ...[
            const SizedBox(height: Spacing.sm),
            datingRefusalLine(loc, refusal!),
          ],
        ],
      ),
      primary: FlowPrimaryButton(
        label: loc.dating_continue,
        busy: saving,
        onPressed: online && _intention != null ? _continue : null,
      ),
    );
  }
}
```

Create `lib/features/dating/setup/where_step.dart` with exactly:

```dart
// Spec 2 §3.2 D3 (Step 2 of 12): the country (preselected from the SIM,
// the device region or the phone number, the first that is open; never
// hard-coded, R-20), the region (a closed one: the inline notice, Continue
// off, "Tell me when it's open in {region}"), the side where defined, the
// scope, the abroad row (disabled until W5c) and the helper.
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/platform/sim_country.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_buttons.dart';
import 'package:attune/features/dating/data/dating_home_repository.dart';
import 'package:attune/features/dating/data/dating_names.dart';
import 'package:attune/features/dating/data/dating_providers.dart';
import 'package:attune/features/dating/gentle_wait/gentle_wait_providers.dart'
    show datingOnlineProvider;
import 'package:attune/features/dating/routes/dating_routes.dart';
import 'package:attune/features/dating/routes/dating_setup_steps.dart';
import 'package:attune/features/dating/setup/dating_list_names.dart';
import 'package:attune/features/dating/setup/dating_picker_sheet.dart';
import 'package:attune/features/dating/setup/dating_setup_models.dart';
import 'package:attune/features/dating/setup/dating_setup_providers.dart';
import 'package:attune/features/dating/setup/dating_step_frame.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class DatingWhereStep extends ConsumerStatefulWidget {
  const DatingWhereStep({super.key, required this.nav});

  final DatingStepNav nav;

  @override
  ConsumerState<DatingWhereStep> createState() => _DatingWhereStepState();
}

class _DatingWhereStepState extends ConsumerState<DatingWhereStep>
    with DatingStepState<DatingWhereStep> {
  String? _country;
  String? _region;
  String? _side;
  String _scope = 'region';
  bool _chosen = false;
  DatingNoticeResult? _notice;

  @override
  void resetAnswers() {
    _country = null;
    _region = null;
    _side = null;
    _scope = 'region';
    _chosen = false;
    _notice = null;
  }

  @override
  void seedAnswers(DatingMyProfile p) {
    if (p.countryCode == null) return;
    _country = p.countryCode;
    _region = p.regionCode;
    _side = p.sideCode;
    _scope = p.regionScope ?? 'region';
    _chosen = true;
  }

  String? _preselect(DatingSetupLists lists) {
    final device = ref.watch(deviceCountryProvider).valueOrNull;
    for (final c in [device?.sim, device?.region, lists.phoneCountry]) {
      if (c != null && lists.country(c) != null) return c;
    }
    return null;
  }

  String _regionName(AppLocalizations loc, DatingRegion r) =>
      datingListName(loc, r.nameKey) ?? r.code;

  Future<void> _pickCountry(
    AppLocalizations loc,
    DatingSetupLists lists,
    String? current,
  ) async {
    const notListed = '__not_listed__';
    final chosen = await showDatingPicker<String>(
      context,
      title: loc.dating_countryLabel,
      selected: current,
      items: [
        for (final c in lists.countries)
          (c.code, datingCountryName(loc, c.code)),
        (notListed, loc.dating_countryNotListed),
      ],
    );
    if (chosen == null || !mounted) return;
    if (chosen == notListed) {
      final device = ref.read(deviceCountryProvider).valueOrNull;
      context.push(
        DatingPaths.notOpenFor(
          country: device?.sim ?? device?.region ?? lists.phoneCountry,
        ),
      );
      return;
    }
    setState(() {
      _chosen = true;
      if (chosen != _country) {
        _country = chosen;
        _region = null;
        _side = null;
        _scope = 'region';
        _notice = null;
      }
    });
  }

  Future<void> _pickRegion(
    AppLocalizations loc,
    DatingCountryLists country,
  ) async {
    final regions = [...country.regions]
      ..sort((a, b) => _regionName(loc, a).compareTo(_regionName(loc, b)));
    final chosen = await showDatingPicker<String>(
      context,
      title: loc.dating_regionLabel,
      selected: _region,
      items: [for (final r in regions) (r.code, _regionName(loc, r))],
    );
    if (chosen == null || !mounted) return;
    setState(() {
      _region = chosen;
      _side = null;
      if (_scope == 'side') _scope = 'region';
      _notice = null;
    });
  }

  Future<void> _tellMe(String country, String region) async {
    final result = await ref
        .read(datingHomeGatewayProvider)
        .requestNotice(country, region: region);
    if (mounted) setState(() => _notice = result);
  }

  void _continue(String country, String region) {
    final gateway = ref.read(datingSetupGatewayProvider);
    write(
      'd3',
      [country, region, _side, _scope],
      (key) => gateway.saveLocation(
        key,
        country: country,
        region: region,
        side: _side,
        scope: _scope,
      ),
      (w) => widget.nav.next(w.nextStep ?? 'privacy'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    watchProfile();
    final online = ref.watch(datingOnlineProvider).valueOrNull ?? true;
    final lists =
        ref
            .watch(datingSetupListsProvider(ref.watch(datingAccountProvider)))
            .valueOrNull;
    final countryCode =
        _chosen ? _country : (lists == null ? null : _preselect(lists));
    final country = lists?.country(countryCode);
    final region = country?.region(_region);
    final closed = region != null && !region.open;
    final theme = Theme.of(context);
    Widget row(String label, String? value, VoidCallback? onTap) => ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      subtitle: Text(value ?? loc.dating_choose),
      trailing: const Icon(Icons.expand_more),
      onTap: onTap,
    );
    return DatingStepFrame(
      step: 'where',
      title: loc.dating_whereTitle,
      onBack: widget.nav.back,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          row(
            loc.dating_countryLabel,
            countryCode == null ? null : datingCountryName(loc, countryCode),
            lists == null ? null : () => _pickCountry(loc, lists, countryCode),
          ),
          if (country != null)
            row(
              loc.dating_regionLabel,
              region == null ? null : _regionName(loc, region),
              () => _pickRegion(loc, country),
            ),
          if (closed && country != null) ...[
            Semantics(
              liveRegion: true,
              child: Text(
                loc.dating_regionClosed(
                  datingRegionList(loc, country.code, [
                    for (final r in country.regions)
                      if (r.open) r.code,
                  ]),
                ),
                style: theme.textTheme.bodyMedium,
              ),
            ),
            const SizedBox(height: Spacing.sm),
            if (_notice == DatingNoticeResult.saved)
              Text(loc.dating_tellMeDone, style: theme.textTheme.bodyMedium)
            else
              FlowSecondaryButton(
                label: loc.dating_tellMeRegion(_regionName(loc, region)),
                onPressed:
                    online ? () => _tellMe(country.code, region.code) : null,
              ),
          ],
          if (region != null && region.open && region.sides.isNotEmpty) ...[
            const SizedBox(height: Spacing.md),
            DatingChoiceGroup<String?>(
              label: loc.dating_sideLabel(_regionName(loc, region)),
              options: [
                for (final s in region.sides)
                  (s.code, datingListName(loc, s.nameKey) ?? s.code),
                (null, loc.dating_sideEither),
              ],
              value: _side,
              onChanged:
                  (v) => setState(() {
                    _side = v;
                    if (v == null && _scope == 'side') _scope = 'region';
                  }),
            ),
          ],
          if (region != null && region.open) ...[
            const SizedBox(height: Spacing.md),
            DatingChoiceGroup<String>(
              label: loc.dating_scopeQ,
              options: [
                if (_side != null) ('side', loc.dating_scopeSide),
                ('region', loc.dating_scopeRegion),
                (
                  'country',
                  loc.dating_scopeCountry(
                    datingCountryName(loc, country!.code),
                  ),
                ),
              ],
              value: _scope,
              onChanged: (v) => setState(() => _scope = v),
            ),
          ],
          const SizedBox(height: Spacing.md),
          ListTile(
            contentPadding: EdgeInsets.zero,
            enabled: false,
            title: Text(loc.dating_abroadRow),
            subtitle: Text(loc.dating_abroadDisabled),
          ),
          Text(loc.dating_whereHelper, style: theme.textTheme.bodySmall),
          if (refusal != null) ...[
            const SizedBox(height: Spacing.sm),
            datingRefusalLine(loc, refusal!),
          ],
        ],
      ),
      primary: FlowPrimaryButton(
        label: loc.dating_continue,
        busy: saving,
        onPressed:
            online && countryCode != null && region != null && region.open
                ? () => _continue(countryCode, region.code)
                : null,
      ),
    );
  }
}
```

Create `lib/features/dating/setup/privacy_step.dart` with exactly:

```dart
// Spec 2 §3.2 D4 (Step 3 of 12; consent; no motion): five headed blocks,
// the consent with its full sentence, the Dating terms and privacy links
// (Spec 1's sheets, R-31). "Agree and continue": three consent events
// (dating-2.0) and the enrolment. Disabled offline.
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_buttons.dart';
import 'package:attune/features/dating/gentle_wait/gentle_wait_providers.dart'
    show datingOnlineProvider;
import 'package:attune/features/dating/routes/dating_setup_steps.dart';
import 'package:attune/features/dating/setup/dating_setup_models.dart';
import 'package:attune/features/dating/setup/dating_setup_providers.dart';
import 'package:attune/features/dating/setup/dating_step_frame.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class DatingPrivacyStep extends ConsumerStatefulWidget {
  const DatingPrivacyStep({super.key, required this.nav});

  final DatingStepNav nav;

  @override
  ConsumerState<DatingPrivacyStep> createState() => _DatingPrivacyStepState();
}

class _DatingPrivacyStepState extends ConsumerState<DatingPrivacyStep>
    with DatingStepState<DatingPrivacyStep> {
  bool _agreed = false;

  @override
  void resetAnswers() => _agreed = false;

  @override
  void seedAnswers(DatingMyProfile profile) {}

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final online = ref.watch(datingOnlineProvider).valueOrNull ?? true;
    Widget block(String head, String body) => Padding(
      padding: const EdgeInsets.only(bottom: Spacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(head, style: theme.textTheme.titleSmall),
          ),
          const SizedBox(height: Spacing.xs),
          Text(body, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
    return DatingStepFrame(
      step: 'privacy',
      title: loc.dating_privacyTitle,
      onBack: widget.nav.back,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          block(loc.dating_privacyWhyHead, loc.dating_privacyWhy),
          block(loc.dating_privacyWhoHead, loc.dating_privacyWho),
          block(loc.dating_privacyNeverHead, loc.dating_privacyNever),
          block(loc.dating_privacyProtectedHead, loc.dating_privacyProtected),
          block(loc.dating_privacyLeavingHead, loc.dating_privacyLeaving),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(loc.dating_privacyConsent),
            value: _agreed,
            onChanged: (v) => setState(() => _agreed = v ?? false),
          ),
          FlowTextLink(
            label: loc.dating_datingTerms,
            alignment: AlignmentDirectional.centerStart,
            onPressed: () => showTermsSheet(context),
          ),
          FlowTextLink(
            label: loc.dating_privacyNotice,
            alignment: AlignmentDirectional.centerStart,
            onPressed: () => showPrivacySheet(context),
          ),
          if (refusal != null) datingRefusalLine(loc, refusal!),
        ],
      ),
      primary: FlowPrimaryButton(
        label: loc.dating_agreeContinue,
        busy: saving,
        onPressed:
            online && _agreed
                ? () => write(
                  'd4',
                  'agree',
                  (key) =>
                      ref.read(datingSetupGatewayProvider).agreeAndBegin(key),
                  (w) => widget.nav.next(w.nextStep ?? 'you'),
                )
                : null,
      ),
    );
  }
}
```

Create `$D/edit_T6.py` with exactly:

```python
import sys
sys.path.insert(0, '.superpowers/sdd/2026-11-07-spec2-w3')
from anchor import edit
F = 'lib/features/dating/routes/dating_setup_steps.dart'
edit(F, [
    ("import 'package:attune/features/dating/routes/dating_routes.dart';\n",
     "import 'package:attune/features/dating/routes/dating_routes.dart';\n"
     "import 'package:attune/features/dating/setup/how_step.dart';\n"
     "import 'package:attune/features/dating/setup/looking_for_step.dart';\n"
     "import 'package:attune/features/dating/setup/privacy_step.dart';\n"
     "import 'package:attune/features/dating/setup/where_step.dart';\n"),
    ("  'wait' => DatingWaitStep(nav: nav),\n",
     "  'wait' => DatingWaitStep(nav: nav),\n"
     "  'how' => DatingHowStep(nav: nav),\n"
     "  'looking-for' => DatingLookingForStep(nav: nav),\n"
     "  'where' => DatingWhereStep(nav: nav),\n"
     "  'privacy' => DatingPrivacyStep(nav: nav),\n"),
], 'T6 steps')
```

```bash
D=.superpowers/sdd/2026-11-07-spec2-w3
python3 -I $D/edit_T6.py
dart format lib/features/dating/setup/dating_step_frame.dart lib/features/dating/setup/dating_picker_sheet.dart lib/features/dating/setup/how_step.dart lib/features/dating/setup/looking_for_step.dart lib/features/dating/setup/where_step.dart lib/features/dating/setup/privacy_step.dart test/features/dating/setup/d1_d4_test.dart
flutter analyze --no-pub lib/features/dating test/features/dating 2>&1 | tail -1
flutter test --update-goldens test/features/dating/setup/d1_d4_test.dart 2>&1 | tail -1
flutter test test/features/dating 2>&1 | tail -1
python3 scripts/large_text_audit.py --scale 2.0 test/features/dating/setup 2>&1 | tail -1
```

Expected: the edit line; `Formatted …`; `No issues found!`; goldens written for `d1_how`, `d2_looking_for`, `d3_where`, `d4_privacy` (×4) — open each `scale2.0.png`: the step counter, every choice and the primary reachable, nothing clipped; `All tests passed!`; `SCALE 2.0: 0 site(s) to fix, 0 listed apart`. A test whose finder is ambiguous at large text (`find.text('Volta').last` picks the sheet's row) is fixed in the test, never by shrinking the screen.

- [ ] **Step 5: Mutants**

Create `$D/mut_T6.py` with exactly:

```python
S = 'lib/features/dating/setup/'
T = ['test/features/dating/setup/d1_d4_test.dart']
MUTS = {
  'd2_attest_not_reasked': (S + 'looking_for_step.dart', "    _attested = false;\n  });", "  });", T),
  'd2_sends_unticked': (S + 'looking_for_step.dart', "    if (!_attested) {\n      setState(() => _attestError = true);\n      return;\n    }\n", "", T),
  # (d2_seed_from_stale is equivalent: answers are seeded once per account,
  # and an error after a value carries that same account's value.)
  'd8_no_reset': (S + 'dating_step_frame.dart', "        resetAnswers();\n", "", T),
  'keys_per_tap': (S + 'dating_step_frame.dart', "    final w = await call(keys.keyFor(action, '$account|$payload'));", "    final w = await call(DatingActionKeys().keyFor(action));", T),
  'd3_closed_region_continues': (S + 'where_step.dart', "            online && countryCode != null && region != null && region.open\n", "            online && countryCode != null && region != null\n", T),
  'd3_hardcoded_country': (S + 'where_step.dart', "    for (final c in [device?.sim, device?.region, lists.phoneCountry]) {", "    for (final c in ['GB']) {", T),
  'd4_agree_unticked': (S + 'privacy_step.dart', "            online && _agreed\n", "            online\n", T),
  'd1_undo_short': (S + 'how_step.dart', "            reader ? const Duration(seconds: 20) : const Duration(seconds: 5),", "            const Duration(milliseconds: 1),", T),
  'd1_closed_shows_how': (S + 'how_step.dart', "        }.contains(home.state)) {", "        }.contains(home.state) && false) {", T),
}
```

```bash
python3 -I $D/dmut.py $D/mut_T6.py | tee $D/mut_T6.txt | tail -1
```

Expected (verified, fix round 1): `9/9 killed` (`keys_per_tap` dies on the double-tap test: two keys; `d8_no_reset` on the D8 test; the anchors are the formatted text, I-10).

- [ ] **Step 6: Do not commit; record the tree in the report.**

### Task 7: D5–D8, the off-country screens, the "Why?" and support sheets, the country note; the W3b gate (§2.4, §3.2 D5–D8, §3.15 rows D5–D8, §7.2 S3/S22, §7.4 off-country no-call; R-18, R-21)

**Files:**
- Create: `lib/features/dating/setup/you_step.dart`, `lib/features/dating/setup/meet_step.dart`, `lib/features/dating/setup/country_note_screen.dart`, `lib/features/dating/setup/children_step.dart`, `lib/features/dating/setup/faith_step.dart`, `lib/features/dating/setup/dating_support_sheet.dart`, `test/features/dating/setup/d5_d8_test.dart` (+ goldens), `$D/{arb_fragment_T7.txt, edit_T7.py, mut_T7.py}`
- Modify: `lib/features/dating/routes/dating_setup_steps.dart` (four cases), `lib/i10n/app_en.arb` + generated

**Interfaces:**
- Consumes: Task 6's frame, mixin, `DatingChoiceGroup`, `datingRefusalLine`; Task 5's gateway and lists; Task 4's `showDatingWhySheet`, `datingCountryName`, `datingListName`; Spec 1's `supportResourcesProvider`, `openSupportUrl`, `supportDirectoryUrl`, `SupportCategory`, `showFlowConfirm`, `RouteNames.safetyPin`.
- Produces: `DatingYouStep`, `DatingMeetStep`, `DatingChildrenStep`, `DatingFaithStep` (`({required DatingStepNav nav})`); `enum DatingNoteChoice { save, back }`, `Future<DatingNoteChoice> showDatingCountryNote(BuildContext, {required String country})`; `showDatingSupportSheet(BuildContext, {required String country})`; `const datingEveryone = ['man', 'non_binary', 'woman']`.

- [ ] **Step 1: The strings**

Create `$D/arb_fragment_T7.txt` with exactly (spec copy verbatim; "(plan)" marks this plan's own, for the LGBTQ+ and DV reviewers):

```
  "dating_youTitle": "Which best describes you?",
  "@dating_youTitle": {"description": "Spec 2 §3.2 D5 (LGBTQ+ reviewer, W3 gate)."},
  "dating_identityWoman": "Woman", "dating_identityMan": "Man", "dating_identityNonBinary": "Non-binary",
  "dating_moreSpecific": "Add something more specific",
  "dating_specificTransWoman": "Trans woman", "dating_specificTransMan": "Trans man", "dating_specificGenderfluid": "Genderfluid",
  "dating_specificGenderqueer": "Genderqueer", "dating_specificAgender": "Agender", "dating_specificIntersex": "Intersex",
  "dating_specificOwnWords": "In my own words",
  "dating_specificInvalid": "Use letters, spaces and hyphens only, up to 30.",
  "@dating_specificInvalid": {"description": "D5 own words, refused (plan)."},
  "dating_nbPoolsQ": "Should we also introduce you to people looking for:",
  "dating_poolWomen": "Women", "dating_poolMen": "Men",
  "dating_nbPoolsHelper": "People open to everyone can always be introduced to you.",
  "dating_pronouns": "Pronouns (optional)",
  "dating_genderShow": "Show my gender on my profile",
  "dating_youHelper": "We use this only to introduce you to people who want to meet someone like you.",
  "dating_offCountryLine": "In {country}, Dating introduces men and women to each other for now. If neither of these fits you, Dating can't introduce you safely here yet.",
  "@dating_offCountryLine": {"description": "D5 off-country, read before the options (LGBTQ+ reviewer).", "placeholders": {"country": {"type": "String"}}},
  "dating_supportForYou": "Support for you",
  "@dating_supportForYou": {"description": "D5 off-country link to support_resources (lgbtq_legal, crisis)."},
  "dating_supportCall": "Call {number}",
  "@dating_supportCall": {"description": "Support sheet (plan).", "placeholders": {"number": {"type": "String"}}},
  "dating_supportVisit": "Visit the website",
  "@dating_supportVisit": {"description": "Support sheet (plan)."},
  "dating_supportLeave": "This opens outside Attune.",
  "@dating_supportLeave": {"description": "Support sheet confirm (plan)."},
  "dating_supportOpen": "Open",
  "@dating_supportOpen": {"description": "Support sheet confirm (plan)."},
  "dating_supportFind": "Find a helpline",
  "@dating_supportFind": {"description": "Support sheet with no checked list (plan)."},

  "dating_meetTitle": "Who would you like to meet?",
  "@dating_meetTitle": {"description": "Spec 2 §3.2 D6."},
  "dating_seekMen": "Men", "dating_seekWomen": "Women", "dating_seekEveryone": "Everyone",
  "dating_meetPrivate": "Only you can see this. It's never on your profile.",
  "dating_offMeetMen": "You'll be introduced to men.", "dating_offMeetWomen": "You'll be introduced to women.",
  "dating_offMeetLine": "In {country}, Attune introduces men and women to each other for now.",
  "@dating_offMeetLine": {"description": "D6 off-country (LGBTQ+ reviewer).", "placeholders": {"country": {"type": "String"}}},
  "dating_ages": "Ages {min} to {max}",
  "@dating_ages": {"description": "D6.", "placeholders": {"min": {"type": "int"}, "max": {"type": "int"}}},
  "dating_agesYoungest": "Youngest {age}",
  "@dating_agesYoungest": {"description": "D6 slider semantics.", "placeholders": {"age": {"type": "int"}}},
  "dating_agesOldest": "Oldest {age}",
  "@dating_agesOldest": {"description": "D6 slider semantics.", "placeholders": {"age": {"type": "int"}}},
  "dating_noteTitle": "Before you save this",
  "@dating_noteTitle": {"description": "D6 country note (LGBTQ+ reviewer)."},
  "dating_notePhone": "Your phone number is from {country}, where relationships between people of the same gender can carry legal risk, and people have been targeted through dating apps, including by people they know.",
  "@dating_notePhone": {"description": "D6 note, phone variant (R-18).", "placeholders": {"country": {"type": "String"}}},
  "dating_noteThen": "Attune never shows who you'd like to meet, never shows distance, and keeps Dating out of your notifications. You can also set a PIN, use a plain app icon, and leave Dating at any time to delete these answers.",
  "dating_noteSave": "Save", "dating_noteSetPin": "Set a PIN first", "dating_noteBack": "Go back",

  "dating_childrenTitle": "Children",
  "@dating_childrenTitle": {"description": "Spec 2 §3.2 D7."},
  "dating_childrenHaveQ": "Do you have children?",
  "dating_yes": "Yes", "dating_no": "No",
  "dating_childrenWantQ": "Do you want children (or more children)?",
  "dating_openToIt": "Open to it",
  "dating_childrenMustMatch": "Only introduce me to people whose answer fits mine",
  "dating_childrenExcludeParents": "I'd rather not meet people who have children",
  "dating_childrenHelper": "We never ask for your children's names or ages, and photos with children can't be used.",

  "dating_faithTitle": "Faith",
  "@dating_faithTitle": {"description": "Spec 2 §3.2 D8 (cultural reviewer for the lists)."},
  "dating_optional": "Optional",
  "dating_denomination": "Denomination (optional)",
  "dating_importanceQ": "How much does sharing a faith matter to you?",
  "dating_importanceNo": "It doesn't matter", "dating_importanceNice": "Nice if we share", "dating_importanceMust": "We must share it",
  "dating_faithShow": "Show my faith on my profile",
  "dating_faithConsent": "Faith is sensitive information. I agree that Attune can use it to introduce me.",
  "dating_faithConsentError": "Please agree, or choose Skip.",
  "@dating_faithConsentError": {"description": "D8: Continue with a faith but no consent (plan)."}
```

```bash
D=.superpowers/sdd/2026-11-07-spec2-w3
python3 -I .superpowers/sdd/2026-10-26-spec1-w3/arb_append.py $D/arb_fragment_T7.txt
flutter gen-l10n --arb-dir=lib/i10n --template-arb-file=app_en.arb --output-dir=lib/i10n/generated --output-localization-file=app_localizations.dart --no-synthetic-package
```

Expected: `added 63 keys`.

- [ ] **Step 2: Write the failing tests**

Create `test/features/dating/setup/d5_d8_test.dart` with exactly:

```dart
// Spec 2 W3b (§2.4, §3.2 D5-D8, §7.2 S3/S22, §7.4): D5-D8 on- and
// off-country; the off-country screens never send a same-gender set and
// the "Why?" sheet calls nothing; the country note; D8.
import 'dart:async';

import 'package:attune/features/dating/data/dating_rpc.dart';
import 'package:attune/features/dating/routes/dating_setup_steps.dart';
import 'package:attune/features/dating/setup/children_step.dart';
import 'package:attune/features/dating/setup/dating_setup_models.dart';
import 'package:attune/features/dating/setup/dating_setup_providers.dart';
import 'package:attune/features/dating/setup/faith_step.dart';
import 'package:attune/features/dating/setup/meet_step.dart';
import 'package:attune/features/dating/setup/you_step.dart';
import 'package:attune/features/safety/data/support_resources_repository.dart';
import 'package:attune/features/safety/presentation/providers/support_resources_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/flow_harness.dart';
import '../../../helpers/tap_in_reach.dart';
import '../support/dating_fakes.dart';
import '../support/dating_setup_fakes.dart';
import '../support/dating_shell.dart';

const _ghana = DatingMyProfile(
  countryCode: 'GH',
  regionCode: 'AA',
  identity: 'woman',
);
const _uk = DatingMyProfile(
  countryCode: 'GB',
  regionCode: 'TLI',
  identity: 'woman',
);

class _Run {
  _Run(this.setup, this.home, this.steps);
  final FakeDatingSetupGateway setup;
  final FakeDatingHomeGateway home;
  final List<String> steps;
}

Future<_Run> _open(
  WidgetTester t,
  Widget Function(DatingStepNav) screen, {
  DatingMyProfile profile = _ghana,
  DatingSetupLists lists = ghanaLists,
  bool forbidSameGender = false,
}) async {
  await t.pumpWidget(const SizedBox());
  final setup = FakeDatingSetupGateway(profile: profile, listsValue: lists);
  if (forbidSameGender) {
    // §7.4: the off-country screens fail the test if they try.
    setup.guard = (name, args) {
      if (name == 'saveIdentity') {
        expect(args['identity'], isIn(['woman', 'man']));
        expect(args['specific'], isNull);
        expect(args['pronouns'], isNull);
        expect(args['extraPools'], isEmpty);
      }
      if (name == 'saveWhoToMeet') {
        final own = profile.identity;
        expect((args['seeking'] as List).contains(own), isFalse);
        expect((args['seeking'] as List).length, 1);
      }
    };
  }
  final home = FakeDatingHomeGateway();
  final steps = <String>[];
  await pumpFlowScreen(
    t,
    () => screen(DatingStepNav(next: steps.add, back: () {}, toMe: () {})),
    overrides: [
      ...datingShellOverrides(home: home),
      datingSetupGatewayProvider.overrideWithValue(setup),
      supportResourcesProvider.overrideWith(
        (ref, country) async => const SupportResources(
          country: 'GH',
          countrySupported: true,
          catalogueVersion: 'test',
          resources: [],
          fromServer: false,
        ),
      ),
    ],
  );
  await t.pumpAndSettle();
  return _Run(setup, home, steps);
}

void main() {
  group('D5', () {
    testWidgets('off-country (Ghana): Woman or Man only, the line first, '
        'Why? and Support for you', (t) async {
      final r = await _open(
        t,
        (nav) => DatingYouStep(nav: nav),
        forbidSameGender: true,
      );
      expect(find.text('Non-binary'), findsNothing);
      expect(find.text('Add something more specific'), findsNothing);
      expect(find.text('Pronouns (optional)'), findsNothing);
      expect(
        find.textContaining('In Ghana, Dating introduces men and women'),
        findsOneWidget,
      );
      final line = t.getTopLeft(
        find.textContaining('In Ghana, Dating introduces men and women'),
      );
      final woman = t.getTopLeft(find.text('Woman'));
      expect(line.dy, lessThan(woman.dy));
      await tapInReach(t, find.text('Woman'));
      await t.pump();
      await tapInReach(t, find.text('Continue'));
      await t.pumpAndSettle();
      expect(r.setup.writes, ['saveIdentity']);
      expect(r.steps, ['meet']);
    });

    testWidgets('off-country: answers saved while the switch was on are '
        'never sent', (t) async {
      final r = await _open(
        t,
        (nav) => DatingYouStep(nav: nav),
        profile: const DatingMyProfile(
          countryCode: 'GH',
          regionCode: 'AA',
          identity: 'woman',
          specific: 'trans_woman',
          pronouns: 'she/her',
        ),
      );
      await tapInReach(t, find.text('Continue'));
      await t.pumpAndSettle();
      expect(r.setup.lastWrite.$1, 'saveIdentity');
      expect(r.setup.lastWrite.$2['specific'], isNull);
      expect(r.setup.lastWrite.$2['pronouns'], isNull);
    });

    testWidgets('a country missing from the lists is treated as off', (
      t,
    ) async {
      await _open(
        t,
        (nav) => DatingYouStep(nav: nav),
        lists: const DatingSetupLists(countries: [ghanaListsUk]),
      );
      expect(find.text('Non-binary'), findsNothing);
      expect(find.text('Pronouns (optional)'), findsNothing);
    });

    testWidgets('off-country: the Why? sheet makes no request (10 S3)', (
      t,
    ) async {
      final r = await _open(
        t,
        (nav) => DatingYouStep(nav: nav),
        forbidSameGender: true,
      );
      final calls = r.setup.calls.length;
      final reads = r.home.reads;
      await tapInReach(t, find.text('Why?'));
      await t.pumpAndSettle();
      expect(
        find.textContaining(
          'In Ghana, relationships between people of the same gender',
        ),
        findsOneWidget,
      );
      expect(r.setup.calls.length, calls);
      expect(r.home.reads, reads);
    });

    testWidgets('on-country (UK): the full set, the own-words field filtered '
        'here and on the server', (t) async {
      final r = await _open(t, (nav) => DatingYouStep(nav: nav), profile: _uk);
      await tapInReach(t, find.text('Non-binary'));
      await t.pumpAndSettle();
      expect(
        find.text('Should we also introduce you to people looking for:'),
        findsOneWidget,
      );
      await tapInReach(t, find.text('Women'));
      await t.pump();
      await tapInReach(t, find.text('Add something more specific'));
      await t.pumpAndSettle();
      await tapInReach(t, find.text('Genderqueer'));
      await t.enterText(
        find.byKey(const ValueKey('dating_pronouns')),
        'they/them',
      );
      await tapInReach(t, find.text('Continue'));
      await t.pumpAndSettle();
      expect(r.setup.lastWrite.$2['identity'], 'non_binary');
      expect(r.setup.lastWrite.$2['specific'], 'genderqueer');
      expect(r.setup.lastWrite.$2['extraPools'], ['woman']);
      expect(r.setup.lastWrite.$2['pronouns'], 'they/them');
      expect(r.setup.lastWrite.$2['visible'], isFalse);
    });

    testWidgets('a refusal from a modified client reads as not available', (
      t,
    ) async {
      final r = await _open(t, (nav) => DatingYouStep(nav: nav), profile: _uk);
      r.setup.answer = const DatingWrite(ok: false, reason: 'not_available');
      await tapInReach(t, find.text('Man'));
      await t.pump();
      await tapInReach(t, find.text('Continue'));
      await t.pumpAndSettle();
      expect(find.text("This choice isn't available here."), findsOneWidget);
    });

    testWidgets('D8: the next account sees nothing of the last one\'s answer '
        'while its read is held', (t) async {
      final r = await _open(t, (nav) => DatingYouStep(nav: nav), profile: _uk);
      await tapInReach(t, find.text('Non-binary'));
      await t.pumpAndSettle();
      r.setup.holdProfile = Completer<DatingMyProfile>();
      ProviderScope.containerOf(t.element(find.byType(MaterialApp)))
          .read(datingTestAccount.notifier)
          .state = 'kofi';
      for (var i = 0; i < 4; i++) {
        await t.pump(const Duration(milliseconds: 40));
        expect(
          find.text('Should we also introduce you to people looking for:'),
          findsNothing,
        );
      }
      r.setup.holdProfile!.complete(_uk);
      await t.pumpAndSettle();
    });
  });

  group('D6', () {
    testWidgets('off-country: no choice; "You\'ll be introduced to men."', (
      t,
    ) async {
      final r = await _open(
        t,
        (nav) => DatingMeetStep(nav: nav),
        forbidSameGender: true,
      );
      expect(find.text('Everyone'), findsNothing);
      expect(find.text("You'll be introduced to men."), findsOneWidget);
      expect(
        find.textContaining('In Ghana, Attune introduces men and women'),
        findsOneWidget,
      );
      await tapInReach(t, find.text('Continue'));
      await t.pumpAndSettle();
      expect(r.setup.lastWrite.$2['seeking'], ['man']);
      expect(r.setup.lastWrite.$2['minAge'], 25);
      expect(r.setup.lastWrite.$2['maxAge'], 35);
    });

    testWidgets('on-country, Everyone: the explicit full set', (t) async {
      final r = await _open(t, (nav) => DatingMeetStep(nav: nav), profile: _uk);
      await tapInReach(t, find.text('Everyone'));
      await t.pump();
      await tapInReach(t, find.text('Continue'));
      await t.pumpAndSettle();
      expect(r.setup.lastWrite.$2['seeking'], ['man', 'non_binary', 'woman']);
    });

    testWidgets('a Tier 1 phone and a choice that includes her own gender: the '
        'note first, never animated; Go back saves nothing', (t) async {
      final r = await _open(
        t,
        (nav) => DatingMeetStep(nav: nav),
        profile: _uk,
        lists: const DatingSetupLists(
          countries: [ghanaListsUk],
          phoneCountry: 'GH',
          noteCountry: 'GH',
          defaultAges: (25, 35),
        ),
      );
      await tapInReach(t, find.text('Women'));
      await t.pump();
      await tapInReach(t, find.text('Continue'));
      await t.pump();
      expect(find.text('Before you save this'), findsOneWidget);
      expect(
        find.textContaining('Your phone number is from Ghana'),
        findsOneWidget,
      );
      await tapInReach(t, find.text('Go back'));
      await t.pumpAndSettle();
      expect(r.setup.writes, isEmpty);
      await tapInReach(t, find.text('Continue'));
      await t.pump();
      await tapInReach(t, find.text('Save'));
      await t.pumpAndSettle();
      expect(r.setup.writes, ['saveWhoToMeet']);
    });

    testWidgets('the slider reads both ends and steps them', (t) async {
      final semantics = t.ensureSemantics();
      await _open(t, (nav) => DatingMeetStep(nav: nav), profile: _uk);
      expect(find.bySemanticsLabel('Youngest 25'), findsOneWidget);
      expect(find.bySemanticsLabel('Oldest 35'), findsOneWidget);
      t.semantics.increase(find.semantics.byLabel('Youngest 25'));
      await t.pumpAndSettle();
      expect(find.text('Ages 26 to 35'), findsOneWidget);
      semantics.dispose();
    });
  });

  group('D7', () {
    testWidgets('both questions required; no option to seek parents', (
      t,
    ) async {
      final r = await _open(t, (nav) => DatingChildrenStep(nav: nav));
      await tapInReach(t, find.text('Continue'));
      await t.pumpAndSettle();
      expect(r.setup.writes, isEmpty);
      expect(
        find.textContaining('meet people who have children'),
        findsOneWidget,
      );
      expect(
        find.textContaining(RegExp('only meet people', caseSensitive: false)),
        findsNothing,
      );
      await tapInReach(t, find.text('Yes').first);
      await t.pump();
      await tapInReach(t, find.text('Open to it'));
      await t.pump();
      await tapInReach(
        t,
        find.text("I'd rather not meet people who have children"),
      );
      await t.pump();
      await tapInReach(t, find.text('Continue'));
      await t.pumpAndSettle();
      expect(r.setup.lastWrite.$2, {
        'key': r.setup.lastWrite.$2['key'],
        'have': true,
        'want': 'open',
        'mustMatch': false,
        'excludeParents': true,
      });
      expect(r.steps, ['faith']);
    });
  });

  group('D8', () {
    testWidgets('Skip stores nothing (the clear, never gated)', (t) async {
      final r = await _open(t, (nav) => DatingFaithStep(nav: nav));
      await tapInReach(t, find.text('Skip'));
      await t.pumpAndSettle();
      expect(r.setup.writes, ['clearFaith']);
      expect(r.steps, ['photos']);
    });

    testWidgets('a faith needs the importance and the consent', (t) async {
      final r = await _open(t, (nav) => DatingFaithStep(nav: nav));
      await tapInReach(t, find.text('Christian'));
      await t.pumpAndSettle();
      expect(find.text('Denomination (optional)'), findsOneWidget);
      await tapInReach(t, find.text('Methodist'));
      await t.pump();
      await tapInReach(t, find.text('We must share it'));
      await t.pump();
      await tapInReach(t, find.text('Continue'));
      await t.pumpAndSettle();
      expect(find.text('Please agree, or choose Skip.'), findsOneWidget);
      expect(r.setup.writes, isEmpty);
      await tapInReach(
        t,
        find.textContaining('Faith is sensitive information.'),
      );
      await t.pump();
      await tapInReach(t, find.text('Continue'));
      await t.pumpAndSettle();
      expect(r.setup.lastWrite.$2['faith'], 'christian');
      expect(r.setup.lastWrite.$2['denomination'], 'methodist');
      expect(r.setup.lastWrite.$2['importance'], 'must_share');
      expect(r.setup.lastWrite.$2['visible'], isFalse);
    });

    testWidgets('the country\'s own list (Ghana has no Hindu row)', (t) async {
      await _open(t, (nav) => DatingFaithStep(nav: nav));
      expect(find.text('Muslim'), findsOneWidget);
      expect(find.text('Hindu'), findsNothing);
    });
  });

  testWidgets('guidelines on every screen, both countries', (t) async {
    final semantics = t.ensureSemantics();
    for (final profile in [_ghana, _uk]) {
      for (final screen in <Widget Function(DatingStepNav)>[
        (nav) => DatingYouStep(nav: nav),
        (nav) => DatingMeetStep(nav: nav),
        (nav) => DatingChildrenStep(nav: nav),
        (nav) => DatingFaithStep(nav: nav),
      ]) {
        await _open(t, screen, profile: profile);
        await expectFlowGuidelines(t);
      }
    }
    semantics.dispose();
  });

  for (final (name, profile, screen)
      in <(String, DatingMyProfile, Widget Function(DatingStepNav))>[
        ('d5_you_off_country', _ghana, (nav) => DatingYouStep(nav: nav)),
        ('d5_you', _uk, (nav) => DatingYouStep(nav: nav)),
        ('d6_meet_off_country', _ghana, (nav) => DatingMeetStep(nav: nav)),
        ('d6_meet', _uk, (nav) => DatingMeetStep(nav: nav)),
        ('d7_children', _ghana, (nav) => DatingChildrenStep(nav: nav)),
        ('d8_faith', _ghana, (nav) => DatingFaithStep(nav: nav)),
      ]) {
    testWidgets('$name goldens', (t) async {
      await expectFlowGoldens(
        t,
        name,
        () => screen(DatingStepNav(next: (_) {}, back: () {}, toMe: () {})),
        overrides: [
          ...datingShellOverrides(),
          datingSetupGatewayProvider.overrideWithValue(
            FakeDatingSetupGateway(profile: profile),
          ),
        ],
      );
    });
  }
}
```

Add to `test/features/dating/support/dating_setup_fakes.dart` (appended at the end of the file; Task 7's own `dart format` line formats it):

```dart
/// The UK row alone (for a Tier 1 phone on a UK profile).
const ghanaListsUk = DatingCountryLists(
  code: 'GB',
  sameGender: true,
  regions: [DatingRegion(code: 'TLI', nameKey: 'dating_region_gb_tli', open: true)],
);
```

(Import `package:attune/features/dating/data/dating_rpc.dart` for `DatingWrite` and `package:flutter/rendering.dart` for `SemanticsAction` in the test if the analyzer asks.)

Run: `flutter test test/features/dating/setup/d5_d8_test.dart 2>&1 | tail -2`
Expected: FAIL — `Target of URI doesn't exist: 'package:attune/features/dating/setup/you_step.dart'`.

- [ ] **Step 3: The sheets and the note**

Create `lib/features/dating/setup/dating_support_sheet.dart` with exactly:

```dart
// Spec 2 §3.2 D5 off-country: "Support for you" — the country's
// support_resources in the lgbtq_legal and crisis categories (S1 W7a). A
// call or a link is opened only after the person confirms it. Nothing is
// stored; reading the list says nothing about why it was opened.
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/ui/text/allow_large_text.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_buttons.dart';
import 'package:attune/features/dating/data/dating_names.dart';
import 'package:attune/features/onboarding/presentation/path_chooser.dart'
    show showFlowConfirm;
import 'package:attune/features/safety/data/support_resources_repository.dart';
import 'package:attune/features/safety/presentation/providers/support_resources_providers.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

Future<void> showDatingSupportSheet(
  BuildContext context, {
  required String country,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (sheet) => AllowLargeText(child: _Support(country: country)),
);

class _Support extends ConsumerWidget {
  const _Support({required this.country});

  final String country;

  Future<void> _open(BuildContext context, String title, String url) async {
    final loc = AppLocalizations.of(context)!;
    final ok = await showFlowConfirm(
      context,
      title: title,
      body: loc.dating_supportLeave,
      confirm: loc.dating_supportOpen,
      cancel: loc.flow_cancel,
    );
    if (ok && context.mounted) await openSupportUrl(context, url);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final list = ref.watch(supportResourcesProvider(country)).valueOrNull;
    final shown = [
      for (final r in list?.resources ?? const <SupportResource>[])
        if (r.category == SupportCategory.lgbtqLegal ||
            r.category == SupportCategory.crisis)
          r,
    ];
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          Spacing.lg,
          0,
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
                loc.dating_supportForYou,
                style: theme.textTheme.titleLarge,
              ),
            ),
            const SizedBox(height: Spacing.sm),
            Text(
              datingCountryName(loc, country),
              style: theme.textTheme.bodyMedium,
            ),
            for (final r in shown) ...[
              const SizedBox(height: Spacing.md),
              Text(r.name, style: theme.textTheme.titleSmall),
              if (r.description != null)
                Text(r.description!, style: theme.textTheme.bodyMedium),
              if (r.phone != null)
                FlowTextLink(
                  label: loc.dating_supportCall(r.phone!),
                  alignment: AlignmentDirectional.centerStart,
                  onPressed: () => _open(context, r.name, 'tel:${r.phone}'),
                ),
              if (r.url != null)
                FlowTextLink(
                  label: loc.dating_supportVisit,
                  alignment: AlignmentDirectional.centerStart,
                  onPressed: () => _open(context, r.name, r.url!),
                ),
            ],
            if (shown.isEmpty)
              FlowTextLink(
                label: loc.dating_supportFind,
                alignment: AlignmentDirectional.centerStart,
                onPressed:
                    () => _open(
                      context,
                      loc.dating_supportFind,
                      supportDirectoryUrl,
                    ),
              ),
            const SizedBox(height: Spacing.md),
            FlowSecondaryButton(
              label: loc.dating_close,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }
}
```

Create `lib/features/dating/setup/country_note_screen.dart` with exactly:

```dart
// Spec 2 §3.2 D6 country note (§3.15: no animation; never logged; shown on
// the device only): full screen, the phone variant (R-18), then Save, Set a
// PIN first (the existing PIN setup, then back here), Go back.
import 'package:attune/app/routing/app_router.dart' show RouteNames;
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_buttons.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_frame.dart';
import 'package:attune/features/dating/data/dating_names.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

enum DatingNoteChoice { save, back }

Future<DatingNoteChoice> showDatingCountryNote(
  BuildContext context, {
  required String country,
}) async {
  final choice = await Navigator.of(context).push<DatingNoteChoice>(
    PageRouteBuilder<DatingNoteChoice>(
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
      pageBuilder: (context, _, __) => _Note(country: country),
    ),
  );
  return choice ?? DatingNoteChoice.back;
}

class _Note extends StatelessWidget {
  const _Note({required this.country});

  final String country;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final style = Theme.of(context).textTheme.bodyLarge;
    return FlowFrame(
      title: loc.dating_noteTitle,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            loc.dating_notePhone(datingCountryName(loc, country)),
            style: style,
          ),
          const SizedBox(height: Spacing.md),
          Text(loc.dating_noteThen, style: style),
        ],
      ),
      actions: [
        FlowPrimaryButton(
          label: loc.dating_noteSave,
          onPressed: () => Navigator.of(context).pop(DatingNoteChoice.save),
        ),
        FlowSecondaryButton(
          label: loc.dating_noteSetPin,
          onPressed: () => context.push(RouteNames.safetyPin),
        ),
        FlowTextLink(
          label: loc.dating_noteBack,
          onPressed: () => Navigator.of(context).pop(DatingNoteChoice.back),
        ),
      ],
    );
  }
}
```

- [ ] **Step 4: D5–D8**

Create `lib/features/dating/setup/you_step.dart` with exactly:

```dart
// Spec 2 §3.2 D5 (Step 4 of 12; §2.4). Off-country (the Dating country's
// same-gender rule off): the line first, Woman or Man only, Why? (static,
// calls nothing) and Support for you; nothing more can be sent. On-country:
// the full set, a more specific term (own words: letters, spaces, hyphens,
// 30), non-binary pools, pronouns (20), visibility off by default.
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_buttons.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_text_field.dart'
    show FlowErrorLine;
import 'package:attune/features/dating/data/dating_names.dart';
import 'package:attune/features/dating/data/dating_providers.dart';
import 'package:attune/features/dating/gentle_wait/gentle_wait_providers.dart'
    show datingOnlineProvider;
import 'package:attune/features/dating/routes/dating_setup_steps.dart';
import 'package:attune/features/dating/section/dating_why_sheet.dart';
import 'package:attune/features/dating/setup/dating_setup_models.dart';
import 'package:attune/features/dating/setup/dating_setup_providers.dart';
import 'package:attune/features/dating/setup/dating_step_frame.dart';
import 'package:attune/features/dating/setup/dating_support_sheet.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final _ownWords = RegExp(r"^\p{L}[\p{L} \-]{0,29}$", unicode: true);

class DatingYouStep extends ConsumerStatefulWidget {
  const DatingYouStep({super.key, required this.nav});

  final DatingStepNav nav;

  @override
  ConsumerState<DatingYouStep> createState() => _DatingYouStepState();
}

class _DatingYouStepState extends ConsumerState<DatingYouStep>
    with DatingStepState<DatingYouStep> {
  String? _identity;
  String? _specific;
  final _own = TextEditingController();
  final _pronouns = TextEditingController();
  final _pools = <String>{};
  bool _visible = false;
  bool _more = false;
  bool _ownInvalid = false;

  @override
  void dispose() {
    _own.dispose();
    _pronouns.dispose();
    super.dispose();
  }

  @override
  void resetAnswers() {
    _identity = null;
    _specific = null;
    _own.clear();
    _pronouns.clear();
    _pools.clear();
    _visible = false;
    _more = false;
    _ownInvalid = false;
  }

  @override
  void seedAnswers(DatingMyProfile p) {
    _identity = p.identity;
    _specific = p.specific ?? (p.specificText != null ? 'own' : null);
    _own.text = p.specificText ?? '';
    _pronouns.text = p.pronouns ?? '';
    _pools
      ..clear()
      ..addAll(p.pools.where((x) => x == 'woman' || x == 'man'));
    _visible = p.genderVisible;
    _more = _specific != null;
  }

  void _continue(bool sameGender) {
    final identity = _identity;
    if (identity == null) return;
    String? specific;
    String? pronouns;
    var pools = <String>[];
    if (sameGender) {
      if (_specific == 'own') {
        final text = _own.text.trim();
        if (!_ownWords.hasMatch(text)) {
          setState(() => _ownInvalid = true);
          return;
        }
        specific = text;
      } else {
        specific = _specific;
      }
      final p = _pronouns.text.trim();
      pronouns = p.isEmpty ? null : p;
      pools = identity == 'non_binary' ? (_pools.toList()..sort()) : const [];
    }
    final gateway = ref.read(datingSetupGatewayProvider);
    write(
      'd5',
      [identity, specific, pronouns, pools, _visible],
      (key) => gateway.saveIdentity(
        key,
        identity: identity,
        specific: specific,
        pronouns: pronouns,
        extraPools: pools,
        visible: _visible,
      ),
      (w) => widget.nav.next(w.nextStep ?? 'meet'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final profile = watchProfile();
    final online = ref.watch(datingOnlineProvider).valueOrNull ?? true;
    final lists =
        ref
            .watch(datingSetupListsProvider(ref.watch(datingAccountProvider)))
            .valueOrNull;
    final country = profile?.countryCode;
    // Unknown is off: nothing same-gender is offered until the rule is known.
    final sameGender = lists?.country(country)?.sameGender ?? false;
    final countryName = country == null ? '' : datingCountryName(loc, country);
    final theme = Theme.of(context);
    return DatingStepFrame(
      step: 'you',
      title: loc.dating_youTitle,
      onBack: widget.nav.back,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!sameGender) ...[
            Text(
              loc.dating_offCountryLine(countryName),
              style: theme.textTheme.bodyLarge,
            ),
            Wrap(
              children: [
                FlowTextLink(
                  label: loc.dating_why,
                  onPressed:
                      () => showDatingWhySheet(context, country: country ?? ''),
                ),
                FlowTextLink(
                  label: loc.dating_supportForYou,
                  onPressed:
                      () => showDatingSupportSheet(
                        context,
                        country: country ?? '',
                      ),
                ),
              ],
            ),
            const SizedBox(height: Spacing.sm),
          ],
          DatingChoiceGroup<String>(
            label: loc.dating_youTitle,
            options: [
              ('woman', loc.dating_identityWoman),
              ('man', loc.dating_identityMan),
              if (sameGender) ('non_binary', loc.dating_identityNonBinary),
            ],
            value: _identity,
            onChanged: (v) => setState(() => _identity = v),
          ),
          if (sameGender) ...[
            if (!_more)
              FlowTextLink(
                label: loc.dating_moreSpecific,
                alignment: AlignmentDirectional.centerStart,
                onPressed: () => setState(() => _more = true),
              )
            else
              DatingChoiceGroup<String?>(
                label: loc.dating_moreSpecific,
                options: [
                  ('trans_woman', loc.dating_specificTransWoman),
                  ('trans_man', loc.dating_specificTransMan),
                  ('genderfluid', loc.dating_specificGenderfluid),
                  ('genderqueer', loc.dating_specificGenderqueer),
                  ('agender', loc.dating_specificAgender),
                  ('intersex', loc.dating_specificIntersex),
                  ('own', loc.dating_specificOwnWords),
                ],
                value: _specific,
                onChanged: (v) => setState(() => _specific = v),
              ),
            if (_more && _specific == 'own')
              TextField(
                controller: _own,
                maxLength: 30,
                decoration: InputDecoration(
                  labelText: loc.dating_specificOwnWords,
                ),
                onChanged: (_) => setState(() => _ownInvalid = false),
              ),
            if (_ownInvalid)
              FlowErrorLine(text: loc.dating_specificInvalid, liveRegion: true),
            if (_identity == 'non_binary') ...[
              const SizedBox(height: Spacing.md),
              Text(loc.dating_nbPoolsQ, style: theme.textTheme.titleSmall),
              for (final (pool, label) in [
                ('woman', loc.dating_poolWomen),
                ('man', loc.dating_poolMen),
              ])
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(label),
                  value: _pools.contains(pool),
                  onChanged:
                      (v) => setState(
                        () =>
                            v == true ? _pools.add(pool) : _pools.remove(pool),
                      ),
                ),
              Text(loc.dating_nbPoolsHelper, style: theme.textTheme.bodySmall),
            ],
            const SizedBox(height: Spacing.md),
            TextField(
              key: const ValueKey('dating_pronouns'),
              controller: _pronouns,
              maxLength: 20,
              inputFormatters: [
                FilteringTextInputFormatter.allow(
                  RegExp(r"[\p{L}/ \-]", unicode: true),
                ),
              ],
              decoration: InputDecoration(labelText: loc.dating_pronouns),
            ),
            Wrap(
              spacing: Spacing.sm,
              children: [
                for (final s in const ['she/her', 'he/him', 'they/them'])
                  ActionChip(
                    label: Text(s),
                    onPressed: () => setState(() => _pronouns.text = s),
                  ),
              ],
            ),
          ],
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(loc.dating_genderShow),
            value: _visible,
            onChanged: (v) => setState(() => _visible = v),
          ),
          Text(loc.dating_youHelper, style: theme.textTheme.bodySmall),
          if (refusal != null) ...[
            const SizedBox(height: Spacing.sm),
            datingRefusalLine(loc, refusal!),
          ],
        ],
      ),
      primary: FlowPrimaryButton(
        label: loc.dating_continue,
        busy: saving,
        onPressed:
            online && _identity != null && profile != null
                ? () => _continue(sameGender)
                : null,
      ),
    );
  }
}
```

Create `lib/features/dating/setup/meet_step.dart` with exactly:

```dart
// Spec 2 §3.2 D6 (Step 5 of 12; §2.4). Off-country: no choice ("You'll be
// introduced to men."), the line and Why?. On-country: Men / Women /
// Everyone (the explicit full set), "Only you can see this." The ages:
// 18-99, defaulted by the server (18-20: up to own age + 7), a two-thumb
// slider read as "Youngest {n}" and "Oldest {n}" with increase/decrease.
// The country note first when the phone country is Tier 1/2 and the
// choice includes the person's own gender, or the person is non-binary.
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_buttons.dart';
import 'package:attune/features/dating/data/dating_names.dart';
import 'package:attune/features/dating/data/dating_providers.dart';
import 'package:attune/features/dating/gentle_wait/gentle_wait_providers.dart'
    show datingOnlineProvider;
import 'package:attune/features/dating/routes/dating_setup_steps.dart';
import 'package:attune/features/dating/section/dating_why_sheet.dart';
import 'package:attune/features/dating/setup/country_note_screen.dart';
import 'package:attune/features/dating/setup/dating_setup_models.dart';
import 'package:attune/features/dating/setup/dating_setup_providers.dart';
import 'package:attune/features/dating/setup/dating_step_frame.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const datingEveryone = ['man', 'non_binary', 'woman'];

class DatingMeetStep extends ConsumerStatefulWidget {
  const DatingMeetStep({super.key, required this.nav});

  final DatingStepNav nav;

  @override
  ConsumerState<DatingMeetStep> createState() => _DatingMeetStepState();
}

class _DatingMeetStepState extends ConsumerState<DatingMeetStep>
    with DatingStepState<DatingMeetStep> {
  String? _seek;
  RangeValues? _ages;

  @override
  void resetAnswers() {
    _seek = null;
    _ages = null;
  }

  @override
  void seedAnswers(DatingMyProfile p) {
    final s = [...p.seeking]..sort();
    _seek =
        s.isEmpty
            ? null
            : s.length == 1
            ? s.single
            : 'everyone';
    if (p.minAge != null && p.maxAge != null) {
      _ages = RangeValues(p.minAge!.toDouble(), p.maxAge!.toDouble());
    }
  }

  Future<void> _continue(
    String? identity,
    bool sameGender,
    String? noteCountry,
    RangeValues ages,
  ) async {
    if (identity == null) return;
    final seeking =
        sameGender
            ? (_seek == 'everyone' ? datingEveryone : [_seek!])
            : [identity == 'woman' ? 'man' : 'woman'];
    final ownIncluded = identity == 'non_binary' || seeking.contains(identity);
    if (noteCountry != null && sameGender && ownIncluded) {
      final choice = await showDatingCountryNote(context, country: noteCountry);
      if (choice != DatingNoteChoice.save || !mounted) return;
    }
    final gateway = ref.read(datingSetupGatewayProvider);
    final min = ages.start.round();
    final max = ages.end.round();
    await write(
      'd6',
      [seeking, min, max],
      (key) => gateway.saveWhoToMeet(
        key,
        seeking: seeking,
        minAge: min,
        maxAge: max,
      ),
      (w) => widget.nav.next(w.nextStep ?? 'children'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final profile = watchProfile();
    final online = ref.watch(datingOnlineProvider).valueOrNull ?? true;
    final lists =
        ref
            .watch(datingSetupListsProvider(ref.watch(datingAccountProvider)))
            .valueOrNull;
    final country = profile?.countryCode;
    final identity = profile?.identity;
    final sameGender = lists?.country(country)?.sameGender ?? false;
    final defaults = lists?.defaultAges ?? (18, 99);
    final ages =
        _ages ?? RangeValues(defaults.$1.toDouble(), defaults.$2.toDouble());
    final min = ages.start.round();
    final max = ages.end.round();
    final theme = Theme.of(context);
    void step(bool young, int by) => setState(() {
      final lo = young ? (min + by).clamp(18, max) : min;
      final hi = young ? max : (max + by).clamp(min, 99);
      _ages = RangeValues(lo.toDouble(), hi.toDouble());
    });
    final ready =
        online && identity != null && (sameGender ? _seek != null : true);
    return DatingStepFrame(
      step: 'meet',
      title: loc.dating_meetTitle,
      onBack: widget.nav.back,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!sameGender) ...[
            Text(
              identity == 'man'
                  ? loc.dating_offMeetWomen
                  : loc.dating_offMeetMen,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: Spacing.xs),
            Text(
              loc.dating_offMeetLine(
                country == null ? '' : datingCountryName(loc, country),
              ),
              style: theme.textTheme.bodyMedium,
            ),
            FlowTextLink(
              label: loc.dating_why,
              alignment: AlignmentDirectional.centerStart,
              onPressed:
                  () => showDatingWhySheet(context, country: country ?? ''),
            ),
          ] else ...[
            DatingChoiceGroup<String>(
              label: loc.dating_meetTitle,
              options: [
                ('man', loc.dating_seekMen),
                ('woman', loc.dating_seekWomen),
                ('everyone', loc.dating_seekEveryone),
              ],
              value: _seek,
              onChanged: (v) => setState(() => _seek = v),
            ),
            Text(loc.dating_meetPrivate, style: theme.textTheme.bodySmall),
          ],
          const SizedBox(height: Spacing.lg),
          Text(loc.dating_ages(min, max), style: theme.textTheme.titleSmall),
          ExcludeSemantics(
            child: RangeSlider(
              min: 18,
              max: 99,
              divisions: 81,
              values: ages,
              onChanged: (v) => setState(() => _ages = v),
            ),
          ),
          Row(
            children: [
              for (final (young, label) in [
                (true, loc.dating_agesYoungest(min)),
                (false, loc.dating_agesOldest(max)),
              ])
                Expanded(
                  child: Semantics(
                    label: label,
                    // An adjustable needs its value with the stepped ones.
                    value: '${young ? min : max}',
                    increasedValue: '${(young ? min : max) + 1}',
                    decreasedValue: '${(young ? min : max) - 1}',
                    onIncrease: () => step(young, 1),
                    onDecrease: () => step(young, -1),
                    child: ExcludeSemantics(
                      child: Text(label, style: theme.textTheme.bodySmall),
                    ),
                  ),
                ),
            ],
          ),
          if (refusal != null) ...[
            const SizedBox(height: Spacing.sm),
            datingRefusalLine(loc, refusal!),
          ],
        ],
      ),
      primary: FlowPrimaryButton(
        label: loc.dating_continue,
        busy: saving,
        onPressed:
            ready
                ? () =>
                    _continue(identity, sameGender, lists?.noteCountry, ages)
                : null,
      ),
    );
  }
}
```

Create `lib/features/dating/setup/children_step.dart` with exactly:

```dart
// Spec 2 §3.2 D7 (Step 6 of 12): two questions, both required; two toggles;
// no option to seek parents (10 S22).
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_buttons.dart';
import 'package:attune/features/dating/gentle_wait/gentle_wait_providers.dart'
    show datingOnlineProvider;
import 'package:attune/features/dating/routes/dating_setup_steps.dart';
import 'package:attune/features/dating/setup/dating_setup_models.dart';
import 'package:attune/features/dating/setup/dating_setup_providers.dart';
import 'package:attune/features/dating/setup/dating_step_frame.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class DatingChildrenStep extends ConsumerStatefulWidget {
  const DatingChildrenStep({super.key, required this.nav});

  final DatingStepNav nav;

  @override
  ConsumerState<DatingChildrenStep> createState() => _DatingChildrenStepState();
}

class _DatingChildrenStepState extends ConsumerState<DatingChildrenStep>
    with DatingStepState<DatingChildrenStep> {
  bool? _have;
  String? _want;
  bool _mustMatch = false;
  bool _excludeParents = false;

  @override
  void resetAnswers() {
    _have = null;
    _want = null;
    _mustMatch = false;
    _excludeParents = false;
  }

  @override
  void seedAnswers(DatingMyProfile p) {
    _have = p.childrenHave;
    _want = p.childrenWant;
    _mustMatch = p.wantMustMatch;
    _excludeParents = p.excludeParents;
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    watchProfile();
    final online = ref.watch(datingOnlineProvider).valueOrNull ?? true;
    final have = _have;
    final want = _want;
    return DatingStepFrame(
      step: 'children',
      title: loc.dating_childrenTitle,
      onBack: widget.nav.back,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DatingChoiceGroup<bool>(
            label: loc.dating_childrenHaveQ,
            options: [(true, loc.dating_yes), (false, loc.dating_no)],
            value: have,
            onChanged: (v) => setState(() => _have = v),
          ),
          const SizedBox(height: Spacing.md),
          DatingChoiceGroup<String>(
            label: loc.dating_childrenWantQ,
            options: [
              ('yes', loc.dating_yes),
              ('no', loc.dating_no),
              ('open', loc.dating_openToIt),
            ],
            value: want,
            onChanged: (v) => setState(() => _want = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(loc.dating_childrenMustMatch),
            value: _mustMatch,
            onChanged: (v) => setState(() => _mustMatch = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(loc.dating_childrenExcludeParents),
            value: _excludeParents,
            onChanged: (v) => setState(() => _excludeParents = v),
          ),
          Text(
            loc.dating_childrenHelper,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (refusal != null) ...[
            const SizedBox(height: Spacing.sm),
            datingRefusalLine(loc, refusal!),
          ],
        ],
      ),
      primary: FlowPrimaryButton(
        label: loc.dating_continue,
        busy: saving,
        onPressed:
            online && have != null && want != null
                ? () => write(
                  'd7',
                  [have, want, _mustMatch, _excludeParents],
                  (key) => ref
                      .read(datingSetupGatewayProvider)
                      .saveChildren(
                        key,
                        have: have,
                        want: want,
                        mustMatch: _mustMatch,
                        excludeParents: _excludeParents,
                      ),
                  (w) => widget.nav.next(w.nextStep ?? 'faith'),
                )
                : null,
      ),
    );
  }
}
```

Create `lib/features/dating/setup/faith_step.dart` with exactly:

```dart
// Spec 2 §3.2 D8 (Step 7 of 12; optional): the Dating country's own list; a
// Christian choice opens "Denomination (optional)"; with a faith chosen the
// importance and the faith consent are required; visibility off by
// default. Skip (bottom-left) stores nothing: it is the never-gated clear
// (R-21).
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_buttons.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_text_field.dart'
    show FlowErrorLine;
import 'package:attune/features/dating/data/dating_providers.dart';
import 'package:attune/features/dating/gentle_wait/gentle_wait_providers.dart'
    show datingOnlineProvider;
import 'package:attune/features/dating/routes/dating_setup_steps.dart';
import 'package:attune/features/dating/setup/dating_list_names.dart';
import 'package:attune/features/dating/setup/dating_setup_models.dart';
import 'package:attune/features/dating/setup/dating_setup_providers.dart';
import 'package:attune/features/dating/setup/dating_step_frame.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class DatingFaithStep extends ConsumerStatefulWidget {
  const DatingFaithStep({super.key, required this.nav});

  final DatingStepNav nav;

  @override
  ConsumerState<DatingFaithStep> createState() => _DatingFaithStepState();
}

class _DatingFaithStepState extends ConsumerState<DatingFaithStep>
    with DatingStepState<DatingFaithStep> {
  String? _faith;
  String? _denomination;
  String? _importance;
  bool _visible = false;
  bool _consent = false;
  bool _consentError = false;

  @override
  void resetAnswers() {
    _faith = null;
    _denomination = null;
    _importance = null;
    _visible = false;
    _consent = false;
    _consentError = false;
  }

  @override
  void seedAnswers(DatingMyProfile p) {
    _faith = p.faith;
    _denomination = p.denomination;
    _importance = p.importance;
    _visible = p.faithVisible;
  }

  void _continue() {
    final faith = _faith;
    final importance = _importance;
    if (faith == null || importance == null) return;
    if (!_consent) {
      setState(() => _consentError = true);
      return;
    }
    write(
      'd8',
      [faith, _denomination, importance, _visible],
      (key) => ref
          .read(datingSetupGatewayProvider)
          .saveFaith(
            key,
            faith: faith,
            denomination: _denomination,
            importance: importance,
            visible: _visible,
          ),
      (w) => widget.nav.next(w.nextStep ?? 'photos'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final profile = watchProfile();
    final online = ref.watch(datingOnlineProvider).valueOrNull ?? true;
    final lists =
        ref
            .watch(datingSetupListsProvider(ref.watch(datingAccountProvider)))
            .valueOrNull;
    final faiths =
        lists?.country(profile?.countryCode)?.faiths ?? const <DatingFaith>[];
    DatingFaith? chosen;
    for (final f in faiths) {
      if (f.code == _faith) chosen = f;
    }
    String name(String key, String code) => datingListName(loc, key) ?? code;
    return DatingStepFrame(
      step: 'faith',
      title: loc.dating_faithTitle,
      hint: loc.dating_optional,
      onBack: widget.nav.back,
      onSkip:
          () => write(
            'd8_skip',
            'skip',
            (key) => ref.read(datingSetupGatewayProvider).clearFaith(key),
            (w) => widget.nav.next(w.nextStep ?? 'photos'),
          ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DatingChoiceGroup<String>(
            label: loc.dating_faithTitle,
            options: [
              for (final f in faiths) (f.code, name(f.nameKey, f.code)),
            ],
            value: _faith,
            onChanged:
                (v) => setState(() {
                  _faith = v;
                  _denomination = null;
                }),
          ),
          if (chosen != null && chosen.denominations.isNotEmpty) ...[
            const SizedBox(height: Spacing.md),
            DatingChoiceGroup<String?>(
              label: loc.dating_denomination,
              options: [
                for (final d in chosen.denominations)
                  (d.code, name(d.nameKey, d.code)),
              ],
              value: _denomination,
              onChanged: (v) => setState(() => _denomination = v),
            ),
          ],
          if (_faith != null) ...[
            const SizedBox(height: Spacing.md),
            DatingChoiceGroup<String>(
              label: loc.dating_importanceQ,
              options: [
                ('doesnt_matter', loc.dating_importanceNo),
                ('nice_to_share', loc.dating_importanceNice),
                ('must_share', loc.dating_importanceMust),
              ],
              value: _importance,
              onChanged: (v) => setState(() => _importance = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(loc.dating_faithShow),
              value: _visible,
              onChanged: (v) => setState(() => _visible = v),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(loc.dating_faithConsent),
              value: _consent,
              onChanged:
                  (v) => setState(() {
                    _consent = v ?? false;
                    if (_consent) _consentError = false;
                  }),
            ),
            if (_consentError)
              FlowErrorLine(
                text: loc.dating_faithConsentError,
                liveRegion: true,
              ),
          ],
          if (refusal != null) ...[
            const SizedBox(height: Spacing.sm),
            datingRefusalLine(loc, refusal!),
          ],
        ],
      ),
      primary: FlowPrimaryButton(
        label: loc.dating_continue,
        busy: saving,
        onPressed:
            online && _faith != null && _importance != null ? _continue : null,
      ),
    );
  }
}
```

Create `$D/edit_T7.py` with exactly:

```python
import sys
sys.path.insert(0, '.superpowers/sdd/2026-11-07-spec2-w3')
from anchor import edit
F = 'lib/features/dating/routes/dating_setup_steps.dart'
edit(F, [
    ("import 'package:attune/features/dating/setup/how_step.dart';\n",
     "import 'package:attune/features/dating/setup/children_step.dart';\n"
     "import 'package:attune/features/dating/setup/faith_step.dart';\n"
     "import 'package:attune/features/dating/setup/how_step.dart';\n"),
    ("import 'package:attune/features/dating/setup/looking_for_step.dart';\n",
     "import 'package:attune/features/dating/setup/looking_for_step.dart';\n"
     "import 'package:attune/features/dating/setup/meet_step.dart';\n"),
    ("import 'package:attune/features/dating/setup/where_step.dart';\n",
     "import 'package:attune/features/dating/setup/where_step.dart';\n"
     "import 'package:attune/features/dating/setup/you_step.dart';\n"),
    ("  'privacy' => DatingPrivacyStep(nav: nav),\n",
     "  'privacy' => DatingPrivacyStep(nav: nav),\n"
     "  'you' => DatingYouStep(nav: nav),\n"
     "  'meet' => DatingMeetStep(nav: nav),\n"
     "  'children' => DatingChildrenStep(nav: nav),\n"
     "  'faith' => DatingFaithStep(nav: nav),\n"),
], 'T7 steps')
```

```bash
D=.superpowers/sdd/2026-11-07-spec2-w3
python3 -I $D/edit_T7.py
dart format lib/features/dating/setup/you_step.dart lib/features/dating/setup/meet_step.dart lib/features/dating/setup/country_note_screen.dart lib/features/dating/setup/children_step.dart lib/features/dating/setup/faith_step.dart lib/features/dating/setup/dating_support_sheet.dart test/features/dating/setup/d5_d8_test.dart test/features/dating/support/dating_setup_fakes.dart
flutter analyze --no-pub lib/features/dating test/features/dating 2>&1 | tail -1
flutter test --update-goldens test/features/dating/setup/d5_d8_test.dart 2>&1 | tail -1
flutter test test/features/dating 2>&1 | tail -1
python3 scripts/large_text_audit.py --scale 2.0 test/features/dating/setup 2>&1 | tail -1
```

Expected: the edit; `Formatted …`; `No issues found!`; goldens written for the six names (×4); open each `scale2.0.png` and the two off-country ones at 1.0: the off-country line sits above Woman and Man, nothing else offered; `All tests passed!`; `SCALE 2.0: 0 site(s) to fix, 0 listed apart`.

- [ ] **Step 5: Mutants**

Create `$D/mut_T7.py` with exactly:

```python
S = 'lib/features/dating/setup/'
T = ['test/features/dating/setup/d5_d8_test.dart']
MUTS = {
  'd5_offcountry_nonbinary': (S + 'you_step.dart', "              if (sameGender) ('non_binary', loc.dating_identityNonBinary),", "              ('non_binary', loc.dating_identityNonBinary),", T),
  'd5_offcountry_sends_pronouns': (S + 'you_step.dart', "    if (sameGender) {\n      if (_specific == 'own') {", "    if (true) {\n      if (_specific == 'own') {", T),
  'd5_unknown_rule_on': (S + 'you_step.dart', "    final sameGender = lists?.country(country)?.sameGender ?? false;", "    final sameGender = lists?.country(country)?.sameGender ?? true;", T),
  # The sheet reads the home (a request) when it opens (M-6: two edits).
  'd5_why_reads': (S + '../section/dating_why_sheet.dart', [
      ("import 'package:flutter/material.dart';\n",
       "import 'package:flutter/material.dart';\n"
       "import 'package:flutter_riverpod/flutter_riverpod.dart';\n"
       "import 'package:attune/features/dating/data/dating_providers.dart';\n"),
      ("  return showModalBottomSheet<void>(",
       "  ProviderScope.containerOf(context).read(datingHomeGatewayProvider).read();\n"
       "  return showModalBottomSheet<void>("),
  ], None, T),
  'd6_offcountry_everyone': (S + 'meet_step.dart', "        : [identity == 'woman' ? 'man' : 'woman'];", "        : datingEveryone;", T),
  'd6_no_note': (S + 'meet_step.dart', "    if (noteCountry != null && sameGender && ownIncluded) {", "    if (noteCountry != null && sameGender && ownIncluded && noteCountry.isEmpty) {", T),
  'd6_everyone_partial': (S + 'meet_step.dart', "const datingEveryone = ['man', 'non_binary', 'woman'];", "const datingEveryone = ['man', 'woman'];", T),
  'd6_slider_no_actions': (S + 'meet_step.dart', "                    onIncrease: () => step(young, 1),\n", "", T),
  'd7_seek_parents': (S + 'children_step.dart', "            title: Text(loc.dating_childrenExcludeParents),", "            title: const Text('Only meet people who have children'),", T),
  'd8_skip_stores': (S + 'faith_step.dart', "      onSkip:\n          () => write(\n            'd8_skip',\n            'skip',\n            (key) => ref.read(datingSetupGatewayProvider).clearFaith(key),\n            (w) => widget.nav.next(w.nextStep ?? 'photos'),\n          ),\n", "      onSkip: () => widget.nav.next('photos'),\n", T),
  'd8_no_consent': (S + 'faith_step.dart', "    if (!_consent) {\n      setState(() => _consentError = true);\n      return;\n    }\n", "", T),
}
```

```bash
python3 -I $D/dmut.py $D/mut_T7.py | tee $D/mut_T7.txt | tail -1
```

Expected (verified, fix round 1): `11/11 killed`. `d5_why_reads` is a two-edit mutant (the imports, then a home read when the sheet opens) and dies on the "Why? sheet makes no request" test; `d5_offcountry_sends_pronouns` dies on "answers saved while the switch was on are never sent"; `d5_unknown_rule_on` on "a country missing from the lists is treated as off"; `d6_no_note` keeps `noteCountry` promoted (`&& noteCountry.isEmpty`) so it compiles; `d7_seek_parents` dies on `findsNothing` for "only meet people who have children".

- [ ] **Step 6: The W3b gate**

Run every command of Task 4 Step 11 again with `W3b` in the file names (`$D/sql-after-W3b.txt`, `$D/flutter-after-W3b.txt`, `$D/analyze-after-W3b.txt`), plus the race script on a fresh scratch copy (Task 3 Step 8's commands, the push-key line included with `w3b_race`; W3b re-created no writer, so the expected result is unchanged: 20 `PASS`). Expected: `159 PASS, 14 FAIL`, `no new FAIL`; Flutter with no failure beyond the known one; `no new analyzer issue`; `0`, `0`; the latch OK; Games `All tests passed!`; races 20/20. Do not commit; record the tree. **W3b ships here** (D1–D8 routed; D9 onward still opens Me).


---

## Batch W3c — photos, prompts, preview, ready, settings, docs

### Task 8: Migration `dating_v2_photos`: positions 1–6, captions, `csam_state`, child-label config, the v2 photo RPCs, the storage policies on definer predicates, the last client grants revoked (§4.9 W3c, §3.2 D9, §4.3, §4.4 Photos, §4.5, §4.10, §7.1 photo rows; I-10, R11; R-2, R-24, R-25, R-37)

**Files:**
- Create: `supabase/migrations/20261107170000_dating_v2_photos.sql`, `supabase/migrations/20261107170010_dating_v2_photos_grants.sql`, `$D/{setup_W3c.sql, edit_T8.py, mut_T8.py}`
- Modify: `supabase/tests/dating_v2_setup_contracts.sql` (sections P–T appended; G3's owner probe and photo-reader list), `supabase/tests/storage_bucket_policies.sql` (the two policy hashes), `supabase/tests/dating_rls_canary.sql`, `scripts/local_pg_grants.sql`; one transaction-scoped fixture line (R-24: `csam_state` defaults to `'clear'` for the file's own approved-photo fixtures) after the top-level `BEGIN;` of `dating_v2_setup_contracts.sql`, `dating_v2_identity_contracts.sql`, `dating_v2_home_contracts.sql`, `dating_mode_contracts.sql`, `identity_foundation_contracts.sql`

**Interfaces:**
- Consumes: Task 1's `$D/before/` photo bodies (the v1 RPCs are replaced whole: their return types change); `private.dating_setup_guard()`, `private.dating_invalid`, `private.dating_trim`, `private.dating_has_invisible(text) → boolean`, `public.check_dating_rate_limit(text, integer, interval)` (raises `rate_limited`), `public.claim_dating_idempotency(text, text)`, `public.dating_require_trusted_device()`.
- Produces: `create_dating_photo_upload_intent(p_mime_type text) → jsonb {ok, intent_id, storage_key, bucket, expires_at}` | `{ok:false, reason: invalid(mime) | too_many | rate_limited | not_eligible | reverify_device}`; `insert_dating_profile_photo(p_intent_id uuid, p_position smallint) → jsonb {ok, photo_id}` | `invalid(position) | intent_unavailable | object_missing | too_many`; `list_dating_profile_photos() → jsonb {ok, photos:[{id, position, state, reason, caption, storage_key, created_at}], after_mutual, after_mutual_from}`; `delete_dating_profile_photo(p_photo_id uuid) → jsonb` (never gated); `reorder_dating_photos(p_idempotency_key text, p_order uuid[]) → jsonb`; `set_dating_photo_caption(p_photo_id uuid, p_caption text) → jsonb`; `record_dating_photo_csam(p_photo_id uuid, p_outcome text) → jsonb` (service role; `clear`, `hit`, `error`); the orphan sweep (I-14, service role only): `claim_dating_orphan_uploads(p_limit integer) → TABLE(intent_id, user_id, storage_key)` (intents expired 15 minutes, unused, their object there, no photo row; a claim older than 10 minutes is claimed again) and `record_dating_orphan_scan(p_intent_id uuid, p_outcome text) → jsonb` (`clear` queues the object's deletion; `hit` only marks it, since Spec 1's inline record already owns the object, deleting the original after its quarantine copy and keeping it when the copy failed; `error` releases the claim; `not_claimed`, `invalid(outcome)`), metrics `dating.photo.orphan_{swept,csam,scan_error}`, cron `sweep-dating-photo-orphans` every 15 minutes; `public.dating_storage_intent_open(text) → boolean`, `public.dating_storage_owns(text) → boolean`; rejection reasons exactly `face_unclear`, `too_small`, `contains_child`, `unsafe`, `needs_review`; `dating_photo_moderation_config.child_label_reject` (0.7) / `child_label_review` (0.5).

- [ ] **Step 1: Write the failing contract sections**

Create `$D/setup_W3c.sql` with exactly:

```sql
-- Section T's role switches (this file defines pg_temp.call only; I-5).
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

-- =====================================================================
-- P. (W3c, §4.3, R-24) The photo table: positions 1-6; captions to 100;
--    csam_state; the five slot reasons; an approval needs a clear scan;
--    the child-label thresholds.
-- =====================================================================
DO $p$
DECLARE
  v_u constant uuid := pg_temp.ready('b0', 'GB', 'TLI', 'woman', ARRAY['man']);
  v_msg text;
BEGIN
  -- (This file's older fixtures default csam_state to 'clear'; a real
  -- upload is 'pending' until the scan, as insert_dating_profile_photo
  -- sets it: section Q.)
  INSERT INTO public.dating_profile_photos (user_id, storage_key, position, csam_state)
  VALUES (v_u, 'dating-photos/' || md5('p6') || '.jpg', 6, 'pending');
  BEGIN
    INSERT INTO public.dating_profile_photos (user_id, storage_key, position) VALUES (v_u, 'dating-photos/' || md5('p7') || '.jpg', 7);
    RAISE EXCEPTION 'CONTRACT VIOLATED: position 7 was stored';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  BEGIN
    UPDATE public.dating_profile_photos SET moderation_state = 'approved' WHERE user_id = v_u AND position = 6;
    RAISE EXCEPTION 'CONTRACT VIOLATED: a photo with no clear scan was approved';
  EXCEPTION WHEN check_violation THEN
    GET STACKED DIAGNOSTICS v_msg = CONSTRAINT_NAME;
    IF v_msg IS DISTINCT FROM 'dating_profile_photos_approved_clear_check' THEN
      RAISE EXCEPTION 'CONTRACT VIOLATED: the approval was refused by % instead', v_msg;
    END IF;
  END;
  BEGIN
    UPDATE public.dating_profile_photos SET rejection_reason = 'face_blurred' WHERE user_id = v_u AND position = 6;
    RAISE EXCEPTION 'CONTRACT VIOLATED: a v1 rejection reason was stored';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  IF (SELECT child_label_reject::text || '/' || child_label_review::text FROM public.dating_photo_moderation_config) IS DISTINCT FROM '0.7/0.5' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the child-label thresholds are not 0.7 / 0.5';
  END IF;
END $p$;

-- =====================================================================
-- Q. (W3c, §4.4 Photos) The upload: an intent (setup guard; mime; at most
--    6; counted), the object, the insert; a slot replaced deletes its old
--    photo; the owner's list; the hit is never named.
-- =====================================================================
DO $q$
DECLARE
  v_u constant uuid := pg_temp.ready('b1', 'GB', 'TLI', 'woman', ARRAY['man']);
  v_other constant uuid := pg_temp.ready('b2', 'GB', 'TLI', 'man', ARRAY['woman']);
  v jsonb;
  v2 jsonb;
  v_intent uuid;
  v_key text;
  v_first uuid;
  v_n int;
BEGIN
  IF pg_temp.call(v_u, $s$SELECT public.create_dating_photo_upload_intent('image/gif')$s$)
       IS DISTINCT FROM '{"ok": false, "reason": "invalid", "field": "mime"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a gif intent was not refused as invalid';
  END IF;
  v := pg_temp.call(v_u, $s$SELECT public.create_dating_photo_upload_intent('image/jpeg')$s$);
  v_intent := (v ->> 'intent_id')::uuid;
  v_key := v ->> 'storage_key';
  IF (v ->> 'ok')::boolean IS NOT TRUE OR v ->> 'bucket' IS DISTINCT FROM 'dating-profile-photos' OR v_key !~ '^dating-photos/[0-9a-f]{32}\.jpg$' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the intent reads %', v;
  END IF;
  IF pg_temp.call(v_u, format($s$SELECT public.insert_dating_profile_photo(%L, 1::smallint)$s$, v_intent))
       IS DISTINCT FROM '{"ok": false, "reason": "object_missing"}'::jsonb
     OR pg_temp.call(v_u, format($s$SELECT public.insert_dating_profile_photo(%L, 9::smallint)$s$, v_intent))
       IS DISTINCT FROM '{"ok": false, "reason": "invalid", "field": "position"}'::jsonb
     OR pg_temp.call(v_other, format($s$SELECT public.insert_dating_profile_photo(%L, 1::smallint)$s$, v_intent))
       IS DISTINCT FROM '{"ok": false, "reason": "intent_unavailable"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an insert without the object, at position 9, or with another''s intent was not refused';
  END IF;
  INSERT INTO storage.objects (bucket_id, name, owner) VALUES ('dating-profile-photos', v_key, v_u);
  v := pg_temp.call(v_u, format($s$SELECT public.insert_dating_profile_photo(%L, 1::smallint)$s$, v_intent));
  v_first := (v ->> 'photo_id')::uuid;
  IF (v ->> 'ok')::boolean IS NOT TRUE
     OR (SELECT csam_state FROM public.dating_profile_photos WHERE id = v_first) IS DISTINCT FROM 'pending'
     OR NOT EXISTS (SELECT 1 FROM public.dating_photo_moderation_outbox WHERE photo_id = v_first AND state = 'pending')
     OR (SELECT used_at FROM public.dating_photo_upload_intents WHERE id = v_intent) IS NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the insert reads % (queued? used?)', v;
  END IF;
  -- The same slot again: the old photo goes.
  v := pg_temp.call(v_u, $s$SELECT public.create_dating_photo_upload_intent('image/jpeg')$s$);
  INSERT INTO storage.objects (bucket_id, name, owner) VALUES ('dating-profile-photos', v ->> 'storage_key', v_u);
  v := pg_temp.call(v_u, format($s$SELECT public.insert_dating_profile_photo(%L, 1::smallint)$s$, v ->> 'intent_id'));
  IF EXISTS (SELECT 1 FROM public.dating_profile_photos WHERE id = v_first)
     OR (SELECT count(*) FROM public.dating_profile_photos WHERE user_id = v_u) <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: replacing slot 1 kept the old photo';
  END IF;
  -- Six at most.
  FOR v_n IN 2..6 LOOP
    v := pg_temp.call(v_u, $s$SELECT public.create_dating_photo_upload_intent('image/png')$s$);
    INSERT INTO storage.objects (bucket_id, name, owner) VALUES ('dating-profile-photos', v ->> 'storage_key', v_u);
    PERFORM pg_temp.call(v_u, format($s$SELECT public.insert_dating_profile_photo(%L, %s::smallint)$s$, v ->> 'intent_id', v_n));
  END LOOP;
  IF pg_temp.call(v_u, $s$SELECT public.create_dating_photo_upload_intent('image/jpeg')$s$)
       IS DISTINCT FROM '{"ok": false, "reason": "too_many"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a seventh intent was given';
  END IF;
  -- The list: own photos only, no csam_state, the day-30 date.
  v := pg_temp.call(v_u, 'SELECT public.list_dating_profile_photos()');
  IF jsonb_array_length(v -> 'photos') <> 6 OR v::text ~ 'csam' OR v -> 'after_mutual_from' IS NULL
     OR pg_temp.call(v_other, 'SELECT public.list_dating_profile_photos()') -> 'photos' IS DISTINCT FROM '[]'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the photo list reads %', v;
  END IF;
  -- The guard: Dating off refuses an intent (not_eligible).
  UPDATE public.feature_flags SET enabled = false WHERE key = 'dating_mode_enabled';
  IF pg_temp.call(v_other, $s$SELECT public.create_dating_photo_upload_intent('image/jpeg')$s$) ->> 'reason' IS DISTINCT FROM 'not_eligible' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an intent was given with Dating off';
  END IF;
  -- ... and deleting is never gated, and idempotent. (Each call is its own
  -- statement: a read in the same IF would not see the call's write, I-1.)
  v := pg_temp.call(v_u, format($s$SELECT public.delete_dating_profile_photo(%L)$s$, (SELECT id FROM public.dating_profile_photos WHERE user_id = v_u AND position = 6)));
  v2 := pg_temp.call(v_u, format($s$SELECT public.delete_dating_profile_photo(%L)$s$, gen_random_uuid()));
  IF v IS DISTINCT FROM '{"ok": true}'::jsonb OR v2 IS DISTINCT FROM '{"ok": true}'::jsonb
     OR (SELECT count(*) FROM public.dating_profile_photos WHERE user_id = v_u) <> 5 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a delete was gated or not idempotent';
  END IF;
  UPDATE public.feature_flags SET enabled = true WHERE key = 'dating_mode_enabled';
END $q$;

-- =====================================================================
-- R. (W3c) Reorder: a permutation of one's own photos only; positions 1..n;
--    a replay changes nothing. Captions: own photos, 100 at most, no
--    invisible characters; blank clears.
-- =====================================================================
DO $r$
DECLARE
  v_u constant uuid := pg_temp.ready('b3', 'GB', 'TLI', 'woman', ARRAY['man']);
  v_a uuid;
  v_b uuid;
  v_c uuid;
  v_key text := pg_temp.key('ro');
  v jsonb;
  v2 jsonb;
  v3 jsonb;
  v4 jsonb;
BEGIN
  INSERT INTO public.dating_profile_photos (user_id, storage_key, position) VALUES
    (v_u, 'dating-photos/' || md5('r1') || '.jpg', 1) RETURNING id INTO v_a;
  INSERT INTO public.dating_profile_photos (user_id, storage_key, position) VALUES
    (v_u, 'dating-photos/' || md5('r2') || '.jpg', 2) RETURNING id INTO v_b;
  INSERT INTO public.dating_profile_photos (user_id, storage_key, position) VALUES
    (v_u, 'dating-photos/' || md5('r3') || '.jpg', 4) RETURNING id INTO v_c;
  IF pg_temp.call(v_u, format($s$SELECT public.reorder_dating_photos(%L, ARRAY[%L, %L]::uuid[])$s$, pg_temp.key('x'), v_a, v_b))
       IS DISTINCT FROM '{"ok": false, "reason": "invalid", "field": "order"}'::jsonb
     OR pg_temp.call(v_u, format($s$SELECT public.reorder_dating_photos(%L, ARRAY[%L, %L, %L]::uuid[])$s$, pg_temp.key('x'), v_a, v_a, v_b))
       IS DISTINCT FROM '{"ok": false, "reason": "invalid", "field": "order"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a reorder that is not a permutation was taken';
  END IF;
  v := pg_temp.call(v_u, format($s$SELECT public.reorder_dating_photos(%L, ARRAY[%L, %L, %L]::uuid[])$s$, v_key, v_c, v_a, v_b));
  IF v IS DISTINCT FROM '{"ok": true}'::jsonb
     OR (SELECT string_agg(position::text, ',' ORDER BY id = v_c DESC, id = v_a DESC) FROM public.dating_profile_photos WHERE user_id = v_u) IS DISTINCT FROM '1,2,3' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the reorder did not number the photos 1..3 in order';
  END IF;
  v := pg_temp.call(v_u, format($s$SELECT public.set_dating_photo_caption(%L, 'Me at the beach')$s$, v_a));
  v2 := pg_temp.call(v_u, format($s$SELECT public.set_dating_photo_caption(%L, %L)$s$, v_a, repeat('x', 101)));
  v3 := pg_temp.call(v_u, format($s$SELECT public.set_dating_photo_caption(%L, %L)$s$, v_a, E'hi​there'));
  v4 := pg_temp.call(pg_temp.ready('b4', 'GB', 'TLI', 'man', ARRAY['woman']), format($s$SELECT public.set_dating_photo_caption(%L, 'mine now')$s$, v_a));
  IF v IS DISTINCT FROM '{"ok": true}'::jsonb
     OR v2 IS DISTINCT FROM '{"ok": false, "reason": "invalid", "field": "caption"}'::jsonb
     OR v3 IS DISTINCT FROM '{"ok": false, "reason": "invalid", "field": "caption"}'::jsonb
     OR v4 IS DISTINCT FROM '{"ok": false, "reason": "invalid", "field": "photo"}'::jsonb
     OR (SELECT caption FROM public.dating_profile_photos WHERE id = v_a) IS DISTINCT FROM 'Me at the beach' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: captions are not the owner''s, bounded and clean';
  END IF;
  v := pg_temp.call(v_u, format($s$SELECT public.set_dating_photo_caption(%L, '   ')$s$, v_a));
  IF v IS DISTINCT FROM '{"ok": true}'::jsonb
     OR (SELECT caption FROM public.dating_profile_photos WHERE id = v_a) IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a blank caption did not clear';
  END IF;
END $r$;

-- =====================================================================
-- S. (W3c, I-10, R-25) The CSAM outcome is the service's to record: a hit
--    rejects as "unsafe", holds the Dating account once, and is final; an
--    error leaves the photo unapproved; clear lets Vision's verdict stand.
-- =====================================================================
DO $s$
DECLARE
  v_u constant uuid := pg_temp.ready('b5', 'GB', 'TLI', 'woman', ARRAY['man']);
  v_a uuid;
  v_b uuid;
BEGIN
  IF has_function_privilege('authenticated', 'public.record_dating_photo_csam(uuid,text)', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'public.record_dating_photo_csam(uuid,text)', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the CSAM recorder is not the service role''s alone';
  END IF;
  INSERT INTO public.dating_profile_photos (user_id, storage_key, position) VALUES
    (v_u, 'dating-photos/' || md5('s1') || '.jpg', 1) RETURNING id INTO v_a;
  INSERT INTO public.dating_profile_photos (user_id, storage_key, position) VALUES
    (v_u, 'dating-photos/' || md5('s2') || '.jpg', 2) RETURNING id INTO v_b;
  PERFORM public.record_dating_photo_csam(v_a, 'hit');
  PERFORM public.record_dating_photo_csam(v_b, 'hit');
  PERFORM public.record_dating_photo_csam(v_a, 'clear');
  IF (SELECT csam_state || '/' || moderation_state || '/' || rejection_reason FROM public.dating_profile_photos WHERE id = v_a)
       IS DISTINCT FROM 'hit/rejected/unsafe'
     OR (SELECT count(*) FROM public.dating_account_restrictions WHERE user_id = v_u AND restriction_type = 'moderation_hold' AND lifted_at IS NULL) <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a hit is not rejected/unsafe, final, with one hold';
  END IF;
  DELETE FROM public.dating_account_restrictions WHERE user_id = v_u;
  INSERT INTO public.dating_profile_photos (user_id, storage_key, position) VALUES
    (v_u, 'dating-photos/' || md5('s3') || '.jpg', 3) RETURNING id INTO v_a;
  PERFORM public.record_dating_photo_csam(v_a, 'error');
  IF (SELECT csam_state || '/' || moderation_state FROM public.dating_profile_photos WHERE id = v_a) IS DISTINCT FROM 'error/pending' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a matcher error does not leave the photo pending';
  END IF;
  PERFORM public.record_dating_photo_csam(v_a, 'clear');
  UPDATE public.dating_profile_photos SET moderation_state = 'approved' WHERE id = v_a;
  IF public.record_dating_photo_csam(v_a, 'maybe') IS DISTINCT FROM '{"ok": false, "reason": "invalid", "field": "outcome"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an unknown outcome was taken';
  END IF;
END $s$;

-- =====================================================================
-- T. (R11, R-2) No client reads the photo or intent tables; the owner still
--    uploads by intent and reads her own object through the storage
--    policies' definer predicates; nobody else does.
-- =====================================================================
DO $t$
DECLARE
  v_u constant uuid := pg_temp.ready('b6', 'GB', 'TLI', 'woman', ARRAY['man']);
  v_x constant uuid := pg_temp.ready('b7', 'GB', 'TLI', 'man', ARRAY['woman']);
  v jsonb;
  v_key text;
  v_n bigint;
BEGIN
  IF has_table_privilege('authenticated', 'public.dating_profile_photos', 'SELECT')
     OR has_table_privilege('authenticated', 'public.dating_photo_upload_intents', 'SELECT')
     OR has_any_column_privilege('authenticated', 'public.dating_profile_photos', 'SELECT')
     OR EXISTS (SELECT 1 FROM pg_policies WHERE policyname IN ('dating_profile_photos_select_own', 'dating_photo_upload_intents_select_own')) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a client can still read the photo or intent table';
  END IF;
  v := pg_temp.call(v_u, $s$SELECT public.create_dating_photo_upload_intent('image/jpeg')$s$);
  v_key := v ->> 'storage_key';
  ALTER TABLE storage.objects ENABLE ROW LEVEL SECURITY;
  GRANT SELECT, INSERT ON storage.objects TO authenticated;
  PERFORM pg_temp.as_person(v_u);
  INSERT INTO storage.objects (bucket_id, name, owner) VALUES ('dating-profile-photos', v_key, v_u);
  PERFORM pg_temp.as_db();
  PERFORM pg_temp.as_person(v_x);
  BEGIN
    INSERT INTO storage.objects (bucket_id, name, owner) VALUES ('dating-profile-photos', 'dating-photos/' || md5('t-x') || '.jpg', v_x);
    RAISE EXCEPTION 'CONTRACT VIOLATED: an upload without an intent was let in';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  v_n := (SELECT count(*) FROM storage.objects WHERE name = v_key);
  PERFORM pg_temp.as_db();
  IF v_n <> 0 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a stranger reads another''s upload';
  END IF;
  PERFORM pg_temp.call(v_u, format($s$SELECT public.insert_dating_profile_photo(%L, 1::smallint)$s$, v ->> 'intent_id'));
  PERFORM pg_temp.as_person(v_u);
  v_n := (SELECT count(*) FROM storage.objects WHERE name = v_key);
  PERFORM pg_temp.as_db();
  IF v_n <> 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the owner cannot read her own photo object';
  END IF;
END $t$;

-- =====================================================================
-- U. (I-14) Orphan uploads: an object uploaded under an intent that expired
--    unused is claimed for a scan, and only a recorded scan deletes it
--    (nothing is deleted unscanned); an error releases it for a retry; the
--    sweep is the service role's only.
-- =====================================================================
DO $u$
DECLARE
  v_u constant uuid := pg_temp.ready('b8', 'GB', 'TLI', 'woman', ARRAY['man']);
  v_orphan uuid;
  v_hit uuid;
  v_stale uuid;
  v_key text := 'dating-photos/' || md5('u-orphan') || '.jpg';
  v_hit_key text := 'dating-photos/' || md5('u-hit') || '.jpg';
  v_stale_key text := 'dating-photos/' || md5('u-stale') || '.jpg';
  v_got uuid[];
  v jsonb;
  v_swept bigint := pg_temp.metric('dating.photo.orphan_swept');
  v_errors bigint := pg_temp.metric('dating.photo.orphan_scan_error');
BEGIN
  IF has_function_privilege('authenticated', 'public.claim_dating_orphan_uploads(integer)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.record_dating_orphan_scan(uuid,text)', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'public.claim_dating_orphan_uploads(integer)', 'EXECUTE') THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the orphan sweep is not the service role''s alone';
  END IF;
  -- One orphan, and five that are not: not yet expired, expired just now,
  -- expired with no object, used (a photo), and an unused stamp whose key
  -- is a live photo anyway (a live photo is never swept).
  INSERT INTO public.dating_photo_upload_intents (user_id, storage_key, mime_type, expires_at, created_at)
  VALUES (v_u, v_key, 'image/jpeg', now() - interval '1 hour', now() - interval '2 hours') RETURNING id INTO v_orphan;
  INSERT INTO public.dating_photo_upload_intents (user_id, storage_key, mime_type, expires_at, used_at, created_at) VALUES
    (v_u, 'dating-photos/' || md5('u-fresh') || '.jpg', 'image/jpeg', now() + interval '10 minutes', NULL, now()),
    (v_u, 'dating-photos/' || md5('u-recent') || '.jpg', 'image/jpeg', now() - interval '5 minutes', NULL, now() - interval '20 minutes'),
    (v_u, 'dating-photos/' || md5('u-noobj') || '.jpg', 'image/jpeg', now() - interval '1 hour', NULL, now() - interval '2 hours'),
    (v_u, 'dating-photos/' || md5('u-used') || '.jpg', 'image/jpeg', now() - interval '1 hour', now() - interval '90 minutes', now() - interval '2 hours'),
    (v_u, 'dating-photos/' || md5('u-live') || '.jpg', 'image/jpeg', now() - interval '1 hour', NULL, now() - interval '2 hours');
  INSERT INTO storage.objects (bucket_id, name, owner) VALUES
    ('dating-profile-photos', v_key, v_u),
    ('dating-profile-photos', 'dating-photos/' || md5('u-fresh') || '.jpg', v_u),
    ('dating-profile-photos', 'dating-photos/' || md5('u-recent') || '.jpg', v_u),
    ('dating-profile-photos', 'dating-photos/' || md5('u-used') || '.jpg', v_u),
    ('dating-profile-photos', 'dating-photos/' || md5('u-live') || '.jpg', v_u);
  INSERT INTO public.dating_profile_photos (user_id, storage_key, position) VALUES
    (v_u, 'dating-photos/' || md5('u-used') || '.jpg', 1), (v_u, 'dating-photos/' || md5('u-live') || '.jpg', 2);
  SELECT array_agg(c.intent_id) INTO v_got FROM public.claim_dating_orphan_uploads(50) AS c WHERE c.user_id = v_u;
  IF v_got IS DISTINCT FROM ARRAY[v_orphan] THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the sweep claimed % (only the expired, unused, uploaded intent expected)', v_got;
  END IF;
  -- A claim deletes nothing (the bytes are not scanned yet), and is not
  -- claimed twice.
  IF EXISTS (SELECT 1 FROM public.media_deletion_queue WHERE bucket_id = 'dating-profile-photos' AND object_name = v_key) THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: an orphan was queued for deletion before its scan';
  END IF;
  SELECT array_agg(c.intent_id) INTO v_got FROM public.claim_dating_orphan_uploads(50) AS c WHERE c.user_id = v_u;
  IF v_got IS NOT NULL THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a claimed orphan was claimed again: %', v_got;
  END IF;
  -- The matcher couldn't answer: kept, released, counted; claimed again.
  v := public.record_dating_orphan_scan(v_orphan, 'error');
  IF v IS DISTINCT FROM '{"ok": true}'::jsonb
     OR EXISTS (SELECT 1 FROM public.media_deletion_queue WHERE object_name = v_key)
     OR (SELECT orphan_claimed_at FROM public.dating_photo_upload_intents WHERE id = v_orphan) IS NOT NULL
     OR pg_temp.metric('dating.photo.orphan_scan_error') <> v_errors + 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a failed scan reads % (kept, released, counted)', v;
  END IF;
  SELECT array_agg(c.intent_id) INTO v_got FROM public.claim_dating_orphan_uploads(50) AS c WHERE c.user_id = v_u;
  IF v_got IS DISTINCT FROM ARRAY[v_orphan] THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a released orphan was not claimed again: %', v_got;
  END IF;
  -- Scanned clear: deleted, once.
  v := public.record_dating_orphan_scan(v_orphan, 'clear');
  IF v IS DISTINCT FROM '{"ok": true}'::jsonb
     OR NOT EXISTS (SELECT 1 FROM public.media_deletion_queue WHERE bucket_id = 'dating-profile-photos' AND object_name = v_key)
     OR (SELECT orphan_state FROM public.dating_photo_upload_intents WHERE id = v_orphan) IS DISTINCT FROM 'swept'
     OR pg_temp.metric('dating.photo.orphan_swept') <> v_swept + 1 THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a clear scan reads % (deleted, swept, counted)', v;
  END IF;
  IF public.record_dating_orphan_scan(v_orphan, 'clear') IS DISTINCT FROM '{"ok": false, "reason": "not_claimed"}'::jsonb
     OR public.record_dating_orphan_scan(v_orphan, 'maybe') IS DISTINCT FROM '{"ok": false, "reason": "invalid", "field": "outcome"}'::jsonb THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a swept orphan or an unknown outcome was recorded';
  END IF;
  -- A hit: recorded, and not deleted here (Spec 1's inline record owns the
  -- object: it keeps it when the quarantine copy failed); a claim a dead
  -- worker left 11 minutes ago is claimed again.
  INSERT INTO public.dating_photo_upload_intents (user_id, storage_key, mime_type, expires_at, created_at, orphan_claimed_at) VALUES
    (v_u, v_hit_key, 'image/jpeg', now() - interval '1 hour', now() - interval '2 hours', NULL),
    (v_u, v_stale_key, 'image/jpeg', now() - interval '1 hour', now() - interval '2 hours', now() - interval '11 minutes');
  INSERT INTO storage.objects (bucket_id, name, owner) VALUES
    ('dating-profile-photos', v_hit_key, v_u), ('dating-profile-photos', v_stale_key, v_u);
  SELECT id INTO v_hit FROM public.dating_photo_upload_intents WHERE storage_key = v_hit_key;
  SELECT id INTO v_stale FROM public.dating_photo_upload_intents WHERE storage_key = v_stale_key;
  SELECT array_agg(c.intent_id ORDER BY c.storage_key = v_hit_key DESC) INTO v_got
    FROM public.claim_dating_orphan_uploads(50) AS c WHERE c.user_id = v_u;
  IF v_got IS DISTINCT FROM ARRAY[v_hit, v_stale] THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: the hit and the stale claim were not claimed: %', v_got;
  END IF;
  v := public.record_dating_orphan_scan(v_hit, 'hit');
  IF v IS DISTINCT FROM '{"ok": true}'::jsonb
     OR EXISTS (SELECT 1 FROM public.media_deletion_queue WHERE object_name = v_hit_key)
     OR (SELECT orphan_state FROM public.dating_photo_upload_intents WHERE id = v_hit) IS DISTINCT FROM 'csam' THEN
    RAISE EXCEPTION 'CONTRACT VIOLATED: a hit orphan reads %', v;
  END IF;
END $u$;
```

(Fixture numbers `94`–`9b` must be unused in this file: `grep -n "ready('9[0-9a-b]'" supabase/tests/dating_v2_setup_contracts.sql` before writing; pick the next free ones otherwise. `pg_temp.key(text)` is the file's key helper.)

```bash
D=.superpowers/sdd/2026-11-07-spec2-w3
python3 -I - <<'PY'
import pathlib
p = pathlib.Path('supabase/tests/dating_v2_setup_contracts.sql')
s = p.read_text()
assert s.rstrip().endswith('ROLLBACK;')
body = s.rstrip()[:-len('ROLLBACK;')]
p.write_text(body + pathlib.Path('.superpowers/sdd/2026-11-07-spec2-w3/setup_W3c.sql').read_text() + '\nROLLBACK;\n')
print('dating_v2_setup_contracts.sql: sections P-T added')
PY
psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/dating_v2_setup_contracts.sql 2>&1 | grep -m1 ERROR
```

Expected: `ERROR:  column "csam_state" does not exist` (section P, before the migration).

- [ ] **Step 2: The migration**

Create `supabase/migrations/20261107170000_dating_v2_photos.sql` with exactly:

```sql
-- Spec 2 W3c, migration 1 (§4.9 W3c; §3.2 D9; §4.3 dating_profile_photos,
-- dating_photo_moderation_config; §4.4 Photos; §4.10; I-10, R11; plan
-- R-2, R-24, R-25, R-37): photo positions 1-6, captions (the owner's
-- only), csam_state, the five slot reasons, an approval only after a clear
-- inline CSAM scan, the child-label thresholds; the v2 photo RPCs (the
-- setup guard on everything that adds, never on a delete); the CSAM
-- outcome recorder for process-dating-photo; the two storage.objects
-- policies moved onto definer predicates (same names, commands, roles and
-- bucket), so the photo and intent tables lose their client SELECT (twin)
-- and their row policies. No storage.objects trigger (F-1).
-- Grants in 20261107170010_dating_v2_photos_grants.sql.
BEGIN;
SET LOCAL lock_timeout = '5s';

-- 1. The photo table.
ALTER TABLE public.dating_profile_photos ADD COLUMN IF NOT EXISTS caption text;
ALTER TABLE public.dating_profile_photos ADD COLUMN IF NOT EXISTS csam_state text NOT NULL DEFAULT 'pending';
UPDATE public.dating_profile_photos AS f SET rejection_reason = CASE
    WHEN f.rejection_reason IN ('adult_content_detected', 'violent_content_detected', 'racy_content_detected') THEN 'unsafe'
    WHEN f.rejection_reason IN ('face_blurred', 'face_underexposed', 'face_too_small') THEN 'face_unclear'
    WHEN f.rejection_reason = 'image_too_small' THEN 'too_small'
    ELSE 'needs_review' END
 WHERE f.rejection_reason IS NOT NULL
   AND f.rejection_reason NOT IN ('face_unclear', 'too_small', 'contains_child', 'unsafe', 'needs_review');
-- R-24: an approval needs a clear scan; photos approved before (development
-- only) go back to pending and are scanned again.
UPDATE public.dating_profile_photos AS f
   SET moderation_state = 'pending', rejection_reason = NULL, reviewed_at = NULL
 WHERE f.moderation_state = 'approved' AND f.csam_state IS DISTINCT FROM 'clear';
INSERT INTO public.dating_photo_moderation_outbox (photo_id, user_id)
SELECT f.id, f.user_id FROM public.dating_profile_photos AS f WHERE f.moderation_state = 'pending'
ON CONFLICT (photo_id) DO UPDATE
   SET state = 'pending', attempts = 0, last_error_code = NULL, processing_started_at = NULL,
       completed_at = NULL, updated_at = now()
 WHERE public.dating_photo_moderation_outbox.state IN ('done', 'dead_letter');

ALTER TABLE public.dating_profile_photos DROP CONSTRAINT IF EXISTS dating_profile_photos_position_check;
ALTER TABLE public.dating_profile_photos ADD CONSTRAINT dating_profile_photos_position_check CHECK (position BETWEEN 1 AND 6);
ALTER TABLE public.dating_profile_photos DROP CONSTRAINT IF EXISTS dating_profile_photos_caption_check;
ALTER TABLE public.dating_profile_photos ADD CONSTRAINT dating_profile_photos_caption_check
  CHECK (caption IS NULL OR char_length(caption) BETWEEN 1 AND 100);
ALTER TABLE public.dating_profile_photos DROP CONSTRAINT IF EXISTS dating_profile_photos_csam_state_check;
ALTER TABLE public.dating_profile_photos ADD CONSTRAINT dating_profile_photos_csam_state_check
  CHECK (csam_state IN ('pending', 'clear', 'hit', 'error'));
ALTER TABLE public.dating_profile_photos DROP CONSTRAINT IF EXISTS dating_profile_photos_rejection_reason_check;
ALTER TABLE public.dating_profile_photos ADD CONSTRAINT dating_profile_photos_rejection_reason_check
  CHECK (rejection_reason IS NULL OR rejection_reason IN ('face_unclear', 'too_small', 'contains_child', 'unsafe', 'needs_review'));
ALTER TABLE public.dating_profile_photos DROP CONSTRAINT IF EXISTS dating_profile_photos_approved_clear_check;
ALTER TABLE public.dating_profile_photos ADD CONSTRAINT dating_profile_photos_approved_clear_check
  CHECK (moderation_state <> 'approved' OR csam_state = 'clear');
-- Reorder renumbers inside one statement (deferred, then checked at once).
ALTER TABLE public.dating_profile_photos DROP CONSTRAINT IF EXISTS dating_profile_photos_user_id_position_key;
ALTER TABLE public.dating_profile_photos ADD CONSTRAINT dating_profile_photos_user_id_position_key
  UNIQUE (user_id, position) DEFERRABLE INITIALLY IMMEDIATE;

ALTER TABLE public.dating_photo_moderation_config ADD COLUMN IF NOT EXISTS child_label_reject numeric NOT NULL DEFAULT 0.7;
ALTER TABLE public.dating_photo_moderation_config ADD COLUMN IF NOT EXISTS child_label_review numeric NOT NULL DEFAULT 0.5;
ALTER TABLE public.dating_photo_moderation_config DROP CONSTRAINT IF EXISTS dating_photo_moderation_config_child_check;
ALTER TABLE public.dating_photo_moderation_config ADD CONSTRAINT dating_photo_moderation_config_child_check
  CHECK (child_label_review > 0 AND child_label_review < child_label_reject AND child_label_reject <= 1);

-- 2. The v2 RPCs (return types change: dropped and made again).
DROP FUNCTION IF EXISTS public.create_dating_photo_upload_intent(text);
CREATE FUNCTION public.create_dating_photo_upload_intent(p_mime_type text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
SET lock_timeout = '2s'
AS $$
DECLARE
  v_user constant uuid := auth.uid();
  v_reason text;
  v_ext text;
  v_key text;
  v_id uuid;
  v_expires timestamptz;
  v_try integer;
BEGIN
  v_reason := private.dating_setup_guard();
  IF v_reason IS NOT NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', v_reason);
  END IF;
  v_ext := CASE p_mime_type WHEN 'image/jpeg' THEN 'jpg' WHEN 'image/png' THEN 'png' WHEN 'image/webp' THEN 'webp' END;
  IF v_ext IS NULL THEN
    RETURN private.dating_invalid('mime');
  END IF;
  IF (SELECT count(*) FROM public.dating_profile_photos AS f WHERE f.user_id = v_user) >= 6 THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'too_many');
  END IF;
  BEGIN
    PERFORM public.check_dating_rate_limit('dating_photo_intent', 30, interval '1 day');
  EXCEPTION WHEN invalid_parameter_value THEN
    IF SQLERRM = 'rate_limited' THEN
      RETURN jsonb_build_object('ok', false, 'reason', 'rate_limited');
    END IF;
    RAISE;
  END;
  v_key := 'dating-photos/' || encode(extensions.gen_random_bytes(16), 'hex') || '.' || v_ext;
  -- The shared lock rule (M-9): a bounded retry, then dating:busy.
  FOR v_try IN 1..3 LOOP
    BEGIN
      INSERT INTO public.dating_photo_upload_intents (user_id, storage_key, mime_type, expires_at)
      VALUES (v_user, v_key, p_mime_type, now() + interval '15 minutes')
      RETURNING id, expires_at INTO v_id, v_expires;
      EXIT;
    EXCEPTION WHEN deadlock_detected OR lock_not_available OR serialization_failure THEN
      IF v_try = 3 THEN
        RAISE EXCEPTION 'dating:busy' USING ERRCODE = SQLSTATE;
      END IF;
    END;
  END LOOP;
  RETURN jsonb_build_object('ok', true, 'intent_id', v_id, 'storage_key', v_key,
                            'bucket', 'dating-profile-photos', 'expires_at', v_expires);
END;
$$;

DROP FUNCTION IF EXISTS public.insert_dating_profile_photo(uuid, smallint);
CREATE FUNCTION public.insert_dating_profile_photo(p_intent_id uuid, p_position smallint)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
SET lock_timeout = '2s'
AS $$
DECLARE
  v_user constant uuid := auth.uid();
  v_reason text;
  v_intent public.dating_photo_upload_intents;
  v_photo uuid;
  v_try integer;
BEGIN
  v_reason := private.dating_setup_guard(); -- the setup lock (and the country's same-gender lock) first
  IF v_reason IS NOT NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', v_reason);
  END IF;
  IF p_position IS NULL OR p_position NOT BETWEEN 1 AND 6 THEN
    RETURN private.dating_invalid('position');
  END IF;
  FOR v_try IN 1..3 LOOP
    BEGIN
      SELECT * INTO v_intent FROM public.dating_photo_upload_intents AS i
       WHERE i.id = p_intent_id AND i.user_id = v_user AND i.used_at IS NULL AND i.expires_at > now()
         FOR UPDATE;
      IF NOT FOUND THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'intent_unavailable');
      END IF;
      IF NOT EXISTS (SELECT 1 FROM storage.objects AS o
                      WHERE o.bucket_id = 'dating-profile-photos' AND o.name = v_intent.storage_key) THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'object_missing');
      END IF;
      PERFORM 1 FROM public.dating_profiles AS p WHERE p.user_id = v_user FOR UPDATE;
      IF (SELECT count(*) FROM public.dating_profile_photos AS f
           WHERE f.user_id = v_user AND f.position <> p_position) >= 6 THEN
        RETURN jsonb_build_object('ok', false, 'reason', 'too_many');
      END IF;
      -- A slot replaced: its photo goes (its trigger queues the object's deletion).
      DELETE FROM public.dating_profile_photos AS f WHERE f.user_id = v_user AND f.position = p_position;
      UPDATE public.dating_photo_upload_intents AS i SET used_at = now() WHERE i.id = p_intent_id;
      INSERT INTO public.dating_profile_photos (user_id, storage_key, position, moderation_state, csam_state)
      VALUES (v_user, v_intent.storage_key, p_position, 'pending', 'pending')
      RETURNING id INTO v_photo;
      INSERT INTO public.dating_photo_moderation_outbox (photo_id, user_id) VALUES (v_photo, v_user);
      -- A new photo must match the verification too.
      UPDATE public.dating_profiles AS p SET verification_state = 'needs_review'
       WHERE p.user_id = v_user AND p.verification_state = 'verified';
      EXIT;
    EXCEPTION WHEN deadlock_detected OR lock_not_available OR serialization_failure THEN
      IF v_try = 3 THEN
        RAISE EXCEPTION 'dating:busy' USING ERRCODE = SQLSTATE;
      END IF;
    END;
  END LOOP;
  RETURN jsonb_build_object('ok', true, 'photo_id', v_photo);
END;
$$;

DROP FUNCTION IF EXISTS public.list_dating_profile_photos();
CREATE FUNCTION public.list_dating_profile_photos()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user constant uuid := auth.uid();
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;
  IF public.dating_require_trusted_device() IS NOT TRUE THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'reverify_device');
  END IF;
  -- The owner's own photos; a CSAM hit reads as "unsafe", never named.
  RETURN jsonb_build_object(
    'ok', true,
    'photos', coalesce((
      SELECT jsonb_agg(jsonb_build_object(
               'id', f.id, 'position', f.position, 'state', f.moderation_state,
               'reason', f.rejection_reason, 'caption', f.caption,
               'storage_key', f.storage_key, 'created_at', f.created_at) ORDER BY f.position)
        FROM public.dating_profile_photos AS f WHERE f.user_id = v_user), '[]'::jsonb),
    'after_mutual', coalesce((SELECT p.photos_after_mutual FROM public.dating_profiles AS p WHERE p.user_id = v_user), false),
    'after_mutual_from', (SELECT u.created_at + interval '30 days' FROM public.users AS u WHERE u.id = v_user));
END;
$$;

DROP FUNCTION IF EXISTS public.delete_dating_profile_photo(uuid);
CREATE FUNCTION public.delete_dating_profile_photo(p_photo_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
SET lock_timeout = '1s'
AS $$
DECLARE
  v_user constant uuid := auth.uid();
  v_try integer;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;
  -- Exposure-reducing: never gated, idempotent.
  FOR v_try IN 1..3 LOOP
    BEGIN
      DELETE FROM public.dating_profile_photos AS f WHERE f.id = p_photo_id AND f.user_id = v_user;
      RETURN jsonb_build_object('ok', true);
    EXCEPTION WHEN deadlock_detected OR lock_not_available OR serialization_failure OR query_canceled THEN
      NULL;
    END;
  END LOOP;
  RETURN jsonb_build_object('ok', false, 'reason', 'busy');
END;
$$;

CREATE OR REPLACE FUNCTION public.reorder_dating_photos(p_idempotency_key text, p_order uuid[])
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
SET lock_timeout = '2s'
AS $$
DECLARE
  v_user constant uuid := auth.uid();
  v_reason text;
  v_mine uuid[];
  v_try integer;
BEGIN
  v_reason := private.dating_setup_guard();
  IF v_reason IS NOT NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', v_reason);
  END IF;
  v_mine := ARRAY(SELECT f.id FROM public.dating_profile_photos AS f WHERE f.user_id = v_user ORDER BY f.id);
  IF p_order IS NULL OR cardinality(p_order) IS DISTINCT FROM cardinality(v_mine)
     OR array_position(p_order, NULL) IS NOT NULL
     OR ARRAY(SELECT x FROM unnest(p_order) AS x ORDER BY x) IS DISTINCT FROM v_mine THEN
    RETURN private.dating_invalid('order');
  END IF;
  IF NOT public.claim_dating_idempotency('reorder_dating_photos', p_idempotency_key) THEN
    RETURN jsonb_build_object('ok', true);
  END IF;
  -- The shared lock rule (M-9): a bounded retry, then dating:busy.
  FOR v_try IN 1..3 LOOP
    BEGIN
      SET CONSTRAINTS public.dating_profile_photos_user_id_position_key DEFERRED;
      UPDATE public.dating_profile_photos AS f SET position = o.n
        FROM unnest(p_order) WITH ORDINALITY AS o(id, n)
       WHERE f.id = o.id AND f.user_id = v_user;
      SET CONSTRAINTS public.dating_profile_photos_user_id_position_key IMMEDIATE;
      EXIT;
    EXCEPTION WHEN deadlock_detected OR lock_not_available OR serialization_failure THEN
      IF v_try = 3 THEN
        RAISE EXCEPTION 'dating:busy' USING ERRCODE = SQLSTATE;
      END IF;
    END;
  END LOOP;
  RETURN jsonb_build_object('ok', true);
END;
$$;

-- A caption is shown only to its owner (§4.3; 09 P12): no filter but
-- length and invisible characters; blank clears.
CREATE OR REPLACE FUNCTION public.set_dating_photo_caption(p_photo_id uuid, p_caption text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
SET lock_timeout = '1s'
AS $$
DECLARE
  v_user constant uuid := auth.uid();
  v_text text;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;
  IF public.dating_require_trusted_device() IS NOT TRUE THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'reverify_device');
  END IF;
  IF char_length(p_caption) > 400 THEN
    RETURN private.dating_invalid('caption');
  END IF;
  v_text := nullif(private.dating_trim(coalesce(p_caption, '')), '');
  IF v_text IS NOT NULL AND (char_length(v_text) > 100 OR coalesce(private.dating_has_invisible(v_text), true)) THEN
    RETURN private.dating_invalid('caption');
  END IF;
  UPDATE public.dating_profile_photos AS f SET caption = v_text WHERE f.id = p_photo_id AND f.user_id = v_user;
  IF NOT FOUND THEN
    RETURN private.dating_invalid('photo');
  END IF;
  RETURN jsonb_build_object('ok', true);
END;
$$;

-- 3. process-dating-photo's CSAM outcome (I-10, R-25). A hit is final.
CREATE OR REPLACE FUNCTION public.record_dating_photo_csam(p_photo_id uuid, p_outcome text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user uuid;
BEGIN
  IF p_outcome IS NULL OR p_outcome NOT IN ('clear', 'hit', 'error') THEN
    RETURN private.dating_invalid('outcome');
  END IF;
  SELECT f.user_id INTO v_user FROM public.dating_profile_photos AS f WHERE f.id = p_photo_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'gone');
  END IF;
  IF p_outcome = 'hit' THEN
    UPDATE public.dating_profile_photos AS f
       SET csam_state = 'hit', moderation_state = 'rejected', rejection_reason = 'unsafe', reviewed_at = now()
     WHERE f.id = p_photo_id;
    IF NOT EXISTS (SELECT 1 FROM public.dating_account_restrictions AS r
                    WHERE r.user_id = v_user AND r.restriction_type = 'moderation_hold' AND r.lifted_at IS NULL
                      AND (r.ends_at IS NULL OR r.ends_at > now())) THEN
      -- W7a stamps category 'csam' and source 'csam_hash' (R-25).
      INSERT INTO public.dating_account_restrictions (user_id, restriction_type) VALUES (v_user, 'moderation_hold');
    END IF;
    BEGIN
      PERFORM private.bump_metric_internal('dating.photo.csam_hit');
    EXCEPTION WHEN OTHERS THEN
      NULL;
    END;
  ELSE
    UPDATE public.dating_profile_photos AS f SET csam_state = p_outcome
     WHERE f.id = p_photo_id AND f.csam_state IS DISTINCT FROM 'hit';
  END IF;
  RETURN jsonb_build_object('ok', true);
END;
$$;

-- 4. The storage policies' predicates (R-2): definer reads of the person's
--    own rows, so the tables need no client SELECT.
CREATE OR REPLACE FUNCTION public.dating_storage_intent_open(p_name text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT EXISTS (SELECT 1 FROM public.dating_photo_upload_intents AS i
                  WHERE i.storage_key = p_name AND i.user_id = auth.uid()
                    AND i.used_at IS NULL AND i.expires_at > now());
$$;

CREATE OR REPLACE FUNCTION public.dating_storage_owns(p_name text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT EXISTS (SELECT 1 FROM public.dating_profile_photos AS f
                  WHERE f.storage_key = p_name AND f.user_id = auth.uid());
$$;

DROP POLICY IF EXISTS dating_profile_photos_insert_by_intent ON storage.objects;
CREATE POLICY dating_profile_photos_insert_by_intent ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'dating-profile-photos' AND public.dating_storage_intent_open(name));
DROP POLICY IF EXISTS dating_profile_photos_select_owner ON storage.objects;
CREATE POLICY dating_profile_photos_select_owner ON storage.objects
  FOR SELECT TO authenticated
  USING (bucket_id = 'dating-profile-photos' AND public.dating_storage_owns(name));

DROP POLICY IF EXISTS dating_profile_photos_select_own ON public.dating_profile_photos;
DROP POLICY IF EXISTS dating_photo_upload_intents_select_own ON public.dating_photo_upload_intents;

-- 5. Orphan uploads (I-14): an object uploaded under an intent that then
--    expired unused (no photo row) is scanned like a photo, CSAM first, by
--    process-dating-photo. Clear: deleted here. A match: recorded through
--    Spec 1's inline path, which quarantines a copy and deletes the
--    original (and keeps it when the copy failed: it is then the only
--    evidence). Nothing is deleted unscanned: a claim deletes nothing, and
--    a scan that can't answer releases the claim for a retry.
ALTER TABLE public.dating_photo_upload_intents ADD COLUMN IF NOT EXISTS orphan_claimed_at timestamptz;
ALTER TABLE public.dating_photo_upload_intents ADD COLUMN IF NOT EXISTS orphan_state text;
ALTER TABLE public.dating_photo_upload_intents DROP CONSTRAINT IF EXISTS dating_photo_upload_intents_orphan_state_check;
ALTER TABLE public.dating_photo_upload_intents ADD CONSTRAINT dating_photo_upload_intents_orphan_state_check
  CHECK (orphan_state IS NULL OR orphan_state IN ('swept', 'csam'));

CREATE OR REPLACE FUNCTION public.claim_dating_orphan_uploads(p_limit integer)
RETURNS TABLE (intent_id uuid, user_id uuid, storage_key text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 50 THEN
    RAISE EXCEPTION 'dating:invalid_limit' USING ERRCODE = '22023';
  END IF;
  -- Expired 15 minutes ago, never used, its object there, no photo row;
  -- a claim older than 10 minutes (a worker that died) is claimed again.
  RETURN QUERY
  WITH picked AS (
    SELECT i.id FROM public.dating_photo_upload_intents AS i
     WHERE i.used_at IS NULL AND i.orphan_state IS NULL
       AND i.expires_at < now() - interval '15 minutes'
       AND (i.orphan_claimed_at IS NULL OR i.orphan_claimed_at < now() - interval '10 minutes')
       AND EXISTS (SELECT 1 FROM storage.objects AS o
                    WHERE o.bucket_id = 'dating-profile-photos' AND o.name = i.storage_key)
       AND NOT EXISTS (SELECT 1 FROM public.dating_profile_photos AS f WHERE f.storage_key = i.storage_key)
     ORDER BY i.expires_at
     LIMIT p_limit
       FOR UPDATE OF i SKIP LOCKED)
  UPDATE public.dating_photo_upload_intents AS i SET orphan_claimed_at = now()
    FROM picked WHERE i.id = picked.id
  RETURNING i.id, i.user_id, i.storage_key;
END;
$$;

CREATE OR REPLACE FUNCTION public.record_dating_orphan_scan(p_intent_id uuid, p_outcome text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_intent public.dating_photo_upload_intents;
BEGIN
  IF p_outcome IS NULL OR p_outcome NOT IN ('clear', 'hit', 'error') THEN
    RETURN private.dating_invalid('outcome');
  END IF;
  SELECT * INTO v_intent FROM public.dating_photo_upload_intents AS i WHERE i.id = p_intent_id FOR UPDATE;
  IF NOT FOUND OR v_intent.orphan_claimed_at IS NULL OR v_intent.orphan_state IS NOT NULL
     OR v_intent.used_at IS NOT NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'not_claimed');
  END IF;
  IF p_outcome = 'error' THEN
    -- The matcher couldn't answer: nothing is deleted; the next sweep retries.
    UPDATE public.dating_photo_upload_intents AS i SET orphan_claimed_at = NULL WHERE i.id = p_intent_id;
  ELSIF p_outcome = 'clear' THEN
    -- Scanned clear: the object goes.
    PERFORM public.queue_media_deletion('dating-profile-photos', v_intent.storage_key);
    UPDATE public.dating_photo_upload_intents AS i SET orphan_state = 'swept' WHERE i.id = p_intent_id;
  ELSE
    -- A match: Spec 1's inline record (already made) owns the object's fate;
    -- nothing here deletes evidence.
    UPDATE public.dating_photo_upload_intents AS i SET orphan_state = 'csam' WHERE i.id = p_intent_id;
  END IF;
  BEGIN
    PERFORM private.bump_metric_internal(CASE p_outcome WHEN 'hit' THEN 'dating.photo.orphan_csam'
                                                        WHEN 'clear' THEN 'dating.photo.orphan_swept'
                                                        ELSE 'dating.photo.orphan_scan_error' END);
  EXCEPTION WHEN OTHERS THEN
    NULL;
  END;
  RETURN jsonb_build_object('ok', true);
END;
$$;

-- The sweep runs with process-dating-photo's own invocation (no photo id).
SELECT cron.schedule('sweep-dating-photo-orphans', '*/15 * * * *',
  $cron$SELECT public.invoke_edge_function('process-dating-photo')$cron$);

REVOKE ALL ON FUNCTION public.record_dating_photo_csam(uuid, text) FROM PUBLIC, anon, authenticated;

COMMIT;
```

Create `supabase/migrations/20261107170010_dating_v2_photos_grants.sql` with exactly:

```sql
-- Spec 2 W3c: grants for 20261107170000_dating_v2_photos.sql. R11, R-2: the
-- photo and intent tables lose the client SELECT (table and any column
-- grant). The photo RPCs and the two storage predicates are the app's
-- (the predicates run inside the storage policies as the signed-in role);
-- the CSAM recorder is the service role's alone.
BEGIN;
SET LOCAL lock_timeout = '5s';
REVOKE SELECT ON TABLE public.dating_profile_photos, public.dating_photo_upload_intents FROM authenticated, anon;
DO $cols$
DECLARE
  r record;
BEGIN
  FOR r IN SELECT DISTINCT c.table_name, c.column_name, c.grantee
             FROM information_schema.column_privileges AS c
            WHERE c.table_schema = 'public' AND c.privilege_type = 'SELECT'
              AND c.grantee IN ('authenticated', 'anon')
              AND c.table_name IN ('dating_profile_photos', 'dating_photo_upload_intents') LOOP
    EXECUTE format('REVOKE SELECT (%I) ON TABLE public.%I FROM %I', r.column_name, r.table_name, r.grantee);
  END LOOP;
END $cols$;
REVOKE ALL ON FUNCTION public.create_dating_photo_upload_intent(text) FROM PUBLIC, anon, service_role;
REVOKE ALL ON FUNCTION public.insert_dating_profile_photo(uuid, smallint) FROM PUBLIC, anon, service_role;
REVOKE ALL ON FUNCTION public.list_dating_profile_photos() FROM PUBLIC, anon, service_role;
REVOKE ALL ON FUNCTION public.delete_dating_profile_photo(uuid) FROM PUBLIC, anon, service_role;
REVOKE ALL ON FUNCTION public.reorder_dating_photos(text, uuid[]) FROM PUBLIC, anon, service_role;
REVOKE ALL ON FUNCTION public.set_dating_photo_caption(uuid, text) FROM PUBLIC, anon, service_role;
REVOKE ALL ON FUNCTION public.dating_storage_intent_open(text) FROM PUBLIC, anon, service_role;
REVOKE ALL ON FUNCTION public.dating_storage_owns(text) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.create_dating_photo_upload_intent(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.insert_dating_profile_photo(uuid, smallint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.list_dating_profile_photos() TO authenticated;
GRANT EXECUTE ON FUNCTION public.delete_dating_profile_photo(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.reorder_dating_photos(text, uuid[]) TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_dating_photo_caption(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.dating_storage_intent_open(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.dating_storage_owns(text) TO authenticated;
REVOKE ALL ON FUNCTION public.record_dating_photo_csam(uuid, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.record_dating_photo_csam(uuid, text) TO service_role;
-- I-14: the orphan sweep is the photo worker's (the service role's) only.
REVOKE ALL ON FUNCTION public.claim_dating_orphan_uploads(integer) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.record_dating_orphan_scan(uuid, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.claim_dating_orphan_uploads(integer) TO service_role;
GRANT EXECUTE ON FUNCTION public.record_dating_orphan_scan(uuid, text) TO service_role;
COMMIT;
```

```bash
D=.superpowers/sdd/2026-11-07-spec2-w3
grep -rn 'ON CONFLICT (user_id, position)\|ON CONFLICT (user_id, "position")' supabase/migrations supabase/tests | grep -v 20260813130000
for f in supabase/migrations/20261107170000_dating_v2_photos.sql supabase/migrations/20261107170010_dating_v2_photos_grants.sql; do
  for run in 1 2; do psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f $f > /dev/null; echo "$(basename $f) run $run exit=$?"; done
done
python3 -I $D/grants_line.py supabase/migrations/20261107160010_dating_v2_setup_lists_grants.sql \
  "Spec 2 W3c: the photo and intent tables lose the client SELECT (R11); the photo RPCs and the storage predicates are the app's; the CSAM recorder and the orphan sweep are the service role's." \
  supabase/migrations/20261107170010_dating_v2_photos_grants.sql
```

Expected: no `grep` output (a deferrable unique can't be an `ON CONFLICT` arbiter; nothing else uses it); four `exit=0`; the grants line.

- [ ] **Step 3: The contracts W3c changes (G3, the bucket hashes, the canary)**

Create `$D/edit_T8.py` with exactly:

```python
import os, pathlib, subprocess, sys
sys.path.insert(0, '.superpowers/sdd/2026-11-07-spec2-w3')
from anchor import edit
S = 'supabase/tests/dating_v2_setup_contracts.sql'
edit(S, [
    # G3: the owner now reads her object only; the table is no client's (R11).
    ("    IF v_role = 'authenticated' THEN\n      v_read := v_read + (SELECT count(*) FROM public.dating_profile_photos WHERE user_id = v_u);\n    END IF;\n",
     "    -- Spec 2 W3c (R11): no client reads the photo table any more.\n"
     "    IF v_role = 'authenticated' AND has_table_privilege('authenticated', 'public.dating_profile_photos', 'SELECT') THEN\n"
     "      RAISE EXCEPTION 'CONTRACT VIOLATED: authenticated can read dating_profile_photos';\n    END IF;\n"),
    ("    IF v_read IS DISTINCT FROM (CASE WHEN v_x = v_u THEN 3 ELSE 0 END)::bigint OR v_upd <> 0 OR v_del <> 0 THEN",
     "    IF v_read IS DISTINCT FROM (CASE WHEN v_x = v_u THEN 1 ELSE 0 END)::bigint OR v_upd <> 0 OR v_del <> 0 THEN"),
    ("(stranger 0/0/0, owner 3/0/0)", "(stranger 0/0/0, owner 1/0/0)"),
    ("  IF v_got IS DISTINCT FROM 'private.dating_exit_internal(uuid, boolean):; private.dating_next_step(uuid):; public.create_dating_photo_upload_intent(text):; public.dating_photos_queue_media_before_delete():; public.dating_profile_complete(uuid):; public.delete_dating_profile_photo(uuid):authenticated; public.get_dating_operational_health():service_role; public.get_dating_profile_preview():authenticated; public.insert_dating_profile_photo(uuid, smallint):; public.list_dating_profile_photos():authenticated; public.prepare_account_deletion(uuid):service_role' THEN",
     "  -- Spec 2 W3c: the v2 photo RPCs (the app's), the owner-read storage\n"
     "  -- predicate (the app's: it runs inside the storage policy) and the CSAM\n"
     "  -- recorder and the orphan sweep (the service role's, I-14). None returns\n"
     "  -- a photo to anyone else.\n"
     "  IF v_got IS DISTINCT FROM 'private.dating_exit_internal(uuid, boolean):; private.dating_next_step(uuid):; public.claim_dating_orphan_uploads(integer):service_role; public.create_dating_photo_upload_intent(text):authenticated; public.dating_photos_queue_media_before_delete():; public.dating_profile_complete(uuid):; public.dating_storage_owns(text):authenticated; public.delete_dating_profile_photo(uuid):authenticated; public.get_dating_operational_health():service_role; public.get_dating_profile_preview():authenticated; public.insert_dating_profile_photo(uuid, smallint):authenticated; public.list_dating_profile_photos():authenticated; public.prepare_account_deletion(uuid):service_role; public.record_dating_orphan_scan(uuid, text):service_role; public.record_dating_photo_csam(uuid, text):service_role; public.reorder_dating_photos(text, uuid[]):authenticated; public.set_dating_photo_caption(uuid, text):authenticated' THEN"),
], 'T8 G3')

# The two storage policies' new hashes, read from the database just migrated.
rows = subprocess.run(['psql', '-X', '-At', '-d', os.environ.get('W3_DB', 'attune_spec3a'), '-c',
    "select policyname || '=' || md5(coalesce(qual, '') || '|' || coalesce(with_check, '')) from pg_policies "
    "where schemaname = 'storage' and tablename = 'objects' and policyname in "
    "('dating_profile_photos_insert_by_intent', 'dating_profile_photos_select_owner') order by policyname"],
    capture_output=True, text=True, check=True).stdout.split()
assert len(rows) == 2, rows
edit('supabase/tests/storage_bucket_policies.sql', [
    ("  IF v_got IS DISTINCT FROM 'dating_profile_photos_insert_by_intent=05db310ea7b8f81fdc3d1e6c5dacc318;'\n"
     "                            'dating_profile_photos_select_owner=17e2b968cf902d0ad91fde017e587929' THEN",
     "  -- Spec 2 W3c (R-2): both policies call definer predicates now.\n"
     f"  IF v_got IS DISTINCT FROM '{rows[0]};'\n"
     f"                            '{rows[1]}' THEN"),
], 'T8 bucket hashes')

# R-24: the older contracts' approved-photo fixtures stand for scanned
# photos; each file is one transaction, so the default is rolled back with it.
FIXTURE = ("\nBEGIN;\n",
           "\nBEGIN;\n-- Spec 2 W3c (R-24): this file's photo fixtures stand for photos the\n"
           "-- inline CSAM scan cleared (an approval needs csam_state 'clear');\n"
           "-- rolled back with the file.\n"
           "ALTER TABLE public.dating_profile_photos ALTER COLUMN csam_state SET DEFAULT 'clear';\n")
for f in ['dating_v2_setup_contracts', 'dating_v2_identity_contracts', 'dating_v2_home_contracts',
          'dating_mode_contracts', 'identity_foundation_contracts']:
    edit(f'supabase/tests/{f}.sql', [FIXTURE], 'T8 fixture default')

edit('supabase/tests/dating_rls_canary.sql', [
    ("-- ---------------------------------------------------------------------\n"
     "-- Checks (every batch adds its rows above this line).\n",
     "-- W3c (migration 1): the photo and intent tables lose the client SELECT\n"
     "-- (R11, R-2); the v2 photo RPCs and the storage predicates are the app's;\n"
     "-- the CSAM recorder is the service role's.\n"
     "UPDATE allowed_rel SET authenticated = '' WHERE name IN ('dating_photo_upload_intents', 'dating_profile_photos');\n"
     "UPDATE allowed_fn SET clients = 'authenticated'\n"
     " WHERE sig IN ('create_dating_photo_upload_intent(text)', 'insert_dating_profile_photo(uuid,smallint)');\n"
     "INSERT INTO allowed_fn (sig, clients, service) VALUES\n"
     "  ('dating_storage_intent_open(text)', 'authenticated', ''),\n"
     "  ('dating_storage_owns(text)', 'authenticated', ''),\n"
     "  ('claim_dating_orphan_uploads(integer)', '', 'service_role'),\n"
     "  ('record_dating_orphan_scan(uuid,text)', '', 'service_role'),\n"
     "  ('record_dating_photo_csam(uuid,text)', '', 'service_role'),\n"
     "  ('reorder_dating_photos(text,uuid[])', 'authenticated', ''),\n"
     "  ('set_dating_photo_caption(uuid,text)', 'authenticated', '');\n"
     "-- ---------------------------------------------------------------------\n"
     "-- Checks (every batch adds its rows above this line).\n"),
], 'T8 canary')

# I-6: W1's N-I1 pinned "no client can start a Dating upload". From W3c the
# v2 intent and insert RPCs are the app's (the setup guard and the intent
# answer); no client writes the intent table itself, and no other client
# function writes it.
edit('supabase/tests/dating_v2_identity_contracts.sql', [
    ("  -- N-I1: no client can start a Dating upload: both v1 photo writers are\n"
     "  -- refused, no client can write an upload intent, and no function a client\n"
     "  -- can run writes one (the bucket's INSERT policy needs an intent).\n"
     "  v_msg := pg_temp.err_as(v_a, 'SELECT * FROM public.create_dating_photo_upload_intent(''image/jpeg'')');\n"
     "  IF v_msg IS DISTINCT FROM 'permission denied for function create_dating_photo_upload_intent' THEN\n"
     "    RAISE EXCEPTION 'CONTRACT VIOLATED: a signed-in user can still create a Dating upload intent (%)', v_msg;\n"
     "  END IF;\n"
     "  v_msg := pg_temp.err_as(v_a, format('SELECT public.insert_dating_profile_photo(%L, 1::smallint)', gen_random_uuid()));\n"
     "  IF v_msg IS DISTINCT FROM 'permission denied for function insert_dating_profile_photo' THEN\n"
     "    RAISE EXCEPTION 'CONTRACT VIOLATED: a signed-in user can still attach a Dating photo (%)', v_msg;\n"
     "  END IF;\n",
     "  -- N-I1, as of Spec 2 W3c: the v2 intent and insert RPCs are the app's\n"
     "  -- (the setup guard and the intent answer, never a raw error); no client\n"
     "  -- writes the intent table itself, and no other client function does.\n"
     "  v_msg := pg_temp.err_as(v_a, 'SELECT * FROM public.create_dating_photo_upload_intent(''image/jpeg'')');\n"
     "  IF v_msg IS NOT NULL THEN\n"
     "    RAISE EXCEPTION 'CONTRACT VIOLATED: the v2 upload intent raised for a signed-in user (%)', v_msg;\n"
     "  END IF;\n"
     "  v_msg := pg_temp.err_as(v_a, format('SELECT public.insert_dating_profile_photo(%L, 1::smallint)', gen_random_uuid()));\n"
     "  IF v_msg IS NOT NULL THEN\n"
     "    RAISE EXCEPTION 'CONTRACT VIOLATED: the v2 photo insert raised for a signed-in user (%)', v_msg;\n"
     "  END IF;\n"),
    ("                 WHERE n.nspname IN ('public', 'private') AND p.prosrc ~* 'insert\\s+into\\s+public\\.dating_photo_upload_intents'\n",
     "                 WHERE n.nspname IN ('public', 'private') AND p.prosrc ~* 'insert\\s+into\\s+public\\.dating_photo_upload_intents'\n"
     "                   AND p.oid IS DISTINCT FROM 'public.create_dating_photo_upload_intent(text)'::regprocedure\n"),
], 'T8 identity N-I1 (I-6)')
```

```bash
D=.superpowers/sdd/2026-11-07-spec2-w3
grep -n "'create_dating_photo_upload_intent(text)'" supabase/tests/dating_rls_canary.sql
python3 -I $D/edit_T8.py
for f in dating_v2_setup_contracts storage_bucket_policies dating_rls_canary dating_v2_identity_contracts dating_v2_home_contracts dating_mode_contracts identity_foundation_contracts account_deletion_contracts dating_v2_client_reads_contracts; do
  psql -X -q -v ON_ERROR_STOP=1 -d attune_spec3a -f supabase/tests/$f.sql > /dev/null 2>/tmp/w3c.err && echo "PASS $f" || echo "FAIL $f: $(grep -m1 ERROR /tmp/w3c.err)"
done; rm -f /tmp/w3c.err
```

Expected: the canary already has a `create_dating_photo_upload_intent(text)` row (if not, change that `UPDATE` to an `INSERT` row and say so); the edit lines (G3, the bucket hashes, five `T8 fixture default` lines, the canary); nine `PASS` (account deletion queues photo objects through the unchanged before-delete trigger; exit's hard delete is unchanged). A G3 list that differs from the edited expectation names a function this task didn't plan: stop and report it, never paste it in.

- [ ] **Step 4: Mutants**

Create `$D/mut_T8.py` with exactly:

```python
MUTS = {
 'approve_without_scan': ("ALTER TABLE public.dating_profile_photos ADD CONSTRAINT dating_profile_photos_approved_clear_check\n  CHECK (moderation_state <> 'approved' OR csam_state = 'clear');\n", ""),
 'seven_positions': ("CHECK (position BETWEEN 1 AND 6);", "CHECK (position BETWEEN 1 AND 7);"),
 'intent_unguarded': ("  v_reason := private.dating_setup_guard();\n  IF v_reason IS NOT NULL THEN\n    RETURN jsonb_build_object('ok', false, 'reason', v_reason);\n  END IF;\n  v_ext := CASE", "  v_ext := CASE"),
 'intent_no_cap': ("  IF (SELECT count(*) FROM public.dating_profile_photos AS f WHERE f.user_id = v_user) >= 6 THEN\n    RETURN jsonb_build_object('ok', false, 'reason', 'too_many');\n  END IF;\n  BEGIN", "  BEGIN"),
 'insert_any_intent': ("       WHERE i.id = p_intent_id AND i.user_id = v_user AND i.used_at IS NULL AND i.expires_at > now()", "       WHERE i.id = p_intent_id AND i.used_at IS NULL AND i.expires_at > now()"),
 'replace_keeps_old': ("      DELETE FROM public.dating_profile_photos AS f WHERE f.user_id = v_user AND f.position = p_position;\n", "      UPDATE public.dating_profile_photos AS f SET position = 6 WHERE f.user_id = v_user AND f.position = p_position AND false;\n"),
 'list_names_csam': ("               'reason', f.rejection_reason, 'caption', f.caption,", "               'reason', f.rejection_reason, 'caption', f.caption, 'csam', f.csam_state,"),
 'delete_gated': ("  -- Exposure-reducing: never gated, idempotent.\n", "  IF public.dating_eligibility(v_user, 'setup') IS DISTINCT FROM 'eligible' THEN RETURN jsonb_build_object('ok', false, 'reason', 'not_eligible'); END IF;\n"),
 'reorder_any_ids': ("     OR ARRAY(SELECT x FROM unnest(p_order) AS x ORDER BY x) IS DISTINCT FROM v_mine THEN", "     OR false THEN"),
 'caption_unbounded': ("  IF v_text IS NOT NULL AND (char_length(v_text) > 100 OR coalesce(private.dating_has_invisible(v_text), true)) THEN", "  IF false THEN"),
 'caption_anyones': ("  UPDATE public.dating_profile_photos AS f SET caption = v_text WHERE f.id = p_photo_id AND f.user_id = v_user;", "  UPDATE public.dating_profile_photos AS f SET caption = v_text WHERE f.id = p_photo_id;"),
 'hit_overwritten': ("     WHERE f.id = p_photo_id AND f.csam_state IS DISTINCT FROM 'hit';", "     WHERE f.id = p_photo_id;"),
 'hit_two_holds': ("    IF NOT EXISTS (SELECT 1 FROM public.dating_account_restrictions AS r", "    IF true OR NOT EXISTS (SELECT 1 FROM public.dating_account_restrictions AS r"),
 'storage_owner_anyone': ("                  WHERE f.storage_key = p_name AND f.user_id = auth.uid());", "                  WHERE f.storage_key = p_name);"),
 'storage_insert_no_intent': ("                  WHERE i.storage_key = p_name AND i.user_id = auth.uid()\n                    AND i.used_at IS NULL AND i.expires_at > now());", "                  WHERE true);"),
 # I-14: the orphan sweep.
 'orphan_takes_photos': ("       AND NOT EXISTS (SELECT 1 FROM public.dating_profile_photos AS f WHERE f.storage_key = i.storage_key)\n", ""),
 'orphan_no_grace': ("       AND i.expires_at < now() - interval '15 minutes'\n", ""),
 'orphan_error_deletes': ("    -- The matcher couldn't answer: nothing is deleted; the next sweep retries.\n", "    PERFORM public.queue_media_deletion('dating-profile-photos', v_intent.storage_key);\n"),
 'orphan_error_kept_claimed': ("    UPDATE public.dating_photo_upload_intents AS i SET orphan_claimed_at = NULL WHERE i.id = p_intent_id;\n", "    NULL;\n"),
 'orphan_hit_deletes': ("    UPDATE public.dating_photo_upload_intents AS i SET orphan_state = 'csam' WHERE i.id = p_intent_id;\n", "    PERFORM public.queue_media_deletion('dating-profile-photos', v_intent.storage_key);\n    UPDATE public.dating_photo_upload_intents AS i SET orphan_state = 'csam' WHERE i.id = p_intent_id;\n"),
 'orphan_claim_twice': ("       AND (i.orphan_claimed_at IS NULL OR i.orphan_claimed_at < now() - interval '10 minutes')\n", ""),
}
```

```bash
python3 -I $D/mutate.py supabase/migrations/20261107170000_dating_v2_photos.sql supabase/tests/dating_v2_setup_contracts.sql $D/mut_T8.py $D/mut supabase/migrations/20261107170010_dating_v2_photos_grants.sql | tee $D/mut_T8.txt
```

Expected (verified on a clone of `attune_spec3a`, fix round 1): 21 lines, none `NO ERROR (mutant survived)`. The grants twin runs after each mutant (I-7), so a DROP + CREATE'd RPC keeps its real grants and each mutant dies at its own assertion, not at G3's privilege list: `storage_insert_no_intent` in T (the upload without an intent let in); `storage_owner_anyone` in T (a stranger reads); the six `orphan_*` mutants in U (`orphan_takes_photos` and `orphan_no_grace`: "the sweep claimed …"; `orphan_error_deletes` and `orphan_error_kept_claimed`: "a failed scan reads …"; `orphan_hit_deletes`: "a hit orphan reads …" (a match's object is Spec 1's to keep or delete: it is the only evidence when the quarantine copy failed); `orphan_claim_twice`: "a claimed orphan was claimed again"). Two die at a table constraint, which is the backstop the RPC's check stands in front of (M-3): `replace_keeps_old` (`dating_profile_photos_user_id_position_key`) and `caption_unbounded` (`dating_profile_photos_caption_check`).

- [ ] **Step 5: The suite; do not commit; record the tree in the report.**

`$D/suite.sh attune_spec3a` → `159 PASS, 14 FAIL`, no new FAIL against the baseline.

### Task 9: `process-dating-photo` CSAM-first with child labels and slot reasons; `upload-dating-photo` removed; the image preparer at 1600 px (§3.2 D9 Server/Client, §4.7, §4.10, §7.3 `process-dating-photo`; I-10; R-23, R-25)

**Files:**
- Create: `supabase/functions/process-dating-photo/handler.ts`, `supabase/functions/process-dating-photo/handler.test.ts`
- Modify: `supabase/functions/process-dating-photo/index.ts` (rewired onto the handler), `supabase/functions/_shared/google_vision.ts` (label detection, slot reasons), `supabase/functions/_shared/google_vision.test.ts` (rewritten for the slot reasons), `lib/features/dating/domain/services/dating_image_preparer.dart`, `test/features/dating/dating_image_preparer_test.dart` (one test added), `.github/workflows/tests.yml` (one path in the Deno job)
- Delete: `supabase/functions/upload-dating-photo/`

**Interfaces:**
- Consumes: `CsamMatcher`, `matcherFromEnv` (`_shared/csam_matcher.ts`); `quarantineAndRecord`, `inlineRecorder`, `storageQuarantine`, `QuarantineStore`, `MatchRpcClient` (`_shared/csam_match_path.ts`); Task 8's `record_dating_photo_csam`, the reasons and the child thresholds; `claim_dating_photo_jobs` (unchanged).
- Produces: `processPhotoJob(job: PhotoJob, deps: PhotoDeps): Promise<JobOutcome>` (`"approved" | "rejected" | "needs_review" | "csam_hit" | "retry" | "dead"`); `sweepOrphan(o: Orphan, deps: OrphanDeps): Promise<"swept" | "csam_hit" | "retry">` (I-14, R-46: CSAM first, then `record_dating_orphan_scan`; never deletes unscanned) and `index.ts` running it on the cron call (no photo id, up to 10 orphans); `decideModerationOutcome(result, config)` returning the five slot reasons; `VisionModerationResult.childLabelScore`; `DatingImagePreparer` (long side ≤ 1600 px, quality 80, temp name `p_<micros>.jpg`).

- [ ] **Step 1: Write the failing Deno tests**

Create `supabase/functions/process-dating-photo/handler.test.ts` with exactly (local imports only, so the CI lockfile is unchanged):

```ts
// Spec 2 W3c (§3.2 D9, §7.3, I-10): the inline CSAM scan runs first and
// once; a match is quarantined and recorded through Spec 1's path, Vision is
// never called, and the photo is rejected; a matcher error never approves;
// child labels reject or go to a person; the slot reasons.
import type { CsamMatcher, MatchResult } from "../_shared/csam_matcher.ts";
import type { QuarantineStore } from "../_shared/csam_match_path.ts";
import type { VisionModerationResult } from "../_shared/google_vision.ts";
import { type OrphanDeps, type PhotoDeps, processPhotoJob, sweepOrphan } from "./handler.ts";

function eq(actual: unknown, expected: unknown, why = "") {
  const a = JSON.stringify(actual), e = JSON.stringify(expected);
  if (a !== e) throw new Error(`${why} expected ${e}, got ${a}`);
}

/** A JPEG header the dimension reader and the metadata strip both accept. */
function jpeg(width: number, height: number): Uint8Array {
  return new Uint8Array([
    0xFF, 0xD8,
    0xFF, 0xC0, 0x00, 0x11, 0x08, height >> 8, height & 255, width >> 8, width & 255,
    0x03, 0x01, 0x22, 0x00, 0x02, 0x11, 0x01, 0x03, 0x11, 0x01,
    0xFF, 0xDA, 0x00, 0x08, 0x01, 0x01, 0x00, 0x00, 0x3F, 0x00, 0x11, 0x22,
  ]);
}

const goodVision: VisionModerationResult = {
  safeSearchFlags: { adult: "VERY_UNLIKELY", violence: "VERY_UNLIKELY", racy: "UNLIKELY", medical: "UNLIKELY", spoof: "UNLIKELY" },
  faceDetected: true,
  faceConfidence: 0.95,
  faceBlurred: false,
  faceUnderexposed: false,
  faceAreaRatio: null,
  faceBoundingPolyVertices: [{ x: 100, y: 100 }, { x: 500, y: 100 }, { x: 500, y: 500 }, { x: 100, y: 500 }],
  childLabelScore: null,
};

function deps(over: { match?: MatchResult["outcome"]; vision?: Partial<VisionModerationResult>; bytes?: Uint8Array } = {}) {
  const log: string[] = [];
  const rpcs: Array<[string, Record<string, unknown> | undefined]> = [];
  const verdicts: Array<[string, string, string | null]> = [];
  const finishes: Array<[string, string]> = [];
  const quarantined: Uint8Array[] = [];
  const bytes = over.bytes ?? jpeg(1200, 1600);
  const matcher: CsamMatcher = {
    name: "fake",
    supportsVideo: false,
    async match(b) {
      log.push("csam");
      if (b !== bytes) throw new Error("the matcher did not get the downloaded bytes");
      return { outcome: over.match ?? "clear", vendor: "fake", vendorRef: over.match === "match" ? "ref-1" : null };
    },
  };
  const quarantine: QuarantineStore = {
    async put(_path, b) {
      log.push("quarantine");
      quarantined.push(b);
      return "stored";
    },
  };
  const d: PhotoDeps = {
    rpc: (fn, args) => {
      log.push(`rpc:${fn}${args && "p_outcome" in args ? `:${args.p_outcome}` : ""}`);
      rpcs.push([fn, args]);
      return Promise.resolve({ data: fn === "record_inline_csam_match" ? 7 : { ok: true }, error: null });
    },
    photo: async (id) => ({ id, user_id: "u-1", storage_key: "dating-photos/abc.jpg" }),
    download: async () => (log.push("download"), bytes),
    replace: async () => (log.push("replace"), true),
    verdict: async (id, state, reason) => { log.push(`verdict:${state}`); verdicts.push([id, state, reason]); },
    finish: async (id, state) => { log.push(`finish:${state}`); finishes.push([id, state]); },
    vision: async () => (log.push("vision"), { ...goodVision, ...over.vision }),
    matcher,
    quarantine,
    config: { minFaceConfidence: 0.7, minFaceAreaRatio: 0.06, childLabelReject: 0.7, childLabelReview: 0.5 },
  };
  return { d, log, rpcs, verdicts, finishes, quarantined, bytes };
}

Deno.test("clear: CSAM first and once, then Vision, the strip, approved", async () => {
  const t = deps();
  eq(await processPhotoJob({ photo_id: "p1", attempts: 1 }, t.d), "approved");
  eq(t.log, ["download", "csam", "rpc:record_dating_photo_csam:clear", "vision", "replace", "verdict:approved", "finish:done"]);
});

Deno.test("a match: quarantined with the scanned bytes, recorded once through Spec 1, the photo rejected, Vision never called", async () => {
  const t = deps({ match: "match" });
  eq(await processPhotoJob({ photo_id: "p2", attempts: 1 }, t.d), "csam_hit");
  eq(t.log.filter((l) => l === "csam").length, 1);
  if (t.log.includes("vision")) throw new Error("Vision ran after a match");
  if (t.quarantined[0] !== t.bytes) throw new Error("the quarantine copy is not the scanned bytes");
  eq(t.rpcs.filter(([fn]) => fn === "record_inline_csam_match").length, 1);
  const inline = t.rpcs.find(([fn]) => fn === "record_inline_csam_match")![1]!;
  eq([inline.p_bucket, inline.p_object_name, inline.p_owner, inline.p_quarantined], ["dating-profile-photos", "dating-photos/abc.jpg", "u-1", true]);
  eq(t.log.indexOf("quarantine") < t.log.indexOf("rpc:record_inline_csam_match"), true, "copy before record");
  eq(t.log.includes("rpc:record_dating_photo_csam:hit"), true);
  eq(t.verdicts, []);
  eq(t.finishes, [["p2", "done"]]);
});

Deno.test("a matcher error never approves: csam error, retried, no Vision", async () => {
  const t = deps({ match: "unavailable" });
  eq(await processPhotoJob({ photo_id: "p3", attempts: 1 }, t.d), "retry");
  eq(t.log.includes("rpc:record_dating_photo_csam:error"), true);
  if (t.log.includes("vision")) throw new Error("Vision ran without a clear scan");
  eq(t.verdicts, []);
  eq(t.finishes, [["p3", "pending"]]);
});

Deno.test("the last attempt: needs a person, dead-lettered, never approved", async () => {
  const t = deps({ match: "unavailable" });
  eq(await processPhotoJob({ photo_id: "p4", attempts: 5 }, t.d), "dead");
  eq(t.verdicts, [["p4", "needs_review", "needs_review"]]);
  eq(t.finishes, [["p4", "dead_letter"]]);
});

Deno.test("child labels: 0.8 rejects (contains_child), 0.6 goes to a person", async () => {
  const a = deps({ vision: { childLabelScore: 0.8 } });
  eq(await processPhotoJob({ photo_id: "p5" }, a.d), "rejected");
  eq(a.verdicts, [["p5", "rejected", "contains_child"]]);
  const b = deps({ vision: { childLabelScore: 0.6 } });
  eq(await processPhotoJob({ photo_id: "p6" }, b.d), "needs_review");
  eq(b.verdicts, [["p6", "needs_review", "needs_review"]]);
});

Deno.test("too small: rejected after the CSAM scan, before Vision", async () => {
  const t = deps({ bytes: jpeg(400, 400) });
  eq(await processPhotoJob({ photo_id: "p7" }, t.d), "rejected");
  eq(t.verdicts, [["p7", "rejected", "too_small"]]);
  eq(t.log.includes("csam"), true);
  if (t.log.includes("vision")) throw new Error("Vision ran on a too-small photo");
});

Deno.test("unsafe and an unclear face read as their slot reasons", async () => {
  const a = deps({ vision: { safeSearchFlags: { ...goodVision.safeSearchFlags, adult: "LIKELY" } } });
  await processPhotoJob({ photo_id: "p8" }, a.d);
  eq(a.verdicts, [["p8", "rejected", "unsafe"]]);
  const b = deps({ vision: { faceBlurred: true } });
  await processPhotoJob({ photo_id: "p9" }, b.d);
  eq(b.verdicts, [["p9", "rejected", "face_unclear"]]);
  const c = deps({ vision: { faceDetected: false } });
  await processPhotoJob({ photo_id: "pa" }, c.d);
  eq(c.verdicts, [["pa", "needs_review", "needs_review"]]);
});

// I-14: orphan uploads (an intent that expired unused, its object there).
function orphanDeps(over: { match?: MatchResult["outcome"]; bytes?: Uint8Array | null; throws?: boolean } = {}) {
  const log: string[] = [];
  const bytes = over.bytes === undefined ? jpeg(1200, 1600) : over.bytes;
  const d: OrphanDeps = {
    rpc: (fn, args) => {
      log.push(`rpc:${fn}${args && "p_outcome" in args ? `:${args.p_outcome}` : ""}`);
      return Promise.resolve({ data: fn === "record_inline_csam_match" ? 7 : { ok: true }, error: null });
    },
    download: async () => (log.push("download"), bytes),
    matcher: {
      name: "fake",
      supportsVideo: false,
      async match(b) {
        log.push("csam");
        if (over.throws) throw new Error("vendor down");
        if (b !== bytes) throw new Error("the matcher did not get the downloaded bytes");
        return { outcome: over.match ?? "clear", vendor: "fake", vendorRef: over.match === "match" ? "ref-o" : null };
      },
    },
    quarantine: { async put() { log.push("quarantine"); return "stored"; } },
  };
  return { d, log };
}
const orphan = { intent_id: "i-1", user_id: "u-1", storage_key: "dating-photos/orphan.jpg" };

Deno.test("orphan clear: scanned first, then recorded clear (its deletion queued)", async () => {
  const t = orphanDeps();
  eq(await sweepOrphan(orphan, t.d), "swept");
  eq(t.log, ["download", "csam", "rpc:record_dating_orphan_scan:clear"]);
});

Deno.test("orphan match: quarantined and recorded through Spec 1, then hit; never cleared", async () => {
  const t = orphanDeps({ match: "match" });
  eq(await sweepOrphan(orphan, t.d), "csam_hit");
  eq(t.log, ["download", "csam", "quarantine", "rpc:record_inline_csam_match", "rpc:record_dating_orphan_scan:hit"]);
});

Deno.test("orphan: a matcher that can't answer, throws or has no bytes never clears (no deletion unscanned)", async () => {
  for (const over of [{ match: "unavailable" as const }, { throws: true }, { bytes: null }]) {
    const t = orphanDeps(over);
    eq(await sweepOrphan(orphan, t.d), "retry", JSON.stringify(over));
    eq(t.log.includes("rpc:record_dating_orphan_scan:clear"), false, JSON.stringify(over));
    eq(t.log.at(-1), "rpc:record_dating_orphan_scan:error", JSON.stringify(over));
  }
});
```

Replace the whole of `supabase/functions/_shared/google_vision.test.ts` with exactly:

```ts
import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { decideModerationOutcome, type VisionModerationResult } from "./google_vision.ts";

const base: VisionModerationResult = {
  safeSearchFlags: { adult: "VERY_UNLIKELY", violence: "VERY_UNLIKELY", racy: "UNLIKELY", medical: "UNLIKELY", spoof: "UNLIKELY" },
  faceDetected: true,
  faceConfidence: 0.95,
  faceBlurred: false,
  faceUnderexposed: false,
  faceAreaRatio: 0.2,
  faceBoundingPolyVertices: null,
  childLabelScore: null,
};
const config = { minFaceConfidence: 0.7, minFaceAreaRatio: 0.06, childLabelReject: 0.7, childLabelReview: 0.5 };

Deno.test("a clear, recent photo of one adult is approved", () => {
  assertEquals(decideModerationOutcome(base, config), { state: "approved", reason: null });
});
Deno.test("SafeSearch: unsafe", () => {
  for (const flags of [{ adult: "POSSIBLE" }, { violence: "POSSIBLE" }, { racy: "LIKELY" }]) {
    assertEquals(decideModerationOutcome({ ...base, safeSearchFlags: { ...base.safeSearchFlags, ...flags } }, config), { state: "rejected", reason: "unsafe" });
  }
});
Deno.test("children: at 0.7 rejected, from 0.5 to a person, below untouched", () => {
  assertEquals(decideModerationOutcome({ ...base, childLabelScore: 0.7 }, config), { state: "rejected", reason: "contains_child" });
  assertEquals(decideModerationOutcome({ ...base, childLabelScore: 0.5 }, config), { state: "needs_review", reason: "needs_review" });
  assertEquals(decideModerationOutcome({ ...base, childLabelScore: 0.49 }, config).state, "approved");
});
Deno.test("no face or a low confidence: a person looks", () => {
  assertEquals(decideModerationOutcome({ ...base, faceDetected: false }, config), { state: "needs_review", reason: "needs_review" });
  assertEquals(decideModerationOutcome({ ...base, faceConfidence: 0.5 }, config), { state: "needs_review", reason: "needs_review" });
});
Deno.test("blurred, dark or a tiny face: face_unclear", () => {
  for (const r of [{ faceBlurred: true }, { faceUnderexposed: true }, { faceAreaRatio: 0.01 }, { faceAreaRatio: null }]) {
    assertEquals(decideModerationOutcome({ ...base, ...r }, config), { state: "rejected", reason: "face_unclear" });
  }
});
```

```bash
cd supabase/functions && deno test --allow-read --allow-env process-dating-photo/handler.test.ts _shared/google_vision.test.ts 2>&1 | tail -3; cd ../..
```

Expected: FAIL — `Module not found "…/process-dating-photo/handler.ts"` and a type error on `childLabelScore`.

- [ ] **Step 2: Vision with labels and slot reasons**

In `supabase/functions/_shared/google_vision.ts`, by an exact-anchor script (`$D/edit_T9.py`, below), make these changes and no others: `VisionModerationResult` gains `childLabelScore: number | null;` after `faceBoundingPolyVertices`; `ModerationConfig` gains `childLabelReject?: number;` and `childLabelReview?: number;`; `decideModerationOutcome` becomes the slot-reason version below; the request's `features` gains `{ type: "LABEL_DETECTION", maxResults: 20 },`; the parsed result gains `childLabelScore: childScore(annotation.labelAnnotations),` with the helper below.

Create `$D/edit_T9.py` with exactly:

```python
import sys
sys.path.insert(0, '.superpowers/sdd/2026-11-07-spec2-w3')
from anchor import edit
V = 'supabase/functions/_shared/google_vision.ts'
s = open(V).read()
start = s.index('export function decideModerationOutcome(')
end = s.index('const VISION_URL')
DECIDE = '''export function decideModerationOutcome(
  result: VisionModerationResult,
  config: ModerationConfig,
): ModerationOutcome {
  // Spec 2 W3c (§3.2 D9): the five slot reasons. Unsafe first, then
  // children (a photo with a child can't be used), then the face.
  const flags = result.safeSearchFlags;
  if (REJECT_AT_POSSIBLE.has(flags.adult) || REJECT_AT_POSSIBLE.has(flags.violence) || REJECT_AT_LIKELY.has(flags.racy)) {
    return { state: "rejected", reason: "unsafe" };
  }
  const child = result.childLabelScore ?? 0;
  if (child >= (config.childLabelReject ?? 0.7)) return { state: "rejected", reason: "contains_child" };
  if (child >= (config.childLabelReview ?? 0.5)) return { state: "needs_review", reason: "needs_review" };
  if (!result.faceDetected || result.faceConfidence === null || result.faceConfidence < config.minFaceConfidence) {
    return { state: "needs_review", reason: "needs_review" };
  }
  if (result.faceBlurred || result.faceUnderexposed || result.faceAreaRatio === null || result.faceAreaRatio < config.minFaceAreaRatio) {
    return { state: "rejected", reason: "face_unclear" };
  }
  return { state: "approved", reason: null };
}

/** Spec 2 W3c: the highest score among the labels that mean a child. */
const CHILD_LABELS = new Set(["child", "baby", "toddler", "infant"]);
export function childScore(labels: unknown): number | null {
  if (!Array.isArray(labels)) return null;
  let best: number | null = null;
  for (const l of labels) {
    const name = typeof l?.description === "string" ? l.description.toLowerCase() : "";
    const score = typeof l?.score === "number" ? l.score : null;
    if (CHILD_LABELS.has(name) && score !== null && (best === null || score > best)) best = score;
  }
  return best;
}

'''
open(V, 'w').write(s[:start] + DECIDE + s[end:])
edit(V, [
    ("  faceBoundingPolyVertices: Array<{ x?: number; y?: number }> | null;\n}",
     "  faceBoundingPolyVertices: Array<{ x?: number; y?: number }> | null;\n  /** Spec 2 W3c: Child, Baby, Toddler or Infant (LABEL_DETECTION). */\n  childLabelScore: number | null;\n}"),
    ("  minFaceAreaRatio: number;\n}",
     "  minFaceAreaRatio: number;\n  childLabelReject?: number;\n  childLabelReview?: number;\n}"),
    ('            { type: "FACE_DETECTION", maxResults: 5 },\n',
     '            { type: "FACE_DETECTION", maxResults: 5 },\n            { type: "LABEL_DETECTION", maxResults: 20 },\n'),
    ("    faceAreaRatio: null,\n    faceBoundingPolyVertices,\n  };",
     "    faceAreaRatio: null,\n    faceBoundingPolyVertices,\n    childLabelScore: childScore(annotation.labelAnnotations),\n  };"),
], 'T9 vision')
```

- [ ] **Step 3: The handler; `index.ts` on it**

Create `supabase/functions/process-dating-photo/handler.ts` with exactly:

```ts
// Spec 2 W3c (§3.2 D9 Server, §4.7, I-10): one photo job. The inline CSAM
// scan is first and the only scan this bucket gets (it is not in Spec 1's
// scan queue). A match: the scanned bytes to safety-quarantine, recorded
// through Spec 1's record_inline_csam_match (one hold, one escalation, the
// original's deletion), then this photo rejected and the Dating hold
// (record_dating_photo_csam 'hit'); Vision is never called. A matcher that
// can't answer never approves ('error', retried; at the last attempt a
// person looks). Clear: the size, then Vision with child labels, then the
// metadata strip before anything can be approved. Nothing is logged here.
import type { CsamMatcher } from "../_shared/csam_matcher.ts";
import { inlineRecorder, type MatchRpcClient, quarantineAndRecord, type QuarantineStore } from "../_shared/csam_match_path.ts";
import { computeFaceAreaRatio, decideModerationOutcome, type ModerationConfig, type VisionModerationResult } from "../_shared/google_vision.ts";

export const BUCKET = "dating-profile-photos";
export const MAX_ATTEMPTS = 5;
export const MIN_DIMENSION = 600;

export interface PhotoJob {
  photo_id: string;
  attempts?: number | null;
}
export interface PhotoRow {
  id: string;
  user_id: string;
  storage_key: string;
}
export type Verdict = "approved" | "rejected" | "needs_review";
export interface PhotoDeps {
  rpc: MatchRpcClient["rpc"];
  photo(id: string): Promise<PhotoRow | null>;
  download(key: string): Promise<Uint8Array | null>;
  replace(key: string, bytes: Uint8Array): Promise<boolean>;
  verdict(id: string, state: Verdict, reason: string | null): Promise<void>;
  finish(id: string, state: "pending" | "done" | "dead_letter", code: string | null): Promise<void>;
  vision(bytes: Uint8Array): Promise<VisionModerationResult>;
  matcher: CsamMatcher;
  quarantine: QuarantineStore;
  config: ModerationConfig;
}
export type JobOutcome = Verdict | "csam_hit" | "retry" | "dead";

async function csam(deps: PhotoDeps, id: string, outcome: "clear" | "hit" | "error") {
  const { error } = await deps.rpc("record_dating_photo_csam", { p_photo_id: id, p_outcome: outcome });
  if (error) throw new Error("csam_record_failed");
}

export async function processPhotoJob(job: PhotoJob, deps: PhotoDeps): Promise<JobOutcome> {
  try {
    const photo = await deps.photo(job.photo_id);
    if (!photo) throw new Error("photo_missing");
    const bytes = await deps.download(photo.storage_key);
    if (!bytes) throw new Error("decode_failed");
    const mime = sniffMime(bytes);
    const match = await deps.matcher.match(bytes, mime);
    if (match.outcome === "match") {
      const recorded = await quarantineAndRecord({
        bucket: BUCKET,
        objectName: photo.storage_key,
        bytes,
        mime,
        store: deps.quarantine,
        record: inlineRecorder({ rpc: deps.rpc }, {
          bucket: BUCKET,
          objectName: photo.storage_key,
          ownerUserId: photo.user_id,
          vendor: match.vendor,
          vendorRef: match.vendorRef,
        }),
      });
      if (!recorded.recorded) throw new Error("csam_inline_record_failed");
      await csam(deps, photo.id, "hit");
      await deps.finish(photo.id, "done", null);
      return "csam_hit";
    }
    if (match.outcome !== "clear") {
      await csam(deps, photo.id, "error");
      throw new Error(`csam_${match.outcome}`);
    }
    await csam(deps, photo.id, "clear");
    const dims = readImageDimensions(bytes);
    if (!dims || dims.width < MIN_DIMENSION || dims.height < MIN_DIMENSION) {
      await deps.verdict(photo.id, "rejected", "too_small");
      await deps.finish(photo.id, "done", null);
      return "rejected";
    }
    const vision = await deps.vision(bytes);
    const ratio = vision.faceBoundingPolyVertices
      ? computeFaceAreaRatio(vision.faceBoundingPolyVertices, dims.width, dims.height)
      : null;
    const outcome = decideModerationOutcome({ ...vision, faceAreaRatio: ratio }, deps.config);
    if (outcome.state === "approved") {
      // Strip metadata before the photo can be seen (§4.3): a photo that
      // can't be cleaned goes to a person, never out with its GPS.
      const stripped = stripJpegMetadata(bytes);
      if (stripped) {
        if (!(await deps.replace(photo.storage_key, stripped))) throw new Error("strip_reupload_failed");
      } else if (!(bytes.length > 8 && bytes[0] === 0x89 && bytes[1] === 0x50)) {
        await deps.verdict(photo.id, "needs_review", "needs_review");
        await deps.finish(photo.id, "done", null);
        return "needs_review";
      }
    }
    await deps.verdict(photo.id, outcome.state, outcome.reason);
    await deps.finish(photo.id, "done", null);
    return outcome.state;
  } catch (error) {
    const dead = Number(job.attempts ?? 0) >= MAX_ATTEMPTS;
    if (dead) await deps.verdict(job.photo_id, "needs_review", "needs_review").catch(() => {});
    await deps.finish(job.photo_id, dead ? "dead_letter" : "pending", errorCode(error)).catch(() => {});
    return dead ? "dead" : "retry";
  }
}

/** An upload whose intent expired unused (I-14), from claim_dating_orphan_uploads. */
export interface Orphan {
  intent_id: string;
  user_id: string;
  storage_key: string;
}
export interface OrphanDeps {
  rpc: MatchRpcClient["rpc"];
  download(key: string): Promise<Uint8Array | null>;
  matcher: CsamMatcher;
  quarantine: QuarantineStore;
}
export type OrphanOutcome = "swept" | "csam_hit" | "retry";

/**
 * I-14: an orphan is scanned like a photo, CSAM first with the same matcher,
 * and only a recorded scan deletes it: clear -> record_dating_orphan_scan
 * 'clear' (its deletion is queued); a match -> Spec 1's inline record
 * (quarantine copy, hold, escalation; the original deleted only when the copy
 * exists), then 'hit'; a matcher that can't answer, missing bytes or any
 * failure -> 'error' (the claim is released for the next sweep). Vision is
 * never called: the object is going either way.
 */
export async function sweepOrphan(o: Orphan, deps: OrphanDeps): Promise<OrphanOutcome> {
  const record = async (outcome: "clear" | "hit" | "error") => {
    const { error } = await deps.rpc("record_dating_orphan_scan", { p_intent_id: o.intent_id, p_outcome: outcome });
    if (error) throw new Error("orphan_record_failed");
  };
  try {
    const bytes = await deps.download(o.storage_key);
    if (!bytes) {
      await record("error");
      return "retry";
    }
    const mime = sniffMime(bytes);
    const match = await deps.matcher.match(bytes, mime);
    if (match.outcome === "match") {
      const recorded = await quarantineAndRecord({
        bucket: BUCKET,
        objectName: o.storage_key,
        bytes,
        mime,
        store: deps.quarantine,
        record: inlineRecorder({ rpc: deps.rpc }, {
          bucket: BUCKET,
          objectName: o.storage_key,
          ownerUserId: o.user_id,
          vendor: match.vendor,
          vendorRef: match.vendorRef,
        }),
      });
      if (!recorded.recorded) throw new Error("csam_inline_record_failed");
      await record("hit");
      return "csam_hit";
    }
    if (match.outcome !== "clear") throw new Error(`csam_${match.outcome}`);
    await record("clear");
    return "swept";
  } catch {
    // Never deleted unscanned: the claim is released (or lapses in 10 min).
    await record("error").catch(() => {});
    return "retry";
  }
}

export function sniffMime(b: Uint8Array): string {
  if (b.length >= 3 && b[0] === 0xFF && b[1] === 0xD8 && b[2] === 0xFF) return "image/jpeg";
  if (b.length >= 8 && b[0] === 0x89 && b[1] === 0x50 && b[2] === 0x4E && b[3] === 0x47) return "image/png";
  if (b.length >= 12 && b[0] === 0x52 && b[1] === 0x49 && b[8] === 0x57 && b[9] === 0x45) return "image/webp";
  return "application/octet-stream";
}

export function errorCode(error: unknown): string {
  return (error instanceof Error ? error.message : "unknown_error").slice(0, 120);
}

/**
 * Removes EXIF and every other metadata segment from a JPEG.
 *
 * Spec §4.3 requires stripping server-side. The client already passes
 * `keepExif: false`, but that is a courtesy the client can withdraw: a
 * modified or replayed upload can carry GPS coordinates, a capture
 * timestamp, and a device serial straight into a dating photo other users
 * will see. Stripping here is what makes it true regardless of the client.
 *
 * JPEG is a sequence of marker segments. Everything a camera writes lives
 * in APPn (0xE0-0xEF, holding EXIF/GPS in APP1 and thumbnails that carry
 * their own EXIF) or COM (0xFE). Dropping those segments leaves the
 * compressed image data untouched, so this re-encodes nothing and cannot
 * degrade the picture.
 *
 * Returns null when the input is not a JPEG we can safely walk, so callers
 * fall back to leaving the object alone rather than writing something
 * corrupt.
 */
export function stripJpegMetadata(bytes: Uint8Array): Uint8Array | null {
  if (bytes.length < 4 || bytes[0] !== 0xFF || bytes[1] !== 0xD8) return null;

  const keep: Array<[number, number]> = [];
  let offset = 2;

  while (offset < bytes.length - 1) {
    if (bytes[offset] !== 0xFF) return null;

    const marker = bytes[offset + 1];

    // Start of scan: the entropy-coded image data runs to the end of the
    // file, so copy the remainder verbatim and stop parsing.
    if (marker === 0xDA) {
      keep.push([offset, bytes.length]);
      break;
    }

    // Standalone markers carry no length field.
    if (marker === 0x01 || (marker >= 0xD0 && marker <= 0xD7)) {
      keep.push([offset, offset + 2]);
      offset += 2;
      continue;
    }

    const segmentLength = (bytes[offset + 2] << 8) | bytes[offset + 3];
    if (segmentLength < 2 || offset + 2 + segmentLength > bytes.length) {
      return null;
    }

    const isAppSegment = marker >= 0xE0 && marker <= 0xEF;
    const isComment = marker === 0xFE;
    if (!isAppSegment && !isComment) {
      keep.push([offset, offset + 2 + segmentLength]);
    }

    offset += 2 + segmentLength;
  }

  let size = 2;
  for (const [start, end] of keep) size += end - start;

  const out = new Uint8Array(size);
  out[0] = 0xFF;
  out[1] = 0xD8;
  let cursor = 2;
  for (const [start, end] of keep) {
    out.set(bytes.subarray(start, end), cursor);
    cursor += end - start;
  }
  return out;
}

export function readImageDimensions(
  bytes: Uint8Array,
): { width: number; height: number } | null {
  // Minimal JPEG/PNG header parse sufficient for the dimension gate; a full
  // decode is not required here since Vision already validated decodability.
  if (bytes.length > 24 && bytes[0] === 0x89 && bytes[1] === 0x50) {
    // PNG: width/height are big-endian uint32 at offset 16/20.
    const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
    return { width: view.getUint32(16), height: view.getUint32(20) };
  }
  if (bytes.length > 4 && bytes[0] === 0xFF && bytes[1] === 0xD8) {
    // JPEG: scan markers for SOF0/SOF2 to find dimensions.
    let offset = 2;
    while (offset < bytes.length - 8) {
      if (bytes[offset] !== 0xFF) { offset++; continue; }
      const marker = bytes[offset + 1];
      if (marker === 0xC0 || marker === 0xC2) {
        const height = (bytes[offset + 5] << 8) | bytes[offset + 6];
        const width = (bytes[offset + 7] << 8) | bytes[offset + 8];
        return { width, height };
      }
      const segmentLength = (bytes[offset + 2] << 8) | bytes[offset + 3];
      offset += 2 + segmentLength;
    }
    return null;
  }
  return null;
}
```

(`stripJpegMetadata` and `readImageDimensions` are in the block above: moved from the old `index.ts` unchanged except `export` and `readImageDimensions` made synchronous, since it never awaits. `sweepOrphan` is the orphan path, I-14.)

Replace the whole of `supabase/functions/process-dating-photo/index.ts` with exactly:

```ts
// supabase/functions/process-dating-photo/index.ts
// Spec 2 W3c: the wiring for handler.ts (CSAM first, inline; I-10).
import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { HttpError, jsonResponse, requireServiceRole, serviceRoleClient } from "../_shared/attune_auth.ts";
import { matcherFromEnv } from "../_shared/csam_matcher.ts";
import { storageQuarantine, type StorageLike } from "../_shared/csam_match_path.ts";
import { analyzeDatingPhoto } from "../_shared/google_vision.ts";
import { BUCKET, errorCode, processPhotoJob, sweepOrphan } from "./handler.ts";

const VISION_API_KEY = Deno.env.get("GOOGLE_VISION_API_KEY");

serve(async (req) => {
  if (req.method === "OPTIONS") return jsonResponse({ ok: true });
  try {
    requireServiceRole(req);
    if (!VISION_API_KEY) throw new Error("missing_vision_api_key");
    const supabase = serviceRoleClient();
    const body = await req.json().catch(() => ({}));
    const requestedId = typeof body.photo_id === "string" ? body.photo_id : null;
    const { data: env } = await supabase.rpc("get_attune_environment");
    const matcher = matcherFromEnv({
      env: (name) => Deno.env.get(name),
      fetch,
      environment: env === "development" ? "development" : "production",
    });
    const { data: configRows } = await supabase.from("dating_photo_moderation_config")
      .select("min_face_confidence, min_face_area_ratio, child_label_reject, child_label_review").limit(1);
    const c = configRows?.[0];
    const config = {
      minFaceConfidence: Number(c?.min_face_confidence ?? 0.7),
      minFaceAreaRatio: Number(c?.min_face_area_ratio ?? 0.06),
      childLabelReject: Number(c?.child_label_reject ?? 0.7),
      childLabelReview: Number(c?.child_label_review ?? 0.5),
    };
    const { data: jobs, error } = await supabase.rpc("claim_dating_photo_jobs", { p_limit: requestedId ? 1 : 20, p_photo_id: requestedId });
    if (error) throw error;
    let processed = 0;
    for (const job of jobs ?? []) {
      const outcome = await processPhotoJob(job, {
        rpc: (fn, args) => supabase.rpc(fn, args),
        photo: async (id) => {
          const { data } = await supabase.from("dating_profile_photos").select("id, user_id, storage_key").eq("id", id).maybeSingle();
          return data ?? null;
        },
        download: async (key) => {
          const { data } = await supabase.storage.from(BUCKET).download(key);
          return data ? new Uint8Array(await data.arrayBuffer()) : null;
        },
        replace: async (key, bytes) => {
          const { error } = await supabase.storage.from(BUCKET).update(key, bytes, { contentType: "image/jpeg", upsert: true });
          return !error;
        },
        verdict: async (id, state, reason) => {
          const { error } = await supabase.from("dating_profile_photos")
            .update({ moderation_state: state, rejection_reason: reason, reviewed_at: new Date().toISOString() }).eq("id", id);
          if (error) throw error;
        },
        finish: async (id, state, code) => {
          const now = new Date().toISOString();
          const { error } = await supabase.from("dating_photo_moderation_outbox").update({
            state,
            last_error_code: code,
            processing_started_at: state === "pending" ? null : undefined,
            completed_at: state === "pending" ? null : now,
            updated_at: now,
          }).eq("photo_id", id).eq("state", "processing");
          if (error) throw error;
        },
        vision: (bytes) => analyzeDatingPhoto({ imageBytes: bytes, apiKey: VISION_API_KEY }),
        matcher,
        quarantine: storageQuarantine(supabase.storage as unknown as StorageLike),
        config,
      });
      if (outcome !== "retry") processed++;
    }
    // I-14: the 15-minute cron call (no photo id) also sweeps orphan
    // uploads, CSAM first; nothing is deleted unscanned.
    let orphans = 0;
    if (!requestedId) {
      const { data: claimed, error: claimError } = await supabase.rpc("claim_dating_orphan_uploads", { p_limit: 10 });
      if (claimError) throw claimError;
      for (const o of claimed ?? []) {
        const outcome = await sweepOrphan(o, {
          rpc: (fn, args) => supabase.rpc(fn, args),
          download: async (key) => {
            const { data } = await supabase.storage.from(BUCKET).download(key);
            return data ? new Uint8Array(await data.arrayBuffer()) : null;
          },
          matcher,
          quarantine: storageQuarantine(supabase.storage as unknown as StorageLike),
        });
        if (outcome !== "retry") orphans++;
      }
    }
    return jsonResponse({ success: true, processed, orphans });
  } catch (error) {
    const status = error instanceof HttpError ? error.status : 500;
    return jsonResponse({ success: false, error: errorCode(error) }, status);
  }
});
```

```bash
D=.superpowers/sdd/2026-11-07-spec2-w3
python3 -I $D/edit_T9.py
cd supabase/functions
deno check process-dating-photo/index.ts 2>&1 | tail -2
deno test --allow-read --allow-env process-dating-photo/handler.test.ts _shared/google_vision.test.ts _shared/csam_match_path.test.ts 2>&1 | tail -2
cd ../..
rm -r supabase/functions/upload-dating-photo
grep -rn "upload-dating-photo" supabase lib .github scripts docs/superpowers/specs 2>/dev/null | grep -v "^docs/superpowers/specs"
```

Expected: `T9 vision` edit line; `deno check` clean; `ok | 26 passed | 0 failed` (verified, fix round 1: the handler's 10, three of them the orphan sweep's, then Vision's and the existing match-path tests); no `grep` output outside the spec (its `config.toml` has no entry; if one appears, remove that one block and say so).

- [ ] **Step 4: CI runs the handler's tests**

```bash
python3 -I - <<'PY'
import sys; sys.path.insert(0, '.superpowers/sdd/2026-11-07-spec2-w3')
from anchor import edit
edit('.github/workflows/tests.yml', [
    (" _shared/healing_ai_gate.test.ts analyse-journal-entry/",
     " _shared/healing_ai_gate.test.ts process-dating-photo/handler.test.ts analyse-journal-entry/"),
], 'T9 CI')
PY
cd supabase/functions && deno test --allow-read --allow-env --lock=../../.github/deno-w9.lock --frozen _shared/unicode_normaliser.test.ts _shared/writer_crisis_check.test.ts _shared/healing_ai_gate.test.ts process-dating-photo/handler.test.ts analyse-journal-entry/ generate-healing-portrait/ generate-healing-post-mortem/ 2>&1 | tail -1; cd ../..
```

Expected: the edit; the frozen-lock run `ok | … passed | 0 failed` (the handler test imports only local modules, so the lock is unchanged).

- [ ] **Step 5: The image preparer (R-23)**

Create `$D/preparer_test_T9.dart` (the new test; the script below appends it inside `main` and adds the `image` import) with exactly:

```dart

  // Spec 2 W3c (R-23, C-5): at most 1600 px on the long side, a neutral
  // temp name, EXIF gone.
  test('a large photo comes out at most 1600 px, under a neutral name', () async {
    final dir = await Directory.systemTemp.createTemp('w3c');
    addTearDown(() => dir.delete(recursive: true));
    final big = img.Image(width: 4000, height: 3000);
    img.fill(big, color: img.ColorRgb8(200, 120, 90));
    final source = File('${dir.path}/source.jpg')..writeAsBytesSync(img.encodeJpg(big, quality: 95));
    final prepared = await const DatingImagePreparer().prepare(source.path);
    final out = img.decodeJpg(await prepared.file.readAsBytes())!;
    expect(out.width, 1600);
    expect(out.height, 1200);
    expect(prepared.file.path.toLowerCase(), isNot(contains('dating')));
    expect(prepared.byteSize, lessThanOrEqualTo(DatingImagePreparer.maxBytes));
    await prepared.file.delete();
  });
```

Create `$D/edit_T9_preparer.py` (the preparer at 1600 px / quality 80 on the Dart encoder only; the temp name `p_<micros>.jpg`; `flutter_image_compress` no longer imported) with exactly:

```python
# Spec 2 W3c Task 9 Step 5 (R-23): the preparer at 1600 px / quality 80 on
# the Dart encoder only, a neutral temp name; its new test appended.
import pathlib, sys
sys.path.insert(0, '.superpowers/sdd/2026-11-07-spec2-w3')
from anchor import edit

L = 'lib/features/dating/domain/services/dating_image_preparer.dart'
s = pathlib.Path(L).read_text()
start = s.index("    final targetPath = await _tempTargetPath();\n")
end = s.index("  img.Image _resizeLongestEdge(")
body = """    final targetPath = await _tempTargetPath();
    // Spec 2 W3c (R-23): one deterministic path: upright, at most 1600 px on
    // the long side, EXIF (GPS included) cleared, JPEG at quality 80,
    // stepping down only to fit maxBytes.
    final upright = img.bakeOrientation(decoded);
    final resized = _resizeLongestEdge(upright, maxDimension);
    resized.exif = img.ExifData();
    for (final q in const [quality, 70, 60, 50]) {
      final jpeg = img.encodeJpg(resized, quality: q);
      if (jpeg.lengthInBytes <= maxBytes) {
        final outFile = File(targetPath);
        await outFile.writeAsBytes(jpeg, flush: true);
        return PreparedDatingImage(
          file: outFile,
          mimeType: 'image/jpeg',
          byteSize: jpeg.lengthInBytes,
        );
      }
    }
    throw const DatingImageRejected('media_compress_failed');
  }

"""
pathlib.Path(L).write_text(s[:start] + body + s[end:])
print(f'{L}: prepare body replaced (T9 preparer)')
edit(L, [
    ("import 'package:flutter_image_compress/flutter_image_compress.dart';\n", ''),
    ("  static const int maxDimension = 2000;\n",
     "  static const int maxDimension = 1600;\n  static const int quality = 80;\n"),
    ("    final name = 'dating_photo_${DateTime.now().microsecondsSinceEpoch}.jpg';\n",
     "    final name = 'p_${DateTime.now().microsecondsSinceEpoch}.jpg';\n"),
], 'T9 preparer constants and temp name (C-5)')

T = 'test/features/dating/dating_image_preparer_test.dart'
t = pathlib.Path(T).read_text()
assert t.endswith('}\n'), 'the preparer test does not end with }'
add = pathlib.Path('.superpowers/sdd/2026-11-07-spec2-w3/preparer_test_T9.dart').read_text()
t = t[:-2] + add.rstrip('\n') + '\n}\n'
if "import 'package:image/image.dart' as img;\n" not in t:
    t = t.replace("import 'package:flutter_test/flutter_test.dart';\n",
                  "import 'package:flutter_test/flutter_test.dart';\nimport 'package:image/image.dart' as img;\n", 1)
pathlib.Path(T).write_text(t)
print(f'{T}: the 1600 px test added (T9 preparer test)')
```

```bash
python3 -I $D/edit_T9_preparer.py
```

Expected: three lines (`prepare body replaced`, `3 edit(s)`, `the 1600 px test added`). Then:

```bash
flutter analyze --no-pub lib/features/dating test/features/dating 2>&1 | tail -1
flutter test test/features/dating/dating_image_preparer_test.dart test/features/dating/dating_image_preparer_exif_test.dart 2>&1 | tail -1
```

Expected: `No issues found!`; `All tests passed!` (the EXIF test still passes: the strip is explicit).

- [ ] **Step 6: Mutants (Deno, by hand, each restored)**

For each of these edits to `handler.ts`, apply it, run `deno test --allow-read --allow-env process-dating-photo/handler.test.ts`, expect FAIL with the named test, restore the file byte for byte (`cmp` against a copy taken first): `vision_before_csam` (move `const vision = await deps.vision(bytes);` above the matcher call) → "clear: CSAM first …"; `match_still_vision` (remove `return "csam_hit";`) → "a match: …"; `error_approves` (change `if (match.outcome !== "clear") {` to `if (false) {`) → "a matcher error never approves"; `no_quarantine` (replace `store: deps.quarantine,` with `store: { put: async () => "failed" as const },`) → "a match: …" (the copy is not the scanned bytes); `child_ignored` (in `google_vision.ts`, `const child = result.childLabelScore ?? 0;` → `const child = 0;`) → "child labels …"; `orphan_clear_unscanned` (in `sweepOrphan`, add `await record("clear");` as the first line inside `try {`) → all three "orphan …" tests (verified, fix round 1). Record the six FAIL lines in `$D/mut_T9.txt`.

- [ ] **Step 7: Do not commit; record the tree in the report.**

### Task 10: D9 (photos) and D10 (prompts) (§3.2 D9 Fields/Client/Validation/Accessibility, D10, §3.15 rows D9–D10; C-5; R-22, R-23, R-37, R-42)

**Files:**
- Create: `lib/features/dating/photos/dating_photos_repository.dart`, `lib/features/dating/photos/dating_photos_providers.dart`, `lib/features/dating/setup/photos_step.dart`, `lib/features/dating/setup/prompts_step.dart`, `test/features/dating/setup/d9_d10_test.dart` (+ goldens), `test/features/dating/support/dating_photos_fakes.dart`, `$D/{arb_fragment_T10.txt, edit_T10.py, mut_T10.py}`
- Modify: `lib/features/dating/data/models/dating_profile_photo.dart` (§4.10: positions 1–6, caption, the v2 keys; v1 keys still read), `test/features/dating/dating_profile_photo_model_test.dart` (one test added), `lib/features/dating/routes/dating_setup_steps.dart` (two cases), `lib/i10n/app_en.arb` + generated

**Interfaces:**
- Consumes: Task 8's photo RPCs; Task 9's `DatingImagePreparer`; Task 6's frame and mixin; Task 5's `savePrompts`, `DatingMyProfile.prompts`; `image_picker`, `image_cropper` (both dependencies already).
- Produces: `DatingProfilePhoto` (+ `caption`); `DatingPhotoList({photos, afterMutual, afterMutualFrom})`; `DatingPhotosGateway` (`list()`, `add(int position, Uint8List bytes, String mime)`, `remove(String id)`, `reorder(String key, List<String> ids)`, `caption(String id, String text)`, `photosAfterMutual(String key, bool on)`, `bytes(String storageKey)`); providers `datingPhotosGatewayProvider`, `datingPhotosProvider(account)`, `datingPhotoPickerProvider` (`Future<String?> Function()`), `datingPhotoCropperProvider` (`Future<String?> Function(String path)`), `datingImagePreparerProvider`; `DatingPhotosStep`, `DatingPromptsStep`; `const datingPromptIds` (the ten, in §3.2 D10's order).

- [ ] **Step 1: The strings**

Create `$D/arb_fragment_T10.txt` with exactly (spec copy verbatim; "(plan)" for the reviewers):

```
  "dating_photosTitle": "Add your photos",
  "@dating_photosTitle": {"description": "Spec 2 §3.2 D9."},
  "dating_photosBody": "Add 2 to 6 photos. Clear, recent photos of just you work best.",
  "dating_photoAdd": "Add photo",
  "dating_photoPreparing": "Preparing photo {n}…",
  "@dating_photoPreparing": {"description": "D9 progress in words (R-22).", "placeholders": {"n": {"type": "int"}}},
  "dating_photoUploading": "Uploading photo {n}…",
  "@dating_photoUploading": {"description": "D9 progress in words (R-22).", "placeholders": {"n": {"type": "int"}}},
  "dating_photoChecking": "Checking…",
  "dating_photoReady": "Ready",
  "dating_photoReview": "Needs a person to check it. That usually takes less than a day.",
  "dating_photoFaceUnclear": "Photo {n}: we couldn't see your face clearly.",
  "@dating_photoFaceUnclear": {"description": "D9 rejection.", "placeholders": {"n": {"type": "int"}}},
  "dating_photoTooSmall": "Photo {n} is too small.",
  "@dating_photoTooSmall": {"description": "D9 rejection.", "placeholders": {"n": {"type": "int"}}},
  "dating_photoChild": "Photo {n}: photos with children can't be used on Dating. Crop to just you?",
  "@dating_photoChild": {"description": "D9 rejection (then Crop).", "placeholders": {"n": {"type": "int"}}},
  "dating_photoCrop": "Crop",
  "dating_photoCantUse": "Photo {n} can't be used.",
  "@dating_photoCantUse": {"description": "D9 rejection (unsafe, and a CSAM hit, never named).", "placeholders": {"n": {"type": "int"}}},
  "dating_photoFailed": "Photo {n} didn't upload. Try again.",
  "@dating_photoFailed": {"description": "D9: the upload failed (plan).", "placeholders": {"n": {"type": "int"}}},
  "dating_photoSlot": "Photo {n} of 6, {state}",
  "@dating_photoSlot": {"description": "D9 slot semantics.", "placeholders": {"n": {"type": "int"}, "state": {"type": "String"}}},
  "dating_photoMoveEarlier": "Move earlier", "dating_photoMoveLater": "Move later",
  "dating_photoRemove": "Remove",
  "dating_photoReplace": "Replace",
  "@dating_photoReplace": {"description": "D9 slot action (plan)."},
  "dating_photoCaption": "Add a caption (only you see it)",
  "@dating_photoCaption": {"description": "D9 caption action (plan; 09 P12)."},
  "dating_photoCaptionLabel": "Caption",
  "@dating_photoCaptionLabel": {"description": "D9 caption field (plan)."},
  "dating_photoSave": "Save",
  "@dating_photoSave": {"description": "D9 caption sheet (plan)."},
  "dating_photosAfterMutual": "Show my photos only after we're both interested",
  "dating_photosAfterMutualFrom": "Available from {date}. New accounts show their photos for the first 30 days, which helps stop fake profiles.",
  "@dating_photosAfterMutualFrom": {"description": "D9 toggle before account day 30.", "placeholders": {"date": {"type": "String"}}},
  "dating_photosData": "Each photo uses about 300 KB.",
  "dating_photosOffline": "You're offline. Add photos when you're connected.",

  "dating_promptsTitle": "A little about you",
  "@dating_promptsTitle": {"description": "Spec 2 §3.2 D10."},
  "dating_promptsBody": "Answer 2 of these. Short is fine.",
  "dating_prompt_perfect_sunday": "A perfect Sunday for me looks like…",
  "dating_prompt_feel_at_home": "I feel most at home when…",
  "dating_prompt_friends_say": "My friends would say I'm…",
  "dating_prompt_looking_for": "I'm looking for someone who…",
  "dating_prompt_small_thing": "A small thing that makes my day…",
  "dating_prompt_win_me_over": "The way to win me over is…",
  "dating_prompt_learning_to": "I'm learning to…",
  "dating_prompt_family_describe": "My family would describe me as…",
  "dating_prompt_place_love": "A kind of place I love spending time…",
  "dating_prompt_ask_me_about": "Ask me about…",
  "dating_promptTooShort": "At least 10 characters.",
  "@dating_promptTooShort": {"description": "D10 length (plan)."}
```

```bash
D=.superpowers/sdd/2026-11-07-spec2-w3
python3 -I .superpowers/sdd/2026-10-26-spec1-w3/arb_append.py $D/arb_fragment_T10.txt
flutter gen-l10n --arb-dir=lib/i10n --template-arb-file=app_en.arb --output-dir=lib/i10n/generated --output-localization-file=app_localizations.dart --no-synthetic-package
```

Expected: `added 39 keys` (verified, fix round 1; the ellipsis `…` is plain UTF-8 in the fragment, no `\u` escape).

- [ ] **Step 2: Write the failing tests**

Create `test/features/dating/support/dating_photos_fakes.dart` with exactly:

```dart
import 'dart:typed_data';

import 'package:attune/features/dating/data/dating_rpc.dart';
import 'package:attune/features/dating/data/models/dating_profile_photo.dart';
import 'package:attune/features/dating/photos/dating_photos_repository.dart';

class FakeDatingPhotosGateway implements DatingPhotosGateway {
  FakeDatingPhotosGateway({this.photos = const [], this.afterMutualFrom});

  List<DatingProfilePhoto> photos;
  DateTime? afterMutualFrom;
  bool afterMutual = false;
  final calls = <(String, Object?)>[];
  DatingWrite addAnswer = const DatingWrite(ok: true);

  @override
  Future<DatingPhotoList> list() async {
    calls.add(('list', null));
    return DatingPhotoList(
      photos: photos,
      afterMutual: afterMutual,
      afterMutualFrom: afterMutualFrom,
    );
  }

  @override
  Future<DatingWrite> add(int position, Uint8List bytes, String mime) async {
    calls.add(('add', (position, bytes.length, mime)));
    if (addAnswer.ok) {
      photos = [
        ...photos.where((p) => p.position != position),
        DatingProfilePhoto(
          id: 'new-$position',
          position: position,
          moderationState: 'pending',
          storageKey: 'k-$position',
          createdAt: DateTime.utc(2026, 11, 7),
        ),
      ];
    }
    return addAnswer;
  }

  @override
  Future<DatingWrite> remove(String id) async {
    calls.add(('remove', id));
    photos = photos.where((p) => p.id != id).toList();
    return const DatingWrite(ok: true);
  }

  @override
  Future<DatingWrite> reorder(String key, List<String> ids) async {
    calls.add(('reorder', ids));
    return const DatingWrite(ok: true);
  }

  @override
  Future<DatingWrite> caption(String id, String text) async {
    calls.add(('caption', (id, text)));
    return const DatingWrite(ok: true);
  }

  @override
  Future<DatingWrite> photosAfterMutual(String key, bool on) async {
    calls.add(('afterMutual', on));
    afterMutual = on;
    return const DatingWrite(ok: true);
  }

  @override
  Future<Uint8List?> bytes(String storageKey) async => null;
}

DatingProfilePhoto photo(int position, String state, {String? reason}) =>
    DatingProfilePhoto(
      id: 'p$position',
      position: position,
      moderationState: state,
      rejectionReason: reason,
      storageKey: 'k$position',
      createdAt: DateTime.utc(2026, 11, 1),
    );
```

Create `test/features/dating/setup/d9_d10_test.dart` with exactly:

```dart
// Spec 2 W3c (§3.2 D9-D10, §3.15, C-5): photos and prompts.
import 'dart:io';

import 'package:attune/features/auth/sign_up/presentation/widgets/flow_buttons.dart';
import 'package:attune/features/dating/data/dating_rpc.dart';
import 'package:attune/features/dating/domain/services/dating_image_preparer.dart';
import 'package:attune/features/dating/photos/dating_photos_providers.dart';
import 'package:attune/features/dating/routes/dating_setup_steps.dart';
import 'package:attune/features/dating/setup/dating_setup_models.dart';
import 'package:attune/features/dating/setup/dating_setup_providers.dart';
import 'package:attune/features/dating/setup/photos_step.dart';
import 'package:attune/features/dating/setup/prompts_step.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/flow_harness.dart';
import '../../../helpers/tap_in_reach.dart';
import '../support/dating_photos_fakes.dart';
import '../support/dating_setup_fakes.dart';
import '../support/dating_shell.dart';

class _Prep extends DatingImagePreparer {
  _Prep(this.dir);
  final Directory dir;
  final made = <File>[];
  @override
  Future<PreparedDatingImage> prepare(String localPath) async {
    final f = File('${dir.path}/p_${made.length}.jpg')
      ..writeAsBytesSync(List.filled(300, 1));
    made.add(f);
    return PreparedDatingImage(file: f, mimeType: 'image/jpeg', byteSize: 300);
  }
}

Future<(FakeDatingPhotosGateway, List<String>, _Prep, Directory)> _photos(
  WidgetTester t, {
  List photos = const [],
  bool online = true,
  DateTime? afterMutualFrom,
}) async {
  await t.pumpWidget(const SizedBox());
  final dir = Directory.systemTemp.createTempSync('d9');
  addTearDown(() => dir.deleteSync(recursive: true));
  final picked = File('${dir.path}/picked.jpg')
    ..writeAsBytesSync(List.filled(10, 2));
  final gateway = FakeDatingPhotosGateway(
    photos: [...photos],
    afterMutualFrom: afterMutualFrom ?? DateTime.utc(2026, 1, 1),
  );
  final prep = _Prep(dir);
  final steps = <String>[];
  await pumpFlowScreen(
    t,
    () => DatingPhotosStep(
      nav: DatingStepNav(next: steps.add, back: () {}, toMe: () {}),
    ),
    overrides: [
      ...datingShellOverrides(online: online),
      datingPhotosGatewayProvider.overrideWithValue(gateway),
      datingImagePreparerProvider.overrideWithValue(prep),
      datingPhotoPickerProvider.overrideWithValue(() async => picked.path),
      datingPhotoCropperProvider.overrideWithValue((path) async => path),
    ],
  );
  await t.pumpAndSettle();
  return (gateway, steps, prep, dir);
}

/// The add path reads and deletes real files: let that I/O finish (the test
/// clock doesn't run it), a frame at a time.
Future<void> _settleIo(WidgetTester t) async {
  for (var i = 0; i < 10; i++) {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await t.pump();
  }
}

void main() {
  group('D9', () {
    testWidgets('six slots, each read as "Photo n of 6, state"', (t) async {
      final semantics = t.ensureSemantics();
      await _photos(t, photos: [photo(1, 'approved'), photo(2, 'pending')]);
      expect(find.text('Add your photos'), findsOneWidget);
      expect(find.text('Step 8 of 12'), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp(r'^Photo 1 of 6, Ready')),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(RegExp(r'^Photo 2 of 6, Checking…')),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(RegExp(r'^Photo 3 of 6, Add photo')),
        findsOneWidget,
      );
      expect(find.text('Each photo uses about 300 KB.'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('add: prepared, uploaded, and every temp file deleted (C-5)', (
      t,
    ) async {
      final (gateway, _, prep, dir) = await _photos(t);
      await tapInReach(t, find.widgetWithText(FlowTextLink, 'Add photo').first);
      await _settleIo(t);
      expect(gateway.calls.where((c) => c.$1 == 'add').single.$2, (
        1,
        300,
        'image/jpeg',
      ));
      expect(prep.made.single.existsSync(), isFalse);
      expect(File('${dir.path}/picked.jpg').existsSync(), isFalse);
      for (final f in dir.listSync()) {
        expect(f.path.toLowerCase(), isNot(contains('dating')));
      }
    });

    testWidgets(
      'each rejection names its slot and its reason; a child photo offers Crop',
      (t) async {
        await _photos(
          t,
          photos: [
            photo(1, 'rejected', reason: 'face_unclear'),
            photo(2, 'rejected', reason: 'too_small'),
            photo(3, 'rejected', reason: 'contains_child'),
            photo(4, 'rejected', reason: 'unsafe'),
            photo(5, 'needs_review', reason: 'needs_review'),
          ],
        );
        expect(
          find.text("Photo 1: we couldn't see your face clearly."),
          findsOneWidget,
        );
        expect(find.text('Photo 2 is too small.'), findsOneWidget);
        expect(
          find.text(
            "Photo 3: photos with children can't be used on Dating. Crop to just you?",
          ),
          findsOneWidget,
        );
        expect(find.text('Crop'), findsOneWidget);
        expect(find.text("Photo 4 can't be used."), findsOneWidget);
        expect(
          find.text(
            'Needs a person to check it. That usually takes less than a day.',
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets('Continue needs two photos that aren\'t rejected', (t) async {
      final (_, steps, _, _) = await _photos(
        t,
        photos: [photo(1, 'approved'), photo(2, 'rejected', reason: 'unsafe')],
      );
      await tapInReach(t, find.text('Continue'));
      await t.pumpAndSettle();
      expect(steps, isEmpty);
      final (_, steps2, _, _) = await _photos(
        t,
        photos: [photo(1, 'approved'), photo(2, 'pending')],
      );
      await tapInReach(t, find.text('Continue'));
      await t.pumpAndSettle();
      expect(steps2, ['prompts']);
    });

    testWidgets('Move later: the new order is sent', (t) async {
      final (gateway, _, _, _) = await _photos(
        t,
        photos: [photo(1, 'approved'), photo(2, 'approved')],
      );
      await tapInReach(t, find.byTooltip('Move later').first);
      await t.pumpAndSettle();
      expect(gateway.calls.where((c) => c.$1 == 'reorder').single.$2, [
        'p2',
        'p1',
      ]);
    });

    testWidgets('drag by the thumbnail: the new order is sent', (t) async {
      final (gateway, _, _, _) = await _photos(
        t,
        photos: [photo(1, 'approved'), photo(2, 'approved')],
      );
      await bringIntoReach(t, find.byKey(const ValueKey('drag_p1')));
      await t.drag(find.byKey(const ValueKey('drag_p1')), const Offset(0, 400));
      await t.pumpAndSettle();
      expect(gateway.calls.where((c) => c.$1 == 'reorder').single.$2, [
        'p2',
        'p1',
      ]);
    });

    testWidgets(
      'before account day 30 the photos-after toggle is off and says when',
      (t) async {
        await _photos(
          t,
          afterMutualFrom: DateTime.now().toUtc().add(const Duration(days: 9)),
        );
        final toggle = t.widget<SwitchListTile>(
          find.widgetWithText(
            SwitchListTile,
            "Show my photos only after we're both interested",
          ),
        );
        expect(toggle.onChanged, isNull);
        expect(find.textContaining('Available from '), findsOneWidget);
      },
    );

    testWidgets('offline: adding is off and says so', (t) async {
      final (gateway, _, _, _) = await _photos(t, online: false);
      await tapInReach(t, find.widgetWithText(FlowTextLink, 'Add photo').first);
      await _settleIo(t);
      expect(gateway.calls.where((c) => c.$1 == 'add'), isEmpty);
      expect(
        find.text("You're offline. Add photos when you're connected."),
        findsOneWidget,
      );
    });

    testWidgets('a failed upload names the slot', (t) async {
      final (gateway, _, _, _) = await _photos(t);
      gateway.addAnswer = DatingWrite.failed;
      await tapInReach(t, find.widgetWithText(FlowTextLink, 'Add photo').first);
      await _settleIo(t);
      expect(find.text("Photo 1 didn't upload. Try again."), findsOneWidget);
    });
  });

  group('D10', () {
    Future<(FakeDatingSetupGateway, List<String>)> prompts(
      WidgetTester t, {
      DatingMyProfile profile = const DatingMyProfile(),
    }) async {
      await t.pumpWidget(const SizedBox());
      final setup = FakeDatingSetupGateway(profile: profile);
      final steps = <String>[];
      await pumpFlowScreen(
        t,
        () => DatingPromptsStep(
          nav: DatingStepNav(next: steps.add, back: () {}, toMe: () {}),
        ),
        overrides: [
          ...datingShellOverrides(),
          datingSetupGatewayProvider.overrideWithValue(setup),
        ],
      );
      await t.pumpAndSettle();
      return (setup, steps);
    }

    testWidgets('two answers of 10 to 200 characters, sent in order', (
      t,
    ) async {
      final (setup, steps) = await prompts(t);
      expect(find.text('Answer 2 of these. Short is fine.'), findsOneWidget);
      await tapInReach(t, find.text('A perfect Sunday for me looks like…'));
      await t.pump();
      await tapInReach(t, find.text('Ask me about…'));
      await t.pumpAndSettle();
      await t.enterText(
        find.byKey(const ValueKey('dating_prompt_perfect_sunday')),
        'A long walk, then lunch.',
      );
      await t.enterText(
        find.byKey(const ValueKey('dating_prompt_ask_me_about')),
        'short',
      );
      await tapInReach(t, find.text('Continue'));
      await t.pumpAndSettle();
      expect(setup.writes, isEmpty);
      expect(find.text('At least 10 characters.'), findsOneWidget);
      await t.enterText(
        find.byKey(const ValueKey('dating_prompt_ask_me_about')),
        'My grandmother.',
      );
      await tapInReach(t, find.text('Continue'));
      await t.pumpAndSettle();
      expect(setup.lastWrite.$2['items'], [
        ('perfect_sunday', 'A long walk, then lunch.'),
        ('ask_me_about', 'My grandmother.'),
      ]);
      expect(steps, ['verify']);
    });

    testWidgets('the contact and kindness filters land on their prompt', (
      t,
    ) async {
      final (setup, _) = await prompts(
        t,
        profile: const DatingMyProfile(
          prompts: [
            ('perfect_sunday', 'A long walk, then lunch.'),
            ('ask_me_about', 'My grandmother stories.'),
          ],
        ),
      );
      setup.answer = const DatingWrite(
        ok: false,
        reason: 'contact_details',
        position: 2,
      );
      await tapInReach(t, find.text('Continue'));
      await t.pumpAndSettle();
      expect(
        find.text(
          "Contact details can't go on your profile. You can swap them in a chat when you're both ready.",
        ),
        findsOneWidget,
      );
      setup.answer = const DatingWrite(
        ok: false,
        reason: 'unkind',
        position: 1,
      );
      await t.enterText(
        find.byKey(const ValueKey('dating_prompt_perfect_sunday')),
        'A long walk, then a lunch.',
      );
      await tapInReach(t, find.text('Continue'));
      await t.pumpAndSettle();
      expect(
        find.text("Please rephrase this so it's kind to everyone."),
        findsOneWidget,
      );
    });

    testWidgets('at most three prompts', (t) async {
      await prompts(t);
      for (final p in [
        'A perfect Sunday for me looks like…',
        'I feel most at home when…',
        "My friends would say I'm…",
        'Ask me about…',
      ]) {
        await tapInReach(t, find.text(p));
        await t.pumpAndSettle();
      }
      expect(find.byType(TextField), findsNWidgets(3));
    });
  });

  testWidgets('guidelines', (t) async {
    final semantics = t.ensureSemantics();
    await _photos(
      t,
      photos: [
        photo(1, 'approved'),
        photo(3, 'rejected', reason: 'contains_child'),
      ],
    );
    await expectFlowGuidelines(t);
    semantics.dispose();
  });

  for (final (name, photos) in [
    ('d9_photos_empty', const <dynamic>[]),
    (
      'd9_photos_states',
      [
        photo(1, 'approved'),
        photo(2, 'pending'),
        photo(3, 'rejected', reason: 'contains_child'),
        photo(4, 'needs_review', reason: 'needs_review'),
      ],
    ),
  ]) {
    testWidgets('$name goldens', (t) async {
      final gateway = FakeDatingPhotosGateway(
        photos: [...photos],
        afterMutualFrom: DateTime.utc(2026, 1, 1),
      );
      await expectFlowGoldens(
        t,
        name,
        () => DatingPhotosStep(
          nav: DatingStepNav(next: (_) {}, back: () {}, toMe: () {}),
        ),
        overrides: [
          ...datingShellOverrides(),
          datingPhotosGatewayProvider.overrideWithValue(gateway),
        ],
      );
    });
  }

  testWidgets('d10_prompts goldens', (t) async {
    await expectFlowGoldens(
      t,
      'd10_prompts',
      () => DatingPromptsStep(
        nav: DatingStepNav(next: (_) {}, back: () {}, toMe: () {}),
      ),
      overrides: [
        ...datingShellOverrides(),
        datingSetupGatewayProvider.overrideWithValue(
          FakeDatingSetupGateway(
            profile: const DatingMyProfile(
              prompts: [('perfect_sunday', 'A long walk, then lunch.')],
            ),
          ),
        ),
      ],
    );
  });
}
```

Add to `test/features/dating/dating_profile_photo_model_test.dart` (inserted before the file's final `}` of `main`; assert the file ends with `}\n` first; the file is not formatted):

```dart

  // Spec 2 W3c (§4.10): the v2 list's keys, and the caption.
  test('DatingProfilePhoto.fromJson reads the v2 list', () {
    final p = DatingProfilePhoto.fromJson({
      'id': 'photo-6',
      'position': 6,
      'state': 'approved',
      'reason': null,
      'caption': 'At the beach',
      'storage_key': 'dating-photos/x.jpg',
      'created_at': '2026-11-07T10:00:00Z',
    });
    expect(p.position, 6);
    expect(p.isApproved, isTrue);
    expect(p.caption, 'At the beach');
  });
```

Run: `flutter test test/features/dating/setup/d9_d10_test.dart test/features/dating/dating_profile_photo_model_test.dart 2>&1 | tail -2`
Expected: FAIL — `Target of URI doesn't exist: 'package:attune/features/dating/photos/dating_photos_providers.dart'`.

- [ ] **Step 3: The model, the repository, the providers**

Replace the whole of `lib/features/dating/data/models/dating_profile_photo.dart` with exactly (§4.10 "Change": the file is rewritten whole, so it is formatted as new):

```dart
import 'package:equatable/equatable.dart';

/// A Dating photo of the signed-in person (§3.2 D9; positions 1-6). Reads
/// the v2 list's keys (`state`, `reason`, `caption`) and the v1 ones.
class DatingProfilePhoto extends Equatable {
  final String id;
  final int position;
  final String moderationState; // pending | approved | rejected | needs_review
  final String?
  rejectionReason; // face_unclear | too_small | contains_child | unsafe | needs_review
  final String? caption;
  final String storageKey;
  final DateTime createdAt;

  const DatingProfilePhoto({
    required this.id,
    required this.position,
    required this.moderationState,
    this.rejectionReason,
    this.caption,
    required this.storageKey,
    required this.createdAt,
  });

  factory DatingProfilePhoto.fromJson(Map<String, dynamic> json) {
    return DatingProfilePhoto(
      id: json['id'] as String,
      position: json['position'] as int,
      moderationState: (json['state'] ?? json['moderation_state']) as String,
      rejectionReason: (json['reason'] ?? json['rejection_reason']) as String?,
      caption: json['caption'] as String?,
      storageKey: json['storage_key'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  bool get isApproved => moderationState == 'approved';
  bool get isPending => moderationState == 'pending';
  bool get isRejected => moderationState == 'rejected';
  bool get needsReview => moderationState == 'needs_review';

  @override
  List<Object?> get props => [
    id,
    position,
    moderationState,
    rejectionReason,
    caption,
    storageKey,
    createdAt,
  ];
}
```

Create `lib/features/dating/photos/dating_photos_repository.dart` with exactly:

```dart
// Spec 2 W3c (§3.2 D9, §4.4 Photos): the person's own photos, RPC-only,
// the bytes uploaded under an intent and read back by their owner only
// (storage policies, R-2). Nothing is written to disk here.
import 'dart:typed_data';

import 'package:attune/features/dating/data/dating_rpc.dart';
import 'package:attune/features/dating/data/models/dating_profile_photo.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const datingPhotoBucket = 'dating-profile-photos';

class DatingPhotoList {
  const DatingPhotoList({
    this.photos = const [],
    this.afterMutual = false,
    this.afterMutualFrom,
  });

  final List<DatingProfilePhoto> photos;
  final bool afterMutual;
  final DateTime? afterMutualFrom;

  factory DatingPhotoList.fromJson(Map<String, dynamic> json) =>
      DatingPhotoList(
        photos: [
          if (json['photos'] is List)
            for (final p in (json['photos'] as List).whereType<Map>())
              DatingProfilePhoto.fromJson(Map<String, dynamic>.from(p)),
        ],
        afterMutual: json['after_mutual'] == true,
        afterMutualFrom:
            json['after_mutual_from'] is String
                ? DateTime.tryParse(json['after_mutual_from'] as String)
                : null,
      );
}

abstract class DatingPhotosGateway {
  Future<DatingPhotoList> list();
  Future<DatingWrite> add(int position, Uint8List bytes, String mime);
  Future<DatingWrite> remove(String id);
  Future<DatingWrite> reorder(String key, List<String> ids);
  Future<DatingWrite> caption(String id, String text);
  Future<DatingWrite> photosAfterMutual(String key, bool on);
  Future<Uint8List?> bytes(String storageKey);
}

class DatingPhotosRepository implements DatingPhotosGateway {
  DatingPhotosRepository(this._rpc, this._storage);

  final DatingRpc _rpc;
  final SupabaseStorageClient _storage;

  @override
  Future<DatingPhotoList> list() async {
    final json = Map<String, dynamic>.from(
      await _rpc.call('list_dating_profile_photos') as Map,
    );
    if (json['ok'] != true) throw StateError('photos:${json['reason']}');
    return DatingPhotoList.fromJson(json);
  }

  @override
  Future<DatingWrite> add(int position, Uint8List bytes, String mime) async {
    Object? raw;
    try {
      raw = await _rpc.call('create_dating_photo_upload_intent', {
        'p_mime_type': mime,
      });
    } on DatingBusy {
      return DatingWrite.busy;
    } catch (_) {
      return DatingWrite.failed;
    }
    if (raw is! Map || raw['ok'] != true) return DatingWrite.fromJson(raw);
    try {
      await _storage
          .from(datingPhotoBucket)
          .uploadBinary(
            raw['storage_key'] as String,
            bytes,
            fileOptions: FileOptions(contentType: mime, upsert: false),
          );
    } catch (_) {
      return DatingWrite.failed;
    }
    return datingWrite(
      () => _rpc.call('insert_dating_profile_photo', {
        'p_intent_id': raw is Map ? raw['intent_id'] : null,
        'p_position': position,
      }),
    );
  }

  @override
  Future<DatingWrite> remove(String id) => datingWrite(
    () => _rpc.call('delete_dating_profile_photo', {'p_photo_id': id}),
  );

  @override
  Future<DatingWrite> reorder(String key, List<String> ids) => datingWrite(
    () => _rpc.call('reorder_dating_photos', {
      'p_idempotency_key': key,
      'p_order': ids,
    }),
  );

  @override
  Future<DatingWrite> caption(String id, String text) => datingWrite(
    () => _rpc.call('set_dating_photo_caption', {
      'p_photo_id': id,
      'p_caption': text,
    }),
  );

  @override
  Future<DatingWrite> photosAfterMutual(String key, bool on) => datingWrite(
    () => _rpc.call('set_dating_photos_after_mutual', {
      'p_idempotency_key': key,
      'p_on': on,
    }),
  );

  @override
  Future<Uint8List?> bytes(String storageKey) async {
    try {
      return await _storage.from(datingPhotoBucket).download(storageKey);
    } catch (_) {
      return null;
    }
  }
}
```

(The file has exactly one `create_dating_photo_upload_intent` call: `grep -c create_dating_photo_upload_intent lib/features/dating/photos/dating_photos_repository.dart` prints `1`.)

Create `lib/features/dating/photos/dating_photos_providers.dart` with exactly:

```dart
// Spec 2 W3c (D8, C-5): the photos, one entry per account, memory only; the
// picker and the cropper are seams (tests replace them) that never copy a
// picked photo to a permanent directory (R-23).
import 'package:attune/features/dating/data/dating_providers.dart';
import 'package:attune/features/dating/data/dating_supabase_client.dart';
import 'package:attune/features/dating/domain/services/dating_image_preparer.dart';
import 'package:attune/features/dating/photos/dating_photos_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';

final datingPhotosGatewayProvider = Provider<DatingPhotosGateway>(
  (ref) => DatingPhotosRepository(
    ref.watch(datingRpcProvider),
    ref.watch(datingSupabaseClientProvider).storage,
  ),
);

final datingPhotosProvider = FutureProvider.autoDispose
    .family<DatingPhotoList, String?>((ref, account) async {
      if (account == null) return const DatingPhotoList();
      return ref.read(datingPhotosGatewayProvider).list();
    });

final datingImagePreparerProvider = Provider<DatingImagePreparer>(
  (ref) => const DatingImagePreparer(),
);

/// The system picker (gallery); its file is a temporary copy the step deletes.
final datingPhotoPickerProvider = Provider<Future<String?> Function()>(
  (ref) =>
      () async =>
          (await ImagePicker().pickImage(source: ImageSource.gallery))?.path,
);

/// Crop to just you (§3.2 D9), into the cache directory; deleted after.
final datingPhotoCropperProvider =
    Provider<Future<String?> Function(String path)>(
      (ref) =>
          (path) async =>
              (await ImageCropper().cropImage(sourcePath: path))?.path,
    );
```

- [ ] **Step 4: D9 and D10**

Create `lib/features/dating/setup/photos_step.dart` with exactly:

```dart
// Spec 2 §3.2 D9 (Step 8 of 12). Six slots, each read as "Photo {n} of 6,
// {state}"; progress in words (R-22); every rejection names its photo and
// its reason (a CSAM hit is "can't be used", never named); Move earlier /
// Move later beside drag; captions only the person sees; the photos-after
// toggle from account day 30; ~300 KB each. The picked and the prepared
// files are deleted as soon as the upload ends (C-5); thumbnails are the
// person's own bytes, in memory, evicted when the step goes.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/ui/text/allow_large_text.dart';
import 'package:attune/core/utils/date_formatter.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_buttons.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_text_field.dart'
    show FlowErrorLine;
import 'package:attune/features/dating/data/dating_providers.dart';
import 'package:attune/features/dating/data/models/dating_profile_photo.dart';
import 'package:attune/features/dating/domain/services/dating_image_preparer.dart';
import 'package:attune/features/dating/gentle_wait/gentle_wait_providers.dart'
    show datingOnlineProvider;
import 'package:attune/features/dating/photos/dating_photos_providers.dart';
import 'package:attune/features/dating/routes/dating_setup_steps.dart';
import 'package:attune/features/dating/setup/dating_setup_models.dart';
import 'package:attune/features/dating/setup/dating_step_frame.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum _Phase { preparing, uploading }

class DatingPhotosStep extends ConsumerStatefulWidget {
  const DatingPhotosStep({super.key, required this.nav});

  final DatingStepNav nav;

  @override
  ConsumerState<DatingPhotosStep> createState() => _DatingPhotosStepState();
}

class _DatingPhotosStepState extends ConsumerState<DatingPhotosStep>
    with DatingStepState<DatingPhotosStep> {
  final _phase = <int, _Phase>{};
  final _failed = <int>{};
  final _thumbs = <String, Uint8List>{};
  Timer? _poll;
  int _ticks = 0;

  @override
  void resetAnswers() {
    _phase.clear();
    _failed.clear();
    _evict();
    _poll?.cancel();
    _poll = null;
  }

  @override
  void seedAnswers(DatingMyProfile profile) {}

  void _evict() {
    for (final bytes in _thumbs.values) {
      PaintingBinding.instance.imageCache.evict(MemoryImage(bytes));
    }
    _thumbs.clear();
  }

  @override
  void dispose() {
    _poll?.cancel();
    _evict();
    super.dispose();
  }

  void _refresh() =>
      ref.invalidate(datingPhotosProvider(ref.read(datingAccountProvider)));

  void _keepChecking(List<DatingProfilePhoto> photos) {
    final pending = photos.any((p) => p.isPending);
    if (!pending) {
      _poll?.cancel();
      _poll = null;
      return;
    }
    _poll ??= Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted || ++_ticks > 45) {
        _poll?.cancel();
        _poll = null;
        return;
      }
      _refresh();
    });
  }

  void _loadThumbs(List<DatingProfilePhoto> photos) {
    final gateway = ref.read(datingPhotosGatewayProvider);
    for (final p in photos) {
      if (_thumbs.containsKey(p.storageKey)) continue;
      _thumbs[p.storageKey] = Uint8List(0);
      gateway.bytes(p.storageKey).then((b) {
        if (mounted && b != null && b.isNotEmpty) {
          setState(() => _thumbs[p.storageKey] = b);
        }
      });
    }
  }

  Future<void> _add(int position, {bool crop = false}) async {
    if (_phase.containsKey(position)) return;
    final account = ref.read(datingAccountProvider);
    String? picked = await ref.read(datingPhotoPickerProvider)();
    if (picked == null || !mounted) return;
    String? cropped;
    if (crop) {
      cropped = await ref.read(datingPhotoCropperProvider)(picked);
      if (cropped == null || !mounted) {
        await _delete(picked);
        return;
      }
    }
    setState(() {
      _phase[position] = _Phase.preparing;
      _failed.remove(position);
    });
    File? prepared;
    var ok = false;
    try {
      prepared =
          (await ref
              .read(datingImagePreparerProvider)
              .prepare(cropped ?? picked)).file;
      if (!mounted) return;
      setState(() => _phase[position] = _Phase.uploading);
      final bytes = await prepared.readAsBytes();
      ok =
          (await ref
              .read(datingPhotosGatewayProvider)
              .add(position, bytes, 'image/jpeg')).ok;
    } on DatingImageRejected {
      ok = false;
    } catch (_) {
      ok = false;
    } finally {
      await _delete(prepared?.path);
      await _delete(cropped);
      await _delete(picked);
    }
    if (!mounted || ref.read(datingAccountProvider) != account) return;
    setState(() {
      _phase.remove(position);
      if (!ok) _failed.add(position);
    });
    _refresh();
  }

  Future<void> _delete(String? path) async {
    if (path == null) return;
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  Future<void> _move(List<DatingProfilePhoto> photos, int index, int by) async {
    final ids = [for (final p in photos) p.id];
    final to = index + by;
    if (by == 0) return;
    if (to < 0 || to >= ids.length) return;
    final id = ids.removeAt(index);
    ids.insert(to, id);
    await ref
        .read(datingPhotosGatewayProvider)
        .reorder(keys.keyFor('reorder', ids), ids);
    _refresh();
  }

  Future<void> _caption(DatingProfilePhoto photo) async {
    final loc = AppLocalizations.of(context)!;
    final controller = TextEditingController(text: photo.caption ?? '');
    final text = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder:
          (sheet) => AllowLargeText(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                Spacing.lg,
                0,
                Spacing.lg,
                MediaQuery.of(sheet).viewInsets.bottom + Spacing.lg,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: controller,
                    maxLength: 100,
                    decoration: InputDecoration(
                      labelText: loc.dating_photoCaptionLabel,
                    ),
                  ),
                  FlowPrimaryButton(
                    label: loc.dating_photoSave,
                    onPressed: () => Navigator.of(sheet).pop(controller.text),
                  ),
                ],
              ),
            ),
          ),
    );
    controller.dispose();
    if (text == null || !mounted) return;
    await ref.read(datingPhotosGatewayProvider).caption(photo.id, text.trim());
    _refresh();
  }

  String _stateText(AppLocalizations loc, int n, DatingProfilePhoto? p) {
    final phase = _phase[n];
    if (phase == _Phase.preparing) return loc.dating_photoPreparing(n);
    if (phase == _Phase.uploading) return loc.dating_photoUploading(n);
    if (_failed.contains(n)) return loc.dating_photoFailed(n);
    if (p == null) return loc.dating_photoAdd;
    if (p.isApproved) return loc.dating_photoReady;
    if (p.isPending) return loc.dating_photoChecking;
    if (p.needsReview) return loc.dating_photoReview;
    return switch (p.rejectionReason) {
      'face_unclear' => loc.dating_photoFaceUnclear(n),
      'too_small' => loc.dating_photoTooSmall(n),
      'contains_child' => loc.dating_photoChild(n),
      _ => loc.dating_photoCantUse(n),
    };
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final online = ref.watch(datingOnlineProvider).valueOrNull ?? true;
    final list =
        ref
            .watch(datingPhotosProvider(ref.watch(datingAccountProvider)))
            .valueOrNull;
    final photos = [...?list?.photos]
      ..sort((a, b) => a.position.compareTo(b.position));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _keepChecking(photos);
      _loadThumbs(photos);
    });
    final usable = photos.where((p) => !p.isRejected).length;
    final from = list?.afterMutualFrom;
    final afterOpen = from != null && !DateTime.now().toUtc().isBefore(from);
    final byPosition = {for (final p in photos) p.position: p};
    Widget slot(int n, {int? dragIndex}) {
      final p = byPosition[n];
      return _Slot(
        n: n,
        photo: p,
        dragIndex: dragIndex,
        thumb: p == null ? null : _thumbs[p.storageKey],
        state: _stateText(loc, n, p),
        busy: _phase.containsKey(n),
        online: online,
        onAdd: () => _add(n),
        onCrop: () => _add(n, crop: true),
        onEarlier:
            p == null ? null : () => _move(photos, photos.indexOf(p), -1),
        onLater: p == null ? null : () => _move(photos, photos.indexOf(p), 1),
        onCaption: p == null ? null : () => _caption(p),
        onRemove:
            p == null
                ? null
                : () async {
                  await ref.read(datingPhotosGatewayProvider).remove(p.id);
                  _refresh();
                },
      );
    }

    return DatingStepFrame(
      step: 'photos',
      title: loc.dating_photosTitle,
      onBack: widget.nav.back,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(loc.dating_photosBody, style: theme.textTheme.bodyLarge),
          if (!online) ...[
            const SizedBox(height: Spacing.sm),
            Text(loc.dating_photosOffline, style: theme.textTheme.bodyMedium),
          ],
          const SizedBox(height: Spacing.md),
          // Drag (the thumbnail is the handle) or Move earlier / Move later
          // (§3.2 D9 "reorder by drag or by" the actions); empty slots follow.
          ReorderableListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            onReorder:
                (from, to) =>
                    _move(photos, from, (to > from ? to - 1 : to) - from),
            children: [
              for (final (i, p) in photos.indexed)
                KeyedSubtree(
                  key: ValueKey('slot_${p.id}'),
                  child: slot(p.position, dragIndex: i),
                ),
            ],
          ),
          for (var n = 1; n <= 6; n++)
            if (byPosition[n] == null) slot(n),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(loc.dating_photosAfterMutual),
            subtitle:
                afterOpen || from == null
                    ? null
                    : Text(
                      loc.dating_photosAfterMutualFrom(
                        MyDateFormat.toDate(from.toLocal()),
                      ),
                    ),
            value: list?.afterMutual ?? false,
            onChanged:
                afterOpen && online
                    ? (on) async {
                      await ref
                          .read(datingPhotosGatewayProvider)
                          .photosAfterMutual(keys.keyFor('after', on), on);
                      _refresh();
                    }
                    : null,
          ),
          Text(loc.dating_photosData, style: theme.textTheme.bodySmall),
        ],
      ),
      primary: FlowPrimaryButton(
        label: loc.dating_continue,
        onPressed:
            online && usable >= 2 ? () => widget.nav.next('prompts') : null,
      ),
    );
  }
}

class _Slot extends StatelessWidget {
  const _Slot({
    required this.n,
    required this.photo,
    required this.thumb,
    required this.state,
    required this.busy,
    required this.online,
    required this.onAdd,
    required this.onCrop,
    required this.onEarlier,
    required this.onLater,
    required this.onCaption,
    required this.onRemove,
    this.dragIndex,
  });

  final int n;
  final DatingProfilePhoto? photo;
  final Uint8List? thumb;
  final String state;
  final bool busy;
  final bool online;
  final VoidCallback onAdd;
  final VoidCallback onCrop;
  final VoidCallback? onEarlier;
  final VoidCallback? onLater;
  final VoidCallback? onCaption;
  final VoidCallback? onRemove;
  final int? dragIndex;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final p = photo;
    final rejected = p != null && p.isRejected;
    final image =
        thumb != null && thumb!.isNotEmpty
            ? Image.memory(
              thumb!,
              width: 64,
              height: 64,
              fit: BoxFit.cover,
              gaplessPlayback: true,
            )
            : Icon(
              p == null ? Icons.add_a_photo_outlined : Icons.image_outlined,
              size: 32,
            );
    return Semantics(
      container: true,
      label: loc.dating_photoSlot(n, state),
      customSemanticsActions: {
        if (onEarlier != null)
          CustomSemanticsAction(label: loc.dating_photoMoveEarlier): onEarlier!,
        if (onLater != null)
          CustomSemanticsAction(label: loc.dating_photoMoveLater): onLater!,
      },
      child: Padding(
        padding: const EdgeInsets.only(bottom: Spacing.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ExcludeSemantics(
              child:
                  dragIndex == null
                      ? SizedBox(
                        width: 64,
                        height: 64,
                        child: Center(child: image),
                      )
                      : ReorderableDragStartListener(
                        key: ValueKey('drag_${p!.id}'),
                        index: dragIndex!,
                        child: SizedBox(
                          width: 64,
                          height: 64,
                          child: Center(child: image),
                        ),
                      ),
            ),
            const SizedBox(width: Spacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ExcludeSemantics(
                    child:
                        rejected
                            ? FlowErrorLine(text: state)
                            : Text(state, style: theme.textTheme.bodyMedium),
                  ),
                  Wrap(
                    children: [
                      if (p == null || rejected)
                        FlowTextLink(
                          label:
                              p == null
                                  ? loc.dating_photoAdd
                                  : loc.dating_photoReplace,
                          onPressed: online && !busy ? onAdd : () {},
                        ),
                      if (p != null && p.rejectionReason == 'contains_child')
                        FlowTextLink(
                          label: loc.dating_photoCrop,
                          onPressed: online && !busy ? onCrop : () {},
                        ),
                      if (p != null) ...[
                        IconButton(
                          tooltip: loc.dating_photoMoveEarlier,
                          icon: const Icon(Icons.arrow_upward),
                          onPressed: onEarlier,
                        ),
                        IconButton(
                          tooltip: loc.dating_photoMoveLater,
                          icon: const Icon(Icons.arrow_downward),
                          onPressed: onLater,
                        ),
                        IconButton(
                          tooltip: loc.dating_photoCaption,
                          icon: const Icon(Icons.short_text),
                          onPressed: onCaption,
                        ),
                        IconButton(
                          tooltip: loc.dating_photoRemove,
                          icon: const Icon(Icons.delete_outline),
                          onPressed: onRemove,
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

(Reorder: drag by the thumbnail (`ReorderableDragStartListener`, no long-press delay) or the Move earlier / Move later buttons and semantic actions, as §3.2 D9 asks; empty slots sit after the filled ones and are not draggable.)

Create `lib/features/dating/setup/prompts_step.dart` with exactly:

```dart
// Spec 2 §3.2 D10 (Step 9 of 12): two of ten prompts (a third optional),
// 10-200 characters each, each a labelled field with its count; the
// server's contact and kindness filters land on their own prompt.
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_buttons.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_text_field.dart'
    show FlowErrorLine;
import 'package:attune/features/dating/gentle_wait/gentle_wait_providers.dart'
    show datingOnlineProvider;
import 'package:attune/features/dating/routes/dating_setup_steps.dart';
import 'package:attune/features/dating/setup/dating_setup_models.dart';
import 'package:attune/features/dating/setup/dating_setup_providers.dart';
import 'package:attune/features/dating/setup/dating_step_frame.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const datingPromptIds = [
  'perfect_sunday',
  'feel_at_home',
  'friends_say',
  'looking_for',
  'small_thing',
  'win_me_over',
  'learning_to',
  'family_describe',
  'place_love',
  'ask_me_about',
];

String datingPromptText(AppLocalizations loc, String id) => switch (id) {
  'perfect_sunday' => loc.dating_prompt_perfect_sunday,
  'feel_at_home' => loc.dating_prompt_feel_at_home,
  'friends_say' => loc.dating_prompt_friends_say,
  'looking_for' => loc.dating_prompt_looking_for,
  'small_thing' => loc.dating_prompt_small_thing,
  'win_me_over' => loc.dating_prompt_win_me_over,
  'learning_to' => loc.dating_prompt_learning_to,
  'family_describe' => loc.dating_prompt_family_describe,
  'place_love' => loc.dating_prompt_place_love,
  _ => loc.dating_prompt_ask_me_about,
};

class DatingPromptsStep extends ConsumerStatefulWidget {
  const DatingPromptsStep({super.key, required this.nav});

  final DatingStepNav nav;

  @override
  ConsumerState<DatingPromptsStep> createState() => _DatingPromptsStepState();
}

class _DatingPromptsStepState extends ConsumerState<DatingPromptsStep>
    with DatingStepState<DatingPromptsStep> {
  final _chosen = <String>[];
  final _answers = <String, TextEditingController>{};
  bool _tooShort = false;

  TextEditingController _controller(String id) =>
      _answers.putIfAbsent(id, TextEditingController.new);

  @override
  void dispose() {
    for (final c in _answers.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  void resetAnswers() {
    _chosen.clear();
    for (final c in _answers.values) {
      c.clear();
    }
    _tooShort = false;
  }

  @override
  void seedAnswers(DatingMyProfile p) {
    _chosen
      ..clear()
      ..addAll(p.prompts.map((x) => x.$1));
    for (final (id, answer) in p.prompts) {
      _controller(id).text = answer;
    }
  }

  void _continue() {
    final items = [for (final id in _chosen) (id, _controller(id).text.trim())];
    if (items.length < 2 ||
        items.any((i) => i.$2.runes.length < 10 || i.$2.runes.length > 200)) {
      setState(() => _tooShort = true);
      return;
    }
    setState(() => _tooShort = false);
    write(
      'd10',
      items,
      (key) => ref.read(datingSetupGatewayProvider).savePrompts(key, items),
      (w) => widget.nav.next(w.nextStep ?? 'verify'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    watchProfile();
    final online = ref.watch(datingOnlineProvider).valueOrNull ?? true;
    final theme = Theme.of(context);
    final refusedAt = refusal?.position;
    return DatingStepFrame(
      step: 'prompts',
      title: loc.dating_promptsTitle,
      onBack: widget.nav.back,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(loc.dating_promptsBody, style: theme.textTheme.bodyLarge),
          const SizedBox(height: Spacing.md),
          for (final id in datingPromptIds) ...[
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(datingPromptText(loc, id)),
              value: _chosen.contains(id),
              onChanged:
                  _chosen.contains(id) || _chosen.length < 3
                      ? (v) => setState(
                        () => v == true ? _chosen.add(id) : _chosen.remove(id),
                      )
                      : null,
            ),
            if (_chosen.contains(id)) ...[
              ListenableBuilder(
                listenable: _controller(id),
                builder:
                    (context, _) => TextField(
                      key: ValueKey('dating_prompt_$id'),
                      controller: _controller(id),
                      maxLength: 200,
                      minLines: 2,
                      maxLines: 5,
                      decoration: InputDecoration(
                        labelText: datingPromptText(loc, id),
                        counterText: loc.dating_gentleWaitAnswerCount(
                          _controller(id).text.runes.length,
                          200,
                        ),
                      ),
                    ),
              ),
              if (refusedAt != null && refusedAt == _chosen.indexOf(id) + 1)
                datingRefusalLine(loc, refusal!),
            ],
          ],
          if (_tooShort)
            FlowErrorLine(text: loc.dating_promptTooShort, liveRegion: true),
          if (refusal != null && refusedAt == null)
            datingRefusalLine(loc, refusal!),
        ],
      ),
      primary: FlowPrimaryButton(
        label: loc.dating_continue,
        busy: saving,
        onPressed: online && _chosen.length >= 2 ? _continue : null,
      ),
    );
  }
}
```

Create `$D/edit_T10.py` with exactly:

```python
import sys
sys.path.insert(0, '.superpowers/sdd/2026-11-07-spec2-w3')
from anchor import edit
F = 'lib/features/dating/routes/dating_setup_steps.dart'
edit(F, [
    ("import 'package:attune/features/dating/setup/meet_step.dart';\n",
     "import 'package:attune/features/dating/setup/meet_step.dart';\n"
     "import 'package:attune/features/dating/setup/photos_step.dart';\n"
     "import 'package:attune/features/dating/setup/prompts_step.dart';\n"),
    ("  'faith' => DatingFaithStep(nav: nav),\n",
     "  'faith' => DatingFaithStep(nav: nav),\n"
     "  'photos' => DatingPhotosStep(nav: nav),\n"
     "  'prompts' => DatingPromptsStep(nav: nav),\n"),
], 'T10 steps')
```

```bash
D=.superpowers/sdd/2026-11-07-spec2-w3
python3 -I $D/edit_T10.py
dart format lib/features/dating/data/models/dating_profile_photo.dart lib/features/dating/photos lib/features/dating/setup/photos_step.dart lib/features/dating/setup/prompts_step.dart test/features/dating/setup/d9_d10_test.dart test/features/dating/support/dating_photos_fakes.dart
flutter analyze --no-pub lib/features/dating test/features/dating 2>&1 | tail -1
flutter test --update-goldens test/features/dating/setup/d9_d10_test.dart 2>&1 | tail -1
flutter test test/features/dating 2>&1 | tail -1
python3 scripts/large_text_audit.py --scale 2.0 test/features/dating/setup 2>&1 | tail -1
```

Expected: the edit; `Formatted …`; `No issues found!`; goldens `d9_photos_empty`, `d9_photos_states`, `d10_prompts` (×4) — open the 2.0 ones: each slot's state text wraps, every action reachable; `All tests passed!`; `SCALE 2.0: 0 site(s) to fix, 0 listed apart`.

- [ ] **Step 5: Mutants**

Create `$D/mut_T10.py` with exactly:

```python
S = 'lib/features/dating/setup/'
T = ['test/features/dating/setup/d9_d10_test.dart']
MUTS = {
  'temp_kept': (S + 'photos_step.dart', "      await _delete(prepared?.path);\n", "", T),
  'picked_kept': (S + 'photos_step.dart', "      await _delete(picked);\n    }\n    if (!mounted", "    }\n    if (!mounted", T),
  'continue_counts_rejected': (S + 'photos_step.dart', "    final usable = photos.where((p) => !p.isRejected).length;", "    final usable = photos.length;", T),
  'child_reason_generic': (S + 'photos_step.dart', "      'contains_child' => loc.dating_photoChild(n),\n", "", T),
  'slot_label_lost': (S + 'photos_step.dart', "      label: loc.dating_photoSlot(n, state),", "      label: state,", T),
  'after_mutual_early': (S + 'photos_step.dart', "                afterOpen && online\n                    ? (on) async {", "                online\n                    ? (on) async {", T),
  'offline_adds': (S + 'photos_step.dart', "                          onPressed: online && !busy ? onAdd : () {},", "                          onPressed: onAdd,", T),
  'move_wrong_way': (S + 'photos_step.dart', "    final to = index + by;", "    final to = index - by;", T),
  'drag_lost': (S + 'photos_step.dart', "            onReorder:\n                (from, to) =>\n                    _move(photos, from, (to > from ? to - 1 : to) - from),\n", "            onReorder: (from, to) {},\n", T),
  'prompt_short_sent': (S + 'prompts_step.dart', "    if (items.length < 2 ||\n        items.any((i) => i.$2.runes.length < 10 || i.$2.runes.length > 200)) {", "    if (items.length < 2) {", T),
  # A fourth prompt can be ticked (the bound gone; the closure kept, so it compiles).
  'prompt_four': (S + 'prompts_step.dart', "                  _chosen.contains(id) || _chosen.length < 3\n", "                  _chosen.contains(id) || _chosen.length < 4\n", T),
  'filter_lands_nowhere': (S + 'prompts_step.dart', "              if (refusedAt != null && refusedAt == _chosen.indexOf(id) + 1)\n                datingRefusalLine(loc, refusal!),\n", "", T),
}
```

```bash
python3 -I $D/dmut.py $D/mut_T10.py | tee $D/mut_T10.txt | tail -1
```

Expected: `12/12 killed`.

- [ ] **Step 6: Do not commit; record the tree in the report.**


### Task 11: D11's shell, the introduction card, D12 (preview) and D13 (ready) (§3.2 D11–D13, §3.3.2 intro copy, §3.4 card, §3.15 rows D11–D13, §7.2 S17; A-11; R-26, R-27, R-28, R-38, R-39, R-40)

**Files:**
- Create: `lib/features/dating/card/dating_card.dart` (`DatingCard`, `DatingCardView`), `lib/features/dating/setup/dating_preview_providers.dart`, `lib/features/dating/section/dating_lifecycle_errors.dart`, `lib/features/dating/setup/{verify_step,preview_step,ready_step}.dart`, `test/features/dating/setup/d11_d13_test.dart` (+ goldens), `$D/{arb_fragment_T11.txt, edit_T11.py, mut_T11.py}`
- Modify: `lib/features/dating/routes/dating_setup_steps.dart` (three cases), `lib/i10n/app_en.arb` + generated

**Interfaces:**
- Consumes: `get_dating_profile_preview()` (W1d, live; `{ok, card:{display_name, age, region_name_key, intention, marriage_timeline, children_have, children_want, gender:{identity, specific, specific_text}|null, pronouns, faith:{faith, denomination}|null, marital, prompts:[{prompt_id, answer}], photos_after_mutual, photos:[{id, position}]}}` or `{ok:false, reason}`); Task 10's `datingPhotosProvider`/`DatingPhotosGateway.bytes`, `datingPromptText`; Task 5's `saveDisplayName`, `saveSettings`, `DatingMyProfile` (`displayName`, `dropTime`, `digestPush`, `chatPush`, `dataSaver`); Task 6's `DatingStepFrame`, `DatingStepState`, `DatingChoiceGroup`, `showDatingPicker`; Task 1's `datingLifecycleGatewayProvider`, `datingHomeProvider` (`firstDropAt`, R-4); Spec 1's `setDatingLock(context, ref, on, {pins})`, `datingLockProvider`, `SafetyPinStore` (`hasPin`, `everyOpen`, `setEveryOpen`), `confirmSafetyPin`, `pushAskerProvider` (`permissionGranted`, `askInContext`), `RouteNames.safetyPin`, `RouteNames.reflectionJournal`.
- Produces: `DatingCard.fromJson`, `DatingCardView({card, photos, photosHidden, onShowPhotos, trailing})` (W5b's Today reuses both, adding the "Why you two" block and the actions); `datingIntentionLine(AppLocalizations, DatingCard)`; `DatingPreviewGateway`, `datingPreviewGatewayProvider`, `datingPreviewProvider(account)`; `datingLifecycleErrorRows(BuildContext, AppLocalizations, DatingLifecycleError, {VoidCallback? onVerify})`, `DatingCalmLine`; `const datingDropTimes` (07:00–22:00, 30-minute steps), `datingDropTimeLabel(String)`, `pickDatingDropTime(BuildContext, String current) → Future<String?>`; `DatingVerifyStep`, `DatingPreviewStep`, `DatingReadyStep({nav, SafetyPinStore? pins})`.

Rulings: R-38, R-39, R-40 (pre-flight list).

- [ ] **Step 1: The strings**

Create `$D/arb_fragment_T11.txt` with exactly:

```
  "dating_verifyTitle": "Verify it's you",
  "@dating_verifyTitle": {"description": "Spec 2 §3.2 D11 / §3.3.2 (the shell until W4a, R-26)."},
  "dating_verifyBody": "A short video selfie checks that you're a real person, that your photos are you, and that you're over 18. The video is deleted at once. We keep only whether it passed.",
  "dating_verifyLater": "You'll do this check before your first introduction.",
  "@dating_verifyLater": {"description": "D11 shell line until W4a (plan, R-26)."},

  "dating_previewTitle": "This is what others see",
  "@dating_previewTitle": {"description": "Spec 2 §3.2 D12."},
  "dating_previewNever": "Never shown: who you'd like to meet, your exact location, your date of birth.",
  "dating_previewUnavailable": "Your preview can't be shown right now.",
  "@dating_previewUnavailable": {"description": "D12: the preview read failed (plan)."},
  "dating_tryAgain": "Try again",
  "@dating_tryAgain": {"description": "Retry (plan)."},
  "dating_nameLabel": "First name",
  "dating_nameHelper": "Use your first name or what friends call you.",
  "dating_nameInvalid": "Use 1 to 30 characters.",
  "@dating_nameInvalid": {"description": "D12 first-name length (plan)."},
  "dating_save": "Save",
  "@dating_save": {"description": "Save (plan)."},
  "dating_editName": "Edit first name",
  "dating_editLooking": "Edit what you're looking for",
  "dating_editWhere": "Edit where you are",
  "dating_editPrompts": "Edit your answers",
  "dating_editChildren": "Edit children",
  "dating_editAbout": "Edit what you show about yourself",
  "dating_editPhotos": "Edit photos",
  "@dating_editName": {"description": "D12 per-section edit links (plan; §3.2 D12 'Edit links: per section')."},
  "dating_pushDigest": "Tell me about new introductions and matches, at most once a day.",
  "dating_pushTurnOn": "Turn on",
  "dating_pushDigestOn": "We'll tell you about new introductions and matches, at most once a day.",
  "@dating_pushDigestOn": {"description": "D12 after Turn on (plan)."},
  "dating_pushMessages": "Tell me when someone messages me",

  "dating_cardHeading": "{name}, {age}",
  "@dating_cardHeading": {"description": "§3.4 card heading.", "placeholders": {"name": {"type": "String"}, "age": {"type": "int"}}},
  "dating_cardMarriage": "Looking for marriage",
  "@dating_cardMarriage": {"description": "§3.4 intention, timeline hidden (plan)."},
  "dating_cardMarriageSoon": "Looking for marriage, in the next year or two",
  "dating_cardMarriageFew": "Looking for marriage, in a few years",
  "@dating_cardMarriageFew": {"description": "§3.4 intention with D2's 'In a few years' (plan; cultural reviewer)."},
  "dating_cardMarriageNone": "Looking for marriage, with no set time",
  "@dating_cardMarriageNone": {"description": "§3.4 intention with D2's 'No set time' (plan; cultural reviewer)."},
  "dating_cardCommitted": "Looking for a committed relationship",
  "dating_cardCompanionship": "Looking for companionship, at their own pace",
  "dating_cardNotSure": "Not sure yet",
  "dating_cardHasChildren": "Has children",
  "dating_cardNoChildren": "No children",
  "dating_cardWantsChildren": "Wants children",
  "dating_cardNoWantChildren": "Doesn't want children",
  "dating_cardOpenChildren": "Open to children",
  "dating_cardPhotosLater": "Photos appear after you're both interested.",
  "dating_cardShowPhotos": "Show photos (about 1 MB)",
  "dating_cardPhoto": "Photo {n} of {count}",
  "@dating_cardPhoto": {"description": "§3.4 carousel semantics (plan).", "placeholders": {"n": {"type": "int"}, "count": {"type": "int"}}},

  "dating_readyTitle": "You're all set",
  "@dating_readyTitle": {"description": "Spec 2 §3.2 D13."},
  "dating_readyFirst": "Your first introductions arrive {date} at {time}.",
  "@dating_readyFirst": {"description": "D13.", "placeholders": {"date": {"type": "String"}, "time": {"type": "String"}}},
  "dating_readyChangeTime": "Change time",
  "dating_readyTimeTitle": "Pick a time when you have a few quiet minutes.",
  "dating_readyWhile": "While you wait",
  "@dating_readyWhile": {"description": "D13 heading (plan)."},
  "dating_readyJournal": "Write in your journal",
  "dating_readySharedQ": "Does anyone else use this phone?",
  "dating_readyLock": "Lock Dating with your PIN",
  "dating_readyEveryOpen": "Ask for my PIN every time Attune opens",
  "dating_done": "Done",
  "dating_readyGates": "We still need to check it's you before introductions start.",
  "@dating_readyGates": {"description": "D13 activation before W4a (plan, R-26)."}
```

```bash
D=.superpowers/sdd/2026-11-07-spec2-w3
python3 -I .superpowers/sdd/2026-10-26-spec1-w3/arb_append.py $D/arb_fragment_T11.txt
flutter gen-l10n --arb-dir=lib/i10n --template-arb-file=app_en.arb --output-dir=lib/i10n/generated --output-localization-file=app_localizations.dart --no-synthetic-package
```

Expected: `added 49 keys`. (`dating_cardCompanionship` is §3.4's copy verbatim, "at their own pace", about the person on the card, not a partner; `dating_cardMarriageFew`/`None` are this plan's and go to the cultural reviewer with D2.)

- [ ] **Step 2: Write the failing tests**

Create `test/features/dating/setup/d11_d13_test.dart` with exactly:

```dart
// Spec 2 W3c (§3.2 D11-D13, §3.4, §3.15, S17): verify shell, preview, ready.
import 'package:attune/core/notifications/services/onesignal_service.dart';
import 'package:attune/core/notifications/services/push_permission_policy.dart';
import 'package:attune/features/dating/card/dating_card.dart';
import 'package:attune/features/dating/data/dating_home.dart';
import 'package:attune/features/dating/data/dating_rpc.dart';
import 'package:attune/features/dating/data/dating_lifecycle_repository.dart';
import 'package:attune/features/dating/photos/dating_photos_providers.dart';
import 'package:attune/features/dating/routes/dating_setup_steps.dart';
import 'package:attune/features/dating/setup/dating_preview_providers.dart';
import 'package:attune/features/dating/setup/dating_setup_models.dart';
import 'package:attune/features/dating/setup/dating_setup_providers.dart';
import 'package:attune/features/dating/setup/preview_step.dart';
import 'package:attune/features/dating/setup/ready_step.dart';
import 'package:attune/features/dating/setup/verify_step.dart';
import 'package:attune/features/safety/data/dating_lock_store.dart';
import 'package:attune/features/safety/data/safety_pin_store.dart';
import 'package:attune/features/safety/domain/safety_pin.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../helpers/fake_push_asker.dart';
import '../../../helpers/flow_harness.dart';
import '../../../helpers/tap_in_reach.dart';
import '../support/dating_fakes.dart';
import '../support/dating_photos_fakes.dart';
import '../support/dating_setup_fakes.dart';
import '../support/dating_shell.dart';

class _Preview implements DatingPreviewGateway {
  _Preview(this.card);
  DatingCard? card;
  Object? error;
  @override
  Future<DatingCard?> preview() async {
    if (error != null) throw error!;
    return card;
  }
}

final _ama = DatingCard.fromJson({
  'display_name': 'Ama',
  'age': 29,
  'region_name_key': 'dating_region_gh_aa',
  'intention': 'marriage',
  'marriage_timeline': 'within_two_years',
  'children_have': false,
  'children_want': 'yes',
  'gender': null,
  'pronouns': null,
  'faith': {'faith': 'christian', 'denomination': 'methodist'},
  'marital': null,
  'prompts': [
    {
      'prompt_id': 'perfect_sunday',
      'answer': 'Church, then jollof with my sisters.',
    },
    {'prompt_id': 'ask_me_about', 'answer': 'My grandmother stories.'},
  ],
  'photos_after_mutual': false,
  'photos': [
    {'id': 'p1', 'position': 1},
    {'id': 'p2', 'position': 2},
  ],
});

typedef _Nav = ({List<String> steps, List<String> me});

DatingStepNav _nav(_Nav n) =>
    DatingStepNav(next: n.steps.add, back: () {}, toMe: () => n.me.add('me'));

/// A Safety PIN store (cheap hashing). pumpFlowScreen empties the keystore
/// mock, so the PIN is set after the screen is pumped.
SafetyPinStore _store() => SafetyPinStore(
  hasher: (p) async => hashPin(p, iterations: 1000),
  verifier: (p, e) async => verifyPinHash(p, e),
);

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('D11 shell: the intro copy, Continue opens the preview (R-26)', (
    t,
  ) async {
    final n = (steps: <String>[], me: <String>[]);
    await pumpFlowScreen(
      t,
      () => DatingVerifyStep(nav: _nav(n)),
      overrides: datingShellOverrides(),
    );
    await t.pumpAndSettle();
    expect(find.text("Verify it's you"), findsOneWidget);
    expect(find.text('Step 10 of 12'), findsOneWidget);
    expect(
      find.textContaining('The video is deleted at once.'),
      findsOneWidget,
    );
    await tapInReach(t, find.text('Continue'));
    expect(n.steps, ['preview']);
  });

  group('D12', () {
    Future<(FakeDatingSetupGateway, FakePushAsker, _Nav, _Preview)> preview(
      WidgetTester t, {
      DatingCard? card,
      bool granted = false,
      bool grantOnAsk = true,
      DatingMyProfile profile = const DatingMyProfile(displayName: 'Ama'),
    }) async {
      await t.pumpWidget(const SizedBox());
      final setup = FakeDatingSetupGateway(profile: profile);
      final asker = FakePushAsker(granted: granted, grantOnAsk: grantOnAsk);
      final n = (steps: <String>[], me: <String>[]);
      final gateway = _Preview(card ?? _ama);
      await pumpFlowScreen(
        t,
        () => DatingPreviewStep(nav: _nav(n)),
        overrides: [
          ...datingShellOverrides(),
          datingSetupGatewayProvider.overrideWithValue(setup),
          datingPreviewGatewayProvider.overrideWithValue(gateway),
          datingPhotosGatewayProvider.overrideWithValue(
            FakeDatingPhotosGateway(
              photos: [photo(1, 'approved'), photo(2, 'approved')],
            ),
          ),
          pushAskerProvider.overrideWithValue(asker),
        ],
      );
      await t.pumpAndSettle();
      return (setup, asker, n, gateway);
    }

    testWidgets('the card, person first, in the order others read it', (
      t,
    ) async {
      await preview(t);
      expect(find.text('This is what others see'), findsOneWidget);
      expect(find.text('Step 11 of 12'), findsOneWidget);
      final order = [
        'Ama, 29',
        'Looking for marriage, in the next year or two',
        'A perfect Sunday for me looks like…',
        'No children',
        'Methodist',
      ];
      double y(String s) => t.getTopLeft(find.textContaining(s).first).dy;
      for (var i = 1; i < order.length; i++) {
        expect(
          y(order[i - 1]),
          lessThan(y(order[i])),
          reason: '${order[i - 1]} before ${order[i]}',
        );
      }
      expect(
        find.text(
          "Never shown: who you'd like to meet, your exact location, your date of birth.",
        ),
        findsOneWidget,
      );
    });

    testWidgets(
      'photos after mutual interest: the card says so and shows none',
      (t) async {
        await preview(
          t,
          card: DatingCard.fromJson({
            'display_name': 'Ama',
            'age': 29,
            'photos_after_mutual': true,
            'photos': [],
            'prompts': [],
          }),
        );
        expect(
          find.text("Photos appear after you're both interested."),
          findsOneWidget,
        );
        expect(find.bySemanticsLabel(RegExp(r'^Photo 1 of')), findsNothing);
      },
    );

    testWidgets('data saver: photos wait for a tap', (t) async {
      await preview(
        t,
        profile: const DatingMyProfile(displayName: 'Ama', dataSaver: true),
      );
      expect(find.text('Show photos (about 1 MB)'), findsOneWidget);
    });

    testWidgets('first name: 1 to 30 characters, saved through its writer', (
      t,
    ) async {
      final (setup, _, _, _) = await preview(t);
      await tapInReach(t, find.text('Edit first name'));
      await t.pumpAndSettle();
      expect(
        find.text('Use your first name or what friends call you.'),
        findsOneWidget,
      );
      await t.enterText(find.byKey(const ValueKey('dating_name_field')), '   ');
      await tapInReach(t, find.text('Save'));
      await t.pumpAndSettle();
      expect(find.text('Use 1 to 30 characters.'), findsOneWidget);
      expect(setup.writes, isEmpty);
      await t.enterText(
        find.byKey(const ValueKey('dating_name_field')),
        ' Ama B ',
      );
      await tapInReach(t, find.text('Save'));
      await t.pumpAndSettle();
      expect(setup.lastWrite.$1, 'saveDisplayName');
      expect(setup.lastWrite.$2['name'], 'Ama B');
    });

    testWidgets('edit links reopen the step and come back (R-40)', (t) async {
      final (_, _, n, _) = await preview(t);
      await tapInReach(t, find.text('Edit your answers'));
      expect(n.steps, ['prompts?from=preview']);
    });

    testWidgets('Turn on asks in context, then saves the digest (R-27)', (
      t,
    ) async {
      final (setup, asker, _, _) = await preview(t);
      expect(
        t
            .widget<SwitchListTile>(
              find.widgetWithText(
                SwitchListTile,
                'Tell me when someone messages me',
              ),
            )
            .onChanged,
        isNull,
      );
      await tapInReach(t, find.text('Turn on'));
      await t.pumpAndSettle();
      expect(asker.asked, [PushAskContext.j3]);
      expect(setup.lastWrite.$2['values'], {'digest_push': true});
      expect(
        t
            .widget<SwitchListTile>(
              find.widgetWithText(
                SwitchListTile,
                'Tell me when someone messages me',
              ),
            )
            .onChanged,
        isNotNull,
      );
    });

    testWidgets('a declined ask saves nothing', (t) async {
      final (setup, _, _, _) = await preview(t, grantOnAsk: false);
      await tapInReach(t, find.text('Turn on'));
      await t.pumpAndSettle();
      expect(setup.writes, isEmpty);
    });

    testWidgets('an unreadable preview says so and can be retried', (t) async {
      await t.pumpWidget(const SizedBox());
      final gateway = _Preview(_ama)..error = StateError('preview:unavailable');
      await pumpFlowScreen(
        t,
        () => DatingPreviewStep(nav: _nav((steps: <String>[], me: <String>[]))),
        overrides: [
          ...datingShellOverrides(),
          datingSetupGatewayProvider.overrideWithValue(
            FakeDatingSetupGateway(),
          ),
          datingPreviewGatewayProvider.overrideWithValue(gateway),
          datingPhotosGatewayProvider.overrideWithValue(
            FakeDatingPhotosGateway(),
          ),
          pushAskerProvider.overrideWithValue(FakePushAsker()),
        ],
      );
      await t.pumpAndSettle();
      expect(
        find.text("Your preview can't be shown right now."),
        findsOneWidget,
      );
      gateway.error = null;
      await tapInReach(t, find.text('Try again'));
      await t.pumpAndSettle();
      expect(find.text('Ama, 29'), findsOneWidget);
    });

    testWidgets('Continue opens D13', (t) async {
      final (_, _, n, _) = await preview(t);
      await tapInReach(t, find.text('Continue'));
      expect(n.steps, ['ready']);
    });
  });

  group('D13', () {
    Future<(FakeDatingSetupGateway, FakeDatingLifecycleGateway, _Nav)> ready(
      WidgetTester t, {
      SafetyPinStore? pins,
      bool online = true,
      DatingLifecycleResult result = const DatingLifecycleResult.done('active'),
    }) async {
      await t.pumpWidget(const SizedBox());
      final setup = FakeDatingSetupGateway(
        profile: const DatingMyProfile(dropTime: '19:00:00'),
      );
      final life = FakeDatingLifecycleGateway()..result = result;
      final home = FakeDatingHomeGateway(
        home: DatingHome(
          state: DatingHomeState.setupInProgress,
          firstDropAt: DateTime.utc(2026, 12, 1, 19),
        ),
      );
      final n = (steps: <String>[], me: <String>[]);
      await pumpFlowScreen(
        t,
        () => DatingReadyStep(nav: _nav(n), pins: pins),
        overrides: [
          ...datingShellOverrides(home: home, life: life, online: online),
          datingSetupGatewayProvider.overrideWithValue(setup),
        ],
      );
      await t.pumpAndSettle();
      return (setup, life, n);
    }

    test('the drop times: 07:00 to 22:00 in 30-minute steps', () {
      expect(datingDropTimes.length, 31);
      expect(datingDropTimes.first, '07:00');
      expect(datingDropTimes.last, '22:00');
      expect(datingDropTimes, contains('19:30'));
    });

    testWidgets('the first drop, the time picker, one item while you wait', (
      t,
    ) async {
      final (setup, _, _) = await ready(t);
      expect(find.text("You're all set"), findsOneWidget);
      expect(find.text('Step 12 of 12'), findsOneWidget);
      expect(
        find.textContaining('Your first introductions arrive '),
        findsOneWidget,
      );
      expect(find.text('Write in your journal'), findsOneWidget);
      expect(find.textContaining('app icon'), findsNothing);
      await tapInReach(t, find.text('Change time'));
      await t.pumpAndSettle();
      expect(
        find.text('Pick a time when you have a few quiet minutes.'),
        findsOneWidget,
      );
      await tapInReach(t, find.text(datingDropTimeLabel('07:30')));
      await t.pumpAndSettle();
      expect(setup.lastWrite.$2['values'], {'drop_time': '07:30'});
    });

    testWidgets(
      'shared phone: No shows nothing more; Yes offers the lock and every-open (S17)',
      (t) async {
        final pins = _store();
        await ready(t, pins: pins);
        await pins.setPin('2580');
        await tapInReach(t, find.text('No'));
        await t.pumpAndSettle();
        expect(find.text('Lock Dating with your PIN'), findsNothing);
        await tapInReach(t, find.text('Yes'));
        await t.pumpAndSettle();
        await tapInReach(
          t,
          find.widgetWithText(SwitchListTile, 'Lock Dating with your PIN'),
        );
        await t.pumpAndSettle();
        final container = ProviderScope.containerOf(
          t.element(find.byType(DatingReadyStep)),
        );
        expect(container.read(datingLockProvider).valueOrNull, isTrue);
        await tapInReach(
          t,
          find.widgetWithText(
            SwitchListTile,
            'Ask for my PIN every time Attune opens',
          ),
        );
        await t.pumpAndSettle();
        expect(await pins.everyOpen(), isTrue);
      },
    );

    testWidgets('Done activates, then Me', (t) async {
      final (_, life, n) = await ready(t);
      await tapInReach(t, find.text('Done'));
      await t.pumpAndSettle();
      expect(life.calls, ['activate']);
      expect(n.me, ['me']);
    });

    testWidgets(
      'before W4a: activation waits for the check, with a way to it (R-26)',
      (t) async {
        final (_, _, n) = await ready(
          t,
          result: const DatingLifecycleResult.refused(
            DatingLifecycleError.activationGatesNotMet,
          ),
        );
        await tapInReach(t, find.text('Done'));
        await t.pumpAndSettle();
        expect(n.me, isEmpty);
        expect(
          find.text(
            "We still need to check it's you before introductions start.",
          ),
          findsOneWidget,
        );
        await tapInReach(t, find.text("Verify it's you"));
        expect(n.steps, ['verify']);
      },
    );

    testWidgets('offline: Done is off', (t) async {
      final (_, life, _) = await ready(t, online: false);
      await tapInReach(t, find.text('Done'));
      await t.pumpAndSettle();
      expect(life.calls, isEmpty);
    });
  });

  testWidgets('guidelines: D12 and D13', (t) async {
    final semantics = t.ensureSemantics();
    await pumpFlowScreen(
      t,
      () => DatingPreviewStep(nav: _nav((steps: <String>[], me: <String>[]))),
      overrides: [
        ...datingShellOverrides(),
        datingSetupGatewayProvider.overrideWithValue(FakeDatingSetupGateway()),
        datingPreviewGatewayProvider.overrideWithValue(_Preview(_ama)),
        datingPhotosGatewayProvider.overrideWithValue(
          FakeDatingPhotosGateway(),
        ),
        pushAskerProvider.overrideWithValue(FakePushAsker()),
      ],
    );
    await t.pumpAndSettle();
    await expectFlowGuidelines(t);
    await t.pumpWidget(const SizedBox());
    await pumpFlowScreen(
      t,
      () => DatingReadyStep(nav: _nav((steps: <String>[], me: <String>[]))),
      overrides: [
        ...datingShellOverrides(),
        datingSetupGatewayProvider.overrideWithValue(FakeDatingSetupGateway()),
      ],
    );
    await t.pumpAndSettle();
    await expectFlowGuidelines(t);
    semantics.dispose();
  });

  testWidgets('d11_verify goldens', (t) async {
    await expectFlowGoldens(
      t,
      'd11_verify',
      () => DatingVerifyStep(nav: _nav((steps: <String>[], me: <String>[]))),
      overrides: datingShellOverrides(),
    );
  });

  testWidgets('d12_preview goldens', (t) async {
    await expectFlowGoldens(
      t,
      'd12_preview',
      () => DatingPreviewStep(nav: _nav((steps: <String>[], me: <String>[]))),
      overrides: [
        ...datingShellOverrides(),
        datingSetupGatewayProvider.overrideWithValue(
          FakeDatingSetupGateway(
            profile: const DatingMyProfile(displayName: 'Ama'),
          ),
        ),
        datingPreviewGatewayProvider.overrideWithValue(_Preview(_ama)),
        datingPhotosGatewayProvider.overrideWithValue(
          FakeDatingPhotosGateway(),
        ),
        pushAskerProvider.overrideWithValue(FakePushAsker()),
      ],
    );
  });

  testWidgets('d13_ready goldens', (t) async {
    await expectFlowGoldens(
      t,
      'd13_ready',
      () => DatingReadyStep(nav: _nav((steps: <String>[], me: <String>[]))),
      overrides: [
        ...datingShellOverrides(
          home: FakeDatingHomeGateway(
            home: DatingHome(
              state: DatingHomeState.setupInProgress,
              firstDropAt: DateTime.utc(2026, 12, 1, 19),
            ),
          ),
        ),
        datingSetupGatewayProvider.overrideWithValue(FakeDatingSetupGateway()),
      ],
    );
  });
}
```

Run: `flutter test test/features/dating/setup/d11_d13_test.dart 2>&1 | tail -2`
Expected: FAIL — `Target of URI doesn't exist: 'package:attune/features/dating/card/dating_card.dart'`.

- [ ] **Step 3: The card, the preview read, the lifecycle error rows**

Create `lib/features/dating/card/dating_card.dart` with exactly:

```dart
// Spec 2 §3.4: the introduction card, person first, photo after, read in
// the order it shows (§3.15 D12). D12 shows it for the person's own profile
// (R-38: no "Why you two" and no actions, which need another person); W5b's
// Today adds both through [DatingCardView.trailing]. Never the date of
// birth, the side, or who the person would like to meet.
import 'dart:typed_data';

import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_buttons.dart';
import 'package:attune/features/dating/setup/dating_list_names.dart';
import 'package:attune/features/dating/setup/prompts_step.dart'
    show datingPromptText;
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';

class DatingCard {
  const DatingCard({
    this.displayName,
    this.age,
    this.regionNameKey,
    this.intention,
    this.timeline,
    this.childrenHave,
    this.childrenWant,
    this.identity,
    this.specific,
    this.specificText,
    this.pronouns,
    this.faith,
    this.denomination,
    this.marital,
    this.prompts = const [],
    this.photosAfterMutual = false,
    this.photoIds = const [],
  });

  final String? displayName;
  final int? age;
  final String? regionNameKey;
  final String? intention;
  final String? timeline;
  final bool? childrenHave;
  final String? childrenWant;
  final String? identity;
  final String? specific;
  final String? specificText;
  final String? pronouns;
  final String? faith;
  final String? denomination;
  final String? marital;
  final List<(String, String)> prompts;
  final bool photosAfterMutual;
  final List<String> photoIds;

  factory DatingCard.fromJson(Map<String, dynamic> j) {
    String? text(Object? v) => v is String && v.isNotEmpty ? v : null;
    final gender = j['gender'] is Map ? j['gender'] as Map : const {};
    final faith = j['faith'] is Map ? j['faith'] as Map : const {};
    final photos =
        j['photos'] is List
            ? (j['photos'] as List).whereType<Map>().toList()
            : <Map>[];
    photos.sort(
      (a, b) => ((a['position'] as int?) ?? 0).compareTo(
        (b['position'] as int?) ?? 0,
      ),
    );
    return DatingCard(
      displayName: text(j['display_name']),
      age: j['age'] is int ? j['age'] as int : null,
      regionNameKey: text(j['region_name_key']),
      intention: text(j['intention']),
      timeline: text(j['marriage_timeline']),
      childrenHave:
          j['children_have'] is bool ? j['children_have'] as bool : null,
      childrenWant: text(j['children_want']),
      identity: text(gender['identity']),
      specific: text(gender['specific']),
      specificText: text(gender['specific_text']),
      pronouns: text(j['pronouns']),
      faith: text(faith['faith']),
      denomination: text(faith['denomination']),
      marital: text(j['marital']),
      prompts: [
        if (j['prompts'] is List)
          for (final p in (j['prompts'] as List).whereType<Map>())
            if (p['prompt_id'] is String && p['answer'] is String)
              (p['prompt_id'] as String, p['answer'] as String),
      ],
      photosAfterMutual: j['photos_after_mutual'] == true,
      photoIds: [
        for (final p in photos)
          if (p['id'] is String) p['id'] as String,
      ],
    );
  }
}

String? datingIntentionLine(AppLocalizations loc, DatingCard c) => switch (c
    .intention) {
  'marriage' => switch (c.timeline) {
    'within_two_years' => loc.dating_cardMarriageSoon,
    'few_years' => loc.dating_cardMarriageFew,
    'no_set_time' => loc.dating_cardMarriageNone,
    _ => loc.dating_cardMarriage,
  },
  'committed' => loc.dating_cardCommitted,
  'companionship' => loc.dating_cardCompanionship,
  'not_sure' => loc.dating_cardNotSure,
  _ => null,
};

String? _identity(AppLocalizations loc, String? v) => switch (v) {
  'woman' => loc.dating_identityWoman,
  'man' => loc.dating_identityMan,
  'non_binary' => loc.dating_identityNonBinary,
  _ => null,
};

String? _specific(AppLocalizations loc, DatingCard c) =>
    c.specificText ??
    switch (c.specific) {
      'trans_woman' => loc.dating_specificTransWoman,
      'trans_man' => loc.dating_specificTransMan,
      'genderfluid' => loc.dating_specificGenderfluid,
      'genderqueer' => loc.dating_specificGenderqueer,
      'agender' => loc.dating_specificAgender,
      'intersex' => loc.dating_specificIntersex,
      _ => null,
    };

/// The optional lines, only those the person chose to show (§3.4).
List<String> datingShownLines(AppLocalizations loc, DatingCard c) => [
  for (final s in [_identity(loc, c.identity), _specific(loc, c), c.pronouns])
    if (s != null) s,
  if (c.faith != null)
    if (datingListName(loc, 'dating_faith_${c.faith}') case final f?) f,
  if (c.denomination != null)
    if (datingListName(loc, 'dating_denomination_${c.denomination}')
        case final d?)
      d,
  if (c.marital == 'widowed') loc.dating_maritalWidowed,
  if (c.marital == 'divorced') loc.dating_maritalDivorced,
];

class DatingCardView extends StatelessWidget {
  const DatingCardView({
    super.key,
    required this.card,
    this.photos = const [],
    this.photosHidden = false,
    this.onShowPhotos,
    this.trailing,
  });

  final DatingCard card;

  /// The photos' bytes, in card order (memory only; the caller evicts).
  final List<Uint8List> photos;
  final bool photosHidden;
  final VoidCallback? onShowPhotos;

  /// A widget after a part ('heading', 'intention', 'prompts', 'children',
  /// 'shown', 'photos'): D12's edit links; W5b's reasons and actions.
  final Widget? Function(String part)? trailing;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    Widget? after(String part) => trailing?.call(part);
    final region =
        card.regionNameKey == null
            ? null
            : datingListName(loc, card.regionNameKey!);
    final intention = datingIntentionLine(loc, card);
    final heading = [
      Text(
        card.age == null
            ? (card.displayName ?? '')
            : loc.dating_cardHeading(card.displayName ?? '', card.age!),
        style: theme.textTheme.headlineSmall,
      ),
      if (region != null) Text(region, style: theme.textTheme.bodyMedium),
      if (after('heading') case final w?) w,
    ];
    final intentionPart = [
      if (intention != null) Text(intention, style: theme.textTheme.bodyLarge),
      if (after('intention') case final w?) w,
    ];
    final prompts = [
      for (final (id, answer) in card.prompts) ...[
        const SizedBox(height: Spacing.sm),
        Text(datingPromptText(loc, id), style: theme.textTheme.titleSmall),
        Text(answer, style: theme.textTheme.bodyLarge),
      ],
      if (after('prompts') case final w?) w,
    ];
    final children = [
      if (card.childrenHave != null || card.childrenWant != null)
        Text(
          [
            if (card.childrenHave == true) loc.dating_cardHasChildren,
            if (card.childrenHave == false) loc.dating_cardNoChildren,
            if (card.childrenWant == 'yes') loc.dating_cardWantsChildren,
            if (card.childrenWant == 'no') loc.dating_cardNoWantChildren,
            if (card.childrenWant == 'open') loc.dating_cardOpenChildren,
          ].join(' · '),
          style: theme.textTheme.bodyMedium,
        ),
      if (after('children') case final w?) w,
    ];
    final shown = datingShownLines(loc, card);
    final shownPart = [
      if (shown.isNotEmpty)
        Text(shown.join(' · '), style: theme.textTheme.bodyMedium),
      if (after('shown') case final w?) w,
    ];
    final photoPart = <Widget>[
      if (card.photosAfterMutual)
        Text(loc.dating_cardPhotosLater, style: theme.textTheme.bodyMedium)
      else if (photosHidden && card.photoIds.isNotEmpty)
        FlowTextLink(
          label: loc.dating_cardShowPhotos,
          alignment: AlignmentDirectional.centerStart,
          onPressed: onShowPhotos ?? () {},
        )
      else if (card.photoIds.isNotEmpty)
        SizedBox(
          height: 280,
          child: PageView(
            children: [
              for (var i = 0; i < card.photoIds.length; i++)
                Semantics(
                  image: true,
                  label: loc.dating_cardPhoto(i + 1, card.photoIds.length),
                  child:
                      i < photos.length && photos[i].isNotEmpty
                          ? Image.memory(
                            photos[i],
                            fit: BoxFit.cover,
                            gaplessPlayback: true,
                          )
                          : const ColoredBox(
                            color: Colors.black12,
                            child: Center(child: Icon(Icons.image_outlined)),
                          ),
                ),
            ],
          ),
        ),
      if (after('photos') case final w?) w,
    ];
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ...heading,
            ...intentionPart,
            ...prompts,
            ...children,
            ...shownPart,
            const SizedBox(height: Spacing.sm),
            ...photoPart,
          ],
        ),
      ),
    );
  }
}
```

(Each optional part uses an if-case element, `if (after('x') case final w?) w,`, which Dart 3.7 accepts; null-aware elements `?x` need 3.8.)

Create `lib/features/dating/setup/dating_preview_providers.dart` with exactly:

```dart
// Spec 2 W3c (§3.2 D12, D8): the person's own card, one entry per account,
// memory only.
import 'package:attune/features/dating/card/dating_card.dart';
import 'package:attune/features/dating/data/dating_providers.dart';
import 'package:attune/features/dating/data/dating_rpc.dart';
import 'package:attune/features/dating/photos/dating_photos_providers.dart';
import 'package:attune/features/dating/setup/dating_setup_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

abstract class DatingPreviewGateway {
  Future<DatingCard?> preview();
}

class DatingPreviewRepository implements DatingPreviewGateway {
  DatingPreviewRepository(this._rpc);

  final DatingRpc _rpc;

  @override
  Future<DatingCard?> preview() async {
    final raw = await _rpc.call('get_dating_profile_preview');
    if (raw is! Map || raw['ok'] != true) {
      throw StateError('preview:${raw is Map ? raw['reason'] : 'shape'}');
    }
    final card = raw['card'];
    return card is Map
        ? DatingCard.fromJson(Map<String, dynamic>.from(card))
        : null;
  }
}

final datingPreviewGatewayProvider = Provider<DatingPreviewGateway>(
  (ref) => DatingPreviewRepository(ref.watch(datingRpcProvider)),
);

final datingPreviewProvider = FutureProvider.autoDispose
    .family<DatingCard?, String?>((ref, account) async {
      if (account == null) return null;
      // A saved answer or a photo change (an edit link, R-40) reads the card
      // again; once per new value, not per loading frame.
      ref.watch(datingMyProfileProvider(account).select((v) => v.valueOrNull));
      ref.watch(datingPhotosProvider(account).select((v) => v.valueOrNull));
      return ref.read(datingPreviewGatewayProvider).preview();
    });
```

Create `lib/features/dating/section/dating_lifecycle_errors.dart` with exactly:

```dart
// Spec 2 W3c (carries 1, 13): a lifecycle refusal in words, for D13 and
// Dating settings (the section keeps its own copy from Task 4). Calm for
// busy, reverify and the pre-W4a gate; error red with an icon otherwise.
import 'package:attune/app/routing/app_router.dart' show RouteNames;
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_buttons.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_text_field.dart'
    show FlowErrorLine;
import 'package:attune/features/dating/data/dating_rpc.dart';
import 'package:attune/features/dating/routes/dating_routes.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class DatingCalmLine extends StatelessWidget {
  const DatingCalmLine(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
    ),
  );
}

List<Widget> datingLifecycleErrorRows(
  BuildContext context,
  AppLocalizations loc,
  DatingLifecycleError error, {
  VoidCallback? onVerify,
}) {
  Widget link(String label, VoidCallback onPressed) => FlowTextLink(
    label: label,
    alignment: AlignmentDirectional.centerStart,
    onPressed: onPressed,
  );
  return switch (error) {
    DatingLifecycleError.activationGatesNotMet => [
      DatingCalmLine(loc.dating_readyGates),
      if (onVerify != null) link(loc.dating_verifyTitle, onVerify),
    ],
    DatingLifecycleError.pathNotDating => [
      FlowErrorLine(text: loc.dating_errorPathNotDating, liveRegion: true),
      link(
        loc.dating_openHowYouUse,
        () => context.push(RouteNames.howYouUseAttune),
      ),
    ],
    DatingLifecycleError.consentRequired => [
      FlowErrorLine(text: loc.dating_errorConsent, liveRegion: true),
      link(
        loc.dating_sectionFinish,
        () => context.push(DatingPaths.step('privacy')),
      ),
    ],
    DatingLifecycleError.profileIncomplete ||
    DatingLifecycleError.activationRequired ||
    DatingLifecycleError.enrollmentIncomplete => [
      FlowErrorLine(text: loc.dating_errorIncomplete, liveRegion: true),
      link(
        loc.dating_sectionFinish,
        () => context.push(DatingPaths.step('how')),
      ),
    ],
    DatingLifecycleError.resumeGatesNotMet ||
    DatingLifecycleError.notEligible => [
      FlowErrorLine(text: loc.dating_errorResumeGates, liveRegion: true),
    ],
    DatingLifecycleError.reverifyDevice => [
      DatingCalmLine(loc.dating_sectionReverify),
    ],
    DatingLifecycleError.busy => [DatingCalmLine(loc.dating_busy)],
    DatingLifecycleError.rateLimited => [
      FlowErrorLine(text: loc.dating_errorRateLimited, liveRegion: true),
    ],
    _ => [FlowErrorLine(text: loc.dating_errorGeneric, liveRegion: true)],
  };
}
```

- [ ] **Step 4: D11, D12, D13**

Create `lib/features/dating/setup/verify_step.dart` with exactly:

```dart
// Spec 2 §3.2 D11 (Step 10 of 12): the shell until W4a builds §3.3's flow
// (R-26). The intro copy is §3.3.2's; Continue opens D12.
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_buttons.dart';
import 'package:attune/features/dating/routes/dating_setup_steps.dart';
import 'package:attune/features/dating/setup/dating_step_frame.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';

class DatingVerifyStep extends StatelessWidget {
  const DatingVerifyStep({super.key, required this.nav});

  final DatingStepNav nav;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return DatingStepFrame(
      step: 'verify',
      title: loc.dating_verifyTitle,
      onBack: nav.back,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(loc.dating_verifyBody, style: theme.textTheme.bodyLarge),
          const SizedBox(height: Spacing.md),
          Text(loc.dating_verifyLater, style: theme.textTheme.bodyMedium),
        ],
      ),
      primary: FlowPrimaryButton(
        label: loc.dating_continue,
        onPressed: () => nav.next('preview'),
      ),
    );
  }
}
```

Create `lib/features/dating/setup/preview_step.dart` with exactly:

```dart
// Spec 2 §3.2 D12 (Step 11 of 12): the person's own card from
// get_dating_profile_preview(), the "Never shown" line, edit links per part
// (R-40), the first-name editor, and the notification ask in context (R-27:
// the OS prompt, no metric). Photos are the person's own bytes, in memory,
// evicted when the step goes; with data saver on they wait for a tap.
import 'dart:typed_data';

import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/notifications/services/onesignal_service.dart';
import 'package:attune/core/notifications/services/push_permission_policy.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_buttons.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_text_field.dart'
    show FlowErrorLine;
import 'package:attune/features/dating/card/dating_card.dart';
import 'package:attune/features/dating/data/dating_providers.dart';
import 'package:attune/features/dating/gentle_wait/gentle_wait_providers.dart'
    show datingOnlineProvider;
import 'package:attune/features/dating/photos/dating_photos_providers.dart';
import 'package:attune/features/dating/routes/dating_setup_steps.dart';
import 'package:attune/features/dating/setup/dating_preview_providers.dart';
import 'package:attune/features/dating/setup/dating_setup_models.dart';
import 'package:attune/features/dating/setup/dating_setup_providers.dart';
import 'package:attune/features/dating/setup/dating_step_frame.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class DatingPreviewStep extends ConsumerStatefulWidget {
  const DatingPreviewStep({super.key, required this.nav});

  final DatingStepNav nav;

  @override
  ConsumerState<DatingPreviewStep> createState() => _DatingPreviewStepState();
}

class _DatingPreviewStepState extends ConsumerState<DatingPreviewStep>
    with DatingStepState<DatingPreviewStep> {
  final _name = TextEditingController();
  final _bytes = <String, Uint8List>{};
  bool _editingName = false;
  bool _nameInvalid = false;
  bool _showPhotos = false;
  late bool _granted;

  @override
  void initState() {
    super.initState();
    _granted = ref.read(pushAskerProvider).permissionGranted;
  }

  @override
  void resetAnswers() {
    _name.clear();
    _editingName = false;
    _nameInvalid = false;
    _showPhotos = false;
    _evict();
  }

  @override
  void seedAnswers(DatingMyProfile p) => _name.text = p.displayName ?? '';

  void _evict() {
    for (final b in _bytes.values) {
      PaintingBinding.instance.imageCache.evict(MemoryImage(b));
    }
    _bytes.clear();
  }

  @override
  void dispose() {
    _name.dispose();
    _evict();
    super.dispose();
  }

  void _edit(String step) => widget.nav.next('$step?from=preview');

  void _saveName() {
    final name = _name.text.trim();
    final n = name.runes.length;
    if (n < 1 || n > 30) {
      setState(() => _nameInvalid = true);
      return;
    }
    setState(() => _nameInvalid = false);
    write(
      'd12name',
      name,
      (key) => ref.read(datingSetupGatewayProvider).saveDisplayName(key, name),
      (_) {
        setState(() => _editingName = false);
        ref.invalidate(datingPreviewProvider(ref.read(datingAccountProvider)));
      },
    );
  }

  Future<void> _turnOn() async {
    final outcome = await ref
        .read(pushAskerProvider)
        .askInContext(PushAskContext.j3);
    if (!mounted) return;
    setState(() => _granted = outcome == PushAskOutcome.granted);
    if (!_granted) return;
    await write(
      'd12digest',
      true,
      (key) => ref.read(datingSetupGatewayProvider).saveSettings(key, {
        'digest_push': true,
      }),
      (_) {},
    );
  }

  void _messages(bool on) => write(
    'd12chat',
    on,
    (key) => ref.read(datingSetupGatewayProvider).saveSettings(key, {
      'chat_push': on,
    }),
    (_) {},
  );

  void _loadPhotos(DatingCard card) {
    final account = ref.read(datingAccountProvider);
    final list = ref.read(datingPhotosProvider(account)).valueOrNull;
    if (list == null) return;
    final gateway = ref.read(datingPhotosGatewayProvider);
    for (final id in card.photoIds) {
      if (_bytes.containsKey(id)) continue;
      final match = list.photos.where((p) => p.id == id);
      if (match.isEmpty) continue;
      _bytes[id] = Uint8List(0);
      gateway.bytes(match.first.storageKey).then((b) {
        if (mounted &&
            b != null &&
            b.isNotEmpty &&
            ref.read(datingAccountProvider) == account) {
          setState(() => _bytes[id] = b);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final profile = watchProfile();
    final account = ref.watch(datingAccountProvider);
    final online = ref.watch(datingOnlineProvider).valueOrNull ?? true;
    final read = ref.watch(datingPreviewProvider(account));
    ref.watch(datingPhotosProvider(account));
    final card = read.valueOrNull;
    final dataSaver = profile?.dataSaver ?? false;
    final hidden = dataSaver && !_showPhotos;
    if (card != null && !hidden && !card.photosAfterMutual) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _loadPhotos(card);
      });
    }
    Widget? edit(String part) {
      final (label, step) = switch (part) {
        'heading' => (loc.dating_editWhere, 'where'),
        'intention' => (loc.dating_editLooking, 'looking-for'),
        'prompts' => (loc.dating_editPrompts, 'prompts'),
        'children' => (loc.dating_editChildren, 'children'),
        'shown' => (loc.dating_editAbout, 'you'),
        'photos' => (loc.dating_editPhotos, 'photos'),
        _ => ('', ''),
      };
      if (step.isEmpty) return null;
      return FlowTextLink(
        label: label,
        alignment: AlignmentDirectional.centerStart,
        onPressed: () => _edit(step),
      );
    }

    return DatingStepFrame(
      step: 'preview',
      title: loc.dating_previewTitle,
      onBack: widget.nav.back,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (read.hasError) ...[
            FlowErrorLine(
              text: loc.dating_previewUnavailable,
              liveRegion: true,
            ),
            FlowTextLink(
              label: loc.dating_tryAgain,
              alignment: AlignmentDirectional.centerStart,
              onPressed: () => ref.invalidate(datingPreviewProvider(account)),
            ),
          ] else if (card != null)
            DatingCardView(
              card: card,
              photos: [
                for (final id in card.photoIds) _bytes[id] ?? Uint8List(0),
              ],
              photosHidden: hidden,
              onShowPhotos: () => setState(() => _showPhotos = true),
              trailing: edit,
            )
          else if (read.isLoading)
            const Center(child: CircularProgressIndicator.adaptive()),
          const SizedBox(height: Spacing.md),
          Text(loc.dating_previewNever, style: theme.textTheme.bodyMedium),
          const SizedBox(height: Spacing.md),
          if (!_editingName)
            FlowTextLink(
              label: loc.dating_editName,
              alignment: AlignmentDirectional.centerStart,
              onPressed: () => setState(() => _editingName = true),
            )
          else ...[
            TextField(
              key: const ValueKey('dating_name_field'),
              controller: _name,
              maxLength: 30,
              decoration: InputDecoration(
                labelText: loc.dating_nameLabel,
                helperText: loc.dating_nameHelper,
                helperMaxLines: 3,
              ),
            ),
            if (_nameInvalid)
              FlowErrorLine(text: loc.dating_nameInvalid, liveRegion: true),
            FlowSecondaryButton(
              label: loc.dating_save,
              onPressed: online && !saving ? _saveName : null,
            ),
          ],
          if (refusal != null) datingRefusalLine(loc, refusal!),
          const SizedBox(height: Spacing.md),
          if (profile?.digestPush ?? false)
            Text(loc.dating_pushDigestOn, style: theme.textTheme.bodyMedium)
          else ...[
            Text(loc.dating_pushDigest, style: theme.textTheme.bodyMedium),
            FlowTextLink(
              label: loc.dating_pushTurnOn,
              alignment: AlignmentDirectional.centerStart,
              onPressed: online ? _turnOn : () {},
            ),
          ],
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(loc.dating_pushMessages),
            value: _granted && (profile?.chatPush ?? true),
            onChanged: _granted && online ? _messages : null,
          ),
        ],
      ),
      primary: FlowPrimaryButton(
        label: loc.dating_continue,
        onPressed: () => widget.nav.next('ready'),
      ),
    );
  }
}
```

Create `lib/features/dating/setup/ready_step.dart` with exactly:

```dart
// Spec 2 §3.2 D13 (Step 12 of 12): the first drop and its time (07:00-22:00,
// 30-minute steps, a labelled list), one item while you wait (R-39), the
// shared-phone question (S17: Spec 1's Dating lock, the PIN set up first;
// the existing every-open PIN), and Done -> activate_dating_profile, then Me.
// The plain-icon offer stays hidden until W8b (A-11). No motion (§3.15).
import 'package:attune/app/routing/app_router.dart' show RouteNames;
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/utils/date_formatter.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_buttons.dart';
import 'package:attune/features/dating/data/dating_providers.dart';
import 'package:attune/features/dating/data/dating_rpc.dart';
import 'package:attune/features/dating/gentle_wait/gentle_wait_providers.dart'
    show datingOnlineProvider;
import 'package:attune/features/dating/routes/dating_setup_steps.dart';
import 'package:attune/features/dating/section/dating_lifecycle_errors.dart';
import 'package:attune/features/dating/setup/dating_picker_sheet.dart';
import 'package:attune/features/dating/setup/dating_setup_models.dart';
import 'package:attune/features/dating/setup/dating_setup_providers.dart';
import 'package:attune/features/dating/setup/dating_step_frame.dart';
import 'package:attune/features/me/presentation/widgets/dating_lock_setting.dart'
    show setDatingLock;
import 'package:attune/features/safety/data/dating_lock_store.dart';
import 'package:attune/features/safety/data/safety_pin_store.dart';
import 'package:attune/features/safety/presentation/widgets/confirm_safety_pin.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// §3.2 D13: 07:00 to 22:00 in 30-minute steps.
final datingDropTimes = [
  for (var m = 7 * 60; m <= 22 * 60; m += 30)
    '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}',
];

/// '19:30' (or the server's '19:30:00') in the person's clock format.
String datingDropTimeLabel(String hhmm) {
  final parts = hhmm.split(':');
  return MyDateFormat.toTime(
    DateTime(2000, 1, 1, int.parse(parts[0]), int.parse(parts[1])),
  );
}

String datingDropTimeOf(DatingMyProfile? p) {
  final t = p?.dropTime;
  return t != null &&
          t.length >= 5 &&
          datingDropTimes.contains(t.substring(0, 5))
      ? t.substring(0, 5)
      : '19:00';
}

Future<String?> pickDatingDropTime(BuildContext context, String current) {
  final loc = AppLocalizations.of(context)!;
  return showDatingPicker<String>(
    context,
    title: loc.dating_readyTimeTitle,
    items: [for (final t in datingDropTimes) (t, datingDropTimeLabel(t))],
    selected: current,
  );
}

class DatingReadyStep extends ConsumerStatefulWidget {
  const DatingReadyStep({super.key, required this.nav, this.pins});

  final DatingStepNav nav;
  final SafetyPinStore? pins;

  @override
  ConsumerState<DatingReadyStep> createState() => _DatingReadyStepState();
}

class _DatingReadyStepState extends ConsumerState<DatingReadyStep>
    with DatingStepState<DatingReadyStep> {
  bool? _shared;
  bool _everyOpen = false;
  bool _activating = false;
  DatingLifecycleError? _error;

  SafetyPinStore get _pins => widget.pins ?? SafetyPinStore.instance;

  @override
  void initState() {
    super.initState();
    _pins
        .everyOpen()
        .then((on) {
          if (mounted) setState(() => _everyOpen = on);
        })
        .catchError((Object _) {});
  }

  @override
  void resetAnswers() {
    _shared = null;
    _activating = false;
    _error = null;
  }

  @override
  void seedAnswers(DatingMyProfile profile) {}

  Future<void> _changeTime(String current) async {
    final picked = await pickDatingDropTime(context, current);
    if (picked == null || picked == current || !mounted) return;
    await write(
      'd13time',
      picked,
      (key) => ref.read(datingSetupGatewayProvider).saveSettings(key, {
        'drop_time': picked,
      }),
      (_) {
        ref.invalidate(datingHomeProvider(ref.read(datingAccountProvider)));
      },
    );
  }

  Future<void> _setEveryOpen(bool on) async {
    if (on) {
      if (!await _pins.hasPin()) {
        if (!mounted) return;
        await context.push(RouteNames.safetyPin);
        if (!await _pins.hasPin()) return;
      }
    } else {
      if (!mounted) return;
      if (!await confirmSafetyPin(context, store: _pins)) return;
    }
    await _pins.setEveryOpen(on);
    if (mounted) setState(() => _everyOpen = on);
  }

  Future<void> _done() async {
    if (_activating) return;
    final account = ref.read(datingAccountProvider);
    setState(() {
      _activating = true;
      _error = null;
    });
    final r = await ref
        .read(datingLifecycleGatewayProvider)
        .activate(keys.keyFor('activate', account ?? ''));
    if (!mounted || ref.read(datingAccountProvider) != account) return;
    setState(() {
      _activating = false;
      _error = r.error;
    });
    if (r.ok) {
      ref.invalidate(datingHomeProvider(account));
      widget.nav.toMe();
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final profile = watchProfile();
    final account = ref.watch(datingAccountProvider);
    final online = ref.watch(datingOnlineProvider).valueOrNull ?? true;
    final drop =
        ref
            .watch(datingHomeProvider(account))
            .valueOrNull
            ?.firstDropAt
            ?.toLocal();
    final lock = ref.watch(datingLockProvider).valueOrNull ?? false;
    final current = datingDropTimeOf(profile);
    return DatingStepFrame(
      step: 'ready',
      title: loc.dating_readyTitle,
      onBack: widget.nav.back,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (drop != null)
            Text(
              loc.dating_readyFirst(
                MyDateFormat.toDate(drop),
                MyDateFormat.toTime(drop),
              ),
              style: theme.textTheme.bodyLarge,
            ),
          FlowTextLink(
            label: loc.dating_readyChangeTime,
            alignment: AlignmentDirectional.centerStart,
            onPressed: online && !saving ? () => _changeTime(current) : () {},
          ),
          if (refusal != null) datingRefusalLine(loc, refusal!),
          const SizedBox(height: Spacing.md),
          Text(loc.dating_readyWhile, style: theme.textTheme.titleSmall),
          FlowTextLink(
            label: loc.dating_readyJournal,
            alignment: AlignmentDirectional.centerStart,
            onPressed: () => context.push(RouteNames.reflectionJournal),
          ),
          const SizedBox(height: Spacing.md),
          DatingChoiceGroup<bool>(
            label: loc.dating_readySharedQ,
            options: [(true, loc.dating_yes), (false, loc.dating_no)],
            value: _shared,
            onChanged: (v) => setState(() => _shared = v),
          ),
          if (_shared == true) ...[
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(loc.dating_readyLock),
              value: lock,
              onChanged:
                  (on) => setDatingLock(context, ref, on, pins: widget.pins),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(loc.dating_readyEveryOpen),
              value: _everyOpen,
              onChanged: _setEveryOpen,
            ),
          ],
          // A-11: "Some people like their apps to look plain." arrives with
          // Settings -> App icon in W8b.
          if (_error != null)
            ...datingLifecycleErrorRows(
              context,
              loc,
              _error!,
              onVerify: () => widget.nav.next('verify'),
            ),
        ],
      ),
      primary: FlowPrimaryButton(
        label: loc.dating_done,
        busy: _activating,
        onPressed: online ? _done : null,
      ),
    );
  }
}
```

- [ ] **Step 5: The steps, `from` (R-40), format, run**

Create `$D/edit_T11.py` with exactly:

```python
import sys
sys.path.insert(0, '.superpowers/sdd/2026-11-07-spec2-w3')
from anchor import edit
F = 'lib/features/dating/routes/dating_setup_steps.dart'
edit(F, [
    ("import 'package:attune/features/dating/setup/prompts_step.dart';\n",
     "import 'package:attune/features/dating/setup/preview_step.dart';\n"
     "import 'package:attune/features/dating/setup/prompts_step.dart';\n"
     "import 'package:attune/features/dating/setup/ready_step.dart';\n"
     "import 'package:attune/features/dating/setup/verify_step.dart';\n"),
    ("  'prompts' => DatingPromptsStep(nav: nav),\n",
     "  'prompts' => DatingPromptsStep(nav: nav),\n"
     "  'verify' => DatingVerifyStep(nav: nav),\n"
     "  'preview' => DatingPreviewStep(nav: nav),\n"
     "  'ready' => DatingReadyStep(nav: nav),\n"),
    # R-40: a step opened with ?from=preview|settings goes back there when it
    # saves, instead of walking forward.
    ("  const DatingSetupStepRoute({super.key, required this.step});\n\n  final String step;\n",
     "  const DatingSetupStepRoute({super.key, required this.step, this.from});\n\n"
     "  final String step;\n\n"
     "  /// 'preview' or 'settings' (R-40): Continue returns there.\n"
     "  final String? from;\n"),
    ("      next:\n          (next) =>\n              next == 'done' ? toMe() : context.push(DatingPaths.step(next)),\n",
     "      next: (next) {\n"
     "        if (next == 'done') return toMe();\n"
     "        if ((from == 'preview' || from == 'settings') && !next.contains('?') && context.canPop()) {\n"
     "          return context.pop();\n"
     "        }\n"
     "        final at = next.indexOf('?');\n"
     "        context.push(at < 0 ? DatingPaths.step(next) : '${DatingPaths.step(next.substring(0, at))}${next.substring(at)}');\n"
     "      },\n"),
], 'T11 steps')
edit('lib/features/dating/routes/dating_routes.dart', [
    ("    (s) => DatingSetupStepRoute(step: s.pathParameters['step'] ?? ''),\n",
     "    (s) => DatingSetupStepRoute(\n"
     "      step: s.pathParameters['step'] ?? '',\n"
     "      from: s.uri.queryParameters['from'],\n"
     "    ),\n"),
], 'T11 from')
```

Create `$D/routes_test_T11.dart` (the R-40 case, inserted before the routes test's final `}` by the script below) with exactly:

```dart
  // Spec 2 W3c (R-40): a step opened with ?from= goes back when it moves
  // on; without it, it walks forward. (A push doesn't change
  // currentConfiguration.uri in go_router 10, so the screen shown is read.)
  testWidgets('from=preview: Continue goes back instead of forward', (t) async {
    final shell = await pumpDatingShell(
      t,
      overrides: [
        datingPreviewGatewayProvider.overrideWithValue(
          FakeDatingPreviewGateway(),
        ),
        datingSetupGatewayProvider.overrideWithValue(FakeDatingSetupGateway()),
        datingPhotosGatewayProvider.overrideWithValue(FakeDatingPhotosGateway()),
        pushAskerProvider.overrideWithValue(FakePushAsker()),
      ],
    );
    shell.router.push('${DatingPaths.step('verify')}?from=preview');
    await t.pumpAndSettle();
    expect(find.text("Verify it's you"), findsOneWidget);
    await tapInReach(t, find.text('Continue'));
    await t.pumpAndSettle();
    expect(find.text("Verify it's you"), findsNothing);
    expect(find.text('This is what others see'), findsNothing);
    expect(find.textContaining('ME '), findsOneWidget);
    shell.router.push(DatingPaths.step('verify'));
    await t.pumpAndSettle();
    await tapInReach(t, find.text('Continue'));
    await t.pumpAndSettle();
    expect(find.text('This is what others see'), findsOneWidget);
  });
```

Create `$D/preview_fake_T11.dart` (appended to `dating_photos_fakes.dart` by the script below) with exactly:

```dart

/// D12's read with no profile yet (an empty preview).
class FakeDatingPreviewGateway implements DatingPreviewGateway {
  FakeDatingPreviewGateway([this.card]);
  DatingCard? card;
  @override
  Future<DatingCard?> preview() async => card;
}
```

Create `$D/edit_T11_tests.py` with exactly:

```python
# Spec 2 W3c Task 11 Step 5: the routes test's R-40 case (and its imports)
# and the preview fake (and its imports), from the two snippets above.
import pathlib, sys
sys.path.insert(0, '.superpowers/sdd/2026-11-07-spec2-w3')
from anchor import edit
D = pathlib.Path('.superpowers/sdd/2026-11-07-spec2-w3')


def before_final_brace(path, snippet, label):
    p = pathlib.Path(path)
    s = p.read_text()
    assert s.endswith('}\n'), f'{label}: {path} does not end with }}'
    p.write_text(s[:-2] + snippet.rstrip('\n') + '\n}\n')
    print(f'{path}: 1 insert ({label})')


F = 'test/features/dating/support/dating_photos_fakes.dart'
edit(F, [
    ("import 'package:attune/features/dating/data/dating_rpc.dart';\n",
     "import 'package:attune/features/dating/card/dating_card.dart';\n"
     "import 'package:attune/features/dating/data/dating_rpc.dart';\n"),
    ("import 'package:attune/features/dating/photos/dating_photos_repository.dart';\n",
     "import 'package:attune/features/dating/photos/dating_photos_repository.dart';\n"
     "import 'package:attune/features/dating/setup/dating_preview_providers.dart';\n"),
], 'T11 preview fake imports')
pathlib.Path(F).write_text(pathlib.Path(F).read_text() + '\n' + (D / 'preview_fake_T11.dart').read_text())
print(f'{F}: FakeDatingPreviewGateway added (T11)')

R = 'test/features/dating/routes/dating_routes_test.dart'
edit(R, [
    ("import 'package:attune/core/device/device_wipe_registry.dart';\n",
     "import 'package:attune/core/device/device_wipe_registry.dart';\n"
     "import 'package:attune/core/notifications/services/onesignal_service.dart';\n"),
    ("import 'package:attune/features/dating/lock/dating_unlock.dart';\n",
     "import 'package:attune/features/dating/lock/dating_unlock.dart';\n"
     "import 'package:attune/features/dating/photos/dating_photos_providers.dart';\n"),
    ("import 'package:attune/features/dating/routes/dating_setup_steps.dart';\n",
     "import 'package:attune/features/dating/routes/dating_setup_steps.dart';\n"
     "import 'package:attune/features/dating/setup/dating_preview_providers.dart';\n"
     "import 'package:attune/features/dating/setup/dating_setup_providers.dart';\n"),
    ("import '../../../helpers/flow_harness.dart';\n",
     "import '../../../helpers/fake_push_asker.dart';\n"
     "import '../../../helpers/flow_harness.dart';\n"),
    ("import '../support/dating_fakes.dart';\n",
     "import '../support/dating_fakes.dart';\n"
     "import '../support/dating_photos_fakes.dart';\n"
     "import '../support/dating_setup_fakes.dart';\n"),
], 'T11 routes test imports')
before_final_brace(R, (D / 'routes_test_T11.dart').read_text(), 'T11 R-40 routes test')
```

```bash
D=.superpowers/sdd/2026-11-07-spec2-w3
python3 -I $D/edit_T11.py
python3 -I $D/edit_T11_tests.py
dart format lib/features/dating/card lib/features/dating/setup/dating_preview_providers.dart lib/features/dating/section/dating_lifecycle_errors.dart lib/features/dating/setup/verify_step.dart lib/features/dating/setup/preview_step.dart lib/features/dating/setup/ready_step.dart test/features/dating/setup/d11_d13_test.dart
flutter analyze --no-pub lib/features/dating test/features/dating 2>&1 | tail -1
flutter test --update-goldens test/features/dating/setup/d11_d13_test.dart 2>&1 | tail -1
flutter test test/features/dating 2>&1 | tail -1
python3 scripts/large_text_audit.py --scale 2.0 test/features/dating/setup 2>&1 | tail -1
```

Expected (verified, fix round 1): the edit lines (`T11 steps`, `T11 from`, `T11 preview fake imports`, `FakeDatingPreviewGateway added`, `T11 routes test imports`, `1 insert (T11 R-40 routes test)`); `Formatted …` (only the files this task created: an edited file is never formatted, so later anchors stay exact, I-10); `No issues found!`; goldens `d11_verify`, `d12_preview`, `d13_ready` (×4) — open the 2.0 ones: the card wraps, every edit link and both switches reachable, the time line wraps; `All tests passed!`; `SCALE 2.0: 0 site(s) to fix, 0 listed apart`.

- [ ] **Step 6: Mutants**

Create `$D/mut_T11.py` with exactly:

```python
S = 'lib/features/dating/'
T = ['test/features/dating/setup/d11_d13_test.dart']
R = ['test/features/dating/routes/dating_routes_test.dart']
MUTS = {
  'verify_skips_preview': (S + 'setup/verify_step.dart', "onPressed: () => nav.next('preview')", "onPressed: () => nav.next('ready')", T),
  'card_order': (S + 'card/dating_card.dart', "            ...prompts,\n            ...children,\n", "            ...children,\n            ...prompts,\n", T),
  'photos_after_ignored': (S + 'card/dating_card.dart', "      if (card.photosAfterMutual)\n", "      if (false)\n", T),
  'saver_ignored': (S + 'setup/preview_step.dart', "    final hidden = dataSaver && !_showPhotos;", "    final hidden = false;", T),
  'name_unbounded': (S + 'setup/preview_step.dart', "    if (n < 1 || n > 30) {", "    if (false) {", T),
  'digest_without_grant': (S + 'setup/preview_step.dart', "    if (!_granted) return;\n", "", T),
  'chat_before_grant': (S + 'setup/preview_step.dart', "            onChanged: _granted && online ? _messages : null,", "            onChanged: online ? _messages : null,", T),
  'edit_no_return': (S + 'setup/preview_step.dart', "  void _edit(String step) => widget.nav.next('$step?from=preview');", "  void _edit(String step) => widget.nav.next(step);", T),
  'times_short': (S + 'setup/ready_step.dart', "  for (var m = 7 * 60; m <= 22 * 60; m += 30)", "  for (var m = 7 * 60; m < 22 * 60; m += 30)", T),
  'shared_no_shows_lock': (S + 'setup/ready_step.dart', "          if (_shared == true) ...[", "          if (_shared != null) ...[", T),
  'every_open_not_saved': (S + 'setup/ready_step.dart', "    await _pins.setEveryOpen(on);\n", "", T),
  'done_stays': (S + 'setup/ready_step.dart', "      widget.nav.toMe();\n", "", T),
  'gates_generic': (S + 'section/dating_lifecycle_errors.dart', "    DatingLifecycleError.activationGatesNotMet => [\n      DatingCalmLine(loc.dating_readyGates),\n      if (onVerify != null) link(loc.dating_verifyTitle, onVerify),\n    ],\n", "", T),
  'done_offline': (S + 'setup/ready_step.dart', "onPressed: online ? _done : null", "onPressed: _done", T),
  'from_ignored': (S + 'routes/dating_setup_steps.dart', "        if ((from == 'preview' || from == 'settings') && !next.contains('?') && context.canPop()) {", "        if (false) {", R),
}
```

```bash
python3 -I $D/dmut.py $D/mut_T11.py | tee $D/mut_T11.txt | tail -1
```

Expected: `15/15 killed`.

- [ ] **Step 7: Do not commit; record the tree in the report.**


### Task 12: Dating settings (§3.12), Leave (§3.8), the manual topic and its flags; the W3c and W3 gates (§3.8, §3.12, §3.14, §3.15, §4.10 docs/registry; carries 1, 12, 13; R-35, R-40, R-41)

**Files:**
- Create: `lib/features/dating/settings/dating_leave_screen.dart`, `test/features/dating/settings/dating_settings_rows_test.dart`, `test/features/dating/settings/dating_leave_screen_test.dart` (+ goldens), `$D/{arb_fragment_T12.txt, edit_T12.py, edit_T12_docs.py, mut_T12.py}`
- Modify: `lib/features/dating/settings/dating_settings_screen.dart` (rows at Task 4's marker; Pause/Resume and Leave after the last row), `lib/features/dating/routes/dating_routes.dart` (the `leave` route), `test/architecture/text_scale_routes_test.dart` (one name; `lib/app/text_scale_policy.dart` needs nothing, its `/dating/` prefix covers the route), `lib/app/documentations/user_manual/data/dating_mode_docs.dart` (rewritten whole), `lib/app/documentations/user_manual/data/manual_documentation_registry.dart` (one map entry, one import), `lib/app/documentations/user_manual/data/documentation_flags.dart` (R-35), `test/app/documentations/documentation_registry_flags_test.dart`, `test/app/documentations/manual_content_guard_test.dart` (one gated id), `test/features/dating/routes/dating_routes_test.dart` (one test), `lib/i10n/app_en.arb` + generated

**Interfaces:**
- Consumes: Task 11's `pickDatingDropTime`, `datingDropTimeLabel`, `datingDropTimeOf`, `datingLifecycleErrorRows`, `DatingCalmLine`, R-40's `?from=settings`; Task 10's `datingPhotosProvider`/`photosAfterMutual`; Task 5's `saveSettings`; Task 1's lifecycle gateway (`pause`, `resume`, `exit(keepNeverIntroduce:)`, `DatingLifecycleResult.state` = `'suspended'` on a restricted exit); `pushAskerProvider`.
- Produces: `DatingLeaveScreen()` at `/dating/leave` (route name `datingLeave`); the manual topic `datingMode` gated on `flow_signin_v2`, `flow_paths_v2`, `dating_mode_enabled`.

Ruling: R-41 (pre-flight list).

- [ ] **Step 1: The strings**

Create `$D/arb_fragment_T12.txt` with exactly:

```
  "dating_settingsTime": "Introduction time",
  "@dating_settingsTime": {"description": "Spec 2 §3.12 row."},
  "dating_settingsWho": "Who I'd like to meet",
  "dating_settingsAges": "Ages",
  "dating_settingsAgesValue": "{min} to {max}",
  "@dating_settingsAgesValue": {"description": "§3.12 Ages row value (plan).", "placeholders": {"min": {"type": "int"}, "max": {"type": "int"}}},
  "dating_settingsHowFar": "How far",
  "dating_settingsPhotosAfter": "Photos after mutual interest",
  "dating_settingsDataSaver": "Data saver",
  "dating_settingsDataSaverSub": "Show photos only when I tap",
  "dating_settingsNotifications": "Notifications",
  "dating_settingsPause": "Pause Dating",
  "dating_pausedLine": "Dating is paused. Nobody new sees you, and your conversations stay open.",
  "@dating_pausedLine": {"description": "§3.8 Pause."},
  "dating_settingsResume": "Resume Dating",
  "dating_settingsLeave": "Leave Dating and delete my data",

  "dating_leaveTitle": "Leave Dating?",
  "@dating_leaveTitle": {"description": "Spec 2 §3.8 Leave."},
  "dating_leaveNow": "Deleted now: your Dating profile, photos, prompts, who you'd like to meet, your gender and faith answers, your settings and your private notes.",
  "dating_leave30": "Kept for 30 days, then deleted: your conversations, so either of you can still report a problem.",
  "dating_leaveSafety": "Kept for safety, for up to 2 years, only if your account is restricted or you've blocked someone: a code made from your phone number, never the number itself.",
  "dating_leaveRecord": "Kept as a record: when you agreed to Dating's terms and when you left.",
  "dating_leaveKeepList": "Keep my 'Never introduce me' list in case I come back. It holds codes, not numbers.",
  "dating_leaveConfirm": "Leave and delete",
  "dating_leavePause": "Pause instead",
  "dating_leftDone": "You've left Dating. You can set it up again any time.",
  "dating_leftSuspended": "You've left Dating.",
  "@dating_leftSuspended": {"description": "§3.8 Done when exit answers suspended (carry 13; plan: no 'set it up again')."}
```

```bash
D=.superpowers/sdd/2026-11-07-spec2-w3
python3 -I .superpowers/sdd/2026-10-26-spec1-w3/arb_append.py $D/arb_fragment_T12.txt
flutter gen-l10n --arb-dir=lib/i10n --template-arb-file=app_en.arb --output-dir=lib/i10n/generated --output-localization-file=app_localizations.dart --no-synthetic-package
```

Expected: `added 23 keys`. (The notification rows reuse D12's `dating_pushDigest` and `dating_pushMessages`.)

- [ ] **Step 2: Write the failing tests**

Create `test/features/dating/settings/dating_settings_rows_test.dart` with exactly:

```dart
// Spec 2 W3c (§3.12, §3.8 pause; carries 1, 13; R-40, R-41): the rows.
import 'package:attune/core/notifications/services/onesignal_service.dart';
import 'package:attune/features/dating/data/dating_home.dart';
import 'package:attune/features/dating/data/dating_lifecycle_repository.dart';
import 'package:attune/features/dating/data/dating_rpc.dart';
import 'package:attune/features/dating/photos/dating_photos_providers.dart';
import 'package:attune/features/dating/settings/dating_settings_screen.dart';
import 'package:attune/features/dating/setup/dating_setup_models.dart';
import 'package:attune/features/dating/setup/dating_setup_providers.dart';
import 'package:attune/features/dating/setup/ready_step.dart'
    show datingDropTimeLabel;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/fake_push_asker.dart';
import '../../../helpers/flow_harness.dart';
import '../../../helpers/tap_in_reach.dart';
import '../support/dating_fakes.dart';
import '../support/dating_photos_fakes.dart';
import '../support/dating_setup_fakes.dart';
import '../support/dating_shell.dart';

Future<
  (
    FakeDatingSetupGateway,
    FakeDatingLifecycleGateway,
    FakeDatingPhotosGateway,
    FakePushAsker,
  )
>
_pump(
  WidgetTester t, {
  DatingHomeState state = DatingHomeState.active,
  bool hasData = false,
  DatingMyProfile profile = const DatingMyProfile(
    dropTime: '19:00:00',
    minAge: 25,
    maxAge: 35,
  ),
  DateTime? afterMutualFrom,
  bool granted = true,
  DatingLifecycleResult result = const DatingLifecycleResult.done('paused'),
}) async {
  await t.pumpWidget(const SizedBox());
  final setup = FakeDatingSetupGateway(profile: profile);
  final life = FakeDatingLifecycleGateway()..result = result;
  final photos = FakeDatingPhotosGateway(
    afterMutualFrom: afterMutualFrom ?? DateTime.utc(2026, 1, 1),
  );
  final asker = FakePushAsker(granted: granted);
  await pumpFlowScreen(
    t,
    () => const DatingSettingsScreen(),
    overrides: [
      ...datingShellOverrides(
        home: FakeDatingHomeGateway(
          home: DatingHome(state: state, hasData: hasData),
        ),
        life: life,
      ),
      datingSetupGatewayProvider.overrideWithValue(setup),
      datingPhotosGatewayProvider.overrideWithValue(photos),
      pushAskerProvider.overrideWithValue(asker),
    ],
  );
  await t.pumpAndSettle();
  return (setup, life, photos, asker);
}

void main() {
  testWidgets(
    '§3.12 order: time, who, ages, how far, photos, data saver, notifications, lock, pause, leave',
    (t) async {
      await _pump(t);
      final order = [
        'Introduction time',
        "Who I'd like to meet",
        'Ages',
        'How far',
        'Photos after mutual interest',
        'Data saver',
        'Notifications',
        'Dating lock',
        'Pause Dating',
        'Leave Dating and delete my data',
      ];
      double y(String s) => t.getTopLeft(find.text(s).first).dy;
      for (var i = 1; i < order.length; i++) {
        expect(
          y(order[i - 1]),
          lessThan(y(order[i])),
          reason: '${order[i - 1]} before ${order[i]}',
        );
      }
      expect(find.text(datingDropTimeLabel('19:00')), findsOneWidget);
      expect(find.text('25 to 35'), findsOneWidget);
      expect(find.textContaining('Never introduce'), findsNothing);
      expect(find.textContaining('App icon'), findsNothing);
    },
  );

  testWidgets('introduction time: the labelled list, saved', (t) async {
    final (setup, _, _, _) = await _pump(t);
    await tapInReach(t, find.text('Introduction time'));
    await t.pumpAndSettle();
    await tapInReach(t, find.text(datingDropTimeLabel('07:00')));
    await t.pumpAndSettle();
    expect(setup.lastWrite.$2['values'], {'drop_time': '07:00'});
  });

  testWidgets('data saver and messages save their own keys', (t) async {
    final (setup, _, _, _) = await _pump(t);
    await tapInReach(t, find.widgetWithText(SwitchListTile, 'Data saver'));
    await t.pumpAndSettle();
    expect(setup.lastWrite.$2['values'], {'data_saver': true});
    await tapInReach(
      t,
      find.widgetWithText(SwitchListTile, 'Tell me when someone messages me'),
    );
    await t.pumpAndSettle();
    expect(setup.lastWrite.$2['values'], {'chat_push': false});
  });

  testWidgets('the digest asks for permission first when it is off', (t) async {
    final (setup, _, _, asker) = await _pump(t, granted: false);
    asker.grantOnAsk = false;
    await tapInReach(
      t,
      find.widgetWithText(
        SwitchListTile,
        'Tell me about new introductions and matches, at most once a day.',
      ),
    );
    await t.pumpAndSettle();
    expect(asker.asked, hasLength(1));
    expect(setup.writes, isEmpty);
  });

  testWidgets('photos after mutual interest waits for day 30', (t) async {
    await _pump(
      t,
      afterMutualFrom: DateTime.now().toUtc().add(const Duration(days: 3)),
    );
    final toggle = t.widget<SwitchListTile>(
      find.widgetWithText(SwitchListTile, 'Photos after mutual interest'),
    );
    expect(toggle.onChanged, isNull);
    expect(find.textContaining('Available from '), findsOneWidget);
  });

  testWidgets('pause: the §3.8 line, silent to everyone', (t) async {
    final (_, life, _, _) = await _pump(t);
    await tapInReach(t, find.text('Pause Dating'));
    await t.pumpAndSettle();
    expect(life.calls, ['pause']);
    expect(
      find.text(
        'Dating is paused. Nobody new sees you, and your conversations stay open.',
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'resume on a path that is not Dating says how to carry on (carry 1)',
    (t) async {
      final (_, life, _, _) = await _pump(
        t,
        state: DatingHomeState.paused,
        result: const DatingLifecycleResult.refused(
          DatingLifecycleError.pathNotDating,
        ),
      );
      expect(find.text('Pause Dating'), findsNothing);
      await tapInReach(t, find.text('Resume Dating'));
      await t.pumpAndSettle();
      expect(life.calls, ['resume']);
      expect(
        find.text('Choose Dating in How you use Attune to carry on.'),
        findsOneWidget,
      );
      expect(find.text('How you use Attune'), findsOneWidget);
    },
  );

  for (final state in DatingHomeState.values) {
    testWidgets('R-41: Leave is there for ${state.wire} unless not started', (
      t,
    ) async {
      await _pump(t, state: state);
      expect(
        find.text('Leave Dating and delete my data'),
        state == DatingHomeState.notStarted ? findsNothing : findsOneWidget,
      );
    });
  }

  // C-2: with any Dating data (a reflection, a notice, an enrolment) Leave
  // and Clear are both there, whatever the state.
  for (final state in DatingHomeState.values) {
    testWidgets('C-2: ${state.wire} with Dating data offers Leave and Clear', (
      t,
    ) async {
      await _pump(t, state: state, hasData: true);
      expect(find.text('Leave Dating and delete my data'), findsOneWidget);
      expect(
        find.text('Clear my answers to the three questions'),
        findsOneWidget,
      );
    });
  }

  testWidgets('settings goldens', (t) async {
    await expectFlowGoldens(
      t,
      'dating_settings_full',
      () => const DatingSettingsScreen(),
      overrides: [
        ...datingShellOverrides(
          home: FakeDatingHomeGateway(
            home: const DatingHome(state: DatingHomeState.active),
          ),
        ),
        datingSetupGatewayProvider.overrideWithValue(
          FakeDatingSetupGateway(
            profile: const DatingMyProfile(
              dropTime: '19:00:00',
              minAge: 25,
              maxAge: 35,
            ),
          ),
        ),
        datingPhotosGatewayProvider.overrideWithValue(
          FakeDatingPhotosGateway(afterMutualFrom: DateTime.utc(2026, 1, 1)),
        ),
        pushAskerProvider.overrideWithValue(FakePushAsker(granted: true)),
      ],
    );
  });
}
```

Create `test/features/dating/settings/dating_leave_screen_test.dart` with exactly:

```dart
// Spec 2 W3c (§3.8; carries 12, 13): Leave Dating and delete my data.
import 'package:attune/features/dating/data/dating_lifecycle_repository.dart';
import 'package:attune/features/dating/data/dating_rpc.dart';
import 'package:attune/features/dating/settings/dating_leave_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/flow_harness.dart';
import '../../../helpers/tap_in_reach.dart';
import '../support/dating_fakes.dart';
import '../support/dating_shell.dart';

Future<FakeDatingLifecycleGateway> _pump(
  WidgetTester t, {
  DatingLifecycleResult? result,
  bool online = true,
}) async {
  await t.pumpWidget(const SizedBox());
  final life = FakeDatingLifecycleGateway();
  if (result != null) life.result = result;
  await pumpFlowScreen(
    t,
    () => const DatingLeaveScreen(),
    overrides: datingShellOverrides(life: life, online: online),
  );
  await t.pumpAndSettle();
  return life;
}

void main() {
  testWidgets('the §3.8 copy, word for word; the list box starts off', (
    t,
  ) async {
    await _pump(t);
    for (final line in [
      'Leave Dating?',
      "Deleted now: your Dating profile, photos, prompts, who you'd like to meet, your gender and faith answers, your settings and your private notes.",
      'Kept for 30 days, then deleted: your conversations, so either of you can still report a problem.',
      "Kept for safety, for up to 2 years, only if your account is restricted or you've blocked someone: a code made from your phone number, never the number itself.",
      "Kept as a record: when you agreed to Dating's terms and when you left.",
      "Keep my 'Never introduce me' list in case I come back. It holds codes, not numbers.",
      'Leave and delete',
      'Pause instead',
    ]) {
      expect(find.text(line), findsOneWidget, reason: line);
    }
    expect(
      t.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
      isFalse,
    );
  });

  testWidgets(
    'Leave and delete: one exit, the list not kept, then the done line',
    (t) async {
      final life = await _pump(
        t,
        result: const DatingLifecycleResult.done('exited'),
      );
      await tapInReach(t, find.text('Leave and delete'));
      await t.pumpAndSettle();
      expect(life.calls, ['exit']);
      expect(life.keptList, isFalse);
      expect(
        find.text("You've left Dating. You can set it up again any time."),
        findsOneWidget,
      );
      expect(find.text('Leave and delete'), findsNothing);
    },
  );

  testWidgets('ticked: the list is kept', (t) async {
    final life = await _pump(
      t,
      result: const DatingLifecycleResult.done('exited'),
    );
    await tapInReach(t, find.byType(CheckboxListTile));
    await t.pump();
    await tapInReach(t, find.text('Leave and delete'));
    await t.pumpAndSettle();
    expect(life.keptList, isTrue);
  });

  testWidgets('a restricted account: "You\'ve left Dating." only (carry 13)', (
    t,
  ) async {
    await _pump(t, result: const DatingLifecycleResult.done('suspended'));
    await tapInReach(t, find.text('Leave and delete'));
    await t.pumpAndSettle();
    expect(find.text("You've left Dating."), findsOneWidget);
    expect(find.textContaining('set it up again'), findsNothing);
  });

  testWidgets('Pause instead pauses and says so', (t) async {
    final life = await _pump(
      t,
      result: const DatingLifecycleResult.done('paused'),
    );
    await tapInReach(t, find.text('Pause instead'));
    await t.pumpAndSettle();
    expect(life.calls, ['pause']);
    expect(
      find.text(
        'Dating is paused. Nobody new sees you, and your conversations stay open.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('busy and offline', (t) async {
    final life = await _pump(
      t,
      result: const DatingLifecycleResult.refused(DatingLifecycleError.busy),
    );
    await tapInReach(t, find.text('Leave and delete'));
    await t.pumpAndSettle();
    expect(
      find.text(
        'This is taking a little longer than usual. Try again in a moment.',
      ),
      findsOneWidget,
    );
    expect(find.text('Leave and delete'), findsOneWidget);
    final offline = await _pump(t, online: false);
    await tapInReach(t, find.text('Leave and delete'));
    await t.pumpAndSettle();
    expect(offline.calls, isEmpty);
    expect(
      find.text("You're offline. Dating needs a connection."),
      findsOneWidget,
    );
    expect(life.calls, ['exit']);
  });

  testWidgets('guidelines and goldens', (t) async {
    final semantics = t.ensureSemantics();
    await _pump(t);
    await expectFlowGuidelines(t);
    semantics.dispose();
    await expectFlowGoldens(
      t,
      'dating_leave',
      () => const DatingLeaveScreen(),
      overrides: datingShellOverrides(),
    );
  });
}
```

Create `$D/routes_test_T12.dart` (inserted before the routes test's final brace in Step 5) with exactly:

```dart
  // Spec 2 W3c (§3.14): Leave is inside the group, behind the lock. (A push
  // doesn't change currentConfiguration.uri in go_router 10: the screen
  // shown is read.)
  testWidgets('/dating/leave asks for the PIN first when the lock is on', (
    t,
  ) async {
    final shell = await pumpDatingShell(t, locked: true, pinSet: true);
    shell.router.push(DatingPaths.leave);
    await t.pumpAndSettle();
    expect(find.text('Enter your Safety PIN'), findsOneWidget);
    expect(find.text('Leave Dating?'), findsNothing);
  });
```

Run: `flutter test test/features/dating/settings 2>&1 | tail -2`
Expected: FAIL — `Target of URI doesn't exist: 'package:attune/features/dating/settings/dating_leave_screen.dart'`.

- [ ] **Step 3: The Leave screen**

Create `lib/features/dating/settings/dating_leave_screen.dart` with exactly:

```dart
// Spec 2 §3.8 (carries 12, 13): Leave Dating and delete my data. One exit
// v2 call (one hard delete; the never-introduce list kept only if ticked,
// off by default). Never blocked by state; a restricted account's exit is
// `suspended`, which reads "You've left Dating." alone. No motion.
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/ui/text/allow_large_text.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_buttons.dart';
import 'package:attune/features/dating/data/dating_providers.dart';
import 'package:attune/features/dating/data/dating_rpc.dart';
import 'package:attune/features/dating/gentle_wait/gentle_wait_providers.dart'
    show datingOnlineProvider;
import 'package:attune/features/dating/section/dating_lifecycle_errors.dart';
import 'package:attune/features/onboarding/domain/home_state.dart' show AppTab;
import 'package:attune/home/home_location.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

enum _Outcome { left, leftSuspended, paused }

class DatingLeaveScreen extends ConsumerStatefulWidget {
  const DatingLeaveScreen({super.key});

  @override
  ConsumerState<DatingLeaveScreen> createState() => _DatingLeaveScreenState();
}

class _DatingLeaveScreenState extends ConsumerState<DatingLeaveScreen> {
  final _keys = DatingActionKeys();
  bool _keepList = false;
  bool _busy = false;
  DatingLifecycleError? _error;
  _Outcome? _outcome;

  Future<void> _run(String action) async {
    if (_busy) return;
    final account = ref.read(datingAccountProvider);
    setState(() {
      _busy = true;
      _error = null;
    });
    final life = ref.read(datingLifecycleGatewayProvider);
    final key = _keys.keyFor(action, '$account|$_keepList');
    final r =
        action == 'exit'
            ? await life.exit(key, keepNeverIntroduce: _keepList)
            : await life.pause(key);
    if (!mounted || ref.read(datingAccountProvider) != account) return;
    setState(() {
      _busy = false;
      _error = r.error;
      if (r.ok) {
        _outcome =
            action == 'pause'
                ? _Outcome.paused
                : (r.state == 'suspended'
                    ? _Outcome.leftSuspended
                    : _Outcome.left);
      }
    });
    if (r.ok) ref.invalidate(datingHomeProvider(account));
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final online = ref.watch(datingOnlineProvider).valueOrNull ?? true;
    final outcome = _outcome;
    Widget line(String text) => Padding(
      padding: const EdgeInsets.only(bottom: Spacing.sm),
      child: Text(text, style: theme.textTheme.bodyLarge),
    );
    return AllowLargeText(
      child: Scaffold(
        appBar: AppBar(title: Text(loc.dating_leaveTitle)),
        body: SafeArea(
          // Not a lazy list: both buttons are always built (and reachable).
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(Spacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (outcome != null) ...[
                  DatingCalmLine(switch (outcome) {
                    _Outcome.left => loc.dating_leftDone,
                    _Outcome.leftSuspended => loc.dating_leftSuspended,
                    _Outcome.paused => loc.dating_pausedLine,
                  }),
                  FlowPrimaryButton(
                    label: loc.dating_done,
                    onPressed: () => context.go(homeLocation(tab: AppTab.me)),
                  ),
                ] else ...[
                  if (!online) DatingCalmLine(loc.dating_offline),
                  line(loc.dating_leaveNow),
                  line(loc.dating_leave30),
                  line(loc.dating_leaveSafety),
                  line(loc.dating_leaveRecord),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text(loc.dating_leaveKeepList),
                    value: _keepList,
                    onChanged:
                        _busy
                            ? null
                            : (v) => setState(() => _keepList = v ?? false),
                  ),
                  if (_error != null)
                    ...datingLifecycleErrorRows(context, loc, _error!),
                  const SizedBox(height: Spacing.md),
                  FlowPrimaryButton(
                    label: loc.dating_leaveConfirm,
                    busy: _busy,
                    onPressed: online ? () => _run('exit') : null,
                  ),
                  FlowSecondaryButton(
                    label: loc.dating_leavePause,
                    onPressed: online && !_busy ? () => _run('pause') : null,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: The settings rows**

Create `$D/edit_T12.py` with exactly:

```python
import pathlib, sys
sys.path.insert(0, '.superpowers/sdd/2026-11-07-spec2-w3')
from anchor import edit

F = 'lib/features/dating/settings/dating_settings_screen.dart'
edit(F, [
    ("import 'package:attune/features/safety/data/dating_lock_store.dart';\n",
     "import 'package:attune/features/safety/data/dating_lock_store.dart';\n"
     "import 'package:attune/core/notifications/services/onesignal_service.dart';\n"
     "import 'package:attune/core/notifications/services/push_permission_policy.dart';\n"
     "import 'package:attune/core/utils/date_formatter.dart';\n"
     "import 'package:attune/features/dating/data/dating_rpc.dart';\n"
     "import 'package:attune/features/dating/data/dating_home.dart';\n"
     "import 'package:attune/features/dating/photos/dating_photos_providers.dart';\n"
     "import 'package:attune/features/dating/routes/dating_routes.dart';\n"
     "import 'package:attune/features/dating/section/dating_lifecycle_errors.dart';\n"
     "import 'package:attune/features/dating/setup/dating_setup_providers.dart';\n"
     "import 'package:attune/features/dating/setup/ready_step.dart'\n"
     "    show datingDropTimeLabel, datingDropTimeOf, pickDatingDropTime;\n"
     "import 'package:go_router/go_router.dart';\n"),
    ("  GentleWaitSave? _cleared;\n",
     "  GentleWaitSave? _cleared;\n"
     "  final _keys = DatingActionKeys();\n"
     "  bool _lifeBusy = false;\n"
     "  bool _paused = false;\n"
     "  DatingLifecycleError? _lifeError;\n"
     "\n"
     "  String? get _account => ref.read(datingAccountProvider);\n"
     "\n"
     "  Future<void> _save(String action, Map<String, Object> values) async {\n"
     "    final account = _account;\n"
     "    await ref.read(datingSetupGatewayProvider).saveSettings(_keys.keyFor(action, '$account|$values'), values);\n"
     "    if (!mounted || _account != account) return;\n"
     "    ref.invalidate(datingMyProfileProvider(account));\n"
     "    if (values.containsKey('drop_time')) {\n"
     "      ref.invalidate(datingHomeProvider(account));\n"
     "    }\n"
     "  }\n"
     "\n"
     "  Future<void> _changeTime(String current) async {\n"
     "    final picked = await pickDatingDropTime(context, current);\n"
     "    if (picked != null && picked != current && mounted) {\n"
     "      await _save('time', {'drop_time': picked});\n"
     "    }\n"
     "  }\n"
     "\n"
     "  /// R-40: the step comes back here when it saves.\n"
     "  void _open(String step) => context.push('${DatingPaths.step(step)}?from=settings');\n"
     "\n"
     "  Future<void> _push(String key, bool on) async {\n"
     "    if (on && !ref.read(pushAskerProvider).permissionGranted) {\n"
     "      final outcome = await ref.read(pushAskerProvider).askInContext(PushAskContext.j3);\n"
     "      if (outcome != PushAskOutcome.granted || !mounted) return;\n"
     "    }\n"
     "    await _save(key, {key: on});\n"
     "  }\n"
     "\n"
     "  Future<void> _photosAfter(bool on) async {\n"
     "    final account = _account;\n"
     "    await ref.read(datingPhotosGatewayProvider).photosAfterMutual(_keys.keyFor('after', '$account|$on'), on);\n"
     "    if (mounted && _account == account) {\n"
     "      ref.invalidate(datingPhotosProvider(account));\n"
     "    }\n"
     "  }\n"
     "\n"
     "  Future<void> _lifecycle(bool pause) async {\n"
     "    if (_lifeBusy) return;\n"
     "    final account = _account;\n"
     "    setState(() {\n"
     "      _lifeBusy = true;\n"
     "      _lifeError = null;\n"
     "    });\n"
     "    final life = ref.read(datingLifecycleGatewayProvider);\n"
     "    final key = _keys.keyFor(pause ? 'pause' : 'resume', account ?? '');\n"
     "    final r = pause ? await life.pause(key) : await life.resume(key);\n"
     "    if (!mounted || _account != account) return;\n"
     "    setState(() {\n"
     "      _lifeBusy = false;\n"
     "      _lifeError = r.error;\n"
     "      _paused = pause && r.ok;\n"
     "    });\n"
     "    if (r.ok) {\n"
     "      ref.invalidate(datingHomeProvider(account));\n"
     "    }\n"
     "  }\n"),
    ("    final lock = ref.watch(datingLockProvider).valueOrNull ?? false;\n",
     "    final lock = ref.watch(datingLockProvider).valueOrNull ?? false;\n"
     "    final account = ref.watch(datingAccountProvider);\n"
     "    final hasProfile = home?.hasProfile ?? false;\n"
     "    final profile = hasProfile ? ref.watch(datingMyProfileProvider(account)).valueOrNull : null;\n"
     "    final photos = hasProfile ? ref.watch(datingPhotosProvider(account)).valueOrNull : null;\n"
     "    final from = photos?.afterMutualFrom;\n"
     "    final afterOpen = from != null && !DateTime.now().toUtc().isBefore(from);\n"
     "    final time = datingDropTimeOf(profile);\n"
     "    final granted = ref.watch(pushAskerProvider).permissionGranted;\n"
     "    Widget toggle(String title, String? subtitle, bool value, ValueChanged<bool>? onChanged) => SwitchListTile(\n"
     "      contentPadding: EdgeInsets.zero,\n"
     "      title: Text(title),\n"
     "      subtitle: subtitle == null ? null : Text(subtitle),\n"
     "      value: value,\n"
     "      onChanged: online ? onChanged : null,\n"
     "    );\n"
     "    Widget row(String title, String subtitle, IconData icon, VoidCallback onTap) => InfoRowWidget(\n"
     "      title: title,\n"
     "      subtitle: subtitle,\n"
     "      icon: icon,\n"
     "      showAvatar: false,\n"
     "      onTap: online ? onTap : null,\n"
     "    );\n"),
    ("                // W3c (Task 12): §3.12's rows go here.\n",
     "                // §3.12, in its order (W3c; Other countries and Never\n"
     "                // introduce me are W5c's, App icon W8b's).\n"
     "                if (hasProfile) ...[\n"
     "                  row(loc.dating_settingsTime, datingDropTimeLabel(time), Icons.schedule, () => _changeTime(time)),\n"
     "                  row(loc.dating_settingsWho, '', Icons.people_outline, () => _open('meet')),\n"
     "                  row(\n"
     "                    loc.dating_settingsAges,\n"
     "                    profile?.minAge != null && profile?.maxAge != null\n"
     "                        ? loc.dating_settingsAgesValue(profile!.minAge!, profile.maxAge!)\n"
     "                        : '',\n"
     "                    Icons.cake_outlined,\n"
     "                    () => _open('meet'),\n"
     "                  ),\n"
     "                  row(loc.dating_settingsHowFar, '', Icons.near_me_outlined, () => _open('where')),\n"
     "                  toggle(\n"
     "                    loc.dating_settingsPhotosAfter,\n"
     "                    afterOpen || from == null ? null : loc.dating_photosAfterMutualFrom(MyDateFormat.toDate(from.toLocal())),\n"
     "                    photos?.afterMutual ?? false,\n"
     "                    afterOpen ? _photosAfter : null,\n"
     "                  ),\n"
     "                  toggle(loc.dating_settingsDataSaver, loc.dating_settingsDataSaverSub, profile?.dataSaver ?? false,\n"
     "                      (on) => _save('saver', {'data_saver': on})),\n"
     "                  Padding(\n"
     "                    padding: const EdgeInsets.only(top: Spacing.md),\n"
     "                    child: Text(loc.dating_settingsNotifications, style: theme.textTheme.titleSmall),\n"
     "                  ),\n"
     "                  toggle(loc.dating_pushDigest, null, granted && (profile?.digestPush ?? false), (on) => _push('digest_push', on)),\n"
     "                  toggle(loc.dating_pushMessages, null, granted && (profile?.chatPush ?? true), (on) => _push('chat_push', on)),\n"
     "                ],\n"),
], 'T12 rows')

# Pause/Resume and Leave go after the last row (§3.12: after the Dating
# lock); found by its own text, not by indentation.
p = pathlib.Path(F)
s = p.read_text()
probe = '_cleared != GentleWaitSave.busy)'
assert s.count(probe) == 1, 'T12: the clear-error row moved'
i = s.index(probe)
end = s.index('\n              ],\n', i)
tail = (
    "\n"
    "                if (home?.state == DatingHomeState.active || home?.state == DatingHomeState.coolOff)\n"
    "                  row(loc.dating_settingsPause, '', Icons.pause_circle_outline, () => _lifecycle(true)),\n"
    "                if (home?.state == DatingHomeState.paused)\n"
    "                  row(loc.dating_settingsResume, '', Icons.play_circle_outline, () => _lifecycle(false)),\n"
    "                if (_paused) DatingCalmLine(loc.dating_pausedLine),\n"
    "                if (_lifeError != null) ...datingLifecycleErrorRows(context, loc, _lifeError!),\n"
    "                // R-41, C-2: never blocked by state; with no Dating data at\n"
    "                // all (not started, nothing saved) there is nothing to leave.\n"
    "                if (home != null &&\n"
    "                    (home.hasData || home.state != DatingHomeState.notStarted))\n"
    "                  row(loc.dating_settingsLeave, '', Icons.logout, () => context.push(DatingPaths.leave)),"
)
p.write_text(s[:end] + tail + s[end:])
print(f'{F}: 1 insert (T12 pause, leave)')

edit('lib/features/dating/routes/dating_routes.dart', [
    ("import 'package:attune/features/dating/settings/dating_settings_screen.dart';\n",
     "import 'package:attune/features/dating/settings/dating_leave_screen.dart';\n"
     "import 'package:attune/features/dating/settings/dating_settings_screen.dart';\n"),
    ("      region: s.uri.queryParameters['region'],\n    ),\n  ),\n];",
     "      region: s.uri.queryParameters['region'],\n    ),\n  ),\n"
     "  datingRoute(\n    DatingPaths.leave,\n    'datingLeave',\n    signedIn,\n"
     "    (s) => const DatingLeaveScreen(),\n    motion: (s) => DatingMotion.none,\n  ),\n];"),
], 'T12 leave route')
edit('test/architecture/text_scale_routes_test.dart', [
    ("  'datingSettings',\n  'datingNotOpen',\n",
     "  'datingSettings',\n  'datingNotOpen',\n  'datingLeave',\n"),
], 'T12 text scale name')
```

(`dart format` is not run on `dating_settings_screen.dart` again if Task 4 already formatted it — it is this wave's own file, so running it is allowed; run it once after the edit and review the diff stays inside the new lines plus their neighbours.)

- [ ] **Step 5: The manual topic, its flags (R-35)**

Replace the whole of `lib/app/documentations/user_manual/data/dating_mode_docs.dart` with exactly (§4.10 "Replace [W3]": the file is rewritten whole, so it is formatted as new):

```dart
// lib/app/documentations/user_manual/data/dating_mode_docs.dart
//
// Dating (Spec 2, docs/superpowers/specs/2026-10-24-dating-mode-design.md).
// Listed only while flow_signin_v2, flow_paths_v2 and dating_mode_enabled
// are on (DocumentationRegistry). Healing never decides when someone can
// date (§2.1); nothing here says otherwise.

import 'package:flutter/material.dart';
import 'package:attune/app/documentations/user_manual/models/documentation_model.dart'
    show DocumentationModule;
import 'package:attune/app/documentations/user_manual/models/faq_model.dart';
import 'package:attune/app/documentations/user_manual/models/manual_content.dart';
import 'package:attune/app/documentations/user_manual/models/manual_section.dart';

class DatingModeDocs implements DocumentationModule {
  @override
  String getTitle(BuildContext context) => 'Dating';

  @override
  String get id => 'datingMode';

  @override
  String getSubtitle(BuildContext context) =>
      'Up to 3 introductions a day, never a swipe deck';

  @override
  IconData get icon => Icons.favorite_border;

  @override
  int get order => 21;

  @override
  List<ManualSection> getSections(BuildContext context) => [
    ManualSection(
      id: 'dating_what_it_is',
      title: 'What Dating is',
      subtitle: 'A few introductions, chosen with care',
      icon: Icons.favorite_border,
      category: 'Dating',
      order: 1,
      contents: [
        ManualContent(
          id: 'dating_intro',
          title: 'Up to 3 introductions a day',
          numberPrefix: '1',
          content:
              'Dating introduces you to up to 3 people a day, at a time you choose. Each introduction says why you two were introduced: what you could do together and what you both say you value. There is no swipe deck, no browsing, no counters and no streaks.',
          type: ManualContentType.text,
        ),
        ManualContent(
          id: 'dating_not_prediction',
          title: '',
          content:
              'Attune can\'t predict chemistry; meeting is how you find out.',
          type: ManualContentType.important,
        ),
        ManualContent(
          id: 'dating_who',
          title: 'Who can use it',
          numberPrefix: '2',
          content:
              'Dating is for adults whose account is in good standing, who aren\'t married or in a relationship, in a country where Attune has opened Dating. Healing never decides when you can date. If your relationship ended on Attune, Dating opens for you when your shared space closes, 30 days after it ended, or sooner if you both close it.',
          type: ManualContentType.text,
        ),
        ManualContent(
          id: 'dating_inputs',
          title: '',
          content:
              'Nothing from your journal, quizzes or Healing is used to introduce you. Your answers are never used for ads, never sold, and never read by AI.',
          type: ManualContentType.tip,
        ),
      ],
    ),
    ManualSection(
      id: 'dating_setup',
      title: 'Setting up',
      subtitle: 'One question per screen',
      icon: Icons.checklist_outlined,
      category: 'Dating',
      order: 2,
      contents: [
        ManualContent(
          id: 'dating_setup_steps',
          title: 'Twelve short steps',
          numberPrefix: '1',
          content:
              'You choose what you\'re looking for, where you are, how you describe yourself, who you\'d like to meet, children and, if you like, faith. Then you add 2 to 6 photos and answer 2 short prompts. You can stop at any step and carry on later.',
          type: ManualContentType.text,
        ),
        ManualContent(
          id: 'dating_setup_private',
          title: 'What stays private',
          numberPrefix: '2',
          content:
              'Nobody ever sees who you\'d like to meet, your exact location or your date of birth. Your gender, faith and marriage history appear on your profile only if you choose.',
          type: ManualContentType.text,
        ),
        ManualContent(
          id: 'dating_setup_photos',
          title: 'Your photos',
          numberPrefix: '3',
          content:
              'Every photo is checked before anyone sees it. Photos with children can\'t be used. From your account\'s 30th day you can choose to show your photos only after you\'re both interested.',
          type: ManualContentType.text,
        ),
        ManualContent(
          id: 'dating_setup_verify',
          title: 'Checking it\'s you',
          numberPrefix: '4',
          content:
              'Before your first introduction, a short video selfie checks your age and that your photos are you. The video is deleted straight away.',
          type: ManualContentType.text,
        ),
      ],
    ),
    ManualSection(
      id: 'dating_interest',
      title: 'Interest and matches',
      subtitle: 'Both of you, or nothing',
      icon: Icons.thumb_up_alt_outlined,
      category: 'Dating',
      order: 3,
      contents: [
        ManualContent(
          id: 'dating_double_opt_in',
          title: 'A match needs both of you',
          numberPrefix: '1',
          content:
              'You answer each introduction with "Interested" or "Not for me". Nobody is told you passed. A match appears only when you\'re both interested.',
          type: ManualContentType.text,
        ),
        ManualContent(
          id: 'dating_former_partner',
          title: 'Former partners are never introduced',
          numberPrefix: '2',
          content:
              'A former Attune partner is never introduced to you, even if either of you later makes a new account.',
          type: ManualContentType.text,
        ),
        ManualContent(
          id: 'dating_money',
          title: '',
          content:
              'Never send money, account details or mobile money to someone you haven\'t met in person, whatever the story. Report it from the conversation.',
          type: ManualContentType.warning,
        ),
      ],
    ),
    ManualSection(
      id: 'dating_privacy_on_phone',
      title: 'On your phone',
      subtitle: 'Discreet by design',
      icon: Icons.lock_outline,
      category: 'Dating',
      order: 4,
      contents: [
        ManualContent(
          id: 'dating_notifications',
          title: 'Plain notifications',
          numberPrefix: '1',
          content:
              'Dating notifications only ever say "You have something new in Attune." Tapping one opens Me.',
          type: ManualContentType.text,
        ),
        ManualContent(
          id: 'dating_lock',
          title: 'The Dating lock',
          numberPrefix: '2',
          content:
              'If someone else uses your phone, you can lock Dating with your Safety PIN in Dating settings, and ask for the PIN every time Attune opens.',
          type: ManualContentType.text,
        ),
      ],
    ),
    ManualSection(
      id: 'dating_control',
      title: 'Pausing and leaving',
      subtitle: 'Whenever you want',
      icon: Icons.pause_circle_outline,
      category: 'Dating',
      order: 5,
      contents: [
        ManualContent(
          id: 'dating_pause',
          title: 'Pause Dating',
          numberPrefix: '1',
          content:
              'Pausing means nobody new sees you, and your conversations stay open. Nobody is told.',
          type: ManualContentType.text,
        ),
        ManualContent(
          id: 'dating_leave',
          title: 'Leave Dating and delete my data',
          numberPrefix: '2',
          content:
              'Leaving deletes your Dating profile, photos, prompts, who you\'d like to meet, your gender and faith answers, your settings and your private notes straight away. Your conversations are kept for 30 days so either of you can still report a problem, then deleted.',
          type: ManualContentType.text,
        ),
        ManualContent(
          id: 'dating_not_auto_relationship',
          title: '',
          content:
              'A match never creates an Attune relationship on its own. Becoming a couple on Attune is a separate step you both choose.',
          type: ManualContentType.important,
        ),
      ],
    ),
  ];

  @override
  List<FAQModel> getFAQs(BuildContext context) {
    return [
      FAQModel(
        id: 'faq_dating_when_available',
        question: 'When can I use Dating?',
        answer:
            'When you choose, as an adult whose account is in good standing, who isn\'t married or in a relationship, in a country where Dating is open. Healing never decides it. If your relationship ended on Attune, Dating opens for you when your shared space closes, 30 days after it ended, or sooner if you both close it; you can set up Dating in the meantime.',
        category: 'Dating',
        order: 1,
      ),
      FAQModel(
        id: 'faq_dating_swipe',
        question: 'Is Dating a swiping app?',
        answer:
            'No. There is no swipe deck, no browsing and no counters. You get up to 3 introductions a day, each with the reasons you two were introduced.',
        category: 'Dating',
        order: 2,
      ),
      FAQModel(
        id: 'faq_dating_not_open',
        question: 'Why isn\'t Dating open where I live?',
        answer:
            'Attune opens Dating one country at a time, so it can keep it safe and well looked after. You can ask to be told when it opens where you are.',
        category: 'Dating',
        order: 3,
      ),
      FAQModel(
        id: 'faq_dating_rejection_visible',
        question: 'Will someone know if I said "Not for me"?',
        answer:
            'No. Nobody is told you passed. A match appears only when you\'re both interested.',
        category: 'Dating',
        order: 4,
      ),
      FAQModel(
        id: 'faq_dating_who_sees',
        question: 'Who sees my answers?',
        answer:
            'Nobody sees who you\'d like to meet, your exact location or your date of birth. Your gender, faith and marriage history show on your profile only if you turn them on.',
        category: 'Dating',
        order: 5,
      ),
      FAQModel(
        id: 'faq_dating_money_request',
        question: 'A match is asking me for money. Is that normal?',
        answer:
            'No. Never send money, account details or mobile money to someone you haven\'t met in person, whatever the reason. Report it from the conversation.',
        category: 'Dating',
        order: 6,
      ),
      FAQModel(
        id: 'faq_dating_leave',
        question: 'What happens to my data if I leave?',
        answer:
            'Your Dating profile, photos and answers are deleted straight away. Conversations are kept for 30 days so either of you can report a problem, then deleted. A record of when you agreed to Dating\'s terms and when you left is kept.',
        category: 'Dating',
        order: 7,
      ),
    ];
  }
}
```

Create `$D/edit_T12_docs.py` with exactly:

```python
import sys
sys.path.insert(0, '.superpowers/sdd/2026-11-07-spec2-w3')
from anchor import edit
edit('lib/app/documentations/user_manual/data/manual_documentation_registry.dart', [
    ("import 'package:attune/features/chat/domain/services/chat_feature_flags.dart';\n",
     "import 'package:attune/features/chat/domain/services/chat_feature_flags.dart';\n"
     "import 'package:attune/features/dating/domain/services/dating_feature_flags.dart';\n"),
    ("    'aboutUs': [\n      'flow_signin_v2',\n      'flow_paths_v2',\n      'flow_couples_v2',\n      'couple_profile',\n    ],\n  };\n",
     "    'aboutUs': [\n      'flow_signin_v2',\n      'flow_paths_v2',\n      'flow_couples_v2',\n      'couple_profile',\n    ],\n"
     "    // Spec 2 W3c: Dating (dating_mode_enabled is read through\n"
     "    // get_dating_home, R-35).\n"
     "    'datingMode': [\n      'flow_signin_v2',\n      'flow_paths_v2',\n      DatingFeatureFlags.datingModeEnabled,\n    ],\n  };\n"),
], 'T12 registry')
edit('lib/app/documentations/user_manual/data/documentation_flags.dart', [
    ("import 'package:attune/features/chat/domain/services/chat_feature_flags.dart';\n",
     "import 'package:attune/features/chat/domain/services/chat_feature_flags.dart';\n"
     "import 'package:attune/features/dating/domain/services/dating_feature_flags.dart';\n"),
    ("      if (await ChatFeatureFlags.isEnabled(client, flag)) enabled.add(flag);\n",
     "      // R-35: dating_% flags are server-only; Dating's own read answers.\n"
     "      final on = flag == DatingFeatureFlags.datingModeEnabled\n"
     "          ? await DatingFeatureFlags.isDatingModeAvailable(client)\n"
     "          : await ChatFeatureFlags.isEnabled(client, flag);\n"
     "      if (on) enabled.add(flag);\n"),
], 'T12 flags')
edit('test/app/documentations/documentation_registry_flags_test.dart', [
    ("          // Spec 1 W9b: Opinions safety.\n          'opinions_safety_v1',\n",
     "          // Spec 1 W9b: Opinions safety.\n          'opinions_safety_v1',\n"
     "          // Spec 2 W3c: Dating (R-35).\n          'dating_mode_enabled',\n"),
], 'T12 flags test allowlist')
edit('test/app/documentations/manual_content_guard_test.dart', [
    ("      'communicationQuiz',\n      'conflictStyleQuiz',\n    ]) {\n",
     "      'communicationQuiz',\n      'conflictStyleQuiz',\n      'datingMode',\n    ]) {\n"),
], 'T12 guard gated id')
```

Create `$D/registry_test_T12.dart` (inserted before the registry flags test's final brace, with its dart:io import) with exactly:

```dart

  // Spec 2 W3c (§4.10, R-35): the Dating topic needs all three flags, and
  // the manual reads dating_mode_enabled through get_dating_home.
  test('Dating is listed only with sign-in v2, paths v2 and Dating on', () {
    bool listed(Set<String> on) =>
        DocumentationRegistry.visibleModules(on).any((m) => m.id == 'datingMode');
    expect(listed(const {'flow_signin_v2', 'flow_paths_v2'}), isFalse);
    expect(listed(const {'flow_signin_v2', 'flow_paths_v2', 'dating_mode_enabled'}), isTrue);
    final source = File('lib/app/documentations/user_manual/data/documentation_flags.dart').readAsStringSync();
    // dating_mode_enabled itself is answered by get_dating_home (R-35).
    expect(
      source,
      matches(RegExp(
        r'flag == DatingFeatureFlags\.datingModeEnabled\s*\?\s*'
        r'await DatingFeatureFlags\.isDatingModeAvailable\(client\)',
      )),
    );
  });
```

Create `$D/edit_T12_tests.py` with exactly:

```python
# Spec 2 W3c Task 12: the Leave route case and the registry flags case,
# each inserted before its file's final }, with the registry test's import.
import pathlib, sys
sys.path.insert(0, '.superpowers/sdd/2026-11-07-spec2-w3')
from anchor import edit
D = pathlib.Path('.superpowers/sdd/2026-11-07-spec2-w3')


def before_final_brace(path, snippet, label):
    p = pathlib.Path(path)
    s = p.read_text()
    assert s.endswith('}\n'), f'{label}: {path} does not end with }}'
    p.write_text(s[:-2] + snippet.rstrip('\n') + '\n}\n')
    print(f'{path}: 1 insert ({label})')


before_final_brace('test/features/dating/routes/dating_routes_test.dart',
                   (D / 'routes_test_T12.dart').read_text(), 'T12 Leave route test')
R = 'test/app/documentations/documentation_registry_flags_test.dart'
edit(R, [
    ("import 'package:attune/app/documentations/user_manual/data/manual_documentation_registry.dart';\n",
     "import 'dart:io';\n\n"
     "import 'package:attune/app/documentations/user_manual/data/manual_documentation_registry.dart';\n"),
], 'T12 registry test import')
before_final_brace(R, (D / 'registry_test_T12.dart').read_text(), 'T12 registry flags test')
```

```bash
D=.superpowers/sdd/2026-11-07-spec2-w3
python3 -I $D/edit_T12.py
python3 -I $D/edit_T12_docs.py
python3 -I $D/edit_T12_tests.py
dart format lib/features/dating/settings/dating_leave_screen.dart test/features/dating/settings/dating_settings_rows_test.dart test/features/dating/settings/dating_leave_screen_test.dart lib/app/documentations/user_manual/data/dating_mode_docs.dart
flutter analyze --no-pub lib test/features/dating test/app/documentations 2>&1 | tail -1
flutter test --update-goldens test/features/dating/settings 2>&1 | tail -1
flutter test test/features/dating test/app/documentations test/features/healing/healing_never_gates_dating_test.dart test/architecture 2>&1 | tail -1
python3 scripts/large_text_audit.py --scale 2.0 test/features/dating/settings 2>&1 | tail -1
grep -rn "eligible through Healing\|8 weeks\|potentially eligible\|Alignment preview\|84% match" lib/app/documentations/user_manual/data/dating_mode_docs.dart
```

Expected (verified, fix round 1): the edit lines (`T12 rows`, `1 insert (T12 pause, leave)`, `T12 leave route`, `T12 text scale name`, `T12 registry`, `T12 flags`, `T12 flags test allowlist`, `T12 guard gated id`, `1 insert (T12 Leave route test)`, `T12 registry test import`, `1 insert (T12 registry flags test)`); `Formatted …` (the files this task created only; `dating_settings_screen.dart` is edited, so it is not formatted again and the mutant anchors below stay exact, I-10); `No issues found!` (the `lib` run compares against the baseline in the gate; this run must add nothing); goldens `dating_settings_full`, `dating_leave` (×4) — open the 2.0 ones: every row wraps, both toggles' subtitles wrap, the four leave lines wrap above the box; `All tests passed!` (including `healing_never_gates_dating_test.dart`: the new topic has "Healing never decides when you can date." and "Healing never decides it." and none of the stale phrases); `SCALE 2.0: 0 site(s) to fix, 0 listed apart`; no `grep` output.

- [ ] **Step 6: Mutants**

Create `$D/mut_T12.py` with exactly:

```python
S = 'lib/features/dating/settings/'
T = ['test/features/dating/settings/dating_settings_rows_test.dart']
L = ['test/features/dating/settings/dating_leave_screen_test.dart']
G = ['test/app/documentations/documentation_registry_flags_test.dart']
MUTS = {
  'leave_keeps_list_default': (S + 'dating_leave_screen.dart', "  bool _keepList = false;", "  bool _keepList = true;", L),
  'leave_suspended_generic': (S + 'dating_leave_screen.dart', "(r.state == 'suspended'\n                    ? _Outcome.leftSuspended\n                    : _Outcome.left)", "_Outcome.left", L),
  'leave_offline': (S + 'dating_leave_screen.dart', "onPressed: online ? () => _run('exit') : null", "onPressed: () => _run('exit')", L),
  'pause_instead_exits': (S + 'dating_leave_screen.dart', "onPressed: online && !_busy ? () => _run('pause') : null", "onPressed: online && !_busy ? () => _run('exit') : null", L),
  'leave_blocked_by_state': (S + 'dating_settings_screen.dart', "                    (home.hasData || home.state != DatingHomeState.notStarted))\n", "                    (home.state == DatingHomeState.active))\n", T),
  # C-2: Leave only by state, so a not-started person with saved answers
  # (a reflection) can't leave and delete them.
  'leave_ignores_data': (S + 'dating_settings_screen.dart', "                    (home.hasData || home.state != DatingHomeState.notStarted))\n", "                    (home.state != DatingHomeState.notStarted))\n", T),
  'pause_line_lost': (S + 'dating_settings_screen.dart', "              if (_paused) DatingCalmLine(loc.dating_pausedLine),\n", "", T),
  'resume_error_lost': (S + 'dating_settings_screen.dart', "              if (_lifeError != null) ...datingLifecycleErrorRows(context, loc, _lifeError!),\n", "", T),
  'digest_no_ask': (S + 'dating_settings_screen.dart', "    if (on && !ref.read(pushAskerProvider).permissionGranted) {", "    if (false) {", T),
  'after_mutual_early': (S + 'dating_settings_screen.dart', "                  afterOpen ? _photosAfter : null,\n", "                  _photosAfter,\n", T),
  'saver_wrong_key': (S + 'dating_settings_screen.dart', "(on) => _save('saver', {'data_saver': on})", "(on) => _save('saver', {'digest_push': on})", T),
  'docs_ungated': ('lib/app/documentations/user_manual/data/documentation_flags.dart', "      final on = flag == DatingFeatureFlags.datingModeEnabled\n", "      final on = flag == 'never'\n", G),
}
```

```bash
python3 -I $D/dmut.py $D/mut_T12.py | tee $D/mut_T12.txt | tail -1
```

Expected (verified, fix round 1): `12/12 killed` (`leave_ignores_data` dies at `C-2: not_started with Dating data offers Leave and Clear`; `docs_ungated` at the registry test's source match). (If `dart format` reflowed a mutated line, re-copy its exact text from the formatted file into `mut_T12.py` before running; the mutant's intent is fixed.)

- [ ] **Step 7: The W3c gate, then the W3 gate**

Run every command of Task 4 Step 11 again with `W3c` in the file names (`$D/sql-after-W3c.txt`, `$D/flutter-after-W3c.txt`, `$D/analyze-after-W3c.txt`), plus:

```bash
D=.superpowers/sdd/2026-11-07-spec2-w3
# the race script on a fresh scratch copy (Task 3 Step 8's commands, the push-key line included, db w3c_race)
(cd supabase/functions && deno test --allow-read process-dating-photo/ _shared/google_vision.test.ts process-scheduled-notifications/privacy_allowlist.test.ts 2>&1 | tail -1)
# §4.1 by the end of W3: no client SELECT on a Dating table, no v1 path left
psql -X -q -At -d attune_spec3a -c "SELECT count(*) FROM information_schema.role_table_grants WHERE grantee IN ('anon','authenticated') AND table_schema = 'public' AND table_name LIKE 'dating\_%' AND privilege_type = 'SELECT'"
grep -rln "upload-dating-photo\|get_dating_eligibility\|delete_dating_profile\b\|from('dating_" lib supabase/functions | grep -v '_test\|\.test\.' || echo "no v1 path"
grep -rn "datingConsent\|datingDashboard\|seen_feature_intro_datingMode" lib || echo "no v1 route"
flutter test test/features/dating/no_disk_writes_test.dart 2>&1 | tail -1
for f in $D/mut_T*.txt; do echo "$f: $(tail -1 $f)"; done
```

Expected: `159 PASS, 14 FAIL`; `no new FAIL`; Flutter with no failure beyond the known `planning_recent` flake (and the `together_rituals` clock failure if the clock trips it); `571 issues found.` or fewer and `no new analyzer issue`; `0`, `0`; the latch OK; Games `All tests passed!`; races 20/20 (W3c re-created no writer the races touch); Deno `ok | … passed | 0 failed`; `0`; `no v1 path`; `no v1 route`; `All tests passed!`; every mutant file ending `n/n killed`. Do not commit; record the tree. **W3c ships here, and with it W3** (Dating off in production; D11's flow is W4a's, and D13's Done answers "We still need to check it's you…" until then).


---

## Owner checklist (nothing here is done by an implementer)

1. **W3's production gate (§8 W3, before Dating is switched on anywhere in production).**
   - The **Ghanaian cultural reviewer, with faith advisers,** signs: D2's intention wording (and this plan's two card lines "Looking for marriage, in a few years" / "…, with no set time", R-38), the married / polygamy attestation sentence and the "I'm separated but not divorced" sheet, the Ghana region and side lists (Task 4's 32 names), the faith and denomination lists (Task 5's migration and names).
   - The **LGBTQ+ safety reviewer (West African context)** signs: D5's off-country line, the "Why?" sheet, D6's off-country copy, the support sheet, the country note (phone variant only, R-18), and §3.10's not-open copy.
   - The **Ghanaian legal opinion** on the reconsidered bill confirms Ghana's switch state (Dating on, same-gender off) before `publish_country_config` is ever run for production.
2. **Still open from W2 (unchanged by W3).**
   - **The clinician's note** (packet §7 of `lib/architecture/DATING_MODE_CLINICAL_REVIEW_PACKET.md`): the 30-day length; setup during the wait; the three questions; D0's copy and its no-shortcut variant (with the DV reviewer); Healing offered and Healing's new result message; the meaning of `is_eligible`; the deleted-former-partner and second-account rules; the gate-erosion clause.
   - **The DV reviewer's read** of every W2 string (D0, the fix-round and busy-clear strings, the no-shortcut sentence), now **plus every string W3 adds that a person in a controlling relationship could be shown**: the Dating section's states (R-29's neutral restricted/hold/age-review copy), the lock row, "Clear my answers to the three questions" and its results, D13's shared-phone question and its two switches, the §3.8 Leave copy, the pause line, and the neutral push "You have something new in Attune." / "Something you asked about is ready in Attune." (W2's dashboard fallback string is deleted by Task 2, so it leaves the review.)
   - The DPIA reflection row for counsel (W2).
3. **New reviewer items from this plan** (each a "(plan)" string in its ARB description): D9's progress and failure lines (R-22), the caption sheet, D10's length line, D11's shell line "You'll do this check before your first introduction.", D12's name, preview and push lines, D13's "While you wait" heading and the pre-W4a line "We still need to check it's you before introductions start.", the settings rows' names, "You've left Dating." for a restricted exit (R-41). Counsel: D4's Dating terms text (R-31) and the Leave copy's retention periods against the DPIA.
4. **Owner decisions.** Approved 2026-11-07: R-5 ("Tell me when it's here" only when the country itself is closed), R-18 (country note: phone variant now, location variant W4b/W8b), R-22 (no upload percentage). Still asked for: R-11 (v1 screens deleted), R-13 (`getResultMessage` kept, carry 15), R-24/R-25 (approval needs a clear scan; the CSAM hold's category waits for W7a), R-26 (D11 is a shell; D13's Done can't activate until W4a), R-38 (no "Why you two" or actions on the preview), R-41/R-43 (Leave and Clear reachable from every card whenever there is Dating data), R-44 (the push key is its own secret; without it no Dating push is queued), R-46 (orphan uploads swept after a CSAM scan, never unscanned).
5. **Device checks for W3 (§7.7, the parts this wave can run; release builds, F-4).**
   - TalkBack and VoiceOver through D1–D13 (D11 as a shell), Dating settings and Leave: every control named, the step counter read, rejections read with their photo number, Move earlier / Move later as actions.
   - 200% text on every Dating screen and sheet, and an RTL smoke test (the goldens cover layout; the device check covers real fonts).
   - Offline and EDGE on every step (D1–D13, settings, Leave): each offline line shows, nothing saves half-way; then **no Dating file or prefs key on disk** (clear app data on the test phones first — R-12's legacy `seen_feature_intro_datingMode`; then check the app's data directory, prefs and caches after a full setup with photos).
   - Data use: measure setup end to end and one photo upload; correct D1's and D9's figures ("about 300 KB" each) if off by more than 25%.
   - Lock screen on Android and iOS: a "Tell me when it's here" push shows only "Attune" / "Something you asked about is ready in Attune."; with the Dating lock on, tapping it asks for the PIN.
   - Quick exit from a setup step and from D0: back in the app, the step's typed text is gone and the Dating unlock is gone; the Dating lock and the Safety PIN are unchanged.
   - Photo upload on an Android Go / 2 GB phone (Tecno or Itel) and an iPhone SE: picking, preparing at 1600 px, uploading, "Checking…" then "Ready"; a photo with a child gets the Crop offer.
6. **Deploy (owner only; Dating stays off in production).**
   - `supabase db push` the six files: `20261107150000_dating_v2_client_reads.sql`, `20261107150010_dating_v2_client_reads_grants.sql`, `20261107160000_dating_v2_setup_lists.sql`, `20261107160010_dating_v2_setup_lists_grants.sql`, `20261107170000_dating_v2_photos.sql`, `20261107170010_dating_v2_photos_grants.sql` (with the W1, W2 and Spec 1 migrations still waiting, in order).
   - Deploy `process-dating-photo` (CSAM-first handler, labels) and `process-scheduled-notifications` (the `"route"` allowlist line, R-7); delete the hosted `upload-dating-photo` function.
   - Confirm the Vision key the function already uses has `LABEL_DETECTION` enabled, and that Spec 1 W7b's CSAM matcher settings are present for the function (a missing matcher leaves photos pending, never approved).
   - Create the vault secret `dating_push_key` (a random 32-byte hex) in every project (R-44); until it exists no "Tell me when it's here" push is queued and `dating.notify.queue_failed` counts each opening.
   - The W3c migration schedules `sweep-dating-photo-orphans` (every 15 minutes, `invoke_edge_function('process-dating-photo')`): it needs the deployed function and the CSAM matcher settings; with the matcher missing, orphans are kept and retried, never deleted (R-46).
   - The dev script needs no re-run for W3 (R-34).
7. **Carried to later waves (recorded, not built here):** W4a: D11's flow, then D13's activation succeeds; W4b: the country note's location variant (R-18), the `lists_no_device` mutant on `get_dating_setup_lists`; W5a/W5b: the card's "Why you two" block and actions (R-38), Today; W5c: Other countries and Never introduce me rows; W6c: the first-date guide item at D13; W7a: the CSAM hold's category and source (R-25), the restricted/hold copy (R-29); W8a: the rest of `registerDatingDeviceWipes` (R-9); W8b: the plain-icon offer at D13 and the App icon row (A-11); W10: `dating_mutual_match` removed from `notification_config.dart` (A-7), `save_dating_profile_draft` dropped (R-3). W6 (M-12): R-11 deleted the v1 `dating_matches_screen.dart` and `dating_guided_date_screen.dart`, which §4.10 marks "Change [W6]" ("keeps the private reflection"): W6 rebuilds the guided date's private reflection on `dating_date_reflections` as a new screen.

---

## Spec coverage (self-review)

| Spec | Where |
|---|---|
| §2.2 faith and denomination lists | Task 5 (migration, names) |
| §2.4 same-gender off: D5/D6, "Why?", support, country note | Task 7; contract rows Task 5 |
| §2.7 "Tell me when it's here" | Task 3 (RPCs, queue on publish, race), Task 4 (button, settings row) |
| §3.0 frame, progress, Skip, motion, offline | Task 6 (`DatingStepFrame`), every step task's tests |
| §3.1 Dating section | Task 4 |
| §3.2 D0 routed | Task 2 |
| §3.2 D1–D4 | Task 6 |
| §3.2 D5–D8 | Task 7 |
| §3.2 D9 (2–6 photos, slot states, CSAM-first, child labels, crop, captions, day-30 toggle, reorder) | Tasks 8, 9, 10 |
| §3.2 D10 (prompts, filters) | Task 10 (server filters are W1c's, reused) |
| §3.2 D11 shell | Task 11 (R-26); flow W4a |
| §3.2 D12 (card, edit links, name, never shown, push ask) | Task 11 (R-27, R-38, R-40) |
| §3.2 D13 (time, while you wait, shared phone, Done) | Task 11 (R-39; plain icon A-11) |
| §3.4 card | Task 11 (`DatingCardView`, R-38) |
| §3.8 pause, leave | Task 12 |
| §3.10 not-open | Task 4 |
| §3.12 settings (W3 rows) | Task 4 (shell, lock, notice, clear), Task 12 (rows, pause, leave; R-41) |
| §3.13 neutral push | Task 2 (routing), Task 3 (type, copy, allowlist R-7) |
| §3.14 routes, lock redirect, removed routes | Task 2, Task 4, Task 12 (R-8, R-10, R-11) |
| §3.15 per-screen motion, accessibility, errors | each screen task's tests and goldens |
| §4.1 no client SELECT on Dating tables | Task 3, Task 8 (R-2), W3 gate query |
| §4.3 photo columns | Task 8 |
| §4.4 RPCs (lifecycle, setup, photos) | Tasks 1, 5, 8 |
| §4.5 storage | Task 8 (R-2) |
| §4.7 `process-dating-photo` | Task 9 |
| §4.9 W3 migrations | Tasks 3, 5, 8 |
| §4.10 client files (repository, providers, flags, preparer, model, docs, registry, wipes) | Tasks 1, 2, 9, 10, 12 (R-9, R-23, R-35) |
| §7.1 contracts | Tasks 3, 5, 8 |
| §7.2 S3, S17, S22 | Tasks 7, 11 |
| §7.3 Deno | Tasks 3, 9 |
| §7.4 off-country no-call | Task 7 |
| §7.5 mutants 4 and 7 | Task 5 |
| §7.7 device checks | Owner checklist 5 |
| §8 W3 gate | Owner checklist 1 |
| I-4, I-9, I-10, R11, R21, A-11, C-5, D8, D20 | Tasks 1/3 (I-4), 2/3 (I-9), 8/9 (I-10), 2 grep test (R11), 3 (R21), 11 (A-11), 9/10 (C-5), every provider (D8), Task 4 `no_disk_writes_test` (D20) |
| carries 1–15 | the Carries table (every row names a task or a ruling) |

Placeholder scan: no "TBD"/"TODO"/"fill in" in a step; every step gives its exact file, code, command and expected line. Type consistency checked by name across tasks: `DatingWrite` (`ok`, `reason`, `position`, `nextStep`, `busy`, `failed`), `DatingStepNav` (`next`, `back`, `toMe`), `DatingStepState` (`keys`, `saving`, `refusal`, `write`, `watchProfile`, `resetAnswers`, `seedAnswers`), `DatingLifecycleResult` (`ok`, `state`, `error`), `DatingPhotoList` (`photos`, `afterMutual`, `afterMutualFrom`), `DatingMyProfile` (`displayName`, `dropTime`, `digestPush`, `chatPush`, `dataSaver`, `prompts`, `minAge`, `maxAge`). Where a step says "if the anchor misses", the instruction is to stop and report (R-32), never to improvise.
